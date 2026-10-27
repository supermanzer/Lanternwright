import Metal

/// What a pass needs of the frame: the command buffer, the final target, the camera and a VALUE copy of the frame uniforms (G10.1.3: no pass changes what the next one sees).
struct FrameContext {
    let commandBuffer: MTLCommandBuffer
    let target: MTLTexture
    let camera: Camera
    let frame: FrameUniforms
}

/// One stage of the frame graph: an object that encodes its own encoders into the frame's command buffer. Passes run in the order of `Renderer.passes`.
protocol RenderPass: AnyObject {
    var name: String { get }
    func encode(_ c: FrameContext)
}
