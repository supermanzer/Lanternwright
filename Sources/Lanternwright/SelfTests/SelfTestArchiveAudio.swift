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
        check(rms(silent) < 1e-5 && rms(there) > 0.002 && rms(there) < 0.1, "archive audio: silent outside the Archive and present, quiet, inside (RMS \(String(format: "%.5f", rms(silent))) outside, \(String(format: "%.4f", rms(there))) inside)")
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

        // The drone's level against the stones' own drone (all three voices on, at the same master): the Archive's bed holds its own without drowning anything.
        func stoneDroneRMS() -> Float {
            let sy = AmbienceSynth(sampleRate: sr); sy.windGain = 0; sy.surfGain = 0; sy.master = 1
            for v in 0..<3 { sy.setDrone(v, on: true) }
            var l = [Float](repeating: 0, count: Int(sr * 6)), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in sy.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }
            return rms(Array(l[Int(sr * 3)...]))
        }
        let stoneRMS = stoneDroneRMS(), bed = rms(there)
        if verbose { print("drone levels: stones \(stoneRMS) archive bed \(bed) (ratio \(bed / stoneRMS))") }
        check(bed > 0.3 * stoneRMS && bed < 0.9 * stoneRMS, "archive audio: the Archive's bed holds its own beside the stones' drone without drowning it (\(String(format: "%.2f", bed / stoneRMS)) x its level)")
        // The engine mixes the layers through the synth's master (0.5 in the game): scaled by it, to the sample.
        do {
            let a = ArchiveAudio(sampleRate: sr), b = ArchiveAudio(sampleRate: sr)
            a.setInputs(base); b.setInputs(base)
            var l1 = [Float](repeating: 0, count: 8192), r1 = l1, l2 = l1, r2 = l1
            l1.withUnsafeMutableBufferPointer { lp in r1.withUnsafeMutableBufferPointer { rp in a.render(frames: 8192, left: lp.baseAddress!, right: rp.baseAddress!) } }
            l2.withUnsafeMutableBufferPointer { lp in r2.withUnsafeMutableBufferPointer { rp in b.render(frames: 8192, left: lp.baseAddress!, right: rp.baseAddress!, master: 0.5) } }
            check(zip(l1, l2).allSatisfy { abs($0 * 0.5 - $1) < 1e-7 } && (l1.map { abs($0) }.max() ?? 0) > 0, "archive audio: the layers are scaled by the synth's master gain, as the rest of the mix is")
        }
        // Pitch does not drift with the session's length: started at 10 minutes, Oren's D3 drone and the hall hum are still within their own few cents of the ToneTable pitch.
        var lateO = base; lateO.route = .oren; lateO.waterDistance = 3; lateO.tide = 0.5; lateO.tideRate = 0.035
        func late(_ start: Double, _ inp: ArchiveAudio.Inputs) -> [Float] {
            let a = ArchiveAudio(sampleRate: sr, startTime: start); a.setInputs(inp)
            var l = [Float](repeating: 0, count: Int(sr * 10)), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in a.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }
            return Array(l[Int(sr * 3)...])
        }
        let xl = late(600, lateO)
        func peakNear(_ x: [Float], _ f0: Float, span: Float) -> Float { var best: Float = 0, bf = f0; var f = f0 - span; while f <= f0 + span { let p = tone(x, f); if p > best { best = p; bf = f }; f += 0.1 }; return bf }
        let dPeak = peakNear(xl, ArchiveTones.baseHz[0], span: 12), hPeak = peakNear(xl, ArchiveTones.hallHz[0], span: 4)
        if verbose { print("late pitch: drone D3 at \(dPeak) Hz (\(ArchiveTones.baseHz[0])), hall at \(hPeak) Hz (\(ArchiveTones.hallHz[0]))") }
        check(abs(dPeak / ArchiveTones.baseHz[0] - 1) < 0.01 && abs(hPeak / ArchiveTones.hallHz[0] - 1) < 0.01, "archive audio: ten minutes into a session the drone and the hum are still on their ToneTable pitches (D3 at \(String(format: "%.1f", dPeak)) Hz, hum at \(String(format: "%.1f", hPeak)) Hz)")
        check(late(0, base) != late(600, base), "archive audio: and the slow pulses and drifts really do start where the clock says")

        // The gallery's reverb (S04.4b): a stable four-line FDN whose tail falls 60 dB in about its rt60, and one wet constant.
        do {
            var rv = ArchiveReverb(sampleRate: sr)
            var tail: [Float] = []
            for i in 0..<Int(sr * 4) { let w = rv.process(left: i == 0 ? 1 : 0, right: 0); tail.append(w.0 + w.1) }
            func energy(_ lo: Float, _ hi: Float) -> Float { tail[Int(lo * sr)..<Int(hi * sr)].reduce(0) { $0 + $1 * $1 } }
            let e1 = energy(0.4, 0.6), e2 = energy(1.4, 1.6)
            let dbPerSecond = 10 * log10(max(e1, 1e-20) / max(e2, 1e-20))                         // energy drop over one second
            let rt60 = 60 / max(dbPerSecond, 1e-3)
            if verbose { print("reverb: drop \(dbPerSecond) dB per second, rt60 \(rt60) s, peak \(tail.map { abs($0) }.max() ?? 0)") }
            check(!tail.contains { !$0.isFinite } && (tail.map { abs($0) }.max() ?? 9) < 1 && e1 > 0, "archive audio: the gallery reverb is stable and finite")
            check(rt60 > 0.6 * ArchiveFoley.reverbSeconds && rt60 < 1.6 * ArchiveFoley.reverbSeconds, "archive audio: its tail falls 60 dB in about \(ArchiveFoley.reverbSeconds) s (measured \(String(format: "%.1f", rt60)) s)")
            check(energy(3.5, 4.0) < 1e-3 * energy(0.0, 0.5), "archive audio: and it dies away (the last half second has under a thousandth of the first)")
            let dry = { () -> [Float] in let a = ArchiveAudio(sampleRate: sr); a.wet = 0; a.setInputs(off); a.handle(.sluice(0, opening: false)); var l = [Float](repeating: 0, count: Int(sr * 5)), r = l; l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in a.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }; return l }()
            let wetX = { () -> [Float] in let a = ArchiveAudio(sampleRate: sr); a.setInputs(off); a.handle(.sluice(0, opening: false)); var l = [Float](repeating: 0, count: Int(sr * 5)), r = l; l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in a.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }; return l }()
            let after = Int(2.6 * sr)                                                               // the closing sluice's buffer ends at 2.3 s: what is left after it is the room
            let tailDry = rms(Array(dry[after..<(after + Int(sr))])), tailWet = rms(Array(wetX[after..<(after + Int(sr))]))
            check(tailDry < 1e-6 && tailWet > 1e-4 && tailWet < 0.05, "archive audio: the wet constant (\(ArchiveFoley.reverbWet)) puts the room in: a second after the gate has stopped there is a tail (RMS \(String(format: "%.5f", tailWet))) where the dry layers are silent")
            check(abs(rms(Array(wetX[0..<Int(2.2 * sr)])) / rms(Array(dry[0..<Int(2.2 * sr)])) - 1) < 0.6, "archive audio: and the room does not change the level much (\(String(format: "%.2f", rms(Array(wetX[0..<Int(2.2 * sr)])) / rms(Array(dry[0..<Int(2.2 * sr)])))) x the dry RMS)")
            // bounded CPU: ten seconds of the busiest layers, drips and a sluice, take a tiny share of the time they last
            let a = ArchiveAudio(sampleRate: sr); var busy = base; busy.waterDistance = 2; busy.tideRate = -0.035; a.setInputs(busy)
            var l = [Float](repeating: 0, count: 512), r = l
            let t0 = Date()
            for k in 0..<Int(sr * 10 / 512) { if k % 40 == 0 { a.handle(.sluice(0, opening: true)); a.handle(.grate(run: true)) }; l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in a.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } } }
            let used = Float(Date().timeIntervalSince(t0)) / 10
            if verbose { print("archive audio cpu: \(used * 100) % of real time") }
            check(used < 0.10, "archive audio: with the reverb the busiest ten seconds cost \(String(format: "%.1f", used * 100)) % of real time (under 10 %)")
        }
        // The brass grating under a boot: a smear of ring over a small hollow knock, quiet, short, and not a pitch.
        do {
            let run = (1.4 / AmbienceSynth.stepMix) * { () -> Float in let s = AmbienceSynth(sampleRate: sr); s.windGain = 0; s.surfGain = 0; s.master = 1; s.stepSurface = .stone; s.stepRun = true; s.stepCounter += 1; var l = [Float](repeating: 0, count: Int(sr * 2)), r = l; l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }; return l.map { abs($0) }.max() ?? 0 }()
            let g = (0..<4).map { ArchiveFoley.grate(variant: $0, sampleRate: sr) }
            let sp = A.spectrum(g[0])
            let ringShare = A.band(sp, 400, 2000) / max(A.band(sp, 40, 9000), 1e-12)
            let peak = (g.map { ($0.map { abs($0) }.max() ?? 0) * ArchiveFoley.grateGain }.max() ?? 0) / run
            if verbose { print("grate: ring share \(ringShare), peak \(peak) of a run step") }
            check(g.allSatisfy { !$0.contains { !$0.isFinite } && $0.count == Int(0.3 * sr) } && g[0] != g[1] && g[2] != g[3], "archive audio: the grating step has four variants, finite, 0.3 s each")
            check(ringShare > 0.5, "archive audio: it is the ring of bars: \(Int(100 * ringShare)) % of its power in 400-2000 Hz")
            check(peak <= 0.4 && peak >= 0.05, "archive audio: and quiet: at most \(String(format: "%.2f", peak)) of a stone run step (the same reference as the door), riding on the step's own stone and wood")
            let decayT = A.decayTime(g[0], lowpass: 3000, dB: 30)
            check(decayT < 0.25, "archive audio: it rings out in \(String(format: "%.2f", decayT)) s, not a drone")
        }

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
