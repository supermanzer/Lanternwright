import simd

/// Places sound in the world: the stones hum, the lit lighthouse carries a distant tone, a bell buoy rings out at sea, and
/// the wind sings around the lighthouse gallery. Everything here is a pure function of where the listener stands (so the
/// falloff and panning are testable offline); `AudioEngine` copies the result into the synth a few times a second.
enum SonicLandmarks {
    struct Levels: Equatable {
        /// Per stone (tide, wind, stone) and the lit lighthouse: 0...1 loudness and -1...1 pan.
        var hum = SIMD4<Float>(repeating: 0)        // x, y, z = stones, w = lighthouse tone
        var humPan = SIMD4<Float>(repeating: 0)
        var buoy: Float = 0, buoyPan: Float = 0
        var gallery: Float = 0                      // wind whistling round the lantern room
    }

    // Reference distance (level 0.5) and audible range (level 0) for each source, in metres.
    static let stoneRef: Float = 8, stoneRange: Float = 60
    static let lighthouseRef: Float = 70, lighthouseRange: Float = 420
    static let buoyRef: Float = 45, buoyRange: Float = 260
    static let galleryRef: Float = 10, galleryRange: Float = 45

    /// Inverse-square-ish falloff that reaches exactly zero at `range` (a smooth tail, so sources never pop in or out).
    static func falloff(_ d: Float, ref: Float, range: Float) -> Float {
        guard d < range else { return 0 }
        let near = 1 / (1 + (d / ref) * (d / ref))
        let t = min(max((d - range * 0.55) / (range * 0.45), 0), 1)
        return near * (1 - t * t * (3 - 2 * t))
    }

    /// -1 (hard left) ... 1 (hard right) for a source seen by a listener facing `yaw` (forward = (sin, -cos)).
    static func pan(listener: SIMD3<Float>, yaw: Float, source: SIMD3<Float>) -> Float {
        let d = SIMD2(source.x - listener.x, source.z - listener.z)
        let len = simd_length(d)
        guard len > 0.5 else { return 0 }                       // standing on it: centred
        let right = SIMD2(cos(yaw), sin(yaw))
        return min(max(simd_dot(d / len, right), -1), 1) * 0.85
    }

    static func levels(listener p: SIMD3<Float>, yaw: Float, world: WorldKind, lighthouseLit: Bool) -> Levels {
        var l = Levels()
        guard world == .varrow else { return l }
        for id in StoneID.allCases {
            let s = id.position
            // Horizontal distance with a vertical term, so the hum on a lower terrace does not leak up the hill.
            let d = simd_length(SIMD3(p.x - s.x, (p.y - s.y) * 1.5, p.z - s.z))
            l.hum[id.rawValue] = falloff(d, ref: stoneRef, range: stoneRange)
            l.humPan[id.rawValue] = pan(listener: p, yaw: yaw, source: s)
        }
        let lh = Layout.lighthouse + SIMD3(0, 26, 0)
        if lighthouseLit {
            l.hum.w = falloff(simd_length(p - lh), ref: lighthouseRef, range: lighthouseRange)
            l.humPan.w = pan(listener: p, yaw: yaw, source: lh)
        }
        let b = Layout.buoy
        let bd = simd_length(SIMD3(p.x - b.x, 0, p.z - b.z))
        l.buoy = falloff(bd, ref: buoyRef, range: buoyRange)
        l.buoyPan = pan(listener: p, yaw: yaw, source: b)
        l.gallery = falloff(simd_length(SIMD2(p.x - lh.x, p.z - lh.z)), ref: galleryRef, range: galleryRange)
        return l
    }

    /// Seconds between bell-buoy strikes: it rings when a swell lifts it, so the gaps are irregular but repeatable.
    static func buoyInterval(strike n: Int) -> Float { 5.2 + 3.1 * abs(sin(Float(n) * 2.399)) }
}
