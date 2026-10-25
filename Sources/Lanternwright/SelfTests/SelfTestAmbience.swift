import Foundation
import Metal
import simd

/// Self-tests: the ambient bed at real places (F01 W6.2 and W6.3). The user heard the surf as loud inland as at the shore, and "static white noise" at the
/// summit. These render the wind and the surf offline, with the same parameters the engine derives from the listener's position, at the beach, the
/// mid-slope, the summit and the lighthouse plinth, and measure level, brightness (centroid), flatness (white noise is 1, a band-shaped sound is low)
/// and the depth of the slow swell (0.05-0.3 Hz). The per-position table is printed when the tests run with `--selftest ambience`.
extension SelfTestRunner {
    struct AmbienceMeasure { var rms: Float; var centroid: Float; var flatness: Float; var swellDepth: Float; var highShare: Float }

    static func measureAmbience(_ x: [Float], sampleRate sr: Float) -> AmbienceMeasure {
        let rms = (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot()
        // Band powers by Goertzel at 1/3-octave centres, 100 Hz to 8 kHz, averaged over one-second windows.
        var freqs: [Float] = []; var f: Float = 100
        while f <= 8000 { freqs.append(f); f *= pow(2, 1.0 / 3) }
        var power = [Float](repeating: 0, count: freqs.count)
        let n = Int(sr)
        var windows = 0
        var start = 0
        while start + n <= x.count {
            for (k, fc) in freqs.enumerated() {
                let w = 2 * Float.pi * fc / sr, coeff = 2 * cos(w)
                var s1: Float = 0, s2: Float = 0
                for i in 0..<n { let s0 = x[start + i] + coeff * s1 - s2; s2 = s1; s1 = s0 }
                power[k] += (s1 * s1 + s2 * s2 - coeff * s1 * s2) / Float(n * n)
            }
            windows += 1; start += n
        }
        power = power.map { $0 / Float(max(windows, 1)) + 1e-14 }
        let mean = power.reduce(0, +) / Float(power.count)
        let geo = exp(power.map { log($0) }.reduce(0, +) / Float(power.count))
        let centroid = zip(freqs, power).map { $0 * $1 }.reduce(0, +) / power.reduce(0, +)
        let highShare = zip(freqs, power).filter { $0.0 >= 800 }.map(\.1).reduce(0, +) / power.reduce(0, +)        // the share of the energy above 800 Hz
        // Envelope: rectify, low-pass at ~2 Hz, decimate to 50 Hz; the depth of the swell is the strongest component at 0.07-0.14 Hz over the mean.
        var env: [Float] = [], lp: Float = 0
        let a = 1 - exp(-2 * Float.pi * 2 / sr)
        for (i, v) in x.enumerated() { lp += a * (abs(v) - lp); if i % Int(sr / 50) == 0 { env.append(lp) } }
        let m = env.reduce(0, +) / Float(max(env.count, 1))
        var best: Float = 0
        for fc: Float in [0.07, 0.085, 0.1, 0.12, 0.14] {
            var re: Float = 0, im: Float = 0
            for (i, e) in env.enumerated() { let ph = 2 * Float.pi * fc * Float(i) / 50; re += (e - m) * cos(ph); im += (e - m) * sin(ph) }
            best = max(best, 2 * (re * re + im * im).squareRoot() / Float(env.count))
        }
        return AmbienceMeasure(rms: rms, centroid: centroid, flatness: geo / mean, swellDepth: best / max(m, 1e-9), highShare: highShare)
    }

    func runAmbience() {
        guard name == "all" || name == "ambience" else { return }
        let scene = Scene.makeWorld(device: device)
        let sr: Float = 22050
        let ground: (Float, Float) -> Float = { scene.groundHeight(x: $0, z: $1) }
        let places: [(String, SIMD3<Float>)] = [
            ("beach", SIMD3(Layout.dockShore.x - 6, 0, Layout.dockShore.z - 3)),
            ("mid-slope", Layout.windStone),
            ("summit", Layout.summitStone),
            ("plinth", SIMD3(Layout.lighthouse.x, 0, Layout.lighthouse.z + 5.4)),
        ].map { ($0.0, SIMD3($0.1.x, ground($0.1.x, $0.1.z), $0.1.z)) }
        func render(_ amb: AudioSpace.Ambient, surf: Bool, wind: Bool, seconds: Float = 60) -> [Float] {
            let s = AmbienceSynth(sampleRate: sr)
            s.windGain = wind ? amb.windGain : 0; s.windAltitude = amb.windAltitude
            s.surfGain = surf ? amb.surfGain : 0; s.surfFar = amb.surfFar; s.surfAirCutoff = amb.surfAirCutoff
            s.master = 1
            var out: [Float] = []
            let block = 2048
            var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
            for _ in 0..<Int(seconds * sr) / block { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: block, left: lp.baseAddress!, right: rp.baseAddress!) } }; out += l }
            return out
        }
        var table: [(String, AudioSpace.Ambient, AmbienceMeasure, AmbienceMeasure, AmbienceMeasure)] = []
        for (nm, p) in places {
            let amb = AudioSpace.ambient(at: p, ground: ground)
            table.append((nm, amb, Self.measureAmbience(render(amb, surf: true, wind: false), sampleRate: sr), Self.measureAmbience(render(amb, surf: false, wind: true), sampleRate: sr),
                          Self.measureAmbience(render(amb, surf: true, wind: true), sampleRate: sr)))
        }
        if name == "ambience" {
            print("place       coast  | surf: rms   centroid depth  >800Hz | wind: rms   centroid flatness | both: rms centroid flatness")
            for (nm, amb, s, w, b) in table {
                print(String(format: "%-10@ %5.0f m | %.4f %7.0f Hz %.2f  %.3f | %.4f %7.0f Hz %.2f | %.4f %6.0f Hz %.2f", nm as NSString, amb.shoreDistance, s.rms, s.centroid, s.swellDepth, s.highShare, w.rms, w.centroid, w.flatness, b.rms, b.centroid, b.flatness))
            }
        }
        let beach = table[0], mid = table[1], summit = table[2], plinth = table[3]
        check(beach.2.rms > 3 * mid.2.rms && mid.2.rms > 1.2 * summit.2.rms && beach.2.rms > 8 * summit.2.rms, "surf falls with distance from the coast: beach \(beach.2.rms), mid-slope \(mid.2.rms), summit \(summit.2.rms) (rms; beach/summit \(beach.2.rms / max(summit.2.rms, 1e-9)))")
        check(beach.2.highShare > 1.8 * summit.2.highShare && beach.2.highShare >= mid.2.highShare && summit.2.centroid < 450, "distant surf is darker, a low rumble (share above 800 Hz: beach \(beach.2.highShare), mid \(mid.2.highShare), summit \(summit.2.highShare); summit centroid \(Int(summit.2.centroid)) Hz)")
        check([beach, mid, summit, plinth].allSatisfy { $0.2.swellDepth > 0.15 }, "the surf keeps a clear slow swell everywhere (depth beach \(beach.2.swellDepth), mid \(mid.2.swellDepth), summit \(summit.2.swellDepth), plinth \(plinth.2.swellDepth))")
        check(summit.2.swellDepth >= beach.2.swellDepth * 0.95, "far away the swell is at least as deep as on the beach: a slow breathing (summit \(summit.2.swellDepth) vs beach \(beach.2.swellDepth))")
        check(summit.3.flatness < 0.30 && plinth.3.flatness < 0.30, "wind at the summit and on the plinth is band-shaped, not broadband static (flatness \(summit.3.flatness) / \(plinth.3.flatness); white noise is 1)")
        check(summit.3.centroid < 900 && plinth.3.centroid < 900, "and low: a moan and a whistle, not a hiss (centroid \(Int(summit.3.centroid)) / \(Int(plinth.3.centroid)) Hz)")
        check(summit.4.flatness < 0.35 && plinth.4.flatness < 0.35, "surf and wind together at the summit are not static (flatness \(summit.4.flatness) / \(plinth.4.flatness))")
        check(table.allSatisfy { !$0.2.rms.isNaN && !$0.3.rms.isNaN && $0.4.rms < 1.2 }, "all ambient renders are finite and not loud")
    }

    /// F01 W6.1: planks that rest on the ground thud; planks over water boom. The weight comes from the clearance under the deck.
    func runHollowness() {
        guard name == "all" || name == "hollow" else { return }
        typealias A = FootstepAnalysis
        func measure(_ hollow: Float) -> (low: Float, decay: Float) {
            let feet = Footsteps(sampleRate: A.sr)
            let n = Int(A.sr * 0.8)
            var lows: [Float] = [], decays: [Float] = []
            for _ in 0..<10 {
                feet.start(mix: A.pure(.wood), run: false, pan: 0, plank: 7, pebble: 0, hollow: hollow)
                var x = [Float](repeating: 0, count: n)
                for i in 0..<n { let s = feet.render(dt: 1 / A.sr); x[i] = s.0 + s.1 }
                lows.append(A.band(A.spectrum(x), 80, 400)); decays.append(A.decayTime(x, lowpass: 400, dB: 30))
            }
            return (A.mean(lows), A.mean(decays))
        }
        let ms = [0, 0.25, 0.5, 0.75, 1].map { measure(Float($0)) }
        let mono = zip(ms, ms.dropFirst()).allSatisfy { $1.low >= $0.low * 0.85 && $1.decay >= $0.decay * 0.98 }
        check(mono && ms[4].low > 1.1 * ms[0].low && ms[4].decay > 2 * ms[0].decay, "dock planks: low-band energy and ring time still rise with clearance, now within a solid-plank range (energy \(ms.map { String(format: "%.2g", $0.low) }), -30 dB time \(ms.map { String(format: "%.2f", $0.decay) }) s)")
        check(ms[4].decay < 0.4, "dock planks at hollowness 1: -30 dB decay under 0.4 s (\(String(format: "%.2f", ms[4].decay)) s)")
        let sc = Scene.makeWorld(device: device)
        let s = Layout.dockStrip(), dir = simd_normalize(s.b - s.a), len = simd_length(s.b - s.a)
        let along = [1.0, 3.0, 6.0, 10.0, 14.0, 18.0].map { Float($0) }.filter { $0 < len }
        let h = along.map { u -> Float in let q = s.a + dir * u; return sc.hollowness(x: q.x, z: q.y) }
        check(h.first! < 0.35 && h.last! > 0.85 && zip(h, h.dropFirst()).allSatisfy { $1 >= $0 - 0.02 }, "along the dock the hollowness rises from the shore to the water: \(h.map { String(format: "%.2f", $0) }) (planks over the beach thud, planks over the sea boom)")
        check(sc.hollowness(x: Layout.lighthouse.x, z: Layout.lighthouse.z) == 0, "off the dock there is no hollowness")
    }

    /// R07-5: wading makes a wet, low splash from the step engine's grain layer: more energy than the dry foot, darker than sand, a body in the low band, no clipping.
    func runSplash() {
        guard name == "all" || name == "splash" else { return }
        typealias A = FootstepAnalysis
        func steps(_ splash: Float, run: Bool = false) -> [[Float]] {
            let feet = Footsteps(sampleRate: A.sr)
            let n = Int(A.sr * 0.8)
            return (0..<10).map { _ in
                feet.start(mix: A.pure(.wetSand), run: run, pan: 0, splash: splash)
                var x = [Float](repeating: 0, count: n)
                for i in 0..<n { let s = feet.render(dt: 1 / A.sr); x[i] = s.0 + s.1 }
                return x
            }
        }
        let dry = steps(0), wade = steps(1), run = steps(1, run: true)
        let eDry = A.mean(dry.map { $0.reduce(0) { $0 + $1 * $1 } }), eWade = A.mean(wade.map { $0.reduce(0) { $0 + $1 * $1 } })
        check(eWade > 3 * eDry, "wading adds a splash: much more energy than the same step on wet sand (\(eWade) vs \(eDry))")
        let low = A.mean(wade.map { A.band(A.spectrum($0), 80, 400) / max(A.band(A.spectrum($0), 80, 9000), 1e-12) })
        let cWade = A.mean(wade.map { A.centroid(A.spectrum($0)) })
        check(low > 0.35 && cWade < 1500, "the splash is wet and low (\(Int(low * 100)) % of its energy below 400 Hz, centroid \(Int(cWade)) Hz)")
        check(A.mean(wade.map { A.decayTime($0, lowpass: 400, dB: 30) }) > 0.12, "it sloshes for a moment, not a click")
        check((wade + run).allSatisfy { ($0.map { abs($0) }.max() ?? 0) < 0.9 } && !wade.joined().contains { !$0.isFinite }, "no clipping, all finite")
    }
}
