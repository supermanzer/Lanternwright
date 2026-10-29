import Metal
import simd

/// G10.1.2: TAA pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class TAAPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "taa"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        let target = c.target
        // 1c''. Temporal anti-aliasing: resolve the jittered frame against the history, then sharpen into the scene HDR that bloom and the composite read.
        if r.taaEnabled, !r.metalFXActive, let hdr = r.hdrTexture, let hist = r.targets?.taaHistory, let res = r.targets?.taaResolved, let depth = r.depthTexture {
            var tu = TaaUniforms(prevViewProj: r.taaPrevViewProj, invViewProj: r.taaCurrentViewProj.inverse,
                                 params: SIMD4(r.taaJitter.x, r.taaJitter.y, r.taaHistoryValid ? 1 : 0, r.taaSharpness),
                                 screen: SIMD4(Float(hdr.width), Float(hdr.height), 1 / Float(hdr.width), 1 / Float(hdr.height)), tuning: r.taaTuning)
            func fullscreen(_ label: String, _ pipeline: MTLRenderPipelineState, target: MTLTexture, textures: [MTLTexture]) {
                let pd = MTLRenderPassDescriptor()
                pd.colorAttachments[0].texture = target
                pd.colorAttachments[0].loadAction = .dontCare
                pd.colorAttachments[0].storeAction = .store
                guard let enc = r.renderEncoder(commandBuffer, pd) else { return }
                enc.label = label
                enc.setRenderPipelineState(pipeline)
                enc.setFragmentBytes(&tu, length: MemoryLayout<TaaUniforms>.stride, index: 0)
                for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
            fullscreen("taa resolve", r.taaResolvePipeline, target: res, textures: [hdr, hist, depth])
            fullscreen("taa sharpen", r.taaSharpenPipeline, target: hdr, textures: [res])
            r.targets?.swapTAA()                                 // the resolved frame is next frame's history
            r.taaPrevViewProj = r.taaCurrentViewProj
            r.taaHistoryValid = true
        }
    }
}
