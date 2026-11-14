import Foundation
import Metal
import simd

/// Self-tests: the mirror court's three receiving crystals (P02.1 / F10 A2) and the line of sight to the lighthouse signal (P02.3).
extension SelfTestRunner {
    func runReceiverGlow() {
        guard name == "all" || name == "receiverglow" else { return }
        // The cells: three distinct, inside the court, clear of every mirror, pane and the prism (B2: the cells are MirrorCourt.receivers).
        let taken = MirrorCourt.mirrorCells + MirrorCourt.paneCells + [MirrorCourt.source]
        let cells = ReceiverGlow.cells
        check(cells.count == 3 && Set(cells.map { $0.c * 10 + $0.r }).count == 3 && cells.allSatisfy { cell in (0..<MirrorCourt.size).contains(cell.c) && (0..<MirrorCourt.size).contains(cell.r) && !taken.contains(where: { $0 == cell }) }, "receiverglow: three distinct crystal cells \(cells), inside the court and clear of the mirrors, panes, prism and old orb")
        // The curve: dormant is dim, the level lifts it smoothly to the lit strength, blaze beats a single hit, the colour follows the pane.
        let strengths = [0, 0.25, 0.5, 0.75, 1].map { ReceiverGlow.emissive(level: Float($0), color: SIMD3(1, 0, 0), blaze: false).w }
        check(zip(strengths, strengths.dropFirst()).allSatisfy { $0 < $1 } && abs(strengths[0] - ReceiverGlow.dormantStrength) < 1e-4 && abs(strengths[4] - ReceiverGlow.litStrength) < 1e-4 && ReceiverGlow.blazeStrength > 1.5 * ReceiverGlow.litStrength,
              "receiverglow: strength \(strengths.map { String(format: "%.2f", $0) }) rises from dormant to lit, and the solved blaze is \(ReceiverGlow.blazeStrength)")
        let cyan = ReceiverGlow.emissive(level: 1, color: GlassPuzzleProps.color(0), blaze: false), amber = ReceiverGlow.emissive(level: 1, color: GlassPuzzleProps.color(2), blaze: false)
        check(simd_length(SIMD3(cyan.x, cyan.y, cyan.z) - SIMD3(amber.x, amber.y, amber.z)) > 0.4 && ReceiverGlow.emissive(level: 0, color: GlassPuzzleProps.color(0), blaze: false).x < 0.4, "receiverglow: a lit crystal shows the colour the pane gave the beam, a dormant one none")
        // The items exist in the Glass Wood, start dormant, give no shadow when lit-only... and `set` drives each one alone.
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "receiverglow: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 12; renderer.autoExposure = false; renderer.taaEnabled = false
        renderer.world = .glassWood
        let scene = renderer.scene
        func item(_ n: String) -> DrawItem? { scene.items.first { $0.name == n } }
        check(ReceiverGlow.allNames.allSatisfy { item($0) != nil && item($0)!.uniforms.emissive.w < 0.5 }, "receiverglow: three crystals and three rings exist in the Glass Wood and start dormant")
        ReceiverGlow.set(scene, 1, level: 1, color: GlassPuzzleProps.color(1))
        check(abs(item(ReceiverGlow.name(1))!.uniforms.emissive.w - ReceiverGlow.litStrength) < 1e-4 && item(ReceiverGlow.name(0))!.uniforms.emissive.w < 0.5 && item(ReceiverGlow.name(2))!.uniforms.emissive.w < 0.5 && item(ReceiverGlow.ringName(1))!.uniforms.emissive.w > 1, "receiverglow: set(1, level 1) lights crystal 1 and its ring and leaves 0 and 2 dormant")
        ReceiverGlow.set(scene, 9, level: 1); ReceiverGlow.set(scene, 1, level: 0)
        check(item(ReceiverGlow.name(1))!.uniforms.emissive.w < 0.5, "receiverglow: an unknown index is ignored and level 0 darkens the crystal again")
        // Rendered: the crystal seen from 6 m is brighter lit than dormant, and brighter still blazing (the centre of the view is the crystal).
        let w = 400, h = 225
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc), let cam = Viewpoints.named("gw-crystal0") else { check(false, "receiverglow: no target or view"); return }
        func luma(level: Float, blaze: Bool) -> Float? {
            for k in 0..<3 { ReceiverGlow.set(scene, k, level: level, color: GlassPuzzleProps.color(k), blaze: blaze) }
            for _ in 0..<2 { guard let cb = renderer.queue.makeCommandBuffer() else { return nil }; renderer.encode(commandBuffer: cb, target: tex, camera: cam); cb.commit(); cb.waitUntilCompleted() }
            var px = [UInt8](repeating: 0, count: w * h * 4)
            tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            var s: Float = 0
            for y in (h / 2 - 8)..<(h / 2 + 8) { for x in (w / 2 - 4)..<(w / 2 + 4) { let i = (y * w + x) * 4; s += 0.2126 * Float(px[i + 2]) + 0.7152 * Float(px[i + 1]) + 0.0722 * Float(px[i]) } }
            return s / 128
        }
        guard let l0 = luma(level: 0, blaze: false), let l1 = luma(level: 0.5, blaze: false), let l2 = luma(level: 1, blaze: false), let l3 = luma(level: 1, blaze: true) else { check(false, "receiverglow: no frame"); return }
        check(l0 + 20 < l2 && l1 > l0 && l1 < l2 + 1 && l3 >= l2 - 1, "receiverglow: the crystal's centre luma rises with the level: dormant \(Int(l0)), half \(Int(l1)), lit \(Int(l2)), blazing \(Int(l3))")
    }

    /// P02.3: can the lighthouse signal be SEEN from the dock approach? A terrain ray test from eye height along the dock and the beach path to the lens and to the beam's far end (the beam
    /// is flashed at the door heading), clear of the ground by half a metre all the way. (Trees are checked in the frames, see docs/INSPECT.md.)
    func runSignalSight() {
        guard name == "all" || name == "signalsight" else { return }
        let terrain = Scene.makeWorld(device: MTLCreateSystemDefaultDevice()!).terrain!
        let lens = Landmarks.lensPosition
        let door = BeamSignal.doorHeading
        let beamEnd = lens + SIMD3(sin(door), 0, -cos(door)) * 30
        func clear(from eye: SIMD3<Float>, to target: SIMD3<Float>) -> Float {
            var worst = Float.infinity
            let n = Int(simd_length(target - eye))
            for i in 1..<max(n, 2) { let p = eye + (target - eye) * (Float(i) / Float(n)); worst = min(worst, p.y - terrain.sampleHeight(x: p.x, z: p.z)) }
            return worst
        }
        let s = Layout.dockShore, e = Layout.dockEnd
        var dockOK = 0, dockN = 0, worstDock = Float.infinity
        for i in 0...10 {
            let t = Float(i) / 10, p = s + (e - s) * t, eye = SIMD3(p.x, p.y + Player.eyeHeight, p.z)
            dockN += 1
            let c = min(clear(from: eye, to: lens), clear(from: eye, to: beamEnd)); worstDock = min(worstDock, c)
            if c > 0.5 { dockOK += 1 }
        }
        check(dockOK == dockN, "signalsight: the lens and the beam's far end are above the terrain from all \(dockN) points along the dock (worst clearance \(String(format: "%.1f", worstDock)) m)")
        // The beach path from the dock's land end toward the tide stone: how far along can the lens still be seen (reported, and at least the first 20 m).
        let tide = Layout.tideStone
        var seen: Float = 0
        for i in 0...20 {
            let t = Float(i) / 20, p = s + (tide - s) * t
            let g = terrain.sampleHeight(x: p.x, z: p.z), eye = SIMD3(p.x, g + Player.eyeHeight, p.z)
            if clear(from: eye, to: lens) > 0.5 { seen = t * simd_length(SIMD2(tide.x - s.x, tide.z - s.z)) } else { break }
        }
        check(seen >= 20, "signalsight: walking from the dock's landward end toward the tide stone the lens stays above the terrain for the first \(Int(seen)) m")
    }
}
