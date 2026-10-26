import Foundation
import simd

/// The mooring posts, their rope coils and the horn cleats on the dock (F02 R11 / T67.1). All coordinates are in the dock's own frame
/// (x across, y up, z along it), the same frame `Landmarks.addDock` builds in.
///
/// The posts and the rope are built as seam-duplicated grids rather than with `MeshBuilder.cylinder`/`torus`, because their materials
/// (24 `post`, 25 `rope`) need a continuous coordinate per vertex that a primitive cannot give: the angle round the shaft goes in the
/// material-id fraction (`aux`, -1...1, the same trick as the deck boards' cross coordinate) and a second value in the vertex alpha
/// (post: cap radius fraction, or 1 + depth below the cap on the shaft; rope: length along it).
enum DockFurniture {
    /// Rope length (m) that vertex alpha 1.0 stands for; `mat_rope` multiplies by the same constant.
    static let ropeScale: Float = 6
    static let ropeRadius: Float = 0.0165

    // MARK: A grid of vertices that wraps in u

    /// (nu + 1) x (nv + 1) vertices; column nu repeats column 0 so that per-vertex data can run -1...1 round the ring without a smeared seam.
    /// Normals come from the grid's own central differences (wrapping in u), so the shading is continuous across the duplicated seam.
    /// `outward` orients them; a pole row (all points equal) takes the average of its neighbour row.
    static func grid(nu: Int, nv: Int, position: (Int, Int) -> SIMD3<Float>, aux: (Int, Int) -> Float, alpha: (Int, Int) -> Float,
                     outward: (Int, Int) -> SIMD3<Float>, surface: Surface) -> MeshBuilder {
        func pos(_ i: Int, _ j: Int) -> SIMD3<Float> { position(((i % nu) + nu) % nu, j) }
        var normals = [SIMD3<Float>](repeating: .zero, count: (nu + 1) * (nv + 1))
        var degenerate = [Bool](repeating: false, count: normals.count)
        for j in 0...nv {
            for i in 0...nu {
                let du = pos(i + 1, j) - pos(i - 1, j), dv = pos(i, min(j + 1, nv)) - pos(i, max(j - 1, 0))
                var n = simd_cross(dv, du)
                if simd_length_squared(n) < 1e-14 { degenerate[j * (nu + 1) + i] = true; continue }
                n = simd_normalize(n)
                if simd_dot(n, outward(i % nu, j)) < 0 { n = -n }
                normals[j * (nu + 1) + i] = n
            }
        }
        for j in 0...nv {
            for i in 0...nu where degenerate[j * (nu + 1) + i] {
                let r = j == nv ? j - 1 : j + 1
                var s = SIMD3<Float>.zero
                for k in 0...nu { s += normals[r * (nu + 1) + k] }
                normals[j * (nu + 1) + i] = simd_length_squared(s) > 0 ? simd_normalize(s) : SIMD3(0, 1, 0)
            }
        }
        var positions: [SIMD3<Float>] = [], idx: [UInt32] = []
        for j in 0...nv { for i in 0...nu { positions.append(pos(i, j)) } }
        for j in 0..<nv {
            for i in 0..<nu {
                let a = UInt32(j * (nu + 1) + i), b = a + 1, c = a + UInt32(nu + 1), d = c + 1
                for t in [[a, c, d], [a, d, b]] {                                                // wind each triangle to face along its vertex normals
                    let p0 = positions[Int(t[0])], p1 = positions[Int(t[1])], p2 = positions[Int(t[2])]
                    let fn = simd_cross(p1 - p0, p2 - p0)
                    let vn = normals[Int(t[0])] + normals[Int(t[1])] + normals[Int(t[2])]
                    idx.append(contentsOf: simd_dot(fn, vn) >= 0 ? t : [t[0], t[2], t[1]])
                }
            }
        }
        var m = MeshBuilder()
        m.addIndexed(positions: positions, indices: idx, smoothNormals: normals, surface: surface, transform: matrix_identity_float4x4)
        var k = 0
        let base = surface.material.rawValue
        m.adjust { v in
            let i = k % (nu + 1), j = k / (nu + 1)
            v.normal.w = base + 0.4 * max(-1, min(1, aux(i, j)))
            v.color.w = alpha(i, j)
            k += 1
        }
        return m
    }

    // MARK: Mooring post

    struct Post {
        let x: Float, z: Float                 // where the axis crosses y = base
        let top: Float                         // height of the middle of the cap
        let seed: Int32
        let base: Float = -3.0
        let lean: SIMD2<Float>                 // (x, z) displacement per metre of height: a degree or two
        private let ph: [Float]
        private let psi: Float                 // the direction the cap slopes toward
        private let wearPh: (Float, Float)

        init(x: Float, z: Float, top: Float, seed: Int32) {
            let n = Island.noise
            self.x = x; self.z = z; self.top = top; self.seed = seed
            let mag = tan(0.017 + 0.018 * n.unit(seed, 131)), dir = 6.2831853 * n.unit(seed, 132)
            lean = SIMD2(cos(dir), sin(dir)) * mag
            ph = (0..<5).map { 6.2831853 * n.unit(seed &* 8 &+ Int32($0), 133) }
            psi = 6.2831853 * n.unit(seed, 134)
            wearPh = (6.2831853 * n.unit(seed, 135), 6.2831853 * n.unit(seed, 136))
        }
        func centre(_ y: Float) -> SIMD2<Float> { SIMD2(x, z) + lean * (y - base) }
        /// Radius of the shaft at height y and angle theta: a taper, an irregular girth and a slow bulge, so the silhouette is never a clean cylinder.
        func radius(_ y: Float, _ theta: Float) -> Float {
            let t = min(max((y - base) / (top - base), 0), 1)
            let wob = 1 + 0.028 * sin(2 * theta + ph[0] + 1.7 * y) + 0.022 * sin(3 * theta + ph[1] - 2.3 * y)
                + 0.012 * sin(5 * theta + ph[2] + 4 * y) + 0.020 * sin(3.1 * y + ph[3])
            return (0.104 + 0.012 * (1 - t)) * wob
        }
        /// How far the cap's rim has worn away at this angle (0...1): the edge is chewed in two or three places.
        func wear(_ theta: Float) -> Float {
            let a = 0.5 + 0.5 * sin(3 * theta + wearPh.0), b = 0.5 + 0.5 * sin(2 * theta + wearPh.1)
            return smoothstep(0.25, 0.9, a * b * 1.6)
        }
        /// Height of the cap at radial fraction f (0 centre, 1 rim) and angle theta: domed, sloping a little toward `psi`, chewed at the rim.
        func capY(_ theta: Float, _ f: Float) -> Float {
            top + 0.011 * (1 - f * f) + 0.010 * f * cos(theta - psi) - 0.022 * wear(theta) * smoothstep(0.5, 1, f)
        }
        /// A point on the surface of the shaft.
        func surfacePoint(_ y: Float, _ theta: Float) -> SIMD3<Float> {
            let c = centre(y), r = radius(y, theta)
            return SIMD3(c.x + r * cos(theta), y, c.y + r * sin(theta))
        }
    }

    enum Row { case shaft(Float), shoulder, disc(Float) }

    static func postMesh(_ p: Post) -> MeshBuilder {
        var rows: [Row] = [.shaft(p.base), .shaft(-1.5), .shaft(-0.6), .shaft(-0.1)]
        var y: Float = 0.12
        while y < p.top - 0.12 { rows.append(.shaft(y)); y += 0.19 }
        rows.append(.shaft(p.top - 0.05)); rows.append(.shoulder)
        for f: Float in [0.90, 0.74, 0.56, 0.38, 0.19, 0] { rows.append(.disc(f)) }
        let nu = 16, nv = rows.count - 1
        let surf = Surface(color: SIMD3(0.20, 0.14, 0.09), roughness: 0.9, material: .post)
        func point(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let th = Float(i) / Float(nu) * 2 * .pi
            switch rows[j] {
            case .shaft(let y): return p.surfacePoint(y, th)
            case .shoulder:
                let c = p.centre(p.top), r = p.radius(p.top, th) * 0.975
                return SIMD3(c.x + r * cos(th), p.top - 0.004 - 0.016 * p.wear(th), c.y + r * sin(th))
            case .disc(let f):
                let c = p.centre(p.top), r = p.radius(p.top, th) * 0.975 * f
                return SIMD3(c.x + r * cos(th), p.capY(th, f), c.y + r * sin(th))
            }
        }
        return grid(nu: nu, nv: nv, position: point,
                    aux: { i, _ in Float(i) / Float(nu) * 2 - 1 },
                    alpha: { _, j in                                                    // cap: radial fraction 0...1; shaft: 1 + depth below the cap, so the material can grade the weathering
                        switch rows[j] { case .disc(let f): return f; case .shoulder: return 1; case .shaft(let y): return 1 + max(0, p.top - y) }
                    },
                    outward: { i, j in
                        if case .disc = rows[j] { return SIMD3(0, 1, 0) }
                        let th = Float(i) / Float(nu) * 2 * .pi; return SIMD3(cos(th), 0.2, sin(th))
                    }, surface: surf)
    }

    // MARK: Rope coil

    /// The rope: about four turns round the post, each lying against the one below and touching the shaft (the centreline runs at the
    /// post's radius plus the rope's), with a sag at the front, then a loose end that hangs down and frays.
    /// The centreline of the turns round the post (first to last), before the loose end.
    static func coilCentreline(_ p: Post) -> (points: [SIMD3<Float>], theta0: Float, perTurn: Int) {
        let n = Island.noise, rr = ropeRadius
        let turns = 4.0 + 0.5 * n.unit(p.seed, 141), perTurn = 18
        let th0 = 6.2831853 * n.unit(p.seed, 142), front = 6.2831853 * n.unit(p.seed, 143)
        let y0 = p.top - 0.118, pitch = 2 * rr * 0.97
        var pts: [SIMD3<Float>] = []
        for k in 0...Int(turns * Float(perTurn)) {
            let t = Float(k) / Float(perTurn), th = th0 + 2 * .pi * t
            let y = y0 - pitch * t - 0.020 * (0.5 + 0.5 * cos(th - front))
            let tuck = (1 - smoothstep(0, 7, Float(k))) * rr * 1.7                      // the first turn's start sinks into the shaft, so no cut end shows
            let c = p.centre(y), r = p.radius(y, th) + rr * 0.92 - tuck
            pts.append(SIMD3(c.x + r * cos(th), y, c.y + r * sin(th)))
        }
        return (pts, th0, perTurn)
    }

    static func ropeMesh(_ p: Post) -> MeshBuilder {
        let n = Island.noise, rr = ropeRadius
        let coil = coilCentreline(p), th0 = coil.theta0, perTurn = coil.perTurn
        var pts = coil.points, radii = (0..<coil.points.count).map { rr * (0.55 + 0.45 * smoothstep(0, 5, Float($0))) }       // the start tapers in, so it tucks under the first turn instead of ending in a notch
        let count = pts.count - 1
        let thEnd = th0 + 2 * .pi * Float(count) / Float(perTurn)
        let last = pts[pts.count - 1]
        let tan = SIMD3<Float>(-sin(thEnd), 0, cos(thEnd)), rad = SIMD3<Float>(cos(thEnd), 0, sin(thEnd))
        let hang = 0.27 + 0.07 * n.unit(p.seed, 144)
        let hangRows = 12
        for k in 1...hangRows {
            let u = Float(k) / Float(hangRows)
            pts.append(last + tan * (0.07 * sin(u * .pi / 2)) + rad * (0.006 * u + 0.03 * u * u) + SIMD3(0, -hang * u, 0))
            radii.append(rr * (u > 0.8 ? 1 - 0.45 * (u - 0.8) / 0.2 : 1))
        }
        // Carry a round section along the path (parallel transport), keeping the arc length for the twist.
        let nu = 8, rows = pts.count
        var tangents: [SIMD3<Float>] = []
        for k in 0..<rows { tangents.append(simd_normalize(pts[min(k + 1, rows - 1)] - pts[max(k - 1, 0)])) }
        var U = simd_normalize(simd_cross(tangents[0], SIMD3(0, 1, 0)))
        var V = simd_cross(tangents[0], U)
        var frames: [(SIMD3<Float>, SIMD3<Float>)] = [(U, V)]
        for k in 1..<rows {
            let ax = simd_cross(tangents[k - 1], tangents[k])
            if simd_length(ax) > 1e-6 {
                let q = simd_quatf(angle: asin(min(1, simd_length(ax))), axis: simd_normalize(ax))
                U = q.act(U); V = q.act(V)
            }
            frames.append((U, V))
        }
        var arc: [Float] = [0]
        for k in 1..<rows { arc.append(arc[k - 1] + simd_length(pts[k] - pts[k - 1])) }
        let surf = Surface(color: SIMD3(0.36, 0.295, 0.20), roughness: 1.0, material: .rope)
        func point(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let a = Float(i) / Float(nu) * 2 * .pi
            return pts[j] + (frames[j].0 * cos(a) + frames[j].1 * sin(a)) * radii[j]
        }
        var m = grid(nu: nu, nv: rows - 1, position: point, aux: { i, _ in Float(i) / Float(nu) * 2 - 1 },
                     alpha: { _, j in min(arc[j] / ropeScale, 1) },
                     outward: { i, j in point(i, j) - pts[j] }, surface: surf)
        // The free end: three unlaid strands, paler than the weathered rope.
        let end = pts[rows - 1]
        let fray = Surface(color: SIMD3(0.62, 0.53, 0.38), roughness: 1.0)
        for q in 0..<3 {
            let a = Float(q) * 2.1 + 6 * n.unit(p.seed, 145), l = 0.035 + 0.03 * n.unit(p.seed &* 3 &+ Int32(q), 146)
            let d = simd_normalize(SIMD3(0.55 * cos(a), -1, 0.55 * sin(a)))
            m.tube(points: [end - SIMD3(0, 0.004, 0), end + d * (l * 0.5), end + d * l + SIMD3(0.01 * cos(a), 0, 0.01 * sin(a))],
                   radii: [0.0050, 0.0036, 0.0020], sides: 4, surface: fray)
        }
        return m
    }

    // MARK: Horn cleat

    /// A cast-iron horn cleat lying on the planks with its origin on the deck surface: a foot plate bolted down at both ends, two legs, and a
    /// bar that tapers to a horn at each end and lifts a little at the tips; the tops of the horns are polished bright by rope, the rest is dark and rust-bloomed
    /// (the iron material adds the bloom). A darkened stain on the planks round the foot gives the contact.
    static func cleatMesh(seed: Int32) -> MeshBuilder {
        let n = Island.noise
        var m = MeshBuilder()
        let dark = SIMD3<Float>(0.085, 0.080, 0.082)
        let iron = Surface(color: dark, roughness: 0.55, material: .iron)
        m.chamferBox(size: SIMD3(0.036, 0.008, 0.17), chamfer: 0.0025, surface: iron, transform: translation(SIMD3(0, 0.004, 0)))
        for s: Float in [-1, 1] {
            m.chamferBox(size: SIMD3(0.026, 0.032, 0.022), chamfer: 0.003, surface: iron, transform: translation(SIMD3(0, 0.022, s * 0.04)))
        }
        let start = m.vertices.count
        var pts: [SIMD3<Float>] = [], radii: [Float] = []
        let half: Float = 0.135, steps = 12
        for k in 0...steps {
            let z = (Float(k) / Float(steps) * 2 - 1) * half, a = abs(z) / half
            pts.append(SIMD3(0, 0.043 + 0.016 * pow(a, 2.2), z))
            radii.append(0.0145 * (1 - 0.6 * a) + 0.0032)
        }
        m.tube(points: pts, radii: radii, sides: 8, surface: iron, transform: scaling(SIMD3(0.82, 1, 1)))
        for e: Float in [-1, 1] {                                                                         // round off the horn tips
            m.sphere(radius: radii[0], segments: 8, smooth: true, surface: iron,
                     transform: translation(pts[e < 0 ? 0 : steps]) * scaling(SIMD3(0.82, 1, 1)))
        }
        m.recolor(from: start) { p, nrm, c in                                                              // rope-polished tops, darker undersides
            let tipness = smoothstep(0.02, 0.10, abs(p.z))
            let polish = smoothstep(0.35, 0.8, nrm.y) * tipness
            return SIMD4(simd_mix(SIMD3(c.x, c.y, c.z), SIMD3(0.20, 0.19, 0.18), SIMD3(repeating: polish * 0.7)), c.w - 0.10 * polish)
        }
        for s: Float in [-1, 1] {                                                                         // bolts: washer, hex head, a rust bleed on the plate
            let at = SIMD3<Float>(0, 0.008, s * 0.07 + 0.002 * (n.unit(seed &+ Int32(s), 151) - 0.5))
            m.cylinder(radiusTop: 0.0105, radiusBottom: 0.0105, height: 0.0025, segments: 10, smooth: false, surface: iron, transform: translation(at))
            m.cylinder(radiusTop: 0.0072, radiusBottom: 0.0078, height: 0.0062, segments: 6, smooth: false, surface: iron,
                       transform: translation(at + SIMD3(0, 0.0025, 0)) * rotationY(6 * n.unit(seed &+ Int32(s), 152)))
            m.cylinder(radiusTop: 0.016, radiusBottom: 0.016, height: 0.0003, segments: 9, smooth: false,
                       surface: Surface(color: SIMD3(0.13, 0.06, 0.035), roughness: 1.0), transform: translation(at + SIMD3(0, -0.0001, 0)))
        }
        // Contact darkening on the planks: a margin of oil and rust-stained wood round the foot plate, a few millimetres wide, dark enough to sit in the shade.
        m.box(size: SIMD3(0.056, 0.0004, 0.195), surface: Surface(color: SIMD3(0.040, 0.027, 0.018), roughness: 0.97), transform: translation(SIMD3(0.001, 0.0021, 0)))
        return m
    }
}
