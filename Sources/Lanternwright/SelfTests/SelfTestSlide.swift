import Foundation
import Metal
import simd

/// F09.4 (#91a: "the sound on the steeper grades is very odd. Like loud static"): the slope slide is a few separate scuffs and clacks, never a continuous bed, with a rate that follows the slip speed
/// and a level well under the footsteps. Numbers only: nobody can hear it in a test (untested by ear).
extension SelfTestRunner {
    func runSlide() {
        guard name == "all" || name == "slide" || name == "foley" else { return }
        typealias A = FootstepAnalysis
        let sr: Float = 44100
        let verbose = name == "slide"
        func render(_ speed: Float, _ gravel: Float, _ seconds: Float = 6) -> [Float] { SlideSynth.render(speed: speed, gravel: gravel, seconds: seconds, sampleRate: sr) }
        func started(_ speed: Float, _ gravel: Float = 1) -> (scuffs: Int, clacks: Int) { let g = SlideSynth(sampleRate: sr); for _ in 0..<Int(6 * sr) { _ = g.next(speed: speed, gravel: gravel) }; return (g.scuffsStarted, g.clacksStarted) }
        let full = Array(render(1, 1, 8).dropFirst(Int(0.5 * sr)))
        // Sparse: separate events with silence between them (the fraction of 10 ms windows that carry sound), not a bed.
        let win = Int(sr * 0.01)
        let env = stride(from: 0, to: full.count - win, by: win).map { k in (full[k..<k + win].reduce(0) { $0 + $1 * $1 } / Float(win)).squareRoot() }
        let top = env.max()!
        let duty = Float(env.filter { $0 > 0.1 * top }.count) / Float(env.count)
        let crestDB = 20 * log10(full.map { abs($0) }.max()! / Self.rms(full))
        if verbose { print(String(format: "slide: duty %.2f (windows above -20 dB of the peak), crest %.1f dB, rms %.5f, peak %.4f", duty, crestDB, Self.rms(full), full.map { abs($0) }.max()!)) }
        check(duty < 0.45 && crestDB > 12, "slide: it is a set of separate events, not static: only \(Int(duty * 100)) % of 10 ms windows carry sound (under 45 %) and the crest factor is \(String(format: "%.1f", crestDB)) dB (a noise bed is 10-12 dB or less; at least 12)")
        // No low bed: the F03 voice put 100-250 Hz under a grain cloud.
        let sp = A.spectrum(full)
        let total = max(A.band(sp, 40, 9000), 1e-12)
        check(A.band(sp, 40, 250) / total < 0.08, "slide: no low bed: \(String(format: "%.1f", 100 * A.band(sp, 40, 250) / total)) % of the power is under 250 Hz (F03's mass bed was the static)")
        // The rate follows the slip speed.
        let sl = started(0.25), sm = started(0.6), sh = started(1)
        let perSec = { (v: (scuffs: Int, clacks: Int)) in Float(v.scuffs + v.clacks) / 6 }
        if verbose { print("slide: events per second at slip 0.25 / 0.6 / 1: \(perSec(sl)) / \(perSec(sm)) / \(perSec(sh)) (scuffs \(sl.scuffs)/\(sm.scuffs)/\(sh.scuffs), clacks \(sl.clacks)/\(sm.clacks)/\(sh.clacks))") }
        check(perSec(sl) < perSec(sm) && perSec(sm) < perSec(sh) && perSec(sl) >= 1.5 && perSec(sh) >= 6 && perSec(sh) <= 14, "slide: the event rate follows the slip: \(String(format: "%.1f", perSec(sl))) a second at 0.25, \(String(format: "%.1f", perSec(sm))) at 0.6, \(String(format: "%.1f", perSec(sh))) at full speed (1.5 at least slow; 6-14 fast)")
        check(sh.clacks >= 6 && sh.clacks <= 40 && sl.clacks < sh.clacks, "slide: a few stones clack on gravel: \(sh.clacks) in six seconds at full speed, \(sl.clacks) at a slow slip")
        // The level follows the slip.
        let rms = [Float(0.25), 0.5, 0.75, 1].map { Self.rms(Array(render($0, 1, 12).dropFirst(Int(0.5 * sr)))) }
        check(zip(rms, rms.dropFirst()).allSatisfy { $1 > $0 * 1.1 } && rms[3] > 1.8 * rms[0], "slide: the level follows the slip (rms at 0.25, 0.5, 0.75, 1: \(rms.map { String(format: "%.5f", $0) }))")
        // Well under the footsteps, through the same mix (the footsteps carry `AmbienceSynth.stepMix`, the slide is added as it is).
        let rock = A.render(mix: A.pure(.rock), count: 12, seconds: 0.5).map { $0.map { $0 * AmbienceSynth.stepMix } }
        let rockPeak = A.mean(rock.map { $0.map { abs($0) }.max() ?? 0 })
        let rockRms = (rock.map { $0.reduce(0) { $0 + $1 * $1 } }.reduce(0, +) / Float(rock.count * rock[0].count)).squareRoot()      // a step every half second
        let slidePeak = full.map { abs($0) }.max()!
        let peakDB = 20 * log10(slidePeak / rockPeak), rmsDB = 20 * log10(Self.rms(full) / rockRms)
        if verbose { print(String(format: "slide vs a rock footstep every 0.5 s: peak %.1f dB, rms %.1f dB", peakDB, rmsDB)) }
        check(peakDB < -9 && rmsDB < -9, "slide: well under the footsteps: its peak is \(String(format: "%.1f", peakDB)) dB and its RMS \(String(format: "%.1f", rmsDB)) dB against rock footsteps at a step every half second (both under -9 dB)")
        // Gone within 0.2 s of regaining footing.
        let g = SlideSynth(sampleRate: sr)
        var trace: [Float] = []
        for _ in 0..<Int(2 * sr) { trace.append(g.next(speed: 1, gravel: 1)) }
        let steadyRms = Self.rms(Array(trace.suffix(Int(1.0 * sr))))
        var after: [Float] = []
        for _ in 0..<Int(0.6 * sr) { after.append(g.next(speed: 0, gravel: 1)) }
        let w1 = Self.rms(Array(after[Int(0.15 * sr)..<Int(0.20 * sr)])), w2 = Self.rms(Array(after[Int(0.20 * sr)..<Int(0.25 * sr)]))
        check(w1 < 0.03 * steadyRms && w2 < 0.01 * steadyRms, "slide: gone within 0.2 s of regaining footing (-30 dB by 200 ms: \(String(format: "%.0f", 20 * log10(max(w1, 1e-9) / steadyRms))) dB; -40 dB by 250 ms: \(String(format: "%.0f", 20 * log10(max(w2, 1e-9) / steadyRms))) dB)")
        check(Self.rms(render(0, 1, 1)) < 1e-6, "slide: no sound at all when not slipping")
        // Soil: softer, darker, scuffs only.
        let gr = Array(render(1, 0, 8).dropFirst(Int(0.5 * sr)))
        let gs = started(1, 0)
        let cg = A.centroid(A.spectrum(gr)), cv = A.centroid(sp)
        check(Self.rms(gr) < 0.6 * Self.rms(full) && Self.rms(gr) > 0.04 * Self.rms(full) && cg < 0.85 * cv && gs.clacks == 0, "slide: soil is softer, darker and has no clacks (rms \(Int(100 * Self.rms(gr) / Self.rms(full))) % of the gravel's, centroid \(Int(cg)) Hz against \(Int(cv)) Hz, \(gs.clacks) clacks)")
    }
}
