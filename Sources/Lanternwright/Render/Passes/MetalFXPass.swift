import Metal
import MetalFX
import simd
import Foundation

/// G10.4.1: MetalFX temporal upscaling. Active only when `Renderer.renderScale` is below 1 and the device supports it: the scene (opaque, water, glass, the beams) has been drawn at
/// the render size with the sub-pixel jitter, and this pass turns it into the full-size image the bloom, god rays and composite read, from the depth, the camera-motion vectors
/// (VelocityPass) and the jitter. It REPLACES the native temporal resolve (TAAPass is skipped then). Inactive: no work.
final class MetalFXPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "metalfx"
    /// Which way MetalFX wants the jitter: our projection moves the image by (-jitter.x, -jitter.y) pixels (see Renderer.updateFrame). Checked by the selftest and on frames.
    nonisolated(unsafe) static var jitterSign: Float = Float(ProcessInfo.processInfo.environment["MFX_JITTER_SIGN"] ?? "") ?? 1

    func encode(_ c: FrameContext) {
        guard r.metalFXActive, let scaler = r.temporalScaler, let t = r.targets, let up = t.upscaled else { return }
        scaler.colorTexture = t.hdr
        scaler.depthTexture = t.depth
        scaler.motionTexture = t.velocity
        scaler.outputTexture = up
        scaler.inputContentWidth = t.renderWidth
        scaler.inputContentHeight = t.renderHeight
        scaler.jitterOffsetX = Self.jitterSign * r.taaJitter.x
        scaler.jitterOffsetY = Self.jitterSign * r.taaJitter.y
        scaler.motionVectorScaleX = 1
        scaler.motionVectorScaleY = 1
        scaler.preExposure = 1
        scaler.reset = !r.scalerHistoryValid
        scaler.encode(commandBuffer: c.commandBuffer)
        r.scalerHistoryValid = true
    }
}
