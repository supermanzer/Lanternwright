// Full-screen post passes. T1.11: ACES filmic tonemap + vignette + grain.
enum PostShaders {
    static let source = #"""
// Stephen Hill's fit of the ACES RRT+ODT. It compresses the huge HDR range with a soft shoulder, and desaturates
// very bright colours toward white the way film does (a bright orange sun becomes a warm white, not a flat orange).
// NB: the published matrices are row-major; MSL float3x3 constructors fill by column, so use row dot products.
inline float3 aces_input(float3 c) {
    return float3(dot(float3(0.59719, 0.35458, 0.04823), c),
                  dot(float3(0.07600, 0.90834, 0.01566), c),
                  dot(float3(0.02840, 0.13383, 0.83777), c));
}
inline float3 aces_output(float3 c) {
    return float3(dot(float3(1.60475, -0.53108, -0.07367), c),
                  dot(float3(-0.10208, 1.10813, -0.00605), c),
                  dot(float3(-0.00327, -0.07276, 1.07602), c));
}
inline float3 aces_fitted(float3 c) {
    c = aces_input(c);
    float3 a = c * (c + 0.0245786) - 0.000090537;
    float3 b = c * (0.983729 * c + 0.4329510) + 0.238081;
    c = aces_output(a / b);
    return saturate(c);
}

constexpr sampler bloomSampler(filter::linear, address::clamp_to_edge);

// Bloom: bright pixels bleed light into their surroundings, like glare in a lens or the eye.
// 1. prefilter keeps only energy above a soft threshold (knee avoids a hard cut-off flicker);
// 2. a chain of downsamples (13-tap filter: stable under motion, no shimmer on small bright sources);
// 3. upsample back up with a tent filter, adding each level onto the one above, so glow has a wide falloff.
fragment float4 bloom_prefilter_fragment(FullscreenOut in [[stage_in]],
                                         texture2d<float> src [[texture(0)]]) {
    float2 t = 1.0 / float2(src.get_width(), src.get_height());
    float3 c = 0.25 * (src.sample(bloomSampler, in.uv + float2(-0.5, -0.5) * t).rgb
                     + src.sample(bloomSampler, in.uv + float2( 0.5, -0.5) * t).rgb
                     + src.sample(bloomSampler, in.uv + float2(-0.5,  0.5) * t).rgb
                     + src.sample(bloomSampler, in.uv + float2( 0.5,  0.5) * t).rgb);
    c = min(c, float3(64.0));                               // tame the sun disk so one pixel can't dominate
    const float threshold = 1.0, knee = 0.5;
    float br = max(c.r, max(c.g, c.b));
    float soft = clamp(br - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contrib = max(soft, br - threshold) / max(br, 1e-4);
    return float4(c * contrib, 1.0);
}

fragment float4 bloom_down_fragment(FullscreenOut in [[stage_in]],
                                    texture2d<float> src [[texture(0)]]) {
    float2 t = 1.0 / float2(src.get_width(), src.get_height());
    float2 uv = in.uv;
    float3 a = src.sample(bloomSampler, uv + float2(-2, -2) * t).rgb;
    float3 b = src.sample(bloomSampler, uv + float2( 0, -2) * t).rgb;
    float3 c = src.sample(bloomSampler, uv + float2( 2, -2) * t).rgb;
    float3 d = src.sample(bloomSampler, uv + float2(-2,  0) * t).rgb;
    float3 e = src.sample(bloomSampler, uv).rgb;
    float3 f = src.sample(bloomSampler, uv + float2( 2,  0) * t).rgb;
    float3 g = src.sample(bloomSampler, uv + float2(-2,  2) * t).rgb;
    float3 h = src.sample(bloomSampler, uv + float2( 0,  2) * t).rgb;
    float3 i = src.sample(bloomSampler, uv + float2( 2,  2) * t).rgb;
    float3 j = src.sample(bloomSampler, uv + float2(-1, -1) * t).rgb;
    float3 k = src.sample(bloomSampler, uv + float2( 1, -1) * t).rgb;
    float3 l = src.sample(bloomSampler, uv + float2(-1,  1) * t).rgb;
    float3 m = src.sample(bloomSampler, uv + float2( 1,  1) * t).rgb;
    float3 r = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
    return float4(r, 1.0);
}

// Output is ADDED onto the destination level (additive blending is set on the pipeline).
fragment float4 bloom_up_fragment(FullscreenOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]]) {
    float2 t = 1.0 / float2(src.get_width(), src.get_height());
    float2 uv = in.uv;
    float3 r = src.sample(bloomSampler, uv).rgb * 4.0
             + (src.sample(bloomSampler, uv + float2(0, -1) * t).rgb + src.sample(bloomSampler, uv + float2(-1, 0) * t).rgb
              + src.sample(bloomSampler, uv + float2(1, 0) * t).rgb + src.sample(bloomSampler, uv + float2(0, 1) * t).rgb) * 2.0
             + (src.sample(bloomSampler, uv + float2(-1, -1) * t).rgb + src.sample(bloomSampler, uv + float2(1, -1) * t).rgb
              + src.sample(bloomSampler, uv + float2(-1, 1) * t).rgb + src.sample(bloomSampler, uv + float2(1, 1) * t).rgb);
    return float4(r / 16.0, 1.0);
}

// Screen-space ambient occlusion. Ambient light reaches creases (where grass meets soil, a rock meets the ground,
// a trunk meets the slope) less than open ground; SSAO estimates that from the depth buffer alone. For each pixel we
// rebuild its world position and normal from the distance buffer, scatter 12 sample points in the hemisphere above it,
// project each into the screen and ask "is something in front of that point?". The fraction that are blocked is the
// occlusion. A range check stops far-away surfaces (a hill behind a tree) from darkening the tree.
constant float3 AO_KERNEL[12] = {
    float3(0.35, 0.20, 0.55), float3(-0.40, 0.25, 0.35), float3(0.15, -0.50, 0.45), float3(-0.25, -0.30, 0.70),
    float3(0.60, -0.10, 0.30), float3(-0.55, -0.05, 0.50), float3(0.05, 0.65, 0.40), float3(0.30, 0.35, 0.85),
    float3(-0.15, 0.10, 0.95), float3(0.45, -0.40, 0.60), float3(-0.35, 0.55, 0.55), float3(0.10, -0.15, 0.30)
};

inline float ao_dist(texture2d<float> distTex, int2 p) {
    int2 size = int2(distTex.get_width(), distTex.get_height());
    return distTex.read(uint2(clamp(p, int2(0), size - 1))).r;
}

fragment float4 ssao_fragment(FullscreenOut in [[stage_in]],
                              texture2d<float> distTex [[texture(0)]],
                              constant FrameUniforms& frame [[buffer(1)]]) {
    int2 full = int2(in.position.xy) * 2;
    float d = ao_dist(distTex, full);
    if (d > 9.0e4) return float4(1.0);                                         // sky
    float3 cam = frame.cameraPos.xyz;
    float2 texel = 1.0 / float2(distTex.get_width(), distTex.get_height());
    float2 uv = (float2(full) + 0.5) * texel;
    float3 dir = view_ray(uv, frame);
    float3 P = cam + dir * d;
    // Normal from neighbouring positions, picking the side with the smaller depth jump (avoids smearing over edges).
    int2 e = int2(2, 2);
    float dl = ao_dist(distTex, full - int2(e.x, 0)), dr = ao_dist(distTex, full + int2(e.x, 0));
    float du = ao_dist(distTex, full - int2(0, e.y)), dd = ao_dist(distTex, full + int2(0, e.y));
    float3 Pl = cam + view_ray(uv - float2(e.x * texel.x, 0.0), frame) * dl, Pr = cam + view_ray(uv + float2(e.x * texel.x, 0.0), frame) * dr;
    float3 Pu = cam + view_ray(uv - float2(0.0, e.y * texel.y), frame) * du, Pd = cam + view_ray(uv + float2(0.0, e.y * texel.y), frame) * dd;
    float3 vx = abs(dl - d) < abs(dr - d) ? (P - Pl) : (Pr - P);
    float3 vy = abs(du - d) < abs(dd - d) ? (P - Pu) : (Pd - P);
    float3 N = normalize(cross(vx, vy));
    if (dot(N, -dir) < 0.0) N = -N;

    float radius = frame.casTexel.w;                                          // metres
    float ang = 6.2831853 * fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453);
    float3 helper = abs(N.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 T0 = normalize(cross(helper, N)), B0 = cross(N, T0);
    float3 T = T0 * cos(ang) + B0 * sin(ang), B = cross(N, T);
    float occ = 0.0;
    for (int i = 0; i < 12; i++) {
        float3 k = AO_KERNEL[i];
        float3 S = P + (T * k.x + B * k.y + N * k.z) * radius;
        float4 clip = frame.viewProj * float4(S, 1.0);
        if (clip.w <= 0.0) continue;
        float2 suv = float2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
        if (any(suv < 0.0) || any(suv > 1.0)) continue;
        float sd = ao_dist(distTex, int2(suv / texel));
        float expected = length(S - cam);
        float blocked = (sd < expected - 0.04) ? 1.0 : 0.0;
        float range = 1.0 - smoothstep(0.0, 1.0, abs(d - sd) / (radius * 1.5));
        occ += blocked * range;
    }
    return float4(pow(saturate(1.0 - occ / 12.0), 2.0), 0.0, 0.0, 1.0);
}

// Depth-aware 5x5 blur: smooths the per-pixel rotation noise without bleeding occlusion across depth edges.
fragment float4 ssao_blur_fragment(FullscreenOut in [[stage_in]],
                                   texture2d<float> ao [[texture(0)]],
                                   texture2d<float> distTex [[texture(1)]]) {
    int2 p = int2(in.position.xy);
    int2 size = int2(ao.get_width(), ao.get_height());
    float d0 = ao_dist(distTex, p * 2);
    float sum = 0.0, wsum = 0.0;
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            int2 q = clamp(p + int2(x, y), int2(0), size - 1);
            float dq = ao_dist(distTex, q * 2);
            float w = exp(-abs(dq - d0) / max(0.05 * d0, 0.1));
            sum += ao.read(uint2(q)).r * w; wsum += w;
        }
    }
    return float4(sum / max(wsum, 1e-4), 0.0, 0.0, 1.0);
}

// Multiply the occlusion into the scene. We have no separate ambient buffer, so weight it by how dark the pixel
// already is: a pixel in full sun is mostly direct light (which AO must not darken); a shaded one is all ambient.
fragment float4 ssao_apply_fragment(FullscreenOut in [[stage_in]],
                                    texture2d<float> scene [[texture(0)]],
                                    texture2d<float> ao [[texture(1)]],
                                    constant FrameUniforms& frame [[buffer(1)]]) {
    float3 c = scene.read(uint2(in.position.xy)).rgb;
    float a = ao.sample(bloomSampler, in.uv).r;
    float lum = dot(c, float3(0.3, 0.5, 0.2));
    float weight = frame.casRange.w * (1.0 - smoothstep(0.4, 2.5, lum) * 0.6);
    if (frame.misc.z > 4.5) return float4(float3(a), 1.0);                     // debug: --debug ao
    return float4(c * mix(1.0, a, weight), 1.0);
}

// God rays (crepuscular rays): light shafts that stream from the sun past anything that blocks part of the sky.
// Screen-space trick: for each pixel, march toward the sun's screen position and add up how much unobstructed
// bright sky lies along the way. Only SKY pixels count (the distance buffer holds 1e5 there), so a tree, the hill
// or the lighthouse between you and the sun carves dark shafts out of the glow. Tinted with the sun's own colour.
fragment float4 godrays_fragment(FullscreenOut in [[stage_in]],
                                 texture2d<float> hdr [[texture(0)]],
                                 texture2d<float> distTex [[texture(1)]],
                                 constant FrameUniforms& frame [[buffer(1)]]) {
    float3 sunDir = normalize(frame.sunDir.xyz);
    float4 clip = frame.viewProj * float4(frame.cameraPos.xyz + sunDir * 1000.0, 1.0);
    if (clip.w <= 0.0 || sunDir.y < -0.02) return float4(0.0);            // sun behind the camera or below the horizon
    float2 sunUV = float2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
    float2 delta = sunUV - in.uv;
    float distToSun = length(delta * float2(frame.screen.x / frame.screen.y, 1.0));
    const int N = 48;
    float2 step = delta / float(N) * 0.95;
    float2 uv = in.uv;
    float illum = 1.0, sum = 0.0;
    uint2 size = uint2(distTex.get_width(), distTex.get_height());
    for (int i = 0; i < N; i++) {
        uv += step;
        if (any(uv < 0.0) || any(uv > 1.0)) break;
        float d = distTex.read(min(uint2(uv * float2(size)), size - 1)).r;
        float sky = d > 9.0e4 ? 1.0 : 0.0;
        float3 c = hdr.sample(bloomSampler, uv).rgb;
        sum += sky * min(dot(c, float3(0.33)), 3.0) * illum;
        illum *= 0.965;
    }
    float falloff = 1.0 - smoothstep(0.1, 1.3, distToSun);               // shafts fade with distance from the sun
    float3 tint = frame.sunColor.rgb / max(max(frame.sunColor.r, max(frame.sunColor.g, frame.sunColor.b)), 1e-3);
    return float4(tint * (sum / float(N)) * falloff, 1.0);
}

fragment float4 composite_fragment(FullscreenOut in [[stage_in]],
                                   texture2d<float> hdr [[texture(0)]],
                                   texture2d<float> bloom [[texture(1)]],
                                   texture2d<float> rays [[texture(2)]],
                                   constant FrameUniforms& frame [[buffer(1)]]) {
    float3 c = hdr.read(uint2(in.position.xy)).rgb;
    c += bloom.sample(bloomSampler, in.uv).rgb * frame.fogParams.w;     // bloom strength
    c += rays.sample(bloomSampler, in.uv).rgb * frame.casRadius.w;       // god-ray strength (casRadius.w)
    c *= frame.fogParams.z * 0.6;                       // exposure (0.6 is the scale Hill's fit was authored for)
    c = aces_fitted(c);

    // Vignette: darken toward the corners, gently.
    float2 d = (in.uv - 0.5) * float2(frame.screen.x / frame.screen.y, 1.0);
    c *= mix(1.0, 0.72, smoothstep(0.45, 1.05, length(d)));

    // Grain: +-1.5 % multiplicative, so shadows are not speckled (additive noise is very visible in dark sRGB).
    float g = fract(sin(dot(in.position.xy + frame.cameraPos.w, float2(12.9898, 78.233))) * 43758.5453);
    c *= 1.0 + (g - 0.5) * 0.03;
    return float4(c, 1.0);   // linear; the sRGB drawable encodes it
}

// Debug: view distance (r32Float), 0..1200 m as black..white; the sky (1e5) clamps to white.
fragment float4 depthviz_fragment(FullscreenOut in [[stage_in]],
                                  texture2d<float> dist [[texture(0)]]) {
    float d = dist.read(uint2(in.position.xy)).r;
    float v = saturate(d / 1200.0);
    return float4(float3(v), 1.0);
}
"""#
}
