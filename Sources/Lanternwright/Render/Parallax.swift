import Foundation
import Metal
import simd

/// `--parallax`: does the world obey a pinhole camera as you walk (F02 R2, user note #26: "distant details appear to jump back after so many steps toward them")?
///
/// Walks the camera north from (-39, y, 140) in 0.5 m steps. For each pair of consecutive frames it takes the renderer's per-pixel DISTANCE buffer, turns every sampled
/// pixel of frame k into a world point (camera + ray x distance), projects that point into frame k+1 and compares its predicted distance with what frame k+1 actually
/// stored there. Static geometry that is drawn where it really is agrees to within a pixel's worth; geometry that changes shape or position with the camera (an LOD swap,
/// a snapped layer) disagrees. Pixels next to a depth edge (where one pixel step legitimately changes the surface) are skipped. The error is in metres along the ray.
enum Parallax {
    struct Band { let lo: Float, hi: Float; var name: String { hi > 1e6 ? "\(Int(lo))+ m" : "\(Int(lo))-\(Int(hi)) m" } }
    static let bands = [Band(lo: 15, hi: 60), Band(lo: 60, hi: 150), Band(lo: 150, hi: 400), Band(lo: 400, hi: 1e9)]

    struct Stats { var n = 0; var errs: [Float] = [] }
    struct Pair { var bad: [(x: Int, y: Int, d: Float, e: Float)] = []; var step: Int; var perBand: [Stats]; var worst: Float = 0; var worstDist: Float = 0; var worstPixel = SIMD2<Int>(0, 0) }

    static func readDistance(renderer: Renderer, width: Int, height: Int) -> [Float] {
        guard let tex = renderer.distanceTexture, let buf = renderer.device.makeBuffer(length: width * height * 4, options: .storageModeShared),
              let cb = renderer.queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { return [] }
        blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buf, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        return Array(UnsafeBufferPointer(start: buf.contents().assumingMemoryBound(to: Float.self), count: width * height))
    }

    static func basis(_ c: Camera) -> (f: SIMD3<Float>, r: SIMD3<Float>, u: SIMD3<Float>) {
        let f = c.forward, r = simd_normalize(simd_cross(f, SIMD3(0, 1, 0)))
        return (f, r, simd_cross(r, f))
    }

    /// Compare frame A's distances, reprojected into B's camera, against B's own.
    static func compare(_ a: [Float], cameraA: Camera, _ b: [Float], cameraB: Camera, width: Int, height: Int, stride: Int = 4) -> (perBand: [Stats], worst: Float, worstDist: Float, worstPixel: SIMD2<Int>, bad: [(x: Int, y: Int, d: Float, e: Float)]) {
        let aspect = Float(width) / Float(height)
        let ty = tan(cameraA.fovY / 2), tx = ty * aspect
        let ba = basis(cameraA), bb = basis(cameraB)
        var stats = [Stats](repeating: Stats(), count: bands.count)
        var worst: Float = 0, worstDist: Float = 0, worstPixel = SIMD2(0, 0)
        var bad: [(x: Int, y: Int, d: Float, e: Float)] = []
        for y in Swift.stride(from: 4, to: height - 4, by: stride) {
            for x in Swift.stride(from: 4, to: width - 4, by: stride) {
                let d = a[y * width + x]
                guard d.isFinite, d > 15, d < 3000 else { continue }
                let nx = (Float(x) + 0.5) / Float(width) * 2 - 1, ny = 1 - (Float(y) + 0.5) / Float(height) * 2
                let dir = simd_normalize(ba.f + ba.r * (nx * tx) + ba.u * (ny * ty))
                let w = cameraA.position + dir * d
                let rel = w - cameraB.position
                let zc = simd_dot(rel, bb.f)
                guard zc > 0.5 else { continue }
                let px = (simd_dot(rel, bb.r) / (zc * tx) * 0.5 + 0.5) * Float(width), py = (1 - (simd_dot(rel, bb.u) / (zc * ty) * 0.5 + 0.5)) * Float(height)
                let ix = Int(px), iy = Int(py)
                guard ix >= 2, iy >= 2, ix < width - 2, iy < height - 2 else { continue }
                // skip depth edges in B (a one-pixel shift legitimately changes the surface there) and in A
                var lo = Float.infinity, hi: Float = 0
                for dy in -2...2 { for dx in -2...2 { let v = b[(iy + dy) * width + ix + dx]; lo = min(lo, v); hi = max(hi, v) } }
                if !(hi < 1e6) || (hi - lo) > 0.012 * hi { continue }
                var alo = Float.infinity, ahi: Float = 0
                for dy in -2...2 { for dx in -2...2 { let v = a[(y + dy) * width + x + dx]; alo = min(alo, v); ahi = max(ahi, v) } }
                if !(ahi < 1e6) || (ahi - alo) > 0.012 * ahi { continue }
                let predicted = simd_length(rel)
                let err = b[iy * width + ix] - predicted
                for (i, band) in bands.enumerated() where d >= band.lo && d < band.hi { stats[i].n += 1; stats[i].errs.append(abs(err)) }
                if abs(err) > 0.5 { bad.append((x, y, d, err)) }
                if abs(err) > worst { worst = abs(err); worstDist = d; worstPixel = SIMD2(x, y) }
            }
        }
        return (stats, worst, worstDist, worstPixel, bad)
    }

    /// Render the walk and print the table; returns the pairs for the selftest.
    @discardableResult
    static func run(renderer: Renderer, width: Int = 1600, height: Int = 900, steps: Int = 80, step: Float = 0.5, start: SIMD2<Float> = SIMD2(-39, 140), quiet: Bool = false) throws -> [Pair] {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .private
        guard let target = renderer.device.makeTexture(descriptor: desc) else { throw Screenshot.Failure.texture }
        renderer.fixedTime = 12
        var frames: [(Camera, [Float])] = []
        for k in 0...steps {
            let z = start.y - Float(k) * step
            let cam = Camera(position: SIMD3(start.x, renderer.scene.groundHeight(x: start.x, z: z) + 1.7, z), yaw: 0, pitch: 0.02)
            guard let cb = renderer.queue.makeCommandBuffer() else { throw Screenshot.Failure.texture }
            renderer.encode(commandBuffer: cb, target: target, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            frames.append((cam, readDistance(renderer: renderer, width: width, height: height)))
        }
        var pairs: [Pair] = []
        for k in 0..<steps {
            let r = compare(frames[k].1, cameraA: frames[k].0, frames[k + 1].1, cameraB: frames[k + 1].0, width: width, height: height)
            pairs.append(Pair(bad: r.bad, step: k, perBand: r.perBand, worst: r.worst, worstDist: r.worstDist, worstPixel: r.worstPixel))
        }
        if !quiet {
            print("parallax: \(steps) steps of \(step) m from (\(start.x), \(start.y)) looking north, \(width)x\(height). Depth disagreement (m along the ray) after reprojecting each frame into the next:")
            for (i, band) in bands.enumerated() {
                let all = pairs.flatMap { $0.perBand[i].errs }.sorted()
                let perPairMean = pairs.map { p -> Float in let e = p.perBand[i].errs; return e.isEmpty ? 0 : e.reduce(0, +) / Float(e.count) }
                let worstPair = perPairMean.enumerated().max { $0.element < $1.element }
                print(String(format: "  %-10@ samples %7d  median %.3f m  p99 %.3f m  max %.2f m | worst pair step %d (mean %.3f m), median pair mean %.3f m",
                             band.name as NSString, all.count, all.isEmpty ? 0 : all[all.count / 2], all.isEmpty ? 0 : all[Int(Double(all.count) * 0.99)], all.last ?? 0,
                             worstPair?.offset ?? 0, worstPair?.element ?? 0, perPairMean.sorted()[perPairMean.count / 2]))
            }
            let worst = pairs.max { $0.worst < $1.worst }
            // Where the disagreements (over half a metre) are: pairs with the most, and a coarse map (screen cell x distance) of the worst of them.
            let noisy = pairs.filter { $0.bad.count > 20 }.sorted { $0.bad.count > $1.bad.count }
            print("  pairs with more than 20 samples off by over 0.5 m: \(noisy.count) of \(pairs.count)")
            for p in noisy.prefix(6) {
                let xs = p.bad.map(\.x), ys = p.bad.map(\.y), ds = p.bad.map(\.d), es = p.bad.map { abs($0.e) }
                print(String(format: "    step %2d: %4d samples; screen x %d-%d y %d-%d; distance %.0f-%.0f m; error median %.1f m",
                             p.step, p.bad.count, xs.min()!, xs.max()!, ys.min()!, ys.max()!, ds.min()!, ds.max()!, es.sorted()[es.count / 2]))
            }
            if let w = worst { print(String(format: "  largest single disagreement %.2f m at distance %.0f m, pixel (%d, %d), step %d", w.worst, w.worstDist, w.worstPixel.x, w.worstPixel.y, w.step)) }
        }
        return pairs
    }

    /// F02 R2, the sea: walk in 0.25 m steps along the beach toward the open water and measure, for each pair of frames, how much the FAR water changes (mean absolute luma
    /// difference over the band of rows between the horizon and a quarter of the way down, in 4x4 blocks) after taking out the smooth trend. Returns, per step, the change;
    /// `snapSteps` are the steps at which the disc re-snapped (the camera crossed a multiple of Ocean.snap / 2).
    static func seaSteps(renderer: Renderer, width: Int = 1280, height: Int = 720, steps: Int = 96, step: Float = 0.25) throws -> (changes: [Float], snaps: [Int]) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: desc) else { throw Screenshot.Failure.texture }
        renderer.fixedTime = 12
        let start = SIMD3<Float>(Layout.dockShore.x - 4, 1.7, Layout.dockShore.z + 6)       // on the beach, looking out to sea (south-east: yaw about 2.3 toward the open water)
        var prev: [Float]? = nil
        var changes: [Float] = [], snaps: [Int] = [], lastSnap: (Float, Float)? = nil
        let yaw: Float = 2.2
        let dir = SIMD3<Float>(sin(yaw), 0, -cos(yaw))
        for k in 0...steps {
            let p = start + dir * (Float(k) * step)
            let cam = Camera(position: SIMD3(p.x, 2.2, p.z), yaw: yaw, pitch: 0.0)
            guard let cb = renderer.queue.makeCommandBuffer() else { throw Screenshot.Failure.texture }
            renderer.encode(commandBuffer: cb, target: target, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            // luma of the far-water band: rows from the horizon (about the middle) down a quarter of the frame, in 4x4 blocks
            var luma: [Float] = []
            for by in stride(from: Int(Float(height) * 0.52), to: Int(Float(height) * 0.70), by: 4) {
                for bx in stride(from: 0, to: width, by: 4) {
                    var sum: Float = 0
                    for dy in 0..<4 { for dx in 0..<4 { let i = ((by + dy) * width + bx + dx) * 4; sum += 0.2126 * Float(bytes[i + 2]) + 0.7152 * Float(bytes[i + 1]) + 0.0722 * Float(bytes[i]) } }
                    luma.append(sum / 16)
                }
            }
            let sx = (cam.position.x / Ocean.snap).rounded(), sz = (cam.position.z / Ocean.snap).rounded()
            if let l = lastSnap, (l.0 != sx || l.1 != sz) { snaps.append(k - 1) }
            lastSnap = (sx, sz)
            if let pl = prev { changes.append(zip(luma, pl).map { abs($0 - $1) }.reduce(0, +) / Float(luma.count)) }
            prev = luma
        }
        return (changes, snaps)
    }
}
