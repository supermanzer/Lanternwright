import simd

/// Hand-built props. Every builder returns geometry in local space standing on y = 0 (bases at the origin),
/// so placing one is just `translation(position) * rotationY(angle)`.
enum Props {
    // MARK: Stone

    /// A weathered boulder: an icosphere lumped by noise, flattened on the bottom so it sits in the ground,
    /// mossy on top. `size` is roughly its radius in metres.
    static func rock(seed: UInt32, size: Float) -> MeshBuilder {
        let noise = Noise(seed: seed)
        let tint = 0.8 + 0.4 * noise.unit(3, 7)
        var b = MeshBuilder()
        b.icosphere(subdivisions: 2, radius: { d in
            let lump = noise.fbm(d.x * 2.1 + d.z * 5.3, d.y * 2.3 - d.z * 3.1, octaves: 3)
            return 0.82 + 0.42 * lump
        }, surface: Surface(color: SIMD3(0.30, 0.275, 0.235) * tint, roughness: 0.88),
           transform: translation(SIMD3(0, size * 0.28, 0)) * scaling(SIMD3(size * 1.15, size * 0.72, size)))
        b.recolor { p, n, c in
            let moss = smoothstep(0.55, 0.9, n.y) * 0.55
            return SIMD4(mix(c.x, 0.10, moss), mix(c.y, 0.20, moss), mix(c.z, 0.06, moss), c.w)
        }
        return b
    }

    /// Stone lantern: plinth, post, lamp chamber (four corner pillars around a glowing core), cap and roof.
    /// Returns the stone and the emissive core separately so the core can glow.
    static func stoneLantern() -> (body: MeshBuilder, core: MeshBuilder) {
        let stone = Surface(color: SIMD3(0.36, 0.34, 0.31), roughness: 0.8)
        var body = MeshBuilder()
        body.box(size: SIMD3(0.55, 0.22, 0.55), surface: stone, transform: translation(SIMD3(0, 0.11, 0)))
        body.cylinder(radiusTop: 0.10, radiusBottom: 0.13, height: 0.95, segments: 8, surface: stone, transform: translation(SIMD3(0, 0.22, 0)))
        body.box(size: SIMD3(0.46, 0.08, 0.46), surface: stone, transform: translation(SIMD3(0, 1.21, 0)))
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(Float, Float)] {
            body.box(size: SIMD3(0.06, 0.34, 0.06), surface: stone, transform: translation(SIMD3(sx * 0.19, 1.42, sz * 0.19)))
        }
        body.box(size: SIMD3(0.5, 0.07, 0.5), surface: stone, transform: translation(SIMD3(0, 1.62, 0)))
        body.cone(radius: 0.46, height: 0.32, segments: 4, smooth: false, surface: stone,
                  transform: translation(SIMD3(0, 1.655, 0)) * rotationY(.pi / 4))
        body.sphere(radius: 0.06, segments: 8, surface: stone, transform: translation(SIMD3(0, 2.0, 0)))
        var core = MeshBuilder()
        core.box(size: SIMD3(0.24, 0.26, 0.24), surface: Surface(color: SIMD3(1.0, 0.78, 0.45), roughness: 0.4),
                 transform: translation(SIMD3(0, 1.42, 0)))
        return (body, core)
    }

    // MARK: Trees

    /// Tall narrow cypress: a trunk and a stack of tapering, slightly lopsided foliage tiers.
    static func cypress(seed: UInt32, height: Float) -> MeshBuilder {
        let noise = Noise(seed: seed)
        var b = MeshBuilder()
        let bark = Surface(color: SIMD3(0.18, 0.12, 0.08), roughness: 0.95)
        b.cylinder(radiusTop: 0.08 * height / 8, radiusBottom: 0.16 * height / 8, height: height * 0.3, segments: 6, surface: bark)
        let tiers = 6
        for i in 0..<tiers {
            let t = Float(i) / Float(tiers)
            let r = height * 0.13 * (1 - 0.75 * t) * (0.85 + 0.3 * noise.unit(Int32(i), 1))
            let y = height * (0.12 + 0.82 * t * 0.92)
            let lean = SIMD3((noise.unit(Int32(i), 5) - 0.5) * 0.25, 0, (noise.unit(Int32(i), 9) - 0.5) * 0.25)
            let hue = noise.unit(Int32(i), 3)
            let foliage = Surface(color: SIMD3(0.030 + 0.015 * hue, 0.080 + 0.035 * hue + 0.035 * t, 0.038), roughness: 0.9, material: .foliage)
            b.cone(radius: r, height: height * 0.34, segments: 9, smooth: true, surface: foliage,
                   transform: translation(SIMD3(0, y, 0) + lean))
        }
        return b
    }

    /// Wider, layered pine with a bare lower trunk.
    static func pine(seed: UInt32, height: Float) -> MeshBuilder {
        let noise = Noise(seed: seed)
        var b = MeshBuilder()
        let bark = Surface(color: SIMD3(0.22, 0.14, 0.09), roughness: 0.95)
        b.cylinder(radiusTop: 0.07 * height / 7, radiusBottom: 0.15 * height / 7, height: height * 0.55, segments: 6, surface: bark)
        let tiers = 5
        for i in 0..<tiers {
            let t = Float(i) / Float(tiers)
            let r = height * 0.24 * (1 - 0.8 * t) * (0.9 + 0.2 * noise.unit(Int32(i), 2))
            let y = height * (0.28 + 0.6 * t)
            let g = noise.unit(Int32(i), 4)
            let foliage = Surface(color: SIMD3(0.034 + 0.015 * g, 0.095 + 0.035 * g, 0.042), roughness: 0.9, material: .foliage)
            b.cone(radius: r, height: height * 0.32, segments: 10, smooth: true, surface: foliage,
                   transform: translation(SIMD3(0, y, 0)) * rotationY(Float(i) * 0.7))
        }
        return b
    }
}
