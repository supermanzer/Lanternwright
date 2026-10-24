// Procedural prop materials (R03 / T57.1). Each returns albedo, roughness, metalness, a bumped normal and an ambient-occlusion
// factor from a position alone (no UVs, no textures: `Vertex` is unchanged). `Pl` is the position relative to the object's origin
// (for the lighthouse, the axis of the tower: cylindrical coordinates); `P` is the world position.
//
// Band-limiting: `fpix` is the world size of one pixel (metres). Every feature fades to its average as it nears the pixel size
// (joints at 3-15 cm per pixel, pits at 2-7 cm, ...), and thresholds widen by `fpix`, so detail resolves smoothly instead of
// crawling. We have no anti-aliasing; this is what stands in for it.
//
// Material ids (vertex normal.w): 5 masonry, 6 paint, 7 iron, 8 copper, 9 wood, 10 bark, 11 dressed stone.
enum MaterialShaders {
    static let source = #"""
struct MatOut {
    float3 albedo;
    float rough;
    float metal;
    float3 N;
    float ao;
};

// Bump mapping from a height function using screen-space derivatives (Mikkelsen): no tangents needed.
inline float3 bump_normal(float3 P, float3 N, float h, float strength) {
    float3 dpdx = dfdx(P), dpdy = dfdy(P);
    float dhx = dfdx(h), dhy = dfdy(h);
    float3 r1 = cross(dpdy, N), r2 = cross(N, dpdx);
    float det = dot(dpdx, r1);
    float3 grad = sign(det) * (dhx * r1 + dhy * r2);
    return normalize(abs(det) * N - grad * strength);
}

inline float fadeBelow(float fpix, float a, float b) { return 1.0 - smoothstep(a, b, fpix); }   // 1 while the footprint is small

// Cellular (Worley) noise, F1 distance: round, un-gridded blobs for pits and flakes. `rotated` turns the lattice by a fixed 3D
// rotation first, so no feature lines up with the world axes (value-noise thresholds make L, T and plus shapes).
inline float3 hash33w(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}
inline float worley(float3 x) {
    const float3x3 R = float3x3(float3(0.62, 0.74, -0.26), float3(-0.55, 0.63, 0.55), float3(0.56, -0.24, 0.79));
    x = R * x;
    float3 i = floor(x), f = fract(x);
    float d = 1e9;
    for (int k = 0; k < 27; k++) {
        float3 g = float3(float(k % 3) - 1.0, float((k / 3) % 3) - 1.0, float(k / 9) - 1.0);
        float3 r = g + hash33w(i + g) - f;
        d = min(d, dot(r, r));
    }
    return sqrt(d);
}
// Rounded pits: two scales (about 3x apart) so sizes vary, clustered by a slow mask, gated per block (`gate` 0..1).
inline float pits_mask(float3 Pl, float seed, float gate, float fpix) {
    float microW = fadeBelow(fpix, 0.02, 0.08);
    float w1 = worley(Pl * 26.0 + seed * 7.0), w2 = worley(Pl * 8.5 + seed * 3.0 + 40.0);
    float small = 1.0 - smoothstep(0.10, 0.24, w1);
    float large = 1.0 - smoothstep(0.07, 0.17, w2);
    float cluster = smoothstep(0.35, 0.75, fbm3(Pl * 1.3 + seed));
    return saturate(max(small * 0.8, large) * (0.25 + 0.75 * cluster)) * gate * microW;
}

// ---- Masonry: hand-cut granite blocks in running bond with lime mortar. ------------------------------------------------------
// Each course has its own height (0.26-0.46 m) and block length; each block its own tone, face undulation, chisel-edge width and
// joint width; some blocks are half-blocks, some pitted, a few stained with rust.
inline float courseEdge(float c) { return c * 0.36 + 0.020 * sin(c * 2.3 + 0.7) + 0.011 * sin(c * 5.1 + 1.9); }      // heights stay 0.26-0.46 m
inline MatOut mat_masonry(float3 Pl, float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float r = max(length(Pl.xz), 0.5);
    float ang = atan2(Pl.z, Pl.x);
    // Course: find c with edge(c) <= y < edge(c + 1).
    float yw = Pl.y + 0.012 * sin(Pl.y * 9.3);
    float c = floor(yw / 0.36);
    if (yw < courseEdge(c)) c -= 1.0; else if (yw >= courseEdge(c + 1.0)) c += 1.0;
    float y0 = courseEdge(c), y1 = courseEdge(c + 1.0);
    float courseH = y1 - y0, fv = (yw - y0) / courseH;
    float hc = hash13(float3(c, 5.0, 9.0));
    float blockLen0 = 0.92 * (0.78 + 0.44 * hc);
    float blocks = max(floor(6.2831853 * r / blockLen0), 6.0);
    float u = ang / 6.2831853 * blocks + 0.5 * fmod(abs(c), 2.0) + 0.37 * hc;
    float bi = floor(u), fu = fract(u);
    float h1 = hash13(float3(bi, c, 1.0)), h2 = hash13(float3(bi, c, 2.0)), h3 = hash13(float3(bi, c, 3.0)), h4 = hash13(float3(bi, c, 4.0));
    float blockLen = 6.2831853 * r / blocks;
    float dEdge = min(min(fu, 1.0 - fu) * blockLen, min(fv, 1.0 - fv) * courseH);
    // A half-block now and then: one extra joint down the middle.
    if (h2 > 0.88) dEdge = min(dEdge, abs(fu - 0.5) * blockLen);
    dEdge += 0.003 * (vnoise3(Pl * 18.0 + h1 * 11.0) - 0.5);                          // chiselled, wobbling edges

    float jointFade = smoothstep(0.03, 0.15, fpix);
    float mortarW = 0.009 + 0.008 * h4;
    float edge = max(0.005, fpix * 1.4);
    float mortar = (1.0 - smoothstep(mortarW - edge, mortarW + edge, dEdge)) * (1.0 - jointFade);
    float chamfer = 0.025 + 0.05 * hash13(float3(bi, c, 5.0));

    // Height (metres): convex or dished face, irregular chamfer, recessed joint, a little roughness.
    float cx = fu - 0.5, cy = fv - 0.5;
    float dish = (h3 - 0.5) * 0.045 * (1.0 - 4.0 * (cx * cx + cy * cy)) * 0.5;
    float face = 0.016 * (vnoise3(Pl * 3.2 + h1 * 30.0) - 0.5) + dish;
    float pm = pits_mask(Pl, h1 * 13.0, smoothstep(0.25, 0.85, h2 * 0.6 + h4 * 0.5), fpix);
    float h = face + (h3 - 0.5) * 0.012 + 0.007 * smoothstep(0.0, chamfer, dEdge) - 0.014 * mortar - 0.0035 * pm;
    h *= 1.0 - 0.7 * jointFade;

    float microW = fadeBelow(fpix, 0.02, 0.07);
    float speck = vnoise3(Pl * 55.0) * microW;
    // Tone: warm and cool greys, wide value range, an odd rust-stained block.
    float3 warm = float3(1.10, 1.01, 0.90), cool = float3(0.90, 0.97, 1.06);
    float3 granite = base * mix(cool, warm, h1) * (0.66 + 0.7 * h3) * (0.92 + 0.16 * speck);
    granite = mix(granite, float3(0.52, 0.36, 0.27) * (0.8 + 0.4 * h4), step(h2, 0.06) * 0.8);       // rust-stained
    granite *= 1.0 - 0.3 * pm;
    float3 limeMortar = float3(0.42, 0.39, 0.34) * (0.8 + 0.4 * vnoise3(Pl * 9.0));
    float3 albedo = mix(granite, limeMortar, mortar);
    albedo = mix(albedo, albedo * 0.9, jointFade * 0.5);

    float damp = smoothstep(0.0, 1.7, Pl.y);
    albedo *= mix(0.62, 1.0, damp);
    float streakW = fadeBelow(fpix, 0.04, 0.25);
    float streak = vnoise3(float3(ang * r * 8.0, Pl.y * 0.45, 3.0));
    albedo *= 1.0 - 0.34 * smoothstep(0.55, 0.88, streak) * streakW * smoothstep(0.5, 3.0, Pl.y);
    float zone = 1.0 - smoothstep(1.0, 3.4, Pl.y);
    float windward = saturate(dot(normalize(N.xz + float2(1e-4)), normalize(float2(-0.86, -0.5))) * 0.5 + 0.5);
    float lf = fbm3(Pl * float3(1.7, 1.1, 1.7) + 4.0) * 0.8 + 0.12 * (1.0 - smoothstep(0.1, 0.3, worley(Pl * 6.0 + 3.0))) * microW;
    float lichen = smoothstep(0.50, 0.74, lf + 0.26 * zone + 0.16 * windward - 0.36 + 0.10 * mortar);
    float3 lichenCol = mix(float3(0.36, 0.41, 0.29), float3(0.57, 0.49, 0.24), smoothstep(0.55, 0.8, vnoise3(Pl * 5.0)));
    albedo = mix(albedo, lichenCol, lichen * 0.7);

    o.albedo = albedo;
    o.rough = clamp(0.80 + 0.12 * (h1 - 0.5) + 0.12 * lichen - 0.10 * (1.0 - damp), 0.4, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, h, 1.0);
    o.ao = (1.0 - 0.55 * mortar) * (1.0 - 0.12 * pm);
    return o;
}

// ---- Dressed stone: trim blocks (arch, quoins, sills, steps, resonance stones) whose own geometry makes the joints. ----------
inline MatOut mat_dressed(float3 Pl, float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float microW = fadeBelow(fpix, 0.02, 0.07);
    float cellId = hash13(floor(P * 1.7));
    float pm = pits_mask(P, cellId * 11.0, smoothstep(0.2, 0.9, hash13(floor(P * 3.1) + 5.0)), fpix);
    float scratch = smoothstep(0.62, 0.9, vnoise3(float3(P.x * 5.0 + P.z * 3.0, P.y * 55.0, P.z * 5.0 - P.x * 3.0))) * microW;   // chisel marks, mostly horizontal
    float speck = vnoise3(P * 55.0) * microW;
    float h = 0.012 * (vnoise3(P * 3.0 + 2.0) - 0.5) - 0.0035 * pm - 0.0012 * scratch;
    float3 albedo = base * (0.84 + 0.3 * vnoise3(P * 2.3)) * (0.92 + 0.16 * speck) * (1.0 - 0.3 * pm) * (1.0 - 0.08 * scratch);
    float low = 1.0 - smoothstep(0.05, 0.9, Pl.y);
    float lichen = smoothstep(0.5, 0.74, fbm3(P * 2.1 + 1.0) * 0.85 + 0.3 * low - 0.12);
    albedo = mix(albedo, mix(float3(0.34, 0.40, 0.28), float3(0.52, 0.46, 0.24), vnoise3(P * 6.0)), lichen * 0.65 * smoothstep(1.4, 0.0, Pl.y));
    albedo *= mix(0.65, 1.0, smoothstep(0.0, 0.5, Pl.y));
    o.albedo = albedo;
    o.rough = clamp(0.82 + 0.1 * (cellId - 0.5) + 0.1 * lichen, 0.4, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, h, 1.0);
    o.ao = 1.0 - 0.1 * pm;
    return o;
}

// ---- Painted render: chalky lime-wash; the red bands fade and flake at their edges and along drips, with hairline cracks. ----
inline MatOut mat_paint(float3 Pl, float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float r = max(length(Pl.xz), 0.5);
    float ang = atan2(Pl.z, Pl.x);
    bool red = base.r - base.g > 0.15;
    float macro = fbm3(Pl * 0.9 + 3.0);
    float meso = vnoise3(Pl * 3.3);
    float3 albedo = base * (0.88 + 0.22 * macro) * (0.95 + 0.10 * meso);
    float microW = fadeBelow(fpix, 0.02, 0.09);
    float h = 0.0015 * (vnoise3(Pl * 40.0) - 0.5) * microW;

    // Where the paint has failed: near the band edges (under the string courses, at the top of a band), and along drips.
    float streak = vnoise3(float3(ang * r * 7.0, Pl.y * 0.30, 2.0));
    float dBand = 99.0;
    dBand = min(dBand, abs(Pl.y - 8.16)); dBand = min(dBand, abs(Pl.y - 13.0)); dBand = min(dBand, abs(Pl.y - 20.16)); dBand = min(dBand, abs(Pl.y - 24.6));
    float prox = exp(-dBand * 1.5);
    float flakeW = fadeBelow(fpix, 0.05, 0.3);
    float rad = clamp(0.015 + 0.34 * prox * prox + 0.09 * smoothstep(0.6, 0.9, streak) * smoothstep(0.4, 0.7, macro) + 0.03 * macro, 0.0, 0.42);
    float3 warpP = Pl + 0.16 * (float3(vnoise3(Pl * 4.3), vnoise3(Pl * 4.3 + 7.0), vnoise3(Pl * 4.3 + 13.0)) - 0.5);
    float wf = worley(warpP * float3(2.9, 2.5, 2.9) + 11.0);
    float flake = (1.0 - smoothstep(rad - 0.035, rad + 0.035, wf)) * flakeW;
    float rim = smoothstep(rad - 0.01, rad + 0.04, wf) * (1.0 - smoothstep(rad + 0.04, rad + 0.10, wf)) * flakeW;
    if (red) {
        float fade = smoothstep(0.45, 0.78, fbm3(Pl * float3(1.1, 0.7, 1.1) + 9.0));
        albedo = mix(albedo, float3(0.60, 0.27, 0.22), fade * 0.55);                  // sun-bleached toward pink
        float3 exposed = mix(float3(0.80, 0.78, 0.72), float3(0.52, 0.48, 0.43), smoothstep(0.4, 0.8, vnoise3(Pl * 14.0)));   // white primer or stone
        albedo = mix(albedo, float3(0.16, 0.07, 0.05), rim * 0.7);                    // thin dark rust rim
        albedo = mix(albedo, exposed, flake);
        h -= 0.004 * flake;
    } else {
        albedo = mix(albedo, albedo * float3(0.84, 0.82, 0.78), flake * 0.5);          // white render chips back to a greyer coat
        h -= 0.0015 * flake;
    }
    albedo *= 1.0 - 0.28 * smoothstep(0.58, 0.88, streak) * fadeBelow(fpix, 0.05, 0.3);          // drip stains
    float crackLine = 1.0 - smoothstep(0.0, 0.004 + fpix * 0.7, abs(vnoise3(Pl * float3(3.2, 2.4, 3.2) + 21.0) - 0.5));
    float crack = crackLine * smoothstep(0.45, 0.85, vnoise3(Pl * 0.8 + 5.0)) * fadeBelow(fpix, 0.006, 0.03);
    albedo *= 1.0 - 0.4 * crack;
    h -= 0.003 * crack;
    albedo *= mix(0.80, 1.0, smoothstep(0.0, 6.0, Pl.y));

    o.albedo = albedo;
    o.rough = clamp(0.88 + 0.08 * (meso - 0.5) + 0.06 * flake, 0.5, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, h, 1.0);
    o.ao = 1.0 - 0.3 * flake - 0.3 * crack;
    return o;
}

// ---- Iron: dark blue-black, rust blooming in patches and weeping streaks, a few bright worn spots. ------------------------
inline MatOut mat_iron(float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float microW = fadeBelow(fpix, 0.015, 0.06);
    float bloom = smoothstep(0.52, 0.76, fbm3(P * 3.5 + 3.0));
    float weep = smoothstep(0.62, 0.9, vnoise3(float3(P.x * 18.0 + P.z * 11.0, P.y * 1.4, P.z * 18.0 - P.x * 11.0))) * 0.7;
    float rust = saturate(bloom * 0.8 + weep * 0.6);
    float3 rustCol = float3(0.20, 0.085, 0.045) * (0.7 + 0.6 * vnoise3(P * 25.0));
    float wear = smoothstep(0.80, 0.90, vnoise3(P * 33.0)) * microW * (1.0 - rust);
    float3 albedo = mix(base, rustCol, rust);
    albedo = mix(albedo, float3(0.50, 0.50, 0.53), wear);
    o.albedo = albedo;
    o.rough = clamp(mix(0.34, 0.82, rust) + 0.1 * (vnoise3(P * 20.0) - 0.5) * microW - 0.12 * wear, 0.2, 1.0);
    o.metal = 1.0 - 0.9 * rust;
    o.N = bump_normal(P, N, 0.002 * rust * (vnoise3(P * 40.0) - 0.5) * microW, 1.0);
    o.ao = 1.0;
    return o;
}

// ---- Copper: bright copper under green verdigris, streaked down the slope. -------------------------------------------------
inline MatOut mat_copper(float3 P, float3 N, float fpix) {
    MatOut o;
    float microW = fadeBelow(fpix, 0.02, 0.08);
    float verd = smoothstep(0.26, 0.50, fbm3(P * float3(1.6, 0.9, 1.6) + 6.0) + 0.18 * (1.0 - N.y)
                            + 0.20 * smoothstep(0.55, 0.9, vnoise3(float3(P.x * 14.0 + P.z * 9.0, P.y * 0.8, P.z * 14.0 - P.x * 9.0))));
    float3 copper = float3(0.66, 0.34, 0.20) * (0.85 + 0.3 * vnoise3(P * 12.0));
    float3 patina = mix(float3(0.14, 0.34, 0.29), float3(0.30, 0.55, 0.45), vnoise3(P * 9.0));
    o.albedo = mix(copper, patina, verd);
    o.rough = clamp(mix(0.26, 0.74, verd) + 0.08 * (vnoise3(P * 22.0) - 0.5) * microW, 0.15, 1.0);
    o.metal = 1.0 - 0.9 * verd;
    o.N = bump_normal(P, N, 0.0015 * verd * (vnoise3(P * 30.0) - 0.5) * microW, 1.0);
    o.ao = 1.0;
    return o;
}

// ---- Wood: vertical planks with dark gaps, grain, weathering to silver at the edges. ---------------------------------------
inline MatOut mat_wood(float3 Pl, float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float pw = 0.22;
    float pi = floor(Pl.x / pw);
    float fu = fract(Pl.x / pw);
    float hp = hash13(float3(pi, 3.0, 1.0));
    float gapD = min(fu, 1.0 - fu) * pw;
    float gap = (1.0 - smoothstep(0.004, 0.009 + fpix * 1.5, gapD)) * fadeBelow(fpix, 0.03, 0.12);
    float grainW = fadeBelow(fpix, 0.01, 0.05);
    float grain = vnoise3(float3(Pl.x * 60.0, Pl.y * 2.6, hp * 40.0));
    float ring = 0.5 + 0.5 * sin((Pl.x / pw + hp * 7.0) * 18.0 + 3.0 * vnoise3(float3(Pl.x * 8.0, Pl.y * 1.0, hp * 9.0)));
    float3 albedo = base * (0.65 + 0.55 * hp) * (0.86 + 0.28 * mix(0.5, grain, grainW)) * (0.9 + 0.2 * mix(0.5, ring, grainW));
    albedo = mix(albedo, albedo * float3(1.25, 1.2, 1.15), smoothstep(0.7, 1.0, hp) * 0.5);
    albedo = mix(albedo, float3(0.02, 0.015, 0.01), gap);
    float damp = smoothstep(0.0, 1.2, Pl.y);
    albedo *= mix(0.7, 1.0, damp);
    float h = -0.012 * gap + 0.003 * (grain - 0.5) * grainW + 0.002 * (ring - 0.5) * grainW;
    o.albedo = albedo;
    o.rough = clamp(0.78 + 0.12 * (hp - 0.5), 0.4, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, h, 1.0);
    o.ao = 1.0 - 0.6 * gap;
    return o;
}

// ---- Bark: long vertical fissures between raised plates, moss on the north (windward) side. --------------------------------
inline MatOut mat_bark(float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float3 q = float3(P.x * 8.0 + P.z * 3.0, P.y * 1.1, P.z * 8.0 - P.x * 3.0);          // stretched along the trunk axis
    float w1 = fadeBelow(fpix, 0.03, 0.14), w2 = fadeBelow(fpix, 0.015, 0.07);
    float f1 = 1.0 - abs(2.0 * vnoise3(q) - 1.0);
    float f2 = 1.0 - abs(2.0 * vnoise3(q * float3(2.2, 1.4, 2.2) + 5.0) - 1.0);
    float ridge = mix(0.55, f1, w1) * 0.65 + mix(0.55, f2, w2) * 0.35;
    float plates = smoothstep(0.38, 0.74, ridge);
    float3 albedo = mix(base * 0.28, base * (0.8 + 0.4 * vnoise3(P * 6.0)), plates);
    float moss = smoothstep(0.45, 0.7, fbm3(P * 2.2 + 8.0)) * smoothstep(-0.1, -0.5, N.z) * plates;
    albedo = mix(albedo, float3(0.10, 0.19, 0.05) * (0.8 + 0.4 * vnoise3(P * 20.0)), moss * 0.75);
    o.albedo = albedo;
    o.rough = clamp(0.92 - 0.1 * moss, 0.6, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, 0.03 * plates + 0.012 * moss, 1.0);
    o.ao = mix(0.5, 1.0, plates);
    return o;
}

inline MatOut material_surface(int id, float3 Pl, float3 P, float3 N, float3 base, float rough, float fpix) {
    MatOut o;
    if (id == 5) o = mat_masonry(Pl, P, N, base, fpix);
    else if (id == 6) o = mat_paint(Pl, P, N, base, fpix);
    else if (id == 7) o = mat_iron(P, N, base, fpix);
    else if (id == 8) o = mat_copper(P, N, fpix);
    else if (id == 9) o = mat_wood(Pl, P, N, base, fpix);
    else if (id == 11) o = mat_dressed(Pl, P, N, base, fpix);
    else o = mat_bark(P, N, base, fpix);
    return o;
}
"""#
}
