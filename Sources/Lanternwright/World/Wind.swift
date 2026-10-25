import simd

/// The one wind (F02 A3). Everything that moves or sounds with the wind reads THIS: the grass bends per blade, the conifer crowns sway, the clouds and mist drift
/// along `direction`, and the audio wind's level is `strength` at the listener's feet at the game's own clock.
///
/// Gusts are a slow, irregular 0...1 (periods of about 11, 7 and 4 s) that travel across the land at `travelSpeed` (9 m/s), so a gust reaches a hilltop later than
/// the beach, and a blade of grass 50 m upwind leans about 5.5 s before the gust reaches you: you can see a gust coming, and it arrives with the sound.
/// The shader (`Wind.mslSource`) is generated from the same constants, so Swift and Metal cannot disagree.
enum Wind {
    /// Where the wind blows toward, on the ground plane (x east, z south): from the west-north-west.
    static let direction = simd_normalize(SIMD2<Float>(0.86, 0.5))
    static let travelSpeed: Float = 9
    /// Angular frequencies (rad/s) and phases of the three gust components, and their weights.
    static let omega: SIMD3<Float> = SIMD3(2 * .pi / 11.0, 2 * .pi / 7.1, 2 * .pi / 4.3)
    static let phase: SIMD3<Float> = SIMD3(0, 1.3, 2.1)
    static let weight: SIMD3<Float> = SIMD3(0.5, 0.32, 0.18)
    /// Squares the gust so lulls are long and gusts are peaks (a lull near 0, a gust up to 1).
    static let shape: Float = 1.6
    /// How much stronger the wind is high up: 0.55 at sea level, 1 at 70 m and above.
    static let altitudeBase: Float = 0.55, altitudeSpan: Float = 0.45, altitudeTop: Float = 70

    /// Gust at a given time, 0...1 (before altitude).
    static func gust(time t: Float) -> Float {
        let g = 0.5 + 0.5 * (weight.x * sin(t * omega.x + phase.x) + weight.y * sin(t * omega.y + phase.y) + weight.z * sin(t * omega.z + phase.z))
        return pow(min(max(g, 0), 1), shape)
    }

    /// Strength 0...1 at a place and time: the gust as it reaches this spot, stronger up high.
    static func strength(at p: SIMD3<Float>, time t: Float) -> Float {
        let delay = simd_dot(SIMD2(p.x, p.z), direction) / travelSpeed
        let altitude = altitudeBase + altitudeSpan * min(max(p.y / altitudeTop, 0), 1)
        return min(max(gust(time: t - delay) * altitude, 0), 1)
    }

    /// Wind velocity on the ground plane (direction x strength).
    static func vector(at p: SIMD3<Float>, time t: Float) -> SIMD2<Float> { direction * strength(at: p, time: t) }

    /// The same functions in Metal, generated from the constants above: `wind_strength(float3 worldPos, float time)` and `wind_dir`.
    static var mslSource: String {
        """
        constant float2 WIND_DIR = float2(\(direction.x), \(direction.y));
        constant float3 WIND_OMEGA = float3(\(omega.x), \(omega.y), \(omega.z));
        constant float3 WIND_PHASE = float3(\(phase.x), \(phase.y), \(phase.z));
        constant float3 WIND_WEIGHT = float3(\(weight.x), \(weight.y), \(weight.z));
        inline float wind_gust(float t) {
            float g = 0.5 + 0.5 * dot(WIND_WEIGHT, sin(t * WIND_OMEGA + WIND_PHASE));
            return pow(clamp(g, 0.0, 1.0), \(shape));
        }
        inline float wind_strength(float3 p, float t) {
            float delay = dot(p.xz, WIND_DIR) / \(travelSpeed);
            float altitude = \(altitudeBase) + \(altitudeSpan) * clamp(p.y / \(altitudeTop), 0.0, 1.0);
            return clamp(wind_gust(t - delay) * altitude, 0.0, 1.0);
        }

        """
    }
}
