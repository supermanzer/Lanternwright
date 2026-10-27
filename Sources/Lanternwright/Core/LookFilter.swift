import simd

/// M10.1: a calmer camera. Takes the per-frame look delta (radians) and returns a smoothed, soft-limited delta. Pure and driven by `dt`,
/// never by the frame count, so the same physical sweep turns the camera the same amount at 30, 60 or 120 fps.
///
/// Two stages, both scaled by `calm` (0...1, default 0.6; 0 = the raw delta, returned untouched):
/// 1. Smoothing: a first-order lag with time constant `tau`. Input goes into a pending pool and each frame emits `1 - exp(-dt/tau)` of it,
///    so the angle is conserved (the total turn equals the total input once the pool drains) and a single count turns the view on the very
///    next frame (there is no dead zone and no snap-to-zero).
/// 2. Soft limit on the angular RATE (rad/s, not per frame): below the knee nothing changes, above it the rate is compressed with tanh toward a
///    ceiling. The excess is dropped rather than queued, so the camera never keeps turning after the hand has stopped.
struct LookFilter {
    /// Smoothing time constant at the default calm (about 70 ms to reach 63 % of a step).
    static let defaultCalm: Float = 0.6
    static let baseTau: Float = 0.07
    /// Rate ceiling at the default calm: 240 degrees/s, with the knee at 75 % of it (180 degrees/s).
    static let baseCeiling: Float = 240 * .pi / 180
    static let kneeFraction: Float = 0.75
    /// The limit never goes above this, so a very small calm is nearly raw but still finite.
    static let maxCeiling: Float = 4000 * .pi / 180

    /// The player's setting, applied by the app (same pattern as `Player.slipEnabled`).
    nonisolated(unsafe) static var calm: Float = LookFilter.defaultCalm

    private var pending = SIMD2<Float>(0, 0)

    mutating func reset() { pending = .zero }

    /// Input delta in radians this frame, output delta in radians this frame. `dt` is the frame time in seconds (0 on a first frame: nothing is emitted, nothing is lost).
    mutating func filter(_ raw: SIMD2<Float>, dt: Float, calm: Float) -> SIMD2<Float> {
        guard calm > 0 else { pending = .zero; return raw }                      // calm 0 is today's behaviour, exactly: no arithmetic on the value
        pending += raw
        guard dt > 0 else { return .zero }
        let k = min(max(calm, 0), 1) / LookFilter.defaultCalm                    // 1 at the default; the whole feel scales with it
        let tau = LookFilter.baseTau * k
        var out = pending * (1 - exp(-dt / tau))
        pending -= out
        let rate = length(out) / dt
        let ceiling = min(LookFilter.baseCeiling / k, LookFilter.maxCeiling)
        let knee = ceiling * LookFilter.kneeFraction
        if rate > knee {
            let span = ceiling - knee
            let limited = knee + span * tanh((rate - knee) / span)
            out *= limited / rate
        }
        return out
    }
}
