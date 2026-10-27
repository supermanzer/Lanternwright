import Foundation

/// Sliding down a steep slope (F03 A3, note #45: "should sound like gravel giving way"). A continuous voice made of what gravel on a slope really sounds like:
/// - a LOW BED, 100 to 250 Hz, the moving mass of the slope sliding (brown noise through two low-passes, its corner rising a little with speed);
/// - dense GRAINS, many 5 to 30 ms noise bursts at 1 to 6 kHz (each its own centre and length), their number per second rising with the slide's speed;
/// - a few larger STONES clacking: a short two-partial damped click, about one to three a second at full speed.
/// `speed` 0...1 follows how fast the player is slipping and `gravel` 0...1 how stony the ground is: grass gives a softer, mostly mass-and-slip sound (fewer, darker,
/// quieter grains and no stones). The level follows the speed with a short release, so the sound is gone within 0.2 s of regaining footing.
final class SlideSynth {
    let sampleRate: Float
    private var level: Float = 0
    private var rng = FoleyNoise(seed: 0x51_1DE)
    private var bedA: Float = 0, bedB: Float = 0, bedC: Float = 0, bedD: Float = 0
    private struct Grain { var filter: Biquad; var remaining: Int; var total: Int; var amp: Float }
    private var grains: [Grain] = []
    private struct Stone { var t: Float; var f1: Float; var f2: Float; var amp: Float; var decay: Float }
    private var stones: [Stone] = []
    /// Counters for the selftests: grains and stones started since creation.
    private(set) var grainsStarted = 0, stonesStarted = 0
    /// How loud the slide is at full speed on gravel (linear, before the synth's master).
    static let gain: Float = 0.20
    /// Level time constants: it comes up in about 30 ms and is gone (-40 dB) in about 0.16 s.
    static let attack: Float = 0.03, release: Float = 0.035
    /// Grain and stone rates per second at full speed on gravel (the lowest speed gets a tenth of the grain rate).
    static let grainRate: Float = 260, stoneRate: Float = 2.2

    init(sampleRate: Float) { self.sampleRate = sampleRate }

    /// One mono sample. Call every sample; `speed` and `gravel` may change continuously.
    func next(speed: Float, gravel: Float) -> Float {
        let dt = 1 / sampleRate
        let target = max(0, min(1, speed))
        let tau = target > level ? SlideSynth.attack : SlideSynth.release
        level += (target - level) * (1 - exp(-dt / tau))
        if level < 1e-4 && grains.isEmpty && stones.isEmpty { return 0 }
        let sp = level, g = max(0, min(1, gravel))
        // The bed: the mass of the slope in motion.
        let w = rng.next()
        let corner = 110 + 110 * sp
        let a = 1 - exp(-2 * Float.pi * corner * dt)
        bedA += a * (w - bedA); bedB += a * (bedA - bedB)
        bedC += 0.02 * (bedB - bedC)                                          // a slow 'breath' removal keeps it from rumbling under 60 Hz
        let bed = (bedB - bedC) * 8.0 * (0.35 + 0.65 * sp) * (0.8 + 0.4 * (1 - g))      // grass: more mass, less grit
        // New grains: a Poisson process whose rate rises with speed (and falls on grass).
        let rate = SlideSynth.grainRate * (0.1 + 0.9 * sp * sp) * (0.3 + 0.7 * g) * (sp > 0.02 ? 1 : 0)
        if rng.unit() < rate * dt && grains.count < 60 {
            let dur = 0.005 + 0.025 * rng.unit() * rng.unit() * 1.6              // 5 to 30 ms, mostly short
            let lo = 1000 - 400 * (1 - g), hi = 6000 - 3500 * (1 - g)            // grass grains are darker and narrower
            let f = lo * pow(hi / lo, rng.unit())
            let n = max(8, Int(min(dur, 0.030) * sampleRate))
            grains.append(Grain(filter: Biquad.bandpass(f, q: 1.4, sampleRate: sampleRate), remaining: n, total: n, amp: (0.25 + 0.75 * rng.unit()) * (0.3 + 0.7 * g)))
            grainsStarted += 1
        }
        var grit: Float = 0
        for i in grains.indices {
            let t = Float(grains[i].total - grains[i].remaining) / Float(grains[i].total)
            let env = min(1, t * 12) * exp(-t * 4.2)
            grit += grains[i].filter.process(rng.next()) * grains[i].amp * env
            grains[i].remaining -= 1
        }
        grains.removeAll { $0.remaining <= 0 }
        // Stones: a few larger ones clack.
        if g > 0.4 && rng.unit() < SlideSynth.stoneRate * sp * sp * (g - 0.3) * dt && stones.count < 6 {
            let f = 650 + 1600 * rng.unit()
            stones.append(Stone(t: 0, f1: f, f2: f * (1.52 + 0.2 * rng.unit()), amp: 0.5 + 0.5 * rng.unit(), decay: 0.006 + 0.008 * rng.unit()))
            stonesStarted += 1
        }
        var clack: Float = 0
        for i in stones.indices {
            let s = stones[i], e = exp(-s.t / s.decay)
            clack += (sin(2 * Float.pi * s.f1 * s.t) + 0.5 * sin(2 * Float.pi * s.f2 * s.t)) * e * s.amp * min(1, s.t / 0.0005)
            stones[i].t += dt
        }
        stones.removeAll { $0.t > 0.08 }
        return (bed * 0.55 + grit * 1.9 + clack * 0.55) * SlideSynth.gain * 3.2 * pow(sp, 0.6) * (0.55 + 0.45 * g)        // grass is softer overall
    }

    /// Offline render (selftests): `seconds` at constant speed and gravel.
    static func render(speed: Float, gravel: Float, seconds: Float, sampleRate: Float, seed: UInt32? = nil) -> [Float] {
        let s = SlideSynth(sampleRate: sampleRate)
        if let seed { s.rng = FoleyNoise(seed: seed) }
        return (0..<Int(seconds * sampleRate)).map { _ in s.next(speed: speed, gravel: gravel) }
    }
}
