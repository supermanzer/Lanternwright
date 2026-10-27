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

    struct Run { var flicker: Float; var detail: Float; var sum: Double = 0; var n = 0 }
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
    static func score(frames: [(cam: Camera, y: [Float], dist: [Float])], width: Int, height: Int, include: ((_ frame: Int, _ pixel: Int) -> Bool)? = nil) -> Run {
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
                    if let include, !include(k, y * width + x) { continue }
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
        return Run(flicker: n > 0 ? Float(sum / Double(n)) : 0, detail: detail(frames[frames.count / 2].y, width: width, height: height), sum: sum, n: n)
    }

    static func measure(renderer: Renderer, scene: Scene, motion: Motion, width: Int, height: Int, frames: Int, warmup: Int = 12) throws -> Result {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: desc) else { throw Screenshot.Failure.texture }
        renderer.fixedTime = 12
        let savedAuto = renderer.autoExposure; renderer.autoExposure = false          // G10.0.2: the asynchronous eye-adaptation readback made repeat runs differ
        defer { renderer.autoExposure = savedAuto }
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

// MARK: - G10.0.2 attribution in a moving world

extension Shimmer {
    /// A walk through a place where the layers of the frame are all present. `world` is the world it lives in.
    struct MovingScene { let name: String; let view: String; let world: WorldKind }
    static let movingScenes = [MovingScene(name: "grove", view: "ground-grass-5m", world: .varrow), MovingScene(name: "woods", view: "tree-at-14", world: .varrow),
                               MovingScene(name: "shore", view: "shore", world: .varrow), MovingScene(name: "dock", view: "dock", world: .varrow),
                               MovingScene(name: "crystal", view: "gw-court", world: .glassWood)]
    /// The walk is 0.028 m a frame; at the player's walking pace (2.3 m/s) that is this many seconds of game clock a frame, so wind and walk keep their real ratio.
    static let clockStep: Float = 0.028 / 2.3

    typealias Frames = [(cam: Camera, y: [Float], dist: [Float])]
    /// One walk of `frames` frames with TAA on (as in the game), the clock advancing (`moving`) or frozen, and the given layers off. Every walk starts from the same TAA state and
    /// jitter, so two walks differ only where a layer made them differ (the GPU is deterministic: identical pixels come out bit-identical).
    static func walk(renderer: Renderer, scene: MovingScene, off: Set<RenderLayer>, moving: Bool, width: Int, height: Int, frames: Int, target: MTLTexture, warmup: Int = 12) throws -> Frames {
        renderer.world = scene.world
        let base = Screenshot.viewCamera(scene.view, renderer: renderer)
        let savedHidden = renderer.scene.hiddenFlags
        RenderLayer.off = off
        defer { RenderLayer.off = []; renderer.scene.hiddenFlags = savedHidden }
        renderer.taaEnabled = true; renderer.resetTAA(); renderer.taaFrameIndex = 0
        let savedAuto = renderer.autoExposure; renderer.autoExposure = false          // the eye-adaptation readback is asynchronous: it would make two identical walks differ
        defer { renderer.autoExposure = savedAuto }
        var out: Frames = []
        for k in -warmup..<frames {
            renderer.fixedTime = moving ? 12 + Float(k) * clockStep : 12
            let cam = camera(base: base, motion: .walk, frame: k)
            guard let cb = renderer.queue.makeCommandBuffer() else { throw Screenshot.Failure.texture }
            renderer.encode(commandBuffer: cb, target: target, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            if k >= 0 { out.append((cam, luma(target), Parallax.readDistance(renderer: renderer, width: width, height: height))) }
        }
        return out
    }

    /// `share`: the part of the crawl (sum of squared differences) that falls on the pixels the layer is responsible for, which are the pixels that change by more than `ownThreshold` / 255
    /// when it is switched off. `pixels`: those pixels as a share of all scored pixels. Layers overlap (water seen through glass, shadow on grass), so shares can add up to more than 100 %.
    /// A pixel belongs to a layer when switching the layer off changes its luma by more than this (0-255). Small changes are the layer's light spilling onto other things (the sun's glow, bounce).
    static let ownThreshold: Float = 12
    struct LayerShare { var share: Float; var pixels: Float; var edgeShare: Float = 0; var edgePixels: Float = 0 }
    struct Attribution { var scene: String; var all: Run; var frozen: Run; var layers: [RenderLayer: LayerShare]; var edge: Run = Run(flicker: 0, detail: 0); var edgeFrozen: Run = Run(flicker: 0, detail: 0) }

    /// Edge crawl: the metric above cannot see silhouettes against the sky (no depth to reproject with), which is where a twig, a blade tip or a crystal point can flicker most. This one
    /// needs no depth: for every pixel on a strong edge (gradient over 24 / 255) it takes the squared difference to the best match among the 3 x 3 pixels around it in the previous
    /// frame (so a slide of up to a pixel costs nothing, and a speck that appears or vanishes costs its full contrast). Mean over the edge pixels; sky included.
    static func edgeScore(frames: Frames, width: Int, height: Int, include: ((_ frame: Int, _ pixel: Int) -> Bool)? = nil) -> Run {
        var sum = 0.0, n = 0
        for k in 1..<frames.count {
            let a = frames[k - 1].y, b = frames[k].y
            for y in stride(from: 2, to: height - 2, by: 1) {
                for x in stride(from: 2, to: width - 2, by: 1) {
                    let i = y * width + x
                    let gx = b[i + 1] - b[i - 1], gy = b[i + width] - b[i - width]
                    guard gx * gx + gy * gy > 576 else { continue }
                    if let include, !include(k, i) { continue }
                    var best = Float.infinity
                    for dy in -1...1 { for dx in -1...1 { let d = b[i] - a[i + dy * width + dx]; best = min(best, d * d) } }
                    sum += Double(best); n += 1
                }
            }
        }
        return Run(flicker: n > 0 ? Float(sum / Double(n)) : 0, detail: 0, sum: sum, n: n)
    }

    static func attribute(renderer: Renderer, width: Int, height: Int, frames: Int) throws -> [Attribution] {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: desc) else { throw Screenshot.Failure.texture }
        var rows: [Attribution] = []
        for sc in movingScenes {
            _ = try walk(renderer: renderer, scene: sc, off: [], moving: true, width: width, height: height, frames: 4, target: target)          // settles anything the renderer keeps between frames
            let all = try walk(renderer: renderer, scene: sc, off: [], moving: true, width: width, height: height, frames: frames, target: target)
            let allRun = score(frames: all, width: width, height: height)
            let frozenFrames = try walk(renderer: renderer, scene: sc, off: [], moving: false, width: width, height: height, frames: frames, target: target)
            let frozen = score(frames: frozenFrames, width: width, height: height)
            let edgeAll = edgeScore(frames: all, width: width, height: height), edgeFrozen = edgeScore(frames: frozenFrames, width: width, height: height)
            let again = try walk(renderer: renderer, scene: sc, off: [], moving: true, width: width, height: height, frames: frames, target: target)
            var differing = 0, total = 0, maxd: Float = 0
            for k in all.indices { for i in all[k].y.indices { let d = abs(all[k].y[i] - again[k].y[i]); if d > 1 { differing += 1 }; maxd = max(maxd, d); total += 1 } }
            FileHandle.standardError.write(Data(String(format: "  [determinism %@: %.3f %% of pixels differ by > 1 between two identical walks, max %.1f]\n", sc.name, 100 * Double(differing) / Double(max(total, 1)), maxd).utf8))
            var layers: [RenderLayer: LayerShare] = [:]
            for l in RenderLayer.allCases {
                let without = try walk(renderer: renderer, scene: sc, off: [l], moving: true, width: width, height: height, frames: frames, target: target)
                let part = score(frames: all, width: width, height: height, include: { k, i in abs(all[k].y[i] - without[k].y[i]) > ownThreshold })
                let ePart = edgeScore(frames: all, width: width, height: height, include: { k, i in abs(all[k].y[i] - without[k].y[i]) > ownThreshold })
                layers[l] = LayerShare(share: allRun.sum > 0 ? Float(part.sum / allRun.sum) : 0, pixels: allRun.n > 0 ? Float(part.n) / Float(allRun.n) : 0,
                                       edgeShare: edgeAll.sum > 0 ? Float(ePart.sum / edgeAll.sum) : 0, edgePixels: edgeAll.n > 0 ? Float(ePart.n) / Float(edgeAll.n) : 0)
            }
            rows.append(Attribution(scene: sc.name, all: allRun, frozen: frozen, layers: layers, edge: edgeAll, edgeFrozen: edgeFrozen))
        }
        return rows
    }

    static func report(_ rows: [Attribution], width: Int, height: Int, frames: Int) -> String {
        var s = "shimmer attribution (G10.0.2): a walk at 0.028 m/frame with the wind on, the game clock advancing at the walking pace, TAA on, \(frames) frames at \(width)x\(height).\n"
        s += "Two metrics (0-255 luma squared; lower is steadier): SURFACE crawl is the F02 motion-compensated one (it reprojects with depth, so it skips sky, depth edges and silhouettes);\n"
        s += "EDGE crawl is new and needs no depth: edge pixels (gradient > 24) matched against the best of 3x3 pixels of the previous frame, so it sees twigs, blade tips and crystal points against the sky.\n"
        s += "Each layer is switched off in turn; its pixels are the ones whose luma changes by more than \(Int(ownThreshold)) / 255 when it is off, and its share is the part of the crawl that falls on them.\n"
        s += "Wind moves blades and boughs for real, which counts as crawl ('clock frozen' = the same walk with the clock stopped: aliasing alone). Shares overlap (a shadow on grass counts for\n"
        s += "both), so they can add to more than 100 %. Every walk is reproducible (exposure fixed, TAA state and jitter reset): two identical walks differ by less than 1/255 in every pixel that matters.\n"
        s += "READ WITH CARE: ownership says where the crawl falls, not what causes it. The sky's edge share is mostly tree and glass silhouettes against the sky, counted twice (the sky pixel beside them\n"
        s += "belongs to the sky layer, the twig to the tree). The shadows share is lighting dependence (a canopy's shade covers most of a wood), largely inherited from the trees. Glass shows 0 % surface\n"
        s += "because the surface metric skips refractive pixels: only its edge share means anything. 'grove' is the ground-grass-5m view, which stands inside the woods (grass is judged on\n"
        s += "the edge column and on the dock/crystal scenes, not here).\n\n"
        var weighted: [RenderLayer: Double] = [:], edgeWeighted: [RenderLayer: Double] = [:], total = 0.0, edgeTotal = 0.0
        for r in rows {
            total += r.all.sum; edgeTotal += r.edge.sum
            s += String(format: "%-8@ surface %7.3f (clock frozen %7.3f, %d px)   edge %7.3f (clock frozen %7.3f, %d px)\n", r.scene as NSString, r.all.flicker, r.frozen.flicker, r.all.n, r.edge.flicker, r.edgeFrozen.flicker, r.edge.n)
            for l in RenderLayer.allCases.sorted(by: { r.layers[$0]!.share + r.layers[$0]!.edgeShare > r.layers[$1]!.share + r.layers[$1]!.edgeShare }) {
                let v = r.layers[l]!
                weighted[l, default: 0] += Double(v.share) * r.all.sum
                edgeWeighted[l, default: 0] += Double(v.edgeShare) * r.edge.sum
                s += String(format: "    %-8@ surface %5.1f %% of the crawl (on %5.1f %% of pixels)   edge %5.1f %% of the crawl (on %5.1f %% of edge pixels)\n", l.rawValue as NSString, v.share * 100, v.pixels * 100, v.edgeShare * 100, v.edgePixels * 100)
            }
        }
        s += "\nRANKED over the five scenes (share of the summed crawl):\n"
        s += "  surface:                         edge (silhouettes included):\n"
        let bySurface = RenderLayer.allCases.sorted { weighted[$0, default: 0] > weighted[$1, default: 0] }
        let byEdge = RenderLayer.allCases.sorted { edgeWeighted[$0, default: 0] > edgeWeighted[$1, default: 0] }
        for i in 0..<bySurface.count {
            let a = bySurface[i], b = byEdge[i]
            s += String(format: "  %d. %-8@ %5.1f %%               %d. %-8@ %5.1f %%\n", i + 1, a.rawValue as NSString, 100 * weighted[a, default: 0] / max(total, 1e-9), i + 1, b.rawValue as NSString, 100 * edgeWeighted[b, default: 0] / max(edgeTotal, 1e-9))
        }
        return s
    }
}
