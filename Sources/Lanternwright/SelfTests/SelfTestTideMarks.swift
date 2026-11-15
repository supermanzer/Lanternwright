import Foundation
import Metal
import simd

/// Self-tests: Phase A6 (S05.4 / Q80 / Q84): the plates' length bars at the door (bright and as wide as the plate), the tide gauges on both quays (the bars' heights are the sea's heights at B's three levels, the water
/// crosses them, a bar lights on the crossing and B's `TideMarks.set` holds it), each sluice room's answer line and the lamp that is lit while the room is wadeable. Run alone with `--selftest tidemarks`.
extension SelfTestRunner {
    func runTideMarks() {
        guard name == "all" || name == "tidemarks" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "tidemarks: no Metal device"); return }
        let terrain = Terrain(spec: .tideArchive)
        let P = Tide.period

        // ---- The door plates (A6): the longest bar is as wide as the plate, the three keep 1 : 2.1 : 3.7, and the bars are pale and lit by themselves.
        let lens = (0..<3).map { TonePlates.barLength($0) }
        check(abs(lens[2] - TonePlates.size.x) < 1e-5 && lens[0] > 0.08 && lens[1] > 1.9 * lens[0] && TonePlates.barH >= 0.06, "tidemarks: the plate bars are \(lens.map { String(format: "%.2f", $0) }.joined(separator: ", ")) m wide (the longest as wide as the plate, \(TonePlates.size.x) m) and \(TonePlates.barH) m thick")

        // ---- The gauges: bars at the sea's own heights, foot at the lowest water, top above the highest, a quay each.
        let h = (0..<3).map { TideMarks.height($0) }
        let spaced = h[0] > h[1] && h[1] > h[2] && h[0] - h[1] > 0.5 && h[1] - h[2] > 0.5 && h.allSatisfy { $0 > Tide.lowSea + 0.15 && $0 < Tide.highSea - 0.15 }
        var heightsOK = true
        for k in 0..<3 { if abs(TideMarks.height(k) - Tide.metres(Orrery.alignmentClock(k))) > 0.02 { heightsOK = false } }      // the water stands at bar k when the arm k aligns (B's matching clock)
        check(spaced && heightsOK, "tidemarks: the three bars stand at \(h.map { String(format: "%.2f", $0) }.joined(separator: ", ")) m (highest first, over 0.5 m apart, inside the sea's range) and the water is at each at its matching clock")
        for site in 0..<TideMarks.sites {
            let f = TideMarks.foot(site, terrain: terrain), q = TideMarks.quay(site)
            check(abs(f.x - q.x) < 1e-4 && f.z > q.z + 10 && f.z < q.z + 60 && f.y <= Tide.lowSea + 0.05 && f.y > Tide.lowSea - 0.6, "tidemarks: gauge \(site) stands \(String(format: "%.0f", f.z - q.z)) m seaward of its quay with its foot at \(String(format: "%.2f", f.y)) m (low water is \(Tide.lowSea))")
        }

        // ---- The water crosses each bar: twice a cycle, at B's matching clocks.
        var cross = [0, 0, 0]
        var t: Float = 0
        while t < 2 * P { let t1 = t + Game.tick; for k in 0..<3 where TideMarks.crossed(k, from: t, to: t1) { cross[k] += 1 }; t = t1 }
        var onTime = true
        for k in 0..<3 { let a = Orrery.alignmentClock(k); if !TideMarks.crossed(k, from: a - 0.05, to: a + 0.05) || TideMarks.crossed(k, from: a - 3, to: a - 1) { onTime = false } }
        check(cross == [4, 4, 4] && onTime, "tidemarks: the water crosses each bar twice a cycle (\(cross) in two cycles) and at the matching clock exactly")
        check(TideMarks.pulse(age: 0) == 1 && TideMarks.pulse(age: TideMarks.holdSeconds) == 1 && TideMarks.pulse(age: TideMarks.holdSeconds + TideMarks.fadeSeconds) == 0 && TideMarks.pulse(age: 2.5) < 1 && TideMarks.pulse(age: 2.5) > TideMarks.pulse(age: 3.5), "tidemarks: a mark's pulse holds \(TideMarks.holdSeconds) s then fades to nothing over \(TideMarks.fadeSeconds) s")

        // ---- In the scene: the gauge's bars glow on the crossing (driven by `ArchiveProps.update`), fade, and B's `set` holds one.
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 0; renderer.autoExposure = false; renderer.taaEnabled = false
        renderer.world = .tideArchive
        let scene = renderer.scene
        func emissive(_ site: Int, _ k: Int) -> Float { scene.items.first { $0.name == TideMarks.name(site, k) }?.uniforms.emissive.w ?? -1 }
        func lampGlow(_ k: Int) -> Float { scene.items.first { $0.name == WadeLamps.glowName(k) }?.uniforms.emissive.w ?? -1 }
        func run(from a: Float, to b: Float) { var c = a; while c < b { c += Game.tick; ArchiveProps.update(scene, time: c, ringAngle: nil, tableau: nil) } }
        ArchiveProps.update(scene, time: 20, ringAngle: nil, tableau: nil)          // the first update: a jump, no crossing
        let idle = (0..<2).flatMap { s in (0..<3).map { emissive(s, $0) } }
        run(from: 20, to: Orrery.alignmentClock(0) - 0.2)
        let before = emissive(0, 0)
        run(from: Orrery.alignmentClock(0) - 0.2, to: Orrery.alignmentClock(0) + 0.2)
        let during = (emissive(0, 0), emissive(1, 0), emissive(0, 1))
        run(from: Orrery.alignmentClock(0) + 0.2, to: Orrery.alignmentClock(0) + TideMarks.holdSeconds + TideMarks.fadeSeconds + 0.5)
        let after = emissive(0, 0)
        check(idle.allSatisfy { abs($0 - TideMarks.idleEmissive) < 1e-4 } && abs(before - TideMarks.idleEmissive) < 1e-4 && during.0 > 2.5 && during.1 > 2.5 && abs(during.2 - TideMarks.idleEmissive) < 1e-4 && abs(after - TideMarks.idleEmissive) < 1e-4,
              "tidemarks: every bar idles (\(TideMarks.idleEmissive)), bar 0 glows on both gauges as the water crosses it (\(String(format: "%.2f", during.0))) while bar 1 does not, and it is idle again after the fade (\(String(format: "%.2f", after)))")
        TideMarks.set(scene, 2, lit: 1); let both = (emissive(0, 2), emissive(1, 2))
        TideMarks.set(scene, 2, lit: 0, site: 1); let oneLeft = (emissive(0, 2), emissive(1, 2))
        TideMarks.set(scene, 2, lit: 0); let none = (emissive(0, 2), emissive(1, 2))
        TideMarks.set(scene, 7, lit: 1); TideMarks.set(scene, 0, lit: 1, site: 5)          // unknown bar or gauge: ignored
        check(both.0 > 2.5 && both.1 > 2.5 && oneLeft.0 > 2.5 && abs(oneLeft.1 - TideMarks.idleEmissive) < 1e-4 && abs(none.0 - TideMarks.idleEmissive) < 1e-4 && abs(none.1 - TideMarks.idleEmissive) < 1e-4 && abs(emissive(0, 0) - TideMarks.idleEmissive) < 1e-4,
              "tidemarks: B's set lights a bar on both gauges, on one by `site:`, releases it at 0, and ignores an unknown bar or gauge")

        // ---- The sluice rooms' answer lines and lamps.
        var lineOK = true
        for k in 0..<3 {
            let y = SluiceLines.aboveFloor(k), band = Tide.windows[k]
            let lo = Tide.metres(level: band.lowerBound) - ArchiveLayout.sluiceFloors[k], hi = Tide.metres(level: band.upperBound) - ArchiveLayout.sluiceFloors[k]
            if !(y > 0.03 && y >= lo - 0.01 && y <= hi + 0.01) || scene.items.first(where: { $0.name == SluiceLines.name(k) }) == nil { lineOK = false }
            if abs(Tide.metres(Orrery.alignmentClock(k)) - ArchiveLayout.sluiceFloors[k] - y) > 0.02 { lineOK = false }          // the room's water is at the line at the gate's clock
        }
        check(lineOK, "tidemarks: each sluice room's answer line stands \((0..<3).map { String(format: "%.2f", SluiceLines.aboveFloor($0)) }.joined(separator: ", ")) m over its floor, inside the gate's painted band, and the water is at it at the gate's clock")
        let share = (0..<3).map { k in Float((0..<900).filter { WadeLamps.lit(k, clock: Float($0) / 900 * P) }.count) / 900 }
        let sameAsRule = (0..<3).allSatisfy { k in (0..<90).allSatisfy { WadeLamps.lit(k, clock: Float($0)) == Tide.isWadeable(ground: ArchiveLayout.sluiceFloors[k], time: Float($0)) } }
        check(sameAsRule && share[2] < 0.35 && share[2] > 0.05 && share[0] > share[1] && share[1] > share[2] && WadeLamps.lit(2, clock: 0) && !WadeLamps.lit(2, clock: P / 2), "tidemarks: a room's lamp follows `Tide.isWadeable` (lit shares tide \(String(format: "%.2f", share[0])), wind \(String(format: "%.2f", share[1])), stone \(String(format: "%.2f", share[2]))): the stone room only near low water")
        run(from: 20, to: 25)
        ArchiveProps.update(scene, time: 0, ringAngle: nil, tableau: nil); let lowGlow = lampGlow(2)
        ArchiveProps.update(scene, time: P / 2, ringAngle: nil, tableau: nil); let highGlow = lampGlow(2)
        check(lowGlow > 2 && highGlow < 0.5, "tidemarks: the stone room's lamp glows at low water (\(String(format: "%.1f", lowGlow))) and goes dark at high (\(String(format: "%.1f", highGlow)))")
        var dry = true, clearOfWalk = true
        for k in 0..<3 {
            let p = WadeLamps.position(k, terrain: terrain)
            if p.y < Tide.highSea + 0.2 { dry = false }
            for i in 0..<(ArchiveLayout.sluiceWalk.count - 1) {
                let a = SIMD2(ArchiveLayout.sluiceWalk[i].x, ArchiveLayout.sluiceWalk[i].z), b = SIMD2(ArchiveLayout.sluiceWalk[i + 1].x, ArchiveLayout.sluiceWalk[i + 1].z), ab = b - a, q = SIMD2(p.x, p.z)
                let u = min(max(simd_dot(q - a, ab) / max(simd_dot(ab, ab), 1e-6), 0), 1)
                if simd_length(q - (a + ab * u)) < 1.5 { clearOfWalk = false }
            }
        }
        check(dry && clearOfWalk, "tidemarks: each wadeable lamp stands on ground above the highest sea and at least 1.5 m from the sluice walk")

        // ---- The guided walks stay clear of the new colliders (the gauges and the lamps).
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
        check(blocked == 0 && samples > 400, "tidemarks: the guided walks stay clear of every collider with the gauges and lamps in (\(samples) points, \(blocked) blocked)")

        // ---- Rendered: a lit bar is brighter than an idle one at the door-view distance, and the plate bars read pale at 8 m.
        let wpx = 640, hpx = 360
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: wpx, height: hpx, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc), let gaugeCam = Viewpoints.named("ta-marks0"), let plateCam = Viewpoints.named("lh-plates8") else { check(false, "tidemarks: no view"); return }
        func frame(_ cam: Camera, _ clock: Float) -> [UInt8]? {
            renderer.fixedTime = clock
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
        let c80 = Orrery.alignmentClock(2)
        for k in 0..<3 { TideMarks.set(scene, k, lit: 0) }
        guard let idleF = frame(gaugeCam, c80) else { check(false, "tidemarks: no frame"); return }
        for k in 0..<3 { TideMarks.set(scene, k, lit: 1) }
        guard let litF = frame(gaugeCam, c80) else { check(false, "tidemarks: no frame"); return }
        let px = changed(idleF, litF)
        check(px > 300, "tidemarks: from the plaza's edge at the stone bar's clock, lighting the marks changes \(px) pixels of the frame (640 x 360)")
        for k in 0..<3 { TideMarks.set(scene, k, lit: 0) }
        guard let low = frame(gaugeCam, c80), let high = frame(gaugeCam, 40) else { check(false, "tidemarks: no frame"); return }
        let moved = changed(low, high)
        check(moved > 5000, "tidemarks: the gauge's picture changes with the water (\(moved) pixels between the stone bar's clock and high water): the water is seen to cross the bars")
        guard let lineCam = Viewpoints.named("ta-sluice-line0") else { check(false, "tidemarks: no view"); return }
        guard let withLine = frame(lineCam, Orrery.alignmentClock(0)) else { check(false, "tidemarks: no frame"); return }
        scene.update(SluiceLines.name(0)) { $0.hidden = true }
        guard let noLine = frame(lineCam, Orrery.alignmentClock(0)) else { check(false, "tidemarks: no frame"); return }
        scene.update(SluiceLines.name(0)) { $0.hidden = false }
        let linePx = changed(withLine, noLine)
        check(linePx > 150, "tidemarks: in the tide room the answer line (pier and pipe plate) changes \(linePx) pixels of the frame (640 x 360): it stands out from the painted band")
        renderer.world = .varrow
        let barsName = "tone_plate_bars"
        guard let withBars = frame(plateCam, 12) else { check(false, "tidemarks: no frame"); return }
        renderer.scene.update(barsName) { $0.hidden = true }
        guard let without = frame(plateCam, 12) else { check(false, "tidemarks: no frame"); return }
        let barPx = changed(withBars, without)
        check(barPx > 40, "tidemarks: from 8 m the door plates' bars change \(barPx) pixels of the frame (640 x 360): they are seen, not just present")
    }
}
