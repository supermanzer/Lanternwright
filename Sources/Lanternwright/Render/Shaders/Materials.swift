// Procedural prop materials (R03 / T57.1). Each returns albedo, roughness, metalness, a bumped normal and an ambient-occlusion
// factor from a position alone (no UVs, no textures: `Vertex` is unchanged). `Pl` is the position relative to the object's origin
// (for the lighthouse, the axis of the tower: cylindrical coordinates); `P` is the world position.
//
// Band-limiting: `fpix` is the world size of one pixel (metres). Every feature fades to its average as it nears the pixel size
// (joints at 3-15 cm per pixel, pits at 2-7 cm, ...), and thresholds widen by `fpix`, so detail resolves smoothly instead of
// crawling. We have no anti-aliasing; this is what stands in for it.
//
// Material ids (vertex normal.w): 5 masonry, 6 paint, 7 iron, 8 copper, 9 wood, 10 bark.
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

// ---- Masonry: rough-hewn granite blocks in running bond with recessed lime mortar. ----------------------------------------
inline MatOut mat_masonry(float3 Pl, float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float r = max(length(Pl.xz), 0.5);
    float ang = atan2(Pl.z, Pl.x);
    // Courses: heights 0.28-0.45 m (a slow warp of y), blocks about 0.9 m long, each course offset by half a block.
    float yw = Pl.y + 0.030 * sin(Pl.y * 4.1) + 0.020 * sin(Pl.y * 9.3);
    float courseH = 0.36;
    float c = floor(yw / courseH);
    float fv = fract(yw / courseH);
    float blocks = max(floor(6.2831853 * r / 0.92), 6.0);
    float u = ang / 6.2831853 * blocks + 0.5 * fmod(c, 2.0) + 0.31 * hash13(float3(c, 7.0, 1.0));
    float bi = floor(u);
    float fu = fract(u);
    float h1 = hash13(float3(bi, c, 1.0)), h2 = hash13(float3(bi, c, 2.0)), h3 = hash13(float3(bi, c, 3.0));
    float blockLen = 6.2831853 * r / blocks;
    float d = min(min(fu, 1.0 - fu) * blockLen, min(fv, 1.0 - fv) * courseH);      // metres to the nearest joint

    float jointFade = smoothstep(0.03, 0.15, fpix);                                  // joints vanish into an average tone
    float edge = max(0.005, fpix * 1.4);
    float mortar = (1.0 - smoothstep(0.013 - edge, 0.013 + edge, d)) * (1.0 - jointFade);
    float microW = fadeBelow(fpix, 0.02, 0.07);
    float pits = smoothstep(0.74, 0.88, vnoise3(Pl * 38.0 + 7.0)) * microW;
    float speck = vnoise3(Pl * 55.0) * microW;

    // Height (metres): domed faces, recessed joints, per-block offset, pits.
    float h = (h3 - 0.5) * 0.016 + 0.007 * smoothstep(0.0, 0.07, d) - 0.014 * mortar - 0.003 * pits;
    h *= 1.0 - 0.7 * jointFade;

    float3 granite = base * (0.78 + 0.44 * h1) * (0.92 + 0.16 * speck);
    granite = mix(granite, granite * float3(1.08, 0.97, 0.92), step(0.7, h2));       // a few warmer blocks
    float3 limeMortar = float3(0.40, 0.37, 0.32) * (0.8 + 0.4 * vnoise3(Pl * 9.0));
    float3 albedo = mix(granite, limeMortar, mortar);
    albedo = mix(albedo, albedo * 0.9, jointFade * 0.5);

    // Weathering: damp base, rain streaks, lichen (splash zone, windward and shaded faces, thicker in the joints).
    float damp = smoothstep(0.0, 1.7, Pl.y);
    albedo *= mix(0.60, 1.0, damp);
    float streakW = fadeBelow(fpix, 0.04, 0.25);
    float streak = vnoise3(float3(ang * r * 8.0, Pl.y * 0.45, 3.0));
    albedo *= 1.0 - 0.38 * smoothstep(0.55, 0.85, streak) * streakW * smoothstep(0.5, 3.0, Pl.y);
    float zone = 1.0 - smoothstep(1.0, 3.4, Pl.y);
    float windward = saturate(dot(normalize(N.xz + float2(1e-4)), normalize(float2(-0.86, -0.5))) * 0.5 + 0.5);
    float lf = fbm3(Pl * float3(1.7, 1.1, 1.7) + 4.0) * 0.8 + 0.12 * vnoise3(Pl * 9.0) * microW;
    float lichen = smoothstep(0.50, 0.72, lf + 0.26 * zone + 0.16 * windward - 0.36 + 0.10 * mortar);
    float3 lichenCol = mix(float3(0.34, 0.40, 0.27), float3(0.55, 0.47, 0.22), smoothstep(0.55, 0.8, vnoise3(Pl * 5.0)));
    albedo = mix(albedo, lichenCol, lichen * 0.7);

    o.albedo = albedo;
    o.rough = clamp(0.80 + 0.12 * (h1 - 0.5) + 0.12 * lichen - 0.10 * (1.0 - damp), 0.4, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, h, 1.0);
    o.ao = (1.0 - 0.55 * mortar) * (1.0 - 0.12 * pits);
    return o;
}

// ---- Painted render: chalky lime-wash, red bands fading and flaking to the stone, drips and hairline cracks. -------------
inline MatOut mat_paint(float3 Pl, float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float r = max(length(Pl.xz), 0.5);
    float ang = atan2(Pl.z, Pl.x);
    bool red = base.r - base.g > 0.15;
    float macro = fbm3(Pl * 0.9 + 3.0);
    float meso = vnoise3(Pl * 3.3);
    float3 albedo = base * (0.86 + 0.24 * macro) * (0.94 + 0.12 * meso);
    float microW = fadeBelow(fpix, 0.02, 0.09);

    float h = 0.002 * (vnoise3(Pl * 40.0) - 0.5) * microW;
    float flake = 0.0;
    if (red) {
        float fade = smoothstep(0.45, 0.78, fbm3(Pl * float3(1.1, 0.7, 1.1) + 9.0));
        albedo = mix(albedo, float3(0.60, 0.27, 0.22), fade * 0.65);                  // sun-bleached toward pink
        float fw = 0.012 + fpix * 1.5;
        flake = smoothstep(0.76 - fw, 0.76 + fw, vnoise3(Pl * float3(2.6, 2.0, 2.6) + 11.0)) * (1.0 - smoothstep(0.1, 0.4, fpix) * 0.5);
        albedo = mix(albedo, float3(0.52, 0.48, 0.43) * (0.8 + 0.4 * vnoise3(Pl * 14.0)), flake);   // render gone, stone showing
        h -= 0.004 * flake;
    }
    // Drip stains and weeping streaks (vertical), darker below the bands.
    float streak = vnoise3(float3(ang * r * 7.0, Pl.y * 0.30, 2.0));
    albedo *= 1.0 - 0.30 * smoothstep(0.58, 0.86, streak) * fadeBelow(fpix, 0.05, 0.3);
    // Hairline cracks: thin ridged lines, only in patches.
    float crackLine = 1.0 - smoothstep(0.0, 0.004 + fpix * 0.7, abs(vnoise3(Pl * float3(3.2, 2.4, 3.2) + 21.0) - 0.5));
    float crack = crackLine * smoothstep(0.50, 0.70, vnoise3(Pl * 0.8 + 5.0)) * fadeBelow(fpix, 0.006, 0.03);
    albedo *= 1.0 - 0.4 * crack;
    h -= 0.003 * crack;
    // Damp and salt toward the ground, a little lichen creeping up.
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
    else o = mat_bark(P, N, base, fpix);
    return o;
}
"""#
}
