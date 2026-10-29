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
        if r.world == .varrow && (r.beamIntensity > 0.001 || r.interiorOpen), let hdr = r.hdrTexture {
            let signal: BeamSignal.Pose? = r.beamSignal ? BeamSignal.pose(clock: r.clock) : nil
            let beamHeading = signal?.heading ?? (0.6 + r.clock * Renderer.beamRate)
            let beamLevel = r.beamIntensity * (signal?.intensity ?? 1)
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
                if r.taaEnabled && !r.metalFXActive { beamFrame.viewProj = r.taaCurrentViewProj; beamFrame.invViewProj = r.taaCurrentViewProj.inverse }
            do {
                enc.setRenderPipelineState(r.beamPipeline)
                enc.setDepthStencilState(r.waterDepthState)
                enc.setCullMode(.none)
                enc.setVertexBuffer(r.beamMesh.vertexBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&beamFrame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentBytes(&beamFrame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentTexture(r.distanceTexture, index: 3)
                for (sign, glow) in [(Float(1), Float(0)), (Float(-1), Float(0)), (Float(1), Float(1))] where r.beamIntensity > 0.001 {
                    if signal != nil && sign < 0 && !(signal!.opposite) { continue }          // the rest and the flash are ONE beam
                    var bu = ObjectUniforms()
                    bu.tint = SIMD4(sign, beamHeading, glow > 0.5 ? r.beamIntensity * max(signal?.intensity ?? 1, 0.35) : beamLevel, 0)
                    bu.emissive = SIMD4(Landmarks.lensPosition, glow)
                    enc.setVertexBytes(&bu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.setFragmentBytes(&bu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: r.beamMesh.indexCount, indexType: .uint32, indexBuffer: r.beamMesh.indexBuffer, indexBufferOffset: 0)
                }
            }
                // S03.5b: the windows' light shafts inside the open tower (no shadow: light casts none). Each window on the sun's side lets a soft warm shaft fall along the sun's direction.
                if r.interiorOpen {
                    let sunToward = simd_normalize(SIMD3(frame.sunDir.x, frame.sunDir.y, frame.sunDir.z))
                    if sunToward.y > 0.0 {
                        let travel = -sunToward
                        let horiz = SIMD2(travel.x, travel.z)
                        for (i, wy) in Lighthouse.windowYs.enumerated() {
                            let a = Lighthouse.windowAngle(i)
                            let inward = SIMD2(-cos(a), -sin(a))
                            let facing = simd_length(horiz) > 1e-4 ? simd_dot(simd_normalize(horiz), inward) : 0
                            guard facing > 0.2 else { continue }
                            let ri = LighthouseInterior.innerR(wy)
                            let origin = Layout.lighthouse + SIMD3(cos(a) * ri, wy, sin(a) * ri)
                            let level = facing * min(1, sunToward.y * 6 + 0.25)
                            var su = ObjectUniforms()
                            su.model = float4x4(columns: (SIMD4(0.42, 0, 0, 0), SIMD4(7.5, 0, 0, 0), SIMD4(travel.x, travel.y, travel.z, 0), SIMD4(origin.x, origin.y, origin.z, 1)))
                            su.tint = SIMD4(0, 0, 1, 0)
                            su.emissive = SIMD4(frame.sunColor.x * 3.0 * level, frame.sunColor.y * 3.0 * level, frame.sunColor.z * 3.0 * level, 2)
                            enc.setVertexBytes(&su, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                            enc.setFragmentBytes(&su, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                            enc.drawIndexedPrimitives(type: .triangle, indexCount: r.beamMesh.indexCount, indexType: .uint32, indexBuffer: r.beamMesh.indexBuffer, indexBufferOffset: 0)
                        }
                    }
                }
                enc.endEncoding()
            }
        }
    }
}
