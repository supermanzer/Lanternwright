import Foundation

/// Small offline-built one-shot sounds (F03 A2 onward): impacts made of band-limited noise bursts, rendered into a mono buffer that the synth plays back. Building them as
/// buffers (rather than as pure tones) keeps wood on stone from ringing like a bell, and lets the selftests measure exactly what is played.
struct FoleyNoise {
    var s: UInt32
    init(seed: UInt32) { s = seed == 0 ? 0x9E37_79B9 : seed }
    mutating func next() -> Float { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return Float(Int32(bitPattern: s)) / Float(Int32.max) }     // -1...1
    mutating func unit() -> Float { 0.5 + 0.5 * next() }                                                                                  // 0...1
}

/// RBJ biquad (transposed direct form II): a band-pass of unit peak gain, or a low-pass.
struct Biquad {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    var z1: Float = 0, z2: Float = 0
    static func bandpass(_ f: Float, q: Float, sampleRate sr: Float) -> Biquad {
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
    }
    static func lowpass(_ f: Float, q: Float = 0.707, sampleRate sr: Float) -> Biquad {
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr, alpha = sin(w) / (2 * q), a0 = 1 + alpha, c = cos(w)
        return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }
    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

enum Foley {
    /// F07 A-door (#72: "like a snare drum, far too thin and staccato, no weight of solid wood or stone"; the third complaint about this sound): a PHYSICAL model of a heavy oak door (about 5 cm of it) shifting a
    /// centimetre against its stone jamb, with the iron ring on its plate. Built from four layers, each of the kind of thing that makes the sound:
    ///  1. THE THUD, the door's mass meeting stone: a low modal body (70-140 Hz: four damped modes at 72, 96, 118 and 138 Hz that ring for 150-250 ms) over a low-passed noise body; attack about 8 ms to full (3-8 ms from 10 % to 90 %: not an impulse).
    ///  2. THE WOOD KNOCK, 200-500 Hz: three damped modes at 230, 330 and 470 Hz and a band of noise, decaying in about 60 ms, 6 dB under the thud.
    ///  3. THE FRICTION CREAK, planks scraping the stone: noise through 300-1500 Hz, chopped by a random stick-slip (a 25-60 Hz wobble), 60-330 ms after the thud, 16 dB under it.
    ///  4. THE IRON RING'S CLINK, 1.5-3 kHz, 18 dB under the thud, ringing about 150 ms (noise through nine resonances of Q 6 at random inharmonic frequencies: a smear, never a pitch), twice (the ring swings back).
    /// The only things above 1 kHz are the clink and the creak's top, both quiet and noise-built. `strength` 0...1 scales level (and the creak and clink a little more).
    static func doorLocked(strength: Float, sampleRate sr: Float, seed: UInt32 = 0xD00B) -> [Float] {
        var n = FoleyNoise(seed: seed)
        let len = Int(0.95 * sr)
        var out = [Float](repeating: 0, count: len)
        let s = 0.35 + 0.65 * strength
        // 1. the thud
        let modes: [(f: Float, tau: Float, a: Float)] = [(72, 0.085, 1.0), (96, 0.07, 0.85), (118, 0.06, 0.6), (138, 0.05, 0.45)]
        var bodyA = Biquad.lowpass(150, sampleRate: sr), bodyB = Biquad.lowpass(150, sampleRate: sr)
        // 2. the knock
        let knockModes: [(f: Float, a: Float)] = [(230, 0.5), (330, 0.4), (470, 0.25)]
        var knockBand = Biquad.bandpass(330, q: 1.4, sampleRate: sr)
        // 3. the creak
        var creakA = Biquad.bandpass(480, q: 1.1, sampleRate: sr), creakB = Biquad.bandpass(950, q: 1.2, sampleRate: sr), creakC = Biquad.bandpass(1350, q: 1.3, sampleRate: sr)
        var chop: Float = 0.5, chopTarget: Float = 0.5, chopLeft = 0
        // 4. the clink: two hits of nine resonances each
        var clinkHits: [(start: Int, res: [Biquad], amp: Float)] = []
        for (k, at) in [Float(0.11), 0.205].enumerated() {
            clinkHits.append((Int(at * sr), (0..<9).map { _ in Biquad.bandpass(1500 + 1500 * n.unit(), q: 6, sampleRate: sr) }, k == 0 ? 1.0 : 0.7))
        }
        for i in 0..<len {
            let t = Float(i) / sr
            let attack = min(1, t / 0.008); let att = attack * attack * (3 - 2 * attack)
            var thud: Float = 0
            for m in modes { thud += m.a * sin(2 * .pi * m.f * t) * exp(-t / m.tau) }
            thud += bodyB.process(bodyA.process(n.next())) * 5.0 * exp(-t / 0.05)
            var knock: Float = 0
            if t >= 0.004 {
                let u = t - 0.004
                for m in knockModes { knock += m.a * sin(2 * .pi * m.f * u) * exp(-u / 0.016) }
                knock += knockBand.process(n.next()) * 1.6 * exp(-u / 0.02)
            }
            var creak: Float = 0
            if t >= 0.06 && t < 0.33 {
                if chopLeft <= 0 { chopTarget = 0.2 + 0.8 * n.unit(); chopLeft = Int(sr / (25 + 35 * n.unit())) }
                chopLeft -= 1; chop += (chopTarget - chop) * 0.02
                let u = t - 0.06, env = min(1, u / 0.05) * min(1, (0.27 - u) / 0.1)
                let x = n.next()
                creak = (creakA.process(x) * 0.9 + creakB.process(x) * 0.7 + creakC.process(x) * 0.45) * chop * max(env, 0)
            }
            var clink: Float = 0
            for h in clinkHits.indices where i >= clinkHits[h].start {
                let u = Float(i - clinkHits[h].start) / sr
                let x = n.next()
                var ring: Float = 0
                for r in clinkHits[h].res.indices { ring += clinkHits[h].res[r].process(x) }
                clink += ring * 0.55 * exp(-u / 0.045) * clinkHits[h].amp
            }
            out[i] = (thud * 0.42 + knock * 0.9 * 0.42 + creak * (0.16 + 0.1 * strength) * 0.42 * 2.2 + clink * (0.125 + 0.05 * strength) * 0.42) * att * s * 0.65
        }
        return out
    }

    /// F06 A4: the lens ring turning one twelfth (stone-on-brass). About 0.6 s: a LOW grind (noise through a 250-1400 Hz band, roughened by a 20-45 Hz random amplitude wobble so it scrapes, not hums) over a brass
    /// body's dull rumble (noise below 180 Hz), swelling in 90 ms and easing off, and at the end the detent: a soft click (a short 1.5-3.5 kHz transient) with a small low thunk as the ring seats. All noise,
    /// no sustained partial. Starts at 0 s.
    static func ringTurn(sampleRate sr: Float, seed: UInt32 = 0xB1A5) -> [Float] {
        var n = FoleyNoise(seed: seed)
        let len = Int(0.78 * sr)
        var out = [Float](repeating: 0, count: len)
        var grind = Biquad.bandpass(620, q: 0.55, sampleRate: sr), grindLow = Biquad.bandpass(330, q: 0.8, sampleRate: sr), grindHigh = Biquad.bandpass(1250, q: 0.7, sampleRate: sr)
        var rumbleA = Biquad.lowpass(170, sampleRate: sr), rumbleB = Biquad.lowpass(170, sampleRate: sr)
        var click = Biquad.bandpass(2300, q: 0.6, sampleRate: sr), thunk = Biquad.lowpass(210, sampleRate: sr), thunk2 = Biquad.lowpass(210, sampleRate: sr)
        var wob: Float = 0.5, wobTarget: Float = 0.5, wobLeft = 0
        let grindEnd: Float = 0.52, clickAt: Float = 0.56
        for i in 0..<len {
            let t = Float(i) / sr
            if wobLeft <= 0 { wobTarget = 0.35 + 0.65 * n.unit(); wobLeft = Int(sr / (20 + 25 * n.unit())) }
            wobLeft -= 1; wob += (wobTarget - wob) * 0.004 * 44100 / sr * 6
            let env = min(1, t / 0.09) * (t < grindEnd ? 1 - 0.45 * (t / grindEnd) : exp(-(t - grindEnd) / 0.03))
            let x = n.next()
            let g = (grind.process(x) * 0.9 + grindLow.process(x) * 0.8 + grindHigh.process(x) * 0.45) * wob
            let body = rumbleB.process(rumbleA.process(n.next())) * 5.5
            var v = (g * 0.75 + body * 0.55) * env
            if t >= clickAt {
                let u = t - clickAt
                v += click.process(n.next()) * 2.0 * exp(-u / 0.0026) + thunk2.process(thunk.process(n.next())) * 7.0 * exp(-u / 0.022)
            }
            out[i] = v * 0.22
        }
        return out
    }
}
