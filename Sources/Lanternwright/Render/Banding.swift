import Foundation
import Metal
import simd

/// `--banding` (G10.0.3): how many distinct 8-bit levels does a smooth sky gradient actually use in the final image, and how big is the largest step? A gradient that is
/// smooth in the 16-bit HDR buffer is quantised to 8 bits at the very end, and a slow one then shows as bands: runs of identical values with a step of one between them.
/// For each sky view this renders the real frame (TAA on, as in the game), takes 32 columns of the sky (pixels the renderer says are infinitely far, away from the sun's disc
/// and clouds, where the neighbouring rows differ by at most 3/255) and reports, per channel, the distinct levels used along a column, the largest step between adjacent rows,
/// and the longest run of identical rows. The baseline for G10.2.3 (output dither): that task must raise the levels and shorten the runs without visible grain.
enum Banding {
    struct View { let name: String; let world: WorldKind; let camera: Camera; let sun: SIMD2<Float>? }
    static func views() -> [View] {
        // Looking along the horizon and up into the sky, away from the sun and toward it (the default sun is at azimuth 250 degrees, 8 degrees high), and the Glass Wood's night sky.
        let eye = SIMD3<Float>(0, 3, 0)
        return [View(name: "dusk-away", world: .varrow, camera: Camera(position: eye, yaw: 1.2, pitch: 0.55), sun: nil),
                View(name: "dusk-toward", world: .varrow, camera: Camera(position: eye, yaw: -1.9, pitch: 0.55), sun: nil),
                View(name: "dusk-high", world: .varrow, camera: Camera(position: eye, yaw: 1.2, pitch: 1.0), sun: nil),
                View(name: "glass-night", world: .glassWood, camera: Camera(position: eye + SIMD3(0, 0, 330), yaw: 0, pitch: 0.55), sun: nil)]
    }

    struct Channel { var levels: Int; var maxStep: Int; var longestRun: Int; var zeroShare: Float }
    struct Result { var view: String; var columns: Int; var rows: Int; var channels: [String: Channel] }

    static func measure(renderer: Renderer, view: View, width: Int, height: Int) throws -> Result {
        renderer.world = view.world
        renderer.fixedTime = 12
        let savedAuto = renderer.autoExposure; renderer.autoExposure = false
        let savedTAA = renderer.taaEnabled; renderer.taaEnabled = true
        defer { renderer.autoExposure = savedAuto; renderer.taaEnabled = savedTAA }
        renderer.resetTAA(); renderer.taaFrameIndex = 0
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: desc) else { throw Screenshot.Failure.texture }
        for _ in 0..<12 {
            guard let cb = renderer.queue.makeCommandBuffer() else { throw Screenshot.Failure.texture }
            renderer.encode(commandBuffer: cb, target: target, camera: view.camera)
            cb.commit(); cb.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&px, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let dist = Parallax.readDistance(renderer: renderer, width: width, height: height)
        // bgra: channel 0 is blue, 1 green, 2 red.
        let names = ["blue", "green", "red"]
        var levels = [Set<Int>](repeating: [], count: 3), maxStep = [0, 0, 0], longest = [0, 0, 0], same = [0, 0, 0], pairs = 0, columns = 0, rows = 0
        for x in stride(from: width / 8, to: width - width / 8, by: max(1, width / 40)) {
            // The longest stretch of rows, from the top of the frame down, that is all sky and smooth.
            var run: [Int] = []
            for y in 0..<height {
                guard dist[y * width + x] > 1e4 else { if run.count > 40 { break } else { run = []; continue } }
                if let last = run.last {
                    let step = (0..<3).map { abs(Int(px[(y * width + x) * 4 + $0]) - Int(px[(last * width + x) * 4 + $0])) }.max()!
                    if step > 3 { if run.count > 40 { break } else { run = [y]; continue } }
                }
                run.append(y)
            }
            guard run.count > 40 else { continue }
            columns += 1; rows = max(rows, run.count)
            for c in 0..<3 {
                var current = 1
                for (j, y) in run.enumerated() {
                    let v = Int(px[(y * width + x) * 4 + c]); levels[c].insert(v)
                    if j > 0 {
                        let d = abs(v - Int(px[(run[j - 1] * width + x) * 4 + c]))
                        maxStep[c] = max(maxStep[c], d)
                        if d == 0 { current += 1; same[c] += 1 } else { current = 1 }
                        longest[c] = max(longest[c], current)
                        if c == 0 { pairs += 1 }
                    }
                }
            }
        }
        var ch: [String: Channel] = [:]
        for c in 0..<3 { ch[names[c]] = Channel(levels: levels[c].count, maxStep: maxStep[c], longestRun: longest[c], zeroShare: pairs > 0 ? Float(same[c]) / Float(pairs) : 0) }
        return Result(view: view.name, columns: columns, rows: rows, channels: ch)
    }

    static func run(renderer: Renderer, width: Int, height: Int) throws -> String {
        var s = "banding probe (G10.0.3): the final 8-bit image of smooth sky strips, \(width)x\(height), TAA on, 32 columns per view. levels = distinct values used by a channel in the strip; max step = the biggest change\n"
        s += "between adjacent rows; longest run = most identical rows in a row; flat = share of adjacent rows with no change at all (a smooth ramp that uses every level has flat close to 0 where the gradient is\n"
        s += "steep, and runs of 1 to 4 where it is shallow; bands are long runs). Dithering (G10.2.3) should raise the levels and cut the runs.\n"
        s += "A strip is cut where adjacent rows differ by more than 3, so a max step is at most 3 by construction; 2 or 3 inside a smooth strip is itself a band edge.\n\n"
        for v in views() {
            let r = try measure(renderer: renderer, view: v, width: width, height: height)
            s += "\(r.view): \(r.columns) columns of up to \(r.rows) sky rows\n"
            for c in ["red", "green", "blue"] { let x = r.channels[c]!; s += String(format: "    %-5@ levels %3d   max step %d   longest run %3d rows   flat %4.1f %%\n", c as NSString, x.levels, x.maxStep, x.longestRun, x.zeroShare * 100) }
        }
        return s
    }
}
