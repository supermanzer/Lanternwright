import Foundation
import Metal
import simd

/// Self-tests: the charge meters (P02.4 / F10.3): a soft light that grows on the lens-room receiver and on the prism's marks while a hold runs, driven by one level 0...1.
extension SelfTestRunner {
    func runChargeMeter() {
        guard name == "all" || name == "chargemeter" else { return }
        // The curve: nothing at 0 (hidden), a visible spark at the smallest level, growing in size and strength all the way to 1, never a dark patch.
        let levels: [Float] = [0.02, 0.1, 0.25, 0.5, 0.75, 1.0]
        let sizes = levels.map { ChargeMeter.scale(level: $0) }, strengths = levels.map { ChargeMeter.strength(level: $0) }
        check(zip(sizes, sizes.dropFirst()).allSatisfy { $0 < $1 } && zip(strengths, strengths.dropFirst()).allSatisfy { $0 < $1 }, "chargemeter: size \(sizes.map { String(format: "%.2f", $0) }) and strength \(strengths.map { String(format: "%.2f", $0) }) both grow with the level")
        check(abs(sizes.last! - 1) < 1e-4 && abs(strengths.last! - ChargeMeter.fullStrength) < 1e-4 && strengths.first! > 0.8, "chargemeter: level 1 is the full lens (size 1, strength \(ChargeMeter.fullStrength)) and even level 0.02 is a lit spark (strength \(String(format: "%.2f", strengths.first!)))")
        // The items exist in the worlds that have the machines, start hidden, give no shadow, and `set` shows, scales and hides them without moving them.
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "chargemeter: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 12; renderer.autoExposure = false; renderer.taaEnabled = false
        renderer.world = .varrow
        let varrow = renderer.scene
        renderer.world = .tideArchive
        let archive = renderer.scene
        func item(_ s: Scene, _ n: String) -> DrawItem? { s.items.first { $0.name == n } }
        check(item(varrow, ChargeMeter.receiverName)?.hidden == true && ChargeMeter.prismNames.allSatisfy { item(archive, $0)?.hidden == true }, "chargemeter: the receiver meter (Varrow) and the three mark meters (Archive) exist and start hidden")
        check(([item(varrow, ChargeMeter.receiverName)] + ChargeMeter.prismNames.map { item(archive, $0) }).allSatisfy { $0 != nil && !$0!.castsShadow }, "chargemeter: a meter is light, it casts no shadow")
        let before = item(archive, ChargeMeter.prismName(1))!.uniforms.model
        ChargeMeter.set(archive, ChargeMeter.prismName(1), level: 0.5)
        let mid = item(archive, ChargeMeter.prismName(1))!
        let sx = simd_length(SIMD3(mid.uniforms.model.columns.0.x, mid.uniforms.model.columns.0.y, mid.uniforms.model.columns.0.z))
        check(!mid.hidden && abs(sx - ChargeMeter.scale(level: 0.5)) < 1e-4 && simd_length(mid.uniforms.model.columns.3 - before.columns.3) < 1e-6 && abs(mid.uniforms.emissive.w - ChargeMeter.strength(level: 0.5)) < 1e-4, "chargemeter: set(level 0.5) shows it at size \(String(format: "%.2f", sx)), strength \(String(format: "%.2f", mid.uniforms.emissive.w)), and keeps its place")
        ChargeMeter.set(archive, ChargeMeter.prismName(1), level: 0)
        check(item(archive, ChargeMeter.prismName(1))!.hidden, "chargemeter: set(level 0) hides it again (a broken hold fades to nothing)")
        // Rendered: the mark seen from inside the chamber gets brighter at its centre as the level rises, and is unchanged (the plain panel) at 0.
        renderer.world = .tideArchive
        let w = 400, h = 225
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc), let cam = Viewpoints.named("ta-mark0") else { check(false, "chargemeter: no target or view"); return }
        func centreLuma(_ level: Float) -> Float? {
            for n in ChargeMeter.allNames { ChargeMeter.set(archive, n, level: level) }
            for _ in 0..<2 { guard let cb = renderer.queue.makeCommandBuffer() else { return nil }; renderer.encode(commandBuffer: cb, target: tex, camera: cam); cb.commit(); cb.waitUntilCompleted() }
            var px = [UInt8](repeating: 0, count: w * h * 4)
            tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            var s: Float = 0
            for y in (h / 2 - 3)..<(h / 2 + 3) { for x in (w / 2 - 3)..<(w / 2 + 3) { let i = (y * w + x) * 4; s += 0.2126 * Float(px[i + 2]) + 0.7152 * Float(px[i + 1]) + 0.0722 * Float(px[i]) } }
            return s / 36
        }
        guard let l0 = centreLuma(0), let l1 = centreLuma(0.1), let l2 = centreLuma(0.3), let l3 = centreLuma(0.6), let l4 = centreLuma(1) else { check(false, "chargemeter: no frame"); return }
        check(l0 + 8 < l1 && l1 < l2 && l2 < l3 && l3 < l4 + 1, "chargemeter: the mark's centre luma rises with the level: 0 \(Int(l0)), 0.1 \(Int(l1)), 0.3 \(Int(l2)), 0.6 \(Int(l3)), 1 \(Int(l4))")
    }
}
