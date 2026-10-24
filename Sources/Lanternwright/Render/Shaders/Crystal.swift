// Glass. Crystal geometry is drawn AFTER the opaque scene has been copied, and each pixel looks *through* the facet:
// the view ray is bent by the facet's normal (Snell's law with an index of about 1.45), the bent ray's end point is
// projected back to the screen, and the copied scene colour there is what you see inside the glass. Flat facets bend the
// view by different amounts, which is what gives faceted glass its stained-glass, kaleidoscopic look. On top:
//   - Fresnel reflection of the sky (glass mirrors grazing views),
//   - a specular highlight of the main light (the moon),
//   - slowly drifting "veins" of light inside, tinted by the vertex colour.
enum CrystalShaders {
    static let source = #"""
fragment float4 crystal_fragment(LitOut in [[stage_in]],
                                 constant FrameUniforms& frame [[buffer(1)]],
                                 constant ObjectUniforms& obj [[buffer(2)]],
                                 texture2d<float> skyLUT [[texture(1)]],
                                 texture2d<float> sceneCopy [[texture(2)]],
                                 texture2d<float> distTex [[texture(3)]]) {
    if (kLodDither && tree_lod_discard(obj.lod, in.worldPos, frame.cameraPos.xyz, in.stagger, in.position.xy)) discard_fragment();
    float3 P = in.worldPos;
    float3 toCam = frame.cameraPos.xyz - P;
    float dist = length(toCam);
    float3 V = toCam / dist;
    float3 N = normalize(in.normal);
    if (dot(N, V) < 0.0) N = -N;                          // facets are flat, so just make sure the normal faces the viewer
    float NoV = saturate(dot(N, V));
    float t = frame.cameraPos.w;

    // Refraction: bend the view ray, project where it would end up, and read the scene there.
    float3 R = refract(-V, N, 1.0 / 1.45);
    float3 target = P + R * 3.0;
    float4 clip = frame.viewProj * float4(target, 1.0);
    float2 uv = in.position.xy * frame.screen.zw;
    float2 uvR = (clip.w > 0.0) ? float2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5) : uv;
    uvR = clamp(uvR, 0.001, 0.999);
    uint2 size = uint2(distTex.get_width(), distTex.get_height());
    // Never "see through" a pixel that is in front of the glass (a nearer tree, the player's own foreground).
    float behind = distTex.read(min(uint2(uvR * float2(size)), size - 1)).r;
    if (behind < dist) uvR = uv;
    float3 through = sceneCopy.sample(waterLinear, uvR).rgb;

    // The glass tint (vertex colour) filters what passes through, and a little of it scatters inside.
    float3 tint = in.color.rgb;
    float3 body = through * mix(float3(1.0), tint, 0.75) + tint * 0.035;

    // Fresnel reflection of the sky and a sharp highlight of the main light.
    float F = 0.04 + 0.96 * pow(1.0 - NoV, 5.0);
    float3 refl = skyLUT.sample(skySampler, lut_uv(reflect(-V, N)), level(1)).rgb;
    float3 L = normalize(frame.sunDir.xyz);
    float3 H = normalize(V + L);
    float NoH = saturate(dot(N, H));
    float a2 = 0.0064;                                    // roughness 0.28 squared-ish: tight but not a pinpoint
    float dd = NoH * NoH * (a2 - 1.0) + 1.0;
    float D = a2 / (M_PI_F * dd * dd);
    float3 spec = frame.sunColor.rgb * frame.sunColor.w * min(D * 0.12, 25.0) * saturate(dot(N, L) + 0.2);

    // Veins of light drifting through the crystal (3D noise, so they flow across facets without UV seams).
    float3 vp = P * 1.1 + float3(0.0, t * 0.08, t * 0.05);
    float vein = 0.65 * vnoiseV(vp) + 0.35 * vnoiseV(vp * 2.3);        // two octaves are plenty for slow veins, and cheap
    vein = smoothstep(0.58, 0.72, vein);
    float pulse = 0.75 + 0.25 * sin(t * 1.3 + P.x * 0.2 + P.z * 0.17);
    float core = step(0.5, in.color.a);                              // vertex alpha > 0.5 marks a self-lit vein (the crystal trees' trunk vein)
    float3 glow = tint * obj.emissive.rgb * obj.emissive.w * (0.18 + 1.8 * vein * pulse + 3.0 * core * pulse);

    float3 col = mix(body, refl, F) + spec + glow;
    col = apply_fog(col, P, frame, skyLUT);
    return float4(col, 1.0);
}
"""#
}
