import Foundation
import Metal
import simd

/// Self-tests: the sea reads as deep where it is deep (F10.1, note #112 again: the strait was physically deep but the same light teal as the shelf).
extension SelfTestRunner {
    func runSeaDepth() {
        guard name == "all" || name == "seadepth" else { return }
        // The CPU mirror of the shader's look: red goes first, the bed is gone past about 2.5 m, the scatter darkens, a thin film is untouched by the new terms.
        let t03 = SeaDepthLook.transmit(path: 0.3, column: 0.3), t25 = SeaDepthLook.transmit(path: 2.5, column: 2.5)
        check(t03.x > 0.8 && t03.z > 0.9, "seadepth: at 0.3 m the bed shows through almost undimmed (\(t03))")
        check(t25.x < 0.01 && t25.y < 0.12 && t25.z < 0.12, "seadepth: at 2.5 m red is gone and the bed is nearly lost (\(t25))")
        check(SeaDepthLook.absorb(column: 2.5).x > 2 * SeaDepthLook.absorb(column: 0.3).x && SeaDepthLook.transmit(path: 4, column: 0.3).x > SeaDepthLook.transmit(path: 4, column: 2.5).x, "seadepth: deeper water absorbs faster than the shelf")
        let l03 = SeaDepthLook.lumaStraightDown(column: 0.3, bed: 0.3, light: 1), l25 = SeaDepthLook.lumaStraightDown(column: 2.5, bed: 0.3, light: 1)
        check(l03 > 3 * l25, "seadepth: the model's luminance at 0.3 m is over 3x that at 2.5 m (\(String(format: "%.3f", l03)) vs \(String(format: "%.3f", l25)))")
        // The rendered sea: a straight-down look at the real strait over a 0.3 m spot and over a 2.5 m spot, the water layer's own HDR luminance (mist left out of both).
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "seadepth: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.world = .varrow; renderer.fixedTime = 12; renderer.autoExposure = false; renderer.taaEnabled = false
        let terrain = renderer.scene.terrain!
        func find(_ target: Float, tol: Float, r: Float) -> SIMD2<Float>? {
            var best: (Float, SIMD2<Float>)? = nil
            for z in stride(from: Float(-310), through: -225, by: 0.75) { for x in stride(from: Float(-90), through: 20, by: 0.75) {
                // a flat-bedded spot (the bed 3 m round it within 25 cm), so the patch is one depth
                let g = terrain.sampleHeight(x: x, z: z); guard abs(g - target) < tol else { continue }
                let nb = [(r, 0), (-r, 0), (0, r), (0, -r)].map { terrain.sampleHeight(x: x + $0.0, z: z + $0.1) }
                let spread = nb.map { abs($0 - g) }.max()!
                if best == nil || spread < best!.0 { best = (spread, SIMD2(x, z)) }
            } }
            guard let b = best, b.0 < 0.2 else { return nil }          // the bed within 20 cm over r m round the patch
            return b.1
        }
        let sh = find(-0.3, tol: 0.08, r: 1), dp = find(-2.5, tol: 0.25, r: 3)
        guard let shallow = sh, let deep = dp else { check(false, "seadepth: no flat 0.3 m (\(String(describing: sh))) / 2.5 m (\(String(describing: dp))) spot in the strait"); return }
        let w = 320, h = 180
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "seadepth: no target"); return }
        func luma(at p: SIMD2<Float>) -> Float? {
            RenderLayer.off = [.mist]; defer { RenderLayer.off = [] }
            let cam = Camera(position: SIMD3(p.x, 6, p.y), yaw: 0, pitch: -1.5)
            for _ in 0..<2 { guard let cb = renderer.queue.makeCommandBuffer() else { return nil }; renderer.encode(commandBuffer: cb, target: tex, camera: cam); cb.commit(); cb.waitUntilCompleted() }
            guard let hdr = renderer.hdrTexture, let buf = device.makeBuffer(length: w * h * 8, options: .storageModeShared), let cb = renderer.queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: hdr, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: w, height: h, depth: 1), to: buf, destinationOffset: 0, destinationBytesPerRow: w * 8, destinationBytesPerImage: w * h * 8)
            blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            let q = buf.contents().assumingMemoryBound(to: Float16.self)
            var s: Float = 0; var n: Float = 0
            for y in (h / 2 - 6)..<(h / 2 + 6) { for x in (w / 2 - 6)..<(w / 2 + 6) { let i = (y * w + x) * 4; s += 0.2126 * Float(q[i]) + 0.7152 * Float(q[i + 1]) + 0.0722 * Float(q[i + 2]); n += 1 } }
            return s / n
        }
        guard let ls = luma(at: shallow), let ld = luma(at: deep) else { check(false, "seadepth: no frame"); return }
        let factor = ls / max(ld, 1e-5)
        check(factor > 1.8, "seadepth: rendered straight down, the 0.3 m spot at \(shallow) is \(String(format: "%.2f", factor))x the luminance of the 2.5 m spot at \(deep) (\(String(format: "%.4f", ls)) vs \(String(format: "%.4f", ld)); at least 1.8x)")
    }
}
