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
        /// A piece with its full transform already worked out (see Placement.lay); the cell comes from the transform's position.
        mutating func addPlaced(_ piece: MeshBuilder, transform: float4x4, prefix: String) {
            let p = transform.columns.3
            cells["\(prefix)_\(Int(floor(p.x / 120)))_\(Int(floor(p.z / 120)))", default: MeshBuilder()].append(piece, transform: transform)
        }
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
        var pebble = MeshBuilder(), pebbleSmall = MeshBuilder(), shell = MeshBuilder(), wood = MeshBuilder()
        // F01 W3.1: pebbles are rounded, lumpy stones in the rock material (they were white faceted gems), shells are ribbed scallops, driftwood is a bleached,
        // knobbly timber with a split end. All are placed on the terrain (Placement) and recorded for the contact test.
        let pn = Noise(seed: 4411)
        pebble.icosphere(subdivisions: 1, geometricNormals: true, radius: { d in 0.86 + 0.22 * pn.fbm(d.x * 2.3 + d.z * 3.7, d.y * 2.9 - d.z * 1.7, octaves: 3) }, surface: Surface(color: SIMD3(0.40, 0.37, 0.33), roughness: 0.8, material: .rock))
        pebbleSmall.icosphere(subdivisions: 0, geometricNormals: true, radius: { d in 0.86 + 0.22 * pn.fbm(d.x * 2.3 + d.z * 3.7, d.y * 2.9 - d.z * 1.7, octaves: 2) }, surface: Surface(color: SIMD3(0.40, 0.37, 0.33), roughness: 0.8, material: .rock))
        shell.icosphere(subdivisions: 0, geometricNormals: true, radius: { d in
            let a = atan2(d.z, d.x)
            let rib = 1 + 0.10 * pow(abs(sin(a * 7)), 0.7)
            return 0.7 * rib * (d.y < -0.05 ? 0.5 : 1)                 // a flattened fan: ribs on the dome, a flat underside
        }, surface: Surface(color: SIMD3(0.80, 0.72, 0.62), roughness: 0.55), transform: scaling(SIMD3(0.10, 0.045, 0.085)))
        wood.cylinder(radiusTop: 0.045, radiusBottom: 0.075, height: 1.0, segments: 9, smooth: true, surface: Surface(color: SIMD3(0.42, 0.38, 0.32), roughness: 0.9, material: .timber))   // sun-bleached grey-brown
        for kn in 0..<3 {                                                                   // knobs where branches were
            let t = 0.2 + 0.6 * pn.unit(Int32(kn), 5), a = pn.unit(Int32(kn), 6) * 6.28
            wood.sphere(radius: 0.04, segments: 6, smooth: true, surface: Surface(color: SIMD3(0.40, 0.36, 0.30), roughness: 0.9, material: .timber), transform: translation(SIMD3(cos(a) * 0.06, t, sin(a) * 0.06)))
        }
        var batch = Batcher()
        var placed: [Placement.PlacedProp] = []

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
                var one = MeshBuilder(); one.append((s < 0.09 ? pebbleSmall : pebble).tinted(SIMD3(repeating: 0.8 + 0.4 * r2)), transform: translation(SIMD3(0, s * 0.65, 0)) * scaling(SIMD3(s * 1.3, s * 0.65, s)))
                let tr = Placement.lay(terrain: terrain, x: q.x, z: q.y, heading: r1 * 6.28, halfX: s * 1.3, halfZ: s, sink: s * 0.4)     // lies on the slope, a third sunk
                batch.addPlaced(one, transform: tr, prefix: "clutter_pebble"); placed.append(Placement.record(kind: "pebble", mesh: one, transform: tr))
            }
            for i in 0..<woodPieces {                                         // lying flat, partly buried, roughly along the shore
                let r1 = noise.unit(Int32(k * 17 + i), 41), r2 = noise.unit(Int32(k * 17 + i), 43), r3 = noise.unit(Int32(k * 17 + i), 47)
                let q = p + SIMD2(r1 - 0.5, r2 - 0.5) * 3.2 * scale
                let len = 0.7 + 1.5 * r3
                var one = MeshBuilder()
                one.append(wood, transform: translation(SIMD3(0, 0.06, 0)) * rotationX(.pi / 2) * scaling(SIMD3(1, len, 1)) * translation(SIMD3(0, -0.5, 0)))   // along local +Z, underside at y = 0
                let tr = Placement.lay(terrain: terrain, x: q.x, z: q.y, heading: along + (r1 - 0.5) * 0.7, halfX: 0.07, halfZ: len / 2, sink: 0.035)
                batch.addPlaced(one, transform: tr, prefix: "clutter_wood"); placed.append(Placement.record(kind: "driftwood", mesh: one, transform: tr))
            }
            for i in 0..<shells {
                let r1 = noise.unit(Int32(k * 13 + i), 53), r2 = noise.unit(Int32(k * 13 + i), 59)
                let q = p + SIMD2(cos(r1 * 6.28), sin(r1 * 6.28)) * (r2 * 2.2 * scale)
                let tr = Placement.lay(terrain: terrain, x: q.x, z: q.y, heading: r1 * 6.28, halfX: 0.07, halfZ: 0.07, sink: 0.012)
                batch.addPlaced(shell, transform: tr, prefix: "clutter_shell"); placed.append(Placement.record(kind: "shell", mesh: shell, transform: tr))
            }
        }
        for (k, p) in beachSites.enumerated() {
            let r = noise.unit(Int32(k), 97)
            place(p, k, scale: 1.0, pebbles: 5 + Int(r * 8), woodPieces: r > 0.45 ? 2 + Int(r * 3) : 0, shells: 2 + Int(r * 4))
        }
        for (k, p) in pathSites.enumerated() { place(p, k + 500, scale: 0.8, pebbles: 3 + Int(noise.unit(Int32(k), 99) * 5), woodPieces: 0, shells: 0) }
        batch.commit(scene, device: device)
        scene.placed += placed
    }

    // MARK: Lanterns

    /// Stone lanterns every 18 m along the path, alternating sides. This is the main "guidance by light" device:
    /// from any lantern you can see the next one, and they pass by every resonance stone in order.
    static func addLanterns(_ scene: Scene, device: MTLDevice) {
        let (bodyProto, coreProto) = Props.stoneLantern()
        var body = MeshBuilder(), core = MeshBuilder()
        var side: Float = 1
        let pts = Layout.route.map { SIMD2($0.x, $0.z) }
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
                    // F01 W3.5: the lantern stays vertical, its pivot at the highest ground under the base, and a stone footing with a soil apron reaches
                    // down to the lowest, so the base meets the slope on every side.
                    let up = Placement.upright(terrain: scene.terrain, x: c.x, z: c.y, radius: 0.36, yaw: yaw)
                    let m = up.transform
                    body.append(bodyProto, transform: m)
                    core.append(coreProto, transform: m)
                    let foot = Placement.skirt(radius: 0.30, depth: up.depth, surface: Surface(color: SIMD3(0.50, 0.47, 0.43), roughness: 0.9, material: .dressed))
                    body.append(foot, transform: m)
                    let footing = Placement.skirt(radius: 0.30, depth: up.depth, apron: false, surface: Surface(color: SIMD3(0.50, 0.47, 0.43), roughness: 0.9, material: .dressed))
                    scene.placed.append(Placement.record(kind: "lantern", mesh: footing, transform: m))
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
            guard h > 0.4, ny > 0.80, isClear(terrain: scene.terrain, x: x, z: z, pathMargin: 4, padMargin: 5) else { return false }      // no boulders on cliffs: they would be buried to nothing
            let steep = ny < 0.92
            let shore = h < 3
            return r < (steep ? 0.42 : shore ? 0.22 : 0.06)
        }, terrain: scene.terrain)
        var batch = Batcher()
        var count = 0
        for s in spots.prefix(150) {
            let y = scene.terrain.sampleHeight(x: s.x, z: s.z)
            let size = 0.35 + 1.9 * pow(s.rand * 7.31 - floor(s.rand * 7.31), 3)
            var rock = MeshBuilder()
            rock.append(Props.rock(seed: UInt32(truncatingIfNeeded: count &* 7919 &+ 13), size: size), transform: translation(SIMD3(0, size * 0.3, 0)))      // underside at local y = 0
            let tr = Placement.lay(terrain: scene.terrain, x: s.x, z: s.z, heading: s.rand * 40, halfX: size * 1.5, halfZ: size * 1.35, sink: size * (0.2 + 1.2 * (1 - scene.terrain.normal(x: s.x, z: s.z).y)))      // deeper on a slope: boulders sit INTO a hillside
            batch.addPlaced(rock, transform: tr, prefix: "rocks")
            scene.placed.append(Placement.record(kind: "rock", mesh: rock, transform: tr))
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
    private static var treeCache: (cells: [[String: MeshBuilder]], colliders: [(c: SIMD2<Float>, y: Float, h: Float)], litter: [String: MeshBuilder], placed: [Placement.PlacedProp])?
    static let treeCell: Float = 60

    static func addTrees(_ scene: Scene, device: MTLDevice) {
        let terrain = scene.terrain!
        if treeCache == nil {
            let sites = treeSites(terrain: terrain)
            var cells = [[String: MeshBuilder]](repeating: [:], count: 3)
            var colliders: [(c: SIMD2<Float>, y: Float, h: Float)] = []
            var litter: [String: MeshBuilder] = [:]
            var placed: [Placement.PlacedProp] = []
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
                // The pivot sits at the highest ground under the trunk (the trunk is sunk 10 cm there) and a footing reaches down to the lowest (Placement).
                let sm = Placement.samples(terrain: terrain, x: p.x, z: p.y, radius: 0.55 * width)
                let at = fallen ? SIMD3(p.x, y + 0.25, p.y) : SIMD3(p.x, sm.high - 0.1, p.y)
                let yaw = r3 * 6.28
                let stagger = 3 + (noise.unit(Int32(count), 97) * 2 - 1)                // position.w = 3 + stagger in -1...1
                let i = Int(floor(p.x / treeCell)), j = Int(floor(p.y / treeCell))
                for lod in 0..<3 {
                    let mesh: MeshBuilder = (dead || fallen) ? Trees.snagVariant(variantIndex, lod: min(lod, 1)).tinted(SIMD3(repeating: 1))
                        : Trees.variant(pine ? .pine : .cypress, variantIndex, lod: lod).tinted(shade)
                    let m = translation(at) * rotationY(yaw) * rotationX(tilt.x) * rotationZ(tilt.y) * scaling(SIMD3(width, h, width))
                    let key = "trees_L\(lod)_\(i)_\(j)"
                    var cell = cells[lod][key] ?? MeshBuilder()
                    let start = cell.vertices.count
                    cell.append(mesh, transform: m)
                    cell.adjust(from: start) { $0.position.w = stagger }              // the same stagger on every level of this tree (see tree_lod_level)
                    if !fallen {
                        let foot = Placement.skirt(radius: 0.5 * width, depth: max(0.05, sm.high - 0.1 - sm.low), surface: Surface(color: SIMD3(0.19, 0.13, 0.09) * (0.9 + 0.2 * r1), roughness: 0.95))
                        let ft = translation(at) * rotationY(yaw)
                        let s0 = cell.vertices.count
                        cell.append(foot, transform: ft)
                        cell.adjust(from: s0) { $0.position.w = stagger }
                        if lod == 0 {
                            let footing = Placement.skirt(radius: 0.5 * width, depth: max(0.05, sm.high - 0.1 - sm.low), apron: false, surface: Surface(color: SIMD3(0.19, 0.13, 0.09), roughness: 0.95))
                            placed.append(Placement.record(kind: "trunk", mesh: footing, transform: ft))
                        }
                    }
                    cells[lod][key] = cell
                }
                if !fallen { colliders.append((SIMD2(p.x, p.y), y, height)) }
                // Fallen cones and twigs on the ground around the trunk, each placed on the terrain under it (they used to be baked into the tree and floated).
                if !fallen {
                    let litterKey = "litter_\(i)_\(j)"
                    for k in 0..<13 {
                        let cone = k < 7
                        let salt = Int32(count * 40 + k)
                        let a = noise.unit(salt, 201) * 2 * .pi, d = (cone ? 0.7 + 1.8 * noise.unit(salt, 202) : 0.6 + 2.0 * noise.unit(salt, 202)) * max(h, 0.7)
                        let q = SIMD2(p.x + cos(a) * d, p.y + sin(a) * d)
                        let rr = { (n: Int) in noise.unit(salt, Int32(210 + n)) }
                        if cone {
                            let piece = Trees.litterCone(rr)
                            let tr = Placement.lay(terrain: terrain, x: q.x, z: q.y, heading: noise.unit(salt, 203) * 6.28, halfX: piece.halfX, halfZ: piece.halfZ, sink: piece.sink)
                            litter[litterKey, default: MeshBuilder()].append(piece.mesh, transform: tr)
                            placed.append(Placement.record(kind: "cone", mesh: piece.mesh, transform: tr))
                        } else {
                            // A twig is long and bends with the ground: its stations follow the terrain (in world space), so no part hovers over a dip.
                            let twig = Trees.litterTwig(rr)
                            let heading = noise.unit(salt, 203) * 6.28
                            let dir = SIMD2(sin(heading), cos(heading))
                            let rad = twig.halfX, len = twig.halfZ * 2
                            var pts: [SIMD3<Float>] = []
                            for st in 0..<5 {
                                let u = Float(st) / 4 * len
                                let wx = q.x + dir.x * (u - len / 2), wz = q.y + dir.y * (u - len / 2)
                                pts.append(SIMD3(wx, terrain.sampleHeight(x: wx, z: wz) + rad * 0.6, wz))
                            }
                            var mesh = MeshBuilder()
                            mesh.tube(points: pts, radii: [rad, rad * 0.9, rad * 0.8, rad * 0.65, rad * 0.4], sides: 4, surface: Surface(color: SIMD3(0.18, 0.13, 0.09) * (0.8 + 0.4 * rr(4)), roughness: 0.95))
                            litter[litterKey, default: MeshBuilder()].append(mesh)
                            placed.append(Placement.record(kind: "twig", mesh: mesh, transform: matrix_identity_float4x4))
                        }
                    }
                }
            }
            treeCache = (cells, colliders, litter, placed)
        }
        let cache = treeCache!
        for c in cache.colliders { scene.colliders.addCylinder(center: c.c, radius: 0.3, minY: c.y - 1, maxY: c.y + c.h) }
        scene.placed += cache.placed
        for name in cache.cells[0].keys.sorted() {
            let suffix = String(name.dropFirst("trees_L0".count))
            var names: [String] = []
            for lod in 0..<3 {
                let n = "trees_L\(lod)\(suffix)"
                guard let mb = cache.cells[lod][n], !mb.isEmpty else { continue }
                scene.add(n, mesh: mb.build(device: device, label: n), uniforms: ObjectUniforms(lod: SIMD4(1, Float(lod), 0, 0)), hidden: lod != 0)
                names.append(n)
            }
            // The litter of this cell belongs to the near level only: it is drawn (and dithered out with the level) wherever level 0 is.
            var extras: [String] = []
            if let lit = cache.litter["litter\(suffix)"], !lit.isEmpty {
                let n = "litter\(suffix)"
                scene.add(n, mesh: lit.build(device: device, label: n), uniforms: ObjectUniforms(lod: SIMD4(1, 0, 0, 0)), hidden: false)
                extras.append(n)
            }
            let parts = suffix.split(separator: "_").compactMap { Int($0) }
            if parts.count == 2 {
                let lo = SIMD2(Float(parts[0]) * treeCell, Float(parts[1]) * treeCell)
                scene.lodGroups.append(Scene.LODGroup(names: names, extras: extras, min: lo, max: lo + SIMD2(treeCell, treeCell)))
            }
        }
    }
}
