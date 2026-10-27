import Metal
import simd

/// G10.1.2: AO pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class AOPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "ao"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        let target = c.target
        var frame = c.frame
        // 1c'. SSAO: occlusion from the distance buffer (half res), blurred, multiplied into the scene.
        if let ao = r.aoTexture, let blurred = r.aoBlurred, let dist = r.distanceTexture, let hdr = r.hdrTexture, let copy = r.sceneCopy {
            if let blit = r.blitEncoder(commandBuffer) {
                blit.label = "scene copy for AO"
                blit.copy(from: hdr, to: copy)
                blit.endEncoding()
            }
            func run(_ label: String, _ pipeline: MTLRenderPipelineState, target: MTLTexture, textures: [MTLTexture], needsFrame: Bool) {
                let pd = MTLRenderPassDescriptor()
                pd.colorAttachments[0].texture = target
                pd.colorAttachments[0].loadAction = .dontCare
                pd.colorAttachments[0].storeAction = .store
                guard let enc = r.renderEncoder(commandBuffer, pd) else { return }
                enc.label = label
                enc.setRenderPipelineState(pipeline)
                for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
                if needsFrame { enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1) }
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
            run("ssao", r.aoPipeline, target: ao, textures: [dist], needsFrame: true)
            run("ssao blur", r.aoBlurPipeline, target: blurred, textures: [ao, dist], needsFrame: false)
            run("ssao apply", r.aoApplyPipeline, target: hdr, textures: [copy, blurred], needsFrame: true)
        }
    }
}
