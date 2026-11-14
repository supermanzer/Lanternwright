import simd

/// S03.4a: the lighthouse beam as a SIGNAL, once the Glass Wood altar is solved and the player is back on Varrow (`Game.lighthouseSignal`). A pure function of the game clock, repeating
/// every `period` seconds, so frames are reproducible:
///   0-10 s   two long sweeps (5 s each, a half turn each: with the two opposite beams the whole circle is swept twice per 10 s, three times the old rate), ending on the trail heading;
///   10-16 s  the REST: one beam standing still along the trail toward the door (from the lens at Layout.causewayStart's side, where the player arrives);
///   16 s on  THREE GROUPS (P02.3): the beam, brighter and at the door (the south face), is lit for `Layout.Navigation.SignalPattern.groupSeconds` (long, short, middle) with dark gaps between,
///            then dark: a faint ember until the cycle begins again (`period` = 27 s).
/// The old continuous turning never returns while the signal is on.
enum BeamSignal {
    typealias Pattern = Layout.Navigation.SignalPattern
    static let restEnd: Float = 16
    /// The clock windows (start, end), within one period, in which each group is lit.
    static let groupWindows: [(start: Float, end: Float)] = {
        var t = restEnd + Pattern.leadSeconds, out: [(Float, Float)] = []
        for d in Pattern.groupSeconds { out.append((t, t + d)); t += d + Pattern.gapSeconds }
        return out
    }()
    static let period: Float = groupWindows.last!.end + Pattern.tailSeconds
    struct Pose { var heading: Float; var intensity: Float; var opposite: Bool; var flash: Bool }

    /// The heading (radians, 0 = north = -z, clockwise: the beam's direction is (sin h, 0, -cos h)) from the lens to a point.
    static func heading(to p: SIMD3<Float>, from lens: SIMD3<Float> = Landmarks.lensPosition) -> Float {
        atan2(p.x - lens.x, -(p.z - lens.z))
    }
    static var trailHeading: Float { heading(to: Layout.Navigation.signalTrailPoint) }
    static var doorHeading: Float { heading(to: Layout.Navigation.signalDoorPoint) }

    static func pose(clock: Float, trail: Float = BeamSignal.trailHeading, door: Float = BeamSignal.doorHeading) -> Pose {
        var t = clock.truncatingRemainder(dividingBy: period)
        if t < 0 { t += period }
        func ramp(_ x: Float, _ a: Float, _ b: Float) -> Float { let u = min(max((x - a) / (b - a), 0), 1); return u * u * (3 - 2 * u) }
        if t < 10 {
            // Two half-turn sweeps, each starting and ending gently (the heading eases within each 5 s), so the pair reads as two distinct sweeps; the second ends exactly on the trail.
            let sweep = Float(Int(t / 5)), u = (t - 5 * sweep) / 5
            let eased = u * u * (3 - 2 * u)
            return Pose(heading: trail + .pi * (sweep - 2 + eased), intensity: 1, opposite: true, flash: false)
        }
        if t < restEnd {
            let breath = 1 + 0.06 * sin((t - 10) * 1.4)
            return Pose(heading: trail, intensity: breath * ramp(t, 10, 10.6), opposite: false, flash: false)
        }
        for w in groupWindows where t >= w.start - 0.01 && t < w.end + 0.01 {
            let up = ramp(t, w.start, w.start + 0.12) * (1 - ramp(t, w.end - 0.12, w.end))
            return Pose(heading: door, intensity: 0.05 + 2.4 * up, opposite: false, flash: true)
        }
        return Pose(heading: door, intensity: 0.05, opposite: false, flash: false)
    }
}
