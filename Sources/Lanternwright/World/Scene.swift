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

    /// F04 L1 (#57: "should a beam of light throw a shadow?"): light does not cast shadows. `lightOnly` marks the things that are only light (set when the item is added, from
    /// `isLightOnly`): the beams, the columns of light, the altar glow, the lanterns' and the lens's cores and rings, the source and return cores, the lamps and the pane markers.
    /// A blazing emitter (emissive 3 or more: the lit lens, a lamp) is light too, read every frame so the lens stops casting once lit. Solid things with a faint glow of their own
    /// (the stones' glyph faces 0.3, caps, mirrors, chimes, glyph decals) are NOT light: they keep their shadows. Glass never casts.
    var lightOnly = false
    var castsShadow: Bool { !refractive && !lightOnly && uniforms.emissive.w < 3 }
    static func isLightOnly(_ name: String) -> Bool {
        name.hasPrefix("beam_") || name.hasPrefix("gw_beam_") || name.hasPrefix("gw_column") || name == "gw_altar_glow" || name.hasPrefix(LanternChain.coreName) || name == "lens_core" || name == "lens_ring"
            || name == "gw_return_core" || name == "gw_return_ring" || name == "gw_source" || name == "gw_lamps" || (name.hasPrefix("gw_pane_") && name.hasSuffix("_marker"))
    }

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
        var item = DrawItem(name: name, mesh: mesh, uniforms: uniforms, hidden: hidden, refractive: refractive)
        item.lightOnly = DrawItem.isLightOnly(name)
        items.append(item)
    }

    func has(_ name: String) -> Bool { nameIndex[name] != nil }

    /// Modify an item in place by name (animation, visibility, glow).
    func update(_ name: String, _ change: (inout DrawItem) -> Void) {
        guard let i = nameIndex[name] else { return }
        change(&items[i])
    }

    /// Level-of-detail groups: items that are alternatives of each other (near, mid, far versions of the same trees). Exactly one is
    /// visible per group, chosen from the eye's distance to the group's footprint. Applied by the renderer each frame.
    /// `extras` are items that belong to the near level only (the cell's cones and twigs): drawn whenever level 0 is.
    struct LODGroup { var names: [String]; var extras: [String] = []; var min: SIMD2<Float>; var max: SIMD2<Float> }
    var lodGroups: [LODGroup] = []
    static let lodDistances: [Float] = [45, 130]
    /// Which levels of a tree cell can be needed when its box is `d` metres from the eye (R09). The shader decides per tree and per pixel
    /// (`tree_lod_level`: 45 m and 130 m, +-7.5 % bands, +-10 m stagger per tree); a level is hidden here only when no tree in the cell can need
    /// it. The trees of a cell are between `d` and `d + diagonal` away, so neighbouring levels overlap and two are drawn inside a band.
    static func lodLevelsDrawn(boxDistance d: Float, diagonal: Float) -> [Bool] {
        [d < 45 + 10 + 3.4, d + diagonal > 45 - 10 - 3.4 && d < 130 + 10 + 9.75, d + diagonal > 130 - 10 - 9.75]
    }
    /// Debug (`--hard-lod`): the pre-R09 behaviour, one level per cell chosen by distance to its box, no dithering. Only for measuring.
    static var hardLOD = false
    /// Debug (selftest `needles`): draw no conifer cells, to render the background a crown stands against.
    nonisolated(unsafe) static var hideTrees = false
    /// Debug (`--hide <text>`): draw no item whose name contains this, for bisecting what draws or shadows something in a frame.
    nonisolated(unsafe) static var hideNamed: String?
    /// Put the hidden flags back as they were (`hiddenFlags`), after a tool has switched layers off.
    var hiddenFlags: [Bool] { get { items.map(\.hidden) } set { for (i, h) in newValue.enumerated() where i < items.count { items[i].hidden = h } } }
    func applyLOD(eye: SIMD3<Float>) {
        defer { if let h = Scene.hideNamed { for i in items.indices where items[i].name.contains(h) { items[i].hidden = true } }
               if Scene.hideTrees { for i in items.indices where items[i].name.hasPrefix("trees_") || items[i].name.hasPrefix("needles_") { items[i].hidden = true } }
               if !RenderLayer.off.isEmpty { for i in items.indices { if let l = RenderLayer.of(name: items[i].name, refractive: items[i].refractive), RenderLayer.off.contains(l) { items[i].hidden = true } } } }
        if Scene.hardLOD {
            for g in lodGroups {
                let dx = max(g.min.x - eye.x, 0, eye.x - g.max.x), dz = max(g.min.y - eye.z, 0, eye.z - g.max.y)
                let d = (dx * dx + dz * dz).squareRoot()
                let level = d < Scene.lodDistances[0] ? 0 : (d < Scene.lodDistances[1] ? 1 : 2)
                for (i, name) in g.names.enumerated() { update(name) { $0.hidden = (i != min(level, g.names.count - 1)); $0.uniforms.lod.x = 0 } }
                for name in g.extras { update(name) { $0.hidden = level != 0; $0.uniforms.lod.x = 0 } }
            }
            return
        }
        for g in lodGroups {
            let dx = max(g.min.x - eye.x, 0, eye.x - g.max.x), dz = max(g.min.y - eye.z, 0, eye.z - g.max.y)
            let d = (dx * dx + dz * dz).squareRoot()
            let diagonal = ((g.max.x - g.min.x) * (g.max.x - g.min.x) + (g.max.y - g.min.y) * (g.max.y - g.min.y)).squareRoot()
            let drawn = Scene.lodLevelsDrawn(boxDistance: d, diagonal: diagonal)
            for (i, name) in g.names.enumerated() { update(name) { $0.hidden = !drawn[min(i, 2)]; $0.uniforms.lod.x = 1 } }
            for name in g.extras { update(name) { $0.hidden = !drawn[0]; $0.uniforms.lod.x = 1 } }
        }
    }
    var terrain: Terrain!
    /// Every piece placed on the ground (cones, twigs, pebbles, rocks, lanterns, trunk footings...), for the contact selftest (see Placement).
    var placed: [Placement.PlacedProp] = []
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
        if platforms.contains(where: { $0.contains(p) && $0.top > terrainY + 0.02 }) || stoneZones.contains(where: { simd_length(p - $0.center) < $0.radius }) { return .stone }
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
        for pl in platforms where pl.contains(p) { h = max(h, pl.top) }
        return h
    }

    /// A flat-topped block you can step onto (the lighthouse plinth and doorstep): a disc or an axis-aligned rectangle.
    struct Platform {
        var center: SIMD2<Float>
        var radius: Float = 0                      // > 0: a disc
        var halfSize: SIMD2<Float> = .zero         // otherwise a rectangle
        var top: Float
        func contains(_ p: SIMD2<Float>) -> Bool {
            if radius > 0 { return simd_length(p - center) <= radius }
            let d = simd_abs(p - center)
            return d.x <= halfSize.x && d.y <= halfSize.y
        }
    }
    var platforms: [Platform] = []
    /// Ground that is paved stone though it is not a step (the Glass Wood's inlaid arrival plate): footsteps ring off it.
    var stoneZones: [(center: SIMD2<Float>, radius: Float)] = []

    /// What is under the foot, as weights for the footstep voice (order of `StepMaterial`), and how pebbly the ground is. Surfaces blend:
    /// sand fades to grass over the beach edge (wet near the waterline, dry above it), the path softens into the grass, rock takes over
    /// on steep and high ground, and the dock's planks give way to sand over its landward metre or two.
    func surfaceMix(x: Float, z: Float) -> (mix: StepMix, pebble: Float) {
        let p = SIMD2(x, z)
        let y = terrain.sampleHeight(x: x, z: z)
        var grass: Float = 1, sand: Float = 0, rock: Float = 0, earth: Float = 0, stone: Float = 0, wood: Float = 0
        sand = 1 - smoothstep(1.6, 2.8, y); grass = 1 - sand
        let r = max(smoothstep(0.86, 0.74, terrain.normal(x: x, z: z).y), smoothstep(50, 58, y))
        grass *= 1 - r; sand *= 1 - r; rock = r
        let e = smoothstep(0.2, 0.8, terrain.pathWeight(x: x, z: z))
        grass *= 1 - e; sand *= 1 - e; rock *= 1 - e; earth = e
        // Paved stone: the lighthouse plinth and steps, the inlaid plate. Hard edges: a boot meets stone at once.
        if platforms.contains(where: { $0.contains(p) && $0.top > y + 0.02 }) { stone = 1 }
        for z in stoneZones { stone = max(stone, 1 - smoothstep(z.radius - 0.4, z.radius, simd_length(p - z.center))) }
        // Walkable strips (the dock, the causeway): full weight in the middle, fading over the first and last 1.3 m.
        for w in walkables {
            guard let h = w.height(at: p), h > y - 0.05 else { continue }
            let ab = w.b - w.a, len = simd_length(ab), dir = ab / len
            let s = simd_dot(p - w.a, dir)
            let fade = smoothstep(0, 1.3, s) * smoothstep(0, 1.3, len - s)
            if w.surface == .wood { wood = max(wood, fade) } else { stone = max(stone, fade) }
        }
        let keep = 1 - min(1, wood + stone)
        let wet = 1 - smoothstep(0.1, 0.9, y)
        var mix = StepMix(repeating: 0)
        mix[StepMaterial.grass.rawValue] = grass * keep
        mix[StepMaterial.drySand.rawValue] = sand * (1 - wet) * keep
        mix[StepMaterial.wetSand.rawValue] = sand * wet * keep
        mix[StepMaterial.earth.rawValue] = earth * keep
        mix[StepMaterial.rock.rawValue] = rock * keep
        mix[StepMaterial.stone.rawValue] = stone
        mix[StepMaterial.wood.rawValue] = wood
        let pebble = smoothstep(0.62, 0.8, Island.noise.value(x * 6, z * 6)) * e
        return (mix, pebble)
    }

    /// How hollow the planks sound under (x, z) (F01 W6.1): 0 = planks resting on the ground (a dull thud, a scuff of sand), 1 = suspended over open space (the
    /// full cavity boom). From the CLEARANCE: the deck's height above whatever is under it, the terrain or the sea surface (y = 0), whichever is higher.
    func hollowness(x: Float, z: Float) -> Float {
        let p = SIMD2(x, z)
        for w in walkables where w.surface == .wood {
            guard let h = w.height(at: p) else { continue }
            let under = max(terrain.sampleHeight(x: x, z: z), 0)
            return smoothstep(0.15, 0.8, h - under)
        }
        return 0
    }

    /// Which dock plank the foot is on (boards run across the dock, 0.275 m apart): each plank gets its own pitch.
    func plankIndex(x: Float, z: Float) -> Int {
        let s = Layout.dockStrip()
        let ab = s.b - s.a
        return Int(floor(simd_dot(SIMD2(x, z) - s.a, ab / simd_length(ab)) / 0.275))
    }
    func isOnPlatform(_ p: SIMD2<Float>) -> Bool { platforms.contains { $0.contains(p) } }
    /// True where the ground under `p` is something built to be stepped onto: a platform (stair, plinth, dais) or a deck (the dock, the causeway once it has risen).
    func isOnStep(_ p: SIMD2<Float>) -> Bool { isOnPlatform(p) || walkables.contains { $0.height(at: p) != nil } }

    static func make(_ kind: WorldKind, device: MTLDevice) -> Scene {
        switch kind {
        case .varrow: return makeWorld(device: device)
        case .glassWood: return GlassWood.build(device: device)
        }
    }

    static func makeWorld(device: MTLDevice) -> Scene {
        let scene = Scene()
        scene.terrain = Terrain()
        scene.terrain.setDuff(Island.duffDiscs(terrain: scene.terrain))
        for chunk in TerrainMesh.buildChunks(terrain: scene.terrain, device: device) {
            scene.add(chunk.name, mesh: chunk.mesh, uniforms: chunk.uniforms)
        }

        // Solid things (their meshes arrive in M3; the collision shapes are fixed by the layout now).
        let lh = Layout.lighthouse
        scene.colliders.addCylinder(center: SIMD2(lh.x, lh.z), radius: Lighthouse.colliderRadius, minY: lh.y - 1, maxY: lh.y + 30)
        // The dock: planks 2.4 m wide from the beach out over the water.
        let dock = Layout.dockStrip()
        scene.walkables.append(Walkable(a: dock.a, b: dock.b, halfWidth: 1.2, y0: dock.y0, y1: dock.y1))
        Island.populate(scene, device: device)
        if Props.includeMaterialSheet { Props.addMaterialSheet(scene, device: device) }
        return scene
    }
}
