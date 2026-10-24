// Instanced grass. Nothing is stored per blade: each instance's position, height, colour and sway come from a hash of its
// world-space grid cell, so the field is stable (blades don't swim as you walk) and costs no memory. The vertex stage
// reads terrain height from a texture, so blades sit on the ground; the fragment stage is the ordinary lit shader.
enum GrassShaders {
    static let source = #"""
struct GrassParams {
    float4 field;      // x = cell size (m), y = cells per side, z = draw radius (m), w = unused
    float4 wind;       // xy = wind direction on the ground (unit), z = strength 0...1 at the camera (see Wind.swift)
};

inline float h11(float n) { return fract(sin(n) * 43758.5453); }
inline float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Bilinear sample of the terrain texture (x = height, y = path weight, z = landmark-pad mask), using read() so no float32
// filtering is needed.
float3 terrain_sample(texture2d<float> tex, float2 xz) {
    float g = (xz.x + 512.0) / 2.0, h = (xz.y + 512.0) / 2.0;
    g = clamp(g, 0.0, 511.0); h = clamp(h, 0.0, 511.0);
    uint x0 = uint(g), z0 = uint(h);
    float fx = g - float(x0), fz = h - float(z0);
    float3 a = tex.read(uint2(x0, z0)).rgb,     b = tex.read(uint2(x0 + 1, z0)).rgb;
    float3 c = tex.read(uint2(x0, z0 + 1)).rgb, d = tex.read(uint2(x0 + 1, z0 + 1)).rgb;
    return mix(mix(a, b, fx), mix(c, d, fx), fz);
}

vertex LitOut grass_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           constant FrameUniforms& frame [[buffer(1)]],
                           constant GrassParams& gp [[buffer(3)]],
                           texture2d<float> terrainTex [[texture(5)]]) {
    LitOut o;
    o.position = float4(0.0, 0.0, 2.0, 1.0);        // default: outside the clip volume = culled
    o.worldPos = float3(0.0); o.normal = float3(0.0, 1.0, 0.0); o.color = float4(0.0); o.material = 3.0;

    float cell = gp.field.x;
    int n = int(gp.field.y);
    int ix = int(iid) % n, iz = int(iid) / n;
    // World-snapped grid centred on the camera: the same blade always lands in the same world cell.
    int2 base = int2(floor(frame.cameraPos.xz / cell)) - int2(n / 2);
    int2 gcell = base + int2(ix, iz);
    float2 rnd = hash22(float2(gcell));
    float2 xz = (float2(gcell) + rnd) * cell;
    float dist = length(xz - frame.cameraPos.xz);
    float radius = gp.field.z;
    if (dist > radius) return o;

    float3 ts = terrain_sample(terrainTex, xz);
    float y = ts.x;
    // Normal from the height field (central differences, 2 m apart).
    float hx = terrain_sample(terrainTex, xz + float2(2.0, 0.0)).x - terrain_sample(terrainTex, xz - float2(2.0, 0.0)).x;
    float hz = terrain_sample(terrainTex, xz + float2(0.0, 2.0)).x - terrain_sample(terrainTex, xz - float2(0.0, 2.0)).x;
    float ny = 1.0 / sqrt(1.0 + (hx * hx + hz * hz) / 16.0);

    // Where does grass grow? Not on sand/beach, the path, steep rock or the bare summit.
    float density = smoothstep(2.2, 4.0, y) * (1.0 - smoothstep(0.35, 0.9, ts.y)) * (1.0 - ts.z) * smoothstep(0.80, 0.90, ny) * (1.0 - smoothstep(52.0, 64.0, y));
    // Meadow structure at three scales: ~11 m clumps (with bare patches between them), ~2 m tufts, and per-blade variance.
    float clump = fbm3(float3(xz.x, 3.0, xz.y) * 0.09);                       // 0..0.94, mean ~0.47
    float tuft = vnoise3(float3(xz.x, 9.0, xz.y) * 0.55);
    density *= mix(0.22, 1.0, smoothstep(0.30, 0.52, clump)) * (0.75 + 0.25 * tuft);
    // Thin the field with distance so far blades (sub-pixel) are not drawn at all.
    float keep = density * (1.0 - smoothstep(0.35 * radius, radius, dist) * 0.9);
    if (hash22(float2(gcell) + 17.0).x > keep) return o;

    // Blade shape: height, width, lean, facing.
    float hr = h11(rnd.x * 91.7 + rnd.y * 13.1);
    bool seedHead = h11(rnd.x * 53.3 + rnd.y * 7.7) > 0.955;                  // a few taller stems with a pale tip: meadow, not carpet
    float height = (0.22 + 0.34 * hr) * (0.62 + 0.75 * clump) * (0.85 + 0.3 * tuft) * (seedHead ? 1.9 : 1.0) * (1.0 - smoothstep(0.7 * radius, radius, dist));
    float width = 0.030 + 0.012 * rnd.y;
    float yaw = rnd.x * 6.2831853;
    float2 facing = float2(cos(yaw), sin(yaw));
    float2 side = float2(-facing.y, facing.x);

    // Local blade coordinates from the vertex id: 3 pairs of vertices going up, then the tip.
    uint row = min(vid / 2, 3u);
    float t = float(row) / 3.0;                       // 0 at the root, 1 at the tip
    float taper = (row == 0) ? 1.0 : (row == 1 ? 0.82 : (row == 2 ? 0.52 : 0.0));
    float sideSign = (vid % 2 == 0) ? -1.0 : 1.0;
    if (vid == 6) sideSign = 0.0;

    // Wind: a travelling wave plus per-blade flutter, bending the upper part more (bend ~ t^2).
    float time = frame.cameraPos.w;
    float wave = sin(dot(xz, float2(0.35, 0.21)) + time * 1.7) * 0.6 + sin(dot(xz, float2(-0.8, 0.5)) + time * 2.9 + hr * 6.0) * 0.4;
    float bend = (0.10 + 0.10 * hr) + 0.16 * wave;
    float3 wp = float3(xz.x, y, xz.y);
    wp.xz += side * sideSign * width * taper;
    wp.xz += facing * (bend * height * t * t);
    wp.xz += gp.wind.xy * (gp.wind.z * 0.30 * height * t * t);              // the blades lean along the wind, more in a gust
    wp.y += height * t - 0.4 * bend * bend * height * t * t;      // bending shortens the blade slightly

    // Colour: the terrain's lush/parched patches (same large-scale noise) with a dark root and a pale tip.
    float macro = fbm3(float3(xz.x, 0.0, xz.y) * 0.012);
    float dry = 0.7 * smoothstep(0.44, 0.72, macro + (y - 20.0) * 0.004);       // mostly lush, with parched patches
    bool glass = frame.worldB.x > 0.5;
    float3 lush = glass ? float3(0.04, 0.17, 0.20) : float3(0.060, 0.165, 0.030);
    float3 parched = glass ? float3(0.15, 0.10, 0.28) : float3(0.27, 0.205, 0.070);
    float hue = clump - 0.47;                                                  // patches lean toward one colour or the other
    float3 col = mix(lush, parched, clamp(dry + hue * 0.9, 0.0, 1.0)) * (0.75 + 0.55 * hr) * (0.55 + 0.75 * t) * (0.85 + 0.3 * tuft);
    if (seedHead) col = mix(col, glass ? float3(0.55, 0.62, 0.85) : float3(0.62, 0.55, 0.30), smoothstep(0.55, 1.0, t) * 0.8);

    o.worldPos = wp;
    o.position = frame.viewProj * float4(wp, 1.0);
    o.normal = normalize(float3(facing.x * 0.35, 1.0, facing.y * 0.35));      // soft, mostly upward: blades are thin
    o.color = float4(col, 0.9);
    o.material = 3.0;                                                          // foliage shading: wrap light + translucency
    return o;
}
"""#
}
