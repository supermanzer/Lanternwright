import Foundation
import Metal
import simd

/// Self-tests: the sea (F02 A1, user notes #18 and #27). Absolute targets, asserted on the output of the synth itself rendered with the parameters the engine derives
/// from the listener's surroundings (`AudioSpace.ambient`): level in dB against the level standing at the waterline, depth of the wave rhythm, and that the rhythm
/// does not repeat. `--selftest surf` prints the table.
extension SelfTestRunner {
    /// Render `seconds` of the surf alone (no wind) for an ambient reading; mono mix of both channels.
    static func renderSurf(_ amb: AudioSpace.Ambient, seconds: Float, sampleRate sr: Float = 22050) -> [Float] {
        let s = AmbienceSynth(sampleRate: sr)
        s.windGain = 0; s.surfGain = amb.surfGain; s.surfFar = amb.surfFar; s.surfAirCutoff = amb.surfAirCutoff
        s.master = 1
        var out: [Float] = []
        let block = 2048
        var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
        for _ in 0..<Int(seconds * sr) / block {
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: block, left: lp.baseAddress!, right: rp.baseAddress!) } }
            for k in 0..<block { out.append(0.5 * (l[k] + r[k])) }
        }
        return out
    }
    static func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }
    /// RMS of each one-second window.
    static func envelope1s(_ x: [Float], sampleRate sr: Float) -> [Float] {
        let n = Int(sr)
        return stride(from: 0, to: x.count - n + 1, by: n).map { rms(Array(x[$0..<$0 + n])) }
    }

    func runSurf() {
        guard name == "all" || name == "surf" else { return }
        // The law: one curve, three absolute targets.
        let dB = { (d: Float) in AudioSpace.surfLevelDB(distance: d) }
        check(abs(dB(40) + 14) < 0.5 && abs(dB(100) + 26) < 0.5 && abs(dB(200) + 38) < 0.5 && dB(0) == 0, "the surf level law: 40 m \(String(format: "%.1f", dB(40))) dB, 100 m \(String(format: "%.1f", dB(100))) dB, 200 m \(String(format: "%.1f", dB(200))) dB (targets -14, -26, -38)")
        // A straight coast: land for x < 0 (height 5), sea for x >= 0. The listener stands d metres inland.
        let coast: (Float, Float) -> Float = { x, _ in x < 0 ? 5 : -5 }
        let sr: Float = 22050
        func measure(_ d: Float, seconds: Float = 60) -> (amb: AudioSpace.Ambient, x: [Float]) {
            let amb = AudioSpace.ambient(at: SIMD3(-d, 5, 0), ground: coast)
            return (amb, Self.renderSurf(amb, seconds: seconds, sampleRate: sr))
        }
        let ref = measure(2)
        let refRMS = Self.rms(ref.x)
        var table: [(Float, Float)] = []
        for d: Float in [5, 40, 100, 200, 300] {
            let m = measure(d)
            table.append((d, 20 * log10(max(Self.rms(m.x), 1e-9) / refRMS)))
        }
        if name == "surf" {
            print("distance to water | rendered level vs the waterline (dB) | the law (dB)")
            for (d, v) in table { print(String(format: "%8.0f m | %8.1f | %8.1f", d, v, dB(d))) }
        }
        func level(_ d: Float) -> Float { table.first { $0.0 == d }!.1 }
        check(level(5) > -4 && level(5) < 0.5, "surf at 5 m from the water is within 4 dB of the waterline (\(String(format: "%.1f", level(5))) dB)")
        check(level(40) < -11 && level(40) > -17.5, "surf 40 m inland: about -14 dB against the waterline (\(String(format: "%.1f", level(40))) dB)")
        check(level(100) < -23 && level(100) > -30, "surf 100 m inland: about -26 dB (\(String(format: "%.1f", level(100))) dB)")
        check(level(200) <= -38, "surf 200 m inland: -38 dB or less, inaudible under the ambient bed (\(String(format: "%.1f", level(200))) dB)")
        check(level(300) <= -42, "surf 300 m inland: -42 dB or less (\(String(format: "%.1f", level(300))) dB)")
        // The user's own spot (note #18): about 130 m inland, play position (90, 94).
        let scene = Scene.makeWorld(device: device)
        let ground: (Float, Float) -> Float = { scene.groundHeight(x: $0, z: $1) }
        let spot = SIMD3<Float>(90, ground(90, 94), 94)
        let ambSpot = AudioSpace.ambient(at: spot, ground: ground)
        let spotDB = 20 * log10(max(Self.rms(Self.renderSurf(ambSpot, seconds: 40, sampleRate: sr)), 1e-9) / refRMS)
        if name == "surf" { print(String(format: "note #18 spot (90, 94): nearest water %.0f m, surf %.1f dB against the waterline", ambSpot.shoreDistance, spotDB)) }
        check(ambSpot.shoreDistance > 60 && spotDB < -22, "at the note #18 spot (nearest water \(Int(ambSpot.shoreDistance)) m) the surf is at least 22 dB below the waterline (\(String(format: "%.1f", spotDB)) dB)")
        // Rhythm at the waterline: discrete waves with a clear gap, at least 8 dB between the loudest and quietest second over a minute.
        for d: Float in [2, 5] {
            let e = Self.envelope1s(measure(d).x, sampleRate: sr)
            let depth = 20 * log10(e.max()! / max(e.min()!, 1e-9))
            check(depth >= 8, "the surf has a rhythm \(Int(d)) m from the water: loudest second \(String(format: "%.1f", depth)) dB above the quietest over 60 s (at least 8)")
        }
        // It does not loop: the autocorrelation of the one-second level at lags of 5 to 40 s stays low over three minutes.
        do {
            let e = Self.envelope1s(measure(2, seconds: 180).x, sampleRate: sr)
            let m = e.reduce(0, +) / Float(e.count), v = e.map { ($0 - m) * ($0 - m) }.reduce(0, +)
            var worst: Float = 0
            for lag in 5...40 { var c: Float = 0; for i in 0..<(e.count - lag) { c += (e[i] - m) * (e[i + lag] - m) }; worst = max(worst, c / v * Float(e.count) / Float(e.count - lag)) }
            check(worst < 0.55, "the wave pattern never repeats audibly: the strongest autocorrelation at 5-40 s lags is \(String(format: "%.2f", worst)) (under 0.55)")
        }
        // F02 A1: the clock must not freeze. A Float time stepped by 1/44100 stops advancing at 507 s; after that the wind, the waves and the drone stood still (the
        // user's saves have 600-957 s of play). Start the synth's clock at ten minutes, at the real sample rate, and require the surf to be as alive as it is at the start.
        do {
            let amb = AudioSpace.ambient(at: SIMD3(-2, 5, 0), ground: coast)
            func aliveness(startAt: Double) -> Float {
                let s = AmbienceSynth(sampleRate: 44100)
                s.setClock(seconds: startAt)
                s.windGain = 0; s.surfGain = amb.surfGain; s.surfFar = amb.surfFar; s.surfAirCutoff = amb.surfAirCutoff; s.master = 1
                var mono: [Float] = []
                var l = [Float](repeating: 0, count: 2048), r = [Float](repeating: 0, count: 2048)
                for _ in 0..<(44100 * 40 / 2048) {
                    l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: 2048, left: lp.baseAddress!, right: rp.baseAddress!) } }
                    for k in 0..<2048 { mono.append(0.5 * (l[k] + r[k])) }
                }
                let e = Self.envelope1s(mono, sampleRate: 44100)
                return 20 * log10(e.max()! / max(e.min()!, 1e-9))
            }
            let early = aliveness(startAt: 0), late = aliveness(startAt: 600)
            check(late >= 8 && late > 0.6 * early, "the surf is just as rhythmic at minute ten as at the start (depth \(String(format: "%.1f", early)) dB, then \(String(format: "%.1f", late)) dB): the synth clock does not freeze")
        }
        // The scheduler itself.
        var gaps: [Float] = [], big = 0, rises: [Float] = [], drains: [Float] = []
        for n in 1..<300 { gaps.append(SurfWaves.start(n + 1) - SurfWaves.start(n)); if SurfWaves.size(n) >= 1 { big += 1 }; rises.append(SurfWaves.rise(n)); drains.append(SurfWaves.drain(n)) }
        check(gaps.min()! >= 6 - 1e-3 && gaps.max()! <= 11 + 1e-3 && abs(gaps.reduce(0, +) / Float(gaps.count) - 8.5) < 0.5, "wave sets arrive every 6 to 11 s (\(String(format: "%.1f", gaps.min()!)) to \(String(format: "%.1f", gaps.max()!)) s, mean \(String(format: "%.1f", gaps.reduce(0, +) / Float(gaps.count))))")
        check(Float(big) / 299 > 0.25 && Float(big) / 299 < 0.45, "about every third wave is much larger (\(big) of 299)")
        check(rises.min()! >= 1.2 - 1e-3 && rises.max()! <= 2.0 + 1e-3 && drains.min()! >= 2.4 - 1e-3 && drains.max()! <= 4.0 + 1e-3, "each swash rises over 1.2-2 s and drains over 2.4-4 s")
        var sweepLo: Float = 0, sweepHi: Float = 0, quiet = 0, loud = 0
        for k in 0..<6000 { let st = SurfWaves.state(time: Float(k) * 0.01); sweepLo = min(sweepLo, st.sweep); sweepHi = max(sweepHi, st.sweep); if st.body < 0.12 { quiet += 1 }; if st.body > 0.5 { loud += 1 } }
        check(sweepLo < -0.3 && sweepHi > 0.3, "each wave travels along the shore: the stereo sweep covers \(String(format: "%.2f", sweepLo)) to \(String(format: "%.2f", sweepHi))")
        check(quiet > 600 && loud > 600, "there is a clear quiet gap between waves and real peaks (a quiet \(quiet / 60) s and a loud \(loud / 60) s in a minute)")
        check(AudioSpace.surfField(at: SIMD3(0, 5, 0), ground: { _, _ in -3 }).level == 1 && AudioSpace.surfField(at: SIMD3(0, 5, 0), ground: { _, _ in 5 }).level == 0, "in the water the sea is everywhere (level 1); with no coast anywhere there is no surf")
    }
}
