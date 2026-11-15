import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Headless capture: renders N frames offscreen through the normal pipeline and writes a PNG.
/// This is how agents "see" the game without opening a window.
enum Screenshot {
    enum Failure: Error { case texture, image, write(String) }

    /// Render one frame at `camera` and write it as a PNG (used by the in-game feedback panel).
    static func snapshot(renderer: Renderer, camera: Camera, width: Int, height: Int, to url: URL) throws {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: desc), let cb = renderer.queue.makeCommandBuffer() else { throw Failure.texture }
        renderer.encode(commandBuffer: cb, target: target, camera: camera)
        cb.commit(); cb.waitUntilCompleted()
        if let err = cb.error { throw Failure.write("GPU error: \(err)") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writePNG(texture: target, to: url.path)
    }

    /// `--state`: put the world into a puzzle state so it can be photographed.
    @discardableResult
    static func applyState(_ name: String?, scenes scenesForState: [WorldKind: Scene]) -> Game? {
        guard let name else { return nil }
        let g = Game(scenes: scenesForState)
        switch name {
        case "solved": g.puzzle.forceSolved()
        case "travelled": g.puzzle.forceSolved(); g.state.set("lensTouched")
        case "mirrors": g.glass?.forceMirrorsSolved()
        case "chimes": g.glass?.forceChimesSolved()
        case "both": g.glass?.forceMirrorsSolved(); g.glass?.forceChimesSolved(); g.glass?.forceAltar()
        case "mirrorswrong": g.glass?.setArrangement(mirrors: MirrorCourt.solutionMirrors, panes: [2, 0, 1])
        // P02.1: the court with 0, 1, 2 receiving crystals lit (3 is `mirrors`); the arrangements are the ones the careful six clicks pass through
        case "court0": g.glass?.setArrangement(mirrors: [3, 1, 1], panes: [2, 1, 0])
        case "court1": g.glass?.setArrangement(mirrors: MirrorCourt.initialMirrors, panes: MirrorCourt.initialPanes)
        case "court2": g.glass?.setArrangement(mirrors: [3, 1, 3], panes: [1, 1, 0])
        case let s where s.hasPrefix("charge"):          // F10.3: every charge meter of the world at a level (`charge` = 60 %, `charge25`, `charge100`, ...)
            let pct = Float(s.dropFirst(6)).map { $0 / 100 } ?? 0.6
            for sc in scenesForState.values { for n in ChargeMeter.allNames { ChargeMeter.set(sc, n, level: pct) } }
        case "crystals", "crystals1", "crystals2", "crystalswrong", "crystalsblaze":          // F10 A2: the three receiving crystals: all lit (the pane colours), one or two lit, or solved (blazing)
            let n = name == "crystals1" ? 1 : (name == "crystals2" ? 2 : 3)
            for sc in scenesForState.values { for k in 0..<ReceiverGlow.count {
                let col = name == "crystalswrong" ? GlassPuzzleProps.color(-1) : GlassPuzzleProps.color(k)
                ReceiverGlow.set(sc, k, level: k < n ? 1 : 0, color: col, blaze: name == "crystalsblaze")
            } }
        case "bays", "bayssour", "baysmixed":          // S05.1: the shelf bays all warm, all sour, or a mix (0 warm and swinging, 1 sour, 2 warm, 3 and 4 dormant)
            for sc in scenesForState.values { for k in 0..<ShelfBays.count {
                let look: ShelfBays.Look = name == "bays" ? .warm : (name == "bayssour" ? .sour : [.warm, .sour, .warm, .dormant, .dormant][k])
                ShelfBays.set(sc, k, look: look, swing: name == "baysmixed" && k == 0 ? 0.8 : 0)
            } }
        case "ledger": for sc in scenesForState.values { LedgerRoom.setDoor(sc, open: 1) }          // S05.1: the ledger room's door open (sunk into the floor)
        case "pipesagree":                   // S05.1: every pipe at its gate's level, agreeing with the fork (crowns lit)
            for sc in scenesForState.values { for k in 0..<BellPipes.count { BellPipes.set(sc, k, level: IlseTones.matchLevel(k), agree: 1) } }
        case let s where s.hasPrefix("pipes"):          // `pipes` = every pipe's water at 60 %, `pipes25`, `pipes100`, ...
            let pct = Float(s.dropFirst(5)).map { $0 / 100 } ?? 0.6
            for sc in scenesForState.values { for k in 0..<BellPipes.count { BellPipes.set(sc, k, level: pct) } }
        case "windows", "windows1", "windows2":          // S05.2: all three dome windows lit (the prism's components all there), or only the first, or the first two
            let n = name == "windows1" ? 1 : (name == "windows2" ? 2 : 3)
            for sc in scenesForState.values { for k in 0..<DomeWindows.count { DomeWindows.set(sc, k, lit: k < n ? 1 : 0) }; PrismInputs.set(sc, lit: (0..<3).map { $0 < n }) }
        case "prismdark":                    // S05.2: no window lit: the prism's components are dim ghosts
            for sc in scenesForState.values { PrismInputs.set(sc, lit: [false, false, false]) }
        case "orreryheld":                   // S05.2: each arm stopped at its own alignment (pointing at its window), the windows lit
            for sc in scenesForState.values { for k in 0..<Orrery.armCount { Orrery.hold(sc, k, at: Orrery.alignmentClock(k)); DomeWindows.set(sc, k, lit: 1) } }
        case "marks":                       // A6: every tide mark held lit (the pulse is driven by the clock: use --clock to see the water cross a bar)
            for sc in scenesForState.values { for k in 0..<TideMarks.count { TideMarks.set(sc, k, lit: 1) } }
        case "tide": g.puzzle.strike(.tide)
        case "tidewind": g.puzzle.strike(.tide); g.simulate(seconds: 0.7); g.puzzle.strike(.wind)
        case "fork", "forkoren":            // F08.1: the lens room at the fork (the altar solved, the gate ready, the door open); forkoren: the ring turned onto the receiver and the doorway of light open
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end"); g.story.contradictionsResolved = ["who-left"]; g.state.set(Game.doorOpenFlag)
            var t = 100.0
            func frames(_ n: Int) { for _ in 0..<n { t += 0.05; g.advance(now: t, input: InputState()) } }
            frames(4)
            if name == "forkoren" { for _ in 0..<3 { g.lensPortal.turn(1); g.simulate(seconds: 0.3) }; g.simulate(seconds: LensPortalProps.holdSeconds + 0.6) }
            frames(4)
        default: FileHandle.standardError.write(Data("unknown --state \(name)\n".utf8))
        }
        g.simulate(seconds: 1.5)
        g.settleAtmosphere()
        _ = g.drainEvents()
        return g
    }

    /// `--bench N`: render N frames per viewpoint offscreen and report GPU time, so performance can be judged
    /// without a window. Each frame is waited on, so the numbers are GPU-bound times, not queue depth.
    static func bench(renderer: Renderer, options: LaunchOptions) throws {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.outputFormat, width: options.width, height: options.height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let target = renderer.device.makeTexture(descriptor: desc) else { throw Failure.texture }
        renderer.fixedTime = nil
        print("benchmark at \(options.width)x\(options.height), \(options.benchFrames ?? 0) frames per view")
        if let w = options.world { renderer.world = w }
        var views = renderer.world == .glassWood ? ["gw-arrival", "gw-overview", "gw-court", "gw-altar"] : (renderer.world == .tideArchive ? ["ta-quay", "ta-terraces", "ta-gallery", "ta-dome"] : ["dock", "overview", "shore", "summit"])
        if let v = options.viewName { views = [v] }                // --bench N --view NAME: just that view (F02 T66.13: the cost near trees)
        let glassTris = renderer.scene.items.filter { $0.refractive }.reduce(0) { $0 + $1.mesh.indexCount / 3 }
        let allTris = renderer.scene.items.reduce(0) { $0 + $1.mesh.indexCount / 3 }
        print("triangles: glass \(glassTris), scene total \(allTris)")
        renderer.passTimer = PassTimer(device: renderer.device)
        if renderer.passTimer == nil { print("pass timer: this device cannot sample GPU counters at stage boundaries; no per-pass table") }
        defer { renderer.passTimer = nil }
        for name in views {
            let camera = Viewpoints.named(name) ?? Screenshot.viewCamera(name, renderer: renderer)
            var times: [Double] = []
            var passOrder: [String] = [], passSums: [String: Double] = [:], passFrames = 0
            var cpuEncode: [Double] = []
            for i in 0..<((options.benchFrames ?? 60) + 5) {
                guard let cb = renderer.queue.makeCommandBuffer() else { throw Failure.texture }
                let encodeStart = DispatchTime.now().uptimeNanoseconds
                renderer.encode(commandBuffer: cb, target: target, camera: camera)
                if i >= 5 { cpuEncode.append(Double(DispatchTime.now().uptimeNanoseconds - encodeStart) / 1e6) }          // G10.3.4: CPU time to encode the frame
                cb.commit(); cb.waitUntilCompleted()
                if i >= 5 { times.append((cb.gpuEndTime - cb.gpuStartTime) * 1000) }      // skip warm-up frames
                if let t = renderer.passTimer, i >= 5 {
                    t.drain(cb)
                    passFrames += 1
                    for (pass, ms) in t.latest { if passSums[pass] == nil { passOrder.append(pass) }; passSums[pass, default: 0] += ms }
                }
            }
            times.sort()
            let avg = times.reduce(0, +) / Double(times.count)
            print(String(format: "  %-9@ avg %.2f ms (%.0f fps)  median %.2f  worst %.2f  draws opaque %d shadow %d",
                         name as NSString, avg, 1000 / avg, times[times.count / 2], times.last!, renderer.lastOpaqueDraws, renderer.lastShadowDraws))
            print(String(format: "      cpu encode %.3f ms (mean), %.3f ms (worst)", cpuEncode.reduce(0, +) / Double(max(cpuEncode.count, 1)), cpuEncode.max() ?? 0))
            if passFrames > 0 {
                var total = 0.0
                for pass in passOrder { let ms = passSums[pass]! / Double(passFrames); total += ms; print(String(format: "      %-22@ %6.3f ms  %4.1f %%", pass as NSString, ms, 100 * ms / avg)) }
                print(String(format: "      %-22@ %6.3f ms  of the frame's %.2f ms (%+.1f %%; each pass is charged from the previous pass's end, so the sum is the GPU busy time)", "sum of passes" as NSString, total, avg, 100 * (total - avg) / avg))
            }
        }
    }

    /// Writes the sky LUT (tonemapped) so the atmosphere can be inspected on its own.
    static func dumpSkyLUT(renderer: Renderer, to path: String) throws {
        let (w, h) = Renderer.skyLUTSize
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget]
        desc.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: desc),
              let cb = renderer.queue.makeCommandBuffer() else { throw Failure.texture }
        renderer.bakeSkyLUTForDebug(commandBuffer: cb, camera: Camera(position: .zero, yaw: 0, pitch: 0))
        renderer.encodeDebugView(commandBuffer: cb, source: renderer.skyLUT, target: target)
        cb.commit(); cb.waitUntilCompleted()
        if let err = cb.error { throw Failure.write("GPU error: \(err)") }
        try writePNG(texture: target, to: path)
    }

    static func capture(renderer: Renderer, options: LaunchOptions, to path: String) throws {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.outputFormat, width: options.width, height: options.height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared  // Apple silicon: unified memory, CPU can read it directly
        guard let target = renderer.device.makeTexture(descriptor: desc) else { throw Failure.texture }

        renderer.fixedTime = options.clock
        renderer.autoExposure = options.autoExposure
        if let w = options.world { renderer.world = w } else if options.viewName?.hasPrefix("gw-") == true { renderer.world = .glassWood } else if options.viewName?.hasPrefix("ta-") == true { renderer.world = .tideArchive }
        if let g = applyState(options.state, scenes: renderer.scenes) { renderer.mistScale = g.mistScale; renderer.beamIntensity = g.beamAmount }
        if renderer.world == .tideArchive {                                              // S04.3: the Archive's moving items for a still frame (the game drives them in play)
            let sc = renderer.scene
            if options.gatesOpen { for k in 0..<3 { sc.update(ArchiveProps.gateName(k)) { $0.uniforms.emissive = SIMD4(0.55, 0.85, 1.0, 1.4) } } }
            for step in 0..<40 { ArchiveProps.update(sc, time: options.clock + Float(step) * 0.1, ringAngle: options.ringDegrees.map { $0 * Float.pi / 180 }, tableau: options.tableau) }
        }
        let camera = options.camera ?? Self.viewCamera(options.viewName, renderer: renderer)

        // Several frames so time-dependent or temporally accumulated effects settle.
        for _ in 0..<options.frames {
            guard let cb = renderer.queue.makeCommandBuffer() else { throw Failure.texture }
            renderer.encode(commandBuffer: cb, target: target, camera: camera)
            cb.commit()
            cb.waitUntilCompleted()
            if let err = cb.error { throw Failure.write("GPU error: \(err)") }
        }

        try writePNG(texture: target, to: path)
    }

    /// The camera for a named view: the terrain-dependent ones first, then the fixed ones, then the overview.
    static func viewCamera(_ name: String?, renderer: Renderer) -> Camera {
        let terrain: Terrain = renderer.scene.terrain
        guard let name else { return Viewpoints.named("overview")! }
        switch name {
        case "tree-close": return Viewpoints.treeClose(terrain: terrain)
        case "page-close": return Viewpoints.pageClose(scene: renderer.scene)
        case "rock-close": return Viewpoints.rockClose(scene: renderer.scene)
        case "lantern-close": return Viewpoints.lanternClose(scene: renderer.scene)
        case "pillar-close", "pillar-far": return Viewpoints.pillarClose(terrain: terrain, far: name == "pillar-far")
        default: break
        }
        if let c = Viewpoints.treeNeedle(terrain: terrain, name: name) { return c }
        if let c = Viewpoints.treeTrunk(terrain: terrain, name: name, sun: Renderer.sunDirection(elevationDeg: renderer.options.sunElevation, azimuthDeg: renderer.options.sunAzimuth)) { return c }
        if let c = Viewpoints.poolView(terrain: terrain, name: name) { return c }
        if let c = Viewpoints.pageView(scene: renderer.scene, name: name) { return c }
        if let c = Viewpoints.treeBase(terrain: terrain, name: name) { return c }
        if let c = Viewpoints.ground(name, terrain: renderer.scenes[.varrow]!.terrain) { return c }
        return Viewpoints.named(name) ?? Viewpoints.named("overview")!
    }

    static func writePNG(texture: MTLTexture, to path: String) throws {
        let width = texture.width, height = texture.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        // BGRA bytes, already sRGB-encoded by the _srgb format.
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info,
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent)
        else { throw Failure.image }

        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.write(path) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.write(path) }
    }
}
