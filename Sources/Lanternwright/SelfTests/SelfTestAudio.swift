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
                check(peak(walk[0..<Int(sr * 0.0002)]) < 0.3 * peak(walk[0..<Int(sr * 0.4)]) && !walk.contains { !$0.isFinite }, "\(surface) step has no click (the first 0.2 ms is not the peak) and is finite")
                check(peak(walk[Int(sr * 1.5)...]) < 2e-3, "\(surface) step has died away by 1.5 s (\(peak(walk[Int(sr * 1.5)...])))")
            }
            let walkGrass = step(.grass, run: false), runGrass = step(.grass, run: true)
            check(ringOut(walkGrass) >= 0.12, "a grass footstep rings out for at least 0.12 s, not a click (\(String(format: "%.2f", ringOut(walkGrass))) s)")
            let walkStone = step(.stone, run: false), runStone = step(.stone, run: true)
            check(peak(runStone[...]) > 1.2 * peak(walkStone[...]) && ringOut(runStone) < ringOut(walkStone),
                  "a run step is harder and shorter than a walk step (peak \(String(format: "%.2f", peak(walkStone[...]))) -> \(String(format: "%.2f", peak(runStone[...]))), ring-out \(String(format: "%.2f", ringOut(walkStone))) -> \(String(format: "%.2f", ringOut(runStone))) s)")
            // The walk has a second, softer hit (the toe) after the heel.
            let heel = peak(walkGrass[0..<Int(sr * 0.06)]), toe = peak(walkGrass[Int(sr * 0.075)..<Int(sr * 0.2)])
            check(toe > 0.15 * heel && toe < heel, "walking is heel then toe (toe is \(Int(100 * toe / heel)) % of the heel; heel \(heel), toe \(toe), env at 0.075 \(peak(walkGrass[Int(sr * 0.07)..<Int(sr * 0.08)])), 0.15 \(peak(walkGrass[Int(sr * 0.14)..<Int(sr * 0.16)])))")
            // Consecutive steps differ.
            let two = step(.grass, run: false, count: 2)
            let first = peak(two[0..<Int(sr * 2)]), second = peak(two[Int(sr * 2)...])
            check(abs(first - second) / max(first, second) > 0.01, "consecutive steps are not identical (peaks \(String(format: "%.3f", first)) vs \(String(format: "%.3f", second)))")
        }
        if name == "footstep-report" {
            typealias A = FootstepAnalysis
            for m in StepMaterial.allCases {
                let steps = A.render(mix: A.pure(m)), runs = A.render(mix: A.pure(m), run: true)
                let specs = steps.map(A.spectrum)
                let pk = A.mean(steps.map { $0.map { abs($0) }.max() ?? 0 }), pkRun = A.mean(runs.map { $0.map { abs($0) }.max() ?? 0 })
                let total = A.mean(specs.map { A.band($0, 40, 9000) })
                let low = A.mean(specs.map { A.band($0, 80, 400) }) / max(total, 1e-12), ring = A.mean(specs.map { A.band($0, 1200, 3000) }) / max(total, 1e-12)
                let tex = A.render(mix: A.pure(m), layers: .texture), body = A.render(mix: A.pure(m), layers: .body)
                print("\(m): peak \(pk) run \(pkRun) low \(low) ring \(ring) centroid \(A.mean(specs.map(A.centroid))) decay30low \(A.mean(steps.map { A.decayTime($0, lowpass: 400, dB: 30) })) attack \(A.mean(steps.map(A.attackTime))) grains(texture only) \(A.mean(tex.map { Float(A.grainCount($0)) })) bodyDecay20 \(A.mean(body.map { A.decayTime($0, lowpass: 400, dB: 20) }))")
            }
        }
        if name == "all" || name == "footsteps" {
            typealias A = FootstepAnalysis
            typealias M = StepMaterial
            func summary(_ m: StepMix, count: Int = 10, run: Bool = false, plank: Int = 0, pebble: Float = 0) -> (peak: Float, low: Float, ring: Float, centroid: Float, decay30: Float, rise: Float, grains: Float, bodyDecay: Float) {
                let steps = A.render(mix: m, count: count, run: run, plank: plank, pebble: pebble)
                let specs = steps.map(A.spectrum)
                let total = A.mean(specs.map { A.band($0, 40, 9000) })
                let tex = A.render(mix: m, count: count, run: run, plank: plank, pebble: pebble, layers: .texture)
                let body = A.render(mix: m, count: count, run: run, plank: plank, pebble: pebble, layers: .body)
                return (A.mean(steps.map { $0.map { abs($0) }.max() ?? 0 }), A.mean(specs.map { A.band($0, 80, 400) }) / max(total, 1e-12),
                        A.mean(specs.map { A.band($0, 1200, 3000) }) / max(total, 1e-12), A.mean(specs.map(A.centroid)),
                        A.mean(steps.map { A.decayTime($0, lowpass: 400, dB: 30) }), A.mean(steps.map(A.attackTime)),
                        A.mean(tex.map { Float(A.grainCount($0)) }), A.mean(body.map { A.decayTime($0, lowpass: 400, dB: 20) }))
            }
            let wood = summary(A.pure(.wood)), dry = summary(A.pure(.drySand)), wet = summary(A.pure(.wetSand)), earth = summary(A.pure(.earth))
            let stone = summary(A.pure(.stone)), rock = summary(A.pure(.rock)), grass = summary(A.pure(.grass))
            let others = [dry, wet, earth, stone, rock, grass]
            // wood: suspended planks, hollow
            check(wood.low > 0.9 && others.allSatisfy { wood.low > $0.low * 1.15 }, "wood: nearly all the energy is in the 80-400 Hz cavity band, clearly more than any other surface (\(wood.low) vs best other \(others.map(\.low).max() ?? 0))")
            check(wood.decay30 > 0.2 && wood.bodyDecay > 0.2, "wood: the hollow body rings on (-30 dB after \(wood.decay30) s)")
            func plankPitch(_ i: Int) -> Float { A.mean(A.render(mix: A.pure(.wood), count: 10, plank: i, seconds: 0.8, layers: .body).map { A.dominantPitch($0, 90, 190) }) }
            var planks: [(Int, Float)] = []; for i in 0..<40 { planks.append((i, Footsteps.plankHash(i, salt: 1))) }
            let lowP = planks.min { $0.1 < $1.1 }!, highP = planks.max { $0.1 < $1.1 }!
            let pLow = plankPitch(lowP.0), pHigh = plankPitch(highP.0), pLow2 = plankPitch(lowP.0)
            check((pHigh - pLow) / pLow > 0.10, "wood: two different planks sound at different pitches (plank \(lowP.0) \(pLow) Hz, plank \(highP.0) \(pHigh) Hz)")
            check(abs(pLow2 - pLow) / pLow < 0.02, "wood: the same plank always has the same pitch (\(pLow) Hz, again \(pLow2) Hz)")
            // sand: grains shifting
            check(dry.grains >= 5 * stone.grains && dry.grains >= 30, "sand: a dense grain cloud (\(dry.grains) grains) at least 5x stone's grit (\(stone.grains))")
            check(dry.rise > 0.010 && wet.rise > 0.004, "sand: soft contact, no click (dry rise \(dry.rise) s, wet \(wet.rise) s)")
            check(wet.centroid < dry.centroid * 0.6 && wet.grains < dry.grains, "sand: wet sand is darker (\(wet.centroid) Hz) and sparser than dry (\(dry.centroid) Hz)")
            // earth: solid with some crunch
            check(earth.low > 0.5 && earth.bodyDecay < 0.08, "earth: a dull, short thump under 80 ms (low share \(earth.low), -20 dB in \(earth.bodyDecay) s)")
            check(earth.grains > 4 && earth.grains < dry.grains * 0.5, "earth: some crunch, far fewer grains than sand (\(earth.grains) vs \(dry.grains))")
            let pebbly = summary(A.pure(.earth), pebble: 1)
            check(pebbly.grains > earth.grains * 1.4, "earth: pebbles on the path add crunch (\(earth.grains) -> \(pebbly.grains) grains)")
            // stone: hard, bright, a ring
            check(others.allSatisfy { stone.rise <= $0.rise } && stone.rise < 0.0012, "stone: the sharpest contact of any surface (rise \(stone.rise) s)")
            check([wood, dry, earth, wet].allSatisfy { stone.centroid > $0.centroid * 1.1 }, "stone: the brightest of wood, sand and earth (centroid \(stone.centroid) Hz vs sand \(dry.centroid), earth \(earth.centroid))")
            let ringBody = A.render(mix: A.pure(.stone), count: 6, seconds: 0.4, layers: .body).map { A.dominantPitch($0, 1000, 4000) }
            check(ringBody.allSatisfy { $0 >= 1200 && $0 <= 3000 }, "stone: a ring partial between 1.2 and 3 kHz (\(A.mean(ringBody)) Hz)")
            check(stone.ring > 0.5 && rock.ring < stone.ring, "stone rings more than rock (ring share \(stone.ring) vs \(rock.ring))")
            check(grass.peak < 0.5 * [dry, earth, stone, wood, rock].map(\.peak).min()!, "grass is the quietest surface (peak \(grass.peak))")
            // blends: a mixed step lies between its pure steps
            var half = StepMix(repeating: 0); half[M.drySand.rawValue] = 0.5; half[M.grass.rawValue] = 0.5
            let mixed = summary(half)
            check(mixed.grains > grass.grains && mixed.grains < dry.grains && mixed.centroid > grass.centroid && mixed.centroid < dry.centroid, "blend: a 50/50 sand-grass step lies between them (grains \(grass.grains) < \(mixed.grains) < \(dry.grains), centroid \(grass.centroid) < \(mixed.centroid) < \(dry.centroid))")
            var edge = StepMix(repeating: 0); edge[M.wood.rawValue] = 0.5; edge[M.drySand.rawValue] = 0.5
            let dockEnd = summary(edge)
            check(dockEnd.low < wood.low && dockEnd.low > dry.low && dockEnd.grains > 0.2 * dry.grains && dockEnd.grains < dry.grains, "blend: at the end of the dock the planks give way to sand (low share \(dry.low) < \(dockEnd.low) < \(wood.low))")
            // regression: no clipping at run; deterministic; cadence parts unchanged
            check([wood, dry, wet, earth, stone, rock, grass].allSatisfy { _ in true } && [M.wood, .drySand, .wetSand, .earth, .stone, .rock, .grass].allSatisfy { summary(A.pure($0), count: 6, run: true).peak < 0.9 }, "no surface clips when running (all run peaks below 0.9)")
            check(A.render(mix: A.pure(.earth), count: 3) == A.render(mix: A.pure(.earth), count: 3), "footsteps are deterministic for a given seed")
            check(A.render(mix: A.pure(.stone), count: 8).allSatisfy { $0.allSatisfy { $0.isFinite } }, "footsteps are finite")
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
