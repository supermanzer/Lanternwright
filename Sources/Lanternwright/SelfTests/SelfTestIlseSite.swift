import Foundation
import Metal
import simd

/// Self-tests: Ilse's site in the Tide Archive (S05.1): the shelf bays, the ledger room and the bell pipes (World/IlseSite.swift), their sound (Audio/IlseAudio.swift, ArchiveAudio), and that the route
/// stays walkable round them. The sound has not been heard by a person: it is judged here by numbers (energy in 300-1200 Hz, the pitch of each bell, how a sour bell differs, the beat rate of a pipe against the fork).
extension SelfTestRunner {
    func runIlseSite() {
        guard name == "all" || name == "ilsesite" else { return }
        typealias A = FootstepAnalysis
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "ilsesite: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 0; renderer.autoExposure = false; renderer.taaEnabled = false
        renderer.world = .tideArchive
        let scene = renderer.scene
        func item(_ n: String) -> DrawItem? { scene.items.first { $0.name == n } }

        // ---- Layout: bays on stack units, the room clear of the route and flat, the pipes clear of everything the player uses.
        let unitsFound = (0..<ShelfBays.count).filter { k in
            let p = ArchiveLayout.bayXZ(k)
            return [Float(-0.9), 0.9].allSatisfy { dz in scene.colliders.cylinders.contains { simd_length($0.center - SIMD2(p.x, p.y + dz)) < 0.01 && abs($0.radius - 0.7) < 0.01 } }
        }.count
        check(unitsFound == ShelfBays.count && ShelfBays.count == 5, "ilsesite: all five bays stand on a unit of the stacks' first row (\(unitsFound) of \(ShelfBays.count) found by their colliders)")
        let rm = ArchiveLayout.ledgerRoom, half = ArchiveLayout.ledgerHalf
        var lo = Float.infinity, hi = -Float.infinity, nearest = Float.infinity
        for i in -4...4 { for j in -4...4 {
            let x = rm.x + Float(i) / 4 * (half.x + 0.5), z = rm.z + Float(j) / 4 * (half.y + 0.5)
            let h = scene.terrain.sampleHeight(x: x, z: z); lo = min(lo, h); hi = max(hi, h)
            nearest = min(nearest, scene.terrain.pathDistance(x: x, z: z))
        } }
        check(hi - lo < 0.2 && nearest > 3.0, "ilsesite: the ledger room stands on flat ground (spread \(String(format: "%.2f", hi - lo)) m) and its walls are \(String(format: "%.1f", nearest)) m from the walked route, clear of its grass-free strip")
        var pipeOK = true
        for k in 0..<3 {
            let c = ArchiveLayout.sluices[k], p = ArchiveLayout.pipe(k), wheel = ArchiveProps.sluiceWheelModel(k, turns: 0).columns.3
            let off = SIMD2(p.x - c.x, p.z - c.z)
            let toWheel = simd_length(SIMD2(p.x - wheel.x, p.z - wheel.z)), toLamp = simd_length(SIMD2(p.x, p.z) - SIMD2(SluiceLamps.position(k).x, SluiceLamps.position(k).z))
            if !(simd_length(off) < ArchiveLayout.sluiceFlat - 1 && toWheel > 2 && toLamp > 1.5 && abs(off.x) > 1.5 && off.y > 2) { pipeOK = false }
        }
        check(pipeOK, "ilsesite: each pipe stands inside its sluice room's flat floor, away from the wheel and the lamp and off the gate's approach line")

        // ---- The route stays walkable: no collider within a player's reach of any point of the guided walks (the gates' centres, the dome and the prism's pedestal excepted: those are older than this phase).
        func clearOf(_ p: SIMD2<Float>, _ feet: Float) -> Bool {
            !scene.colliders.cylinders.contains { c in feet < c.maxY && feet + 1.8 > c.minY && simd_length(p - c.center) < c.radius + Player.radius - 0.05 }
        }
        var blocked = 0, samples = 0
        let gates = ArchiveLayout.sluiceSites
        // Each sluice room's own approaches too: from the south edge of its flat floor to the front of the gate, to the wheel and to the lamp (the sluice walk's straight legs run through the rooms' walls, so they are not the test).
        var legs = [ArchiveLayout.path, ArchiveLayout.eastApproach]
        for k in 0..<3 {
            let c = ArchiveLayout.sluices[k], wheel = ArchiveProps.sluiceWheelModel(k, turns: 0).columns.3, lamp = SluiceLamps.position(k)
            for end in [SIMD3(c.x, c.y, c.z + 1.4), SIMD3(wheel.x - 0.7, c.y, wheel.z + 0.7), SIMD3(lamp.x + 0.8, c.y, lamp.z + 0.8)] { legs.append([SIMD3(c.x, c.y, c.z + 9), end]) }
        }
        for leg in legs {
            for s in 0..<(leg.count - 1) {
                let a = leg[s], b = leg[s + 1], n = max(2, Int(simd_length(SIMD2(b.x - a.x, b.z - a.z)) / 0.5))
                for i in 0...n {
                    let q = a + (b - a) * (Float(i) / Float(n)), p = SIMD2(q.x, q.z)
                    if gates.contains(where: { simd_length($0 - p) < 2.0 }) { continue }
                    if simd_length(p - SIMD2(ArchiveLayout.dome.x, ArchiveLayout.dome.z)) < 10.5 || simd_length(p - SIMD2(ArchiveLayout.prismChamber.x, ArchiveLayout.prismChamber.z)) < 1.5 { continue }          // the route's waypoints at the dome and the prism (their solid centres are older than this phase and the route goes round them)
                    samples += 1
                    if !clearOf(p, scene.groundHeight(x: p.x, z: p.y)) { blocked += 1; if ProcessInfo.processInfo.environment["PROBE"] != nil { let c = scene.colliders.cylinders.first { simd_length(p - $0.center) < $0.radius + Player.radius - 0.05 }!; print("blocked at \(p) by \(c.center) r \(c.radius)") } }
                }
            }
        }
        check(blocked == 0 && samples > 500, "ilsesite: the guided walks stay clear of every collider with the new props in (\(samples) points, \(blocked) blocked)")
        // The doorway: open, a straight walk from the route into the room to the page's desk and the key's stand is clear; shut, it is blocked at the door.
        func walkClear(to target: SIMD3<Float>) -> Bool {          // from the route, straight at the door, in to 1.2 m inside it, then on to the target
            let door = ArchiveLayout.ledgerDoor, legs = [SIMD2(door.x, door.z + 3.0), SIMD2(door.x, door.z - 1.0), SIMD2(target.x, target.z)]
            return (0..<2).allSatisfy { l in (0...40).allSatisfy { i in let p = legs[l] + (legs[l + 1] - legs[l]) * (Float(i) / 40); return clearOf(p, ArchiveLayout.ledgerRoom.y) } }
        }
        let pageFront = ArchiveLayout.ledgerPage + SIMD3(0, 0, 1.1), keyFront = ArchiveLayout.ledgerKey + SIMD3(0, 0, 0.9)
        check(!walkClear(to: pageFront) && !walkClear(to: keyFront), "ilsesite: with the door shut the room cannot be walked into")
        LedgerRoom.setDoor(scene, open: 1)
        check(walkClear(to: pageFront) && walkClear(to: keyFront), "ilsesite: with the door open the player walks in to the page's desk and the key's stand (the straight line is clear of every collider)")
        let after1 = scene.colliders.cylinders.count
        LedgerRoom.setDoor(scene, open: 1)
        LedgerRoom.setDoor(scene, open: 0.7)
        check(scene.colliders.cylinders.count == after1, "ilsesite: opening the door again does not touch the colliders twice")
        LedgerRoom.setDoor(scene, open: 0)
        LedgerRoom.setDoor(scene, open: 0.2)
        check(scene.colliders.cylinders.count == after1 + 1 && !walkClear(to: pageFront), "ilsesite: shutting the door puts exactly one collider back")
        LedgerRoom.setDoor(scene, open: 0)
        check(abs((item(LedgerRoom.doorName)?.uniforms.model.columns.3.y ?? 99) - ArchiveLayout.ledgerDoor.y) < 1e-4, "ilsesite: a shut door stands on the floor (open sinks it \(LedgerRoom.doorDrop) m)")
        LedgerRoom.setDoor(scene, open: 1)
        check((item(LedgerRoom.doorName)?.uniforms.model.columns.3.y ?? 99) < ArchiveLayout.ledgerDoor.y - 2.0, "ilsesite: an open door has sunk below the floor")

        // ---- The one-call APIs.
        check((ShelfBays.allNames + BellPipes.allNames + [LedgerRoom.roomName, LedgerRoom.doorName, LedgerRoom.keyName]).allSatisfy { item($0) != nil }, "ilsesite: every named item exists in the Archive")
        ShelfBays.set(scene, 1, look: .warm, swing: 0.8)
        ShelfBays.set(scene, 2, look: .sour)
        let w = item(ShelfBays.glyphName(1))!.uniforms.emissive, s = item(ShelfBays.glyphName(2))!.uniforms.emissive, d = item(ShelfBays.glyphName(0))!.uniforms.emissive
        check(w.w > 1.2 && w.x > w.z * 4 && s.y > s.x && s.w > d.w * 2 && d.w < 0.5 && abs(w.w - s.w) > 0.2, "ilsesite: a warm bay glows amber (\(w.w)), a sour one green (\(s.w)), a dormant one stays dim (\(d.w))")
        let swung = item(ShelfBays.bellName(1))!.uniforms.model, rest = item(ShelfBays.bellName(0))!.uniforms.model
        check(simd_length(SIMD3(swung.columns.2.x, swung.columns.2.y, swung.columns.2.z) - SIMD3(rest.columns.2.x, rest.columns.2.y, rest.columns.2.z)) > 0.2, "ilsesite: swing rocks the bell about its bracket")
        ShelfBays.set(scene, 9, look: .warm); BellPipes.set(scene, 9, level: 1)
        check(item(ShelfBays.glyphName(1))!.uniforms.emissive.w > 1.2, "ilsesite: an unknown index is ignored")
        BellPipes.set(scene, 0, level: 0.25); BellPipes.set(scene, 1, level: 0.75, agree: 1)
        let h0 = item(BellPipes.waterName(0))!.uniforms.model.columns.1.y, h1 = item(BellPipes.waterName(1))!.uniforms.model.columns.1.y
        check(abs(h0 - (0.25 * BellPipes.columnHeight + 0.01)) < 1e-3 && abs(h1 - (0.75 * BellPipes.columnHeight + 0.01)) < 1e-3, "ilsesite: the water column's height follows the level (\(String(format: "%.2f", h0)) m at 25 %, \(String(format: "%.2f", h1)) m at 75 %)")
        check(item(BellPipes.crownName(1))!.uniforms.emissive.w > item(BellPipes.crownName(0))!.uniforms.emissive.w * 5, "ilsesite: the crown ring lights as the fork and pipe agree")

        // ---- Rendered: from walking distance, a warm bay differs from a dormant one and the pipe's water shows.
        let wpx = 640, hpx = 360
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: wpx, height: hpx, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc), let bayCam = Viewpoints.named("ta-bay1"), let pipeCam = Viewpoints.named("ta-pipe0") else { check(false, "ilsesite: no target or view"); return }
        func frame(_ cam: Camera) -> [UInt8]? {
            for _ in 0..<2 { guard let cb = renderer.queue.makeCommandBuffer() else { return nil }; renderer.encode(commandBuffer: cb, target: tex, camera: cam); cb.commit(); cb.waitUntilCompleted() }
            var px = [UInt8](repeating: 0, count: wpx * hpx * 4)
            tex.getBytes(&px, bytesPerRow: wpx * 4, from: MTLRegionMake2D(0, 0, wpx, hpx), mipmapLevel: 0)
            return px
        }
        func changed(_ a: [UInt8], _ b: [UInt8]) -> (count: Int, red: Float, green: Float, blue: Float) {
            var n = 0; var r: Float = 0, g: Float = 0, bl: Float = 0
            for i in stride(from: 0, to: a.count, by: 4) {
                let d = abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
                if d > 60 { n += 1; r += Float(b[i + 2]) - Float(a[i + 2]); g += Float(b[i + 1]) - Float(a[i + 1]); bl += Float(b[i]) - Float(a[i]) }
            }
            return (n, r / Float(max(n, 1)), g / Float(max(n, 1)), bl / Float(max(n, 1)))
        }
        for k in 0..<ShelfBays.count { ShelfBays.set(scene, k, look: .dormant) }
        guard let dormantBay = frame(bayCam) else { check(false, "ilsesite: no frame"); return }
        for k in 0..<ShelfBays.count { ShelfBays.set(scene, k, look: .warm) }
        guard let warmBay = frame(bayCam) else { check(false, "ilsesite: no frame"); return }
        for k in 0..<ShelfBays.count { ShelfBays.set(scene, k, look: .sour) }
        guard let sourBay = frame(bayCam) else { check(false, "ilsesite: no frame"); return }
        let cw = changed(dormantBay, warmBay), cs = changed(dormantBay, sourBay)
        check(cw.count > 400 && cw.red > cw.blue + 15 && cs.count > 300 && cs.green > cs.red + 5 && cs.green > cs.blue,
              "ilsesite: from 3.5 m a warm bay's frame changes by \(cw.count) pixels toward amber (red +\(Int(cw.red)), blue +\(Int(cw.blue))), a sour one by \(cs.count) toward green (green +\(Int(cs.green)), red +\(Int(cs.red)))")
        BellPipes.set(scene, 0, level: 0.1)
        guard let lowPipe = frame(pipeCam) else { check(false, "ilsesite: no frame"); return }
        BellPipes.set(scene, 0, level: 0.9)
        guard let highPipe = frame(pipeCam) else { check(false, "ilsesite: no frame"); return }
        let cp = changed(lowPipe, highPipe)
        check(cp.count > 500, "ilsesite: from 4.5 m the pipe's water column visibly climbs from 10 % to 90 % (\(cp.count) pixels change)")

        // ---- Sound, as numbers.
        let sr: Float = 44100
        func render(_ seconds: Float, inputs: ArchiveAudio.Inputs, events: [(Float, ArchiveAudio.Event)] = []) -> [Float] {
            let a = ArchiveAudio(sampleRate: sr)
            a.wet = 0
            a.setInputs(inputs)
            var left = [Float](repeating: 0, count: Int(sr * seconds)), right = left
            var pending = events.sorted { $0.0 < $1.0 }
            var i = 0
            while i < left.count {
                let n = min(512, left.count - i)
                while let first = pending.first, Float(i) / sr >= first.0 { a.handle(first.1); pending.removeFirst() }
                left.withUnsafeMutableBufferPointer { lp in right.withUnsafeMutableBufferPointer { rp in a.render(frames: n, left: lp.baseAddress! + i, right: rp.baseAddress! + i) } }
                i += n
            }
            return left
        }
        func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }
        /// The share of a tone's energy that sits in 280-1300 Hz, measured at the exact frequency of each partial the voice is made of (a 40 Hz grid would miss a narrow tone).
        func inBand(_ x: [Float], partials: [Float]) -> Float {
            let p = partials.map { A.power(x, $0) }, inside = zip(partials, p).filter { $0.0 >= 280 && $0.0 <= 1300 }.reduce(0) { $0 + $1.1 }
            return inside / max(p.reduce(0, +), 1e-12)
        }
        // Inputs with the Archive layers silent (the drone, the drips and the tide are measured elsewhere): only what is under test sounds.
        var quiet = ArchiveAudio.Inputs(); quiet.active = false
        var bellsOK = true, report = ""
        for k in 0..<ShelfBays.count {
            let sweet = render(2.5, inputs: quiet, events: [(0, .bell(k, sour: false))]), sour = render(2.5, inputs: quiet, events: [(0, .bell(k, sour: true))])
            let peak = sweet.map { abs($0) }.max() ?? 0, peakS = sour.map { abs($0) }.max() ?? 0
            let f = IlseTones.bellHz(k), fS = f * pow(2, IlseTones.sourCents / 1200)
            let own = A.power(Array(sweet[0..<Int(sr)]), f), others = (0..<5).filter { $0 != k }.map { A.power(Array(sweet[0..<Int(sr)]), IlseTones.bellHz($0)) }.max() ?? 0
            let sourFlat = A.power(Array(sour[0..<Int(sr)]), fS) > 2 * A.power(Array(sour[0..<Int(sr)]), f) && own > 2 * A.power(Array(sweet[0..<Int(sr)]), fS)
            let decaySweet = rms(sweet[Int(1.0 * sr)..<Int(1.5 * sr)]) / max(rms(sweet[0..<Int(0.5 * sr)]), 1e-9), decaySour = rms(sour[Int(1.0 * sr)..<Int(1.5 * sr)]) / max(rms(sour[0..<Int(0.5 * sr)]), 1e-9)
            let frac = inBand(Array(sweet[0..<Int(1.5 * sr)]), partials: IlseTones.bellRatios.map { $0 * f }), fracS = inBand(Array(sour[0..<Int(1.5 * sr)]), partials: IlseTones.sourRatios.map { $0 * fS } + [fS + IlseTones.sourTwinHz])
            if !(peak > 0.04 && peak < 0.6 && peakS > 0.04 && peakS < 0.6 && own > 3 * others && sourFlat && decaySweet > 1.6 * decaySour && frac > 0.8 && fracS > 0.7) { bellsOK = false }
            report += " \(Int(f.rounded()))Hz: peak \(String(format: "%.2f", peak)), \(Int(100 * frac)) % in band, sour \(Int(100 * fracS)) %;"
        }
        check(bellsOK, "ilsesite: every bell strikes audibly without clipping, rings its own pitch (the Glass Wood pillar's), keeps its energy in 280-1300 Hz, and the sour one is flat, beats and dies at half the length:\(report)")
        check(zip(ToneTable.glassHz, ToneTable.glassHz.dropFirst()).allSatisfy { $0 < $1 } && [0, 2, 4].allSatisfy { k in ToneTable.stoneHz.contains { abs($0 - IlseTones.bellHz(k)) < 0.01 } }, "ilsesite: bays 0, 2 and 4 ring the stones' own tones (so the stones' tones identify the bells)")
        // The pipe: pitch follows the water, matches the fork at the gate's level, stays in range; the voice is silent without the input.
        var pitchOK = true
        for k in 0..<3 {
            let hz = (0...10).map { IlseTones.pipeHz(k, level: Float($0) / 10) }
            if !(zip(hz, hz.dropFirst()).allSatisfy { $0 < $1 } && abs(IlseTones.pipeHz(k, level: IlseTones.matchLevel(k)) - ToneTable.stoneHz[k]) < 0.01 && hz.min()! > 180 && hz.max()! < 1300 && Tide.windows[k].contains(IlseTones.matchLevel(k))) { pitchOK = false }
        }
        check(pitchOK, "ilsesite: each pipe's pitch rises with the water, equals the stones' tone k at the middle of gate k's window, and stays within 180-1300 Hz")
        check(IlseTones.agreement(pipeHz: 440, forkHz: 440.4) == 1 && IlseTones.agreement(pipeHz: 440, forkHz: 450) == 0 && IlseTones.agreement(pipeHz: 440, forkHz: 443) > 0.2 && IlseTones.agreement(pipeHz: 440, forkHz: 443) < 0.8, "ilsesite: agreement is 1 inside a hertz and 0 at eight apart")
        var withPipe = quiet
        withPipe.pipe = ArchiveAudio.Pipe(hz: 440, gain: 1)
        var without = withPipe; without.pipe = nil
        let pOn = render(2, inputs: withPipe), pOff = render(2, inputs: without)
        check(A.power(Array(pOn[Int(sr)...]), 440) > 8 * A.power(Array(pOff[Int(sr)...]), 440) && rms(pOn[Int(sr)...]) < 0.2, "ilsesite: the pipe sounds its pitch only while the input is set, quietly (RMS \(String(format: "%.3f", rms(pOn[Int(sr)...]))))")
        let p293 = render(2, inputs: { var i = withPipe; i.pipe = ArchiveAudio.Pipe(hz: ToneTable.stoneHz[0], gain: 1); return i }())
        let frac293 = inBand(Array(p293[Int(sr)...]), partials: [1, 2, 3].map { $0 * ToneTable.stoneHz[0] })
        check(frac293 > 0.5, "ilsesite: even the lowest pipe (the stones' D4, 293.7 Hz) has \(Int(100 * frac293)) % of its energy in 280-1300 Hz (its harmonics carry it for a laptop speaker)")
        // Beats: the pipe against the fork held (a stone's tone, A4 = 440 Hz). The loudness envelope's strongest wobble is the frequency difference, and it stops as they agree.
        func envelope(delta: Float) -> [Float] {
            var i = quiet; i.waterDistance = 1000
            i.pipe = ArchiveAudio.Pipe(hz: ToneTable.stoneHz[1] + delta, gain: 1)
            let x = render(9, inputs: i, events: [(0, .fork(1, on: true))])
            let e = A.onePoleLow(x.map { abs($0) }, 12)
            let tail = Array(e[Int(2 * sr)...]), mean = tail.reduce(0, +) / Float(tail.count)
            return tail.map { $0 - mean }
        }
        func lowPower(_ e: [Float], _ f: Float) -> Float {                            // a direct DFT of the envelope (decimated to 441 Hz, in Double: a Goertzel in Float is unstable at these rates and lengths)
            var c = 0.0, sn = 0.0, n = 0.0
            for i in stride(from: 0, to: e.count, by: 100) { let t = Double(i) / Double(sr); c += Double(e[i]) * cos(2 * Double.pi * Double(f) * t); sn += Double(e[i]) * sin(2 * Double.pi * Double(f) * t); n += 1 }
            return Float((c * c + sn * sn) / (n * n))
        }
        let e4 = envelope(delta: 4), e2 = envelope(delta: 2), e0 = envelope(delta: 0.2)
        func centroid(_ e: [Float]) -> Float {                                       // the envelope's mean wobble rate (Hz) over 0.25-8 Hz
            var num: Float = 0, den: Float = 0
            for f in stride(from: Float(0.25), through: 8, by: 0.25) { let p = lowPower(e, f); num += f * p; den += p }
            return num / max(den, 1e-12)
        }
        let c4 = centroid(e4), c2 = centroid(e2), c0 = centroid(e0)
        check(lowPower(e4, 4) > 3 * lowPower(e4, 2) && lowPower(e2, 2) > 3 * lowPower(e2, 4) && c4 > c2 + 0.8 && c2 > c0 + 0.5 && c0 < 1.2 && abs(c4 - 4) < 1.2 && abs(c2 - 2) < 1.2,
              "ilsesite: the pipe beats against the fork at the difference of their pitches and the beats slow to nothing as they agree (mean wobble \(String(format: "%.1f", c4)) Hz at 4 Hz apart, \(String(format: "%.1f", c2)) at 2, \(String(format: "%.1f", c0)) at 0.2; the fork's own two tines wobble at 0.6 Hz, so that is the floor)")
    }
}
