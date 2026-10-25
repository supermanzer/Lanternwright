// Temporal anti-aliasing (F02 R1, user note #23: shimmer on fine detail). The scene is rendered with a sub-pixel jitter (Halton 2,3 over 8 samples, see Renderer.updateFrame);
// this resolves it against the previous resolved frame:
//   1. Reproject: each pixel's depth (the hardware depth buffer, which includes water and glass) is turned into a world point with the UNJITTERED inverse view-projection,
//      and projected with the previous frame's unjittered matrix: that is the motion vector (the world is static; camera motion is all of it).
//   2. History is read with a Catmull-Rom filter (so repeated resampling does not blur), clipped to the colour box of the current 3x3 neighbourhood (variance clipping in YCoCg,
//      gamma 1.25) so anything that changed (a disocclusion, a moving beam) cannot ghost, and blended: 10 % current when still, more with motion, 100 % without history.
//   3. All of it in a compressed colour space (c / (1 + max c)) so one hot pixel (the sun, a glint) cannot dominate; the stored history is plain HDR.
// A second pass sharpens the resolved image a little (a contrast-adaptive sharpen), writing back into the scene HDR buffer that bloom and the composite read.
enum TAAShaders {
    static let source = #"""
struct TaaUniforms {
    float4x4 prevViewProj;   // previous frame, UNjittered
    float4x4 invViewProj;    // current frame, UNjittered
    float4 params;           // x, y = this frame's jitter (pixels), z = 1 when the history is valid, w = sharpen strength
    float4 screen;           // width, height, 1/width, 1/height
    float4 tuning;           // x = weight of the new frame when still, y = at speed, z = colour box width (sigma multiples)
};

inline float3 taa_comp(float3 c) { return c / (1.0 + max(c.r, max(c.g, c.b))); }
inline float3 taa_uncomp(float3 c) { float m = min(max(c.r, max(c.g, c.b)), 0.9995); return c / (1.0 - m); }
inline float3 taa_ycocg(float3 c) { return float3(0.25 * c.r + 0.5 * c.g + 0.25 * c.b, 0.5 * c.r - 0.5 * c.b, -0.25 * c.r + 0.5 * c.g - 0.25 * c.b); }
inline float3 taa_rgb(float3 c) { return float3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z); }

constexpr sampler taaLinear(filter::linear, address::clamp_to_edge);

// Catmull-Rom history lookup in 5 bilinear taps (the corner taps are dropped): sharp under sub-pixel motion, where plain bilinear would blur a little every frame.
inline float3 taa_history(texture2d<float> hist, float2 uv, float2 size) {
    float2 pos = uv * size;
    float2 c = floor(pos - 0.5) + 0.5;
    float2 f = pos - c;
    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f * f * (-0.5 + 0.5 * f);
    float2 w12 = w1 + w2;
    float2 o12 = w2 / w12;
    float2 t0 = (c - 1.0) / size, t3 = (c + 2.0) / size, t12 = (c + o12) / size;
    float3 r = hist.sample(taaLinear, float2(t12.x, t0.y)).rgb * (w12.x * w0.y)
             + hist.sample(taaLinear, float2(t0.x, t12.y)).rgb * (w0.x * w12.y)
             + hist.sample(taaLinear, float2(t12.x, t12.y)).rgb * (w12.x * w12.y)
             + hist.sample(taaLinear, float2(t3.x, t12.y)).rgb * (w3.x * w12.y)
             + hist.sample(taaLinear, float2(t12.x, t3.y)).rgb * (w12.x * w3.y);
    float wsum = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    return max(r / wsum, float3(0.0));
}

fragment float4 taa_resolve_fragment(FullscreenOut in [[stage_in]],
                                     constant TaaUniforms& u [[buffer(0)]],
                                     texture2d<float> cur [[texture(0)]],
                                     texture2d<float> hist [[texture(1)]],
                                     depth2d<float> depthTex [[texture(2)]]) {
    int2 size = int2(cur.get_width(), cur.get_height());
    int2 p = int2(in.position.xy);
    // Current neighbourhood: mean and deviation in YCoCg (the colour box history is clipped to), and the CLOSEST depth in the 3x3 (so an edge pixel
    // reprojects with the nearer surface and does not smear). The current colour itself is RECONSTRUCTED from the 3x3 with a Gaussian-like weight on how far each
    // sample actually fell from this pixel's centre (neighbour (dx, dy) sampled the scene at (dx, dy) - jitter from the centre), so the sub-pixel jitter is a real
    // area filter and not a source of flicker.
    float3 m1 = float3(0.0), m2 = float3(0.0), cw = float3(0.0);
    float wsum = 0.0, nearest = 1.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2 q = clamp(p + int2(dx, dy), int2(0), size - 1);
            float3 sc = taa_comp(cur.read(uint2(q)).rgb);
            float3 s = taa_ycocg(sc);
            m1 += s; m2 += s * s;
            float2 off = float2(float(dx), float(dy)) - u.params.xy;
            float wt = exp(-2.29 * dot(off, off));
            cw += sc * wt; wsum += wt;
            nearest = min(nearest, depthTex.read(uint2(q)));
        }
    }
    float3 c0 = cw / max(wsum, 1e-4);
    float3 mean = m1 / 9.0, sigma = sqrt(max(m2 / 9.0 - mean * mean, float3(0.0)));
    float2 uv = (float2(p) + 0.5) * u.screen.zw;
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 wp = u.invViewProj * float4(ndc, nearest, 1.0);
    wp /= wp.w;
    float4 pc = u.prevViewProj * wp;
    float2 pndc = pc.xy / pc.w;
    float2 prevUV = float2(pndc.x * 0.5 + 0.5, 0.5 - pndc.y * 0.5);
    bool inside = all(prevUV > 0.0) && all(prevUV < 1.0) && pc.w > 0.0;
    if (u.params.z < 0.5 || !inside) return float4(taa_uncomp(c0), 1.0);
    float3 h = taa_comp(taa_history(hist, prevUV, u.screen.xy));
    // Clip the history toward the neighbourhood's mean until it sits inside mean +- gamma * sigma (in YCoCg).
    float3 hy = taa_ycocg(h);
    float3 lo = mean - u.tuning.z * sigma - 0.002, hi = mean + u.tuning.z * sigma + 0.002;
    float3 d = hy - mean;
    float3 ext = max(hi - mean, 1e-4);
    float k = max(max(abs(d.x) / ext.x, abs(d.y) / ext.y), abs(d.z) / ext.z);
    if (k > 1.0) hy = mean + d / k;
    (void)lo;
    h = taa_rgb(hy);
    float velocity = length((prevUV - uv) * u.screen.xy);              // pixels this surface moved since the last frame
    float alpha = mix(u.tuning.x, u.tuning.y, saturate(velocity / 8.0));
    return float4(taa_uncomp(mix(h, c0, alpha)), 1.0);
}

// Contrast-adaptive sharpening of the resolved frame (after AMD's CAS): the sharpening weight shrinks where the local contrast is already high, so there are no halos.
fragment float4 taa_sharpen_fragment(FullscreenOut in [[stage_in]],
                                     constant TaaUniforms& u [[buffer(0)]],
                                     texture2d<float> src [[texture(0)]]) {
    int2 size = int2(src.get_width(), src.get_height());
    int2 p = int2(in.position.xy);
    float3 raw = src.read(uint2(p)).rgb;
    float3 c = taa_comp(raw);
    float3 n = taa_comp(src.read(uint2(clamp(p + int2(0, -1), int2(0), size - 1))).rgb);
    float3 s = taa_comp(src.read(uint2(clamp(p + int2(0, 1), int2(0), size - 1))).rgb);
    float3 e = taa_comp(src.read(uint2(clamp(p + int2(1, 0), int2(0), size - 1))).rgb);
    float3 w = taa_comp(src.read(uint2(clamp(p + int2(-1, 0), int2(0), size - 1))).rgb);
    float3 mn = min(c, min(min(n, s), min(e, w))), mx = max(c, max(max(n, s), max(e, w)));
    float3 amp = sqrt(saturate(min(mn, 1.0 - mx) / max(mx, 1e-3)));
    float peak = -1.0 / mix(8.0, 5.0, saturate(u.params.w));
    float3 wgt = amp * peak;
    float3 sharp = saturate((c + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt));
    return float4(taa_uncomp(mix(c, sharp, step(0.001, u.params.w))), 1.0);
}
"""#
}
