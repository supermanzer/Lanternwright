import simd

/// Everything that makes one world's ground different from another's. The `Terrain` machinery (grid cache, normals,
/// pad flattening, path wear, detail noise) is shared; a world supplies its large-scale shape and its landmarks.
struct TerrainSpec {
    var pads: [Layout.Pad]
    /// The walking route: calms the detail noise, gets worn 15 cm into the ground and coloured as a path.
    var path: [SIMD3<Float>]
    var seaFloor: Float
    /// Large-scale shape (coast, hills) before detail, path and pads are applied.
    var baseHeight: (_ noise: Noise, _ x: Float, _ z: Float) -> Float
    var rollingAmplitude: Float = 9
    var cragAmplitude: Float = 18
}

/// Distance from p to the segment ab.
func segmentDistance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    let ab = b - a
    let t = min(max(dot(p - a, ab) / dot(ab, ab), 0), 1)
    return length(p - (a + ab * t))
}

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
    let spec: TerrainSpec
    private(set) var heights: [Float]
    /// Forest-floor litter weight 0...1 on the same grid (needle duff under conifers); zero until `setDuff` is called.
    private(set) var duff: [Float] = []
    /// Splat a soft disc of litter around each (position, radius): full inside 45 % of the radius, fading to nothing at the radius.
    func setDuff(_ discs: [(c: SIMD2<Float>, r: Float)]) {
        let n = Terrain.gridCount
        var d = [Float](repeating: 0, count: n * n)
        for disc in discs {
            let i0 = max(0, Int(((disc.c.x - disc.r) - Terrain.origin) / Terrain.spacing)), i1 = min(n - 1, Int(((disc.c.x + disc.r) - Terrain.origin) / Terrain.spacing) + 1)
            let j0 = max(0, Int(((disc.c.y - disc.r) - Terrain.origin) / Terrain.spacing)), j1 = min(n - 1, Int(((disc.c.y + disc.r) - Terrain.origin) / Terrain.spacing) + 1)
            guard i0 <= i1, j0 <= j1 else { continue }
            for j in j0...j1 { for i in i0...i1 {
                let x = Terrain.origin + Float(i) * Terrain.spacing, z = Terrain.origin + Float(j) * Terrain.spacing
                let w = 1 - smoothstep(disc.r * 0.45, disc.r, simd_length(SIMD2(x, z) - disc.c))
                if w > d[j * n + i] { d[j * n + i] = w }
            } }
        }
        duff = d
    }
    func duffAt(x: Float, z: Float) -> Float {
        guard !duff.isEmpty else { return 0 }
        let n = Terrain.gridCount
        let gx = min(max((x - Terrain.origin) / Terrain.spacing, 0), Float(n - 1) - 1e-3), gz = min(max((z - Terrain.origin) / Terrain.spacing, 0), Float(n - 1) - 1e-3)
        let i = Int(gx), j = Int(gz), fx = gx - Float(i), fz = gz - Float(j)
        return mix(mix(duff[j * n + i], duff[j * n + i + 1], fx), mix(duff[(j + 1) * n + i], duff[(j + 1) * n + i + 1], fx), fz)
    }

    init(seed: UInt32 = 20_26, spec: TerrainSpec = .varrow) {
        noise = Noise(seed: seed)
        self.spec = spec
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

    /// 1 on the path centreline, 0 beyond 3.5 m. The soft 1.2...3.5 m edge is wide enough for the 2 m mesh to resolve.
    func pathWeight(x: Float, z: Float) -> Float {
        1 - smoothstep(1.2, 3.5, pathDistance(x: x, z: z))
    }

    /// Height of the graded route under (x, z): the waypoints' heights interpolated along the nearest leg (nil on a world without a path).
    func pathGradedHeight(x: Float, z: Float) -> Float? {
        let pts = spec.path
        if pts.count < 2 { return nil }
        let p = SIMD2(x, z)
        var best = Float.infinity, hBest: Float = 0
        for k in 0..<(pts.count - 1) {
            let a = SIMD2(pts[k].x, pts[k].z), b = SIMD2(pts[k + 1].x, pts[k + 1].z)
            let ab = b - a
            let t = min(max(dot(p - a, ab) / dot(ab, ab), 0), 1)
            let d = length(p - (a + ab * t))
            if d < best {
                best = d
                let len = length(ab), m: Float = min(7, len * 0.3)                    // flat within m of each waypoint
                let s = min(max((t * len - m) / max(len - 2 * m, 1e-3), 0), 1)
                hBest = pts[k].y + (pts[k + 1].y - pts[k].y) * s
            }
        }
        return hBest
    }

    /// Horizontal distance from (x, z) to the lantern-path polyline.
    func pathDistance(x: Float, z: Float) -> Float {
        let p = SIMD2(x, z)
        var best = Float.infinity
        let pts = spec.path
        if pts.count < 2 { return .infinity }
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
        var h = spec.baseHeight(noise, x, z)

        // Detail: rolling fBm everywhere (gentle on the sea floor), craggy ridges on the high ground.
        // Detail is calmed near the lantern path so the route stays walkable (slope limit, T2.5).
        let calm = 0.2 + 0.8 * smoothstep(4, 35, pathDistance(x: x, z: z))
        let rolling = noise.fbm(x * 0.012, z * 0.012, octaves: 5) * spec.rollingAmplitude * (0.2 + 0.8 * smoothstep(0, 40, h))
        let crags = (noise.ridged(x * 0.02 + 90, z * 0.02 - 40, octaves: 5) - 0.35) * spec.cragAmplitude * smoothstep(20, 50, h)
        h += (rolling + crags) * calm

        // The path is worn 15 cm into the ground (also visible as a darker colour in the terrain material).
        h -= 0.15 * pathWeight(x: x, z: z)

        // Flatten pads so landmarks sit on solid, level ground.
        for pad in spec.pads {
            let d = length(p - SIMD2(pad.center.x, pad.center.z))
            let w = 1 - smoothstep(pad.radius, pad.radius + pad.blend, d)
            h = mix(h, pad.center.y, w)
        }
        // F01 W5.2: a graded BENCH along the route (after the pads, which otherwise steepen the ground just outside them): between two waypoints the path runs at
        // the straight-line grade instead of following the hill's relief (some 10 m stretches were 0.5-0.7), cut and filled into the hillside over a few metres and
        // blended out over about 14 m. The graded profile is flat within 7 m of each waypoint (the pads) and runs straight between.
        let bw = 1 - smoothstep(3.0, 14.0, pathDistance(x: x, z: z))
        if bw > 0.001, let gh = pathGradedHeight(x: x, z: z) {
            h = mix(h, gh - 0.15 * pathWeight(x: x, z: z), bw)
        }
        return h
    }

    // MARK: Cached sampling

    /// The four corner heights and fractional position of the grid cell containing (x, z); positions outside clamp to the edge.
    private func cell(x: Float, z: Float) -> (h00: Float, h10: Float, h01: Float, h11: Float, fx: Float, fz: Float) {
        let n = Terrain.gridCount
        let gx = min(max((x - Terrain.origin) / Terrain.spacing, 0), Float(n - 1) - 1e-3)
        let gz = min(max((z - Terrain.origin) / Terrain.spacing, 0), Float(n - 1) - 1e-3)
        let i = Int(gx), j = Int(gz)
        return (heights[j * n + i], heights[j * n + i + 1], heights[(j + 1) * n + i], heights[(j + 1) * n + i + 1], gx - Float(i), gz - Float(j))
    }

    /// Height of the rendered surface. The terrain mesh splits every cell along its a-d diagonal into triangles (a, c, d) and
    /// (a, d, b) (a = (i, j), b = (i+1, j), c = (i, j+1), d = (i+1, j+1); see TerrainMesh), so the ground you walk on is the
    /// ground you see: this interpolates on that same triangle, not bilinearly (which would float or sink up to a few cm).
    func sampleHeight(x: Float, z: Float) -> Float {
        let c = cell(x: x, z: z)
        if c.fx >= c.fz { return c.h00 + c.fx * (c.h10 - c.h00) + c.fz * (c.h11 - c.h10) }     // triangle (a, d, b)
        return c.h00 + c.fz * (c.h01 - c.h00) + c.fx * (c.h11 - c.h01)                          // triangle (a, c, d)
    }

    /// Normal of the mesh triangle under (x, z): what a physics query or a decal should use (`normal` is the smooth lighting normal).
    func faceNormal(x: Float, z: Float) -> SIMD3<Float> {
        let c = cell(x: x, z: z), s = Terrain.spacing
        if c.fx >= c.fz { return normalize(SIMD3(-(c.h10 - c.h00) / s, 1, -(c.h11 - c.h10) / s)) }
        return normalize(SIMD3(-(c.h11 - c.h01) / s, 1, -(c.h01 - c.h00) / s))
    }

    /// Surface normal from central differences of the cached grid.
    func normal(x: Float, z: Float) -> SIMD3<Float> {
        let d = Terrain.spacing
        let dhdx = (sampleHeight(x: x + d, z: z) - sampleHeight(x: x - d, z: z)) / (2 * d)
        let dhdz = (sampleHeight(x: x, z: z + d) - sampleHeight(x: x, z: z - d)) / (2 * d)
        return normalize(SIMD3(-dhdx, 1, -dhdz))
    }
}

extension TerrainSpec {
    /// The Isle of Varrow: a hill with a bench at the wind stone, a low shelf running south-east to the dock, and the islet.
    static let varrow = TerrainSpec(pads: Layout.pads, path: Layout.route, seaFloor: Layout.seaFloor) { noise, x, z in
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
        return max(hill, max(shelf, islet))
    }
}
