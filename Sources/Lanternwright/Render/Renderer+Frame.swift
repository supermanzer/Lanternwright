import Metal
import simd
import Foundation

/// The renderer's per-frame helpers: per-frame uniforms, render targets, the sky LUT, post passes, eye-adaptation readback and the
/// shadow cascade fit. `Renderer.swift` keeps the pipelines and the frame graph (`encode`).
extension Renderer {
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

    func ensureTargets(width: Int, height: Int) {
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

    func updateFrame(camera: Camera, width: Int, height: Int) {
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
        var autoScale: Float = 1
        if autoExposure {
            lumaLock.lock(); let l = measuredLuma; lumaLock.unlock()
            if let l {
                if let last = lastAdaptTime { adaptation.update(averageLuminance: l, dt: min(max(t - last, 0), 0.25)) } else { adaptation.snap(averageLuminance: l) }
                lastAdaptTime = t
            }
            autoScale = adaptation.exposure
        }
        frame.fogParams = SIMD4(wp.fogDensity, wp.fogFalloff, wp.exposure * autoScale, wp.bloom)
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
    func updateSkyLUT(commandBuffer: MTLCommandBuffer) {
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

    func postPass(_ cb: MTLCommandBuffer, _ label: String, _ pipeline: MTLRenderPipelineState,
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

    /// Average the HDR image down to 64 x 36 log-luminance samples and read them back when the GPU is done (one frame late).
    func encodeLuma(_ cb: MTLCommandBuffer, hdr: MTLTexture) {
        if lumaTexture == nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: 64, height: 36, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .shared
            lumaTexture = device.makeTexture(descriptor: d)
            lumaTexture?.label = "luma"
        }
        guard let target = lumaTexture else { return }
        postPass(cb, "luma", lumaPipeline, source: hdr, target: target, load: .dontCare)
        cb.addCompletedHandler { [weak self] _ in
            var px = [Float](repeating: 0, count: 64 * 36 * 2)
            target.getBytes(&px, bytesPerRow: 64 * 2 * MemoryLayout<Float>.stride, from: MTLRegionMake2D(0, 0, 64, 36), mipmapLevel: 0)
            var num: Float = 0, den: Float = 0
            for i in 0..<(64 * 36) { num += px[2 * i] * px[2 * i + 1]; den += px[2 * i + 1] }
            let mean = num / max(den, 1e-4)
            guard let self, mean.isFinite else { return }
            self.lumaLock.lock(); self.measuredLuma = pow(2, mean); self.lumaLock.unlock()
        }
    }

    func encodeBloom(_ cb: MTLCommandBuffer) {
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
    func fitCascade(center c: SIMD3<Float>, radius R: Float, size: Int, sun: SIMD3<Float>)
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
}
