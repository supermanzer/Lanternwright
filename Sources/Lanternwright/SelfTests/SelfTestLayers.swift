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
}
