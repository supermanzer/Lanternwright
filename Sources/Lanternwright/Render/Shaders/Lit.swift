// Main opaque surface shader. T1.3: Lambert + flat ambient. Later tasks add terrain materials,
// image-based lighting, GGX, shadows and aerial perspective.
enum LitShaders {
    static let source = #"""
// Depth-only pass from the sun's point of view.
vertex float4 shadow_vertex(uint vid [[vertex_id]],
                            device const Vertex* verts [[buffer(0)]],
                            constant FrameUniforms& frame [[buffer(1)]],
                            constant ObjectUniforms& obj [[buffer(2)]]) {
    float4 wp = obj.model * float4(verts[vid].position.xyz, 1.0);
    wp.xyz = tree_sway(wp.xyz, vertex_sway(verts[vid].position.w), frame.cameraPos.w);
    return frame.sunViewProj * wp;
}

// R09: true only in the pipeline variant that draws tree LOD objects (see ShaderLibrary.function(lodDither:)).
constant bool kLodDither [[function_constant(0)]];

struct LitOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float4 color;      // rgb albedo, a roughness
    float material;
    float stagger;     // per-tree LOD stagger (the vertex's position.w), see tree_lod_level
};

vertex LitOut lit_vertex(uint vid [[vertex_id]],
                         device const Vertex* verts [[buffer(0)]],
                         constant FrameUniforms& frame [[buffer(1)]],
                         constant ObjectUniforms& obj [[buffer(2)]]) {
    Vertex v = verts[vid];
    float3 localPos = v.position.xyz;
    if (v.normal.w > 3.5 && v.normal.w < 4.5) {
        // Birds: flap the wings. Vertices farther from the body (|x|) move more; obj.tint.w is the bird's own phase.
        float wing = abs(localPos.x);
        localPos.y += sin(frame.cameraPos.w * 9.0 + obj.tint.w) * wing * 0.32;
    }
    float4 wp = obj.model * float4(localPos, 1.0);
    wp.xyz = tree_sway(wp.xyz, vertex_sway(v.position.w), frame.cameraPos.w);
    LitOut o;
    o.position = frame.viewProj * wp;
    o.worldPos = wp.xyz;
    o.normal = (obj.model * float4(v.normal.xyz, 0.0)).xyz;   // uniform scale assumed
    o.color = float4(v.color.rgb * obj.tint.rgb, v.color.a);
    o.material = v.normal.w;
    o.stagger = vertex_stagger(v.position.w);      // tree vertices carry 3 + stagger (-1...1) + 4 * round(7 sway) in position.w; everything else has w = 1
    return o;
}

// Terrain material: grass (lush/parched patches), rock (steep or high, with horizontal strata),
// sand (shore, darker where wet), packed earth on the path. Also perturbs the normal for close-up detail.
float3 terrain_surface(float3 P, float3 Ng, float pathW, float wet, float duff, float palette, float fpix, thread float3& N, thread float& rough) {
    bool glass = palette > 0.5;                       // the Glass Wood: teal and violet instead of green and gold
    float slope = Ng.y;
    float macro = fbmV(P * 0.012);                 // large patches
    // Band-limiting: `fpix` is the world size of one pixel (metres). Noise finer than a pixel aliases into hard blocks, so each
    // octave fades to its mean as its cell size approaches the pixel size, and thresholds widen by the footprint.
    float mesoW = featVis(2.5, fpix);
    float meso = mix(0.5, fbmV(P * 0.35), mesoW);          // clumps (macro: 2.5 m)
    float microW = featVis(0.11, fpix);
    float micro = microW > 0.01 ? mix(0.5, vnoise3(P * 9.0), microW) : 0.5;      // grain (about 11 cm cells)

    float dry = smoothstep(0.38, 0.62, macro + (P.y - 20.0) * 0.004);
    float3 lush = glass ? float3(0.045, 0.15, 0.18) : float3(0.060, 0.165, 0.030);
    float3 parched = glass ? float3(0.16, 0.10, 0.26) : float3(0.27, 0.205, 0.070);
    // Blade-scale grain (3 cm) hints at the grass from afar: as the instanced blades thin out with distance, the ground already carries their texture.
    float bladeW = featVis(0.03, fpix);
    float bladeGrain = bladeW > 0.01 ? mix(0.5, vnoise3(float3(P.x * 34.0, P.y * 6.0, P.z * 34.0)), bladeW) : 0.5;
    // Mid-scale variation (R10-2): three bands at about 2, 8 and 30 m change the grass's tone and height, and the hollows go earthy, so the meadow is patches,
    // drifts and bare ground, not one felt. (The blades use the same bands: see Grass.swift.)
    float b2 = vnoiseV(P * 0.5 + 1.7), b8 = vnoiseV(P * 0.125 + 4.1), b30 = vnoiseV(P * 0.033 + 9.3);
    float bands = 0.5 * b8 + 0.3 * b2 + 0.4 * b30;
    float hollow = smoothstep(0.38, 0.22, b8 * 0.6 + b30 * 0.4);
    float3 grass = mix(lush, parched, dry) * (0.65 + 0.7 * meso) * (0.9 + 0.2 * micro) * (0.9 + 0.2 * bladeGrain) * (0.70 + 0.65 * bands);
    grass = mix(grass, (glass ? float3(0.10, 0.08, 0.15) : float3(0.17, 0.12, 0.07)) * (0.7 + 0.6 * meso), hollow * 0.55);

    // Strata are horizontal bands (noise squashed along Y). They only read as rock layers on steep faces: on flat or gently
    // rolling ground the same bands trace elevation contours (concentric rings), so there the rock is isotropic, and the bands
    // are warped by a slow horizontal noise so they never follow a height contour exactly.
    float stratWarp = (vnoiseV(P * 0.045) - 0.5) * 5.0;
    float stratBands = fbmV(float3(P.x * 0.12, (P.y + stratWarp) * 0.55, P.z * 0.12));
    float strata = mix(fbmV(P * 0.16), stratBands, smoothstep(0.93, 0.72, slope));
    float3 rock = mix(glass ? float3(0.10, 0.09, 0.18) : float3(0.20, 0.185, 0.165), glass ? float3(0.30, 0.26, 0.42) : float3(0.40, 0.355, 0.30), strata) * (0.85 + 0.3 * micro);

    float rockMask = 1.0 - smoothstep(0.72, 0.90, slope);
    rockMask = max(rockMask, 0.65 * smoothstep(52.0, 66.0, P.y + 12.0 * (macro - 0.5)));
    // Height blending: let the layers' own grain decide where one gives way to the other, so a boundary is a crisp, ragged
    // edge (rock poking through grass) rather than a soft linear fade.
    rockMask = mix(rockMask, smoothstep(0.30, 0.70, rockMask + ((meso - 0.5) * 0.55 + (micro - 0.5) * 0.25) * min(rockMask * 4.0, 1.0)), 0.5);   // half-sharpened: grain acts only where rock is already likely
    float wetSand = 1.0 - smoothstep(-0.1, 0.5, P.y);
    float3 sand = mix(glass ? float3(0.21, 0.24, 0.35) : float3(0.56, 0.47, 0.31), glass ? float3(0.20, 0.21, 0.32) : float3(0.30, 0.235, 0.15), wetSand) * (0.94 + 0.12 * micro) * (0.86 + 0.28 * meso) * (0.92 + 0.16 * macro);
    // The grass/sand boundary (F01 W0.2, note #3): a coarse mask from a warped fractal (the old threshold on 11 cm noise is what drew the pixel pattern), and
    // at close range the boundary is decided by the layers' HEIGHTS, so sand drifts into the grass and grass tufts stand in the sand along irregular lines.
    float sandCoarse = 0.0;
    if (wet > 0.05) {                                                        // dry ground (wet = 0) cannot be sand: skip the noise there
        float3 pwm = warp3(P, 0.45, 0.45);
        sandCoarse = smoothstep(0.30, 0.70, wet * (1.0 - 0.7 * rockMask) + (rfbm3(pwm * 2.6, 3) - 0.5) * 0.75 + (vnoise3(P * 9.0) - 0.5) * 0.30 * featVis(0.05, fpix));        // a ragged ecotone: tongues and islands, not a line
    }
    float sandMask = sandCoarse;
    // Ground detail (Ground.swift): soil, moss, clover and straw under the grass; grains, grit and pebbles in the sand; scree on the slopes. Each layer
    // fades to its mean colour (`grass`, `sand`, `rock` as computed above) with distance, so distant ground is unchanged.
    GroundOut gm, gs, gr;
    gm.albedo = grass; gm.h = 0.0; gm.rough = 0.95; gs.albedo = sand; gs.h = 0.0; gs.rough = 0.8; gr.albedo = rock; gr.h = 0.0; gr.rough = 0.9;
    bool hasDetail = fpix < 0.10;                                            // the layers' coarsest feature (6 cm moss clumps) is gone by ~8 cm per pixel (80 m)
    float pathProx = smoothstep(0.02, 0.4, pathW) * (1.0 - smoothstep(0.4, 0.95, pathW));
    float hDetail = 0.0;
    if (hasDetail) {
        float wMeadow = (1.0 - sandCoarse) * (1.0 - rockMask);
        float moisture = saturate(0.5 * fbmV(P * 0.045 + 3.0) + 0.45 * (1.0 - smoothstep(3.0, 24.0, P.y)) + 0.35 * pathProx - 0.05);
        if (wMeadow > 0.01) gm = ground_meadow(P, fpix, grass, moisture, glass);
        if (sandCoarse > 0.01) gs = ground_sand(P, fpix, sand, wetSand, glass ? 1.0 : 0.0);
        if (rockMask > 0.01) gr = ground_scree(P, Ng, fpix, rock);
        if (wMeadow > 0.01 && sandCoarse > 0.01) {
            float hg = saturate(gm.h * 80.0), hsd = saturate(0.35 + gs.h * 60.0);
            sandMask = mix(sandCoarse, height_blend(hg, hsd, sandCoarse, 0.2), featVis(0.02, fpix));
        }
        hDetail = mix(mix(gm.h, gr.h, rockMask), gs.h, sandMask);
    }
    float3 albedo = mix(gm.albedo, gr.albedo, rockMask);
    albedo = mix(albedo, gs.albedo, sandMask);

    // Path surface (R06): Worley cobbles, rounded pebbles of varied size with dark soil-and-sand gaps, a few large stones, a tone and
    // roughness per pebble. The dome heights feed the bump normal and darken the gaps (a little occlusion) below.
    float4 cob = cobbles(P.xz, fpix);
    float3 gapCol = (glass ? float3(0.11, 0.11, 0.19) : float3(0.15, 0.11, 0.075)) * (0.8 + 0.4 * meso);
    float3 stoneA = glass ? float3(0.36, 0.40, 0.58) : float3(0.40, 0.34, 0.27);
    float3 stoneB = glass ? float3(0.58, 0.52, 0.74) : float3(0.30, 0.285, 0.265);
    float3 stoneCol = mix(stoneA, stoneB, cob.z) * (0.8 + 0.4 * fract(cob.z * 7.3)) * (0.9 + 0.2 * micro);
    stoneCol *= mix(0.78, 1.08, cob.x);                                      // tops catch more light, flanks sit darker
    float3 earth = mix(gapCol, stoneCol, cob.y) * (0.9 + 0.2 * meso);
    float pm = smoothstep(0.25, 0.75, pathW + (meso - 0.5) * 0.5);
    // The islet's ground (R10-5): a worn paved ring of flagstones round the pillars and the lens, with ragged edges, instead of bare turf.
    if (!glass) {
        float di = length(P.xz - float2(-40.0, -320.0)) + 1.6 * (vnoiseV(P * 0.9) - 0.5) * 2.0;
        pm = max(pm, (1.0 - smoothstep(6.0, 9.5, di)) * 0.9);
    }
    albedo = mix(albedo, earth, pm);

    // Forest floor under conifers: warm brown needle litter and duff, finer-grained and darker than the meadow, with lighter fallen
    // needles lying in streaks. Band-limited like the rest.
    float duffW = duff * (1.0 - pm) * (1.0 - 0.6 * smoothstep(0.55, 0.9, rockMask));
    if (duffW > 0.002) {
        float needleW = featVis(0.022, fpix);
        float needles = mix(0.5, vnoise3(float3(P.x * 46.0 + P.z * 17.0, P.y * 3.0, P.z * 46.0 - P.x * 17.0)), needleW);
        float clumps = vnoise3(P * 7.0 + 3.0);
        float3 duffCol = mix(float3(0.25, 0.145, 0.065), float3(0.50, 0.32, 0.15), smoothstep(0.55, 0.9, needles)) * (0.72 + 0.5 * clumps);
        albedo = mix(albedo, duffCol, duffW * 0.93);
    }

    // Wet ground darkens near the waterline (spray and damp), beyond the wet sand itself.
    float damp = (1.0 - smoothstep(0.3, 2.0, P.y)) * (1.0 - sandMask);
    albedo *= mix(1.0, 0.68, damp);

    // Normal perturbation: gradient of a small bump field, projected onto the surface plane.
    float rockiness = max(rockMask, pm * 0.5);
    // One fixed scale: varying it with the rock mask made the noise coordinate (P x scale, hundreds of cells away from the origin)
    // sweep through many lattice cells inside a mask transition, which drew concentric contour rings.
    const float scale = 2.2;
    float e = 0.12;
    float3 q = P * scale;
    float bumpStrength = mix(0.006, 0.09, rockiness) * (1.0 - 0.5 * sandMask) * featVis(0.09, fpix);   // sand stays smooth: pits read as noise at a grazing sun
    float3 g = float3(0.0);
    if (bumpStrength > 0.0015) {
        float b0 = vnoiseV(q) * 0.6 + vnoiseV(q * 3.1) * 0.4;
        g = float3(vnoiseV(q + float3(e, 0, 0)) * 0.6 + vnoiseV((q + float3(e, 0, 0)) * 3.1) * 0.4 - b0,
                   vnoiseV(q + float3(0, e, 0)) * 0.6 + vnoiseV((q + float3(0, e, 0)) * 3.1) * 0.4 - b0,
                   vnoiseV(q + float3(0, 0, e)) * 0.6 + vnoiseV((q + float3(0, 0, e)) * 3.1) * 0.4 - b0) / e;
        g -= dot(g, Ng) * Ng;
    }
    N = normalize(Ng - g * bumpStrength);
    if (hasDetail) N = bump_normal(P, N, hDetail * (1.0 - smoothstep(0.25, 0.75, pathW)), 1.0);        // the layers' own relief: grit, moss, stones, grains
    N = normalize(mix(N, bump_normal(P, N, cob.x * (cob.w > 0.5 ? 0.04 : 0.022) * (cob.w > 0.5 ? featVis(0.30, fpix) : featVis(0.10, fpix)), 1.0), pm));
    // Sand and flat pale ground carry faint wind ripples (crests across the wind, bent by a slow noise) so open flats are not a
    // smooth dome. They fade with the pixel footprint so distant sand does not shimmer.
    float rippleFade = featVis(0.5, fpix) * max(sandMask, 0.0) * smoothstep(0.6, 0.95, Ng.y);
    if (rippleFade > 0.001) {
        float ph = dot(P.xz, float2(0.86, 0.5)) * 6.0 + (macro - 0.5) * 26.0 + (meso - 0.5) * 7.0;
        float crest = cos(ph);
        N = normalize(N + float3(0.86, 0.0, 0.5) * crest * 0.065 * rippleFade);
        albedo *= 1.0 + 0.035 * crest * rippleFade;
    }

    rough = mix(mix(0.92, 0.85, rockMask), mix(0.95, 0.45, wetSand), sandMask);
    rough = mix(rough, 1.0, duffW);
    if (hasDetail) rough = mix(rough, mix(mix(gm.rough, gr.rough, rockMask), gs.rough, sandMask), 0.75 * (1.0 - smoothstep(0.25, 0.75, pathW)));
    rough = mix(rough, glass ? mix(0.5, 0.78, fract(cob.z * 5.1)) : mix(0.72, 0.95, fract(cob.z * 5.1)), pm * cob.y * 0.7);   // pebbles: a faint glassy sheen in the Glass Wood
    // Gloss varies at three scales (patches, clumps, grain) so no surface has one uniform sheen; damp ground is glossier.
    rough += ((macro - 0.5) * 0.16 + (meso - 0.5) * 0.20 + (micro - 0.5) * 0.12) * 0.6;
    rough -= 0.22 * damp;
    rough += 0.22 * (1.0 - featVis(0.09, fpix)) * (1.0 - 0.7 * sandMask);        // roughness follows the bump that is no longer resolved (R09)
    rough = clamp(rough, mix(0.62, 0.28, max(damp, sandMask)), 0.98);       // dry ground never turns glossy (it would mirror the sky on flats)
    return albedo;
}

constexpr sampler shadowSampler(coord::normalized, filter::linear, address::clamp_to_border,
                                border_color::opaque_white, compare_func::less_equal);

constexpr sampler depthPoint(coord::normalized, filter::nearest, address::clamp_to_edge);

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
// leftover banding becomes fine noise. Bias: normal offset (pushes the lookup off the surface) plus a
// slope-scaled depth bias covering the whole PCF kernel (~2.5 texels of slope at a grazing sun).
float shadow_lookup(depth2d<float> tex, float4x4 vp, float texelWorld, float range,
                    float3 P, float3 N, float NoL, float2 pixel) {
    float3 Po = P + N * (texelWorld * (0.5 + 1.0 * (1.0 - NoL)));
    float4 sp = vp * float4(Po, 1.0);
    float2 uv = float2(sp.x * 0.5 + 0.5, 0.5 - sp.y * 0.5);
    if (any(uv < 0.0) || any(uv > 1.0) || sp.z > 1.0) return 1.0;
    float cosT = max(NoL, 0.05);
    float tanT = min(sqrt(1.0 - cosT * cosT) / cosT, 12.0);
    float z = sp.z - (0.0002 + 2.5 * tanT * texelWorld / range);       // world-space bias -> depth units
    // Interleaved gradient noise (Jimenez): a per-pixel rotation whose error is spread evenly across neighbouring pixels, so the
    // leftover banding becomes fine, even noise (the old sin-hash gave clumpy noise and costs a sin per pixel).
    float ang = 6.2831853 * fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
    float2x2 rot = float2x2(float2(cos(ang), sin(ang)), float2(-sin(ang), cos(ang)));
    float texel = 1.0 / float(tex.get_width());
    // PCSS contact hardening. 1) Blocker search: 8 taps in a small disc; none closer to the light = fully lit, done (also the
    // cheap path for most of the screen). 2) The sun is a disc of ~0.53 degrees, so a shadow edge widens by ~0.0093 m for every
    // metre between blocker and receiver: crisp where the shadow touches its caster, soft far from it. 3) PCF at that width.
    float blockerSum = 0.0; int blockers = 0;
    for (int i = 0; i < 8; i++) {
        float d = tex.sample(depthPoint, uv + (rot * POISSON16[i * 2]) * texel * 4.0);
        if (d < z) { blockerSum += d; blockers++; }
    }
    if (blockers == 0) return 1.0;
    float blockerDepth = blockerSum / float(blockers);
    float penumbraWorld = (z - blockerDepth) * range * 0.0093;                 // metres
    float radius = clamp(penumbraWorld / max(texelWorld, 1e-4) * 2.0, 1.2, 5.0);   // PCF radius in texels (1.2 = the old crisp edge)
    float sum = 0.0;
    for (int i = 0; i < 16; i++) {
        sum += tex.sample_compare(shadowSampler, uv + (rot * POISSON16[i]) * texel * radius, z);
    }
    return sum / 16.0;
}

// Cascaded shadow maps. Resolution is spent where the eye is: cascade 0 (a few metres around you) is razor sharp,
// cascade 1 covers the neighbourhood, cascade 2 the whole island. The cascade is picked by distance from the
// camera, with a short cross-fade so the seams don't show. `cascade` reports which one was used (debug view).
float sun_shadow(float3 P, float3 N, float NoL, float2 pixel, constant FrameUniforms& frame,
                 depth2d<float> far2, depth2d<float> near0, depth2d<float> mid1, thread int& cascade) {
    float d = length(P - frame.cameraPos.xyz);
    float r0 = frame.casRadius.x * 0.9, r1 = frame.casRadius.y * 0.9;
    float sFar = 1.0;
    if (d >= r1 * 0.85)
        sFar = shadow_lookup(far2, frame.sunViewProj, frame.casTexel.z, frame.casRange.z, P, N, NoL, pixel);
    if (d >= r1) { cascade = 2; return sFar; }
    float sMid = shadow_lookup(mid1, frame.sunViewProj1, frame.casTexel.y, frame.casRange.y, P, N, NoL, pixel);
    if (d >= r0) {
        cascade = 1;
        return mix(sMid, sFar, smoothstep(r1 * 0.85, r1, d));
    }
    float sNear = shadow_lookup(near0, frame.sunViewProj0, frame.casTexel.x, frame.casRange.x, P, N, NoL, pixel);
    cascade = 0;
    return mix(sNear, sMid, smoothstep(r0 * 0.85, r0, d));
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
                             texture2d<float> irradianceMap [[texture(4)]],
                             depth2d<float> shadowNear [[texture(6)]],
                             depth2d<float> shadowMid [[texture(7)]]) {
    if (kLodDither && tree_lod_discard(obj.lod, in.worldPos, frame.cameraPos.xyz, in.stagger, in.position.xy + frame.misc.x * float2(5.588238, 3.14159))) discard_fragment();
    float3 n = normalize(in.normal);
    float fpix = max(length(dfdx(in.worldPos)), length(dfdy(in.worldPos)));     // metres per pixel (for band-limited noise)
    float3 albedo = in.color.rgb;
    float rough = in.color.a;
    if (in.material > 0.5 && in.material < 1.5) {
        float3 Ng = n;
        albedo = terrain_surface(in.worldPos, Ng, in.color.r, in.color.g, in.color.b, frame.worldB.x, fpix, n, rough);
    }

    // Procedural prop materials (masonry, paint, iron, copper, wood, bark): albedo, roughness, metalness, bumped normal, AO.
    float metal = 0.0, matAO = 1.0;
    float3 glyphGlow = float3(0.0);
    int mid = int(in.material + 0.5);
    if (mid >= 5) {
        // Position in the object's own frame (origin and orientation of its model matrix: the lighthouse axis, the dock's length, a stone's face).
        float3x3 Rm = float3x3(obj.model.columns[0].xyz, obj.model.columns[1].xyz, obj.model.columns[2].xyz);
        float3 Pl = transpose(Rm) * (in.worldPos - obj.model.columns[3].xyz);
        MatOut mo = material_surface(mid, Pl, in.worldPos, n, albedo, rough, fpix);
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
