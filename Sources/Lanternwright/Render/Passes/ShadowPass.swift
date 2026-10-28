import Metal
import simd

/// G10.1.2: shadow pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class ShadowPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "shadow"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        let camera = c.camera
        var frame = c.frame
        // 0. Shadow maps: scene depth as seen from the sun, once per cascade (far, mid, near).
        r.lastShadowDraws = 0
        let cascades: [(MTLTexture, float4x4)] = [(r.shadowMap, frame.sunViewProj), (r.shadowMid, frame.sunViewProj1), (r.shadowNear, frame.sunViewProj0)]
        for (texture, matrix) in cascades {
            let sp = MTLRenderPassDescriptor()
            sp.depthAttachment.texture = texture
            sp.depthAttachment.loadAction = .clear
            sp.depthAttachment.clearDepth = 1
            sp.depthAttachment.storeAction = .store
            guard let enc = r.renderEncoder(commandBuffer, sp) else { continue }
            enc.label = "shadow \(texture.width)"
            enc.setRenderPipelineState(r.shadowPipeline)
            enc.setDepthStencilState(r.depthState)
            enc.setFrontFacing(.counterClockwise)
            enc.setCullMode(.none)               // terrain is a single-sided sheet; normal-offset bias handles acne
            enc.setDepthBias(1.0, slopeScale: 1.5, clamp: 0)
            var f = frame
            f.sunViewProj = matrix               // shadow_vertex reads sunViewProj: point it at this cascade
            enc.setVertexBytes(&f, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            // Cull against the SUN's box, not the camera's: things behind you can still shadow what you see.
            let sunFrustum = Frustum(viewProj: matrix)
            for item in r.scene.items where !RenderLayer.isOff(.shadows) {
                let b = item.worldBounds
                guard !item.hidden, item.castsShadow, item.uniforms.lod.w < 0.5, sunFrustum.intersects(min: b.min, max: b.max) else { continue }          // needle cards cast no shadow (the sprays of the same trees do)
                r.lastShadowDraws += 1
                var u = item.uniforms
                enc.setVertexBuffer(item.mesh.vertexBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.indexCount, indexType: .uint32,
                                          indexBuffer: item.mesh.indexBuffer, indexBufferOffset: 0)
            }
            enc.endEncoding()
        }
    }
}
