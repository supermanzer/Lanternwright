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

if let which = options.approachTarget, let out = options.approachOut {
    let renderer = Renderer(device: device, options: options)
    do { try Approach.main(renderer: renderer, which: which, out: out, width: options.width, height: options.height); exit(0) }
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
