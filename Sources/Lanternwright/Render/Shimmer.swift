import Foundation
import Metal
import simd

/// `--shimmer`: how much do fine details crawl when the camera moves (F02 R1, user note #23)? The world here is static (the clock is fixed), so when the camera moves a
/// pixel's colour should change ONLY because the content slid across it. For each pair of consecutive frames this reprojects frame k-1 onto frame k with the renderer's own
/// depth and the known camera motion, and measures how much the pixels still differ: what motion cannot explain is crawl (aliasing flicker, a speck that appears and vanishes).
/// Blur would also lower that number, so each run also reports how much fine detail survives (mean absolute Laplacian) and the score only counts if detail is kept.
/// All on 0...255 luma of what ends up on screen; depth edges, sky and pixels that left the frame are skipped. Lower is steadier.
enum Shimmer {
    struct Scene { let name: String; let view: String }
    static let scenes = [Scene(name: "turf", view: "ground-grass-1m"), Scene(name: "sand", view: "ground-sand-1m"), Scene(name: "dock", view: "dock-top"),
                         Scene(name: "cobbles", view: "lantern-close"), Scene(name: "masonry", view: "lh-base"), Scene(name: "grass", view: "ground-grass-5m")]
    enum Motion: String { case pan, walk }

    struct Run { var flicker: Float; var detail: Float }
    /// `detail` of each mode is the mean absolute Laplacian of the middle frame; `ideal` the same for that frame rendered at 3x3 supersampling and box-filtered down.
    struct Result { var scene: String; var motion: Motion; var off: Run; var on: Run; var ideal: Float
        var reduction: Float { off.flicker > 0 ? 1 - on.flicker / off.flicker : 0 }
        var detailOn: Float { ideal > 0 ? on.detail / ideal : 1 }
        var detailOff: Float { ideal > 0 ? off.detail / ideal : 1 } }

    static func luma(_ tex: MTLTexture) -> [Float] {
        let w = tex.width, h = tex.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var out = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { out[i] = 0.114 * Float(bytes[i * 4]) + 0.587 * Float(bytes[i * 4 + 1]) + 0.299 * Float(bytes[i * 4 + 2]) }
        return out
    }

    static func camera(base: Camera, motion: Motion, frame k: Int) -> Camera {
        var c = base
        switch motion {
        case .pan: c.yaw += 0.0022 * Float(k)
        case .walk: c.position += simd_normalize(SIMD3(base.forward.x, 0, base.forward.z)) * (0.028 * Float(k))
        }
        return c
    }

    /// Mean absolute Laplacian over the frame (the amount of fine detail).
    static func detail(_ y: [Float], width: Int, height: Int) -> Float {
        var sum: Double = 0, n = 0
        for yy in stride(from: 2, to: height - 2, by: 2) { for xx in stride(from: 2, to: width - 2, by: 2) {
            let c = y[yy * width + xx]
            sum += Double(abs(4 * c - y[yy * width + xx - 1] - y[yy * width + xx + 1] - y[(yy - 1) * width + xx] - y[(yy + 1) * width + xx])); n += 1
        } }
        return Float(sum / Double(max(n, 1)))
    }

    /// Mean squared difference between each frame and the previous one reprojected onto it, and the mean absolute Laplacian (the amount of fine detail).
    static func score(frames: [(cam: Camera, y: [Float], dist: [Float])], width: Int, height: Int) -> Run {
        let aspect = Float(width) / Float(height)
        var sum: Double = 0, n = 0
        for k in 1..<frames.count {
            let a = frames[k - 1], b = frames[k]
            let ty = tan(b.cam.fovY / 2), tx = ty * aspect
            let bb = Parallax.basis(b.cam), ba = Parallax.basis(a.cam)
            for y in stride(from: 3, to: height - 3, by: 2) {
                for x in stride(from: 3, to: width - 3, by: 2) {
                    let d = b.dist[y * width + x]
                    guard d.isFinite, d > 0.6, d < 400 else { continue }
                    var lo = Float.infinity, hi: Float = 0
                    for dy in -2...2 { for dx in -2...2 { let v = b.dist[(y + dy) * width + x + dx]; lo = min(lo, v); hi = max(hi, v) } }
                    if hi - lo > 0.02 * hi { continue }                                    // not a depth edge
                    let nx = (Float(x) + 0.5) / Float(width) * 2 - 1, ny = 1 - (Float(y) + 0.5) / Float(height) * 2
                    let w = b.cam.position + simd_normalize(bb.f + bb.r * (nx * tx) + bb.u * (ny * ty)) * d
                    let rel = w - a.cam.position
                    let zc = simd_dot(rel, ba.f)
                    guard zc > 0.3 else { continue }
                    let px = (simd_dot(rel, ba.r) / (zc * tx) * 0.5 + 0.5) * Float(width) - 0.5, py = (1 - (simd_dot(rel, ba.u) / (zc * ty) * 0.5 + 0.5)) * Float(height) - 0.5
                    let ix = Int(floor(px)), iy = Int(floor(py))
                    guard ix >= 1, iy >= 1, ix < width - 2, iy < height - 2 else { continue }
                    let fx = px - Float(ix), fy = py - Float(iy)
                    let p00 = a.y[iy * width + ix], p10 = a.y[iy * width + ix + 1], p01 = a.y[(iy + 1) * width + ix], p11 = a.y[(iy + 1) * width + ix + 1]
                    let prev = (p00 * (1 - fx) + p10 * fx) * (1 - fy) + (p01 * (1 - fx) + p11 * fx) * fy
                    let diff = b.y[y * width + x] - prev
                    sum += Double(diff * diff); n += 1
                }
            }
        }
        return Run(flicker: n > 0 ? Float(sum / Double(n)) : 0, detail: detail(frames[frames.count / 2].y, width: width, height: height))
    }

    static func measure(renderer: Renderer, scene: Scene, motion: Motion, width: Int, height: Int, frames: Int, warmup: Int = 12) throws -> Result {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: desc) else { throw Screenshot.Failure.texture }
        renderer.fixedTime = 12
        let base = Screenshot.viewCamera(scene.view, renderer: renderer)
        let saved = renderer.taaEnabled
        func sequence(taa: Bool) throws -> Run {
            renderer.taaEnabled = taa; renderer.resetTAA()
            var out: [(cam: Camera, y: [Float], dist: [Float])] = []
            for k in -warmup..<frames {
                let cam = camera(base: base, motion: motion, frame: k)
                guard let cb = renderer.queue.makeCommandBuffer() else { throw Screenshot.Failure.texture }
                renderer.encode(commandBuffer: cb, target: target, camera: cam)
                cb.commit(); cb.waitUntilCompleted()
                if k >= 0 { out.append((cam, luma(target), Parallax.readDistance(renderer: renderer, width: width, height: height))) }
            }
            return score(frames: out, width: width, height: height)
        }
        let off = try sequence(taa: false), on = try sequence(taa: true)
        // The ideal: the middle frame at 3x3 supersampling, box-filtered down, with no temporal filter.
        renderer.taaEnabled = false
        let bd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width * 3, height: height * 3, mipmapped: false)
        bd.usage = [.renderTarget, .shaderRead]; bd.storageMode = .shared
        guard let big = renderer.device.makeTexture(descriptor: bd), let cb = renderer.queue.makeCommandBuffer() else { throw Screenshot.Failure.texture }
        renderer.encode(commandBuffer: cb, target: big, camera: camera(base: base, motion: motion, frame: frames / 2))
        cb.commit(); cb.waitUntilCompleted()
        let yb = luma(big)
        var ys = [Float](repeating: 0, count: width * height)
        for yy in 0..<height { for xx in 0..<width {
            var a: Float = 0
            for dy in 0..<3 { for dx in 0..<3 { a += yb[(yy * 3 + dy) * width * 3 + xx * 3 + dx] } }
            ys[yy * width + xx] = a / 9
        } }
        renderer.taaEnabled = saved
        return Result(scene: scene.name, motion: motion, off: off, on: on, ideal: detail(ys, width: width, height: height))
    }

    static func run(renderer: Renderer, width: Int, height: Int, frames: Int, only: [String]? = nil) throws -> [Result] {
        var results: [Result] = []
        print("shimmer: motion-compensated frame-to-frame change of a static world (0-255 luma squared; lower is steadier) and the fine detail kept, \(frames) frames at \(width)x\(height)")
        for sc in scenes where only == nil || only!.contains(sc.name) {
            for m in [Motion.pan, .walk] {
                let r = try measure(renderer: renderer, scene: sc, motion: m, width: width, height: height, frames: frames)
                results.append(r)
                print(String(format: "  %-8@ %-5@ crawl: TAA off %8.3f  on %8.3f  (%5.1f %% lower)   fine detail vs the ideal image: off %5.1f %%, on %5.1f %%", sc.name as NSString, m.rawValue as NSString, r.off.flicker, r.on.flicker, r.reduction * 100, r.detailOff * 100, r.detailOn * 100))
            }
        }
        let off = results.map(\.off.flicker).reduce(0, +), on = results.map(\.on.flicker).reduce(0, +)
        let ideal = results.map(\.ideal).reduce(0, +)
        print(String(format: "  all      total crawl: TAA off %8.3f  on %8.3f  (%5.1f %% lower)   fine detail vs the ideal image: off %5.1f %%, on %5.1f %%", off, on, (1 - on / max(off, 1e-9)) * 100,
                     100 * results.map(\.off.detail).reduce(0, +) / max(ideal, 1e-9), 100 * results.map(\.on.detail).reduce(0, +) / max(ideal, 1e-9)))
        return results
    }
}
