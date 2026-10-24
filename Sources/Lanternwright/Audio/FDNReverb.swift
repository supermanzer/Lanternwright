import Foundation

/// An 8-line feedback delay network: eight mutually prime delay lines whose outputs are mixed back into each other by an
/// orthogonal Hadamard matrix (so the mixing itself neither adds nor removes energy), each line attenuated so the tail
/// falls 60 dB in `rt60` seconds, with a one-pole low-pass in the loop so highs die faster than lows, as in real rooms.
/// Far denser and smoother than a two-tap echo: a chime blooms into a room instead of repeating.
struct FDNReverb {
    static let lines = 8
    /// Delay lengths in samples at 44.1 kHz (mutually prime, 23 to 66 ms), rescaled to the actual sample rate.
    private static let base: [Int] = [1009, 1307, 1481, 1699, 1951, 2203, 2467, 2897]

    private var buffers: [[Float]]
    private var positions = [Int](repeating: 0, count: FDNReverb.lines)
    private var damp = [Float](repeating: 0, count: FDNReverb.lines)
    private var gains = [Float](repeating: 0, count: FDNReverb.lines)
    private let sampleRate: Float
    private(set) var rt60: Float = 1.5
    /// 0 = bright tail, 1 = dark (loop low-pass coefficient).
    var darkness: Float = 0.45

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        buffers = FDNReverb.base.map { [Float](repeating: 0, count: max(8, Int(Float($0) * sampleRate / 44100))) }
        setDecay(1.5)
    }

    /// Set the time (s) for the tail to fall by 60 dB. Each line's gain is 10^(-3 d / rt60) for its own delay d.
    mutating func setDecay(_ seconds: Float) {
        rt60 = min(max(seconds, 0.2), 12)
        for i in 0..<FDNReverb.lines {
            let d = Float(buffers[i].count) / sampleRate
            gains[i] = pow(10, -3 * d / rt60)
        }
    }

    /// One stereo sample in, one out (wet only).
    mutating func process(left: Float, right: Float) -> (Float, Float) {
        var out = [Float](repeating: 0, count: FDNReverb.lines)
        for i in 0..<FDNReverb.lines {
            let b = buffers[i]
            out[i] = b[positions[i]]
            // Loop damping: a one-pole low-pass on what is read from the line.
            damp[i] += (1 - darkness) * (out[i] - damp[i])
            out[i] = damp[i]
        }
        // Hadamard mixing (8 x 8, scaled by 1/sqrt(8) so it is orthogonal): fast Walsh-Hadamard transform.
        var h = out
        var span = 1
        while span < FDNReverb.lines {
            var i = 0
            while i < FDNReverb.lines {
                for j in i..<(i + span) { let a = h[j], b = h[j + span]; h[j] = a + b; h[j + span] = a - b }
                i += span * 2
            }
            span *= 2
        }
        let norm: Float = 1 / Float(8).squareRoot()
        for i in 0..<FDNReverb.lines {
            let input = (i % 2 == 0 ? left : right) * 0.5
            buffers[i][positions[i]] = h[i] * norm * gains[i] + input
            positions[i] = (positions[i] + 1) % buffers[i].count
        }
        // Stereo taps: even lines left, odd lines right (decorrelated by their different lengths).
        var l: Float = 0, r: Float = 0
        for i in 0..<FDNReverb.lines { if i % 2 == 0 { l += out[i] } else { r += out[i] } }
        return (l * 0.5, r * 0.5)
    }
}
