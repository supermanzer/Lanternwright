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
    /// G10.G.1: the compute pass that picks the grass cells worth drawing (and the buffers it fills).
    let grassField: GrassField
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

    var hdrTexture: MTLTexture? { targets?.hdr }
    // Temporal anti-aliasing (F02 R1, see Shaders/TAA.swift). Off in headless screenshots unless `--taa`, so existing baselines stay comparable.
    var taaEnabled = false
    var taaSharpness: Float = 0.8
    /// Weight of the new frame when still / at speed, and the colour-box width in sigmas (see TAA.swift). Tools can override them with TAA_ALPHA="a b" TAA_GAMMA="g" TAA_SHARP="s".
    var taaTuning = SIMD4<Float>(0.20, 0.35, 1.5, 0)
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
    /// G10.1.1: the textures that follow the output size (see RenderTargets); nil until the first frame. The old names below read from it.
    var targets: RenderTargets?
    var depthTexture: MTLTexture? { targets?.depth }
    /// Straight-line camera distance per pixel (1e5 for sky). Read by the water pass.
    var distanceTexture: MTLTexture? { targets?.distance }
    /// Copy of the HDR colour after opaque + sky; the water pass samples it for refraction.
    var sceneCopy: MTLTexture? { targets?.sceneCopy }
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
    var aoTexture: MTLTexture? { targets?.ao }
    var aoBlurred: MTLTexture? { targets?.aoBlurred }
    var raysTexture: MTLTexture? { targets?.rays }
    let bloomDownPipeline: MTLRenderPipelineState
    let bloomUpPipeline: MTLRenderPipelineState
    /// Half-resolution bloom chain; level i is (w, h) / 2^(i+1).
    var bloomChain: [MTLTexture] { targets?.bloom ?? [] }
    /// Eye adaptation: a 64 x 36 grid of mean log luminance, read back on the CPU one frame late.
    var lumaPipeline: MTLRenderPipelineState!
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
        grassField = GrassField(device: device, library: lib, cellsPerSide: Int((2 * LookDefaults.grassRadius / LookDefaults.grassCell).rounded()))

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

    /// G10.0.1: the per-pass GPU timer, when a tool (`--bench`) or the game has switched it on. Nil costs nothing.
    var passTimer: PassTimer?
    func renderEncoder(_ cb: MTLCommandBuffer, _ descriptor: MTLRenderPassDescriptor) -> MTLRenderCommandEncoder? {
        passTimer?.renderEncoder(cb, descriptor) ?? cb.makeRenderCommandEncoder(descriptor: descriptor)
    }
    func blitEncoder(_ cb: MTLCommandBuffer) -> MTLBlitCommandEncoder? { passTimer?.blitEncoder(cb) ?? cb.makeBlitCommandEncoder() }

    /// The passes of a frame, in order (G10.1.2). Each one reads what the earlier ones wrote; see the pass files for what.
    lazy var passes: [RenderPass] = [ShadowPass(self), OpaquePass(self), WaterPass(self), AOPass(self), TAAPass(self), BeamsPass(self), GodRaysPass(self), BloomPass(self), CompositePass(self)]

    /// Encode a full frame that ends by writing `target` (format `outputFormat`).
    func encode(commandBuffer: MTLCommandBuffer, target: MTLTexture, camera: Camera) {
        passTimer?.begin(commandBuffer)
        defer { passTimer?.end() }
        scene.applyLOD(eye: camera.position)
        ensureTargets(width: target.width, height: target.height)
        updateFrame(camera: camera, width: target.width, height: target.height)
        updateSkyLUT(commandBuffer: commandBuffer)
        let context = FrameContext(commandBuffer: commandBuffer, target: target, camera: camera, frame: frame)
        for pass in passes { pass.encode(context) }
    }
}
