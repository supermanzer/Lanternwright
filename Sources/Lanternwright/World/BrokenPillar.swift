import simd

/// The islet's broken pillar (F02 G2, user note #25). The old version stood a flat-capped stump beside a flat-ended drum that had been rotated so it
/// pierced the stump's side. Now: one fracture surface (a stepped, oblique, conchoidal break from domain-warped noise, 3 to 8 cm deep) is used for BOTH the
/// stump's top and the fallen piece's broken end, so the two would fit together; the fallen piece's rest pose is solved from its own vertices (it lies
/// outward from the stump, clear of the stump and its footing by more than 2 cm, its lowest vertex 1.5 cm into the ground); fresh break faces are paler
/// and rougher than the weathered sides; a few chips lie around. Pure functions of their inputs so the selftest can check the geometry.
enum BrokenPillar {
    struct Result {
        var stump: MeshBuilder            // in the pillar's own frame (y = 0 is the stump's base); the caller transforms it with `stumpTransform`
        var stumpTransform: float4x4      // islet-local
        var fallen: MeshBuilder           // islet-local, final pose, including its cap block
        var chips: MeshBuilder            // islet-local
        var footingHalf: Float            // half-width of the square footing under the stump (m), centred on the pillar, in the pillar's frame
        var stumpTopY: Float              // pillar-frame height of the stump's lowest top point
    }

    /// Smooth value noise on an integer lattice (deterministic).
    private static func vn(_ x: Float, _ z: Float, _ salt: Int32) -> Float {
        let ix = floor(x), iz = floor(z), fx = x - ix, fz = z - iz
        let sx = fx * fx * (3 - 2 * fx), sz = fz * fz * (3 - 2 * fz)
        func h(_ i: Float, _ j: Float) -> Float { Island.noise.unit(Int32(i) &+ salt &* 31, Int32(j) &+ salt) }
        let a = h(ix, iz), b = h(ix + 1, iz), c = h(ix, iz + 1), d = h(ix + 1, iz + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sz
    }

    /// Height offset (m) of the break plane at (x, z) in the pillar's frame: a warped two-octave noise snapped partly to steps, plus an oblique tilt.
    static func fracture(seed: Int32, amp: Float, tilt: SIMD2<Float>) -> (Float, Float) -> Float {
        return { x, z in
            let wx = x + 0.35 * (vn(x * 2.1 + 7, z * 2.1, seed) - 0.5), wz = z + 0.35 * (vn(x * 2.1, z * 2.1 + 13, seed + 5) - 0.5)
            var v = (vn(wx * 3.0, wz * 3.0, seed + 11) - 0.5) + 0.35 * (vn(wx * 7.3 + 31, wz * 7.3, seed + 17) - 0.5)
            v = 0.55 * v + 0.45 * (floor(v * 4 + 0.5) / 4)                          // part smooth, part stepped
            return amp * 2 * v + tilt.x * x + tilt.y * z
        }
    }

    /// A tapering hexagonal prism along +Y from y = 0 to `length`; either end may be a fracture surface (`fractureBottom`/`fractureTop` give the end's y offset at
    /// (x, z)). Side facets and caps are flat-shaded. The fractured ends use `fresh` (pale, rough), everything else `stone`.
    static func prism(rBottom: Float, rTop: Float, length: Float, fractureBottom: ((Float, Float) -> Float)?, fractureTop: ((Float, Float) -> Float)?,
                      chipSalt: Int32, stone: Surface, fresh: Surface) -> MeshBuilder {
        let sub = 4, nb = 6 * sub
        var unit: [SIMD2<Float>] = []                                              // the hexagon's outline with unit circumradius
        for i in 0..<6 {
            let a0 = Float(i) / 6 * 2 * .pi, a1 = Float(i + 1) / 6 * 2 * .pi
            let c0 = SIMD2(cos(a0), sin(a0)), c1 = SIMD2(cos(a1), sin(a1))
            for j in 0..<sub { unit.append(c0 + (c1 - c0) * (Float(j) / Float(sub))) }
        }
        func chip(_ k: Int, _ end: Int) -> Float {                                    // an edge chip: the outline pulled in by up to 4 cm at some points
            let r = Island.noise.unit(Int32(k) &+ chipSalt, Int32(end) &+ 91)
            return r > 0.62 ? (r - 0.62) / 0.38 * 0.04 : 0
        }
        func end(_ y: Float, _ r: Float, _ f: ((Float, Float) -> Float)?, _ endIndex: Int) -> [SIMD3<Float>] {
            (0..<nb).map { k in
                let inset = f == nil ? 0 : chip(k, endIndex)
                let p = unit[k] * (r - inset)
                return SIMD3(p.x, y + (f?(p.x, p.y) ?? 0), p.y)
            }
        }
        let bot = end(0, rBottom, fractureBottom, 0), top = end(length, rTop, fractureTop, 1)
        var m = MeshBuilder()
        // Sides.
        var pos = bot + top, idx: [UInt32] = []
        for k in 0..<nb {
            let k1 = (k + 1) % nb
            idx += [UInt32(k), UInt32(nb + k), UInt32(nb + k1), UInt32(k), UInt32(nb + k1), UInt32(k1)]
        }
        for t in stride(from: 0, to: idx.count, by: 3) {                               // make every facet face outward
            let a = pos[Int(idx[t])], b = pos[Int(idx[t + 1])], c = pos[Int(idx[t + 2])]
            let n = simd_cross(b - a, c - a), mid = (a + b + c) / 3
            if simd_dot(n, SIMD3(mid.x, 0, mid.z)) < 0 { idx.swapAt(t + 1, t + 2) }
        }
        m.addIndexed(positions: pos, indices: idx, smoothNormals: nil, surface: stone, transform: matrix_identity_float4x4)
        // Caps: a polar grid of three rings and a centre, every point lifted by the fracture function.
        func cap(ring0: [SIMD3<Float>], f: ((Float, Float) -> Float)?, y: Float, up: Bool) {
            guard let f else {
                var p = ring0 + [SIMD3(0, y, 0)], ix: [UInt32] = []
                for k in 0..<nb { ix += [UInt32(nb), UInt32(k), UInt32((k + 1) % nb)] }
                orient(&p, &ix, up: up)
                m.addIndexed(positions: p, indices: ix, smoothNormals: nil, surface: stone, transform: matrix_identity_float4x4)
                return
            }
            var p: [SIMD3<Float>] = [], ix: [UInt32] = []
            let fr: [Float] = [1, 0.66, 0.33]
            for s in fr { for k in 0..<nb { let q = SIMD2(ring0[k].x, ring0[k].z) * s; p.append(SIMD3(q.x, y + f(q.x, q.y), q.y)) } }
            p.append(SIMD3(0, y + f(0, 0), 0))
            let centre = UInt32(p.count - 1)
            for r in 0..<(fr.count - 1) {
                for k in 0..<nb {
                    let k1 = (k + 1) % nb
                    let o0 = UInt32(r * nb + k), o1 = UInt32(r * nb + k1), i0 = UInt32((r + 1) * nb + k), i1 = UInt32((r + 1) * nb + k1)
                    ix += [o0, o1, i1, o0, i1, i0]
                }
            }
            let last = (fr.count - 1) * nb
            for k in 0..<nb { ix += [UInt32(last + k), UInt32(last + (k + 1) % nb), centre] }
            orient(&p, &ix, up: up)
            m.addIndexed(positions: p, indices: ix, smoothNormals: nil, surface: fresh, transform: matrix_identity_float4x4)
        }
        func orient(_ p: inout [SIMD3<Float>], _ ix: inout [UInt32], up: Bool) {
            for t in stride(from: 0, to: ix.count, by: 3) {
                let n = simd_cross(p[Int(ix[t + 1])] - p[Int(ix[t])], p[Int(ix[t + 2])] - p[Int(ix[t])])
                if (up && n.y < 0) || (!up && n.y > 0) { ix.swapAt(t + 1, t + 2) }
            }
        }
        // The cap rings are the plain outlines (no chips) so the grid stays in step with the sides' end ring; the end ring itself carries the chips.
        cap(ring0: bottomOutline(unit, rBottom), f: fractureBottom, y: 0, up: false)
        cap(ring0: topOutline(unit, rTop), f: fractureTop, y: length, up: true)
        return m
    }
    private static func bottomOutline(_ u: [SIMD2<Float>], _ r: Float) -> [SIMD3<Float>] { u.map { SIMD3($0.x * r, 0, $0.y * r) } }
    private static func topOutline(_ u: [SIMD2<Float>], _ r: Float) -> [SIMD3<Float>] { u.map { SIMD3($0.x * r, 0, $0.y * r) } }

    /// Build the broken pillar `index` of the islet. `centre` is the pillar's base in islet-local coordinates, `h` its full height, `rb`/`rt` base/top radius,
    /// `ground(x, z)` the islet-local ground height, `outward` the world heading (radians about +Y, x = cos, z = sin) the top fell toward.
    static func build(index: Int, centre: SIMD3<Float>, yaw: Float, h: Float, rb: Float, rt: Float, outward: Float, ground: (Float, Float) -> Float) -> Result {
        let stone = Surface(color: SIMD3(0.40, 0.38, 0.35), roughness: 0.85, material: .dressed)
        let fresh = Surface(color: SIMD3(0.62, 0.59, 0.54), roughness: 0.97, material: .rock)         // newly broken: pale, rough, unweathered
        let seed = Int32(index) &* 17 &+ 3
        let fr = fracture(seed: seed, amp: 0.055, tilt: SIMD2(0.16, -0.05))
        let stumpL = h * 0.45, upperL = h - stumpL
        let rBreak = rb + (rt - rb) * 0.45
        let stump = prism(rBottom: rb, rTop: rBreak, length: stumpL, fractureBottom: nil, fractureTop: fr, chipSalt: seed, stone: stone, fresh: fresh)
        let stumpT = translation(centre) * rotationY(yaw) * translation(SIMD3(0, 0.1, 0))

        // The fallen upper part, in its own upright frame: broken end at y = 0 (the same fracture surface), original top at y = upperL.
        var piece = prism(rBottom: rBreak, rTop: rt, length: upperL, fractureBottom: fr, fractureTop: nil, chipSalt: seed &+ 1000, stone: stone, fresh: fresh)
        piece.chamferBox(size: SIMD3(rt * 2.0, 0.22, rt * 2.0), chamfer: 0.05, surface: stone, transform: translation(SIMD3(0, upperL + 0.1, 0)))
        // Rest pose: its axis points along the fall heading (a cone rests with its thin end a little higher), lying on a hexagon face.
        let heading = outward + 0.5
        let f = SIMD3<Float>(cos(heading), 0, sin(heading))
        let tilt = atan((rBreak - rt) * 0.866 / upperL)
        let fAxis = simd_normalize(f * cos(tilt) + SIMD3(0, sin(tilt), 0))
        let right = simd_normalize(simd_cross(fAxis, SIMD3(0, 1, 0)))
        let upAxis = simd_cross(right, fAxis)
        let start = centre + f * 1.3 + right * 0.2                                    // the break end: clear of the footing's 1.0 m corner reach
        var pose = float4x4(columns: (SIMD4(right, 0), SIMD4(fAxis, 0), SIMD4(upAxis, 0), SIMD4(start.x, 0, start.z, 1)))
        var lowest: Float = .infinity
        for v in piece.vertices {
            let w = pose * SIMD4(v.position.x, v.position.y, v.position.z, 1)
            lowest = min(lowest, w.y - ground(w.x, w.z))
        }
        pose.columns.3.y = -lowest - 0.015                                           // settle: the lowest vertex 1.5 cm below the ground
        var fallen = MeshBuilder()
        fallen.append(piece, transform: pose)

        // Chips: little flat pieces of fresh stone around the break and the drum's end.
        var chips = MeshBuilder()
        let chipSurface = Surface(color: SIMD3(0.58, 0.55, 0.50), roughness: 0.97, material: .rock)
        for k in 0..<7 {
            let r1 = Island.noise.unit(Int32(k) &+ seed, 301), r2 = Island.noise.unit(Int32(k) &+ seed, 302), r3 = Island.noise.unit(Int32(k) &+ seed, 303)
            let near = k < 4 ? start : centre + f * 0.9
            let a = r1 * 2 * .pi, d = 0.3 + 0.9 * r2
            let p = near + SIMD3(cos(a) * d, 0, sin(a) * d)
            let s = 0.04 + 0.08 * r3
            let g = ground(p.x, p.z)
            chips.icosphere(subdivisions: 1, smooth: false, geometricNormals: true, radius: { n in 1 + 0.3 * sin(n.x * 5.1 + n.z * 3.7 + Float(k)) },
                            surface: chipSurface, transform: translation(SIMD3(p.x, g + s * 0.1, p.z)) * rotationY(r1 * 6.28) * scaling(SIMD3(s * 1.2, s * 0.55, s)))
        }
        return Result(stump: stump, stumpTransform: stumpT, fallen: fallen, chips: chips, footingHalf: rb * 1.25, stumpTopY: 0.1 + stumpL)
    }
}
