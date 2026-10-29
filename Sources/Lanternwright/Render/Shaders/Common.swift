// Shared MSL prelude: struct layouts must match Render/GPUTypes.swift exactly.
enum CommonShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position;
    float4 normal;
    float4 color;
};

struct FrameUniforms {
    float4x4 viewProj;
    float4x4 invViewProj;
    float4x4 sunViewProj;
    float4 cameraPos;
    float4 sunDir;
    float4 sunColor;
    float4 fogParams;
    float4 screen;
    float4 misc;
    float4x4 sunViewProj0;
    float4x4 sunViewProj1;
    float4 casTexel;
    float4 casRange;
    float4 casRadius;
    float4 worldA;
    float4 moonB;
    float4 worldB;
};

struct ObjectUniforms {
    float4x4 model;
    float4 tint;
    float4 emissive;
    float4 lod;          // x = 1: a level of a tree LOD set (dithered cross-fade), y = its level 0...2
};

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;          // 0..1, origin top-left
};

// One oversized triangle covers the screen with no diagonal seam (cheaper than a quad).
vertex FullscreenOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

// Interleaved gradient noise (Jimenez): a per-pixel threshold in [0,1) whose error is spread evenly, so a screen-door dissolve looks like fine,
// even grain, not clumps. Used for the dithered LOD cross-fades.
inline float ign(float2 pixel) { return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715)))); }

// ---- The minimum-footprint rule for thin things (G10.2.2; shared with the grass rewrite G10.G.2). Anything narrower than a pixel (a blade, a twig, a rope, a rail) is sampled by
// the rasteriser at random, so it flickers between "a speck" and "nothing" as the camera moves. Draw it at least `minPixels` wide (usually 1) and scale its coverage by
// the true width over the drawn width, so it becomes a faint, stable tint of the same average energy instead of a flickering speck.
//   pixel_world_size(worldPos, frame): metres covered by one pixel at that point (from the view depth, the projection's scale and the render height).
//   thin_coverage(worldWidth, footprint, minPixels): .width = the width to DRAW (never below footprint * minPixels), .coverage = worldWidth / .width, 0...1.
// Use: in the vertex stage push the two edges of the thin shape apart to `.width`; pass `.coverage` to the fragment; there either fade alpha/brightness by it (blended
// things) or discard stochastically when ign(pixel + frame jitter) > coverage (opaque things in a pipeline that already discards; the temporal resolve averages it).
// Example (a blade or rope of half-width hw at world position P, pushed sideways by `side` = -1 or +1 along its own right vector):
//   ThinCover tc = thin_coverage(2.0 * hw, pixel_world_size(P, frame), 1.0);   P += right * side * 0.5 * tc.width;   // widen about the centre line, do not ADD the footprint
// The footprint is metres per RENDER pixel (the height of the frame being drawn), so it stays right if the frame is ever rendered below the drawable's size.
struct ThinCover { float width; float coverage; };
inline float pixel_world_size(float3 worldPos, constant FrameUniforms& frame) {
    float viewDepth = frame.viewProj[0][3] * worldPos.x + frame.viewProj[1][3] * worldPos.y + frame.viewProj[2][3] * worldPos.z + frame.viewProj[3][3];
    float scaleY = length(float3(frame.viewProj[0][1], frame.viewProj[1][1], frame.viewProj[2][1]));       // the projection's 1 / tan(fovY / 2)
    return 2.0 * max(viewDepth, 0.0) / max(scaleY * frame.screen.y, 1e-4);
}
inline ThinCover thin_coverage(float worldWidth, float footprint, float minPixels) {
    ThinCover c;
    c.width = max(worldWidth, footprint * minPixels);
    c.coverage = worldWidth / max(c.width, 1e-6);
    return c;
}

// Tree LOD level as a continuous number 0...2 from the horizontal distance to the eye (R09). Level 0 -> 1 around 45 m and 1 -> 2 around 130 m,
// each over a band of 15 % of the distance (+-7.5 %), shifted per tree by `stagger` (-1...1, x 10 m) so a stand never changes all at once.
// The fragment keeps its LOD only if floor(level + noise) equals its own index, so neighbouring levels dissolve into each other exactly
// complementarily (every pixel belongs to one level) and nothing is drawn twice.
inline float tree_lod_level(float d, float stagger) {
    float s = stagger * 10.0;
    return smoothstep(45.0 + s - 3.4, 45.0 + s + 3.4, d) + smoothstep(130.0 + s - 9.75, 130.0 + s + 9.75, d);
}
// How much of a tree's near foliage is needles rather than stylised sprays, 1 close and 0 beyond about 13 m (shifted per tree by `stagger`, x 4 m, over a 15 % band like the
// other levels). The spray foliage of level 0 and the needle cards are dithered complementarily with this weight, so every pixel belongs to exactly one of them (F02 T66.13).
inline float needle_weight(float d, float stagger) {
    float s = stagger * 4.0;
    return 1.0 - smoothstep(13.0 + s - 2.0, 13.0 + s + 2.0, d);
}
inline bool tree_lod_discard(float4 lod, float3 worldPos, float3 eye, float stagger, float2 pixel) {
    if (lod.x < 0.5) return false;
    float level = tree_lod_level(length(worldPos.xz - eye.xz), stagger);
    return floor(level + ign(pixel)) != lod.y;
}

// 3D value noise. Procedural 3D noise needs no UVs and no texture, so it cannot stretch on steep
// slopes the way a planar projection would (this is why we do not need triplanar mapping).
inline float hash13(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

// ---- Noise toolkit (F01 W0.1). The first noise here was value noise, whose axis-aligned lattice shows as blocks wherever it is thresholded (pits, flakes,
// the path, then the ground). Everything now builds on GRADIENT noise (Perlin, 12 edge gradients, quintic fade) evaluated in a ROTATED frame, and
// every octave of an fbm is rotated again, so no feature direction ever lines up with the world axes. `vnoise3` keeps its name and its 0..1 look
// (mean 0.5, similar spread) so existing thresholds still mean what they did, but it is gradient noise now.
// Perlin's improved gradient selection by bit tricks (16 gradients, 4 of them repeated): no table lookup, a handful of selects.
inline float gdot3(float3 i, float3 d) {
    uint h = uint(hash13(i) * 15.999);
    float a = (h < 8u) ? d.x : d.y;
    float b = (h < 4u) ? d.y : ((h == 12u || h == 14u) ? d.x : d.z);
    return (((h & 1u) == 0u) ? a : -a) + (((h & 2u) == 0u) ? b : -b);
}

// Raw gradient noise, about -1...1. Needs no UVs and no texture, so it cannot stretch on steep slopes.
inline float gnoise3(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);        // quintic fade: C2-continuous, so normals derived from it show no creases
    float a = gdot3(i, f),                          b = gdot3(i + float3(1, 0, 0), f - float3(1, 0, 0));
    float c = gdot3(i + float3(0, 1, 0), f - float3(0, 1, 0)), d = gdot3(i + float3(1, 1, 0), f - float3(1, 1, 0));
    float e = gdot3(i + float3(0, 0, 1), f - float3(0, 0, 1)), g = gdot3(i + float3(1, 0, 1), f - float3(1, 0, 1));
    float h = gdot3(i + float3(0, 1, 1), f - float3(0, 1, 1)), k = gdot3(i + float3(1, 1, 1), f - float3(1, 1, 1));
    return 0.70 * mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}

// A fixed rotation (rows are orthonormal): applied to every query, and again per octave.
constant float3x3 NZ_ROT = float3x3(float3(0.80, -0.48, 0.36), float3(0.60, 0.64, -0.48), float3(0.00, 0.60, 0.80));

// The cheap original, kept for LOW-FREQUENCY fields whose lattice can never be seen (cloud and water noise, the metre-scale patches of the terrain,
// per-blade fields): half the cost of gradient noise, and these run on every pixel of the sky, the sea and the ground.
inline float vnoiseV(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float n000 = hash13(i);
    float n100 = hash13(i + float3(1, 0, 0));
    float n010 = hash13(i + float3(0, 1, 0));
    float n110 = hash13(i + float3(1, 1, 0));
    float n001 = hash13(i + float3(0, 0, 1));
    float n101 = hash13(i + float3(1, 0, 1));
    float n011 = hash13(i + float3(0, 1, 1));
    float n111 = hash13(i + float3(1, 1, 1));
    return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
               mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
inline float fbmV(float3 p) {            // 4 octaves of value noise, range about 0..0.94
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += a * vnoiseV(p);
        p = p * 2.03 + float3(11.7, 3.1, 7.3);
        a *= 0.5;
    }
    return s;
}

inline float vnoise3(float3 x) {
    return clamp(0.5 + 0.72 * gnoise3(NZ_ROT * x + float3(17.3, 5.1, 9.7)), 0.0, 1.0);
}

inline float fbm3(float3 p) {            // 4 octaves, each rotated, range about 0.05..0.95
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += a * vnoise3(p);
        p = NZ_ROT * p * 2.03 + float3(11.7, 3.1, 7.3);
        a *= 0.5;
    }
    return s * 1.06;
}
// Fractal noise with a chosen octave count (rotated octaves), 0..1.
inline float rfbm3(float3 p, int octaves) {
    float s = 0.0, a = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        s += a * vnoise3(p); norm += a;
        p = NZ_ROT * p * 2.03 + float3(11.7, 3.1, 7.3);
        a *= 0.5;
    }
    return s / norm;
}
// Domain warp: bends the coordinate by a slow noise so that shapes built on it curve instead of following a lattice.
inline float3 warp3(float3 p, float amp, float freq) {
    float3 q = p * freq;
    return p + amp * (float3(vnoise3(q), vnoise3(q + 7.7), vnoise3(q + 13.1)) - 0.5);
}
// Ridged (sharp crests: cracks, strata, bark) and billow (rounded lumps: clumps, mounds) variants, 0..1.
inline float ridged3(float3 p, int octaves) {
    float s = 0.0, a = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        float r = 1.0 - abs(2.0 * vnoise3(p) - 1.0);
        s += a * r * r; norm += a;
        p = NZ_ROT * p * 2.07 + float3(3.3, 8.1, 1.9);
        a *= 0.5;
    }
    return s / norm;
}
inline float billow3(float3 p, int octaves) {
    float s = 0.0, a = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        s += a * abs(2.0 * vnoise3(p) - 1.0); norm += a;
        p = NZ_ROT * p * 2.07 + float3(5.9, 2.3, 6.1);
        a *= 0.5;
    }
    return s / norm;
}
// Height blend (F01 W0.2): choose between two layers by their HEIGHTS plus a mask, so the boundary follows the surface's own relief (moss creeping over
// stones, sand drifting into grass) and is never a clean smoothstep of one noise. Returns the weight of layer B, 0..1; `c` is the contrast of the edge.
inline float height_blend(float hA, float hB, float maskB, float c) {
    float a = hA + (1.0 - maskB), b = hB + maskB;
    float m = max(a, b) - c;
    float wa = max(a - m, 0.0), wb = max(b - m, 0.0);
    return wb / max(wa + wb, 1e-5);
}
"""#
}
