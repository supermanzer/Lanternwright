import simd

/// M10.3: where the player may walk. A world's reachable ground is a set of soft CORRIDORS: trails (a centre line with a half-width at each point) and plazas
/// (a disc round a landmark). Everything is 2D (x, z, metres); eye height and the ground itself belong to other systems. The data is authored in
/// `Layout.Navigation` (positions live in Layout); this file only knows how to ask questions of it.
///
/// The shape of the union is `min over regions of (distance - width)`, so `signedDistance` is negative inside, zero on the edge, and continuous
/// everywhere (the half-width of a trail is interpolated along each leg, and two legs share their vertex's width). M10.4 turns the part outside into a
/// slow-down, a drift and a hard limit, so a jump in this function would be felt as a jolt, and the fuzz selftest depends on it being well behaved.
struct NavNetwork {
    /// A polyline of centre points with a half-width at each point. The ends are round caps (a plain distance to a polyline), so a spawn exactly at an end is inside.
    struct Trail {
        var name: String
        var points: [SIMD2<Float>]
        var halfWidths: [Float]
        init(_ name: String, _ points: [SIMD2<Float>], halfWidth: Float) { self.init(name, points, halfWidths: [Float](repeating: halfWidth, count: points.count)) }
        init(_ name: String, _ points: [SIMD2<Float>], halfWidths: [Float]) {
            precondition(points.count >= 2 && points.count == halfWidths.count, "a trail needs two points or more and a half-width for each")
            self.name = name; self.points = points; self.halfWidths = halfWidths
        }

        /// The nearest point on the centre line, plus where it is: the leg, the parameter along it (0...1), the half-width there and the distance to it.
        struct Hit { var point: SIMD2<Float>; var leg: Int; var t: Float; var halfWidth: Float; var distance: Float }
        func nearest(_ p: SIMD2<Float>) -> Hit {
            var best = Hit(point: points[0], leg: 0, t: 0, halfWidth: halfWidths[0], distance: .infinity)
            for k in 0..<(points.count - 1) {
                let a = points[k], ab = points[k + 1] - a
                let denom = dot(ab, ab)
                let t = denom > 0 ? min(max(dot(p - a, ab) / denom, 0), 1) : 0
                let c = a + ab * t
                let d = length(p - c)
                if d < best.distance { best = Hit(point: c, leg: k, t: t, halfWidth: halfWidths[k] + (halfWidths[k + 1] - halfWidths[k]) * t, distance: d) }
            }
            return best
        }
        /// The signed distance to this trail's edge: negative inside.
        func signedDistance(_ p: SIMD2<Float>) -> Float {
            var best = Float.infinity
            for k in 0..<(points.count - 1) {
                let a = points[k], ab = points[k + 1] - a
                let denom = dot(ab, ab)
                let t = denom > 0 ? min(max(dot(p - a, ab) / denom, 0), 1) : 0
                best = min(best, length(p - (a + ab * t)) - (halfWidths[k] + (halfWidths[k + 1] - halfWidths[k]) * t))
            }
            return best
        }
        var totalLength: Float { zip(points, points.dropFirst()).reduce(0) { $0 + simd.length($1.1 - $1.0) } }
        /// Points along the centre line, at most `spacing` metres apart (the ends included).
        func samples(spacing: Float) -> [SIMD2<Float>] {
            var out = [points[0]]
            for k in 0..<(points.count - 1) {
                let a = points[k], b = points[k + 1]
                let n = max(Int((simd.length(b - a) / spacing).rounded(.up)), 1)
                for i in 1...n { out.append(a + (b - a) * (Float(i) / Float(n))) }
            }
            return out
        }
    }

    /// A rounded open area round a landmark (a disc).
    struct Plaza {
        var name: String
        var center: SIMD2<Float>
        var radius: Float
        func signedDistance(_ p: SIMD2<Float>) -> Float { simd.length(p - center) - radius }
    }

    /// A composed view: stand within `tolerance` metres of `position` and look toward `target` (M10.5 adds the framing assist; M10.6 checks the target is visible).
    struct Vantage {
        var name: String
        var position: SIMD2<Float>
        var target: SIMD3<Float>
        var tolerance: Float
        /// Marked for the puzzle that will move it (M10.5 places the real stations for the stones).
        var provisional = false
    }

    var trails: [Trail]
    var plazas: [Plaza]
    var vantages: [Vantage]
    /// Where the player starts (inside the network).
    var spawn: SIMD2<Float>
    /// Where the player is put on arriving by another route (the lens, the way back): also inside.
    var arrivals: [SIMD2<Float>]

    /// Regions are numbered trails first, then plazas.
    var regionCount: Int { trails.count + plazas.count }
    func regionName(_ i: Int) -> String { i < trails.count ? trails[i].name : plazas[i - trails.count].name }
    private func regionSignedDistance(_ i: Int, _ p: SIMD2<Float>) -> Float { i < trails.count ? trails[i].signedDistance(p) : plazas[i - trails.count].signedDistance(p) }

    /// Which regions are connected to which (they overlap by more than half a metre), and the regions that can be reached from the spawn.
    private(set) var adjacency: [[Int]] = []
    private(set) var reachableFromSpawn: Set<Int> = []
    /// The centre lines as a graph (nodes every 4 m along each trail, shared where trails meet) for `route`: how a scripted walker follows the trails.
    private(set) var graphNodes: [SIMD2<Float>] = []
    private var graphLinks: [[Int]] = []

    init(trails: [Trail], plazas: [Plaza], vantages: [Vantage] = [], spawn: SIMD2<Float>, arrivals: [SIMD2<Float>] = []) {
        self.trails = trails; self.plazas = plazas; self.vantages = vantages; self.spawn = spawn; self.arrivals = arrivals
        let n = trails.count + plazas.count
        var adj = [[Int]](repeating: [], count: n)
        for i in 0..<n {
            for j in (i + 1)..<max(n, i + 1) where overlap(i, j) { adj[i].append(j); adj[j].append(i) }
        }
        adjacency = adj
        var seen = Set<Int>(), stack = (0..<n).filter { regionSignedDistance($0, spawn) <= 0 }
        while let r = stack.popLast() {
            if !seen.insert(r).inserted { continue }
            stack += adj[r].filter { !seen.contains($0) }
        }
        reachableFromSpawn = seen
        buildGraph()
    }

    private mutating func buildGraph() {
        var nodes: [SIMD2<Float>] = [], links: [[Int]] = []
        func node(_ p: SIMD2<Float>) -> Int {
            if let i = nodes.firstIndex(where: { length($0 - p) < 0.5 }) { return i }
            nodes.append(p); links.append([]); return nodes.count - 1
        }
        func link(_ a: Int, _ b: Int) { if a != b && !links[a].contains(b) { links[a].append(b); links[b].append(a) } }
        for t in trails {
            var previous: Int?
            for p in t.samples(spacing: 4) { let n = node(p); if let pv = previous { link(pv, n) }; previous = n }
        }
        for pl in plazas {
            let n = node(pl.center)
            if links[n].isEmpty, let other = nodes.indices.filter({ $0 != n }).min(by: { length(nodes[$0] - pl.center) < length(nodes[$1] - pl.center) }) { link(n, other) }
        }
        graphNodes = nodes; graphLinks = links
    }

    /// The way along the trails from `a` to `b`: the centre-line nodes of the shortest path between the nodes nearest each (Dijkstra), so a walker follows the
    /// corridors instead of cutting across country. Empty when the network has no trails.
    func route(from a: SIMD2<Float>, to b: SIMD2<Float>) -> [SIMD2<Float>] {
        guard !graphNodes.isEmpty else { return [] }
        func nearest(_ p: SIMD2<Float>) -> Int { graphNodes.indices.min(by: { length(graphNodes[$0] - p) < length(graphNodes[$1] - p) })! }
        let start = nearest(a), goal = nearest(b)
        var dist = [Float](repeating: .infinity, count: graphNodes.count), prev = [Int](repeating: -1, count: graphNodes.count), done = [Bool](repeating: false, count: graphNodes.count)
        dist[start] = 0
        while true {
            var u = -1
            for i in graphNodes.indices where !done[i] && dist[i] < .infinity && (u < 0 || dist[i] < dist[u]) { u = i }
            if u < 0 || u == goal { break }
            done[u] = true
            for v in graphLinks[u] { let d = dist[u] + length(graphNodes[v] - graphNodes[u]); if d < dist[v] { dist[v] = d; prev[v] = u } }
        }
        guard dist[goal] < .infinity else { return [] }
        var path = [goal]
        while path.last! != start { path.append(prev[path.last!]) }
        return path.reversed().map { graphNodes[$0] }
    }

    /// Do two regions share some ground, by more than half a metre? Disc and disc and disc and trail are closed-form; two trails are checked along their centre lines.
    private func overlap(_ i: Int, _ j: Int) -> Bool {
        let slack: Float = 0.5
        switch (i < trails.count, j < trails.count) {
        case (false, false):
            let a = plazas[i - trails.count], b = plazas[j - trails.count]
            return length(a.center - b.center) < a.radius + b.radius - slack
        case (true, false), (false, true):
            let t = trails[i < trails.count ? i : j], p = plazas[(i < trails.count ? j : i) - trails.count]
            return t.signedDistance(p.center) < p.radius - slack
        case (true, true):
            let a = trails[i], b = trails[j]
            return a.samples(spacing: 1).contains { b.signedDistance($0) < -slack } || b.samples(spacing: 1).contains { a.signedDistance($0) < -slack }
        }
    }

    // MARK: Queries

    /// Negative inside any corridor or plaza, zero on the edge, positive outside (metres to the nearest edge). Continuous.
    func signedDistance(_ p: SIMD2<Float>) -> Float {
        var best = Float.infinity
        for t in trails { best = min(best, t.signedDistance(p)) }
        for pl in plazas { best = min(best, pl.signedDistance(p)) }
        return best
    }

    func contains(_ p: SIMD2<Float>) -> Bool { signedDistance(p) <= 0 }

    /// Inside a region that can be walked to from the spawn (a region cut off from it does not count).
    func isReachable(_ p: SIMD2<Float>) -> Bool { (0..<regionCount).contains { reachableFromSpawn.contains($0) && regionSignedDistance($0, p) <= 0 } }

    /// True when every region can be reached from the spawn.
    var isFullyConnected: Bool { reachableFromSpawn.count == regionCount }

    /// Are two regions joined (directly or through others)? Used by the audit and the tests.
    func areConnected(_ a: Int, _ b: Int) -> Bool {
        var seen = Set<Int>(), stack = [a]
        while let r = stack.popLast() {
            if r == b { return true }
            if !seen.insert(r).inserted { continue }
            stack += adjacency[r].filter { !seen.contains($0) }
        }
        return false
    }

    /// The nearest point on any centre line (a trail's polyline, or a plaza's centre), with where it is. `leg` and `t` are set for trails (the M10.6 bot follows them).
    struct Centre { var point: SIMD2<Float>; var region: Int; var leg: Int?; var t: Float?; var distance: Float }
    func nearestCentre(_ p: SIMD2<Float>) -> Centre {
        var best = Centre(point: spawn, region: 0, leg: nil, t: nil, distance: .infinity)
        for (i, tr) in trails.enumerated() {
            let h = tr.nearest(p)
            if h.distance < best.distance { best = Centre(point: h.point, region: i, leg: h.leg, t: h.t, distance: h.distance) }
        }
        for (i, pl) in plazas.enumerated() {
            let d = length(p - pl.center)
            if d < best.distance { best = Centre(point: pl.center, region: trails.count + i, leg: nil, t: nil, distance: d) }
        }
        return best
    }

    /// How far inside the edge a corrected point is put, so it is not left on a knife edge (the same reason the dock strip is extended past its ends).
    static let inset: Float = 0.05

    /// The nearest point that is inside: `p` itself when it already is, otherwise the closest point of any region's edge, drawn in by `inset` metres.
    func nearestInside(_ p: SIMD2<Float>) -> SIMD2<Float> {
        if signedDistance(p) <= 0 { return p }
        var best = spawn, bestD = Float.infinity
        func consider(_ c: SIMD2<Float>) { let d = length(p - c); if d < bestD { bestD = d; best = c } }
        for tr in trails {
            let h = tr.nearest(p)
            consider(h.point + (p - h.point) / max(h.distance, 1e-6) * max(h.halfWidth - NavNetwork.inset, 0))
        }
        for pl in plazas { consider(pl.center + (p - pl.center) / max(length(p - pl.center), 1e-6) * max(pl.radius - NavNetwork.inset, 0)) }
        return best
    }

    /// The same, but only over the regions reachable from the spawn (where a teleported player should land).
    func nearestReachable(_ p: SIMD2<Float>) -> SIMD2<Float> {
        if isReachable(p) { return p }
        var best = spawn, bestD = Float.infinity
        func consider(_ c: SIMD2<Float>) { let d = length(p - c); if d < bestD { bestD = d; best = c } }
        for (i, tr) in trails.enumerated() where reachableFromSpawn.contains(i) {
            let h = tr.nearest(p)
            consider(h.point + (p - h.point) / max(h.distance, 1e-6) * max(h.halfWidth - NavNetwork.inset, 0))
        }
        for (i, pl) in plazas.enumerated() where reachableFromSpawn.contains(trails.count + i) {
            consider(pl.center + (p - pl.center) / max(length(p - pl.center), 1e-6) * max(pl.radius - NavNetwork.inset, 0))
        }
        return best
    }
}
