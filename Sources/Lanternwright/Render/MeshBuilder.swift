import Metal
import simd

/// Material parameters baked into vertices.
struct Surface {
    var color: SIMD3<Float>          // linear albedo
    var roughness: Float = 0.8
    var material: MaterialID = .standard
}

/// Accumulates geometry on the CPU. Every primitive takes an optional transform; normals are
/// transformed with the inverse-transpose so non-uniform scales stay correct.
///
/// Primitive origins: box/sphere/torus are centred on the origin; cylinder/cone stand on y = 0
/// (the base is at the origin), which is the handy origin for props that sit on the ground;
/// plane lies in XZ with normal +Y, centred.
struct MeshBuilder {
    private(set) var vertices: [Vertex] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool { vertices.isEmpty }

    /// A copy with every vertex colour multiplied by `m` (per-instance value/hue jitter; roughness is untouched).
    func tinted(_ m: SIMD3<Float>) -> MeshBuilder {
        var out = self
        for i in 0..<out.vertices.count {
            let c = out.vertices[i].color
            out.vertices[i].color = SIMD4(c.x * m.x, c.y * m.y, c.z * m.z, c.w)
        }
        return out
    }

    mutating func append(_ other: MeshBuilder, transform: float4x4 = matrix_identity_float4x4) {
        let base = UInt32(vertices.count)
        let n = normalMatrix(transform)
        for var v in other.vertices {
            let p = transform * v.position
            let nn = normalize(n * SIMD3(v.normal.x, v.normal.y, v.normal.z))
            v.position = SIMD4(p.x, p.y, p.z, 1)
            v.normal = SIMD4(nn, v.normal.w)
            vertices.append(v)
        }
        indices.append(contentsOf: other.indices.map { $0 + base })
    }

    func build(device: MTLDevice, label: String = "mesh") -> Mesh {
        Mesh(device: device, vertices: vertices, indices: indices, label: label)
    }

    // MARK: Core

    private func normalMatrix(_ m: float4x4) -> simd_float3x3 {
        let m3 = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                               SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                               SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        return m3.inverse.transpose
    }

    /// Adds triangles over shared positions. `smoothNormals == nil` means flat shading (each triangle
    /// gets its own vertices and face normal); otherwise vertices are shared with those normals.
    /// Degenerate triangles (poles, cone tips) are skipped.
    mutating func addIndexed(positions: [SIMD3<Float>], indices tris: [UInt32], smoothNormals: [SIMD3<Float>]?,
                             surface: Surface, transform: float4x4) {
        let nm = normalMatrix(transform)
        let color = SIMD4(surface.color, surface.roughness)
        let mat = surface.material.rawValue
        func emit(_ p: SIMD3<Float>, _ n: SIMD3<Float>) {
            let wp = transform * SIMD4(p, 1)
            let wn = normalize(nm * n)
            vertices.append(Vertex(position: SIMD4(wp.x, wp.y, wp.z, 1), normal: SIMD4(wn, mat), color: color))
        }
        if let normals = smoothNormals {
            let base = UInt32(vertices.count)
            for (p, n) in zip(positions, normals) { emit(p, n) }
            for t in stride(from: 0, to: tris.count, by: 3) {
                let (a, b, c) = (positions[Int(tris[t])], positions[Int(tris[t + 1])], positions[Int(tris[t + 2])])
                if length_squared(cross(b - a, c - a)) < 1e-12 { continue }
                indices.append(contentsOf: [base + tris[t], base + tris[t + 1], base + tris[t + 2]])
            }
        } else {
            for t in stride(from: 0, to: tris.count, by: 3) {
                let (a, b, c) = (positions[Int(tris[t])], positions[Int(tris[t + 1])], positions[Int(tris[t + 2])])
                let n = cross(b - a, c - a)
                if length_squared(n) < 1e-12 { continue }
                let fn = normalize(n)
                let base = UInt32(vertices.count)
                emit(a, fn); emit(b, fn); emit(c, fn)
                indices.append(contentsOf: [base, base + 1, base + 2])
            }
        }
    }

    // MARK: Post-processing

    /// Rewrite vertex colours (e.g. moss on upward faces). The closure gets position, normal and colour.
    mutating func recolor(from start: Int = 0, _ f: (SIMD3<Float>, SIMD3<Float>, SIMD4<Float>) -> SIMD4<Float>) {
        for i in start..<vertices.count {
            let v = vertices[i]
            vertices[i].color = f(SIMD3(v.position.x, v.position.y, v.position.z), SIMD3(v.normal.x, v.normal.y, v.normal.z), v.color)
        }
    }

    // MARK: Primitives

    /// Revolve a profile of (radius, height) points about the Y axis. Each profile segment is its own band, so corners between
    /// segments stay crisp (plinth steps, string courses, cornices) while each band is smooth around its ring. Wind the profile
    /// bottom to top along the outside of the solid.
    mutating func lathe(profile: [SIMD2<Float>], segments: Int = 32, smooth: Bool = true, surface: Surface,
                        transform: float4x4 = matrix_identity_float4x4) {
        let n = max(3, segments)
        for k in 0..<max(profile.count - 1, 0) {
            let p0 = profile[k], p1 = profile[k + 1]
            let d = p1 - p0
            guard simd_length(d) > 1e-6 else { continue }
            let n2 = simd_normalize(SIMD2(d.y, -d.x))                    // outward normal in the (r, y) plane
            var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi, (c, s) = (cos(a), sin(a))
                pos.append(SIMD3(p0.x * c, p0.y, p0.x * s)); nrm.append(SIMD3(n2.x * c, n2.y, n2.x * s))
            }
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi, (c, s) = (cos(a), sin(a))
                pos.append(SIMD3(p1.x * c, p1.y, p1.x * s)); nrm.append(SIMD3(n2.x * c, n2.y, n2.x * s))
            }
            for i in 0..<n {
                let j = (i + 1) % n
                let (b0, b1, t0, t1) = (UInt32(i), UInt32(j), UInt32(n + i), UInt32(n + j))
                idx.append(contentsOf: [b0, t0, t1, b0, t1, b1])
            }
            addIndexed(positions: pos, indices: idx, smoothNormals: smooth ? nrm : nil, surface: surface, transform: transform)
        }
    }

    /// A tapered tube along a polyline (rails, brackets, branches, trunks). `radii` has one radius per point. The cross-section is
    /// carried along the path by parallel transport, so it never twists. Ends are capped flat.
    mutating func tube(points: [SIMD3<Float>], radii: [Float], sides: Int = 6, caps: Bool = true, surface: Surface,
                       transform: float4x4 = matrix_identity_float4x4) {
        guard points.count >= 2, radii.count == points.count else { return }
        let ns = max(3, sides)
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
        var tangent = simd_normalize(points[1] - points[0])
        var ref = abs(tangent.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        var u = simd_normalize(simd_cross(tangent, ref)), v = simd_cross(tangent, u)
        for (k, p) in points.enumerated() {
            let t = k == 0 ? simd_normalize(points[1] - points[0])
                : (k == points.count - 1 ? simd_normalize(points[k] - points[k - 1]) : simd_normalize(points[k + 1] - points[k - 1]))
            if k > 0 {                                                   // parallel transport: rotate the frame by the tangent change
                let axis = simd_cross(tangent, t)
                if simd_length(axis) > 1e-6 {
                    let ang = asin(min(1, simd_length(axis))), q = simd_quatf(angle: ang, axis: simd_normalize(axis))
                    u = q.act(u); v = q.act(v)
                }
                tangent = t
            }
            ref = tangent
            for j in 0..<ns {
                let a = Float(j) / Float(ns) * 2 * .pi
                let dir = u * cos(a) + v * sin(a)
                pos.append(p + dir * radii[k]); nrm.append(dir)
            }
        }
        for k in 0..<(points.count - 1) {
            for j in 0..<ns {
                let jn = (j + 1) % ns
                let a = UInt32(k * ns + j), b = UInt32(k * ns + jn), c = UInt32((k + 1) * ns + j), d = UInt32((k + 1) * ns + jn)
                idx.append(contentsOf: [a, c, d, a, d, b])
            }
        }
        addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: surface, transform: transform)
        guard caps else { return }
        for (k, up) in [(0, false), (points.count - 1, true)] {
            var p: [SIMD3<Float>] = [points[k]], ci: [UInt32] = []
            for j in 0..<ns { p.append(pos[k * ns + j]) }
            for j in 0..<ns { let (a, b) = (UInt32(1 + j), UInt32(1 + (j + 1) % ns)); ci.append(contentsOf: up ? [0, a, b] : [0, b, a]) }
            let axisDir = simd_normalize(up ? points[k] - points[k - 1] : points[k] - points[k + 1])
            addIndexed(positions: p, indices: ci, smoothNormals: [SIMD3<Float>](repeating: axisDir, count: p.count), surface: surface, transform: transform)
        }
    }

    /// The stone surround of an arched opening in the XY plane, facing +Z (the front face is at z = +depth/2): jambs of alternating
    /// long and short blocks, a semicircular ring of voussoirs and a larger keystone. `width` and `height` are the clear opening.
    mutating func arch(width: Float, height: Float, depth: Float, voussoirs: Int = 11, blockHeight: Float = 0.36,
                       surface: Surface, transform: float4x4 = matrix_identity_float4x4) {
        let bw = 0.30 * max(width, 0.8) / 1.2 + 0.1                      // jamb and voussoir thickness
        let spring = max(height - width / 2, blockHeight)                // where the curve starts
        var y: Float = 0, row = 0
        while y < spring - 1e-3 {
            let h = min(blockHeight * (row % 2 == 0 ? 1.0 : 0.8), spring - y)
            let w = bw * (row % 2 == 0 ? 1.0 : 1.35)
            for side: Float in [-1, 1] {
                bevelBox(size: SIMD3(w, h * 0.97, depth), bevel: 0.025, surface: surface,
                         transform: transform * translation(SIMD3(side * (width / 2 + w / 2), y + h / 2, 0)))
            }
            y += h; row += 1
        }
        let n = max(5, voussoirs | 1)                                    // odd, so there is a keystone at the crown
        let mid = width / 2 + bw / 2
        for i in 0..<n {
            let t = (Float(i) + 0.5) / Float(n)
            let ang = .pi - t * .pi                                      // from the left springing over the top to the right
            let arc = .pi * mid / Float(n)
            let key = i == n / 2
            let c = SIMD3(cos(ang) * mid, spring + sin(ang) * mid, 0)
            bevelBox(size: SIMD3(bw * (key ? 1.25 : 1.0), arc * 0.97 * (key ? 1.15 : 1.0), depth * (key ? 1.08 : 1.0)), bevel: 0.02, surface: surface,
                     transform: transform * translation(c) * rotationZ(ang - .pi / 2))
        }
    }

    /// A box with its edges chamfered by `bevel`, built as three overlapping boxes each inset on two axes. The steps catch
    /// the light along every edge (a hard-edged box looks like a computer model; a bevelled one looks made). No coplanar faces.
    mutating func bevelBox(size: SIMD3<Float>, bevel: Float, surface: Surface, transform: float4x4 = matrix_identity_float4x4) {
        let b = min(bevel, min(size.x, min(size.y, size.z)) * 0.3)
        box(size: SIMD3(size.x, size.y - 2 * b, size.z - 2 * b), surface: surface, transform: transform)
        box(size: SIMD3(size.x - 2 * b, size.y, size.z - 2 * b), surface: surface, transform: transform)
        box(size: SIMD3(size.x - 2 * b, size.y - 2 * b, size.z), surface: surface, transform: transform)
    }

    mutating func box(size: SIMD3<Float>, surface: Surface, transform: float4x4 = matrix_identity_float4x4) {
        let h = size * 0.5
        let faces: [[SIMD3<Float>]] = [
            [SIMD3(h.x, -h.y, h.z), SIMD3(h.x, -h.y, -h.z), SIMD3(h.x, h.y, -h.z), SIMD3(h.x, h.y, h.z)],        // +X
            [SIMD3(-h.x, -h.y, -h.z), SIMD3(-h.x, -h.y, h.z), SIMD3(-h.x, h.y, h.z), SIMD3(-h.x, h.y, -h.z)],    // -X
            [SIMD3(-h.x, h.y, h.z), SIMD3(h.x, h.y, h.z), SIMD3(h.x, h.y, -h.z), SIMD3(-h.x, h.y, -h.z)],        // +Y
            [SIMD3(-h.x, -h.y, -h.z), SIMD3(h.x, -h.y, -h.z), SIMD3(h.x, -h.y, h.z), SIMD3(-h.x, -h.y, h.z)],    // -Y
            [SIMD3(-h.x, -h.y, h.z), SIMD3(h.x, -h.y, h.z), SIMD3(h.x, h.y, h.z), SIMD3(-h.x, h.y, h.z)],        // +Z
            [SIMD3(h.x, -h.y, -h.z), SIMD3(-h.x, -h.y, -h.z), SIMD3(-h.x, h.y, -h.z), SIMD3(h.x, h.y, -h.z)],    // -Z
        ]
        var pos: [SIMD3<Float>] = [], idx: [UInt32] = []
        for f in faces {
            let b = UInt32(pos.count)
            pos.append(contentsOf: f)
            idx.append(contentsOf: [b, b + 1, b + 2, b, b + 2, b + 3])
        }
        addIndexed(positions: pos, indices: idx, smoothNormals: nil, surface: surface, transform: transform)
    }

    /// Frustum of a cone standing on y = 0. radiusTop == 0 gives a cone. `smooth` interpolates the side normals.
    mutating func cylinder(radiusTop: Float, radiusBottom: Float, height: Float, segments: Int = 16,
                           smooth: Bool = true, caps: Bool = true, surface: Surface,
                           transform: float4x4 = matrix_identity_float4x4) {
        let n = max(3, segments)
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
        // Ring vertices: bottom 0..<n, top n..<2n.
        for i in 0..<n {
            let a = Float(i) / Float(n) * 2 * .pi
            let (c, s) = (cos(a), sin(a))
            pos.append(SIMD3(radiusBottom * c, 0, radiusBottom * s))
            nrm.append(normalize(SIMD3(c * height, radiusBottom - radiusTop, s * height)))
        }
        for i in 0..<n {
            let a = Float(i) / Float(n) * 2 * .pi
            let (c, s) = (cos(a), sin(a))
            pos.append(SIMD3(radiusTop * c, height, radiusTop * s))
            nrm.append(normalize(SIMD3(c * height, radiusBottom - radiusTop, s * height)))
        }
        for i in 0..<n {
            let j = (i + 1) % n
            let (b0, b1, t0, t1) = (UInt32(i), UInt32(j), UInt32(n + i), UInt32(n + j))
            idx.append(contentsOf: [b0, t0, t1, b0, t1, b1])
        }
        addIndexed(positions: pos, indices: idx, smoothNormals: smooth ? nrm : nil, surface: surface, transform: transform)

        guard caps else { return }
        func cap(radius: Float, y: Float, up: Bool) {
            guard radius > 1e-5 else { return }
            var p: [SIMD3<Float>] = [SIMD3(0, y, 0)]
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi
                p.append(SIMD3(radius * cos(a), y, radius * sin(a)))
            }
            var ci: [UInt32] = []
            for i in 0..<n {
                let (a, b) = (UInt32(1 + i), UInt32(1 + (i + 1) % n))
                ci.append(contentsOf: up ? [0, b, a] : [0, a, b])
            }
            let normal = SIMD3<Float>(0, up ? 1 : -1, 0)
            addIndexed(positions: p, indices: ci, smoothNormals: [SIMD3<Float>](repeating: normal, count: p.count),
                       surface: surface, transform: transform)
        }
        cap(radius: radiusBottom, y: 0, up: false)
        cap(radius: radiusTop, y: height, up: true)
    }

    mutating func cone(radius: Float, height: Float, segments: Int = 16, smooth: Bool = true, surface: Surface,
                       transform: float4x4 = matrix_identity_float4x4) {
        cylinder(radiusTop: 0, radiusBottom: radius, height: height, segments: segments, smooth: smooth,
                 surface: surface, transform: transform)
    }

    mutating func sphere(radius: Float, segments: Int = 24, smooth: Bool = true, surface: Surface,
                         transform: float4x4 = matrix_identity_float4x4) {
        let lon = max(3, segments), rings = max(2, segments / 2)
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
        for r in 0...rings {
            let theta = Float(r) / Float(rings) * .pi
            for s in 0..<lon {
                let phi = Float(s) / Float(lon) * 2 * .pi
                let n = SIMD3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
                pos.append(n * radius); nrm.append(n)
            }
        }
        for r in 0..<rings {
            for s in 0..<lon {
                let a = UInt32(r * lon + s), b = UInt32(r * lon + (s + 1) % lon)
                let c = UInt32((r + 1) * lon + s), d = UInt32((r + 1) * lon + (s + 1) % lon)
                idx.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        addIndexed(positions: pos, indices: idx, smoothNormals: smooth ? nrm : nil, surface: surface, transform: transform)
    }

    /// Torus around the Y axis: `major` is the ring radius, `minor` the tube radius.
    mutating func torus(major: Float, minor: Float, segments: Int = 32, sides: Int = 12, smooth: Bool = true,
                        surface: Surface, transform: float4x4 = matrix_identity_float4x4) {
        let nu = max(3, segments), nv = max(3, sides)
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
        for i in 0..<nu {
            let u = Float(i) / Float(nu) * 2 * .pi
            for j in 0..<nv {
                let v = Float(j) / Float(nv) * 2 * .pi
                let n = SIMD3(cos(v) * cos(u), sin(v), cos(v) * sin(u))
                pos.append(SIMD3((major + minor * cos(v)) * cos(u), minor * sin(v), (major + minor * cos(v)) * sin(u)))
                nrm.append(n)
            }
        }
        for i in 0..<nu {
            for j in 0..<nv {
                let a = UInt32(i * nv + j), b = UInt32(((i + 1) % nu) * nv + j)
                let c = UInt32(i * nv + (j + 1) % nv), d = UInt32(((i + 1) % nu) * nv + (j + 1) % nv)
                idx.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        addIndexed(positions: pos, indices: idx, smoothNormals: smooth ? nrm : nil, surface: surface, transform: transform)
    }

    /// Flat grid in XZ, normal +Y, `grid` quads per side.
    mutating func plane(width: Float, depth: Float, grid: Int = 1, surface: Surface,
                        transform: float4x4 = matrix_identity_float4x4) {
        let g = max(1, grid)
        var pos: [SIMD3<Float>] = [], idx: [UInt32] = []
        for i in 0...g {
            for j in 0...g {
                pos.append(SIMD3((Float(i) / Float(g) - 0.5) * width, 0, (Float(j) / Float(g) - 0.5) * depth))
            }
        }
        for i in 0..<g {
            for j in 0..<g {
                let a = UInt32(i * (g + 1) + j), c = UInt32(i * (g + 1) + j + 1)
                let b = UInt32((i + 1) * (g + 1) + j), d = UInt32((i + 1) * (g + 1) + j + 1)
                idx.append(contentsOf: [a, c, d, a, d, b])
            }
        }
        addIndexed(positions: pos, indices: idx, smoothNormals: [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: pos.count),
                   surface: surface, transform: transform)
    }

    /// Subdivided icosahedron, a sphere with even triangles (no pinched poles). `radius(direction)` scales each
    /// vertex, which is how rocks get their lumpy shape. Flat-shaded by default (faceted stone).
    mutating func icosphere(subdivisions: Int = 2, smooth: Bool = false, radius: (SIMD3<Float>) -> Float,
                            surface: Surface, transform: float4x4 = matrix_identity_float4x4) {
        let t: Float = (1 + Float(5).squareRoot()) / 2
        var dirs: [SIMD3<Float>] = [
            SIMD3(-1, t, 0), SIMD3(1, t, 0), SIMD3(-1, -t, 0), SIMD3(1, -t, 0),
            SIMD3(0, -1, t), SIMD3(0, 1, t), SIMD3(0, -1, -t), SIMD3(0, 1, -t),
            SIMD3(t, 0, -1), SIMD3(t, 0, 1), SIMD3(-t, 0, -1), SIMD3(-t, 0, 1),
        ].map { normalize($0) }
        var faces: [UInt32] = [
            0, 11, 5,  0, 5, 1,  0, 1, 7,  0, 7, 10,  0, 10, 11,
            1, 5, 9,  5, 11, 4,  11, 10, 2,  10, 7, 6,  7, 1, 8,
            3, 9, 4,  3, 4, 2,  3, 2, 6,  3, 6, 8,  3, 8, 9,
            4, 9, 5,  2, 4, 11,  6, 2, 10,  8, 6, 7,  9, 8, 1,
        ]
        for _ in 0..<max(0, subdivisions) {
            var cache: [UInt64: UInt32] = [:]
            func mid(_ a: UInt32, _ b: UInt32) -> UInt32 {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                if let m = cache[key] { return m }
                dirs.append(normalize(dirs[Int(a)] + dirs[Int(b)]))
                let idx = UInt32(dirs.count - 1)
                cache[key] = idx
                return idx
            }
            var next: [UInt32] = []
            for f in stride(from: 0, to: faces.count, by: 3) {
                let (a, b, c) = (faces[f], faces[f + 1], faces[f + 2])
                let (ab, bc, ca) = (mid(a, b), mid(b, c), mid(c, a))
                next.append(contentsOf: [a, ab, ca,  b, bc, ab,  c, ca, bc,  ab, bc, ca])
            }
            faces = next
        }
        let pos = dirs.map { $0 * radius($0) }
        addIndexed(positions: pos, indices: faces, smoothNormals: smooth ? dirs : nil, surface: surface, transform: transform)
    }
}
