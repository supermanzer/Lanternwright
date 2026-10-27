import Foundation
import simd

/// Self-tests: the framing assist at vantage stations (M10.5), through the real `Player.applyLook`.
extension SelfTestRunner {
    func runFraming() {
        guard name == "all" || name == "framing" else { return }
        let deg: Float = .pi / 180
        let scene = Scene.makeWorld(device: device)
        let net = Layout.Navigation.varrow
        guard let st = net.vantages.first(where: { $0.name.hasPrefix("the climb") }), let st2 = net.vantages.first(where: { $0.name.hasPrefix("the descent") }) else {
            check(false, "framing: the two stones stations exist in Layout.Navigation.varrow"); return
        }
        check(!st.provisional && !st2.provisional && st.tolerance == 4 && st2.tolerance == 4, "framing: the stones pilot has two stations (the climb and the descent), 4 m tolerance")
        let savedCalm = LookFilter.calm
        defer { LookFilter.calm = savedCalm }
        func forward(_ p: Player) -> SIMD3<Float> { SIMD3(sin(p.yaw) * cos(p.pitch), sin(p.pitch), -cos(p.yaw) * cos(p.pitch)) }
        func angle(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { atan2(simd_length(simd_cross(a, b)), simd_dot(a, b)) }
        func player(at v: NavNetwork.Vantage, offset: SIMD2<Float> = .zero, yawOff: Float = 0, pitchOff: Float = 0) -> (Player, SIMD3<Float>) {
            var p = Player(position: SIMD3(v.position.x + offset.x, 0, v.position.y + offset.y), yaw: 0)
            p.position.y = scene.groundHeight(x: p.position.x, z: p.position.z)
            let want = simd_normalize(v.target - (p.position + SIMD3(0, Player.eyeHeight, 0)))
            p.yaw = atan2(want.x, -want.z) + yawOff; p.pitch = asin(want.y) + pitchOff
            return (p, want)
        }

        // It engages, closes the error smoothly (never overshoots) and settles.
        LookFilter.calm = 0
        var (p, want) = player(at: st, yawOff: 10 * deg, pitchOff: -3 * deg)
        let start = angle(forward(p), want)
        var prev = start, monotone = true, firstTenth: Float = 0
        for k in 0..<(30 * 120) {
            p.applyLook(.zero, dt: 1.0 / 120, nav: net)
            let a = angle(forward(p), want)
            if a > prev + 1e-5 { monotone = false }
            prev = a
            if k == 11 { firstTenth = start - a }
        }
        check(start > 9 * deg && prev < 0.5 * deg && monotone, "framing: from \(start / deg) degrees off it settles within \(prev / deg) degrees and never overshoots")
        check(firstTenth < 0.15 * deg, "framing: it eases in (\(firstTenth / deg) degrees in the first 0.1 s)")

        // The rate: never above 6 degrees/s per frame or over any one-second window, at 30, 60 and 120 fps; scaled down by look-closer.
        for fps in [30, 60, 120] as [Float] {
            for (scale, limit) in [(Float(1), 6 * deg), (0.35, 6 * deg * 0.35)] {
                var (q, _) = player(at: st, yawOff: 20 * deg, pitchOff: 2 * deg)
                let dt = 1 / fps
                var worstFrame: Float = 0, window = [Float](), worstWindow: Float = 0
                for _ in 0..<Int(15 * fps) {
                    let before = forward(q)
                    q.applyLook(.zero, dt: dt, nav: net, assistScale: scale)
                    let moved = angle(before, forward(q))
                    worstFrame = max(worstFrame, moved / dt)
                    window.append(moved)
                    if window.count > Int(fps) { window.removeFirst() }
                    worstWindow = max(worstWindow, window.reduce(0, +))
                }
                check(worstFrame <= limit * 1.001 && worstWindow <= limit * 1.001 && worstFrame > limit * 0.5,
                      "framing: at \(Int(fps)) fps, look-closer x\(scale), the pull peaks at \(worstFrame / deg) deg/s (\(worstWindow / deg) deg in the worst second; limit \(limit / deg))")
            }
        }

        // Cancelled at once by input, and off for the hold-off: after a mouse movement the camera moves only by what the player did.
        (p, want) = player(at: st, yawOff: 12 * deg)
        for _ in 0..<(2 * 60) { p.applyLook(.zero, dt: 1.0 / 60, nav: net) }
        let engaged = angle(forward(p), want)
        let yawBefore = p.yaw, pitchBefore = p.pitch
        p.applyLook(SIMD2(0.003, -0.002), dt: 1.0 / 60, nav: net)
        check(p.yaw == yawBefore + 0.003 && p.pitch == pitchBefore - 0.002, "framing: on the frame the player turns, the camera moves exactly by their input and not by the assist")
        let held = (p.yaw, p.pitch)
        var still = true
        for _ in 0..<30 { p.applyLook(.zero, dt: 1.0 / 60, nav: net); if (p.yaw, p.pitch) != held { still = false } }
        check(still && engaged < start, "framing: it stays off for 0.5 s after input, and had been pulling before it (\(engaged / deg) degrees left)")
        for _ in 0..<30 { p.applyLook(.zero, dt: 1.0 / 60, nav: net) }
        check((p.yaw, p.pitch) != held, "framing: and resumes once the player has been still")
        // With the default look filter on: the same input stream, with and without the assist, gives the same camera for the whole hold-off.
        LookFilter.calm = LookFilter.defaultCalm
        var (a, _) = player(at: st, yawOff: 12 * deg), (b, _) = player(at: st, yawOff: 12 * deg)
        for _ in 0..<120 { a.applyLook(.zero, dt: 1.0 / 60, nav: net); b.applyLook(.zero, dt: 1.0 / 60, nav: nil) }
        var same = true
        a.applyLook(SIMD2(0.004, 0), dt: 1.0 / 60, nav: net); b.applyLook(SIMD2(0.004, 0), dt: 1.0 / 60, nav: nil)
        let a0 = a.yaw - b.yaw, p0 = a.pitch - b.pitch                                          // whatever the assist had already added before the input
        for _ in 0..<30 {
            a.applyLook(.zero, dt: 1.0 / 60, nav: net); b.applyLook(.zero, dt: 1.0 / 60, nav: nil)
            if abs((a.yaw - b.yaw) - a0) > 1e-6 || abs((a.pitch - b.pitch) - p0) > 1e-6 { same = false }
        }
        check(same, "framing: with the default look filter on, the assist adds nothing after input while the filter's tail drains")

        // Randomised: 60 s of random input at 60 fps; in the 0.6 s after any real input (above the cancel threshold) the camera moves by the input alone.
        LookFilter.calm = 0
        var seed: UInt32 = 5_105
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
        (p, _) = player(at: st, yawOff: 15 * deg)
        var sinceInput: Float = 99, checked = 0, bad = 0, pulled = 0
        for _ in 0..<(60 * 60) {
            var raw = SIMD2<Float>.zero
            if rnd() < 0.012 { raw = SIMD2((rnd() - 0.5) * 0.02, (rnd() - 0.5) * 0.01) }
            let isInput = simd_length(raw) * 60 > FramingAssist.cancelRate
            let before = (p.yaw, p.pitch)
            p.applyLook(raw, dt: 1.0 / 60, nav: net)
            if isInput { sinceInput = 0 } else { sinceInput += 1.0 / 60 }
            if isInput || sinceInput < 0.5 {
                checked += 1
                if abs(p.yaw - (before.0 + raw.x)) > 1e-6 && !(before.0 + raw.x > .pi || before.0 + raw.x < -.pi) { bad += 1 }
                if abs(p.pitch - (before.1 + raw.y)) > 1e-6 && abs(before.1 + raw.y) < Player.maxPitch - 1e-3 { bad += 1 }
            } else if (p.yaw, p.pitch) != before { pulled += 1 }
        }
        check(bad == 0 && checked > 300 && pulled > 100, "framing: over 60 s of random input the assist never moved the camera on or within 0.5 s of the player's input (\(checked) frames checked, \(bad) violations; it pulled on \(pulled) quiet frames)")

        // It stays out of the way everywhere else: outside the station's tolerance, outside the 25 degree cone, and with no network (free roam).
        LookFilter.calm = 0
        (p, _) = player(at: st, offset: SIMD2(6, 0), yawOff: 10 * deg)
        let outsidePose = (p.yaw, p.pitch)
        for _ in 0..<(5 * 60) { p.applyLook(.zero, dt: 1.0 / 60, nav: net) }
        check((p.yaw, p.pitch) == outsidePose, "framing: 6 m from the station (tolerance 4 m) it does nothing")
        (p, _) = player(at: st, yawOff: 40 * deg)
        let coneYaw = p.yaw
        for _ in 0..<(5 * 60) { p.applyLook(.zero, dt: 1.0 / 60, nav: net) }
        check(p.yaw == coneYaw, "framing: looking 40 degrees away from the target (cone 25) it does nothing")
        (p, _) = player(at: st, yawOff: 10 * deg)
        let freeYaw = p.yaw
        for _ in 0..<(5 * 60) { p.applyLook(.zero, dt: 1.0 / 60, nav: nil) }
        check(p.yaw == freeYaw, "framing: with no network (free roam) it does nothing")
        // Through the real game loop: the assist acts in play, and does not act behind an open journal.
        LookFilter.calm = 0
        func yawAfterThreeSeconds(journalOpen: Bool) -> (Float, Float) {
            let g = Game(scene: scene)
            var q = Player(position: SIMD3(st.position.x, 0, st.position.y), yaw: 0)
            q.position.y = scene.groundHeight(x: q.position.x, z: q.position.z)
            let aim = simd_normalize(st.target - (q.position + SIMD3(0, Player.eyeHeight, 0)))
            q.yaw = atan2(aim.x, -aim.z) + 10 * deg; q.pitch = asin(aim.y)
            g.player = q
            g.journal.isOpen = journalOpen
            var t = 5000.0
            for _ in 0..<180 { t += 1.0 / 60; g.advance(now: t, input: InputState()) }
            return (g.player.yaw - q.yaw, g.player.pitch - q.pitch)
        }
        let played = yawAfterThreeSeconds(journalOpen: false), paused = yawAfterThreeSeconds(journalOpen: true)
        check(abs(played.0) > 0.5 * deg && paused.0 == 0 && paused.1 == 0, "framing: in the game loop it pulls the view (\(played.0 / deg) degrees in 3 s) and stays off behind an open journal")
        // The other station works too, and its target is where the plan says (the frames are shots/m105-station-*.png).
        (p, want) = player(at: st2, yawOff: -8 * deg, pitchOff: 2 * deg)
        for _ in 0..<(20 * 60) { p.applyLook(.zero, dt: 1.0 / 60, nav: net) }
        check(angle(forward(p), want) < 0.5 * deg, "framing: the descent station draws the view to its target too (\(angle(forward(p), want) / deg) degrees off after 20 s)")
    }
}
