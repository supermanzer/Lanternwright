import Metal
import simd

/// Owns GPU state and encodes one frame into any color target, whether the window drawable
/// or an offscreen screenshot texture, so both paths share exactly the same pipeline.
///
/// Frame graph (grows through M1):
///   1. opaque  -> HDR rgba16Float + depth32Float
///   2. composite -> target (tonemap)
final class Renderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    static let outputFormat: MTLPixelFormat = .bgra8Unorm_srgb
    static let hdrFormat: MTLPixelFormat = .rgba16Float
    static let depthFormat: MTLPixelFormat = .depth32Float
    static let distanceFormat: MTLPixelFormat = .r32Float

    var scene: Scene
    var options: LaunchOptions
    /// Fixed clock for deterministic screenshots; nil = wall clock.
    var fixedTime: Float?

    private var frame = FrameUniforms()
    /// Draw calls issued last frame (opaque / shadow), for diagnostics.
    private(set) var lastOpaqueDraws = 0
    private(set) var lastShadowDraws = 0
    private let litPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let skyLUTPipeline: MTLRenderPipelineState
    private let irradiancePipeline: MTLRenderPipelineState
    /// Cosine-convolved sky (32x16): diffuse ambient light for any normal. Rebuilt whenever the LUT is.
    let irradianceMap: MTLTexture
    private let skyPipeline: MTLRenderPipelineState
    private let waterPipeline: MTLRenderPipelineState
    private let waterDepthState: MTLDepthStencilState
    let ocean: Ocean
    private let shadowPipeline: MTLRenderPipelineState
    /// Sun shadow map. The sun camera is orthographic and fitted to a sphere around the island.
    let shadowMap: MTLTexture
    static let shadowSize = 4096
    static let shadowCenter = SIMD3<Float>(-15, 30, -60)
    static let shadowRadius: Float = 340
    private let depthState: MTLDepthStencilState
    private let skyDepthState: MTLDepthStencilState
    /// Lat-long sky radiance (see Shaders/Sky.swift). Mipmapped: high mips double as diffuse irradiance.
    let skyLUT: MTLTexture
    private var lutSunDir = SIMD3<Float>(repeating: .nan)
    static let skyLUTSize = (width: 256, height: 128)
    private let startTime = Date()

    private var hdrTexture: MTLTexture?
    private var depthTexture: MTLTexture?
    /// Straight-line camera distance per pixel (1e5 for sky). Read by the water pass.
    private(set) var distanceTexture: MTLTexture?
    /// Copy of the HDR colour after opaque + sky; the water pass samples it for refraction.
    private(set) var sceneCopy: MTLTexture?
    private let depthVizPipeline: MTLRenderPipelineState
    private let bloomPrefilterPipeline: MTLRenderPipelineState
    private let bloomDownPipeline: MTLRenderPipelineState
    private let bloomUpPipeline: MTLRenderPipelineState
    /// Half-resolution bloom chain; level i is (w, h) / 2^(i+1).
    private var bloomChain: [MTLTexture] = []
    private let blackTexture: MTLTexture
    static let bloomLevels = 5

    init(device: MTLDevice, options: LaunchOptions) {
        self.device = device
        self.options = options
        guard let q = device.makeCommandQueue() else { fatalError("no command queue") }
        queue = q
        let lib = ShaderLibrary.make(device: device)
        library = lib
        scene = Scene.makeWorld(device: device)
        ocean = Ocean(device: device)

        let lit = MTLRenderPipelineDescriptor()
        lit.label = "lit"
        lit.vertexFunction = ShaderLibrary.function(library, "lit_vertex")
        lit.fragmentFunction = ShaderLibrary.function(library, "lit_fragment")
        lit.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        lit.colorAttachments[1].pixelFormat = Renderer.distanceFormat
        lit.depthAttachmentPixelFormat = Renderer.depthFormat
        litPipeline = try! device.makeRenderPipelineState(descriptor: lit)

        let comp = MTLRenderPipelineDescriptor()
        comp.label = "composite"
        comp.vertexFunction = ShaderLibrary.function(library, "fullscreen_vertex")
        comp.fragmentFunction = ShaderLibrary.function(library, "composite_fragment")
        comp.colorAttachments[0].pixelFormat = Renderer.outputFormat
        compositePipeline = try! device.makeRenderPipelineState(descriptor: comp)

        let sky = MTLRenderPipelineDescriptor()
        sky.label = "skylut"
        sky.vertexFunction = ShaderLibrary.function(library, "fullscreen_vertex")
        sky.fragmentFunction = ShaderLibrary.function(library, "skylut_fragment")
        sky.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        skyLUTPipeline = try! device.makeRenderPipelineState(descriptor: sky)

        let sh = MTLRenderPipelineDescriptor()
        sh.label = "shadow"
        sh.vertexFunction = ShaderLibrary.function(library, "shadow_vertex")
        sh.depthAttachmentPixelFormat = Renderer.depthFormat
        shadowPipeline = try! device.makeRenderPipelineState(descriptor: sh)
        let shDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.depthFormat,
            width: Renderer.shadowSize, height: Renderer.shadowSize, mipmapped: false)
        shDesc.usage = [.renderTarget, .shaderRead]
        shDesc.storageMode = .private
        shadowMap = device.makeTexture(descriptor: shDesc)!
        shadowMap.label = "shadowMap"

        let wp = MTLRenderPipelineDescriptor()
        wp.label = "water"
        wp.vertexFunction = ShaderLibrary.function(library, "water_vertex")
        wp.fragmentFunction = ShaderLibrary.function(library, "water_fragment")
        wp.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        wp.depthAttachmentPixelFormat = Renderer.depthFormat
        waterPipeline = try! device.makeRenderPipelineState(descriptor: wp)
        let wds = MTLDepthStencilDescriptor()
        wds.depthCompareFunction = .less
        wds.isDepthWriteEnabled = false
        waterDepthState = device.makeDepthStencilState(descriptor: wds)!

        let skyBG = MTLRenderPipelineDescriptor()
        skyBG.label = "sky"
        skyBG.vertexFunction = ShaderLibrary.function(library, "sky_vertex")
        skyBG.fragmentFunction = ShaderLibrary.function(library, "sky_fragment")
        skyBG.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        skyBG.colorAttachments[1].pixelFormat = Renderer.distanceFormat
        skyBG.depthAttachmentPixelFormat = Renderer.depthFormat
        skyPipeline = try! device.makeRenderPipelineState(descriptor: skyBG)

        let irr = MTLRenderPipelineDescriptor()
        irr.label = "irradiance"
        irr.vertexFunction = ShaderLibrary.function(lib, "fullscreen_vertex")
        irr.fragmentFunction = ShaderLibrary.function(lib, "irradiance_fragment")
        irr.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        irradiancePipeline = try! device.makeRenderPipelineState(descriptor: irr)
        let irrDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.hdrFormat, width: 32, height: 16, mipmapped: false)
        irrDesc.usage = [.renderTarget, .shaderRead]
        irrDesc.storageMode = .private
        irradianceMap = device.makeTexture(descriptor: irrDesc)!
        irradianceMap.label = "irradiance"

        let lutDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.hdrFormat,
            width: Renderer.skyLUTSize.width, height: Renderer.skyLUTSize.height, mipmapped: true)
        lutDesc.usage = [.renderTarget, .shaderRead]
        lutDesc.storageMode = .private
        skyLUT = device.makeTexture(descriptor: lutDesc)!
        skyLUT.label = "skyLUT"

        let dv = MTLRenderPipelineDescriptor()
        dv.label = "depthviz"
        dv.vertexFunction = ShaderLibrary.function(library, "fullscreen_vertex")
        dv.fragmentFunction = ShaderLibrary.function(library, "depthviz_fragment")
        dv.colorAttachments[0].pixelFormat = Renderer.outputFormat
        depthVizPipeline = try! device.makeRenderPipelineState(descriptor: dv)

        func postPipeline(_ label: String, _ fragment: String, additive: Bool = false) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.label = label
            d.vertexFunction = ShaderLibrary.function(lib, "fullscreen_vertex")
            d.fragmentFunction = ShaderLibrary.function(lib, fragment)
            d.colorAttachments[0].pixelFormat = Renderer.hdrFormat
            if additive {
                d.colorAttachments[0].isBlendingEnabled = true
                d.colorAttachments[0].sourceRGBBlendFactor = .one
                d.colorAttachments[0].destinationRGBBlendFactor = .one
                d.colorAttachments[0].sourceAlphaBlendFactor = .one
                d.colorAttachments[0].destinationAlphaBlendFactor = .one
            }
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        bloomPrefilterPipeline = postPipeline("bloom prefilter", "bloom_prefilter_fragment")
        bloomDownPipeline = postPipeline("bloom down", "bloom_down_fragment")
        bloomUpPipeline = postPipeline("bloom up", "bloom_up_fragment", additive: true)

        let blackDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.hdrFormat, width: 1, height: 1, mipmapped: false)
        blackDesc.usage = .shaderRead
        blackTexture = device.makeTexture(descriptor: blackDesc)!
        var zeros = [UInt16](repeating: 0, count: 4)
        blackTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zeros, bytesPerRow: 8)

        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less
        ds.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: ds)!
        let sds = MTLDepthStencilDescriptor()
        sds.depthCompareFunction = .lessEqual      // sky vertices sit at depth 1: pass only where nothing was drawn
        sds.isDepthWriteEnabled = false
        skyDepthState = device.makeDepthStencilState(descriptor: sds)!
    }

    /// Debug: tonemap `source` (same size as `target`) into `target` using the composite pipeline.
    func encodeDebugView(commandBuffer: MTLCommandBuffer, source: MTLTexture, target: MTLTexture) {
        let comp = MTLRenderPassDescriptor()
        comp.colorAttachments[0].texture = target
        comp.colorAttachments[0].loadAction = .dontCare
        comp.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: comp) else { return }
        enc.label = "debug view"
        enc.setRenderPipelineState(compositePipeline)
        enc.setFragmentTexture(source, index: 0)
        enc.setFragmentTexture(blackTexture, index: 1)
        enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Bake the LUT for the current options and return it (used by --dump-lut).
    func bakeSkyLUTForDebug(commandBuffer: MTLCommandBuffer, camera: Camera) {
        updateFrame(camera: camera, width: 16, height: 9)
        lutSunDir = SIMD3(repeating: .nan)
        updateSkyLUT(commandBuffer: commandBuffer)
    }

    /// Direction TOWARD the sun. Azimuth is clockwise from north (-Z), like compass bearings.
    static func sunDirection(elevationDeg: Float, azimuthDeg: Float) -> SIMD3<Float> {
        let el = elevationDeg * .pi / 180, az = azimuthDeg * .pi / 180
        return SIMD3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
    }

    private func ensureTargets(width: Int, height: Int) {
        if let h = hdrTexture, h.width == width, h.height == height { return }
        func make(_ format: MTLPixelFormat, _ label: String) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            let t = device.makeTexture(descriptor: d)!
            t.label = label
            return t
        }
        hdrTexture = make(Renderer.hdrFormat, "hdr")
        sceneCopy = make(Renderer.hdrFormat, "sceneCopy")
        distanceTexture = make(Renderer.distanceFormat, "distance")
        bloomChain = (0..<Renderer.bloomLevels).map { i in
            let w = max(1, width >> (i + 1)), h = max(1, height >> (i + 1))
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.hdrFormat, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            let t = device.makeTexture(descriptor: d)!
            t.label = "bloom\(i)"
            return t
        }
        depthTexture = make(Renderer.depthFormat, "depth")
    }

    private func updateFrame(camera: Camera, width: Int, height: Int) {
        let aspect = Float(width) / Float(height)
        let viewProj = camera.proj(aspect: aspect) * camera.view
        frame.viewProj = viewProj
        frame.invViewProj = viewProj.inverse
        let t = fixedTime ?? Float(Date().timeIntervalSince(startTime))
        frame.cameraPos = SIMD4(camera.position, t)
        let sun = Renderer.sunDirection(elevationDeg: options.sunElevation, azimuthDeg: options.sunAzimuth)
        frame.sunDir = SIMD4(sun, 1)
        let sunT = Atmosphere.sunTransmittance(elevationDeg: options.sunElevation)
        frame.sunColor = SIMD4(sunT, Atmosphere.sunIrradiance)   // rgb = transmittance, w = irradiance
        // Sun camera: eye one radius from the centre along the sun direction, box = the bounding sphere.
        let R = Renderer.shadowRadius
        let eye = Renderer.shadowCenter + sun * R
        let sunView = lookAt(eye: eye, target: Renderer.shadowCenter, up: SIMD3(0, 1, 0))
        frame.sunViewProj = orthographic(left: -R, right: R, bottom: -R, top: R, near: 0, far: 2 * R) * sunView
        frame.misc.z = ["shadow": 1, "albedo": 2, "ambient": 3][options.debugView ?? ""] ?? 0
        frame.misc.w = 2 * R / Float(Renderer.shadowSize)                     // world size of one shadow texel
        let (w, h) = (Float(width), Float(height))
        frame.screen = SIMD4(w, h, 1 / w, 1 / h)
    }

    /// Re-bake the sky LUT only when the sun has moved (it depends on nothing else).
    private func updateSkyLUT(commandBuffer: MTLCommandBuffer) {
        let sun = SIMD3(frame.sunDir.x, frame.sunDir.y, frame.sunDir.z)
        if simd_distance(sun, lutSunDir) < 1e-5 { return }
        lutSunDir = sun
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = skyLUT
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            enc.label = "sky LUT"
            enc.setRenderPipelineState(skyLUTPipeline)
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "sky LUT mips"
            blit.generateMipmaps(for: skyLUT)
            blit.endEncoding()
        }
        // Convolve the (now mipmapped) LUT into the irradiance map.
        let ip = MTLRenderPassDescriptor()
        ip.colorAttachments[0].texture = irradianceMap
        ip.colorAttachments[0].loadAction = .dontCare
        ip.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: ip) {
            enc.label = "irradiance"
            enc.setRenderPipelineState(irradiancePipeline)
            enc.setFragmentTexture(skyLUT, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
    }

    private func postPass(_ cb: MTLCommandBuffer, _ label: String, _ pipeline: MTLRenderPipelineState,
                          source: MTLTexture, target: MTLTexture, load: MTLLoadAction) {
        let pd = MTLRenderPassDescriptor()
        pd.colorAttachments[0].texture = target
        pd.colorAttachments[0].loadAction = load
        pd.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pd) else { return }
        enc.label = label
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(source, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func encodeBloom(_ cb: MTLCommandBuffer) {
        guard let hdr = hdrTexture, bloomChain.count == Renderer.bloomLevels else { return }
        postPass(cb, "bloom prefilter", bloomPrefilterPipeline, source: hdr, target: bloomChain[0], load: .dontCare)
        for i in 1..<Renderer.bloomLevels {
            postPass(cb, "bloom down \(i)", bloomDownPipeline, source: bloomChain[i - 1], target: bloomChain[i], load: .dontCare)
        }
        for i in stride(from: Renderer.bloomLevels - 2, through: 0, by: -1) {
            postPass(cb, "bloom up \(i)", bloomUpPipeline, source: bloomChain[i + 1], target: bloomChain[i], load: .load)
        }
    }

    /// Encode a full frame that ends by writing `target` (format `outputFormat`).
    func encode(commandBuffer: MTLCommandBuffer, target: MTLTexture, camera: Camera) {
        ensureTargets(width: target.width, height: target.height)
        updateFrame(camera: camera, width: target.width, height: target.height)

        updateSkyLUT(commandBuffer: commandBuffer)

        // 0. Shadow map: scene depth as seen from the sun.
        let sp = MTLRenderPassDescriptor()
        sp.depthAttachment.texture = shadowMap
        sp.depthAttachment.loadAction = .clear
        sp.depthAttachment.clearDepth = 1
        sp.depthAttachment.storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: sp) {
            enc.label = "shadow"
            enc.setRenderPipelineState(shadowPipeline)
            enc.setDepthStencilState(depthState)
            enc.setFrontFacing(.counterClockwise)
            enc.setCullMode(.none)               // terrain is a single-sided sheet; normal-offset bias handles acne
            enc.setDepthBias(1.0, slopeScale: 1.5, clamp: 0)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            // Cull against the SUN's box, not the camera's: things behind you can still shadow what you see.
            let sunFrustum = Frustum(viewProj: frame.sunViewProj)
            lastShadowDraws = 0
            for item in scene.items {
                let b = item.worldBounds
                guard !item.hidden, sunFrustum.intersects(min: b.min, max: b.max) else { continue }
                lastShadowDraws += 1
                var u = item.uniforms
                enc.setVertexBuffer(item.mesh.vertexBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.indexCount, indexType: .uint32,
                                          indexBuffer: item.mesh.indexBuffer, indexBufferOffset: 0)
            }
            enc.endEncoding()
        }

        // 1. Opaque geometry into HDR.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = hdrTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[1].texture = distanceTexture
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].clearColor = MTLClearColor(red: 1e5, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[1].storeAction = .store
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store          // the water pass depth-tests against it
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            enc.label = "opaque"
            enc.setRenderPipelineState(litPipeline)
            enc.setDepthStencilState(depthState)
            enc.setFrontFacing(.counterClockwise)
            enc.setCullMode(.back)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setFragmentTexture(shadowMap, index: 0)
            enc.setFragmentTexture(skyLUT, index: 1)
            enc.setFragmentTexture(irradianceMap, index: 4)
            let camFrustum = Frustum(viewProj: frame.viewProj)
            lastOpaqueDraws = 0
            for item in scene.items {
                let b = item.worldBounds
                guard !item.hidden, camFrustum.intersects(min: b.min, max: b.max) else { continue }
                lastOpaqueDraws += 1
                var u = item.uniforms
                enc.setVertexBuffer(item.mesh.vertexBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.setFragmentBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.indexCount, indexType: .uint32,
                                          indexBuffer: item.mesh.indexBuffer, indexBufferOffset: 0)
            }
            // Sky last, so the depth test rejects it everywhere geometry was drawn (saves shading those pixels).
            enc.label = "opaque + sky"
            enc.setRenderPipelineState(skyPipeline)
            enc.setDepthStencilState(skyDepthState)
            enc.setCullMode(.none)
            enc.setFragmentTexture(skyLUT, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // 1b. Snapshot the colour so later passes (water) can read the scene while drawing over it.
        if let blit = commandBuffer.makeBlitCommandEncoder(), let src = hdrTexture, let dst = sceneCopy {
            blit.label = "scene copy"
            blit.copy(from: src, to: dst)
            blit.endEncoding()
        }

        // 1c. Water: drawn over the HDR colour, depth-tested against the opaque depth, reading the scene copy.
        let wpass = MTLRenderPassDescriptor()
        wpass.colorAttachments[0].texture = hdrTexture
        wpass.colorAttachments[0].loadAction = .load
        wpass.colorAttachments[0].storeAction = .store
        wpass.depthAttachment.texture = depthTexture
        wpass.depthAttachment.loadAction = .load
        wpass.depthAttachment.storeAction = .dontCare
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: wpass) {
            enc.label = "water"
            enc.setRenderPipelineState(waterPipeline)
            enc.setDepthStencilState(waterDepthState)
            enc.setCullMode(.none)
            var u = ocean.uniforms(camera: camera)
            enc.setVertexBuffer(ocean.mesh.vertexBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setFragmentTexture(skyLUT, index: 1)
            enc.setFragmentTexture(sceneCopy, index: 2)
            enc.setFragmentTexture(distanceTexture, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: ocean.mesh.indexCount, indexType: .uint32,
                                      indexBuffer: ocean.mesh.indexBuffer, indexBufferOffset: 0)
            enc.endEncoding()
        }

        // 1d. Bloom chain.
        encodeBloom(commandBuffer)

        // 2. Composite (tonemap) into the target.
        let comp = MTLRenderPassDescriptor()
        comp.colorAttachments[0].texture = target
        comp.colorAttachments[0].loadAction = .dontCare
        comp.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: comp) {
            enc.label = "composite"
            if options.debugView == "depth" {
                enc.setRenderPipelineState(depthVizPipeline)
                enc.setFragmentTexture(distanceTexture, index: 0)
            } else {
                enc.setRenderPipelineState(compositePipeline)
                enc.setFragmentTexture(hdrTexture, index: 0)
                enc.setFragmentTexture(bloomChain.first, index: 1)
            }
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
    }
}
