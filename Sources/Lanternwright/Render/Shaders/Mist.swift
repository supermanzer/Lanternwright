// Drifting mist sheets: a few big translucent layers hovering just above the sea and the low ground. Each is the ocean
// disc mesh drawn alpha-blended with a slowly moving noise pattern, tinted with the horizon-air colour from the sky LUT.
// Where a sheet meets geometry (the beach, a rock) its opacity fades over a few metres, so there is no hard intersection line.
enum MistShaders {
    static let source = #"""
struct MistOut {
    float4 position [[position]];
    float3 worldPos;
};

vertex MistOut mist_vertex(uint vid [[vertex_id]],
                           device const Vertex* verts [[buffer(0)]],
                           constant FrameUniforms& frame [[buffer(1)]],
                           constant ObjectUniforms& obj [[buffer(2)]]) {
    float4 wp = obj.model * float4(verts[vid].position.xyz, 1.0);
    MistOut o;
    o.worldPos = wp.xyz;
    o.position = frame.viewProj * wp;
    return o;
}

fragment float4 mist_fragment(MistOut in [[stage_in]],
                              constant FrameUniforms& frame [[buffer(1)]],
                              constant ObjectUniforms& obj [[buffer(2)]],
                              texture2d<float> skyLUT [[texture(1)]],
                              texture2d<float> distTex [[texture(3)]]) {
    float3 P = in.worldPos;
    float3 toP = P - frame.cameraPos.xyz;
    float dist = length(toP);
    float3 dir = toP / dist;
    float t = frame.cameraPos.w;
    float seed = obj.tint.w;                                       // per-sheet offset so layers differ

    // Patchy density that drifts slowly with the wind.
    float2 q = P.xz * 0.0035 + float2(t * 0.012, t * 0.007) + seed * 7.0;
    float d = fbm3(float3(q, t * 0.01 + seed));
    d = smoothstep(0.40, 0.78, d);

    // Fade with distance (nothing right under your nose, nothing at the horizon) and with how edge-on the sheet is.
    float distFade = smoothstep(12.0, 90.0, dist) * (1.0 - smoothstep(550.0, 1000.0, dist));
    float flat = smoothstep(0.0, 4.0, abs(frame.cameraPos.y - P.y));

    // Soft intersection: fade where geometry is just behind the sheet.
    uint2 size = uint2(distTex.get_width(), distTex.get_height());
    float sceneD = distTex.read(min(uint2(in.position.xy), size - 1)).r;
    float soft = clamp((sceneD - dist) / 8.0, 0.0, 1.0);

    float3 mistDir = normalize(float3(dir.x, max(dir.y, 0.04), dir.z));
    float3 color = skyLUT.sample(skySampler, lut_uv(mistDir), level(2)).rgb;
    float alpha = d * distFade * flat * soft * obj.tint.x;
    return float4(color, alpha);
}
"""#
}
