import Metal
import simd

/// G10.1.2: water pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class WaterPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "water"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        let camera = c.camera
        var frame = c.frame
        // 1b. Snapshot the colour so later passes (water) can read the scene while drawing over it.
        if let blit = r.blitEncoder(commandBuffer), let src = r.hdrTexture, let dst = r.sceneCopy {
            blit.label = "scene copy"
            blit.copy(from: src, to: dst)
            blit.endEncoding()
        }

        // 1c. Water: drawn over the HDR colour, depth-tested against the opaque depth, reading the scene copy.
        let wpass = MTLRenderPassDescriptor()
        wpass.colorAttachments[0].texture = r.hdrTexture
        wpass.colorAttachments[0].loadAction = .load
        wpass.colorAttachments[0].storeAction = .store
        wpass.depthAttachment.texture = r.depthTexture
        wpass.depthAttachment.loadAction = .load
        wpass.depthAttachment.storeAction = .store          // F02 R1: the temporal resolve reprojects from this depth (water and glass included)
        if let enc = r.renderEncoder(commandBuffer, wpass) {
            enc.label = "water"
            enc.setRenderPipelineState(r.waterPipeline)
            enc.setDepthStencilState(r.waterDepthState)
            enc.setCullMode(.none)
            var u = r.ocean.uniforms(camera: camera, level: r.tideLevel)
            var u0 = u
            enc.setVertexBuffer(r.ocean.mesh.vertexBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
            enc.setVertexTexture(r.terrainTextures[r.world], index: 5)           // F03 G2: the water's vertices read the ground to shoal, delay and swash
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setFragmentTexture(r.skyLUT, index: 1)
            enc.setFragmentTexture(r.terrainTextures[r.world], index: 5)          // F04 W1: the water fragment compares its height with the ground under the pixel
            enc.setFragmentTexture(r.sceneCopy, index: 2)
            enc.setFragmentTexture(r.distanceTexture, index: 3)
            if !RenderLayer.isOff(.water) { enc.drawIndexedPrimitives(type: .triangle, indexCount: r.ocean.mesh.indexCount, indexType: .uint32,
                                      indexBuffer: r.ocean.mesh.indexBuffer, indexBufferOffset: 0) }
            // S04.3: the Archive's water bodies (the Great Ledger gallery): the same water, drawn as a calm pool at their own height (their model's translation is the drain, B's; the tide lifts a held one a little).
            let bodies = r.scene.items.filter { $0.isWaterBody && !$0.hidden }
            if !bodies.isEmpty && !RenderLayer.isOff(.water) {
                var bodyFrame = frame
                bodyFrame.worldB = SIMD4(1, 0, 0, 0)                                                    // calm (no swash film), no sea offset
                enc.setVertexBytes(&bodyFrame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentBytes(&bodyFrame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                for item in bodies {
                    var u = item.uniforms
                    let held = max(0, 1 + u.model.columns.3.y / ArchiveStory.drainDepth)
                    u.model = translation(SIMD3(0, ArchiveStory.galleryTideRise(clock: r.clock) * held, 0)) * u.model
                    enc.setVertexBuffer(item.mesh.vertexBuffer, offset: 0, index: 0)
                    enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.indexCount, indexType: .uint32, indexBuffer: item.mesh.indexBuffer, indexBufferOffset: 0)
                }
                enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setVertexBuffer(r.ocean.mesh.vertexBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&u0, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
            }
            // Glass (crystal trees etc.): refracts the scene copy, so it is drawn after the water has been laid down.
            let glass = r.scene.items.filter { $0.refractive && !$0.hidden && !$0.isWaterBody }
            if !glass.isEmpty {
                enc.setRenderPipelineState(r.crystalPipeline)
                // Depth WRITE on and back faces culled. This is a performance rule on Apple's tile-based GPU, measured here:
                // a depth-tested pass that does not write depth cannot discard hidden fragments, and drawing both faces of
                // closed prisms shades everything twice. Together they made the glass cost 6-11 ms; with both, it is free.
                enc.setDepthStencilState(r.depthState)
                enc.setCullMode(.back)
                enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                let camFrustum = Frustum(viewProj: frame.viewProj)
                for item in glass {
                    let b = item.worldBounds
                    guard camFrustum.intersects(min: b.min, max: b.max) else { continue }
                    var u = item.uniforms
                    enc.setVertexBuffer(item.mesh.vertexBuffer, offset: 0, index: 0)
                    enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.setFragmentBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.indexCount, indexType: .uint32,
                                              indexBuffer: item.mesh.indexBuffer, indexBufferOffset: 0)
                }
            }
            // Mist sheets: same disc, alpha-blended, two layers at different heights with different noise.
            let beamHeading = 0.6 + r.clock * Renderer.beamRate          // the mist sheets' beam sector direction
            // The glass loop above left the last crystal's vertices bound at slot 0: the sheets are the ocean disc, so bind ITS vertices again (F03 #47: the mist was
            // drawn with the ocean's indices over a crystal tree's vertices, a faint faceted ghost in the sky near the horizon).
            enc.setVertexBuffer(r.ocean.mesh.vertexBuffer, offset: 0, index: 0)
            enc.setRenderPipelineState(r.mistPipeline)
            for (height, strength, seed) in [(Float(1.6), Float(0.85), Float(0.0)), (Float(6.5), Float(0.5), Float(0.37))] where !RenderLayer.isOff(.water) && !RenderLayer.isOff(.mist) {
                var mu = r.ocean.uniforms(camera: camera, level: height)
                mu.tint = SIMD4(strength * r.mistScale, beamHeading, r.world == .varrow ? r.beamIntensity : 0, seed)
                mu.emissive = SIMD4(Landmarks.lensPosition, 0)
                enc.setVertexBytes(&mu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.setFragmentBytes(&mu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: r.ocean.mesh.indexCount, indexType: .uint32,
                                          indexBuffer: r.ocean.mesh.indexBuffer, indexBufferOffset: 0)
            }
            enc.endEncoding()
        }
    }
}
