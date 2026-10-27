import simd

/// Waves meeting an island (F03 G2, note #34: "the water appears to rise up straight out of the ground as the waves progress... incorporate the physics of actual water
/// interacting with an island to correctly reflect the way wave energy would propagate along the coast"). The sea was a plane lifted by deep-water waves of the same
/// size everywhere, so on a steep shore the whole sheet rose vertically out of the ground in step with the open sea. Real waves do four things at a shore, and so does this:
///  1. they SLOW in shallow water (celerity sqrt(g h)), so a crest reaches the beach later than deep-water travel says, by an amount that depends on the depth and slope
///     along its way (`delay`): the coast is reached in a sequence, the lee side after the windward side, and crests bend toward the beach;
///  2. they SHOAL (Green's law, height grows as h^-1/4) and then die at the contact line (`amplitudeScale`): no wall of water at the edge;
///  3. what reaches the beach is a thin SWASH tongue that runs up the slope fast and drains slowly, in groups (`swashLevel`), whose height above the sea is the sheet level
///     there: it is a film that thins to nothing at the contact line (its thickness is the terrain's slope times the distance from the tip);
///  4. the sand behind the tongue stays WET and darkens, drying with height (`wetReach`).
/// The same functions are generated as Metal (`mslSource`) so the water and the terrain shaders and the selftests cannot disagree.
enum Shore {
    static let gravity: Float = 9.81
    /// Depth (m) at which shoaling begins: deeper than this a wave is the open sea's.
    static let deepDepth: Float = 6
    static let slopeFloor: Float = 0.04
    static let maxDelay: Float = 20
    /// The swash cycle (s), the run-up of the biggest group (m above the sea) and the depth under which the swash takes the sheet over from the waves.
    static let swashPeriod: Float = 7.3, swashMax: Float = 0.55, swashDepth: Float = 0.7

    /// Seconds a crest takes longer than deep-water travel to reach depth `h` (m) up a beach of slope `s`: the integral of (1/sqrt(g h) - 1/c0) along the way, for a
    /// uniform slope: 2 (sqrt(deepDepth) - sqrt(h)) / (s sqrt(g)).
    static func delay(depth h: Float, slope s: Float) -> Float {
        let hh = min(max(h, 0), deepDepth)
        return min(maxDelay, 2 * (deepDepth.squareRoot() - hh.squareRoot()) / (max(s, slopeFloor) * gravity.squareRoot()))
    }

    /// Multiplier of the open-sea wave height: 1 beyond `deepDepth`, up to 1.5 by Green's law as the water shoals, and zero at the contact line and over land.
    static func amplitudeScale(depth h: Float) -> Float {
        let shoal = h >= deepDepth ? 1 : min(1.5, pow(deepDepth / max(h, 0.4), 0.25))
        return shoal * smoothstep(0, 1.5, h)
    }

    /// The direction the main swell travels (the first Gerstner wave of Render/Shaders/Water.swift, 0.30 rad from +x toward +z), its speed (wavelength 60 m: sqrt(g lambda / 2 pi)).
    static let waveDirection: Float = 0.30
    static let swellSpeed: Float = 9.7
    static let shadowStep: Float = 24, shadowSteps = 20

    /// How many metres of land or shoal (ground above -2 m) the swell has to pass behind on its way to this point: the lee of the island. March upwind in `shadowSteps` steps.
    static func shadow(x: Float, z: Float, ground: (Float, Float) -> Float) -> Float {
        let dx = cos(waveDirection), dz = sin(waveDirection)
        var len: Float = 0
        for i in 1...shadowSteps { if ground(x - dx * shadowStep * Float(i), z - dz * shadowStep * Float(i)) > -2 { len += shadowStep } }
        return len
    }
    /// Seconds later the crests reach a point in the lee (they refract and diffract round the island: a longer path at the swell's speed), and how much smaller they are.
    static func leeDelay(shadow m: Float) -> Float { min(14, 0.55 * m / swellSpeed) }
    static func leeAmplitude(shadow m: Float) -> Float { 1 - 0.45 * smoothstep(0, 140, m) }

    /// The shape of one swash cycle, 0...1 of its period: a fast run-up (28 % of the cycle) and a slow drain (72 %), as 0...1 of the run-up.
    static func runup(phase u: Float) -> Float {
        u < 0.28 ? sin(.pi / 2 * u / 0.28) : pow(cos(.pi / 2 * (u - 0.28) / 0.72), 1.6)
    }

    /// Wave groups: the run-up of one swash cycle is larger or smaller than the next, varying slowly in time and along the coast (0...1).
    static func group(x: Float, z: Float, time t: Float) -> Float {
        let a = 0.5 + 0.5 * sin(x * 0.021 - z * 0.014 + 0.05 * t + 1.3)
        return 0.3 + 0.7 * a * (0.65 + 0.35 * sin(x * 0.007 + z * 0.011 + 0.031 * t))
    }

    /// The level (m above the sea) the swash sheet stands at, at a place with ground `depth` m under the sea (negative on land) and slope `s`, at time `t`.
    /// It is the sea's level plus the tongue; the ground above it hides the sheet, so the contact line is where the ground equals this level.
    static func swashLevel(x: Float, z: Float, time t: Float, depth h: Float, slope s: Float) -> Float {
        let tt = t - delay(depth: 0, slope: s)                                    // the swash arrives with the delay of the whole beach
        let u = tt / swashPeriod - floor(tt / swashPeriod)
        let take = 1 - smoothstep(0.1, swashDepth, h)                            // the swash owns the sheet where it is shallower than this
        return swashMax * (0.4 + 0.6 * group(x: x, z: z, time: t)) * runup(phase: u) * take
    }

    /// How far up the beach (m above the sea) the sand is still wet behind the swash: the largest recent run-up there.
    static func wetReach(x: Float, z: Float, time t: Float) -> Float {
        swashMax * (0.4 + 0.6 * group(x: x, z: z, time: t)) * 0.92
    }

    static var mslSource: String {
        """
        constant float SHORE_DEEP = \(deepDepth), SHORE_SLOPE_FLOOR = \(slopeFloor), SHORE_MAX_DELAY = \(maxDelay);
        constant float SHORE_SWASH_PERIOD = \(swashPeriod), SHORE_SWASH_MAX = \(swashMax), SHORE_SWASH_DEPTH = \(swashDepth);
        inline float shore_delay(float h, float s) {
            float hh = clamp(h, 0.0, SHORE_DEEP);
            return min(SHORE_MAX_DELAY, 2.0 * (sqrt(SHORE_DEEP) - sqrt(hh)) / (max(s, SHORE_SLOPE_FLOOR) * sqrt(\(gravity))));
        }
        inline float shore_amp(float h) {
            float shoal = h >= SHORE_DEEP ? 1.0 : min(1.5, pow(SHORE_DEEP / max(h, 0.4), 0.25));
            return shoal * smoothstep(0.0, 1.5, h);
        }
        constant float2 SHORE_WAVE_DIR = float2(\(cos(waveDirection)), \(sin(waveDirection)));
        inline float shore_lee_delay(float m) { return min(14.0, 0.55 * m / \(swellSpeed)); }
        inline float shore_lee_amp(float m) { return 1.0 - 0.45 * smoothstep(0.0, 140.0, m); }
        inline float shore_runup(float u) { return u < 0.28 ? sin(1.5707963 * u / 0.28) : pow(cos(1.5707963 * (u - 0.28) / 0.72), 1.6); }
        inline float shore_group(float2 p, float t) {
            float a = 0.5 + 0.5 * sin(p.x * 0.021 - p.y * 0.014 + 0.05 * t + 1.3);
            return 0.3 + 0.7 * a * (0.65 + 0.35 * sin(p.x * 0.007 + p.y * 0.011 + 0.031 * t));
        }
        inline float shore_swash(float2 p, float t, float h, float s) {
            float tt = t - shore_delay(0.0, s);
            float u = fract(tt / SHORE_SWASH_PERIOD);
            float take = 1.0 - smoothstep(0.1, SHORE_SWASH_DEPTH, h);
            return SHORE_SWASH_MAX * (0.4 + 0.6 * shore_group(p, t)) * shore_runup(u) * take;
        }
        inline float shore_wet_reach(float2 p, float t) { return SHORE_SWASH_MAX * (0.4 + 0.6 * shore_group(p, t)) * 0.92; }

        """
    }
}
