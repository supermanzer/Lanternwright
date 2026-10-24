import Metal
import simd

/// Builds everything that stands on the island. All placement is deterministic.
enum Island {
    static let noise = Noise(seed: 77)

    static func populate(_ scene: Scene, device: MTLDevice) {
        Landmarks.populate(scene, device: device)
        PuzzleProps.populate(scene, device: device)
        Birds.populate(scene, device: device)
        addLanterns(scene, device: device)
        addRocks(scene, device: device)
        addClutter(scene, device: device)
        addTrees(scene, device: device)
    }

    // MARK: Placement rules

    /// True if (x, z) is clear of the path, the landmark pads, the dock and the islet's lens ring.
    static func isClear(terrain: Terrain, x: Float, z: Float, pathMargin: Float, padMargin: Float, avoidDock: Bool = true) -> Bool {
        if terrain.pathDistance(x: x, z: z) < pathMargin { return false }
        let p = SIMD2(x, z)
        for pad in terrain.spec.pads where length(p - SIMD2(pad.center.x, pad.center.z)) < pad.radius + padMargin { return false }
        guard avoidDock else { return true }
        let dock = Layout.dockStrip()
        let ab = dock.b - dock.a
        let t = min(max(dot(p - dock.a, ab) / dot(ab, ab), 0), 1)
        if length(p - (dock.a + ab * t)) < 5 { return false }
        return true
    }

    /// Jittered-grid candidates over the island's bounding region; `accept` decides each one.
    static func scatter(spacing: Float, salt: Int32,
                        accept: (_ x: Float, _ z: Float, _ height: Float, _ normalY: Float, _ rand: Float) -> Bool,
                        terrain: Terrain) -> [(x: Float, z: Float, rand: Float)] {
        var out: [(Float, Float, Float)] = []
        let x0: Float = -290, x1: Float = 260, z0: Float = -380, z1: Float = 260
        var j = 0
        var z = z0
        while z < z1 {
            var i = 0
            var x = x0
            while x < x1 {
                let jx = noise.unit(Int32(i) &+ salt, Int32(j)), jz = noise.unit(Int32(i), Int32(j) &+ salt &* 7)
                let px = x + jx * spacing, pz = z + jz * spacing
                let h = terrain.sampleHeight(x: px, z: pz)
                let ny = terrain.normal(x: px, z: pz).y
                let r = noise.unit(Int32(i) &* 3 &+ salt, Int32(j) &* 5 &+ 1)
                if accept(px, pz, h, ny, r) { out.append((px, pz, r)) }
                x += spacing; i += 1
            }
            z += spacing; j += 1
        }
        return out.map { (x: $0.0, z: $0.1, rand: $0.2) }
    }

    /// Merge placed pieces into one mesh per 120 m cell so they can be culled by region.
    struct Batcher {
        var cells: [String: MeshBuilder] = [:]
        mutating func add(_ piece: MeshBuilder, at p: SIMD3<Float>, yaw: Float, prefix: String, scale: SIMD3<Float> = SIMD3(1, 1, 1), tilt: SIMD2<Float> = .zero) {
            let key = "\(prefix)_\(Int(floor(p.x / 120)))_\(Int(floor(p.z / 120)))"
            cells[key, default: MeshBuilder()].append(piece, transform: translation(p) * rotationY(yaw) * rotationX(tilt.x) * rotationZ(tilt.y) * scaling(scale))
        }
        func commit(_ scene: Scene, device: MTLDevice, uniforms: ObjectUniforms = ObjectUniforms(), refractive: Bool = false) {
            for (name, b) in cells.sorted(by: { $0.key < $1.key }) where !b.isEmpty {
                scene.add(name, mesh: b.build(device: device, label: name), uniforms: uniforms, refractive: refractive)
            }
        }
    }

    // MARK: Clutter

    /// Beach and path-edge litter in clusters, not a uniform sprinkle. Cluster centres are blue-noise sites (Poisson disc) on the
    /// wrack line, the band just above the foam where the tide leaves things; each cluster has a few pieces of driftwood lying
    /// (nearly) flat, partly buried and aligned along the shoreline, a clump of pebbles of very different sizes, and shells.
    /// Pebble-only clusters also sit beside the path. All deterministic, kept off the path, pads and dock.
    static func addClutter(_ scene: Scene, device: MTLDevice) {
        let terrain = scene.terrain!
        var pebble = MeshBuilder(), shell = MeshBuilder(), wood = MeshBuilder()
        pebble.icosphere(subdivisions: 0, smooth: false, radius: { _ in 1 }, surface: Surface(color: SIMD3(0.36, 0.34, 0.31), roughness: 0.8))
        shell.cone(radius: 0.07, height: 0.05, segments: 7, smooth: false, surface: Surface(color: SIMD3(0.80, 0.72, 0.62), roughness: 0.5))
        wood.cylinder(radiusTop: 0.05, radiusBottom: 0.07, height: 1.0, segments: 6, surface: Surface(color: SIMD3(0.42, 0.37, 0.30), roughness: 0.9))   // sun-bleached grey-brown
        var batch = Batcher()

        func wrack(_ x: Float, _ z: Float) -> Bool {
            let h = terrain.sampleHeight(x: x, z: z)
            return h > 0.15 && h < 1.8 && isClear(terrain: terrain, x: x, z: z, pathMargin: 1.2, padMargin: 1.5)
        }
        func beside(_ x: Float, _ z: Float) -> Bool {
            let d = terrain.pathDistance(x: x, z: z)
            return d > 1.8 && d < 5.5 && terrain.normal(x: x, z: z).y > 0.85 && isClear(terrain: terrain, x: x, z: z, pathMargin: 1.2, padMargin: 1.5)
        }
        let beachSites = PoissonDisc.sample(min: SIMD2(-290, -380), max: SIMD2(260, 260), rMin: 6.5, rMax: 6.5, radius: { _ in 6.5 },
                                            accept: { wrack($0.x, $0.y) }, seed: 0xBEAC4, seedSpacing: 30)
        let pathSites = PoissonDisc.sample(min: SIMD2(-290, -380), max: SIMD2(260, 260), rMin: 14, rMax: 14, radius: { _ in 14 },
                                           accept: { beside($0.x, $0.y) }, seed: 0x9A7C, seedSpacing: 40)

        func place(_ p: SIMD2<Float>, _ k: Int, scale: Float, pebbles: Int, woodPieces: Int, shells: Int) {
            // Direction along the shore: perpendicular to the ground's gradient.
            let gx = terrain.sampleHeight(x: p.x + 1.5, z: p.y) - terrain.sampleHeight(x: p.x - 1.5, z: p.y)
            let gz = terrain.sampleHeight(x: p.x, z: p.y + 1.5) - terrain.sampleHeight(x: p.x, z: p.y - 1.5)
            let along = atan2(-gx, gz)                                        // yaw whose local +Z runs along the contour
            for i in 0..<pebbles {                                            // clumped, with a ~4x size range
                let r1 = noise.unit(Int32(k * 31 + i), 3), r2 = noise.unit(Int32(k * 31 + i), 5), r3 = noise.unit(Int32(k * 31 + i), 7)
                let q = p + SIMD2(cos(r1 * 6.28), sin(r1 * 6.28)) * (r2 * r2 * 2.6 * scale)
                let s = 0.04 + 0.17 * r3 * r3 * r3 * 1.3
                let y = terrain.sampleHeight(x: q.x, z: q.y)
                var one = MeshBuilder(); one.append(pebble.tinted(SIMD3(repeating: 0.8 + 0.4 * r2)), transform: scaling(SIMD3(s * 1.3, s * 0.65, s)))
                batch.add(one, at: SIMD3(q.x, y + s * 0.12, q.y), yaw: r1 * 6.28, prefix: "clutter_pebble")
            }
            for i in 0..<woodPieces {                                         // lying flat, partly buried, roughly along the shore
                let r1 = noise.unit(Int32(k * 17 + i), 41), r2 = noise.unit(Int32(k * 17 + i), 43), r3 = noise.unit(Int32(k * 17 + i), 47)
                let q = p + SIMD2(r1 - 0.5, r2 - 0.5) * 3.2 * scale
                let y = terrain.sampleHeight(x: q.x, z: q.y)
                let len = 0.7 + 1.5 * r3
                var one = MeshBuilder()
                one.append(wood, transform: rotationX(.pi / 2) * scaling(SIMD3(1, len, 1)) * translation(SIMD3(0, -0.5, 0)))   // along local +Z
                batch.add(one, at: SIMD3(q.x, y + 0.02, q.y), yaw: along + (r1 - 0.5) * 0.7, prefix: "clutter_wood", tilt: SIMD2((r2 - 0.5) * 0.12, 0))
            }
            for i in 0..<shells {
                let r1 = noise.unit(Int32(k * 13 + i), 53), r2 = noise.unit(Int32(k * 13 + i), 59)
                let q = p + SIMD2(cos(r1 * 6.28), sin(r1 * 6.28)) * (r2 * 2.2 * scale)
                batch.add(shell, at: SIMD3(q.x, terrain.sampleHeight(x: q.x, z: q.y) + 0.01, q.y), yaw: r1 * 6.28, prefix: "clutter_shell")
            }
        }
        for (k, p) in beachSites.enumerated() {
            let r = noise.unit(Int32(k), 97)
            place(p, k, scale: 1.0, pebbles: 5 + Int(r * 8), woodPieces: r > 0.45 ? 2 + Int(r * 3) : 0, shells: 2 + Int(r * 4))
        }
        for (k, p) in pathSites.enumerated() { place(p, k + 500, scale: 0.8, pebbles: 3 + Int(noise.unit(Int32(k), 99) * 5), woodPieces: 0, shells: 0) }
        batch.commit(scene, device: device)
    }

    // MARK: Lanterns

    /// Stone lanterns every 18 m along the path, alternating sides. This is the main "guidance by light" device:
    /// from any lantern you can see the next one, and they pass by every resonance stone in order.
    static func addLanterns(_ scene: Scene, device: MTLDevice) {
        let (bodyProto, coreProto) = Props.stoneLantern()
        var body = MeshBuilder(), core = MeshBuilder()
        var side: Float = 1
        let pts = Layout.lanternPath.map { SIMD2($0.x, $0.z) }
        var carried: Float = 9           // start the first lantern 9 m along so none sits on the dock pad
        for k in 0..<(pts.count - 1) {
            let a = pts[k], b = pts[k + 1]
            let dir = normalize(b - a), nrm = SIMD2(-dir.y, dir.x)
            let len = length(b - a)
            var s = carried
            while s < len {
                let c = a + dir * s + nrm * 2.6 * side
                side = -side
                let stoneClear = Layout.pads.allSatisfy { length(c - SIMD2($0.center.x, $0.center.z)) > $0.radius + 3 }
                if stoneClear {
                    let y = scene.terrain.sampleHeight(x: c.x, z: c.y)
                    let yaw = noise.unit(Int32(c.x), Int32(c.y)) * 2 * .pi
                    let m = translation(SIMD3(c.x, y, c.y)) * rotationY(yaw)
                    body.append(bodyProto, transform: m)
                    core.append(coreProto, transform: m)
                    scene.colliders.addCylinder(center: c, radius: 0.3, minY: y - 1, maxY: y + 2)
                }
                s += 18
            }
            carried = s - len
        }
        scene.add("lanterns", mesh: body.build(device: device, label: "lanterns"))
        scene.add("lantern_cores", mesh: core.build(device: device, label: "lantern_cores"),
                  uniforms: ObjectUniforms(model: matrix_identity_float4x4, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.62, 0.25, 8)))
    }

    // MARK: Rocks

    static func addRocks(_ scene: Scene, device: MTLDevice) {
        let spots = scatter(spacing: 15, salt: 101, accept: { x, z, h, ny, r in
            guard h > 0.4, isClear(terrain: scene.terrain, x: x, z: z, pathMargin: 4, padMargin: 5) else { return false }
            let steep = ny < 0.92
            let shore = h < 3
            return r < (steep ? 0.42 : shore ? 0.22 : 0.06)
        }, terrain: scene.terrain)
        var batch = Batcher()
        var count = 0
        for s in spots.prefix(150) {
            let y = scene.terrain.sampleHeight(x: s.x, z: s.z)
            let size = 0.35 + 1.9 * pow(s.rand * 7.31 - floor(s.rand * 7.31), 3)
            let rock = Props.rock(seed: UInt32(truncatingIfNeeded: count &* 7919 &+ 13), size: size)
            batch.add(rock, at: SIMD3(s.x, y - size * 0.12, s.z), yaw: s.rand * 40, prefix: "rocks")
            if size > 1.0 {
                scene.colliders.addCylinder(center: SIMD2(s.x, s.z), radius: size * 0.85, minY: y - 1, maxY: y + size * 0.9)
            }
            count += 1
        }
        batch.commit(scene, device: device)
    }

    // MARK: Trees

    /// Where trees are allowed and how dense: altitude band, slope, clear of the path, pads and dock; a low-frequency noise makes
    /// groves (dense), clearings (sparse) and the odd loner.
    static func treeDensity(terrain: Terrain, x: Float, z: Float) -> Float {
        let grove = noise.fbm(x * 0.012 + 30, z * 0.012 - 7, octaves: 3)
        return min(max(0.45 + 1.6 * grove, 0), 1)
    }
    static func treeAllowed(terrain: Terrain, x: Float, z: Float) -> Bool {
        let h = terrain.sampleHeight(x: x, z: z)
        guard h > 2.5, h < 48, terrain.normal(x: x, z: z).y > 0.86 else { return false }
        return isClear(terrain: terrain, x: x, z: z, pathMargin: 6, padMargin: 9)
    }
    /// Blue-noise tree sites: spacing 6-22 m depending on the grove field, deterministic.
    private static var siteCache: [SIMD2<Float>]?
    static func treeSites(terrain: Terrain) -> [SIMD2<Float>] {
        if let c = siteCache { return c }
        let sites = PoissonDisc.sample(min: SIMD2(-290, -380), max: SIMD2(260, 260), rMin: 6, rMax: 22,
                           radius: { 22 - 16 * treeDensity(terrain: terrain, x: $0.x, z: $0.y) },
                           accept: { treeAllowed(terrain: terrain, x: $0.x, z: $0.y) }, seed: 0x7EE5)
        siteCache = sites
        return sites
    }
    /// Height of placed tree `index` (shared by the trees and by the litter that surrounds them).
    static func treeHeight(_ index: Int) -> Float { (6 + 7.5 * noise.unit(Int32(index), 11)) * (0.7 + 0.6 * noise.unit(Int32(index), 29)) }
    /// The litter discs under the placed conifers: radius about 0.4 of the tree's height (the drip line).
    static func duffDiscs(terrain: Terrain) -> [(c: SIMD2<Float>, r: Float)] {
        treeSites(terrain: terrain).prefix(420).enumerated().map { (i, p) in (c: p, r: 1.4 + 0.42 * treeHeight(i)) }
    }

    /// The three level-of-detail batches of every tree cell, and the trunk colliders: deterministic, so built once per run and shared by
    /// every scene (the selftests build dozens).
    private static var treeCache: (cells: [[String: MeshBuilder]], colliders: [(c: SIMD2<Float>, y: Float, h: Float)])?
    static let treeCell: Float = 60

    static func addTrees(_ scene: Scene, device: MTLDevice) {
        let terrain = scene.terrain!
        if treeCache == nil {
            let sites = treeSites(terrain: terrain)
            var cells = [[String: MeshBuilder]](repeating: [:], count: 3)
            var colliders: [(c: SIMD2<Float>, y: Float, h: Float)] = []
            for (count, p) in sites.prefix(420).enumerated() {
                let r1 = noise.unit(Int32(count), 11), r2 = noise.unit(Int32(count), 29), r3 = noise.unit(Int32(count), 47), r4 = noise.unit(Int32(count), 83)
                let y = terrain.sampleHeight(x: p.x, z: p.y)
                let height = treeHeight(count)
                let dead = r4 < 0.04, fallen = r4 > 0.985
                let pine = y > 24 || r3 > 0.55
                let variantIndex = Int(noise.unit(Int32(count), 5) * Float(Trees.variantCount)) % Trees.variantCount
                let h = height / Trees.nominalHeight
                let width = h * (0.85 + 0.3 * noise.unit(Int32(count), 13))
                let lean = (1 + 2 * noise.unit(Int32(count), 71)) * .pi / 180
                let la = noise.unit(Int32(count), 73) * 2 * .pi
                let tilt = fallen ? SIMD2<Float>(0, .pi / 2 - 0.05) : SIMD2(lean * cos(la), lean * sin(la))
                let shade = SIMD3(repeating: 0.8 + 0.4 * noise.unit(Int32(count), 61)) * SIMD3<Float>(1, 1 + 0.15 * (r2 - 0.5), 1 - 0.1 * (r1 - 0.5))
                let at = SIMD3(p.x, y - (fallen ? -0.25 : 0.15), p.y)
                let yaw = r3 * 6.28
                let i = Int(floor(p.x / treeCell)), j = Int(floor(p.y / treeCell))
                for lod in 0..<3 {
                    let mesh: MeshBuilder = (dead || fallen) ? Trees.snagVariant(variantIndex, lod: min(lod, 1)).tinted(SIMD3(repeating: 1))
                        : Trees.variant(pine ? .pine : .cypress, variantIndex, lod: lod).tinted(shade)
                    let m = translation(at) * rotationY(yaw) * rotationX(tilt.x) * rotationZ(tilt.y) * scaling(SIMD3(width, h, width))
                    cells[lod]["trees_L\(lod)_\(i)_\(j)", default: MeshBuilder()].append(mesh, transform: m)
                }
                if !fallen { colliders.append((SIMD2(p.x, p.y), y, height)) }
            }
            treeCache = (cells, colliders)
        }
        let cache = treeCache!
        for c in cache.colliders { scene.colliders.addCylinder(center: c.c, radius: 0.3, minY: c.y - 1, maxY: c.y + c.h) }
        for name in cache.cells[0].keys.sorted() {
            let suffix = String(name.dropFirst("trees_L0".count))
            var names: [String] = []
            for lod in 0..<3 {
                let n = "trees_L\(lod)\(suffix)"
                guard let mb = cache.cells[lod][n], !mb.isEmpty else { continue }
                scene.add(n, mesh: mb.build(device: device, label: n), uniforms: ObjectUniforms(), hidden: lod != 0)
                names.append(n)
            }
            let parts = suffix.split(separator: "_").compactMap { Int($0) }
            if parts.count == 2 {
                let lo = SIMD2(Float(parts[0]) * treeCell, Float(parts[1]) * treeCell)
                scene.lodGroups.append(Scene.LODGroup(names: names, min: lo, max: lo + SIMD2(treeCell, treeCell)))
            }
        }
    }
}
