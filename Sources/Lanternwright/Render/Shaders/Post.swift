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

fragment float4 composite_fragment(FullscreenOut in [[stage_in]],
                                   texture2d<float> hdr [[texture(0)]],
                                   texture2d<float> bloom [[texture(1)]],
                                   constant FrameUniforms& frame [[buffer(1)]]) {
    float3 c = hdr.read(uint2(in.position.xy)).rgb;
    c += bloom.sample(bloomSampler, in.uv).rgb * frame.fogParams.w;     // bloom strength
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
