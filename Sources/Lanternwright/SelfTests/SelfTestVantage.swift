import Foundation
import Metal
import simd

/// Self-tests: Phase A5 (S05.4): the door plates' signal-length bars, the two vantage stations (a terrain ray test and the rendered view from each), the orrery's brass tick (by numbers), the dome's slit
/// and the ledger room's floor. Run alone with `--selftest vantage`.
extension SelfTestRunner {
    func runVantage() {
        guard name == "all" || name == "vantage" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "vantage: no Metal device"); return }

        // ---- The door plates: a short, a middle and a long bar, in the beam's own proportions.
        let groups = Layout.Navigation.SignalPattern.groupSeconds, ranks = Layout.Navigation.SignalPattern.ranks
        let lens = (0..<3).map { TonePlates.barLength($0) }
        var rankOK = true
        for k in 0..<3 { if abs(lens[k] - groups[ranks.firstIndex(of: k)!] * TonePlates.barScale) > 1e-6 { rankOK = false } }       // plate k (tide, wind, stone) carries the length of the group of rank k
        let plateFits = lens.allSatisfy { $0 > 0.04 && $0 <= TonePlates.size.x + 1e-5 } && abs(TonePlates.barY) + TonePlates.barH / 2 <= TonePlates.size.y / 2
        check(lens[0] < lens[1] && lens[1] < lens[2] && rankOK && plateFits, "vantage: the plates' bars are short, middle, long (\(lens.map { String(format: "%.2f", $0) }.joined(separator: ", ")) m), each the length of the beam's group of its rank, and fit the plate")
        // Ratios: the bars keep the beam's proportions (long : short = 2.6 : 0.7), so the eye reads the same ratio the beam shows.
        check(abs(lens[2] / lens[0] - groups.max()! / groups.min()!) < 1e-4, "vantage: the long bar is \(String(format: "%.1f", lens[2] / lens[0])) times the short one, as the long flash is to the short")

        // ---- The stations: every target in line of sight over the terrain, with a margin, from the walked spot; and the test can say no.
        let terrain = Terrain(spec: .tideArchive)
        for k in 0..<Vantage.count {
            let s = Vantage.seen(k, terrain: terrain)
            check(s.visible == s.total && s.farthest < (k == 0 ? 45 : 75), "vantage: station \(k) sees \(s.visible) of \(s.total) targets over the terrain, the farthest \(String(format: "%.0f", s.farthest)) m off")
        }
        let o = ArchiveLayout.orrery
        let plain = ArchiveLayout.point(17, -18.24)
        let hiddenFromPlain = Vantage.targets(0).filter { !Vantage.clear(terrain, from: plain + SIMD3(0, Player.eyeHeight, 0), to: $0) }.count
        let blind = hiddenFromPlain >= 2
        let quayBlind = Vantage.targets(0).suffix(3).allSatisfy { !Vantage.clear(terrain, from: ArchiveLayout.lampEnd + SIMD3(0, Player.eyeHeight, 0), to: $0) }
        check(blind && quayBlind, "vantage: the ray test refuses the orrery's rim and arm points from the plain 80 m south (\(hiddenFromPlain) of 6 hidden by the rim) and the orrery's three points from the quay (its windows are in line of sight there, 230 m off: far, not hidden)")
        // The stand is on the walked line, the post beside it (not on it, not on a collider's footprint of the walk).
        func routeDistance(_ p: SIMD3<Float>) -> Float {
            var best = Float.infinity
            for i in 0..<(ArchiveLayout.path.count - 1) {
                let a = SIMD2(ArchiveLayout.path[i].x, ArchiveLayout.path[i].z), b = SIMD2(ArchiveLayout.path[i + 1].x, ArchiveLayout.path[i + 1].z), ab = b - a, q = SIMD2(p.x, p.z)
                let t = min(max(simd_dot(q - a, ab) / max(simd_dot(ab, ab), 1e-6), 0), 1)
                best = min(best, simd_length(q - (a + ab * t)))
            }
            return best
        }
        var standOK = true, postOK = true
        for k in 0..<Vantage.count {
            if routeDistance(ArchiveLayout.vantageStand[k]) > 0.5 { standOK = false }
            let d = routeDistance(ArchiveLayout.vantagePost(k))
            if d < 2.0 || d > 4.5 { postOK = false }
        }
        check(standOK && postOK, "vantage: each stand is on the walked line and each post 2-4.5 m beside it")
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 0; renderer.autoExposure = false; renderer.taaEnabled = false
        renderer.world = .tideArchive
        let scene = renderer.scene
        func item(_ n: String) -> DrawItem? { scene.items.first { $0.name == n } }
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
        check(blocked == 0 && samples > 400 && (0..<Vantage.count).allSatisfy { item(Vantage.name($0)) != nil }, "vantage: both posts are in the scene and the guided walks stay clear of every collider with them in (\(samples) points, \(blocked) blocked)")

        // ---- Rendered, from each stand, at full LookCloser: the windows' colours and the orrery's arm readable.
        let wpx = 640, hpx = 360
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: wpx, height: hpx, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc), let cam0 = Viewpoints.named("ta-vantage0-zoom"), let cam1 = Viewpoints.named("ta-vantage1-zoom"), let ledgerCam = Viewpoints.named("ta-ledger-in") else { check(false, "vantage: no target or view"); return }
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
        // Station 0: lighting the windows and moving the arms both change the picture (they are readable, not just present).
        Orrery.update(scene, clock: 5)
        for k in 0..<3 { DomeWindows.set(scene, k, lit: 0) }
        guard let dark0 = frame(cam0) else { check(false, "vantage: no frame"); return }
        for k in 0..<3 { DomeWindows.set(scene, k, lit: 1) }
        guard let lit0 = frame(cam0) else { check(false, "vantage: no frame"); return }
        Orrery.update(scene, clock: 40)
        guard let moved0 = frame(cam0) else { check(false, "vantage: no frame"); return }
        let winPx = changed(dark0, lit0), armPx = changed(lit0, moved0)
        check(winPx > 400 && armPx > 40, "vantage: from station 0 at full zoom lighting the windows changes \(winPx) pixels and turning the arms from clock 5 to 40 changes \(armPx) (640 x 360)")
        for k in 0..<3 { DomeWindows.set(scene, k, lit: 0) }
        Orrery.update(scene, clock: 5)
        // Station 1: the bays' glyph boards and the mast are in the frame: the picture is not sky and ground alone (the share of strongly saturated or bright pixels in the bays' band).
        guard let bays = frame(cam1) else { check(false, "vantage: no frame"); return }
        var board = 0
        for y in 100..<250 { for x in 100..<540 { let i = (y * wpx + x) * 4; let b = Int(bays[i]), g = Int(bays[i + 1]), r = Int(bays[i + 2]); if r > b + 25 && g > b + 15 { board += 1 } } }     // BGRA: warm oak and brass
        check(board > 6000, "vantage: from station 1 at full zoom the five bays' warm oak and brass fill the middle of the frame (\(board) warm pixels of 66 000)")

        // ---- The dome's slit: every bar lies along the shell, and the next begins where this one ends.
        var along = true, joined = true
        for k in 0..<12 {
            let bar = ArchiveProps.slitBar(k)
            let axis = SIMD2(sin(bar.turn), cos(bar.turn))                    // rotationX(t) sends y to (0, cos t, sin t): as (z, y) -> (sin t, cos t)
            let chord = simd_normalize(ArchiveProps.domePoint(k + 1, 0.35) - ArchiveProps.domePoint(k, 0.35))
            if simd_dot(axis, SIMD2(chord.x, chord.y)) < 0.9999 { along = false }
            let end = bar.mid + axis * ((bar.length - 0.02) / 2), next = ArchiveProps.slitBar(min(k + 1, 11)).mid - SIMD2(sin(ArchiveProps.slitBar(min(k + 1, 11)).turn), cos(ArchiveProps.slitBar(min(k + 1, 11)).turn)) * ((ArchiveProps.slitBar(min(k + 1, 11)).length - 0.02) / 2)
            if k < 11 && simd_length(end - next) > 1e-3 { joined = false }
        }
        check(along && joined, "vantage: the dome's twelve slit bars lie along the shell (not against it) and each starts where the last ends")

        // ---- The ledger room's floor reads as stone, not as dark ground: its mean brightness from the doorway is above 40 / 255 (it was 18-27).
        guard let room = frame(ledgerCam) else { check(false, "vantage: no frame"); return }
        var sum = 0, n = 0
        for y in 250..<340 { for x in 120..<520 { let i = (y * wpx + x) * 4; sum += Int(room[i]) + Int(room[i + 1]) + Int(room[i + 2]); n += 3 } }
        check(sum / max(n, 1) > 40, "vantage: the ledger room's floor (the lower third of the frame) averages \(sum / max(n, 1)) / 255, brighter than the old ground's 18-27")

        // ---- The brass tick, by numbers.
        let P = Tide.period
        var crossings = [0, 0, 0], held = 0
        var t: Float = 0
        while t < 2 * P { let t1 = t + Game.tick; for k in 0..<3 where Orrery.tickCrossed(k, from: t, to: t1) { crossings[k] += 1 }; t = t1 }
        check(crossings == [2, 2, 2], "vantage: each arm ticks once per tide cycle (\(crossings) in two cycles)")
        var onTime = true
        for k in 0..<3 { let a = Orrery.alignmentClock(k); if !Orrery.tickCrossed(k, from: a - 0.004, to: a + 0.004) || Orrery.tickCrossed(k, from: a + 0.004, to: a + 0.02) || Orrery.tickCrossed(k, from: a + P / 2 - 1, to: a + P / 2 + 1) { onTime = false } }
        scene.archive.armStops[1] = 0
        held = Orrery.ticks(scene, from: Orrery.alignmentClock(1) - 0.01, to: Orrery.alignmentClock(1) + 0.01).count + Orrery.ticks(scene, from: Orrery.alignmentClock(0) - 0.01, to: Orrery.alignmentClock(0) + 0.01).count
        scene.archive.armStops[1] = nil
        check(onTime && held == 1, "vantage: a tick falls exactly at the arm's alignment moment, and a held arm does not tick (\(held) of the two tested)")
        let g = [Float(0), 6, 8, 20, 40, 55].map { Orrery.tickGain(distance: $0) }
        check(g[0] == 1 && g[1] == 1 && g[2] == 1 && g[3] > 0.3 && g[3] < 0.8 && g[4] == 0 && g[5] == 0 && g[2] >= g[3] && g[3] >= g[4], "vantage: the tick is full within 8 m of the orrery, half by 20 m and gone by 40 m (\(g.map { String(format: "%.2f", $0) }.joined(separator: ", ")))")
        let sr: Float = 44100
        func render(_ seconds: Float, _ events: [ArchiveAudio.Event]) -> [Float] {
            let a = ArchiveAudio(sampleRate: sr); a.wet = 0
            var q = ArchiveAudio.Inputs(); q.active = false; a.setInputs(q)
            for e in events { a.handle(e) }
            var left = [Float](repeating: 0, count: Int(sr * seconds)), right = left
            var i = 0
            while i < left.count { let n = min(512, left.count - i); left.withUnsafeMutableBufferPointer { lp in right.withUnsafeMutableBufferPointer { rp in a.render(frames: n, left: lp.baseAddress! + i, right: rp.baseAddress! + i) } }; i += n }
            return left
        }
        func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }
        var tickOK = true, detail = ""
        for k in 0..<3 {
            let x = render(0.5, [.tick(k, gain: 1)]), early = rms(x[0..<Int(sr * 0.05)]), late = rms(x[Int(sr * 0.25)..<x.count]), peak = x.map { abs($0) }.max() ?? 0
            let f0 = OrreryTone.hz(k), inBand = FootstepAnalysis.power(x, f0) > FootstepAnalysis.power(x, f0 * 0.5) * 4
            if !(early > 0.003 && late < 1e-6 && peak < 0.5 && inBand && OrreryTone.hz(k) >= 1000 && OrreryTone.hz(k) * OrreryTone.ratios.last! < 8000) { tickOK = false }
            detail += String(format: " %.0f Hz: early %.4f peak %.3f;", f0, early, peak)
        }
        let quiet = render(0.3, [.tick(0, gain: 0)]), none = render(0.3, [])
        check(tickOK && rms(quiet[0..<quiet.count]) < 1e-6 && rms(none[0..<none.count]) < 1e-6, "vantage: the tick sounds in the first 50 ms, is gone by 0.25 s, peaks under 0.5, sits at its own pitch and is silent at gain 0 or with no event:\(detail)")
        check(OrreryTone.hz(0) < OrreryTone.hz(1) && OrreryTone.hz(1) < OrreryTone.hz(2), "vantage: the three arms tick at three pitches, rising with the arm's length")
    }
}
