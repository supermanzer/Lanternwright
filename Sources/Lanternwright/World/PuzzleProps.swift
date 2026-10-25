import Metal
import simd

/// World objects that the puzzle moves or reveals: beams, the causeway, the lens on the islet, journal pages.
enum PuzzleProps {
    // MARK: Causeway

    static let slabCount = 14
    static let slabPitch: Float = 4
    static let slabSubmergedBy: Float = 4.6

    struct CausewayPlan {
        var start: SIMD2<Float>
        var dir: SIMD2<Float>
        var length: Float
        var yStart: Float
        var yEnd: Float
        var yaw: Float { atan2(dir.x, dir.y) }
        var tilt: Float { -atan((yEnd - yStart) / length) }
        func center(_ k: Int) -> SIMD2<Float> { start + dir * (2 + slabPitch * Float(k)) }
        func top(_ k: Int) -> Float { yStart + (yEnd - yStart) * (2 + slabPitch * Float(k)) / length }
    }

    /// The causeway runs from the north shore to the islet and ramps up to meet the islet's raised ground
    /// (a flat causeway would end against a 3 m step the player cannot climb).
    static func causewayPlan(terrain: Terrain) -> CausewayPlan {
        let start = SIMD2(Layout.causewayStart.x, Layout.causewayStart.z)
        let dir = normalize(SIMD2(Layout.isletCenter.x, Layout.isletCenter.z) - start)
        let length = slabPitch * Float(slabCount) + 2
        let end = start + dir * length
        let yEnd = max(1.4, terrain.sampleHeight(x: end.x, z: end.y) - 0.05)
        return CausewayPlan(start: start, dir: dir, length: length, yStart: 1.2, yEnd: yEnd)
    }

    static func slabModel(_ plan: CausewayPlan, _ k: Int, rise: Float) -> float4x4 {
        let c = plan.center(k)
        let y = plan.top(k) - 0.3 - (1 - rise) * slabSubmergedBy
        return translation(SIMD3(c.x, y, c.y)) * rotationY(plan.yaw) * rotationX(plan.tilt)
    }

    // MARK: Beams

    static let beamRadius: Float = 0.11

    /// A beam from a stone's capstone to the lens, grown to `growth` (0...1) of its length.
    static func beamModel(_ id: StoneID, capRise: Float, growth: Float) -> float4x4 {
        let start = Landmarks.capstoneBase(id) + SIMD3(0, capRise, 0)
        let d = Landmarks.lensPosition - start
        return translation(start) * rotation(aligningYTo: d) * scaling(SIMD3(1, max(length(d) * growth, 1e-3), 1))
    }

    // MARK: Pages

    /// World position of each journal page (lying where the player will pass).
    static func pagePosition(_ number: Int, terrain: Terrain) -> SIMD3<Float> {
        switch number {
        case 1:   // on the dock, near the landward end, by the right-hand edge
            let strip = Layout.dockStrip()
            let dir = normalize(strip.b - strip.a), side = SIMD2(-dir.y, dir.x)
            let along: Float = 8.5
            let p = strip.a + dir * along - side * 0.7
            let y = strip.y0 + (strip.y1 - strip.y0) * along / simd_length(strip.b - strip.a)
            return SIMD3(p.x, y + 0.02, p.y)
        case 2, 3:   // on the stone's plinth, on the arrival side
            let id: StoneID = number == 2 ? .tide : .wind
            let toward = normalize(SIMD2(id.approachFrom.x - id.position.x, id.approachFrom.z - id.position.z))
            let right = SIMD2(toward.y, -toward.x)
            let p = SIMD2(id.position.x, id.position.z) + toward * 1.15 + right * 0.5
            return SIMD3(p.x, terrain.sampleHeight(x: p.x, z: p.y) + 0.28, p.y)
        default:     // on the lighthouse doorstep
            let p = SIMD2(Layout.lighthouse.x + 1.6, Layout.lighthouse.z + 6.3)
            return SIMD3(p.x, terrain.sampleHeight(x: p.x, z: p.y) + 0.02, p.y)
        }
    }

    // MARK: Build

    static func populate(_ scene: Scene, device: MTLDevice) {
        addBeams(scene, device: device)
        addCauseway(scene, device: device)
        addIslet(scene, device: device)
        addPages(scene, device: device)
    }

    static func addBeams(_ scene: Scene, device: MTLDevice) {
        var b = MeshBuilder()
        b.cylinder(radiusTop: beamRadius, radiusBottom: beamRadius, height: 1, segments: 8, smooth: true, caps: false,
                   surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.5))
        let mesh = b.build(device: device, label: "beam")
        for id in StoneID.allCases {
            scene.add("beam_\(id.name)", mesh: mesh,
                      uniforms: ObjectUniforms(model: beamModel(id, capRise: 0, growth: 0), tint: SIMD4(id.color, 1), emissive: SIMD4(id.color, 6)),
                      hidden: true)
        }
    }

    static func addCauseway(_ scene: Scene, device: MTLDevice) {
        let plan = causewayPlan(terrain: scene.terrain)
        for k in 0..<slabCount {
            var b = MeshBuilder()
            let tone = 0.85 + 0.3 * Island.noise.unit(Int32(k), 313)
            let n = Island.noise
            // F01 W3.3: weathered dressed stone, not a box. Chamfered, chipped, its top gently dished and tilted a little differently each time, a darker
            // footing course, a sunk corner and a loose chip of stone at one edge. The slab material (22) does the waterline: wet and algae below, barnacles at the
            // surface, salt above, so the stones DRIP as they come up out of the sea.
            let surf = Surface(color: SIMD3(0.36, 0.34, 0.31) * tone, roughness: 0.88, material: .slab)
            let tiltX = (n.unit(Int32(k), 321) - 0.5) * 0.03, tiltZ = (n.unit(Int32(k), 322) - 0.5) * 0.03
            b.chamferBox(size: SIMD3(3.1 - 0.15 * n.unit(Int32(k), 323), 0.6, 3.7 - 0.15 * n.unit(Int32(k), 324)), chamfer: 0.07 + 0.05 * n.unit(Int32(k), 325), surface: surf,
                         transform: rotationX(tiltX) * rotationZ(tiltZ) * translation(SIMD3((n.unit(Int32(k), 326) - 0.5) * 0.08, 0, 0)))
            b.chamferBox(size: SIMD3(3.35, 0.14, 3.95), chamfer: 0.05, surface: Surface(color: SIMD3(0.24, 0.225, 0.20) * tone, roughness: 0.9, material: .slab), transform: translation(SIMD3(0, -0.33, 0)))
            // The top dished: a low chamfered inset, a few millimetres, that holds a film of water.
            b.chamferBox(size: SIMD3(2.5, 0.02, 3.0), chamfer: 0.008, surface: Surface(color: SIMD3(0.33, 0.31, 0.285) * tone, roughness: 0.8, material: .slab),
                         transform: rotationX(tiltX) * rotationZ(tiltZ) * translation(SIMD3(0, 0.298, 0)))
            for c in 0..<2 {                                                                 // chips and rubble at the edge
                let a = n.unit(Int32(k * 5 + c), 330) * 2 * .pi, rr = 1.45 + 0.4 * n.unit(Int32(k * 5 + c), 331)
                b.chamferBox(size: SIMD3(0.28, 0.14, 0.22) * (0.6 + 0.8 * n.unit(Int32(k * 5 + c), 332)), chamfer: 0.03, surface: surf,
                             transform: translation(SIMD3(cos(a) * rr, 0.25, sin(a) * rr * 1.1)) * rotationY(a) * rotationZ(0.3 * (n.unit(Int32(k * 5 + c), 333) - 0.5)))
            }
            scene.add("causeway_\(k)", mesh: b.build(device: device, label: "slab"),
                      uniforms: ObjectUniforms(model: slabModel(plan, k, rise: 0)), hidden: true)   // revealed when the rumble starts
        }
        let end = plan.start + plan.dir * plan.length
        scene.causewayIndex = scene.walkables.count
        scene.walkables.append(Walkable(a: plan.start, b: end, halfWidth: 1.5, y0: plan.yStart, y1: plan.yEnd, enabled: false, surface: .stone))
    }

    static func addIslet(_ scene: Scene, device: MTLDevice) {
        let c = Layout.isletCenter
        // F01 W3.4: the islet's stones. The lens base is a stepped footing of dressed stone with an iron band; the five pillars are tapering, leaning, faceted standing
        // stones with chamfered tops, a stone footing and (some of them) a carved glyph panel on the face turned to the lens; one has fallen and broken.
        let stone = Surface(color: SIMD3(0.40, 0.38, 0.35), roughness: 0.85, material: .dressed)
        let dark = Surface(color: SIMD3(0.30, 0.285, 0.265), roughness: 0.9, material: .dressed)
        let iron = Surface(color: SIMD3(0.07, 0.065, 0.07), roughness: 0.5, material: .iron)
        var b = MeshBuilder()
        b.lathe(profile: [SIMD2(2.0, -0.3), SIMD2(2.0, 0.18), SIMD2(1.75, 0.18), SIMD2(1.75, 0.42), SIMD2(1.35, 0.42), SIMD2(1.3, 0.62), SIMD2(0, 0.62)], segments: 14, smooth: false, surface: stone)
        b.torus(major: 1.38, minor: 0.05, segments: 28, sides: 6, surface: iron, transform: translation(SIMD3(0, 0.55, 0)))
        let n = Island.noise
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi + 0.3
            let h = 2.6 + 0.8 * n.unit(Int32(i), 55)
            let broken = i == 3
            let lean = (n.unit(Int32(i), 7) - 0.5) * 0.14
            let m = translation(SIMD3(6.5 * cos(a), 0, 6.5 * sin(a))) * rotationY(a + 0.4 * n.unit(Int32(i), 8))
            let rb = 0.55 + 0.1 * n.unit(Int32(i), 9), rt = rb * (0.62 + 0.15 * n.unit(Int32(i), 10))
            b.chamferBox(size: SIMD3(rb * 2.5, 0.35, rb * 2.5), chamfer: 0.06, surface: dark, transform: m * translation(SIMD3(0, 0.0, 0)))              // footing
            if broken {                                                                    // F02 G2: a stump and a fallen part that respect each other (BrokenPillar)
                let ground: (Float, Float) -> Float = { x, z in scene.terrain.sampleHeight(x: c.x + x, z: c.z + z) - c.y }
                let r = BrokenPillar.build(index: i, centre: SIMD3(6.5 * cos(a), 0, 6.5 * sin(a)), yaw: a + 0.4 * n.unit(Int32(i), 8), h: h, rb: rb, rt: rt, outward: a, ground: ground)
                b.append(r.stump, transform: r.stumpTransform)
                b.append(r.fallen); b.append(r.chips)
                scene.placed.append(Placement.record(kind: "pillar", mesh: r.fallen, transform: translation(c)))
            } else {
                b.cylinder(radiusTop: rt, radiusBottom: rb, height: h, segments: 6, smooth: false, surface: stone, transform: m * rotationZ(lean) * rotationX(lean * 0.5) * translation(SIMD3(0, 0.1, 0)))
                b.chamferBox(size: SIMD3(rt * 2.0, 0.22, rt * 2.0), chamfer: 0.05, surface: stone, transform: m * rotationZ(lean) * rotationX(lean * 0.5) * translation(SIMD3(0, h + 0.1, 0)))     // a cap block
            }
            scene.colliders.addCylinder(center: SIMD2(c.x + 6.5 * cos(a), c.z + 6.5 * sin(a)), radius: 0.7, minY: c.y - 1, maxY: c.y + h)
        }
        // F02 M1: the lens base's three tiers (lathe radii 2.0 / 1.75 / 1.35 above the islet's level; tops 0.18 / 0.42 / 0.62) can be climbed.
        for (r, top) in [(Float(2.0), Float(0.18)), (1.75, 0.42), (1.35, 0.62)] {
            scene.platforms.append(Scene.Platform(center: SIMD2(c.x, c.z), radius: r - 0.03, top: c.y + top))
        }
        scene.add("islet", mesh: b.build(device: device, label: "islet"), uniforms: ObjectUniforms(model: translation(c)))

        // The lens: a floating ring of glass around a bright core. Both hover above the pedestal.
        var ring = MeshBuilder()
        ring.torus(major: 0.95, minor: 0.12, segments: 36, sides: 10, surface: Surface(color: SIMD3(0.8, 0.95, 1.0), roughness: 0.1, material: .emissiveGlass),
                   transform: rotationX(.pi / 2))
        scene.add("lens_ring", mesh: ring.build(device: device, label: "lens_ring"),
                  uniforms: ObjectUniforms(model: translation(lensRestPosition), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.7, 0.95, 1.0, 2.2)))
        var core = MeshBuilder()
        core.sphere(radius: 0.3, segments: 14, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.2))
        scene.add("lens_core", mesh: core.build(device: device, label: "lens_core"),
                  uniforms: ObjectUniforms(model: translation(lensRestPosition), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.8, 0.97, 1.0, 5)))
    }

    static var lensRestPosition: SIMD3<Float> { Layout.isletCenter + SIMD3(0, 2.3, 0) }

    /// One sheet of paper, shared by every journal page (both worlds): a 12 x 16 grid with a gentle tent over the fold (z = 0.03), a curled
    /// corner, a wavy edge, a ragged outline and a torn corner, a thin underside so it is never see-through, and a pebble weighting the
    /// far corner. Paper is material 15 (grain, foxing, sepia strokes and the crease are procedural); the pebble is material 16.
    static func pageMesh() -> MeshBuilder {
        let nx = 12, nz = 16
        func height(_ x: Float, _ z: Float) -> Float {
            let r = simd_length(SIMD2(x - 0.17, z - 0.23))
            let curl = 0.035 * pow(max(0, 1 - r / 0.13), 2)
            let curl2 = 0.012 * pow(max(0, 1 - simd_length(SIMD2(x + 0.17, z + 0.23)) / 0.09), 2)
            let tent = 0.011 * max(0, 1 - abs(z - 0.03) / 0.21)
            let edge = max(abs(x) / 0.17, abs(z) / 0.23)
            let wave = 0.0035 * sin(z * 34 + x * 11) * max(0, edge - 0.55)
            return -0.008 + curl + curl2 + tent + wave
        }
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = []
        for j in 0...nz {
            for i in 0...nx {
                var x = (Float(i) / Float(nx) - 0.5) * 0.34, z = (Float(j) / Float(nz) - 0.5) * 0.46
                if i == 0 || i == nx || j == 0 || j == nz {                         // ragged edge: pull border vertices in by a few mm
                    let k = Int32(j * 31 + i)
                    let pull = 0.003 + 0.007 * Island.noise.unit(k, 71)
                    x -= (x < 0 ? -1 : 1) * pull * (i == 0 || i == nx ? 1 : 0.3); z -= (z < 0 ? -1 : 1) * pull * (j == 0 || j == nz ? 1 : 0.3)
                }
                if i == 0 && j == nz { x += 0.05; z -= 0.05 }                        // a torn corner
                pos.append(SIMD3(x, height(x, z), z))
                let e: Float = 0.004
                let n = simd_normalize(SIMD3(-(height(x + e, z) - height(x - e, z)) / (2 * e), 1, -(height(x, z + e) - height(x, z - e)) / (2 * e)))
                nrm.append(n)
            }
        }
        var idx: [UInt32] = []
        for j in 0..<nz { for i in 0..<nx {
            let a = UInt32(j * (nx + 1) + i), b = a + 1, c = a + UInt32(nx + 1), d = c + 1
            idx += [a, c, d, a, d, b]
        } }
        let paper = Surface(color: SIMD3(0.85, 0.80, 0.66), roughness: 0.9, material: .paper)
        var m = MeshBuilder()
        m.addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: paper, transform: matrix_identity_float4x4)
        // Underside: the same sheet 1.5 mm lower, wound the other way.
        let under = pos.map { $0 - SIMD3(0, 0.0015, 0) }
        var rev: [UInt32] = []
        for t in stride(from: 0, to: idx.count, by: 3) { rev += [idx[t], idx[t + 2], idx[t + 1]] }
        m.addIndexed(positions: under, indices: rev, smoothNormals: nrm.map { -$0 }, surface: paper, transform: matrix_identity_float4x4)
        // A small flattened pebble on the lower-left corner.
        let pebble = Surface(color: SIMD3(0.46, 0.43, 0.38), roughness: 0.85, material: .pebble)
        m.icosphere(subdivisions: 1, smooth: true, radius: { _ in 1 }, surface: pebble,
                    transform: translation(SIMD3(-0.115, height(-0.115, -0.17) + 0.008, -0.17)) * rotationY(0.6) * scaling(SIMD3(0.034, 0.016, 0.024)))
        return m
    }

    static func addPages(_ scene: Scene, device: MTLDevice) {
        let mesh = pageMesh().build(device: device, label: "page")
        for n in 1...4 {
            let p = pagePosition(n, terrain: scene.terrain)
            let yaw = Island.noise.unit(Int32(n), 17) * 2 * .pi
            scene.add("page_\(n)", mesh: mesh,
                      uniforms: ObjectUniforms(model: translation(p) * rotationY(yaw) * rotationX(0.04),
                                               tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.95, 0.85, 0.6, 0.25)))
        }
    }
}
