import simd

/// Deterministic coherent noise. All world generation goes through this (never Float.random)
/// so the island is identical on every run and every machine.
///
/// Why integer hashing: lattice noise needs a repeatable "random" value per grid corner. Hashing the
/// integer corner coordinates gives that with no stored table and no mutable state.
struct Noise {
    var seed: UInt32

    init(seed: UInt32 = 1337) { self.seed = seed }

    /// 2D integer hash -> uniformly distributed UInt32.
    @inline(__always)
    func hash(_ x: Int32, _ y: Int32) -> UInt32 {
        var h = seed ^ (UInt32(bitPattern: x) &* 0x27d4eb2d) ^ (UInt32(bitPattern: y) &* 0x165667b1)
        h ^= h >> 15; h = h &* 0x2c1b3c6d
        h ^= h >> 12; h = h &* 0x297a2d39
        h ^= h >> 15
        return h
    }

    /// Hash mapped to 0..1.
    @inline(__always)
    func unit(_ x: Int32, _ y: Int32) -> Float { Float(hash(x, y) >> 8) / Float(1 << 24) }

    @inline(__always)
    private func fade(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }   // quintic: C2-continuous

    /// Value noise, range 0..1: smoothly interpolated random corner values. Cheap but blocky-looking.
    func value(_ x: Float, _ y: Float) -> Float {
        let xi = Int32(floor(x)), yi = Int32(floor(y))
        let fx = fade(x - Float(xi)), fy = fade(y - Float(yi))
        let a = unit(xi, yi), b = unit(xi + 1, yi), c = unit(xi, yi + 1), d = unit(xi + 1, yi + 1)
        return mix(mix(a, b, fx), mix(c, d, fx), fy)
    }

    private static let grads: [SIMD2<Float>] = {
        let d: Float = 0.70710678
        return [SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0, 1), SIMD2(0, -1), SIMD2(d, d), SIMD2(-d, d), SIMD2(d, -d), SIMD2(-d, -d)]
    }()

    /// Gradient (Perlin) noise, range about -1..1. Each corner has a random direction; the result is the
    /// blended dot product with the offset to the sample point, which avoids value noise's grid look.
    func perlin(_ x: Float, _ y: Float) -> Float {
        let xi = Int32(floor(x)), yi = Int32(floor(y))
        let fx = x - Float(xi), fy = y - Float(yi)
        func g(_ ix: Int32, _ iy: Int32, _ dx: Float, _ dy: Float) -> Float {
            let gr = Noise.grads[Int(hash(ix, iy) & 7)]
            return gr.x * dx + gr.y * dy
        }
        let n00 = g(xi, yi, fx, fy), n10 = g(xi + 1, yi, fx - 1, fy)
        let n01 = g(xi, yi + 1, fx, fy - 1), n11 = g(xi + 1, yi + 1, fx - 1, fy - 1)
        let u = fade(fx), v = fade(fy)
        return mix(mix(n00, n10, u), mix(n01, n11, u), v) * 1.4142   // 1/0.707 normalises to ~[-1, 1]
    }

    /// Fractal Brownian motion: octaves of Perlin at rising frequency and falling amplitude. Range about -1..1.
    func fbm(_ x: Float, _ y: Float, octaves: Int = 5, lacunarity: Float = 2, gain: Float = 0.5) -> Float {
        var sum: Float = 0, amp: Float = 1, norm: Float = 0, f: Float = 1
        for o in 0..<octaves {
            // Offset each octave so lattices don't line up and create axis artefacts.
            sum += amp * perlin(x * f + Float(o) * 17.3, y * f - Float(o) * 31.7)
            norm += amp
            amp *= gain; f *= lacunarity
        }
        return sum / norm
    }

    /// Ridged multifractal, range about 0..1: sharp crests, good for rocky ridges.
    func ridged(_ x: Float, _ y: Float, octaves: Int = 5, lacunarity: Float = 2, gain: Float = 0.5) -> Float {
        var sum: Float = 0, amp: Float = 1, norm: Float = 0, f: Float = 1
        for o in 0..<octaves {
            let n = 1 - abs(perlin(x * f + Float(o) * 17.3, y * f - Float(o) * 31.7))
            sum += amp * n * n
            norm += amp
            amp *= gain; f *= lacunarity
        }
        return sum / norm
    }

    /// Domain warp: bends the sample coordinates with low-frequency noise so shapes become organic.
    func warp(_ x: Float, _ y: Float, strength: Float, frequency: Float = 0.01) -> SIMD2<Float> {
        SIMD2(x + strength * perlin(x * frequency + 5.2, y * frequency + 1.3),
              y + strength * perlin(x * frequency - 8.7, y * frequency + 9.4))
    }
}
