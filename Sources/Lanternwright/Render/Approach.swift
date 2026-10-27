import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd

/// `--approach <target|all> <out>`: the continuous-detail measurement (R09). Walks the camera toward a fixed target in geometric steps (the
/// distance shrinks by x0.85 per step), renders a fixed crop around the target at every step, and reports per step the crop's mean luma and a
/// high-frequency measure (mean absolute Laplacian of the luma). Detail should grow smoothly: a step where the high-frequency energy jumps, or
/// where the mean luma shifts, is a pop. Also writes a contact sheet (steps left to right) that a person can read.
enum Approach {
    struct Target {
        let name: String
        let world: WorldKind
        let point: SIMD3<Float>          // what the camera looks at
        let dir: SIMD2<Float>            // the camera stands this way from the target (xz, unit)
        var start: Float                 // first distance (m)
        let base: Float                  // camera height above `point` at zero distance
        let rise: Float                  // extra camera height per metre of distance (keeps the target in view from far)
        let crop: Int                    // side of the measured crop (px)
        var minDistance: Float = 0.5     // last distance (m)
    }

    struct Result {
        var name: String
        var distances: [Float] = []
        var luma: [Float] = []
        var hf: [Float] = []
        var thumbs: [[UInt8]] = []       // BGRA crops
        var cropSide = 0
        /// Largest relative change of mean luma between neighbouring steps (fraction).
        var maxLumaStep: Float { zip(luma, luma.dropFirst()).map { abs($1 - $0) / max($0, 1) }.max() ?? 0 }
        /// Largest ratio of high-frequency energy between neighbouring steps (closer / farther, either direction folded to >= 1).
        var maxHFRatio: Float { zip(hf, hf.dropFirst()).map { max($1, 1e-3) / max($0, 1e-3) }.map { max($0, 1 / $0) }.max() ?? 1 }
        /// Number of steps (towards the target) where the energy falls by more than 15 % (detail should not vanish as you approach).
        var hfDrops: Int { zip(hf, hf.dropFirst()).filter { $1 < $0 * 0.85 }.count }
        /// Mean absolute luma difference between each pair of neighbouring crops. A pop is a step whose difference towers over its neighbours.
        var stepDiffs: [Float] {
            var out: [Float] = []
            for k in 1..<max(thumbs.count, 1) {
                let a = thumbs[k - 1], b = thumbs[k]
                var s: Float = 0
                var i = 0
                while i + 3 < a.count {
                    let la = 0.2126 * Float(a[i + 2]) + 0.7152 * Float(a[i + 1]) + 0.0722 * Float(a[i])
                    let lb = 0.2126 * Float(b[i + 2]) + 0.7152 * Float(b[i + 1]) + 0.0722 * Float(b[i])
                    s += abs(la - lb); i += 4
                }
                out.append(s / Float(a.count / 4))
            }
            return out
        }
        /// Largest step difference divided by the median one (1 = perfectly even; a pop shows as a big number).
        var diffSpike: Float {
            let d = stepDiffs.sorted()
            guard let mx = d.last, d.count > 2 else { return 1 }
            return mx / max(d[d.count / 2], 0.25)
        }
    }

    static let names = ["dock", "lh-door", "lh-shaft", "stone", "path", "conifer", "conifer-foliage", "meadow", "sand", "crystal-tree", "gw-grass"]

    // MARK: Targets

    static func target(_ name: String, renderer: Renderer) -> Target? {
        let v = renderer.scenes[.varrow]!.terrain!, g = renderer.scenes[.glassWood]!.terrain!
        func unit(_ a: SIMD3<Float>, from b: SIMD3<Float>) -> SIMD2<Float> { simd_normalize(SIMD2(b.x - a.x, b.z - a.z)) }
        /// The best-scoring point of a coarse grid around `near`.
        func scan(_ t: Terrain, near: SIMD2<Float>, radius: Float, ok: (Float, Float) -> Bool) -> SIMD3<Float> {
            var best = SIMD3<Float>(near.x, t.sampleHeight(x: near.x, z: near.y), near.y), bestD = Float.infinity
            var x = near.x - radius
            while x <= near.x + radius {
                var z = near.y - radius
                while z <= near.y + radius {
                    let d = simd_length(SIMD2(x, z) - near)
                    if d < bestD && ok(x, z) { bestD = d; best = SIMD3(x, t.sampleHeight(x: x, z: z), z) }
                    z += 3
                }
                x += 3
            }
            return best
        }
        switch name {
        case "dock":
            let s = Layout.dockStrip(), dir = simd_normalize(s.b - s.a), along: Float = 9
            let p = s.a + dir * along
            return Target(name: name, world: .varrow, point: SIMD3(p.x, s.y0 + (s.y1 - s.y0) * along / simd_length(s.b - s.a) + 0.01, p.y), dir: dir, start: 40, base: 1.7, rise: 0.35, crop: 24)
        case "lh-door":
            return Target(name: name, world: .varrow, point: Layout.lighthouse + SIMD3(0, 1.6, 4.3), dir: SIMD2(0, 1), start: 100, base: 4.0, rise: 0.0, crop: 40, minDistance: 1.5)
        case "lh-shaft":
            let d = simd_normalize(SIMD2<Float>(-0.6, 0.8))
            return Target(name: name, world: .varrow, point: Layout.lighthouse + SIMD3(d.x * 4.4, 3.2, d.y * 4.4), dir: d, start: 100, base: 4.0, rise: 0.0, crop: 32)
        case "stone":
            return Target(name: name, world: .varrow, point: Layout.tideStone + SIMD3(0, 1.4, 0.5), dir: unit(Layout.tideStone, from: Layout.dockShore), start: 40, base: 0.2, rise: 0.0, crop: 48)
        case "path":
            let a = Layout.dockShore, b = Layout.tideStone
            var p = (a + b) / 2
            for k in 2...8 { let q = a + (b - a) * (Float(k) / 10); if v.pathWeight(x: q.x, z: q.z) > 0.9 { p = q; break } }
            p.y = v.sampleHeight(x: p.x, z: p.z)
            return Target(name: name, world: .varrow, point: p, dir: unit(p, from: a), start: 60, base: 1.7, rise: 0.35, crop: 24)
        case "conifer":
            let sites = Island.treeSites(terrain: v).prefix(420).filter { v.sampleHeight(x: $0.x, z: $0.y) > 6 && v.sampleHeight(x: $0.x, z: $0.y) < 26 }
            let from = SIMD2(Layout.dockShore.x, Layout.dockShore.z)
            guard let tree = sites.filter({ simd_length($0 - from) > 25 }).min(by: { simd_length($0 - from) < simd_length($1 - from) }) else { return nil }
            let y = v.sampleHeight(x: tree.x, z: tree.y)
            return Target(name: name, world: .varrow, point: SIMD3(tree.x, y + 5, tree.y), dir: simd_normalize(from - tree), start: 100, base: -3.3, rise: 0.08, crop: 64)
        case "conifer-foliage":
            // F02 T66.13: the whole lower crown of the same tree in a wide crop (240 px), so the stylised sprays and the needle cards both fill it; the plain "conifer" target
            // frames only the stem, where foliage never appears.
            let sites = Island.treeSites(terrain: v).prefix(420).filter { v.sampleHeight(x: $0.x, z: $0.y) > 6 && v.sampleHeight(x: $0.x, z: $0.y) < 26 && v.normal(x: $0.x, z: $0.y).y > 0.93 }        // the same tree as the tree-needle views
            let from = SIMD2(Layout.dockShore.x, Layout.dockShore.z)
            guard let tree = sites.filter({ simd_length($0 - from) > 25 }).min(by: { simd_length($0 - from) < simd_length($1 - from) }) else { return nil }
            let y = v.sampleHeight(x: tree.x, z: tree.y)
            return Target(name: name, world: .varrow, point: SIMD3(tree.x, y + 3.6, tree.y), dir: simd_normalize(from - tree), start: 30, base: -0.5, rise: 0.0, crop: 240, minDistance: 5)
        case "meadow":
            let p = scan(v, near: SIMD2(20, 40), radius: 150) { x, z in
                let h = v.sampleHeight(x: x, z: z)
                return h > 8 && h < 30 && v.normal(x: x, z: z).y > 0.96 && v.pathDistance(x: x, z: z) > 10 && v.duffAt(x: x, z: z) < 0.01 && Island.isClear(terrain: v, x: x, z: z, pathMargin: 10, padMargin: 10)
            }
            return Target(name: name, world: .varrow, point: p, dir: simd_normalize(SIMD2(1, 1)), start: 150, base: 1.7, rise: 0.2, crop: 64)
        case "sand":
            let p = scan(v, near: SIMD2(Layout.dockShore.x - 25, Layout.dockShore.z - 12), radius: 80) { x, z in
                let h = v.sampleHeight(x: x, z: z)
                return h > 0.5 && h < 1.4 && v.normal(x: x, z: z).y > 0.985 && Island.isClear(terrain: v, x: x, z: z, pathMargin: 6, padMargin: 6)
            }
            return Target(name: name, world: .varrow, point: p, dir: simd_normalize(SIMD2(1, 1)), start: 150, base: 1.7, rise: 0.2, crop: 64)
        case "crystal-tree":
            let a = GlassLayout.arrival
            let from = SIMD2(a.x, a.z)
            let sites = GlassWood.forestSites(terrain: g).prefix(220)
            guard let tree = sites.filter({ simd_length($0 - from) > 30 }).min(by: { simd_length($0 - SIMD2(a.x, a.z - 60)) < simd_length($1 - SIMD2(a.x, a.z - 60)) }) else { return nil }
            let y = g.sampleHeight(x: tree.x, z: tree.y)
            return Target(name: name, world: .glassWood, point: SIMD3(tree.x, y + 5, tree.y), dir: simd_normalize(from - tree), start: 100, base: -3.3, rise: 0.08, crop: 64)
        case "gw-grass":
            let a = GlassLayout.arrival
            let p = scan(g, near: SIMD2(a.x + 15, a.z - 35), radius: 60) { x, z in
                g.sampleHeight(x: x, z: z) > 3 && g.normal(x: x, z: z).y > 0.96 && g.pathDistance(x: x, z: z) > 8 && Island.isClear(terrain: g, x: x, z: z, pathMargin: 8, padMargin: 8, avoidDock: false)
            }
            return Target(name: name, world: .glassWood, point: p, dir: simd_normalize(SIMD2(0, 1)), start: 100, base: 1.7, rise: 0.2, crop: 64)
        default: return nil
        }
    }

    static func camera(_ t: Target, distance d: Float) -> Camera {
        let pos = SIMD3(t.point.x + t.dir.x * d, t.point.y + t.base + t.rise * d, t.point.z + t.dir.y * d)
        let to = t.point - pos
        return Camera(position: pos, yaw: atan2(to.x, -to.z), pitch: asin(max(-1, min(1, to.y / simd_length(to)))))
    }

    // MARK: Running

    /// BGRA bytes of one rendered frame.
    static func pixels(renderer: Renderer, camera: Camera, width: Int, height: Int, target: MTLTexture) -> [UInt8] {
        for _ in 0..<2 {
            guard let cb = renderer.queue.makeCommandBuffer() else { return [] }
            renderer.encode(commandBuffer: cb, target: target, camera: camera)
            cb.commit(); cb.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&px, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return px
    }

    static func run(_ t: Target, renderer: Renderer, width: Int, height: Int, factor: Float = 0.85, minDistance: Float = 0.5) -> Result {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = renderer.device.makeTexture(descriptor: desc) else { return Result(name: t.name) }
        renderer.fixedTime = 12
        renderer.autoExposure = false
        renderer.world = t.world
        var r = Result(name: t.name)
        r.cropSide = t.crop
        var d = t.start
        let x0 = width / 2 - t.crop / 2, y0 = height / 2 - t.crop / 2
        while d >= minDistance {
            let px = pixels(renderer: renderer, camera: camera(t, distance: d), width: width, height: height, target: tex)
            var crop = [UInt8](repeating: 255, count: t.crop * t.crop * 4)
            var luma = [Float](repeating: 0, count: t.crop * t.crop)
            for y in 0..<t.crop {
                for x in 0..<t.crop {
                    let s = ((y0 + y) * width + (x0 + x)) * 4, o = (y * t.crop + x) * 4
                    crop[o] = px[s]; crop[o + 1] = px[s + 1]; crop[o + 2] = px[s + 2]
                    luma[y * t.crop + x] = 0.2126 * Float(px[s + 2]) + 0.7152 * Float(px[s + 1]) + 0.0722 * Float(px[s])
                }
            }
            r.distances.append(d)
            r.luma.append(luma.reduce(0, +) / Float(luma.count))
            var e: Float = 0
            let n = t.crop
            for y in 1..<(n - 1) { for x in 1..<(n - 1) {
                e += abs(4 * luma[y * n + x] - luma[y * n + x - 1] - luma[y * n + x + 1] - luma[(y - 1) * n + x] - luma[(y + 1) * n + x])
            } }
            r.hf.append(e / Float((n - 2) * (n - 2)))
            r.thumbs.append(crop)
            d *= factor
        }
        return r
    }

    // MARK: Output

    static func summary(_ r: Result) -> String {
        var s = String(format: "%-13@ steps %2d  max luma step %5.1f %%  max HF ratio %5.2f  HF drops %d  diff spike %5.2f\n", r.name as NSString, r.distances.count, r.maxLumaStep * 100, r.maxHFRatio, r.hfDrops, r.diffSpike)
        for i in 0..<r.distances.count { s += String(format: "    d %7.2f m  luma %6.1f  hf %6.2f\n", r.distances[i], r.luma[i], r.hf[i]) }
        return s
    }

    /// Steps left to right, far to near, in a grid of 10 columns, each crop at 128 px (nearest-neighbour, so the pixels are honest).
    static func writeContactSheet(_ r: Result, to path: String) throws {
        let cell = 128, gap = 3, cols = 10, n = r.thumbs.count
        guard n > 0 else { return }
        let rows = (n + cols - 1) / cols
        let w = cols * (cell + gap), h = rows * (cell + gap)
        var out = [UInt8](repeating: 30, count: w * h * 4)
        for k in 0..<n {
            let ox = (k % cols) * (cell + gap), oy = (k / cols) * (cell + gap)
            for y in 0..<cell {
                for x in 0..<cell {
                    let sx = x * r.cropSide / cell, sy = y * r.cropSide / cell
                    let s = (sy * r.cropSide + sx) * 4, o = ((oy + y) * w + ox + x) * 4
                    out[o] = r.thumbs[k][s]; out[o + 1] = r.thumbs[k][s + 1]; out[o + 2] = r.thumbs[k][s + 2]; out[o + 3] = 255
                }
            }
        }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw Screenshot.Failure.image }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Screenshot.Failure.write(path) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Screenshot.Failure.write(path) }
    }

    /// `--approach all <base>` writes `<base>-<target>.png` for every target and prints each summary; `--approach <target> <out.png>` does one.
    static func main(renderer: Renderer, which: String, out: String, width: Int, height: Int, range: (start: Float, min: Float, factor: Float)? = nil) throws {
        let list = which == "all" ? names : [which]
        for name in list {
            guard let t = target(name, renderer: renderer) else { print("unknown or unavailable target \(name)"); continue }
            var tt = t
            if let range { tt.start = range.start }
            let r = run(tt, renderer: renderer, width: width, height: height, factor: range?.factor ?? 0.85, minDistance: range?.min ?? t.minDistance)
            print(summary(r))
            try writeContactSheet(r, to: which == "all" ? "\(out)-\(name).png" : out)
        }
    }
}

// MARK: Foliage match (F03 G4, note #41)

extension Approach {
    /// The share of a frame that is foliage (green-dominant, so not the grey-blue sky, not the brown trunk) when a conifer's crown is framed at `distance` metres. The field of
    /// view shrinks in proportion to the distance, so the crown is the SAME size on screen at every distance: the share is then directly comparable between the stylised
    /// sprays (far) and the needle cards (near). `floating` false puts the eye on the ground (1.7 m), as a player's is, looking up into the crown. `write` saves the frame.
    static func foliageShare(renderer: Renderer, distance: Float, floating: Bool = true, width: Int = 480, height: Int = 640, write: String? = nil) -> Float {
        let v = renderer.scenes[.varrow]!.terrain!
        let sites = Island.treeSites(terrain: v).prefix(420).filter { v.sampleHeight(x: $0.x, z: $0.y) > 6 && v.sampleHeight(x: $0.x, z: $0.y) < 26 && v.normal(x: $0.x, z: $0.y).y > 0.93 }
        let from = SIMD2(Layout.dockShore.x, Layout.dockShore.z)
        guard let tree = sites.filter({ simd_length($0 - from) > 25 }).min(by: { simd_length($0 - from) < simd_length($1 - from) }) else { return 0 }
        let g = v.sampleHeight(x: tree.x, z: tree.y)
        let toward = simd_normalize(from - tree)
        let cam2 = tree + toward * distance
        let target = SIMD3(tree.x, g + 6.0, tree.y)                       // the middle of the crown
        // The eye floats so that the crown is always seen from the same elevation (8 degrees below the crown's middle, as at 30 m from a 1.7 m eye): a near eye on the ground looks
        // up into the crown and sees less of it, which would be the view's doing and not the foliage's.
        let eye = SIMD3(cam2.x, floating ? target.y - distance * 0.1405 : v.sampleHeight(x: cam2.x, z: cam2.y) + 1.7, cam2.y)
        let d = target - eye
        let halfHeight: Float = 5.2                                         // metres of crown framed (the crown is about 10 m tall)
        let fov = 2 * atan(halfHeight / simd_length(d))
        let cam = Camera(position: eye, yaw: atan2(d.x, -d.z), pitch: asin(d.y / simd_length(d)), fovY: fov)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = renderer.device.makeTexture(descriptor: desc) else { return 0 }
        renderer.fixedTime = 12; renderer.autoExposure = false; renderer.world = .varrow
        // The same frame without any conifer is the background; foliage is what differs from it, in the central half of the width and the upper half of the frame (where the
        // crown is; the ground's shadows fall lower).
        let withTrees = pixels(renderer: renderer, camera: cam, width: width, height: height, target: tex)
        Scene.hideTrees = true
        let background = pixels(renderer: renderer, camera: cam, width: width, height: height, target: tex)
        Scene.hideTrees = false
        var green = 0, total = 0
        var out = withTrees
        if let path = write { writeRaw(withTrees, width: width, height: height, to: path.replacingOccurrences(of: ".png", with: "-raw.png")) }
        for y in 0..<(height / 2) { for x in (width / 4)..<(3 * width / 4) {
            let i = (y * width + x) * 4
            let delta = abs(Int(withTrees[i]) - Int(background[i])) + abs(Int(withTrees[i + 1]) - Int(background[i + 1])) + abs(Int(withTrees[i + 2]) - Int(background[i + 2]))
            let isFoliage = delta > 36
            total += 1
            if isFoliage { green += 1 } else if write != nil { out[i] = 255; out[i + 1] = 255; out[i + 2] = 255 }
        } }
        if let path = write {
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            if let provider = CGDataProvider(data: Data(out) as CFData),
               let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
               let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
            }
        }
        return Float(green) / Float(max(total, 1))
    }
}

extension Approach {
    static func writeRaw(_ px: [UInt8], width: Int, height: Int, to path: String) {
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        if let provider = CGDataProvider(data: Data(px) as CFData),
           let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
           let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
        }
    }
}
