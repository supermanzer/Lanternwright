import simd

/// How things meet the ground (F01 W3.5 and W3.6). Two rules, both from sampling the terrain under the object's whole footprint, never just its centre:
///
/// - **Props that stand upright** (lanterns, stones, pillars, tree trunks): the pivot sits at the HIGHEST ground under the footprint, the prop stays vertical,
///   and a straight **foundation extension** (the prop's own base carried down, no flare, no apron) reaches down to the LOWEST sample plus a margin, so the downhill side is never in the air.
/// - **Pieces that lie on the ground** (cones, twigs, pebbles, shells, driftwood, rocks): the piece takes the slope's tilt and its pivot is dropped to the
///   LOWEST residual of the ground against that plane, then sunk a little, so no part floats and the high side is just buried.
///
/// Every placed piece is recorded (`PlacedProp`) with its lowest vertices in world space, so a selftest can check contact for all of them.
enum Placement {
    /// A world-space record of one placed piece: what it is, and its lowest vertices (up to 8).
    struct PlacedProp { let kind: String; let low: [SIMD3<Float>] }

    struct Samples {
        var centre: Float
        var high: Float
        var low: Float
        var normal: SIMD3<Float>
    }

    /// Ground heights under a circular footprint: the centre and two rings of eight points.
    static func samples(terrain: Terrain, x: Float, z: Float, radius: Float) -> Samples {
        var hi = terrain.sampleHeight(x: x, z: z), lo = hi
        let c = hi
        for ring in [0.5, 1.0] as [Float] {
            for k in 0..<8 {
                let a = Float(k) / 8 * 2 * .pi
                let h = terrain.sampleHeight(x: x + cos(a) * radius * ring, z: z + sin(a) * radius * ring)
                hi = max(hi, h); lo = min(lo, h)
            }
        }
        return Samples(centre: c, high: hi, low: lo, normal: terrain.normal(x: x, z: z))
    }

    /// Footing for an upright prop whose pivot is at `high`: local y = 0 is the prop's base. F02 G1: the embedding is a plain straight extension of the
    /// prop's own base (same radius, same material, no flare and no separate apron), running down to the lowest ground + `margin`, so no gap can show
    /// on any slope. The terrain hides the buried part. (Tree trunks do not use this: the trunk tube itself is extended, see Trees.conifer.)
    static func skirt(radius: Float, depth: Float, margin: Float = 0.3, surface: Surface) -> MeshBuilder {
        var b = MeshBuilder()
        let total = depth + margin
        b.cylinder(radiusTop: radius, radiusBottom: radius, height: total + 0.04, segments: 10, smooth: true, caps: false, surface: surface,
                   transform: translation(SIMD3(0, -total, 0)))
        return b
    }

    /// Transform for an upright prop: pivot at the highest ground under `radius`, stays vertical, yawed by `yaw`; also returns the footing depth.
    static func upright(terrain: Terrain, x: Float, z: Float, radius: Float, yaw: Float) -> (transform: float4x4, depth: Float) {
        let s = samples(terrain: terrain, x: x, z: z, radius: radius)
        return (translation(SIMD3(x, s.high, z)) * rotationY(yaw), s.high - s.low)
    }

    /// Orientation for a lying piece: local +Y is the ground normal, local +Z the world heading `heading` projected onto the slope.
    static func basis(normal n: SIMD3<Float>, heading: Float) -> float4x4 {
        let f0 = SIMD3<Float>(sin(heading), 0, cos(heading))
        var f = f0 - n * simd_dot(f0, n)
        f = simd_length(f) < 1e-4 ? SIMD3(0, 0, 1) : simd_normalize(f)
        let x = simd_cross(n, f)
        return float4x4(columns: (SIMD4(x, 0), SIMD4(n, 0), SIMD4(f, 0), SIMD4(0, 0, 0, 1)))
    }

    /// Transform for a piece that lies on the ground, with `halfX` x `halfZ` (m) its footprint in its own frame (X across, Z along the heading) and
    /// `sink` how far below the surface its base goes. The piece's local y = 0 is its underside.
    static func lay(terrain: Terrain, x: Float, z: Float, heading: Float, halfX: Float, halfZ: Float, sink: Float) -> float4x4 {
        let n = terrain.normal(x: x, z: z)
        let y0 = terrain.sampleHeight(x: x, z: z)
        let b = basis(normal: n, heading: heading)
        let ex = SIMD3<Float>(b.columns.0.x, b.columns.0.y, b.columns.0.z), ez = SIMD3<Float>(b.columns.2.x, b.columns.2.y, b.columns.2.z)
        var lowest: Float = 0                                      // lowest residual of the ground against the tangent plane (<= 0 where ground dips)
        for iu in -2...2 { for iv in -2...2 {
            let u = Float(iu) / 2, v = Float(iv) / 2
            let p = SIMD3(x, 0, z) + ex * (u * halfX) + ez * (v * halfZ)
            let plane = y0 - (n.x * (p.x - x) + n.z * (p.z - z)) / max(n.y, 0.2)
            lowest = min(lowest, terrain.sampleHeight(x: p.x, z: p.z) - plane)
        } }
        var m = b
        m.columns.3 = SIMD4(x, y0 + lowest - sink, z, 1)
        return m
    }

    /// The lowest vertices of `mesh` under `transform`, in world space.
    static func record(kind: String, mesh: MeshBuilder, transform: float4x4) -> PlacedProp {
        var pts = mesh.vertices.map { v -> SIMD3<Float> in let w = transform * SIMD4(v.position.x, v.position.y, v.position.z, 1); return SIMD3(w.x, w.y, w.z) }
        pts.sort { $0.y < $1.y }
        return PlacedProp(kind: kind, low: Array(pts.prefix(8)))
    }

    /// Gap between each of a recorded piece's lowest vertices and the terrain beneath it: negative = embedded, positive = in the air.
    /// `touching` is the LARGEST gap (the vertex that is least embedded: it must not be in the air, and should be only slightly buried, because the
    /// downhill side of a footing or a lying piece is what meets the ground); `deepest` the smallest (the uphill side, buried by the slope).
    static func contact(_ p: PlacedProp, terrain: Terrain) -> (touching: Float, deepest: Float) {
        let gaps = p.low.map { $0.y - terrain.sampleHeight(x: $0.x, z: $0.z) }
        return (gaps.max() ?? 0, gaps.min() ?? 0)
    }
}
