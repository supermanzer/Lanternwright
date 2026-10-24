// Ground detail (F01 W1): what the green, the sand and the stony slope are MADE of, down to millimetres. The terrain shader used to give the ground
// colour fields from 11 cm noise, which at 0.3 m reads as a magnified low-resolution image. Here the ground is layered like a real one: under the
// blades there is soil with grit and small stones, moss mats (velvety, in damp places), clover and low herbs in clumps, a few dead straw fibres; sand
// has grains, shell grit, pebbles and ripples; slopes have scree. Every layer is band-limited with `featVis` (R09) and FADES TO ITS MEAN, and the mean of
// each class is the old flat colour that the terrain shader computed (`meanCol`), so distant ground is unchanged and the detail arrives gradually.
// Boundaries between layers are decided by HEIGHT (height_blend), so moss creeps over stones and sand drifts into grass along irregular lines.
enum GroundShaders {
    static let source = #"""
struct GroundOut {
    float3 albedo;
    float h;           // relief in metres (feeds the bump normal)
    float rough;
};

// 2D cellular noise with the vector to the nearest feature point: xy = from that point to p (cell units), z = distance F1, w = cell id 0..1.
inline float4 cell2n(float2 p) {
    float2 i = floor(p), f = fract(p);
    float d1 = 1e9; float2 v = float2(0.0); float id = 0.0;
    for (int k = 0; k < 9; k++) {
        float2 g = float2(float(k % 3) - 1.0, float(k / 3) - 1.0);
        float2 h2 = hash22w(i + g + 31.0);
        float2 r = g + 0.15 + 0.7 * h2 - f;
        float d = dot(r, r);
        if (d < d1) { d1 = d; v = -r; id = h2.x; }
    }
    return float4(v, sqrt(d1), id);
}

// The luminance of a colour (for keeping means).
inline float lum3(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ---- Meadow floor, seen from above: a turf mat. Combed fibres (grass blades lying every which way, 3 mm wide and about 3 cm long, in a slowly turning
// direction field so there is never a lattice), dark soil specks between them, moss mats in damp places (soft domes, velvet), sparse small clover, a few straw fibres.
// `meanCol` is the class's old flat colour (lush or parched, with its patchiness): the mat colour is built so the mean stays exactly that.
inline GroundOut ground_meadow(float3 P, float fpix, float3 meanCol, float moisture, bool glass) {
    GroundOut o;
    float v6 = featVis(0.06, fpix), v1 = featVis(0.012, fpix), v4 = featVis(0.004, fpix);
    float3 soil = glass ? float3(0.075, 0.060, 0.125) : float3(0.120, 0.086, 0.054);
    float2 xz = P.xz;
    // Moss: damp, low, sheltered; organic outlines (domain-warped, two scales).
    float3 pw = warp3(P, 0.10, 2.6);
    float mossField = rfbm3(pw * 5.0, 3) * 0.65 + 0.35 * rfbm3(P * 1.1 + 4.0, 2);
    float mossMask = smoothstep(0.42, 0.74, mossField + (moisture - 0.5) * 0.7);
    // Combed fibres: two crossing sets whose direction turns slowly across the ground (only evaluated where they can be seen: inside ~5 m).
    float fibre = 0.5, fibB = 0.5;
    if (v4 > 0.01) {
        float th1 = 9.4 * vnoise3(float3(xz * 2.1, 1.0)), th2 = 9.4 * vnoise3(float3(xz * 2.1 + 9.0, 2.0)) + 1.3;
        float2 d1 = float2(cos(th1), sin(th1)), d2 = float2(cos(th2), sin(th2));
        float fibA = vnoise3(float3(dot(xz, d1) * 32.0, dot(xz, float2(-d1.y, d1.x)) * 300.0, 1.7));
        fibB = vnoise3(float3(dot(xz, d2) * 52.0, dot(xz, float2(-d2.y, d2.x)) * 420.0, 4.2));
        fibre = mix(0.5, 0.58 * fibA + 0.42 * fibB, v4);
    }
    float tuft = mix(0.5, vnoise3(P * 70.0 + 2.0), v1);                              // 1.4 cm clumps within the mat
    float velvet = v4 > 0.01 ? mix(0.5, vnoise3(P * 380.0), v4) : 0.5;               // moss velvet
    // The mat: tone along each fibre (dark root, pale tip), clumped; soil specks where the fibres part.
    float3 grassMat = meanCol * (0.45 + 1.10 * fibre) * (0.84 + 0.32 * tuft);
    float3 mossMat = meanCol * float3(0.88, 1.06, 0.74) * (0.80 + 0.40 * tuft) * (0.92 + 0.16 * velvet);
    float3 mat = mix(grassMat, mossMat, mossMask * v6);
    float speck = smoothstep(0.36, 0.14, fibre) * (1.0 - 0.7 * mossMask) * v4 + 0.05 * (1.0 - v4);          // bare soil, about 8 % on average
    float3 grit = soil * (0.7 + 0.6 * vnoise3(P * 240.0));
    float4 gc = cell2n(xz * 48.0 + 5.0);
    float pebble = (1.0 - smoothstep(0.04, 0.08 + 0.18 * fract(gc.w * 9.3), gc.z)) * step(0.80, gc.w) * v1;      // the odd small stone showing through
    float3 col = mix(mat, grit, saturate(speck));
    col = mix(col, float3(0.25, 0.235, 0.21) * (0.7 + 0.6 * gc.w), pebble * 0.8);
    // Clover: small trifoliate leaves (three lobes round a stem, about 4 cm), in a few clumps in the damp places.
    float4 cl = cell2n(xz * 11.0 + 3.0);
    float ca = cl.w * 6.2831853;
    float2 lp = float2(cl.x * cos(ca) - cl.y * sin(ca), cl.x * sin(ca) + cl.y * cos(ca));
    float lobes = 1e9;
    for (int k = 0; k < 3; k++) { float a = 2.0 * 3.1415927 * float(k) / 3.0; lobes = min(lobes, length(lp - 0.15 * float2(cos(a), sin(a)))); }
    float cloverClump = smoothstep(0.52, 0.76, rfbm3(P * 2.4 + 9.0, 2) + (moisture - 0.5) * 0.35);
    float hasClover = step(0.30, fract(cl.w * 7.31)) * cloverClump;
    float leaf = (1.0 - smoothstep(0.09, 0.14, lobes)) * hasClover * v6;
    float3 cloverCol = meanCol * float3(0.78, 1.30, 0.66) * (0.85 + 0.35 * smoothstep(0.14, 0.0, lobes)) + float3(0.04, 0.05, 0.03) * smoothstep(0.02, 0.0, abs(lp.y));
    col = mix(col, cloverCol, leaf);
    // Straw: a few dead, pale blades lying in the mat.
    float straw = smoothstep(0.80, 0.93, fibB) * (1.0 - mossMask) * v4 * 0.55;
    col = mix(col, float3(0.46, 0.38, 0.21) * (0.8 + 0.4 * tuft), straw);
    // Keep the mean: the mat factors above average to about the old flat colour (tone 0.45 + 1.1 * 0.5 = 1.0; tuft 1.0), soil specks and clover are small.
    o.albedo = col;
    o.h = v1 * (0.0035 * (fibre - 0.5) + 0.0028 * (tuft - 0.5) * (1.0 + mossMask) + 0.004 * pebble) + leaf * 0.002;
    o.rough = mix(0.97, 0.82, mossMask * v1);                                        // moss has a faint soft sheen
    return o;
}

// ---- Sand: grains of several tones, shell grit, a few pebbles, soft ripple relief. `meanCol` is the old sand colour (wet or dry).
inline GroundOut ground_sand(float3 P, float fpix, float3 meanCol, float wetSand) {
    GroundOut o;
    float v3 = featVis(0.03, fpix), v03 = featVis(0.0015, fpix), v1 = featVis(0.012, fpix);
    float2 xz = P.xz;
    float grain = mix(0.5, vnoise3(P * 900.0), v03);                                 // 1.1 mm grains
    float grain2 = mix(0.5, vnoise3(P * 230.0 + 5.0), featVis(0.005, fpix));         // 4 mm clusters
    float3 tint = mix(float3(1.0), mix(float3(1.18, 1.05, 0.88), float3(0.78, 0.74, 0.70), smoothstep(0.35, 0.8, vnoise3(P * 600.0 + 2.0))), 0.5 * v03);
    float3 col = meanCol * tint * (0.88 + 0.24 * grain) * (0.94 + 0.12 * grain2);
    // Shell grit and small pebbles scattered: white flecks and grey stones, in clusters (they collect along the high-tide line).
    float4 pc = cell2n(xz * 34.0 + 7.0);
    float cluster = smoothstep(0.45, 0.8, rfbm3(P * 0.9 + 3.0, 2));
    float stone = (1.0 - smoothstep(0.04, 0.10 + 0.20 * fract(pc.w * 13.7), pc.z)) * step(0.55 - 0.3 * cluster, pc.w) * 0.9 * v3;
    float4 fc = cell2n(xz * 85.0 + 21.0);
    float fleck = (1.0 - smoothstep(0.08, 0.16, fc.z)) * step(0.80 - 0.25 * cluster, fc.w) * v1;
    col = mix(col, float3(0.30, 0.28, 0.25) * (0.7 + 0.6 * pc.w), stone);
    col = mix(col, float3(0.85, 0.82, 0.74), fleck * 0.8);
    // Fine ripples: soft ridges about 6 cm apart, bent by a slow noise (the terrain shader adds the wind ripples at 1 m).
    float rip = sin((dot(xz, float2(0.8, 0.6)) + 0.6 * (rfbm3(P * 1.6, 2) - 0.5)) * 105.0);
    o.albedo = col * (1.0 + 0.03 * rip * v1);
    o.h = v1 * (0.0025 * rip + 0.003 * (grain2 - 0.5)) + stone * 0.008 + fleck * 0.002;
    o.rough = mix(0.88, 0.5, wetSand);
    return o;
}

// ---- Scree: angular plates and stones of rock on a slope, with dark crevices and lit edges. Isotropic 3D cellular noise (no projection, so no stretching
// on a steep face); two scales, the big plates over the small stones. `meanCol` is the old rock colour.
inline GroundOut ground_scree(float3 P, float3 Ng, float fpix, float3 meanCol) {
    GroundOut o;
    float v1 = featVis(0.02, fpix), v6 = featVis(0.08, fpix), v03 = featVis(0.005, fpix);
    float3 q = warp3(P, 0.05, 6.0);
    float3 big = worley3F(q * 6.0), small = worley3F(q * 20.0 + 5.0);
    float crackBig = smoothstep(0.0, 0.10, big.y - big.x), crackSmall = smoothstep(0.0, 0.12, small.y - small.x);
    float plate = crackBig;                                                           // 0 in the crevices, 1 on the plate
    float stones = mix(crackSmall, 1.0, 0.0) * plate;                                // small stones break the plates up
    float tone = 0.42 + 1.00 * mix(small.z, big.z, 0.55);                             // per-stone tone, a wide range: grey-brown to near black
    float grain = mix(0.5, vnoise3(P * 300.0), v03);
    float lichen = smoothstep(0.58, 0.82, vnoise3(q * 11.0 + 3.0)) * step(0.4, big.z) * v6;                // pale lichen on some stones
    float3 stoneCol = meanCol * tone * (0.88 + 0.24 * grain);
    stoneCol = mix(stoneCol, float3(0.46, 0.50, 0.30) * (0.8 + 0.4 * grain), lichen * 0.55);
    float3 gap = mix(meanCol * float3(0.20, 0.18, 0.15), float3(0.07, 0.11, 0.04), smoothstep(0.4, 0.75, vnoise3(q * 5.0 + 8.0)) * 0.6);     // dark, damp, a little moss in the crevices
    float3 col = mix(gap, stoneCol, saturate(stones * 1.1));
    col *= 1.0 + 0.12 * smoothstep(0.55, 0.9, crackBig) * (1.0 - smoothstep(0.9, 1.0, crackBig));        // lit edges
    col = mix(meanCol, col, v6);
    o.albedo = col;
    o.h = v1 * (0.016 * (plate * 0.65 + stones * 0.35) + 0.003 * (grain - 0.5));
    o.rough = mix(0.9, 0.97, (1.0 - stones) * v1);
    return o;
}
"""#
}
