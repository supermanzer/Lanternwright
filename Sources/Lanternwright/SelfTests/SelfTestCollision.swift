import Foundation
import Metal
import simd

/// Self-tests: collision and getting stuck (F01 W4.1). The user reported movement around the lighthouse "appears stuck"; these bots circle the tower and
/// walk into it, and a stuck detector (a whole second of forward input with almost no progress) fails them.
extension SelfTestRunner {
    func runCollision() {
        guard name == "all" || name == "collision" else { return }
        let scene = Scene.makeWorld(device: device)
        let g = Game(scene: scene)
        let bot = PlaythroughBot(g)
        let c = SIMD2(Layout.lighthouse.x, Layout.lighthouse.z)
        // Circling at radii from hugging the wall to a comfortable berth, both ways, walking and running.
        var report: [String] = []
        var stuckTotal = 0
        for radius: Float in [5.0, 5.5, 6.0, 7.0] {
            for cw in [false, true] {
                for run in [false, true] {
                    let r = bot.circle(around: c, radius: radius, clockwise: cw, run: run, seconds: 40, startAngle: radius)
                    stuckTotal += r.stuck
                    if r.stuck > 0 { report.append("r \(radius) \(cw ? "cw" : "ccw") \(run ? "run" : "walk"): \(r.stuck) stuck s at \(r.stuckAt.map { "(\($0.x), \($0.y))" } ?? "?")") }
                }
            }
        }
        check(stuckTotal == 0, "circling the lighthouse at 5.0, 5.5, 6.0 and 7.0 m, both ways, walking and running: never stuck (\(stuckTotal) stuck seconds \(report.prefix(4)))")
        // Walking straight at the tower from eight bearings: each arrival stops at the wall (feet 5.0 m from the axis) on the plinth, within a few seconds.
        var arrived = 0
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi + 0.2
            let start = c + SIMD2(cos(a), sin(a)) * 14
            bot.game.player.position = SIMD3(start.x, scene.groundHeight(x: start.x, z: start.y), start.y)
            bot.wait(0.3)
            _ = bot.approach(c, seconds: 13)
            let d = simd_length(SIMD2(bot.feet.x, bot.feet.z) - c)
            if d < Lighthouse.colliderRadius + Player.radius + 0.35 && d > Lighthouse.colliderRadius + Player.radius - 0.05 { arrived += 1 }
        }
        // F01 W5.5: the whole route, dock to lighthouse and all the way back down to the start of the causeway, leg by leg, reporting where it stops.
        do {
            let rg = Game(scene: scene); let rb = PlaythroughBot(rg)
            let route = Layout.lanternPath + Array(Layout.route.reversed().dropFirst().dropLast(0))
            var failedAt = "none", minPaceSeen: Float = 1, t0 = rb.feet
            for (i, p) in route.enumerated() {
                let before = rb.feet
                if !rb.walk(to: p, within: (p.x == Layout.lighthouse.x && p.z == Layout.lighthouse.z) ? 6.2 : 2.5, timeout: 360) { failedAt = "leg \(i) toward (\(Int(p.x)), \(Int(p.z))) stopped at (\(Int(rb.feet.x)), \(Int(rb.feet.z)), y \(rb.feet.y))"; break }
                _ = before; t0 = rb.feet
            }
            _ = minPaceSeen; minPaceSeen = 0
            check(failedAt == "none", "a bot walks the whole lantern route out and back without stopping (\(failedAt))")
        }
        // The optional slip (default off): on a slope beyond the limit it carries you downhill; off, it does not.
        do {
            var steepAt: SIMD2<Float>?
            search2: for xi in stride(from: -250, to: 250, by: 4) { for zi in stride(from: -300, to: 250, by: 4) {
                let x = Float(xi), z = Float(zi)
                let sl = simd_length(SIMD2(scene.groundHeight(x: x + 1, z: z) - scene.groundHeight(x: x - 1, z: z), scene.groundHeight(x: x, z: z + 1) - scene.groundHeight(x: x, z: z - 1))) / 2
                if scene.groundHeight(x: x, z: z) > 8 && sl > 1.0 && sl < 1.8 { steepAt = SIMD2(x, z); break search2 }
            } }
            if let sp = steepAt {
                func drift(_ on: Bool) -> Float {
                    Player.slipEnabled = on
                    Player.confinementEnabled = false                    // M10.4: this is slope physics on an arbitrary hillside, not a corridor
                    let sg = Game(scene: scene); let sb = PlaythroughBot(sg)
                    sg.player.position = SIMD3(sp.x, scene.groundHeight(x: sp.x, z: sp.y), sp.y)
                    let h0 = sg.player.position.y
                    sb.wait(3)
                    Player.slipEnabled = false
                    Player.confinementEnabled = true
                    return h0 - sb.feet.y
                }
                // F03 A3 (review): the audio chain end to end. A real player on a real steep slope with the slip on: Player.slipAmount, AudioEngine.feedSlide, AmbienceSynth.render.
                do {
                    Player.slipEnabled = true
                    Player.confinementEnabled = false                    // M10.4: slope physics on an arbitrary hillside, not a corridor (a confined player would be moved to one)
                    let sg = Game(scene: scene); let sb = PlaythroughBot(sg)
                    sg.player.position = SIMD3(sp.x, scene.groundHeight(x: sp.x, z: sp.y), sp.y)
                    let sr: Float = 44100
                    let synth = AmbienceSynth(sampleRate: sr)
                    synth.windGain = 0; synth.surfGain = 0; synth.padGain = 0; synth.master = 1
                    func block(_ seconds: Float) -> [Float] {
                        var out: [Float] = []; var l = [Float](repeating: 0, count: 1024), r = l
                        for _ in 0..<Int(seconds * sr) / 1024 { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: 1024, left: lp.baseAddress!, right: rp.baseAddress!) } }; for k in 0..<1024 { out.append(0.5 * (l[k] + r[k])) } }
                        return out
                    }
                    sb.wait(0.5)
                    AudioEngine.feedSlide(into: synth, game: sg)
                    let speedWhileSlipping = synth.slideSpeed, gravelOn = synth.slideGravel
                    _ = block(0.5)
                    let slipping = Self.rms(block(1.0))
                    // Regain footing: the flat dock end, and the slip off.
                    sg.player.position = SIMD3(Layout.dockEnd.x, scene.groundHeight(x: Layout.dockEnd.x, z: Layout.dockEnd.z), Layout.dockEnd.z)
                    sb.wait(0.3)
                    AudioEngine.feedSlide(into: synth, game: sg)
                    let speedAfter = synth.slideSpeed
                    _ = block(0.2)
                    let after = Self.rms(block(0.5))
                    Player.slipEnabled = false
                    Player.confinementEnabled = true
                    check(speedWhileSlipping > 0.5 && slipping > 0.01 && slipping < 0.15 && speedAfter == 0 && after < 0.03 * slipping,
                          "the slide sound end to end: slipping on a real steep slope feeds the synth (speed \(String(format: "%.2f", speedWhileSlipping)), gravel \(String(format: "%.2f", gravelOn))) and renders at rms \(String(format: "%.3f", slipping)) (a sensible level: the waterline surf is 0.064); on level ground the speed is \(speedAfter) and the rendered slide is gone (rms \(String(format: "%.5f", after)), under 3 % of it) within 0.2 s")
                }
                let off = drift(false), on = drift(true)
                check(off < 0.3 && on > 1.0, "the soft slip is off by default and, when enabled, carries you downhill on steep ground (standing 3 s: slid down \(off) m off, \(on) m on)")
            } else { check(true, "no steep slope found for the slip test (skipped)") }
        }
        // The way down to the causeway: how steep is the ground between the lighthouse hill and the north shore, along the straight line?
        do {
            let a = SIMD2(Layout.lighthouse.x, Layout.lighthouse.z), b = SIMD2(Layout.causewayStart.x, Layout.causewayStart.z)
            var worst: Float = 0, at = a
            var s: Float = 0; let L = simd_length(b - a)
            while s < L - 5 {
                let p0 = a + (b - a) / L * s, p1 = a + (b - a) / L * (s + 5)
                let g = abs(scene.groundHeight(x: p1.x, z: p1.y) - scene.groundHeight(x: p0.x, z: p0.y)) / 5
                if g > worst { worst = g; at = p0 }
                s += 5
            }
            print("steepest 5 m between the lighthouse and the causeway start: \(worst) at (\(at.x), \(at.y))")
        }
        // Wandering at random around the tower (and over the plinth, the steps and the door), looking for a place the player cannot walk out of.
        var trapped: [SIMD2<Float>] = [], stalls = 0
        for seed in 1...6 {
            let a = Float(seed) * 1.1
            let start = c + SIMD2(cos(a), sin(a)) * 9
            bot.game.player.position = SIMD3(start.x, scene.groundHeight(x: start.x, z: start.y), start.y)
            let r = bot.wander(around: c, radius: seed <= 3 ? 16 : 45, seconds: 120, seed: UInt32(seed * 977))
            trapped += r.trapped; stalls += r.stalls
        }
        check(trapped.isEmpty, "a random-walk bot never gets trapped within 16 and 45 m of the lighthouse (\(trapped.count) trapped, \(stalls) harmless stalls; first at \(trapped.first.map { "(\($0.x), \($0.y))" } ?? "none"))")
        // The final approach as a player takes it: from the summit stone up the lantern path to the door, then onto the steps in front of it.
        bot.game.player.position = SIMD3(Layout.summitStone.x, scene.groundHeight(x: Layout.summitStone.x, z: Layout.summitStone.z), Layout.summitStone.z)
        bot.wait(0.3)
        let door = SIMD3(Layout.lighthouse.x, Layout.lighthouse.y, Layout.lighthouse.z + Lighthouse.colliderRadius + Player.radius + 0.4)
        let reached = bot.walk(to: door, within: 1.0, timeout: 180, straight: true)          // M10.6: this is a physics check of the final approach to the steps, so it keeps the straight line (the network route arrives at the 1 m circle from the side)
        check(reached, "a bot walks from the summit stone to the lighthouse door (\(reached ? "arrived" : "stopped at \(bot.feet)"))")
        check(bot.feet.y > Layout.lighthouse.y + 0.1, "and stands on the plinth in front of the door (feet \(bot.feet.y - Layout.lighthouse.y) m above the pad)")
        // F01 W4.2 phase 1: standing at the door, clicking it gives a rattle, a thump and one line in the keeper's voice; nothing opens.
        _ = bot.game.drainEvents()
        bot.aim(at: SIMD3(Layout.lighthouse.x, Layout.lighthouse.y + 1.2, Layout.lighthouse.z + 4.3))
        let hoveredDoor = bot.game.hovered?.id
        let clicked = bot.click("lh_door")
        let evs = bot.game.drainEvents()
        check(clicked && evs.contains(.chime(.doorLocked)) && (bot.game.banner ?? "").hasPrefix("Locked."), "trying the lighthouse door: a latch rattle and thump, the banner says it is locked (clicked \(clicked), hovered \(hoveredDoor ?? "nothing"), events \(evs), banner \(bot.game.banner ?? "none"), feet \(bot.feet))")
        // Steep ground behaves like a wall: walking straight into a slope steeper than the limit slides along its contour (it used to stop dead).
        var steep: SIMD2<Float>?
        search: for xi in stride(from: -250, to: 250, by: 4) { for zi in stride(from: -300, to: 250, by: 4) {
            let x = Float(xi), z = Float(zi)
            let h = scene.groundHeight(x: x, z: z)
            let slope = simd_length(SIMD2(scene.groundHeight(x: x + 1, z: z) - scene.groundHeight(x: x - 1, z: z), scene.groundHeight(x: x, z: z + 1) - scene.groundHeight(x: x, z: z - 1))) / 2
            if h > 8 && slope > Player.maxSlope * 1.15 && slope < 2.6 { steep = SIMD2(x, z); break search }
        } }
        if let sp = steep {
            let g0 = SIMD2(scene.groundHeight(x: sp.x + 0.5, z: sp.y) - scene.groundHeight(x: sp.x - 0.5, z: sp.y), scene.groundHeight(x: sp.x, z: sp.y + 0.5) - scene.groundHeight(x: sp.x, z: sp.y - 0.5))
            let up = simd_normalize(g0), start = sp - up * 1.0
            bot.game.player.position = SIMD3(start.x, scene.groundHeight(x: start.x, z: start.y), start.y)
            bot.wait(0.3)
            let before = SIMD2(bot.feet.x, bot.feet.z)
            for _ in 0..<240 { bot.game.player.yaw = atan2(up.x + 0.25 * -up.y, -(up.y + 0.25 * up.x)); var i = InputState(); i.move = SIMD2(0, 1); bot.tick(i) }
            let moved = simd_length(SIMD2(bot.feet.x, bot.feet.z) - before)
            check(moved > 2.0, "walking at a slope steeper than the limit slides along it instead of stopping dead (moved \(moved) m in 4 s at (\(sp.x), \(sp.y)))")
        } else { check(true, "no slope steeper than the limit to test on (skipped)") }
        check(arrived == 8, "walking straight at the lighthouse from eight bearings always reaches the wall (\(arrived) of 8)")
    }
}
