import Metal
import simd

/// G10.1.2: opaque pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class OpaquePass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "opaque"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        let camera = c.camera
        var frame = c.frame
        // 1. Opaque geometry into HDR.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = r.hdrTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[1].texture = r.distanceTexture
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].clearColor = MTLClearColor(red: 1e5, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[1].storeAction = .store
        pass.depthAttachment.texture = r.depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store          // the water pass depth-tests against it
        if let enc = r.renderEncoder(commandBuffer, pass) {
            enc.label = "opaque"
            enc.setRenderPipelineState(r.litPipeline)
            enc.setDepthStencilState(r.depthState)
            enc.setFrontFacing(.counterClockwise)
            enc.setCullMode(.back)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setFragmentTexture(r.shadowMap, index: 0)
            enc.setFragmentTexture(r.shadowNear, index: 6)
            enc.setFragmentTexture(r.shadowMid, index: 7)
            enc.setFragmentTexture(r.skyLUT, index: 1)
            enc.setFragmentTexture(r.irradianceMap, index: 4)
            let camFrustum = Frustum(viewProj: frame.viewProj)
            r.lastOpaqueDraws = 0
            // Two sweeps: ordinary objects first (a pipeline without any discard keeps early depth rejection), then the tree LOD objects, whose
            // fragments dither between levels and so need the variant with `discard_fragment`.
            for lodSweep in [false, true] {
                if lodSweep { enc.setRenderPipelineState(r.litLODPipeline) }
                for item in r.scene.items {
                    let b = item.worldBounds
                    guard !item.hidden, !item.refractive, (item.uniforms.lod.x > 0.5) == lodSweep, camFrustum.intersects(min: b.min, max: b.max) else { continue }
                    r.lastOpaqueDraws += 1
                    enc.setCullMode(item.uniforms.lod.w > 0.5 ? .none : .back)              // needle cards are two-sided
                    var u = item.uniforms
                    enc.setVertexBuffer(item.mesh.vertexBuffer, offset: 0, index: 0)
                    enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.setFragmentBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.indexCount, indexType: .uint32,
                                              indexBuffer: item.mesh.indexBuffer, indexBufferOffset: 0)
                }
            }
            // Grass: one instanced draw, 7 vertices per blade, positions generated in the vertex shader.
            enc.setRenderPipelineState(r.grassPipeline)
            enc.setCullMode(.none)
            let windNow = Wind.strength(at: camera.position, time: r.clock)
            var gp = [SIMD4<Float>(LookDefaults.grassCell, Float(r.grassCellsPerSide), LookDefaults.grassRadius, 0),
                      SIMD4<Float>(Wind.direction.x, Wind.direction.y, windNow, 0)]
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setVertexBytes(&gp, length: MemoryLayout<SIMD4<Float>>.stride * gp.count, index: 3)
            enc.setVertexTexture(r.terrainTextures[r.world], index: 5)
            var identity = ObjectUniforms()
            enc.setFragmentBytes(&identity, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
            if !Renderer.skipGrass && !RenderLayer.isOff(.grass) { enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 7, instanceCount: r.grassCellsPerSide * r.grassCellsPerSide) }
            enc.setCullMode(.back)

            // Sky last, so the depth test rejects it everywhere geometry was drawn (saves shading those pixels).
            enc.label = "opaque + sky"
            enc.setRenderPipelineState(r.skyPipeline)
            enc.setDepthStencilState(r.skyDepthState)
            enc.setCullMode(.none)
            enc.setFragmentTexture(r.skyLUT, index: 1)
            if !RenderLayer.isOff(.sky) { enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3) }
            enc.endEncoding()
        }
    }
}
