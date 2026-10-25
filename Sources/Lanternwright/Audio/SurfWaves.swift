import Foundation

/// The sea as discrete waves (F02 A1, user notes #18 and #27: "like one wave always breaking"). A pure function of time, so the synth, the selftests and any
/// future visual can ask the same question: which waves are in progress at time t, and how far into each one are we.
///
/// A wave set arrives every 6 to 11 s (each gap an independent value from a fixed hash, mean 8.5 s: the spacing is a random walk, so it never settles into a rhythm that could be heard as a loop),
/// about one in three is much larger. Each wave is: a rising swash (1.2 to 2 s), a crest hiss at its peak, and a retreating drain (2.4 to 4 s) whose
/// low-pass falls as the water runs back; then a quiet gap before the next.
enum SurfWaves {
    static let spacing: Float = 8.5
    static let minGap: Float = 6, maxGap: Float = 11

    @inline(__always) private static func h(_ n: Int, _ salt: UInt32) -> Float {
        var x = UInt32(truncatingIfNeeded: n) &* 0x9E3779B1 &+ salt &* 0x85EBCA6B
        x ^= x >> 15; x = x &* 0x2C1B3C6D; x ^= x >> 12; x = x &* 0x297A2D39; x ^= x >> 15
        return Float(x >> 8) / Float(1 << 24)
    }
    /// Start times of the first 20 000 waves (about 47 hours); beyond that the table repeats from its first wave.
    private static let starts: [Float] = {
        var t: Float = 3, out: [Float] = []
        out.reserveCapacity(20_000)
        for n in 0..<20_000 { out.append(t); t += minGap + (maxGap - minGap) * h(n, 1) }
        return out
    }()
    static func start(_ n: Int) -> Float { starts[n % starts.count] + Float(n / starts.count) * starts[starts.count - 1] }
    /// Index of the first wave that could still be sounding at time t (a wave lasts at most 4 s of swash and 6.4 s of drain).
    private static func firstIndex(_ t: Float) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if starts[mid] < t - 12 { lo = mid + 1 } else { hi = mid } }
        return lo
    }
    /// 1 for a big wave (about every third), 0.35...0.7 otherwise.
    static func size(_ n: Int) -> Float { h(n, 2) > 0.66 ? 1.0 : 0.35 + 0.35 * h(n, 3) }
    static func rise(_ n: Int) -> Float { 1.2 + 0.8 * h(n, 4) }
    static func drain(_ n: Int) -> Float { 2.4 + 1.6 * h(n, 5) }
    /// +1 or -1: which way along the shore this wave travels (the stereo image sweeps with it).
    static func direction(_ n: Int) -> Float { h(n, 6) < 0.5 ? -1 : 1 }

    struct State {
        var body: Float = 0           // the wash: swash and drain, 0...1
        var hiss: Float = 0           // the crest's foam, 0...1 (a short pulse at the top of each swash)
        var cutoff: Float = 1         // multiplier on the wash's low-pass: 1 at the crest, falling to about 0.4 as the water drains back
        var sweep: Float = 0          // -1...1: the stereo position along the shore, travelling with the wave
    }

    /// The state of the sea at time `t` (seconds).
    static func state(time t: Float) -> State {
        var s = State()
        let first = firstIndex(t)
        var weight: Float = 0, cutoffSum: Float = 0, sweepSum: Float = 0
        for n in first..<min(first + 6, starts.count) {
            let u = t - start(n)
            let r = rise(n), d = drain(n), z = size(n)
            guard u > 0, u < r + d * 1.6 else { continue }
            var b: Float
            if u < r { let x = u / r; b = z * x * x * (3 - 2 * x) }                       // the swash builds
            else { b = z * exp(-(u - r) / (d / 3)) }                                     // and drains (about -26 dB after d seconds)
            s.body += b
            s.hiss += z * exp(-((u - r) / 0.35) * ((u - r) / 0.35)) * (u < r ? 0.6 : 1)    // foam at the crest
            let drainT = min(max((u - r) / d, 0), 1)
            cutoffSum += b * (1 - 0.6 * drainT); weight += b
            sweepSum += b * direction(n) * (2 * min(u / (r + d), 1) - 1)
        }
        s.body = min(s.body, 1.2)
        s.hiss = min(s.hiss, 1)
        s.cutoff = weight > 1e-4 ? cutoffSum / weight : 0.4
        s.sweep = weight > 1e-4 ? max(-1, min(1, sweepSum / weight)) : 0
        return s
    }

    /// A slow, smooth swell with no discrete events, for the far shore: three incommensurate periods, 0.1 to 0.2 Hz.
    static func farSwell(time t: Float) -> Float {
        0.5 + 0.5 * (0.5 * sin(t * 2 * .pi / 7.3) + 0.3 * sin(t * 2 * .pi / 10.1 + 1.1) + 0.2 * sin(t * 2 * .pi / 13.7 + 2.3))
    }
}
