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
        // F03 M1 (#35, "I should be able to step up onto obstacles of such a modest height but I cannot"): the dock's first board was refused as a steep slope, because only
        // `Platform`s were exempt from the slope rule and a deck is not one. A step up of at most `Player.maxStep` onto a platform or a deck is taken; a higher one is a wall.
        do {
            let home = Scene.makeWorld(device: device)
            func flatSpot() -> SIMD2<Float>? {
                for xi in stride(from: -250, to: 250, by: 5) { for zi in stride(from: -250, to: 250, by: 5) {
                    let x = Float(xi), z = Float(zi), g = home.groundHeight(x: x, z: z)
                    if g < 3 { continue }
                    var ok = true
                    for dx in stride(from: Float(-4), through: 4, by: 2) { for dz in stride(from: Float(-4), through: 4, by: 2) { if abs(home.groundHeight(x: x + dx, z: z + dz) - g) > 0.15 { ok = false } } }
                    if ok { return SIMD2(x, z) }
                } }
                return nil
            }
            if let f = flatSpot() {
                func tryBox(_ h: Float) -> (climbed: Bool, x: Float) {
                    let g = home.groundHeight(x: f.x, z: f.y)
                    home.platforms.append(Scene.Platform(center: f, halfSize: SIMD2(1.5, 1.5), top: g + h))
                    defer { home.platforms.removeLast() }
                    var pl = Player(position: SIMD3(f.x - 3.0, g, f.y), yaw: .pi / 2)
                    var input = InputState(); input.move = SIMD2(0, 1)
                    var topY: Float = -.infinity
                    for _ in 0..<Int(3.5 / dt) { pl.step(dt: dt, input: input, scene: home); topY = max(topY, pl.position.y) }          // (it walks across the box and off the far side)
                    return (topY > g + h - 0.01, pl.position.x - f.x)
                }
                let r30 = tryBox(0.30), r40 = tryBox(0.40), r60 = tryBox(0.60)
                check(r30.climbed && r40.climbed && !r60.climbed && r60.x < -1.4, "a step up is taken at 0.30 m and 0.40 m (the plan's 0.35-0.4) and refused at 0.60 m (climbed \(r30.climbed) / \(r40.climbed) / \(r60.climbed); the 0.6 m box stops the player at x = \(String(format: "%.2f", r60.x)) m from its centre, edge at -1.5); the limit is \(Player.maxStep) m")
            } else { check(false, "found a flat spot for the step tests") }
            // The player's own spot in #35: the dock's landward end. Walk onto the first board from the path.
            let strip = Layout.dockStrip(), dir = normalize(strip.b - strip.a)
            let start = strip.a - dir * 2.5
            var pl = Player(position: SIMD3(start.x, home.groundHeight(x: start.x, z: start.y), start.y), yaw: atan2(dir.x, -dir.y))
            var input = InputState(); input.move = SIMD2(0, 1)
            var firstRise: Float = 0, prevY = pl.position.y
            for _ in 0..<Int(5 / dt) { pl.step(dt: dt, input: input, scene: home); firstRise = max(firstRise, pl.position.y - prevY); prevY = pl.position.y }
            let along = simd_dot(SIMD2(pl.position.x, pl.position.z) - strip.a, dir)
            check(along > 4.0 && home.walkables.contains { $0.height(at: SIMD2(pl.position.x, pl.position.z)) != nil }, "walking from the path onto the dock's landward end works: after 5 s the player is \(String(format: "%.1f", along)) m along the boards (largest single step up \(String(format: "%.0f", firstRise * 100)) cm)")
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
