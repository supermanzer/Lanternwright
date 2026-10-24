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
