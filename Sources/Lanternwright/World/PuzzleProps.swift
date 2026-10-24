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
            b.box(size: SIMD3(3.2, 0.6, 3.8), surface: Surface(color: SIMD3(0.30, 0.285, 0.26) * tone, roughness: 0.88),
                  transform: matrix_identity_float4x4)
            b.box(size: SIMD3(3.3, 0.12, 3.9), surface: Surface(color: SIMD3(0.22, 0.21, 0.19) * tone, roughness: 0.9),
                  transform: translation(SIMD3(0, -0.3, 0)))
            scene.add("causeway_\(k)", mesh: b.build(device: device, label: "slab"),
                      uniforms: ObjectUniforms(model: slabModel(plan, k, rise: 0)), hidden: true)   // revealed when the rumble starts
        }
        let end = plan.start + plan.dir * plan.length
        scene.causewayIndex = scene.walkables.count
        scene.walkables.append(Walkable(a: plan.start, b: end, halfWidth: 1.5, y0: plan.yStart, y1: plan.yEnd, enabled: false, surface: .stone))
    }

    static func addIslet(_ scene: Scene, device: MTLDevice) {
        let c = Layout.isletCenter
        let stone = Surface(color: SIMD3(0.34, 0.325, 0.30), roughness: 0.85)
        var b = MeshBuilder()
        b.cylinder(radiusTop: 1.5, radiusBottom: 1.8, height: 0.6, segments: 12, smooth: false, surface: stone, transform: translation(SIMD3(0, 0, 0)))
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi + 0.3
            let h = 2.6 + 0.8 * Island.noise.unit(Int32(i), 55)
            let m = translation(SIMD3(6.5 * cos(a), 0, 6.5 * sin(a))) * rotationY(a) * rotationZ((Island.noise.unit(Int32(i), 7) - 0.5) * 0.12)
            b.box(size: SIMD3(0.9, h, 0.9), surface: stone, transform: m * translation(SIMD3(0, h / 2 - 0.2, 0)))
            scene.colliders.addCylinder(center: SIMD2(c.x + 6.5 * cos(a), c.z + 6.5 * sin(a)), radius: 0.7, minY: c.y - 1, maxY: c.y + h)
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

    static func addPages(_ scene: Scene, device: MTLDevice) {
        var b = MeshBuilder()
        b.box(size: SIMD3(0.34, 0.012, 0.46), surface: Surface(color: SIMD3(0.85, 0.80, 0.66), roughness: 0.9))
        let mesh = b.build(device: device, label: "page")
        for n in 1...4 {
            let p = pagePosition(n, terrain: scene.terrain)
            let yaw = Island.noise.unit(Int32(n), 17) * 2 * .pi
            scene.add("page_\(n)", mesh: mesh,
                      uniforms: ObjectUniforms(model: translation(p) * rotationY(yaw) * rotationX(0.04),
                                               tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.95, 0.85, 0.6, 0.25)))
        }
    }
}
