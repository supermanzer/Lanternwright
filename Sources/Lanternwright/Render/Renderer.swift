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

    /// Every world's scene, built once. The renderer draws whichever `world` is current.
    let scenes: [WorldKind: Scene]
    var world: WorldKind = .varrow
    var scene: Scene { scenes[world]! }
    var params: WorldParams { WorldParams.make(world, options: options) }
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
    private let grassPipeline: MTLRenderPipelineState
    /// Terrain heights (r) and path weight (g) on a 513 x 513 grid, for the grass vertex shader.
    private var terrainTextures: [WorldKind: MTLTexture] = [:]
    private var grassCellsPerSide: Int { Int((2 * LookDefaults.grassRadius / LookDefaults.grassCell).rounded()) }
    private let waterPipeline: MTLRenderPipelineState
    private let waterDepthState: MTLDepthStencilState
    let ocean: Ocean
    private let shadowPipeline: MTLRenderPipelineState
    /// Sun shadow map. The sun camera is orthographic and fitted to a sphere around the island.
    let shadowMap: MTLTexture
    static let shadowSize = 4096
    /// Two nearer cascades that follow the camera (see `fitCascade`).
    let shadowNear: MTLTexture
    let shadowMid: MTLTexture
    static let nearSize = 2048, midSize = 2048
    static let nearRadius: Float = 14, midRadius: Float = 70
    static let shadowCenter = SIMD3<Float>(-15, 30, -60)
    static let shadowRadius: Float = 340
    private let depthState: MTLDepthStencilState
    private let skyDepthState: MTLDepthStencilState
    /// Lat-long sky radiance (see Shaders/Sky.swift). Mipmapped: high mips double as diffuse irradiance.
    let skyLUT: MTLTexture
    /// What the sky LUT was baked for: sun direction and irradiance (it depends on nothing else).
    private var lutKey = SIMD4<Float>(repeating: .nan)
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
    private let godRaysPipeline: MTLRenderPipelineState
    private let mistPipeline: MTLRenderPipelineState
    private let crystalPipeline: MTLRenderPipelineState
    private let aoPipeline: MTLRenderPipelineState
    private let aoBlurPipeline: MTLRenderPipelineState
    private let aoApplyPipeline: MTLRenderPipelineState
    private var aoTexture: MTLTexture?
    private var aoBlurred: MTLTexture?
    private var raysTexture: MTLTexture?
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
        scenes = Dictionary(uniqueKeysWithValues: WorldKind.allCases.map { ($0, Scene.make($0, device: device)) })
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
        func cascadeTexture(_ size: Int, _ label: String) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.depthFormat, width: size, height: size, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
            let t = device.makeTexture(descriptor: d)!
            t.label = label
            return t
        }
        shadowNear = cascadeTexture(Renderer.nearSize, "shadowNear")
        shadowMid = cascadeTexture(Renderer.midSize, "shadowMid")

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

        let gr = MTLRenderPipelineDescriptor()
        gr.label = "grass"
        gr.vertexFunction = ShaderLibrary.function(lib, "grass_vertex")
        gr.fragmentFunction = ShaderLibrary.function(lib, "lit_fragment")
        gr.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        gr.colorAttachments[1].pixelFormat = Renderer.distanceFormat
        gr.depthAttachmentPixelFormat = Renderer.depthFormat
        grassPipeline = try! device.makeRenderPipelineState(descriptor: gr)

        // Terrain heights (r) and path weight (g) per world, for the grass vertex shader.
        for (kind, sc) in scenes {
            let tDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: Terrain.gridCount, height: Terrain.gridCount, mipmapped: false)
            tDesc.usage = .shaderRead
            let tex = device.makeTexture(descriptor: tDesc)!
            tex.label = "terrain heights \(kind.rawValue)"
            let n = Terrain.gridCount
            var texels = [Float](repeating: 0, count: n * n * 4)
            for j in 0..<n {
                for i in 0..<n {
                    let x = Terrain.origin + Float(i) * Terrain.spacing, z = Terrain.origin + Float(j) * Terrain.spacing
                    texels[(j * n + i) * 4] = sc.terrain.sampleHeight(x: x, z: z)
                    texels[(j * n + i) * 4 + 1] = sc.terrain.pathWeight(x: x, z: z)
                    // Grass-free zone around every landmark pad (about 0.62 of its radius, softly edged), so floors stay clear.
                    var bare: Float = 0
                    for pad in sc.terrain.spec.pads {
                        let d = length(SIMD2(x - pad.center.x, z - pad.center.z))
                        let r = pad.radius * 0.62
                        bare = max(bare, 1 - smoothstep(r - 1.5, r + 1.5, d))
                    }
                    texels[(j * n + i) * 4 + 2] = bare
                }
            }
            tex.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, withBytes: texels, bytesPerRow: n * 16)
            terrainTextures[kind] = tex
        }

        let cr = MTLRenderPipelineDescriptor()
        cr.label = "crystal"
        cr.vertexFunction = ShaderLibrary.function(lib, "lit_vertex")
        cr.fragmentFunction = ShaderLibrary.function(lib, "crystal_fragment")
        cr.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        cr.depthAttachmentPixelFormat = Renderer.depthFormat
        crystalPipeline = try! device.makeRenderPipelineState(descriptor: cr)

        let mist = MTLRenderPipelineDescriptor()
        mist.label = "mist"
        mist.vertexFunction = ShaderLibrary.function(lib, "mist_vertex")
        mist.fragmentFunction = ShaderLibrary.function(lib, "mist_fragment")
        mist.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        mist.colorAttachments[0].isBlendingEnabled = true
        mist.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        mist.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        mist.colorAttachments[0].sourceAlphaBlendFactor = .zero
        mist.colorAttachments[0].destinationAlphaBlendFactor = .one
        mist.depthAttachmentPixelFormat = Renderer.depthFormat
        mistPipeline = try! device.makeRenderPipelineState(descriptor: mist)

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
        func monoPipeline(_ label: String, _ fragment: String, format: MTLPixelFormat) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.label = label
            d.vertexFunction = ShaderLibrary.function(lib, "fullscreen_vertex")
            d.fragmentFunction = ShaderLibrary.function(lib, fragment)
            d.colorAttachments[0].pixelFormat = format
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        aoPipeline = monoPipeline("ssao", "ssao_fragment", format: .r16Float)
        aoBlurPipeline = monoPipeline("ssao blur", "ssao_blur_fragment", format: .r16Float)
        aoApplyPipeline = monoPipeline("ssao apply", "ssao_apply_fragment", format: Renderer.hdrFormat)
        godRaysPipeline = postPipeline("god rays", "godrays_fragment")
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
        enc.setFragmentTexture(blackTexture, index: 2)
        enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Bake the LUT for the current options and return it (used by --dump-lut).
    func bakeSkyLUTForDebug(commandBuffer: MTLCommandBuffer, camera: Camera) {
        updateFrame(camera: camera, width: 16, height: 9)
        lutKey = SIMD4(repeating: .nan)
        updateSkyLUT(commandBuffer: commandBuffer)
    }

    /// Direction TOWARD the sun. Azimuth is clockwise from north (-Z), like compass bearings.
    static func sunDirection(elevationDeg: Float, azimuthDeg: Float) -> SIMD3<Float> {
        let el = elevationDeg * .pi / 180, az = azimuthDeg * .pi / 180
        return SIMD3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
    }

    private func ensureTargets(width: Int, height: Int) {
        if let h = hdrTexture, h.width == width, h.height == height { return }
        func make(_ format: MTLPixelFormat, _ label: String, _ w: Int? = nil, _ h: Int? = nil) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w ?? width, height: h ?? height, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            let t = device.makeTexture(descriptor: d)!
            t.label = label
            return t
        }
        hdrTexture = make(Renderer.hdrFormat, "hdr")
        sceneCopy = make(Renderer.hdrFormat, "sceneCopy")
        distanceTexture = make(Renderer.distanceFormat, "distance")
        raysTexture = make(Renderer.hdrFormat, "rays", width / 2, height / 2)
        aoTexture = make(.r16Float, "ao", width / 2, height / 2)
        aoBlurred = make(.r16Float, "ao blurred", width / 2, height / 2)
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
        let wp = params
        let sun = Renderer.sunDirection(elevationDeg: wp.sunElevation, azimuthDeg: wp.sunAzimuth)
        frame.sunDir = SIMD4(sun, 1)
        let sunT = wp.lightTint ?? Atmosphere.sunTransmittance(elevationDeg: wp.sunElevation)
        frame.sunColor = SIMD4(sunT, wp.sunIrradiance)   // rgb = transmittance (or a fixed tint), w = irradiance
        frame.fogParams = SIMD4(wp.fogDensity, wp.fogFalloff, wp.exposure, wp.bloom)
        frame.worldA = SIMD4(wp.starAmount, wp.lightDiskScale, wp.secondMoon?.radius ?? 0, wp.lightDiskRadius)
        if let m = wp.secondMoon {
            let d = Renderer.sunDirection(elevationDeg: m.elevation, azimuthDeg: m.azimuth)
            frame.moonB = SIMD4(d, 0)
        } else {
            frame.moonB = SIMD4(0, 1, 0, 0)
        }
        frame.worldB = SIMD4(wp.palette, 0, 0, 0)
        // Sun camera: eye one radius from the centre along the sun direction, box = the bounding sphere.
        let R = Renderer.shadowRadius
        let eye = Renderer.shadowCenter + sun * R
        let sunView = lookAt(eye: eye, target: Renderer.shadowCenter, up: SIMD3(0, 1, 0))
        frame.sunViewProj = orthographic(left: -R, right: R, bottom: -R, top: R, near: 0, far: 2 * R) * sunView
        frame.misc.z = ["shadow": 1, "albedo": 2, "ambient": 3, "cascade": 4, "ao": 5][options.debugView ?? ""] ?? 0
        frame.misc.w = 2 * R / Float(Renderer.shadowSize)                     // world size of one shadow texel
        let near = fitCascade(center: camera.position, radius: Renderer.nearRadius, size: Renderer.nearSize, sun: sun)
        let mid = fitCascade(center: camera.position, radius: Renderer.midRadius, size: Renderer.midSize, sun: sun)
        frame.sunViewProj0 = near.viewProj
        frame.sunViewProj1 = mid.viewProj
        frame.casTexel = SIMD4(near.texel, mid.texel, 2 * R / Float(Renderer.shadowSize), 0)
        frame.casRange = SIMD4(near.range, mid.range, 2 * R, 0)
        frame.casRadius = SIMD4(Renderer.nearRadius, Renderer.midRadius, R, wp.godRays)
        frame.casTexel.w = LookDefaults.aoRadius       // SSAO radius (m)
        frame.casRange.w = options.debugView == "noao" ? 0 : LookDefaults.aoStrength   // SSAO strength
        let (w, h) = (Float(width), Float(height))
        frame.screen = SIMD4(w, h, 1 / w, 1 / h)
    }

    /// Re-bake the sky LUT only when the light has changed (it depends on nothing else): a different direction or
    /// strength, which happens when the sun moves or when you travel to another world.
    private func updateSkyLUT(commandBuffer: MTLCommandBuffer) {
        let key = SIMD4(frame.sunDir.x, frame.sunDir.y, frame.sunDir.z, frame.sunColor.w)
        if simd_distance(key, lutKey) < 1e-5 { return }
        lutKey = key
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

    /// Fit an orthographic sun camera to a sphere around `center`. The centre is snapped to whole shadow texels in light
    /// space, so as the camera moves the shadow map's sampling grid stays fixed relative to the world and shadow edges
    /// don't crawl or shimmer. Casters up to 300 m toward the sun are included (a hill can shadow your feet).
    private func fitCascade(center c: SIMD3<Float>, radius R: Float, size: Int, sun: SIMD3<Float>)
        -> (viewProj: float4x4, texel: Float, range: Float) {
        let casterRange: Float = 300
        let worldUp = SIMD3<Float>(0, 1, 0)
        let fwd = -sun
        let right = normalize(cross(fwd, worldUp)), up = cross(right, fwd)
        let texel = 2 * R / Float(size)
        let cx = dot(c, right), cy = dot(c, up)
        let snapped = c + right * ((cx / texel).rounded(.down) * texel - cx) + up * ((cy / texel).rounded(.down) * texel - cy)
        let eye = snapped + sun * (R + casterRange)
        let far = 2 * R + casterRange
        let vp = orthographic(left: -R, right: R, bottom: -R, top: R, near: 0, far: far) * lookAt(eye: eye, target: snapped, up: worldUp)
        return (vp, texel, far)
    }

    /// Encode a full frame that ends by writing `target` (format `outputFormat`).
    func encode(commandBuffer: MTLCommandBuffer, target: MTLTexture, camera: Camera) {
        ensureTargets(width: target.width, height: target.height)
        updateFrame(camera: camera, width: target.width, height: target.height)

        updateSkyLUT(commandBuffer: commandBuffer)

        // 0. Shadow maps: scene depth as seen from the sun, once per cascade (far, mid, near).
        lastShadowDraws = 0
        let cascades: [(MTLTexture, float4x4)] = [(shadowMap, frame.sunViewProj), (shadowMid, frame.sunViewProj1), (shadowNear, frame.sunViewProj0)]
        for (texture, matrix) in cascades {
            let sp = MTLRenderPassDescriptor()
            sp.depthAttachment.texture = texture
            sp.depthAttachment.loadAction = .clear
            sp.depthAttachment.clearDepth = 1
            sp.depthAttachment.storeAction = .store
            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: sp) else { continue }
            enc.label = "shadow \(texture.width)"
            enc.setRenderPipelineState(shadowPipeline)
            enc.setDepthStencilState(depthState)
            enc.setFrontFacing(.counterClockwise)
            enc.setCullMode(.none)               // terrain is a single-sided sheet; normal-offset bias handles acne
            enc.setDepthBias(1.0, slopeScale: 1.5, clamp: 0)
            var f = frame
            f.sunViewProj = matrix               // shadow_vertex reads sunViewProj: point it at this cascade
            enc.setVertexBytes(&f, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            // Cull against the SUN's box, not the camera's: things behind you can still shadow what you see.
            let sunFrustum = Frustum(viewProj: matrix)
            for item in scene.items {
                let b = item.worldBounds
                guard !item.hidden, !item.refractive, sunFrustum.intersects(min: b.min, max: b.max) else { continue }
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
            enc.setFragmentTexture(shadowNear, index: 6)
            enc.setFragmentTexture(shadowMid, index: 7)
            enc.setFragmentTexture(skyLUT, index: 1)
            enc.setFragmentTexture(irradianceMap, index: 4)
            let camFrustum = Frustum(viewProj: frame.viewProj)
            lastOpaqueDraws = 0
            for item in scene.items {
                let b = item.worldBounds
                guard !item.hidden, !item.refractive, camFrustum.intersects(min: b.min, max: b.max) else { continue }
                lastOpaqueDraws += 1
                var u = item.uniforms
                enc.setVertexBuffer(item.mesh.vertexBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.setFragmentBytes(&u, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.indexCount, indexType: .uint32,
                                          indexBuffer: item.mesh.indexBuffer, indexBufferOffset: 0)
            }
            // Grass: one instanced draw, 7 vertices per blade, positions generated in the vertex shader.
            enc.setRenderPipelineState(grassPipeline)
            enc.setCullMode(.none)
            var gp = SIMD4<Float>(LookDefaults.grassCell, Float(grassCellsPerSide), LookDefaults.grassRadius, 0)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setVertexBytes(&gp, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
            enc.setVertexTexture(terrainTextures[world], index: 5)
            var identity = ObjectUniforms()
            enc.setFragmentBytes(&identity, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 7, instanceCount: grassCellsPerSide * grassCellsPerSide)
            enc.setCullMode(.back)

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
            // Glass (crystal trees etc.): refracts the scene copy, so it is drawn after the water has been laid down.
            let glass = scene.items.filter { $0.refractive && !$0.hidden }
            if !glass.isEmpty {
                enc.setRenderPipelineState(crystalPipeline)
                // Depth WRITE on and back faces culled. This is a performance rule on Apple's tile-based GPU, measured here:
                // a depth-tested pass that does not write depth cannot discard hidden fragments, and drawing both faces of
                // closed prisms shades everything twice. Together they made the glass cost 6-11 ms; with both, it is free.
                enc.setDepthStencilState(depthState)
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
            enc.setRenderPipelineState(mistPipeline)
            for (height, strength, seed) in [(Float(1.6), Float(0.85), Float(0.0)), (Float(6.5), Float(0.5), Float(0.37))] {
                var mu = ocean.uniforms(camera: camera, level: height)
                mu.tint = SIMD4(strength, 0, 0, seed)
                enc.setVertexBytes(&mu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.setFragmentBytes(&mu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: ocean.mesh.indexCount, indexType: .uint32,
                                          indexBuffer: ocean.mesh.indexBuffer, indexBufferOffset: 0)
            }
            enc.endEncoding()
        }

        // 1c'. SSAO: occlusion from the distance buffer (half res), blurred, multiplied into the scene.
        if let ao = aoTexture, let blurred = aoBlurred, let dist = distanceTexture, let hdr = hdrTexture, let copy = sceneCopy {
            if let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.label = "scene copy for AO"
                blit.copy(from: hdr, to: copy)
                blit.endEncoding()
            }
            func run(_ label: String, _ pipeline: MTLRenderPipelineState, target: MTLTexture, textures: [MTLTexture], needsFrame: Bool) {
                let pd = MTLRenderPassDescriptor()
                pd.colorAttachments[0].texture = target
                pd.colorAttachments[0].loadAction = .dontCare
                pd.colorAttachments[0].storeAction = .store
                guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pd) else { return }
                enc.label = label
                enc.setRenderPipelineState(pipeline)
                for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
                if needsFrame { enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1) }
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
            run("ssao", aoPipeline, target: ao, textures: [dist], needsFrame: true)
            run("ssao blur", aoBlurPipeline, target: blurred, textures: [ao, dist], needsFrame: false)
            run("ssao apply", aoApplyPipeline, target: hdr, textures: [copy, blurred], needsFrame: true)
        }

        // 1d. God rays (half resolution), then the bloom chain.
        if let rays = raysTexture, let hdr = hdrTexture, let dist = distanceTexture {
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = rays
            rp.colorAttachments[0].loadAction = .dontCare
            rp.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rp) {
                enc.label = "god rays"
                enc.setRenderPipelineState(godRaysPipeline)
                enc.setFragmentTexture(hdr, index: 0)
                enc.setFragmentTexture(dist, index: 1)
                enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        }
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
                enc.setFragmentTexture(raysTexture, index: 2)
            }
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
    }
}
