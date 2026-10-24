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

    // The lit lighthouse's beam: two opposite sectors that sweep round the lens (obj.emissive.xyz). They are only seen as they
    // light the mist, so the beam shows over the sea and low shore and brightens wherever the haze is thick.
    float beamOn = obj.tint.z;
    if (beamOn > 0.001) {
        float2 dv = P.xz - obj.emissive.xyz.xz;
        float r = length(dv);
        float ang = atan2(dv.x, -dv.y);                                  // 0 = north, increasing clockwise (same as player yaw)
        float a1 = ang - obj.tint.y;
        a1 = a1 - 6.2831853 * floor((a1 + 3.1415927) / 6.2831853);       // wrap to -pi...pi
        float da = min(abs(a1), 3.1415927 - abs(a1));                    // nearest of the two opposite beams
        float widthAng = 0.05;                                           // a narrow wedge of constant angle
        float core = exp(-(da * da) / (widthAng * widthAng));
        float reach = smoothstep(60.0, 220.0, r) * (1.0 - smoothstep(900.0, 2600.0, r));
        float visible = smoothstep(6.0, 60.0, dist) * flat * soft;
        float bm = core * reach * visible * beamOn;
        color = mix(color, float3(3.2, 2.5, 1.3), min(1.0, bm * 1.4));
        alpha = max(alpha, bm * (0.35 + 0.65 * d) * 0.8);
    }
    return float4(color, alpha);
}
"""#
}
