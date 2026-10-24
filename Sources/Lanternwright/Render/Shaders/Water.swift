// Ocean surface. Everything about the look comes from five ideas:
//  1. Gerstner waves move vertices in circles (not just up/down), giving sharp crests and flat troughs.
//  2. Scrolling noise normals add the small ripples the mesh can't represent.
//  3. Fresnel: looking straight down you see through the water, at grazing angles you see the sky reflected.
//  4. Beer-Lambert absorption: red light dies within a few metres, blue survives, so depth turns teal.
//  5. Refraction: the "see-through" colour is the scene copy sampled at a slightly offset pixel.
enum WaterShaders {
    static let source = #"""
struct WaterOut {
    float4 position [[position]];
    float3 worldPos;
    float3 gNormal;
};

// x = direction angle (rad), y = wavelength (m), z = amplitude (m), w = steepness 0..1
constant float4 WAVES[4] = {
    float4(0.30, 60.0, 0.22, 0.6), float4(1.10, 31.0, 0.12, 0.6),
    float4(-0.70, 17.0, 0.06, 0.6), float4(2.20, 9.0, 0.03, 0.5)
};

vertex WaterOut water_vertex(uint vid [[vertex_id]],
                             device const Vertex* verts [[buffer(0)]],
                             constant FrameUniforms& frame [[buffer(1)]],
                             constant ObjectUniforms& obj [[buffer(2)]]) {
    float4 w0 = obj.model * float4(verts[vid].position.xyz, 1.0);
    float2 xz = w0.xz;
    float t = frame.cameraPos.w;
    float dist = length(xz - frame.cameraPos.xz);
    float strength = frame.misc.y * (1.0 - smoothstep(250.0, 1800.0, dist));   // flatten far waves (aliasing)

    float3 disp = float3(0.0);
    float3 nrm = float3(0.0, 1.0, 0.0);
    for (int i = 0; i < 4; i++) {
        float2 d = float2(cos(WAVES[i].x), sin(WAVES[i].x));
        float k = 2.0 * M_PI_F / WAVES[i].y;
        float A = WAVES[i].z * strength;
        float omega = sqrt(9.81 * k);                       // deep-water dispersion: long waves travel faster
        float th = k * dot(d, xz) - omega * t;
        float Q = WAVES[i].w / (k * max(WAVES[i].z, 1e-3) * 4.0);   // keeps crests from looping over themselves
        disp.xz += Q * A * d * cos(th);
        disp.y += A * sin(th);
        nrm.xz -= d * k * A * cos(th);
        nrm.y -= Q * k * A * sin(th);
    }
    WaterOut o;
    float3 wp = float3(w0.x + disp.x, w0.y + disp.y, w0.z + disp.z);
    o.worldPos = wp;
    o.gNormal = normalize(nrm);
    o.position = frame.viewProj * float4(wp, 1.0);
    return o;
}

constexpr sampler waterLinear(filter::linear, address::clamp_to_edge);

// Ripple height field: three scrolling layers of noise. The normal comes from finite differences.
inline float ripple_height(float2 p, float t) {
    float h = 0.0;
    h += 0.50 * vnoise3(float3(p * 0.9 + float2(t * 0.35, t * 0.12), t * 0.15));
    h += 0.30 * vnoise3(float3(p * 2.3 + float2(-t * 0.22, t * 0.41), t * 0.23));
    h += 0.20 * vnoise3(float3(p * 5.7 + float2(t * 0.30, -t * 0.26), t * 0.37));
    return h;
}

fragment float4 water_fragment(WaterOut in [[stage_in]],
                               constant FrameUniforms& frame [[buffer(1)]],
                               texture2d<float> skyLUT [[texture(1)]],
                               texture2d<float> sceneCopy [[texture(2)]],
                               texture2d<float> distTex [[texture(3)]]) {
    float t = frame.cameraPos.w;
    float3 P = in.worldPos;
    float3 toCam = frame.cameraPos.xyz - P;
    float waterDist = length(toCam);
    float3 V = toCam / waterDist;

    // Normal = geometric (Gerstner) + ripples, with the ripples fading out with distance to avoid shimmer.
    float rippleAmt = 0.35 * (1.0 - smoothstep(40.0, 400.0, waterDist));
    float e = 0.08;
    float h0 = ripple_height(P.xz, t);
    float hx = ripple_height(P.xz + float2(e, 0.0), t);
    float hz = ripple_height(P.xz + float2(0.0, e), t);
    float3 N = normalize(in.gNormal + float3(-(hx - h0) / e, 0.0, -(hz - h0) / e) * rippleAmt * 0.35);
    float NoV = saturate(dot(N, V));

    // Fresnel (Schlick, F0 of water = 0.02).
    float F = 0.02 + 0.98 * pow(1.0 - NoV, 5.0);

    // Reflection of the sky. Rays that would go below the horizon (from wave tilt) are mirrored up.
    float3 R = reflect(-V, N);
    R.y = max(abs(R.y), 0.03);                            // keep clear of the LUT horizon row, which blends in the ground
    float3 reflection = skyLUT.sample(skySampler, lut_uv(normalize(R)), level(1)).rgb;

    // Refraction: look at the scene copy through the surface.
    uint2 size = uint2(distTex.get_width(), distTex.get_height());
    float2 uv = in.position.xy * frame.screen.zw;
    float sceneD0 = distTex.read(min(uint2(in.position.xy), size - 1)).r;
    float thick0 = min(max(sceneD0 - waterDist, 0.0), 200.0);
    float2 uv2 = uv + N.xz * 0.03 * smoothstep(0.0, 1.5, thick0);
    float sceneD = distTex.read(min(uint2(uv2 * frame.screen.xy), size - 1)).r;
    if (sceneD < waterDist) { uv2 = uv; sceneD = sceneD0; }      // never refract a pixel from in front of the water
    float3 sceneCol = sceneCopy.sample(waterLinear, uv2).rgb;
    float thick = min(max(sceneD - waterDist, 0.0), 200.0);       // path length through the water

    // Beer-Lambert: transmitted fraction falls off exponentially with distance, red fastest.
    float3 absorb = float3(0.45, 0.09, 0.06);
    float3 transmit = exp(-thick * absorb);
    float3 sunDir = normalize(frame.sunDir.xyz);
    float3 lightUp = skyLUT.sample(skySampler, float2(0.5, 0.0), level(5)).rgb + frame.sunColor.rgb * frame.sunColor.w / M_PI_F * max(sunDir.y, 0.0) * 0.25;
    float3 deep = float3(0.02, 0.10, 0.12) * lightUp * 1.5;       // light scattered back up out of the water
    float3 refracted = sceneCol * transmit + deep * (1.0 - transmit);

    // Sun glint: GGX specular lobe on the rippled surface.
    float3 L = sunDir;
    float NoL = saturate(dot(N, L));
    float3 H = normalize(V + L);
    float NoH = saturate(dot(N, H));
    float a = 0.045;
    float a2 = a * a;
    float dd = NoH * NoH * (a2 - 1.0) + 1.0;
    float D = a2 / (M_PI_F * dd * dd);
    float3 E = frame.sunColor.rgb * frame.sunColor.w;
    float3 glint = E * min(D * 0.25 / max(NoV, 0.05), 60.0) * F * NoL * 0.25;

    float3 col = refracted * (1.0 - F) + reflection * F + glint;

    // Shore foam: where the water is shallow (vertical depth = path length x cos of the view angle).
    float vDepth = thick * V.y;
    float n1 = vnoise3(float3(P.xz * 1.3, t * 0.4));
    float n2 = vnoise3(float3(P.xz * 4.1, -t * 0.6));
    float surge = 0.5 + 0.5 * sin(t * 0.9 + n1 * 6.0);                // foam line advances and retreats
    float foam = smoothstep(0.55 + 0.25 * surge, 0.0, vDepth + (n1 - 0.5) * 0.3) * (0.55 + 0.45 * n2);
    foam *= smoothstep(0.0, 0.08, vDepth);                            // clean edge where water meets land
    float3 foamLit = (lightUp + E * max(sunDir.y, 0.0) / M_PI_F * 0.5) * 0.7;
    col = mix(col, foamLit, saturate(foam) * 0.85);

    col = apply_fog(col, P, frame, skyLUT);
    return float4(col, 1.0);
}
"""#
}
