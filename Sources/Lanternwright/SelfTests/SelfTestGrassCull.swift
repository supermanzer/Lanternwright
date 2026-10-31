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
            let was = GrassField.cullEnabled
            GrassField.cullEnabled = culled
            defer { GrassField.cullEnabled = was }
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
        // G10.G.2: the far field does not twinkle. Walk the camera 0.028 m a frame (the shimmer tool's pace) and compare, frame to frame, which far cells the pass keeps. A cell that is
        // kept in one frame and not the next is a blade that popped in or out: the old per-blade distance thinning made 102 in the 60 steps below, the chunk fade makes none (a blade that is
        // beyond reach has no height, it is not dropped). The region is a fixed patch of world, 0.55 to 0.85 of the draw radius ahead of the first camera, well inside the view.
        do {
            renderer.world = .varrow
            renderer.fixedTime = 12
            let n = renderer.grassField.cellsPerSide, cell = LookDefaults.grassCell, radius = LookDefaults.grassRadius
            let start = SIMD3<Float>(30, 36.0, 60), steps = 60, stride: Float = 0.028
            let cells = renderer.device.makeBuffer(length: n * n * 4, options: .storageModeShared)!, base = renderer.device.makeBuffer(length: 8, options: .storageModeShared)!
            func keptSet(_ z: Float) -> Set<Int64> {
                let cam = Camera(position: SIMD3(start.x, start.y, z), yaw: 0, pitch: -0.25)
                _ = shot(renderer, cam, culled: true)
                let count = renderer.grassField.survivorCount(queue: renderer.queue)
                guard count > 0, let cb = renderer.queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { return [] }
                blit.copy(from: renderer.grassField.cells, sourceOffset: 0, to: cells, destinationOffset: 0, size: count * 4)
                blit.copy(from: renderer.grassField.gridBase, sourceOffset: 0, to: base, destinationOffset: 0, size: 8)
                blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
                let b = base.contents().bindMemory(to: Int32.self, capacity: 2), ids = cells.contents().bindMemory(to: UInt32.self, capacity: count)
                var out = Set<Int64>()
                for k in 0..<count {
                    let ix = Int(ids[k]) % n, iz = Int(ids[k]) / n
                    let gx = Int(b[0]) + ix, gz = Int(b[1]) + iz
                    let dx = (Float(gx) + 0.5) * cell - start.x, dz = (Float(gz) + 0.5) * cell - start.z          // from the first camera (cell centres: the blade is within a cell of it)
                    let d = (dx * dx + dz * dz).squareRoot()
                    if d >= 0.55 * radius && d <= 0.85 * radius && -dz > 0.94 * d { out.insert(Int64(gx) << 32 | Int64(UInt32(bitPattern: Int32(gz)))) }      // 20 degrees either side of north
                }
                return out
            }
            var previous = keptSet(start.z), flips = 0, seen = previous.count
            for k in 1...steps {
                let now = keptSet(start.z - Float(k) * stride)
                flips += previous.symmetricDifference(now).count
                seen += now.count
                previous = now
            }
            check(seen > 0, "grass fade: the far patch holds blades to compare (\(seen / (steps + 1)) kept cells a frame)")
            if name == "grasscull" { print("grass fade: \(flips) cells popped in or out of the far patch over \(steps) steps of \(stride) m (\(seen / (steps + 1)) kept a frame)") }
            check(flips == 0, "grass fade: no far cell pops in or out as the camera walks (\(flips) did in \(steps) steps; the per-blade thinning it replaced popped 102 in the same walk)")
        }
        // G10.G.3: the near-field blade LOD (off by default): at each level the culling pass and the vertex shader still agree to the byte, and fewer blades are kept near the eye.
        do {
            let was = GrassShaders.nearLOD
            defer { GrassShaders.nearLOD = was }
            var perLevel: [Int] = []
            for level in [0, 1, 2] {
                GrassShaders.nearLOD = level
                let lr = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"])); lr.autoExposure = false
                lr.world = .varrow; lr.fixedTime = 12
                let cam = Camera(position: SIMD3(30, 34.4, 60), yaw: 2.2, pitch: -0.3)                    // eye near the ground: most of the kept cells are within 14 m
                _ = shot(lr, cam, culled: true)
                let all = shot(lr, cam, culled: false), culled = shot(lr, cam, culled: true)
                check(!all.isEmpty && all == culled, "grass LOD \(level): the frame is byte-identical with and without the culling pass")
                perLevel.append(lr.grassField.survivorCount(queue: lr.queue))
            }
            check(perLevel.count == 3 && perLevel[1] < perLevel[0] && perLevel[2] < perLevel[1], "grass LOD: level 1 keeps fewer cells than 0 and level 2 fewer than 1 with the eye at the ground (\(perLevel))")
        }
        let looking = kept.filter { $0.0.hasPrefix("varrow yaw") }.map(\.1)
        check((looking.max() ?? total) < total * 6 / 10, "grass cull: with the view turned any way round the meadow, at most 60 % of the cells survive (\(looking.max() ?? 0) of \(total))")
    }
}
