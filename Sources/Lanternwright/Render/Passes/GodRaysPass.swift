import Metal
import simd

/// G10.1.2: god rays pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class GodRaysPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "god rays"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        var frame = c.frame
        // 1d. God rays (half resolution), then the bloom chain.
        if let rays = r.raysTexture, let hdr = r.finalHDRTexture, let dist = r.distanceTexture {
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = rays
            rp.colorAttachments[0].loadAction = .dontCare
            rp.colorAttachments[0].storeAction = .store
            if let enc = r.renderEncoder(commandBuffer, rp) {
                enc.label = "god rays"
                enc.setRenderPipelineState(r.godRaysPipeline)
                enc.setFragmentTexture(hdr, index: 0)
                enc.setFragmentTexture(dist, index: 1)
                enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        }
    }
}
