import simd

/// M10.5: at a vantage station (see `NavNetwork.Vantage`), when the player has stopped turning and is already looking roughly at the composed view, the camera is drawn
/// a few degrees toward it, slowly, so the view the designers made is the one the player gets. It is an assist, never a hand on the mouse:
///  - it only acts within the vantage's `tolerance` of its position, and only when the view is within `cone` (25 degrees) of the target;
///  - it turns the camera at most `maxRate` (6 degrees/s), eases in over `rampTime` and eases out as the error closes (the rate is proportional to the remaining
///    angle, so it settles instead of snapping);
///  - ANY mouse or key turn beyond `cancelRate` cancels it at once and keeps it off until the player has been still for `holdOff` seconds (longer than the look filter
///    takes to drain, so the assist never competes with the smoothing's tail);
///  - the pull is scaled by the same factor as look-closer (`scale`), so zooming in slows it to keep the on-screen speed the same: the two compose.
/// It is pure: the caller passes the frame time, the eye and the raw look delta, and gets back a yaw/pitch delta in radians.
struct FramingAssist {
    static let maxRate: Float = 6 * .pi / 180
    static let cone: Float = 25 * .pi / 180
    /// Raw look input above this angular speed (about 1.5 degrees/s: one stray mouse count in a tenth of a second) counts as the player steering.
    static let cancelRate: Float = 1.5 * .pi / 180
    static let holdOff: Float = 0.6
    static let rampTime: Float = 0.6
    /// The pull is `min(maxRate, error * easeK)`: with the error under 4 degrees the rate falls in proportion to it.
    static let easeK: Float = 1.5
    /// Settled: closer than this to the ideal framing, it stops (a tenth of a degree).
    static let settled: Float = 0.1 * .pi / 180

    private var still: Float = 0
    private var ramp: Float = 0
    /// The vantage the last pull used (for tools and tests).
    private(set) var active: String?

    /// - Parameters:
    ///   - eye: where the eyes are (feet + eye height), metres.
    ///   - feet: the player's x, z.
    ///   - rawLook: this frame's look input in radians (yaw, pitch), before the look filter.
    ///   - scale: the look-closer factor (1 when not zoomed, below 1 when zoomed).
    mutating func step(dt: Float, eye: SIMD3<Float>, feet: SIMD2<Float>, yaw: Float, pitch: Float, rawLook: SIMD2<Float>, scale: Float = 1, vantages: [NavNetwork.Vantage]) -> SIMD2<Float> {
        guard dt > 0 else { return .zero }
        if length(rawLook) / dt > FramingAssist.cancelRate { still = 0; ramp = 0; active = nil; return .zero }
        still += dt
        guard still >= FramingAssist.holdOff else { active = nil; return .zero }
        // The nearest station the player stands within.
        var best: NavNetwork.Vantage?, bestD = Float.infinity
        for v in vantages {
            let d = length(feet - v.position)
            if d <= v.tolerance && d < bestD { best = v; bestD = d }
        }
        guard let v = best else { ramp = 0; active = nil; return .zero }
        let toTarget = v.target - eye
        guard length(toTarget) > 1 else { active = nil; return .zero }
        let want = normalize(toTarget)
        let forward = SIMD3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        let angle = atan2(length(cross(forward, want)), dot(forward, want))          // accurate for tiny angles (acos of a dot near 1 is not)
        guard angle <= FramingAssist.cone else { ramp = 0; active = nil; return .zero }
        guard angle > FramingAssist.settled else { active = v.name; return .zero }
        active = v.name
        ramp = min(ramp + dt / FramingAssist.rampTime, 1)
        let eased = ramp * ramp * (3 - 2 * ramp)
        let rate = min(FramingAssist.maxRate, angle * FramingAssist.easeK) * eased * min(max(scale, 0), 1)
        let step = min(rate * dt, angle)
        // Toward the ideal yaw and pitch, the angular step shared between the two in proportion to their errors.
        var errYaw = atan2(want.x, -want.z) - yaw
        if errYaw > .pi { errYaw -= 2 * .pi } else if errYaw < -.pi { errYaw += 2 * .pi }
        let errPitch = asin(min(max(want.y, -1), 1)) - pitch
        let fraction = step / angle
        return SIMD2(errYaw * fraction, errPitch * fraction)
    }
}
