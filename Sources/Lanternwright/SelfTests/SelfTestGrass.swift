import Foundation
import Metal
import simd

/// Self-tests: the meadow does not blink (F03 R3, note #48: "the entire grassy area appears to blink as I pass by"). The grass's share of the frame is measured the way a
/// player would see it: the frame with grass against the same frame without, a few hundred thousand pixels, for consecutive camera positions 0.1 m apart (a third of a
/// grass cell), for consecutive clock steps at a fixed camera, and with the temporal anti-aliasing history running.
extension SelfTestRunner {
    func runGrassCoverage() {
        guard name == "all" || name == "grass" else { return }
        func coverage(_ renderer: Renderer, _ cam: Camera, size w: Int, _ h: Int, frames: Int) -> Float {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
            guard let tex = renderer.device.makeTexture(descriptor: desc) else { return 0 }
            func shot() -> [UInt8] {
                var px: [UInt8] = []
                for _ in 0..<frames {
                    guard let cb = renderer.queue.makeCommandBuffer() else { return [] }
                    renderer.encode(commandBuffer: cb, target: tex, camera: cam)
                    cb.commit(); cb.waitUntilCompleted()
                }
                px = [UInt8](repeating: 0, count: w * h * 4)
                tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                return px
            }
            Renderer.skipGrass = false
            let with = shot()
            Renderer.skipGrass = true
            let without = shot()
            Renderer.skipGrass = false
            var n = 0
            for i in stride(from: 0, to: with.count, by: 4) {
                let d = abs(Int(with[i]) - Int(without[i])) + abs(Int(with[i + 1]) - Int(without[i + 1])) + abs(Int(with[i + 2]) - Int(without[i + 2]))
                if d > 24 { n += 1 }
            }
            return Float(n) / Float(w * h)
        }
        var results: [(String, Float, Float)] = []
        for taa in [false, true] {
            let renderer = Renderer(device: device, options: LaunchOptions.parse(taa ? ["lanternwright", "--taa"] : ["lanternwright"]))
            renderer.fixedTime = 12; renderer.autoExposure = false; renderer.world = .glassWood
            let frames = taa ? 8 : 2
            // Walking: z from 105.9 in 0.1 m steps, the player's own spot in note #48 (eye = feet + 1.7).
            var cov: [Float] = []
            for k in 0..<14 { cov.append(coverage(renderer, Camera(position: SIMD3(-14.5, 10.8, 105.9 - 0.1 * Float(k)), yaw: -0.12, pitch: -0.13), size: 400, 225, frames: frames)) }
            let walk = zip(cov, cov.dropFirst()).map { abs($1 - $0) / max($0, 1e-4) }.max() ?? 0
            // Standing: the clock advances 0.1 s a step (the gusts and the sway move; the set of blades must not).
            var cov2: [Float] = []
            for k in 0..<14 { renderer.fixedTime = 30 + 0.1 * Float(k); cov2.append(coverage(renderer, Camera(position: SIMD3(-14.5, 10.8, 105.9), yaw: -0.12, pitch: -0.13), size: 400, 225, frames: frames)) }
            renderer.fixedTime = 12
            let stand = zip(cov2, cov2.dropFirst()).map { abs($1 - $0) / max($0, 1e-4) }.max() ?? 0
            results.append((taa ? "TAA on" : "TAA off", walk, stand))
            if name == "grass" { print("grass coverage (\(taa ? "TAA on" : "TAA off")): walking \(cov.map { String(format: "%.3f", $0) }) max step \(String(format: "%.1f", walk * 100)) %; standing \(cov2.map { String(format: "%.3f", $0) }) max step \(String(format: "%.1f", stand * 100)) %") }
            check((cov + cov2).allSatisfy { $0 > 0.10 }, "the grass is in the frame (share of pixels \(String(format: "%.2f", cov.min() ?? 0)) to \(String(format: "%.2f", cov.max() ?? 0)), \(taa ? "TAA on" : "TAA off"))")
        }
        for (label, walk, stand) in results {
            // A 0.1 m step changes the projected size of the nearest blades by itself (about 5-7 % of the coverage); a blink would be a jump far beyond that. Measured: walking 6.5 / 7.0 %, standing 2.3 / 4.7 %.
            check(walk <= 0.09 && stand <= 0.06, "\(label): the grass's share of the frame changes by at most 9 % between frames walking 0.1 m a step (\(String(format: "%.1f", walk * 100)) %, the perspective change of the nearest blades) and at most 6 % standing with the clock moving 0.1 s a step (\(String(format: "%.1f", stand * 100)) %)")
        }
    }

    /// Walking with the temporal history running: one frame per 0.1 m (about 6 m/s at 60 fps), the history carried from frame to frame as in play. Prints the mean luma of the
    /// lower half of each frame and the roughness of that series (RMS of its second difference): a blink is a series that jumps, not one that drifts.
    func runGrassWalk() {
        guard name == "all" || name == "grass" || name == "grasswalk" else { return }
        for taa in [false, true] {
            let renderer = Renderer(device: device, options: LaunchOptions.parse(taa ? ["lanternwright", "--taa"] : ["lanternwright"]))
            renderer.fixedTime = 12; renderer.autoExposure = false; renderer.world = .glassWood
            let w = 400, h = 225
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
            guard let tex = renderer.device.makeTexture(descriptor: desc) else { return }
            var series: [Float] = []
            for k in 0..<60 {
                renderer.fixedTime = 12 + Float(k) / 60
                let cam = Camera(position: SIMD3(-14.5, 10.8, 105.9 - 0.1 * Float(k)), yaw: -0.12, pitch: -0.13)
                guard let cb = renderer.queue.makeCommandBuffer() else { return }
                renderer.encode(commandBuffer: cb, target: tex, camera: cam)
                cb.commit(); cb.waitUntilCompleted()
                var px = [UInt8](repeating: 0, count: w * h * 4)
                tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                var sum: Float = 0
                for y in (h / 2)..<h { for x in 0..<w { let i = (y * w + x) * 4; sum += 0.2126 * Float(px[i + 2]) + 0.7152 * Float(px[i + 1]) + 0.0722 * Float(px[i]) } }
                series.append(sum / Float(w * h / 2))
            }
            var rough: Float = 0
            for k in 2..<series.count { let d = series[k] - 2 * series[k - 1] + series[k - 2]; rough += d * d }
            if name != "all" { print("grass walk TAA \(taa ? "on" : "off"): mean luma of the lower half \(series.map { String(format: "%.1f", $0) }.joined(separator: " ")); roughness (rms 2nd difference) \(String(format: "%.3f", (rough / Float(series.count - 2)).squareRoot()))") }
            let rms = (rough / Float(series.count - 2)).squareRoot(), drift = (series.first ?? 0) - (series.last ?? 0)
            check(rms < 0.5 && drift > 0, "walking a metre every ten frames with the temporal history running (TAA \(taa ? "on" : "off")), the grass region's brightness drifts smoothly and does not pulse (roughness \(String(format: "%.2f", rms)), at most 0.5; measured 0.26 off, 0.24 on)")
        }
    }
}
