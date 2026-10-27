// G10.1.4: shadow-map lookup (PCF and the cascade choice and cross-fade) for the lit shader, split out of Lit.swift unchanged.
enum ShadowLookupShaders {
    static let source = #"""
constexpr sampler shadowSampler(coord::normalized, filter::linear, address::clamp_to_border,
                                border_color::opaque_white, compare_func::less_equal);

constexpr sampler depthPoint(coord::normalized, filter::nearest, address::clamp_to_edge);

constant float2 POISSON16[16] = {
    float2(-0.94201624, -0.39906216), float2(0.94558609, -0.76890725), float2(-0.09418410, -0.92938870),
    float2(0.34495938, 0.29387760),   float2(-0.91588581, 0.45771432), float2(-0.81544232, -0.87912464),
    float2(-0.38277543, 0.27676845),  float2(0.97484398, 0.75648379),  float2(0.44323325, -0.97511554),
    float2(0.53742981, -0.47373420),  float2(-0.26496911, -0.41893023), float2(0.79197514, 0.19090188),
    float2(-0.24188840, 0.99706507),  float2(-0.81409955, 0.91437590), float2(0.19984126, 0.78641367),
    float2(0.14383161, -0.14100790)
};

// Percentage-closer filtering: compare against the shadow map at 16 jittered taps and average the
// yes/no answers, which turns a hard aliased edge into a soft one. The taps are rotated per pixel so the
// leftover banding becomes fine noise. Bias: normal offset (pushes the lookup off the surface) plus a
// slope-scaled depth bias covering the whole PCF kernel (~2.5 texels of slope at a grazing sun).
float shadow_lookup(depth2d<float> tex, float4x4 vp, float texelWorld, float range,
                    float3 P, float3 N, float NoL, float2 pixel) {
    float3 Po = P + N * (texelWorld * (0.5 + 1.0 * (1.0 - NoL)));
    float4 sp = vp * float4(Po, 1.0);
    float2 uv = float2(sp.x * 0.5 + 0.5, 0.5 - sp.y * 0.5);
    if (any(uv < 0.0) || any(uv > 1.0) || sp.z > 1.0) return 1.0;
    float cosT = max(NoL, 0.05);
    float tanT = min(sqrt(1.0 - cosT * cosT) / cosT, 12.0);
    float z = sp.z - (0.0002 + 2.5 * tanT * texelWorld / range);       // world-space bias -> depth units
    // Interleaved gradient noise (Jimenez): a per-pixel rotation whose error is spread evenly across neighbouring pixels, so the
    // leftover banding becomes fine, even noise (the old sin-hash gave clumpy noise and costs a sin per pixel).
    float ang = 6.2831853 * fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
    float2x2 rot = float2x2(float2(cos(ang), sin(ang)), float2(-sin(ang), cos(ang)));
    float texel = 1.0 / float(tex.get_width());
    // PCSS contact hardening. 1) Blocker search: 8 taps in a small disc; none closer to the light = fully lit, done (also the
    // cheap path for most of the screen). 2) The sun is a disc of ~0.53 degrees, so a shadow edge widens by ~0.0093 m for every
    // metre between blocker and receiver: crisp where the shadow touches its caster, soft far from it. 3) PCF at that width.
    float blockerSum = 0.0; int blockers = 0;
    for (int i = 0; i < 8; i++) {
        float d = tex.sample(depthPoint, uv + (rot * POISSON16[i * 2]) * texel * 4.0);
        if (d < z) { blockerSum += d; blockers++; }
    }
    if (blockers == 0) return 1.0;
    float blockerDepth = blockerSum / float(blockers);
    float penumbraWorld = (z - blockerDepth) * range * 0.0093;                 // metres
    float radius = clamp(penumbraWorld / max(texelWorld, 1e-4) * 2.0, 1.2, 5.0);   // PCF radius in texels (1.2 = the old crisp edge)
    float sum = 0.0;
    for (int i = 0; i < 16; i++) {
        sum += tex.sample_compare(shadowSampler, uv + (rot * POISSON16[i]) * texel * radius, z);
    }
    return sum / 16.0;
}

// Cascaded shadow maps. Resolution is spent where the eye is: cascade 0 (a few metres around you) is razor sharp,
// cascade 1 covers the neighbourhood, cascade 2 the whole island. The cascade is picked by distance from the
// camera, with a short cross-fade so the seams don't show. `cascade` reports which one was used (debug view).
float sun_shadow(float3 P, float3 N, float NoL, float2 pixel, constant FrameUniforms& frame,
                 depth2d<float> far2, depth2d<float> near0, depth2d<float> mid1, thread int& cascade) {
    float d = length(P - frame.cameraPos.xyz);
    float r0 = frame.casRadius.x * 0.9, r1 = frame.casRadius.y * 0.9;
    float sFar = 1.0;
    if (d >= r1 * 0.85)
        sFar = shadow_lookup(far2, frame.sunViewProj, frame.casTexel.z, frame.casRange.z, P, N, NoL, pixel);
    if (d >= r1) { cascade = 2; return sFar; }
    float sMid = shadow_lookup(mid1, frame.sunViewProj1, frame.casTexel.y, frame.casRange.y, P, N, NoL, pixel);
    if (d >= r0) {
        cascade = 1;
        return mix(sMid, sFar, smoothstep(r1 * 0.85, r1, d));
    }
    float sNear = shadow_lookup(near0, frame.sunViewProj0, frame.casTexel.x, frame.casRange.x, P, N, NoL, pixel);
    cascade = 0;
    return mix(sNear, sMid, smoothstep(r0 * 0.85, r0, d));
}
"""#
}
