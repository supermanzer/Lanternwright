import Metal
import simd

enum StoneID: Int, CaseIterable {
    case tide, wind, summit

    var name: String { ["tide", "wind", "stone"][rawValue] }
    var position: SIMD3<Float> { [Layout.tideStone, Layout.windStone, Layout.summitStone][rawValue] }
    /// Glyph/capstone colour: tide = cyan, wind = pale green, stone = amber.
    var color: SIMD3<Float> { [SIMD3(0.3, 0.8, 1.0), SIMD3(0.7, 1.0, 0.8), SIMD3(1.0, 0.7, 0.3)][rawValue] }
    /// Where the player arrives from, so the stone can face them.
    var approachFrom: SIMD3<Float> { [Layout.dockShore, Layout.tideStone, Layout.windStone][rawValue] }
    static let height: Float = 3.0
}

/// The big hand-built structures: dock, lighthouse, resonance stones.
enum Landmarks {
    static let stoneHeight = StoneID.height

    static func populate(_ scene: Scene, device: MTLDevice) {
        addDock(scene, device: device)
        addBuoy(scene, device: device)
        addLighthouse(scene, device: device)
        for id in StoneID.allCases { addStone(id, scene: scene, device: device) }
    }

    // MARK: Dock

    /// A red bell buoy riding at sea; `Game` bobs it with the swell. Its bell is heard in `SonicLandmarks`.
    static func addBuoy(_ scene: Scene, device: MTLDevice) {
        let red = Surface(color: SIMD3(0.62, 0.08, 0.06), roughness: 0.5)
        let iron = Surface(color: SIMD3(0.10, 0.10, 0.11), roughness: 0.5)
        var b = MeshBuilder()
        b.cylinder(radiusTop: 0.55, radiusBottom: 0.9, height: 0.9, segments: 10, surface: red, transform: translation(SIMD3(0, -0.45, 0)))
        b.cylinder(radiusTop: 0.12, radiusBottom: 0.2, height: 1.6, segments: 8, surface: iron, transform: translation(SIMD3(0, 0.4, 0)))
        for i in 0..<4 {                                       // the bell cage: four struts and a cap
            let a = Float(i) / 4 * 2 * .pi + 0.4
            b.cylinder(radiusTop: 0.025, radiusBottom: 0.03, height: 0.9, segments: 4, surface: iron, transform: translation(SIMD3(0.3 * cos(a), 0.4, 0.3 * sin(a))))
        }
        b.cone(radius: 0.38, height: 0.35, segments: 8, surface: red, transform: translation(SIMD3(0, 1.3, 0)))
        scene.add("buoy", mesh: b.build(device: device, label: "buoy"), uniforms: ObjectUniforms(model: translation(Layout.buoy)))
    }

    static func addDock(_ scene: Scene, device: MTLDevice) {
        let strip = Layout.dockStrip()
        let ab = strip.b - strip.a
        let len = length(ab), dir = ab / len
        let slope = (strip.y1 - strip.y0) / len
        let angle = atan2(dir.x, dir.y)
        let tilt = rotationX(-atan(slope))
        let model = translation(SIMD3(strip.a.x, 0, strip.a.y)) * rotationY(angle)
        func deckY(_ z: Float) -> Float { strip.y0 + slope * z }

        var b = MeshBuilder()
        let width: Float = 2.4
        let pitch: Float = 0.275
        let deck = Surface(color: SIMD3(0.30, 0.20, 0.115), roughness: 0.85, material: .plank)
        let timber = Surface(color: SIMD3(0.20, 0.14, 0.09), roughness: 0.9, material: .timber)
        let iron = Surface(color: SIMD3(0.16, 0.15, 0.14), roughness: 0.5, material: .iron)
        let rope = Surface(color: SIMD3(0.46, 0.38, 0.26), roughness: 1.0)
        var z: Float = 0.15
        var k: Int32 = 0
        while z < len - 0.1 {
            // Each board sits a little differently: a hair of twist, a few millimetres up or down, a slightly different length.
            let tw = Island.noise.unit(k, 92) - 0.5, lift = (Island.noise.unit(k, 93) - 0.5) * 0.006
            let w = width - 0.03 * Island.noise.unit(k, 94)
            b.chamferBox(size: SIMD3(w, 0.07, 0.24), chamfer: 0.012, surface: deck,
                         transform: translation(SIMD3(0, deckY(z) - 0.035 + lift, z)) * tilt * rotationZ(tw * 0.015) * rotationX(tw * 0.012))
            // Four nail heads per board, two at each end over the beams.
            for sx: Float in [-0.95, -0.80, 0.80, 0.95] {
                for dz: Float in [-0.06, 0.06] where abs(sx) > 0.9 || dz > 0 {
                    b.cylinder(radiusTop: 0.008, radiusBottom: 0.009, height: 0.006, segments: 6, smooth: false, surface: iron,
                               transform: translation(SIMD3(sx, deckY(z) + lift + 0.002, z + dz)) * tilt)
                }
            }
            z += pitch; k += 1
        }
        for sx: Float in [-0.95, 0.95] {
            b.box(size: SIMD3(0.14, 0.16, len), surface: timber,
                  transform: translation(SIMD3(sx, (deckY(0) + deckY(len)) / 2 - 0.16, len / 2)) * rotationX(-atan(slope)))
        }
        // Piles every 4 m on both sides, reaching well below the water; every other one stands above the deck as a mooring post with
        // a coil of rope, a cap, and an iron cleat on the nearest beam.
        var pz: Float = 0.8, idx = 0
        while pz < len {
            for sx: Float in [-1.1, 1.1] {
                let post = idx % 2 == 0
                let top = deckY(pz) + (post ? 0.55 : -0.12)
                b.cylinder(radiusTop: 0.10, radiusBottom: 0.12, height: top + 3.0, segments: 10, surface: timber, transform: translation(SIMD3(sx, -3.0, pz)))
                if post {
                    b.cylinder(radiusTop: 0.085, radiusBottom: 0.108, height: 0.05, segments: 10, smooth: false, surface: timber, transform: translation(SIMD3(sx, top, pz)))
                    for c in 0..<4 {
                        b.torus(major: 0.125, minor: 0.017, segments: 16, sides: 5, surface: rope,
                                transform: translation(SIMD3(sx, top - 0.10 - 0.034 * Float(c), pz)) * rotationY(Float(c) * 0.4))
                    }
                    let side: Float = sx < 0 ? 1 : -1
                    b.chamferBox(size: SIMD3(0.07, 0.04, 0.22), chamfer: 0.008, surface: iron,
                                 transform: translation(SIMD3(sx + side * 0.24, deckY(pz) - 0.02, pz)) * tilt)                        // a cleat on the deck edge
                }
            }
            pz += 4; idx += 1
        }
        scene.add("dock", mesh: b.build(device: device, label: "dock"), uniforms: ObjectUniforms(model: model))
    }

    // MARK: Lighthouse

    static let lighthouseTop: Float = 30

    static func addLighthouse(_ scene: Scene, device: MTLDevice) {
        let lh = Layout.lighthouse
        Lighthouse.build(into: scene, device: device)

        // Glass of the lantern room (material 2: glossy; it glows once the lighthouse is lit).
        var glass = MeshBuilder()
        glass.cylinder(radiusTop: 2.1, radiusBottom: 2.1, height: 3.2, segments: 16, smooth: true, caps: false,
                       surface: Surface(color: SIMD3(0.35, 0.42, 0.45), roughness: 0.05, material: .emissiveGlass),
                       transform: translation(SIMD3(0, 25.4, 0)))
        scene.add("lighthouse_glass", mesh: glass.build(device: device, label: "lighthouse_glass"), uniforms: ObjectUniforms(model: translation(lh)))

        // The lens: dark until the puzzle is solved, then blazing.
        var lens = MeshBuilder()
        lens.sphere(radius: 0.85, segments: 16, surface: Surface(color: SIMD3(0.8, 0.75, 0.6), roughness: 0.2), transform: translation(SIMD3(0, 26.9, 0)))
        scene.add("lighthouse_lens", mesh: lens.build(device: device, label: "lens"), uniforms: ObjectUniforms(model: translation(lh)))
    }

    // MARK: Resonance stones

    /// World position of the lens (where the beams converge).
    static var lensPosition: SIMD3<Float> { Layout.lighthouse + SIMD3(0, 26.9, 0) }
    /// Capstone rest position for a stone (it rises and bobs when lit).
    static func capstoneBase(_ id: StoneID) -> SIMD3<Float> { id.position + SIMD3(0, stoneHeight + 0.7, 0) }

    static func addStone(_ id: StoneID, scene: Scene, device: MTLDevice) {
        let p = id.position
        let from = id.approachFrom
        // Face the way the player arrives from: local +Z points toward the previous waypoint.
        let toward = SIMD2(from.x - p.x, from.z - p.z)
        let yaw = atan2(toward.x, toward.y)
        let model = translation(p) * rotationY(yaw)
        let basalt = Surface(color: SIMD3(0.30, 0.31, 0.34), roughness: 0.75, material: .dressed)

        var body = MeshBuilder()
        body.chamferBox(size: SIMD3(1.3, stoneHeight, 0.85), chamfer: 0.06, surface: basalt, transform: translation(SIMD3(0, stoneHeight / 2 - 0.1, 0)))
        body.chamferBox(size: SIMD3(1.12, 0.3, 0.7), chamfer: 0.05, surface: basalt, transform: translation(SIMD3(0.03, stoneHeight - 0.05, 0)) * rotationY(0.14))
        body.chamferBox(size: SIMD3(1.9, 0.25, 1.5), chamfer: 0.05, surface: Surface(color: SIMD3(0.40, 0.38, 0.35), roughness: 0.85, material: .dressed), transform: translation(SIMD3(0, 0.05, 0)))
        // Rank marks: 1, 2 or 3 notches low on the arrival face = how near the sky this stone stands (tide 1, wind 2, stone 3).
        // With the journal's "each stone a little nearer the sky than the last" the order is deduced, not read out.
        let rank = id.rawValue + 1
        for i in 0..<rank {
            body.box(size: SIMD3(0.07, 0.30, 0.05), surface: Surface(color: SIMD3(0.30, 0.31, 0.36), roughness: 0.4),
                     transform: translation(SIMD3((Float(i) - Float(rank - 1) / 2) * 0.17, 0.62, 0.43)))
        }
        scene.add("stone_\(id.name)", mesh: body.build(device: device, label: "stone_\(id.name)"), uniforms: ObjectUniforms(model: model))

        let g = glyphMesh(id, z: 0.435, y: 1.55)
        let idle = SIMD4(id.color, 0.3)
        scene.add("glyph_\(id.name)", mesh: g.build(device: device, label: "glyph"),
                  uniforms: ObjectUniforms(model: model, tint: SIMD4(id.color, 1), emissive: idle))

        // Hovering capstone.
        var cap = MeshBuilder()
        cap.icosphere(subdivisions: 0, radius: { _ in 1 }, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.3),
                      transform: scaling(SIMD3(0.26, 0.38, 0.26)))
        scene.add("cap_\(id.name)", mesh: cap.build(device: device, label: "cap"),
                  uniforms: ObjectUniforms(model: translation(capstoneBase(id)), tint: SIMD4(id.color, 1), emissive: SIMD4(id.color, 0.5)))

        scene.colliders.addCylinder(center: SIMD2(p.x, p.z), radius: 0.85, minY: p.y - 1, maxY: p.y + stoneHeight)
    }

    /// The glyph for a stone, as thin raised bars/squares facing +Z at (0, y, z). Reused on the Glass Wood's murals so the
    /// player meets the same symbols in both worlds: tide = three waves, wind = two diagonals, stone = a solid square.
    static func glyphMesh(_ id: StoneID, z: Float, y: Float, scale: Float = 1) -> MeshBuilder {
        var g = MeshBuilder()
        let glow = Surface(color: SIMD3(1, 1, 1), roughness: 0.4)
        switch id {
        case .tide:
            let offsets: [Float] = [-0.07, 0.07, -0.07]
            for (i, dx) in offsets.enumerated() {
                g.box(size: SIMD3(0.62, 0.07, 0.03) * scale, surface: glow, transform: translation(SIMD3(dx, y + (0.24 - Float(i) * 0.24) * scale, z)))
            }
        case .wind:
            for dx: Float in [-0.17, 0.17] {
                g.box(size: SIMD3(0.07, 0.72, 0.03) * scale, surface: glow, transform: translation(SIMD3(dx * scale, y, z)) * rotationZ(0.6))
            }
        case .summit:
            g.box(size: SIMD3(0.48, 0.48, 0.03) * scale, surface: glow, transform: translation(SIMD3(0, y, z)))
        }
        return g
    }
}
