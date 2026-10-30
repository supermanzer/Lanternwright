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
    static func doorRattle(count: Int, strength: Float, sampleRate sr: Float, seed: UInt32 = 0xD00C) -> [Float] { doorRattleWithTimes(count: count, strength: strength, sampleRate: sr, seed: seed).0 }

    /// The same, with the start time (s) of each impact (the selftests check their number, spacing and that each one is audible).
    static func doorRattleWithTimes(count: Int, strength: Float, sampleRate sr: Float, seed: UInt32 = 0xD00C) -> ([Float], [Float]) {
        var n = FoleyNoise(seed: seed)
        let len = Int(0.30 * sr)
        var out = [Float](repeating: 0, count: len)
        var at: Float = 0.05 + 0.01 * n.unit()                                                           // the first loose impact follows the knock closely
        let s = 0.35 + 0.65 * strength
        var times: [Float] = []
        for k in 0..<max(2, min(count, 4)) {
            times.append(at)
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
        return (out, times)
    }

    /// F05 A1 (#63: the pull-ring jangle was four short pure tones, 1.6 to 2.8 kHz: "a computer alert"): the iron ring and its plate clank. A struck iron fitting is not a pitch: each of
    /// `hits` (3...5, spaced 55 to 95 ms, each softer and shorter than the last) is a noise burst through nine resonances at INHARMONIC, per-hit random frequencies between 1 and 4.2 kHz
    /// (Q 5, so they are smeared, never a sine) over a short broadband tick and a low iron-on-wood "tock" (300 to 700 Hz), decaying in 25 to 70 ms. The hits never repeat a frequency, so the
    /// long-time spectrum is a smooth band of 1 to 4 kHz, not a few lines. Starts at 0 s; `Foley.jangleDelay` is where `doorLocked` places it.
    static func ironClank(hits: Int, strength: Float, sampleRate sr: Float, seed: UInt32 = 0xD00D) -> [Float] {
        var n = FoleyNoise(seed: seed)
        let count = max(3, min(hits, 5))
        let len = Int(0.42 * sr)
        var out = [Float](repeating: 0, count: len)
        let s = 0.35 + 0.65 * strength
        var at: Float = 0
        for k in 0..<count {
            let fall = 1 - 0.17 * Float(k)
            let tau = (0.058 - 0.008 * Float(k)) * (0.8 + 0.4 * n.unit())
            var res = (0..<9).map { _ in Biquad.bandpass(1000 + 3200 * n.unit(), q: 5, sampleRate: sr) }
            var tick = Biquad.bandpass(3400 + 1500 * n.unit(), q: 0.6, sampleRate: sr)
            var tock = Biquad.bandpass(300 + 400 * n.unit(), q: 0.9, sampleRate: sr)
            var wash = Biquad.bandpass(2300, q: 0.45, sampleRate: sr)                                          // the ring's broadband scrape: fills the gaps between the resonances
            let start = Int(at * sr), dur = Int(0.26 * sr)
            for j in 0..<dur where start + j < len {
                let t = Float(j) / sr
                let x = n.next()
                var ring: Float = 0
                for i in res.indices { ring += res[i].process(x) }
                let v = ring * 0.95 * exp(-t / tau) + tick.process(x) * 1.4 * exp(-t / 0.0035) + tock.process(x) * 1.2 * exp(-t / 0.012) + wash.process(x) * 1.6 * exp(-t / 0.03)
                out[start + j] += v * fall * s * min(1, t / 0.0004) * 0.14
            }
            at += 0.055 + 0.04 * n.unit()
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

    /// The whole wood-on-stone-and-iron event: the knock, then the rattle, then the iron ring's clank (`jangleDelay` after the knock). How many rattles and clanks follow depends on how hard the attempt was.
    static func doorLocked(strength: Float, sampleRate sr: Float) -> [Float] {
        let knock = doorKnock(strength: strength, sampleRate: sr)
        let rattle = doorRattle(count: 2 + Int(min(max(strength, 0), 0.999) * 3), strength: strength, sampleRate: sr)
        let clank = ironClank(hits: 3 + Int(min(max(strength, 0), 0.999) * 3), strength: strength, sampleRate: sr)
        let off = Int(jangleDelay * sr)
        var out = [Float](repeating: 0, count: max(rattle.count, off + clank.count))
        for i in 0..<rattle.count { out[i] += rattle[i] }
        for i in 0..<min(knock.count, out.count) { out[i] += knock[i] }
        for i in 0..<clank.count { out[off + i] += clank[i] }
        return out
    }

    /// Seconds after the knock that the iron ring's clank starts (A2: the pull ring answers a moment after the door meets the stone).
    static let jangleDelay: Float = 0.13
}
