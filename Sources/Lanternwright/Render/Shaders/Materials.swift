// Procedural prop materials (R03 / T57.1). Each returns albedo, roughness, metalness, a bumped normal and an ambient-occlusion
// factor from a position alone (no UVs, no textures: `Vertex` is unchanged). `Pl` is the position relative to the object's origin
// (for the lighthouse, the axis of the tower: cylindrical coordinates); `P` is the world position.
//
// Band-limiting: `fpix` is the world size of one pixel (metres). Every feature fades to its average as it nears the pixel size
// (joints at 3-15 cm per pixel, pits at 2-7 cm, ...), and thresholds widen by `fpix`, so detail resolves smoothly instead of
// crawling. We have no anti-aliasing; this is what stands in for it.
//
// Material ids (vertex normal.w): 5 masonry, 6 paint, 7 iron, 8 copper, 9 wood, 10 bark, 11 dressed stone, 12 deck plank, 13 timber, 14 carved glyph stone (dressed + carve_glyph), 15 paper, 16 pebble (dressed, no object emissive), 17 glass stone, 18 mirror, 19 pale metal, 20 carved glyph on glass stone.
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

// Continuous detail (R09): one visibility rule for every feature, from the feature's size over the pixel footprint (size / fpix = how many
// pixels it spans). Below ~0.6 px it is invisible, above ~2.5 px fully resolved, smooth in between, so every feature is *hinted* from
// about 1.7 x its size per pixel and sharp from 0.4 x. That puts macro features (courses, plank joints, colour patches: 0.2-1 m) in view
// at 100-400 m, meso (cobbles, pits, board grain: 5-15 cm) at 20-130 m, micro (fibres, sparkle, fine grain: 0.5-3 cm) at 3-30 m, with no
// per-feature magic numbers: it also follows the field of view, the render scale and look-closer. Every feature must fade TO ITS MEAN
// (mix(mean, value, vis)), never to zero, or the surface changes brightness where the detail goes.
inline float featVis(float size, float fpix) { return smoothstep(0.6, 2.5, size / max(fpix, 1e-5)); }
// A line or groove of width w seen with a footprint f: when it is narrower than the pixel its darkness is spread over the pixel, so its
// contrast falls as w / f and its average stays the same (energy preserved). Multiply a line's coverage by this.
inline float lineAmp(float w, float edge) { return saturate(w / max(edge, w)); }

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
// Worley with F1, F2 and the nearest cell's id (3D, rotated lattice): x = F1, y = F2, z = id 0..1. The crevice distance F2 - F1 makes angular plates.
inline float3 worley3F(float3 x) {
    const float3x3 R = float3x3(float3(0.62, 0.74, -0.26), float3(-0.55, 0.63, 0.55), float3(0.56, -0.24, 0.79));
    x = R * x;
    float3 i = floor(x), f = fract(x);
    float d1 = 1e9, d2 = 1e9, id = 0.0;
    for (int k = 0; k < 27; k++) {
        float3 g = float3(float(k % 3) - 1.0, float((k / 3) % 3) - 1.0, float(k / 9) - 1.0);
        float3 h = hash33w(i + g);
        float3 r = g + h - f;
        float d = dot(r, r);
        if (d < d1) { d2 = d1; d1 = d; id = h.x; } else if (d < d2) { d2 = d; }
    }
    return float3(sqrt(d1), sqrt(d2), id);
}
// Cobbles (R06): a 2D cellular pattern of rounded pebbles with dark gaps. Two scales (cells of about 12 cm and 36 cm); a third of the
// large cells become stones that replace the small pebbles beneath them. x = dome height 0..1 (0 in the gaps), y = body mask
// (1 on a pebble, 0 in a gap), z = per-pebble hash, w = 1 on a large stone. Band-limited by `fpix` to its mean.
inline float2 hash22w(float2 p) {
    float3 q = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.xx + q.yz) * q.zy);
}
inline float4 cobble_cell(float2 p, float seed) {
    float2 i = floor(p), f = fract(p);
    float d1 = 1e9, d2 = 1e9;
    float2 id1 = float2(0.0);
    for (int k = 0; k < 9; k++) {
        float2 g = float2(float(k % 3) - 1.0, float(k / 3) - 1.0);
        float2 o = hash22w(i + g + seed);
        float2 r = g + 0.15 + 0.7 * o - f;                       // jitter kept off the cell edge so pebbles stay round
        float d = dot(r, r);
        if (d < d1) { d2 = d1; d1 = d; id1 = i + g + seed; }
        else if (d < d2) { d2 = d; }
    }
    float bd = 0.5 * (sqrt(d2) - sqrt(d1));                       // distance to the nearest border (approximately)
    float hid = hash22w(id1 + 17.0).x;
    return float4(bd, hid, hash22w(id1 + 3.0).y, 0.0);
}
inline float4 cobbles(float2 P, float fpix) {
    const float2x2 R = float2x2(float2(0.82, 0.57), float2(-0.57, 0.82));
    float2 p = R * (P + 0.035 * float2(vnoise3(float3(P * 7.0, 1.0)) - 0.5, vnoise3(float3(P * 7.0, 5.0)) - 0.5) * 2.0);   // wobble the outlines: no straight facets
    float4 a = cobble_cell(p * 8.5, 0.0);                        // pebbles, 12 cm
    float4 b = cobble_cell(p * 2.9 + 40.0, 11.0);                // stones, 35 cm
    bool big = b.y > 0.70;
    float bdA = a.x / 8.5, bdB = b.x / 2.9;                      // borders in metres
    float bd = big ? bdB : bdA;
    float rad = big ? 0.045 : 0.03;                              // how far in from the border the dome reaches full height
    float gap = big ? 0.012 : 0.008;
    float soft = 0.004 + fpix * 0.8;
    float body = smoothstep(gap - soft, gap + soft, bd);
    float tt = saturate((bd - gap) / rad);
    float dome = (1.0 - (1.0 - tt) * (1.0 - tt)) * (0.55 + 0.45 * (big ? b.z : a.z));      // round shoulder, flat crown (no crease along the medial axis)
    dome = saturate(dome) * (big ? 1.0 : 0.8);
    float w = big ? featVis(0.30, fpix) : featVis(0.10, fpix);                 // stones 30 cm, pebbles 10 cm
    float hid = big ? b.z : a.z;
    return float4(mix(0.45, dome, w), mix(0.82, body, w), hid, big ? 1.0 : 0.0);
}

// ---- Carved glyphs (R06): the resonance stones' symbols are cut into the face (material 14). Signed-distance shapes in the stone's own
// frame; the groove is 2 cm deep with a bevelled edge, the emissive sits on its floor and is found with a one-step parallax, so the
// stone edge hides it at an angle. A lit rim runs round the bevel and a soft halo spills onto the stone (a fake local light).
// obj.tint.w encodes the glyph: integer part = kind (0 tide, 1 wind, 2 summit), fraction = (scale - 1) / 2 (murals draw it 1.9x);
// obj.emissive = glow colour and strength.
inline float sd_box(float2 p, float2 h) { float2 d = abs(p) - h; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
inline float sd_rbox(float2 p, float2 h, float r) { return sd_box(p, h - r) - r; }
inline float2 rot2(float2 p, float a) { float c = cos(a), s = sin(a); return float2(c * p.x - s * p.y, s * p.x + c * p.y); }
inline float glyph_sdf(int kind, float2 q) {
    if (kind == 0) {
        float d = sd_rbox(q - float2(-0.07, 0.24), float2(0.31, 0.035), 0.02);
        d = min(d, sd_rbox(q - float2(0.07, 0.0), float2(0.31, 0.035), 0.02));
        return min(d, sd_rbox(q - float2(-0.07, -0.24), float2(0.31, 0.035), 0.02));
    }
    if (kind == 1) {
        float d = sd_rbox(rot2(q - float2(-0.17, 0.0), -0.6), float2(0.035, 0.36), 0.02);
        return min(d, sd_rbox(rot2(q - float2(0.17, 0.0), -0.6), float2(0.035, 0.36), 0.02));
    }
    return sd_rbox(q, float2(0.24), 0.03);
}
// Returns the glow (added to the colour); changes albedo, roughness and the normal in place.
inline float3 carve_glyph(float3 Pl, float3 P, float3 faceN, float3 Vl, float4 tint, float4 em, thread float3& albedo, thread float& rough, thread float3& N) {
    int kind = int(floor(tint.w + 0.01));
    float scale = 1.0 + (tint.w - float(kind)) * 2.0;
    float y0 = scale > 1.2 ? 1.7 : 1.55;
    const float depth = 0.020;
    float face = smoothstep(0.85, 0.95, faceN.z);                          // only the flat front, never the sides
    if (face < 0.01) return float3(0.0);
    float2 q0 = (Pl.xy - float2(0.0, y0)) / scale;
    float d0 = glyph_sdf(kind, q0) * scale;
    float2 q1 = (Pl.xy - Vl.xy / max(Vl.z, 0.2) * depth - float2(0.0, y0)) / scale;     // where the sight line meets the floor
    float d1 = glyph_sdf(kind, q1) * scale;
    float strength = em.w;
    float3 col = em.rgb;
    float aa = max(length(dfdx(P)), length(dfdy(P)));
    float inside = 1.0 - smoothstep(-aa, aa, d0);
    float bevel = smoothstep(-0.013, 0.0, d0) * inside;                     // 1 at the lip, 0 in the flat floor
    float h = -depth * (1.0 - bevel) * inside;
    N = normalize(mix(N, bump_normal(P, N, h, 1.0), face));
    float floorSeen = inside * (1.0 - smoothstep(-0.002 - aa, 0.001 + aa, d1));
    float3 glow = col * strength * floorSeen * 0.9;                         // the lit floor of the channel
    float rim = inside * smoothstep(-0.016, -0.004, d0) * (1.0 - smoothstep(-0.004, 0.0, d0));
    glow += col * min(strength, 3.0) * rim * 0.6;                           // thin lit rim on the bevel
    float halo = exp(-max(d0, 0.0) / (0.05 * max(scale, 1.0))) * (1.0 - inside);
    glow += col * albedo * 4.0 * min(strength, 3.0) * halo * 0.22;          // soft halo: light falling on the stone around it
    albedo *= mix(1.0, 0.35, inside * (1.0 - floorSeen));                   // a groove wall in shade
    rough = mix(rough, 0.45, inside);
    // The rank marks (1 to 3 notches low on the arrival face: how near the sky this stone stands): carved, with a faint glint.
    if (scale < 1.2) {
        int rank = kind + 1;
        float nd = 1e9;
        for (int i = 0; i < 3; i++) if (i < rank) nd = min(nd, sd_rbox(Pl.xy - float2((float(i) - float(rank - 1) * 0.5) * 0.17, 0.62), float2(0.035, 0.15), 0.02));
        float nin = 1.0 - smoothstep(-aa, aa, nd);
        float nb = smoothstep(-0.01, 0.0, nd);
        N = normalize(mix(N, bump_normal(P, N, -0.014 * (1.0 - nb) * nin, 1.0), face));
        albedo *= mix(1.0, 0.4, nin);
        glow += col * min(strength, 2.0) * nin * 0.12;
    }
    return glow * face;
}

// ---- Journal paper (R06): warm, foxed at the edges, with fibre grain, a crease and rows of hand-written-looking sepia strokes. The page is
// a sheet about 0.34 x 0.46 m; Pl is its own frame (x across, z down the sheet). Ink is band-limited to a faint average density.
inline MatOut mat_paper(float3 Pl, float3 P, float3 N, float fpix) {
    MatOut o;
    float fibreW = featVis(0.0045, fpix);
    float fibre = mix(0.5, vnoise3(float3(Pl.x * 220.0, Pl.y * 3.0, Pl.z * 60.0)) * 0.6 + vnoise3(float3(Pl.x * 60.0, 0.0, Pl.z * 190.0)) * 0.4, fibreW);
    float3 paper = float3(0.80, 0.70, 0.50) * (0.92 + 0.16 * fibre);
    float2 e = float2(0.17 - abs(Pl.x), 0.23 - abs(Pl.z));
    float edge = min(e.x, e.y);
    float fox = fbm3(float3(Pl.x * 14.0, 0.0, Pl.z * 14.0) + 5.0);
    paper *= 1.0 - 0.30 * smoothstep(0.045, 0.0, edge) - 0.16 * smoothstep(0.5, 0.8, fox);
    paper = mix(paper, paper * float3(0.85, 0.72, 0.5), smoothstep(0.03, 0.0, edge) * 0.5);        // browned rim
    // Ink rows
    const float rowH = 0.0245;
    float zr = (Pl.z + 0.205) / rowH;
    float r = floor(zr);
    float hr = hash13(float3(r, 3.0, 9.0)), hr2 = hash13(float3(r, 8.0, 2.0));
    float wob = (vnoise3(float3(Pl.x * 26.0, r, 5.0)) - 0.5) * 0.0016;
    float dz = (fract(zr) - 0.38) * rowH + wob;
    float xEnd = 0.135 - 0.11 * step(0.72, hr2) * hr;                      // short last lines of paragraphs
    bool inBlock = abs(Pl.x + 0.0) < 0.135 && Pl.x < xEnd && Pl.z > -0.205 && Pl.z < 0.19 && hr < 0.93;
    float words = smoothstep(0.30, 0.38, vnoise3(float3(Pl.x * 24.0 + r * 5.3, r, 3.0)));
    float letters = 0.55 + 0.45 * vnoise3(float3(Pl.x * 330.0 + r * 11.0, r, 1.0));
    float thick = 0.00115 * (0.7 + 0.6 * vnoise3(float3(Pl.x * 90.0, r, 2.0)));
    float stroke = (1.0 - smoothstep(thick * 0.6, thick * 1.3 + fpix, abs(dz))) * words * letters * (inBlock ? 1.0 : 0.0);
    float inkW = featVis(0.003, fpix);
    float cover = mix((inBlock ? 0.22 : 0.0) * words, stroke, inkW);
    float3 ink = float3(0.18, 0.10, 0.045);
    float3 albedo = mix(paper, ink, saturate(cover) * 0.9);
    // The crease: a dark hairline with a pale shoulder either side.
    float cz = Pl.z - 0.03;
    albedo *= 1.0 - 0.28 * exp(-cz * cz / (2.0 * 0.0035 * 0.0035)) + 0.04 * exp(-cz * cz / (2.0 * 0.02 * 0.02));
    o.albedo = albedo;
    o.rough = 0.92;
    o.metal = 0.0;
    o.N = bump_normal(P, N, 0.0004 * (fibre - 0.5) - 0.0003 * cover, 1.0);
    o.ao = mix(0.75, 1.0, smoothstep(0.0, 0.05, edge));
    return o;
}

// Rounded pits: two scales (about 3x apart) so sizes vary, clustered by a slow mask, gated per block (`gate` 0..1).
inline float pits_mask(float3 Pl, float seed, float gate, float fpix) {
    float vs = featVis(0.04, fpix), vl = featVis(0.12, fpix);                 // small pits 4 cm, large pits 12 cm
    float w1 = worley(Pl * 26.0 + seed * 7.0), w2 = worley(Pl * 8.5 + seed * 3.0 + 40.0);
    float small = mix(0.12, 1.0 - smoothstep(0.10, 0.24, w1), vs);              // each fades to its mean coverage, not to zero
    float large = mix(0.07, 1.0 - smoothstep(0.07, 0.17, w2), vl);
    float cluster = smoothstep(0.35, 0.75, fbm3(Pl * 1.3 + seed));
    return saturate(max(small * 0.8, large) * (0.25 + 0.75 * cluster)) * gate;
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

    float mortarW = 0.009 + 0.008 * h4;
    float edge = max(0.005, fpix * 0.9);
    // Joints are macro structure: they stay (faintly) at any distance. A joint narrower than a pixel keeps its average darkness (lineAmp).
    float mortar = (1.0 - smoothstep(mortarW - edge, mortarW + edge, dEdge)) * lineAmp(mortarW, edge);
    float chamfer = 0.025 + 0.05 * hash13(float3(bi, c, 5.0));

    // Height (metres): convex or dished face, irregular chamfer, recessed joint, a little roughness.
    float cx = fu - 0.5, cy = fv - 0.5;
    float dish = (h3 - 0.5) * 0.045 * (1.0 - 4.0 * (cx * cx + cy * cy)) * 0.5;
    float face = 0.016 * (vnoise3(Pl * 3.2 + h1 * 30.0) - 0.5) + dish;
    float pm = pits_mask(Pl, h1 * 13.0, smoothstep(0.25, 0.85, h2 * 0.6 + h4 * 0.5), fpix);
    float h = face + (h3 - 0.5) * 0.012 + 0.007 * smoothstep(0.0, chamfer, dEdge) - 0.014 * mortar - 0.0035 * pm;
    h *= mix(0.3, 1.0, featVis(0.10, fpix));                                           // the relief fades; roughness takes over (see material_surface)

    float speck = mix(0.5, vnoise3(Pl * 55.0), featVis(0.018, fpix));
    // Tone: warm and cool greys, wide value range, an odd rust-stained block. Per-block tone is a 0.3-0.9 m feature: hinted from afar.
    float3 warm = float3(1.10, 1.01, 0.90), cool = float3(0.90, 0.97, 1.06);
    float3 blockTone = mix(float3(1.0), mix(cool, warm, h1) * (0.66 + 0.7 * h3), featVis(0.30, fpix));
    float3 granite = base * blockTone * (0.92 + 0.16 * speck);
    granite = mix(granite, float3(0.52, 0.36, 0.27) * (0.8 + 0.4 * h4), step(h2, 0.06) * 0.8);       // rust-stained
    granite *= 1.0 - 0.3 * pm;
    float3 limeMortar = float3(0.42, 0.39, 0.34) * (0.8 + 0.4 * vnoise3(Pl * 9.0));
    float3 albedo = mix(granite, limeMortar, mortar);

    float damp = smoothstep(0.0, 1.7, Pl.y);
    albedo *= mix(0.62, 1.0, damp);
    float streak = vnoise3(float3(ang * r * 8.0, Pl.y * 0.45, 3.0));
    albedo *= 1.0 - 0.34 * mix(0.12, smoothstep(0.55, 0.88, streak), featVis(0.25, fpix)) * smoothstep(0.5, 3.0, Pl.y);      // drip stains: 0.25 m wide
    float zone = 1.0 - smoothstep(1.0, 3.4, Pl.y);
    float windward = saturate(dot(normalize(N.xz + float2(1e-4)), normalize(float2(-0.86, -0.5))) * 0.5 + 0.5);
    float lf = fbm3(Pl * float3(1.7, 1.1, 1.7) + 4.0) * 0.8 + 0.12 * (1.0 - smoothstep(0.1, 0.3, worley(Pl * 6.0 + 3.0))) * featVis(0.08, fpix);
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
    float cellId = hash13(floor(P * 1.7));
    float pm = pits_mask(P, cellId * 11.0, smoothstep(0.2, 0.9, hash13(floor(P * 3.1) + 5.0)), fpix);
    float scratch = mix(0.08, smoothstep(0.62, 0.9, vnoise3(float3(P.x * 5.0 + P.z * 3.0, P.y * 55.0, P.z * 5.0 - P.x * 3.0))), featVis(0.018, fpix));   // chisel marks, mostly horizontal
    float speck = mix(0.5, vnoise3(P * 55.0), featVis(0.018, fpix));
    float h = 0.012 * (vnoise3(P * 3.0 + 2.0) - 0.5) - 0.0035 * pm - 0.0012 * scratch;
    float3 albedo = base * (0.84 + 0.3 * vnoise3(P * 2.3)) * (0.92 + 0.16 * speck) * (1.0 - 0.3 * pm) * (1.0 - 0.08 * scratch);
    float low = 1.0 - smoothstep(0.05, 0.9, Pl.y);
    float lichen = smoothstep(0.38, 0.62, fbm3(P * 2.1 + 1.0) * 0.85 + 0.55 * low - 0.12);
    albedo = mix(albedo, mix(float3(0.34, 0.40, 0.28), float3(0.52, 0.46, 0.24), vnoise3(P * 6.0)), lichen * 0.85 * smoothstep(1.6, 0.0, Pl.y));
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
    float h = 0.0015 * (vnoise3(Pl * 40.0) - 0.5) * featVis(0.025, fpix);

    // Where the paint has failed: near the band edges (under the string courses, at the top of a band), and along drips.
    float streak = vnoise3(float3(ang * r * 7.0, Pl.y * 0.30, 2.0));
    float dBand = 99.0;
    dBand = min(dBand, abs(Pl.y - 8.16)); dBand = min(dBand, abs(Pl.y - 13.0)); dBand = min(dBand, abs(Pl.y - 20.16)); dBand = min(dBand, abs(Pl.y - 24.6));
    float prox = exp(-dBand * 1.5);
    float flakeW = featVis(0.30, fpix);                                       // flake cells are ~0.34 m: macro, hinted from far away
    float rad = clamp(0.015 + 0.34 * prox * prox + 0.09 * smoothstep(0.6, 0.9, streak) * smoothstep(0.4, 0.7, macro) + 0.03 * macro, 0.0, 0.42);
    float3 warpP = Pl + 0.16 * (float3(vnoise3(Pl * 4.3), vnoise3(Pl * 4.3 + 7.0), vnoise3(Pl * 4.3 + 13.0)) - 0.5);
    float wf = worley(warpP * float3(2.9, 2.5, 2.9) + 11.0);
    // Faded to its mean coverage (Poisson: 1 - exp(-4/3 pi r^3) of the cell), so the band keeps its average colour.
    float flake = mix(1.0 - exp(-4.19 * rad * rad * rad), 1.0 - smoothstep(rad - 0.035, rad + 0.035, wf), flakeW);
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
    albedo *= 1.0 - 0.28 * mix(0.10, smoothstep(0.58, 0.88, streak), featVis(0.20, fpix));          // drip stains
    // Hairline cracks: the iso-line of a noise stretched hard along Y, so they run mostly down the wall (an unstretched iso-line closes into rings).
    float crackLine = 1.0 - smoothstep(0.0, 0.004 + fpix * 0.7, abs(vnoise3(Pl * float3(3.2, 0.35, 3.2) + 21.0) - 0.5));
    float crack = crackLine * smoothstep(0.45, 0.85, vnoise3(Pl * 0.8 + 5.0)) * featVis(0.012, fpix);
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
    float microW = featVis(0.03, fpix);
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
    float microW = featVis(0.045, fpix);
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
    float gapEdge = 0.009 + fpix * 0.9;
    float gap = (1.0 - smoothstep(0.004, gapEdge, gapD)) * lineAmp(0.007, gapEdge);        // plank joints are macro: hinted from afar, energy kept
    float grainW = featVis(0.02, fpix);
    float grain = vnoise3(float3(Pl.x * 60.0, Pl.y * 2.6, hp * 40.0));
    float ring = 0.5 + 0.5 * sin((Pl.x / pw + hp * 7.0) * 18.0 + 3.0 * vnoise3(float3(Pl.x * 8.0, Pl.y * 1.0, hp * 9.0)));
    float3 albedo = base * mix(1.0, 0.65 + 0.55 * hp, featVis(0.22, fpix)) * (0.86 + 0.28 * mix(0.5, grain, grainW)) * (0.9 + 0.2 * mix(0.5, ring, grainW));
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
    float w1 = featVis(0.12, fpix), w2 = featVis(0.05, fpix);
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

// 2D cellular noise with the vector to the nearest feature point: xy = from that point to p (cell units), z = distance F1, w = cell id 0..1.
inline float4 cell2n(float2 p) {
    float2 i = floor(p), f = fract(p);
    float d1 = 1e9; float2 v = float2(0.0); float id = 0.0;
    for (int k = 0; k < 9; k++) {
        float2 g = float2(float(k % 3) - 1.0, float(k / 3) - 1.0);
        float2 h2 = hash22w(i + g + 31.0);
        float2 r = g + 0.15 + 0.7 * h2 - f;
        float d = dot(r, r);
        if (d < d1) { d1 = d; v = -r; id = h2.x; }
    }
    return float4(v, sqrt(d1), id);
}

// ---- Deck planks (F01 W2): weathered deck boards. `seed` (0..1, the vertex roughness channel; exactly 1 = a replacement board) selects the board's own tone,
// grain, knots and checks. Grain is a GROWTH-RING model: distance from a virtual trunk axis below the board, domain-warped, with cathedral figures, knots that
// swirl the rings round them, long checks opening toward the ends; silvered grey on top, dark and mossy low and wet, salt crust, rust streaks under nail heads,
// a worn walking line down the middle. Board axis is local x; the dock runs along local z (Pl is the dock's own frame).
inline MatOut mat_plank(float3 Pl, float3 P, float3 N, float3 base, float seed, float fpix) {
    MatOut o;
    bool fresh = seed > 0.995;
    float hp = fract(seed * 7.13), hq = fract(seed * 13.7 + 0.3);
    float vGrain = featVis(0.02, fpix), vFib = featVis(0.004, fpix), vKnot = featVis(0.08, fpix);
    // The board-local cross coordinate: boards are ~0.2 m deep; use the position within the dock plus the seed to decorrelate neighbours.
    float zz = Pl.z * 3.7 + seed * 41.0;
    // Growth rings: distance from a trunk axis 0.35 m below the board, bent by a slow warp, so rings run along the board as cathedral arches.
    float2 q = float2(Pl.x * 1.3 + hp * 9.0, zz);
    float warpA = 0.9 * (vnoise3(float3(q * 0.6, seed * 5.0)) - 0.5);
    float ringPos = (zz * 0.42 + warpA + 0.35 * sin(Pl.x * 2.1 + hp * 6.0)) * 22.0 + hq * 9.0;
    // Knots: a few per board; the rings swirl round them.
    float4 kc = cell2n(float2(Pl.x * 2.2 + seed * 17.0, zz * 0.9));
    float knot = (1.0 - smoothstep(0.04, 0.15, kc.z)) * step(0.80, kc.w) * vKnot;           // one board in five has a knot or two
    ringPos += knot * 5.0 * (1.0 - kc.z * 5.0);
    float rings = 0.5 + 0.5 * sin(ringPos);
    float late = smoothstep(0.55, 0.9, rings);                                     // dark latewood bands
    float fibre = mix(0.5, vnoise3(float3(Pl.x * 2.2, zz * 70.0, seed * 3.0)) * 0.7 + 0.3 * vnoise3(float3(Pl.x * 0.9, zz * 190.0, seed * 5.0)), vFib);        // long fibres along the board
    // Checks: long cracks along the grain, opening toward the ends of the board.
    float checkLine = 1.0 - smoothstep(0.0, 0.05 + fpix * 3.0, abs(vnoise3(float3(Pl.x * 0.4, zz * 11.0, seed * 9.0 + 2.0)) - 0.5));
    float check = checkLine * smoothstep(0.42, 0.7, vnoise3(float3(Pl.x * 1.1 + 4.0, zz * 2.0, seed * 4.0))) * step(0.35, hq) * featVis(0.012, fpix);
    // Colour: the board's own tone, silvered by the sun, darker where wet (seaward, low), salt-bleached patches, a worn walking line.
    float silver = saturate(0.55 + 0.45 * (hp - 0.5) * 2.0 + 0.3 * (vnoise3(P * 0.7) - 0.5));
    float3 wood = base * (0.55 + 0.75 * mix(0.5, hp, featVis(0.15, fpix)));
    wood *= mix(0.78, 1.14, mix(0.5, late, vGrain)) * (0.88 + 0.24 * fibre);
    float3 silverCol = float3(0.40, 0.375, 0.34) * (0.72 + 0.4 * mix(0.5, late, vGrain)) * (0.85 + 0.3 * fibre);
    float3 albedo = fresh ? wood : mix(wood, silverCol, silver * 0.82);
    float low = 1.0 - smoothstep(0.7, 1.6, P.y);
    albedo *= 1.0 - 0.42 * low;
    float green = low * smoothstep(0.55, 0.8, vnoise3(P * 3.0 + 6.0)) * 0.5;      // a film of algae on the lowest boards
    albedo = mix(albedo, float3(0.10, 0.17, 0.07) * (0.8 + 0.4 * fibre), green);
    float salt = smoothstep(0.62, 0.82, vnoise3(float3(P.x * 1.5, P.y * 0.5, P.z * 1.5) + 9.0)) * (1.0 - low * 0.5) * 0.35;
    albedo = mix(albedo, float3(0.78, 0.76, 0.70), salt * (fresh ? 0.0 : 1.0));
    float walk = exp(-Pl.x * Pl.x / (2.0 * 0.38 * 0.38));
    albedo *= mix(1.0, 1.14, walk * 0.7);                                          // polished by feet
    // Rust streaks running along the board from the nail heads (columns at x = +-0.8 and +-0.95).
    float rustCol = exp(-pow(abs(Pl.x) - 0.88, 2.0) / (2.0 * 0.07 * 0.07));
    float rust = rustCol * smoothstep(0.45, 0.8, vnoise3(float3(Pl.x * 8.0, zz * 5.0, seed * 6.0))) * featVis(0.05, fpix);
    albedo = mix(albedo, float3(0.30, 0.13, 0.05) * (0.8 + 0.4 * fibre), rust * 0.65);
    albedo *= 1.0 - 0.7 * check - 0.30 * knot * smoothstep(0.14, 0.03, kc.z);
    o.albedo = albedo;
    o.rough = clamp(0.86 + 0.10 * (fibre - 0.5) - 0.14 * low - 0.10 * walk + 0.06 * salt, 0.4, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, 0.0018 * (late - 0.5) * vGrain + 0.002 * (fibre - 0.5) - 0.004 * check + 0.002 * knot, 1.0);
    o.ao = 1.0 - 0.45 * check;
    return o;
}

// ---- Timber: piles, beams and posts: vertical fibres, silvered above the deck, and the tide's bands below it: wet dark wood, a weed band
// at the waterline, barnacles just above it. (The sea level is y = 0.) -----------------------------------------------------------
inline MatOut mat_timber(float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float grainW = featVis(0.03, fpix);
    float fibre = mix(0.5, vnoise3(float3(P.x * 30.0, P.y * 2.5, P.z * 30.0)), grainW);
    float3 albedo = base * (0.72 + 0.5 * fibre);
    float above = smoothstep(0.9, 1.6, P.y);
    albedo = mix(albedo, float3(0.34, 0.31, 0.27) * (0.8 + 0.4 * fibre), above * 0.7);          // silvered by sun above the deck
    float wet = 1.0 - smoothstep(0.4, 1.4, P.y);
    albedo *= mix(1.0, 0.55, wet);
    float weedN = fbm3(P * 5.0 + 2.0);
    float weed = smoothstep(0.35, 0.0, P.y) * smoothstep(-0.7, -0.1, P.y) * smoothstep(0.35, 0.7, weedN + 0.3);
    albedo = mix(albedo, float3(0.06, 0.13, 0.04) * (0.7 + 0.6 * weedN), weed * 0.9);
    float barn = (1.0 - smoothstep(0.10, 0.22, worley(P * 40.0))) * smoothstep(0.9, 0.4, P.y) * smoothstep(-0.2, 0.1, P.y);
    barn = mix(0.07 * smoothstep(0.9, 0.4, P.y) * smoothstep(-0.2, 0.1, P.y), barn, featVis(0.025, fpix));      // barnacles: 2.5 cm, to their mean coverage
    albedo = mix(albedo, float3(0.62, 0.60, 0.55), barn * 0.85);
    o.albedo = albedo;
    o.rough = clamp(0.88 - 0.2 * wet + 0.1 * barn, 0.4, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, 0.003 * (fibre - 0.5) + 0.006 * barn, 1.0);
    o.ao = 1.0 - 0.25 * barn;
    return o;
}

// ---- Glass Wood materials (R06): cold frosted stone, true mirror, pale brushed metal. -----------------------------------------
inline MatOut mat_glassstone(float3 Pl, float3 P, float3 N, float3 base, float fpix) {
    MatOut o = mat_dressed(Pl + float3(0.0, 4.0, 0.0), P, N, base, fpix);                 // pits and chisel marks, no lichen
    float sparkle = step(0.965, vnoise3(P * 80.0)) * featVis(0.012, fpix);
    o.albedo = o.albedo * float3(0.94, 0.96, 1.08) + float3(0.10, 0.12, 0.20) * sparkle;   // frost glints
    o.rough = clamp(o.rough - 0.2, 0.3, 1.0);
    return o;
}
inline MatOut mat_mirror(float3 P, float3 N, float fpix) {
    MatOut o;
    o.albedo = float3(0.93, 0.96, 1.0);
    o.rough = 0.03;
    o.metal = 1.0;
    o.N = bump_normal(P, N, 0.0003 * vnoise3(P * 2.5), 1.0);                                 // a whisper of waviness so reflections are not CG-flat
    o.ao = 1.0;
    return o;
}
inline MatOut mat_palemetal(float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float W = featVis(0.02, fpix);
    float streak = mix(0.5, vnoise3(float3(P.x * 4.0 + P.z * 4.0, P.y * 90.0, 1.0)), W);    // brushed along the horizontal
    o.albedo = base * (0.88 + 0.24 * streak);
    o.rough = 0.30 + 0.16 * streak;
    o.metal = 1.0;
    o.N = N;
    o.ao = 1.0;
    return o;
}

// ---- Rock (F01 W3.2): weathered boulders and outcrops. World-space only (the rocks are merged batches). Strata bands, chipped pale edges on convex rims,
// lichen discs and moss on upward faces, a dark wet band at the waterline and salt-bleached stone above it, pits.
inline MatOut mat_rock(float3 P, float3 N, float3 base, float fpix) {
    MatOut o;
    float vS = featVis(0.4, fpix), vM = featVis(0.08, fpix), vF = featVis(0.015, fpix);
    float3 q = warp3(P, 0.25, 1.3);
    float strata = mix(0.5, ridged3(float3(q.x * 1.1, q.y * 4.0, q.z * 1.1), 3), vS);                 // horizontal layers
    float grain = mix(0.5, vnoise3(P * 120.0), vF);
    float pits = (1.0 - smoothstep(0.10, 0.22, worley(P * 30.0))) * vM;
    float3 col = base * (0.62 + 0.8 * strata) * (0.85 + 0.30 * grain);
    col *= 1.0 - 0.35 * pits;
    float up = smoothstep(0.55, 0.95, N.y);
    float lichenN = mix(0.5, vnoise3(P * 9.0 + 3.0) * 0.6 + 0.4 * vnoise3(P * 22.0), vM);
    float lichen = smoothstep(0.55, 0.75, lichenN) * (0.35 + 0.65 * smoothstep(0.1, 0.8, N.y)) * vM;
    col = mix(col, mix(float3(0.50, 0.52, 0.30), float3(0.70, 0.66, 0.40), vnoise3(P * 14.0)), lichen * 0.6);
    float mossN = rfbm3(P * 3.0 + 7.0, 3);
    float moss = smoothstep(0.50, 0.70, mossN + 0.25 * up - 0.12) * up * (1.0 - lichen * 0.5);
    col = mix(col, float3(0.08, 0.17, 0.05) * (0.7 + 0.6 * mossN), moss * 0.8 * featVis(0.03, fpix));
    float wet = 1.0 - smoothstep(0.3, 1.2, P.y);
    float salt = smoothstep(0.9, 1.8, P.y) * (1.0 - smoothstep(1.8, 3.5, P.y));
    col *= mix(1.0, 0.55, wet);
    col = mix(col, float3(0.72, 0.70, 0.64), salt * 0.25 * smoothstep(0.45, 0.8, vnoise3(P * 4.0)));
    o.albedo = col;
    o.rough = clamp(0.90 - 0.30 * wet - 0.12 * moss + 0.05 * (grain - 0.5), 0.4, 1.0);
    o.metal = 0.0;
    o.N = bump_normal(P, N, 0.010 * (strata - 0.5) * vS - 0.004 * pits + 0.0015 * (grain - 0.5) + 0.006 * moss * vM, 1.0);
    o.ao = 1.0 - 0.2 * pits - 0.10 * wet;
    return o;
}

// ---- Slab (F01 W3.3): the causeway's dressed stone, which rises out of the sea. World height drives the tide: dark wet stone with algae below about 0.5 m,
// barnacles at the waterline, salt crust above; dressed-stone pits, lichen, cracks and chips otherwise. Because slabs RISE during the puzzle the wet band
// travels down them: they drip dry as they come up.
inline MatOut mat_slab(float3 Pl, float3 P, float3 N, float3 base, float fpix) {
    MatOut o = mat_dressed(Pl + float3(0.0, 4.0, 0.0), P, N, base, fpix);
    float vB = featVis(0.03, fpix), vM = featVis(0.10, fpix);
    float wet = 1.0 - smoothstep(0.15, 0.75, P.y);
    float algae = wet * smoothstep(0.40, 0.70, rfbm3(P * 6.0 + 2.0, 3)) * vM;
    float barn = (1.0 - smoothstep(0.10, 0.22, worley(P * 38.0))) * smoothstep(0.55, 0.20, P.y) * smoothstep(-0.5, 0.0, P.y);
    barn = mix(0.05 * smoothstep(0.55, 0.20, P.y), barn, vB);
    float3 c = o.albedo * mix(1.0, 0.50, wet);
    c = mix(c, float3(0.05, 0.14, 0.05) * (0.7 + 0.6 * vnoise3(P * 20.0)), algae * 0.75);
    c = mix(c, float3(0.66, 0.64, 0.58), barn * 0.8);
    float salt = smoothstep(0.7, 1.4, P.y) * smoothstep(0.55, 0.8, vnoise3(P * 3.5 + 5.0)) * 0.30;
    c = mix(c, float3(0.78, 0.76, 0.70), salt);
    float crack = (1.0 - smoothstep(0.0, 0.012 + fpix * 2.0, worley3F(P * 1.6 + 3.0).y - worley3F(P * 1.6 + 3.0).x)) * step(0.6, vnoise3(P * 0.9 + 1.0)) * featVis(0.01, fpix);
    c *= 1.0 - 0.38 * crack;
    o.albedo = c;
    o.rough = clamp(o.rough - 0.35 * wet + 0.1 * barn, 0.3, 1.0);
    o.N = bump_normal(P, o.N, 0.004 * barn - 0.004 * crack, 1.0);
    o.ao *= 1.0 - 0.3 * crack;
    return o;
}

inline MatOut material_surface_raw(int id, float3 Pl, float3 P, float3 N, float3 base, float rough, float fpix) {
    MatOut o;
    if (id == 5) o = mat_masonry(Pl, P, N, base, fpix);
    else if (id == 6) o = mat_paint(Pl, P, N, base, fpix);
    else if (id == 7) o = mat_iron(P, N, base, fpix);
    else if (id == 8) o = mat_copper(P, N, fpix);
    else if (id == 9) o = mat_wood(Pl, P, N, base, fpix);
    else if (id == 11 || id == 14) o = mat_dressed(Pl, P, N, base, fpix);
    else if (id == 16) o = mat_dressed(Pl + float3(0.0, 4.0, 0.0), P, N, base, fpix);      // a loose pebble: no lichen at its "foot"
    else if (id == 15) o = mat_paper(Pl, P, N, fpix);
    else if (id == 17 || id == 20) o = mat_glassstone(Pl, P, N, base, fpix);
    else if (id == 18) o = mat_mirror(P, N, fpix);
    else if (id == 19) o = mat_palemetal(P, N, base, fpix);
    else if (id == 12) o = mat_plank(Pl, P, N, base, rough, fpix);
    else if (id == 13) o = mat_timber(P, N, base, fpix);
    else if (id == 21) o = mat_rock(P, N, base, fpix);
    else if (id == 22) o = mat_slab(Pl, P, N, base, fpix);
    else o = mat_bark(P, N, base, fpix);
    return o;
}

inline MatOut material_surface(int id, float3 Pl, float3 P, float3 N, float3 base, float rough, float fpix) {
    MatOut o = material_surface_raw(id, Pl, P, N, base, rough, fpix);
    // Roughness follows lost detail (Toksvig idea): the relief that is no longer resolved still scatters light, so the surface goes matte
    // with distance instead of getting a cleaner, brighter highlight. A footprint of 1.5 cm starts it; 40 cm has taken a third of the way.
    if (id != 18) o.rough = mix(o.rough, 1.0, 0.33 * smoothstep(0.015, 0.40, fpix));        // (a mirror stays a mirror)
    return o;
}
"""#
}
