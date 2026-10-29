import Foundation
import Metal
import simd

/// Self-tests: the per-pass GPU timer (G10.0.1). It must not change what is drawn, must list the passes of a frame by label, and its table must add up to the frame.
extension SelfTestRunner {
    func runPassTimer() {
        guard name == "all" || name == "passtimer" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "passtimer: no Metal device"); return }
        guard let timer = PassTimer(device: device) else { check(true, "passtimer: this device cannot sample counters at stage boundaries: unavailable, and everything runs without it (skipped)"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright", "--taa"]))
        renderer.fixedTime = 12
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: 640, height: 360, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "passtimer: no target"); return }
        let cam = Viewpoints.named("dock") ?? Camera(position: SIMD3(0, 3, 0), yaw: 0, pitch: 0)
        func frame() -> [UInt8] {
            guard let cb = renderer.queue.makeCommandBuffer() else { return [] }
            renderer.encode(commandBuffer: cb, target: tex, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            timer.drain(cb)
            var px = [UInt8](repeating: 0, count: 640 * 360 * 4)
            tex.getBytes(&px, bytesPerRow: 640 * 4, from: MTLRegionMake2D(0, 0, 640, 360), mipmapLevel: 0)
            return px
        }
        for _ in 0..<4 { _ = frame() }                                   // warm up and let the TAA history settle
        // The same frame twice: the jitter index and the TAA history are put back before each, so only the timer differs.
        let jitter = renderer.taaFrameIndex
        renderer.resetTAA(); renderer.taaFrameIndex = jitter
        renderer.passTimer = nil; let plain = frame()
        renderer.resetTAA(); renderer.taaFrameIndex = jitter
        renderer.passTimer = timer; let timed = frame()
        check(plain == timed, "passtimer: the timer changes no pixel of the frame (\(plain.count) bytes compared)")
        for _ in 0..<3 { _ = frame() }
        let labels = timer.latest.map { $0.pass }
        let sum = timer.latest.reduce(0) { $0 + $1.ms }
        check(labels.contains("opaque + sky") && labels.contains("water") && labels.contains("composite") && labels.contains("taa resolve") && timer.latest.allSatisfy { $0.ms >= 0 && $0.ms < 1000 },
              "passtimer: the table names the passes of the frame, each a sane time (\(labels.count) passes: \(labels.prefix(6).joined(separator: ", ")) ...)")
        check(timer.latestFrameMS > 0 && abs(sum - timer.latestFrameMS) <= 0.10 * timer.latestFrameMS,
              "passtimer: the table adds up to the frame's GPU time within 10 % (sum \(String(format: "%.3f", sum)) ms, frame \(String(format: "%.3f", timer.latestFrameMS)) ms)")
        check(timer.summary.hasPrefix("frame ") && timer.summary.contains("opaque + sky"), "passtimer: the one-line summary for the F-key context reads '\(timer.summary.prefix(70))...'")
        renderer.passTimer = nil
    }

    /// G10.1.2 and G10.1.3: the frame is a fixed list of passes, and no pass writes the renderer's frame uniforms (each gets a value copy in its FrameContext).
    func runFrameGraph() {
        guard name == "all" || name == "framegraph" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "framegraph: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        check(renderer.passes.map(\.name) == ["shadow", "opaque", "water", "velocity", "ao", "taa", "beams", "metalfx", "god rays", "bloom", "composite"],
              "framegraph: the passes in order: \(renderer.passes.map(\.name).joined(separator: ", "))")
        let dir = "Sources/Lanternwright/Render/Passes"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { $0.hasSuffix("Pass.swift") && $0 != "RenderPass.swift" } ?? []
        var offenders: [String] = []
        for f in files {
            let text = (try? String(contentsOfFile: dir + "/" + f, encoding: .utf8)) ?? ""
            if text.contains("r.frame") { offenders.append(f) }
        }
        check(files.count == 11 && offenders.isEmpty, "framegraph: no pass touches the renderer's frame uniforms (\(files.count) pass files, offenders: \(offenders))")
        let enc = (try? String(contentsOfFile: "Sources/Lanternwright/Render/Renderer.swift", encoding: .utf8)) ?? ""
        let body = enc.components(separatedBy: "    func encode(commandBuffer: MTLCommandBuffer, target: MTLTexture, camera: Camera) {").last?.components(separatedBy: "\n    }\n").first ?? ""
        check(!body.isEmpty && body.split(separator: "\n").count < 60, "framegraph: Renderer.encode is under 60 lines (\(body.split(separator: "\n").count))")
    }

    /// Every material id the shaders know has a name in the prop audit (it crashed on the ids past `slab`, and silently misnamed them before that).
    func runMaterialNames() {
        guard name == "all" || name == "framegraph" else { return }
        let ids = (0..<40).filter { MaterialID(rawValue: Float($0)) != nil }
        let names = ids.map { PropAudit.materialName($0) }
        check(ids.count >= 26 && Set(names).count == ids.count && !names.contains { $0.hasPrefix("id") } && PropAudit.materialName(99) == "id99" && PropAudit.materialName(25) == "rope",
              "prop audit: all \(ids.count) material ids have distinct names (needles, post, rope included)")
    }
}

extension SelfTestRunner {
    /// G10.2.1: the motion vector buffer (camera motion). A still camera gives zero vectors; a turn of the camera gives the analytic shift in pixels; the pass is silent when it is off.
    func runVelocity() {
        guard name == "all" || name == "velocity" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "velocity: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 12; renderer.autoExposure = false
        let w = 640, h = 360
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "velocity: no target"); return }
        func frame(_ cam: Camera) -> [Float] {
            guard let cb = renderer.queue.makeCommandBuffer() else { return [] }
            renderer.encode(commandBuffer: cb, target: tex, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            guard let v = renderer.velocityTexture, let buf = device.makeBuffer(length: w * h * 4, options: .storageModeShared), let cb2 = renderer.queue.makeCommandBuffer(), let blit = cb2.makeBlitCommandEncoder() else { return [] }
            blit.copy(from: v, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: w, height: h, depth: 1), to: buf, destinationOffset: 0, destinationBytesPerRow: w * 4, destinationBytesPerImage: w * h * 4)
            blit.endEncoding(); cb2.commit(); cb2.waitUntilCompleted()
            let p = buf.contents().assumingMemoryBound(to: Float16.self)
            return (0..<(w * h * 2)).map { Float(p[$0]) }
        }
        let base = Camera(position: SIMD3(150, 4, 180), yaw: -1.9, pitch: -0.1)
        renderer.velocityEnabled = false
        if let timer = PassTimer(device: device) {
            renderer.passTimer = timer
            _ = frame(base); _ = frame(base)
            check(!timer.latest.contains { $0.pass == "velocity" } && !timer.latest.isEmpty, "velocity: with the pass off no velocity encoder is in the frame (\(timer.latest.count) passes)")
            renderer.velocityEnabled = true; renderer.resetTAA(); _ = frame(base); _ = frame(base)
            check(timer.latest.contains { $0.pass == "velocity" }, "velocity: with it on the frame has a velocity pass")
            renderer.passTimer = nil
        } else { check(true, "velocity: no per-pass timer on this device: the on/off check is skipped") }
        renderer.velocityEnabled = true; renderer.resetTAA()
        _ = frame(base)                                   // the first frame has no history: zero motion
        let still = frame(base)
        let sortedStill = still.map { abs($0) }.sorted()
        let median = sortedStill.isEmpty ? 99 : sortedStill[sortedStill.count / 2], p99 = sortedStill.isEmpty ? 99 : sortedStill[sortedStill.count * 99 / 100]
        check(still.count == w * h * 2 && median < 0.02 && p99 < 0.1, "velocity: a still camera gives (almost) zero motion: median \(String(format: "%.4f", median)) px, 99 % under \(String(format: "%.3f", p99)) px (the float round trip of a far depth), largest \(String(format: "%.3f", sortedStill.last ?? 99)) px")
        var turned = base; turned.yaw += 0.01
        let moved = frame(turned)
        // At the centre of the frame a yaw of d radians moves the picture by f * tan(d) pixels, f = h / (2 tan(fovY / 2)).
        let f = Float(h) / (2 * tan(base.fovY / 2))
        let expect = f * tan(0.01)
        let c = (h / 2) * w + w / 2
        let vx = moved[c * 2], vy = moved[c * 2 + 1]
        check(abs(abs(vx) - expect) < 0.06 * expect && abs(vy) < 0.05 * expect + 0.05, "velocity: a 0.01 rad turn moves the centre by \(String(format: "%.2f", abs(vx))) px (expected \(String(format: "%.2f", expect))), vertical \(String(format: "%.2f", vy))")
        // Direction: looking turned toward +yaw, the picture content moves to the one side consistently across the frame (same sign everywhere in the middle band).
        var signs = Set<Bool>()
        for x in stride(from: w / 4, to: 3 * w / 4, by: 16) { signs.insert(moved[((h / 2) * w + x) * 2] > 0) }
        check(signs.count == 1, "velocity: the horizontal motion has one sign across the middle of the frame")
        // The sign: yaw is measured so that +yaw turns toward +x (east); the picture then moves toward -x, so a pixel was last frame at larger x: vx = prev - cur > 0.
        check(moved[c * 2] > 0, "velocity: a +yaw turn gives a positive horizontal vector (the pixel was further right last frame): \(String(format: "%.2f", moved[c * 2]))")
        // A camera cut (a teleport over 12 m) must not produce a frame of bogus vectors: the history is dropped and the vectors are zero.
        var teleported = turned; teleported.position += SIMD3(40, 0, 0)
        let cut = frame(teleported)
        let cutMax = cut.map { abs($0) }.sorted()
        check(cutMax[cutMax.count * 99 / 100] < 0.2, "velocity: after a 40 m teleport the vectors are zero, not hundreds of pixels (99 % under \(String(format: "%.3f", cutMax[cutMax.count * 99 / 100])) px, largest \(String(format: "%.2f", cutMax.last ?? 0)))")
        // Switching the pass off and on again drops the old history too.
        renderer.velocityEnabled = false; _ = frame(teleported); renderer.velocityEnabled = true
        var far = teleported; far.yaw += 0.3
        let reOn = frame(far).map { abs($0) }.sorted()
        check(reOn[reOn.count * 99 / 100] < 0.1, "velocity: switched off and on again, the first frame has zero motion (99 % under \(String(format: "%.3f", reOn[reOn.count * 99 / 100])) px)")
        renderer.velocityEnabled = false
    }
}

extension SelfTestRunner {
    /// G10.4.1: MetalFX upscaling at a render scale below 1 draws the scene smaller, outputs the full size, and looks like the native frame (same overall brightness, no NaNs).
    func runUpscale() {
        guard name == "all" || name == "upscale" else { return }
        guard Renderer.metalFXSupported, let device = MTLCreateSystemDefaultDevice() else { check(true, "upscale: MetalFX is not supported on this device: skipped"); return }
        let w = 800, h = 450
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "upscale: no target"); return }
        func mean(_ renderer: Renderer, frames: Int) -> (Float, Bool) {
            renderer.fixedTime = 12; renderer.autoExposure = false
            for _ in 0..<frames { guard let cb = renderer.queue.makeCommandBuffer() else { return (0, false) }; renderer.encode(commandBuffer: cb, target: tex, camera: Viewpoints.named("dock") ?? Camera(position: SIMD3(0, 3, 0), yaw: 0, pitch: 0)); cb.commit(); cb.waitUntilCompleted() }
            let y = Shimmer.luma(tex)
            return (y.reduce(0, +) / Float(y.count), y.allSatisfy { $0.isFinite })
        }
        let native = Renderer(device: device, options: LaunchOptions.parse(["lanternwright", "--taa"]))
        let (m0, ok0) = mean(native, frames: 10)
        let scaled = Renderer(device: device, options: LaunchOptions.parse(["lanternwright", "--render-scale", "0.75"]))
        let (m1, ok1) = mean(scaled, frames: 10)
        let t = scaled.targets
        check(ok0 && ok1 && t?.renderWidth == 600 && t?.renderHeight == 338 && t?.width == w && t?.upscaled?.width == w && t?.hdr.width == 600,
              "upscale: at 0.75 the scene is \(t?.renderWidth ?? 0) x \(t?.renderHeight ?? 0), the upscaled image \(t?.upscaled?.width ?? 0) x \(t?.upscaled?.height ?? 0), every output value finite")
        check(abs(m1 - m0) < 0.08 * m0, "upscale: the upscaled frame has the native frame's overall brightness (mean luma \(String(format: "%.1f", m1)) against \(String(format: "%.1f", m0)))")
        check(scaled.passes.map(\.name).contains("metalfx") && Renderer.metalFXSupported, "upscale: the MetalFX pass is in the frame graph")
    }
}
