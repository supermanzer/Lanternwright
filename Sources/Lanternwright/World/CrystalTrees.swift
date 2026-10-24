import simd

/// The Glass Wood's crystal trees (R06): a faceted, twisted trunk of stacked hexagonal frusta with horizontal growth bands and a glowing
/// vein spiralling up its surface, branches that taper and fork, and crowns of crystal clusters (3 to 7 elongated hexagonal prisms with
/// pointed tips at varied angles, teal to violet). Everything is drawn through the refractive glass pass, where the vertex colour is the
/// glass tint and a vertex alpha above 0.5 marks the self-lit vein (see crystal_fragment). Built like the conifers: a handful of
/// variants at three LODs (the placer picks one per tree and scales it), merged per 60 m cell and switched by eye distance.
enum CrystalTrees {
    static let variantCount = 10
    static let nominalHeight: Float = 10
    private static var cache: [Int: MeshBuilder] = [:]

    static func variant(_ i: Int, lod: Int) -> MeshBuilder {
        let key = i * 3 + lod
        if let m = cache[key] { return m }
        let m = build(seed: UInt32(1000 + i * 131), lod: lod)
        cache[key] = m
        return m
    }

    /// Teal to violet (rarely rose), with a little brightness jitter.
    private static func tint(_ u: Float, _ j: Float, rose: Float) -> SIMD3<Float> {
        let teal = SIMD3<Float>(0.40, 0.95, 1.0), violet = SIMD3<Float>(0.74, 0.55, 1.0), rosy = SIMD3<Float>(1.0, 0.62, 0.92)
        var c = teal + (violet - teal) * min(max(u, 0), 1)
        if rose > 0.93 { c = rosy }
        return c * (0.85 + 0.3 * j)
    }

    /// One crystal: a hexagonal prism with a pointed hexagonal tip, growing from `at` along `dir`.
    private static func crystal(_ b: inout MeshBuilder, at: SIMD3<Float>, dir: SIMD3<Float>, length: Float, radius: Float, color: SIMD3<Float>) {
        let s = Surface(color: color, roughness: 0.08)
        let m = translation(at) * rotation(aligningYTo: dir)
        b.cylinder(radiusTop: radius * 0.92, radiusBottom: radius, height: length * 0.72, segments: 6, smooth: false, caps: false, surface: s, transform: m)
        b.cone(radius: radius * 0.92, height: length * 0.34, segments: 6, smooth: false, surface: s, transform: m * translation(SIMD3(0, length * 0.72, 0)))
    }

    /// A cluster of `count` crystals fanned around `dir` (the first, tallest one nearest the axis).
    private static func cluster(_ b: inout MeshBuilder, noise: Noise, salt: Int32, at: SIMD3<Float>, dir: SIMD3<Float>, size: Float, count: Int, hue: Float, spread: Float) {
        let axis = simd_normalize(dir)
        let helper: SIMD3<Float> = abs(axis.y) > 0.95 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let u = simd_normalize(simd_cross(helper, axis)), v = simd_cross(axis, u)
        for j in 0..<count {
            let k = salt * 17 + Int32(j)
            let a = noise.unit(k, 1) * 2 * .pi + Float(j) * 2.4
            let tilt = (j == 0 ? 0.0 : spread * (0.55 + 0.6 * noise.unit(k, 2)))
            let d = simd_normalize(axis * cos(tilt) + (u * cos(a) + v * sin(a)) * sin(tilt))
            let L = size * (j == 0 ? 1.25 : 0.55 + 0.6 * noise.unit(k, 3))
            let R = L * (0.085 + 0.05 * noise.unit(k, 4))
            let col = tint(hue + (noise.unit(k, 5) - 0.5) * 0.45, noise.unit(k, 6), rose: noise.unit(k, 7))
            crystal(&b, at: at + d * R * 0.4, dir: d, length: L, radius: R, color: col)
        }
    }

    static func build(seed: UInt32, lod: Int) -> MeshBuilder {
        let noise = Noise(seed: seed)
        var b = MeshBuilder()
        let H = nominalHeight
        let trunkTop: Float = 0.60                                    // fraction of H where the trunk ends and the branching crown begins
        let sections = lod == 0 ? 9 : (lod == 1 ? 5 : 3)
        let r0: Float = 0.42
        let phase = noise.unit(1, 1) * 6.28, lean = 0.35 + 0.5 * noise.unit(2, 2)
        func centre(_ t: Float) -> SIMD3<Float> {
            SIMD3(lean * sin(2.1 * t + phase) * t, t * H * trunkTop, lean * 0.8 * sin(1.6 * t + phase * 1.7) * t)
        }
        func radius(_ t: Float) -> Float { r0 * (1 - 0.72 * t) }
        let hueBase = noise.unit(3, 3) * 0.5
        // Trunk: stacked frusta, each turned a little from the one below (a twist), with a thin wider collar at every other joint (growth bands).
        for i in 0..<sections {
            let t0 = Float(i) / Float(sections), t1 = Float(i + 1) / Float(sections)
            let p0 = centre(t0), p1 = centre(t1)
            let col = tint(hueBase + 0.5 * t0, noise.unit(Int32(i), 11) * 0.5, rose: 0)
            let s = Surface(color: col * SIMD3(0.8, 0.95, 1.0), roughness: 0.08)
            let twist = Float(i) * 0.31
            b.cylinder(radiusTop: radius(t1), radiusBottom: radius(t0), height: simd_length(p1 - p0) * 1.02, segments: 6, smooth: false, caps: false,
                       surface: s, transform: translation(p0) * rotation(aligningYTo: p1 - p0) * rotationY(twist))
            if lod < 2 && i % 2 == 1 {
                b.cylinder(radiusTop: radius(t0) * 1.10, radiusBottom: radius(t0) * 1.2, height: 0.16, segments: 6, smooth: false, surface: s,
                           transform: translation(p0 - SIMD3(0, 0.05, 0)) * rotationY(twist + 0.15))
            }
        }
        // The vein: a thin self-lit ridge spiralling up the trunk (vertex alpha 1 = lit core).
        if lod < 2 {
            var pts: [SIMD3<Float>] = [], rad: [Float] = []
            let steps = lod == 0 ? 22 : 11
            for k in 0...steps {
                let t = Float(k) / Float(steps)
                let a = phase + t * 9.0
                pts.append(centre(t) + SIMD3(cos(a), 0, sin(a)) * radius(t) * 0.88 + SIMD3(0, 0.0, 0))
                rad.append(0.045 * (1 - 0.5 * t))
            }
            b.tube(points: pts, radii: rad, sides: 4, caps: false, surface: Surface(color: SIMD3(0.6, 1.0, 1.0), roughness: 1.0))
        }
        // Branches: the crown. Each leaves the upper trunk reaching up and out, tapers, and forks near its end; crystals grow from the tips.
        let top = centre(1)
        let nBranch = lod == 0 ? 5 : (lod == 1 ? 4 : 3)
        for k in 0..<nBranch {
            let f = Float(k) / Float(nBranch)
            let t = 0.52 + 0.46 * f
            let from = centre(min(t, 1))
            let az = Float(k) * 2.399 + noise.unit(Int32(k), 21) * 1.2
            let el = 0.55 + 0.45 * noise.unit(Int32(k), 22)
            let d = simd_normalize(SIMD3(cos(az) * cos(el), sin(el) + 0.15, sin(az) * cos(el)))
            let L = H * (0.20 + 0.14 * noise.unit(Int32(k), 23)) * (1.05 - 0.35 * f)
            let rb = radius(min(t, 1)) * 0.55 + 0.04
            let col = tint(hueBase + 0.45 + 0.3 * f, noise.unit(Int32(k), 24), rose: 0)
            let s = Surface(color: col, roughness: 0.08)
            let mid = from + d * L * 0.55
            let d2 = simd_normalize(d + SIMD3(0, 0.45, 0))                       // curls up toward the sky
            let end = mid + d2 * L * 0.45
            b.cylinder(radiusTop: rb * 0.68, radiusBottom: rb, height: L * 0.55, segments: 5, smooth: false, caps: false, surface: s, transform: translation(from) * rotation(aligningYTo: d))
            b.cylinder(radiusTop: rb * 0.32, radiusBottom: rb * 0.68, height: L * 0.45, segments: 5, smooth: false, caps: false, surface: s, transform: translation(mid) * rotation(aligningYTo: d2))
            let tips: [(SIMD3<Float>, SIMD3<Float>)]
            if lod == 0 {
                // Fork: two children leave the end, one each side, shorter and thinner.
                let side = simd_normalize(simd_cross(d2, SIMD3(0, 1, 0)))
                let da = simd_normalize(d2 + side * 0.65 + SIMD3(0, 0.2, 0)), db = simd_normalize(d2 - side * 0.65 + SIMD3(0, 0.3, 0))
                let Lc = L * 0.40
                var out: [(SIMD3<Float>, SIMD3<Float>)] = []
                for (dc, kk) in [(da, Int32(0)), (db, Int32(1))] {
                    b.cylinder(radiusTop: rb * 0.12, radiusBottom: rb * 0.32, height: Lc, segments: 5, smooth: false, caps: false, surface: s, transform: translation(end) * rotation(aligningYTo: dc))
                    out.append((end + dc * Lc, dc))
                    _ = kk
                }
                out.append((end, d2))
                tips = out
            } else {
                tips = [(end, d2)]
            }
            for (j, tip) in tips.enumerated() {
                let count = lod == 0 ? 3 + Int(noise.unit(Int32(k * 3 + j), 25) * 4.99) : (lod == 1 ? 4 : 3)
                cluster(&b, noise: noise, salt: Int32(40 + k * 3 + j), at: tip.0, dir: tip.1 + SIMD3(0, 0.6, 0), size: H * (0.09 + 0.05 * noise.unit(Int32(k * 3 + j), 26)),
                        count: count, hue: hueBase + 0.5 + 0.35 * f, spread: 0.65)
            }
        }
        // The trunk's own crown: a taller cluster straight up from the top, and a few small crystals thrusting out of the ground at the foot.
        cluster(&b, noise: noise, salt: 90, at: top, dir: SIMD3(0, 1, 0), size: H * 0.19, count: lod == 2 ? 5 : 7, hue: hueBase + 0.6, spread: 0.5)
        if lod < 2 {
            for k in 0..<(lod == 0 ? 4 : 2) {
                let a = Float(k) * 1.9 + noise.unit(Int32(k), 31) * 2
                cluster(&b, noise: noise, salt: Int32(100 + k), at: SIMD3(cos(a) * 0.5, -0.05, sin(a) * 0.5), dir: SIMD3(cos(a) * 0.55, 1, sin(a) * 0.55), size: 0.5 + 0.5 * noise.unit(Int32(k), 32), count: 3, hue: hueBase + 0.1, spread: 0.5)
            }
        }
        return b
    }
}
