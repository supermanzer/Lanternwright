import Foundation
import simd

/// Self-tests: the guidance setting, the way back to free roam (M10.7).
extension SelfTestRunner {
    func runGuidance() {
        guard name == "all" || name == "guidance" else { return }
        let savedGuidance = Player.guidance, savedSettings = Settings.current, savedCalm = LookFilter.calm
        defer { Player.guidance = savedGuidance; Settings.current = savedSettings; LookFilter.calm = savedCalm }
        func v(_ x: Float, _ z: Float) -> SIMD2<Float> { SIMD2(x, z) }
        let deg: Float = .pi / 180
        let scene = Scene.makeWorld(device: device)

        // MARK: Free roam reproduces the unconfined movement exactly
        // A recorded input stream (walking, running, strafing, turning; 8 segments, 10 s) starting on the open hillside, well outside every corridor.
        let start = SIMD3<Float>(100, scene.groundHeight(x: 100, z: 0), 0)             // open ground on the hill's gentle bench, far from every corridor
        check(Layout.Navigation.varrow.signedDistance(SIMD2(start.x, start.z)) > 20, "guidance: the recording starts well outside every corridor (\(Layout.Navigation.varrow.signedDistance(SIMD2(start.x, start.z))) m from the nearest edge)")
        struct Segment { var yaw: Float; var move: SIMD2<Float>; var run: Bool; var ticks: Int }
        let recording: [Segment] = [Segment(yaw: 0.3, move: SIMD2(0, 1), run: false, ticks: 300), Segment(yaw: 0.6, move: SIMD2(0, 1), run: true, ticks: 360), Segment(yaw: 0.2, move: SIMD2(1, 0.4), run: false, ticks: 240),
                                    Segment(yaw: 0.8, move: SIMD2(0.3, 1), run: true, ticks: 400), Segment(yaw: 0.4, move: SIMD2(0, 1), run: false, ticks: 300), Segment(yaw: 1.4, move: SIMD2(0, -1), run: false, ticks: 120),
                                    Segment(yaw: 0.5, move: SIMD2(-0.5, 1), run: true, ticks: 400), Segment(yaw: 0.3, move: SIMD2(0, 1), run: false, ticks: 280)]
        Player.guidance = .free
        let free = Game(scene: scene)
        free.player = Player(position: start, yaw: 0)
        var plain = Player(position: start, yaw: 0)
        var exact = true, wandered: Float = 0
        for seg in recording {
            var input = InputState(); input.move = seg.move; input.run = seg.run
            free.player.yaw = seg.yaw; plain.yaw = seg.yaw
            free.simulate(seconds: Float(seg.ticks) * Game.tick, input: input)
            for _ in 0..<seg.ticks { plain.step(dt: Game.tick, input: input, scene: scene, nav: nil) }
            if free.player.position != plain.position || free.player.velocity != plain.velocity { exact = false }
            wandered = max(wandered, simd_length(SIMD2(free.player.position.x, free.player.position.z) - SIMD2(start.x, start.z)))
        }
        check(exact && wandered > 30, "guidance: in Free roam a recorded 20 s input stream from open ground moves the player exactly as unconfined movement does, bit for bit, at the end of each of its 8 segments (it travelled \(wandered) m from the start)")
        Player.guidance = .guided
        let guided = Game(scene: scene)
        guided.player = Player(position: start, yaw: 0)
        var walk = InputState(); walk.move = SIMD2(0, 1)
        guided.simulate(seconds: 0.1, input: walk)
        check(Layout.Navigation.varrow.signedDistance(SIMD2(guided.player.position.x, guided.player.position.z)) <= Player.marginWidth + 1e-3 && simd_length(guided.player.position - start) > 15,
              "guidance: the same start under Guided is put back on the network, more than 15 m away (so Free roam is a real difference)")
        check(Layout.Navigation.active(for: .varrow) != nil && { () -> Bool in Player.guidance = .free; defer { Player.guidance = .guided }; return Layout.Navigation.active(for: .varrow) == nil }(),
              "guidance: Free roam has no network at all (nil), Guided has one")

        // MARK: Loose: corridors 1.6x wider, margin 2x
        let g = Layout.Navigation.varrow, l = Layout.Navigation.varrowLoose
        let ridge = g.trails[2]                                                   // the ridge path
        let mid = (ridge.points[0] + ridge.points[1]) / 2
        let across = simd_normalize(SIMD2(-(ridge.points[1] - ridge.points[0]).y, (ridge.points[1] - ridge.points[0]).x))
        check(abs(l.signedDistance(mid) - (-5.5 * 1.6)) < 0.01 && abs(l.plazas[1].radius - g.plazas[1].radius * 1.6) < 1e-4, "guidance: Loose trails are 1.6x wider (centre line \(l.signedDistance(mid)) m) and plazas 1.6x the radius")
        check(g.signedDistance(mid + across * 8) > 0 && l.signedDistance(mid + across * 8) < 0, "guidance: a point 8 m off the ridge path is outside Guided but inside Loose")
        var seed: UInt32 = 1_007
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
        var notSuperset = 0
        for _ in 0..<2000 { let p = v(-120 + rnd() * 340, -360 + rnd() * 600); if g.signedDistance(p) <= 0 && l.signedDistance(p) > 0 { notSuperset += 1 } }
        check(notSuperset == 0 && l.isFullyConnected && l.contains(l.spawn) && l.arrivals.allSatisfy { l.isReachable($0) } && l.vantages.count == g.vantages.count, "guidance: Loose contains everything Guided does (2000 points), is fully connected, and keeps the spawn, arrivals and vantages")
        let glassLoose = Layout.Navigation.glassWoodLoose
        check(glassLoose.isFullyConnected && Layout.Navigation.network(for: .glassWood, guidance: .loose) != nil, "guidance: the Glass Wood has a Loose network too, and it is connected")
        // Loose margin: running straight out of a corridor ends beyond the Guided margin but within the doubled one; the fuzz never leaves it.
        let gscene = Scene.make(.glassWood, device: device)
        Player.guidance = .loose
        check(Player.margin == 8, "guidance: the margin is 8 m in Loose (4 m in Guided)")
        let a = GlassLayout.path[0], b = GlassLayout.path[1]
        var pl = Player(position: SIMD3((a.x + b.x) / 2, 0, (a.z + b.z) / 2), yaw: .pi / 2)
        pl.position.y = gscene.groundHeight(x: pl.position.x, z: pl.position.z)
        var run = InputState(); run.move = SIMD2(0, 1); run.run = true
        var deepest: Float = -.infinity
        for _ in 0..<(40 * 120) { pl.step(dt: Game.tick, input: run, scene: gscene, nav: glassLoose); deepest = max(deepest, glassLoose.signedDistance(SIMD2(pl.position.x, pl.position.z))) }
        check(deepest > Player.marginWidth + 1 && deepest <= 8 + 1e-3, "guidance: running straight out in Loose goes past the Guided margin and stops at the 8 m limit (deepest \(deepest) m)")
        var q = Player(position: SIMD3(glassLoose.spawn.x, 0, glassLoose.spawn.y), yaw: 0)
        q.position.y = gscene.groundHeight(x: q.position.x, z: q.position.z)
        var beyond = 0, inMargin = 0, nextTurn = 0
        let pts = glassLoose.trails.flatMap { $0.points }
        let lo = SIMD2(pts.map(\.x).min()!, pts.map(\.y).min()!) - 100, hi = SIMD2(pts.map(\.x).max()!, pts.map(\.y).max()!) + 100
        for k in 0..<10_000 {
            if k % 1000 == 0 && k > 0 { let t = lo + (hi - lo) * v(rnd(), rnd()); q = Player(position: SIMD3(t.x, gscene.groundHeight(x: t.x, z: t.y), t.y), yaw: 0) }
            if k >= nextTurn {
                let outward = rnd() > 0.5
                nextTurn = k + (outward ? 2400 : 25 + Int(rnd() * 350))
                var i = InputState(); i.move = SIMD2(0, 1); i.run = outward || rnd() > 0.4; run = i
                if outward { let away = SIMD2(q.position.x, q.position.z) - glassLoose.nearestCentre(SIMD2(q.position.x, q.position.z)).point; q.yaw = atan2(away.x, -away.y) } else { q.yaw = rnd() * 6 - 3 }
            }
            q.step(dt: Game.tick, input: run, scene: gscene, nav: glassLoose)
            let sd = glassLoose.signedDistance(SIMD2(q.position.x, q.position.z))
            if sd > 8 + 1e-3 { beyond += 1 }; if sd > 0 { inMargin += 1 }
        }
        check(beyond == 0 && inMargin > 300, "guidance: 10,000 random ticks in Loose (with 9 teleports) never end beyond the 8 m limit (\(beyond) violations, \(inMargin) ticks in the margin)")
        // The framing assist works in Loose and is off in Free roam, in the real game loop.
        func pull(_ mode: Guidance) -> Float {
            Player.guidance = mode; LookFilter.calm = 0
            let station = Layout.Navigation.varrow.vantages.first { $0.name.hasPrefix("the climb") }!
            let gm = Game(scene: scene)
            var p = Player(position: SIMD3(station.position.x, 0, station.position.y), yaw: 0)
            p.position.y = scene.groundHeight(x: p.position.x, z: p.position.z)
            let want = simd_normalize(station.target - (p.position + SIMD3(0, Player.eyeHeight, 0)))
            p.yaw = atan2(want.x, -want.z) + 10 * deg; p.pitch = asin(want.y)
            gm.player = p
            var t = 9000.0
            for _ in 0..<180 { t += 1.0 / 60; gm.advance(now: t, input: InputState()) }
            return abs(gm.player.yaw - p.yaw)
        }
        let looseCloser = pull(.loose), freeCloser = pull(.free)
        check(looseCloser > 0.5 * deg && freeCloser == 0, "guidance: the framing assist pulls in Loose (\(looseCloser / deg) degrees in 3 s) and is off in Free roam (\(freeCloser / deg))")

        // A live switch from the pause menu: standing 12 m off the ridge path, which is inside Loose's margin but beyond Guided's, the player stays put in Loose and is
        // moved back onto the Guided network (never trapped) as soon as the setting changes.
        let off = mid + across * 12
        Player.guidance = .loose
        let live = Game(scene: scene)
        live.player = Player(position: SIMD3(off.x, scene.groundHeight(x: off.x, z: off.y), off.y), yaw: 0)
        live.simulate(seconds: 0.2)
        let stayed = SIMD2(live.player.position.x, live.player.position.z)
        Player.guidance = .guided
        live.simulate(seconds: 0.1)
        let moved = SIMD2(live.player.position.x, live.player.position.z)
        check(simd_length(stayed - off) < 0.05 && g.signedDistance(off) > Player.marginWidth + Player.strandedSlack && g.signedDistance(moved) <= Player.marginWidth + 1e-3 && g.isReachable(moved),
              "guidance: switching Loose to Guided while 12 m off the path (inside Loose's margin, beyond Guided's) leaves the player alone in Loose and puts them back on the Guided network at once (moved \(simd_length(moved - off)) m)")

        // MARK: Settings, the flag, the feedback context
        var s = Settings(); s.guidance = .loose
        let round = try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        check(Settings().guidance == .guided && round?.guidance == .loose, "guidance: the setting defaults to Guided and survives a save and load")
        let legacy = try? JSONDecoder().decode(Settings.self, from: Data(#"{"volume":0.3}"#.utf8))
        let junk = try? JSONDecoder().decode(Settings.self, from: Data(#"{"guidance":"banana","volume":0.3}"#.utf8))
        check(legacy?.guidance == .guided && junk?.guidance == .guided && junk?.volume == 0.3, "guidance: a settings blob without it, or with an unknown value, loads as Guided and keeps its other fields")
        check(LaunchOptions.parse(["Lanternwright", "--freeroam"]).freeRoam && !LaunchOptions.parse(["Lanternwright"]).freeRoam, "guidance: --freeroam is parsed")
        var custom = Settings(); custom.lookSpeed = 1.2; custom.calmCamera = 0.3; custom.pace = 0.8
        Settings.current = custom; Player.guidance = .loose
        let ctx = Game(scene: scene).feedbackContext()
        check(ctx["guidance"] == "loose" && ctx["look"] == "speed 1.20 x calm 0.30" && ctx["pace"] == "0.80", "guidance: the F-key context records the guidance, look (speed x calm) and pace (\(ctx["guidance"] ?? "-"), \(ctx["look"] ?? "-"), \(ctx["pace"] ?? "-"))")
        Player.guidance = .free; Settings.current = Settings()
        check(Game(scene: scene).feedbackContext()["guidance"] == "free" && Game(scene: scene).feedbackContext()["pace"] == "1.00", "guidance: and it follows a change (free roam, default pace)")

        // The region for each setting.
        let guidedRegion = ReachableRegion.make(.varrow, scene: scene), looseRegion = ReachableRegion.make(.varrow, scene: scene, guidance: .loose)
        check(guidedRegion.margin == 4 && looseRegion.margin == 8 && looseRegion.contains(mid + across * 14) && !guidedRegion.contains(mid + across * 14) && looseRegion.bounds.max.x > guidedRegion.bounds.max.x,
              "guidance: ReachableRegion.make(guidance: .loose) is the wider region with the 8 m margin (a point 14 m off the ridge path is in Loose, not in Guided)")
    }
}
