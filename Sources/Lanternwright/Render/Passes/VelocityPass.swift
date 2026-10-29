import Metal
import simd

/// G10.2.1: the motion vector pass (camera motion; see `velocity_fragment`). Runs after the water and glass have written their depth, only when `Renderer.velocityEnabled` is set.
/// The first frame after a camera cut (or the first ever) writes zero motion: `velocityHistoryValid` is false then.
final class VelocityPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "velocity"

    func encode(_ c: FrameContext) {
        guard r.velocityNeeded, let velocity = r.velocityTexture, let depth = r.depthTexture else { r.velocityHistoryValid = false; return }          // off: the last matrix would be stale when it is switched on again
        // This frame's unjittered view-projection (updateFrame sets it) and the last one; a camera cut or world change makes the old one meaningless.
        let current = r.taaCurrentViewProj
        let previous = r.velocityHistoryValid ? r.velocityPrevViewProj : current
        defer { r.velocityPrevViewProj = current; r.velocityHistoryValid = true }
        var tu = TaaUniforms(prevViewProj: previous, invViewProj: current.inverse, params: SIMD4(0, 0, 0, 0),
                             screen: SIMD4(Float(depth.width), Float(depth.height), 1 / Float(depth.width), 1 / Float(depth.height)), tuning: SIMD4(0, 0, 0, 0))
        let pd = MTLRenderPassDescriptor()
        pd.colorAttachments[0].texture = velocity
        pd.colorAttachments[0].loadAction = .dontCare
        pd.colorAttachments[0].storeAction = .store
        guard let enc = r.renderEncoder(c.commandBuffer, pd) else { return }
        enc.label = "velocity"
        enc.setRenderPipelineState(r.velocityPipeline)
        enc.setFragmentBytes(&tu, length: MemoryLayout<TaaUniforms>.stride, index: 0)
        enc.setFragmentTexture(depth, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
