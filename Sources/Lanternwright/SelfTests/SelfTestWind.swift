import Foundation
import Metal
import simd

/// Self-tests: the wind (F02 A3, user notes #22 and #30: "a boiling kettle", "very loud", "nothing visual shows wind"). Absolute targets against the surf at the waterline,
/// no tonal resonance, deep gusts, and the audio and the grass driven by the same wind at the same clock. `--selftest wind` prints the table.
extension SelfTestRunner {
    static func renderWind(at p: SIMD3<Float>, seconds: Float, sampleRate sr: Float = 22050, vegetation: Float = 0) -> [Float] {
        let s = AmbienceSynth(sampleRate: sr)
        s.windGain = 1; s.surfGain = 0; s.master = 1; s.vegetation = vegetation
        s.windSource = { Wind.strength(at: p, time: $0) }
        var out: [Float] = []
        let block = 2048
        var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
        for _ in 0..<Int(seconds * sr) / block {
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: block, left: lp.baseAddress!, right: rp.baseAddress!) } }
            for k in 0..<block { out.append(0.5 * (l[k] + r[k])) }
        }
        return out
    }

    func runWind() {
        guard name == "all" || name == "wind" else { return }
        let sr: Float = 22050
        let coast: (Float, Float) -> Float = { x, _ in x < 0 ? 5 : -5 }
        let surfRef = Self.rms(Self.renderSurf(AudioSpace.ambient(at: SIMD3(-2, 5, 0), ground: coast), seconds: 60, sampleRate: sr))
        func db(_ v: Float) -> Float { 20 * log10(max(v, 1e-9) / surfRef) }
        let summit = SIMD3<Float>(Layout.summitStone.x, Layout.summitStone.y, Layout.summitStone.z)
        let beach = SIMD3<Float>(Layout.dockShore.x - 6, 1.5, Layout.dockShore.z - 3)
        let xs = Self.renderWind(at: summit, seconds: 150, sampleRate: sr), xb = Self.renderWind(at: beach, seconds: 150, sampleRate: sr)
        let es = Self.envelope1s(xs, sampleRate: sr), eb = Self.envelope1s(xb, sampleRate: sr)
        let lull = db(es.min()!), gust = db(es.max()!), depth = gust - lull
        if name == "wind" {
            print(String(format: "surf at the waterline rms %.4f", surfRef))
            print(String(format: "summit: lull %.1f dB, gust peak %.1f dB against the waterline surf, depth %.1f dB | beach: lull %.1f, gust %.1f", lull, gust, depth, db(eb.min()!), db(eb.max()!)))
        }
        check(lull <= -6 && gust <= 2, "wind level at the summit: the lull is at most 6 dB below the waterline surf and a gust peaks at most 2 dB above it (lull \(String(format: "%.1f", lull)) dB, gust \(String(format: "%.1f", gust)) dB)")
        check(depth >= 10, "wind gusts are deep: the loudest second is at least 10 dB above the quietest at the summit (\(String(format: "%.1f", depth)) dB)")
        check(db(eb.max()!) < gust - 1.5 && es.reduce(0, +) > eb.reduce(0, +), "the beach is calmer than the summit, because the shared wind field is (beach gust \(String(format: "%.1f", db(eb.max()!))) dB vs \(String(format: "%.1f", gust)) dB)")
        // Not a kettle: no narrow resonance. Average the power spectrum of one-second chunks and test every bin's prominence over its neighbours (no band 10 dB above the local spectrum).
        let chunks = stride(from: 0, to: xs.count - Int(sr), by: Int(sr)).map { Array(xs[$0..<$0 + Int(sr)]) }
        let prom = FootstepAnalysis.tonalProminence(Array(chunks.prefix(60)))
        check(prom < 3.0, "the wind has no resonant peak above 300 Hz: no band stands out from its neighbours (prominence \(String(format: "%.2f", prom)), 10 dB would be 10; a whistling kettle is a narrow peak)")
        let m = Self.measureAmbience(xs, sampleRate: sr)
        check(m.centroid < 700 && m.highShare < 0.05, "and it is low, a rush and not a hiss (centroid \(Int(m.centroid)) Hz, share above 800 Hz \(String(format: "%.3f", m.highShare)))")
        check(abs(AmbienceSynth.windLullDB - (-25)) < 1e-4 && AmbienceSynth.windGustDB - AmbienceSynth.windLullDB >= 10, "the synth's wind range is lull -25 dB to gust -8 dB against the waterline surf (F03 A1: a further -11 dB in lulls and -6 dB at gust peaks)")
        // F03 A1 (#37, "the audio implies a very high velocity wind"): ABSOLUTE targets, measured on the rendered output at the summit against the surf at the waterline.
        check(lull <= -24 && gust <= -7.5, "a light breeze, not a gale: the lull is at most -24 dB and the loudest gust at most -7.5 dB against the waterline surf (lull \(String(format: "%.1f", lull)) dB, gust \(String(format: "%.1f", gust)) dB)")
        let specs0 = chunks.prefix(60).map { FootstepAnalysis.spectrum($0) }
        let totalP = FootstepAnalysis.mean(specs0.map { FootstepAnalysis.band($0, 20, 9000) })
        let lowShare = FootstepAnalysis.mean(specs0.map { FootstepAnalysis.band($0, 20, 300) }) / max(totalP, 1e-12)
        let highShare = FootstepAnalysis.mean(specs0.map { FootstepAnalysis.band($0, 2000, 9000) }) / max(totalP, 1e-12)
        check(lowShare > 0.6 && highShare < 0.003, "the wind is a low rush: below 300 Hz holds \(String(format: "%.0f", lowShare * 100)) % of its power (at least 60 %) and above 2 kHz \(String(format: "%.3f", highShare * 100)) % (at most 0.3 %) with no grass underfoot")
        // Rustle only where there is something to rustle: with no vegetation the high band is absent, with grass underfoot it appears in a gust.
        func rustleBand(_ veg: Float) -> Float {
            let x = Self.renderWind(at: summit, seconds: 40, sampleRate: sr, vegetation: veg)
            let ch = stride(from: 0, to: x.count - Int(sr), by: Int(sr)).map { Array(x[$0..<$0 + Int(sr)]) }
            return FootstepAnalysis.mean(ch.map { FootstepAnalysis.band(FootstepAnalysis.spectrum($0), 1200, 3500) })
        }
        let bare = rustleBand(0), grassy = rustleBand(1)
        do {   // the rustle is the ONLY thing above 2 kHz, faint, and it follows the grass's own gust (the same Wind.strength the blades bend with)
            let xg = Self.renderWind(at: summit, seconds: 120, sampleRate: sr, vegetation: 1)
            let cg = stride(from: 0, to: xg.count - Int(sr), by: Int(sr)).map { Array(xg[$0..<$0 + Int(sr)]) }
            let sp = cg.map { FootstepAnalysis.spectrum($0) }
            let tot = FootstepAnalysis.mean(sp.map { FootstepAnalysis.band($0, 20, 9000) })
            let hiShare = FootstepAnalysis.mean(sp.map { FootstepAnalysis.band($0, 2000, 9000) }) / max(tot, 1e-12)
            let rus = sp.map { FootstepAnalysis.band($0, 1200, 3500) }
            let ws = (0..<cg.count).map { Wind.strength(at: summit, time: Float($0) + 0.5) }
            let mr = FootstepAnalysis.mean(rus), mw = FootstepAnalysis.mean(ws)
            var sxy: Float = 0, sxx: Float = 0, syy: Float = 0
            for k in 0..<rus.count { sxy += (rus[k] - mr) * (ws[k] - mw); sxx += (rus[k] - mr) * (rus[k] - mr); syy += (ws[k] - mw) * (ws[k] - mw) }
            let cor = sxy / max((sxx * syy).squareRoot(), 1e-12)
            check(hiShare < 0.03 && cor > 0.5, "with grass underfoot the only sound above 2 kHz is a faint rustle (\(String(format: "%.2f", hiShare * 100)) % of the power, at most 3 %) that follows the gust the grass bends with (correlation \(String(format: "%.2f", cor)), at least 0.5)")
        }
        check(grassy > bare * 1.5, "the wind rustles only where there is grass or leaf underfoot (power at 1.2-3.5 kHz: bare \(String(format: "%.2e", bare)), grass \(String(format: "%.2e", grassy)))")

        // One wind, one clock: drive the REAL plumbing (the engine's `windInput` from the game's player and clock; the renderer's clock) for a minute of play and
        // require the rendered audio level and the grass's bend at the player's feet to follow each other.
        do {
            let scene = Scene.makeWorld(device: device)
            let g = Game(scene: scene)
            g.player.position = SIMD3(Layout.summitStone.x - 10, Layout.summitStone.y, Layout.summitStone.z - 10)
            let synth = AmbienceSynth(sampleRate: sr)
            synth.windGain = 1; synth.surfGain = 0; synth.master = 1
            var now = 1000.0
            var audio: [Float] = [], bend: [Float] = []
            let per = Int(sr / 60)
            var l = [Float](repeating: 0, count: per), r = [Float](repeating: 0, count: per)
            var win: [Float] = [], bendWin: [Float] = []
            for _ in 0..<(60 * 60) {
                now += 1.0 / 60; g.advance(now: now, input: InputState())
                synth.windStrength = AudioEngine.windInput(game: g)
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: per, left: lp.baseAddress!, right: rp.baseAddress!) } }
                win.append(contentsOf: l); bendWin.append(Wind.strength(at: g.player.position, time: Renderer.windClock(game: g)))
                if bendWin.count == 15 { audio.append(Self.rms(win)); bend.append(bendWin.reduce(0, +) / 15); win = []; bendWin = [] }
            }
            let ma = audio.reduce(0, +) / Float(audio.count), mb = bend.reduce(0, +) / Float(bend.count)
            var sab: Float = 0, saa: Float = 0, sbb: Float = 0
            for i in 0..<audio.count { sab += (audio[i] - ma) * (bend[i] - mb); saa += (audio[i] - ma) * (audio[i] - ma); sbb += (bend[i] - mb) * (bend[i] - mb) }
            let corr = sab / max((saa * sbb).squareRoot(), 1e-9)
            check(corr > 0.8, "the wind you hear and the grass's bend at your feet are one wind: correlation \(String(format: "%.2f", corr)) over a minute of play (above 0.8; same Wind.strength, same game clock)")
        }
        // The shader and the Swift wind are one definition: the Metal source is generated from the same constants, the grass, the trees and the sky use it, and a
        // tree's packed sway weight survives the round trip through position.w.
        let msl = ShaderLibrary.sources.joined(separator: "\n")
        check(msl.contains(Wind.mslSource) && msl.contains("wind_strength(float3(xz.x, y, xz.y), time)") && msl.contains("tree_sway(wp.xyz, vertex_sway(") && msl.contains("WIND_DIR * (t * 0.0037)"),
              "the Metal wind is generated from Wind's constants and used by the grass (per blade), the trees (main and shadow passes) and the clouds")
        func encode(_ stagger: Float, _ q: Float) -> Float { 3 + stagger + 4 * (q * 7).rounded() }
        func decode(_ w: Float) -> (Float, Float) { (w > 1.5 ? (w - 2) - 4 * floor((w - 2) / 4) - 1 : 0, w > 1.5 ? floor((w - 2) / 4) / 7 : 0) }
        var roundTrip = true
        for st: Float in stride(from: -1, through: 1, by: 0.25) { for k in 0...7 { let (s2, q2) = decode(encode(st, Float(k) / 7)); if abs(s2 - st) > 1e-4 || abs(q2 - Float(k) / 7) > 1e-4 { roundTrip = false } } }
        check(roundTrip && decode(1).1 == 0 && decode(1).0 == 0, "a tree vertex's LOD stagger and sway weight survive being packed into position.w (and ordinary vertices read 0, 0)")
        check(abs(Wind.grassSway / Wind.grassSwayWas - 2.5) < 0.05 && Wind.treeBreeze >= 0.12, "the grass sways 2.5 times as far as before F03 (\(Wind.grassSwayWas) -> \(Wind.grassSway) of its height) and the conifer crowns carry a continuous breeze sway (\(Wind.treeBreeze) m at the top), so the visuals read as the breeze the audio implies")
        let src2 = ShaderLibrary.sources.joined(separator: "\n")
        check(src2.contains("WIND_GRASS_SWAY * wave") && src2.contains("WIND_TREE_BREEZE"), "the shaders use those constants")
        // The gust is the shared one and has the shape the plan asks for.
        var gl: Float = 1, gh: Float = 0
        for k in 0..<12_000 { let v = Wind.gust(time: Float(k) * 0.05); gl = min(gl, v); gh = max(gh, v) }
        // F03 #48 (R3, "the entire grassy area blinks as I pass"): the whole meadow leaned and sprang back together. Two bounds: how fast any blade's lean can change, and that
        // neighbouring patches of grass are NOT in step (same gust, different phase).
        var maxRate: Float = 0
        let probe = SIMD3<Float>(-14.5, 9.1, 105.9)
        var prevS = Wind.strength(at: probe, time: 0)
        for k in 1..<12_000 { let v = Wind.strength(at: probe, time: Float(k) * 0.05); maxRate = max(maxRate, abs(v - prevS) / 0.05); prevS = v }
        check(Wind.grassLean * maxRate <= 0.30, "a blade's lean changes by at most 0.30 of its height per second (\(String(format: "%.2f", Wind.grassLean * maxRate)); it was 0.9 x 0.65 before F03)")
        var diff: Float = 0, n: Float = 0
        for k in 0..<2400 { let t = Float(k) * 0.25; for d: Float in [10, 20, 30] {
            diff += abs(Wind.strength(at: probe, time: t) - Wind.strength(at: probe + SIMD3(-0.5, 0, 0.86) * d, time: t)); n += 1 } }
        check(diff / n > 0.06, "grass 10 to 30 m apart across the wind is not in step: mean difference in gust strength \(String(format: "%.3f", diff / n)) (a flat front gave 0.00 at 0 m offset and a regular beat otherwise)")
        check(gl < 0.03 && gh > 0.9, "the shared gust really lulls and really gusts (range \(String(format: "%.3f", gl)) ... \(String(format: "%.3f", gh)) over ten minutes)")
    }
}
