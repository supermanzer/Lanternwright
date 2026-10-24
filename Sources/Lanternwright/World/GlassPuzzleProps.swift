import Metal
import simd

/// The physical things of the Glass Wood's puzzles: the mirror court, the mural, journal pages.
enum GlassPuzzleProps {
    static let beamHeight: Float = 1.25
    static let beamSegments = 16
    static let moonlight = SIMD3<Float>(0.85, 0.92, 1.0)

    /// Colour of pane/beam colour index 0...2: the same colours as the Varrow stones (tide cyan, wind green, stone amber).
    static func color(_ index: Int) -> SIMD3<Float> {
        index < 0 ? moonlight : StoneID.allCases[index % 3].color
    }

    /// Beams are thin and bright, so they wash out toward white. Squaring the channels deepens the hue (cyan -> blue-cyan,
    /// amber -> orange) so the colour a pane gives the light is still readable after tonemapping and bloom.
    static func beamColor(_ index: Int) -> SIMD3<Float> {
        let c = color(index)
        return c * c * 1.5
    }

    static func populate(_ scene: Scene, device: MTLDevice) {
        addMirrorCourt(scene, device: device)
        addPages(scene, device: device)
    }

    // MARK: Mirror court

    /// Which way a pane faces: panes stand across the beam, so a pane on an east-west beam is turned a quarter.
    static let paneYaw: [Float] = [.pi / 2, 0, .pi / 2]

    static func mirrorPosition(_ k: Int) -> SIMD3<Float> { MirrorCourt.world(MirrorCourt.mirrorCells[k]) }
    static func panePosition(_ k: Int) -> SIMD3<Float> { MirrorCourt.world(MirrorCourt.paneCells[k]) }

    static func mirrorModel(_ k: Int, turns: Float) -> float4x4 {
        // The plate's width runs along its local X; the line direction at angle a (from +x toward +z) needs yaw -a.
        translation(mirrorPosition(k) + SIMD3(0, 1.25, 0)) * rotationY(-turns * .pi / 4)
    }

    static func addMirrorCourt(_ scene: Scene, device: MTLDevice) {
        let stone = Surface(color: SIMD3(0.20, 0.21, 0.30), roughness: 0.45)
        var fixed = MeshBuilder()

        // Floor tiles mark the 5 x 5 grid so the court reads as a board.
        for c in 0..<MirrorCourt.size {
            for r in 0..<MirrorCourt.size {
                let w = MirrorCourt.world((c, r))
                let shade: Float = (c + r) % 2 == 0 ? 1.0 : 0.78
                fixed.box(size: SIMD3(MirrorCourt.cell - 0.35, 0.06, MirrorCourt.cell - 0.35),
                          surface: Surface(color: SIMD3(0.24, 0.25, 0.38) * shade, roughness: 0.35),
                          transform: translation(w - GlassLayout.mirrorCourt + SIMD3(0, 0.0, 0)))
            }
        }
        // Mirror posts and pane frames.
        for k in 0..<3 {
            let p = mirrorPosition(k) - GlassLayout.mirrorCourt
            fixed.cylinder(radiusTop: 0.10, radiusBottom: 0.16, height: 0.55, segments: 8, smooth: false, surface: stone, transform: translation(p))
            let q = panePosition(k) - GlassLayout.mirrorCourt
            let yaw = rotationY(paneYaw[k])
            for dx: Float in [-1.05, 1.05] {
                fixed.box(size: SIMD3(0.16, 2.5, 0.2), surface: stone, transform: translation(q + SIMD3(0, 1.25, 0)) * yaw * translation(SIMD3(dx, 0, 0)))
            }
            fixed.box(size: SIMD3(2.3, 0.16, 0.2), surface: stone, transform: translation(q + SIMD3(0, 2.5, 0)) * yaw)
            fixed.box(size: SIMD3(2.3, 0.16, 0.2), surface: stone, transform: translation(q + SIMD3(0, 0.05, 0)) * yaw)
        }
        // Receiver pedestal.
        let rp = MirrorCourt.world(MirrorCourt.receiver) - GlassLayout.mirrorCourt
        fixed.cylinder(radiusTop: 0.45, radiusBottom: 0.8, height: 1.0, segments: 8, smooth: false, surface: stone, transform: translation(rp))
        scene.add("gw_court", mesh: fixed.build(device: device, label: "court"), uniforms: ObjectUniforms(model: translation(GlassLayout.mirrorCourt)))

        // The moon-prism: a tall glowing crystal that always fires east.
        var prism = MeshBuilder()
        prism.cylinder(radiusTop: 0.05, radiusBottom: 0.5, height: 3.2, segments: 6, smooth: false, surface: Surface(color: SIMD3(0.85, 0.93, 1.0), roughness: 0.1))
        prism.cylinder(radiusTop: 0.6, radiusBottom: 0.6, height: 0.35, segments: 6, smooth: false, surface: stone, transform: translation(SIMD3(0, -0.1, 0)))
        scene.add("gw_source", mesh: prism.build(device: device, label: "prism"),
                  uniforms: ObjectUniforms(model: translation(MirrorCourt.world(MirrorCourt.source)), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(moonlight, 3.5)))

        // Mirrors (they turn) and panes (they change colour).
        var plate = MeshBuilder()
        plate.box(size: SIMD3(1.9, 1.7, 0.06), surface: Surface(color: SIMD3(0.9, 0.95, 1.0), roughness: 0.02, material: .emissiveGlass))
        for sx: Float in [-0.97, 0.97] { plate.box(size: SIMD3(0.07, 1.78, 0.12), surface: stone, transform: translation(SIMD3(sx, 0, 0))) }
        plate.box(size: SIMD3(2.0, 0.07, 0.12), surface: stone, transform: translation(SIMD3(0, 0.88, 0)))
        plate.box(size: SIMD3(2.0, 0.07, 0.12), surface: stone, transform: translation(SIMD3(0, -0.88, 0)))
        let plateMesh = plate.build(device: device, label: "mirror")
        var pane = MeshBuilder()
        pane.box(size: SIMD3(1.9, 2.3, 0.07), surface: Surface(color: SIMD3(0.32, 0.32, 0.32), roughness: 0.04, material: .emissiveGlass))
        let paneMesh = pane.build(device: device, label: "pane")
        for k in 0..<3 {
            scene.add("gw_mirror_\(k)", mesh: plateMesh,
                      uniforms: ObjectUniforms(model: mirrorModel(k, turns: Float(MirrorCourt.initialMirrors[k])), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.5, 0.6, 0.8, 0.5)))
            let col = color(MirrorCourt.initialPanes[k])
            scene.add("gw_pane_\(k)", mesh: paneMesh,
                      uniforms: ObjectUniforms(model: translation(panePosition(k) + SIMD3(0, 1.3, 0)) * rotationY(paneYaw[k]), tint: SIMD4(col, 1), emissive: SIMD4(col, 0.7)))
        }

        // The receiver orb, and the column of light it releases when the puzzle is solved.
        var orb = MeshBuilder()
        orb.sphere(radius: 0.42, segments: 16, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.05, material: .emissiveGlass))
        scene.add("gw_receiver", mesh: orb.build(device: device, label: "receiver"),
                  uniforms: ObjectUniforms(model: translation(MirrorCourt.world(MirrorCourt.receiver) + SIMD3(0, 1.45, 0)), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.3, 0.35, 0.45, 0.6)))
        var column = MeshBuilder()
        column.cylinder(radiusTop: 0.28, radiusBottom: 0.5, height: 1, segments: 10, smooth: true, caps: false, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.5))
        scene.add("gw_column", mesh: column.build(device: device, label: "column"),
                  uniforms: ObjectUniforms(model: translation(MirrorCourt.world(MirrorCourt.receiver)) * scaling(SIMD3(1, 0.001, 1)), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.9, 0.95, 1.0, 7)),
                  hidden: true)

        // Beam segments (reused each time the arrangement changes).
        var beam = MeshBuilder()
        beam.cylinder(radiusTop: 0.07, radiusBottom: 0.07, height: 1, segments: 8, smooth: true, caps: false, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.5))
        let beamMesh = beam.build(device: device, label: "mirror beam")
        for i in 0..<beamSegments {
            scene.add("gw_beam_\(i)", mesh: beamMesh, uniforms: ObjectUniforms(emissive: SIMD4(moonlight, 1.7)), hidden: true)
        }

        // The mural: three glyphs in the order the beam must meet its glass, on a wall facing the way the player arrives.
        let m = GlassLayout.mirrorCourt + SIMD3(0, 0, 12.5)
        var wall = MeshBuilder()
        wall.box(size: SIMD3(9, 3.4, 0.6), surface: Surface(color: SIMD3(0.12, 0.12, 0.2), roughness: 0.4), transform: translation(SIMD3(0, 1.7, 0)))
        wall.box(size: SIMD3(9.6, 0.3, 0.9), surface: stone, transform: translation(SIMD3(0, 3.5, 0)))
        wall.box(size: SIMD3(9.6, 0.3, 0.9), surface: stone, transform: translation(SIMD3(0, 0.1, 0)))
        scene.add("gw_mural", mesh: wall.build(device: device, label: "mural"), uniforms: ObjectUniforms(model: translation(m)))
        for (i, id) in StoneID.allCases.enumerated() {
            let g = Landmarks.glyphMesh(id, z: 0.33, y: 1.7, scale: 1.9)
            scene.add("gw_mural_glyph_\(i)", mesh: g.build(device: device, label: "mural glyph"),
                      uniforms: ObjectUniforms(model: translation(m + SIMD3((Float(i) - 1) * 2.9, 0, 0)), tint: SIMD4(id.color, 1), emissive: SIMD4(id.color, 0.9)))
        }
    }

    // MARK: Pages

    /// Oren's journal pages: 5 at the arrival pad, 6 at the receiver (appears when the mirrors are solved), 7 at the chime ring
    /// (when the chimes are solved), 8 at the altar (when both are).
    static func pagePosition(_ number: Int) -> SIMD3<Float> {
        switch number {
        case 5: return GlassLayout.arrival + SIMD3(2.3, 0.02, 1.2)
        case 6: return MirrorCourt.world(MirrorCourt.receiver) + SIMD3(1.5, 0.02, 0.6)
        case 7: return GlassLayout.chimeRing + SIMD3(0, 0.02, 4.2)
        default: return GlassLayout.altar + SIMD3(1.6, 0.02, 2.4)
        }
    }

    static func addPages(_ scene: Scene, device: MTLDevice) {
        var b = MeshBuilder()
        b.box(size: SIMD3(0.34, 0.012, 0.46), surface: Surface(color: SIMD3(0.85, 0.80, 0.66), roughness: 0.9))
        let mesh = b.build(device: device, label: "page")
        for n in 5...8 {
            let p = pagePosition(n)
            scene.add("page_\(n)", mesh: mesh,
                      uniforms: ObjectUniforms(model: translation(p) * rotationY(Island.noise.unit(Int32(n), 17) * 2 * .pi) * rotationX(0.04),
                                               tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.7, 0.9, 1.0, 0.35)),
                      hidden: n != 5)
        }
    }
}
