import Metal
import simd

struct DrawItem {
    var name: String
    var mesh: Mesh
    var uniforms: ObjectUniforms
    /// Hidden items are skipped by every pass (used for things that appear later, such as puzzle beams).
    var hidden = false
    /// Glass: drawn in its own pass after the opaque scene (it refracts a copy of it), and casts no shadow.
    var refractive = false

    /// World-space bounding box: the mesh's local box transformed by the model matrix.
    var worldBounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for i in 0..<8 {
            let c = SIMD3(i & 1 == 0 ? mesh.boundsMin.x : mesh.boundsMax.x,
                          i & 2 == 0 ? mesh.boundsMin.y : mesh.boundsMax.y,
                          i & 4 == 0 ? mesh.boundsMin.z : mesh.boundsMax.z)
            let w = uniforms.model * SIMD4(c, 1)
            lo = simd_min(lo, SIMD3(w.x, w.y, w.z)); hi = simd_max(hi, SIMD3(w.x, w.y, w.z))
        }
        return (lo, hi)
    }
}

/// Everything the renderer draws. World-building code fills `items`.
final class Scene {
    let kind: WorldKind
    init(kind: WorldKind = .varrow) { self.kind = kind }

    private(set) var items: [DrawItem] = []
    private var nameIndex: [String: Int] = [:]

    func add(_ name: String, mesh: Mesh, uniforms: ObjectUniforms = ObjectUniforms(), hidden: Bool = false, refractive: Bool = false) {
        precondition(nameIndex[name] == nil, "duplicate scene item \(name)")
        nameIndex[name] = items.count
        items.append(DrawItem(name: name, mesh: mesh, uniforms: uniforms, hidden: hidden, refractive: refractive))
    }

    func has(_ name: String) -> Bool { nameIndex[name] != nil }

    /// Modify an item in place by name (animation, visibility, glow).
    func update(_ name: String, _ change: (inout DrawItem) -> Void) {
        guard let i = nameIndex[name] else { return }
        change(&items[i])
    }

    /// Level-of-detail groups: items that are alternatives of each other (near, mid, far versions of the same trees). Exactly one is
    /// visible per group, chosen from the eye's distance to the group's footprint. Applied by the renderer each frame.
    struct LODGroup { var names: [String]; var min: SIMD2<Float>; var max: SIMD2<Float> }
    var lodGroups: [LODGroup] = []
    static let lodDistances: [Float] = [45, 130]
    func applyLOD(eye: SIMD3<Float>) {
        for g in lodGroups {
            let dx = max(g.min.x - eye.x, 0, eye.x - g.max.x), dz = max(g.min.y - eye.z, 0, eye.z - g.max.y)
            let d = (dx * dx + dz * dz).squareRoot()
            let level = d < Scene.lodDistances[0] ? 0 : (d < Scene.lodDistances[1] ? 1 : 2)
            for (i, name) in g.names.enumerated() { update(name) { $0.hidden = (i != min(level, g.names.count - 1)) } }
        }
    }
    var terrain: Terrain!
    var colliders = Colliders()
    var walkables: [Walkable] = []
    /// Index in `walkables` of the causeway, which starts disabled and is enabled once the slabs have risen.
    var causewayIndex: Int?

    /// What you are standing on at (x, z): a walkable strip's material, or inferred from the terrain
    /// (the same rules the terrain shader uses to pick grass, sand, rock and path).
    func surface(x: Float, z: Float) -> SurfaceKind {
        let p = SIMD2(x, z)
        let terrainY = terrain.sampleHeight(x: x, z: z)
        for w in walkables { if let h = w.height(at: p), h > terrainY - 0.05 { return w.surface } }
        if terrain.pathWeight(x: x, z: z) > 0.5 { return .earth }
        if terrainY < 2.2 { return .sand }
        if terrain.normal(x: x, z: z).y < 0.8 || terrainY > 55 { return .rock }
        return .grass
    }

    /// Distance to the nearest water within `maxRadius`, found by probing rings in 24 directions
    /// (cheap enough to call a few times a second). Returns maxRadius if the sea is out of range.
    func shoreDistance(x: Float, z: Float, maxRadius: Float = 160) -> Float {
        if terrain.sampleHeight(x: x, z: z) < 0 { return 0 }
        var best = maxRadius
        for k in 0..<24 {
            let a = Float(k) / 24 * 2 * .pi
            let d = SIMD2(cos(a), sin(a))
            var r: Float = 4
            while r < best {
                if terrain.sampleHeight(x: x + d.x * r, z: z + d.y * r) < 0 { best = r; break }
                r *= 1.25
            }
        }
        return best
    }

    /// Height of whatever you would stand on at (x, z): the terrain or a walkable strip, whichever is higher.
    func groundHeight(x: Float, z: Float) -> Float {
        var h = terrain.sampleHeight(x: x, z: z)
        let p = SIMD2(x, z)
        for w in walkables { if let wh = w.height(at: p) { h = max(h, wh) } }
        return h
    }

    static func make(_ kind: WorldKind, device: MTLDevice) -> Scene {
        switch kind {
        case .varrow: return makeWorld(device: device)
        case .glassWood: return GlassWood.build(device: device)
        }
    }

    static func makeWorld(device: MTLDevice) -> Scene {
        let scene = Scene()
        scene.terrain = Terrain()
        for chunk in TerrainMesh.buildChunks(terrain: scene.terrain, device: device) {
            scene.add(chunk.name, mesh: chunk.mesh, uniforms: chunk.uniforms)
        }

        // Solid things (their meshes arrive in M3; the collision shapes are fixed by the layout now).
        let lh = Layout.lighthouse
        scene.colliders.addCylinder(center: SIMD2(lh.x, lh.z), radius: 5.5, minY: lh.y - 1, maxY: lh.y + 30)
        // The dock: planks 2.4 m wide from the beach out over the water.
        let dock = Layout.dockStrip()
        scene.walkables.append(Walkable(a: dock.a, b: dock.b, halfWidth: 1.2, y0: dock.y0, y1: dock.y1))
        Island.populate(scene, device: device)
        return scene
    }
}
