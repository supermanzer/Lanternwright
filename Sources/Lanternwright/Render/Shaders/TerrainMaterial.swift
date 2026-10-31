// G10.1.4: the ground material of the lit shader (grass, rock, sand, earth, path), split out of Lit.swift unchanged.
enum TerrainShaders {
    static let source = #"""
// Terrain material: grass (lush/parched patches), rock (steep or high, with horizontal strata),
// sand (shore, darker where wet), packed earth on the path. Also perturbs the normal for close-up detail.
float3 terrain_surface(float3 P, float3 Ng, float pathW, float wet, float duff, float palette, float fpix, float clock, float archiveFlag, float tide, thread float3& N, thread float& rough) {
    bool glass = palette > 0.5;                       // the Glass Wood: teal and violet instead of green and gold
    bool arch = archiveFlag > 0.5;                    // S04.3: the Tide Archive: wet slate, damp moss and pale dry stone (frame.worldB.z); `tide` is the sea's height (frame.worldB.y)
    float slope = Ng.y;
    float macro = fbmV(P * 0.012);                 // large patches
    // Band-limiting: `fpix` is the world size of one pixel (metres). Noise finer than a pixel aliases into hard blocks, so each
    // octave fades to its mean as its cell size approaches the pixel size, and thresholds widen by the footprint.
    float mesoW = featVis(2.5, fpix);
    float meso = mix(0.5, fbmV(P * 0.35), mesoW);          // clumps (macro: 2.5 m)
    float microW = featVis(0.11, fpix);
    float micro = microW > 0.01 ? mix(0.5, vnoise3(P * 9.0), microW) : 0.5;      // grain (about 11 cm cells)

    float dry = smoothstep(0.38, 0.62, macro + (P.y - 20.0) * 0.004);
    float3 lush = glass ? float3(0.045, 0.15, 0.18) : (arch ? float3(0.055, 0.080, 0.070) : float3(0.060, 0.165, 0.030));
    float3 parched = glass ? float3(0.16, 0.10, 0.26) : (arch ? float3(0.15, 0.165, 0.158) : float3(0.27, 0.205, 0.070));
    // Blade-scale grain (3 cm) hints at the grass from afar: as the instanced blades thin out with distance, the ground already carries their texture.
    float bladeW = featVis(0.03, fpix);
    float bladeGrain = bladeW > 0.01 ? mix(0.5, vnoise3(float3(P.x * 34.0, P.y * 6.0, P.z * 34.0)), bladeW) : 0.5;
    // Mid-scale variation (R10-2): three bands at about 2, 8 and 30 m change the grass's tone and height, and the hollows go earthy, so the meadow is patches,
    // drifts and bare ground, not one felt. (The blades use the same bands: see Grass.swift.)
    float b2 = vnoiseV(P * 0.5 + 1.7), b8 = vnoiseV(P * 0.125 + 4.1), b30 = vnoiseV(P * 0.033 + 9.3);
    float bands = 0.5 * b8 + 0.3 * b2 + 0.4 * b30;
    float hollow = smoothstep(0.38, 0.22, b8 * 0.6 + b30 * 0.4);
    float3 grass = mix(lush, parched, dry) * (0.65 + 0.7 * meso) * (0.9 + 0.2 * micro) * (0.9 + 0.2 * bladeGrain) * (0.70 + 0.65 * bands);
    grass = mix(grass, (glass ? float3(0.10, 0.08, 0.15) : (arch ? float3(0.06, 0.07, 0.07) : float3(0.17, 0.12, 0.07))) * (0.7 + 0.6 * meso), hollow * 0.55);

    // Strata are horizontal bands (noise squashed along Y). They only read as rock layers on steep faces: on flat or gently
    // rolling ground the same bands trace elevation contours (concentric rings), so there the rock is isotropic, and the bands
    // are warped by a slow horizontal noise so they never follow a height contour exactly.
    float rockMask = 1.0 - smoothstep(0.72, 0.90, slope);
    rockMask = max(rockMask, 0.65 * smoothstep(52.0, 66.0, P.y + 12.0 * (macro - 0.5)));
    // Height blending: let the layers' own grain decide where one gives way to the other, so a boundary is a crisp, ragged
    // edge (rock poking through grass) rather than a soft linear fade.
    rockMask = mix(rockMask, smoothstep(0.30, 0.70, rockMask + ((meso - 0.5) * 0.55 + (micro - 0.5) * 0.25) * min(rockMask * 4.0, 1.0)), 0.5);   // half-sharpened: grain acts only where rock is already likely
    // G10.3.5: the strata (three fractal noises) colour the rock only; where the rock mask is exactly zero (most flat ground: slope above 0.90 and below the high rock line) the rock
    // is blended in with weight 0 below, so skipping it there leaves the image byte-identical.
    float3 rock = float3(0.0);
    if (rockMask > 0.0) {
        float stratWarp = (vnoiseV(P * 0.045) - 0.5) * 5.0;
        float stratBands = fbmV(float3(P.x * 0.12, (P.y + stratWarp) * 0.55, P.z * 0.12));
        float strata = mix(fbmV(P * 0.16), stratBands, smoothstep(0.93, 0.72, slope));
        rock = mix(glass ? float3(0.10, 0.09, 0.18) : (arch ? float3(0.12, 0.14, 0.15) : float3(0.20, 0.185, 0.165)), glass ? float3(0.30, 0.26, 0.42) : (arch ? float3(0.30, 0.33, 0.34) : float3(0.40, 0.355, 0.30)), strata) * (0.85 + 0.3 * micro);
    }

    // F03 G2: the sand stays wet up to the reach of the recent swash (Shore.wetReach: it breathes with the wave groups) and dries, lighter, with height above it, instead of
    // a fixed band at one height.
    float wetReach = shore_wet_reach(P.xz, clock) * (glass ? 0.25 : 1.0);
    float wetSand = 1.0 - smoothstep(0.35 * wetReach - 0.1, wetReach + 0.1, P.y);
    if (arch) wetSand = 1.0 - smoothstep(tide - 0.05, tide + 0.55, P.y);        // the Archive's stone is wet up to the tide (and a little above it: spray), pale and dry above
    float3 sand = mix(glass ? float3(0.21, 0.24, 0.35) : (arch ? float3(0.24, 0.26, 0.255) : float3(0.56, 0.47, 0.31)), glass ? float3(0.20, 0.21, 0.32) : (arch ? float3(0.085, 0.105, 0.115) : float3(0.30, 0.235, 0.15)), wetSand) * (0.94 + 0.12 * micro) * (0.86 + 0.28 * meso) * (0.92 + 0.16 * macro);
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
    float pm = smoothstep(0.25, 0.75, pathW + (meso - 0.5) * 0.5);
    // The islet's ground (R10-5): a worn paved ring of flagstones round the pillars and the lens, with ragged edges, instead of bare turf.
    if (!glass && !arch) {
        float di = length(P.xz - float2(-40.0, -320.0)) + 1.6 * (vnoiseV(P * 0.9) - 0.5) * 2.0;
        pm = max(pm, (1.0 - smoothstep(6.0, 9.5, di)) * 0.9);
    }
    // G10.3.5: the cobbles (a Worley search) matter only where the path or the islet's paving has weight; in a quad where nobody does, they are blended in with weight 0 (and their
    // bump derivative is multiplied by 0), so skipping them is byte-identical. quad_any keeps the four pixels together so the bump's derivative stays valid at the edge of the path.
    float4 cob = float4(0.0);
    if (quad_any(pm > 0.0)) cob = cobbles(P.xz, fpix);
    float3 gapCol = (glass ? float3(0.11, 0.11, 0.19) : (arch ? float3(0.05, 0.06, 0.06) : float3(0.15, 0.11, 0.075))) * (0.8 + 0.4 * meso);
    float3 stoneA = glass ? float3(0.36, 0.40, 0.58) : (arch ? float3(0.34, 0.36, 0.36) : float3(0.40, 0.34, 0.27));
    float3 stoneB = glass ? float3(0.58, 0.52, 0.74) : (arch ? float3(0.22, 0.24, 0.25) : float3(0.30, 0.285, 0.265));
    float3 stoneCol = mix(stoneA, stoneB, cob.z) * (0.8 + 0.4 * fract(cob.z * 7.3)) * (0.9 + 0.2 * micro);
    stoneCol *= mix(0.78, 1.08, cob.x);                                      // tops catch more light, flanks sit darker
    float3 earth = mix(gapCol, stoneCol, cob.y) * (0.9 + 0.2 * meso);
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
    float damp = (1.0 - smoothstep(0.3, 2.0, P.y - (arch ? tide : 0.0))) * (1.0 - sandMask);
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
    // Sand carries a few broad, soft swells, not combed rows (F03 #33, #50): crest to crest about 2.6 m (water in a swash zone does not sort sand into fine
    // rows), bent and broken by slow noise so crests fork and fade out, strongest in the swash zone and gone by 3 m above the sea. The long wavelength and the
    // small amplitude also leave nothing to alias: the stripes seen on the Glass Wood's shelf at 50 m were 1 m ripples at full strength.
    float rippleFade = featVis(1.3, fpix) * max(sandMask, 0.0) * smoothstep(0.6, 0.95, Ng.y) * (1.0 - smoothstep(0.4, 3.0, P.y));
    if (rippleFade > 0.001) {
        float ph = dot(P.xz, float2(0.86, 0.5)) * 2.4 + (macro - 0.5) * 9.0 + (meso - 0.5) * 3.0 + (vnoiseV(P * 0.31 + 9.0) - 0.5) * 3.4;
        float patchy = smoothstep(0.30, 0.65, fbmV(P * 0.17 + 4.0));                        // crests come and go
        float crest = cos(ph) * (0.35 + 0.65 * vnoiseV(P * 0.45 + 2.0)) * patchy;           // and vary in height
        N = normalize(N + float3(0.86, 0.0, 0.5) * crest * 0.03 * rippleFade);
        albedo *= 1.0 + 0.018 * crest * rippleFade;
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
"""#
}
