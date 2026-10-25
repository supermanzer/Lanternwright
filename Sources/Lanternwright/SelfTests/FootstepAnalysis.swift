import Foundation

/// Offline measurements of rendered footsteps (R05): since a person cannot be in the test loop, the character of each surface is
/// checked as numbers: where the energy sits, how long it rings, how many grains it holds, how fast it attacks.
enum FootstepAnalysis {
    static let sr: Float = 44100

    /// `count` consecutive steps of one mix from a fresh voice (fixed seed: deterministic), each rendered for `seconds`, left channel.
    static func render(mix: StepMix, count: Int = 10, run: Bool = false, plank: Int = 0, pebble: Float = 0, seconds: Float = 0.7, layers: Footsteps.Layers = .all, hollow: Float = 1, toe: Bool = true) -> [[Float]] {
        let feet = Footsteps(sampleRate: sr)
        feet.layers = layers; feet.toeEnabled = toe
        let n = Int(sr * seconds)
        var out: [[Float]] = []
        for k in 0..<count {
            feet.start(mix: mix, run: run, pan: 0, plank: plank, pebble: pebble, hollow: hollow)
            var x = [Float](repeating: 0, count: n)
            for i in 0..<n { let s = feet.render(dt: 1 / sr); x[i] = s.0 + s.1 }
            out.append(x); _ = k
        }
        return out
    }
    static func pure(_ m: StepMaterial) -> StepMix { FootstepRecipe.pure(m) }

    /// Power at one frequency (Goertzel).
    static func power(_ x: [Float], _ f: Float) -> Float {
        let w = 2 * Float.pi * f / sr, c = 2 * cos(w)
        var s1: Float = 0, s2: Float = 0
        for v in x { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
        return (s1 * s1 + s2 * s2 - c * s1 * s2) / Float(max(x.count, 1))
    }
    /// Power on a 40 Hz grid up to 9 kHz (index i is (i + 1) x 40 Hz), so every band is summed on the same grid and fractions are honest.
    static func spectrum(_ x: [Float]) -> [Float] { (1...225).map { power(x, Float($0) * 40) } }
    static func band(_ spec: [Float], _ lo: Float, _ hi: Float) -> Float {
        var e: Float = 0
        for (i, p) in spec.enumerated() { let f = Float(i + 1) * 40; if f >= lo && f <= hi { e += p } }
        return e
    }
    static func centroid(_ spec: [Float]) -> Float {
        var num: Float = 0, den: Float = 0
        for (i, p) in spec.enumerated() { let f = Float(i + 1) * 40; if f >= 100 { num += p * f; den += p } }
        return den > 0 ? num / den : 0
    }
    /// Smoothed amplitude envelope with a one-pole of time constant `tau`.
    static func envelope(_ x: [Float], tau: Float) -> [Float] {
        let a = 1 - exp(-1 / (sr * tau)); var e: Float = 0
        return x.map { e += a * (abs($0) - e); return e }
    }
    static func onePoleLow(_ x: [Float], _ hz: Float) -> [Float] { let a = 1 - exp(-2 * .pi * hz / sr); var y: Float = 0; return x.map { y += a * ($0 - y); return y } }
    static func onePoleHigh(_ x: [Float], _ hz: Float) -> [Float] { let l = onePoleLow(x, hz); return zip(x, l).map { $0 - $1 } }
    /// Seconds from the peak of the (low-passed) envelope until it falls `dB` below it.
    static func decayTime(_ x: [Float], lowpass: Float, dB: Float) -> Float {
        let e = envelope(onePoleLow(x, lowpass), tau: 0.004)
        guard let top = e.max(), let iTop = e.firstIndex(of: top) else { return 0 }
        let thresh = top * pow(10, -dB / 20)
        let end = (iTop..<e.count).first { e[$0] < thresh } ?? e.count
        return Float(end - iTop) / sr
    }
    /// Rise time: seconds until the 0.7 ms smoothed envelope first reaches half of its maximum (robust against a later, louder grain).
    static func attackTime(_ x: [Float]) -> Float {
        let e = envelope(x, tau: 0.0007)
        guard let top = e.max(), top > 0 else { return 0 }
        let i = e.firstIndex { $0 >= 0.5 * top } ?? 0
        return Float(i) / sr
    }
    /// Distinct bursts in a 1.5-5 kHz band: peaks of the smoothed envelope above 12 % of the maximum, at least 3 ms apart.
    static func grainCount(_ x: [Float]) -> Int {
        let b = onePoleLow(onePoleHigh(onePoleHigh(x, 1500), 1500), 5000)
        let e = envelope(b, tau: 0.0010)
        guard let top = e.max(), top > 1e-6 else { return 0 }
        var count = 0, last = -1000
        let minGap = Int(sr * 0.003)
        for i in 1..<(e.count - 1) where e[i] > 0.12 * top && e[i] >= e[i - 1] && e[i] > e[i + 1] && i - last >= minGap { count += 1; last = i }
        return count
    }
    static func dominantPitch(_ x: [Float], _ lo: Float, _ hi: Float) -> Float {
        var best: Float = 0, bestP: Float = -1
        var f = lo; while f <= hi { let p = power(x, f); if p > bestP { bestP = p; best = f }; f += 2 }
        return best
    }
    /// How tonal a set of steps is: the average power spectrum (40 Hz grid), and for each bin between 300 Hz and 6 kHz its three-bin power over the mean of its
    /// neighbours (6 bins either side, not the nearest 1). Noise gives about 1 (a little more from the averaging's ripple); a ringing partial gives 10 or more.
    static func tonalProminence(_ steps: [[Float]]) -> Float {
        let specs = steps.map(spectrum)
        let avg = (0..<225).map { i in mean(specs.map { $0[i] }) }
        var worst: Float = 0
        for i in 7..<(avg.count - 7) {
            let f = Float(i + 1) * 40
            guard f >= 300 && f <= 6000 else { continue }
            let here = (avg[i - 1] + avg[i] + avg[i + 1]) / 3
            let around = ((i - 7)...(i + 7)).filter { abs($0 - i) > 1 }.map { avg[$0] }
            worst = max(worst, here / max(mean(around), 1e-20))
        }
        return worst
    }
    /// Centre frequency (Hz) of the strongest one-third-octave band of a spectrum (bands from 100 Hz to 8 kHz).
    static func strongestThirdOctave(_ spec: [Float]) -> Float {
        var best: Float = 0, bestE: Float = -1
        var fc: Float = 100
        while fc <= 8000 {
            let e = band(spec, fc / pow(2, 1.0 / 6), fc * pow(2, 1.0 / 6))
            if e > bestE { bestE = e; best = fc }
            fc *= pow(2, 1.0 / 3)
        }
        return best
    }
    static func mean(_ v: [Float]) -> Float { v.isEmpty ? 0 : v.reduce(0, +) / Float(v.count) }
}
