import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Headless capture: renders N frames offscreen through the normal pipeline and writes a PNG.
/// This is how agents "see" the game without opening a window.
enum Screenshot {
    enum Failure: Error { case texture, image, write(String) }

    /// `--state`: put the world into a puzzle state so it can be photographed.
    static func applyState(_ name: String?, scene: Scene) {
        guard let name else { return }
        let g = Game(scene: scene)
        switch name {
        case "solved": g.puzzle.forceSolved()
        case "tide": g.puzzle.strike(.tide)
        case "tidewind": g.puzzle.strike(.tide); g.simulate(seconds: 0.7); g.puzzle.strike(.wind)
        default: FileHandle.standardError.write(Data("unknown --state \(name)\n".utf8))
        }
        g.simulate(seconds: 1.5)
        _ = g.drainEvents()
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
        for name in ["dock", "overview", "shore", "summit"] {
            let camera = Viewpoints.named(name)!
            var times: [Double] = []
            for i in 0..<((options.benchFrames ?? 60) + 5) {
                guard let cb = renderer.queue.makeCommandBuffer() else { throw Failure.texture }
                renderer.encode(commandBuffer: cb, target: target, camera: camera)
                cb.commit(); cb.waitUntilCompleted()
                if i >= 5 { times.append((cb.gpuEndTime - cb.gpuStartTime) * 1000) }      // skip warm-up frames
            }
            times.sort()
            let avg = times.reduce(0, +) / Double(times.count)
            print(String(format: "  %-9@ avg %.2f ms (%.0f fps)  median %.2f  worst %.2f  draws opaque %d shadow %d",
                         name as NSString, avg, 1000 / avg, times[times.count / 2], times.last!, renderer.lastOpaqueDraws, renderer.lastShadowDraws))
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

        renderer.fixedTime = 12
        applyState(options.state, scene: renderer.scene)
        let camera = options.camera
            ?? options.viewName.flatMap(Viewpoints.named)
            ?? Viewpoints.named("overview")!

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
