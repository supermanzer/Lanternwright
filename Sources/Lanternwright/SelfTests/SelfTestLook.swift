import Foundation
import simd

/// Self-tests: the look model (M10.1). `LookFilter` is pure, so every property is checked with synthetic frame times.
extension SelfTestRunner {
    func runLook() {
        guard name == "all" || name == "look" else { return }
        let deg: Float = .pi / 180
        let calm = LookFilter.defaultCalm

        /// Feed `rate` rad/s of yaw for `seconds`, then zeros for `drain` seconds, at `fps`. Returns (total, peak output rate, per-frame outputs).
        func run(rate: Float, seconds: Float, drain: Float, fps: Float, calm: Float) -> (total: Float, peak: Float, first: Float) {
            var f = LookFilter()
            let dt = 1 / fps
            var total: Float = 0, peak: Float = 0, first: Float = 0
            let on = Int((seconds * fps).rounded()), off = Int((drain * fps).rounded())
            for i in 0..<(on + off) {
                let raw = SIMD2<Float>(i < on ? rate * dt : 0, 0)
                let out = f.filter(raw, dt: dt, calm: calm)
                if i == 0 { first = out.x }
                total += out.x
                peak = max(peak, abs(out.x) / dt)
            }
            return (total, peak, first)
        }

        // (a) The same physical sweep (90 degrees/s for a second) turns the same amount at any frame rate, and none of it is lost.
        let sweep = [30, 60, 120].map { run(rate: 90 * deg, seconds: 1, drain: 0.7, fps: Float($0), calm: calm).total }
        let want: Float = 90 * deg
        check(sweep.allSatisfy { abs($0 - want) / want < 0.01 }, "look: a 90 deg/s sweep turns 90 degrees within 1% at 30, 60 and 120 fps (\(sweep.map { $0 / deg }))")
        check((sweep.max()! - sweep.min()!) / want < 0.01, "look: the total turn agrees across frame rates within 1%")

        // (b) A single mouse count turns the camera on the very next frame (no dead zone), at any frame rate, and the whole count is eventually delivered.
        let count = Settings().effectiveSensitivity
        for fps in [30, 60, 120] as [Float] {
            var f = LookFilter()
            let out = f.filter(SIMD2(count, 0), dt: 1 / fps, calm: calm)
            var total = out.x
            for _ in 0..<Int(fps) { total += f.filter(.zero, dt: 1 / fps, calm: calm).x }
            check(out.x > 0 && abs(total - count) / count < 0.01, "look: a 1-count nudge turns on the first frame at \(Int(fps)) fps (\(out.x / count) of it) and all of it arrives")
        }
        var nudge = LookFilter()
        let down = nudge.filter(SIMD2(0, -count), dt: 1.0 / 60, calm: calm)
        check(down.y < 0 && down.x == 0, "look: a pitch nudge moves pitch only, in the right direction")

        // (c) A fast flick (600 degrees/s held for a second) is compressed to under 250 degrees/s at the output, at any frame rate.
        for fps in [30, 60, 120] as [Float] {
            let r = run(rate: 600 * deg, seconds: 1, drain: 0.5, fps: fps, calm: calm)
            check(r.peak / deg < 250 && r.peak / deg > 150, "look: a 600 deg/s flick at \(Int(fps)) fps is compressed to \(Int(r.peak / deg)) deg/s")
        }
        // Normal turning is untouched by the limiter: a 120 deg/s turn comes out at 120 once the smoothing has settled.
        let normal = run(rate: 120 * deg, seconds: 1, drain: 0, fps: 60, calm: calm)
        check(abs(normal.peak / deg - 120) < 2, "look: a 120 deg/s turn is not limited (peak \(normal.peak / deg) deg/s)")
        // A stronger calm limits earlier; a weaker one later.
        let calmer = run(rate: 600 * deg, seconds: 1, drain: 0, fps: 60, calm: 1).peak
        let looser = run(rate: 600 * deg, seconds: 1, drain: 0, fps: 60, calm: 0.2).peak
        check(calmer < run(rate: 600 * deg, seconds: 1, drain: 0, fps: 60, calm: calm).peak && looser > calmer, "look: more calm means a lower ceiling")

        // (d) calm = 0 reproduces today's output exactly: record real Input samples (mouse counts and the arrow keys) and compare bit for bit with the old formula.
        let input = Input()
        input.sensitivity = 0.0022
        var seed: UInt32 = 12345
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(Int32(bitPattern: seed >> 8) % 4000) / 10 }
        var f0 = LookFilter()
        var identical = true, frames = 0
        for i in 0..<600 {
            let dx = rnd(), dy = rnd()
            input.addMouse(dx: dx, dy: dy)
            if i % 7 == 0 { input.keyDown(Input.Key.left) } else if i % 7 == 3 { input.keyUp(Input.Key.left) }
            let s = input.sample(captured: true)
            let out = f0.filter(s.look, dt: [1.0 / 30, 1.0 / 60, 1.0 / 144][i % 3], calm: 0)
            let turn: Float = i % 7 < 3 ? -1 : 0                                    // the left arrow goes down at i%7==0 and up at i%7==3 (before that frame's sample)
            let old = SIMD2(dx * 0.0022 + turn * 0.03, -dy * 0.0022)
            if out.x.bitPattern != old.x.bitPattern || out.y.bitPattern != old.y.bitPattern || out.x.bitPattern != s.look.x.bitPattern { identical = false }
            frames += 1
        }
        check(identical && frames == 600, "look: calm 0 returns the recorded Input output bit for bit (\(frames) frames, the old formula)")

        // The same holds with invertY on: the pitch sign flips and nothing else.
        let inv = Input(); inv.sensitivity = 0.0022; inv.invertY = true
        inv.addMouse(dx: 12, dy: 7)
        let si = inv.sample(captured: true)
        var f1 = LookFilter()
        let oi = f1.filter(si.look, dt: 1.0 / 60, calm: 0)
        check(oi.y.bitPattern == (-Float(7) * 0.0022 * -1).bitPattern && oi.x.bitPattern == (Float(12) * 0.0022).bitPattern, "look: calm 0 with invertY returns the old formula bit for bit")

        // Safety: a zero frame time (the first frame) never makes a NaN and never loses input.
        var g = LookFilter()
        let z = g.filter(SIMD2(0.01, 0), dt: 0, calm: calm)
        let after = g.filter(.zero, dt: 1.0 / 60, calm: calm)
        check(z == .zero && after.x.isFinite && after.x > 0, "look: dt = 0 emits nothing, loses nothing and stays finite")

        // The pitch clamp is 65 degrees, and Player.applyLook goes through the filter (calm 0 here so the numbers are the raw ones).
        let saved = LookFilter.calm
        LookFilter.calm = 0
        var p = Player(position: .zero, yaw: 0)
        p.applyLook(SIMD2(0, 2), dt: 1.0 / 60)
        let up = p.pitch
        p.applyLook(SIMD2(0, -4), dt: 1.0 / 60)
        check(abs(up - 65 * deg) < 1e-6 && abs(p.pitch + 65 * deg) < 1e-6, "look: pitch is clamped to +-65 degrees (\(up / deg), \(p.pitch / deg))")
        var w = Player(position: .zero, yaw: 3.0)
        w.applyLook(SIMD2(0.3, 0), dt: 1.0 / 60)
        check(w.yaw < 0 && w.yaw > -.pi, "look: yaw still wraps around at +-pi")
        LookFilter.calm = saved

        // Settings: defaults, tolerant decoding of an old blob, and clamping.
        let d = Settings()
        check(abs(d.lookSpeed - 0.7) < 1e-6 && abs(d.calmCamera - 0.6) < 1e-6 && abs(d.effectiveSensitivity - 0.0022 * 0.7) < 1e-9, "look: defaults are lookSpeed 0.7 and calm 0.6 (0.7 of today's 0.0022)")
        let old = try? JSONDecoder().decode(Settings.self, from: Data(#"{"sensitivity":0.003,"volume":0.2}"#.utf8))
        check(old != nil && old!.lookSpeed == 0.7 && old!.calmCamera == 0.6 && old!.volume == 0.2, "look: a settings blob saved before M10.1 loads with the new defaults and keeps its values")
        var bad = Settings(); bad.lookSpeed = .nan; bad.calmCamera = 9
        var bad2 = Settings(); bad2.lookSpeed = 9; bad2.calmCamera = -1
        check(bad.clamped().lookSpeed == 0.7 && bad.clamped().calmCamera == 1 && bad2.clamped().lookSpeed == 1.5 && bad2.clamped().calmCamera == 0, "look: lookSpeed (0.5...1.5) and calmCamera (0...1) are clamped; non-finite falls back to the default")
    }
}
