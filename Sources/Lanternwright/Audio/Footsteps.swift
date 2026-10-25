import Foundation

/// What a footfall is made of, per surface (R05). Every number that shapes how a surface sounds lives in `FootstepRecipe.table`, so a
/// surface that the player says sounds wrong is one row to edit.
///
/// A step has three layers:
///  1. **Impact**: 1 to 14 ms of shaped, low-passed noise: the moment of contact. Its attack and brightness say how hard the surface is.
///  2. **Body**: a few damped sine modes (frequency, decay, gain; each detuned about 5 % per step): how the thing under the foot rings.
///     Hollow planks, a dull thump in packed earth, the ring of stone.
///  3. **Texture**: stochastic micro-grains: each a 2 to 15 ms band-passed noise tick at a random time, level and centre frequency,
///     sweeping down a little: what the surface is made of. Sand shifting, gravel crunch, stalks.
/// Heel then toe (toe at 40 % level, half the grains, a brighter shorter body); running is one harder, shorter contact.
enum StepMaterial: Int, CaseIterable {
    case grass = 0, drySand, wetSand, earth, rock, stone, wood
}

/// Weights over `StepMaterial` (index = rawValue); the eighth lane is unused. Surfaces blend by weight, not by switching.
typealias StepMix = SIMD8<Float>

struct FootstepRecipe {
    struct Mode { var hz: Float; var decay: Float; var gain: Float; var glide: Float = 0; var attack: Float = 0.0008; var cavity = false }       // glide: fractional frequency change per second; cavity: the hollow space under a plank (scaled by hollowness)
    // Impact
    var impactAttack: Float, impactDecay: Float, impactCutoff: Float, impactGain: Float
    var impactHighpass: Float = 0                     // > 0: the impact is band-limited (low-passed at the cutoff, high-passed here): a smack, not a thud
    // Body
    var modes: [Mode] = []
    // Texture
    var grainMin = 0, grainMax = 0                    // grains per (heel) step
    var grainWindow: Float = 0.1                      // seconds over which they are spread
    var grainFreqLo: Float = 2000, grainFreqHi: Float = 5000
    var grainLenLo: Float = 0.003, grainLenHi: Float = 0.008
    var grainGain: Float = 0.1
    var grainSweep: Float = 0.7                       // end/start centre frequency over a grain's life
    var grainSwish: Float = 0                         // 0 flat, 1 a level bump across the window (sand settling)
    var grainCrunch: Float = 0                        // 0 even levels, 1 a few much louder grains (small stones giving way)
    var pebbleBoost: Float = 0                        // extra grains per unit of pebble level
    // Character
    var creakChance: Float = 0
    var perPlank = false
    var reverbSend: Float = 0.05

    /// Wading (R07-5): a foot pushed through shallow water. A soft low slosh of the water's mass, then a cloud of wet, low-passed droplet grains (the grain layer of
    /// the step engine, 0.5-2.4 kHz, longer and softer than sand) falling over a quarter of a second, with a bit of reverb.
    static let splash = FootstepRecipe(impactAttack: 0.014, impactDecay: 0.09, impactCutoff: 520, impactGain: 0.10,
                                       modes: [Mode(hz: 150, decay: 0.14, gain: 0.34, glide: -1.2, attack: 0.012), Mode(hz: 310, decay: 0.08, gain: 0.16, glide: -2.0, attack: 0.010)],
                                       grainMin: 16, grainMax: 28, grainWindow: 0.26, grainFreqLo: 500, grainFreqHi: 2400, grainLenLo: 0.004, grainLenHi: 0.014,
                                       grainGain: 0.055, grainSweep: 0.55, grainSwish: 0.6, grainCrunch: 0.5, reverbSend: 0.10)

    /// Indexed by `StepMaterial.rawValue`.
    static let table: [FootstepRecipe] = [
        // grass: the quietest, a soft swish with a few faint stalk crackles
        FootstepRecipe(impactAttack: 0.010, impactDecay: 0.085, impactCutoff: 650, impactGain: 0.13,
                       grainMin: 3, grainMax: 8, grainWindow: 0.15, grainFreqLo: 3000, grainFreqHi: 7000, grainLenLo: 0.002, grainLenHi: 0.005,
                       grainGain: 0.008, grainSweep: 0.9, grainSwish: 0.5, reverbSend: 0.02),
        // dry sand: very soft contact, a dense cloud of fine grains swishing down
        FootstepRecipe(impactAttack: 0.012, impactDecay: 0.07, impactCutoff: 700, impactGain: 0.05,
                       grainMin: 60, grainMax: 120, grainWindow: 0.23, grainFreqLo: 1200, grainFreqHi: 3200, grainLenLo: 0.004, grainLenHi: 0.010,
                       grainGain: 0.055, grainSweep: 0.55, grainSwish: 1.0, reverbSend: 0.02),
        // wet sand: lower, fewer, softer grains and a faint squelch
        FootstepRecipe(impactAttack: 0.010, impactDecay: 0.08, impactCutoff: 600, impactGain: 0.07,
                       modes: [Mode(hz: 190, decay: 0.05, gain: 0.30, glide: -2.2, attack: 0.008)],
                       grainMin: 22, grainMax: 42, grainWindow: 0.20, grainFreqLo: 800, grainFreqHi: 1500, grainLenLo: 0.005, grainLenHi: 0.012,
                       grainGain: 0.085, grainSweep: 0.6, grainSwish: 0.7, reverbSend: 0.02),
        // packed earth / the lantern path: a dull thump and a few stones crunching
        FootstepRecipe(impactAttack: 0.0045, impactDecay: 0.03, impactCutoff: 2200, impactGain: 0.12,
                       modes: [Mode(hz: 95, decay: 0.024, gain: 0.62)],
                       grainMin: 6, grainMax: 20, grainWindow: 0.10, grainFreqLo: 2000, grainFreqHi: 6000, grainLenLo: 0.003, grainLenHi: 0.008,
                       grainGain: 0.075, grainSweep: 0.8, grainSwish: 0.3, grainCrunch: 0.8, pebbleBoost: 1.5, reverbSend: 0.05),
        // rock (F02 A2, #21): solid stone does not resonate. A band-limited smack (0.7-3 kHz), a short damped thump from the ground under it (about 100 Hz, under
        // 30 ms), and a little loose grit; nothing rings above 600 Hz (the old 1.7 kHz partial was the "xylophone"). The whole step is gone in well under 80 ms.
        FootstepRecipe(impactAttack: 0.0012, impactDecay: 0.014, impactCutoff: 3000, impactGain: 0.30, impactHighpass: 700,
                       modes: [Mode(hz: 100, decay: 0.018, gain: 0.17)],
                       grainMin: 8, grainMax: 16, grainWindow: 0.045, grainFreqLo: 1800, grainFreqHi: 4500, grainLenLo: 0.002, grainLenHi: 0.005,
                       grainGain: 0.05, grainSweep: 0.8, grainSwish: 0.2, grainCrunch: 0.6, reverbSend: 0.08),
        // stone (the causeway slabs, the plinth): a superficial smack. Band-limited noise (0.8-3 kHz) with a quick attack, a small damped thump (about 85 Hz, 15 ms),
        // a few quiet clicks; no partial that could ring and no long reverb send (F02 A2, #24: the old 2.5 kHz partial was the high "plink").
        FootstepRecipe(impactAttack: 0.0006, impactDecay: 0.010, impactCutoff: 3000, impactGain: 0.36, impactHighpass: 800,
                       modes: [Mode(hz: 85, decay: 0.015, gain: 0.13)],
                       grainMin: 3, grainMax: 8, grainWindow: 0.035, grainFreqLo: 1500, grainFreqHi: 4200, grainLenLo: 0.002, grainLenHi: 0.005,
                       grainGain: 0.04, grainSweep: 0.8, grainSwish: 0.1, reverbSend: 0.12),
        // wood (the dock): planks on beams, F02 A2 (#31): a solid KNOCK (wood body, 190 and 340 Hz, about 70 ms to -30 dB) on every step; the hollow space under the
        // deck is a small, short addition (125 Hz, at most 0.24 gain and 0.10 s) that scales with the clearance, so even the seaward end is a plank, not a drum.
        FootstepRecipe(impactAttack: 0.002, impactDecay: 0.012, impactCutoff: 3200, impactGain: 0.14,
                       modes: [Mode(hz: 125, decay: 0.10, gain: 0.24, cavity: true), Mode(hz: 190, decay: 0.024, gain: 0.38), Mode(hz: 340, decay: 0.020, gain: 0.30), Mode(hz: 900, decay: 0.02, gain: 0.14)],
                       creakChance: 1.0 / 12.0, perPlank: true, reverbSend: 0.08),
    ]

    static func material(for kind: SurfaceKind) -> StepMaterial {
        switch kind {
        case .grass: return .grass
        case .sand: return .drySand
        case .earth: return .earth
        case .rock: return .rock
        case .stone: return .stone
        case .wood: return .wood
        }
    }
    static func pure(_ m: StepMaterial) -> StepMix { var w = StepMix(repeating: 0); w[m.rawValue] = 1; return w }
}

/// Renders footsteps from `FootstepRecipe`s. Pools are sized once at init; starting a step and rendering never allocate.
final class Footsteps {
    private struct Impact { var delay: Float; var age: Float = 0; var attack: Float; var decay: Float; var gain: Float; var alpha: Float
                            var lp: Float = 0; var lp2: Float = 0; var alpha2: Float = 0; var seed: UInt32; var pan: Float; var send: Float }
    private struct Mode { var delay: Float; var age: Float = 0; var hz: Float; var glide: Float; var attack: Float; var decay: Float; var gain: Float; var phase: Float = 0
                          var pan: Float; var send: Float }
    private struct Grain { var delay: Float; var age: Float = 0; var len: Float; var gain: Float; var f0: Float; var f1: Float
                           var ic1: Float = 0, ic2: Float = 0; var a1: Float = 0, a2: Float = 0, a3: Float = 0; var seed: UInt32; var pan: Float; var send: Float }
    private var impacts: [Impact] = [], modes: [Mode] = [], grains: [Grain] = []
    private static let maxGrains = 640
    private let sr: Float
    private var rng: UInt32 = 0x2468ACE
    /// Reverb send of the latest sample (stone sends more than sand): read after `render`.
    private(set) var sendL: Float = 0, sendR: Float = 0
    /// Which layers a step starts (all by default; the selftests isolate them to measure each).
    struct Layers: OptionSet { let rawValue: Int; static let impact = Layers(rawValue: 1), body = Layers(rawValue: 2), texture = Layers(rawValue: 4); static let all: Layers = [.impact, .body, .texture] }
    var layers: Layers = .all
    /// Selftests only: false drops the toe strike so the heel contact can be measured alone.
    var toeEnabled = true

    init(sampleRate: Float) {
        sr = sampleRate
        impacts.reserveCapacity(48); modes.reserveCapacity(96); grains.reserveCapacity(Footsteps.maxGrains + 16)
    }

    private func rnd() -> Float { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return Float(rng >> 8) / Float(1 << 24) }
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    /// Deterministic 0...1 from a plank index (the same plank always sounds the same).
    static func plankHash(_ i: Int, salt: UInt32) -> Float {
        var x = UInt32(truncatingIfNeeded: i) &* 0x9E3779B1 &+ salt &* 0x85EBCA6B
        x ^= x >> 15; x = x &* 0x2C1B3C6D; x ^= x >> 12; x = x &* 0x297A2D39; x ^= x >> 15
        return Float(x >> 8) / Float(1 << 24)
    }

    /// Start one footfall (heel, plus toe unless running) from a weighted mix of materials.
    /// `hollow` (0...1) only matters for wood: planks resting on the ground thud (the cavity's gain and ring shrink and an earthen thump and a scuff take over),
    /// planks over open water boom.
    func start(mix: StepMix, run: Bool, pan: Float, plank: Int = 0, pebble: Float = 0, hollow: Float = 1, splash: Float = 0) {
        var weights: [(StepMaterial, Float)] = []
        for m in StepMaterial.allCases where mix[m.rawValue] > 0.04 { weights.append((m, mix[m.rawValue])) }
        weights.sort { $0.1 > $1.1 }
        if weights.count > 3 { weights.removeLast(weights.count - 3) }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return }
        let vary = 0.85 + 0.3 * rnd(), bright = 0.9 + 0.2 * rnd()
        if splash > 0.02 {                       // ankle-deep water: the splash joins whatever the foot is on (wet sand underneath)
            emit(FootstepRecipe.splash, level: splash * (run ? 1.3 : 1), vary: vary, bright: bright, delay: 0.01, toe: false, run: run, pan: pan, plank: plank, pebble: 0)
        }
        for (m, w) in weights {
            let level = w / total
            let h: Float = m == .wood ? hollow : 1
            emit(FootstepRecipe.table[m.rawValue], level: level, vary: vary, bright: bright, delay: 0, toe: false, run: run, pan: pan, plank: plank, pebble: pebble, hollow: h)
            if !run && toeEnabled { emit(FootstepRecipe.table[m.rawValue], level: level * 0.28, vary: vary, bright: bright, delay: 0.075, toe: true, run: false, pan: pan, plank: plank, pebble: pebble, hollow: h) }
            if m == .wood && hollow < 0.99 {     // wood lying on stone or sand: the solid thud of the ground under it, with a little scuff
                let solid = (1 - hollow) * 0.6
                emit(FootstepRecipe.table[StepMaterial.earth.rawValue], level: level * solid, vary: vary, bright: bright, delay: 0, toe: false, run: run, pan: pan, plank: plank, pebble: 0, hollow: 1)
            }
        }
    }

    private func emit(_ r: FootstepRecipe, level: Float, vary: Float, bright: Float, delay: Float, toe: Bool, run: Bool, pan: Float, plank: Int, pebble: Float, hollow: Float = 1) {
        let g = level * vary
        let seed = UInt32(truncatingIfNeeded: Int(rnd() * 1e6) &+ 1)
        if layers.contains(.impact) {
        let cutoff = r.impactCutoff * bright * (toe ? 1.25 : 1) * (run ? 1.5 : 1)
        impacts.append(Impact(delay: delay, attack: r.impactAttack * (run ? 0.6 : 1) * (toe ? 1.3 : 1), decay: r.impactDecay * (run ? 0.55 : (toe ? 0.8 : 1)),
                              gain: r.impactGain * g * (run ? 1.8 : 1), alpha: 1 - exp(-2 * .pi * cutoff / sr),
                              alpha2: r.impactHighpass > 0 ? 1 - exp(-2 * .pi * r.impactHighpass * bright / sr) : 0, seed: seed, pan: pan, send: r.reverbSend))
        }
        // Body modes: detuned ~5 % per step; wood also shifts pitch and decay per plank (the same plank always sounds the same).
        let plankPitch: Float = r.perPlank ? 1 + (Footsteps.plankHash(plank, salt: 1) - 0.5) * 0.24 : 1
        let plankJitter: Float = r.perPlank ? 1 + (Footsteps.plankHash(plank, salt: 2) - 0.5) * 0.30 : 1
        let cavityDecay: Float = 0.18 + 0.82 * hollow                                                                                // the space under a plank on the ground does not ring
        let cavity: Float = 0.12 + 0.88 * hollow
        for m in r.modes where modes.count < 90 && layers.contains(.body) {
            modes.append(Mode(delay: delay, hz: m.hz * (1 + (rnd() - 0.5) * 0.10) * plankPitch * (toe ? 1.2 : 1), glide: m.glide, attack: m.attack,
                              decay: m.decay * plankJitter * (m.cavity ? cavityDecay : 1) * (toe ? 0.7 : 1) * (run ? 0.6 : 1), gain: m.gain * g * (run ? 1.7 : 1) * (m.cavity ? cavity : 1), pan: pan, send: r.reverbSend))
        }
        // A creak: a short, gliding squeak, now and then, a little more often when running.
        if r.creakChance > 0 && !toe && rnd() < r.creakChance * level * (run ? 1.6 : 1) * hollow && modes.count < 90 {
            let hz = lerp(600, 1400, rnd())
            modes.append(Mode(delay: delay + 0.02 + 0.05 * rnd(), hz: hz, glide: (rnd() < 0.5 ? -1 : 1) * (0.5 + rnd()), attack: 0.004, decay: 0.09, gain: 0.07 * vary, pan: pan, send: r.reverbSend))
        }
        // Texture: grains spread over the window, shaped by the recipe. The expected count scales with the weight, so a 50/50 blend of two
        // surfaces has half of each one's grains.
        guard r.grainMax > 0, layers.contains(.texture) else { return }
        var expected = lerp(Float(r.grainMin), Float(r.grainMax), rnd()) * (toe ? 0.5 : 1) * (run ? 0.6 : 1) * (1 + pebble * r.pebbleBoost) * level
        var n = Int(expected); expected -= Float(n); if rnd() < expected { n += 1 }
        let window = r.grainWindow * (run ? 0.6 : 1)
        for _ in 0..<n where grains.count < Footsteps.maxGrains {
            let t = rnd()
            let bump = 1 - r.grainSwish + r.grainSwish * pow(sin(.pi * min(max(t * 0.9 + 0.05, 0), 1)), 0.8)    // rises, then settles
            let crunch = r.grainCrunch > 0 ? lerp(1, 0.25 + 2.6 * rnd() * rnd(), r.grainCrunch) : 1
            let f0 = lerp(r.grainFreqLo, r.grainFreqHi, rnd()) * bright * (run ? 1.25 : 1)
            let len = lerp(r.grainLenLo, r.grainLenHi, rnd()) * (run ? 0.7 : 1)
            let gseed = UInt32(truncatingIfNeeded: Int(rnd() * 1e7) &+ 1)
            grains.append(Grain(delay: delay + t * window, len: len, gain: r.grainGain * g * bump * crunch * (run ? 1.4 : 1), f0: f0, f1: f0 * r.grainSweep, seed: gseed, pan: pan, send: r.reverbSend))
        }
    }

    /// One stereo sample of every step voice (add this to the mix); `sendL/R` hold the reverb send for the same sample.
    func render(dt: Float) -> (Float, Float) {
        var l: Float = 0, r: Float = 0, sl: Float = 0, sr_: Float = 0
        func add(_ s: Float, _ pan: Float, _ send: Float) {
            let a = s * (0.5 - 0.5 * pan), b = s * (0.5 + 0.5 * pan)
            l += a; r += b; sl += a * send; sr_ += b * send
        }
        for k in 0..<impacts.count {
            if impacts[k].delay > 0 { impacts[k].delay -= dt; continue }
            var v = impacts[k]
            v.seed ^= v.seed << 13; v.seed ^= v.seed >> 17; v.seed ^= v.seed << 5
            let n = Float(Int32(bitPattern: v.seed)) / Float(Int32.max)
            v.lp += v.alpha * (n - v.lp)
            var shaped = v.lp
            if v.alpha2 > 0 { v.lp2 += v.alpha2 * (v.lp - v.lp2); shaped = v.lp - v.lp2 }           // band-pass: low-passed minus the slower low-pass
            let env = (1 - exp(-v.age / v.attack)) * exp(-v.age / v.decay)
            add(shaped * v.gain * env * 1.1, v.pan, v.send)
            v.age += dt
            impacts[k] = v
        }
        for k in 0..<modes.count {
            if modes[k].delay > 0 { modes[k].delay -= dt; continue }
            var v = modes[k]
            v.phase += 2 * .pi * v.hz * dt
            if v.phase > 2 * .pi { v.phase -= 2 * .pi }
            v.hz *= 1 + v.glide * dt
            let env = (1 - exp(-v.age / v.attack)) * exp(-v.age / v.decay)
            add(sin(v.phase) * v.gain * env * 0.30, v.pan, v.send)
            v.age += dt
            modes[k] = v
        }
        for k in 0..<grains.count {
            if grains[k].delay > 0 { grains[k].delay -= dt; continue }
            var v = grains[k]
            if Int(v.age * sr) % 16 == 0 {                              // retune the band-pass as the grain sweeps down
                let f = max(200, lerp(v.f0, v.f1, min(v.age / v.len, 1)))
                let g = tan(.pi * min(f, sr * 0.45) / sr), kq: Float = 0.45
                v.a1 = 1 / (1 + g * (g + kq)); v.a2 = g * v.a1; v.a3 = g * v.a2
            }
            v.seed ^= v.seed << 13; v.seed ^= v.seed >> 17; v.seed ^= v.seed << 5
            let x = Float(Int32(bitPattern: v.seed)) / Float(Int32.max)
            let v3 = x - v.ic2
            let v1 = v.a1 * v.ic1 + v.a2 * v3
            let v2 = v.ic2 + v.a2 * v.ic1 + v.a3 * v3
            v.ic1 = 2 * v1 - v.ic1; v.ic2 = 2 * v2 - v.ic2
            let w = v.age / v.len
            let hann = w < 1 ? 0.5 - 0.5 * cos(2 * .pi * w) : 0
            add(v1 * v.gain * hann * 1.5, v.pan, v.send)
            v.age += dt
            grains[k] = v
        }
        impacts.removeAll { $0.delay <= 0 && $0.age > $0.decay * 8 + $0.attack * 4 }
        modes.removeAll { $0.delay <= 0 && $0.age > $0.decay * 7 }
        grains.removeAll { $0.delay <= 0 && $0.age >= $0.len }
        sendL = sl; sendR = sr_
        return (l, r)
    }

    var activeVoices: Int { impacts.count + modes.count + grains.count }
}
