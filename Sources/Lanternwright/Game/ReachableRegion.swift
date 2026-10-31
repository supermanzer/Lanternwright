import simd

/// M10.6: the ground a player can stand on in a world: the navigation corridors and plazas, buffered by the margin (the far edge of the margin is the hard limit).
/// This is what the graphics side asks (builder A's G10.3.6 to G10.3.9): how far is this prop from anywhere the eye can be? Everything is horizontal and
/// conservative (a prop can only be as near as this says, never nearer), so a decision made from it (a pinned LOD, a skipped chunk, a shadow bound) is safe.
///
/// Typical use: `let region = ReachableRegion.make(scene.kind, scene: scene)` once when a world is built, then `region.minDistance(item: i)` for `scene.items[i]`
/// (precomputed from the item's bounding sphere at build time; items that move, such as the lens, are measured where they were built).
struct ReachableRegion {
    let network: NavNetwork
    /// Metres of margin beyond the corridor edge (`Player.marginWidth`).
    let margin: Float
    /// The x, z box that holds the whole region.
    let bounds: (min: SIMD2<Float>, max: SIMD2<Float>)
    /// The highest an eye can be: the highest ground inside the region plus the eye height.
    let maxEyeHeight: Float
    /// For each of the scene's items, in order: metres from the region to its bounding sphere (0 when it touches or lies inside the region).
    private(set) var itemDistances: [Float] = []

    init(network: NavNetwork, margin: Float = Player.marginWidth, groundHeight: (Float, Float) -> Float) {
        self.network = network; self.margin = margin
        var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
        for t in network.trails { for (p, w) in zip(t.points, t.halfWidths) { lo = simd_min(lo, p - (w + margin)); hi = simd_max(hi, p + (w + margin)) } }
        for pl in network.plazas { lo = simd_min(lo, pl.center - (pl.radius + margin)); hi = simd_max(hi, pl.center + (pl.radius + margin)) }
        bounds = (lo, hi)
        var top = -Float.infinity
        var z = lo.y
        while z <= hi.y { var x = lo.x; while x <= hi.x { if network.signedDistance(SIMD2(x, z)) <= margin { top = max(top, groundHeight(x, z)) }; x += 2 }; z += 2 }
        maxEyeHeight = top + Player.eyeHeight
    }

    /// The region for a guidance setting (Guided by default; Loose is wider with a deeper margin). The region does not change by itself when the player changes the
    /// setting: rebuild it then. Free roam has no region.
    static func make(_ kind: WorldKind, scene: Scene, guidance: Guidance = .guided, margin: Float? = nil) -> ReachableRegion {
        let net = Layout.Navigation.network(for: kind, guidance: guidance == .free ? .guided : guidance)!
        let margin = margin ?? (guidance == .loose ? Player.marginWidth * Guidance.looseMargin : Player.marginWidth)
        var r = ReachableRegion(network: net, margin: margin, groundHeight: { scene.groundHeight(x: $0, z: $1) })
        r.itemDistances = scene.items.map { item in
            let box = item.worldBounds
            return r.distance(toSphere: (box.min + box.max) / 2, radius: length(box.max - box.min) / 2)
        }
        return r
    }

    /// Inside the corridors or their margin: a place the feet can be.
    func contains(_ p: SIMD2<Float>) -> Bool { network.signedDistance(p) <= margin }
    /// S04.2: reachable NOW in the Tide Archive: inside the region AND, where the sea covers the ground at game time `time`, no deeper than the player can wade (`Tide.wadeDepth`). In the other worlds the sea
    /// does not move, so this is `contains`. The region itself is the dry-land corridor set; the tide takes places out of it for part of each cycle.
    func reachableNow(_ p: SIMD3<Float>, time: Float, kind: WorldKind) -> Bool {
        guard contains(SIMD2(p.x, p.z)) else { return false }
        return kind != .tideArchive || Tide.isWadeable(ground: p.y, time: time)
    }
    /// Metres from the region (0 inside it).
    func distance(to p: SIMD2<Float>) -> Float { max(network.signedDistance(p) - margin, 0) }
    /// Metres from the region to a sphere (0 when they touch). Horizontal, so it never overestimates.
    func distance(toSphere center: SIMD3<Float>, radius: Float) -> Float { max(distance(to: SIMD2(center.x, center.z)) - radius, 0) }
    /// The precomputed distance for `scene.items[index]` (0 for an index out of range: nothing is assumed far).
    func minDistance(item index: Int) -> Float { index >= 0 && index < itemDistances.count ? itemDistances[index] : 0 }
}
