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
    /// The game's own clock (F02 A3): the wind, the grass, the trees and the audio all read the same one, so a gust you see is the gust you hear. Nil in tools that have no game.
    var worldTime: Float?
    var clock: Float { fixedTime ?? worldTime ?? Float(Date().timeIntervalSince(startTime)) }
    /// The clock the game hands the renderer for the wind (the game's own, the same one the audio's wind reads).
    static func windClock(game: Game) -> Float { game.time }
    /// Home-island atmosphere driven by the game: 1 = full mist, lower after the first trip through the lens; beam 0...1 = lit lighthouse sweep.
    var mistScale: Float = 1
    var beamIntensity: Float = 0
    static let beamRate: Float = 0.22      // radians per second: a full turn every ~29 s, each beam passing you every ~14 s

    var frame = FrameUniforms()
    /// Draw calls issued last frame (opaque / shadow), for diagnostics.
    var lastOpaqueDraws = 0
    var lastShadowDraws = 0
    let litPipeline: MTLRenderPipelineState
    /// The same shader with the dithered LOD cross-fade compiled in: used for the tree LOD objects only (R09).
    let litLODPipeline: MTLRenderPipelineState
    let compositePipeline: MTLRenderPipelineState
    let skyLUTPipeline: MTLRenderPipelineState
    let irradiancePipeline: MTLRenderPipelineState
    /// Cosine-convolved sky (32x16): diffuse ambient light for any normal. Rebuilt whenever the LUT is.
    let irradianceMap: MTLTexture
    let skyPipeline: MTLRenderPipelineState
    let grassPipeline: MTLRenderPipelineState
    /// Terrain heights (r) and path weight (g) on a 513 x 513 grid, for the grass vertex shader.
    var terrainTextures: [WorldKind: MTLTexture] = [:]
    var grassCellsPerSide: Int { Int((2 * LookDefaults.grassRadius / LookDefaults.grassCell).rounded()) }
    let waterPipeline: MTLRenderPipelineState
    let waterDepthState: MTLDepthStencilState
    let ocean: Ocean
    let shadowPipeline: MTLRenderPipelineState
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
    let depthState: MTLDepthStencilState
    let skyDepthState: MTLDepthStencilState
    /// Lat-long sky radiance (see Shaders/Sky.swift). Mipmapped: high mips double as diffuse irradiance.
    let skyLUT: MTLTexture
    /// What the sky LUT was baked for: sun direction and irradiance (it depends on nothing else).
    var lutKey = SIMD4<Float>(repeating: .nan)
    static let skyLUTSize = (width: 256, height: 128)
    let startTime = Date()

    var hdrTexture: MTLTexture?
    // Temporal anti-aliasing (F02 R1, see Shaders/TAA.swift). Off in headless screenshots unless `--taa`, so existing baselines stay comparable.
    var taaEnabled = false
    var taaSharpness: Float = 0.8
    /// Weight of the new frame when still / at speed, and the colour-box width in sigmas (see TAA.swift). Tools can override them with TAA_ALPHA="a b" TAA_GAMMA="g" TAA_SHARP="s".
    var taaTuning = SIMD4<Float>(0.20, 0.35, 1.5, 0)
    var taaHistory: MTLTexture?, taaResolved: MTLTexture?
    var taaHistoryValid = false
    var taaFrameIndex = 0
    var taaPrevViewProj = matrix_identity_float4x4
    var taaCurrentViewProj = matrix_identity_float4x4          // this frame's UNjittered view-projection
    var taaJitter = SIMD2<Float>(0, 0)                          // this frame's sub-pixel offset, in pixels
    var taaLastCameraPos: SIMD3<Float>?
    var taaLastFov: Float = 0
    let taaResolvePipeline: MTLRenderPipelineState
    let taaSharpenPipeline: MTLRenderPipelineState
    /// The sub-pixel jitter of frame `i`: Halton (2, 3) over 8 samples, offsets in (-0.5, 0.5) pixels.
    static func jitterOffset(frame i: Int) -> SIMD2<Float> {
        func halton(_ i: Int, _ b: Int) -> Float { var f: Float = 1, r: Float = 0, n = i; while n > 0 { f /= Float(b); r += f * Float(n % b); n /= b }; return r }
        let k = i % 8 + 1
        return SIMD2(halton(k, 2) - 0.5, halton(k, 3) - 0.5)
    }
    var taaLastWorld: WorldKind?
    /// Forget the history (a camera cut: travel between worlds, a teleport, a resize). The next frame is rendered without temporal blending.
    func resetTAA() { taaHistoryValid = false }
    var depthTexture: MTLTexture?
    /// Straight-line camera distance per pixel (1e5 for sky). Read by the water pass.
    var distanceTexture: MTLTexture?
    /// Copy of the HDR colour after opaque + sky; the water pass samples it for refraction.
    var sceneCopy: MTLTexture?
    let depthVizPipeline: MTLRenderPipelineState
    let bloomPrefilterPipeline: MTLRenderPipelineState
    /// Debug (`--no-grass`, and the grass coverage selftest): draw no grass.
    nonisolated(unsafe) static var skipGrass = false
    let godRaysPipeline: MTLRenderPipelineState
    let mistPipeline: MTLRenderPipelineState
    /// The lighthouse beams and the glow at the lens (additive; see Beam.swift) and their ribbon mesh.
    let beamPipeline: MTLRenderPipelineState
    let beamMesh: Mesh
    let crystalPipeline: MTLRenderPipelineState
    let aoPipeline: MTLRenderPipelineState
    let aoBlurPipeline: MTLRenderPipelineState
    let aoApplyPipeline: MTLRenderPipelineState
    var aoTexture: MTLTexture?
    var aoBlurred: MTLTexture?
    var raysTexture: MTLTexture?
    let bloomDownPipeline: MTLRenderPipelineState
    let bloomUpPipeline: MTLRenderPipelineState
    /// Half-resolution bloom chain; level i is (w, h) / 2^(i+1).
    var bloomChain: [MTLTexture] = []
    /// Eye adaptation: a 64 x 36 grid of mean log luminance, read back on the CPU one frame late.
    var lumaPipeline: MTLRenderPipelineState!
    var lumaTexture: MTLTexture?
    var lumaLock = NSLock()
    var measuredLuma: Float?
    var adaptation = EyeAdaptation()
    var lastAdaptTime: Float?
    /// Windowed play adapts; screenshots keep the authored exposure unless `--auto-exposure`.
    var autoExposure = true
    var currentAutoExposure: Float { adaptation.exposure }
    let blackTexture: MTLTexture
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
        lit.fragmentFunction = ShaderLibrary.function(library, "lit_fragment", lodDither: false)
        lit.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        lit.colorAttachments[1].pixelFormat = Renderer.distanceFormat
        lit.depthAttachmentPixelFormat = Renderer.depthFormat
        litPipeline = try! device.makeRenderPipelineState(descriptor: lit)
        lit.label = "lit (lod dither)"
        lit.fragmentFunction = ShaderLibrary.function(library, "lit_fragment", lodDither: true)
        litLODPipeline = try! device.makeRenderPipelineState(descriptor: lit)

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
        gr.fragmentFunction = ShaderLibrary.function(lib, "lit_fragment", lodDither: false)
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
                    texels[(j * n + i) * 4 + 3] = sc.terrain.duffAt(x: x, z: z)
                }
            }
            tex.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, withBytes: texels, bytesPerRow: n * 16)
            terrainTextures[kind] = tex
        }

        let cr = MTLRenderPipelineDescriptor()
        cr.label = "crystal"
        cr.vertexFunction = ShaderLibrary.function(lib, "lit_vertex")
        cr.fragmentFunction = ShaderLibrary.function(lib, "crystal_fragment", lodDither: true)
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

        let beam = MTLRenderPipelineDescriptor()
        beam.label = "beam"
        beam.vertexFunction = ShaderLibrary.function(lib, "beam_vertex")
        beam.fragmentFunction = ShaderLibrary.function(lib, "beam_fragment")
        beam.colorAttachments[0].pixelFormat = Renderer.hdrFormat
        beam.colorAttachments[0].isBlendingEnabled = true
        beam.colorAttachments[0].sourceRGBBlendFactor = .one
        beam.colorAttachments[0].destinationRGBBlendFactor = .one
        beam.colorAttachments[0].sourceAlphaBlendFactor = .zero
        beam.colorAttachments[0].destinationAlphaBlendFactor = .one
        beam.depthAttachmentPixelFormat = Renderer.depthFormat
        beamPipeline = try! device.makeRenderPipelineState(descriptor: beam)
        var bv: [Vertex] = [], bi: [UInt32] = []
        for k in 0...96 {                                                   // a ribbon: 97 stations, two vertices each (x = along 0...1, y = side -1 / +1)
            let s = Float(k) / 96
            for side: Float in [-1, 1] { bv.append(Vertex(position: SIMD4(s, side, 0, 1), normal: SIMD4(0, 1, 0, 0), color: SIMD4(1, 1, 1, 1))) }
            if k > 0 { let a = UInt32(2 * (k - 1)); bi += [a, a + 1, a + 2, a + 1, a + 3, a + 2] }
        }
        beamMesh = Mesh(device: device, vertices: bv, indices: bi, label: "beam ribbon")

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
        lumaPipeline = monoPipeline("luma", "luma_fragment", format: .rg32Float)
        aoPipeline = monoPipeline("ssao", "ssao_fragment", format: .r16Float)
        aoBlurPipeline = monoPipeline("ssao blur", "ssao_blur_fragment", format: .r16Float)
        aoApplyPipeline = monoPipeline("ssao apply", "ssao_apply_fragment", format: Renderer.hdrFormat)
        taaResolvePipeline = monoPipeline("taa resolve", "taa_resolve_fragment", format: Renderer.hdrFormat)
        taaSharpenPipeline = monoPipeline("taa sharpen", "taa_sharpen_fragment", format: Renderer.hdrFormat)
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
        taaEnabled = options.taa
        let env = ProcessInfo.processInfo.environment
        if let a = env["TAA_ALPHA"] { let v = a.split(separator: " ").compactMap { Float($0) }; if v.count == 2 { taaTuning.x = v[0]; taaTuning.y = v[1] } }
        if let g = env["TAA_GAMMA"], let v = Float(g) { taaTuning.z = v }
        if let sh = env["TAA_SHARP"], let v = Float(sh) { taaSharpness = v }
    }

    /// Encode a full frame that ends by writing `target` (format `outputFormat`).
    func encode(commandBuffer: MTLCommandBuffer, target: MTLTexture, camera: Camera) {
        scene.applyLOD(eye: camera.position)
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
                guard !item.hidden, !item.refractive, item.uniforms.lod.w < 0.5, sunFrustum.intersects(min: b.min, max: b.max) else { continue }          // needle cards cast no shadow (the sprays of the same trees do)
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
            // Two sweeps: ordinary objects first (a pipeline without any discard keeps early depth rejection), then the tree LOD objects, whose
            // fragments dither between levels and so need the variant with `discard_fragment`.
            for lodSweep in [false, true] {
                if lodSweep { enc.setRenderPipelineState(litLODPipeline) }
                for item in scene.items {
                    let b = item.worldBounds
                    guard !item.hidden, !item.refractive, (item.uniforms.lod.x > 0.5) == lodSweep, camFrustum.intersects(min: b.min, max: b.max) else { continue }
                    lastOpaqueDraws += 1
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
            enc.setRenderPipelineState(grassPipeline)
            enc.setCullMode(.none)
            let windNow = Wind.strength(at: camera.position, time: clock)
            var gp = [SIMD4<Float>(LookDefaults.grassCell, Float(grassCellsPerSide), LookDefaults.grassRadius, 0),
                      SIMD4<Float>(Wind.direction.x, Wind.direction.y, windNow, 0)]
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            enc.setVertexBytes(&gp, length: MemoryLayout<SIMD4<Float>>.stride * gp.count, index: 3)
            enc.setVertexTexture(terrainTextures[world], index: 5)
            var identity = ObjectUniforms()
            enc.setFragmentBytes(&identity, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
            if !Renderer.skipGrass { enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 7, instanceCount: grassCellsPerSide * grassCellsPerSide) }
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
        wpass.depthAttachment.storeAction = .store          // F02 R1: the temporal resolve reprojects from this depth (water and glass included)
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
            let beamHeading = 0.6 + clock * Renderer.beamRate          // the mist sheets' beam sector direction
            // The glass loop above left the last crystal's vertices bound at slot 0: the sheets are the ocean disc, so bind ITS vertices again (F03 #47: the mist was
            // drawn with the ocean's indices over a crystal tree's vertices, a faint faceted ghost in the sky near the horizon).
            enc.setVertexBuffer(ocean.mesh.vertexBuffer, offset: 0, index: 0)
            enc.setRenderPipelineState(mistPipeline)
            for (height, strength, seed) in [(Float(1.6), Float(0.85), Float(0.0)), (Float(6.5), Float(0.5), Float(0.37))] {
                var mu = ocean.uniforms(camera: camera, level: height)
                mu.tint = SIMD4(strength * mistScale, beamHeading, world == .varrow ? beamIntensity : 0, seed)
                mu.emissive = SIMD4(Landmarks.lensPosition, 0)
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

        // 1c''. Temporal anti-aliasing: resolve the jittered frame against the history, then sharpen into the scene HDR that bloom and the composite read.
        if taaEnabled, let hdr = hdrTexture, let hist = taaHistory, let res = taaResolved, let depth = depthTexture {
            var tu = TaaUniforms(prevViewProj: taaPrevViewProj, invViewProj: taaCurrentViewProj.inverse,
                                 params: SIMD4(taaJitter.x, taaJitter.y, taaHistoryValid ? 1 : 0, taaSharpness),
                                 screen: SIMD4(Float(hdr.width), Float(hdr.height), 1 / Float(hdr.width), 1 / Float(hdr.height)), tuning: taaTuning)
            func fullscreen(_ label: String, _ pipeline: MTLRenderPipelineState, target: MTLTexture, textures: [MTLTexture]) {
                let pd = MTLRenderPassDescriptor()
                pd.colorAttachments[0].texture = target
                pd.colorAttachments[0].loadAction = .dontCare
                pd.colorAttachments[0].storeAction = .store
                guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pd) else { return }
                enc.label = label
                enc.setRenderPipelineState(pipeline)
                enc.setFragmentBytes(&tu, length: MemoryLayout<TaaUniforms>.stride, index: 0)
                for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
            fullscreen("taa resolve", taaResolvePipeline, target: res, textures: [hdr, hist, depth])
            fullscreen("taa sharpen", taaSharpenPipeline, target: hdr, textures: [res])
            swap(&taaHistory, &taaResolved)                    // the resolved frame is next frame's history
            taaPrevViewProj = taaCurrentViewProj
            taaHistoryValid = true
        }

        // 1c-3. The lit lighthouse's beams and the glow at the lens, added as light AFTER the temporal resolve (F02 R1): they sweep round with no motion vectors, so
        // temporal filtering would dim their leading edge and trail them; they are soft and additive, so they have nothing to anti-alias anyway.
        if world == .varrow && beamIntensity > 0.001, let hdr = hdrTexture {
            let beamHeading = 0.6 + clock * Renderer.beamRate
            let bpass = MTLRenderPassDescriptor()
            bpass.colorAttachments[0].texture = hdr
            bpass.colorAttachments[0].loadAction = .load
            bpass.colorAttachments[0].storeAction = .store
            bpass.depthAttachment.texture = depthTexture
            bpass.depthAttachment.loadAction = .load
            bpass.depthAttachment.storeAction = .dontCare
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: bpass) {
                enc.label = "beams"
                // The resolved image lives in unjittered space, so the beams are drawn with the unjittered camera too.
                var beamFrame = frame
                if taaEnabled { beamFrame.viewProj = taaCurrentViewProj; beamFrame.invViewProj = taaCurrentViewProj.inverse }
            do {
                enc.setRenderPipelineState(beamPipeline)
                enc.setDepthStencilState(waterDepthState)
                enc.setCullMode(.none)
                enc.setVertexBuffer(beamMesh.vertexBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&beamFrame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentBytes(&beamFrame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
                enc.setFragmentTexture(distanceTexture, index: 3)
                for (sign, glow) in [(Float(1), Float(0)), (Float(-1), Float(0)), (Float(1), Float(1))] {
                    var bu = ObjectUniforms()
                    bu.tint = SIMD4(sign, beamHeading, beamIntensity, 0)
                    bu.emissive = SIMD4(Landmarks.lensPosition, glow)
                    enc.setVertexBytes(&bu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.setFragmentBytes(&bu, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: beamMesh.indexCount, indexType: .uint32, indexBuffer: beamMesh.indexBuffer, indexBufferOffset: 0)
                }
            }
                enc.endEncoding()
            }
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
        if autoExposure, let hdr = hdrTexture { encodeLuma(commandBuffer, hdr: hdr) }

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
