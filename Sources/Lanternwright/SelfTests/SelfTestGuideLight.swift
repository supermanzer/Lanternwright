import Foundation
import simd

/// F09.2 (#94, #98): the guide light leads while the player approaches its target, parks there and stays; turning round never draws it after the player; it relights toward the next objective.
extension SelfTestRunner {
    func runGuideLight() {
        guard name == "all" || name == "guidelight" else { return }
        typealias L = GuideLight
        // The rule on a straight path of 100 m (pure).
        let path = GuidePath([SIMD2(0, 0), SIMD2(100, 0)])
        var light = L(path: path, player: SIMD2(0, 0))
        check(abs(light.position.x - L.ahead) < 0.01 && !light.parked, "guidelight: it appears \(Int(L.ahead)) m ahead of a player at the start")
        var player = SIMD2<Float>(0, 0), last = light.position.x, forward = true
        for _ in 0..<(60 * 20) { player.x += 1.4 / 60; light.step(dt: 1 / 60, player: player); forward = forward && light.position.x >= last - 1e-5; last = light.position.x }
        check(forward && light.position.x > player.x + 5 && light.position.x < 100 && !light.parked, "guidelight: walking on, it stays ahead of the player and only ever moves forward (player \(Int(player.x)) m, light \(Int(light.position.x)) m)")
        let turned = light.position
        for _ in 0..<(60 * 20) { player.x -= 1.4 / 60; light.step(dt: 1 / 60, player: player) }
        check(simd_length(light.position - turned) < 0.1, "guidelight: the player turns round and walks back for 20 s: the light has not moved (\(String(format: "%.3f", simd_length(light.position - turned))) m)")
        player = SIMD2(96, 0)
        for _ in 0..<(60 * 8) { light.step(dt: 1 / 60, player: player) }
        check(light.parked && simd_length(light.position - SIMD2(100, 0)) < 0.01, "guidelight: within \(Int(L.settleRange)) m of the target the light settles on it")
        let parkedAt = light.position
        var worst: Float = 0
        for i in 0..<(60 * 20) { player.x = i < 600 ? 96 - Float(i) * 0.15 : 6 + Float(i - 600) * 0.15; light.step(dt: 1 / 60, player: player); worst = max(worst, simd_length(light.position - parkedAt)) }
        check(worst < 0.1 && light.parked, "guidelight: parked, it stays within 0.1 m for 20 s of the player walking away and back (worst \(String(format: "%.3f", worst)) m)")
        var late = L(path: path, player: SIMD2(98, 0))
        late.step(dt: 1 / 60, player: SIMD2(98, 0))
        check(late.parked, "guidelight: a player who arrives at the target at once finds the light already there")
        // Mutation: a light that follows the player's progress both ways (the old rule) fails the turn-round check.
        var oldRule = path.progress(of: SIMD2(30, 0)) + L.ahead
        let before = oldRule; oldRule = path.progress(of: SIMD2(10, 0)) + L.ahead
        check(abs(oldRule - before) > 5, "guidelight mutation: the old always-ahead rule moves the light when the player turns back (it would FAIL the check above)")

        // In the game, in the Archive: the light's objectives in order.
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)])
        for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
        g.state.set("gw_end"); g.state.set(Game.doorOpenFlag); g.simulate(seconds: 0.1)
        check(g.beginRoute(.ilse), "guidelight: Ilse's route begins")
        g.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        var clock = 20_000.0
        func frames(_ n: Int) { for _ in 0..<n { clock += 1.0 / 60; g.advance(now: clock, input: InputState()) } }
        func put(_ p: SIMD2<Float>) { g.player.position = SIMD3(p.x, g.scene.groundHeight(x: p.x, z: p.y), p.y) }
        let net = Layout.Navigation.active(for: .tideArchive)!
        frames(30)
        check(g.world == .tideArchive && g.guideLantern != nil && g.guideLightKey == "gate0", "guidelight: on arrival the light is lit toward the first gate (key \(g.guideLightKey ?? "-"))")
        let gate0 = TideSpots.gate(0), g0 = SIMD2(gate0.x, gate0.z)
        let route = net.route(from: SIMD2(g.player.position.x, g.player.position.z), to: g0)
        let along = GuidePath(route)
        var prev = along.progress(of: g.guideLantern!), monotone = true
        for p in 0..<route.count { put(route[p]); frames(40); let now = along.progress(of: g.guideLantern!); monotone = monotone && now >= prev - 0.05; prev = now }
        check(monotone, "guidelight: walking the route to the first gate, the light only ever gets nearer to it")
        put(g0 + SIMD2(3, 0)); frames(600)
        check(g.guideLightParked && simd_length(g.guideLantern! - g0) < 0.5, "guidelight: the player at the gate: the light is parked on it")
        let parked = g.guideLantern!
        var drift: Float = 0
        for k in 0..<20 { put(k % 2 == 0 ? g0 + SIMD2(60, 0) : route.first!); frames(60); drift = max(drift, simd_length(g.guideLantern! - parked)) }
        check(drift < 0.1, "guidelight: the player turns round, walks off and comes back for 20 s: the light stays within 0.1 m of the gate (\(String(format: "%.3f", drift)) m)")
        // The next objective relights it toward the next gate; solving the world sends it to the gallery door, then page 15's taking to the quay.
        g.state.set(TideArchivePuzzle.sluiceFlags[0]); put(g0 + SIMD2(3, 0)); frames(30)
        check(g.guideLightKey == "gate1" && !g.guideLightParked, "guidelight: gate 1 is next: the light relights toward it (key \(g.guideLightKey ?? "-"))")
        g.state.set(Game.routeSolvedFlag); frames(30)
        check(g.guideLightKey == "gallery", "guidelight: the water down, the light points at the gallery's door (key \(g.guideLightKey ?? "-"))")
        let d = TideSpots.galleryDoor
        put(d); frames(60 * 40)
        check(g.guideLightParked && simd_length(g.guideLantern! - d) < 0.5, "guidelight: and parks at the gallery door")
        g.state.set("page_15"); frames(30)
        check(g.guideLightKey == "quay", "guidelight: page 15 taken, the light points to the quay's lens (key \(g.guideLightKey ?? "-"))")
    }
}
