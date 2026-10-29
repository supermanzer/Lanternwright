import Foundation

/// S03.4 (optional "follow the light" lead): when the player returns to Varrow the trail's stone lanterns, which are lit all the time, flare one after another along the route toward the
/// lighthouse door, `step` seconds apart, and settle back. Each lantern's light core is its own scene item (`lantern_core_<k>`, in route order) so it has its own emission; a pure function
/// of the time since the return gives each one's glow, so the pattern is reproducible and testable.
enum LanternChain {
    static let coreName = "lantern_core_"
    /// The lanterns' normal glow (the emissive strength they have always had) and the extra a flare adds at its peak.
    static let baseGlow: Float = 8, flareGlow: Float = 16
    /// Seconds between one lantern flaring and the next, and how long a flare lasts (rise 0.25 s, then a slow fall).
    static let step: Float = 0.4, duration: Float = 1.6

    /// The emissive strength of lantern `k` at `t` seconds after the return (t < 0: not started).
    static func glow(index k: Int, time t: Float) -> Float {
        let u = t - Float(k) * step
        guard u > 0, u < duration else { return baseGlow }
        let rise: Float = 0.25
        let f = u < rise ? u / rise : 1 - (u - rise) / (duration - rise)
        return baseGlow + flareGlow * f * f * (3 - 2 * f)
    }
    /// Seconds after the return when the last of `count` lanterns has settled.
    static func total(count: Int) -> Float { Float(max(count, 1) - 1) * step + duration }
}
