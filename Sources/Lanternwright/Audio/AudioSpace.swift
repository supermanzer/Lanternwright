import simd

/// What the listener's surroundings do to sound, measured from the terrain: how enclosed the place is (reverb length), where
/// the nearest shoreline lies (where the surf comes from) and whether a hill stands between you and it (muffled surf).
/// Pure functions of position and the scene's ground height, evaluated a few times a second by `AudioEngine`.
enum AudioSpace {
    struct Reading: Equatable {
        var openness: Float = 1            // 0 = enclosed (a hollow, a lee), 1 = open sky all around
        var surfPan: Float = 0             // -1 left ... 1 right, toward the nearest shore
        var surfOcclusion: Float = 0       // 0 = clear line to the shore, 1 = a hill in the way
        var shoreDistance: Float = .infinity
    }

    /// Reverb time from openness: a sheltered hollow rings for ~3 s, the open headland barely at all.
    static func reverbTime(openness: Float) -> Float { 0.7 + 2.4 * (1 - min(max(openness, 0), 1)) }

    /// Fraction of 8 horizontal rays (out to 60 m) that run clear of the ground at head height.
    static func openness(at p: SIMD3<Float>, ground: (Float, Float) -> Float) -> Float {
        let eye = ground(p.x, p.z) + Player.eyeHeight
        var clear = 0
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi
            let d = SIMD2(cos(a), sin(a))
            var blocked = false
            var r: Float = 3
            while r <= 60 {
                if ground(p.x + d.x * r, p.z + d.y * r) > eye + 0.5 { blocked = true; break }
                r += 3
            }
            if !blocked { clear += 1 }
        }
        return Float(clear) / 8
    }

    /// Nearest shoreline (where the ground drops below the waterline) found along 32 directions, with the 2D bearing to it.
    static func nearestShore(at p: SIMD3<Float>, ground: (Float, Float) -> Float, maxRadius: Float = 320) -> (direction: SIMD2<Float>, distance: Float)? {
        if ground(p.x, p.z) < 0 { return nil }                      // already in the water: the surf is everywhere
        var best = maxRadius
        var bestDir: SIMD2<Float>?
        for k in 0..<32 {
            let a = Float(k) / 32 * 2 * .pi
            let d = SIMD2(cos(a), sin(a))
            var r: Float = 3
            while r < best {
                if ground(p.x + d.x * r, p.z + d.y * r) < 0 { best = r; bestDir = d; break }
                r *= 1.12
            }
        }
        return bestDir.map { ($0, best) }
    }

    /// 0...1: how much of the line from the listener to `target` is blocked by ground higher than the listener's ears.
    static func occlusion(from p: SIMD3<Float>, toward dir: SIMD2<Float>, distance: Float, ground: (Float, Float) -> Float) -> Float {
        let eye = ground(p.x, p.z) + Player.eyeHeight
        var blocked: Float = 0, samples: Float = 0
        var r: Float = 4
        while r < distance {
            samples += 1
            let over = ground(p.x + dir.x * r, p.z + dir.y * r) - eye
            if over > 0 { blocked += min(over / 8, 1) }
            r += 4
        }
        return samples > 0 ? min(blocked / max(samples * 0.25, 1), 1) : 0
    }

    /// The sea as a LINE source (F01 W6.2): 24 rays out to 450 m, each finding where it first meets water; every shoreline direction contributes
    /// `1 / (1 + (d / 20)^2)` (steeper than 1/d, so surf falls off properly), summed over the coast that is in view. `level` is the normalised sum
    /// to the power 0.7 (0...1: 1 at the water's edge, falling steeply inland, about -30 dB on the summit), `meanDistance` the contribution-weighted distance
    /// to the coast, which drives how dark and how slow the surf has become (air absorption: a distant sea is a low rumble, never a hiss).
    struct SurfField: Equatable {
        var level: Float = 0
        var meanDistance: Float = 450
        /// 0 at the shore ... 1 far inland (about 200 m): how much the surf has become a slow, dark swell.
        var farness: Float { smoothstep(20, 200, meanDistance) }
        /// Air absorption: the surf's low-pass cutoff (Hz): 6 kHz on the beach, about 400 Hz at 150 m, never below 220 Hz.
        var airCutoff: Float { max(220, 6000 * exp(-meanDistance / 55)) }
    }
    static func surfField(at p: SIMD3<Float>, ground: (Float, Float) -> Float, maxRadius: Float = 450) -> SurfField {
        if ground(p.x, p.z) < 0 { return SurfField(level: 1, meanDistance: 0) }
        var sum: Float = 0, weighted: Float = 0
        for k in 0..<24 {
            let a = Float(k) / 24 * 2 * .pi
            let d = SIMD2(cos(a), sin(a))
            var r: Float = 3
            while r < maxRadius {
                if ground(p.x + d.x * r, p.z + d.y * r) < 0 {
                    let w = 1 / (1 + (r / 20) * (r / 20))
                    sum += w; weighted += w * r
                    break
                }
                r *= 1.1
            }
        }
        guard sum > 0 else { return SurfField() }
        return SurfField(level: pow(min(1, 3 * sum / 24), 0.7), meanDistance: weighted / sum)
    }

    /// What the ambient bed needs at a place (shared by the engine and the offline measurement).
    struct Ambient: Equatable {
        var windGain: Float, windAltitude: Float, surfGain: Float, surfFar: Float, surfAirCutoff: Float, shoreDistance: Float
    }
    static func ambient(at p: SIMD3<Float>, ground: (Float, Float) -> Float) -> Ambient {
        let field = surfField(at: p, ground: ground)
        return Ambient(windGain: 0.18 + 0.55 * min(max(p.y / 70, 0), 1), windAltitude: smoothstep(8, 70, p.y),
                       surfGain: 0.75 * field.level + (field.meanDistance < 1 ? 0.1 : 0), surfFar: field.farness, surfAirCutoff: field.airCutoff, shoreDistance: field.meanDistance)
    }

    static func read(listener p: SIMD3<Float>, yaw: Float, ground: (Float, Float) -> Float) -> Reading {
        var r = Reading()
        r.openness = openness(at: p, ground: ground)
        if let shore = nearestShore(at: p, ground: ground) {
            let right = SIMD2(cos(yaw), sin(yaw))
            r.surfPan = min(max(simd_dot(shore.direction, right), -1), 1) * 0.8 * min(1, shore.distance / 12 * 0 + 1)
            r.surfOcclusion = occlusion(from: p, toward: shore.direction, distance: shore.distance, ground: ground)
            r.shoreDistance = shore.distance
        }
        return r
    }
}
