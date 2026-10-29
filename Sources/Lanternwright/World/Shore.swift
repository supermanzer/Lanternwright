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
    /// F05 W2: the half-width (m) over which the beach's slope is measured for the swash's delay: one front, not a phase per pixel.
    static let slopeBase: Float = 24
    /// F05 W2: a ridge (a sandbar or berm) is judged against the ground smoothed over a ring of 8 points `ridgeRadius` m round it, and counts as at most `ridgeClear` above that: the front covers it when
    /// it covers the beach around it, so no dry tongue stands inside a flooded beach. The shader and `effectiveGround` use the same numbers.
    static let ridgeRadius: Float = 12, ridgeClear: Float = 0.04
    static func effectiveGround(raw: Float, ring: [Float]) -> Float { min(raw, ring.reduce(0, +) / Float(max(ring.count, 1)) + ridgeClear) }
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
        for i in 1...shadowSteps { len += shadowStep * smoothstep(-6, -1, ground(x - dx * shadowStep * Float(i), z - dz * shadowStep * Float(i))) }       // continuous in the ground: no steps
        return len * (1 - smoothstep(30, 70, -ground(x, z)))                       // and it fades out with depth instead of switching off (a hard switch drew a seam across the sea)
    }
    /// Seconds later the crests reach a point in the lee (they refract and diffract round the island: a longer path at the swell's speed), and how much smaller they are.
    static func leeDelay(shadow m: Float) -> Float { min(8, 0.35 * m / swellSpeed) }
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

    /// Where the swash's edge stands, as a ground height above the sea (m): it runs UP the beach to the group's run-up and DRAWS DOWN below the sea's contact between surges
    /// (the waterline retreats `drawDown` m down the beach, exposing sand), at the swash cycle (fast up, slow down) delayed by the beach's own shallow-water delay.
    static let drawDown: Float = 0.22, filmThickness: Float = 0.05
    static func swashEdge(x: Float, z: Float, time t: Float, slope s: Float) -> Float {
        let tt = t - delay(depth: 0, slope: s)
        let u = tt / swashPeriod - floor(tt / swashPeriod)
        let run = swashMax * (0.4 + 0.6 * group(x: x, z: z, time: t))
        let r = runup(phase: u)
        return -drawDown + (run + drawDown) * r
    }
    /// How much the swash owns the sheet at ground height `T` (m above the sea): none in the open sea (T < -0.8), all of it near and above the waterline (T > -0.3).
    static func swashOwns(ground T: Float) -> Float { smoothstep(-0.8, -0.3, T) }
    /// The height of the sheet at a place whose ground is `T` m above the sea: the open sea's own level `seaY` (the waves, already scaled to die at the shore) blended with the
    /// swash FILM, a sheet at most `filmThickness` above the ground that ends at the swash's edge: thickness = min(edge - ground, 5 cm), zero at the tip.
    static func sheetHeight(seaY: Float, ground T: Float, swashEdge S: Float) -> Float {
        let film = min(S, T + filmThickness)
        let k = swashOwns(ground: T)
        return seaY * (1 - k) + film * k
    }

    /// How far up the beach (m above the sea) the sand is still wet behind the swash: the largest recent run-up there.
    static func wetReach(x: Float, z: Float, time t: Float) -> Float {
        swashMax * (0.4 + 0.6 * group(x: x, z: z, time: t)) * 0.92
    }

    static var mslSource: String {
        """
        constant float SHORE_DEEP = \(deepDepth), SHORE_SLOPE_FLOOR = \(slopeFloor), SHORE_MAX_DELAY = \(maxDelay);
        constant float SHORE_SLOPE_BASE = \(slopeBase), SHORE_RIDGE_RADIUS = \(ridgeRadius), SHORE_RIDGE_CLEAR = \(ridgeClear);
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
        inline float shore_lee_delay(float m) { return min(8.0, 0.35 * m / \(swellSpeed)); }
        inline float shore_lee_amp(float m) { return 1.0 - 0.45 * smoothstep(0.0, 140.0, m); }
        inline float shore_runup(float u) { return u < 0.28 ? sin(1.5707963 * u / 0.28) : pow(cos(1.5707963 * (u - 0.28) / 0.72), 1.6); }
        inline float shore_group(float2 p, float t) {
            float a = 0.5 + 0.5 * sin(p.x * 0.021 - p.y * 0.014 + 0.05 * t + 1.3);
            return 0.3 + 0.7 * a * (0.65 + 0.35 * sin(p.x * 0.007 + p.y * 0.011 + 0.031 * t));
        }
        inline float shore_swash_edge(float2 p, float t, float s) {
            float tt = t - shore_delay(0.0, s);
            float u = fract(tt / SHORE_SWASH_PERIOD);
            float run = SHORE_SWASH_MAX * (0.4 + 0.6 * shore_group(p, t));
            return -\(drawDown) + (run + \(drawDown)) * shore_runup(u);
        }
        inline float shore_swash_owns(float T) { return smoothstep(-0.8, -0.3, T); }
        inline float shore_sheet(float seaY, float T, float S) {
            float film = min(S, T + \(filmThickness));
            float k = smoothstep(-0.8, -0.3, T);
            return seaY * (1.0 - k) + film * k;
        }
        inline float shore_wet_reach(float2 p, float t) { return SHORE_SWASH_MAX * (0.4 + 0.6 * shore_group(p, t)) * 0.92; }

        """
    }
}
