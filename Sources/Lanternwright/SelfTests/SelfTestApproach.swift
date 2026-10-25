import Foundation
import Metal
import simd

/// Self-tests: continuous detail (R09), measured with the same `--approach` walk the command line uses (at a small render size so it is fast).
/// A pop shows as a step where the crop's mean luma jumps, where its high-frequency energy jumps, or where one step's pixels differ far more
/// than the typical step. These bounds are set from the measured after-R09 runs (docs/TASKS.md T63.5) with some margin: they are guards against
/// regressions (a hard LOD swap, a grass ring, a feature that fades to zero instead of to its mean), not proofs of perfection.
extension SelfTestRunner {
    func runApproach() {
        guard name == "all" || name == "approach" else { return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        let w = 800, h = 450
        func run(_ target: String, start: Float? = nil, minD: Float? = nil, factor: Float = 0.85) -> Approach.Result? {
            guard var t = Approach.target(target, renderer: renderer) else { return nil }
            if let start { t.start = start }
            return Approach.run(t, renderer: renderer, width: w, height: h, factor: factor, minDistance: minD ?? t.minDistance)
        }
        // Tree LOD bands: walking through the 45 m switch (conifer) and the Glass Wood's (crystal tree). The dither spreads the change over several steps.
        for target in ["conifer", "crystal-tree"] {
            if let r = run(target, start: 80, minD: 30, factor: 0.96) {
                check(r.maxLumaStep < 0.06, "\(target): no brightness jump through the LOD band (largest step \(r.maxLumaStep * 100) %)")
                check(r.diffSpike < 3.0, "\(target): no single step differs far more than the rest through the LOD band (spike \(r.diffSpike))")
            } else { check(false, "\(target): approach target exists") }
        }
        // Ground and surfaces: no brightness jump, and detail grows (energy does not collapse) as you approach.
        for (target, lumaBound, ratioBound) in [("meadow", Float(0.10), Float(2.6)), ("sand", 0.06, 2.2), ("path", 0.10, 2.2), ("gw-grass", 0.07, 2.6)] {
            if let r = run(target, start: target == "path" ? 50 : 120, minD: 3) {
                check(r.maxLumaStep < lumaBound, "\(target): mean brightness changes smoothly (largest step \(r.maxLumaStep * 100) %)")
                check(r.maxHFRatio < ratioBound, "\(target): detail arrives gradually, no step multiplies the high-frequency energy (largest ratio \(r.maxHFRatio))")
            } else { check(false, "\(target): approach target exists") }
        }
        // The meadow's grass has no hard outer ring: past its radius the ground carries the grain, so the last metres of the fade do not jump.
        if let r = run("meadow", start: 70, minD: 30, factor: 0.93) {
            check(r.maxHFRatio < 1.7, "the meadow's grass radius is not visible as a ring (largest step ratio \(r.maxHFRatio) across 70 to 30 m)")
        }
        // Every target resolves.
        check(Approach.names.allSatisfy { Approach.target($0, renderer: renderer) != nil }, "all \(Approach.names.count) approach targets resolve")
    }
}

/// Self-tests: the world obeys a pinhole camera (F02 R2). Walk 20 m toward the island from the place the user reported (-39, 140): the renderer's depth must agree with the
/// pinhole prediction frame to frame, and every level of detail of a tree must be the size of the near one (the far cone used to be half the width: the "jump back").
extension SelfTestRunner {
    func runParallax() {
        guard name == "all" || name == "parallax" else { return }
        // The three levels of a tree are one size (before: pine LOD2 was 2.1 m wide against 4.3 m, LOD1 20 % too wide).
        var worstRad: Float = 0, worstMid: Float = 0, worstTop: Float = 0
        for style in [Trees.Style.pine, .cypress] {
            for v in 0..<Trees.variantCount {
                let s0 = Trees.silhouette(Trees.variant(style, v, lod: 0))
                for lod in 1...2 {
                    let s = Trees.silhouette(Trees.variant(style, v, lod: lod))
                    worstRad = max(worstRad, abs(s.rad / s0.rad - 1)); worstMid = max(worstMid, abs(s.mid / s0.mid - 1)); worstTop = max(worstTop, abs(s.top / s0.top - 1))
                }
            }
        }
        check(worstRad < 0.30 && worstMid < 0.30 && worstTop < 0.04, "every tree LOD has the size of the full tree, so a level swap is not a change of size (largest differences: widest radius \(Int(worstRad * 100)) %, half-height radius \(Int(worstMid * 100)) %, height \(Int(worstTop * 100)) %; before the fix about 55 %, 60 % and 6 %)")
        // The depth walk.
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        guard let pairs = try? Parallax.run(renderer: renderer, width: 800, height: 450, steps: 40, step: 0.5, quiet: true) else { check(false, "the parallax walk renders"); return }
        var farErrs: [Float] = [], farBad = 0, nearErrs: [Float] = []
        for p in pairs { for i in 1..<Parallax.bands.count { farErrs += p.perBand[i].errs }; nearErrs += p.perBand[0].errs; farBad += p.bad.filter { $0.d > 60 }.count }
        farErrs.sort(); nearErrs.sort()
        let med = { (v: [Float]) in v.isEmpty ? 0 : v[v.count / 2] }
        check(med(nearErrs) < 0.05 && med(farErrs) < 0.1, "static geometry is drawn where a pinhole camera says it is: median depth disagreement frame to frame \(String(format: "%.3f", med(nearErrs))) m (15-60 m) and \(String(format: "%.3f", med(farErrs))) m (beyond 60 m)")
        check(Float(farBad) < 0.01 * Float(max(farErrs.count, 1)), "beyond 60 m fewer than 1 % of the samples are off by over half a metre (\(farBad) of \(farErrs.count)): nothing far away changes position or shape between steps")
    }
}
