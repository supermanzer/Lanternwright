import Foundation
import Metal
import simd

/// `--banding` (G10.0.3): how much does a smooth sky gradient band in the final image: how long are the runs of identical values, and how many levels does it use? A gradient that is
/// smooth in the 16-bit HDR buffer is quantised to 8 bits at the very end, and a slow one then shows as bands: runs of identical values with a step of one between them.
/// For each sky view this renders the real frame (TAA on, as in the game) and takes up to 40 columns (every width/40 pixels across the middle three quarters): in each, the LONGEST stretch
/// of rows that the renderer says are infinitely far (sky) and smooth (adjacent rows differ by at most 3/255; clouds and the sun's glow are included wherever they are that smooth, so a strip that
/// crosses cloud body is textured by the cloud). Per channel it reports the HEADLINE numbers for G10.2.3, longest run of identical rows and the share of adjacent rows with no change at all
/// (flat), plus the histogram of steps (0, 1, 2, 3) and the fill: distinct levels used divided by the levels the strip spans (max - min + 1), averaged over the strips. A banded gradient has long runs,
/// a high flat share and steps of 0 and 1 only; dither (G10.2.3) must cut the runs and flat share and put weight on steps of 1 and 2 without visible grain.
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

    struct Channel { var fill: Float; var longestRun: Int; var flat: Float; var steps: [Float] }
    struct Result { var view: String; var columns: Int; var rows: Int; var channels: [String: Channel] }

    /// The numbers for one channel from its strips (each strip the channel's values down a run of sky rows). Pure, so a test can feed it a synthetic ramp.
    static func summarize(_ strips: [[Int]]) -> Channel {
        var hist = [Int](repeating: 0, count: 4), pairs = 0, longest = 1, fills: [Float] = []
        for v in strips where v.count > 1 {
            var run = 1
            for j in 1..<v.count {
                let d = min(abs(v[j] - v[j - 1]), 3); hist[d] += 1; pairs += 1
                if d == 0 { run += 1; longest = max(longest, run) } else { run = 1 }
            }
            fills.append(Float(Set(v).count) / Float(v.max()! - v.min()! + 1))
        }
        let n = Float(max(pairs, 1))
        return Channel(fill: fills.isEmpty ? 0 : fills.reduce(0, +) / Float(fills.count), longestRun: longest, flat: Float(hist[0]) / n, steps: hist.map { Float($0) / n })
    }

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
        // bgra: byte 0 is blue, 1 green, 2 red.
        let names = ["blue", "green", "red"]
        var strips = [[[Int]]](repeating: [], count: 3), columns = 0, rows = 0
        // A strip is cut where any channel steps by more than 3: that is the edge of a cloud or the sun's glow, not a gradient. With +-1 LSB dither the steps stay within 3, so the cut does not touch it.
        let maxStep = 3
        for x in stride(from: width / 8, to: width - width / 8, by: max(1, width / 40)) {
            var best: [Int] = [], run: [Int] = []
            func close() { if run.count > best.count { best = run }; run = [] }
            for y in 0..<height {
                guard dist[y * width + x] > 1e4 else { close(); continue }
                if let last = run.last, (0..<3).contains(where: { abs(Int(px[(y * width + x) * 4 + $0]) - Int(px[(last * width + x) * 4 + $0])) > maxStep }) { close() }
                run.append(y)
            }
            close()
            guard best.count > 40 else { continue }
            columns += 1; rows = max(rows, best.count)
            for c in 0..<3 { strips[c].append(best.map { Int(px[($0 * width + x) * 4 + c]) }) }
        }
        var ch: [String: Channel] = [:]
        for c in 0..<3 { ch[names[c]] = summarize(strips[c]) }
        return Result(view: view.name, columns: columns, rows: rows, channels: ch)
    }

    static func run(renderer: Renderer, width: Int, height: Int) throws -> String {
        var s = "banding probe (G10.0.3): the final 8-bit image of smooth sky strips, \(width)x\(height), TAA on, up to 40 columns per view, the longest smooth sky strip in each.\n"
        s += "HEADLINE for G10.2.3: longest run (most identical rows in a row) and flat (share of adjacent rows with no change at all). Banding = long runs and a high flat share; dither must cut both.\n"
        s += "steps = share of adjacent rows whose largest channel step is 0 / 1 / 2 / 3+ (strips are cut at steps over 3). fill = distinct levels used / levels spanned by the strip (max - min + 1), mean over strips:\n"
        s += "a banded ramp is already near 1 (it visits every level), so fill is context, not the target. Clouds and the sun's glow are included wherever they are smooth enough.\n\n"
        for v in views() {
            let r = try measure(renderer: renderer, view: v, width: width, height: height)
            s += "\(r.view): \(r.columns) columns, strips up to \(r.rows) rows\n"
            for c in ["red", "green", "blue"] {
                let x = r.channels[c]!
                s += String(format: "    %-5@ longest run %3d rows   flat %4.1f %%   steps 0/1/2/3+ %4.1f / %4.1f / %4.1f / %4.1f %%   fill %.2f\n", c as NSString, x.longestRun, x.flat * 100, x.steps[0] * 100, x.steps[1] * 100, x.steps[2] * 100, x.steps[3] * 100, x.fill)
            }
        }
        return s
    }
}
