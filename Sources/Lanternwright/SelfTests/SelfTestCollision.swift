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
            _ = bot.approach(c, seconds: 9)
            let d = simd_length(SIMD2(bot.feet.x, bot.feet.z) - c)
            if d < Lighthouse.colliderRadius + Player.radius + 0.35 && d > Lighthouse.colliderRadius + Player.radius - 0.05 { arrived += 1 }
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
        let reached = bot.walk(to: door, within: 1.0, timeout: 120)
        check(reached, "a bot walks from the summit stone to the lighthouse door (\(reached ? "arrived" : "stopped at \(bot.feet)"))")
        check(bot.feet.y > Layout.lighthouse.y + 0.1, "and stands on the plinth in front of the door (feet \(bot.feet.y - Layout.lighthouse.y) m above the pad)")
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
