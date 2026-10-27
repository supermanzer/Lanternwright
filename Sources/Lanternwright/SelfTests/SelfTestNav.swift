import Foundation
import simd

/// A scripted walker for the navigation tests: drives the real `Game.advance` loop, straight at a point, walking or running.
private final class NavWalker {
    let game: Game
    private var now = 3000.0
    init(_ game: Game) { self.game = game }
    var feet: SIMD2<Float> { SIMD2(game.player.position.x, game.player.position.z) }
    /// Seconds taken to get within `r` metres of `target`, or nil if it gave up after `timeout`.
    func walk(to target: SIMD2<Float>, within r: Float, run: Bool, timeout: Float = 400) -> Float? {
        var t: Float = 0
        while t < timeout {
            let d = target - feet
            if simd_length(d) < r { return t }
            game.player.yaw = atan2(d.x, -d.y); game.player.pitch = 0
            var input = InputState(); input.move = SIMD2(0, 1); input.run = run
            now += 1.0 / 60; game.advance(now: now, input: input); t += 1.0 / 60
        }
        return nil
    }
}

/// Self-tests: the navigation model and its authored data (M10.3).
extension SelfTestRunner {
    func runNav() {
        guard name == "all" || name == "nav" else { return }
        typealias Net = NavNetwork
        func near(_ a: Float, _ b: Float, _ tol: Float = 1e-3) -> Bool { abs(a - b) <= tol }
        func v(_ x: Float, _ z: Float) -> SIMD2<Float> { SIMD2(x, z) }

        // MARK: the shapes, on small exact cases
        let straight = Net.Trail("straight", [v(0, 0), v(100, 0)], halfWidth: 5)
        check(near(straight.signedDistance(v(50, 0)), -5) && near(straight.signedDistance(v(50, 5)), 0) && near(straight.signedDistance(v(50, -12)), 7),
              "nav: a straight trail is -5 on its centre line, 0 on its edge, 7 at 12 m")
        check(near(straight.signedDistance(v(-3, 0)), -2) && near(straight.signedDistance(v(-8, 0)), 3), "nav: the end of a trail is a round cap (a spawn at the very end is inside)")
        let arc = (0...6).map { k -> SIMD2<Float> in let a = Float(k) * (.pi / 2) / 6; return v(cos(a) * 50, sin(a) * 50) }
        let curved = Net.Trail("curved", arc, halfWidth: 4)
        let hubCentre = curved.signedDistance(v(0, 0))
        check(near(curved.signedDistance(arc[3]), -4) && hubCentre > 45.5 && hubCentre < 46.1, "nav: a curved trail is -4 on its vertices and about 46 m from the middle of its arc (\(hubCentre))")
        let taper = Net.Trail("taper", [v(0, 0), v(10, 0), v(20, 0)], halfWidths: [2, 6, 2])
        check(near(taper.signedDistance(v(10, 6)), 0) && near(taper.signedDistance(v(5, 4)), 0) && near(taper.signedDistance(v(0, 2)), 0) && near(taper.signedDistance(v(15, 4)), 0),
              "nav: the half-width is interpolated along each leg and shared at the vertex (2 -> 6 -> 2)")
        var worstJump: Float = 0
        for i in -50...50 { let a = taper.signedDistance(v(10 + Float(i) * 0.02 - 0.01, 3)), b = taper.signedDistance(v(10 + Float(i) * 0.02 + 0.01, 3)); worstJump = max(worstJump, abs(a - b)) }
        check(worstJump <= 0.02 * 1.05, "nav: signed distance has no jump across a vertex whose neighbours differ in width (worst step \(worstJump) per 0.02 m)")

        // A junction: two trails meeting at a plaza, and a far plaza that nothing reaches.
        let t = Net(trails: [Net.Trail("east-west", [v(0, 0), v(50, 0)], halfWidth: 5), Net.Trail("north", [v(50, 0), v(50, -60)], halfWidth: 5)],
                    plazas: [Net.Plaza(name: "hub", center: v(50, 0), radius: 12), Net.Plaza(name: "island", center: v(300, 300), radius: 20)], spawn: v(0, 0))
        check(near(t.signedDistance(v(50, 0)), -12) && t.nearestCentre(v(50, 0)).distance == 0 && t.contains(v(55, -30)) && !t.contains(v(70, -30)), "nav: at a junction the plaza dominates (-12 at its centre); the legs are 11 m wide")
        let c = t.nearestCentre(v(20, 3))
        check(c.region == 0 && c.leg == 0 && near(c.t ?? -1, 0.4) && near(c.distance, 3) && near(c.point.x, 20) && near(c.point.y, 0), "nav: nearestCentre reports the trail, the leg, the parameter along it and the distance")
        check(t.areConnected(0, 1) && t.areConnected(1, 2) && !t.areConnected(0, 3) && !t.isFullyConnected, "nav: the connectivity graph joins trails through the hub and leaves the far plaza out")
        check(t.isReachable(v(50, -40)) && !t.isReachable(v(300, 300)) && t.contains(v(300, 300)), "nav: a point inside a region cut off from the spawn is not reachable (it is 'inside', but not connected)")
        let landed = t.nearestReachable(v(300, 300))
        check(t.isReachable(landed) && simd_length(landed - v(50, 0)) < 13, "nav: nearestReachable lands a teleport that ended in the cut-off region back on the connected network")

        // MARK: properties of the real networks (seeded random points)
        var seed: UInt32 = 20_261_027
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
        for kind in WorldKind.allCases {
            let net = Layout.Navigation.network(for: kind)
            let pts = net.trails.flatMap { $0.points } + net.plazas.map { $0.center }
            let lo = SIMD2(pts.map(\.x).min()!, pts.map(\.y).min()!) - 80, hi = SIMD2(pts.map(\.x).max()!, pts.map(\.y).max()!) + 80
            var badInside = 0, badMoved = 0, badKept = 0, badLip = 0, outside = 0
            for _ in 0..<3000 {
                let p = lo + (hi - lo) * SIMD2(rnd(), rnd())
                let sd = net.signedDistance(p), q = net.nearestInside(p)
                if net.signedDistance(q) > 1e-4 { badInside += 1 }
                if sd <= 0 { if q != p { badKept += 1 } } else {
                    outside += 1
                    if !near(simd_length(q - p), sd + NavNetwork.inset, 2e-3) { badMoved += 1 }
                    if net.signedDistance(q) > -NavNetwork.inset + 1e-3 { badInside += 1 }
                }
                let d = SIMD2(rnd() - 0.5, rnd() - 0.5) * 0.4
                if abs(net.signedDistance(p + d) - sd) > simd_length(d) + 1e-4 { badLip += 1 }
            }
            check(badInside == 0 && badKept == 0 && badMoved == 0 && outside > 500, "nav \(kind.rawValue): nearestInside is always inside, leaves inside points alone and moves an outside point by its distance (\(outside) outside of 3000)")
            check(badLip == 0, "nav \(kind.rawValue): signedDistance is 1-Lipschitz (it never changes faster than you move) at 3000 random points")
        }

        // MARK: the authored data
        for kind in WorldKind.allCases {
            let net = Layout.Navigation.network(for: kind)
            check(net.isFullyConnected && net.contains(net.spawn) && net.arrivals.allSatisfy { net.isReachable($0) },
                  "nav \(kind.rawValue): every one of \(net.regionCount) regions is connected to the spawn, and the spawn and arrival points are inside")
            check(net.vantages.allSatisfy { net.contains($0.position) && net.signedDistance($0.position) < -2 }, "nav \(kind.rawValue): every vantage stands well inside a corridor")
        }

        // Coverage: everything the game puts the player at must be inside and connected (a miss would be a soft lock once the edge is a wall).
        for kind in WorldKind.allCases {
            let scene = Scene.make(kind, device: device)
            let net = Layout.Navigation.network(for: kind)
            let pts = NavCoverage.points(for: kind, scene: scene)
            let missed = pts.filter { !net.isReachable(SIMD2($0.position.x, $0.position.z)) }
            check(missed.isEmpty, "nav \(kind.rawValue): all \(pts.count) places the player must reach are inside and connected (missed: \(missed.map(\.name)))")
            let thin = pts.filter { net.signedDistance(SIMD2($0.position.x, $0.position.z)) > -1.5 }
            check(thin.isEmpty, "nav \(kind.rawValue): each has at least 1.5 m of corridor around it (thin: \(thin.map { "\($0.name) \(net.signedDistance(SIMD2($0.position.x, $0.position.z)))" }))")

            // Each vantage's target is in view of its eye position over the terrain (the collider ray test is M10.6's audit).
            for vt in net.vantages {
                let eye = SIMD3(vt.position.x, scene.groundHeight(x: vt.position.x, z: vt.position.y) + Player.eyeHeight, vt.position.y)
                let span = vt.target - eye, n = Int(simd_length(span))
                var blocked: SIMD3<Float>?
                for i in 1..<max(n - 3, 2) {
                    let q = eye + span * (Float(i) / Float(n))
                    if scene.groundHeight(x: q.x, z: q.z) > q.y { blocked = q; break }
                }
                check(blocked == nil, "nav \(kind.rawValue): vantage '\(vt.name)' sees its target over the terrain (\(Int(simd_length(span))) m\(blocked.map { ", blocked near (\(Int($0.x)), \(Int($0.y)), \(Int($0.z)))" } ?? ""))")
            }

            // Every centre line is walkable ground: dry, and nowhere steeper than the walking limit. (The causeway is checked by walking it, once it has risen.)
            var wet: [String] = [], steep: [String] = []
            for tr in net.trails where tr.name != "causeway" {
                let s = tr.samples(spacing: 2)
                for (a, b) in zip(s, s.dropFirst()) {
                    let ga = scene.groundHeight(x: a.x, z: a.y), gb = scene.groundHeight(x: b.x, z: b.y)
                    if gb < Player.minGround || ga < Player.minGround { wet.append("\(tr.name) (\(Int(b.x)), \(Int(b.y)))") }
                    else if abs(gb - ga) / simd_length(b - a) > Player.maxSlope && !scene.isOnPlatform(b) { steep.append("\(tr.name) (\(Int(b.x)), \(Int(b.y)))") }
                }
            }
            check(wet.isEmpty && steep.isEmpty, "nav \(kind.rawValue): every centre line is dry and within the walking slope (wet \(wet.prefix(3)), steep \(steep.prefix(3)))")
        }

        // MARK: walking it, with the real Player.step: the routes the plan asks to be timed
        let scene = Scene.makeWorld(device: device)
        let net = Layout.Navigation.varrow
        let game = Game(scene: scene)
        let w = NavWalker(game)
        let route = Layout.route.map { SIMD2($0.x, $0.z) }                       // dock shore, tide, wind, summit, lighthouse, causeway start
        func timeRoute(run: Bool) -> (toLighthouse: Float, ok: Bool) {
            game.player = Player(position: Layout.dockEnd, yaw: Layout.spawnYaw)
            game.player.position.y = scene.groundHeight(x: Layout.dockEnd.x, z: Layout.dockEnd.z)
            var total: Float = 0
            for (i, p) in route[0...4].enumerated() {
                guard let s = w.walk(to: p, within: i == 4 ? 6.5 : 3, run: run) else { return (total, false) }
                total += s
            }
            return (total, true)
        }
        let walked = timeRoute(run: false)
        let ran = timeRoute(run: true)
        check(walked.ok && ran.ok, "nav varrow: the centre line from the dock to the lighthouse can be walked and run with the real controller")
        check(walked.toLighthouse < 200 && ran.toLighthouse < 130, "nav varrow: TIMES dock -> lighthouse along the network: walking \(Int(walked.toLighthouse.rounded())) s, running \(Int(ran.toLighthouse.rounded())) s (the plan's target of 60 s is not reachable: the straight line is \(Int(simd_length(SIMD2(Layout.dockEnd.x - Layout.lighthouse.x, Layout.dockEnd.z - Layout.lighthouse.z)))) m, 142 s at 2.3 m/s)")
        game.puzzle.forceSolved(); game.simulate(seconds: LighthousePuzzle.Timing.total + 1)
        let plan = PuzzleProps.causewayPlan(terrain: scene.terrain)
        let toCauseway = w.walk(to: route[5], within: 3, run: false), toIslet = w.walk(to: SIMD2(Layout.isletCenter.x, Layout.isletCenter.z), within: 3, run: false)
        check(toCauseway != nil && toIslet != nil && game.player.position.y > 1.0, "nav varrow: after the lighthouse is solved, the lighthouse -> causeway -> islet centre line is walkable (to the causeway \(Int((toCauseway ?? 0).rounded())) s, across it \(Int((toIslet ?? 0).rounded())) s; \(Int(plan.length)) m of slabs)")
        let ranBack = game.player.position
        check(net.isReachable(SIMD2(ranBack.x, ranBack.z)), "nav varrow: where the walk ended (the islet) is inside the network")
    }
}
