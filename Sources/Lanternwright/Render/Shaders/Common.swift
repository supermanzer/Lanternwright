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

// 3D value noise. Procedural 3D noise needs no UVs and no texture, so it cannot stretch on steep
// slopes the way a planar projection would (this is why we do not need triplanar mapping).
inline float hash13(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

inline float vnoise3(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);     // quintic fade: C2-continuous, so normals derived from it show no grid creases
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

inline float fbm3(float3 p) {            // 4 octaves, range about 0..0.94
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += a * vnoise3(p);
        p = p * 2.03 + float3(11.7, 3.1, 7.3);
        a *= 0.5;
    }
    return s;
}
"""#
}
