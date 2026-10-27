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
}
