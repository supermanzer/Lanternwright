import Metal
import simd

/// G10.1.2: beams pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class BeamsPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "beams"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        let camera = c.camera
        var frame = c.frame
        // 1c-3. The lit lighthouse's beams and the glow at the lens, added as light AFTER the temporal resolve (F02 R1): they sweep round with no motion vectors, so
        // temporal filtering would dim their leading edge and trail them; they are soft and additive, so they have nothing to anti-alias anyway.
        if r.world == .varrow && r.beamIntensity > 0.001, let hdr = r.hdrTexture {
            let beamHeading = 0.6 + r.clock * Renderer.beamRate
            let bpass = MTLRenderPassDescriptor()
            bpass.colorAttachments[0].texture = hdr
            bpass.colorAttachments[0].loadAction = .load
            bpass.colorAttachments[0].storeAction = .store
            bpass.depthAttachment.texture = r.depthTexture
            bpass.depthAttachment.loadAction = .load
            bpass.depthAttachment.storeAction = .dontCare
            if let enc = r.renderEncoder(commandBuffer, bpass) {
                enc.label = "beams"
                // The resolved image lives in unjittered space, so the beams are drawn with the unjittered camera too.
                var beamFrame = frame
                if r.taaEnabled { beamFrame.viewProj = r.taaCurrentViewProj; beamFrame.invViewProj = r.taaCurrentViewProj.inverse }
            do {
                enc.setRenderPipelineState(r.beamPipeline)
                enc.setDepthStencilState(r.waterDepthState)
                enc.setCullMode(.none)
                enc.setVertexBuffer(r.beamMesh.vertexBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&beamFrame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentBytes(&beamFrame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentTexture(r.distanceTexture, index: 3)
                for (sign, glow) in [(Float(1), Float(0)), (Float(-1), Float(0)), (Float(1), Float(1))] {
                    var bu = ObjectUniforms()
                    bu.tint = SIMD4(sign, beamHeading, r.beamIntensity, 0)
                    bu.emissive = SIMD4(Landmarks.lensPosition, glow)
                    enc.setVertexBytes(&bu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.setFragmentBytes(&bu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: r.beamMesh.indexCount, indexType: .uint32, indexBuffer: r.beamMesh.indexBuffer, indexBufferOffset: 0)
                }
            }
                enc.endEncoding()
            }
        }
    }
}
