import Foundation

/// Splashing and wading water, built from what makes the sound of water: bubbles (F03 A4, note #49: the shallows "sound like shag carpet and not like water at all").
/// A bubble in water rings at the Minnaert frequency f = 3.26 / r Hz (r in metres: a 1 mm bubble rings near 3.3 kHz, a 3 mm bubble near 1.1 kHz) as a quickly damped sine whose
/// pitch glides UP by 10 to 20 % over its short life (it shrinks as it rises and the water stiffens). So water is a stream of such events, not filtered noise:
/// - bubbles of 0.55 to 4 mm radius (about 0.8 to 5.9 kHz), 5 to 30 ms long (a bigger bubble rings longer and louder), each with its own glide;
/// - a footfall in the water is a low splash body (100 to 400 Hz) and a handful of bubbles, more of them and louder with speed;
/// - the continuous wash while wading is a SPARSE stream of the same bubbles, a few to a few tens a second.
final class BubbleSynth {
    let sampleRate: Float
    var rng: FoleyNoise
    private struct Bubble { var f0: Float; var glide: Float; var life: Float; var amp: Float; var age: Float = 0; var delay: Float; var phase: Float = 0; var pan: Float }
    private var bubbles: [Bubble] = []
    private struct Body { var age: Float = 0; var amp: Float; var lp1: Float = 0, lp2: Float = 0; var delay: Float; var pan: Float; var decay: Float }
    private var bodies: [Body] = []
    private(set) var bubblesStarted = 0
    var isActive: Bool { !bubbles.isEmpty || !bodies.isEmpty }
    /// Peak amplitude of a 2 mm bubble at full level (linear, before the synth's master): water here is quiet.
    static let gain: Float = 0.075

    init(sampleRate: Float, seed: UInt32 = 0xB0B1E) { self.sampleRate = sampleRate; rng = FoleyNoise(seed: seed) }

    /// What a random bubble is: radius (mm), ring frequency (Hz) from f = 3.26 / r, life (s), glide (fraction of f0 gained over the life) and relative loudness.
    struct Params { var radiusMM: Float, frequency: Float, life: Float, glide: Float, loudness: Float }
    static func randomParams(_ rng: inout FoleyNoise) -> Params {
        let rMM = 0.55 * pow(4.0 / 0.55, rng.unit())                                   // log-uniform 0.55 to 4 mm: small bubbles are as common as big ones
        let f = 3.26 / (rMM / 1000)
        let size = (rMM - 0.55) / 3.45
        let life = min(0.030, max(0.005, 0.005 + 0.025 * size * (0.7 + 0.6 * rng.unit())))
        return Params(radiusMM: rMM, frequency: f, life: life, glide: 0.10 + 0.10 * rng.unit(), loudness: pow(rMM / 2, 1.3))
    }

    /// One bubble, `level` 0...1 (relative), starting `delay` s from now.
    func spawn(level: Float, delay: Float = 0, pan: Float = 0) {
        guard bubbles.count < 80 else { return }
        let p = BubbleSynth.randomParams(&rng)
        bubbles.append(Bubble(f0: p.frequency, glide: p.glide, life: p.life, amp: p.loudness * level * BubbleSynth.gain, delay: delay, pan: pan))
        bubblesStarted += 1
    }

    /// How many bubbles a footfall in the water throws: a handful, more with speed (`strength` 0...1: 0.3 is a slow wade, 1 a run or a plunge).
    static func burstCount(strength: Float) -> Int { 3 + Int((9 * min(max(strength, 0), 1)).rounded()) }

    /// A footfall or an entry: a low splash body (100 to 400 Hz) and `burstCount` bubbles over the next 0.15 s.
    func burst(strength: Float, pan: Float = 0) {
        let s = min(max(strength, 0), 1.5)
        bodies.append(Body(amp: 0.34 * pow(s, 1.5) + 0.025, delay: 0, pan: pan, decay: 0.032 + 0.03 * min(s, 1)))
        let n = BubbleSynth.burstCount(strength: s)
        for k in 0..<n { spawn(level: (1.0 + 1.1 * s) * (0.6 + 0.4 * rng.unit()), delay: 0.012 + 0.14 * Float(k) / Float(max(n, 1)) * (0.6 + 0.8 * rng.unit()), pan: pan) }
    }

    /// One stereo sample. `washRate` is the number of wash bubbles per second to throw now (0 = none), `washLevel` their relative loudness.
    func next(washRate: Float = 0, washLevel: Float = 0.5) -> (Float, Float) {
        let dt = 1 / sampleRate
        if washRate > 0 && rng.unit() < washRate * dt { spawn(level: washLevel * (0.35 + 0.65 * rng.unit()), pan: 0.7 * rng.next()) }
        if bubbles.isEmpty && bodies.isEmpty { return (0, 0) }
        var l: Float = 0, r: Float = 0
        for i in bubbles.indices {
            if bubbles[i].delay > 0 { bubbles[i].delay -= dt; continue }
            var b = bubbles[i]
            let t = b.age
            let f = b.f0 * (1 + b.glide * min(1, t / b.life))
            b.phase += 2 * Float.pi * f * dt
            if b.phase > 2 * Float.pi { b.phase -= 2 * Float.pi }
            let x = sin(b.phase) * b.amp * exp(-6.9 * t / b.life) * min(1, t / 0.0004)
            l += x * (0.5 - 0.5 * b.pan); r += x * (0.5 + 0.5 * b.pan)
            b.age += dt
            bubbles[i] = b
        }
        bubbles.removeAll { $0.age > $0.life * 1.05 }
        for i in bodies.indices {
            if bodies[i].delay > 0 { bodies[i].delay -= dt; continue }
            var b = bodies[i]
            let w = rng.next(), a = 1 - exp(-2 * Float.pi * 260 * dt)
            b.lp1 += a * (w - b.lp1); b.lp2 += a * (b.lp1 - b.lp2)
            let x = b.lp2 * 6.0 * b.amp * exp(-b.age / b.decay) * min(1, b.age / 0.004)
            l += x * (0.5 - 0.5 * b.pan); r += x * (0.5 + 0.5 * b.pan)
            b.age += dt
            bodies[i] = b
        }
        bodies.removeAll { $0.age > $0.decay * 7 }
        return (l, r)
    }
}
