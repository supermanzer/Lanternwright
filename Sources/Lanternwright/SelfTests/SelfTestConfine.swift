import Foundation
import simd

/// Self-tests: soft confinement (M10.4). The player is walked with the real `Player.step` on the real scenes, against the real networks.
extension SelfTestRunner {
    func runConfine() {
        guard name == "all" || name == "confine" else { return }
        let margin = Player.marginWidth
        func v(_ x: Float, _ z: Float) -> SIMD2<Float> { SIMD2(x, z) }
        let glass = Scene.make(.glassWood, device: device), varrow = Scene.makeWorld(device: device)
        let gnet = Layout.Navigation.glassWood, vnet = Layout.Navigation.varrow
        func placed(_ scene: Scene, _ p: SIMD2<Float>, yaw: Float) -> Player {
            var pl = Player(position: SIMD3(p.x, 0, p.y), yaw: yaw)
            pl.position.y = scene.groundHeight(x: p.x, z: p.y)
            return pl
        }
        func input(run: Bool = false, move: SIMD2<Float> = SIMD2(0, 1)) -> InputState { var i = InputState(); i.move = move; i.run = run; return i }
        func feet(_ p: Player) -> SIMD2<Float> { SIMD2(p.position.x, p.position.z) }

        // Walking straight out of a corridor, on the western path's long straight leg (gentle ground), on both sides, walking and running: the player slows and is
        // steered back, and never ends beyond the margin.
        let a = GlassLayout.path[0], b = GlassLayout.path[1]                       // arrival -> (0, 118): the straight leg along +z
        let mid = v((a.x + b.x) / 2, (a.z + b.z) / 2)
        var worst: Float = -.infinity, deepest: Float = -.infinity, endSd: [Float] = []
        for run in [false, true] {
            for side: Float in [-1, 1] {
                var pl = placed(glass, mid, yaw: side > 0 ? .pi / 2 : -.pi / 2)         // yaw +pi/2 faces east (+x)
                for _ in 0..<(20 * 120) {
                    pl.step(dt: Game.tick, input: input(run: run), scene: glass, nav: gnet)
                    let sd = gnet.signedDistance(feet(pl)); worst = max(worst, sd); deepest = max(deepest, sd)
                }
                endSd.append(gnet.signedDistance(feet(pl)))
            }
        }
        check(worst <= margin + 1e-3 && endSd.allSatisfy { $0 > 0 }, "confine: walking and running straight out of a corridor, on both sides, stops within the margin (deepest \(deepest) of \(margin) m; ended at \(endSd.map { Int($0 * 10) })/10 m)")
        // Walking settles where the steering balances the outward wish; running reaches the hard limit and holds there.
        check(endSd[0] > 2 && endSd[0] < margin - 0.1 && endSd[2] > margin - 0.1, "confine: walking balances inside the margin (\(endSd[0]) m), running reaches its far edge and holds (\(endSd[2]) m)")

        // Pressing outward and along: the player slides along the edge instead of stopping. Straight edge: run along +z with the view turned 25 degrees outward.
        var pl = placed(glass, v(mid.x + 5.5 + margin - 0.3, mid.y), yaw: .pi - 0.4)       // standing near the limit, east of the path, facing south-east-ish
        let startZ = pl.position.z
        var along: Float = 0
        for _ in 0..<(10 * 120) {
            pl.step(dt: Game.tick, input: input(run: true), scene: glass, nav: gnet)
            along = max(along, abs(pl.position.z - startZ))
            worst = max(worst, gnet.signedDistance(feet(pl)))
        }
        check(along > 12 && worst <= margin + 1e-3, "confine: pushing outward and along a straight edge slides along it (\(along) m in 10 s) and holds the limit")
        // Curved edge: round the arrival pad's margin.
        let arrival = v(GlassLayout.arrival.x, GlassLayout.arrival.z), r = gnet.plazas[0].radius + margin - 0.3
        pl = placed(glass, arrival + v(0, r), yaw: .pi / 2 + 0.3)                      // south of the pad, facing east and a little outward (south)
        var angle: Float = 0, last = atan2(pl.position.z - arrival.y, pl.position.x - arrival.x), maxSd: Float = -.infinity
        for _ in 0..<(12 * 120) {
            pl.step(dt: Game.tick, input: input(run: true), scene: glass, nav: gnet)
            let t = atan2(pl.position.z - arrival.y, pl.position.x - arrival.x)
            var d = t - last; if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
            angle += abs(d); last = t; maxSd = max(maxSd, gnet.signedDistance(feet(pl)))
        }
        check(angle * (gnet.plazas[0].radius + margin) > 12 && maxSd <= margin + 1e-3, "confine: it also slides round a curved edge (\(angle * (gnet.plazas[0].radius + margin)) m of arc in 12 s, never beyond the limit)")

        // The slowing: outward speed deep in the margin is well below the speed inside; motion inside a corridor is untouched, bit for bit.
        func settledSpeed(at p: SIMD2<Float>, yaw: Float, nav: NavNetwork?) -> Float {
            var q = placed(glass, p, yaw: yaw)
            for _ in 0..<60 { q.step(dt: Game.tick, input: input(run: true), scene: glass, nav: nav) }
            return q.speed
        }
        let inside = settledSpeed(at: mid, yaw: .pi / 2, nav: gnet)
        let deep = settledSpeed(at: v(mid.x + 5.5 + 2, mid.y), yaw: .pi / 2, nav: gnet)
        check(inside > 3.3 && deep < 0.65 * inside, "confine: running outward is slowed in the margin (\(deep) m/s at 2 m beyond the edge, \(inside) m/s inside)")
        var free = placed(glass, mid, yaw: 0.3), guided = free
        var identical = true
        for k in 0..<600 {
            let i = input(run: k % 200 < 100, move: SIMD2(Float(k % 3) - 1, 1))
            free.step(dt: Game.tick, input: i, scene: glass); guided.step(dt: Game.tick, input: i, scene: glass, nav: gnet)
            if free.position != guided.position || free.velocity != guided.velocity { identical = false }
        }
        check(identical && gnet.contains(feet(free)), "confine: inside a corridor the motion is identical with and without guidance (600 ticks)")
        check(guided.marginPressure == 0 && placed(glass, mid, yaw: 0).marginPressure == 0, "confine: marginPressure is 0 inside a corridor")
        var pressure = placed(glass, v(mid.x + 5.5 + 2, mid.y), yaw: 0)
        pressure.step(dt: Game.tick, input: InputState(), scene: glass, nav: gnet)
        var edge = placed(glass, v(mid.x + 5.5 + margin - 0.01, mid.y), yaw: 0)
        edge.step(dt: Game.tick, input: InputState(), scene: glass, nav: gnet)
        check(abs(pressure.marginPressure - 0.5) < 0.02 && edge.marginPressure > 0.99, "confine: marginPressure is 0.5 halfway through the margin and 1 at the hard limit (\(pressure.marginPressure), \(edge.marginPressure))")

        // A teleport: a player put anywhere (a hill, the sea, another island) is inside after one tick.
        var seed: UInt32 = 77_001
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
        var landed = 0, tried = 0
        for (scene, net) in [(varrow, vnet), (glass, gnet)] {
            let pts = net.trails.flatMap { $0.points }
            let lo = SIMD2(pts.map(\.x).min()!, pts.map(\.y).min()!) - 150, hi = SIMD2(pts.map(\.x).max()!, pts.map(\.y).max()!) + 150
            for _ in 0..<200 {
                let p = lo + (hi - lo) * v(rnd(), rnd())
                var q = placed(scene, p, yaw: rnd() * 6)
                let before = net.signedDistance(feet(q))
                q.step(dt: Game.tick, input: InputState(), scene: scene, nav: net)
                tried += 1
                let after = net.signedDistance(feet(q))
                // Stranded (beyond the margin and its slack): put on the nearest connected inside point. Just past the limit: projected onto it.
                if before > margin + Player.strandedSlack ? (after <= 0 && net.isReachable(feet(q))) : after <= margin + 1e-3 { landed += 1 }
            }
        }
        check(landed == tried && tried == 400, "confine: a teleport anywhere lands inside a connected corridor after one tick (and one just past the limit is put back on it): \(landed) of \(tried)")
        // The same through the game: a Varrow save from before guidance, with the player on the hillside, resumes on the network.
        let g = Game(scene: varrow)
        g.player = placed(varrow, v(-120, 60), yaw: 0)
        g.simulate(seconds: 0.1)
        check(vnet.signedDistance(feet(g.player)) <= margin + 1e-3 && vnet.isReachable(feet(g.player)), "confine: a game resumed with the player on the open hillside puts them back on the network (\(vnet.signedDistance(feet(g.player))) m from an edge)")

        // The fuzz: 10,000 ticks of random input in each world, with a teleport every 500, and the player is never beyond the limit after any tick.
        for (kind, scene, net) in [(WorldKind.varrow, varrow, vnet), (.glassWood, glass, gnet)] {
            let pts = net.trails.flatMap { $0.points }
            let lo = SIMD2(pts.map(\.x).min()!, pts.map(\.y).min()!) - 120, hi = SIMD2(pts.map(\.x).max()!, pts.map(\.y).max()!) + 120
            var q = placed(scene, net.spawn, yaw: 0)
            var move = SIMD2<Float>(0, 1), run = false, beyond = 0, inMargin = 0, deepest: Float = -.infinity, nonFinite = 0
            var nextTurn = 0, outwardMode = false
            for k in 0..<10_000 {
                if k % 1000 == 0 && k > 0 { q = placed(scene, lo + (hi - lo) * v(rnd(), rnd()), yaw: rnd() * 6) }       // a teleport anywhere
                if k >= nextTurn {
                    // Random headings are held for 0.2 to 3 s; half of the segments lean straight OUT of the corridor (away from the nearest centre line) and RUN for 12 to
                    // 22 s, because running out only creeps past the limit at about 0.1 m/s: only a long push shows whether the hard limit holds.
                    outwardMode = rnd() > 0.5
                    nextTurn = k + (outwardMode ? 1500 + Int(rnd() * 1200) : 25 + Int(rnd() * 350))
                    move = SIMD2(rnd() - 0.5, rnd() > 0.15 ? 1 : -0.5); run = rnd() > 0.4
                    if outwardMode {
                        run = true
                        let away = feet(q) - net.nearestCentre(feet(q)).point
                        let straight = rnd() > 0.5                                    // half of the pushes are perfectly straight out: only those reach the limit
                        q.yaw = atan2(away.x, -away.y) + (straight ? 0 : (rnd() - 0.5) * 0.8)
                        move = SIMD2(straight ? 0 : (rnd() - 0.5) * 0.3, 1)
                    } else { q.yaw = rnd() * 2 * .pi - .pi }
                }
                q.step(dt: Game.tick, input: input(run: run, move: move), scene: scene, nav: net)
                let sd = net.signedDistance(feet(q))
                if !(sd.isFinite && q.position.y.isFinite) { nonFinite += 1 }
                if sd > margin + 1e-3 { beyond += 1 }
                if sd > 0 { inMargin += 1 }
                deepest = max(deepest, sd)
            }
            check(beyond == 0 && nonFinite == 0, "confine \(kind.rawValue): after any of 10,000 random ticks (with 9 teleports) the player is never beyond the limit (\(beyond) violations; \(inMargin) ticks spent in the margin, deepest \(deepest) m)")
            check(inMargin > 500 && deepest > 2.5, "confine \(kind.rawValue): the fuzz really did press on the margin (\(inMargin) ticks in it, deepest \(deepest) m of \(margin))")
        }
    }
}
