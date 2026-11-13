import Foundation
import Metal
import simd

/// F09.4 (#91: "the wind sounds like a strange sine wave of distortion rather than the sonic manifestation of air moving. Ground it in the properties of the physical thing it represents").
/// The F03 wind put 89 % of its power under 300 Hz (centroid 149 Hz): a low hum that a laptop's speakers cannot reproduce and distort, which is what a sine wave of distortion sounds like.
/// Real wind is turbulence: broadband, about 1/f, with the energy where ears and speakers work, gusts that are irregular rather than a regular swell, and resonance only where an object makes one.
extension SelfTestRunner {
    /// A-weighted level (linear RMS) of each one-second chunk of `x`, from the 40 Hz-grid power spectrum (so it measures loudness, not just RMS: a low hum counts for little, a mid-band rush for a lot).
    static func aWeightedLevels(_ x: [Float], sampleRate sr: Float) -> [Float] {
        func aGain(_ f: Float) -> Float {
            let f2 = f * f
            let num = 12194 * 12194 * f2 * f2
            let den = (f2 + 20.6 * 20.6) * ((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)).squareRoot() * (f2 + 12194 * 12194)
            return num / den * 1.2589       // +2 dB: 1 kHz is 0 dB
        }
        let n = Int(sr)
        return stride(from: 0, to: x.count - n, by: n).map { k in
            let spec = FootstepAnalysis.spectrum(Array(x[k..<k + n]))
            var p: Float = 0
            for (i, v) in spec.enumerated() { let f = Float(i + 1) * 40; let g = aGain(f); p += v * g * g }
            return (p * 40 / sr * 2).squareRoot()
        }
    }

    /// A render of the wind voice alone, driven by `source` (a function of the synth's clock), with a lee `shelter` and foliage `vegetation`.
    static func renderWindVoice(source: @escaping (Float) -> Float, seconds: Float, sampleRate sr: Float = 22050, shelter: Float = 0, vegetation: Float = 0, start: Double = 0) -> [Float] {
        let s = AmbienceSynth(sampleRate: sr)
        s.windGain = 1; s.surfGain = 0; s.master = 1; s.vegetation = vegetation; s.windShelter = shelter
        s.windSource = source
        s.setClock(seconds: start)
        var out: [Float] = []
        let block = 2048
        var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
        for _ in 0..<Int(seconds * sr) / block {
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: block, left: lp.baseAddress!, right: rp.baseAddress!) } }
            for k in 0..<block { out.append(0.5 * (l[k] + r[k])) }
        }
        return out
    }

    func runWindVoice() {
        guard name == "all" || name == "windvoice" else { return }
        typealias A = FootstepAnalysis
        let sr: Float = 22050
        let summit = SIMD3<Float>(Layout.summitStone.x, Layout.summitStone.y, Layout.summitStone.z)
        // 1. Loudness is held where F03 put it (A-weighted at the summit: lull -62 dB, gust -38 dB re 1.0), now that the energy has moved up to where ears and speakers work.
        let x = Self.renderWind(at: summit, seconds: 150, sampleRate: sr)
        let a = Self.aWeightedLevels(x, sampleRate: sr)
        let lullDB = 20 * log10(max(a.min()!, 1e-9)), gustDB = 20 * log10(max(a.max()!, 1e-9))
        if name == "windvoice" { print(String(format: "windvoice: A-weighted at the summit: lull %.2f dB, gust %.2f dB (re 1.0; F03 was -61.9 and -37.9)", lullDB, gustDB)) }
        check(abs(lullDB + 61.9) < 3 && abs(gustDB + 37.9) < 3, "windvoice: the wind is as loud as before F09.4 by the A-weighted measure (lull \(String(format: "%.1f", lullDB)) dB against -61.9, gust \(String(format: "%.1f", gustDB)) dB against -37.9; within 3 dB)")
        // 2. Where the energy is: in the band a speaker reproduces, none in the sub-bass hum.
        let chunks = stride(from: 0, to: x.count - Int(sr), by: Int(sr)).map { Array(x[$0..<$0 + Int(sr)]) }
        let specs = chunks.prefix(100).map { A.spectrum($0) }
        let total = A.mean(specs.map { A.band($0, 20, 9000) })
        let sub = A.mean(specs.map { A.band($0, 20, 90) }) / max(total, 1e-12), speaker = A.mean(specs.map { A.band($0, 120, 2000) }) / max(total, 1e-12)
        check(sub < 0.03 && speaker > 0.8, "windvoice: nothing sits where a laptop's speakers distort: under 90 Hz holds \(String(format: "%.1f", 100 * sub)) % of the power (F03: most of it) and 120 Hz-2 kHz holds \(String(format: "%.0f", 100 * speaker)) %")
        // 3. Turbulence, not a tone: at a CONSTANT wind the spectrum falls smoothly (about equal energy per octave through the body: within 6 dB across 125-500 Hz) and no one-third-octave
        // band stands more than 10 dB over the mean of its two neighbours; and the level flutters (50 ms RMS varies by 15-80 %), which a sine or a steady hiss does not.
        let steady = Self.renderWindVoice(source: { _ in 0.5 }, seconds: 60, sampleRate: sr)
        let sp = stride(from: 0, to: steady.count - Int(sr), by: Int(sr)).map { A.spectrum(Array(steady[$0..<$0 + Int(sr)])) }
        let oct = [(125 as Float, 250 as Float), (250, 500), (500, 1000)].map { lo, hi in 10 * log10(A.mean(sp.map { A.band($0, lo, hi) })) }
        var thirds: [Float] = []
        var fc: Float = 100; while fc <= 1600 { thirds.append(A.mean(sp.map { A.band($0, fc / pow(2, 1.0 / 6), fc * pow(2, 1.0 / 6)) })); fc *= pow(2, 1.0 / 3) }
        var worstPeak: Float = -99
        for i in 1..<(thirds.count - 1) { worstPeak = max(worstPeak, 10 * log10(thirds[i] / max((thirds[i - 1] + thirds[i + 1]) / 2, 1e-12))) }
        let win = Int(sr * 0.05)
        let env50 = stride(from: 0, to: steady.count - win, by: win).map { k in (steady[k..<k + win].reduce(0) { $0 + $1 * $1 } / Float(win)).squareRoot() }
        let mEnv = A.mean(env50), cv = (env50.reduce(0) { $0 + ($1 - mEnv) * ($1 - mEnv) } / Float(env50.count)).squareRoot() / mEnv
        if name == "windvoice" { print("windvoice: octaves 125-250/250-500/500-1000 Hz \(oct) dB, worst third-octave peak over its neighbours \(worstPeak) dB, 50 ms envelope variation \(cv)") }
        check((oct.max()! - oct.min()!) < 6, "windvoice: about equal energy per octave through the body (125-500 Hz, 500-1000 Hz within 6 dB: \(oct.map { String(format: "%.1f", $0) }) dB)")
        check(worstPeak < 10, "windvoice: no band stands out: the worst one-third-octave band from 100 Hz to 1.6 kHz is \(String(format: "%.1f", worstPeak)) dB over the mean of its neighbours (the limit is 10 dB)")
        check(cv > 0.15 && cv < 0.8, "windvoice: at a steady wind the level still flutters like turbulence: the 50 ms RMS varies by \(String(format: "%.0f", 100 * cv)) % (15-80 %)")
        // 4. Hills shelter: open ground and a summit are not in a lee; behind a 20 m ridge 25 m upwind is. In the lee the wind is quieter and darker.
        let flat: (Float, Float) -> Float = { _, _ in 10 }
        let up = -Wind.direction
        let ridge: (Float, Float) -> Float = { px, pz in
            let along = (px - 100) * up.x + (pz - 100) * up.y                       // metres upwind of the listener at (100, 100)
            return 10 + (along > 18 && along < 40 ? 22 : 0)
        }
        let open = AudioSpace.windShelter(at: SIMD3(100, 10, 100), ground: flat), lee = AudioSpace.windShelter(at: SIMD3(100, 10, 100), ground: ridge)
        check(open < 0.05 && lee > 0.8, "windvoice: open ground gives no shelter (\(String(format: "%.2f", open))) and the lee of a 22 m ridge 18-40 m upwind gives nearly full shelter (\(String(format: "%.2f", lee)))")
        let exposed = Self.renderWindVoice(source: { _ in 0.5 }, seconds: 30, sampleRate: sr), sheltered = Self.renderWindVoice(source: { _ in 0.5 }, seconds: 30, sampleRate: sr, shelter: 1)
        let cE = A.mean(stride(from: 0, to: exposed.count - Int(sr), by: Int(sr)).map { A.centroid(A.spectrum(Array(exposed[$0..<$0 + Int(sr)]))) })
        let cS = A.mean(stride(from: 0, to: sheltered.count - Int(sr), by: Int(sr)).map { A.centroid(A.spectrum(Array(sheltered[$0..<$0 + Int(sr)]))) })
        let drop = 20 * log10(Self.rms(exposed) / max(Self.rms(sheltered), 1e-9))
        check(drop > 3 && cS < cE, "windvoice: in a lee the wind is \(String(format: "%.1f", drop)) dB quieter and darker (centroid \(Int(cE)) Hz down to \(Int(cS)) Hz)")
        // 5. Foliage: leaves hiss where there are trees; a stone or the tower is not a tree.
        func trunk(_ i: Int) -> CylinderCollider { CylinderCollider(center: SIMD2(100 + Float(i % 5) * 2.0, 100 + Float(i / 5) * 2.0), radius: 0.4, minY: 0, maxY: 12) }
        let wood = (0..<10).map(trunk), stones = [CylinderCollider(center: SIMD2(101, 101), radius: 1.6, minY: 0, maxY: 2.4), CylinderCollider(center: SIMD2(100, 100), radius: 4.65, minY: 0, maxY: 30)]
        let here = SIMD3<Float>(103, 10, 103)
        check(AudioSpace.treeCover(at: here, colliders: wood) > 0.99 && AudioSpace.treeCover(at: here, colliders: stones) == 0 && AudioSpace.treeCover(at: SIMD3(300, 10, 300), colliders: wood) == 0, "windvoice: tree cover counts trunks within 14 m (ten trunks make a wood; a standing stone or the tower does not; none from 200 m away)")
        func rustle(_ veg: Float) -> Float { let r = Self.renderWindVoice(source: { _ in 0.6 }, seconds: 30, sampleRate: sr, vegetation: veg); return A.mean(stride(from: 0, to: r.count - Int(sr), by: Int(sr)).map { A.band(A.spectrum(Array(r[$0..<$0 + Int(sr)])), 1200, 3500) }) }
        let bare = rustle(0), leafy = rustle(0.8)
        check(leafy > bare * 1.5, "windvoice: foliage underfoot or near makes the leaves hiss (1.2-3.5 kHz power \(String(format: "%.2e", bare)) bare, \(String(format: "%.2e", leafy)) in leaf)")
        // 6. The clock: the same at minute ten and later (the turbulence and the corner are not tied to the absolute time).
        let late = Self.renderWindVoice(source: { _ in 0.5 }, seconds: 20, sampleRate: sr, start: 5000)
        check(abs(20 * log10(Self.rms(late) / Self.rms(Array(steady.prefix(late.count))))) < 2, "windvoice: the level at 5000 s equals the level at the start (within 2 dB)")
    }
}
