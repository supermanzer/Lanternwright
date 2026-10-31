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
        check(msl.contains("if (obj.lod.z > 0.5)") && msl.contains("ambient *= 0.14;"), "interiorlight: the lit shader cuts the sky's ambient and adds the lamps only for flagged items")
    }
}

extension SelfTestRunner {
    /// S03.5b: inside the open tower the footstep surface comes from the interior (stone flags in the ground room, wood on the stair), and nothing changes while the door is closed.
    func runInteriorSteps() {
        guard name == "all" || name == "interiorsteps" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "interiorsteps: no Metal device"); return }
        let g = Game(scene: Scene.makeWorld(device: device))
        let o = SIMD2(Layout.lighthouse.x, Layout.lighthouse.z)
        var stoneSpot: SIMD3<Float>?, woodSpot: SIMD3<Float>?
        for r in stride(from: Float(0.5), to: 3.4, by: 0.25) { for k in 0..<24 {
            let a = Float(k) / 24 * 2 * .pi, x = o.x + r * cos(a), z = o.y + r * sin(a)
            if let f = g.interior.floor(x: x, z: z, feetY: Layout.lighthouse.y + LighthouseInterior.floorY) {
                if !f.wood, stoneSpot == nil { stoneSpot = SIMD3(x, f.y, z) }
                if f.wood, woodSpot == nil, f.y < Layout.lighthouse.y + LighthouseInterior.floorY + 0.3 { woodSpot = SIMD3(x, f.y, z) }
            }
        } }
        guard let stone = stoneSpot else { check(false, "interiorsteps: no stone floor found in the ground room"); return }
        g.player.position = stone
        let closed = g.currentSurface
        var clock: Double = 0
        let idle = InputState()
        g.state.set(Game.doorOpenFlag); for _ in 0..<2 { clock += 0.05; g.advance(now: clock, input: idle) }
        g.player.position = stone
        let mixStone = g.surfaceMix.mix
        check(g.currentSurface == .stone && mixStone[StepMaterial.stone.rawValue] == 1 && closed == .stone, "interiorsteps: standing on the ground room's flags with the door open the foot is on stone (closed door: \(closed))")
        if let w = woodSpot {
            g.player.position = w
            check(g.currentSurface == .wood && g.surfaceMix.mix[StepMaterial.wood.rawValue] == 1, "interiorsteps: on the stair's low treads the foot is on wood (surface \(g.currentSurface), wood weight \(g.surfaceMix.mix[StepMaterial.wood.rawValue]) at \(w))")
        } else { check(true, "interiorsteps: no low stair tread found in the sampled ring (skipped)") }
        g.player.position = SIMD3(o.x + 30, g.scene.groundHeight(x: o.x + 30, z: o.y), o.y)
        check(g.currentSurface == g.scene.surface(x: g.player.position.x, z: g.player.position.z), "interiorsteps: outside the tower the scene's own ground still decides")
        // Another world at the same x/z must not read the Varrow interior (the door flag stays set while away).
        let two = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
        two.state.set(Game.doorOpenFlag); for _ in 0..<2 { clock += 0.05; two.advance(now: clock, input: idle) }
        two.player.position = stone
        let inVarrow = two.currentSurface
        two.travel(to: .glassWood); two.player.position = stone
        check(inVarrow == .stone && two.world == .glassWood && two.currentSurface == two.scene.surface(x: stone.x, z: stone.z), "interiorsteps: in the Glass Wood the Varrow interior is not consulted (world \(two.world), surface \(two.currentSurface))")
    }
}

extension SelfTestRunner {
    /// S03.6: the tower has a real doorway: a ray from the south through the door at eye height passes through the shaft (the leaf is its own item), but a ray beside the door hits the wall at once.
    func runDoorway() {
        guard name == "all" || name == "doorway" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "doorway: no Metal device"); return }
        let sc = Scene.makeWorld(device: device)
        guard let tower = sc.items.first(where: { $0.name == "lighthouse" }) else { check(false, "doorway: no lighthouse item"); return }
        let verts = tower.mesh.vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: tower.mesh.vertexBuffer.length / MemoryLayout<Vertex>.stride)
        let idx = tower.mesh.indexBuffer.contents().bindMemory(to: UInt32.self, capacity: tower.mesh.indexCount)
        func hit(origin o: SIMD3<Float>, dir d: SIMD3<Float>) -> Float? {
            var best: Float?
            for t in stride(from: 0, to: tower.mesh.indexCount, by: 3) {
                let a = SIMD3(verts[Int(idx[t])].position.x, verts[Int(idx[t])].position.y, verts[Int(idx[t])].position.z)
                let b = SIMD3(verts[Int(idx[t + 1])].position.x, verts[Int(idx[t + 1])].position.y, verts[Int(idx[t + 1])].position.z)
                let c = SIMD3(verts[Int(idx[t + 2])].position.x, verts[Int(idx[t + 2])].position.y, verts[Int(idx[t + 2])].position.z)
                let e1 = b - a, e2 = c - a, p = simd_cross(d, e2), det = simd_dot(e1, p)
                if abs(det) < 1e-9 { continue }
                let inv = 1 / det, s = o - a, u = simd_dot(s, p) * inv
                if u < 0 || u > 1 { continue }
                let q = simd_cross(s, e1), v = simd_dot(d, q) * inv
                if v < 0 || u + v > 1 { continue }
                let dist = simd_dot(e2, q) * inv
                if dist > 0 && (best == nil || dist < best!) { best = dist }
            }
            return best
        }
        let y = Lighthouse.baseY + 1.3                                           // a metre above the sill
        let through = hit(origin: SIMD3(0, y, 14), dir: SIMD3(0, 0, -1))
        let beside = hit(origin: SIMD3(1.6, y, 14), dir: SIMD3(0, 0, -1))
        let rd = Lighthouse.wallR(y)
        check((through ?? 99) > 14 + rd - 0.5 && abs((beside ?? 0) - (14 - rd)) < 0.6,
              "doorway: through the door a ray runs on to the far wall at \(String(format: "%.1f", through ?? -1)) m; 1.6 m beside it the wall stops it at \(String(format: "%.1f", beside ?? -1)) m (the shaft's radius here is \(String(format: "%.2f", rd)))")
    }
}

extension SelfTestRunner {
    /// S03.5b: the window light shafts: none with the sun down or overhead; with the sun up a window lets light in exactly when it faces the sun; origins on the inner wall; the level is bounded and grows with elevation.
    func runWindowShafts() {
        guard name == "all" || name == "windowshafts" else { return }
        func dir(_ elev: Float, _ az: Float) -> SIMD3<Float> { Renderer.sunDirection(elevationDeg: elev, azimuthDeg: az) }
        check(Lighthouse.windowShafts(sunToward: dir(-2, 100)).isEmpty, "windowshafts: none with the sun below the horizon")
        check(Lighthouse.windowShafts(sunToward: SIMD3(0, 1, 0)).isEmpty, "windowshafts: an overhead sun gives none and divides by nothing")
        var mismatches = 0, originErr: Float = 0, travelErr: Float = 0, maxLevel: Float = 0, any = false
        for az in stride(from: Float(0), to: 360, by: 15) {
            let s = dir(30, az), h = simd_normalize(SIMD2(-s.x, -s.z))
            let got = Lighthouse.windowShafts(sunToward: s)
            for (i, wy) in Lighthouse.windowYs.enumerated() {
                let a = Lighthouse.windowAngle(i)
                let facing = simd_dot(h, SIMD2(-cos(a), -sin(a)))
                if (facing > 0.2) != got.contains(where: { abs($0.origin.y - (Layout.lighthouse.y + wy)) < 1e-4 }) { mismatches += 1 }
            }
            for g in got {
                any = true
                let rel = g.origin - Layout.lighthouse
                originErr = max(originErr, abs(simd_length(SIMD2(rel.x, rel.z)) - LighthouseInterior.innerR(rel.y)))
                travelErr = max(travelErr, simd_length(g.travel + s))
                maxLevel = max(maxLevel, g.level)
            }
        }
        check(any && mismatches == 0, "windowshafts: a window lets light in exactly when it faces the sun (\(mismatches) mismatches over 24 azimuths)")
        check(originErr < 1e-4, "windowshafts: every shaft starts on the inner wall (error \(originErr) m)")
        check(travelErr < 1e-5 && maxLevel <= 1, "windowshafts: the light travels away from the sun and the level stays within 0...1 (max \(maxLevel))")
        func total(_ e: Float) -> Float { Lighthouse.windowShafts(sunToward: dir(e, 150)).reduce(0) { $0 + $1.level } }
        if let device = MTLCreateSystemDefaultDevice() {
            let sc = Scene.makeWorld(device: device)
            let panes = sc.items.first { $0.name == LighthouseInterior.windowPanesName }
            check(panes != nil && panes!.hidden == (LighthouseInterior.shownForTools == false) && panes!.mesh.indexCount == 5 * 36, "windowshafts: the interior has five window panes, drawn only while the door is open (\(panes?.mesh.indexCount ?? -1) indices)")
        }
        check(total(2) < total(5) && total(5) < total(15) && abs(total(15) - total(40)) < 1e-4, "windowshafts: more light as the sun rises, then a plateau above about 7 degrees (\(total(2)), \(total(5)), \(total(15)), \(total(40)))")
    }
}

extension SelfTestRunner {
    /// S03.4 lantern chain: each lantern's light core is its own item in route order; the flare is a pure function of the time since the return: nothing before it, one lantern after another `step` apart, all back to the base glow afterwards.
    func runLanternChain() {
        guard name == "all" || name == "lanternchain" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "lanternchain: no Metal device"); return }
        let sc = Scene.makeWorld(device: device)
        let cores = sc.items.filter { $0.name.hasPrefix(LanternChain.coreName) }
        let names = Set(cores.map(\.name))
        check(cores.count >= 10 && (0..<cores.count).allSatisfy { names.contains("\(LanternChain.coreName)\($0)") }, "lanternchain: \(cores.count) lantern cores, numbered without gaps")
        check(cores.count == sc.placed.filter { $0.kind == "lantern" }.count, "lanternchain: one core per placed lantern")
        check(cores.allSatisfy { $0.uniforms.emissive.w == LanternChain.baseGlow && !$0.castsShadow }, "lanternchain: every core starts at the base glow and casts no shadow")
        check(LanternChain.glow(index: 0, time: -1) == LanternChain.baseGlow && LanternChain.glow(index: 5, time: 0.5) == LanternChain.baseGlow, "lanternchain: nothing before the return, and lantern 5 waits for its turn")
        let peak = (0..<20).map { LanternChain.glow(index: 3, time: 3 * LanternChain.step + Float($0) * 0.08) }.max()!
        check(peak > LanternChain.baseGlow + 0.9 * LanternChain.flareGlow && peak <= LanternChain.baseGlow + LanternChain.flareGlow + 1e-4, "lanternchain: a lantern's flare peaks at \(peak)")
        var order = true
        for k in 0..<8 { if LanternChain.glow(index: k, time: Float(k) * LanternChain.step + 0.25) < LanternChain.glow(index: k + 1, time: Float(k) * LanternChain.step + 0.25) { order = false } }
        check(order, "lanternchain: the lanterns flare in route order")
        let end = LanternChain.total(count: cores.count)
        check((0..<cores.count).allSatisfy { LanternChain.glow(index: $0, time: end + 0.01) == LanternChain.baseGlow }, "lanternchain: every lantern is back to the base glow after \(end) s")
    }
}

extension SelfTestRunner {
    /// S03.4: the answer phrase: made of the stones' tones, audible, finite, not clipping, four notes at their times, and the engine maps `GameEvent.answerPhrase` to it.
    func runAnswerPhrase() {
        guard name == "all" || name == "answerphrase" else { return }
        check(ToneTable.answerHz.allSatisfy { ToneTable.stoneHz.contains($0) } && ToneTable.answerHz.count == ToneTable.answerDelays.count && ToneTable.answerDelays == ToneTable.answerDelays.sorted(),
              "answerphrase: the motif is made of the stones' own tones, in time order")
        let sr: Float = 44100
        let synth = AmbienceSynth(sampleRate: sr)
        synth.windGain = 0; synth.surfGain = 0; synth.master = 1
        synth.play(.answer)
        let n = Int(sr) * 6
        var l = [Float](repeating: 0, count: n), r = l
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!) } }
        check(!l.contains { !$0.isFinite } && (l.map { abs($0) }.max() ?? 2) < 0.9, "answerphrase: finite and well under clipping (peak \(l.map { abs($0) }.max() ?? 0))")
        func power(_ hz: Float, from t0: Float, to t1: Float) -> Float {              // Goertzel over [t0, t1) seconds
            let a = Int(t0 * sr), b = min(n, Int(t1 * sr)), w = 2 * Float.pi * hz / sr, c = 2 * cos(w)
            var s1: Float = 0, s2: Float = 0
            for i in a..<b { let s = l[i] + c * s1 - s2; s2 = s1; s1 = s }
            return (s1 * s1 + s2 * s2 - c * s1 * s2) / Float(b - a)
        }
        // Each note's own pitch is clearly present in the 0.3 s after it is struck, and the 440 Hz note is not yet there before the phrase begins.
        var ok = true
        for (i, hz) in ToneTable.answerHz.enumerated() {
            let t = ToneTable.answerDelays[i]
            let here = power(hz, from: t + 0.05, to: t + 0.35)
            let off = power(hz * 1.19, from: t + 0.05, to: t + 0.35)                // a pitch that is not in the phrase
            if !(here > 4 * off) { ok = false }
        }
        check(ok, "answerphrase: each of the four notes sounds at its pitch when it is due")
        check(ToneTable.answerHz == [440.00, 587.33, 440.00, 293.66] && ToneTable.answerDelays == [0, 0.55, 1.1, 1.9], "answerphrase: the motif is A4 D5 A4 D4 at 0, 0.55, 1.1 and 1.9 s")
        // The repeated A4 is a new strike, not the first one still ringing: its 440 Hz power just after 1.1 s beats the power just before it.
        check(power(440, from: 1.1, to: 1.16) > 1.3 * power(440, from: 1.04, to: 1.1), "answerphrase: the second A4 is struck anew at 1.1 s")
        let tail = l[(Int(sr) * 5)...].map { abs($0) }.max() ?? 1
        check(tail < (l.map { abs($0) }.max() ?? 1) * 0.5, "answerphrase: it rings out and does not drone (tail \(tail))")
    }
}

extension SelfTestRunner {
    /// F05 W2/W3 (#60, #61): the swash's phase follows the beach's slope, so it must be the beach's slope: neighbouring points of the waterline band (2 m apart) get nearly the same swash delay when the slope is measured over `Shore.slopeBase`,
    /// where the pixel's own +-2 m slope gave neighbours phases seconds apart (a dry tongue inside a flooded beach; arcs that stood still round the dock).
    func runSwashCoherence() {
        guard name == "all" || name == "swashcoherence" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "swashcoherence: no Metal device"); return }
        guard let terrain = Scene.makeWorld(device: device).terrain else { check(false, "swashcoherence: no terrain"); return }
        func slope(_ x: Float, _ z: Float, _ b: Float) -> Float {
            let gx = (terrain.sampleHeight(x: x + b, z: z) - terrain.sampleHeight(x: x - b, z: z)) / (2 * b)
            let gz = (terrain.sampleHeight(x: x, z: z + b) - terrain.sampleHeight(x: x, z: z - b)) / (2 * b)
            return (gx * gx + gz * gz).squareRoot()
        }
        var worstNew: Float = 0, worstOld: Float = 0, n = 0
        for xi in stride(from: Float(120), to: 260, by: 2) {
            for zi in stride(from: Float(150), to: 290, by: 2) {
                let h = terrain.sampleHeight(x: xi, z: zi)
                guard h > -0.5 && h < 0.6 else { continue }                                             // the waterline band
                n += 1
                for (dx, dz) in [(Float(2), Float(0)), (0, 2)] {
                    let d = { (b: Float) in abs(Shore.swashDelay(slope: slope(xi, zi, b)) - Shore.swashDelay(slope: slope(xi + dx, zi + dz, b))) }
                    worstNew = max(worstNew, d(Shore.slopeBase)); worstOld = max(worstOld, d(2))
                }
            }
        }
        check(n > 200, "swashcoherence: \(n) waterline-band points sampled")
        check(worstNew < 1.0, "swashcoherence: neighbouring waterline points differ by at most \(worstNew) s of swash delay with the beach-scale slope (the pixel-scale slope gave \(worstOld) s)")
    }
}

extension SelfTestRunner {
    /// F05 W2 (#60), the visible property on the CPU mirror of the film: over a sweep of clocks, no DRY point of the waterline band has water both below it AND above it along the beach's own slope line
    /// (a dry tongue inside a flooded beach). A headland is not one: its landward side is dry. The same scan with the old 6 m / 4-point ridge rule is reported for comparison.
    func runDryInsideWet() {
        guard name == "all" || name == "dryinsidewet" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "dryinsidewet: no Metal device"); return }
        guard let terrain = Scene.makeWorld(device: device).terrain else { check(false, "dryinsidewet: no terrain"); return }
        func h(_ x: Float, _ z: Float) -> Float { terrain.sampleHeight(x: x, z: z) }
        func ring(_ x: Float, _ z: Float, _ r: Float, eight: Bool) -> [Float] {
            var out = [h(x + r, z), h(x - r, z), h(x, z + r), h(x, z - r)]
            if eight { let d = r * 0.70710678; out += [h(x + d, z + d), h(x - d, z - d), h(x + d, z - d), h(x - d, z + d)] }
            return out
        }
        func wet(_ x: Float, _ z: Float, _ t: Float, old: Bool) -> Bool {
            let raw = h(x, z)
            guard raw > -1.2 else { return true }
            let b = old ? Float(16) : Shore.slopeBase
            let gx = (h(x + b, z) - h(x - b, z)) / (2 * b), gz = (h(x, z + b) - h(x, z - b)) / (2 * b)
            let slope = (gx * gx + gz * gz).squareRoot()
            let tEff: Float
            if old {
                tEff = min(raw, ring(x, z, 6, eight: false).reduce(0, +) / 4 + 0.04)                          // the first rule (6 m, 4 points, flatten ridges)
            } else {
                tEff = Shore.coverGround(raw: raw, ring: ring(x, z, Shore.coverRadius, eight: true))
            }
            return Shore.sheetHeight(seaY: 0, ground: tEff, swashEdge: Shore.swashEdge(x: x, z: z, time: t, slope: slope)) - tEff > 0.01
        }
        var bad = 0, badOld = 0, tested = 0
        for t in stride(from: Float(0), to: 60, by: 2) {
            for xi in stride(from: Float(130), to: 250, by: 3) {
                for zi in stride(from: Float(160), to: 280, by: 3) {
                    let raw = h(xi, zi)
                    guard raw > -0.3 && raw < 0.7 else { continue }
                    let gx = h(xi + 6, zi) - h(xi - 6, zi), gz = h(xi, zi + 6) - h(xi, zi - 6), gl = (gx * gx + gz * gz).squareRoot()
                    guard gl > 0.05 else { continue }                                                    // a flat has no up or down
                    let u = SIMD2(gx, gz) / gl                                                            // uphill
                    tested += 1
                    for old in [false, true] {
                        guard !wet(xi, zi, t, old: old) else { continue }
                        let below = [3, 6, 9, 12].contains { wet(xi - u.x * Float($0), zi - u.y * Float($0), t, old: old) }
                        let above = [3, 6, 9, 12].contains { wet(xi + u.x * Float($0), zi + u.y * Float($0), t, old: old) }
                        if below && above { if old { badOld += 1 } else { bad += 1; } }
                    }
                }
            }
        }
        check(tested > 3000, "dryinsidewet: \(tested) waterline-band samples over 30 clocks")
        // Smoothed coverage and one phase along the beach leave almost none: under half the first rule's count (6 m / 4 points, flatten ridges, at the same damped delay) and under 0.5 % of the band.
        check(Double(bad) < 0.5 * Double(badOld) && Double(bad) < 0.005 * Double(tested), "dryinsidewet: almost no dry point has water both below and above it along the beach's slope (\(bad) of \(tested); the first rule at the same delay: \(badOld))")
    }
}

extension SelfTestRunner {
    /// F05 Q1 (#68): no causeway slab floats: with its footing, the underside of every slab or its footing reaches the lowest ground under the footprint (no air gap), and the footing is never absurdly deep.
    func runCausewayGrounded() {
        guard name == "all" || name == "causewaygrounded" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "causewaygrounded: no Metal device"); return }
        let sc = Scene.makeWorld(device: device)
        guard let terrain = sc.terrain else { check(false, "causewaygrounded: no terrain"); return }
        let plan = PuzzleProps.causewayPlan(terrain: terrain)
        var worstGap: Float = -9, footed = 0, deepest: Float = 0
        for k in 0..<PuzzleProps.slabCount {
            let drop = PuzzleProps.slabFootingDrop(plan, k, terrain: terrain)
            let bottom = plan.top(k) - 0.7 - drop
            let c = plan.center(k), across = SIMD2(plan.dir.y, -plan.dir.x)
            for i in -2...2 { for j in -2...2 {
                let p = c + across * (Float(i) * 0.75) + plan.dir * (Float(j) * 0.9)
                worstGap = max(worstGap, bottom - terrain.sampleHeight(x: p.x, z: p.y))                   // > 0: air under the lowest part of the stone
            } }
            if drop > 0.02 { footed += 1 }
            deepest = max(deepest, drop)
        }
        check(worstGap <= 0.0001, "causewaygrounded: every slab or its footing reaches the ground under its whole footprint (worst air gap \(worstGap) m; \(footed) of \(PuzzleProps.slabCount) slabs needed a footing, the deepest \(deepest) m)")
        let slabs = sc.items.filter { $0.name.hasPrefix("causeway_") }
        let footedMeshes = slabs.filter { $0.mesh.indexCount > (slabs.map { $0.mesh.indexCount }.min() ?? 0) }.count
        check(slabs.count == PuzzleProps.slabCount && footedMeshes >= footed, "causewaygrounded: the footing meshes are really built (\(footedMeshes) slab meshes carry more geometry than the plainest, \(footed) slabs need a footing)")
        check(deepest < 8, "causewaygrounded: no footing is absurdly deep (\(deepest) m)")
    }
}

extension SelfTestRunner {
    /// F06 A1 loudness: through the real synth (master 1), the door event's peak is about 1.0-1.3 times a run footstep's on the same stone (the user: "~2x a footstep" was too much); the lens ring's turn is
    /// in the same range, softer than the door.
    func runDoorLevel() {
        guard name == "all" || name == "doorlevel" else { return }
        let sr: Float = 44100
        func render(_ setup: (AmbienceSynth) -> Void, seconds: Float = 2) -> [Float] {
            let s = AmbienceSynth(sampleRate: sr)
            s.windGain = 0; s.surfGain = 0; s.master = 1
            setup(s)
            var l = [Float](repeating: 0, count: Int(sr * seconds)), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }
            return l
        }
        func peak(_ x: [Float]) -> Float { x.map { abs($0) }.max() ?? 0 }
        // The level rules below are against a run step at the level BEFORE F07 A-steps lowered the footsteps by 4 dB (the door was set against that level and keeps its weight; it is now louder than a step by that much).
        let beforeSteps = 1.4 / AmbienceSynth.stepMix
        let runs = [SurfaceKind.stone, .wood, .grass].map { k in beforeSteps * peak(render { $0.stepSurface = k; $0.stepRun = true; $0.stepCounter += 1 }) }
        let door = [Float(0.3), 0.6, 1.0].map { st in peak(render { $0.doorStrength = st; $0.play(.doorLocked) }) }
        let ringSig = render({ $0.play(.ringTurn) }, seconds: 1)
        check(door[2] > 0.6 * runs[0] && door[2] < 1.3 * runs[0] && door[0] > 0.3 * runs[0], "doorlevel: through the synth the door at full strength is \(String(format: "%.2f", door[2] / runs[0])) times a run step on stone (0.3 / 0.6 / 1 strength: \(door.map { String(format: "%.2f", $0 / runs[0]) })), within 0.6-1.3 at its hardest")
        let ring = peak(ringSig)
        check(ring > 0.35 * runs[0] && ring < 1.0 * runs[0] && ring < door[2], "doorlevel: the lens ring's turn is \(String(format: "%.2f", ring / runs[0])) of a run step on stone: audible, softer than the door")
        // The ring is a grind, not a pitch: no one-third-octave band stands out (per 46 ms frame, limit 10 dB), its power is mostly low (80-1500 Hz), and it is over (-40 dB) in under 0.8 s.
        let sp = FootstepAnalysis.spectrum(ringSig)
        let low = FootstepAnalysis.band(sp, 80, 1500) / max(FootstepAnalysis.band(sp, 40, 9000), 1e-12)
        var worst: Float = 0
        let frame = 2048, hop = 512, energies = stride(from: 0, to: ringSig.count - frame, by: hop).map { a in ringSig[a..<a + frame].reduce(0) { $0 + $1 * $1 } }, floor = 0.03 * (energies.max() ?? 0)
        for (k, a) in stride(from: 0, to: ringSig.count - frame, by: hop).enumerated() where energies[k] > floor {
            let f = FootstepAnalysis.spectrum(Array(ringSig[a..<a + frame]))
            var e: [Float] = [], fc: Float = 300
            while fc <= 6000 { e.append(FootstepAnalysis.band(f, fc / pow(2, 1.0 / 6), fc * pow(2, 1.0 / 6))); fc *= pow(2, 1.0 / 3) }
            for q in 1..<(e.count - 1) { worst = max(worst, e[q] / max(max(e[q - 1], e[q + 1]), 1e-20)) }
        }
        // Negative control: an 880 Hz tone of amplitude 0.005 laid over the first half second would push the worst band over the limit (checked at 11.8 dB), so the check does bite on the ring.
        var toned = ringSig
        for i in 0..<Int(0.5 * sr) { toned[i] += 0.005 * sin(2 * .pi * 880 * Float(i) / sr) }
        var worstToned: Float = 0
        for (k, a0) in stride(from: 0, to: toned.count - frame, by: hop).enumerated() where energies[k] > floor {
            let f = FootstepAnalysis.spectrum(Array(toned[a0..<a0 + frame]))
            var e: [Float] = [], fc: Float = 300
            while fc <= 6000 { e.append(FootstepAnalysis.band(f, fc / pow(2, 1.0 / 6), fc * pow(2, 1.0 / 6))); fc *= pow(2, 1.0 / 3) }
            for q in 1..<(e.count - 1) { worstToned = max(worstToned, e[q] / max(max(e[q - 1], e[q + 1]), 1e-20)) }
        }
        check(10 * log10(max(worstToned, 1e-9)) > 10, "doorlevel: and the ring's tone check bites: an 880 Hz tone of 0.005 gives \(String(format: "%.1f", 10 * log10(max(worstToned, 1e-9)))) dB")
        let tailStart = Int(0.8 * sr), tail = ringSig[tailStart...].map { abs($0) }.max() ?? 1
        check(10 * log10(max(worst, 1e-9)) < 10 && low > 0.55 && tail < 0.01 * ring, "doorlevel: the ring's turn has no tone (worst band \(String(format: "%.1f", 10 * log10(max(worst, 1e-9)))) dB over its neighbours, limit 10), \(Int(low * 100)) % of its power under 1.5 kHz, and is over by 0.8 s")
        // The game says it: a turn emits the chime, a touch on the ring too.
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
        g.state.set(Game.doorOpenFlag); g.advance(now: 9000, input: InputState()); _ = g.drainEvents()
        g.lensPortal.turn(1)
        check(g.drainEvents().contains(.chime(.ringTurn)), "doorlevel: turning the ring emits the ringTurn chime")
    }
}

extension SelfTestRunner {
    /// F07 A-door: metrics of the door event (energy under 500 Hz, centroid, strongest one-third-octave rise above 1 kHz, level against a stone run step through the synth).
    func runDoorHeavy() {
        guard name == "all" || name == "doorheavy" else { return }
        let sr: Float = 44100
        let A = FootstepAnalysis.self
        func midShare(_ x: [Float]) -> Float { let sp = A.spectrum(x); return A.band(sp, 150, 900) / max(A.band(sp, 40, 9000), 1e-12) }
        func metrics(_ x: [Float]) -> (low: Float, centroid: Float, rise: Float) {
            let sp = A.spectrum(x), tot = max(A.band(sp, 40, 9000), 1e-12)
            var num: Float = 0, den: Float = 0
            for (i, p) in sp.enumerated() { let f = Float(i + 1) * 40; num += f * p; den += p }
            var e: [Float] = [], fc: Float = 1000
            while fc <= 6000 { e.append(A.band(sp, fc / pow(2, 1.0 / 6), fc * pow(2, 1.0 / 6))); fc *= pow(2, 1.0 / 3) }
            var worst: Float = 0
            for i in 1..<(e.count - 1) { worst = max(worst, e[i] / max(max(e[i - 1], e[i + 1]), 1e-20)) }
            return (A.band(sp, 40, 500) / tot, num / max(den, 1e-12), 10 * log10(max(worst, 1e-9)))
        }
        func synthPeak(_ setup: (AmbienceSynth) -> Void) -> Float {
            let s = AmbienceSynth(sampleRate: sr); s.windGain = 0; s.surfGain = 0; s.master = 1; setup(s)
            var l = [Float](repeating: 0, count: Int(sr * 2)), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }
            return l.map { abs($0) }.max() ?? 0
        }
        let run = (1.4 / AmbienceSynth.stepMix) * synthPeak { $0.stepSurface = .stone; $0.stepRun = true; $0.stepCounter += 1 }          // a run step at the level before F07 A-steps (-4 dB)
        // The user's third complaint (#72: a snare drum, thin and staccato, no weight): the OLD event (knock + rattle + iron clank, builds before F07) measured 21 % of its power under 500 Hz, a centroid of
        // 2.76 kHz and 0.49 / 0.66 / 0.88 of a stone run step at strengths 0.3 / 0.6 / 1. The new physical model must be heavy: at least 70 % of the power under 500 Hz, a centroid under 700 Hz, no tone more than 6 dB
        // over its neighbours in the one-third-octave bands above 1 kHz, a level of 0.8-1.0 of a stone run step at full strength (and not louder than a run step at any), an attack of 3-8 ms, and it must ring out.
        var all: [(Float, (low: Float, centroid: Float, rise: Float), Float)] = []
        for st: Float in [0.3, 0.6, 1.0] {
            let x = Foley.doorLocked(strength: st, sampleRate: sr)
            all.append((st, metrics(x), synthPeak { $0.doorStrength = st; $0.play(.doorLocked) } / run))
        }
        let hard = Foley.doorLocked(strength: 1, sampleRate: sr)
        for (st, m, level) in all { print(String(format: "DOORHEAVY strength %.1f: %.0f %% of the power under 500 Hz, centroid %.0f Hz, worst 1/3-octave rise above 1 kHz %.1f dB, level %.2f x a stone run step", st, m.low * 100, m.centroid, m.rise, level)) }
        check(all.allSatisfy { $0.1.low >= 0.70 } && all.allSatisfy { $0.1.centroid < 700 }, "doorheavy: the door is heavy: \(all.map { String(format: "%.0f", $0.1.low * 100) }) % of the power under 500 Hz (at least 70; the old event had 21) and centroid \(all.map { String(format: "%.0f", $0.1.centroid) }) Hz (under 700; the old one 2760)")
        let mids = [Float(0.3), 0.6, 1.0].map { midShare(Foley.doorLocked(strength: $0, sampleRate: sr)) }
        print("DOORHEAVY 150-900 Hz share \(mids.map { String(format: "%.1f", $0 * 100) }) %")
        check(mids.allSatisfy { $0 >= 0.35 }, "doorheavy: the part a laptop speaker can play: at least 35 % of the power in 150-900 Hz (\(mids.map { String(format: "%.1f", $0 * 100) }) %), not only the sub-100 Hz modes")
        // A small speaker (a laptop's) plays nothing below about 200 Hz: through a 200 Hz high-pass (two poles) the door must still be heard, at least half as loud (RMS) as a stone run step through the same filter.
        func synthSamples(_ setup: (AmbienceSynth) -> Void) -> [Float] {
            let s = AmbienceSynth(sampleRate: sr); s.windGain = 0; s.surfGain = 0; s.master = 1; setup(s)
            var l = [Float](repeating: 0, count: Int(sr * 2)), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }
            return l
        }
        func rmsHP(_ x: [Float]) -> Float { let y = A.onePoleHigh(A.onePoleHigh(x, 200), 200); return (y.reduce(0) { $0 + $1 * $1 } / Float(max(y.count, 1))).squareRoot() }
        let doorHP = rmsHP(synthSamples { $0.doorStrength = 1; $0.play(.doorLocked) }), stepHP = rmsHP(synthSamples { $0.stepSurface = .stone; $0.stepRun = true; $0.stepCounter += 1 }) * (1.4 / AmbienceSynth.stepMix)
        check(doorHP > 0.5 * stepHP, "doorheavy: on a small speaker (200 Hz high-pass) the door is still there: RMS \(String(format: "%.4f", doorHP)) against \(String(format: "%.4f", stepHP)) for a stone run step at the pre-F07 level (\(String(format: "%.1f", doorHP / max(stepHP, 1e-9))) times)")
        check(all.allSatisfy { $0.1.rise < 6 }, "doorheavy: no tone above 1 kHz stands more than 6 dB over its neighbours (one-third-octave bands; worst \(all.map { String(format: "%.1f", $0.1.rise) }) dB)")
        check(all[2].2 >= 0.8 && all[2].2 <= 1.0 && all.allSatisfy { $0.2 <= 1.0 } && all[0].2 < all[1].2 && all[1].2 < all[2].2, "doorheavy: through the synth the door at full strength is \(String(format: "%.2f", all[2].2)) of a run step on stone (0.8-1.0), softer tries are softer (\(all.map { String(format: "%.2f", $0.2) }))")
        let env = A.envelope(hard, tau: 0.001), top = env.max() ?? 1
        let first = env.prefix(Int(0.02 * sr)), top20 = first.max() ?? 1                            // the rise of the first 20 ms (the modal body goes on swelling after it)
        let iHi = first.firstIndex { $0 > 0.9 * top20 } ?? 0
        let iStart = first.firstIndex { $0 > 0.1 * top20 } ?? 0
        let attack = Float(iHi >= iStart ? iHi - iStart : 0) / sr
        let lastLoud = (0..<env.count).last { env[$0] > top * 0.01 }.map { Float($0) / sr } ?? 0
        check(attack >= 0.003 && attack <= 0.008 && lastLoud > 0.25 && lastLoud < 0.95 && !hard.contains { !$0.isFinite }, "doorheavy: a 3-8 ms attack, not an impulse (10 % to 90 % of the first 20 ms in \(String(format: "%.1f", attack * 1000)) ms), and it rings for \(String(format: "%.0f", lastLoud * 1000)) ms (-40 dB), finite")
        let again = Foley.doorLocked(strength: 1, sampleRate: sr)
        check(again == hard, "doorheavy: reproducible (a fixed seed)")
    }
}

extension SelfTestRunner {
    /// F07 A-buoy (#70): the buoy bell is a positional source: the pan and the front/back follow the bearing from the listener and the player's yaw; through the synth the near ear is louder and leads, the far ear is
    /// later and duller, the pan is LIVE (it follows the head while the bell rings), and a bell behind is duller than one ahead.
    func runBuoyPlacement() {
        guard name == "all" || name == "buoyplacement" else { return }
        let dock = SIMD3<Float>(147.9, 1.4, 169.2)                                     // the user's spot in #70; the buoy is east-south-east of it
        func lv(_ yaw: Float) -> (pan: Float, front: Float) { (SonicLandmarks.pan(listener: dock, yaw: yaw, source: Layout.buoy), SonicLandmarks.front(listener: dock, yaw: yaw, source: Layout.buoy)) }
        let north = lv(0), east = lv(.pi / 2), south = lv(.pi), west = lv(-.pi / 2)
        check(north.pan > 0.3 && east.pan > 0.2 && south.pan < -0.3 && west.pan < -0.2, "buoyplacement: the pan sign follows the bearing (facing N / E / S / W: \([north, east, south, west].map { String(format: "%+.2f", $0.pan) }))")
        check(east.front > 0.7 && west.front < -0.7 && abs(north.front) < 0.7, "buoyplacement: and front/back follows it (E / W / N: \([east, west, north].map { String(format: "%+.2f", $0.front) }))")
        let sr: Float = 44100
        func render(pan: Float, front: Float = 1, seconds: Float = 0.8, flipAt: Float? = nil, flipTo: Float = 0) -> (l: [Float], r: [Float]) {
            let s = AmbienceSynth(sampleRate: sr); s.windGain = 0; s.surfGain = 0; s.master = 1
            s.buoyGain = 0.8; s.buoyPan = pan; s.buoyFront = front
            s.play(.buoy)
            let n = Int(sr * seconds)
            var l = [Float](repeating: 0, count: n), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                let flip = flipAt.map { Int($0 * sr) } ?? n
                s.render(frames: flip, left: lp.baseAddress!, right: rp.baseAddress!)
                if flip < n { s.buoyPan = flipTo; s.render(frames: n - flip, left: lp.baseAddress! + flip, right: rp.baseAddress! + flip) }
            } }
            return (l, r)
        }
        func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }
        func lag(_ a: (l: [Float], r: [Float])) -> Int {                                // > 0: the left ear is later than the right
            var best = 0, bestV: Float = -1e9
            for k in -40...40 {
                var acc: Float = 0
                for i in 200..<Int(0.3 * sr) { let j = i + k; if j >= 0 && j < a.l.count { acc += a.l[j] * a.r[i] } }
                if acc > bestV { bestV = acc; best = k }
            }
            return best
        }
        let right = render(pan: 0.8), left = render(pan: -0.8)
        check(rms(right.r[0...]) > 1.6 * rms(right.l[0...]) && rms(left.l[0...]) > 1.6 * rms(left.r[0...]), "buoyplacement: through the synth the near ear is louder (pan +0.8: R/L \(String(format: "%.2f", rms(right.r[0...]) / rms(right.l[0...]))); pan -0.8: L/R \(String(format: "%.2f", rms(left.l[0...]) / rms(left.r[0...]))))")
        let lr = lag(right), ll = lag(left)
        check(lr >= 8 && lr <= 36 && ll <= -8 && ll >= -36, "buoyplacement: the near ear leads by about half a millisecond (lag \(lr) samples with the bell on the right, \(ll) on the left; 0.63 ms is 28)")
        let swung = render(pan: 0.8, seconds: 1.4, flipAt: 0.6, flipTo: -0.8)
        let late = Int(0.9 * sr)..<Int(1.4 * sr)
        check(rms(swung.l[late]) > 1.4 * rms(swung.r[late]), "buoyplacement: the pan is live: a bell struck on the right and then turned to the left sounds from the left while it rings (L/R \(String(format: "%.2f", rms(swung.l[late]) / max(rms(swung.r[late]), 1e-9))))")
        func hiShare(_ x: [Float]) -> Float { let sp = FootstepAnalysis.spectrum(Array(x[0..<Int(0.6 * sr)])); return FootstepAnalysis.band(sp, 1500, 9000) / max(FootstepAnalysis.band(sp, 40, 9000), 1e-12) }
        let ahead = render(pan: 0, front: 1), behind = render(pan: 0, front: -1)
        check(hiShare(behind.l) < 0.7 * hiShare(ahead.l) && rms(behind.l[0...]) > 0.3 * rms(ahead.l[0...]), "buoyplacement: a bell behind is duller than one ahead (power above 1.5 kHz \(String(format: "%.3f", hiShare(behind.l))) against \(String(format: "%.3f", hiShare(ahead.l)))) but still audible")
        let far = AmbienceSynth(sampleRate: sr); far.windGain = 0; far.surfGain = 0; far.master = 1; far.buoyGain = 0; far.play(.buoy)
        check(far.chimeDelaysForTest.isEmpty, "buoyplacement: out of range (level 0) the buoy does not ring at all")
    }
}

extension SelfTestRunner {
    /// F07 A-steps (#75): the footsteps sit 4 dB lower in the mix (one constant), each surface keeping its level against the others.
    func runStepMix() {
        guard name == "all" || name == "stepmix" else { return }
        let sr: Float = 44100
        func peak(_ surface: SurfaceKind, run: Bool) -> Float {
            let s = AmbienceSynth(sampleRate: sr); s.windGain = 0; s.surfGain = 0; s.master = 1
            s.stepSurface = surface; s.stepRun = run; s.stepCounter += 1
            var l = [Float](repeating: 0, count: Int(sr * 2)), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in s.render(frames: lp.count, left: lp.baseAddress!, right: rp.baseAddress!) } }
            return l.map { abs($0) }.max() ?? 0
        }
        let db = 20 * log10(AmbienceSynth.stepMix / 1.4)
        check(abs(db + 4) < 0.05, "stepmix: the footsteps are \(String(format: "%.2f", db)) dB against the F06 mix (1.4), one constant")
        // The pinned stone run step through the synth before F07 was 0.2440 (selftest doorlevel, F06): now 0.631 of it; the surfaces keep their order (wood > stone > grass).
        let stone = peak(.stone, run: true), wood = peak(.wood, run: true), grass = peak(.grass, run: true)
        check(abs(stone / 0.2440 - 0.631) < 0.03 && wood > stone && stone > grass, "stepmix: a stone run step peaks at \(String(format: "%.3f", stone)) (0.2440 x 0.631 = 0.154) and the surfaces keep their order (wood \(String(format: "%.3f", wood)), stone, grass \(String(format: "%.3f", grass)))")
    }
}

extension SelfTestRunner {
    /// F07 A-shell (#77, #78): the floor goes through the doorway (no hole between the step and the room's floor) and the lens room's floor reaches the gallery's iron base (no open ring). Rays dropped straight down
    /// onto the tower's exterior mesh and the interior shell must land on a floor within a few cm of the floor's height at every sample.
    func runShellClosed() {
        guard name == "all" || name == "shellclosed" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "shellclosed: no Metal device"); return }
        let sc = Scene.makeWorld(device: device)
        guard let tower = sc.items.first(where: { $0.name == "lighthouse" }), let shell = sc.items.first(where: { $0.name == LighthouseInterior.wallName }) else { check(false, "shellclosed: no tower or shell item"); return }
        let L = Layout.lighthouse
        /// Height (tower frame: y = 0 at the tower's foot) of the first surface below `yFrom` at the tower-frame point (x, z), over the tower's mesh (in its own frame) and the shell's (in world coordinates).
        func floorAt(_ x: Float, _ z: Float, from yFrom: Float) -> Float? {
            var best: Float?
            for (item, offset) in [(tower, SIMD3<Float>.zero), (shell, L)] {
                let verts = item.mesh.vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: item.mesh.vertexBuffer.length / MemoryLayout<Vertex>.stride)
                let idx = item.mesh.indexBuffer.contents().bindMemory(to: UInt32.self, capacity: item.mesh.indexCount)
                let o = SIMD3(x, yFrom, z) + offset, d = SIMD3<Float>(0, -1, 0)
                for t in stride(from: 0, to: item.mesh.indexCount, by: 3) {
                    let a = SIMD3(verts[Int(idx[t])].position.x, verts[Int(idx[t])].position.y, verts[Int(idx[t])].position.z)
                    let b = SIMD3(verts[Int(idx[t + 1])].position.x, verts[Int(idx[t + 1])].position.y, verts[Int(idx[t + 1])].position.z)
                    let c = SIMD3(verts[Int(idx[t + 2])].position.x, verts[Int(idx[t + 2])].position.y, verts[Int(idx[t + 2])].position.z)
                    let e1 = b - a, e2 = c - a, p = simd_cross(d, e2), det = simd_dot(e1, p)
                    if abs(det) < 1e-9 { continue }
                    let inv = 1 / det, s = o - a, u = simd_dot(s, p) * inv
                    if u < 0 || u > 1 { continue }
                    let q = simd_cross(s, e1), v = simd_dot(d, q) * inv
                    if v < 0 || u + v > 1 { continue }
                    let dist = simd_dot(e2, q) * inv
                    if dist > 0 && (best == nil || dist < best!) { best = dist }
                }
            }
            return best.map { yFrom - $0 }
        }
        // The doorway: down the door's axis and either side of it, from the outer end of the sill to the room's floor.
        var worstDoor: Float = 0, holes = 0, n = 0
        let floor = LighthouseInterior.floorY
        for x: Float in [-0.4, 0, 0.4] {
            for z in stride(from: LighthouseInterior.innerR(floor) - 0.3, through: Lighthouse.wallR(floor) + 0.3, by: 0.1) {
                n += 1
                guard let h = floorAt(x, z, from: floor + 1.5) else { holes += 1; continue }
                worstDoor = max(worstDoor, abs(h - floor)); if abs(h - floor) > 0.02 { holes += 1 }
            }
        }
        check(n > 30 && holes == 0, "shellclosed: the floor runs through the doorway: \(n) rays down its width and thickness all land within 2 cm of the floor's height (worst \(String(format: "%.3f", worstDoor)) m, \(holes) misses)")
        // The lens room: the ring between the floor's edge (2.1 m) and the gallery's iron base (2.62 m), all round, has a floor: no ray falls below the floor's height.
        var ringHoles = 0, ringN = 0
        let lf = LighthouseInterior.lensFloorY
        for k in 0..<24 {
            let a = Float(k) / 24 * 2 * .pi
            for r in stride(from: Float(2.12), through: 2.6, by: 0.12) {
                ringN += 1
                guard let h = floorAt(r * cos(a), r * sin(a), from: lf + 1.2), h >= lf - 0.01 else { ringHoles += 1; continue }
            }
        }
        // The seam under the floor's edge: wherever the floor is there at 1.9 m (everywhere but the stair's hatch), it continues unbroken out to 2.2 m, so no crescent opens between a sector's chord and the ring.
        var seamHoles = 0, seamN = 0
        for k in 0..<180 {
            let a = Float(k) / 180 * 2 * .pi
            guard let inner = floorAt(1.9 * cos(a), 1.9 * sin(a), from: lf + 1.2), abs(inner - lf) < 0.01 else { continue }         // not the hatch
            for r in stride(from: Float(1.95), through: 2.2, by: 0.025) {
                seamN += 1
                guard let h = floorAt(r * cos(a), r * sin(a), from: lf + 1.2), h >= lf - 0.01 else { seamHoles += 1; continue }
            }
        }
        check(seamN > 600 && seamHoles == 0, "shellclosed: the floor's own seam is closed: \(seamN) rays from 1.95 to 2.2 m at every angle where the floor stands at 1.9 m all land on a floor (\(seamHoles) fell through to the ground)")
        check(ringN > 90 && ringHoles == 0, "shellclosed: the lens room's floor reaches the iron base: \(ringN) rays down the ring from 2.12 to 2.6 m all land on the floor ring, the kerb or the iron base, none falls through to the ground (\(ringHoles) misses)")
    }
}

extension SelfTestRunner {
    /// F07 A-fold (#74): pages 6, 7 and 8 stand FOLDED in the Glass Wood from the start (two panels each, not readable, not collectable), open over `PageFold.duration` s when their puzzle is solved with a light
    /// running along the crease, and then the readable page lies where the fold was. Frames: see the TASKS entry.
    func runPageFold() {
        guard name == "all" || name == "pagefold" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "pagefold: no Metal device"); return }
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
        let sc = g.scenes[.glassWood]!
        func item(_ n: String) -> DrawItem? { sc.items.first { $0.name == n } }
        g.travel(to: .glassWood); g.simulate(seconds: 0.2)
        check(PageFold.numbers == [6, 7, 8] && PageFold.allNames.allSatisfy { item($0) != nil }, "pagefold: every one of pages 6, 7 and 8 has its fold items (two panels and a light)")
        check(PageFold.numbers.allSatisfy { n in PageFold.panelNames(n).allSatisfy { item($0)?.hidden == false } && item(PageFold.lightName(n))?.hidden == true && item("page_\(n)")?.hidden == true && g.interactables.first { $0.id == "page_\(n)" }?.enabled == false },
              "pagefold: before their puzzle each stands folded and visible, the readable page is not there and cannot be read")
        // The geometry: a tent of height depth x sin(angle) that opens flat onto the page's own rest pose, the light running one way along the crease.
        let base = item("page_6")!.uniforms.model
        if name == "pagefold" { for n in PageFold.numbers { let c = item("page_\(n)")!.uniforms.model.columns.3; print("PAGEFOLD page \(n) at \(c.x), \(c.y), \(c.z)") } }
        let closed = PageFold.panelModels(base: base, opened: 0), open = PageFold.panelModels(base: base, opened: 1)
        func y(_ m: float4x4) -> Float { m.columns.3.y }
        let flatOK = (0..<4).allSatisfy { c in simd_length(SIMD3(open.a[c].x - base[c].x, open.a[c].y - base[c].y, open.a[c].z - base[c].z)) < 1e-4 && simd_length(SIMD3(open.b[c].x - base[c].x, open.b[c].y - base[c].y, open.b[c].z - base[c].z)) < 1e-4 }
        check(flatOK && y(closed.a) - y(base) > 0.12 && y(closed.a) - y(base) < 0.2, "pagefold: opened all the way the panels lie exactly on the page's rest pose; folded the crease stands \(String(format: "%.0f", (y(closed.a) - y(base)) * 100)) cm up")
        let xs = stride(from: Float(0), through: 1, by: 0.1).map { simd_dot(SIMD3(PageFold.lightModel(base: base, opened: $0).columns.3.x - base.columns.3.x, 0, PageFold.lightModel(base: base, opened: $0).columns.3.z - base.columns.3.z), SIMD3(base.columns.0.x, 0, base.columns.0.z)) }
        check(zip(xs, xs.dropFirst()).allSatisfy { $1 > $0 } && xs.first! < -0.17 && xs.last! > 0.17, "pagefold: the light runs from beyond one end of the crease to beyond the other as it opens (\(String(format: "%.2f", xs.first!)) to \(String(format: "%.2f", xs.last!)) m)")
        // The live reveal: solve the mirror court; the fold opens for `duration` s and only then is the page there.
        _ = g.drainEvents()
        for _ in 0..<3 { g.glass!.click("gw_mirror_0") }; for _ in 0..<3 { g.glass!.click("gw_mirror_1") }; for _ in 0..<2 { g.glass!.click("gw_mirror_2") }
        g.glass!.click("gw_pane_0"); g.glass!.click("gw_pane_1"); g.glass!.click("gw_pane_2")
        check(g.state.has("gw_mirrors"), "pagefold: (the mirror court is solved)")
        g.simulate(seconds: 2.0 + 0.5 * PageFold.duration)                                              // the reward's own delay, then half way through the opening
        let half = item(PageFold.panelNames(6)[0])!, light = item(PageFold.lightName(6))!
        check(!half.hidden && !light.hidden && item("page_6")!.hidden && g.interactables.first { $0.id == "page_6" }?.enabled == false && abs(y(half.uniforms.model) - y(base)) > 0.01 && abs(y(half.uniforms.model) - y(base)) < abs(y(closed.a) - y(base)),
              "pagefold: half way the fold is opening (panel lower than the closed tent), the light is running, the readable page is not yet there")
        g.simulate(seconds: 0.5 * PageFold.duration + 0.3)
        check(PageFold.panelNames(6).allSatisfy { item($0)!.hidden } && item(PageFold.lightName(6))!.hidden && !item("page_6")!.hidden && g.interactables.first { $0.id == "page_6" }?.enabled == true,
              "pagefold: then the fold is gone and the readable page lies there, ready to be read")
        check([7, 8].allSatisfy { n in PageFold.panelNames(n).allSatisfy { item($0)?.hidden == false } && item("page_\(n)")?.hidden == true }, "pagefold: the other two stay folded until their puzzles are solved")
        // A restored game with the mirror court solved has no fold at all, just the page.
        let h = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
        h.state.set("gw_mirrors"); h.glass?.restore(from: h.state.flags); h.travel(to: .glassWood); h.simulate(seconds: 0.3)
        let hs = h.scenes[.glassWood]!
        check(PageFold.panelNames(6).allSatisfy { n in hs.items.first { $0.name == n }!.hidden } && hs.items.first { $0.name == "page_6" }!.hidden == false, "pagefold: a restored game shows no fold for a solved puzzle, only the page")
    }
}

extension SelfTestRunner {
    /// F07 review of A-page2: the pages' own checks use `Scene.groundHeight`, which is not what is DRAWN (page 6 lay 3.5 cm inside the court's slabs and could not be seen). Every sheet is checked against the DRAWN
    /// geometry: rays dropped from above onto every item that is not a page (terrain, slabs, plates, the dock's boards) from 25 points of the sheet; no sheet point may be more than 3 mm below the highest surface under it.
    func runPagesSeated() {
        guard name == "all" || name == "pagesseated" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "pagesseated: no Metal device"); return }
        var report: [String] = []
        var worstAll: Float = 0
        for (scene, pages) in [(Scene.makeWorld(device: device), StoryPages.varrowIDs), (GlassWood.build(device: device), StoryPages.glassIDs)] {
            let sheet = PuzzleProps.pageMesh().vertices.map { SIMD3<Float>($0.position.x, $0.position.y, $0.position.z) }
            let sample = stride(from: 0, to: sheet.count, by: 9).map { sheet[$0] }
            let others = scene.items.filter { !$0.name.hasPrefix("page_") && !$0.name.hasPrefix("oren_fold") && $0.mesh.indexCount > 0 }
            for n in pages {
                guard let page = scene.items.first(where: { $0.name == "page_\(n)" }) else { continue }
                var worst: Float = 0                                                     // the deepest a sampled sheet point lies below the highest drawn surface under it (metres, > 0 = buried)
                for v in sample {
                    let w = page.uniforms.model * SIMD4(v, 1)
                    var top = -Float.infinity
                    for it in others {
                        let inv = it.uniforms.model.inverse
                        let o4 = inv * SIMD4(w.x, w.y + 1.0, w.z, 1), d4 = inv * SIMD4(0, -1, 0, 0)
                        let o = SIMD3(o4.x, o4.y, o4.z), d = SIMD3(d4.x, d4.y, d4.z)
                        let verts = it.mesh.vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: it.mesh.vertexBuffer.length / MemoryLayout<Vertex>.stride)
                        let idx = it.mesh.indexBuffer.contents().bindMemory(to: UInt32.self, capacity: it.mesh.indexCount)
                        for t in stride(from: 0, to: it.mesh.indexCount, by: 3) {
                            let p0 = verts[Int(idx[t])].position, p1 = verts[Int(idx[t + 1])].position, p2 = verts[Int(idx[t + 2])].position
                            let lo = SIMD3(min(p0.x, p1.x, p2.x), 0, min(p0.z, p1.z, p2.z)), hi = SIMD3(max(p0.x, p1.x, p2.x), 0, max(p0.z, p1.z, p2.z))
                            if o.x < lo.x - 1e-4 || o.x > hi.x + 1e-4 || o.z < lo.z - 1e-4 || o.z > hi.z + 1e-4 { continue }     // the ray is vertical in item space for the translation-only models used here
                            let a = SIMD3(p0.x, p0.y, p0.z), b = SIMD3(p1.x, p1.y, p1.z), c = SIMD3(p2.x, p2.y, p2.z)
                            let e1 = b - a, e2 = c - a, pp = simd_cross(d, e2), det = simd_dot(e1, pp)
                            if abs(det) < 1e-9 { continue }
                            let inv2 = 1 / det, s = o - a, u = simd_dot(s, pp) * inv2
                            if u < 0 || u > 1 { continue }
                            let q = simd_cross(s, e1), vv = simd_dot(d, q) * inv2
                            if vv < 0 || u + vv > 1 { continue }
                            let dist = simd_dot(e2, q) * inv2
                            if dist > 0 { top = max(top, (w.y + 1.0) - dist * simd_length(SIMD3(d4.x, d4.y, d4.z)) / max(simd_length(SIMD3(d4.x, d4.y, d4.z)), 1e-9)) }
                        }
                    }
                    if top > -Float.infinity { worst = max(worst, top - w.y) }
                }
                report.append("page \(n) \(String(format: "%+.1f", worst * 1000)) mm")
                worstAll = max(worstAll, worst)
            }
        }
        if name == "pagesseated" { print("PAGESSEATED " + report.joined(separator: ", ")) }
        check(report.count == 9 && worstAll < 0.003, "pagesseated: every page's sheet rests on what is drawn under it, none buried (deepest sampled point \(String(format: "%.1f", worstAll * 1000)) mm below the highest drawn surface; \(report.joined(separator: ", ")))")
    }
}

extension SelfTestRunner {
    /// S04.1: the Tide Archive's world: it builds as its own scene; every landmark stands on dry ground at its pad's height; the terraces rise from the quays to the prism chamber in order; the whole route (both quays to
    /// the prism chamber, past the sluices and down into the gallery) can be walked (no slope over half the walking limit's rise, no step); and the gallery is a court sunk into the second terrace.
    func runArchiveWorld() {
        guard name == "all" || name == "archiveworld" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "tidearchive: no Metal device"); return }
        let sc = Scene.make(.tideArchive, device: device)
        guard let t = sc.terrain else { check(false, "tidearchive: no terrain"); return }
        check(sc.kind == .tideArchive && WorldKind.allCases.contains(.tideArchive) && WorldParams.make(.tideArchive, options: LaunchOptions()).name == "The Tide Archive", "tidearchive: the world is its own scene with its own parameters")
        let marks: [(String, SIMD3<Float>)] = [("lamp end", ArchiveLayout.lampEnd), ("open end", ArchiveLayout.openEnd), ("landing", ArchiveLayout.landing), ("stacks", ArchiveLayout.stacks),
                                                ("gallery", ArchiveLayout.greatLedger), ("upper lamp", ArchiveLayout.upperLamp), ("dome", ArchiveLayout.dome), ("prism chamber", ArchiveLayout.prismChamber)] + ArchiveLayout.sluices.enumerated().map { ("sluice \($0.offset)", $0.element) }
        let bad = marks.filter { m in abs(t.sampleHeight(x: m.1.x, z: m.1.z) - m.1.y) > 0.25 || (!m.0.hasPrefix("sluice") && t.sampleHeight(x: m.1.x, z: m.1.z) < 0.3) }.map(\.0)
        check(bad.isEmpty, "tidearchive: every landmark stands at its pad's height, on dry ground (the sluice rooms are sunk below the sea on purpose; off: \(bad))")
        let order = [ArchiveLayout.lampEnd, ArchiveLayout.landing, ArchiveLayout.stacks, ArchiveLayout.upperLamp, ArchiveLayout.dome, ArchiveLayout.prismChamber].map(\.y)
        check(zip(order, order.dropFirst()).allSatisfy { $1 >= $0 - 0.05 } && order[order.count - 1] - order[0] > 15 && Set(order.map { Int($0 / 3) }).count >= 4, "tidearchive: the terraces climb from the quays to the prism chamber (never down, more than 15 m in all, at least four levels: \(order.map { String(format: "%.1f", $0) }) m)")
        // The route: every metre of both legs, the ground's slope between samples.
        var worst: Float = 0, worstAt = SIMD2<Float>(0, 0), steps = 0
        for leg in [ArchiveLayout.path, ArchiveLayout.eastApproach] {
            for k in 0..<(leg.count - 1) {
                let a = SIMD2(leg[k].x, leg[k].z), b = SIMD2(leg[k + 1].x, leg[k + 1].z), len = simd_length(b - a)
                var prev = t.sampleHeight(x: a.x, z: a.y)
                for i in 1...Int(len) {
                    let p = a + (b - a) * (Float(i) / len)
                    let h = t.sampleHeight(x: p.x, z: p.y)
                    let slope = abs(h - prev); steps += 1
                    if slope > worst { worst = slope; worstAt = p }
                    prev = h
                }
            }
        }
        check(steps > 400 && worst < 0.5 * Player.maxSlope, "tidearchive: the whole route can be walked: \(steps) one-metre steps, the steepest \(String(format: "%.2f", worst)) at (\(Int(worstAt.x)), \(Int(worstAt.y))) (limit \(Player.maxSlope), half of it allowed)")
        // The gallery is sunk into the second terrace: its floor well below the terrace round it.
        let g = ArchiveTerrain.gallery, rim = t.sampleHeight(x: g.centre.x - g.half.x - 8, z: g.centre.y)
        let floor = t.sampleHeight(x: g.centre.x, z: g.centre.y)
        check(rim - floor > 3 && floor > 3 && floor < 9, "tidearchive: the Great Ledger gallery is a court sunk \(String(format: "%.1f", rim - floor)) m into the terrace (floor \(String(format: "%.1f", floor)) m, dry until its water is added)")
        // The ground round the island falls into the sea: nothing walkable beyond the shore.
        check(t.sampleHeight(x: 0, z: 260) < -1 && t.sampleHeight(x: 0, z: -260) < -1, "tidearchive: the island ends in the sea on its south and north sides")
    }
}

extension SelfTestRunner {
    /// S04.2: the tide. A pure function of the clock (period 90 s, -1.0 to +1.4 m, low at t = 0); the sluice rooms are reachable only while the water in them is wadeable, each for a different share of the cycle
    /// (the tide room most of it, the wind room about half, the stone room only near low tide); the region API reports it; the water pass lifts the sea to it (frames: see TASKS).
    func runTide() {
        guard name == "all" || name == "tide" else { return }
        check(abs(Tide.metres(0) + 1.0) < 1e-4 && abs(Tide.metres(45) - 1.4) < 1e-4 && abs(Tide.metres(90) + 1.0) < 1e-4 && abs(Tide.metres(30) - Tide.metres(30 + 90)) < 1e-4,
              "tide: low (-1.0 m) at 0 s, high (+1.4 m) at 45 s, the same again every 90 s (\(String(format: "%.2f", Tide.metres(22.5))) m at a quarter)")
        let shares = ArchiveLayout.sluiceFloors.map { Tide.wadeableShare(ground: $0) }
        check(shares[0] > 0.7 && shares[0] < 0.9 && shares[1] > 0.4 && shares[1] < 0.6 && shares[2] > 0.2 && shares[2] < 0.4, "tide: the sluice rooms (floors 0.8, -0.2, -0.9 m) can be waded for \(shares.map { String(format: "%.0f", $0 * 100) }) % of the cycle (the tide room most, the stone room least: about 80, 50 and 30 %)")
        // The windows come from the rooms' floors (B's `Tide.window(forFloor:)`, Q33): whenever a gate's window is open the water in its room is wadeable, so the gate can be reached while it answers.
        var windowOK = true, someClosed = [false, false, false]
        for n in 0..<900 {
            let t = Float(n) / 900 * Tide.period
            for k in 0..<3 {
                if Tide.inWindow(k, level: Tide.level(t)) && Tide.depth(ground: ArchiveLayout.sluiceFloors[k], time: t) > Tide.wadeDepth + 0.01 { windowOK = false }
                if !Tide.inWindow(k, level: Tide.level(t)) { someClosed[k] = true }
            }
        }
        check(windowOK && someClosed.allSatisfy { $0 }, "tide: whenever a gate's window is open the water in its room can be waded (windows from the floors), and each window does close")
        let low = ArchiveLayout.sluiceFloors.map { Tide.isWadeable(ground: $0, time: 0) }, high = ArchiveLayout.sluiceFloors.map { Tide.isWadeable(ground: $0, time: 45) }
        check(low == [true, true, true] && high == [false, false, false], "tide: at low tide every room can be reached; at high tide (1.4 m) every room is too deep (\(low) / \(high))")
        let wait = ArchiveLayout.sluiceFloors.map { Tide.nextWadeable(ground: $0, after: 45) ?? -1 }
        check(wait[0] > 0 && wait[1] > wait[0] && wait[2] > wait[1], "tide: after high tide the rooms open again in turn (the tide room first, then the wind room, then the stone room: waits \(wait.map { String(format: "%.0f", $0) }) s)")
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let sc = Scene.make(.tideArchive, device: device)
        let region = ReachableRegion.make(.tideArchive, scene: sc)
        let p = ArchiveLayout.sluices[0]
        check(region.reachableNow(p, time: 0, kind: .tideArchive) && !region.reachableNow(p, time: 45, kind: .tideArchive) && region.reachableNow(ArchiveLayout.landing, time: 45, kind: .tideArchive),
              "tide: the reachable-region API reports the tide: the tide room is reachable at low tide and not at high tide, the landing always")
        check(Renderer.tideLevelFor(.tideArchive, clock: 45) > 1.3 && Renderer.tideLevelFor(.varrow, clock: 45) == 0 && Renderer.tideLevelFor(.glassWood, clock: 45) == 0,
              "tide: the renderer lifts the sea in the Archive only (varrow and glass wood stay at 0)")
    }
}

extension SelfTestRunner {
    /// S04.3: the Archive's things are there and stand on the ground: the stacks, the dome, the chamber, the prism (glass) with one beam in and three out (light: no shadow), three sluices (frame, gate, wheel each, the gate
    /// rising over its slots and the wheel turning), the lanterns on footings; every placed piece touches the ground under it (nothing hovers, nothing is buried more than a footing's depth), each landmark's
    /// building sits at its pad's height, and the solid ones block the player.
    func runArchiveProps() {
        guard name == "all" || name == "archiveprops" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "archiveprops: no Metal device"); return }
        let sc = Scene.make(.tideArchive, device: device)
        func item(_ n: String) -> DrawItem? { sc.items.first { $0.name == n } }
        let names = ["ta_stacks", "ta_dome", "ta_chamber", ArchiveProps.prismName, ArchiveProps.beamInName, "ta_lanterns", "ta_lantern_cores"] + (0..<3).flatMap { [ArchiveProps.sluiceName($0), ArchiveProps.gateName($0), ArchiveProps.wheelName($0), ArchiveProps.beamOutName($0)] }
        let missing = names.filter { item($0) == nil }
        check(missing.isEmpty && item(ArchiveProps.prismName)?.refractive == true, "archiveprops: the stacks, dome, chamber, prism (glass), beams, three sluices and the lanterns exist (missing: \(missing))")
        check(([ArchiveProps.beamInName, "ta_lantern_cores"] + (0..<3).map { ArchiveProps.beamOutName($0) }).allSatisfy { item($0)?.castsShadow == false }, "archiveprops: the beams and the lamp cores are light: they cast no shadow")
        // Contact: every recorded piece.
        var up: [String: Float] = [:], down: [String: Float] = [:], counts: [String: Int] = [:]
        for p in sc.placed { let g = Placement.contact(p, terrain: sc.terrain); counts[p.kind, default: 0] += 1; up[p.kind] = max(up[p.kind] ?? -9, g.touching); down[p.kind] = min(down[p.kind] ?? 9, g.touching) }
        let kinds = ["ta_shelf", "ta_dome", "ta_lantern"]
        check(kinds.allSatisfy { (counts[$0] ?? 0) > 0 } && (counts["ta_shelf"] ?? 0) == ArchiveProps.stackUnits * ArchiveProps.stackRows && (counts["ta_lantern"] ?? 0) >= 12,
              "archiveprops: the placed pieces are recorded (\(counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }))")
        check(kinds.allSatisfy { (up[$0] ?? 0) <= 0.03 && (down[$0] ?? 0) >= ($0 == "ta_dome" ? -0.9 : -0.6) }, "archiveprops: nothing hovers and nothing is buried deeper than its footing (largest gap \(kinds.map { String(format: "%.3f", up[$0] ?? 0) }) m, deepest \(kinds.map { String(format: "%.2f", down[$0] ?? 0) }) m for shelf / dome / lantern)")
        // The chamber and the sluice rooms sit on their pads' flat ground.
        let t = sc.terrain!
        let c = ArchiveLayout.prismChamber, flat = (0..<8).map { k -> Float in let a = Float(k) / 8 * 2 * .pi; return t.sampleHeight(x: c.x + cos(a) * 6, z: c.z + sin(a) * 6) }
        check((flat.max()! - flat.min()!) < 0.6 && abs(t.sampleHeight(x: c.x, z: c.z) - c.y) < 0.25 && ArchiveLayout.sluices.allSatisfy { abs(t.sampleHeight(x: $0.x, z: $0.z) - $0.y) < 0.25 },
              "archiveprops: the chamber's ring (\(String(format: "%.2f", flat.max()! - flat.min()!)) m of relief) and the sluice rooms sit on flat pads")
        // The sluice gate rises over its slots, the wheel turns, and nothing else moves.
        let g0 = ArchiveProps.sluiceGateModel(1, open: 0), g1 = ArchiveProps.sluiceGateModel(1, open: 1), g2 = ArchiveProps.sluiceGateModel(1, open: 2)
        let w0 = ArchiveProps.sluiceWheelModel(1, turns: 0), w1 = ArchiveProps.sluiceWheelModel(1, turns: 0.25)
        check(abs((g1.columns.3.y - g0.columns.3.y) - ArchiveProps.gateLift) < 1e-4 && g2.columns.3.y == g1.columns.3.y && abs(w0.columns.0.x - 1) < 1e-4 && abs(w1.columns.0.x) < 1e-4 && abs(abs(w1.columns.0.y) - 1) < 1e-4,
              "archiveprops: a gate lifts \(ArchiveProps.gateLift) m when opened (and no further) and the wheel turns about its axis")
        // The solid buildings block the player.
        func blocked(_ p: SIMD2<Float>) -> Bool { sc.colliders.cylinders.contains { simd_length(p - $0.center) < $0.radius + Player.radius } }
        let pc = ArchiveLayout.prismChamber, jx = (ArchiveProps.chamberRadius - 0.45) * cos(75 * Float.pi / 180), jz = (ArchiveProps.chamberRadius - 0.45) * sin(75 * Float.pi / 180)
        check(blocked(SIMD2(ArchiveLayout.dome.x, ArchiveLayout.dome.z)) && blocked(SIMD2(pc.x + 6.3, pc.z)) && blocked(SIMD2(pc.x + jx, pc.z + jz)) && blocked(SIMD2(pc.x - jx, pc.z + jz))
              && !blocked(SIMD2(pc.x, pc.z + jz)) && !blocked(SIMD2(pc.x, pc.z + 2.5)) && !blocked(SIMD2(pc.x + 0.6, pc.z + jz)) && blocked(SIMD2(ArchiveLayout.sluices[0].x + 3.2, ArchiveLayout.sluices[0].z)) && !blocked(SIMD2(ArchiveLayout.sluices[0].x, ArchiveLayout.sluices[0].z + 3)),
              "archiveprops: the dome, the chamber's wall and BOTH of its doorway's jambs and the sluice walls block the player; the doorway's span (1.5 m clear between the jambs' colliders) and the sluice gap are open")
    }
}

extension SelfTestRunner {
    /// S04.2 (review): the tide must reach the WATER on screen, not only the arithmetic: the frame of a sluice room at low tide (a dry floor) differs a great deal from the same view at high tide (a full room), and
    /// the view at the same level 90 s later does not; the frame uniform and the water pass's level agree with `Tide.level`; and the player wades relative to the sea.
    func runTideOnScreen() {
        guard name == "all" || name == "tide" else { return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.world = .tideArchive; renderer.taaEnabled = false
        let w = 400, h = 225
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        let target = device.makeTexture(descriptor: desc)!
        let cam = Screenshot.viewCamera("ta-sluice", renderer: renderer)
        func frame(_ t: Float) -> [Float] {
            renderer.fixedTime = t
            for _ in 0..<2 { let cb = renderer.queue.makeCommandBuffer()!; renderer.encode(commandBuffer: cb, target: target, camera: cam); cb.commit(); cb.waitUntilCompleted() }
            return Shimmer.luma(target)
        }
        let low = frame(0), high = frame(45), low2 = frame(90)
        func diff(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(a.count) }
        let dHigh = diff(low, high), dSame = diff(low, low2)
        check(dHigh > 4 && dHigh > 5 * dSame, "tide on screen: a sluice room at high tide looks nothing like the same room at low tide (mean luma difference \(String(format: "%.1f", dHigh))), and looks like it again a tide later (\(String(format: "%.2f", dSame)))")
        _ = frame(45)                                                                   // the frame uniform is written while a frame is encoded
        check(abs(renderer.tideLevel - Tide.metres(45)) < 1e-4 && abs(renderer.frame.worldB.y - Tide.metres(45)) < 1e-4 && renderer.frame.worldB.z == 1, "tide on screen: the water pass's level and the frame uniform are the tide (\(renderer.tideLevel), \(renderer.frame.worldB.y))")
        defer { Player.sea = 0 }
        Player.sea = 0
        let dry = Player.wading(ground: -0.9)
        Player.sea = 1.4
        check(Player.wading(ground: -0.9) < dry + 1e-6 && Player.wading(ground: 1.0) < 1 && Player.wading(ground: 2.5) == 1, "tide on screen: wading follows the sea (ground 1.0 m at high tide slows the player: \(String(format: "%.2f", Player.wading(ground: 1.0))), ground 2.5 m does not)")
    }
}

extension SelfTestRunner {
    /// S04.3 follow-up (builder B's Pending-A items): the pages 10-15 lie on the ground at the layout's spots, one object each; the chain map, the tableau (wall, two lanterns, glow, cut-outs that show the right
    /// version and only then), the two tools, the gallery's water body (flat, drawn by the water pass, drained by moving it down, a limit on wading into it); the sluice gates lift when B's emissive says open and their
    /// colliders follow; the marks stand at each window's water levels; the prism's components turn with the ring and rest on the marks at the targets; a flooded room walks the player out.
    func runArchiveStory() {
        guard name == "all" || name == "archivestory" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "archivestory: no Metal device"); return }
        let sc = Scene.make(.tideArchive, device: device)
        func item(_ n: String) -> DrawItem? { sc.items.first { $0.name == n } }
        let sheet = PuzzleProps.pageMesh().vertices.map { SIMD3<Float>($0.position.x, $0.position.y, $0.position.z) }
        var worstClear: Float = 0, pagesOK = true
        for (i, n) in StoryPages.archiveIDs.enumerated() {
            guard let p = item(ArchiveStory.pageName(n)) else { pagesOK = false; continue }
            let c = DroppedPages.lowestClearance(vertices: sheet, model: p.uniforms.model, ground: { sc.groundHeight(x: $0, z: $1) })
            worstClear = max(worstClear, c); if c < 0.0005 || c > 0.005 { pagesOK = false }
            let o = SIMD2(p.uniforms.model.columns.3.x, p.uniforms.model.columns.3.z), s = ArchiveLayout.pageSpots[i]
            if simd_length(o - SIMD2(s.x, s.z)) > 0.6 { pagesOK = false }
        }
        check(StoryPages.archiveIDs.count == 6 && pagesOK, "archivestory: pages 10-15 (ti_page_<n>) lie on the ground at their six spots, each resting within 5 mm (worst \(String(format: "%.1f", worstClear * 1000)) mm)")
        check(["ti_chain_map", "ti_find_fork", "ti_find_lens", ArchiveStory.wallName, ArchiveStory.lanternName(.ilse), ArchiveStory.lanternName(.oren), ArchiveStory.glowName, ArchiveStory.waterName, ArchiveProps.ringName, ArchiveProps.markName(0), ArchiveProps.markName(2)].allSatisfy { item($0) != nil }, "archivestory: the chain map, the two tools, the tableau's wall and lanterns, the gallery water, the prism ring and its marks exist")
        // The tableau: dark until a version is shown; then exactly that version's two figures (their postures) and the glow.
        func shownFigures() -> [String] { sc.items.filter { $0.name.hasPrefix("ta_tableau_fig_") && !$0.hidden }.map(\.name).sorted() }
        ArchiveProps.update(sc, time: 1, ringAngle: nil, tableau: nil)
        let dark = shownFigures().isEmpty && item(ArchiveStory.glowName)?.hidden == true
        ArchiveProps.update(sc, time: 1.1, ringAngle: nil, tableau: .ilse)
        let ilse = shownFigures(), orenFigs = ShadowTableaux.archive.figures(.oren).enumerated().map { ArchiveStory.figureName($0.element.posture, $0.offset) }.sorted()
        let ilseWant = ShadowTableaux.archive.figures(.ilse).enumerated().map { ArchiveStory.figureName($0.element.posture, $0.offset) }.sorted()
        ArchiveProps.update(sc, time: 1.2, ringAngle: nil, tableau: .oren)
        let oren = shownFigures()
        check(dark && ilse == ilseWant && oren == orenFigs && ilse != oren && item(ArchiveStory.glowName)?.hidden == false, "archivestory: the tableau is dark until lit; Ilse's side shows her version's figures \(ilse.count), Oren's the other's, and they differ")
        ArchiveProps.update(sc, time: 1.3, ringAngle: nil, tableau: nil)
        // The gates: B's emissive = open lifts the plate (eased), turns the wheel, takes the collider out; closing puts it back.
        func blocked(_ k: Int) -> Bool { let c = ArchiveLayout.sluices[k]; return sc.colliders.cylinders.contains { simd_length(SIMD2(c.x, c.z) - $0.center) < $0.radius + 0.01 && $0.radius > 0.8 && $0.radius < 1.0 } }
        let closedBlocks = (0..<3).allSatisfy(blocked)
        sc.update(ArchiveProps.gateName(1)) { $0.uniforms.emissive = SIMD4(0.55, 0.85, 1.0, 1.4) }
        var t: Float = 2
        for _ in 0..<100 { t += 0.1; ArchiveProps.update(sc, time: t, ringAngle: nil, tableau: nil) }
        let lifted = item(ArchiveProps.gateName(1))!.uniforms.model.columns.3.y - ArchiveLayout.sluices[1].y
        let openFree = !blocked(1) && blocked(0) && blocked(2)
        sc.update(ArchiveProps.gateName(1)) { $0.uniforms.emissive = SIMD4(0, 0, 0, 0) }
        for _ in 0..<100 { t += 0.1; ArchiveProps.update(sc, time: t, ringAngle: nil, tableau: nil) }
        check(closedBlocks && abs(lifted - ArchiveProps.gateLift) < 0.05 && openFree && blocked(1) && abs(item(ArchiveProps.gateName(1))!.uniforms.model.columns.3.y - ArchiveLayout.sluices[1].y) < 0.05,
              "archivestory: closed gates block their gap; an open one rises \(String(format: "%.2f", lifted)) m and the gap is free; closing puts the plate and the collider back")
        // The prism: the three components turn with the ring and each rests on its mark at its own target.
        var rests = true
        for k in 0..<3 {
            ArchiveProps.update(sc, time: t + 1, ringAngle: TideArchivePuzzle.beamTargets[k], tableau: nil)
            let lit = (0..<3).map { item(ArchiveProps.markName($0))!.uniforms.emissive.w > 1 }
            let dir = item(ArchiveProps.beamOutName(k))!.uniforms.model.columns.1
            let a = atan2(dir.z, dir.x), m = ArchiveProps.markAngle(k)
            var d = (a - m).truncatingRemainder(dividingBy: 2 * Float.pi); if d > Float.pi { d -= 2 * Float.pi }; if d < -Float.pi { d += 2 * Float.pi }
            if lit != (0..<3).map({ $0 == k }) || abs(d) > 0.05 { rests = false }
        }
        ArchiveProps.update(sc, time: t + 2, ringAngle: -0.4, tableau: nil)
        check(rests && (0..<3).allSatisfy { item(ArchiveProps.markName($0))!.uniforms.emissive.w == 0 }, "archivestory: with the ring on gate k's angle component k lies on mark k and only that mark glows; between the targets none does")
        // The marks: each gate's band stands where its window's water levels are (a thin brass cap at the window's top above the floor); the rooms flood: walk out.
        let deepPoint = SIMD3(ArchiveLayout.sluices[2].x + 2, ArchiveLayout.sluices[2].y, ArchiveLayout.sluices[2].z)
        let push = ArchiveProps.floodPush(position: deepPoint, sea: 1.2), none = ArchiveProps.floodPush(position: deepPoint, sea: ArchiveLayout.sluices[2].y + 0.3)
        check(push != nil && push!.x > 0.9 && none == nil && ArchiveProps.floodPush(position: ArchiveLayout.landing, sea: 1.4) == nil, "archivestory: a player standing in a room the tide has flooded deeper than \(ArchiveProps.floodDepth) m is walked out of it (away from its centre); in shallow water and on the route nothing happens")
        // The gallery: the water is a body of its own at its full level, lowered by B's drain; wading into it is limited by its depth.
        let w = item(ArchiveStory.waterName)!
        check(w.isWaterBody && w.refractive && !w.castsShadow && abs(ArchiveStory.waterLevel(sc, clock: 0) - (ArchiveStory.galleryFull - ArchiveStory.galleryTide)) < 0.01 && abs(ArchiveStory.waterLevel(sc, clock: 45) - (ArchiveStory.galleryFull + ArchiveStory.galleryTide)) < 0.01,
              "archivestory: the gallery's water is a body drawn by the water pass at its full level (\(String(format: "%.1f", ArchiveStory.galleryFull)) m, rising and falling \(ArchiveStory.galleryTide) m with the tide)")
        sc.update(ArchiveStory.waterName) { $0.uniforms.model = translation(SIMD3(0, -ArchiveStory.drainDepth, 0)) }
        check(ArchiveStory.waterLevel(sc, clock: 45) <= ArchiveStory.galleryFloor + 0.01 && ArchiveStory.waterLevel(sc, clock: 45) > ArchiveStory.galleryFloor - 0.2, "archivestory: drained (B moves it down \(ArchiveStory.drainDepth) m) its surface is at or just under the floor, whatever the tide")
        let g = ArchiveTerrain.gallery
        Player.galleryWater = (g.centre, g.half, ArchiveStory.galleryFull)
        check(Player.tooDeepInGallery(g.centre, ground: ArchiveStory.galleryFloor) && !Player.tooDeepInGallery(g.centre + SIMD2(g.half.x + 5, 0), ground: ArchiveStory.galleryFloor) && !Player.tooDeepInGallery(g.centre, ground: ArchiveStory.galleryFull - 0.1),
              "archivestory: the player does not wade down into the gallery's flooded floor, only into water shallower than \(-Player.minGround) m, and not outside it")
        Player.galleryWater = nil
    }
}

extension SelfTestRunner {
    /// S04.3 review: the water pass draws the gallery's water (full vs drained looks different on screen), and the lining, the flooded court and the closed sluice gate hold a walking player.
    func runArchiveWalk() {
        guard name == "all" || name == "archivewalk" || name == "archivestory" else { return }
        defer { Player.galleryWater = nil; Player.sea = 0 }
        let gg = ArchiveTerrain.gallery
        // On screen: the gallery full of water against the same court drained (the model moved down by the drain depth) differs a lot; two full frames do not.
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.world = .tideArchive; renderer.taaEnabled = false
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: 400, height: 225, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        let target = device.makeTexture(descriptor: desc)!
        let cam = Screenshot.viewCamera("ta-gallery", renderer: renderer)
        func frame(drain: Float) -> [Float] {
            renderer.scene.update(ArchiveStory.waterName) { $0.uniforms.model = translation(SIMD3(0, -drain, 0)) }
            renderer.fixedTime = 20
            for _ in 0..<2 { let cb = renderer.queue.makeCommandBuffer()!; renderer.encode(commandBuffer: cb, target: target, camera: cam); cb.commit(); cb.waitUntilCompleted() }
            return Shimmer.luma(target)
        }
        let full = frame(drain: 0), drained = frame(drain: ArchiveStory.drainDepth), full2 = frame(drain: 0)
        func diff(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(a.count) }
        let dDrain = diff(full, drained), dSame = diff(full, full2)
        check(dDrain > 4 && dDrain > 5 * dSame, "archivewalk: the gallery full of water looks nothing like the drained court on screen (mean luma difference \(String(format: "%.1f", dDrain)) against \(String(format: "%.2f", dSame)) between two full frames)")
        // On foot.
        let sc = Scene.make(.tideArchive, device: device)
        let game = Game(scenes: [.varrow: Scene.makeWorld(device: device), .tideArchive: sc])
        game.travel(to: .tideArchive)
        let bot = PlaythroughBot(game)
        func inCourt(_ p: SIMD2<Float>) -> Bool { let d = simd_abs(p - gg.centre); return d.x < gg.half.x - 0.3 && d.y < gg.half.y - 0.3 }
        func place(_ p: SIMD2<Float>, yaw: Float) { game.player = Player(position: SIMD3(p.x, sc.groundHeight(x: p.x, z: p.y), p.y), yaw: yaw) }
        // The lining: from outside the north, east and south walls, walking straight at the court's centre never gets inside.
        var breached = 0
        for off in [SIMD2<Float>(0, -gg.half.y - 4), SIMD2(gg.half.x + 4, 0), SIMD2(0, gg.half.y + 4)] {
            place(gg.centre + off, yaw: 0)
            bot.walk(to: SIMD3(gg.centre.x, 0, gg.centre.y), within: 1, timeout: 25, straight: true)
            if inCourt(SIMD2(game.player.position.x, game.player.position.z)) { breached += 1 }
        }
        check(breached == 0, "archivewalk: walking straight at the Great Ledger court from outside its north, east and south walls stops at the lining (\(breached) of 3 got in)")
        // The flooded court: entering from the west opening at the route's z, the player never stands in water deeper than the wading limit.
        game.simulate(seconds: 0.5)
        var worst: Float = 0, entered = false
        place(SIMD2(gg.centre.x - gg.half.x - 6, ArchiveLayout.greatLedger.z), yaw: .pi / 2)
        for k in 0..<(30 * 60) {
            var input = InputState(); input.move = SIMD2(0, 1)
            game.player.yaw = .pi / 2; game.player.pitch = 0
            let p0 = game.player.position
            bot.tick(input)
            let p = game.player.position, g = sc.groundHeight(x: p.x, z: p.z), g0 = sc.groundHeight(x: p0.x, z: p0.z)
            if let w = Player.galleryWater, inCourt(SIMD2(p.x, p.z)) {
                entered = true
                if w.level - g > w.level - g0 + 1e-4 { worst = max(worst, w.level - g) }                       // only steps that deepened the water count (a rising tide may deepen a standing player)
            }
        }
        check(entered && worst <= -Player.minGround + 0.05, "archivewalk: walking east through the west opening into the flooded court never wades deeper than \(-Player.minGround) m (deepest \(String(format: "%.2f", worst)) m)")
        // The closed sluice gate holds a player at its gap; open (B's emissive), they pass.
        func gateTrial(open: Bool) -> Float {
            let s = Scene.make(.tideArchive, device: device)
            let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .tideArchive: s]); g.travel(to: .tideArchive)
            let c = ArchiveProps.gateCollider(0).center
            if open { s.update(ArchiveProps.gateName(0)) { $0.uniforms.emissive.w = 1 } }
            g.simulate(seconds: 4)
            let b = PlaythroughBot(g)
            let start = c + SIMD2(0, 4)                                              // yaw 0 faces -z: from the room's far side toward the gap
            g.player = Player(position: SIMD3(start.x, s.groundHeight(x: start.x, z: start.y), start.y), yaw: 0)
            var minD: Float = 99
            for _ in 0..<(12 * 60) {
                var input = InputState(); input.move = SIMD2(0, 1); g.player.yaw = 0; g.player.pitch = 0
                b.tick(input)
                minD = min(minD, simd_length(SIMD2(g.player.position.x, g.player.position.z) - c))
            }
            return minD
        }
        let closedD = gateTrial(open: false), openD = gateTrial(open: true)
        check(closedD > 0.8 && openD < 0.5, "archivewalk: walking at sluice gate 0 straight on, a closed gate stops you \(String(format: "%.2f", closedD)) m from its centre, an open one lets you through (closest \(String(format: "%.2f", openD)) m)")
    }
}
