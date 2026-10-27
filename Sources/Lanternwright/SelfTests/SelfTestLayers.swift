import Foundation
import Metal
import simd

/// Self-tests: the layer switches and the reproducible moving walk behind the shimmer attribution (G10.0.2).
extension SelfTestRunner {
    func runLayers() {
        guard name == "all" || name == "layers" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "layers: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        let w = 320, h = 180
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "layers: no target"); return }
        let scene = Shimmer.movingScenes.first { $0.name == "woods" }!
        func lumas(_ f: Shimmer.Frames) -> [[Float]] { f.map(\.y) }
        let flagsBefore = renderer.scenes[.varrow]!.hiddenFlags
        do {
            let a = try Shimmer.walk(renderer: renderer, scene: scene, off: [], moving: true, width: w, height: h, frames: 4, target: tex, warmup: 3)
            let b = try Shimmer.walk(renderer: renderer, scene: scene, off: [], moving: true, width: w, height: h, frames: 4, target: tex, warmup: 3)
            check(lumas(a) == lumas(b), "layers: two identical moving walks are bit-identical (exposure fixed, TAA state and jitter reset), so a difference between walks is the layer's")
            let noTrees = try Shimmer.walk(renderer: renderer, scene: scene, off: [.trees], moving: true, width: w, height: h, frames: 4, target: tex, warmup: 3)
            var changed = 0, total = 0
            for k in a.indices { for i in a[k].y.indices { total += 1; if abs(a[k].y[i] - noTrees[k].y[i]) > Shimmer.ownThreshold { changed += 1 } } }
            check(Float(changed) / Float(total) > 0.05, "layers: switching the trees off in the woods changes a real share of the frame (\(Int(100 * Float(changed) / Float(total))) % of pixels by more than \(Int(Shimmer.ownThreshold)) / 255)")
            let noGrassAndSky = try Shimmer.walk(renderer: renderer, scene: scene, off: [.grass, .sky, .shadows, .water, .props], moving: true, width: w, height: h, frames: 4, target: tex, warmup: 3)
            check(lumas(noGrassAndSky) != lumas(a), "layers: the other switches (grass, sky, shadows, water, props) change the frame too")
            check(RenderLayer.off.isEmpty && renderer.scenes[.varrow]!.hiddenFlags == flagsBefore, "layers: after a walk every layer is back on and every item's hidden flag is as it was")
            let c = try Shimmer.walk(renderer: renderer, scene: scene, off: [], moving: true, width: w, height: h, frames: 4, target: tex, warmup: 3)
            check(lumas(a) == lumas(c), "layers: a walk after the switched-off ones is identical to the first (nothing was left off)")
        } catch { check(false, "layers: walk failed: \(error)") }
        check(RenderLayer.parse("grass, trees") == [.grass, .trees] && RenderLayer.parse("grass,bogus") == nil, "layers: --layers-off parses a comma list and rejects an unknown name")
    }

    /// G10.0.3: the banding probe finds smooth sky, counts levels, and gives the same numbers twice.
    func runBanding() {
        guard name == "all" || name == "banding" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "banding: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        do {
            let v = Banding.views()[0]
            let a = try Banding.measure(renderer: renderer, view: v, width: 640, height: 360)
            let b = try Banding.measure(renderer: renderer, view: v, width: 640, height: 360)
            let g = a.channels["green"]!
            check(a.columns >= 10 && a.rows > 40 && g.fill > 0.3 && g.longestRun >= 1 && g.flat >= 0 && g.flat <= 1 && abs(g.steps.reduce(0, +) - 1) < 1e-4, "banding: the probe finds sky strips (\(a.columns) columns, up to \(a.rows) rows), green: longest run \(g.longestRun), flat \(Int(g.flat * 100)) %, fill \(String(format: "%.2f", g.fill))")
            check(a.channels.mapValues { [$0.longestRun, Int($0.flat * 1e4), Int($0.fill * 1e4)] } == b.channels.mapValues { [$0.longestRun, Int($0.flat * 1e4), Int($0.fill * 1e4)] }, "banding: the probe gives the same numbers twice (reproducible)")
            // The control: a slow ramp (one level per 150 rows, as in the high dusk sky) quantised plainly, and the same ramp with triangular +-1 LSB noise before quantising. The headline numbers must move the right way.
            var rng = FoleyNoise(seed: 7)
            let rows = 900, slope: Float = 1.0 / 150
            let plain = (0..<20).map { _ in (0..<rows).map { Int((Float($0) * slope).rounded(.down)) } }
            let dithered = (0..<20).map { _ in (0..<rows).map { Int((Float($0) * slope + (rng.next() + rng.next()) * 0.5 + 0.5).rounded(.down)) } }
            let p = Banding.summarize(plain), d = Banding.summarize(dithered)
            check(p.longestRun >= 140 && p.flat > 0.95 && d.longestRun < p.longestRun / 4 && d.flat < p.flat - 0.15 && d.steps[1] > p.steps[1] && d.fill >= p.fill - 0.01,
                  "banding: the control ramp: plain quantising has runs of \(p.longestRun) rows and \(Int(p.flat * 100)) % flat; with triangular noise \(d.longestRun) rows and \(Int(d.flat * 100)) % flat, more steps of 1 (\(Int(p.steps[1] * 100)) % -> \(Int(d.steps[1] * 100)) %)")
        } catch { check(false, "banding: probe failed: \(error)") }
    }
}
