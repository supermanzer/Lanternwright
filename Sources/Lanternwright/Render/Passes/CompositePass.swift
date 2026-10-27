import Metal
import simd

/// G10.1.2: composite pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class CompositePass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "composite"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        let target = c.target
        var frame = c.frame
        // 2. Composite (tonemap) into the target.
        let comp = MTLRenderPassDescriptor()
        comp.colorAttachments[0].texture = target
        comp.colorAttachments[0].loadAction = .dontCare
        comp.colorAttachments[0].storeAction = .store
        if let enc = r.renderEncoder(commandBuffer, comp) {
            enc.label = "composite"
            if r.options.debugView == "depth" {
                enc.setRenderPipelineState(r.depthVizPipeline)
                enc.setFragmentTexture(r.distanceTexture, index: 0)
            } else {
                enc.setRenderPipelineState(r.compositePipeline)
                enc.setFragmentTexture(r.hdrTexture, index: 0)
                enc.setFragmentTexture(r.bloomChain.first, index: 1)
                enc.setFragmentTexture(r.raysTexture, index: 2)
            }
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
    }
}
