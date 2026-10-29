import Metal
import simd

/// G10.1.2: bloom pass. Moved out of `Renderer.encode` unchanged: it reads the renderer's pipelines and state through `r` and gets its own copy of the frame uniforms.
final class BloomPass: RenderPass {
    unowned let r: Renderer
    init(_ renderer: Renderer) { r = renderer }
    let name = "bloom"

    func encode(_ c: FrameContext) {
        let commandBuffer = c.commandBuffer
        r.encodeBloom(commandBuffer)
        if r.autoExposure, let hdr = r.finalHDRTexture { r.encodeLuma(commandBuffer, hdr: hdr) }
    }
}
