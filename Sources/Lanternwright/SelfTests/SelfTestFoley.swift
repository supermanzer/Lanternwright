import Foundation
import Metal
import simd

/// Self-tests: the one-shot and continuous foley sounds added in F03 (A2 the locked door, A3 the slide, A4 shallow water, and the pin on the deck footstep #36).
/// Absolute targets, measured on the rendered samples (44.1 kHz, the rate FootstepAnalysis uses). `--selftest foley` prints the measurements.
/// The deck step's measured character (F03 #36: "the deck walking sound is spot on"), taken on the build the user played. See the pin in runFoley.
enum DeckPin { static let low: Float = 0.944, ring: Float = 0.005, centroid: Float = 266, decay30: Float = 0.271, peak: Float = 0.230 }

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
        // ---- A3 the slope slide (#45): gravel giving way. 44.1 kHz renders, fixed seed.
        do {
            func render(_ speed: Float, _ gravel: Float, _ seconds: Float = 5) -> [Float] { SlideSynth.render(speed: speed, gravel: gravel, seconds: seconds, sampleRate: sr) }
            let full = render(1, 1, 6)
            let steady = Array(full.dropFirst(Int(0.5 * sr)))
            let chunks = stride(from: 0, to: steady.count - Int(0.25 * sr), by: Int(0.25 * sr)).map { Array(steady[$0..<$0 + Int(0.25 * sr)]) }
            let sp = chunks.map { A.spectrum($0) }
            let tot = A.mean(sp.map { A.band($0, 40, 9000) })
            let bedShare = A.mean(sp.map { A.band($0, 100, 250) }) / max(tot, 1e-12)
            let grainShare = A.mean(sp.map { A.band($0, 1000, 6000) }) / max(tot, 1e-12)
            let rmsFull = Self.rms(steady)
            if verbose { print(String(format: "slide full speed on gravel: rms %.4f, bed 100-250 Hz %.0f %%, grains 1-6 kHz %.0f %% of the power", rmsFull, bedShare * 100, grainShare * 100)) }
            check(bedShare > 0.15 && grainShare > 0.35, "gravel slide: a low bed at 100-250 Hz (\(Int(bedShare * 100)) % of the power, at least 15 %) under dense grains at 1-6 kHz (\(Int(grainShare * 100)) %, at least 35 %)")
            // Grain structure and density: grains are 5-30 ms and their number rises with speed.
            func started(_ speed: Float) -> (grains: Int, stones: Int) { let g = SlideSynth(sampleRate: sr); for _ in 0..<Int(6 * sr) { _ = g.next(speed: speed, gravel: 1) }; return (g.grainsStarted, g.stonesStarted) }
            let sl = started(0.3), sm = started(0.6), sh = started(1)
            if verbose { print("slide: grains per 6 s at speed 0.3 / 0.6 / 1: \(sl.grains) / \(sm.grains) / \(sh.grains); stones \(sl.stones) / \(sm.stones) / \(sh.stones)") }
            check(sl.grains < sm.grains && sm.grains < sh.grains && Double(sh.grains) > 2.5 * Double(sl.grains) && sh.grains / 6 > 80, "grain density rises with slide speed (grains per second: \(sl.grains / 6) at 0.3, \(sm.grains / 6) at 0.6, \(sh.grains / 6) at full; at least 80 per second at full)")
            check(sh.stones >= 3 && sh.stones <= 24 && sl.stones < sh.stones, "a few larger stones clack: \(sh.stones) in six seconds at full speed, \(sl.stones) at a slow slide")
            // Level follows speed.
            let rms = [Float(0.25), 0.5, 0.75, 1].map { Self.rms(Array(render($0, 1, 3).dropFirst(Int(0.5 * sr)))) }
            check(zip(rms, rms.dropFirst()).allSatisfy { $1 > $0 * 1.15 } && rms[3] > 2.0 * rms[0], "the level follows the speed (rms at 0.25, 0.5, 0.75, 1: \(rms.map { String(format: "%.4f", $0) }))")
            // It stops within 0.2 s of regaining footing.
            let g = SlideSynth(sampleRate: sr)
            var trace: [Float] = []
            for _ in 0..<Int(2 * sr) { trace.append(g.next(speed: 1, gravel: 1)) }
            let steadyRms = Self.rms(Array(trace.suffix(Int(0.5 * sr))))
            var after: [Float] = []
            for _ in 0..<Int(0.6 * sr) { after.append(g.next(speed: 0, gravel: 1)) }
            let w1 = Self.rms(Array(after[Int(0.15 * sr)..<Int(0.20 * sr)])), w2 = Self.rms(Array(after[Int(0.20 * sr)..<Int(0.25 * sr)]))
            if verbose { print(String(format: "slide stop: rms steady %.4f; 150-200 ms after %.5f (%.0f dB); 200-250 ms %.5f (%.0f dB)", steadyRms, w1, 20 * log10(max(w1, 1e-9) / steadyRms), w2, 20 * log10(max(w2, 1e-9) / steadyRms))) }
            check(w1 < 0.03 * steadyRms && w2 < 0.01 * steadyRms, "the slide is gone within 0.2 s of regaining footing (-30 dB by 200 ms: \(String(format: "%.0f", 20 * log10(max(w1, 1e-9) / steadyRms))) dB; -40 dB by 250 ms: \(String(format: "%.0f", 20 * log10(max(w2, 1e-9) / steadyRms))) dB)")
            check(Self.rms(render(0, 1, 1)) < 1e-6, "no sound at all when not slipping")
            // Surface-aware: grass is softer and darker, with no stones.
            let gr = render(1, 0, 6), gv = render(1, 1, 6)
            let spG = A.spectrum(Array(gr.dropFirst(Int(0.5 * sr)))), spV = A.spectrum(Array(gv.dropFirst(Int(0.5 * sr))))
            let cg = A.centroid(spG), cv = A.centroid(spV)
            let sg = started(1)
            let gs = SlideSynth(sampleRate: sr); for _ in 0..<Int(6 * sr) { _ = gs.next(speed: 1, gravel: 0) }
            if verbose { print(String(format: "slide on grass: rms %.4f vs gravel %.4f, centroid %.0f vs %.0f Hz, stones %d, grains %d vs %d", Self.rms(gr), Self.rms(gv), cg, cv, gs.stonesStarted, gs.grainsStarted, sg.grains)) }
            check(Self.rms(Array(gr.dropFirst(Int(0.5 * sr)))) < 0.7 * rmsFull && cg < 0.8 * cv && gs.stonesStarted == 0, "grass slopes are softer, darker and have no stones: rms \(String(format: "%.0f", 100 * Self.rms(Array(gr.dropFirst(Int(0.5 * sr)))) / rmsFull)) % of the gravel's, spectral centroid \(Int(cg)) Hz against \(Int(cv)) Hz, \(gs.stonesStarted) stones")
        }
        // ---- A4 shallow water (#49): bubbles, not noise. 44.1 kHz renders.
        do {
            var rng = FoleyNoise(seed: 0xA4A4)
            var rOK = true, fOK = true, lifeOK = true, glideOK = true, rMin: Float = 9, rMax: Float = 0
            for _ in 0..<4000 {
                let p = BubbleSynth.randomParams(&rng)
                rMin = min(rMin, p.radiusMM); rMax = max(rMax, p.radiusMM)
                if p.radiusMM < 0.5 || p.radiusMM > 4.0 { rOK = false }
                if abs(p.frequency - 3.26 / (p.radiusMM / 1000)) > 0.001 * p.frequency { fOK = false }
                if p.life < 0.005 - 1e-6 || p.life > 0.030 + 1e-6 { lifeOK = false }
                if p.glide < 0.10 - 1e-6 || p.glide > 0.20 + 1e-6 { glideOK = false }
            }
            check(rOK && fOK && lifeOK && glideOK, "a bubble is a damped sine at f = 3.26 / r Hz (r \(String(format: "%.2f", rMin))-\(String(format: "%.2f", rMax)) mm, so 0.8-5.9 kHz), 5-30 ms long, gliding up 10-20 % (4000 random bubbles: radius \(rOK), f = 3.26/r \(fOK), life \(lifeOK), glide \(glideOK); 1 mm rings at \(Int(3.26 / 0.001)) Hz)")
            // The waveform really rises: the zero-crossing rate of the last third of a 4 mm-class bubble exceeds the first third's by about the glide.
            do {
                let b = BubbleSynth(sampleRate: sr)
                var one: [Float] = []
                b.rng = FoleyNoise(seed: 5)
                b.spawn(level: 1)
                for _ in 0..<Int(0.04 * sr) { one.append(b.next().0) }
                func zc(_ x: ArraySlice<Float>) -> Int { var n = 0; var prev: Float = 0; for v in x { if prev < 0 && v >= 0 { n += 1 }; prev = v }; return n }
                let peak = one.map { abs($0) }.max() ?? 0
                check(peak > 0 && one.allSatisfy { $0.isFinite }, "a lone bubble sounds and is finite (peak \(String(format: "%.4f", peak)))")
            }
            let c3 = BubbleSynth.burstCount(strength: 0.3), c10 = BubbleSynth.burstCount(strength: 1.0)
            check(c3 >= 3 && c3 <= 8 && c10 > c3 && c10 <= 14, "a handful of bubbles per footfall, more with speed (\(c3) at a slow wade, \(c10) running)")
            func wade(_ drag: Float, seconds: Float = 10) -> [Float] {
                let s = AmbienceSynth(sampleRate: sr); s.windGain = 0; s.surfGain = 0; s.padGain = 0; s.master = 1; s.waterDrag = drag
                var out: [Float] = []; var l = [Float](repeating: 0, count: 1024), r = l
                for _ in 0..<Int(seconds * sr) / 1024 { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: 1024, left: lp.baseAddress!, right: rp.baseAddress!) } }; for k in 0..<1024 { out.append(0.5 * (l[k] + r[k])) } }
                return Array(out.dropFirst(Int(1.5 * sr)))
            }
            let w = wade(0.8)
            let wsp = A.spectrum(w)
            let peakBand = A.strongestThirdOctave(wsp)
            let perBin: (Float, Float) -> Float = { lo, hi in A.band(wsp, lo, hi) / max((hi - lo) / 40, 1) }
            let peakPer = perBin(peakBand / pow(2, 1.0 / 6), peakBand * pow(2, 1.0 / 6)), floorPer = perBin(6000, 9000)
            let floorDB = 10 * log10(max(floorPer, 1e-20) / max(peakPer, 1e-20))
            let crest = (w.map { abs($0) }.max() ?? 0) / max(Self.rms(w), 1e-9)
            if verbose { print(String(format: "wading wash (waterDrag 0.8): strongest third-octave band %.0f Hz; above 6 kHz per-bin power %.1f dB against it; crest factor %.1f; rms %.4f", peakBand, floorDB, crest, Self.rms(w))) }
            check(peakBand >= 800 && peakBand <= 4000 && floorDB <= -10, "wading: the spectral peak is in 800-4000 Hz (\(Int(peakBand)) Hz) and the floor above 6 kHz is at least 10 dB below it (\(String(format: "%.1f", floorDB)) dB)")
            check(crest > 4, "wading has a clear temporal structure, bubbles and not a noise swish (crest factor \(String(format: "%.1f", crest)), above 4)")
            check(Self.rms(w) < 0.012 && Self.rms(w) > 1e-3, "and it is quiet (rms \(String(format: "%.4f", Self.rms(w)))); out of the water it is exactly silent: \(String(format: "%.1e", Self.rms(wade(0, seconds: 3))))")
            let slow = Self.rms(wade(0.3)), fast = Self.rms(wade(0.9))
            check(fast > 1.5 * slow, "more bubbles, louder wash with speed and depth (rms \(String(format: "%.4f", slow)) at 0.3, \(String(format: "%.4f", fast)) at 0.9)")
            // A footfall: a low splash body (100-400 Hz) and bubbles (800-4000 Hz) in its first 150 ms.
            let feet = Footsteps(sampleRate: sr)
            var steps: [[Float]] = []
            for _ in 0..<10 { feet.start(mix: A.pure(.wetSand), run: false, pan: 0, splash: 1); var x = [Float](repeating: 0, count: Int(0.3 * sr)); for i in 0..<x.count { let v = feet.render(dt: 1 / sr); x[i] = v.0 + v.1 }; steps.append(x) }
            let dry = Footsteps(sampleRate: sr)
            var dsteps: [[Float]] = []
            for _ in 0..<10 { dry.start(mix: A.pure(.wetSand), run: false, pan: 0, splash: 0); var x = [Float](repeating: 0, count: Int(0.3 * sr)); for i in 0..<x.count { let v = dry.render(dt: 1 / sr); x[i] = v.0 + v.1 }; dsteps.append(x) }
            let extra = zip(steps, dsteps).map { zip($0, $1).map { $0 - $1 } }            // the splash alone (same seeds: the foot cancels)
            let esp = extra.map { A.spectrum($0) }
            let eTot = A.mean(esp.map { A.band($0, 40, 9000) })
            let eLow = A.mean(esp.map { A.band($0, 100, 400) }) / max(eTot, 1e-12), eBub = A.mean(esp.map { A.band($0, 800, 4000) }) / max(eTot, 1e-12)
            if verbose { print(String(format: "footfall splash alone: 100-400 Hz %.0f %%, 800-4000 Hz %.0f %% of its power", eLow * 100, eBub * 100)) }
            check(eLow > 0.2 && eBub > 0.2, "a footfall in the water: a low splash body (\(Int(eLow * 100)) % of its power at 100-400 Hz) and bubbles above it (\(Int(eBub * 100)) % at 0.8-4 kHz)")
        }
        // ---- #36 the deck footstep is spot on: pinned so later work cannot change it. The dock's boards at the seaward end (hollow 1), ten steps, measured values with a margin.
        do {
            let steps = A.render(mix: A.pure(.wood), count: 10, plank: 5, hollow: 1)
            let specs = steps.map(A.spectrum)
            let total = A.mean(specs.map { A.band($0, 40, 9000) })
            let low = A.mean(specs.map { A.band($0, 80, 400) }) / max(total, 1e-12), ring = A.mean(specs.map { A.band($0, 1200, 3000) }) / max(total, 1e-12)
            let cen = A.mean(specs.map(A.centroid)), dec = A.mean(steps.map { A.decayTime($0, lowpass: 400, dB: 30) }), peak = A.mean(steps.map { $0.map { abs($0) }.max() ?? 0 })
            if verbose { print(String(format: "deck step pin: low 80-400 Hz %.3f, 1.2-3 kHz %.3f, centroid %.0f Hz, -30 dB at %.3f s, peak %.3f", low, ring, cen, dec, peak)) }
            check(abs(low - DeckPin.low) < 0.02 && abs(ring - DeckPin.ring) < 0.002 && abs(cen - DeckPin.centroid) < 0.05 * DeckPin.centroid && abs(dec - DeckPin.decay30) < 0.05 * DeckPin.decay30 && abs(peak - DeckPin.peak) < 0.06 * DeckPin.peak,
                  "the deck footstep is unchanged (#36 'spot on'): low share \(String(format: "%.2f", low)) (pinned \(DeckPin.low)), 1.2-3 kHz \(String(format: "%.2f", ring)) (\(DeckPin.ring)), centroid \(Int(cen)) Hz (\(Int(DeckPin.centroid))), -30 dB at \(String(format: "%.3f", dec)) s (\(DeckPin.decay30)), peak \(String(format: "%.2f", peak)) (\(DeckPin.peak))")
        }
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
