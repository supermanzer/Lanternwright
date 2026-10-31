import AppKit
import Metal

let options = LaunchOptions.parse(CommandLine.arguments)

if options.showFeedbackDir { print(FeedbackStore.directory.path); exit(0) }
if options.showFeedback { print(FeedbackStore.formatted(FeedbackStore.loadAll())); exit(0) }
// --dump-shaders <path>: the Metal source exactly as the game compiles it (ShaderLibrary.make joins the same list with a newline); no device, no window, no output.
if let path = options.dumpShadersPath {
    do { try ShaderLibrary.sources.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}
GPUTypes.validateLayouts()

guard let device = MTLCreateSystemDefaultDevice() else {
    FileHandle.standardError.write(Data("error: no Metal device\n".utf8))
    exit(1)
}

if let test = options.selftest {
    exit(SelfTest.run(test, device: device) ? 0 : 1)
}

if let base = options.dumpOverlayBase {
    MainActor.assumeIsolated {
        do { try OverlayDump.write(base: base); print("wrote \(base)-*.png"); exit(0) }
        catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
    }
}

if options.benchFrames != nil {
    let renderer = Renderer(device: device, options: options)
    do { try Screenshot.bench(renderer: renderer, options: options); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

Scene.hardLOD = options.hardLOD
if options.auditSlopes {
    let renderer = Renderer(device: device, options: options)
    print(SlopeAudit.report(terrain: renderer.scenes[.varrow]!.terrain)); exit(0)
}

if let n = options.shimmer {
    let renderer = Renderer(device: device, options: options)
    do { _ = try Shimmer.run(renderer: renderer, width: options.width, height: options.height, frames: n); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if let n = options.shimmerLayers {
    let renderer = Renderer(device: device, options: options)
    do { print(Shimmer.report(try Shimmer.attribute(renderer: renderer, width: options.width, height: options.height, frames: n), width: options.width, height: options.height, frames: n)); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if options.banding {
    let renderer = Renderer(device: device, options: options)
    do { print(try Banding.run(renderer: renderer, width: options.width, height: options.height)); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if options.parallaxSea {
    let renderer = Renderer(device: device, options: options)
    do {
        let r = try Parallax.seaSteps(renderer: renderer)
        let snapSet = Set(r.snaps)
        let atSnap = r.snaps.compactMap { $0 < r.changes.count ? r.changes[$0] : nil }, others = r.changes.enumerated().filter { !snapSet.contains($0.offset) }.map(\.element)
        func mean(_ v: [Float]) -> Float { v.isEmpty ? 0 : v.reduce(0, +) / Float(v.count) }
        print(String(format: "sea: %d steps, %d disc snaps at steps %@. Far-water change per step (mean abs luma of the band): at the snap steps %.3f (max %.3f), other steps %.3f (max %.3f)",
                     r.changes.count, r.snaps.count, "\(r.snaps)" as NSString, mean(atSnap), atSnap.max() ?? 0, mean(others), others.max() ?? 0))
        print("per step: " + r.changes.map { String(format: "%.2f", $0) }.joined(separator: " "))
        exit(0)
    } catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if options.parallax {
    let renderer = Renderer(device: device, options: options)
    do { try Parallax.run(renderer: renderer, width: options.width, height: options.height); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if options.freeRoam { Player.guidance = .free }
if options.navAudit { exit(NavigationAudit.main(device: device, out: options.navAuditOut) ? 0 : 1) }

if let path = options.navOverlayPath {
    do { try NavigationOverlay.write(to: path, device: device); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if options.listPages {
    let renderer = Renderer(device: device, options: options)
    func f(_ p: SIMD3<Float>) -> String { String(format: "(%.1f, %.1f, %.1f)", p.x, p.y, p.z) }
    let how = ["on the dock's boards, 8.5 m from the landward end, toward the rail", "by the tide stone, off the way in, a pebble on its corner", "by the wind stone, blown into the grass and leaning",
               "beside the lighthouse's door steps, on the open ground, against the slope", "at the Glass Wood arrival pad",
               "by the receiver orb, caught at an angle (appears when the mirror court is solved)", "at the chime ring (appears when the chimes are solved)",
               "on the altar dais' top step (appears when both are solved)", "on the dock's boards at the seaward end, on the left-hand side, away from page 1"]
    for n in StoryPages.all.map(\.id) {
        let onVarrow = StoryPages.varrowIDs.contains(n)
        let sc = renderer.scenes[onVarrow ? .varrow : .glassWood]!
        let lie = onVarrow ? PuzzleProps.pageLie(n, scene: sc) : GlassPuzzleProps.pageLie(n, scene: sc)
        print("page \(n)  \(onVarrow ? "Varrow" : "Glass Wood")  sheet at \(f(lie.origin))  \(how[n - 1])")
    }
    exit(0)
}

if options.auditProps {
    let renderer = Renderer(device: device, options: options)
    do { try PropAudit.run(renderer: renderer, out: options.auditPropsOut); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if let which = options.approachTarget, let out = options.approachOut {
    let renderer = Renderer(device: device, options: options)
    do { try Approach.main(renderer: renderer, which: which, out: out, width: options.width, height: options.height, range: options.approachRange); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if let path = options.dumpAudioPath {
    do { try AudioDump.write(to: path); print("wrote \(path)"); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if let path = options.dumpLUTPath {
    let renderer = Renderer(device: device, options: options)
    do { try Screenshot.dumpSkyLUT(renderer: renderer, to: path); print("wrote \(path)"); exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}

if let path = options.screenshotPath {
    // Headless path: same renderer, offscreen target, no window or NSApplication.
    let renderer = Renderer(device: device, options: options)
    do {
        try Screenshot.capture(renderer: renderer, options: options, to: path)
        print("wrote \(path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(device: device, options: options)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
