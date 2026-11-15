import Metal
import simd

/// S05.4 (A5, builder A): the VANTAGE STATIONS. The two routes see each other's site only across the island's terraces, and what is 1 m across (an orrery arm, a dome window) cannot be read at 230 m from a quay
/// (Q68), so each route is given one place on its own walked line where the other site IS readable: a stone pedestal with a brass far-glass aimed at it, and a ray test that the target is in sight from the
/// spot where the player stands. The glass is a pointer, not a second camera: the player's own LookCloser zoom does the magnifying (2.9x; a 1 m window at 30 m is about 60 px at full zoom on a 720 p frame).
/// Station 0 (Ilse's route) looks at Oren's orrery and the dome's three windows; station 1 (Oren's route) looks at Ilse's five shelf bays and the bell mast. Positions: `ArchiveLayout.vantage*`.
enum Vantage {
    static let count = 2
    static func name(_ k: Int) -> String { "ta_vantage_\(k)" }
    /// The eye of a player standing at station k's walked spot.
    static func eye(_ k: Int) -> SIMD3<Float> { ArchiveLayout.vantageStand[k] + SIMD3(0, Player.eyeHeight, 0) }

    /// The things station k is for, as points in the world: the middle of each dome window and the orrery's highest arm (station 0); the middle of each shelf bay and the top of the bell mast (station 1).
    static func targets(_ k: Int) -> [SIMD3<Float>] {
        if k == 0 {
            let o = ArchiveLayout.orrery, s = ArchiveLayout.vantageStand[0]
            let toward = simd_normalize(SIMD3(s.x - o.x, 0, s.z - o.z)) * Orrery.armLength[2]       // the near edge of the longest arm's sweep: the dial's rim and the highest arm's tip there, and the far side's rim
            return (0..<3).map { j -> SIMD3<Float> in let w = ArchiveLayout.domeWindowXZ(j); return SIMD3(w.x, ArchiveLayout.groundY(w.x, w.y) + DomeWindows.y, w.y) }
                + [SIMD3(o.x, o.y + Orrery.dialY, o.z) + toward, SIMD3(o.x, o.y + Orrery.armHeight[2], o.z) + toward, SIMD3(o.x, o.y + Orrery.dialY, o.z) - toward]
        }
        let m = ArchiveLayout.bellMast
        return (0..<ArchiveLayout.bayCount).map { ArchiveLayout.bay($0) + SIMD3(0, 2.0, 0) } + [SIMD3(m.x, m.y + DormantViews.mastHeight + 1.0, m.z)]
    }

    /// The terrain ray test: true if no ground lies on the straight line from `a` to `b` and it clears every sampled point by `margin` m (a view that grazes the rim is not a view). Sampled every `step` m (the terrain is smooth to a few metres, so 0.5 m is conservative).
    static func clear(_ terrain: Terrain, from a: SIMD3<Float>, to b: SIMD3<Float>, step: Float = 0.5, margin: Float = 0.3) -> Bool {
        let n = max(Int(simd_length(b - a) / step), 2)
        for i in 1..<n { let p = a + (b - a) * (Float(i) / Float(n)); if terrain.sampleHeight(x: p.x, z: p.z) > p.y - margin { return false } }
        return true
    }
    /// How many of station k's targets are in sight from the stand, and the farthest of them.
    static func seen(_ k: Int, terrain: Terrain) -> (visible: Int, total: Int, farthest: Float) {
        let t = targets(k), e = eye(k)
        return (t.filter { clear(terrain, from: e, to: $0) }.count, t.count, t.map { simd_length($0 - e) }.max() ?? 0)
    }

    static func add(to scene: Scene, device: MTLDevice) {
        let stone = ArchiveProps.slateLight, brass = ArchiveProps.brass, iron = ArchiveProps.iron
        for k in 0..<count {
            let post = ArchiveLayout.vantagePost(k), aim = ArchiveLayout.vantageAim[k]
            var b = MeshBuilder()
            // A stepped stone pedestal a little under a metre and a half high, a brass cap plate and a dial ring.
            b.chamferBox(size: SIMD3(0.9, 0.2, 0.9), chamfer: 0.03, surface: stone, transform: translation(SIMD3(0, 0.1, 0)))
            b.chamferBox(size: SIMD3(0.62, 1.0, 0.62), chamfer: 0.04, surface: stone, transform: translation(SIMD3(0, 0.7, 0)))
            b.chamferBox(size: SIMD3(0.8, 0.1, 0.8), chamfer: 0.025, surface: brass, transform: translation(SIMD3(0, 1.25, 0)))
            b.torus(major: 0.3, minor: 0.018, segments: 24, sides: 6, smooth: true, surface: brass, transform: translation(SIMD3(0, 1.31, 0)))
            // The far-glass: a brass tube on two cheeks, pointed at the target (the glass's own pivot is above the pedestal's middle).
            let pivot = SIMD3<Float>(0, 1.5, 0), d = simd_normalize(aim - (post + pivot))
            let side = simd_normalize(simd_cross(d, SIMD3(0, 1, 0)))
            for sgn: Float in [-1, 1] { b.box(size: SIMD3(0.04, 0.3, 0.1), surface: brass, transform: translation(SIMD3(0, 1.4, 0) + side * (0.1 * sgn))) }
            b.tube(points: [pivot - d * 0.42, pivot + d * 0.55], radii: [0.055, 0.075], sides: 10, caps: true, surface: brass)
            b.tube(points: [pivot + d * 0.5, pivot + d * 0.72], radii: [0.075, 0.1], sides: 10, caps: true, surface: brass)      // the objective's bell
            b.tube(points: [pivot - d * 0.42, pivot - d * 0.5], radii: [0.045, 0.045], sides: 8, caps: true, surface: iron)     // the eyepiece
            scene.add(name(k), mesh: b.build(device: device, label: "vantage \(k)"), uniforms: ObjectUniforms(model: translation(post)))
            scene.colliders.addCylinder(center: SIMD2(post.x, post.z), radius: 0.5, minY: post.y - 1, maxY: post.y + 2.2)
        }
    }
}
