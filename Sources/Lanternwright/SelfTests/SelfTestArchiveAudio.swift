import Foundation

/// Self-tests: the Tide Archive's sound (S04.4), in the style of the F07 door tests: since a person cannot be in the loop, every layer is checked as numbers: where its energy sits, how it follows the
/// water's level, rate and distance, what each route's drone does, and that the sluice has the weight of the door (real harmonics in 150-900 Hz, a low thud, a level guard against a stone run step).
extension SelfTestRunner {
    func runArchiveAudio() {
        guard name == "all" || name == "archiveaudio" || name == "story" else { return }
        typealias A = FootstepAnalysis
        let sr: Float = 44100
        let verbose = name == "archiveaudio"

        func render(_ seconds: Float, inputs: ArchiveAudio.Inputs, events: [(Float, ArchiveAudio.Event)] = [], seed: UInt32 = 0xA2C1, lead: Float = 3) -> [Float] {
            let a = ArchiveAudio(sampleRate: sr, seed: seed)
            a.setInputs(inputs)
            var left = [Float](repeating: 0, count: Int(sr * (seconds + lead))), right = left
            let block = 512
            var pending = events.sorted { $0.0 < $1.0 }
            var i = 0
            while i < left.count {
                let n = min(block, left.count - i)
                while let first = pending.first, Float(i) / sr >= first.0 + lead { a.handle(first.1); pending.removeFirst() }
                left.withUnsafeMutableBufferPointer { lp in right.withUnsafeMutableBufferPointer { rp in a.render(frames: n, left: lp.baseAddress! + i, right: rp.baseAddress! + i) } }
                i += n
            }
            return Array(left[Int(sr * lead)...])                      // the first `lead` seconds fade the layers in: not measured
        }
        func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }
        func tone(_ x: [Float], _ f: Float) -> Float { A.power(x, f) }
        var base = ArchiveAudio.Inputs(); base.active = true; base.route = .ilse; base.tide = 0.5; base.tideRate = 0; base.waterDistance = 1000

        // The pitches: every one is a ToneTable pitch or an octave of one (pillar 5).
        func octaveOfToneTable(_ f: Float) -> Bool {
            let pool = ToneTable.stoneHz + ToneTable.glassHz + [ToneTable.buoyHz]
            return pool.contains { p in (-6...6).contains { abs(f - p * pow(2, Float($0))) < 0.01 } }
        }
        check((ArchiveTones.baseHz + ArchiveTones.dripHz + ArchiveTones.hallHz).allSatisfy(octaveOfToneTable), "archive audio: every pitch (the drone's, the drips', the hall's) is a ToneTable pitch or an octave of one")
        check(Set(ArchiveTones.baseHz.map { Int($0.rounded()) }) != Set(ToneTable.droneHz.map { Int($0.rounded()) }) && ArchiveTones.baseHz.count == 3, "archive audio: the Archive has its own three base tones, not the stones' drone (F02 answer 2: each world its own)")

        // Present only when the player is: silent outside, there inside.
        var off = base; off.active = false
        let silent = render(4, inputs: off), there = render(6, inputs: base)
        check(rms(silent) < 1e-5 && rms(there) > 0.002 && rms(there) < 0.05, "archive audio: silent outside the Archive and present, quiet, inside (RMS \(String(format: "%.5f", rms(silent))) outside, \(String(format: "%.4f", rms(there))) inside)")
        let lowPart = A.onePoleLow(A.onePoleLow(there, 420), 420)
        check(rms(lowPart) / rms(there) > 0.75, "archive audio: the drone sits low, with the drips' pings the only thing above it (\(Int(100 * rms(lowPart) / rms(there))) % of the level is under about 400 Hz)")

        // Route keys: Ilse's drone pulses its three tones in order (the stones' order); Oren's drifts between them without that order. Each tone's loudness over time, in half-second windows.
        func series(_ x: [Float], _ k: Int) -> [Float] { let n = Int(0.5 * sr); return stride(from: 0, to: x.count - n, by: n).map { tone(Array(x[$0..<($0 + n)]), ArchiveTones.baseHz[k]) } }
        func foldedPhase(_ s: [Float]) -> Float {                                          // the three 12 s rounds averaged, then the phase of the round's first harmonic
            var prof = [Float](repeating: 0, count: 24)
            for j in 0..<24 { var sum: Float = 0; for c in 0..<3 { sum += s[c * 24 + j] }; prof[j] = sum / 3 }
            var c: Float = 0, sn: Float = 0
            for (k, v) in prof.enumerated() { let a = 2 * Float.pi * Float(k) / 24; c += v * cos(a); sn += v * sin(a) }
            var ph = atan2(sn, c) * 12 / (2 * Float.pi); if ph < 0 { ph += 12 }
            return ph
        }
        func gap(_ a: Float, _ b: Float) -> Float { var d = (b - a).truncatingRemainder(dividingBy: 12); if d < 0 { d += 12 }; return d }
        let ilse = render(36, inputs: base)
        var oren = base; oren.route = .oren
        let orenX = render(36, inputs: oren)
        let sI = (0..<3).map { series(ilse, $0) }, sO = (0..<3).map { series(orenX, $0) }
        let pI = sI.map(foldedPhase)
        let gaps = [gap(pI[0], pI[1]), gap(pI[1], pI[2])]
        if verbose { print("ilse peak gaps \(gaps)") }
        check(gaps.allSatisfy { abs($0 - 4) <= 1.0 }, "archive audio: Ilse's route key: the three base tones peak in turn, a third of a 12 s round apart, in the stones' order (gaps \(gaps.map { String(format: "%.1f", $0) }))")
        let pO = sO.map(foldedPhase)
        let gapsO = [gap(pO[0], pO[1]), gap(pO[1], pO[2])]
        if verbose { print("oren peak gaps \(gapsO)") }
        check(!gapsO.allSatisfy { abs($0 - 4) <= 1.6 } && sO[0].count > 60, "archive audio: Oren's route key drifts: the tones do not peak in turn (gaps \(gapsO.map { String(format: "%.1f", $0) }))")
        check(ilse != orenX && ilse == render(36, inputs: base), "archive audio: the two keys differ, and each is reproducible")

        // The tide's wash follows the water's distance, its rate and its level.
        var rates = base; rates.tideRate = 0.035; rates.waterDistance = 2
        var still = base; still.waterDistance = 2
        var near = base; near.waterDistance = 2; near.tideRate = 0.02
        var mid = near; mid.waterDistance = 10
        var far = near; far.waterDistance = 40
        func bubblesBand(_ x: [Float]) -> Float { A.band(A.spectrum(x), 2600, 6000) }
        let bn = bubblesBand(render(12, inputs: near)), bm = bubblesBand(render(12, inputs: mid)), bf = bubblesBand(render(12, inputs: far)), b0 = bubblesBand(render(12, inputs: { var i = base; i.waterDistance = 1000; i.tideRate = 0.02; return i }()))
        if verbose { print("wash band near \(bn) mid \(bm) far \(bf) none \(b0)") }
        check(bn > bm && bm > bf && bf >= b0 && bn > 2 * b0, "archive audio: the wash is loudest beside the water and falls away with distance (the bubbles' band \(String(format: "%.2f", bn / max(b0, 1e-12))) x at 2 m, \(String(format: "%.2f", bm / max(b0, 1e-12))) at 10, \(String(format: "%.2f", bf / max(b0, 1e-12))) at 40, 1 far away)")
        let quick = render(12, inputs: rates), calm = render(12, inputs: still)
        func highShare(_ x: [Float]) -> Float { let s = A.spectrum(x); return A.band(s, 800, 6000) }
        if verbose { print("laps: moving high band \(highShare(quick)) still \(highShare(calm))") }
        check(highShare(quick) > 2.0 * highShare(calm), "archive audio: the laps quicken when the water is moving (the bubbles' band \(String(format: "%.1f", highShare(quick) / max(highShare(calm), 1e-12))) x a still tide)")
        var lowTide = near; lowTide.tide = 0.05; lowTide.tideRate = 0
        var highTide = lowTide; highTide.tide = 0.95
        func hall(_ x: [Float]) -> Float { ArchiveTones.hallHz.map { tone(x, $0) }.reduce(0, +) }
        let hl = hall(render(10, inputs: lowTide)), hh = hall(render(10, inputs: highTide))
        if verbose { print("hall low \(hl) high \(hh)") }
        check(hh > 1.6 * hl, "archive audio: the hall's hum swells with the water's level (\(String(format: "%.1f", hh / max(hl, 1e-12))) x from low water to high)")
        var up = near; up.tideRate = 0.035
        var down = near; down.tideRate = -0.035
        func leaning(_ x: [Float], _ dir: Float) -> Float { ArchiveTones.hallHz.map { tone(x, $0 * (1 + dir * 0.004)) }.reduce(0, +) }
        let xu = render(14, inputs: up), xd = render(14, inputs: down)
        if verbose { print("lean up: sharp \(leaning(xu, 1)) flat \(leaning(xu, -1))  down: sharp \(leaning(xd, 1)) flat \(leaning(xd, -1))") }
        check(leaning(xu, 1) > 1.5 * leaning(xu, -1) && leaning(xd, -1) > 1.5 * leaning(xd, 1), "archive audio: rising water leans the room's hum a few cents sharp and falling water flat")

        // The drips: tuned to the stones' tones; more of them as the water falls.
        func dripCount(_ inp: ArchiveAudio.Inputs, seconds: Float) -> Int { let a = ArchiveAudio(sampleRate: sr); a.setInputs(inp); var l = [Float](repeating: 0, count: 512), r = l; for _ in 0..<Int(sr * (seconds + 3) / 512) { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in a.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } } }; return a.dripsStarted }
        var restI = base; restI.tideRate = 0
        var fallI = base; fallI.tideRate = -0.035
        let dRest = dripCount(restI, seconds: 120), dFall = dripCount(fallI, seconds: 120)
        if verbose { print("drips rest \(dRest) falling \(dFall)") }
        check(dRest >= 12 && dRest <= 50 && Float(dFall) > 2.5 * Float(dRest), "archive audio: the ledgers drip every few seconds when the water is still and far more when it falls (\(dRest) in 120 s, \(dFall) falling)")

        // The tuning fork's held tone: on its stone's pitch, there while held, gone soon after.
        for k in 0..<3 {
            let held = render(3, inputs: base, events: [(0, .fork(k, on: true))])
            let late = Array(held[Int(1.0 * sr)...])
            let others = (0..<3).filter { $0 != k }.map { tone(late, ToneTable.stoneHz[$0]) }.max()!
            check(tone(late, ToneTable.stoneHz[k]) > 20 * others, "archive audio: the fork held for stone \(k) sounds at its pitch (\(ToneTable.stoneHz[k]) Hz) and no other stone's")
        }
        let heldF = render(4, inputs: off, events: [(0, .fork(1, on: true)), (2, .fork(1, on: false))])
        let during = rms(Array(heldF[Int(1.0 * sr)..<Int(2.0 * sr)])), after = rms(Array(heldF[Int(3.2 * sr)...]))
        check(during > 0.002 && during < 0.1 && after < 0.02 * during && (heldF.map { abs($0) }.max() ?? 1) < 0.25, "archive audio: it is held while the player holds it (RMS \(String(format: "%.4f", during))), lets go within about a second, and is never loud (peak \(String(format: "%.3f", heldF.map { abs($0) }.max() ?? 0)))")

        // The sluice gate: the door's weight rules.
        func metrics(_ x: [Float]) -> (low: Float, mid: Float, centroid: Float, rise: Float) {
            let s = A.spectrum(x), tot = max(A.band(s, 40, 9000), 1e-12)
            var num: Float = 0, den: Float = 0
            for (i, p) in s.enumerated() { let f = Float(i + 1) * 40; num += f * p; den += p }
            var e: [Float] = [], fc: Float = 1000
            while fc <= 6000 { e.append(A.band(s, fc / pow(2, 1.0 / 6), fc * pow(2, 1.0 / 6))); fc *= pow(2, 1.0 / 3) }
            var worst: Float = 0
            for i in 1..<(e.count - 1) { worst = max(worst, e[i] / max(max(e[i - 1], e[i + 1]), 1e-20)) }
            return (A.band(s, 40, 900) / tot, A.band(s, 150, 900) / tot, num / max(den, 1e-12), 10 * log10(max(worst, 1e-9)))
        }
        func synthPeak(_ setup: (AmbienceSynth) -> Void) -> Float {
            let s = AmbienceSynth(sampleRate: sr); s.windGain = 0; s.surfGain = 0; s.master = 1; setup(s)
            var l = [Float](repeating: 0, count: Int(sr * 2)), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }
            return l.map { abs($0) }.max() ?? 0
        }
        let run = (1.4 / AmbienceSynth.stepMix) * synthPeak { $0.stepSurface = .stone; $0.stepRun = true; $0.stepCounter += 1 }      // the same reference the door's guard uses
        let opening = render(2.6, inputs: off, events: [(0, .sluice(0, opening: true))], lead: 0), closing = render(2.6, inputs: off, events: [(0, .sluice(0, opening: false))], lead: 0)
        for (label, x) in [("opening", opening), ("closing", closing)] {
            let m = metrics(x), pk = (x.map { abs($0) }.max() ?? 0) / run
            if verbose { print(String(format: "SLUICE %@: %.0f %% under 900 Hz, %.0f %% in 150-900 Hz, centroid %.0f Hz, worst 1/3-octave rise above 1 kHz %.1f dB, peak %.2f x a stone run step", label, m.low * 100, m.mid * 100, m.centroid, m.rise, pk)) }
        }
        let mo = metrics(opening), mc = metrics(closing)
        check([mo, mc].allSatisfy { $0.low >= 0.70 } && [mo, mc].allSatisfy { $0.centroid < 900 }, "archive audio: the sluice is heavy: \([mo, mc].map { String(format: "%.0f", $0.low * 100) }) % of the power under 900 Hz (opening, closing) and a centroid under 900 Hz (\(Int(mo.centroid)), \(Int(mc.centroid)))")
        check([mo, mc].allSatisfy { $0.mid >= 0.30 }, "archive audio: the part a laptop speaker can play: at least 30 % of the power in 150-900 Hz (\([mo, mc].map { String(format: "%.0f", $0.mid * 100) }) %)")
        check([mo, mc].allSatisfy { $0.rise < 6 }, "archive audio: no tone above 1 kHz stands more than 6 dB over its neighbours (one-third-octave bands; worst \([mo, mc].map { String(format: "%.1f", $0.rise) }) dB)")
        let pkO = (opening.map { abs($0) }.max() ?? 0) / run, pkC = (closing.map { abs($0) }.max() ?? 0) / run
        check(pkC >= 0.8 && pkC <= 1.0 && pkO >= 0.4 && pkO <= pkC, "archive audio: the level guard: the closing thud is \(String(format: "%.2f", pkC)) of a stone run step (0.8-1.0) and the opening \(String(format: "%.2f", pkO)) (softer, not louder than the closing)")
        // The creak is built of REAL harmonics: in the creak's middle the partials of its fundamental stand out in 150-900 Hz.
        let creak = Array(opening[Int(0.7 * sr)..<Int(1.3 * sr)])
        var bestF0: Float = 0, bestScore: Float = 0
        for f0 in stride(from: Float(120), through: 180, by: 1) {
            let score = (2...6).filter { Float($0) * f0 <= 900 }.map { tone(creak, Float($0) * f0) }.reduce(0, +)
            if score > bestScore { bestScore = score; bestF0 = f0 }
        }
        let floorLevel = (1...20).map { tone(creak, 160 + 33.7 * Float($0)) }.reduce(0, +) / 20
        check(bestF0 >= 125 && bestF0 <= 175 && bestScore > 4 * floorLevel, "archive audio: the creak has a fundamental near \(Int(bestF0)) Hz whose own harmonics stand over the floor (\(String(format: "%.1f", bestScore / max(floorLevel, 1e-12))) x)")
        check(ArchiveFoley.sluice(opening: true, sampleRate: sr) == ArchiveFoley.sluice(opening: true, sampleRate: sr) && !opening.contains { !$0.isFinite } && rms(Array(opening[Int(2.2 * sr)...])) < 0.15 * rms(opening), "archive audio: the sluice is reproducible and rings out")
    }
}
