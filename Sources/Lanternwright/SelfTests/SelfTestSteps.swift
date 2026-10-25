import Foundation
import Metal
import simd

/// Self-tests: the camera follows steps (F02 M1, user note #28). The Glass Wood's altar dais and the islet's lens base were drawn but not walkable, so the player
/// glided through them at terrain height; now they are platforms at the drawn heights, the feet are physical, and the eye follows with a critically damped spring.
extension SelfTestRunner {
    func runSteps() {
        guard name == "all" || name == "steps" else { return }
        let gw = Scene.make(.glassWood, device: device)
        let a = GlassLayout.altar
        check(gw.platforms.count >= 3, "the Glass Wood altar dais is part of the ground you walk on (\(gw.platforms.count) platforms)")
        let top = a.y + 0.55
        check(abs(gw.groundHeight(x: a.x + 5.0, z: a.z) - top) < 1e-4 && abs(gw.groundHeight(x: a.x + 5.8, z: a.z) - (a.y + 0.37)) < 1e-4 && abs(gw.groundHeight(x: a.x + 6.4, z: a.z) - (a.y + 0.18)) < 1e-4,
              "the ground under the dais tiers equals the drawn tread heights (0.18 / 0.37 / 0.55 m)")
        // Walk in over three 18 cm-ish risers and back out at a walk, one fixed tick at a time.
        let dt = Game.tick
        for (label, inward) in [("up", true), ("down", false)] {
            var pl = Player(position: SIMD3(a.x, a.y, a.z + (inward ? 8.5 : 2.0)), yaw: inward ? 0 : .pi)      // along z: clear of the pedestals at x = +-3
            pl.position.y = gw.groundHeight(x: pl.position.x, z: pl.position.z)
            var input = InputState(); input.move = SIMD2(0, 1)
            var eye: [Float] = [pl.eyeBase], feetOK = true, maxLag: Float = 0, lastRiserTick = -1, prevFeet = pl.position.y
            for k in 0..<Int(2.3 / dt) {
                pl.step(dt: dt, input: input, scene: gw)
                eye.append(pl.eyeBase)
                if abs(pl.position.y - gw.groundHeight(x: pl.position.x, z: pl.position.z)) > 1e-5 { feetOK = false }
                maxLag = max(maxLag, abs(pl.eyeLag))
                if abs(pl.position.y - prevFeet) > 0.1 { lastRiserTick = k }
                prevFeet = pl.position.y
            }
            let mono = inward ? zip(eye, eye.dropFirst()).allSatisfy { $1 >= $0 - 4e-3 } : zip(eye, eye.dropFirst()).allSatisfy { $1 <= $0 + 4e-3 }
            var jump: Float = 0                                                      // the largest change over one 60 Hz frame (two fixed ticks)
            for k in 2..<eye.count { jump = max(jump, abs(eye[k] - eye[k - 2])) }
            check(lastRiserTick > 0, "walking \(label) the dais crosses three risers (last at tick \(lastRiserTick))")
            var firstBad = "none"
            for k in 1..<eye.count where (inward ? eye[k] < eye[k - 1] - 4e-3 : eye[k] > eye[k - 1] + 4e-3) { firstBad = "tick \(k): \(eye[k - 1]) -> \(eye[k])"; break }
            check(mono, "walking \(label) the dais: the eye height is monotonic to 4 mm per tick, which the terrain's own gentle slope uses up (\(firstBad))")
            check(jump <= 0.04, "walking \(label) the dais: no frame moves the eye by more than 4 cm (largest \(jump) m)")
            check(feetOK, "the feet are exactly on the drawn ground (physical), only the eye is smoothed")
            check(maxLag <= Player.maxEyeLag + 1e-4, "the eye never lags the feet by more than \(Player.maxEyeLag) m (\(maxLag))")
        }
        // Settling: after a single 18 cm riser, the eye is within 2 mm after 0.3 s.
        do {
            var pl = Player(position: SIMD3(a.x, gw.groundHeight(x: a.x, z: a.z + 5.9), a.z + 5.9), yaw: 0)
            var input = InputState(); input.move = SIMD2(0, 1)
            var t: Float = 0, crossed: Float? = nil
            while t < 4 {
                pl.step(dt: dt, input: input, scene: gw); t += dt
                if crossed == nil && pl.position.y > a.y + 0.5 { crossed = t }
                if let c = crossed, t - c >= 0.3 { break }
            }
            check(crossed != nil && abs(pl.eyeLag) < 0.002, "0.3 s after a riser the eye has settled (lag \(pl.eyeLag) m)")
        }
        // The stair audit (F02 M1): every walkable step on both islands.
        let home = Scene.makeWorld(device: device)
        check(home.platforms.count >= 10, "the home island's steps are all platforms: lighthouse door steps and plinth, the islet's lens base (\(home.platforms.count))")
    }
}
