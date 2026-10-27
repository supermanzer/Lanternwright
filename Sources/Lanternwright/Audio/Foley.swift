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
    /// The locked door's wood-on-stone knock: the door shifts about a centimetre in its frame and meets the stone reveal. A dull low thunk (a 150 Hz low-passed noise body and a
    /// short damped thump near 105 Hz, 80 to 200 Hz) and a short bright transient (1 to 3 kHz, a few ms). It is over (-40 dB) in about 60 ms and has no ringing: noise and
    /// quickly damped thump, no sustained partial. `strength` 0...1 scales level.
    static func doorKnock(strength: Float, sampleRate sr: Float, seed: UInt32 = 0xD00B) -> [Float] {
        var n = FoleyNoise(seed: seed)
        let len = Int(0.09 * sr)
        var out = [Float](repeating: 0, count: len)
        var body = Biquad.lowpass(150, sampleRate: sr), body2 = Biquad.lowpass(150, sampleRate: sr)
        var click = Biquad.bandpass(2000, q: 0.7, sampleRate: sr)
        let s = 0.35 + 0.65 * strength
        for i in 0..<len {
            let t = Float(i) / sr
            let slow = body2.process(body.process(n.next())) * 7.0 * exp(-t / 0.0165)                // the dull body, -40 dB at 0.0165 x 4.6 = 76 ms
            let thump = sin(2 * .pi * 105 * t) * exp(-t / 0.011) * 0.8                                  // a damped thump, gone in about 50 ms: a knock, not a note
            let fast = click.process(n.next()) * 2.2 * exp(-t / 0.0028)                                // the stone's short bright transient
            let attack = min(1, t / 0.0006)
            out[i] = (slow + thump + fast) * attack * s * 0.38
        }
        return out
    }

    /// The loose rattle after the knock: `count` (2...4) damped impacts of planks and ironwork a few ms apart, each a short band-limited burst (about 0.5 to 2.6 kHz) that is
    /// gone in about 10 ms, together decaying within 300 ms of the knock. No tonal ringing: the bursts are noise.
    static func doorRattle(count: Int, strength: Float, sampleRate sr: Float, seed: UInt32 = 0xD00C) -> [Float] {
        var n = FoleyNoise(seed: seed)
        let len = Int(0.30 * sr)
        var out = [Float](repeating: 0, count: len)
        var at: Float = 0.05 + 0.01 * n.unit()                                                           // the first loose impact follows the knock closely
        let s = 0.35 + 0.65 * strength
        for k in 0..<max(2, min(count, 4)) {
            let f = 700 + 1900 * n.unit(), amp = (0.55 - 0.1 * Float(k)) * (0.75 + 0.5 * n.unit()) * s
            var bp = Biquad.bandpass(f, q: 2.2, sampleRate: sr), low = Biquad.bandpass(380 + 200 * n.unit(), q: 1.6, sampleRate: sr)
            let start = Int(at * sr), dur = Int(0.022 * sr)
            for j in 0..<dur where start + j < len {
                let t = Float(j) / sr
                let x = n.next()
                out[start + j] += (bp.process(x) * exp(-t / 0.0048) + low.process(x) * 0.6 * exp(-t / 0.007)) * amp * min(1, t / 0.0004) * 0.4
            }
            at += 0.016 + 0.026 * n.unit() - 0.003 * Float(k)                                               // each follow-up arrives a little sooner as the door settles
        }
        return out
    }

    /// The whole wood-on-stone event: the knock, then the rattle. How many rattles follow depends on how hard the attempt was.
    static func doorLocked(strength: Float, sampleRate sr: Float) -> [Float] {
        let knock = doorKnock(strength: strength, sampleRate: sr)
        let rattle = doorRattle(count: 2 + Int(min(max(strength, 0), 0.999) * 3), strength: strength, sampleRate: sr)
        var out = rattle
        for i in 0..<min(knock.count, out.count) { out[i] += knock[i] }
        return out
    }

    /// Seconds after the knock that the existing pull-ring jangle starts (A2: 'then the existing pull-ring jangle, slightly delayed').
    static let jangleDelay: Float = 0.13
}
