import simd

/// S03.4a: the lighthouse beam as a SIGNAL, once the Glass Wood altar is solved and the player is back on Varrow (`Game.lighthouseSignal`). A pure function of the game clock, repeating
/// every 20 s, so frames are reproducible:
///   0-10 s   two long sweeps (5 s each, a half turn each: with the two opposite beams the whole circle is swept twice per 10 s, three times the old rate), ending on the trail heading;
///   10-16 s  the REST: one beam standing still along the trail toward the door (from the lens at Layout.causewayStart's side, where the player arrives);
///   16-17 s  ONE SHORT FLASH, brighter and at the door (the south face);
///   17-20 s  dark: the beam is a faint ember, then the cycle begins again.
/// The old continuous turning never returns while the signal is on.
enum BeamSignal {
    static let period: Float = 20
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
        if t < 16 {
            let breath = 1 + 0.06 * sin((t - 10) * 1.4)
            return Pose(heading: trail, intensity: breath * ramp(t, 10, 10.6), opposite: false, flash: false)
        }
        if t < 17 {
            let up = ramp(t, 16, 16.12) * (1 - ramp(t, 16.8, 17))
            return Pose(heading: door, intensity: 0.05 + 2.4 * up, opposite: false, flash: true)
        }
        return Pose(heading: door, intensity: 0.05, opposite: false, flash: false)
    }
}
