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
        addLighthouse(scene, device: device)
        for id in StoneID.allCases { addStone(id, scene: scene, device: device) }
    }

    // MARK: Dock

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
        var z: Float = 0.15
        var k: Int32 = 0
        while z < len - 0.1 {
            let tone = 0.78 + 0.44 * Island.noise.unit(k, 91)
            let plank = Surface(color: SIMD3(0.30, 0.20, 0.115) * tone, roughness: 0.85)
            b.box(size: SIMD3(width, 0.07, 0.24), surface: plank, transform: translation(SIMD3(0, deckY(z) - 0.035, z)) * tilt)
            z += pitch; k += 1
        }
        let beam = Surface(color: SIMD3(0.16, 0.11, 0.07), roughness: 0.9)
        for sx: Float in [-0.95, 0.95] {
            b.box(size: SIMD3(0.14, 0.16, len), surface: beam,
                  transform: translation(SIMD3(sx, (deckY(0) + deckY(len)) / 2 - 0.16, len / 2)) * rotationX(-atan(slope)))
        }
        // Piles every 4 m on both sides, reaching well below the water; every other one stands above the deck.
        var pz: Float = 0.8, idx = 0
        while pz < len {
            for sx: Float in [-1.1, 1.1] {
                let top = deckY(pz) + (idx % 2 == 0 ? 0.55 : -0.12)
                b.cylinder(radiusTop: 0.10, radiusBottom: 0.12, height: top + 3.0, segments: 7, surface: beam,
                           transform: translation(SIMD3(sx, -3.0, pz)))
            }
            pz += 4; idx += 1
        }
        scene.add("dock", mesh: b.build(device: device, label: "dock"), uniforms: ObjectUniforms(model: model))
    }

    // MARK: Lighthouse

    static let lighthouseTop: Float = 30

    static func addLighthouse(_ scene: Scene, device: MTLDevice) {
        let lh = Layout.lighthouse
        let white = Surface(color: SIMD3(0.60, 0.575, 0.53), roughness: 0.85)
        let red = Surface(color: SIMD3(0.42, 0.085, 0.06), roughness: 0.85)
        let dark = Surface(color: SIMD3(0.05, 0.045, 0.04), roughness: 0.6)
        let iron = Surface(color: SIMD3(0.08, 0.08, 0.09), roughness: 0.5)
        var b = MeshBuilder()
        b.cylinder(radiusTop: 5.0, radiusBottom: 5.3, height: 1.4, segments: 8, smooth: false, surface: Surface(color: SIMD3(0.33, 0.31, 0.28), roughness: 0.9),
                   transform: translation(SIMD3(0, -0.4, 0)))
        // Tower: stacked frusta of one continuous taper (r 4.2 -> 2.8 over 24 m), banded white / red / white / red.
        let bands: [(h: Float, s: Surface)] = [(7, white), (5, red), (7, white), (5, red)]
        var y: Float = 1.0
        for band in bands {
            let r0 = 4.2 - 1.4 * (y - 1) / 24, r1 = 4.2 - 1.4 * (y - 1 + band.h) / 24
            b.cylinder(radiusTop: r1, radiusBottom: r0, height: band.h, segments: 8, smooth: false, surface: band.s,
                       transform: translation(SIMD3(0, y, 0)))
            y += band.h
        }
        // y is now 25: gallery deck and rail.
        b.cylinder(radiusTop: 3.9, radiusBottom: 3.5, height: 0.4, segments: 8, smooth: false, surface: white, transform: translation(SIMD3(0, 24.8, 0)))
        for i in 0..<16 {
            let a = Float(i) / 16 * 2 * .pi
            b.cylinder(radiusTop: 0.04, radiusBottom: 0.05, height: 1.0, segments: 5, surface: iron,
                       transform: translation(SIMD3(3.75 * cos(a), 25.2, 3.75 * sin(a))))
        }
        b.torus(major: 3.75, minor: 0.05, segments: 24, sides: 5, surface: iron, transform: translation(SIMD3(0, 26.2, 0)))
        // Lantern room frame: 8 thin pillars around the glass, a roof dome and a finial.
        for i in 0..<8 {
            let a = (Float(i) + 0.5) / 8 * 2 * .pi
            b.box(size: SIMD3(0.18, 3.4, 0.18), surface: iron, transform: translation(SIMD3(2.15 * cos(a), 27.0, 2.15 * sin(a))))
        }
        b.cylinder(radiusTop: 2.4, radiusBottom: 2.5, height: 0.35, segments: 8, smooth: false, surface: iron, transform: translation(SIMD3(0, 25.2, 0)))
        b.cone(radius: 3.0, height: 2.0, segments: 8, smooth: false, surface: red, transform: translation(SIMD3(0, 28.7, 0)))
        b.sphere(radius: 0.22, segments: 8, surface: iron, transform: translation(SIMD3(0, 30.8, 0)))
        // Door (south face, +Z, toward the approaching player) with a stone surround, and three dark windows.
        b.box(size: SIMD3(1.9, 3.1, 0.5), surface: Surface(color: SIMD3(0.40, 0.38, 0.34), roughness: 0.9), transform: translation(SIMD3(0, 1.55, 4.15)))
        b.box(size: SIMD3(1.4, 2.6, 0.5), surface: Surface(color: SIMD3(0.16, 0.10, 0.06), roughness: 0.8), transform: translation(SIMD3(0, 1.3, 4.25)))
        for wy: Float in [9, 15, 21] {
            let r = 4.2 - 1.4 * (wy - 1) / 24
            b.box(size: SIMD3(0.7, 1.1, 0.4), surface: dark, transform: translation(SIMD3(0, wy, r - 0.1)))
        }
        scene.add("lighthouse", mesh: b.build(device: device, label: "lighthouse"),
                  uniforms: ObjectUniforms(model: translation(lh)))

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
        let basalt = Surface(color: SIMD3(0.075, 0.08, 0.09), roughness: 0.5)

        var body = MeshBuilder()
        body.box(size: SIMD3(1.3, stoneHeight, 0.85), surface: basalt, transform: translation(SIMD3(0, stoneHeight / 2 - 0.1, 0)))
        body.box(size: SIMD3(1.12, 0.3, 0.7), surface: basalt, transform: translation(SIMD3(0.03, stoneHeight - 0.05, 0)) * rotationY(0.14))
        body.box(size: SIMD3(1.9, 0.25, 1.5), surface: Surface(color: SIMD3(0.20, 0.19, 0.17), roughness: 0.85), transform: translation(SIMD3(0, 0.05, 0)))
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
