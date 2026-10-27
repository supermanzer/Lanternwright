import Foundation
import Metal
import simd

/// Self-tests: the one-shot and continuous foley sounds added in F03 (A2 the locked door, A3 the slide, A4 shallow water, and the pin on the deck footstep #36).
/// Absolute targets, measured on the rendered samples (44.1 kHz, the rate FootstepAnalysis uses). `--selftest foley` prints the measurements.
extension SelfTestRunner {
    func runFoley() {
        guard name == "all" || name == "foley" else { return }
        let A = FootstepAnalysis.self
        let sr = A.sr
        let verbose = name == "foley"
        func shares(_ x: [Float]) -> (low: Float, mid: Float, hi: Float, total: Float, spec: [Float]) {
            let sp = A.spectrum(x), tot = max(A.band(sp, 40, 9000), 1e-12)
            return (A.band(sp, 80, 200) / tot, A.band(sp, 200, 1000) / tot, A.band(sp, 1000, 3000) / tot, tot, sp)
        }
        // ---- A2 the locked door (#44)
        let knock1 = Foley.doorKnock(strength: 1, sampleRate: sr), knock3 = Foley.doorKnock(strength: 0.3, sampleRate: sr)
        let k = shares(knock1)
        let env = A.envelope(knock1, tau: 0.002)
        let peakK = env.max() ?? 0
        let iPeak = env.firstIndex(of: peakK) ?? 0
        let t40 = (iPeak..<env.count).first { env[$0] < peakK * 0.01 }.map { Float($0) / sr } ?? Float(env.count) / sr
        let fastBand = A.onePoleHigh(A.onePoleLow(knock1, 3000), 1000)
        let early = fastBand.prefix(Int(0.008 * sr)).map { abs($0) }.max() ?? 0, late = fastBand.dropFirst(Int(0.03 * sr)).map { abs($0) }.max() ?? 0
        if verbose { print(String(format: "door knock: 80-200 Hz %.2f, 200-1000 Hz %.2f, 1-3 kHz %.2f of the power; -40 dB at %.1f ms; 1-3 kHz transient early %.3f late %.3f (peak %.3f)", k.low, k.mid, k.hi, t40 * 1000, early, late, peakK)) }
        check(k.low > 0.45 && k.low > k.mid && k.low > k.hi, "the door's knock is a dull low thunk: its energy is mostly in 80-200 Hz (\(Int(k.low * 100)) % of the power; 200-1000 Hz \(Int(k.mid * 100)) %, 1-3 kHz \(Int(k.hi * 100)) %)")
        check(early > 0.12 * peakK && early > 3 * late, "with a short bright transient in 1-3 kHz at its start (\(String(format: "%.3f", early)) in the first 8 ms against \(String(format: "%.3f", late)) after 30 ms; knock peak \(String(format: "%.3f", peakK)))")
        check(t40 >= 0.040 && t40 <= 0.080, "the knock is over (-40 dB) in 40 to 80 ms (\(String(format: "%.0f", t40 * 1000)) ms)")
        let rt = (2...4).map { Foley.doorRattleWithTimes(count: $0, strength: 1, sampleRate: sr) }
        let rat = rt.map { $0.0 }
        let counts = rt.map { $0.1.count }
        // Each impact is audible: the envelope within 12 ms of its start rises to at least 20 % of the rattle's peak; and the spacing is a few ms to a few tens of ms.
        var audible = true, spacingOK = true
        for (buf, times) in rt {
            let e = A.envelope(A.onePoleHigh(buf, 500), tau: 0.002), top = e.max() ?? 1
            for (i, t) in times.enumerated() {
                let i0 = Int(t * sr), i1 = min(e.count, i0 + Int(0.012 * sr))
                if (e[i0..<i1].max() ?? 0) < 0.2 * top { audible = false }
                if i > 0 { let g = t - times[i - 1]; if g < 0.008 || g > 0.05 { spacingOK = false } }
            }
        }
        let r4 = rat[2], er = A.envelope(r4, tau: 0.004), topR = er.max() ?? 0
        let lastLoud = (0..<er.count).last { er[$0] > topR * 0.01 }.map { Float($0) / sr } ?? 0
        if verbose { print("door rattle: impacts \(counts) for counts 2, 3, 4 at \(rt[2].1.map { String(format: "%.0f", $0 * 1000) }) ms; -40 dB by \(String(format: "%.0f", lastLoud * 1000)) ms") }
        check(counts == [2, 3, 4] && audible && spacingOK, "the loose rattle is 2 to 4 quick impacts, each audible, 8 to 50 ms apart (\(counts) for requests 2, 3, 4; times \(rt[2].1.map { String(format: "%.0f", $0 * 1000) }) ms)")
        check(lastLoud < 0.30, "the whole rattle has decayed (-40 dB) within 300 ms of the knock (\(String(format: "%.0f", lastLoud * 1000)) ms)")
        let whole = Foley.doorLocked(strength: 1, sampleRate: sr)
        let wholeSp = A.spectrum(whole)
        let prom = A.tonalProminence([knock1, rat[2], whole])
        check(prom < 4.0, "the wood-on-stone part has no tonal ringing: no spectral line stands out (prominence \(String(format: "%.2f", prom)); a bell is 10+)")
        let rmsHard = Self.rms(Foley.doorLocked(strength: 1, sampleRate: sr)), rmsSoft = Self.rms(Foley.doorLocked(strength: 0.2, sampleRate: sr))
        check(rmsHard > 1.6 * rmsSoft && wholeSp.allSatisfy { $0.isFinite }, "a harder, longer attempt is louder (rms \(String(format: "%.4f", rmsHard)) against \(String(format: "%.4f", rmsSoft)) for a first light try) and everything is finite")
        _ = knock3
        // The event through the real synth: the knock and rattle play as a one-shot, the existing pull-ring jangle starts only after `Foley.jangleDelay`.
        do {
            let s = AmbienceSynth(sampleRate: sr)
            s.doorStrength = 0.8
            s.play(.doorLocked)
            var l = [Float](repeating: 0, count: 64), r = [Float](repeating: 0, count: 64)
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: 64, left: lp.baseAddress!, right: rp.baseAddress!) } }
            let delays = s.chimeDelaysForTest
            check(s.foleyCountForTest == 1 && delays.count == 4 && delays.allSatisfy { $0 >= Foley.jangleDelay - 0.01 } && Foley.jangleDelay >= 0.1 && Foley.jangleDelay <= 0.2,
                  "through the synth: one wood-on-stone one-shot plays at once and the four-tap pull-ring jangle waits \(String(format: "%.2f", Foley.jangleDelay)) s (delays \(delays.map { String(format: "%.2f", $0) }))")
        }
    }
}
