import Foundation
import Metal
import simd

/// Self-tests: the per-pass GPU timer (G10.0.1). It must not change what is drawn, must list the passes of a frame by label, and its table must add up to the frame.
extension SelfTestRunner {
    func runPassTimer() {
        guard name == "all" || name == "passtimer" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "passtimer: no Metal device"); return }
        guard let timer = PassTimer(device: device) else { check(true, "passtimer: this device cannot sample counters at stage boundaries: unavailable, and everything runs without it (skipped)"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright", "--taa"]))
        renderer.fixedTime = 12
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: 640, height: 360, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "passtimer: no target"); return }
        let cam = Viewpoints.named("dock") ?? Camera(position: SIMD3(0, 3, 0), yaw: 0, pitch: 0)
        func frame() -> [UInt8] {
            guard let cb = renderer.queue.makeCommandBuffer() else { return [] }
            renderer.encode(commandBuffer: cb, target: tex, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            timer.drain(cb)
            var px = [UInt8](repeating: 0, count: 640 * 360 * 4)
            tex.getBytes(&px, bytesPerRow: 640 * 4, from: MTLRegionMake2D(0, 0, 640, 360), mipmapLevel: 0)
            return px
        }
        for _ in 0..<4 { _ = frame() }                                   // warm up and let the TAA history settle
        // The same frame twice: the jitter index and the TAA history are put back before each, so only the timer differs.
        let jitter = renderer.taaFrameIndex
        renderer.resetTAA(); renderer.taaFrameIndex = jitter
        renderer.passTimer = nil; let plain = frame()
        renderer.resetTAA(); renderer.taaFrameIndex = jitter
        renderer.passTimer = timer; let timed = frame()
        check(plain == timed, "passtimer: the timer changes no pixel of the frame (\(plain.count) bytes compared)")
        for _ in 0..<3 { _ = frame() }
        let labels = timer.latest.map { $0.pass }
        let sum = timer.latest.reduce(0) { $0 + $1.ms }
        check(labels.contains("opaque + sky") && labels.contains("water") && labels.contains("composite") && labels.contains("taa resolve") && timer.latest.allSatisfy { $0.ms >= 0 && $0.ms < 1000 },
              "passtimer: the table names the passes of the frame, each a sane time (\(labels.count) passes: \(labels.prefix(6).joined(separator: ", ")) ...)")
        check(timer.latestFrameMS > 0 && abs(sum - timer.latestFrameMS) <= 0.10 * timer.latestFrameMS,
              "passtimer: the table adds up to the frame's GPU time within 10 % (sum \(String(format: "%.3f", sum)) ms, frame \(String(format: "%.3f", timer.latestFrameMS)) ms)")
        check(timer.summary.hasPrefix("frame ") && timer.summary.contains("opaque + sky"), "passtimer: the one-line summary for the F-key context reads '\(timer.summary.prefix(70))...'")
        renderer.passTimer = nil
    }

    /// G10.1.2 and G10.1.3: the frame is a fixed list of passes, and no pass writes the renderer's frame uniforms (each gets a value copy in its FrameContext).
    func runFrameGraph() {
        guard name == "all" || name == "framegraph" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "framegraph: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        check(renderer.passes.map(\.name) == ["shadow", "opaque", "water", "velocity", "ao", "taa", "beams", "metalfx", "god rays", "bloom", "composite"],
              "framegraph: the passes in order: \(renderer.passes.map(\.name).joined(separator: ", "))")
        let dir = "Sources/Lanternwright/Render/Passes"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { $0.hasSuffix("Pass.swift") && $0 != "RenderPass.swift" } ?? []
        var offenders: [String] = []
        for f in files {
            let text = (try? String(contentsOfFile: dir + "/" + f, encoding: .utf8)) ?? ""
            if text.contains("r.frame") { offenders.append(f) }
        }
        check(files.count == 11 && offenders.isEmpty, "framegraph: no pass touches the renderer's frame uniforms (\(files.count) pass files, offenders: \(offenders))")
        let enc = (try? String(contentsOfFile: "Sources/Lanternwright/Render/Renderer.swift", encoding: .utf8)) ?? ""
        let body = enc.components(separatedBy: "    func encode(commandBuffer: MTLCommandBuffer, target: MTLTexture, camera: Camera) {").last?.components(separatedBy: "\n    }\n").first ?? ""
        check(!body.isEmpty && body.split(separator: "\n").count < 60, "framegraph: Renderer.encode is under 60 lines (\(body.split(separator: "\n").count))")
    }

    /// Every material id the shaders know has a name in the prop audit (it crashed on the ids past `slab`, and silently misnamed them before that).
    func runMaterialNames() {
        guard name == "all" || name == "framegraph" else { return }
        let ids = (0..<40).filter { MaterialID(rawValue: Float($0)) != nil }
        let names = ids.map { PropAudit.materialName($0) }
        check(ids.count >= 26 && Set(names).count == ids.count && !names.contains { $0.hasPrefix("id") } && PropAudit.materialName(99) == "id99" && PropAudit.materialName(25) == "rope",
              "prop audit: all \(ids.count) material ids have distinct names (needles, post, rope included)")
    }
}

extension SelfTestRunner {
    /// G10.2.1: the motion vector buffer (camera motion). A still camera gives zero vectors; a turn of the camera gives the analytic shift in pixels; the pass is silent when it is off.
    func runVelocity() {
        guard name == "all" || name == "velocity" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "velocity: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 12; renderer.autoExposure = false
        let w = 640, h = 360
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "velocity: no target"); return }
        func frame(_ cam: Camera) -> [Float] {
            guard let cb = renderer.queue.makeCommandBuffer() else { return [] }
            renderer.encode(commandBuffer: cb, target: tex, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            guard let v = renderer.velocityTexture, let buf = device.makeBuffer(length: w * h * 4, options: .storageModeShared), let cb2 = renderer.queue.makeCommandBuffer(), let blit = cb2.makeBlitCommandEncoder() else { return [] }
            blit.copy(from: v, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: w, height: h, depth: 1), to: buf, destinationOffset: 0, destinationBytesPerRow: w * 4, destinationBytesPerImage: w * h * 4)
            blit.endEncoding(); cb2.commit(); cb2.waitUntilCompleted()
            let p = buf.contents().assumingMemoryBound(to: Float16.self)
            return (0..<(w * h * 2)).map { Float(p[$0]) }
        }
        let base = Camera(position: SIMD3(150, 4, 180), yaw: -1.9, pitch: -0.1)
        renderer.velocityEnabled = false
        if let timer = PassTimer(device: device) {
            renderer.passTimer = timer
            _ = frame(base); _ = frame(base)
            check(!timer.latest.contains { $0.pass == "velocity" } && !timer.latest.isEmpty, "velocity: with the pass off no velocity encoder is in the frame (\(timer.latest.count) passes)")
            renderer.velocityEnabled = true; renderer.resetTAA(); _ = frame(base); _ = frame(base)
            check(timer.latest.contains { $0.pass == "velocity" }, "velocity: with it on the frame has a velocity pass")
            renderer.passTimer = nil
        } else { check(true, "velocity: no per-pass timer on this device: the on/off check is skipped") }
        renderer.velocityEnabled = true; renderer.resetTAA()
        _ = frame(base)                                   // the first frame has no history: zero motion
        let still = frame(base)
        let sortedStill = still.map { abs($0) }.sorted()
        let median = sortedStill.isEmpty ? 99 : sortedStill[sortedStill.count / 2], p99 = sortedStill.isEmpty ? 99 : sortedStill[sortedStill.count * 99 / 100]
        check(still.count == w * h * 2 && median < 0.02 && p99 < 0.1, "velocity: a still camera gives (almost) zero motion: median \(String(format: "%.4f", median)) px, 99 % under \(String(format: "%.3f", p99)) px (the float round trip of a far depth), largest \(String(format: "%.3f", sortedStill.last ?? 99)) px")
        var turned = base; turned.yaw += 0.01
        let moved = frame(turned)
        // At the centre of the frame a yaw of d radians moves the picture by f * tan(d) pixels, f = h / (2 tan(fovY / 2)).
        let f = Float(h) / (2 * tan(base.fovY / 2))
        let expect = f * tan(0.01)
        let c = (h / 2) * w + w / 2
        let vx = moved[c * 2], vy = moved[c * 2 + 1]
        check(abs(abs(vx) - expect) < 0.06 * expect && abs(vy) < 0.05 * expect + 0.05, "velocity: a 0.01 rad turn moves the centre by \(String(format: "%.2f", abs(vx))) px (expected \(String(format: "%.2f", expect))), vertical \(String(format: "%.2f", vy))")
        // Direction: looking turned toward +yaw, the picture content moves to the one side consistently across the frame (same sign everywhere in the middle band).
        var signs = Set<Bool>()
        for x in stride(from: w / 4, to: 3 * w / 4, by: 16) { signs.insert(moved[((h / 2) * w + x) * 2] > 0) }
        check(signs.count == 1, "velocity: the horizontal motion has one sign across the middle of the frame")
        // The sign: yaw is measured so that +yaw turns toward +x (east); the picture then moves toward -x, so a pixel was last frame at larger x: vx = prev - cur > 0.
        check(moved[c * 2] > 0, "velocity: a +yaw turn gives a positive horizontal vector (the pixel was further right last frame): \(String(format: "%.2f", moved[c * 2]))")
        // A camera cut (a teleport over 12 m) must not produce a frame of bogus vectors: the history is dropped and the vectors are zero.
        var teleported = turned; teleported.position += SIMD3(40, 0, 0)
        let cut = frame(teleported)
        let cutMax = cut.map { abs($0) }.sorted()
        check(cutMax[cutMax.count * 99 / 100] < 0.2, "velocity: after a 40 m teleport the vectors are zero, not hundreds of pixels (99 % under \(String(format: "%.3f", cutMax[cutMax.count * 99 / 100])) px, largest \(String(format: "%.2f", cutMax.last ?? 0)))")
        // Switching the pass off and on again drops the old history too.
        renderer.velocityEnabled = false; _ = frame(teleported); renderer.velocityEnabled = true
        var far = teleported; far.yaw += 0.3
        let reOn = frame(far).map { abs($0) }.sorted()
        check(reOn[reOn.count * 99 / 100] < 0.1, "velocity: switched off and on again, the first frame has zero motion (99 % under \(String(format: "%.3f", reOn[reOn.count * 99 / 100])) px)")
        renderer.velocityEnabled = false
    }
}

extension SelfTestRunner {
    /// G10.4.1: MetalFX upscaling at a render scale below 1 draws the scene smaller, outputs the full size, and looks like the native frame (same overall brightness, no NaNs).
    func runUpscale() {
        guard name == "all" || name == "upscale" else { return }
        guard Renderer.metalFXSupported, let device = MTLCreateSystemDefaultDevice() else { check(true, "upscale: MetalFX is not supported on this device: skipped"); return }
        let w = 800, h = 450
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "upscale: no target"); return }
        func mean(_ renderer: Renderer, frames: Int) -> (Float, Bool) {
            renderer.fixedTime = 12; renderer.autoExposure = false
            for _ in 0..<frames { guard let cb = renderer.queue.makeCommandBuffer() else { return (0, false) }; renderer.encode(commandBuffer: cb, target: tex, camera: Viewpoints.named("dock") ?? Camera(position: SIMD3(0, 3, 0), yaw: 0, pitch: 0)); cb.commit(); cb.waitUntilCompleted() }
            let y = Shimmer.luma(tex)
            return (y.reduce(0, +) / Float(y.count), y.allSatisfy { $0.isFinite })
        }
        let native = Renderer(device: device, options: LaunchOptions.parse(["lanternwright", "--taa"]))
        let (m0, ok0) = mean(native, frames: 10)
        let scaled = Renderer(device: device, options: LaunchOptions.parse(["lanternwright", "--render-scale", "0.75"]))
        let (m1, ok1) = mean(scaled, frames: 10)
        let t = scaled.targets
        check(ok0 && ok1 && t?.renderWidth == 600 && t?.renderHeight == 338 && t?.width == w && t?.upscaled?.width == w && t?.hdr.width == 600,
              "upscale: at 0.75 the scene is \(t?.renderWidth ?? 0) x \(t?.renderHeight ?? 0), the upscaled image \(t?.upscaled?.width ?? 0) x \(t?.upscaled?.height ?? 0), every output value finite")
        check(abs(m1 - m0) < 0.08 * m0, "upscale: the upscaled frame has the native frame's overall brightness (mean luma \(String(format: "%.1f", m1)) against \(String(format: "%.1f", m0)))")
        check(scaled.passes.map(\.name).contains("metalfx") && Renderer.metalFXSupported, "upscale: the MetalFX pass is in the frame graph")
    }
}

extension SelfTestRunner {
    /// G10.3.9: the margin cue. Nothing at pressure 0; at pressure 1 the fog is up to 15 % thicker (smoothed over about a second) and the ambience bed darker.
    func runMarginCue() {
        guard name == "all" || name == "margin" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "margin: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        let cam = Camera(position: SIMD3(0, 3, 0), yaw: 0, pitch: 0)
        func fog(at clock: Float) -> Float {
            renderer.fixedTime = clock
            renderer.updateFrame(camera: cam, width: 320, height: 180)
            return renderer.frame.fogParams.x
        }
        let base = fog(at: 10)
        renderer.marginPressure = 0
        check(abs(fog(at: 11) - base) < 1e-7 && renderer.marginCue == 0, "margin: at pressure 0 the fog is untouched (\(base))")
        renderer.marginPressure = 1
        var t: Float = 11
        var halfway: Float = 0
        for k in 0..<5 { t += 0.25; let f = fog(at: t); if k == 3 { halfway = f } }            // one second of 0.25 s frames
        check(halfway > base * 1.03 && halfway < base * 1.15, "margin: after a second at full pressure the fog is \(String(format: "%.1f", (halfway / base - 1) * 100)) % thicker, still easing in (under the 15 % limit)")
        for _ in 0..<40 { t += 0.25; _ = fog(at: t) }
        let full = fog(at: t + 0.25)
        check(abs(full / base - 1.15) < 0.005, "margin: fully settled it is 15 % thicker (\(String(format: "%.3f", full / base)) x)")
        renderer.marginPressure = 0
        for _ in 0..<60 { t += 0.25; _ = fog(at: t) }
        check(abs(fog(at: t + 0.25) / base - 1) < 0.002, "margin: back at pressure 0 the fog returns to its own value")
        // The ambience bed: a low-pass that is silent at 0 and takes the high end off at full pressure.
        func highShare(pressure: Float) -> Float {
            let s = AmbienceSynth(sampleRate: 22050)
            s.marginPressure = pressure
            var l = [Float](repeating: 0, count: 22050 * 3), r = [Float](repeating: 0, count: 22050 * 3)
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: 22050 * 3, left: lp.baseAddress!, right: rp.baseAddress!) } }
            let tail = Array(l[22050...])
            var diff: Float = 0, tot: Float = 0
            for i in 2..<tail.count { let d2 = tail[i] - 2 * tail[i - 1] + tail[i - 2]; diff += d2 * d2; tot += tail[i] * tail[i] }       // the second difference: weighted toward the top of the spectrum
            return diff / max(tot, 1e-12)
        }
        let open = highShare(pressure: 0), closed = highShare(pressure: 1)
        check(closed < 0.9 * open, "margin: at full pressure the ambience bed is darker (high-frequency share \(String(format: "%.5f", closed)) against \(String(format: "%.5f", open)))")
    }
}

extension SelfTestRunner {
    /// S03.4a: the lighthouse signal pattern is a pure function of the clock with a 20 s period.
    func runBeamSignal() {
        guard name == "all" || name == "beamsignal" else { return }
        let trail = BeamSignal.trailHeading, door = BeamSignal.doorHeading
        func wrap(_ a: Float) -> Float { var x = a.truncatingRemainder(dividingBy: 2 * .pi); if x > .pi { x -= 2 * .pi }; if x < -.pi { x += 2 * .pi }; return x }
        // The headings really point from the lens at the trail point and at the door.
        let lens = Landmarks.lensPosition
        let toTrail = SIMD2(Layout.Navigation.signalTrailPoint.x - lens.x, Layout.Navigation.signalTrailPoint.z - lens.z)
        check(abs(sin(trail) * toTrail.y + cos(trail) * toTrail.x) < 1e-3 * simd_length(toTrail) && sin(trail) * toTrail.x - cos(trail) * toTrail.y > 0, "beamsignal: the trail heading points from the lens along the causeway (\(String(format: "%.1f", trail * 180 / .pi)) degrees), the door heading at the south face (\(String(format: "%.1f", door * 180 / .pi)) degrees)")
        check(abs(abs(wrap(door)) - .pi) < 0.2 || abs(wrap(door)) > 2.5, "beamsignal: the door heading points south (about 180 degrees): \(String(format: "%.1f", door * 180 / .pi))")
        // Period: any clock and clock + 20 give the same pose.
        var same = true
        for c in stride(from: Float(0), to: 20, by: 0.37) { let a = BeamSignal.pose(clock: c), b = BeamSignal.pose(clock: c + 20), d = BeamSignal.pose(clock: c + 200); if abs(wrap(a.heading - b.heading)) > 1e-3 || abs(a.intensity - b.intensity) > 1e-3 || abs(wrap(a.heading - d.heading)) > 1e-3 { same = false } }
        check(same, "beamsignal: the pattern repeats every 20 s")
        // The first sweep starts at clock 0 mod 20 and turns; both sweeps turn the same way.
        let h0 = BeamSignal.pose(clock: 0.5).heading, h1 = BeamSignal.pose(clock: 2.5).heading, h2 = BeamSignal.pose(clock: 7.5).heading
        check(abs(wrap(h1 - h0)) > 0.3 && abs(wrap(h2 - BeamSignal.pose(clock: 5.5).heading)) > 0.3 && BeamSignal.pose(clock: 3).opposite, "beamsignal: at clock 0 the first sweep starts and the second follows at 5 s, two opposite beams turning (\(String(format: "%.2f", h1 - h0)) rad in 2 s)")
        // The rest: at least 4 s, standing still on the trail, one beam.
        var restOK = true
        for c in stride(from: Float(11), to: 15.9, by: 0.25) { let p = BeamSignal.pose(clock: c); if abs(wrap(p.heading - trail)) > 1e-4 || p.opposite || p.intensity < 0.5 { restOK = false } }
        check(restOK, "beamsignal: from 11 s to 16 s the beam stands still on the trail heading, a single beam")
        // The flash: about 1 s, on the door, brighter than anything else.
        let flash = BeamSignal.pose(clock: 16.5), steady = BeamSignal.pose(clock: 3)
        check(flash.flash && abs(wrap(flash.heading - door)) < 1e-4 && flash.intensity > 1.8 * steady.intensity && !BeamSignal.pose(clock: 18.5).flash && BeamSignal.pose(clock: 18.5).intensity < 0.2,
              "beamsignal: the flash at 16-17 s points at the door at \(String(format: "%.1f", flash.intensity)) x the sweep's brightness, then the beam is dark (\(String(format: "%.2f", BeamSignal.pose(clock: 18.5).intensity)))")
        // The end of the second sweep meets the rest without a jump.
        check(abs(wrap(BeamSignal.pose(clock: 9.99).heading - BeamSignal.pose(clock: 10.01).heading)) < 0.02, "beamsignal: the second sweep ends on the trail heading where the rest begins")
    }
}

extension SelfTestRunner {
    /// S03.6 prerequisite: the door leaf is its own scene item that swings about its hinge; the tower no longer carries the planks.
    func runDoorLeaf() {
        guard name == "all" || name == "doorleaf" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "doorleaf: no Metal device"); return }
        let sc = Scene.makeWorld(device: device)
        guard let leaf = sc.items.first(where: { $0.name == "lh_door_leaf" }), let tower = sc.items.first(where: { $0.name == "lighthouse" }) else { check(false, "doorleaf: lh_door_leaf or lighthouse missing"); return }
        let rd = Lighthouse.wallR(2.0)
        check(leaf.uniforms.model == translation(Layout.lighthouse) && leaf.mesh.indexCount > 0 && leaf.mesh.indexCount < tower.mesh.indexCount / 4, "doorleaf: closed, the leaf sits in the tower's own frame (\(leaf.mesh.indexCount / 3) triangles, the tower \(tower.mesh.indexCount / 3))")
        let lo = leaf.mesh.boundsMin, hi = leaf.mesh.boundsMax
        check(lo.x > -0.7 && hi.x < 0.7 && lo.y >= Lighthouse.baseY - 0.01 && hi.y < Lighthouse.baseY + 2.6 && lo.z > rd - 0.3 && hi.z < rd + 0.3,
              "doorleaf: the leaf's mesh fills the door opening (x \(String(format: "%.2f", lo.x)) to \(String(format: "%.2f", hi.x)), up to \(String(format: "%.2f", hi.y - Lighthouse.baseY)) m, z \(String(format: "%.2f", lo.z)) to \(String(format: "%.2f", hi.z)))")
        // Swung 90 degrees the free edge is 1.1 m out from the face, the hinge edge has not moved.
        var open = leaf; open.uniforms.model = Lighthouse.doorLeafModel(open: .pi / 2)
        let b = open.worldBounds
        check(b.max.z > Layout.lighthouse.z + rd + 0.9 && abs(b.min.x - (Layout.lighthouse.x - 0.55 - 0.1)) < 0.25,
              "doorleaf: opened 90 degrees the leaf swings outward from the hinge (world z up to \(String(format: "%.2f", b.max.z - Layout.lighthouse.z - rd)) m past the face, hinge edge x \(String(format: "%.2f", b.min.x - Layout.lighthouse.x)))")
        check(Lighthouse.doorLeafModel(open: 0) == translation(Layout.lighthouse), "doorleaf: angle 0 is exactly the closed model")
    }
}

extension SelfTestRunner {
    /// S03.5b: the interior light model flags exactly the inside of the tower (wall, stair, fittings), not the lens ring or the exterior, and the lamps are inside the tower.
    func runInteriorLight() {
        guard name == "all" || name == "interiorlight" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "interiorlight: no Metal device"); return }
        let sc = Scene.makeWorld(device: device)
        let flagged = Set(sc.items.filter { $0.uniforms.lod.z > 0.5 }.map(\.name))
        check(flagged == [LighthouseInterior.wallName, LighthouseInterior.stairName, LighthouseInterior.fittingsName], "interiorlight: only the interior wall, stair and fittings are flagged inside (\(flagged.sorted()))")
        let g = LighthouseInterior.lampGround, l = LighthouseInterior.lampLens
        check(simd_length(SIMD2(g.x - Layout.lighthouse.x, g.z - Layout.lighthouse.z)) < 0.01 && g.y > Layout.lighthouse.y + LighthouseInterior.floorY && g.y < Layout.lighthouse.y + LighthouseInterior.floorY + 4 && l.y > Layout.lighthouse.y + LighthouseInterior.lensFloorY && l.y < Layout.lighthouse.y + LighthouseInterior.lensFloorY + 3,
              "interiorlight: the two lamps hang on the tower's axis, one over each room's floor (ground y \(g.y), lens y \(l.y))")
        let msl = ShaderLibrary.sources.joined(separator: "\n")
        check(msl.contains("if (obj.lod.z > 0.5)") && msl.contains("ambient *= 0.10;"), "interiorlight: the lit shader cuts the sky's ambient and adds the lamps only for flagged items")
    }
}
