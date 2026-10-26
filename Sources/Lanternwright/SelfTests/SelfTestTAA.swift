import Foundation
import Metal
import simd

/// Self-tests: temporal anti-aliasing (F02 R1, user note #23). Crawl and detail are measured with the same tool as `--shimmer`; ghosting with a fast turn and with the
/// rotating lighthouse beam; and the plumbing (jitter, unjittered headless frames, history reset on a world change).
extension SelfTestRunner {
    func runTAA() {
        guard name == "all" || name == "taa" else { return }
        // Jitter: eight distinct, centred sub-pixel offsets.
        let offs = (0..<8).map { Renderer.jitterOffset(frame: $0) }
        let mean = offs.reduce(SIMD2<Float>(0, 0), +) / 8
        check(Set(offs.map { "\($0.x),\($0.y)" }).count == 8 && offs.allSatisfy { abs($0.x) < 0.5 && abs($0.y) < 0.5 } && abs(mean.x) < 0.1 && abs(mean.y) < 0.1 && Renderer.jitterOffset(frame: 3) == Renderer.jitterOffset(frame: 11),
              "TAA jitter: eight distinct offsets inside the pixel, centred (mean \(mean)), repeating every 8 frames")
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        let w = 480, h = 270
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        let target = device.makeTexture(descriptor: desc)!
        renderer.fixedTime = 12
        func frame(_ cam: Camera, taa: Bool, time: Float = 12) -> [Float] {
            renderer.taaEnabled = taa; renderer.fixedTime = time
            let cb = renderer.queue.makeCommandBuffer()!
            renderer.encode(commandBuffer: cb, target: target, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            return Shimmer.luma(target)
        }
        func mse(_ a: [Float], _ b: [Float], where keep: ((Int) -> Bool)? = nil) -> Float {
            var s: Double = 0, n = 0
            for i in 0..<a.count where keep?(i) ?? true { let d = a[i] - b[i]; s += Double(d * d); n += 1 }
            return Float(s / Double(max(n, 1)))
        }
        // Headless frames are unjittered by default (existing baselines stay comparable): two renders of the same camera are identical; with TAA on, successive frames differ (jitter).
        let cam0 = Screenshot.viewCamera("shore", renderer: renderer)
        _ = frame(cam0, taa: false); _ = frame(cam0, taa: false)                // the first frames settle the sky LUT
        let a = frame(cam0, taa: false), b = frame(cam0, taa: false)
        check(a == b, "without --taa a headless frame is exactly reproducible (no jitter, no history)")
        renderer.resetTAA()
        let t1 = frame(cam0, taa: true), t2 = frame(cam0, taa: true)
        check(t1 != t2, "with TAA on, successive frames are jittered and blended (they differ)")
        // Crawl and detail (the --shimmer measurement) on the scenes where fine detail lives.
        var offs2: Float = 0, ons: Float = 0
        for sc in Shimmer.scenes where ["turf", "cobbles", "masonry", "grass"].contains(sc.name) {
            if let r = try? Shimmer.measure(renderer: renderer, scene: sc, motion: .pan, width: w, height: h, frames: 14, warmup: 10) {
                offs2 += r.off.flicker; ons += r.on.flicker
                if name == "taa" { print(String(format: "  %@ pan: crawl %.3f -> %.3f (%.1f %% lower), detail vs the ideal image: off %.0f %% on %.0f %%", sc.name, r.off.flicker, r.on.flicker, r.reduction * 100, r.detailOff * 100, r.detailOn * 100)) }
                check(r.reduction >= 0.6, "TAA (\(sc.name), panning): crawl at least 60 % lower (\(String(format: "%.1f", r.reduction * 100)) %)")
                if sc.name == "masonry" || sc.name == "grass" { check(r.detailOn >= 0.9, "TAA keeps the fine detail of \(sc.name): \(Int(r.detailOn * 100)) % of the ideal (3x3 supersampled) image's (the un-filtered frame has \(Int(r.detailOff * 100)) %, aliasing noise included)") }
            } else { check(false, "the shimmer measurement ran for \(sc.name)") }
        }
        check(offs2 > 0 && 1 - ons / offs2 >= 0.6, "TAA: total crawl across turf, cobbles, masonry and grass at least 60 % lower (\(String(format: "%.1f", (1 - ons / max(offs2, 1e-9)) * 100)) %)")
        // Ghosting, fast turn: 3 degrees per frame (180 degrees a second at 60 fps); the TAA frame must stay close to the un-filtered frame of the same camera,
        // as close as it is when the camera is still (plus a margin), not smeared with the last few frames.
        func ghost(view: String, yawPerFrame: Float, frames: Int = 16) -> Float {
            let base = Screenshot.viewCamera(view, renderer: renderer)
            renderer.resetTAA()
            var worst: Float = 0
            for k in 0..<frames {
                var c = base; c.yaw += yawPerFrame * Float(k)
                let on = frame(c, taa: true), off = frame(c, taa: false)
                if k >= frames - 4 { worst = max(worst, mse(on, off)) }
            }
            return worst
        }
        let still = ghost(view: "shore", yawPerFrame: 0), fast = ghost(view: "shore", yawPerFrame: 0.052), fastDock = ghost(view: "dock", yawPerFrame: 0.052)
        if name == "taa" { print(String(format: "  ghosting (mse of the TAA frame against the un-filtered one): still %.1f, fast turn at the shore %.1f, at the dock %.1f", still, fast, fastDock)) }
        check(fast < 3 * still + 40 && fastDock < 3 * still + 60, "no ghosting on a fast turn: the TAA frame stays close to the un-filtered one (still \(String(format: "%.1f", still)), turning 180 deg/s: shore \(String(format: "%.1f", fast)), dock \(String(format: "%.1f", fastDock)))")
        // Ghosting, the rotating beam: a static camera, the clock running (the beam sweeps visibly between frames). The beam is drawn after the temporal resolve, so it must not
        // trail or dim: on the pixels the beam covers, the TAA frame must be as close to the true (un-filtered) frame as it is on those same pixels with no beam at all.
        do {
            let cam = Screenshot.viewCamera("dock", renderer: renderer)
            func run(beam: Float) -> (on: [[Float]], off: [[Float]]) {
                renderer.beamIntensity = beam; renderer.resetTAA()
                var on: [[Float]] = [], off: [[Float]] = []
                for k in 0..<24 {
                    let t = 12 + Float(k) * 0.1
                    on.append(frame(cam, taa: true, time: t)); off.append(frame(cam, taa: false, time: t))
                }
                return (on, off)
            }
            let with = run(beam: 1), without = run(beam: 0)
            renderer.beamIntensity = 0
            var withErr: Float = 0, withoutErr: Float = 0, covered = 0
            for k in 18..<24 {
                let mask: (Int) -> Bool = { abs(with.off[k][$0] - without.off[k][$0]) > 8 }
                covered += (0..<(w * h)).filter(mask).count
                withErr = max(withErr, mse(with.on[k], with.off[k], where: mask)); withoutErr = max(withoutErr, mse(without.on[k], without.off[k], where: mask))
            }
            if name == "taa" { print(String(format: "  beam: %d covered pixels; TAA frame against the true frame on them: with the beam %.1f, with no beam %.1f", covered, withErr, withoutErr)) }
            check(covered > 200 && withErr < withoutErr + 25, "no trail or dimming on the rotating beam: on the \(covered / 6) pixels it covers, the TAA frame is as close to the true frame as without the beam (mse \(String(format: "%.1f", withErr)) vs \(String(format: "%.1f", withoutErr)))")
        }
        // F02 T66.13: converged TAA frames of the needle foliage must be steady. A clean resolve of a still camera changes very little from one frame to the next; plain
        // dither stipple (stochastic alpha that the temporal blend cannot average out) shows as frame-to-frame change. Compared at 5 m, 8 m and 11 m from the foliage edge.
        // (The same measurement with NO_NEEDLES=1, i.e. the old sprays alone, is 6.94 / 9.18 / 6.69: the remaining noise is the R09 dither and the grass, and the needles must add none.)
        for (label, view, bound) in [("5 m", "tree-needle-5m", Float(7.5)), ("8 m", "tree-at-10", Float(9.7)), ("11 m", "tree-at-13", Float(7.3))] {
            let cam = Screenshot.viewCamera(view, renderer: renderer)
            renderer.resetTAA()
            var last: [Float] = [], prev: [Float] = []
            for _ in 0..<22 { prev = last; last = frame(cam, taa: true) }
            let change = mse(last, prev)
            if name == "taa" { print(String(format: "  needle foliage steadiness (%@): frame-to-frame mse of the converged TAA frame %.2f", label, change)) }
            check(change < bound, "TAA: the needle foliage adds no shimmer at \(label) (converged frame-to-frame mse \(String(format: "%.2f", change)), under \(bound); the old sprays alone measure about the same)")
        }
        // A world change is a camera cut: the first frame in the new world must not carry the old world's history. Compare it with a frame rendered with no history at all.
        do {
            renderer.world = .varrow; renderer.resetTAA()
            let c1 = Screenshot.viewCamera("shore", renderer: renderer)
            for _ in 0..<10 { _ = frame(c1, taa: true) }
            renderer.world = .glassWood
            let c2 = Screenshot.viewCamera("gw-arrival", renderer: renderer)
            let after = frame(c2, taa: true)                          // the first frame after the change (the renderer resets its history itself)
            renderer.resetTAA()
            let noHistory = frame(c2, taa: true)                      // a frame with the history reset by hand
            let truth = frame(c2, taa: false)
            check(mse(after, truth) < 1.6 * mse(noHistory, truth) + 5, "after a world change the first frame has no trace of the old world (mse against the truth \(String(format: "%.1f", mse(after, truth))); with no history at all \(String(format: "%.1f", mse(noHistory, truth))))")
            renderer.world = .varrow
        }
        renderer.taaEnabled = false
    }
}
