import Foundation
import Metal
import simd

/// Self-tests: audio.
extension SelfTestRunner {
    func runAudio() {
        if name == "all" || name == "audio" {
            let sr: Float = 44100
            let n = Int(sr) * 10
            func renderSeconds(_ setup: (AmbienceSynth) -> Void) -> [Float] {
                let synth = AmbienceSynth(sampleRate: sr)
                setup(synth)
                var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    // Render in 512-frame blocks like the real audio callback does.
                    var done = 0
                    while done < n {
                        let c = min(512, n - done)
                        synth.render(frames: c, left: lp.baseAddress! + done, right: rp.baseAddress! + done)
                        done += c
                    }
                } }
                return l
            }
            func rms(_ a: ArraySlice<Float>) -> Float { (a.reduce(0) { $0 + $1 * $1 } / Float(a.count)).squareRoot() }
            let wind = renderSeconds { $0.windGain = 0.6; $0.surfGain = 0 }
            let surf = renderSeconds { $0.windGain = 0; $0.surfGain = 0.8 }
            let everything = renderSeconds { $0.windGain = 1; $0.surfGain = 1; $0.master = 1; $0.stepSurface = .wood; $0.stepCounter = 1 }
            check(!wind.contains { !$0.isFinite } && !surf.contains { !$0.isFinite }, "wind and surf contain no NaN/inf")
            check(rms(wind[...]) > 0.005 && rms(wind[...]) < 0.4, "wind level is audible but not loud (rms \(String(format: "%.3f", rms(wind[...]))))")
            check(rms(surf[...]) > 0.005 && rms(surf[...]) < 0.4, "surf level is audible but not loud (rms \(String(format: "%.3f", rms(surf[...]))))")
            check((everything.map { abs($0) }.max() ?? 2) < 1.0, "everything at full volume never clips (peak \(String(format: "%.2f", everything.map { abs($0) }.max() ?? 0)))")
            // Surf should swell: compare the loudest and quietest second.
            let secs = (0..<10).map { rms(surf[($0 * Int(sr))..<(($0 + 1) * Int(sr))]) }
            check(secs.max()! > 1.5 * secs.min()!, "surf swells and recedes (loudest second \(String(format: "%.3f", secs.max()!)) vs quietest \(String(format: "%.3f", secs.min()!)))")
            // Surf must not sound like static. White noise has |x[n]-x[n-1]| / |x[n]| of about 1.41; a signal whose energy
            // sits under ~1 kHz has about 0.14. (The old surf, with a cutoff up to 4 kHz, was far hissier.)
            let surfTone = renderSeconds { $0.windGain = 0; $0.surfGain = 0.8 }
            var dSq: Float = 0, xSq: Float = 0
            for i in 1..<surfTone.count { let d = surfTone[i] - surfTone[i - 1]; dSq += d * d; xSq += surfTone[i] * surfTone[i] }
            let hiss = (dSq / xSq).squareRoot()
            check(hiss < 0.35, "surf is a low wash, not static (hissiness \(String(format: "%.2f", hiss)); white noise is about 1.41)")

            // Footsteps.
            func step(_ surface: SurfaceKind, run: Bool, count: Int = 1) -> [Float] {
                let synth = AmbienceSynth(sampleRate: sr)
                synth.windGain = 0; synth.surfGain = 0; synth.master = 1
                var l = [Float](repeating: 0, count: Int(sr) * 2 * count), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    for k in 0..<count {
                        synth.stepSurface = surface; synth.stepRun = run; synth.stepCounter += 1
                        synth.render(frames: Int(sr) * 2, left: lp.baseAddress! + k * Int(sr) * 2, right: rp.baseAddress! + k * Int(sr) * 2)
                    }
                } }
                return l
            }
            func peak(_ x: ArraySlice<Float>) -> Float { x.map { abs($0) }.max() ?? 0 }
            /// Seconds until the envelope (peak per 5 ms window) falls below 15 % of the loudest window.
            func ringOut(_ x: [Float]) -> Float {
                let w = Int(sr * 0.005)
                let env = stride(from: 0, to: x.count - w, by: w).map { peak(x[$0..<$0 + w]) }
                let top = env.max() ?? 1
                let iTop = env.firstIndex(of: top) ?? 0
                let end = (iTop..<env.count).first { env[$0] < 0.15 * top } ?? env.count
                return Float(end) * 0.005
            }
            for surface in [SurfaceKind.grass, .sand, .earth, .rock, .stone, .wood] {
                let walk = step(surface, run: false)
                check(peak(walk[0..<Int(sr * 0.001)]) < 0.3 * peak(walk[0..<Int(sr * 0.4)]) && !walk.contains { !$0.isFinite }, "\(surface) step has a soft attack (first millisecond is not the peak) and is finite")
                check(peak(walk[Int(sr * 1.5)...]) < 1e-4, "\(surface) step dies away completely")
            }
            let walkGrass = step(.grass, run: false), runGrass = step(.grass, run: true)
            check(ringOut(walkGrass) >= 0.12, "a grass footstep rings out for at least 0.12 s, not a click (\(String(format: "%.2f", ringOut(walkGrass))) s)")
            let walkStone = step(.stone, run: false), runStone = step(.stone, run: true)
            check(peak(runStone[...]) > 1.2 * peak(walkStone[...]) && ringOut(runStone) < ringOut(walkStone),
                  "a run step is harder and shorter than a walk step (peak \(String(format: "%.2f", peak(walkStone[...]))) -> \(String(format: "%.2f", peak(runStone[...]))), ring-out \(String(format: "%.2f", ringOut(walkStone))) -> \(String(format: "%.2f", ringOut(runStone))) s)")
            // The walk has a second, softer hit (the toe) after the heel.
            let heel = peak(walkGrass[0..<Int(sr * 0.06)]), toe = peak(walkGrass[Int(sr * 0.075)..<Int(sr * 0.2)])
            check(toe > 0.15 * heel && toe < heel, "walking is heel then toe (toe is \(Int(100 * toe / heel)) % of the heel)")
            // Consecutive steps differ.
            let two = step(.grass, run: false, count: 2)
            let first = peak(two[0..<Int(sr * 2)]), second = peak(two[Int(sr * 2)...])
            check(abs(first - second) / max(first, second) > 0.01, "consecutive steps are not identical (peaks \(String(format: "%.3f", first)) vs \(String(format: "%.3f", second)))")
        }
        if name == "all" || name == "sonic" {
            typealias SL = SonicLandmarks
            let tide = StoneID.tide.position
            check(SL.falloff(0, ref: 8, range: 60) > 0.99 && SL.falloff(8, ref: 8, range: 60) > 0.4 && SL.falloff(60, ref: 8, range: 60) == 0 && SL.falloff(500, ref: 8, range: 60) == 0, "falloff: full at the source, about half at the reference distance, exactly zero at and beyond the range")
            var prev: Float = 2; var monotone = true
            for d in stride(from: Float(0), through: 70, by: 0.5) { let f = SL.falloff(d, ref: 8, range: 60); if f > prev + 1e-6 { monotone = false }; prev = f }
            check(monotone, "falloff never increases with distance")
            let near = SL.levels(listener: tide + SIMD3(3, 0, 0), yaw: 0, world: .varrow, lighthouseLit: false)
            let far = SL.levels(listener: tide + SIMD3(40, 0, 0), yaw: 0, world: .varrow, lighthouseLit: false)
            check(near.hum.x > far.hum.x && near.hum.x > 0.5 && near.hum.y == 0 && near.hum.z == 0, "the tide stone hums loud beside it and faintly at 40 m; the other stones are silent from here")
            check(near.hum.w == 0 && SL.levels(listener: tide, yaw: 0, world: .varrow, lighthouseLit: true).hum.w > 0.01 && SL.levels(listener: Layout.dockEnd, yaw: 0, world: .varrow, lighthouseLit: true).hum.w > 0.001, "the lighthouse carries a tone only once lit, and it reaches the dock")
            let dock = SL.levels(listener: Layout.dockEnd, yaw: Layout.spawnYaw, world: .varrow, lighthouseLit: false)
            check(dock.buoy > 0.05 && SL.levels(listener: Layout.summitStone, yaw: 0, world: .varrow, lighthouseLit: false).buoy == 0, "the bell buoy is audible from the dock and gone from the summit")
            check(SL.levels(listener: Layout.dockEnd, yaw: 0, world: .glassWood, lighthouseLit: true) == SL.Levels(), "no Varrow sounds in the Glass Wood")
            // Panning: facing north (yaw 0), a source to the east is on the right, to the west on the left, ahead is centred.
            check(SL.pan(listener: .zero, yaw: 0, source: SIMD3(10, 0, 0)) > 0.8 && SL.pan(listener: .zero, yaw: 0, source: SIMD3(-10, 0, 0)) < -0.8 && abs(SL.pan(listener: .zero, yaw: 0, source: SIMD3(0, 0, -10))) < 0.01, "pan: east is right, west is left, straight ahead is centred (facing north)")
            check(SL.pan(listener: .zero, yaw: .pi / 2, source: SIMD3(0, 0, -10)) < -0.8, "pan follows the head: facing east, north is on the left")
            let galleryNear = SL.levels(listener: Layout.lighthouse + SIMD3(8, 0, 0), yaw: 0, world: .varrow, lighthouseLit: false).gallery
            check(galleryNear > 0.3 && SL.levels(listener: Layout.lighthouse + SIMD3(80, 0, 0), yaw: 0, world: .varrow, lighthouseLit: false).gallery == 0, "wind sings round the lighthouse close to it and not 80 m away")
            let intervals = (0..<20).map { SL.buoyInterval(strike: $0) }
            check(intervals.allSatisfy { $0 >= 5.2 && $0 <= 8.3 } && Set(intervals.map { Int($0 * 100) }).count > 10, "the buoy rings every 5-8 s, irregularly")
            check(Scene.makeWorld(device: device).groundHeight(x: Layout.buoy.x, z: Layout.buoy.z) < -3, "the buoy floats in deep water (ground \(Scene.makeWorld(device: device).groundHeight(x: Layout.buoy.x, z: Layout.buoy.z)) m)")
            // Offline render: located hums add audible energy and the mix never clips; a buoy strike is audible and decays.
            func render(_ setup: (AmbienceSynth) -> Void, seconds: Int = 4) -> [Float] {
                let synth = AmbienceSynth(sampleRate: 44100)
                setup(synth)
                let n = 44100 * seconds
                var l = [Float](repeating: 0, count: n), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    var done = 0
                    while done < n { synth.render(frames: 512, left: lp.baseAddress! + done, right: rp.baseAddress! + done); done += 512 }
                } }
                return l
            }
            func rmsOf(_ a: ArraySlice<Float>) -> Float { (a.reduce(0) { $0 + $1 * $1 } / Float(a.count)).squareRoot() }
            let base = render { _ in }
            let hums = render { $0.humGain = SIMD4(1, 1, 1, 1); $0.galleryGain = 1 }
            let humRms = rmsOf(zip(hums, base).map { $0 - $1 }[88200...])
            check(humRms > 0.003 && humRms < 0.06 && (hums.map { abs($0) }.max() ?? 2) < 1, "the hums and gallery whistle are audible, faint and never clip (added rms \(String(format: "%.4f", humRms)))")
            let bell = render({ $0.buoyGain = 0.8; $0.play(.buoy) }, seconds: 10)
            let bellDiff = zip(bell, render({ _ in }, seconds: 10)).map { $0 - $1 }
            check(rmsOf(bellDiff[0..<22050]) > rmsOf(bellDiff[(44100 * 9)...]) * 2 && rmsOf(bellDiff[0..<22050]) > 0.003, "a bell-buoy strike is audible and decays")
            let silentBell = render({ $0.buoyGain = 0; $0.play(.buoy) })
            check(zip(silentBell, base).allSatisfy { abs($0 - $1) < 1e-6 }, "a buoy too far away to hear adds nothing")
        }
        if name == "all" || name == "space" {
            // FDN reverb: stable, silent after its decay, decay time as asked, never louder than the input.
            func tail(_ rt: Float) -> [Float] {
                var r = FDNReverb(sampleRate: 44100); r.setDecay(rt)
                var out: [Float] = []
                for i in 0..<(44100 * 8) { out.append(r.process(left: i == 0 ? 1 : 0, right: 0).0) }
                return out
            }
            func rmsWindow(_ a: [Float], _ from: Float, _ to: Float) -> Float {
                let s = a[Int(from * 44100)..<Int(to * 44100)]; return (s.reduce(0) { $0 + $1 * $1 } / Float(s.count)).squareRoot()
            }
            let short = tail(0.8), long = tail(3.0)
            check((short + long).allSatisfy { $0.isFinite && abs($0) < 1 }, "the FDN reverb is stable and never louder than a unit impulse")
            check(rmsWindow(short, 7, 8) < 1e-4 && rmsWindow(long, 7, 8) < 1e-3, "and it falls silent after its decay (\(rmsWindow(long, 7, 8)))")
            // Decay measured: the energy envelope should drop ~60 dB over rt60 (within a generous factor: it is a statistical tail).
            func dbDrop(_ a: [Float], _ rt: Float) -> Float { 20 * log10(max(rmsWindow(a, 0.1, 0.3), 1e-9) / max(rmsWindow(a, 0.1 + rt * 0.6, 0.3 + rt * 0.6), 1e-9)) }
            let dShort = dbDrop(short, 0.8), dLong = dbDrop(long, 3.0)
            check(dShort > 20 && dShort < 70 && dLong > 20 && dLong < 70, "decay follows rt60: both fall tens of dB over 60 % of their rt60 (\(dShort) dB, \(dLong) dB)")
            check(rmsWindow(long, 1.0, 2.0) > rmsWindow(short, 1.0, 2.0) * 3, "a longer rt60 keeps ringing after a shorter one has died")
            var loud = FDNReverb(sampleRate: 44100); loud.setDecay(6)
            var peak: Float = 0
            for i in 0..<(44100 * 4) { let x = Float(sin(Double(i) * 0.05)); let o = loud.process(left: x, right: -x); peak = max(peak, abs(o.0), abs(o.1)) }
            check(peak.isFinite && peak < 12, "even fed a continuous full-scale tone it stays finite and bounded (peak \(peak)); the synth's tanh limiter takes it from there")
            // The space probe.
            let sc = Scene.makeWorld(device: device)
            let ground: (Float, Float) -> Float = { sc.groundHeight(x: $0, z: $1) }
            var opens: [Float] = []
            for k in 0..<60 { let x = -150 + Float(k % 10) * 28, z = -150 + Float(k / 10) * 40; if ground(x, z) > 2 { opens.append(AudioSpace.openness(at: SIMD3(x, ground(x, z), z), ground: ground)) } }
            check(opens.count > 10 && ((opens.max() ?? 0) - (opens.min() ?? 1)) > 0.25, "openness varies across the island (min \(opens.min() ?? -1), max \(opens.max() ?? -1) over \(opens.count) places)")
            check(AudioSpace.reverbTime(openness: 1) < AudioSpace.reverbTime(openness: 0) && AudioSpace.reverbTime(openness: 0) <= 3.2 && AudioSpace.reverbTime(openness: 1) >= 0.7, "an enclosed place rings longer than an open one")
            let dock = AudioSpace.read(listener: Layout.dockEnd, yaw: Layout.spawnYaw, ground: ground)
            let dockFlip = AudioSpace.read(listener: Layout.dockEnd, yaw: Layout.spawnYaw + .pi, ground: ground)
            check(dock.shoreDistance < 40 && abs(dock.surfPan) > 0.05 && dock.surfPan * dockFlip.surfPan < 0, "surf pans toward the nearest shore and flips when you turn round (\(dock.surfPan) / \(dockFlip.surfPan))")
            check(dock.surfOcclusion < 0.2, "the dock has a clear line to the sea (occlusion \(dock.surfOcclusion))")
            // Behind the hill: a lee-side spot whose nearest shoreline lies across the ridge should be occluded, the beach not.
            // A synthetic coast: sea for x < 0, a ridge 40 m high at x 10...20, low land beyond. Standing behind the ridge muffles the sea.
            let coast: (Float, Float) -> Float = { x, _ in x < 0 ? -5 : ((x >= 10 && x <= 20) ? 40 : 5) }
            let lee = AudioSpace.read(listener: SIMD3(50, 5, 0), yaw: 0, ground: coast), front = AudioSpace.read(listener: SIMD3(6, 5, 0), yaw: 0, ground: coast)
            check(lee.surfOcclusion > 0.8 && front.surfOcclusion < 0.1, "behind a ridge the sea is occluded; on the near side it is not (\(lee.surfOcclusion) vs \(front.surfOcclusion))")
            // Ducking and the muffled/panned surf, measured offline.
            let synth = AmbienceSynth(sampleRate: 44100)
            var l = [Float](repeating: 0, count: 512), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } }
            check(synth.duckAmount == 0, "no chime, no ducking")
            synth.play(.stone)
            var maxDuck: Float = 0
            for _ in 0..<40 { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } }; maxDuck = max(maxDuck, synth.duckAmount) }
            check(maxDuck > 0.1 && maxDuck <= 0.351, "a chime ducks the ambient bed (peak \(maxDuck))")
            for _ in 0..<(44100 * 12 / 512) { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } } }
            check(synth.duckAmount < 0.02, "and the ducking releases once the chime has gone")
            func surfEnergy(pan: Float, occ: Float) -> (Float, Float, Float) {
                let sy = AmbienceSynth(sampleRate: 44100); sy.windGain = 0; sy.surfGain = 1; sy.surfPan = pan; sy.surfOcclusion = occ
                var a = [Float](repeating: 0, count: 44100 * 6), b = a
                a.withUnsafeMutableBufferPointer { ap in b.withUnsafeMutableBufferPointer { bp in var d = 0; while d < 44100 * 6 { sy.render(frames: 512, left: ap.baseAddress! + d, right: bp.baseAddress! + d); d += 512 } } }
                func rm(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot() }
                // brightness: energy of the sample-to-sample difference relative to the signal
                let diff = zip(a.dropFirst(), a).map { $0 - $1 }
                return (rm(a[88200...]), rm(b[88200...]), rm(diff[88200...]) / max(rm(a[88200...]), 1e-6))
            }
            let centre = surfEnergy(pan: 0, occ: 0), right = surfEnergy(pan: 1, occ: 0), muffled = surfEnergy(pan: 0, occ: 1)
            check(right.1 > right.0 * 1.2 && abs(centre.0 - centre.1) / max(centre.0, 1e-6) < 0.3, "surf from the right is louder in the right ear (\(right.0) / \(right.1)); centred stays balanced")
            check(muffled.2 < centre.2 * 0.85 && muffled.0 < centre.0, "behind a hill the surf is darker and quieter (brightness \(muffled.2) vs \(centre.2))")
        }
        if name == "all" || name == "chimes" {
            let sr: Float = 44100
            func render(_ kind: ChimeKind, seconds: Float) -> [Float] {
                let synth = AmbienceSynth(sampleRate: sr)
                synth.windGain = 0; synth.surfGain = 0; synth.master = 1
                synth.play(kind)
                let n = Int(sr * seconds)
                var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    var d = 0
                    while d < n { let c = min(512, n - d); synth.render(frames: c, left: lp.baseAddress! + d, right: rp.baseAddress! + d); d += c }
                } }
                return l
            }
            /// Goertzel: the signal's energy at one frequency (a one-bin DFT).
            func energy(_ x: [Float], hz: Float, range: Range<Int>) -> Float {
                let w = 2 * Float.pi * hz / sr, c = 2 * cos(w)
                var s1: Float = 0, s2: Float = 0
                for i in range { let s0 = x[i] + c * s1 - s2; s2 = s1; s1 = s0 }
                return s1 * s1 + s2 * s2 - c * s1 * s2
            }
            for (kind, hz, label) in [(ChimeKind.tide, Float(293.66), "tide D4"), (.wind, 440.0, "wind A4"), (.stone, 587.33, "stone D5")] {
                let x = render(kind, seconds: 3)
                let atNote = energy(x, hz: hz, range: 0..<Int(sr))
                let off = energy(x, hz: hz * 1.12, range: 0..<Int(sr))
                check(atNote > 20 * off, "\(label) rings at its pitch (energy ratio vs a whole tone off: \(Int(atNote / max(off, 1e-9)))x)")
                let early = x[0..<Int(sr * 0.5)].map { abs($0) }.max() ?? 0
                let late = x[Int(sr * 2.8)...].map { abs($0) }.max() ?? 0
                check(early < 0.95 && late < early * 0.5 && !x.contains { !$0.isFinite }, "\(label) decays and stays finite (peak \(String(format: "%.2f", early)) -> \(String(format: "%.3f", late)))")
            }
            let fail = render(.fail, seconds: 2), tide = render(.tide, seconds: 2)
            check((fail.map { abs($0) }.max() ?? 1) < (tide.map { abs($0) }.max() ?? 0), "the fail chime is quieter than a success chime")
            let rumble = render(.rumble, seconds: 6)
            check((rumble.map { abs($0) }.max() ?? 0) > 0.02 && !rumble.contains { !$0.isFinite }, "rumble is audible and finite")
            let ignite = render(.ignite, seconds: 4)
            check((ignite.map { abs($0) }.max() ?? 2) < 1.0 && (ignite.map { abs($0) }.max() ?? 0) > 0.1, "ignite chord is clearly audible and never clips (peak \(String(format: "%.2f", ignite.map { abs($0) }.max() ?? 0)))")
        }
    }
}
