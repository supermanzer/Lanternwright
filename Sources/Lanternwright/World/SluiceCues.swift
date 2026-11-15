import Metal
import simd

/// A6 (Q84, builder A): what a player at a sluice room can READ while the room waits for the water.
///  - `SluiceLines`: in each room, a bright brass LINE at the sea height where the pipe's tone agrees with the stone's (`IlseTones.matchLevel`, in metres) on both gate piers, and the same line across the pipe's
///    back plate (`BellPipes`, at the same share of the column). The water in the room reaches the pier line at the moment the pipe's water reaches its plate line, and that is the crossing the gate answers.
///  - `WadeLamps`: a lamp on a post at each room's north rim, on ground above the highest sea (the side the path comes from), in the gate's colour: lit while the room is WADEABLE (the water over its floor is under knee depth,
///    `Tide.isWadeable`: the stone room only near low water), dark while the tide has flooded it. `ArchiveProps.update` drives it from the tide clock, the same function builder B's rule uses.
enum SluiceLines {
    static func name(_ k: Int) -> String { "ta_sluice_line_\(k)" }
    static let emissive = SIMD4<Float>(1.0, 0.95, 0.8, 0.9)
    /// Height of the line above the room's floor (m): the room is a pit in the sea's datum, so the line's world height is `TideMarks.height(k)`.
    static func aboveFloor(_ k: Int) -> Float { TideMarks.height(k) - ArchiveLayout.sluiceFloors[k] }
    static func add(to scene: Scene, device: MTLDevice) {
        let gapHalf: Float = 1.1
        for k in 0..<3 {
            var m = MeshBuilder()
            let y = aboveFloor(k)
            let pale = Surface(color: SIMD3(0.97, 0.95, 0.85), roughness: 0.6, material: .dressed)
            for sx: Float in [-1, 1] {       // a dark outline (stands off the painted band) with a pale glowing core
                m.box(size: SIMD3(0.9, 0.24, 0.05), surface: ArchiveProps.iron, transform: translation(SIMD3(sx * (gapHalf + 0.45), y, 0.5)))
                m.box(size: SIMD3(0.84, 0.12, 0.06), surface: pale, transform: translation(SIMD3(sx * (gapHalf + 0.45), y, 0.52)))
            }          // on the piers' south face, over the painted band
            let p = ArchiveLayout.pipeOffset, share = IlseTones.matchLevel(k)
            m.box(size: SIMD3(0.5, 0.09, 0.05), surface: pale, transform: translation(p + SIMD3(0, BellPipes.columnFoot + BellPipes.columnHeight * share, -0.27)))          // the pipe's back plate
            scene.add(name(k), mesh: m.build(device: device, label: "sluice line \(k)"), uniforms: ObjectUniforms(model: translation(ArchiveLayout.sluices[k]), emissive: emissive))
        }
    }
}

enum WadeLamps {
    static func name(_ k: Int) -> String { "ta_wade_lamp_\(k)" }
    static func glowName(_ k: Int) -> String { "ta_wade_lamp_glow_\(k)" }
    /// The post's offset from the room's centre (north, toward the landing) and the lamp's height above its ground.
    static let offset = SIMD2<Float>(0, -15.5), postHeight: Float = 2.2
    static func position(_ k: Int, terrain: Terrain) -> SIMD3<Float> {
        let s = ArchiveLayout.sluices[k], x = s.x + offset.x, z = s.z + offset.y
        return SIMD3(x, terrain.sampleHeight(x: x, z: z), z)
    }
    /// True while room k can be waded at clock `t` (the same function the movement uses).
    static func lit(_ k: Int, clock t: Float) -> Bool { Tide.isWadeable(ground: ArchiveLayout.sluiceFloors[k], time: t) }
    static let litEmissive: Float = 3.2, darkEmissive: Float = 0.2
    /// A7: the lamp's meaning is in its colour, not the gate's: warm green = safe to wade, a dim ember = wait.
    static let litColour = SIMD3<Float>(0.55, 1.0, 0.35), darkColour = SIMD3<Float>(0.6, 0.12, 0.05)
    static func emissive(lit on: Bool) -> SIMD4<Float> { SIMD4(on ? litColour : darkColour, on ? litEmissive : darkEmissive) }

    static func add(to scene: Scene, device: MTLDevice) {
        let stone = Surface(color: SIMD3(0.42, 0.45, 0.45), roughness: 0.88, material: .dressed)
        for k in 0..<3 {
            let p = position(k, terrain: scene.terrain)
            var m = MeshBuilder()
            m.chamferBox(size: SIMD3(0.7, 0.35, 0.7), chamfer: 0.04, surface: stone, transform: translation(SIMD3(0, 0.1, 0)))
            m.chamferBox(size: SIMD3(0.22, postHeight + 0.24, 0.22), chamfer: 0.02, surface: stone, transform: translation(SIMD3(0, postHeight / 2 - 0.08, 0)))          // (A7: the post reaches the cage's base; it stopped 0.24 m short and the lantern floated)
            m.chamferBox(size: SIMD3(0.62, 0.08, 0.62), chamfer: 0.02, surface: ArchiveProps.iron, transform: translation(SIMD3(0, postHeight + 0.08, 0)))
            m.chamferBox(size: SIMD3(0.62, 0.08, 0.62), chamfer: 0.02, surface: ArchiveProps.iron, transform: translation(SIMD3(0, postHeight + 0.62, 0)))
            for dx: Float in [-1, 1] { for dz: Float in [-1, 1] { m.box(size: SIMD3(0.05, 0.6, 0.05), surface: ArchiveProps.iron, transform: translation(SIMD3(dx * 0.28, postHeight + 0.35, dz * 0.28))) } }
            scene.add(name(k), mesh: m.build(device: device, label: "sluice lamp \(k)"), uniforms: ObjectUniforms(model: translation(p)))
            var g = MeshBuilder()
            g.chamferBox(size: SIMD3(0.46, 0.46, 0.46), chamfer: 0.03, surface: Surface(color: SIMD3(0.12, 0.12, 0.12), roughness: 0.2, material: .emissiveGlass), transform: translation(SIMD3(0, postHeight + 0.35, 0)))
            scene.add(glowName(k), mesh: g.build(device: device, label: "sluice lamp glow \(k)"), uniforms: ObjectUniforms(model: translation(p), emissive: emissive(lit: false)))
            scene.colliders.addCylinder(center: SIMD2(p.x, p.z), radius: 0.4, minY: p.y - 0.5, maxY: p.y + postHeight + 1)
        }
    }

    /// Called every tick from `ArchiveProps.update`: lights each room's lamp while the room is wadeable at `clock` (writes only on a change).
    static func update(_ scene: Scene, clock: Float) {
        let st = scene.archive
        for k in 0..<3 {
            let on = lit(k, clock: clock)
            if st.lampLit[k] != on { st.lampLit[k] = on; scene.update(glowName(k)) { $0.uniforms.emissive = emissive(lit: on) } }
        }
    }
}
