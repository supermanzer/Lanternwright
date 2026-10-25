import AppKit
import Metal

let options = LaunchOptions.parse(CommandLine.arguments)

if options.showFeedbackDir { print(FeedbackStore.directory.path); exit(0) }
if options.showFeedback { print(FeedbackStore.formatted(FeedbackStore.loadAll())); exit(0) }
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

if options.listPages {
    let renderer = Renderer(device: device, options: options)
    let t = renderer.scenes[.varrow]!.terrain!
    func f(_ p: SIMD3<Float>) -> String { String(format: "(%.1f, %.1f, %.1f)", p.x, p.y, p.z) }
    let how = ["on the dock, 8.5 m from the landward end, left of the path", "by the tide stone, beside the way in", "by the wind stone, beside the way in",
               "beside the lighthouse's door steps, on the open ground east of them", "at the Glass Wood arrival pad (announced on arrival)",
               "by the receiver orb (appears when the mirror court is solved)", "at the chime ring (appears when the chimes are solved)",
               "at the altar (appears when both are solved)"]
    for n in 1...8 {
        let base = n <= 4 ? PuzzleProps.pageBase(n, terrain: t) : GlassPuzzleProps.pageBase(n)
        print("page \(n)  \(n <= 4 ? "Varrow" : "Glass Wood")  lectern foot \(f(base))  \(how[n - 1])")
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
