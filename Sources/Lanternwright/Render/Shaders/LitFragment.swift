// G10.1.4: the lit fragment function: the dispatcher that calls the terrain, material, shadow and lighting pieces.
enum LitFragmentShaders {
    static let source = #"""
// Two outputs: HDR colour, and the straight-line distance from the camera (consumed by the water pass).
struct LitFragOut {
    float4 color [[color(0)]];
    float dist [[color(1)]];
};

fragment LitFragOut lit_fragment(LitOut in [[stage_in]],
                             constant FrameUniforms& frame [[buffer(1)]],
                             constant ObjectUniforms& obj [[buffer(2)]],
                             depth2d<float> shadowMap [[texture(0)]],
                             texture2d<float> skyLUT [[texture(1)]],
                             texture2d<float> irradianceMap [[texture(4)]],
                             depth2d<float> shadowNear [[texture(6)]],
                             depth2d<float> shadowMid [[texture(7)]]) {
    if (kLodDither && tree_lod_discard(obj.lod, in.worldPos, frame.cameraPos.xyz, in.stagger, in.position.xy + frame.misc.x * float2(5.588238, 3.14159))) discard_fragment();
    if (kLodDither) {
        // F02 T66.13: needle cards (lod.w = 1) and the spray foliage of level 0 give way to each other within about 16 m, complementarily through one noise value;
        // a needle card is also alpha-tested with its herringbone pattern, stochastically, so the temporal resolve turns it into smooth needle coverage.
        float fpN = max(length(dfdx(in.worldPos)), length(dfdy(in.worldPos)));      // metres per pixel (derivatives taken before any discard)
        float nW = needle_weight(length(in.worldPos.xz - frame.cameraPos.xz), in.stagger);
        float2 px2 = in.position.xy + frame.misc.x * float2(3.7, 8.1) + float2(31.7, 12.3);
        int midN = int(in.material + 0.5);
        if (obj.lod.w > 0.5) {
            if (ign(px2) >= nW) discard_fragment();
            float cover = needle_cover(in.color.a, clamp((in.material - 23.0) / 0.4, -1.0, 1.0), fract(in.color.r * 91.7 + in.color.g * 37.1), fpN);
            if (cover < needle_threshold(fpN, ign(px2 + float2(7.3, 19.9)))) discard_fragment();
        } else if (obj.lod.y < 0.5 && midN == 3 && ign(px2) < nW) {
            discard_fragment();
        }
    }
    float3 n = normalize(in.normal);
    float fpix = max(length(dfdx(in.worldPos)), length(dfdy(in.worldPos)));     // metres per pixel (for band-limited noise)
    float3 albedo = in.color.rgb;
    float rough = in.color.a;
    if (in.material > 0.5 && in.material < 1.5) {
        float3 Ng = n;
        albedo = terrain_surface(in.worldPos, Ng, in.color.r, in.color.g, in.color.b, frame.worldB.x, fpix, frame.cameraPos.w, frame.worldB.z, frame.worldB.y, n, rough);
    }

    // Procedural prop materials (masonry, paint, iron, copper, wood, bark): albedo, roughness, metalness, bumped normal, AO.
    float metal = 0.0, matAO = 1.0;
    float3 glyphGlow = float3(0.0);
    int mid = int(in.material + 0.5);
    if (mid >= 5) {
        // Position in the object's own frame (origin and orientation of its model matrix: the lighthouse axis, the dock's length, a stone's face).
        float3x3 Rm = float3x3(obj.model.columns[0].xyz, obj.model.columns[1].xyz, obj.model.columns[2].xyz);
        float3 Pl = transpose(Rm) * (in.worldPos - obj.model.columns[3].xyz);
        MatOut mo = material_surface(mid, Pl, in.worldPos, n, albedo, rough, clamp((in.material - float(mid)) / 0.4, -1.0, 1.0), fpix);
        albedo = mo.albedo; rough = mo.rough; metal = mo.metal; n = mo.N; matAO = mo.ao;
        if (mid == 14 || mid == 20) {
            float3 Vw = normalize(frame.cameraPos.xyz - in.worldPos);
            glyphGlow = carve_glyph(Pl, in.worldPos, transpose(Rm) * normalize(in.normal), transpose(Rm) * Vw, obj.tint, obj.emissive, albedo, rough, n);
        }
    }

    float3 V = normalize(frame.cameraPos.xyz - in.worldPos);
    float3 L = normalize(frame.sunDir.xyz);
    float NoV = max(dot(n, V), 1e-3);
    float NoL = saturate(dot(n, L));
    const float F0d = 0.04;                                      // dielectrics
    float3 F0 = mix(float3(F0d), albedo, metal);                 // metals: no diffuse, F0 = albedo

    // Sun: E is irradiance (the sun's colour after the atmosphere took its share).
    int cascade = 2;
    float shadow = sun_shadow(in.worldPos, normalize(in.normal), NoL, in.position.xy, frame, shadowMap, shadowNear, shadowMid, cascade);
    float3 E = frame.sunColor.rgb * frame.sunColor.w * shadow;
    float3 diffuse = albedo * (1.0 - metal) / M_PI_F * E * NoL * mix(1.0, matAO, 0.6);

    // GGX specular (Trowbridge-Reitz D, height-correlated Smith V, Schlick F).
    float a = max(rough * rough, 0.02);
    float a2 = a * a;
    float3 H = normalize(V + L);
    float NoH = saturate(dot(n, H)), VoH = saturate(dot(V, H));
    float dd = NoH * NoH * (a2 - 1.0) + 1.0;
    float D = a2 / (M_PI_F * dd * dd);
    float Vis = 0.5 / max(NoL * sqrt(NoV * NoV * (1.0 - a2) + a2) + NoV * sqrt(NoL * NoL * (1.0 - a2) + a2), 1e-4);
    float3 F = F0 + (1.0 - F0) * pow(1.0 - VoH, 5.0);
    float3 specular = E * D * Vis * F * NoL;
    bool foliage = in.material > 2.5 && in.material < 3.5;
    if (foliage) {
        // Leaves are thin and bushy: light wraps around them and shines through. Plain N.L would make a conifer
        // black on its shaded side. Wrap lighting + a back-lit translucency term, no glossy highlight.
        float wrap = saturate((dot(n, L) + 0.45) / 1.45);
        float trans = pow(saturate(dot(V, -L)), 3.0) * saturate(0.6 - n.y * 0.5);
        diffuse = albedo / M_PI_F * E * (wrap + 0.6 * trans);
        specular = float3(0.0);
        n = normalize(mix(n, float3(0.0, 1.0, 0.0), 0.5));          // soft, sky-facing ambient
    }

    // Image-based ambient: the sky LUT is the only light source besides the sun.
    // Diffuse ambient from the convolved irradiance map (see irradiance_fragment for why not a blurry LUT mip).
    float3 irradiance = irradianceMap.sample(skySampler, lut_uv(n)).rgb;
    float3 R = reflect(-V, n);
    if (mid == 8) R = normalize(float3(R.x, max(R.y, 0.30 + 0.25 * rough), R.z));             // copper roof (R07-5): a gloss lobe aimed at the ground row of the sky LUT painted dark patches; fall back to a dim, roughness-biased sky tint
    if (mid == 18) R = normalize(float3(R.x, max(R.y, 0.14), R.z));       // a mirror shows the sky, not the dark ground row of the table
    float3 envSpec = skyLUT.sample(skySampler, lut_uv(R), level(rough * 6.0)).rgb;
    float3 fEnv = F0 + (max(float3(1.0 - rough), F0) - F0) * pow(1.0 - NoV, 5.0);
    float3 ambient = (albedo * irradiance * (1.0 - metal) * (1.0 - dot(fEnv, float3(0.333))) + envSpec * fEnv) * matAO;
    // Warm ground bounce: the sun-lit ground re-radiates into everything that faces down or sideways, so shade is warmer and
    // lighter near the ground instead of lit only by cool sky. Irradiance of the sun on the ground (E cos(elevation)) times a ground
    // albedo, spread over the lower hemisphere: full for surfaces facing down, half for walls, none for tops.
    bool glassWorld = frame.worldB.x > 0.5;
    float3 groundAlb = glassWorld ? float3(0.22, 0.24, 0.34) : float3(0.36, 0.28, 0.18);
    float3 bounce = groundAlb * frame.sunColor.rgb * frame.sunColor.w * max(L.y, 0.10) / M_PI_F * 1.6;
    ambient += albedo * (1.0 - metal) * bounce * saturate(0.5 - 0.5 * n.y) * matAO;
    // S03.5b interior light model: inside the tower (items flagged `lod.z`) the sky's ambient and the ground bounce reach only through the doorway and the windows, so they are cut to a
    // tenth; the sun still lights the inside through the shadow map (the tower's wall occludes it, the open door does not). Two warm lamps, one in the ground room and one in the lens
    // room, light it instead: a soft point light with an inverse-square-ish falloff, no shadow (light casts none, F04 L1).
    if (obj.lod.z > 0.5) {
        ambient *= 0.14;          // a little floor of ambient so the stair is never unreadable between the lamps
        const float3 lampPos[2] = { float3(\#(LighthouseInterior.lampGround.x), \#(LighthouseInterior.lampGround.y), \#(LighthouseInterior.lampGround.z)),
                                    float3(\#(LighthouseInterior.lampLens.x), \#(LighthouseInterior.lampLens.y), \#(LighthouseInterior.lampLens.z)) };
        for (int li = 0; li < 2; li++) {
            float3 toLamp = lampPos[li] - in.worldPos;
            float d2 = dot(toLamp, toLamp);
            float3 Ll = toLamp * rsqrt(max(d2, 1e-4));
            float atten = 1.0 / (1.0 + d2 * 0.12);
            ambient += albedo * (1.0 - metal) * float3(1.0, 0.62, 0.30) * \#(LighthouseInterior.lampPower) * atten * saturate(max(dot(n, Ll), -0.5 * dot(n, Ll)) * 0.8 + 0.2) * matAO;          // two-sided: a tread seen from either side is lit by the lamp
        }
    }

    float3 emissive = (mid == 14 || mid == 20) ? glyphGlow : (mid == 16 ? float3(0.0) : obj.emissive.rgb * obj.emissive.w * (mid == 15 ? 0.35 : 1.0));   // paper: the hover pulse is a hint, not a lamp
    float3 col = diffuse + specular + ambient + emissive;
    col = apply_fog(col, in.worldPos, frame, skyLUT);
    // Debug views (--debug shadow|albedo|ambient).
    if (frame.misc.z > 0.5 && frame.misc.z < 1.5) col = float3(shadow, NoL * 4.0, 0.0);   // r = shadow factor, g = 4 x N.L
    if (frame.misc.z > 1.5 && frame.misc.z < 2.5) col = albedo;
    if (frame.misc.z > 2.5 && frame.misc.z < 3.5) col = ambient;
    if (frame.misc.z > 3.5) col = (cascade == 0 ? float3(1, 0.2, 0.2) : (cascade == 1 ? float3(0.2, 1, 0.2) : float3(0.2, 0.3, 1))) * (0.25 + 0.75 * shadow);   // cascade tint
    LitFragOut o;
    o.color = float4(col, 1.0);
    o.dist = length(in.worldPos - frame.cameraPos.xyz);
    return o;
}
"""#
}
