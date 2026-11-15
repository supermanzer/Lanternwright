import Foundation
import Metal
import simd

/// Self-tests: Oren's site in the Tide Archive (S05.2): the dome's orrery (arms as a pure function of the tide clock, the collar), the dome's windows, the prism's inputs, the dormant models seen from the quays,
/// and that the route stays walkable round them (World/OrenSite.swift). Run alone with `--selftest orensite`.
extension SelfTestRunner {
    func runOrenSite() {
        guard name == "all" || name == "orensite" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "orensite: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 0; renderer.autoExposure = false; renderer.taaEnabled = false
        renderer.world = .tideArchive
        let scene = renderer.scene
        func item(_ n: String) -> DrawItem? { scene.items.first { $0.name == n } }
        let P = Tide.period

        // ---- The arms are a pure function of the tide clock.
        var pure = true, cyc = true, hits = true
        for k in 0..<Orrery.armCount { for t in stride(from: Float(0), to: 2 * P, by: 3.7) {
            if Orrery.armAngle(k, clock: t) != Orrery.armAngle(k, clock: t) { pure = false }
            if abs(Orrery.wrap(Orrery.armAngle(k, clock: t) - Orrery.armAngle(k, clock: t + P))) > 1e-3 { cyc = false }
        } }
        for k in 0..<Orrery.armCount {
            let a = Orrery.alignmentClock(k)
            if abs(Orrery.wrap(Orrery.armAngle(k, clock: a) - Orrery.bearing(k))) > 1e-3 || !Orrery.aligned(k, clock: a) || Orrery.aligned(k, clock: a + P / 2) { hits = false }
        }
        check(pure && cyc && hits, "orensite: arm angle is a pure function of the clock, repeats every tide cycle and points at its window exactly at alignmentClock(k)")
        // Each alignment is on the FALLING tide, at the level its gate answers at, and they come tide, wind, stone.
        var order = true, falling = true
        for k in 0..<3 {
            let a = Orrery.alignmentClock(k)
            if abs(Tide.level(a) - IlseTones.matchLevel(k)) > 0.01 || Tide.rate(a) >= 0 { falling = false }
            if k > 0 && Orrery.alignmentClock(k) <= Orrery.alignmentClock(k - 1) { order = false }
        }
        check(falling && order, "orensite: the arms line up as the falling tide passes each gate's level (\((0..<3).map { String(format: "%.1f", Orrery.alignmentClock($0)) }.joined(separator: ", ")) s), in the order tide, wind, stone")
        // One alignment per arm per cycle, about 2 x tolerance / (2 pi / period) seconds long, and the three bearings are distinct.
        var windows: [Int] = [], lengths: [Float] = []
        for k in 0..<3 {
            var n = 0, was = Orrery.aligned(k, clock: 0), len: Float = 0
            for i in 1...Int(P * 20) { let t = Float(i) * 0.05, now = Orrery.aligned(k, clock: t); if now && !was { n += 1 }; if now { len += 0.05 }; was = now }
            windows.append(n); lengths.append(len)
        }
        let spread = (0..<3).map { Orrery.bearing($0) }
        check(windows == [1, 1, 1] && lengths.allSatisfy { $0 > 2 && $0 < 4.5 } && abs(spread[0] - spread[1]) > 0.1 && abs(spread[1] - spread[2]) > 0.1,
              "orensite: each arm lines up with its window once per cycle for \(lengths.map { String(format: "%.1f", $0) }.joined(separator: ", ")) s; the three bearings are distinct")

        // ---- Layout: the new solids clear of every walked line; the collar and the arms reachable on foot.
        func clearOf(_ p: SIMD2<Float>, _ feet: Float) -> Bool {
            !scene.colliders.cylinders.contains { c in feet < c.maxY && feet + 1.8 > c.minY && simd_length(p - c.center) < c.radius + Player.radius - 0.05 }
        }
        var blocked = 0, samples = 0
        for leg in [ArchiveLayout.path, ArchiveLayout.eastApproach] {
            for s in 0..<(leg.count - 1) {
                let a = leg[s], b = leg[s + 1], n = max(2, Int(simd_length(SIMD2(b.x - a.x, b.z - a.z)) / 0.5))
                for i in 0...n {
                    let q = a + (b - a) * (Float(i) / Float(n)), p = SIMD2(q.x, q.z)
                    if ArchiveLayout.sluiceSites.contains(where: { simd_length($0 - p) < 2.0 }) { continue }
                    if simd_length(p - SIMD2(ArchiveLayout.dome.x, ArchiveLayout.dome.z)) < 10.5 || simd_length(p - SIMD2(ArchiveLayout.prismChamber.x, ArchiveLayout.prismChamber.z)) < 1.5 { continue }
                    samples += 1
                    if !clearOf(p, scene.groundHeight(x: p.x, z: p.y)) { blocked += 1 }
                }
            }
        }
        check(blocked == 0 && samples > 400, "orensite: the guided walks stay clear of every collider with the orrery, the mast and the spire in (\(samples) points, \(blocked) blocked)")
        let o = ArchiveLayout.orrery
        let orreryRoute = scene.terrain.pathDistance(x: o.x, z: o.z)
        let reach = SIMD2(o.x - (Orrery.plinthRadius + 0.25 + Player.radius + 0.15), o.z)
        check(orreryRoute > 8 && clearOf(reach, o.y) && simd_length(SIMD2(reach.x - o.x, reach.y - o.z)) < 2.4 + Orrery.plinthRadius, "orensite: the orrery stands \(String(format: "%.1f", orreryRoute)) m off the route and a player can stand at its plinth, \(String(format: "%.1f", simd_length(SIMD3(reach.x - o.x, 1.6, reach.y - o.z)))) m from the collar")
        var flat: [Float] = []
        for i in -3...3 { for j in -3...3 { flat.append(scene.terrain.sampleHeight(x: o.x + Float(i) * 0.5, z: o.z + Float(j) * 0.5)) } }
        check((flat.max() ?? 0) - (flat.min() ?? 0) < 0.15, "orensite: the orrery's footing is flat (spread \(String(format: "%.2f", (flat.max() ?? 0) - (flat.min() ?? 0))) m)")
        // The grass-free disc covers the ledger room's whole floor (S05.1's Found: grass came up through the slab).
        let rm = ArchiveLayout.ledgerRoom, h = ArchiveLayout.ledgerHalf
        let covered = [SIMD2<Float>(-1, -1), SIMD2(1, -1), SIMD2(-1, 1), SIMD2(1, 1)].allSatisfy { c in
            ArchiveLayout.bareDiscs.contains { simd_length(SIMD2(rm.x + c.x * h.x, rm.z + c.y * h.y) - $0.center) < $0.radius - 0.1 }
        }
        check(covered, "orensite: the ledger room's four corners lie inside a grass-free disc")
        // A8: and the apron in front of the door: the sill and the ground 2 m out from it are inside a disc well enough that the soft edge has not begun (radius - 0.8).
        let door = ArchiveLayout.ledgerDoor
        let apron = [0.0, 1.0, 2.0].allSatisfy { dz in ArchiveLayout.bareDiscs.contains { simd_length(SIMD2(door.x, door.z + Float(dz)) - $0.center) < $0.radius - 0.8 } }
        check(apron, "orensite: the ledger door's sill and the apron 2 m out lie inside a grass-free disc (A8)")

        // ---- The calls B makes.
        let t0: Float = 20
        Orrery.update(scene, clock: t0)
        let run0 = (0..<3).map { item(Orrery.armName($0))!.uniforms.model }
        Orrery.update(scene, clock: t0 + 10)
        let run1 = (0..<3).map { item(Orrery.armName($0))!.uniforms.model }
        check((0..<3).allSatisfy { run0[$0] != run1[$0] } && run1[0] == Orrery.armModel(0, angle: Orrery.armAngle(0, clock: t0 + 10)), "orensite: the arms follow the clock, and what is drawn is armAngle")
        Orrery.hold(scene, 1, at: t0)
        Orrery.update(scene, clock: t0 + 25)
        let held = (0..<3).map { item(Orrery.armName($0))!.uniforms.model }
        check(held[1] == run0[1] && held[0] != run1[0] && held[2] == Orrery.armModel(2, angle: Orrery.armAngle(2, clock: t0 + 25)), "orensite: hold stops arm 1 where it was at the held clock; the other arms keep running")
        Orrery.hold(scene, 1, at: nil); Orrery.update(scene, clock: t0 + 25)
        check(item(Orrery.armName(1))!.uniforms.model == Orrery.armModel(1, angle: Orrery.armAngle(1, clock: t0 + 25)), "orensite: hold(nil) lets the arm run again")
        Orrery.hold(scene, 7, at: 3); Orrery.hold(scene, -1, at: 3)
        check(scene.archive.armStops == [nil, nil, nil], "orensite: an unknown arm is ignored")
        let c0 = item(Orrery.collarName)!.uniforms.model
        Orrery.setCollar(scene, detent: 1)
        let c1 = item(Orrery.collarName)!.uniforms.model
        Orrery.setCollar(scene, detent: Orrery.collarDetents)
        func near(_ a: float4x4, _ b: float4x4) -> Bool { simd_length(a.columns.0 - b.columns.0) + simd_length(a.columns.1 - b.columns.1) + simd_length(a.columns.2 - b.columns.2) + simd_length(a.columns.3 - b.columns.3) < 1e-3 }
        check(!near(c1, c0) && near(item(Orrery.collarName)!.uniforms.model, c0) && near(c1, Orrery.collarModel(detent: 1)), "orensite: the collar turns one detent and comes back round after \(Orrery.collarDetents)")
        // An aligned arm glows more than a running one.
        Orrery.update(scene, clock: Orrery.alignmentClock(0))
        let hot = item(Orrery.armName(0))!.uniforms.emissive.w
        Orrery.update(scene, clock: Orrery.alignmentClock(0) + P / 2)
        check(hot > item(Orrery.armName(0))!.uniforms.emissive.w * 2, "orensite: an arm that is lined up with its window glows")
        DomeWindows.set(scene, 0, lit: 0); DomeWindows.set(scene, 1, lit: 0); DomeWindows.set(scene, 2, lit: 0)
        let dark = (0..<3).map { item(DomeWindows.name($0))!.uniforms.emissive.w }, spireDark = item(DormantViews.spireName)!.uniforms.emissive.w
        DomeWindows.set(scene, 1, lit: 1)
        let one = item(DomeWindows.name(1))!.uniforms.emissive.w, spireOne = item(DormantViews.spireName)!.uniforms.emissive.w
        DomeWindows.set(scene, 0, lit: 1); DomeWindows.set(scene, 2, lit: 1)
        let spireAll = item(DormantViews.spireName)!.uniforms.emissive.w
        DomeWindows.set(scene, 9, lit: 1)
        check(dark.allSatisfy { $0 == 0 } && one > 2 && item(DomeWindows.name(0))!.uniforms.emissive.w > 2 && spireDark == 0 && spireOne > 0 && spireAll > spireOne * 2.5, "orensite: a window lights on its own call, the spire beside the dome glows with the windows (\(String(format: "%.2f", spireOne)) with one, \(String(format: "%.2f", spireAll)) with three)")
        // Default, then the inputs: every component as before S05; a dark window dims its component and leaves its mark dark.
        PrismInputs.set(scene, lit: [true, true, true])
        let full = (0..<3).map { item(ArchiveProps.beamOutName($0))!.uniforms.emissive.w }, beamIn3 = item(ArchiveProps.beamInName)!.uniforms.emissive.w
        PrismInputs.set(scene, lit: [true, false, false])
        let part = (0..<3).map { item(ArchiveProps.beamOutName($0))!.uniforms.emissive.w }, beamIn1 = item(ArchiveProps.beamInName)!.uniforms.emissive.w
        PrismInputs.set(scene, lit: [true, true, true])
        check(full == [5, 5, 5] && beamIn3 == 5 && part[0] == 5 && part[1] == PrismInputs.ghostStrength && part[2] == PrismInputs.ghostStrength && beamIn1 < beamIn3, "orensite: all three windows give the pre-S05 prism; a dark window leaves its component a dim ghost and the white beam weaker")

        // ---- Rendered, from walking distance.
        let wpx = 640, hpx = 360
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: wpx, height: hpx, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc), let orreryCam = Viewpoints.named("ta-orrery-top"), let winCam = Viewpoints.named("ta-windows"), let prismCam = Viewpoints.named("ta-prism-inputs"), let quayCam = Viewpoints.named("ta-quay-dome") else { check(false, "orensite: no target or view"); return }
        func frame(_ cam: Camera) -> [UInt8]? {
            for _ in 0..<2 { guard let cb = renderer.queue.makeCommandBuffer() else { return nil }; renderer.encode(commandBuffer: cb, target: tex, camera: cam); cb.commit(); cb.waitUntilCompleted() }
            var px = [UInt8](repeating: 0, count: wpx * hpx * 4)
            tex.getBytes(&px, bytesPerRow: wpx * 4, from: MTLRegionMake2D(0, 0, wpx, hpx), mipmapLevel: 0)
            return px
        }
        func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
            var n = 0
            for i in stride(from: 0, to: a.count, by: 4) { if abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 60 { n += 1 } }
            return n
        }
        Orrery.update(scene, clock: 5)
        guard let early = frame(orreryCam) else { check(false, "orensite: no frame"); return }
        Orrery.update(scene, clock: 40)
        guard let mid = frame(orreryCam) else { check(false, "orensite: no frame"); return }
        Orrery.update(scene, clock: 5)
        guard let again = frame(orreryCam) else { check(false, "orensite: no frame"); return }
        let moved = changed(early, mid), same = changed(early, again)
        check(moved > 1500 && same == 0, "orensite: from 2.5 m the arms are in different places at clock 5 and 40 (\(moved) pixels differ) and back in the same place at clock 5 (\(same) differ)")
        for k in 0..<3 { DomeWindows.set(scene, k, lit: 0) }
        guard let winDark = frame(winCam) else { check(false, "orensite: no frame"); return }
        for k in 0..<3 { DomeWindows.set(scene, k, lit: 1) }
        guard let winLit = frame(winCam) else { check(false, "orensite: no frame"); return }
        check(changed(winDark, winLit) > 800, "orensite: from the orrery the three lit windows change \(changed(winDark, winLit)) pixels of the dome")
        PrismInputs.set(scene, lit: [false, false, false])
        guard let prismDim = frame(prismCam) else { check(false, "orensite: no frame"); return }
        PrismInputs.set(scene, lit: [true, true, true])
        guard let prismFull = frame(prismCam) else { check(false, "orensite: no frame"); return }
        check(changed(prismDim, prismFull) > 400, "orensite: in the chamber the three components change \(changed(prismDim, prismFull)) pixels between no window and three")
        for k in 0..<3 { DomeWindows.set(scene, k, lit: 0) }
        guard let quayDark = frame(quayCam) else { check(false, "orensite: no frame"); return }
        for k in 0..<3 { DomeWindows.set(scene, k, lit: 1) }
        guard let quayLit = frame(quayCam) else { check(false, "orensite: no frame"); return }
        check(changed(quayDark, quayLit) > 30, "orensite: from the west quay (230 m) the spire beside the dome shows dark or glowing (\(changed(quayDark, quayLit)) pixels)")
    }
}
