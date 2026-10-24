import Metal
import simd

/// Landmark positions in the Glass Wood. All heights derive from the base terrain function, so a pad always sits at the
/// natural height of the hills around it (no hand-tuned numbers that can drift out of agreement).
enum GlassLayout {
    static let noise = Noise(seed: 20_26)          // the seed Terrain uses by default
    static func groundY(_ x: Float, _ z: Float) -> Float { GlassTerrain.base(noise, x, z) }
    static func point(_ x: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, groundY(x, z), z) }

    static let arrival = point(0, 152)             // where the lens deposits you, facing north
    /// Inside the arrival pad (radius 10), where the ground is exactly flat at arrival.y, so the ring's height is exact.
    static let returnLens = SIMD3(arrival.x, arrival.y + 2.3, arrival.z - 6)
    static let mirrorCourt = point(-70, 20)
    static let junction = point(0, -45)
    static let chimeRing = point(70, 10)
    static let altar = point(0, -92)

    /// The walking route: arrival -> mirror court -> junction -> chime ring -> junction -> altar.
    static let path: [SIMD3<Float>] = [
        point(0, 152), point(0, 118), point(-38, 88), point(-68, 52), point(-70, 20), point(-48, -14), point(0, -45),
        point(45, -15), point(70, 10), point(45, -15), point(0, -45), point(0, -92),
    ]

    static let pads: [Layout.Pad] = [
        Layout.Pad(center: arrival, radius: 10),
        Layout.Pad(center: mirrorCourt, radius: 24),
        Layout.Pad(center: junction, radius: 8),
        Layout.Pad(center: chimeRing, radius: 16),
        Layout.Pad(center: altar, radius: 13),
    ]
}

enum GlassTerrain {
    static let center = SIMD2<Float>(0, 20)
    static let radius: Float = 215
    static let pool = SIMD2<Float>(0, 25)
    static let poolRadius: Float = 40
    static let seaFloor: Float = -24

    /// A gentle dome (11 m at the middle falling to the sea at 215 m) with a round pool dug into the middle.
    /// Anything below 0 m is under the ocean plane, so the pool is simply a depression that fills with water.
    static func base(_ noise: Noise, _ x: Float, _ z: Float) -> Float {
        let p = SIMD2(x, z)
        let wobble = noise.fbm(x * 0.006 + 11, z * 0.006 - 5, octaves: 4)
        let d = length(p - center) * (1 + 0.09 * wobble)
        var h: Float = d < radius
            ? 11 * pow(1 - smoothstep(30, radius, d), 1.2) + 2.5 * (1 - smoothstep(radius * 0.8, radius, d)) * smoothstep(0, 1, 1 - d / radius)
            : seaFloor * smoothstep(radius, radius + 110, d)
        h -= 26 * (1 - smoothstep(14, poolRadius, length(p - pool)))      // deep enough that the water goes dark
        return h
    }
}

extension TerrainSpec {
    static let glassWood = TerrainSpec(pads: GlassLayout.pads, path: GlassLayout.path, seaFloor: GlassTerrain.seaFloor,
                                       baseHeight: GlassTerrain.base, rollingAmplitude: 5, cragAmplitude: 2)
}

enum GlassWood {
    static func build(device: MTLDevice) -> Scene {
        let scene = Scene(kind: .glassWood)
        scene.terrain = Terrain(spec: .glassWood)
        for chunk in TerrainMesh.buildChunks(terrain: scene.terrain, device: device) {
            scene.add(chunk.name, mesh: chunk.mesh, uniforms: chunk.uniforms)
        }
        addArrival(scene, device: device)
        addForest(scene, device: device)
        addLamps(scene, device: device)
        addPathTufts(scene, device: device)
        GlassPuzzleProps.populate(scene, device: device)
        return scene
    }

    /// A round stone plate where you arrive, and the ring that leads back to Varrow.
    static func addArrival(_ scene: Scene, device: MTLDevice) {
        let a = GlassLayout.arrival
        var plate = MeshBuilder()
        plate.cylinder(radiusTop: 3.6, radiusBottom: 3.9, height: 0.25, segments: 20, smooth: false,
                       surface: Surface(color: SIMD3(0.16, 0.17, 0.24), roughness: 0.4), transform: translation(SIMD3(0, -0.05, 0)))
        // Inlay: concentric rings, radial tile seams and a roundel, so the plate you stand on reads as laid stone, not one smooth dome.
        let pale = Surface(color: SIMD3(0.34, 0.36, 0.50), roughness: 0.35)
        let seam = Surface(color: SIMD3(0.07, 0.07, 0.12), roughness: 0.6)
        let top: Float = 0.205                  // the plate's top face: the cylinder is lifted -0.05 and 0.25 tall
        for r: Float in [1.15, 2.2, 3.15] {
            plate.torus(major: r, minor: 0.035, segments: 40, sides: 5, surface: pale, transform: translation(SIMD3(0, top, 0)))
        }
        for i in 0..<12 {
            let ang = Float(i) / 12 * 2 * .pi + 0.13
            // a groove from the inner ring to the rim at (sin, cos): boxes are centred, so offset by half the length
            plate.box(size: SIMD3(0.04, 0.012, 2.3), surface: seam,
                      transform: rotationY(ang) * translation(SIMD3(0, top, 2.3)))
        }
        for i in 0..<6 {                       // a six-petalled roundel in the middle
            let ang = Float(i) / 6 * 2 * .pi
            plate.cylinder(radiusTop: 0.22, radiusBottom: 0.24, height: 0.02, segments: 10, smooth: false, surface: pale,
                           transform: rotationY(ang) * translation(SIMD3(0, top - 0.01, 0.55)))
        }
        scene.stoneZones.append((center: SIMD2(a.x, a.z), radius: 3.6))
        scene.add("gw_arrival_plate", mesh: plate.build(device: device, label: "arrival plate"), uniforms: ObjectUniforms(model: translation(a)))

        var ring = MeshBuilder()
        ring.torus(major: 0.95, minor: 0.12, segments: 36, sides: 10,
                   surface: Surface(color: SIMD3(0.8, 0.95, 1.0), roughness: 0.1, material: .emissiveGlass), transform: rotationX(.pi / 2))
        scene.add("gw_return_ring", mesh: ring.build(device: device, label: "return ring"),
                  uniforms: ObjectUniforms(model: translation(GlassLayout.returnLens), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.8, 0.5, 2.2)))
        var core = MeshBuilder()
        core.sphere(radius: 0.3, segments: 14, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.2))
        scene.add("gw_return_core", mesh: core.build(device: device, label: "return core"),
                  uniforms: ObjectUniforms(model: translation(GlassLayout.returnLens), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.85, 0.55, 5)))
    }

    /// Candidate crystal-tree sites (Poisson disc, clear of the route, the pads and the pool): shared by the forest and the `--approach` targets.
    static func forestSites(terrain: Terrain) -> [SIMD2<Float>] {
        func allowed(_ x: Float, _ z: Float) -> Bool {
            guard terrain.sampleHeight(x: x, z: z) > 2.5, terrain.normal(x: x, z: z).y > 0.88,
                  Island.isClear(terrain: terrain, x: x, z: z, pathMargin: 7, padMargin: 7, avoidDock: false) else { return false }
            return length(SIMD2(x, z) - GlassTerrain.pool) >= GlassTerrain.poolRadius + 6
        }
        func density(_ x: Float, _ z: Float) -> Float { min(max(0.4 + 1.7 * Island.noise.fbm(x * 0.014 + 5, z * 0.014 - 12, octaves: 3), 0), 1) }
        return PoissonDisc.sample(min: SIMD2(-290, -380), max: SIMD2(260, 260), rMin: 7, rMax: 24,
                                  radius: { 24 - 17 * density($0.x, $0.y) }, accept: { allowed($0.x, $0.y) }, seed: 0xC0FFEE)
    }

    /// The crystal forest: groves of glass trees on gentle dry ground, clear of the route, the pads and the pool's bank.
    static func addForest(_ scene: Scene, device: MTLDevice) {
        let sites = forestSites(terrain: scene.terrain)
        let spots = sites.map { (x: $0.x, z: $0.y, rand: Island.noise.unit(Int32($0.x * 3.1), Int32($0.y * 3.1))) }
        // Like the conifers: each tree is one of a few variants at three LODs, merged per 60 m cell; the cell shows the LOD for its distance.
        let cell: Float = 60
        var cells = [[String: MeshBuilder]](repeating: [:], count: 3)
        for (count, s) in spots.prefix(220).enumerated() {
            let y = scene.terrain.sampleHeight(x: s.x, z: s.z)
            let height = 6 + 9 * (s.rand * 11.3 - floor(s.rand * 11.3))
            let variant = Int(Island.noise.unit(Int32(count), 5) * Float(CrystalTrees.variantCount)) % CrystalTrees.variantCount
            let h = height / CrystalTrees.nominalHeight
            let width = h * (0.85 + 0.3 * Island.noise.unit(Int32(count), 13))
            let i = Int(floor(s.x / cell)), j = Int(floor(s.z / cell))
            let m = translation(SIMD3(s.x, y - 0.1, s.z)) * rotationY(s.rand * 60) * scaling(SIMD3(width, h, width))
            let stagger = 3 + (Island.noise.unit(Int32(count), 97) * 2 - 1)               // see tree_lod_level
            for lod in 0..<3 {
                let key = "crystals_L\(lod)_\(i)_\(j)"
                var cell = cells[lod][key] ?? MeshBuilder()
                let start = cell.vertices.count
                cell.append(CrystalTrees.variant(variant, lod: lod), transform: m)
                cell.adjust(from: start) { $0.position.w = stagger }
                cells[lod][key] = cell
            }
            scene.colliders.addCylinder(center: SIMD2(s.x, s.z), radius: 0.55, minY: y - 1, maxY: y + height)
        }
        let treeUniforms = { (lod: Int) in ObjectUniforms(model: matrix_identity_float4x4, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.6, 0.85, 1.0, 1.8), lod: SIMD4(1, Float(lod), 0, 0)) }
        for name in cells[0].keys.sorted() {
            let suffix = String(name.dropFirst("crystals_L0".count))
            var names: [String] = []
            for lod in 0..<3 {
                let n = "crystals_L\(lod)\(suffix)"
                guard let mb = cells[lod][n], !mb.isEmpty else { continue }
                scene.add(n, mesh: mb.build(device: device, label: n), uniforms: treeUniforms(lod), hidden: lod != 0, refractive: true)
                names.append(n)
            }
            let parts = suffix.split(separator: "_").compactMap { Int($0) }
            if parts.count == 2 {
                let lo = SIMD2(Float(parts[0]) * cell, Float(parts[1]) * cell)
                scene.lodGroups.append(Scene.LODGroup(names: names, min: lo, max: lo + SIMD2(cell, cell)))
            }
        }
    }

    /// Small glowing crystal tufts beside the path (R06): clusters of 2-4 little prisms in teal and violet, scattered at irregular spacing within a
    /// few metres of the route, something for the eye to find in the grass. Opaque with an emissive, like the lamps.
    static func addPathTufts(_ scene: Scene, device: MTLDevice) {
        let noise = Noise(seed: 777)
        var tufts = MeshBuilder()
        let pts = GlassLayout.path.map { SIMD2($0.x, $0.z) }
        var carried: Float = 3
        var n: Int32 = 0
        for k in 0..<(pts.count - 1) {
            let a = pts[k], b = pts[k + 1]
            let dir = normalize(b - a), nrm = SIMD2(-dir.y, dir.x)
            let len = length(b - a)
            var s = carried
            while s < len {
                n += 1
                let off = (2.2 + 3.8 * noise.unit(n, 1)) * (noise.unit(n, 2) < 0.5 ? -1 : 1)
                let c = a + dir * s + nrm * off
                if GlassLayout.pads.allSatisfy({ length(c - SIMD2($0.center.x, $0.center.z)) > $0.radius * 0.6 }) {
                    let y = scene.terrain.sampleHeight(x: c.x, z: c.y)
                    let hue = noise.unit(n, 3)
                    let count = 2 + Int(noise.unit(n, 4) * 2.99)
                    for j in 0..<count {
                        let ang = noise.unit(n * 5 + Int32(j), 5) * 6.28, lean = 0.15 + 0.45 * noise.unit(n * 5 + Int32(j), 6)
                        let L = 0.16 + 0.34 * noise.unit(n * 5 + Int32(j), 7)
                        let d = normalize(SIMD3(cos(ang) * lean, 1, sin(ang) * lean))
                        let col = SIMD3<Float>(0.40, 0.95, 1.0) + (SIMD3<Float>(0.74, 0.55, 1.0) - SIMD3<Float>(0.40, 0.95, 1.0)) * hue
                        let s = Surface(color: col * (0.8 + 0.4 * noise.unit(n * 5 + Int32(j), 8)), roughness: 0.15)
                        let m = translation(SIMD3(c.x + cos(ang) * 0.06 * Float(j), y - 0.02, c.y + sin(ang) * 0.06 * Float(j))) * rotation(aligningYTo: d)
                        tufts.cylinder(radiusTop: L * 0.09, radiusBottom: L * 0.12, height: L * 0.72, segments: 6, smooth: false, caps: false, surface: s, transform: m)
                        tufts.cone(radius: L * 0.09, height: L * 0.34, segments: 6, smooth: false, surface: s, transform: m * translation(SIMD3(0, L * 0.72, 0)))
                    }
                }
                s += 2.5 + 4.5 * noise.unit(n, 9)
            }
            carried = s - len
        }
        scene.add("gw_tufts", mesh: tufts.build(device: device, label: "tufts"),
                  uniforms: ObjectUniforms(model: matrix_identity_float4x4, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.5, 0.9, 1.0, 2.2)))
    }

    /// Glowing spires every 14 m along the route, alternating sides: the same "follow the light" guidance as Varrow's lanterns.
    static func addLamps(_ scene: Scene, device: MTLDevice) {
        let proto = Props.crystalLamp()
        var lamps = MeshBuilder()
        var side: Float = 1
        let pts = GlassLayout.path.map { SIMD2($0.x, $0.z) }
        var carried: Float = 8
        for k in 0..<(pts.count - 1) {
            let a = pts[k], b = pts[k + 1]
            let dir = normalize(b - a), nrm = SIMD2(-dir.y, dir.x)
            let len = length(b - a)
            var s = carried
            while s < len {
                let c = a + dir * s + nrm * 2.4 * side
                side = -side
                let clearOfPads = GlassLayout.pads.allSatisfy { length(c - SIMD2($0.center.x, $0.center.z)) > $0.radius * 0.6 }
                if clearOfPads {
                    let y = scene.terrain.sampleHeight(x: c.x, z: c.y)
                    lamps.append(proto, transform: translation(SIMD3(c.x, y, c.y)))
                    scene.colliders.addCylinder(center: c, radius: 0.3, minY: y - 1, maxY: y + 1.8)
                }
                s += 14
            }
            carried = s - len
        }
        scene.add("gw_lamps", mesh: lamps.build(device: device, label: "lamps"),
                  uniforms: ObjectUniforms(model: matrix_identity_float4x4, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0.35, 0.9, 1.0, 5)))
    }
}
