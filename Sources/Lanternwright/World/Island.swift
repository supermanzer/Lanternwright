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
        addTrees(scene, device: device)
    }

    // MARK: Placement rules

    /// True if (x, z) is clear of the path, the landmark pads, the dock and the islet's lens ring.
    static func isClear(terrain: Terrain, x: Float, z: Float, pathMargin: Float, padMargin: Float) -> Bool {
        if terrain.pathDistance(x: x, z: z) < pathMargin { return false }
        let p = SIMD2(x, z)
        for pad in Layout.pads where length(p - SIMD2(pad.center.x, pad.center.z)) < pad.radius + padMargin { return false }
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
        func commit(_ scene: Scene, device: MTLDevice, uniforms: ObjectUniforms = ObjectUniforms()) {
            for (name, b) in cells.sorted(by: { $0.key < $1.key }) where !b.isEmpty {
                scene.add(name, mesh: b.build(device: device, label: name), uniforms: uniforms)
            }
        }
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
