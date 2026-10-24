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
        // F01 W2: a deck that has stood in salt air for decades. Every board is different: width 0.15-0.27 m, gaps of 5-30 mm, a few millimetres of lift and
        // twist, cupped across its width, a bow along it; two boards are missing (the stringers and the water show), one is broken off short, one has been
        // replaced and is paler, the deck sags a little between piles. Board identity (0..1) goes into the vertex roughness channel, where the plank material
        // reads it as its seed (grain, knots, checks, tone); a value of exactly 1 marks the replacement.
        let n = Island.noise
        var z: Float = 0.12
        var k: Int32 = 0
        var missing: [Int32] = [], broken: Int32 = -1, replaced: Int32 = -1
        func plankCount() -> Int32 { var zz: Float = 0.12, kk: Int32 = 0; while zz < len - 0.1 { zz += 0.15 + 0.12 * n.unit(kk, 101) + 0.005 + 0.025 * n.unit(kk, 102); kk += 1 }; return kk }
        let total = plankCount()
        missing = [Int32(Float(total) * 0.37), Int32(Float(total) * 0.71)]
        broken = Int32(Float(total) * 0.52); replaced = Int32(Float(total) * 0.23)
        while z < len - 0.1 {
            let depth = 0.15 + 0.12 * n.unit(k, 101)                            // board width along the dock
            let gap = 0.005 + 0.025 * n.unit(k, 102)
            let seed = replaced == k ? 1.0 : min(n.unit(k, 103), 0.97)
            let zc = z + depth / 2
            if !missing.contains(k) {
                let tw = n.unit(k, 92) - 0.5, lift = (n.unit(k, 93) - 0.5) * 0.008
                var w = width - 0.04 * n.unit(k, 94) - (n.unit(k, 95) > 0.9 ? 0.08 : 0)
                var xoff: Float = (n.unit(k, 96) - 0.5) * 0.03
                if broken == k { w *= 0.55; xoff = 0.5 * (width - w) * (n.unit(k, 97) > 0.5 ? 1 : -1) * 0.9 }              // snapped off short
                let sag = -0.012 * sin(.pi * (zc / 4.0).truncatingRemainder(dividingBy: 1))                                   // between piles every 4 m
                let y = deckY(zc) + sag + lift
                let surf = Surface(color: (replaced == k ? SIMD3(0.46, 0.34, 0.20) : SIMD3(0.30, 0.20, 0.115)) * (0.8 + 0.4 * n.unit(k, 98)), roughness: seed, material: .plank)
                let m = translation(SIMD3(xoff, y, zc)) * tilt * rotationZ(tw * 0.02) * rotationX(tw * 0.02)
                // The body, and a cupped top (edges up by 2-4 mm: the board has dried and curled) on a 7 x 3 grid with smooth normals.
                let thick: Float = 0.045 + 0.012 * n.unit(k, 99)
                b.chamferBox(size: SIMD3(w, thick, depth), chamfer: 0.014 + 0.01 * n.unit(k, 104), surface: surf, transform: m * translation(SIMD3(0, -thick / 2 + 0.0015, 0)))
                let cup = 0.002 + 0.004 * n.unit(k, 105), bow = (n.unit(k, 106) - 0.5) * 0.006
                var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
                let nx = 8, nzz = 3
                func hgt(_ u: Float, _ v: Float) -> Float { cup * (v * v) + bow * (1 - u * u) }               // u along the board (-1...1), v across its width (-1...1)
                for j in 0...nzz { for i in 0...nx {
                    let u = Float(i) / Float(nx) * 2 - 1, v = Float(j) / Float(nzz) * 2 - 1
                    pos.append(SIMD3(u * w / 2 * 0.985, 0.0016 + hgt(u, v), v * depth / 2 * 0.97))
                    let e: Float = 0.05
                    nrm.append(simd_normalize(SIMD3(-(hgt(u + e, v) - hgt(u - e, v)) / (2 * e * w / 2), 1, -(hgt(u, v + e) - hgt(u, v - e)) / (2 * e * depth / 2))))
                } }
                for j in 0..<nzz { for i in 0..<nx {
                    let a = UInt32(j * (nx + 1) + i), bb = a + 1, c = a + UInt32(nx + 1), d = c + 1
                    idx += [a, c, d, a, d, bb]
                } }
                b.addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: surf, transform: m)
                // Nail heads: size and presence vary, some are bent (tilted), some missing; two per end over each beam.
                for sx: Float in [-0.95, 0.95] {
                    for dz: Float in [-1, 1] where n.unit(k * 8 + Int32(dz + 1) + (sx > 0 ? 4 : 0), 107) > 0.18 && abs(sx + xoff) < w / 2 {
                        let rr = 0.006 + 0.006 * n.unit(k * 8 + Int32(dz + 1), 108)
                        let bent = (n.unit(k * 8 + Int32(dz + 1) + 2, 109) - 0.5) * 0.7
                        b.cylinder(radiusTop: rr, radiusBottom: rr * 1.15, height: 0.007, segments: 6, smooth: false, surface: iron,
                                   transform: m * translation(SIMD3(sx - xoff, 0.003 + cup * 0.5, dz * depth * 0.30)) * rotationZ(bent) * rotationX(bent * 0.6))
                    }
                }
            }
            z += depth + gap; k += 1
        }
        // Stringers (the two beams the boards are nailed to, with a notch of rot at one end) and cross-beams every 1.1 m that show through the gaps and missing boards.
        for sx: Float in [-0.95, 0.95] {
            b.box(size: SIMD3(0.14, 0.16, len), surface: timber,
                  transform: translation(SIMD3(sx, (deckY(0) + deckY(len)) / 2 - 0.16, len / 2)) * rotationX(-atan(slope)))
        }
        var cz: Float = 0.5, ci: Int32 = 0
        while cz < len {
            b.box(size: SIMD3(2.3, 0.10, 0.12), surface: timber, transform: translation(SIMD3((n.unit(ci, 111) - 0.5) * 0.04, deckY(cz) - 0.15 - 0.008 * n.unit(ci, 112), cz)) * tilt * rotationY((n.unit(ci, 113) - 0.5) * 0.02))
            cz += 1.1; ci += 1
        }
        // Piles every 4 m on both sides, reaching well below the water; every other one stands above the deck as a mooring post with
        // a coil of rope, a cap, and an iron cleat on the nearest beam.
        var pz: Float = 0.8, idx = 0
        while pz < len {
            for sx: Float in [-1.1, 1.1] {
                let post = idx % 2 == 0
                let top = deckY(pz) + (post ? 0.55 : -0.12)
                let lean = (Island.noise.unit(Int32(idx * 2) + (sx > 0 ? 1 : 0), 120) - 0.5) * 0.05
                b.cylinder(radiusTop: 0.10, radiusBottom: 0.12, height: top + 3.0, segments: 10, surface: timber, transform: translation(SIMD3(sx, -3.0, pz)) * rotationZ(lean) * rotationX(lean * 0.6))
                if !post {                                                                         // a split, ragged top: two uneven splinters
                    for q in 0..<3 { b.box(size: SIMD3(0.04, 0.05 + 0.08 * Island.noise.unit(Int32(idx) * 3 + Int32(q), 121), 0.07), surface: timber, transform: translation(SIMD3(sx + (Float(q) - 1) * 0.05, top + 0.02, pz + (Island.noise.unit(Int32(idx) * 3 + Int32(q), 122) - 0.5) * 0.06)) * rotationY(Float(q))) }
                }
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

        // The plinth and the top block are plain dressed stone; the face is its own object (material 14) so only it carries the glyph glow.
        var body = MeshBuilder()
        body.chamferBox(size: SIMD3(1.12, 0.3, 0.7), chamfer: 0.05, surface: Surface(color: SIMD3(0.30, 0.31, 0.34), roughness: 0.75, material: .dressed), transform: translation(SIMD3(0.03, stoneHeight - 0.05, 0)) * rotationY(0.14))
        body.chamferBox(size: SIMD3(1.9, 0.25, 1.5), chamfer: 0.05, surface: Surface(color: SIMD3(0.40, 0.38, 0.35), roughness: 0.85, material: .dressed), transform: translation(SIMD3(0, 0.05, 0)))
        scene.add("stone_\(id.name)", mesh: body.build(device: device, label: "stone_\(id.name)"), uniforms: ObjectUniforms(model: model))

        // The face: the glyph (tide = three waves, wind = two diagonals, summit = a square) and the rank notches (1, 2 or 3 low on the
        // face = how near the sky this stone stands: with the journal's "each stone a little nearer the sky than the last" the order is
        // deduced, not read out) are carved by the shader (carve_glyph). Pulse and lit state drive the object's emissive strength.
        var face = MeshBuilder()
        face.chamferBox(size: SIMD3(1.3, stoneHeight, 0.85), chamfer: 0.06, surface: Surface(color: SIMD3(0.30, 0.31, 0.34), roughness: 0.75, material: .glyphStone),
                        transform: translation(SIMD3(0, stoneHeight / 2 - 0.1, 0)))
        scene.add("stone_\(id.name)_face", mesh: face.build(device: device, label: "stone_face"),
                  uniforms: ObjectUniforms(model: model, tint: SIMD4(1, 1, 1, Float(id.rawValue)), emissive: SIMD4(id.color, 0.3)))

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
