import Foundation
import Metal
import simd

/// Self-tests: the soft pad (F02 A4). Every pitch is the game's own, each world has its own score (the user's decision), the pad is silent on the beach and steady
/// well inland, sits a fixed number of dB under the wind lull, and makes way for chimes. `--selftest pad` prints the numbers.
extension SelfTestRunner {
    static func renderPad(gain: Float, score: PadScore, seconds: Float, start: Double = 0, sampleRate sr: Float = 22050, chime: ChimeKind? = nil, chimeAt: Float = 0) -> [Float] {
        let s = AmbienceSynth(sampleRate: sr)
        s.windGain = 0; s.surfGain = 0; s.master = 1; s.padScore = score; s.padGain = gain
        s.setClock(seconds: start)
        var out: [Float] = []
        let block = 1024
        var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
        var played = chime == nil
        for b in 0..<Int(seconds * sr) / block {
            if !played && Float(b * block) / sr >= chimeAt { s.play(chime!); played = true }
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: block, left: lp.baseAddress!, right: rp.baseAddress!) } }
            for k in 0..<block { out.append(0.5 * (l[k] + r[k])) }
        }
        return out
    }

    func runPad() {
        guard name == "all" || name == "pad" else { return }
        let sr: Float = 22050
        // The notes: every one is a ToneTable tone, or an octave or a fifth of one, within 5 cents.
        for score in [PadScore.varrow, .glassWood] {
            let notes = Set(score.chords.flatMap { $0 })
            check(notes.allSatisfy { ToneTable.isFamilyTone($0) }, "pad (\(score.name)): every note is one of the game's tones (or an octave or fifth of one) within 5 cents (\(notes.sorted().map { String(format: "%.1f", $0) }) Hz)")
            check(score.phraseSeconds > 100 && score.phraseSeconds < 190 && (0..<40).allSatisfy { score.duration(of: $0) >= 25 && score.duration(of: $0) <= 50 }, "pad (\(score.name)): a chord lasts 25 to 50 s and one trip round the score takes about two minutes (\(Int(score.phraseSeconds)) s)")
            let tops = Set(score.chords.map { $0.last! })
            check(tops.count >= 3 && tops.count <= 5, "pad (\(score.name)): the top voice walks 3 to 5 notes (\(tops.count))")
        }
        let vs = Set(PadScore.varrow.chords.flatMap { $0 }), gs = Set(PadScore.glassWood.chords.flatMap { $0 })
        check(vs != gs && gs.contains(ToneTable.glassHz[3]) && !vs.contains(ToneTable.glassHz[3]) && vs.contains(ToneTable.droneThirdHz), "each world has its own tones: the home island sits in the stones' D with the just third, the Glass Wood adds its own C5 (the pillars' key)")
        check(PadScore.score(for: .varrow).name == "varrow" && PadScore.score(for: .glassWood).name == "glassWood", "the engine picks the score by world")
        // What is actually sounding sits on the notes: render the second half of the first chord and find each note's spectral peak within 40 cents.
        do {
            let score = PadScore.varrow
            let hz: Float = FootstepAnalysis.sr                       // the analysis helpers assume 44.1 kHz
            let x = Self.renderPad(gain: 1, score: score, seconds: 22, sampleRate: hz)
            let tail = Array(x[Int(14 * hz)..<Int(21 * hz)])
            var worst: Float = 0
            for note in score.chords[0] {
                var best: Float = 0, bestP: Float = -1
                var f = note * 0.977; while f < note * 1.023 { let p = FootstepAnalysis.power(tail, f); if p > bestP { bestP = p; best = f }; f += 0.1 }
                worst = max(worst, abs(1200 * log2(best / note)))
            }
            check(worst <= 5, "the rendered pad sounds on its notes: the largest error of a spectral peak from its table pitch is \(String(format: "%.1f", worst)) cents (5 at most)")
        }
        // Level: silent on the beach, fading in over 60 m, steady inland, at a fixed dB under the wind lull.
        let summit = SIMD3<Float>(Layout.summitStone.x, Layout.summitStone.y, Layout.summitStone.z)
        // The drone's level is held where the user kept it: against the wind lull as it was before F03 A1 (-14 dB; the wind itself is now -25 dB).
        let lullRMS = Self.envelope1s(Self.renderWind(at: summit, seconds: 150, sampleRate: sr), sampleRate: sr).min()! * pow(10, (AmbienceSynth.windLullDBBeforeF03 - AmbienceSynth.windLullDB) / 20)
        func padDB(_ d: Float) -> Float {
            let x = Self.renderPad(gain: AudioSpace.padLevel(shoreDistance: d), score: .varrow, seconds: 60, start: 100, sampleRate: sr)
            return 20 * log10(max(Self.rms(Array(x[Int(30 * sr)...])), 1e-12) / lullRMS)
        }
        let at10 = padDB(10), at60 = padDB(60), at120 = padDB(120), at300 = padDB(300)
        if name == "pad" { print(String(format: "pad against the wind lull: 10 m %.1f dB, 60 m %.1f dB, 120 m %.1f dB, 300 m %.1f dB (wind lull rms %.4f)", at10, at60, at120, at300, lullRMS)) }
        check(AudioSpace.padLevel(shoreDistance: 10) == 0 && AudioSpace.padLevel(shoreDistance: 25) == 0 && AudioSpace.padLevel(shoreDistance: 85) == 1, "the pad is silent within 25 m of the shore and fully in by 85 m (60 m of fade)")
        check(at10 < -60 && at60 > at10 + 30 && at60 < at120 - 4, "the pad grows inland: 10 m \(String(format: "%.0f", at10)) dB, 60 m \(String(format: "%.1f", at60)) dB, 120 m \(String(format: "%.1f", at120)) dB (against the wind lull)")
        check(abs(at120 - AudioSpace.padPlateauDB) < 2 && abs(at300 - at120) < 0.5, "inland the pad plateaus at \(Int(AudioSpace.padPlateauDB)) dB under the wind lull (\(String(format: "%.1f", at120)) dB at 120 m, \(String(format: "%.1f", at300)) dB at 300 m)")
        // It makes way for a chime: ducking applies to the pad like the wind and the surf. Render the chime with and without the pad, subtract, and compare the pad's own D3
        // band while the chime rings against the same band in a render with no chime.
        do {
            let hz: Float = FootstepAnalysis.sr
            let quiet = Self.renderPad(gain: 1, score: .varrow, seconds: 12, start: 100, sampleRate: hz)
            let withPad = Self.renderPad(gain: 1, score: .varrow, seconds: 12, start: 100, sampleRate: hz, chime: .tide, chimeAt: 5)
            let chimeOnly = Self.renderPad(gain: 0, score: .varrow, seconds: 12, start: 100, sampleRate: hz, chime: .tide, chimeAt: 5)
            let padWhileRinging = zip(withPad, chimeOnly).map { $0 - $1 }
            let range = Int(6 * hz)..<Int(8 * hz)
            let a = FootstepAnalysis.power(Array(quiet[range]), ToneTable.droneHz[0]), b = FootstepAnalysis.power(Array(padWhileRinging[range]), ToneTable.droneHz[0])
            check(b < a * 0.85 && b > a * 0.4, "the pad ducks under a chime (its D3 band falls to \(Int(100 * b / a)) % while the chime rings)")
        }
    }
}
