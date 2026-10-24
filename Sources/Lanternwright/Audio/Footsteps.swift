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
    struct Mode { var hz: Float; var decay: Float; var gain: Float; var glide: Float = 0; var attack: Float = 0.0008 }       // glide: fractional frequency change per second
    // Impact
    var impactAttack: Float, impactDecay: Float, impactCutoff: Float, impactGain: Float
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
        // rock: hard and a little dull, with a short ring and grit
        FootstepRecipe(impactAttack: 0.0015, impactDecay: 0.022, impactCutoff: 4200, impactGain: 0.20,
                       modes: [Mode(hz: 120, decay: 0.07, gain: 0.42), Mode(hz: 1700, decay: 0.045, gain: 0.30)],
                       grainMin: 8, grainMax: 18, grainWindow: 0.08, grainFreqLo: 2500, grainFreqHi: 6500, grainLenLo: 0.002, grainLenHi: 0.006,
                       grainGain: 0.10, grainSweep: 0.8, grainSwish: 0.2, grainCrunch: 0.6, reverbSend: 0.20),
        // stone: sharp, bright tick; a ring in 1.2-3 kHz; mass underneath; a little grit; the most reverb
        FootstepRecipe(impactAttack: 0.0003, impactDecay: 0.012, impactCutoff: 9000, impactGain: 0.40,
                       modes: [Mode(hz: 110, decay: 0.08, gain: 0.12), Mode(hz: 2500, decay: 0.07, gain: 0.50, attack: 0.0002)],
                       grainMin: 4, grainMax: 12, grainWindow: 0.06, grainFreqLo: 4000, grainFreqHi: 9000, grainLenLo: 0.002, grainLenHi: 0.005,
                       grainGain: 0.05, grainSweep: 0.85, grainSwish: 0.1, reverbSend: 0.30),
        // wood (the dock): suspended planks. A hollow cavity resonance, a plank flexing, a knock; no grains; the occasional creak.
        FootstepRecipe(impactAttack: 0.002, impactDecay: 0.012, impactCutoff: 3200, impactGain: 0.14,
                       modes: [Mode(hz: 125, decay: 0.22, gain: 0.62), Mode(hz: 320, decay: 0.07, gain: 0.40), Mode(hz: 900, decay: 0.02, gain: 0.14)],
                       creakChance: 1.0 / 12.0, perPlank: true, reverbSend: 0.12),
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
                            var lp: Float = 0; var seed: UInt32; var pan: Float; var send: Float }
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
    func start(mix: StepMix, run: Bool, pan: Float, plank: Int = 0, pebble: Float = 0) {
        var weights: [(StepMaterial, Float)] = []
        for m in StepMaterial.allCases where mix[m.rawValue] > 0.04 { weights.append((m, mix[m.rawValue])) }
        weights.sort { $0.1 > $1.1 }
        if weights.count > 3 { weights.removeLast(weights.count - 3) }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return }
        let vary = 0.85 + 0.3 * rnd(), bright = 0.9 + 0.2 * rnd()
        for (m, w) in weights {
            let level = w / total
            emit(FootstepRecipe.table[m.rawValue], level: level, vary: vary, bright: bright, delay: 0, toe: false, run: run, pan: pan, plank: plank, pebble: pebble)
            if !run { emit(FootstepRecipe.table[m.rawValue], level: level * 0.28, vary: vary, bright: bright, delay: 0.075, toe: true, run: false, pan: pan, plank: plank, pebble: pebble) }
        }
    }

    private func emit(_ r: FootstepRecipe, level: Float, vary: Float, bright: Float, delay: Float, toe: Bool, run: Bool, pan: Float, plank: Int, pebble: Float) {
        let g = level * vary
        let seed = UInt32(truncatingIfNeeded: Int(rnd() * 1e6) &+ 1)
        if layers.contains(.impact) {
        let cutoff = r.impactCutoff * bright * (toe ? 1.25 : 1) * (run ? 1.5 : 1)
        impacts.append(Impact(delay: delay, attack: r.impactAttack * (run ? 0.6 : 1) * (toe ? 1.3 : 1), decay: r.impactDecay * (run ? 0.55 : (toe ? 0.8 : 1)),
                              gain: r.impactGain * g * (run ? 1.8 : 1), alpha: 1 - exp(-2 * .pi * cutoff / sr), seed: seed, pan: pan, send: r.reverbSend))
        }
        // Body modes: detuned ~5 % per step; wood also shifts pitch and decay per plank (the same plank always sounds the same).
        let plankPitch: Float = r.perPlank ? 1 + (Footsteps.plankHash(plank, salt: 1) - 0.5) * 0.24 : 1
        let plankDecay: Float = r.perPlank ? 1 + (Footsteps.plankHash(plank, salt: 2) - 0.5) * 0.30 : 1
        for m in r.modes where modes.count < 90 && layers.contains(.body) {
            modes.append(Mode(delay: delay, hz: m.hz * (1 + (rnd() - 0.5) * 0.10) * plankPitch * (toe ? 1.2 : 1), glide: m.glide, attack: m.attack,
                              decay: m.decay * plankDecay * (toe ? 0.7 : 1) * (run ? 0.6 : 1), gain: m.gain * g * (run ? 1.7 : 1), pan: pan, send: r.reverbSend))
        }
        // A creak: a short, gliding squeak, now and then, a little more often when running.
        if r.creakChance > 0 && !toe && rnd() < r.creakChance * level * (run ? 1.6 : 1) && modes.count < 90 {
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
            let env = (1 - exp(-v.age / v.attack)) * exp(-v.age / v.decay)
            add(v.lp * v.gain * env * 1.1, v.pan, v.send)
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
