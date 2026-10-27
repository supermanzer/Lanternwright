import Foundation
import Metal
import simd

/// Self-tests: the player's contact with water (F02 A5, note #29). The state machine, the rendered sounds, and a bot that really wades in and out of the sea.
extension SelfTestRunner {
    func runWater() {
        guard name == "all" || name == "water" else { return }
        // The state machine: one enter per entry, one leave per exit, nothing in between, no flutter on the waterline.
        do {
            var w = WaterContact()
            var events: [WaterContact.Event] = []
            func run(_ ground: [Float], speed: Float) { for g in ground { if let e = w.update(groundY: g, speed: speed) { events.append(e) } } }
            run([1.0, 0.6, 0.3, 0.1, 0.02, -0.05, -0.15, -0.3, -0.35], speed: Player.walkSpeed)                       // walk in
            run([-0.3, -0.3, -0.2, -0.25, -0.1, -0.05, -0.01, -0.03], speed: Player.walkSpeed)                       // wade about, a flicker on the line
            run([0.0, 0.05, 0.09, 0.0, -0.01, 0.08], speed: Player.walkSpeed)                                           // hover on the line: hysteresis (wet until 10 cm above, dry until 2 cm below)
            run([0.12, 0.3, 0.8], speed: Player.walkSpeed)                                                           // out
            run([0.3, 0.0, -0.1, -0.2], speed: Player.runSpeed)                                                     // and in again, running
            let enters = events.compactMap { e -> Float? in if case .enter(let s) = e { return s } else { return nil } }
            check(enters.count == 2 && events.filter { $0 == .leave }.count == 1 && events.count == 3, "the first contact fires once per entry (2 entries, 1 exit, no flutter on the line): \(events)")
            check(enters.count == 2 && enters[1] > 1.6 * enters[0], "a run into the water is a stronger event than a walk (strength \(enters.map { String(format: "%.2f", $0) }))")
            var d = WaterContact()
            check(d.drag(speed: Player.walkSpeed) == 0 && d.lap(speed: 0) == 0, "out of the water the wash and the lap are exactly zero")
            _ = d.update(groundY: -0.2, speed: Player.walkSpeed)
            check(d.drag(speed: Player.walkSpeed) > 0.3 && d.drag(speed: 0) == 0 && d.lap(speed: 0) > 0.3 && d.lap(speed: Player.walkSpeed) == 0, "in the water: a wash while moving, a lap when standing, each silent in the other's case (wash \(d.drag(speed: Player.walkSpeed)), lap \(d.lap(speed: 0)))")
            var deep = WaterContact(); _ = deep.update(groundY: -0.38, speed: Player.walkSpeed); var shallow = WaterContact(); _ = shallow.update(groundY: -0.03, speed: Player.walkSpeed)
            check(deep.drag(speed: Player.walkSpeed) > shallow.drag(speed: Player.walkSpeed) * 1.3, "the wash grows with depth (\(shallow.drag(speed: Player.walkSpeed)) at the line, \(deep.drag(speed: Player.walkSpeed)) at 38 cm)")
        }
        // The rendered sounds.
        let sr: Float = 44100
        func render(seconds: Float, setup: (AmbienceSynth) -> Void) -> [Float] {
            let s = AmbienceSynth(sampleRate: sr)
            s.windGain = 0; s.surfGain = 0; s.padGain = 0; s.master = 1
            setup(s)
            var out: [Float] = []
            var l = [Float](repeating: 0, count: 1024), r = l
            for _ in 0..<Int(seconds * sr) / 1024 {
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: 1024, left: lp.baseAddress!, right: rp.baseAddress!) } }
                for k in 0..<1024 { out.append(0.5 * (l[k] + r[k])) }
            }
            return out
        }
        let silent = render(seconds: 2) { _ in }
        // M10 follow-up: the wading levels belong to the pace, not to the old 3.2 / 6.5 m/s literals. At the walking pace they are exactly what they were before M10.2 (3.2 m/s).
        do {
            let oldDrag: (Float, Float) -> Float = { depth, speed in min(1, (0.3 + depth / 0.35) * min(speed / 3.2, 1.2)) }
            var w = WaterContact(); _ = w.update(groundY: -0.03, speed: Player.walkSpeed)       // shallow, so the wash is below its ceiling of 1 and the comparison can fail
            let want = oldDrag(w.depth, 3.2)
            check(abs(WaterContact.entryStrength(speed: Player.walkSpeed) - 3.2 / 6.5) < 1e-6 && abs(WaterContact.entryStrength(speed: Player.runSpeed) - 1) < 1e-6 && abs(w.drag(speed: Player.walkSpeed) - want) < 1e-6 && WaterContact.entryStrength(speed: 0.2) == 0.1,
                  "wading at the walking pace is as loud as before M10 (entry \(WaterContact.entryStrength(speed: Player.walkSpeed)) = 3.2/6.5, run entry \(WaterContact.entryStrength(speed: Player.runSpeed)), wash \(w.drag(speed: Player.walkSpeed)) = \(want))")
        }
        if name == "water" { let wi = Self.rms(render(seconds: 1.2) { $0.waterEvent(.enter(WaterContact.entryStrength(speed: Player.walkSpeed))) }), ri = Self.rms(render(seconds: 1.2) { $0.waterEvent(.enter(WaterContact.entryStrength(speed: Player.runSpeed))) }), dr = Self.rms(render(seconds: 1.2) { $0.waterEvent(.leave) }), wa = Self.rms(Array(render(seconds: 4) { $0.waterDrag = 0.8 }.dropFirst(Int(sr)))), la = Self.rms(Array(render(seconds: 8) { $0.waterLap = 0.8 }.dropFirst(Int(2 * sr)))); print(String(format: "water rms: walk-in %.4f run-in %.4f drips %.4f wash %.4f lap %.5f", wi, ri, dr, wa, la)) }
        check(Self.rms(silent) < 1e-7, "no water sound at all out of the water (rms \(Self.rms(silent)))")
        let walkIn = Self.rms(render(seconds: 1.2) { $0.waterEvent(.enter(WaterContact.entryStrength(speed: Player.walkSpeed))) })
        let runIn = Self.rms(render(seconds: 1.2) { $0.waterEvent(.enter(WaterContact.entryStrength(speed: Player.runSpeed))) })
        check(walkIn > 1e-4 && runIn > 1.8 * walkIn, "entering the water splashes, harder when faster (walk rms \(String(format: "%.4f", walkIn)), run \(String(format: "%.4f", runIn)))")
        let drips = render(seconds: 1.2) { $0.waterEvent(.leave) }
        let dripSpec = FootstepAnalysis.spectrum(Array(drips[0..<Int(sr)]))
        check(Self.rms(drips) > 5e-5 && Self.rms(drips) < 0.8 * walkIn, "leaving the water drips: quieter than a splash (drips rms \(String(format: "%.4f", Self.rms(drips))) against \(String(format: "%.4f", walkIn)))")
        let wash = render(seconds: 4) { $0.waterDrag = 0.8 }
        let lap = render(seconds: 8) { $0.waterLap = 0.8 }
        let washSpec = FootstepAnalysis.spectrum(Array(wash[Int(sr)..<Int(3 * sr)]))
        check(Self.rms(Array(wash[Int(sr)...])) > 1e-3 && Self.rms(Array(wash[Int(sr)...])) < 0.012, "wading is a quiet continuous wash of bubbles (rms \(String(format: "%.4f", Self.rms(Array(wash[Int(sr)...])))), centroid \(Int(FootstepAnalysis.centroid(washSpec))) Hz; the absolute bubble targets are in --selftest foley)")
        check(Self.rms(Array(lap[Int(2 * sr)...])) > 5e-5 && Self.rms(Array(lap[Int(2 * sr)...])) < 0.4 * Self.rms(Array(wash[Int(sr)...])), "standing in the water is a quiet lap, much softer than wading (rms \(String(format: "%.5f", Self.rms(Array(lap[Int(2 * sr)...]))))")
        // A bot that really walks into the sea and back out, through the engine's own plumbing.
        do {
            let scene = Scene.makeWorld(device: device)
            let g = Game(scene: scene)
            let bot = PlaythroughBot(g)
            let ground: (Float, Float) -> Float = { scene.groundHeight(x: $0, z: $1) }
            let start = SIMD3<Float>(Layout.dockShore.x - 12, 0, Layout.dockShore.z - 6)
            let shore = AudioSpace.nearestShore(at: SIMD3(start.x, ground(start.x, start.z), start.z), ground: ground)
            if let shore {
                let dir = shore.direction
                g.player.position = SIMD3(start.x, ground(start.x, start.z), start.z)
                bot.wait(0.3)
                let synth = AmbienceSynth(sampleRate: 22050)
                var water = WaterContact()
                var enters = 0, leaves = 0, sawDrag: Float = 0
                var events: [WaterContact.Event] = []
                func tick(toward d: SIMD2<Float>) {
                    g.player.yaw = atan2(d.x, -d.y)
                    var input = InputState(); input.move = SIMD2(0, 1)
                    bot.tick(input)
                    let p = g.player.position
                    if let e = water.update(groundY: g.scene.groundHeight(x: p.x, z: p.z), speed: g.player.speed) { events.append(e); if case .enter = e { enters += 1 } else { leaves += 1 } }
                    sawDrag = max(sawDrag, water.drag(speed: g.player.speed))
                    AudioEngine.feedWater(&water, into: synth, game: g)         // the real function too, on a copy of the state, must not crash or double-fire
                }
                for _ in 0..<(60 * 14) { tick(toward: dir) }                                                      // wade in until the depth limit stops you
                let wadedIn = water.wet
                for _ in 0..<(60 * 14) { tick(toward: -dir) }                                                     // and back out onto the beach
                check(wadedIn && enters >= 1 && leaves >= 1 && !water.wet, "a bot walks into the sea and out again: it enters the water (\(enters) entries, \(leaves) exits) and ends dry; \(events.prefix(4))")
                check(sawDrag > 0.2, "wading drags at the legs (peak wash \(String(format: "%.2f", sawDrag)))")
            } else { check(false, "found no shore near the beach for the wading bot") }
        }
    }
}
