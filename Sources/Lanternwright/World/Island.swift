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
        mutating func add(_ piece: MeshBuilder, at p: SIMD3<Float>, yaw: Float, prefix: String) {
            let key = "\(prefix)_\(Int(floor(p.x / 120)))_\(Int(floor(p.z / 120)))"
            cells[key, default: MeshBuilder()].append(piece, transform: translation(p) * rotationY(yaw))
        }
        func commit(_ scene: Scene, device: MTLDevice, uniforms: ObjectUniforms = ObjectUniforms(), refractive: Bool = false) {
            for (name, b) in cells.sorted(by: { $0.key < $1.key }) where !b.isEmpty {
                scene.add(name, mesh: b.build(device: device, label: name), uniforms: uniforms, refractive: refractive)
            }
        }
    }

    // MARK: Clutter

    /// Pebbles, shells and driftwood on the beach and along the path's edges: small things that say people and tides were here.
    /// Deterministic, kept off the path itself, the pads and the dock, merged per 120 m cell.
    static func addClutter(_ scene: Scene, device: MTLDevice) {
        let terrain = scene.terrain!
        var pebble = MeshBuilder(), shell = MeshBuilder(), wood = MeshBuilder()
        pebble.icosphere(subdivisions: 1, smooth: false, radius: { _ in 1 }, surface: Surface(color: SIMD3(0.36, 0.34, 0.31), roughness: 0.8))
        shell.cone(radius: 0.07, height: 0.05, segments: 7, smooth: false, surface: Surface(color: SIMD3(0.80, 0.72, 0.62), roughness: 0.5))
        wood.cylinder(radiusTop: 0.045, radiusBottom: 0.065, height: 1.0, segments: 6, surface: Surface(color: SIMD3(0.32, 0.27, 0.21), roughness: 0.9))
        var batch = Batcher()
        let places = scatter(spacing: 3.2, salt: 4242, accept: { x, z, h, ny, r in
            let onBeach = h > 0.15 && h < 1.7
            let besidePath = terrain.pathDistance(x: x, z: z) > 1.6 && terrain.pathDistance(x: x, z: z) < 5.5 && ny > 0.85
            return (onBeach || besidePath) && r < 0.55 && isClear(terrain: terrain, x: x, z: z, pathMargin: 1.2, padMargin: 1.5)
        }, terrain: terrain)
        for (k, p) in places.enumerated() {
            let y = terrain.sampleHeight(x: p.x, z: p.z)
            let yaw = noise.unit(Int32(k), 91) * 2 * .pi
            let kind = noise.unit(Int32(k) &+ 5, 17)
            if kind < 0.6 {                                      // a pebble, squashed and slightly sunk
                let s = 0.07 + 0.12 * noise.unit(Int32(k), 33)
                var one = MeshBuilder(); one.append(pebble, transform: scaling(SIMD3(s * 1.3, s * 0.7, s)))
                batch.add(one, at: SIMD3(p.x, y + s * 0.2, p.z), yaw: yaw, prefix: "clutter_pebble")
            } else if kind < 0.85 {                              // a shell
                batch.add(shell, at: SIMD3(p.x, y + 0.01, p.z), yaw: yaw, prefix: "clutter_shell")
            } else if y < 1.7 {                                  // driftwood lying on the sand
                var one = MeshBuilder()
                let len = 0.8 + 1.4 * noise.unit(Int32(k), 61)
                one.append(wood, transform: rotationZ(.pi / 2) * scaling(SIMD3(1, len, 1)) * translation(SIMD3(0, -0.5, 0)))
                batch.add(one, at: SIMD3(p.x, y + 0.05, p.z), yaw: yaw, prefix: "clutter_wood")
            }
        }
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

    static func addTrees(_ scene: Scene, device: MTLDevice) {
        let spots = scatter(spacing: 10, salt: 211, accept: { x, z, h, ny, r in
            guard h > 2.5, h < 48, ny > 0.86, isClear(terrain: scene.terrain, x: x, z: z, pathMargin: 6, padMargin: 9) else { return false }
            let grove = noise.fbm(x * 0.012 + 30, z * 0.012 - 7, octaves: 3)       // low-frequency clusters
            return r < 0.2 + 0.9 * max(0, grove + 0.05)
        }, terrain: scene.terrain)
        var batch = Batcher()
        var count = 0
        for s in spots.prefix(300) {
            let y = scene.terrain.sampleHeight(x: s.x, z: s.z)
            let height = 6 + 7.5 * (s.rand * 13.7 - floor(s.rand * 13.7))
            let seed = UInt32(truncatingIfNeeded: count &* 104729 &+ 5)
            let tree = (y > 24 || s.rand > 0.55) ? Props.pine(seed: seed, height: height) : Props.cypress(seed: seed, height: height)
            batch.add(tree, at: SIMD3(s.x, y - 0.15, s.z), yaw: s.rand * 90, prefix: "trees")
            scene.colliders.addCylinder(center: SIMD2(s.x, s.z), radius: 0.3, minY: y - 1, maxY: y + height)
            count += 1
        }
        batch.commit(scene, device: device)
    }
}
