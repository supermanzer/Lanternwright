import Foundation
import simd

/// Self-tests: the pace model (M10.2). The speed rule is a pure function (`Player.wishSpeed`), so flat ground, a 25 degree slope and the shallows are exact;
/// the dock gives one real walk through `Player.step` to show the pieces are wired together.
extension SelfTestRunner {
    func runPace() {
        guard name == "all" || name == "pace" else { return }
        let savedPace = Player.paceScale
        Player.paceScale = 1
        func near(_ a: Float, _ b: Float, _ tol: Float) -> Bool { abs(a - b) <= tol }

        // The new constants, on flat dry ground.
        let flat = Player.wishSpeed(run: false, pace: Player.paceFactor(slope: 0), wading: Player.wading(ground: 2))
        let run = Player.wishSpeed(run: true, pace: Player.paceFactor(slope: 0), wading: Player.wading(ground: 2))
        check(near(flat, 2.6, 1e-5) && near(run, 4.4, 1e-5), "pace: walk 2.6 m/s and run 4.4 m/s on flat ground (\(flat), \(run))")

        // A 25 degree slope: the existing paceFactor is kept, so a climb is about 74 % of the flat pace, a descent about 8 % quicker at most.
        let up = Player.wishSpeed(run: false, pace: Player.paceFactor(slope: tan(25 * .pi / 180)), wading: 1)
        let down = Player.wishSpeed(run: false, pace: Player.paceFactor(slope: -tan(25 * .pi / 180)), wading: 1)
        check(near(up, 2.6 * 0.738, 0.01) && down > flat && down <= 2.6 * 1.081, "pace: a 25 degree climb is \(up) m/s (about 74 % of 2.6), the descent \(down) m/s")
        let upRun = Player.wishSpeed(run: true, pace: Player.paceFactor(slope: tan(25 * .pi / 180)), wading: 1)
        check(near(upRun, 4.4 * 0.738, 0.015), "pace: running up a 25 degree slope is \(upRun) m/s")

        // The shallows: 60 % at ankle depth and below, none on dry sand.
        let wade = Player.wishSpeed(run: false, pace: 1, wading: Player.wading(ground: -0.3))
        check(near(wade, 2.6 * 0.6, 1e-4) && near(Player.wading(ground: 0.5), 1, 1e-6), "pace: wading slows to 60 % (\(wade) m/s) and dry ground does not")

        // The setting scales walk and run together and is clamped; the cadence follows it.
        Player.paceScale = 1.3
        check(near(Player.wishSpeed(run: false, pace: 1, wading: 1), 3.38, 1e-4) && near(Player.wishSpeed(run: true, pace: 1, wading: 1), 5.72, 1e-4), "pace: the pace setting 1.3 scales both speeds")
        let fast = Player.stepLength(speed: Player.scaledWalkSpeed)
        Player.paceScale = 0.7
        let slow = Player.stepLength(speed: Player.scaledWalkSpeed)
        Player.paceScale = 1
        check(near(fast, slow, 1e-5) && near(Player.stepLength(speed: Player.walkSpeed), 1.2, 1e-5), "pace: a walk at any pace setting has the walking stride (1.2 m)")
        var wild = Settings(); wild.pace = 9
        var nan = Settings(); nan.pace = .nan
        var low = Settings(); low.pace = 0
        check(wild.clamped().pace == 1.3 && nan.clamped().pace == 1 && low.clamped().pace == 0.7 && Settings().pace == 1, "pace: the setting defaults to 1.0, is clamped to 0.7...1.3, and non-finite falls back to 1")
        let old = try? JSONDecoder().decode(Settings.self, from: Data(#"{"volume":0.2}"#.utf8))
        check(old?.pace == 1 && old?.volume == 0.2, "pace: a settings blob saved before M10.2 loads with pace 1")

        // Gait: walking is about 2.2 steps/s, running about 2.9 (the stride lengthens and the cadence quickens).
        let walkRate = Player.walkSpeed / Player.stepLength(speed: Player.walkSpeed), runRate = Player.runSpeed / Player.stepLength(speed: Player.runSpeed)
        check(walkRate > 1.9 && walkRate < 2.4 && runRate > 1.2 * walkRate && runRate < 3.2, "pace: cadence follows the speed (walk \(walkRate), run \(runRate) steps/s)")

        // A real walk along the dock through Player.step: the eased start, the steady speed, the eased stop.
        let scene = Scene.makeWorld(device: device)
        let from = Layout.dockEnd, to = SIMD3<Float>(150, 1.5, 172)
        let yaw = atan2(to.x - from.x, -(to.z - from.z))
        var pl = Player(position: from, yaw: yaw); pl.position.y = scene.groundHeight(x: from.x, z: from.z)
        var go = InputState(); go.move = SIMD2(0, 1)
        var t63: Float = -1, steps = 0
        for k in 0..<Int(4 / Game.tick) {
            if pl.step(dt: Game.tick, input: go, scene: scene) { steps += 1 }
            if t63 < 0 && pl.speed >= 0.632 * 2.6 * 0.99 { t63 = Float(k + 1) * Game.tick }
        }
        check(near(pl.speed, 2.6, 0.1), "pace: walking the dock settles at 2.6 m/s (\(pl.speed))")
        check(t63 > 0.08 && t63 < 0.2, "pace: it takes about 0.12 s to reach 63 % of walking speed (\(t63) s)")
        check(steps >= 7 && steps <= 10, "pace: 4 s of walking is \(steps) footfalls (about 2.2 per second)")
        var stop = InputState(); stop.move = .zero
        var tStop: Float = -1
        let v0 = pl.speed
        for k in 0..<Int(2 / Game.tick) {
            pl.step(dt: Game.tick, input: stop, scene: scene)
            if tStop < 0 && pl.speed <= 0.368 * v0 { tStop = Float(k + 1) * Game.tick }
        }
        check(tStop > 0.1 && tStop < 0.25, "pace: it eases to a stop, losing 63 % of its speed in \(tStop) s (about 0.16 s)")
        var runner = Player(position: from, yaw: yaw); runner.position.y = scene.groundHeight(x: from.x, z: from.z)
        go.run = true
        for _ in 0..<Int(3 / Game.tick) { runner.step(dt: Game.tick, input: go, scene: scene) }
        check(near(runner.speed, 4.4, 0.15), "pace: running the dock settles at 4.4 m/s (\(runner.speed))")
        Player.paceScale = savedPace
    }
}
