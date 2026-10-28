import Foundation
import Metal
import simd

/// Self-tests: the grass culling pass (G10.G.1) changes nothing a player can see. Every camera below is rendered twice, with the culling pass and with every cell drawn
/// (the pre-G10.G.1 path), and the two frames must match byte for byte. The cameras are the ones that could expose a margin that is too small: looking along, across and away
/// from the meadow, steeply down and up, with the wind blowing, in both worlds. It also reports how many of the 73,984 cells the pass keeps.
extension SelfTestRunner {
    func runGrassCull() {
        guard name == "all" || name == "grass" || name == "grasscull" else { return }
        let w = 480, h = 270
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { check(false, "grass cull: could not make a target"); return }
        func shot(_ renderer: Renderer, _ cam: Camera, culled: Bool) -> [UInt8] {
            GrassField.cullEnabled = culled
            defer { GrassField.cullEnabled = true }
            guard let cb = renderer.queue.makeCommandBuffer() else { return [] }
            renderer.encode(commandBuffer: cb, target: tex, camera: cam)
            cb.commit(); cb.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: w * h * 4)
            tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            return px
        }
        struct Spot { var label: String; var world: WorldKind; var eye: SIMD3<Float>; var yaw: Float; var pitch: Float }
        var spots: [Spot] = []
        for k in 0..<8 { spots.append(Spot(label: "varrow yaw \(k * 45)", world: .varrow, eye: SIMD3(30, 36.0, 60), yaw: Float(k) * .pi / 4, pitch: -0.25)) }       // all the way round, so every edge of the view is tried
        spots += [Spot(label: "varrow straight down", world: .varrow, eye: SIMD3(30, 36.0, 60), yaw: 0.7, pitch: -1.45),
                  Spot(label: "varrow up", world: .varrow, eye: SIMD3(30, 36.0, 60), yaw: 2.2, pitch: 0.9),
                  Spot(label: "varrow eye at the ground", world: .varrow, eye: SIMD3(30, 34.4, 60), yaw: 2.2, pitch: -0.05),
                  Spot(label: "varrow 15 m up", world: .varrow, eye: SIMD3(30, 49.0, 60), yaw: 2.2, pitch: -0.25)]
        for k in 0..<4 { spots.append(Spot(label: "glass wood yaw \(k * 90)", world: .glassWood, eye: SIMD3(-14.5, 10.8, 105.9), yaw: -0.12 + Float(k) * .pi / 2, pitch: -0.13)) }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.autoExposure = false
        var identical = 0, differing: [String] = [], kept: [(String, Int)] = []
        for (i, s) in spots.enumerated() {
            renderer.world = s.world
            renderer.fixedTime = 12 + Float(i) * 0.37                                       // a different gust at every spot
            let cam = Camera(position: s.eye, yaw: s.yaw, pitch: s.pitch)
            _ = shot(renderer, cam, culled: true)                                          // a frame to settle what the first frame of a world sets up (the sky bake)
            let all = shot(renderer, cam, culled: false)
            let culled = shot(renderer, cam, culled: true)
            kept.append((s.label, renderer.grassField.survivorCount(queue: renderer.queue)))
            if !all.isEmpty && all == culled { identical += 1 } else { differing.append(s.label) }
        }
        check(differing.isEmpty, "grass cull: \(identical) of \(spots.count) frames are byte-identical with and without the culling pass (differing: \(differing))")
        let n = renderer.grassField.cellsPerSide, total = n * n
        if name == "grasscull" { for (l, k) in kept { print("grass cull: \(l): \(k) of \(total) cells kept (\(String(format: "%.1f", 100 * Float(k) / Float(total))) %)") } }
        check(kept.allSatisfy { $0.1 >= 0 && $0.1 < total }, "grass cull: the pass keeps fewer than all \(total) cells in every view (most: \(kept.map(\.1).max() ?? 0))")
        let looking = kept.filter { $0.0.hasPrefix("varrow yaw") }.map(\.1)
        check((looking.max() ?? total) < total * 6 / 10, "grass cull: with the view turned any way round the meadow, at most 60 % of the cells survive (\(looking.max() ?? 0) of \(total))")
    }
}
