// Main opaque surface shader. T1.3: Lambert + flat ambient. Later tasks add terrain materials,
// image-based lighting, GGX, shadows and aerial perspective.
enum LitShaders {
    static let source = #"""
// Depth-only pass from the sun's point of view.
vertex float4 shadow_vertex(uint vid [[vertex_id]],
                            device const Vertex* verts [[buffer(0)]],
                            constant FrameUniforms& frame [[buffer(1)]],
                            constant ObjectUniforms& obj [[buffer(2)]]) {
    return frame.sunViewProj * (obj.model * float4(verts[vid].position.xyz, 1.0));
}

struct LitOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float4 color;      // rgb albedo, a roughness
    float material;
};

vertex LitOut lit_vertex(uint vid [[vertex_id]],
                         device const Vertex* verts [[buffer(0)]],
                         constant FrameUniforms& frame [[buffer(1)]],
                         constant ObjectUniforms& obj [[buffer(2)]]) {
    Vertex v = verts[vid];
    float4 wp = obj.model * float4(v.position.xyz, 1.0);
    LitOut o;
    o.position = frame.viewProj * wp;
    o.worldPos = wp.xyz;
    o.normal = (obj.model * float4(v.normal.xyz, 0.0)).xyz;   // uniform scale assumed
    o.color = float4(v.color.rgb * obj.tint.rgb, v.color.a);
    o.material = v.normal.w;
    return o;
}

// Terrain material: grass (lush/parched patches), rock (steep or high, with horizontal strata),
// sand (shore, darker where wet), packed earth on the path. Also perturbs the normal for close-up detail.
float3 terrain_surface(float3 P, float3 Ng, float pathW, float wet, thread float3& N, thread float& rough) {
    float slope = Ng.y;
    float macro = fbm3(P * 0.012);                 // large patches
    float meso = fbm3(P * 0.35);                   // clumps
    float micro = vnoise3(P * 9.0);                // grain (about 11 cm cells)

    float dry = smoothstep(0.38, 0.62, macro + (P.y - 20.0) * 0.004);
    float3 lush = float3(0.060, 0.165, 0.030), parched = float3(0.27, 0.205, 0.070);
    float3 grass = mix(lush, parched, dry) * (0.65 + 0.7 * meso) * (0.9 + 0.2 * micro);

    float strata = fbm3(P * float3(0.12, 0.9, 0.12));      // squashed along Y: horizontal bands
    float3 rock = mix(float3(0.20, 0.185, 0.165), float3(0.40, 0.355, 0.30), strata) * (0.85 + 0.3 * micro);

    float rockMask = 1.0 - smoothstep(0.72, 0.90, slope);
    rockMask = max(rockMask, 0.65 * smoothstep(52.0, 66.0, P.y + 12.0 * (macro - 0.5)));
    float3 albedo = mix(grass, rock, rockMask);

    float wetSand = 1.0 - smoothstep(-0.1, 0.5, P.y);
    float3 sand = mix(float3(0.56, 0.47, 0.31), float3(0.30, 0.235, 0.15), wetSand) * (0.94 + 0.12 * micro);
    float sandMask = wet * (1.0 - 0.7 * rockMask);
    albedo = mix(albedo, sand, sandMask);

    float pebble = smoothstep(0.72, 0.82, vnoise3(P * 6.0));
    float3 earth = mix(float3(0.23, 0.165, 0.10), float3(0.38, 0.32, 0.25), pebble) * (0.85 + 0.3 * meso);
    float pm = smoothstep(0.25, 0.75, pathW + (meso - 0.5) * 0.5);
    albedo = mix(albedo, earth, pm);

    // Normal perturbation: gradient of a small bump field, projected onto the surface plane.
    float rockiness = max(rockMask, pm * 0.5);
    float scale = mix(3.0, 1.5, rockMask);                 // finer grain on soil/sand, coarser on rock
    float e = 0.12;
    float3 q = P * scale;
    float b0 = vnoise3(q) * 0.6 + vnoise3(q * 3.1) * 0.4;
    float3 g = float3(vnoise3(q + float3(e, 0, 0)) * 0.6 + vnoise3((q + float3(e, 0, 0)) * 3.1) * 0.4 - b0,
                      vnoise3(q + float3(0, e, 0)) * 0.6 + vnoise3((q + float3(0, e, 0)) * 3.1) * 0.4 - b0,
                      vnoise3(q + float3(0, 0, e)) * 0.6 + vnoise3((q + float3(0, 0, e)) * 3.1) * 0.4 - b0) / e;
    g -= dot(g, Ng) * Ng;
    float bumpStrength = mix(0.006, 0.15, rockiness) * (1.0 - 0.5 * sandMask);   // sand stays smooth: pits read as noise at a grazing sun
    N = normalize(Ng - g * bumpStrength);

    rough = mix(mix(0.92, 0.85, rockMask), mix(0.95, 0.45, wetSand), sandMask);
    return albedo;
}

constexpr sampler shadowSampler(coord::normalized, filter::linear, address::clamp_to_border,
                                border_color::opaque_white, compare_func::less_equal);

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
// leftover banding becomes fine noise. Normal-offset bias pushes the lookup off the surface in proportion
// to how grazing the light is (the main cause of "shadow acne" at a low sun).
float sun_shadow(float3 P, float3 N, float NoL, float2 pixel,
                 constant FrameUniforms& frame, depth2d<float> tex) {
    float texelWorld = frame.misc.w;
    float3 Po = P + N * (texelWorld * (0.5 + 1.0 * (1.0 - NoL)));
    float4 sp = frame.sunViewProj * float4(Po, 1.0);
    float2 uv = float2(sp.x * 0.5 + 0.5, 0.5 - sp.y * 0.5);
    if (any(uv < 0.0) || any(uv > 1.0) || sp.z > 1.0) return 1.0;
    // Slope-scaled depth bias. On a receiver tilted tan(theta) from the light's view, one shadow texel spans
    // texelWorld * tan(theta) of depth, so that is how much "wrongness" the depth test must forgive. Moving the
    // lookup along the normal cannot do this at a grazing sun (it barely changes depth along the light ray).
    // Depth is normalised over the box depth (2R = texelWorld * width), hence the division by the map width.
    float cosT = max(NoL, 0.05);
    float tanT = min(sqrt(1.0 - cosT * cosT) / cosT, 12.0);
    // The PCF kernel reaches about 1.6 texels from the centre (+0.5 for the bilinear compare), so the bias must
    // cover ~2.5 texels of slope, not one.
    float z = sp.z - (0.0002 + 2.5 * tanT / float(tex.get_width()));
    float ang = 6.2831853 * fract(sin(dot(pixel, float2(12.9898, 78.233))) * 43758.5453);
    float2x2 rot = float2x2(float2(cos(ang), sin(ang)), float2(-sin(ang), cos(ang)));
    float texel = 1.0 / float(tex.get_width());
    float sum = 0.0;
    for (int i = 0; i < 16; i++) {
        sum += tex.sample_compare(shadowSampler, uv + (rot * POISSON16[i]) * texel * 1.6, z);
    }
    return sum / 16.0;
}

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
                             texture2d<float> irradianceMap [[texture(4)]]) {
    float3 n = normalize(in.normal);
    float3 albedo = in.color.rgb;
    float rough = in.color.a;
    if (in.material > 0.5 && in.material < 1.5) {
        float3 Ng = n;
        albedo = terrain_surface(in.worldPos, Ng, in.color.r, in.color.g, n, rough);
    }

    float3 V = normalize(frame.cameraPos.xyz - in.worldPos);
    float3 L = normalize(frame.sunDir.xyz);
    float NoV = max(dot(n, V), 1e-3);
    float NoL = saturate(dot(n, L));
    const float F0 = 0.04;                                       // dielectrics

    // Sun: E is irradiance (the sun's colour after the atmosphere took its share).
    float shadow = sun_shadow(in.worldPos, normalize(in.normal), NoL, in.position.xy, frame, shadowMap);
    float3 E = frame.sunColor.rgb * frame.sunColor.w * shadow;
    float3 diffuse = albedo / M_PI_F * E * NoL;

    // GGX specular (Trowbridge-Reitz D, height-correlated Smith V, Schlick F).
    float a = max(rough * rough, 0.02);
    float a2 = a * a;
    float3 H = normalize(V + L);
    float NoH = saturate(dot(n, H)), VoH = saturate(dot(V, H));
    float dd = NoH * NoH * (a2 - 1.0) + 1.0;
    float D = a2 / (M_PI_F * dd * dd);
    float Vis = 0.5 / max(NoL * sqrt(NoV * NoV * (1.0 - a2) + a2) + NoV * sqrt(NoL * NoL * (1.0 - a2) + a2), 1e-4);
    float F = F0 + (1.0 - F0) * pow(1.0 - VoH, 5.0);
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
    float3 envSpec = skyLUT.sample(skySampler, lut_uv(R), level(rough * 6.0)).rgb;
    float fEnv = F0 + (max(1.0 - rough, F0) - F0) * pow(1.0 - NoV, 5.0);
    float3 ambient = albedo * irradiance * (1.0 - fEnv) + envSpec * fEnv;

    float3 emissive = obj.emissive.rgb * obj.emissive.w;
    float3 col = diffuse + specular + ambient + emissive;
    col = apply_fog(col, in.worldPos, frame, skyLUT);
    // Debug views (--debug shadow|albedo|ambient).
    if (frame.misc.z > 0.5 && frame.misc.z < 1.5) col = float3(shadow, NoL * 4.0, 0.0);   // r = shadow factor, g = 4 x N.L
    if (frame.misc.z > 1.5 && frame.misc.z < 2.5) col = albedo;
    if (frame.misc.z > 2.5) col = ambient;
    LitFragOut o;
    o.color = float4(col, 1.0);
    o.dist = length(in.worldPos - frame.cameraPos.xyz);
    return o;
}
"""#
}
