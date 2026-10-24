import simd

/// The one wind. Gusts are a slow, irregular 0...1 built from three incommensurate sines and travel across the land at
/// `travelSpeed`, so a gust reaches a hilltop later than the beach. The grass leans along `direction` by `strength`, and the
/// audio wind's gusting is this same `gust` function, so the rustle you see and the rush you hear are the same event.
enum Wind {
    /// Where the wind blows toward, on the ground plane (x east, z south): from the west-north-west.
    static let direction = simd_normalize(SIMD2<Float>(0.86, 0.5))
    static let travelSpeed: Float = 9

    /// Gust at a given time, 0...1.
    static func gust(time t: Float) -> Float {
        0.5 + 0.5 * (0.55 * sin(t * 0.43) + 0.3 * sin(t * 0.81 + 1.3) + 0.15 * sin(t * 1.9 + 2.1))
    }

    /// Strength 0...1 at a place and time: the gust as it reaches this spot, stronger up high.
    static func strength(at p: SIMD3<Float>, time t: Float) -> Float {
        let delay = simd_dot(SIMD2(p.x, p.z), direction) / travelSpeed
        let altitude = 0.55 + 0.45 * min(max(p.y / 70, 0), 1)
        return min(max(gust(time: t - delay) * altitude, 0), 1)
    }

    /// Wind velocity on the ground plane (direction x strength).
    static func vector(at p: SIMD3<Float>, time t: Float) -> SIMD2<Float> { direction * strength(at: p, time: t) }
}
