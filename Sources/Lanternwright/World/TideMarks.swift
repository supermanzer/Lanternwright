import Metal
import simd

/// S05.4 / A6 (Q80, builder A): the TIDE MARKS on each route's arrival quay. Builder B's A0 puzzle counts three crossings: the water passes the middle of each sluice room's window (`IlseTones.matchLevel`: 0.79, 0.38
/// and 0.10 of the tide's range). Nothing on the quay showed those levels, so A0 answered on one sense only. Here a stone GAUGE stands in the shallows straight out from each quay (site 0 = the lamp end, Ilse's; site 1 = the
/// open end, Oren's), its foot at the water's lowest edge, and carries three brass bars at exactly those three heights in the sea's own metres (`Tide.metres(level:)`), highest first (tide, wind, stone), each with its
/// stone's mark above it (waves, two slants, a square: the door plates' vocabulary). The player SEES the water climb across a bar.
/// A bar lights when the water crosses it (this file's `update`, driven by `ArchiveProps.update` from the tide clock alone, a pulse that holds and fades), and builder B may light a bar too: `TideMarks.set(scene, k, lit)`
/// holds bar k (both gauges, or `site:`) at that brightness until set to 0; what shows is the greater of the pulse and the held value. Nothing here changes any puzzle state.
enum TideMarks {
    static let count = 3, sites = 2
    static func name(_ site: Int, _ k: Int) -> String { "ta_tidemark_\(site)_\(k)" }
    static func gaugeName(_ site: Int) -> String { "ta_tidegauge_\(site)" }
    static func railName(_ site: Int) -> String { "ta_tiderails_\(site)" }
    /// The sea's height (world metres) at which bar k sits: the water's surface when the tide is at k's matching level.
    static func height(_ k: Int) -> Float { Tide.metres(level: IlseTones.matchLevel(k)) }
    /// The quay each site belongs to.
    static func quay(_ site: Int) -> SIMD3<Float> { site == 0 ? ArchiveLayout.lampEnd : ArchiveLayout.openEnd }

    /// A9 (Q125): the gauge is a LANDMARK seen from the quay 31-33 m off: a pale stone stele 3.4 m wide, rising `topAbove` over the top bar (about 7 m from its foot), with three brass bars 8.4 m wide (about 200 px across in a 1600 px frame at the quay),
    /// 0.44 m thick, that glow a dim brass all the time and brighten when the water crosses them, and a pale stone cap. The bars' heights (the tide's levels) are unchanged.
    static let barWidth: Float = 8.4, barHeight: Float = 0.44, barDepth: Float = 0.2, steleWidth: Float = 3.4, steleDepth: Float = 0.6
    /// How far above the lowest sea the gauge's foot stands, so low water just touches it (m), and how far its stone reaches above the top bar.
    static let footAboveLow: Float = -0.15, topAbove: Float = 5.0
    static let litEmissive = SIMD3<Float>(1.0, 0.74, 0.28), idleEmissive: Float = 1.1, litStrength: Float = 3.0
    /// A pulse after the water crosses a bar: full for `holdSeconds`, then fading over `fadeSeconds`.
    static let holdSeconds: Float = 1.5, fadeSeconds: Float = 2.5
    static func pulse(age: Float) -> Float { age < holdSeconds ? 1 : max(0, 1 - (age - holdSeconds) / fadeSeconds) }

    /// The gauge's place: straight out from the quay (same x), at the first ground (walking seaward) that is down to the lowest sea plus `footAboveLow`.
    static func foot(_ site: Int, terrain: Terrain) -> SIMD3<Float> {
        let q = quay(site), want = Tide.lowSea + footAboveLow
        var z = q.z
        while z < q.z + 80, terrain.sampleHeight(x: q.x, z: z) > want { z += 0.25 }
        return SIMD3(q.x, terrain.sampleHeight(x: q.x, z: z), z)
    }

    /// True if the tide's level crosses bar k's level between the clocks `t0` and `t1` (either way: the water rising past it or falling past it).
    static func crossed(_ k: Int, from t0: Float, to t1: Float) -> Bool {
        let l = IlseTones.matchLevel(k), a = Tide.level(t0) - l, b = Tide.level(t1) - l
        return a != b && a * b <= 0
    }

    static func add(to scene: Scene, device: MTLDevice) {
        let stone = Surface(color: SIMD3(0.62, 0.62, 0.58), roughness: 0.9, material: .masonry)
        let cap = Surface(color: SIMD3(0.86, 0.84, 0.76), roughness: 0.7, material: .dressed)
        let gold = Surface(color: SIMD3(0.95, 0.62, 0.14), roughness: 0.5, material: .dressed)
        let iron = ArchiveProps.iron
        for site in 0..<sites {
            let f = foot(site, terrain: scene.terrain)
            let top = height(0) + topAbove, base = f.y - 0.8            // sunk well under the ground so no gap shows at the foot
            // The stele: faces the quay (north, -Z); its front face is at local z = -steleDepth / 2.
            var m = MeshBuilder()
            m.chamferBox(size: SIMD3(steleWidth, top - base, steleDepth), chamfer: 0.04, surface: stone, transform: translation(SIMD3(0, (top + base) / 2, 0)))
            m.chamferBox(size: SIMD3(steleWidth + 0.6, 0.45, steleDepth + 0.5), chamfer: 0.05, surface: cap, transform: translation(SIMD3(0, top + 0.225, 0)))      // the pale top plate
            // The stone's mark (iron, dark on the bright brass) on each bar's face, near both ends.
            for k in 0..<count { for sx: Float in [-1, 1] {
                let face = translation(SIMD3(sx * (barWidth / 2 - 0.7), height(k), -steleDepth / 2 - 0.02 - barDepth / 2 - 0.03)) * rotationY(.pi)
                switch k {
                case 0: for i in 0..<3 { m.box(size: SIMD3(0.34, 0.05, 0.02), surface: iron, transform: face * translation(SIMD3(0, (Float(i) - 1) * 0.1, 0))) }
                case 1: for dx: Float in [-0.09, 0.09] { m.box(size: SIMD3(0.045, 0.28, 0.02), surface: iron, transform: face * translation(SIMD3(dx, 0, 0)) * rotationZ(-0.5)) }
                default: m.box(size: SIMD3(0.22, 0.22, 0.02), surface: iron, transform: face)
                }
            } }
            scene.add(gaugeName(site), mesh: m.build(device: device, label: "tide gauge \(site)"), uniforms: ObjectUniforms(model: translation(SIMD3(f.x, 0, f.z))))
            for k in 0..<count {
                var b = MeshBuilder()
                b.box(size: SIMD3(barWidth, barHeight, barDepth), surface: gold, transform: translation(SIMD3(0, height(k), -steleDepth / 2 - 0.02 - barDepth / 2 + 0.08)))
                scene.add(name(site, k), mesh: b.build(device: device, label: "tide mark \(site).\(k)"), uniforms: ObjectUniforms(model: translation(SIMD3(f.x, 0, f.z)), emissive: SIMD4(litEmissive, idleEmissive)))
            }
            // Two brass rails up the stele's edges, glowing always (the bars are under water at some tides; these never are).
            var rails = MeshBuilder()
            for sx: Float in [-1, 1] { rails.box(size: SIMD3(0.22, top - f.y - 0.1, 0.1), surface: gold, transform: translation(SIMD3(sx * (steleWidth / 2 - 0.2), (top + f.y + 0.1) / 2, -steleDepth / 2 - 0.03))) }
            scene.add(railName(site), mesh: rails.build(device: device, label: "tide gauge rails \(site)"), uniforms: ObjectUniforms(model: translation(SIMD3(f.x, 0, f.z)), emissive: SIMD4(litEmissive, idleEmissive)))
            scene.colliders.addCylinder(center: SIMD2(f.x, f.z), radius: steleWidth / 2 - 0.4, minY: base, maxY: top)
        }
    }

    private static func show(_ scene: Scene, _ site: Int, _ k: Int, glow: Float) {
        scene.update(name(site, k)) { $0.uniforms.emissive = SIMD4(litEmissive, idleEmissive + (litStrength - idleEmissive) * min(max(glow, 0), 1)) }
    }

    /// Builder B's call: hold bar k lit at `lit` (0...1) on both gauges, or on `site` alone, until it is set to 0. Unknown k or site is ignored.
    static func set(_ scene: Scene, _ k: Int, lit: Float, site: Int? = nil) {
        guard (0..<count).contains(k), site == nil || (0..<sites).contains(site!) else { return }
        let st = scene.archive
        for s in (site.map { [$0] } ?? Array(0..<sites)) { st.markHeld[s][k] = min(max(lit, 0), 1) }
        refresh(scene)
    }

    /// Called every tick from `ArchiveProps.update`: ages each bar's pulse, restarts it when the water crossed the bar since the last clock, and writes the glow (only when it changed).
    static func update(_ scene: Scene, from previous: Float?, to time: Float, dt: Float) {
        let st = scene.archive
        for k in 0..<count {
            if let p = previous, crossed(k, from: p, to: time) { st.markAge[k] = 0 } else { st.markAge[k] += dt }
        }
        refresh(scene)
    }
    static func refresh(_ scene: Scene) {
        let st = scene.archive
        for s in 0..<sites { for k in 0..<count {
            let g = max(pulse(age: st.markAge[k]), st.markHeld[s][k])
            if abs(g - st.markShown[s][k]) > 0.004 { st.markShown[s][k] = g; show(scene, s, k, glow: g) }
        } }
    }
}
