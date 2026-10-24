import Metal
import simd

/// Trees with real structure (R03 / T57.4). A conifer is a bark trunk (root flare, curve, taper) carrying whorls of drooping branch
/// tubes; the foliage is a mass of small, flattened, noise-displaced bough clumps on those branches, not stacked cones. Each clump's
/// normals are bent away from the crown centre, so the whole crown shades as one soft volume instead of showing facets, and its vertex
/// colour bakes a dark interior and light tips (cheap ambient occlusion). The existing wrap lighting and back-lit translucency of the
/// foliage material still apply.
///
/// Three levels of detail are built (0: full structure for under ~45 m; 1: trunk and a few large clumps; 2: the old cone silhouette),
/// 16 seeded variants per species and level. Individual trees are instances of a variant with their own height, width, lean, yaw and
/// shade, so no two neighbours match without building thousands of meshes.
enum Trees {
    enum Style { case pine, cypress }
    static let variantCount = 16
    static let nominalHeight: Float = 9

    private static var cache: [Int: MeshBuilder] = [:]
    static func variant(_ style: Style, _ index: Int, lod: Int) -> MeshBuilder {
        let key = (style == .pine ? 0 : 1000) + index * 10 + lod
        if let c = cache[key] { return c }
        let m = conifer(seed: UInt32(7000 + index * 131 + (style == .pine ? 17 : 0)), style: style, lod: lod)
        cache[key] = m
        return m
    }
    private static var snagCache: [Int: MeshBuilder] = [:]
    static func snagVariant(_ index: Int, lod: Int) -> MeshBuilder {
        let key = index * 10 + lod
        if let c = snagCache[key] { return c }
        let m = snag(seed: UInt32(9100 + index * 71), lod: lod)
        snagCache[key] = m
        return m
    }

    /// One conifer of height `nominalHeight`, standing on y = 0 at the origin.
    static func conifer(seed: UInt32, style: Style, lod: Int) -> MeshBuilder {
        if lod >= 2 { return style == .pine ? Props.pine(seed: seed, height: nominalHeight) : Props.cypress(seed: seed, height: nominalHeight) }
        let n = Noise(seed: seed)
        func r(_ i: Int, _ j: Int) -> Float { n.unit(Int32(i), Int32(j)) }
        let H = nominalHeight, pine = style == .pine
        var b = MeshBuilder()

        // ---- Trunk: slight curve, strong taper, root flare, bark material at full detail.
        let bend = SIMD2<Float>(r(1, 1) - 0.5, r(1, 2) - 0.5) * 0.9
        func trunkAt(_ t: Float) -> SIMD3<Float> {
            SIMD3(bend.x * t * t * 0.9 + 0.08 * sin(t * 6 + r(1, 3) * 6), t * H * 0.97, bend.y * t * t * 0.9 + 0.08 * cos(t * 5 + r(1, 4) * 6))
        }
        let r0 = H * 0.034 * (0.85 + 0.3 * r(1, 5))
        func trunkR(_ t: Float) -> Float { r0 * (1 - 0.84 * t) * (1 + 0.6 * exp(-t * 16)) }
        let bark = Surface(color: SIMD3(0.21, 0.145, 0.10) * (0.85 + 0.3 * r(1, 6)), roughness: 0.95, material: lod == 0 ? .bark : .standard)
        let ts: [Float] = lod == 0 ? [0, 0.03, 0.08, 0.18, 0.35, 0.55, 0.75, 0.9, 1.0] : [0, 0.12, 0.5, 1.0]
        b.tube(points: ts.map(trunkAt), radii: ts.map(trunkR), sides: lod == 0 ? 8 : 5, surface: bark)

        // ---- Crown: whorls of branches, shorter toward the top.
        let tStart: Float = pine ? 0.27 : 0.15
        let crownR = H * (pine ? 0.27 : 0.135) * (0.85 + 0.3 * r(2, 2))
        let whorls = lod == 0 ? (pine ? 9 : 11) : (pine ? 8 : 9)
        let perWhorl = lod == 0 ? (pine ? 5 : 4) : 4
        let droop: Float = (pine ? 0.26 : 0.12) * (0.8 + 0.4 * r(2, 3))
        struct Branch { var base: SIMD3<Float>; var mid: SIMD3<Float>; var tip: SIMD3<Float>; var ang: Float; var len: Float; var t: Float }
        var branches: [Branch] = []
        for w in 0..<whorls {
            let t = tStart + (0.97 - tStart) * (Float(w) + 0.5) / Float(whorls)
            let p0 = trunkAt(t)
            let taper = pow(max(1 - (t - tStart) / (1 - tStart), 0.05), pine ? 0.8 : 0.95)
            let reach = crownR * taper * (0.75 + 0.5 * r(w, 3)) + 0.25
            let phase = r(w, 4) * 2 * .pi
            for k in 0..<perWhorl {
                let ang = phase + (Float(k) + 0.3 * (r(w * 7 + k, 5) - 0.5)) * 2 * .pi / Float(perWhorl)
                let dir = SIMD3<Float>(cos(ang), 0, sin(ang))
                let len = reach * (0.8 + 0.4 * r(w * 7 + k, 6))
                let mid = p0 + dir * len * 0.5 + SIMD3(0, -droop * len * 0.30 + 0.05 * len, 0)
                let tip = p0 + dir * len + SIMD3(0, -droop * len * 0.5 + 0.12 * len, 0)
                branches.append(Branch(base: p0, mid: mid, tip: tip, ang: ang, len: len, t: t))
            }
        }
        if lod == 0 {
            for br in branches {
                let rb = trunkR(br.t) * 0.4
                b.tube(points: [br.base, br.mid, br.tip], radii: [rb, rb * 0.55, 0.012], sides: 4, surface: bark)
            }
        }
        // ---- Foliage: flattened, noise-displaced clumps on the branches; normals bent outward, interior dark, tips light.
        let fStart = b.vertices.count
        let hue = r(3, 1)
        let leaf = Surface(color: SIMD3(0.044 + 0.02 * hue, 0.108 + 0.04 * hue, 0.048 + 0.012 * r(3, 2)), roughness: 0.9, material: .foliage)
        func clump(at p: SIMD3<Float>, radius rc: Float, ang: Float, salt: Int) {
            let off = r(salt, 11) * 9
            b.icosphere(subdivisions: lod == 0 ? 1 : 0, smooth: true,
                        radius: { d in 0.78 + 0.5 * n.fbm(d.x * 2.3 + off, d.y * 2.1 + d.z * 1.7 + off, octaves: 2) },
                        surface: leaf,
                        transform: translation(p) * rotationY(-ang) * rotationZ((r(salt, 12) - 0.5) * 0.5) * scaling(SIMD3(1.1, 0.72, 0.95) * rc))
        }
        for (i, br) in branches.enumerated() {
            let rc = max(br.len * (pine ? 0.36 : 0.42), 0.4)
            if lod == 0 {
                clump(at: br.base + (br.tip - br.base) * 0.84, radius: rc * 1.05, ang: br.ang, salt: i * 3)
                clump(at: br.base + (br.mid - br.base) * 1.0, radius: rc * 0.78, ang: br.ang + 0.25, salt: i * 3 + 1)
                if pine && i % 3 == 0 { clump(at: br.base + (br.tip - br.base) * 0.45 + SIMD3(0, 0.12, 0), radius: rc * 0.6, ang: br.ang - 0.3, salt: i * 3 + 2) }
            } else {
                clump(at: br.base + (br.tip - br.base) * 0.7, radius: rc * 1.5, ang: br.ang, salt: i * 3)
            }
        }
        let top = trunkAt(0.985)
        clump(at: top + SIMD3(0, 0.15, 0), radius: crownR * 0.32 + 0.3, ang: 0, salt: 9001)
        let centre = trunkAt(tStart + (1 - tStart) * 0.45)
        b.adjust(from: fStart) { v in
            let p = SIMD3(v.position.x, v.position.y, v.position.z)
            let nrm = SIMD3(v.normal.x, v.normal.y, v.normal.z)
            let away = simd_normalize(p - centre)
            let bent = simd_normalize(simd_mix(nrm, away, SIMD3(repeating: 0.8)))
            v.normal = SIMD4(bent, v.normal.w)
            let dist = simd_length(SIMD2(p.x - centre.x, p.z - centre.z)) / max(crownR, 0.5)
            let lightness = simd_mix(0.5, 1.25, smoothstep(0.08, 1.0, dist)) * (0.85 + 0.3 * (bent.y * 0.5 + 0.5)) * (0.9 + 0.2 * (p.y / H))
            v.color = SIMD4(v.color.x * lightness, v.color.y * lightness, v.color.z * lightness, v.color.w)
        }
        return b
    }

    /// A dead snag: a bare trunk broken off short, with a few broken limbs and stubs.
    static func snag(seed: UInt32, lod: Int) -> MeshBuilder {
        let n = Noise(seed: seed)
        func r(_ i: Int, _ j: Int) -> Float { n.unit(Int32(i), Int32(j)) }
        let H = nominalHeight * (0.7 + 0.2 * r(1, 1))
        var b = MeshBuilder()
        let bark = Surface(color: SIMD3(0.27, 0.235, 0.20), roughness: 0.95, material: lod == 0 ? .bark : .standard)
        let r0 = nominalHeight * 0.032
        let ts: [Float] = [0, 0.05, 0.2, 0.45, 0.75, 1.0]
        let lean = SIMD2<Float>(r(1, 2) - 0.5, r(1, 3) - 0.5) * 0.6
        b.tube(points: ts.map { SIMD3(lean.x * $0 * $0, $0 * H, lean.y * $0 * $0) },
               radii: ts.map { r0 * (1 - 0.7 * $0) * (1 + 0.5 * exp(-$0 * 14)) }, sides: lod == 0 ? 7 : 5, surface: bark)
        for i in 0..<(lod == 0 ? 6 : 3) {
            let t = 0.35 + 0.55 * Float(i) / 6 + 0.05 * r(i, 4)
            let a = r(i, 5) * 2 * .pi
            let p0 = SIMD3(lean.x * t * t, t * H, lean.y * t * t)
            let len = 0.5 + 1.6 * r(i, 6) * (1 - 0.5 * t)
            let dir = SIMD3<Float>(cos(a), 0.55 + 0.4 * r(i, 7), sin(a))
            let tip = p0 + simd_normalize(dir) * len
            b.tube(points: [p0, (p0 + tip) * 0.5 + SIMD3(0, 0.08, 0), tip], radii: [r0 * 0.34 * (1 - 0.5 * t), r0 * 0.2, r0 * 0.12], sides: 4, surface: bark)
        }
        return b
    }
}
