import Foundation
import Metal
import simd

/// Self-tests: every lens ring is brass lit from within with a glowing disc, not flat white shapes (F10.2: `ta_return_ilse.png` showed the ring and a 14-gon core both blown out).
extension SelfTestRunner {
    func runLensLook() {
        guard name == "all" || name == "lenslook" else { return }
        // The disc's outline is a circle to within a fraction of a pixel at the quay: 64 segments, so the polygon sags 0.12 % of the radius, and every rim vertex is on the circle.
        let disc = LensLook.discMesh(radius: 0.86)
        let rim = disc.vertices.filter { $0.color.x > 0.999 }
        let radii = rim.map { simd_length(SIMD2($0.position.x, $0.position.y)) }
        check(rim.count >= 128 && radii.allSatisfy { abs($0 - 0.86) < 1e-4 }, "lenslook: the disc's rim is \(rim.count / 2) vertices per face, every one on the circle (radius \(radii.min() ?? 0)...\(radii.max() ?? 0))")
        let sag = 0.86 * (1 - cos(Float.pi / 64))
        check(sag < 0.0012, "lenslook: the polygon sags \(String(format: "%.4f", sag)) m between rim vertices: at 6 m with a 60 degree view that is under a quarter of a pixel at 1600x900")
        check(disc.vertices.allSatisfy { $0.normal.w == MaterialID.softDisc.rawValue }, "lenslook: the disc is the soft-disc material throughout")
        check(LensLook.ringBase <= 1.0 && LensLook.discBase <= 2.5 && LensLook.ringLit <= 2.5 && LensLook.discLit <= 4.0, "lenslook: resting and lit strengths are well under the old blown values (ring 2.2/6, core 5/11)")
        // The rendered quay lens: no blown-out plateau, a gradient across the disc.
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "lenslook: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.world = .tideArchive; renderer.fixedTime = 12; renderer.autoExposure = false; renderer.taaEnabled = false
        let c = TideSpots.quayReturn(.ilse), w = 640, h = 360
        let cam = Camera(position: SIMD3(c.x, c.y + 0.1, c.z + 6), yaw: 0, pitch: 0)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "lenslook: no target"); return }
        for _ in 0..<2 { guard let cb = renderer.queue.makeCommandBuffer() else { return }; renderer.encode(commandBuffer: cb, target: tex, camera: cam); cb.commit(); cb.waitUntilCompleted() }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        func luma(_ x: Int, _ y: Int) -> Float { let i = (y * w + x) * 4; return 0.2126 * Float(px[i + 2]) + 0.7152 * Float(px[i + 1]) + 0.0722 * Float(px[i]) }
        let pxPerMetre = Float(h) / 2 / (6 * tan(cam.fovY / 2))
        let cx = w / 2, cy = h / 2
        // The disc's pixels (radius 0.86 m) and the ring's (0.83 to 1.07 m): how many are at the top of the range in all three channels.
        var discN = 0, discHot = 0, ringN = 0, ringHot = 0
        for y in 0..<h { for x in 0..<w {
            let r = (Float(x - cx) * Float(x - cx) + Float(y - cy) * Float(y - cy)).squareRoot() / pxPerMetre
            let i = (y * w + x) * 4; let hot = px[i] >= 250 && px[i + 1] >= 250 && px[i + 2] >= 250
            if r < 0.8 { discN += 1; if hot { discHot += 1 } } else if r > 0.88 && r < 1.02 { ringN += 1; if hot { ringHot += 1 } }
        } }
        check(discN > 1000 && Float(discHot) < 0.01 * Float(discN) && Float(ringHot) < 0.01 * Float(ringN), "lenslook: rendered at 6 m the disc has \(discHot) of \(discN) pixels and the ring \(ringHot) of \(ringN) at white in all channels (under 1 % each)")
        let centre = luma(cx, cy), rimL = luma(cx + Int(0.68 * pxPerMetre), cy)
        check(centre > 1.15 * rimL, "lenslook: the disc is brighter at its heart than near its rim (luma \(Int(centre)) against \(Int(rimL)): a gradient, not a flat shape)")
    }
}
