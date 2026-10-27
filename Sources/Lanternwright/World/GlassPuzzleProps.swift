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
        addChimeRing(scene, device: device)
        addAltar(scene, device: device)
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

    /// The Glass Wood's own material language: cold frosted stone (material 17), pale brushed metal (19), true mirrors (18).
    static func frost(_ tone: Float = 1) -> Surface { Surface(color: SIMD3(0.26, 0.27, 0.39) * tone, roughness: 0.6, material: .glassStone) }
    static let pale = Surface(color: SIMD3(0.62, 0.65, 0.76), roughness: 0.35, material: .paleMetal)

    static func addMirrorCourt(_ scene: Scene, device: MTLDevice) {
        let stone = frost()
        var fixed = MeshBuilder()

        // The court floor: inlaid slabs on a 5 x 5 grid with real joints between them, each a little different in tone and height; the
        // middle of the court is lighter (worn smooth by feet), and a raised kerb frames the whole board.
        let half = Float(MirrorCourt.size) * MirrorCourt.cell / 2
        for c in 0..<MirrorCourt.size {
            for r in 0..<MirrorCourt.size {
                let w = MirrorCourt.world((c, r))
                let k = Int32(c * 7 + r * 13)
                let centre = simd_length(SIMD2(w.x - GlassLayout.mirrorCourt.x, w.z - GlassLayout.mirrorCourt.z)) / half
                let tone: Float = ((c + r) % 2 == 0 ? 1.0 : 0.80) * (0.92 + 0.16 * Island.noise.unit(k, 5)) * (1.12 - 0.25 * min(centre, 1))
                let lift = (Island.noise.unit(k, 6) - 0.5) * 0.006
                fixed.chamferBox(size: SIMD3(MirrorCourt.cell - 0.14, 0.07, MirrorCourt.cell - 0.14), chamfer: 0.025, surface: frost(tone),
                                 transform: translation(w - GlassLayout.mirrorCourt + SIMD3(0, lift, 0)) * rotationY((Island.noise.unit(k, 7) - 0.5) * 0.006))
            }
        }
        for sgn: Float in [-1, 1] {
            fixed.chamferBox(size: SIMD3(half * 2 + 0.9, 0.12, 0.45), chamfer: 0.04, surface: frost(0.85), transform: translation(SIMD3(0, 0.02, sgn * (half + 0.22))))
            fixed.chamferBox(size: SIMD3(0.45, 0.12, half * 2 + 0.9), chamfer: 0.04, surface: frost(0.85), transform: translation(SIMD3(sgn * (half + 0.22), 0.02, 0)))
        }
        // Mirror stands: a base plate with a ring of eight detent marks (one per quarter-eighth turn: the mirror turns in 45 degree
        // steps), a post with a pivot collar. The turning part (see `plateMesh`) carries a pointer that sweeps over the marks.
        for k in 0..<3 {
            let p = mirrorPosition(k) - GlassLayout.mirrorCourt
            fixed.chamferBox(size: SIMD3(1.5, 0.10, 1.5), chamfer: 0.03, surface: frost(1.1), transform: translation(p + SIMD3(0, 0.08, 0)))
            fixed.torus(major: 0.58, minor: 0.018, segments: 24, sides: 6, surface: pale, transform: translation(p + SIMD3(0, 0.135, 0)))
            for d in 0..<8 {
                let a = Float(d) * .pi / 4
                fixed.chamferBox(size: SIMD3(0.07, 0.02, 0.16), chamfer: 0.005, surface: pale,
                                 transform: translation(p + SIMD3(cos(a) * 0.58, 0.14, sin(a) * 0.58)) * rotationY(-a))
            }
            fixed.cylinder(radiusTop: 0.10, radiusBottom: 0.16, height: 0.55, segments: 10, smooth: true, surface: stone, transform: translation(p + SIMD3(0, 0.13, 0)))
            fixed.torus(major: 0.17, minor: 0.04, segments: 18, sides: 6, surface: pale, transform: translation(p + SIMD3(0, 0.60, 0)))
            // The pane's stand: a plinth, frame members with chamfers and pins.
            let q = panePosition(k) - GlassLayout.mirrorCourt
            let yaw = rotationY(paneYaw[k])
            fixed.chamferBox(size: SIMD3(2.7, 0.12, 0.55), chamfer: 0.03, surface: frost(1.05), transform: translation(q + SIMD3(0, 0.04, 0)) * yaw)
            for dx: Float in [-1.05, 1.05] {
                fixed.chamferBox(size: SIMD3(0.16, 2.5, 0.2), chamfer: 0.03, surface: stone, transform: translation(q + SIMD3(0, 1.25, 0)) * yaw * translation(SIMD3(dx, 0, 0)))
            }
            fixed.chamferBox(size: SIMD3(2.3, 0.16, 0.2), chamfer: 0.03, surface: stone, transform: translation(q + SIMD3(0, 2.5, 0)) * yaw)
            fixed.chamferBox(size: SIMD3(2.3, 0.16, 0.2), chamfer: 0.03, surface: stone, transform: translation(q + SIMD3(0, 0.15, 0)) * yaw)
            for (dx, dy): (Float, Float) in [(-1.05, 0.5), (1.05, 0.5), (-1.05, 2.0), (1.05, 2.0)] {
                fixed.cylinder(radiusTop: 0.035, radiusBottom: 0.035, height: 0.03, segments: 8, smooth: true, surface: pale,
                               transform: translation(q + SIMD3(0, dy, 0)) * yaw * translation(SIMD3(dx, 0, 0.1)) * rotationX(.pi / 2))
            }
        }
        // Receiver pedestal: stepped, with an inlaid ring.
        let rp = MirrorCourt.world(MirrorCourt.receiver) - GlassLayout.mirrorCourt
        fixed.lathe(profile: [SIMD2(0.95, 0), SIMD2(0.95, 0.14), SIMD2(0.80, 0.14), SIMD2(0.80, 0.24), SIMD2(0.52, 0.34), SIMD2(0.46, 0.95), SIMD2(0.60, 0.95), SIMD2(0.60, 1.02), SIMD2(0, 1.02)],
                    segments: 16, smooth: false, surface: stone, transform: translation(rp))
        fixed.torus(major: 0.70, minor: 0.02, segments: 24, sides: 6, surface: pale, transform: translation(rp + SIMD3(0, 0.245, 0)))
        scene.add("gw_court", mesh: fixed.build(device: device, label: "court"), uniforms: ObjectUniforms(model: translation(GlassLayout.mirrorCourt)))

        // The moon-prism: a tall glowing crystal that always fires east.
        var prism = MeshBuilder()
        prism.cylinder(radiusTop: 0.05, radiusBottom: 0.5, height: 3.2, segments: 6, smooth: false, surface: Surface(color: SIMD3(0.85, 0.93, 1.0), roughness: 0.1))
        prism.cylinder(radiusTop: 0.6, radiusBottom: 0.6, height: 0.35, segments: 6, smooth: false, surface: stone, transform: translation(SIMD3(0, -0.1, 0)))
        scene.add("gw_source", mesh: prism.build(device: device, label: "prism"),
                  uniforms: ObjectUniforms(model: translation(MirrorCourt.world(MirrorCourt.source)), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(moonlight, 3.5)))

        // Mirrors (they turn) and panes (they change colour). The mirror is a real mirror: a bevelled metal plate (material 18) that reflects
        // the sky, in a pale metal frame with corner bolts, on a yoke with a collar and a pointer that sweeps the base's detent marks.
        var plate = MeshBuilder()
        plate.chamferBox(size: SIMD3(1.84, 1.64, 0.05), chamfer: 0.02, surface: Surface(color: SIMD3(0.93, 0.96, 1.0), roughness: 0.03, material: .mirror))
        for sx: Float in [-0.97, 0.97] { plate.chamferBox(size: SIMD3(0.09, 1.8, 0.12), chamfer: 0.02, surface: pale, transform: translation(SIMD3(sx, 0, 0))) }
        for sy: Float in [-0.885, 0.885] { plate.chamferBox(size: SIMD3(2.04, 0.09, 0.12), chamfer: 0.02, surface: pale, transform: translation(SIMD3(0, sy, 0))) }
        for (bx, by): (Float, Float) in [(-0.97, -0.885), (0.97, -0.885), (-0.97, 0.885), (0.97, 0.885)] {
            plate.cylinder(radiusTop: 0.03, radiusBottom: 0.03, height: 0.03, segments: 8, smooth: true, surface: pale, transform: translation(SIMD3(bx, by, 0.06)) * rotationX(.pi / 2))
        }
        plate.cylinder(radiusTop: 0.04, radiusBottom: 0.04, height: 0.45, segments: 8, smooth: true, surface: pale, transform: translation(SIMD3(0, -1.25, 0)))      // yoke stem
        plate.cylinder(radiusTop: 0.20, radiusBottom: 0.20, height: 0.06, segments: 14, smooth: true, surface: pale, transform: translation(SIMD3(0, -1.0, 0)))
        plate.chamferBox(size: SIMD3(0.62, 0.03, 0.06), chamfer: 0.008, surface: pale, transform: translation(SIMD3(0.4, -1.0, 0)))                            // the pointer
        // R07-4: a thin bright edge catch along the inside of the frame, as light does on a bevel.
        for sx: Float in [-0.9, 0.9] { plate.box(size: SIMD3(0.012, 1.66, 0.052), surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.2, material: .emissiveGlass), transform: translation(SIMD3(sx, 0, 0.02))) }
        for sy: Float in [-0.83, 0.83] { plate.box(size: SIMD3(1.8, 0.012, 0.052), surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.2, material: .emissiveGlass), transform: translation(SIMD3(0, sy, 0.02))) }
        let plateMesh = plate.build(device: device, label: "mirror")
        var pane = MeshBuilder()
        // R07-3: a pane is coloured glass, not a rectangle: 9 cm thick with bevelled edges, drawn through the refractive pass so the court shows through it,
        // tinted by its current colour; a thin darker inner rim reads as the glass's edge; a state marker (see below) sits on its plinth.
        pane.chamferBox(size: SIMD3(1.9, 2.3, 0.09), chamfer: 0.035, surface: Surface(color: SIMD3(0.9, 0.9, 0.9), roughness: 0.04))
        for sx: Float in [-0.88, 0.88] { pane.chamferBox(size: SIMD3(0.05, 2.2, 0.10), chamfer: 0.012, surface: Surface(color: SIMD3(0.55, 0.55, 0.6), roughness: 0.04), transform: translation(SIMD3(sx, 0, 0))) }
        for sy: Float in [-1.08, 1.08] { pane.chamferBox(size: SIMD3(1.8, 0.05, 0.10), chamfer: 0.012, surface: Surface(color: SIMD3(0.55, 0.55, 0.6), roughness: 0.04), transform: translation(SIMD3(0, sy, 0))) }
        let paneMesh = pane.build(device: device, label: "pane")
        for k in 0..<3 {
            scene.add("gw_mirror_\(k)", mesh: plateMesh,
                      uniforms: ObjectUniforms(model: mirrorModel(k, turns: Float(MirrorCourt.initialMirrors[k])), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.55, 0.66, 0.9, 0.22)))       // R07-4: a faint moonlit sheen on the mirror (it reads as a mirror, not a grey panel)
            let col = color(MirrorCourt.initialPanes[k])
            scene.add("gw_pane_\(k)", mesh: paneMesh,
                      uniforms: ObjectUniforms(model: translation(panePosition(k) + SIMD3(0, 1.3, 0)) * rotationY(paneYaw[k]), tint: SIMD4(col, 1), emissive: SIMD4(col, 0.7)), refractive: true)
            var marker = MeshBuilder()
            marker.cylinder(radiusTop: 0.17, radiusBottom: 0.2, height: 0.05, segments: 20, smooth: true, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.3))
            marker.torus(major: 0.2, minor: 0.018, segments: 24, sides: 6, surface: pale, transform: translation(SIMD3(0, 0.03, 0)))
            scene.add("gw_pane_\(k)_marker", mesh: marker.build(device: device, label: "pane marker"),
                      uniforms: ObjectUniforms(model: translation(panePosition(k) + SIMD3(0, 0.17, 0)) * rotationY(paneYaw[k]) * translation(SIMD3(0, 0, 0.36)), tint: SIMD4(col, 1), emissive: SIMD4(col, 1.2)))
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
        addMural(scene, name: "gw_mural", model: translation(GlassLayout.mirrorCourt + SIMD3(0, 0, 12.5)), device: device)
    }

    /// A mural of the three resonance glyphs, as on the Varrow stones: a framed wall of frosted stone with three panels whose glyphs are
    /// carved channels with a glowing floor (material 20, the same shader as the stones). The wall faces local +Z.
    static func addMural(_ scene: Scene, name: String, model: float4x4, device: MTLDevice) {
        var wall = MeshBuilder()
        wall.chamferBox(size: SIMD3(9, 3.4, 0.6), chamfer: 0.05, surface: frost(0.8), transform: translation(SIMD3(0, 1.7, 0)))
        wall.chamferBox(size: SIMD3(9.6, 0.3, 0.9), chamfer: 0.06, surface: frost(1.05), transform: translation(SIMD3(0, 3.5, 0)))
        wall.chamferBox(size: SIMD3(9.6, 0.3, 0.9), chamfer: 0.06, surface: frost(1.05), transform: translation(SIMD3(0, 0.1, 0)))
        for x: Float in [-4.45, -1.45, 1.45, 4.45] {                                   // pilasters between the panels
            wall.chamferBox(size: SIMD3(0.32, 3.4, 0.78), chamfer: 0.05, surface: frost(1.1), transform: translation(SIMD3(x, 1.7, 0.06)))
        }
        scene.add(name, mesh: wall.build(device: device, label: name), uniforms: ObjectUniforms(model: model))
        for (i, id) in StoneID.allCases.enumerated() {
            var panel = MeshBuilder()
            panel.chamferBox(size: SIMD3(2.7, 2.7, 0.12), chamfer: 0.04, surface: Surface(color: SIMD3(0.20, 0.21, 0.32), roughness: 0.6, material: .glyphGlass),
                             transform: translation(SIMD3(0, 1.7, 0.33)))
            scene.add("\(name)_glyph_\(i)", mesh: panel.build(device: device, label: "mural panel"),
                      uniforms: ObjectUniforms(model: model * translation(SIMD3((Float(i) - 1) * 2.9, 0, 0)), tint: SIMD4(1, 1, 1, Float(id.rawValue) + 0.45), emissive: SIMD4(id.color, 0.9)))
        }
    }

    // MARK: Pages

    /// Oren's journal pages: 5 at the arrival pad, 6 at the receiver (appears when the mirrors are solved), 7 at the chime ring
    /// (when the chimes are solved), 8 at the altar (when both are).
    static func pageBase(_ number: Int) -> SIMD3<Float> {
        switch number {
        case 5: return GlassLayout.arrival + SIMD3(2.1, 0, 1.7)         // in the band between the arrival plate's inlaid rings (radii 2.2 and 3.15), clear of both
        case 6: return MirrorCourt.world(MirrorCourt.receiver) + SIMD3(1.9, 0, 0.9)
        case 7: return GlassLayout.chimeRing + SIMD3(0, 0, 4.6)
        default: return GlassLayout.altar + SIMD3(1.2, 0, 3.0)         // on the dais' top step, inside the glowing ring (F03 #51: the lectern had been set INTO the dais)
        }
    }
    /// The page's sheet origin, resting on the surface under it (F03 P1): ground, the arrival plate, or the altar dais' top step.
    static func pagePosition(_ number: Int, scene: Scene) -> SIMD3<Float> { pageLie(number, scene: scene).main.origin }
    static func pageLie(_ number: Int, scene: Scene) -> (main: DroppedPages.Lie, loose: [DroppedPages.Lie]) {
        let b = pageBase(number)
        return DroppedPages.lie(page: number, base: SIMD2(b.x, b.z), sheet: PuzzleProps.pageMesh().vertices.map { SIMD3($0.position.x, $0.position.y, $0.position.z) }, ground: { scene.groundHeight(x: $0, z: $1) })
    }

    static func addPages(_ scene: Scene, device: MTLDevice) {
        let mesh = PuzzleProps.pageMesh().build(device: device, label: "page")
        for n in 5...8 {
            let lie = pageLie(n, scene: scene)
            scene.add("page_\(n)", mesh: mesh, uniforms: ObjectUniforms(model: lie.main.model, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0, 0, 0, 0)), hidden: n != 5)
            for (k, l) in lie.loose.enumerated() {
                scene.add("page_loose_\(n)_\(k)", mesh: mesh, uniforms: ObjectUniforms(model: l.model, tint: SIMD4(0.82, 0.8, 0.86, 1), emissive: SIMD4(0, 0, 0, 0)), hidden: n != 5)
            }
        }
    }

    // MARK: Chime ring

    static let chimeCount = 5
    /// Heights shrink as the pitch rises (D4 longest, D5 shortest): the way a real glass chime or xylophone bar behaves.
    static let chimeHeights: [Float] = [3.5, 3.1, 2.75, 2.45, 2.2]
    static let chimeRadius: Float = 6.5

    static func chimePosition(_ k: Int) -> SIMD3<Float> {
        // An arc on the far side of the ring from where the path arrives, so you stand in the opening facing all five.
        let a = Float.pi / 4 + Float(k - 2) * 0.5
        let c = GlassLayout.chimeRing
        return SIMD3(c.x + chimeRadius * cos(a), c.y, c.z + chimeRadius * sin(a))
    }

    static func chimeModel(_ k: Int, swing: Float) -> float4x4 {
        // Swing about the axis tangent to the ring (a pendulum motion toward and away from the centre).
        let c = GlassLayout.chimeRing
        let p = chimePosition(k)
        let radial = normalize(SIMD3(p.x - c.x, 0, p.z - c.z))
        let tangent = SIMD3(-radial.z, 0, radial.x)
        let ax = rotation(aligningYTo: normalize(SIMD3(0, 1, 0) + radial * swing + tangent * 0))   // lean toward/away from the centre
        return translation(p) * ax
    }

    static func addChimeRing(_ scene: Scene, device: MTLDevice) {
        let stone = frost()
        let c = GlassLayout.chimeRing
        var fixed = MeshBuilder()
        fixed.lathe(profile: [SIMD2(chimeRadius + 2.7, 0), SIMD2(chimeRadius + 2.7, 0.1), SIMD2(chimeRadius + 2.45, 0.13), SIMD2(0, 0.13)], segments: 40, smooth: false, surface: frost(1.0))
        fixed.torus(major: chimeRadius + 1.7, minor: 0.04, segments: 64, sides: 6, surface: pale, transform: translation(SIMD3(0, 0.135, 0)))       // an inlaid ring
        fixed.torus(major: chimeRadius - 1.3, minor: 0.03, segments: 64, sides: 6, surface: pale, transform: translation(SIMD3(0, 0.135, 0)))
        for k in 0..<chimeCount {
            let p = chimePosition(k) - c
            fixed.cylinder(radiusTop: 0.5, radiusBottom: 0.65, height: 0.4, segments: 6, smooth: false, surface: stone, transform: translation(p + SIMD3(0, 0.1, 0)))
        }
        scene.platforms.append(Scene.Platform(center: SIMD2(c.x, c.z), radius: chimeRadius + 2.45, top: c.y + 0.13))      // F03 P1: the base slab is walkable at the height it is drawn
        scene.add("gw_chime_base", mesh: fixed.build(device: device, label: "chime base"), uniforms: ObjectUniforms(model: translation(c)))

        for k in 0..<chimeCount {
            var glass = MeshBuilder()
            let h = chimeHeights[k]
            glass.cylinder(radiusTop: 0.16, radiusBottom: 0.26, height: h, segments: 6, smooth: false,
                           surface: Surface(color: SIMD3(0.8, 0.95, 1.0), roughness: 0.06, material: .emissiveGlass), transform: translation(SIMD3(0, 0.5, 0)))
            glass.cone(radius: 0.16, height: 0.35, segments: 6, smooth: false, surface: Surface(color: SIMD3(0.8, 0.95, 1.0), roughness: 0.06, material: .emissiveGlass),
                       transform: translation(SIMD3(0, 0.5 + h, 0)))
            scene.add("gw_chime_\(k)", mesh: glass.build(device: device, label: "chime \(k)"),
                      uniforms: ObjectUniforms(model: chimeModel(k, swing: 0), tint: SIMD4(0.8, 0.95, 1.0, 1), emissive: SIMD4(0.5, 0.8, 1.0, 0.4)))
        }

        // The mural for this puzzle: the same three glyphs in the same order, on a wall beside the path just before the ring,
        // turned to face the player as they walk in from the north-west (it must show its FACE, not its back).
        addMural(scene, name: "gw_chime_mural", model: translation(c + SIMD3(-6, 0, -12)) * rotationY(-.pi / 4), device: device)      // local +Z -> south-west: toward the path

        // The light released when the chimes are solved: an amber/cyan column from the centre of the ring.
        var column = MeshBuilder()
        column.cylinder(radiusTop: 0.28, radiusBottom: 0.5, height: 1, segments: 10, smooth: true, caps: false, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.5))
        scene.add("gw_column_chimes", mesh: column.build(device: device, label: "column"),
                  uniforms: ObjectUniforms(model: translation(c) * scaling(SIMD3(1, 0.001, 1)), tint: SIMD4(1.0, 0.8, 0.5, 1), emissive: SIMD4(1.0, 0.75, 0.4, 7)), hidden: true)
    }

    // MARK: Altar of two accounts

    static let ilseColor = SIMD3<Float>(1.0, 0.72, 0.38)       // amber: the lamp, the island
    static let orenColor = SIMD3<Float>(0.55, 0.72, 1.0)       // cool blue-violet: the glass wood
    static let altarSunk: Float = 2.4
    static func pedestalPosition(_ which: Int) -> SIMD3<Float> { GlassLayout.altar + SIMD3(which == 0 ? -3.0 : 3.0, 0, 0) }

    static func pedestalModel(_ which: Int, rise: Float) -> float4x4 {
        translation(pedestalPosition(which) + SIMD3(0, -altarSunk * (1 - rise), 0))
    }

    static func addAltar(_ scene: Scene, device: MTLDevice) {
        let stone = frost()
        let a = GlassLayout.altar
        // The dais: three broad steps up to a carved rim; a ring of pale inlay lozenges, and a thin inlaid ring that glows faintly.
        var dais = MeshBuilder()
        dais.lathe(profile: [SIMD2(6.7, 0), SIMD2(6.7, 0.18), SIMD2(6.1, 0.18), SIMD2(6.1, 0.37), SIMD2(5.5, 0.37), SIMD2(5.5, 0.55), SIMD2(0, 0.55)],
                   segments: 48, smooth: false, surface: frost(0.95))
        for k in 0..<24 {
            let ang = Float(k) / 24 * 2 * .pi
            dais.chamferBox(size: SIMD3(0.5, 0.025, 0.14), chamfer: 0.008, surface: pale,
                            transform: translation(SIMD3(cos(ang) * 5.05, 0.555, sin(ang) * 5.05)) * rotationY(-ang))
        }
        dais.torus(major: 4.6, minor: 0.05, segments: 64, sides: 6, surface: pale, transform: translation(SIMD3(0, 0.55, 0)))
        // F02 M1 (#28): the dais is walkable at exactly the heights it is drawn: three discs (lathe radii 6.7 / 6.1 / 5.5, tops 0.18 / 0.37 / 0.55).
        for (r, top) in [(Float(6.7), Float(0.18)), (6.1, 0.37), (5.5, 0.55)] {
            scene.platforms.append(Scene.Platform(center: SIMD2(a.x, a.z), radius: r - 0.03, top: a.y + top))
        }
        scene.add("gw_altar_dais", mesh: dais.build(device: device, label: "altar dais"), uniforms: ObjectUniforms(model: translation(a)))
        var glowRing = MeshBuilder()
        glowRing.torus(major: 4.0, minor: 0.035, segments: 64, sides: 6, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.3), transform: translation(SIMD3(0, 0.56, 0)))
        scene.add("gw_altar_glow", mesh: glowRing.build(device: device, label: "altar glow"),
                  uniforms: ObjectUniforms(model: translation(a), tint: SIMD4(0.55, 0.72, 1.0, 1), emissive: SIMD4(0.55, 0.72, 1.0, 0.7)))

        // The two pedestals start sunk in the ground and rise when both puzzles are solved.
        for which in 0..<2 {
            let col = which == 0 ? ilseColor : orenColor
            var ped = MeshBuilder()
            ped.cylinder(radiusTop: 0.55, radiusBottom: 0.8, height: 1.3, segments: 6, smooth: false, surface: stone)
            ped.torus(major: 0.62, minor: 0.1, segments: 28, sides: 8, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.1, material: .emissiveGlass),
                      transform: translation(SIMD3(0, 1.9, 0)) * rotationX(.pi / 2))
            ped.sphere(radius: 0.22, segments: 12, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.1), transform: translation(SIMD3(0, 1.9, 0)))
            scene.add("gw_altar_\(which == 0 ? "ilse" : "oren")", mesh: ped.build(device: device, label: "pedestal"),
                      uniforms: ObjectUniforms(model: pedestalModel(which, rise: 0), tint: SIMD4(col, 1), emissive: SIMD4(col, 0.0)), hidden: true)
        }
        var column = MeshBuilder()
        column.cylinder(radiusTop: 0.3, radiusBottom: 0.55, height: 1, segments: 10, smooth: true, caps: false, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.5))
        scene.add("gw_column_altar", mesh: column.build(device: device, label: "column"),
                  uniforms: ObjectUniforms(model: translation(a) * scaling(SIMD3(1, 0.001, 1)), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.95, 0.85, 7)), hidden: true)
    }
}
