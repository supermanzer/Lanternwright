// Atmosphere. Single-scattering ray-march (Rayleigh + Mie) baked into a lat-long LUT.
//
// Why a LUT: marching the atmosphere per pixel for every surface (sky, fog, water reflection, ambient light)
// would be far too slow. Marching it once into a 256x128 texture and sampling that everywhere is cheap, and
// it guarantees all of those things agree about the colour of the sky.
//
// LUT mapping: u = azimuth / 2pi (0 = north, clockwise, so +X is east), v = angle from zenith / pi
// (0 = straight up, 0.5 = horizon, 1 = straight down). Keep the constants in sync with World/Atmosphere.swift.
enum SkyShaders {
    static let source = #"""
constant float EARTH_R = 6360e3;
constant float ATMO_R  = 6420e3;
constant float3 BETA_R = float3(5.8e-6, 13.5e-6, 33.1e-6);   // Rayleigh scattering at sea level, per metre
constant float BETA_M  = 21e-6;                              // Mie scattering (extinction = 1.1x)
constant float H_R = 7994.0;                                 // scale heights (m): density falls by e per H
constant float H_M = 1200.0;
constant float MIE_G = 0.76;
constant float LUT_CAM_HEIGHT = 10.0;
constant float3 GROUND_ALBEDO = float3(0.10, 0.09, 0.07);

// Ray vs sphere centred on the planet's centre. Returns (near, far) distances or (-1, -1).
// Uses (|o|-R)(|o|+R) rather than |o|^2 - R^2 because float32 cancels badly at 4e13.
inline float2 ray_sphere(float3 o, float3 d, float R) {
    float b = dot(o, d);
    float lo = length(o);
    float disc = b * b - (lo - R) * (lo + R);
    if (disc < 0.0) return float2(-1.0);
    float s = sqrt(disc);
    return float2(-b - s, -b + s);
}

inline float3 lut_direction(float2 uv) {
    float phi = (uv.x - 0.5) * 2.0 * M_PI_F;
    float theta = uv.y * M_PI_F;
    return float3(sin(theta) * sin(phi), cos(theta), -sin(theta) * cos(phi));
}

// Radiance arriving along rayDir for a viewer at camHeight above sea level.
float3 atmosphere(float3 rayDir, float3 sunDir, float camHeight, float sunI) {
    const int N = 16, M = 6;
    float3 o = float3(0.0, EARTH_R + camHeight, 0.0);
    float tmax = ray_sphere(o, rayDir, ATMO_R).y;
    float2 tg = ray_sphere(o, rayDir, EARTH_R);
    bool hitGround = false;
    if (tg.x > 0.0) { tmax = min(tmax, tg.x); hitGround = true; }

    float mu = dot(rayDir, sunDir);
    float phaseR = 3.0 / (16.0 * M_PI_F) * (1.0 + mu * mu);
    float g = MIE_G;
    float phaseM = 3.0 / (8.0 * M_PI_F) * ((1.0 - g * g) * (1.0 + mu * mu))
                 / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));

    float odR = 0.0, odM = 0.0;
    float3 sumR = 0.0, sumM = 0.0;
    for (int i = 0; i < N; i++) {
        // Quadratic spacing: dense near the viewer where the air is thick.
        float a = float(i) / float(N), b = float(i + 1) / float(N);
        float t0 = tmax * a * a, t1 = tmax * b * b;
        float ds = t1 - t0;
        float3 pos = o + rayDir * (0.5 * (t0 + t1));
        float h = max(length(pos) - EARTH_R, 0.0);
        float hr = exp(-h / H_R) * ds, hm = exp(-h / H_M) * ds;
        odR += hr; odM += hm;

        if (ray_sphere(pos, sunDir, EARTH_R).x > 0.0) continue;          // in the planet's shadow
        float dl = ray_sphere(pos, sunDir, ATMO_R).y / float(M);
        float lodR = 0.0, lodM = 0.0;
        for (int j = 0; j < M; j++) {
            float3 pl = pos + sunDir * ((float(j) + 0.5) * dl);
            float hl = max(length(pl) - EARTH_R, 0.0);
            lodR += exp(-hl / H_R) * dl; lodM += exp(-hl / H_M) * dl;
        }
        // Multiple-scattering fudge: single scattering extinguishes light on long, low paths and leaves the horizon
        // too dark; in reality scattered light is re-scattered into the ray. Counting the view-path extinction at half
        // strength approximates that and gives the pale horizon real skies have. (Sun-path extinction stays full
        // strength: that is what makes a low sun orange.)
        float3 att = exp(-(BETA_R * (0.5 * odR + lodR) + BETA_M * 1.1 * (0.5 * odM + lodM)));
        sumR += att * hr; sumM += att * hm;
    }
    float3 col = (sumR * BETA_R * phaseR + sumM * BETA_M * phaseM) * sunI;

    if (hitGround) {
        float3 gp = o + rayDir * tmax;
        float3 up = normalize(gp);
        float ndl = max(dot(up, sunDir), 0.0);
        if (ndl > 0.0 && ray_sphere(gp + up * 1.0, sunDir, EARTH_R).x <= 0.0) {
            float dl = ray_sphere(gp, sunDir, ATMO_R).y / float(M);
            float lodR = 0.0, lodM = 0.0;
            for (int j = 0; j < M; j++) {
                float3 pl = gp + sunDir * ((float(j) + 0.5) * dl);
                float hl = max(length(pl) - EARTH_R, 0.0);
                lodR += exp(-hl / H_R) * dl; lodM += exp(-hl / H_M) * dl;
            }
            float3 attSun = exp(-(BETA_R * lodR + BETA_M * 1.1 * lodM));
            float3 attView = exp(-(BETA_R * odR + BETA_M * 1.1 * odM));
            col += GROUND_ALBEDO / M_PI_F * sunI * ndl * attSun * attView;
        }
    }
    return col;
}

fragment float4 skylut_fragment(FullscreenOut in [[stage_in]],
                                constant FrameUniforms& frame [[buffer(1)]]) {
    float3 dir = lut_direction(in.uv);
    return float4(atmosphere(dir, normalize(frame.sunDir.xyz), LUT_CAM_HEIGHT, frame.sunColor.w), 1.0);
}

// Diffuse irradiance map (32x16, same lat-long layout as the sky LUT): for each direction n, the cosine-weighted
// average of the sky over the hemisphere around n, divided by pi (so a uniform sky of radiance L gives L).
// Why not just sample a blurry LUT mip at n? Lat-long maps are singular at the poles: for flat ground n is
// almost exactly "up", and the tiniest change in n.xz swings the azimuth lookup to another column, which at a
// coarse mip holds a very different sector of sky. A convolved map is smooth in azimuth near the pole by
// construction, so that jitter is harmless.
fragment float4 irradiance_fragment(FullscreenOut in [[stage_in]],
                                    texture2d<float> lut [[texture(0)]]) {
    float3 n = lut_direction(in.uv);
    const uint W = 32, H = 16;                        // LUT mip 3 is 32x16
    float3 sum = float3(0.0);
    for (uint y = 0; y < H; y++) {
        float theta = (float(y) + 0.5) / float(H) * M_PI_F;
        float dOmega = (2.0 * M_PI_F / float(W)) * (M_PI_F / float(H)) * sin(theta);
        for (uint x = 0; x < W; x++) {
            float3 w = lut_direction(float2((float(x) + 0.5) / float(W), (float(y) + 0.5) / float(H)));
            float c = dot(n, w);
            if (c > 0.0) sum += lut.read(uint2(x, y), 3).rgb * c * dOmega;
        }
    }
    return float4(sum / M_PI_F, 1.0);
}

inline float2 lut_uv(float3 d) {
    return float2(atan2(d.x, -d.z) / (2.0 * M_PI_F) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / M_PI_F);
}

constexpr sampler skySampler(filter::linear, mip_filter::linear, s_address::repeat, t_address::clamp_to_edge);

// Fraction of sunlight surviving the trip through the atmosphere to a viewer at camHeight.
// This is what turns a low sun orange: the long path scatters blue away first.
float3 sun_transmittance(float3 sunDir, float camHeight) {
    float3 o = float3(0.0, EARTH_R + camHeight, 0.0);
    if (ray_sphere(o, sunDir, EARTH_R).x > 0.0) return float3(0.0);
    float len = ray_sphere(o, sunDir, ATMO_R).y;
    float odR = 0.0, odM = 0.0;
    const int N = 24;
    for (int i = 0; i < N; i++) {
        float a = float(i) / float(N), b = float(i + 1) / float(N);
        float t0 = len * a * a, t1 = len * b * b;
        float3 p = o + sunDir * (0.5 * (t0 + t1));
        float h = max(length(p) - EARTH_R, 0.0);
        odR += exp(-h / H_R) * (t1 - t0);
        odM += exp(-h / H_M) * (t1 - t0);
    }
    return exp(-(BETA_R * odR + BETA_M * 1.1 * odM));
}

// Aerial perspective. Air scatters light, so distant things take on the colour of the sky and lose contrast,
// which the brain reads as distance. Density falls off exponentially with height (thick haze near the sea,
// clear air up the hill), and the optical depth along a straight ray through such a medium has a closed form,
// so no per-pixel marching is needed:  tau = d0 * e^(-k*y0) * L * (1 - e^(-k*dy)) / (k*dy)
// The in-scattered colour is read from the same sky LUT as the sky itself, so fog and horizon always agree.
float3 apply_fog(float3 color, float3 P, constant FrameUniforms& frame, texture2d<float> lut) {
    float3 toP = P - frame.cameraPos.xyz;
    float L = length(toP);
    float3 dir = toP / max(L, 1e-4);
    float d0 = frame.fogParams.x, k = frame.fogParams.y;
    float kdy = clamp(k * dir.y * L, -20.0, 20.0);
    float f = abs(kdy) < 1e-3 ? 1.0 : (1.0 - exp(-kdy)) / kdy;
    float tau = d0 * exp(-k * frame.cameraPos.y) * L * f;
    float T = exp(-tau);
    // Rays that point below the horizon would read the LUT's "ground"; haze should look like horizon air instead.
    float3 fogDir = normalize(float3(dir.x, max(dir.y, 0.03), dir.z));
    float3 fogColor = lut.sample(skySampler, lut_uv(fogDir), level(1)).rgb;
    return color * T + fogColor * (1.0 - T);
}

// The sky is drawn as a full-screen triangle at depth 1 so it only shows where no geometry was drawn.
vertex FullscreenOut sky_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenOut o;
    o.position = float4(p * 2.0 - 1.0, 1.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

inline float3 view_ray(float2 uv, constant FrameUniforms& frame) {
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 w = frame.invViewProj * float4(ndc, 1.0, 1.0);
    return normalize(w.xyz / w.w - frame.cameraPos.xyz);
}

// Cloud layer: a flat sheet at CLOUD_ALT whose density comes from 5-octave noise that drifts with the wind.
constant float CLOUD_ALT = 2500.0;

inline float cloud_fbm(float3 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        s += a * vnoise3(p);
        p = p * 2.07 + float3(5.3, 17.1, 9.7);
        a *= 0.5;
    }
    return s;       // about 0..0.97, mean about 0.48
}

// Returns density 0..1 at ground position `p` (metres, xz) at time t.
inline float cloud_density(float2 p, float t) {
    float2 q = p * 0.00022 + float2(t * 0.0035, t * 0.0012);        // wind drift
    float warp = vnoise3(float3(q * 2.3, 3.0)) - 0.5;                // warp so shapes aren't blobby
    float n = cloud_fbm(float3(q + warp * 0.35, t * 0.004));         // z drifts slowly: clouds slowly evolve
    return smoothstep(0.43, 0.66, n);                                // threshold sets coverage
}

struct SkyOut {
    float4 color [[color(0)]];
    float dist [[color(1)]];
};

fragment SkyOut sky_fragment(FullscreenOut in [[stage_in]],
                             constant FrameUniforms& frame [[buffer(1)]],
                             texture2d<float> lut [[texture(1)]]) {
    float3 dir = view_ray(in.uv, frame);
    float3 sunDir = normalize(frame.sunDir.xyz);
    // Rays below the horizon that hit nothing (past the end of the sea) should show horizon air, not the LUT's
    // "ground": clamp to just above the horizon (the LUT's horizon row blends ground in, so stay 1 deg clear).
    float3 skyDir = normalize(float3(dir.x, max(dir.y, 0.02), dir.z));
    float3 col = lut.sample(skySampler, lut_uv(skyDir), level(0)).rgb;

    // Clouds. Lit by the transmitted sun with a forward-scattering lobe (the bright "silver lining" when the
    // cloud sits near the sun), thin edges brighter than thick cores, ambient from the zenith sky.
    float cloudA = 0.0;
    float3 sunT = sun_transmittance(sunDir, LUT_CAM_HEIGHT);
    if (dir.y > 0.01) {
        float t = (CLOUD_ALT - frame.cameraPos.y) / dir.y;
        float2 p = frame.cameraPos.xz + dir.xz * t;
        float d = cloud_density(p, frame.cameraPos.w);
        float fade = smoothstep(0.02, 0.22, dir.y);                  // dissolve into the horizon haze
        cloudA = d * fade;
        float cosT = dot(dir, sunDir);
        float g = 0.65;
        float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cosT, 1.5) * 0.25;   // Henyey-Greenstein lobe
        float phase = 0.35 + 0.65 * min(hg, 4.0);
        float edge = 0.35 + 0.65 * (1.0 - d);                                        // thin edges let light through
        float3 sunlit = sunT * frame.sunColor.w / M_PI_F * 0.9 * phase * edge;
        float3 ambient = lut.sample(skySampler, float2(0.5, 0.0), level(4)).rgb * (0.9 + 0.4 * (1.0 - d));
        col = mix(col, sunlit + ambient * 0.9, cloudA);
    }

    // Sun disk: angular radius 0.00465 rad (0.2665 deg). sin(angle) via |cross| stays precise at tiny angles.
    if (dot(dir, sunDir) > 0.0) {
        float ratio = length(cross(dir, sunDir)) / 0.00465;
        float disk = 1.0 - smoothstep(0.92, 1.0, ratio);
        float mu = sqrt(max(0.0, 1.0 - ratio * ratio));
        float limb = 0.6 + 0.4 * mu;                                   // limb darkening
        col += disk * limb * 50.0 * sunT * (1.0 - cloudA);
    }
    SkyOut o;
    o.color = float4(col, 1.0);
    o.dist = 1.0e5;                  // "infinitely far" for the water pass
    return o;
}
"""#
}
