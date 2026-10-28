import Foundation
import Metal
import simd

/// Self-tests: the waterline is the beach's own contour (F04 W1, note #52: water seen through land, flat polygons in the shallows, a sand bar clipped in straight facets).
extension SelfTestRunner {
    func runShoreWater() {
        guard name == "all" || name == "shorewater" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "shorewater: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.world = .varrow
        renderer.fixedTime = 12
        renderer.autoExposure = false
        let terrain = renderer.scene.terrain!
        let w = 640, h = 360
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "shorewater: no target"); return }
        // The eye of the feedback entry's view (feet 175, 0.8, 205 + 1.7), a look down from the dock's end, and one from the island's high side over the same beach.
        // The feedback entry's own view (informational: along a grazing ray the water in front legitimately lies over rising ground behind it) and three steep looks down at the
        // beach, where the ray is nearly vertical so the ground at the pixel IS the ground under the water: those are asserted.
        let views: [(String, Camera, Bool)] = [("feedback #52 view", Camera(position: SIMD3(175, 2.5, 205), yaw: -0.03, pitch: -0.05), false),
                                               ("down from the dock end", Camera(position: SIMD3(168.5, 4.0, 198.5), yaw: -0.74, pitch: -1.15), true),
                                               ("down on the east beach", Camera(position: SIMD3(150, 6.0, 172), yaw: -1.95, pitch: -1.1), true),
                                               ("down from the high side", Camera(position: SIMD3(150, 14, 172), yaw: -1.2, pitch: -1.0), true)]
        func frame(_ cam: Camera, water: Bool) -> (y: [Float], dist: [Float])? {
            RenderLayer.off = water ? [.mist] : [.mist, .water]          // the mist sheets are a haze over low ground too: leave them out of both frames
            defer { RenderLayer.off = [] }
            renderer.taaEnabled = false
            for _ in 0..<2 {
                guard let cb = renderer.queue.makeCommandBuffer() else { return nil }
                renderer.encode(commandBuffer: cb, target: tex, camera: cam)
                cb.commit(); cb.waitUntilCompleted()
            }
            return (hdrLuma(renderer, width: w, height: h), Parallax.readDistance(renderer: renderer, width: w, height: h))
        }
        // The scene's HDR colour before bloom, god rays and the tonemap (those spread light from bright water onto neighbouring pixels, which is not water over land).
        func hdrLuma(_ r: Renderer, width: Int, height: Int) -> [Float] {
            guard let hdr = r.hdrTexture, let buf = r.device.makeBuffer(length: width * height * 8, options: .storageModeShared),
                  let cb = r.queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { return [] }
            blit.copy(from: hdr, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: buf, destinationOffset: 0, destinationBytesPerRow: width * 8, destinationBytesPerImage: width * height * 8)
            blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            let p = buf.contents().assumingMemoryBound(to: Float16.self)
            return (0..<(width * height)).map { 0.2126 * Float(p[$0 * 4]) + 0.7152 * Float(p[$0 * 4 + 1]) + 0.0722 * Float(p[$0 * 4 + 2]) }
        }
        var report: [String] = []
        var worst: Float = 0, drawnOver = 0, drawnTotal = 0
        var asserted = 0
        for (label, cam, assert) in views {
            guard let on = frame(cam, water: true), let off = frame(cam, water: false) else { check(false, "shorewater: no frame"); return }
            let aspect = Float(w) / Float(h), ty = tan(cam.fovY / 2), tx = ty * aspect, b = Parallax.basis(cam)
            var over = 0, total = 0
            var mark = [UInt8](repeating: 0, count: w * h * 4)
            for y in stride(from: 0, to: h, by: 2) { for x in stride(from: 0, to: w, by: 2) {
                let i = y * w + x
                guard abs(on.y[i] - off.y[i]) > 0.15 * max(off.y[i], 0.05), on.dist[i] < 200 else { continue }          // a pixel the water changed clearly 
                let nx = (Float(x) + 0.5) / Float(w) * 2 - 1, ny = 1 - (Float(y) + 0.5) / Float(h) * 2
                let p = cam.position + simd_normalize(b.f + b.r * (nx * tx) + b.u * (ny * ty)) * on.dist[i]
                let g = terrain.sampleHeight(x: p.x, z: p.z)
                // The scene behind this pixel is the ground when its point is within 15 cm of the height field; then the water above it must be no higher than the swash allows.
                guard abs(p.y - g) < 0.15, g > -0.6, g < 1.2 else { continue }          // ground on the beach band, where the waterline lives
                total += 1
                let gx = (terrain.sampleHeight(x: p.x + 2, z: p.z) - terrain.sampleHeight(x: p.x - 2, z: p.z)) / 4, gz = (terrain.sampleHeight(x: p.x, z: p.z + 2) - terrain.sampleHeight(x: p.x, z: p.z - 2)) / 4
                let edge = Shore.swashEdge(x: p.x, z: p.z, time: 12, slope: (gx * gx + gz * gz).squareRoot())          // the same per-pixel slope the shader uses
                let reach = Shore.swashMax + 0.04 + 0.35 * (gx * gx + gz * gz).squareRoot()          // the highest the swash can ever reach here, plus the rise over the 0.35 m a steep ray can be off by
                let limit: Float = g > -0.3 ? reach : .infinity              // deeper than 30 cm the open sea owns the sheet
                if g > limit { for dy in 0..<2 { for dx in 0..<2 { mark[((y + dy) * w + x + dx) * 4 + 2] = 255 } } }
                if g > limit { over += 1; worst = max(worst, g - limit); if ProcessInfo.processInfo.environment["SHOREWATER_DEBUG"] != nil && g - limit > 0.3 { print("  violation \(label) px \(x),\(y): ground \(g) edge \(edge) on \(on.y[i]) off \(off.y[i]) at \(p)") } }
            } }
            if assert { drawnOver += over; drawnTotal += total; asserted += 1 }
            if let dump = ProcessInfo.processInfo.environment["SHOREWATER_DUMP"] {
                var px = [UInt8](repeating: 0, count: w * h * 4)
                for i in 0..<(w * h) { let l = UInt8(min(255, max(0, on.y[i]) * 90)); px[i * 4] = l; px[i * 4 + 1] = l; px[i * 4 + 2] = mark[i * 4 + 2] > 0 ? 255 : l; px[i * 4 + 3] = 255 }
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false); d.usage = [.shaderRead]; d.storageMode = .shared
                if let t = device.makeTexture(descriptor: d) { t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: px, bytesPerRow: w * 4); try? Screenshot.writePNG(texture: t, to: "\(dump)-\(label.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "#", with: "")).png") }
            }
            report.append("\(label): \(total) pixels of water over ground, \(over) over land above the swash's reach")
        }
        check(asserted == 3 && drawnTotal > 300 && drawnOver == 0, "shorewater: no water pixel is drawn over ground higher than the swash can ever reach (worst excess \(String(format: "%.3f", worst)) m); " + report.joined(separator: "; "))
        // The film is never thicker than its 5 cm and the CPU mirror of the shader's sheet agrees at the contact line.
        let edge = Shore.swashEdge(x: 170, z: 200, time: 12, slope: 0.1)
        let ground: Float = edge - 0.02
        let sheet = Shore.sheetHeight(seaY: 0, ground: ground, swashEdge: edge)
        check(sheet - ground <= Shore.filmThickness + 1e-5 && sheet >= ground, "shorewater: the film over ground just below the swash edge is thinner than \(Shore.filmThickness) m (\(sheet - ground))")
    }
}
