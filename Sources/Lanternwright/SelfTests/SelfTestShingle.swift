import Foundation
import Metal
import simd

/// F09.4 (#90: "the sound of walking on the shingle is odd. Like you have muddy boots on"): the lantern path is shingle, many small hard stones. Judged as numbers (nobody can hear it in a
/// test): no low-frequency thump and nothing wet, a burst of 15-40 clicks over the heel, a low crunch under it, heel then toe, and the level where the old path voice was.
/// Untested by ear: the user is the only listener.
extension SelfTestRunner {
    func runShingle() {
        guard name == "all" || name == "shingle" else { return }
        typealias A = FootstepAnalysis
        let sr = A.sr
        let r = FootstepRecipe.table[StepMaterial.shingle.rawValue]
        check(r.modes.isEmpty && r.impactHighpass >= 400 && r.grainDecaying && r.grainMin >= 15 && r.grainMax <= 40 && r.grainLenLo >= 0.001 && r.grainLenHi <= 0.003 && r.grainFreqLo >= 2000 && r.grainFreqHi <= 6000,
              "shingle: the recipe is clicks (15-40 grains of 1-3 ms, 2-6 kHz, decaying) over a band-passed crunch, with no resonant body mode (no thump, nothing wet)")
        let steps = A.render(mix: A.pure(.shingle), count: 12, seconds: 0.5)
        let old = A.render(mix: A.pure(.earth), count: 12, seconds: 0.5)
        func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot() }
        let specs = steps.map(A.spectrum)
        let total = A.mean(specs.map { A.band($0, 40, 9000) })
        let low = A.mean(specs.map { A.band($0, 40, 300) }) / max(total, 1e-12)
        let sub = A.mean(specs.map { A.band($0, 40, 160) }) / max(total, 1e-12)
        let cent = A.mean(specs.map(A.centroid))
        let hi = A.mean(specs.map { A.band($0, 2000, 6000) }) / max(total, 1e-12)
        let levelDB = 20 * log10(A.mean(steps.map(rms)) / max(A.mean(old.map(rms)), 1e-9))
        let peakDB = 20 * log10(A.mean(steps.map { $0.map { abs($0) }.max() ?? 0 }) / max(A.mean(old.map { $0.map { abs($0) }.max() ?? 0 }), 1e-9))
        let tex = A.render(mix: A.pure(.shingle), count: 12, seconds: 0.5, layers: .texture, toe: false)
        let clicks = A.mean(tex.map { Float(A.grainCount($0)) })
        if name == "shingle" { print("shingle: low(40-300) \(low) sub(40-160) \(sub) centroid \(cent) share 2-6k \(hi) level vs old path \(levelDB) dB, peak \(peakDB) dB, resolved clicks/heel \(clicks)") }
        check(sub < 0.01 && low < 0.04, "shingle: no thump: \(String(format: "%.2f", 100 * sub)) % of the energy under 160 Hz and \(String(format: "%.1f", 100 * low)) % under 300 Hz (the old path voice had a 95 Hz mode)")
        check(cent > 1800 && cent < 4500 && hi > 0.3, "shingle: the sound sits in the stones' band: centroid \(Int(cent)) Hz, \(Int(100 * hi)) % of the energy at 2-6 kHz")
        check(clicks >= 8 && clicks <= 45, "shingle: the heel is a burst of separate clicks (\(String(format: "%.0f", clicks)) resolved of 15-40 started; clicks closer than 3 ms merge)")
        // Heel, then toe: two separate bursts, the toe softer.
        let one = A.render(mix: A.pure(.shingle), count: 8, seconds: 0.4)
        let heel = A.mean(one.map { A.envelope($0, tau: 0.004)[Int(sr * 0.03)..<Int(sr * 0.07)].max() ?? 0 })
        let dip = A.mean(one.map { A.envelope($0, tau: 0.004)[Int(sr * 0.068)..<Int(sr * 0.078)].min() ?? 0 })
        let toe = A.mean(one.map { A.envelope($0, tau: 0.004)[Int(sr * 0.078)..<Int(sr * 0.14)].max() ?? 0 })
        if name == "shingle" { print("shingle: heel env \(heel) dip \(dip) toe \(toe)") }
        check(toe > 0.12 * heel && toe < heel, "shingle: walking is heel then toe (toe \(Int(100 * toe / max(heel, 1e-9))) % of the heel)")
        check(abs(levelDB) < 2.0 && peakDB < 6, "shingle: the level stays where the old path voice was: \(String(format: "%.1f", levelDB)) dB in RMS (peak \(String(format: "%.1f", peakDB)) dB, clicks are peakier than a thump), so the F07 -4 dB footstep balance holds")
        let run = A.render(mix: A.pure(.shingle), count: 8, run: true, seconds: 0.4)
        check(run.allSatisfy { $0.map { abs($0) }.max()! > 0.02 } && A.mean(run.map(rms)) > A.mean(steps.map(rms)) * 0.5, "shingle: a run is one harder, shorter contact, not silent")
        let sc = Scene.makeWorld(device: device)
        let mid = (Layout.tideStone + Layout.windStone) * 0.5
        let m = sc.surfaceMix(x: mid.x, z: mid.z).mix
        check(m[StepMaterial.shingle.rawValue] > 0.4 && m[StepMaterial.earth.rawValue] == 0, "shingle: the lantern path's step mix is shingle, not earth (\(String(format: "%.2f", m[StepMaterial.shingle.rawValue])))")
    }
}
