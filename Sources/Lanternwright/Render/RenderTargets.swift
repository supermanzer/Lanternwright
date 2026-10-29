import Metal

/// G10.1.1: every texture whose size follows the output size, in one value with named members. One of these exists for the current output size; it is rebuilt
/// when the size changes. (The fixed-size textures, the shadow cascades, the sky LUT and the irradiance map, belong to their passes and stay where they are made.)
/// Sizes: full output size unless noted; `rays` and the two AO textures are half size; bloom level i is size >> (i + 1).
struct RenderTargets {
    let width: Int, height: Int
    /// The scene's HDR colour: opaque, sky, water, glass, AO and TAA all write it; bloom and the composite read it.
    let hdr: MTLTexture
    /// Temporal anti-aliasing: last frame's resolved image, and where this frame's is written. They swap every frame (`swapTAA`).
    private(set) var taaHistory: MTLTexture
    private(set) var taaResolved: MTLTexture
    /// A copy of the HDR colour, read by the water (refraction) and by the AO apply pass.
    let sceneCopy: MTLTexture
    /// Straight-line camera distance per pixel (1e5 for sky), written by the opaque pass.
    let distance: MTLTexture
    let rays: MTLTexture                // half size
    let ao: MTLTexture, aoBlurred: MTLTexture          // half size
    let bloom: [MTLTexture]
    let depth: MTLTexture
    /// G10.2.1: motion vectors in pixels (RG16F), written by `VelocityPass` when the renderer's `velocityEnabled` is set (MetalFX, the selftest); otherwise never touched.
    let velocity: MTLTexture
    /// 64 x 36 mean log luminance for eye adaptation, read back on the CPU a frame late (a fixed size, made on first use).
    var luma: MTLTexture?

    init(device: MTLDevice, width: Int, height: Int) {
        func make(_ format: MTLPixelFormat, _ label: String, _ w: Int, _ h: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            let t = device.makeTexture(descriptor: d)!
            t.label = label
            return t
        }
        self.width = width; self.height = height
        hdr = make(Renderer.hdrFormat, "hdr", width, height)
        taaHistory = make(Renderer.hdrFormat, "taa history", width, height)
        taaResolved = make(Renderer.hdrFormat, "taa resolved", width, height)
        sceneCopy = make(Renderer.hdrFormat, "sceneCopy", width, height)
        distance = make(Renderer.distanceFormat, "distance", width, height)
        rays = make(Renderer.hdrFormat, "rays", width / 2, height / 2)
        ao = make(.r16Float, "ao", width / 2, height / 2)
        aoBlurred = make(.r16Float, "ao blurred", width / 2, height / 2)
        bloom = (0..<Renderer.bloomLevels).map { i in make(Renderer.hdrFormat, "bloom\(i)", max(1, width >> (i + 1)), max(1, height >> (i + 1))) }
        depth = make(Renderer.depthFormat, "depth", width, height)
        velocity = make(.rg16Float, "velocity", width, height)
    }

    /// The resolved frame becomes next frame's history.
    mutating func swapTAA() { swap(&taaHistory, &taaResolved) }
}
