import simd

/// Procedural island heightfield.
///
/// `height(x:z:)` is the analytic, deterministic definition (slow: several octaves of noise).
/// Everything at runtime uses the cached grid instead: `sampleHeight` bilinearly interpolates
/// a 513x513 table at 2 m spacing, which is what the mesh, the player and the props read.
final class Terrain {
    static let gridCount = 513
    static let spacing: Float = 2
    static let origin: Float = -512          // grid covers [-512, 512] in x and z
    static let padBlend: Float = 30

    let noise: Noise
    private(set) var heights: [Float]

    init(seed: UInt32 = 20_26) {
        noise = Noise(seed: seed)
        heights = []
        let n = Terrain.gridCount
        var h = [Float](repeating: 0, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                h[j * n + i] = height(x: Terrain.origin + Float(i) * Terrain.spacing,
                                      z: Terrain.origin + Float(j) * Terrain.spacing)
            }
        }
        heights = h
    }

    // MARK: Analytic definition

    private func segmentDistance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let t = min(max(dot(p - a, ab) / dot(ab, ab), 0), 1)
        return length(p - (a + ab * t))
    }

    /// 1 on the path centreline, 0 beyond 3.5 m. The soft 1.2...3.5 m edge is wide enough for the 2 m mesh to resolve.
    static func pathWeight(x: Float, z: Float) -> Float {
        1 - smoothstep(1.2, 3.5, pathDistance(x: x, z: z))
    }

    /// Horizontal distance from (x, z) to the lantern-path polyline.
    static func pathDistance(x: Float, z: Float) -> Float {
        let p = SIMD2(x, z)
        var best = Float.infinity
        let pts = Layout.lanternPath
        for k in 0..<(pts.count - 1) {
            let a = SIMD2(pts[k].x, pts[k].z), b = SIMD2(pts[k + 1].x, pts[k + 1].z)
            let ab = b - a
            let t = min(max(dot(p - a, ab) / dot(ab, ab), 0), 1)
            best = min(best, length(p - (a + ab * t)))
        }
        return best
    }

    // Hill cross-section: a monotone cubic (PCHIP) through knots. A plain smoothstep profile is steepest
    // exactly where the wind stone sits, and flattening a pad on a slope of gradient g forces the rim to climb
    // about g*(r+R)/R (x1.5 at the smoothstep's steepest). So the profile has a *bench* (low gradient) at the
    // wind stone's radius (92...118 m) and drops more steeply between benches.
    private static let profileD: [Float] = [0, 20, 92, 118, 203, Layout.hillRadius]
    private static let profileH: [Float] = [Layout.hillPeak, 69, 37, 33, 3, 0]
    private static let profileM: [Float] = {
        let d = profileD, h = profileH
        let sec = (0..<(d.count - 1)).map { (h[$0 + 1] - h[$0]) / (d[$0 + 1] - d[$0]) }
        var m: [Float] = [0]                                            // flat summit
        for i in 1..<(d.count - 1) { m.append(2 * sec[i - 1] * sec[i] / (sec[i - 1] + sec[i])) }   // harmonic mean keeps it monotone
        m.append(0)                                                     // flat at the shoreline
        return m
    }()

    static func hillProfile(_ d: Float) -> Float {
        var i = 0
        while i < profileD.count - 2 && d >= profileD[i + 1] { i += 1 }
        let span = profileD[i + 1] - profileD[i]
        let t = min(max((d - profileD[i]) / span, 0), 1)
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * profileH[i] + (t3 - 2 * t2 + t) * span * profileM[i]
             + (-2 * t3 + 3 * t2) * profileH[i + 1] + (t3 - t2) * span * profileM[i + 1]
    }

    func height(x: Float, z: Float) -> Float {
        let p = SIMD2(x, z)
        let sea = Layout.seaFloor

        // Hill: warp the radius so the coastline is irregular (about +-6 %).
        let wobble = noise.fbm(x * 0.006, z * 0.006, octaves: 4)
        let dh = length(p - Layout.hillCenter) * (1 + 0.10 * wobble)
        let hill: Float = dh < Layout.hillRadius
            ? Terrain.hillProfile(dh)
            : sea * smoothstep(Layout.hillRadius, Layout.hillRadius + 115, dh)

        // Shelf along the spine to the south-east.
        let ds = segmentDistance(p, Layout.hillCenter, Layout.spineEnd) * (1 + 0.12 * wobble)
        let shelf: Float = ds < Layout.shelfRadius
            ? Layout.shelfHeight * (1 - smoothstep(0, Layout.shelfRadius, ds))
            : sea * smoothstep(Layout.shelfRadius, Layout.shelfRadius + 95, ds)

        // Islet to the north.
        let isletWobble = noise.fbm(x * 0.02 + 40, z * 0.02 - 17, octaves: 3)
        let di = length(p - SIMD2(Layout.isletCenter.x, Layout.isletCenter.z)) * (1 + 0.12 * isletWobble)
        let islet: Float = di < Layout.isletRadius
            ? Layout.isletPeak * pow(1 - smoothstep(0, Layout.isletRadius, di), 0.9)
            : sea * smoothstep(Layout.isletRadius, Layout.isletRadius + 80, di)

        var h = max(hill, max(shelf, islet))

        // Detail: rolling fBm everywhere (gentle on the sea floor), craggy ridges on the high ground.
        // Detail is calmed near the lantern path so the route stays walkable (slope limit, T2.5).
        let calm = 0.2 + 0.8 * smoothstep(4, 35, Terrain.pathDistance(x: x, z: z))
        let rolling = noise.fbm(x * 0.012, z * 0.012, octaves: 5) * 9 * (0.2 + 0.8 * smoothstep(0, 40, h))
        let crags = (noise.ridged(x * 0.02 + 90, z * 0.02 - 40, octaves: 5) - 0.35) * 18 * smoothstep(20, 50, h)
        h += (rolling + crags) * calm

        // The path is worn 15 cm into the ground (also visible as a darker colour in the terrain material).
        h -= 0.15 * Terrain.pathWeight(x: x, z: z)

        // Flatten pads so landmarks sit on solid, level ground.
        for pad in Layout.pads {
            let d = length(p - SIMD2(pad.center.x, pad.center.z))
            let w = 1 - smoothstep(pad.radius, pad.radius + pad.blend, d)
            h = mix(h, pad.center.y, w)
        }
        return h
    }

    // MARK: Cached sampling

    /// Bilinear height from the cached grid. Positions outside the grid clamp to its edge.
    func sampleHeight(x: Float, z: Float) -> Float {
        let n = Terrain.gridCount
        let gx = min(max((x - Terrain.origin) / Terrain.spacing, 0), Float(n - 1) - 1e-3)
        let gz = min(max((z - Terrain.origin) / Terrain.spacing, 0), Float(n - 1) - 1e-3)
        let i = Int(gx), j = Int(gz)
        let fx = gx - Float(i), fz = gz - Float(j)
        let h00 = heights[j * n + i], h10 = heights[j * n + i + 1]
        let h01 = heights[(j + 1) * n + i], h11 = heights[(j + 1) * n + i + 1]
        return mix(mix(h00, h10, fx), mix(h01, h11, fx), fz)
    }

    /// Surface normal from central differences of the cached grid.
    func normal(x: Float, z: Float) -> SIMD3<Float> {
        let d = Terrain.spacing
        let dhdx = (sampleHeight(x: x + d, z: z) - sampleHeight(x: x - d, z: z)) / (2 * d)
        let dhdz = (sampleHeight(x: x, z: z + d) - sampleHeight(x: x, z: z - d)) / (2 * d)
        return normalize(SIMD3(-dhdx, 1, -dhdz))
    }
}
