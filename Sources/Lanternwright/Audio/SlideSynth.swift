import Foundation

/// Sliding down a steep slope. F03 A3 (#45: "should sound like gravel giving way") built it as a continuous voice: a low bed, a dense cloud of 260 grains a second, a few stones. F09.4 (#91: "the sound on the
/// steeper grades is very odd. Like loud static ... ground it in the properties of the physical thing") replaces that: a dense, steady cloud of noise bursts IS static. What a foot slipping on loose ground
/// really makes is a handful of separate events:
/// - a SCUFF: the sole dragging over grit or soil, a 8-35 ms burst of band-passed noise (0.7-2.8 kHz on stones, 0.4-1.4 kHz on soil), with its own pitch, a 2 ms rise and a fall;
/// - a CLACK: one loose stone knocked against another, a two-partial damped click (0.65-2.25 kHz, 4-14 ms), only on stony ground and mostly when the slip is fast.
/// Their RATES follow the slip speed (about 2 a second at a slow slip, 10 at full speed on gravel); between them there is silence. No bed, no grain cloud. The level is capped well under the
/// footsteps (see `--selftest foley`: the peak is at least 9 dB under a rock footstep's). `speed` 0...1 follows how fast the player is slipping and `gravel` 0...1 how stony the ground is (grass: soil
/// scuffs only, softer and darker). The level follows the speed with a short release, so the sound is gone within 0.2 s of regaining footing.
final class SlideSynth {
    let sampleRate: Float
    private var level: Float = 0
    private var rng = FoleyNoise(seed: 0x51_1DE)
    private struct Scuff { var filter: Biquad; var remaining: Int; var total: Int; var amp: Float }
    private var scuffs: [Scuff] = []
    private struct Stone { var t: Float; var f1: Float; var f2: Float; var amp: Float; var decay: Float }
    private var stones: [Stone] = []
    /// Counters for the selftests: events started since creation.
    private(set) var scuffsStarted = 0, clacksStarted = 0
    /// How loud the slide is at full speed on gravel (linear, before the synth's master).
    static let gain: Float = 0.036
    /// Level time constants: it comes up in about 30 ms and is gone (-40 dB) in about 0.16 s.
    static let attack: Float = 0.03, release: Float = 0.035
    /// Events per second at full speed on gravel.
    static let scuffRate: Float = 7, clackRate: Float = 3.5

    init(sampleRate: Float) { self.sampleRate = sampleRate }

    /// One mono sample. Call every sample; `speed` and `gravel` may change continuously.
    func next(speed: Float, gravel: Float) -> Float {
        let dt = 1 / sampleRate
        let target = max(0, min(1, speed))
        let tau = target > level ? SlideSynth.attack : SlideSynth.release
        level += (target - level) * (1 - exp(-dt / tau))
        if level < 1e-4 && scuffs.isEmpty && stones.isEmpty { level = 0; return 0 }          // idle: exactly zero, and no float tail to denormals
        let sp = level, g = max(0, min(1, gravel))
        // Scuffs: a Poisson process whose rate rises with the slip (and is lower on soil).
        let scuffRate = SlideSynth.scuffRate * (0.25 + 0.75 * sp) * (0.5 + 0.5 * g) * (sp > 0.02 ? 1 : 0)
        if rng.unit() < scuffRate * dt && scuffs.count < 8 {
            let dur = 0.008 + 0.027 * rng.unit() * rng.unit() * 1.4                           // 8 to 35 ms, mostly short
            let lo = 400 + 300 * g, hi = 1400 + 1400 * g
            let f = lo * pow(hi / lo, rng.unit())
            let n = max(16, Int(min(dur, 0.035) * sampleRate))
            let r = rng.unit()
            scuffs.append(Scuff(filter: Biquad.bandpass(f, q: 1.0, sampleRate: sampleRate), remaining: n, total: n, amp: (0.2 + 0.8 * r * r) * (0.5 + 0.5 * g)))
            scuffsStarted += 1
        }
        var scuff: Float = 0
        for i in scuffs.indices {
            let t = Float(scuffs[i].total - scuffs[i].remaining) / Float(scuffs[i].total)
            let env = min(1, t * 10) * exp(-t * 3.8)
            scuff += scuffs[i].filter.process(rng.next()) * scuffs[i].amp * env
            scuffs[i].remaining -= 1
        }
        scuffs.removeAll { $0.remaining <= 0 }
        // Clacks: one stone against another, on stony ground, mostly at speed.
        let stony = max(0, min(1, (g - 0.25) / 0.75))
        if stony > 0 && rng.unit() < SlideSynth.clackRate * sp * sp * stony * dt && stones.count < 4 {
            let f = 650 + 1600 * rng.unit()
            stones.append(Stone(t: 0, f1: f, f2: f * (1.5 + 0.2 * rng.unit()), amp: 0.4 + 0.6 * rng.unit(), decay: 0.004 + 0.010 * rng.unit()))
            clacksStarted += 1
        }
        var clack: Float = 0
        for i in stones.indices {
            let s = stones[i], e = exp(-s.t / s.decay)
            clack += (sin(2 * Float.pi * s.f1 * s.t) + 0.5 * sin(2 * Float.pi * s.f2 * s.t)) * e * s.amp * min(1, s.t / 0.0005)
            stones[i].t += dt
        }
        stones.removeAll { $0.t > 0.08 }
        return (scuff * 3.4 + clack * 0.9) * SlideSynth.gain * pow(sp, 0.6) * (0.55 + 0.45 * g)        // soil is softer overall
    }

    /// Offline render (selftests): `seconds` at constant speed and gravel.
    static func render(speed: Float, gravel: Float, seconds: Float, sampleRate: Float, seed: UInt32? = nil) -> [Float] {
        let s = SlideSynth(sampleRate: sampleRate)
        if let seed { s.rng = FoleyNoise(seed: seed) }
        return (0..<Int(seconds * sampleRate)).map { _ in s.next(speed: speed, gravel: gravel) }
    }
}
