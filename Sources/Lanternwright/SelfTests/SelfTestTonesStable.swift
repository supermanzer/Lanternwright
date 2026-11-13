import Foundation
import Metal
import simd

/// F09.4 (#92: "the tones go out of tune after the initial ring as we approach the lighthouse"): the lit lighthouse's tone and the stone drone are pitch-stable at any play time.
/// The fault was a phase of the form `f * (1 + a sin wt) * t` with t the synth's absolute clock: its instantaneous frequency is off by f * t * a w cos wt, so the swing grew with the play
/// time (the user's note was at 933 s). A render that starts at t = 0 cannot see that, so these start the clock at 1000 s and later, and the mutation check runs the old formula.
extension SelfTestRunner {
    /// Frequency stability of a tone in `x` at nominal `f`: the worst departure in cents between consecutive 0.5 s Hann windows (lock-in), and the weakest window's amplitude over the strongest's.
    static func toneDrift(_ x: [Float], sr: Float, f: Float) -> (maxCents: Float, ampRatio: Float) {
        let n = Int(0.5 * sr)
        var hann = [Double](repeating: 0, count: n); var wsum = 0.0
        for i in 0..<n { hann[i] = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n)); wsum += hann[i] }
        var phases: [Double] = [], amps: [Double] = []
        var k = 0
        while (k + 1) * n <= x.count {
            var re = 0.0, im = 0.0
            for i in 0..<n {
                let abs = k * n + i, a = 2 * Double.pi * Double(f) * Double(abs) / Double(sr)
                re += Double(x[abs]) * hann[i] * cos(a); im -= Double(x[abs]) * hann[i] * sin(a)
            }
            phases.append(atan2(im, re)); amps.append((re * re + im * im).squareRoot() * 2 / wsum)
            k += 1
        }
        var worst: Float = 0
        for j in 1..<phases.count {
            var d = phases[j] - phases[j - 1]
            while d > Double.pi { d -= 2 * Double.pi }; while d < -Double.pi { d += 2 * Double.pi }
            let df = d / (2 * Double.pi * 0.5)
            worst = max(worst, Float(abs(1200 * log2(1 + df / Double(f)))))
        }
        return (worst, Float((amps.min() ?? 0) / max(amps.max() ?? 1, 1e-12)))
    }

    func runTonesStable() {
        guard name == "all" || name == "tones" else { return }
        let sr: Float = 44100
        let lhPos = Layout.lighthouse + SIMD3<Float>(0, 26, 0)
        func renderLighthouse(start: Double, distances: [Float], secondsEach: Float) -> [Float] {
            let s = AmbienceSynth(sampleRate: sr)
            s.windGain = 0; s.surfGain = 0; s.padGain = 0; s.master = 1
            s.setClock(seconds: start)
            var out: [Float] = []
            var l = [Float](repeating: 0, count: 1024), r = [Float](repeating: 0, count: 1024)
            for d in distances {
                // The levels the engine computes for a listener d metres from the lighthouse (the listener WALKS: the level, the pan and the phase of the world all move).
                let lv = SonicLandmarks.levels(listener: lhPos + SIMD3(d, -26, 0), yaw: 0, world: .varrow, lighthouseLit: true)
                s.humGain = SIMD4(0, 0, 0, lv.hum.w); s.humPan = SIMD4(0, 0, 0, lv.humPan.w)
                for _ in 0..<Int(secondsEach * sr) / 1024 {
                    l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: 1024, left: lp.baseAddress!, right: rp.baseAddress!) } }
                    for k in 0..<1024 { out.append(0.5 * (l[k] + r[k])) }
                }
            }
            return out
        }
        let d3 = ToneTable.stoneHz[0] * 0.5, a3 = ToneTable.stoneHz[1] * 0.5
        let dists: [Float] = [300, 150, 60, 25, 8]
        for start in [0.0, 600.0, 1000.0, 5000.0] {
            let x = renderLighthouse(start: start, distances: dists, secondsEach: 3)
            let a = Self.toneDrift(x, sr: sr, f: d3), b = Self.toneDrift(x, sr: sr, f: a3)
            // Level changes between the distances change the amplitude but not the pitch; the window straddling a step is skipped by looking at the pitch only.
            check(a.maxCents < 3 && b.maxCents < 3, "tones: the lit lighthouse's D3 and A3 stay within 3 cents at five distances (300 to 8 m) with the synth clock at \(Int(start)) s (worst \(String(format: "%.2f", a.maxCents)) and \(String(format: "%.2f", b.maxCents)) cents)")
        }
        // Mutation: the formula as it was (vibrato multiplying the absolute clock) must be caught by the same measurement.
        do {
            let t0 = 1000.0
            var x: [Float] = []
            for i in 0..<Int(15 * sr) {
                let td = t0 + Double(i) / Double(sr), t = Float(td)
                let vib = 1 + 0.002 * sin(t * 0.7)
                x.append(Float(sin(2 * Double.pi * Double(d3 * vib) * td) + 0.7 * sin(2 * Double.pi * Double(a3 * vib) * td + 0.5)) * 0.03)
            }
            let a = Self.toneDrift(x, sr: sr, f: d3)
            check(a.maxCents > 3 || a.ampRatio < 0.5, "tones: mutation: the old formula at 1000 s is caught by the measurement (drift \(String(format: "%.0f", a.maxCents)) cents, amplitude ratio \(String(format: "%.2f", a.ampRatio)))")
        }
        // The stone drone's sour slide (a wrong strike): it slides at most 1.8 % (31 cents) flat and then is exactly in tune again; late in the game too.
        for start in [0.0, 1000.0] {
            let s = AmbienceSynth(sampleRate: sr)
            s.windGain = 0; s.surfGain = 0; s.padGain = 0; s.master = 1
            s.setClock(seconds: start)
            s.setDrone(0, on: true)
            var l = [Float](repeating: 0, count: 1024), r = [Float](repeating: 0, count: 1024)
            func block() -> [Float] { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: 1024, left: lp.baseAddress!, right: rp.baseAddress!) } }; return (0..<1024).map { 0.5 * (l[$0] + r[$0]) } }
            for _ in 0..<(Int(4 * sr) / 1024) { _ = block() }                                   // let it come up
            s.sourDrone(); s.setDrone(0, on: true)                                              // the wrong strike, with the voice kept sounding to measure it
            var slide: [Float] = [], after: [Float] = []
            for _ in 0..<(Int(2.5 * sr) / 1024) { slide += block() }
            for _ in 0..<(Int(6 * sr) / 1024) { after += block() }
            let during = Self.toneDrift(slide, sr: sr, f: ToneTable.droneHz[0] * 0.982), settled = Self.toneDrift(after, sr: sr, f: ToneTable.droneHz[0])
            check(settled.maxCents < 3, "tones: the drone is back within 3 cents once the sour slide has ended, with the clock at \(Int(start)) s (\(String(format: "%.2f", settled.maxCents)) cents, \(String(format: "%.0f", during.maxCents)) cents of drift while it slid)")
            // A slide of 31 cents keeps the energy in the tone's own neighbourhood (0.96 to 1.01 of the nominal); a chirp of thousands of hertz smears it over the whole spectrum.
            let f0 = ToneTable.droneHz[0]
            var near: Float = 0, rms2: Float = 0
            for v in slide { rms2 += v * v }
            let step = 0.001 * f0
            for k in 0...50 { near += FootstepAnalysis.power(slide, f0 * 0.96 + step * Float(k)) }
            // Parseval: the energy in a band is 2/N of the sum of |X|^2 over the band's bins (the bins here are `step` hertz apart, the transform's own are sr / N apart).
            let share = 2 * near * step * Float(slide.count) / sr / max(rms2, 1e-12)
            if name == "tones" { print("tones: slide energy near the tone: \(String(format: "%.3f", share)) (clock \(Int(start)) s)") }
            check(share > 0.5, "tones: during the slide the drone stays a tone (\(String(format: "%.2f", share)) of its energy within 0.96-1.01 of its pitch, not smeared by a chirp), with the clock at \(Int(start)) s")
        }
    }
}
