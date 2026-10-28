import Metal
import simd

/// Trees with real structure (R03 / T57.4). A conifer is a bark trunk (root flare, curve, taper) carrying whorls of drooping branch
/// tubes; the foliage is a mass of small, flattened, noise-displaced bough clumps on those branches, not stacked cones. Each clump's
/// normals are bent away from the crown centre, so the whole crown shades as one soft volume instead of showing facets, and its vertex
/// colour bakes a dark interior and light tips (cheap ambient occlusion). The existing wrap lighting and back-lit translucency of the
/// foliage material still apply.
///
/// Three levels of detail are built (0: full structure for under ~45 m; 1: trunk and a few large clumps; 2: the old cone silhouette),
/// 16 seeded variants per species and level. Individual trees are instances of a variant with their own height, width, lean, yaw and
/// shade, so no two neighbours match without building thousands of meshes.
enum Trees {
    enum Style { case pine, cypress }
    static let variantCount = 16
    static let nominalHeight: Float = 9
    /// How far (tree-local metres, before the tree's height scale) a trunk continues below its pivot, hidden by the terrain (F02 G1).
    static let buriedDepth: Float = 1.5

    private static var cache: [Int: MeshBuilder] = [:]
    /// A fallen cone lying on its side, 5-9 cm long: its underside (the lower generatrix) at local y = 0, pointing along +Z, base end first. Place with Placement.lay.
    static func litterCone(_ r: (Int) -> Float) -> (mesh: MeshBuilder, halfX: Float, halfZ: Float, sink: Float) {
        let L = 0.05 + 0.04 * r(1), R = 0.017 + 0.011 * r(2)
        var b = MeshBuilder()
        let axis = simd_normalize(SIMD3<Float>(0, -R, L))                    // the apex touches the ground, the base end is R above it
        b.cone(radius: R, height: simd_length(SIMD3(R, L, 0)), segments: 7, smooth: true, surface: Surface(color: SIMD3(0.20, 0.115, 0.06) * (0.8 + 0.4 * r(3)), roughness: 0.9),
               transform: translation(SIMD3(0, R, 0)) * rotation(aligningYTo: axis))
        return (b, R, L / 2, 0.45 * R)
    }
    /// A fallen twig 25-80 cm long lying along +Z with its underside at local y = 0.
    static func litterTwig(_ r: (Int) -> Float) -> (mesh: MeshBuilder, halfX: Float, halfZ: Float, sink: Float) {
        let len = 0.25 + 0.55 * r(1), rad = 0.008 + 0.006 * r(2)
        var b = MeshBuilder()
        b.tube(points: [SIMD3(0, rad, 0), SIMD3(0.01 * (r(3) - 0.5), rad * 1.1, len * 0.5), SIMD3(0, rad, len)], radii: [rad, rad * 0.75, rad * 0.4], sides: 4,
               surface: Surface(color: SIMD3(0.18, 0.13, 0.09), roughness: 0.95))
        return (b, rad, len / 2, 0.4 * rad)
    }

    static func variant(_ style: Style, _ index: Int, lod: Int) -> MeshBuilder {
        let key = (style == .pine ? 0 : 1000) + index * 10 + lod
        if let c = cache[key] { return c }
        var m = conifer(seed: UInt32(7000 + index * 131 + (style == .pine ? 17 : 0)), style: style, lod: lod)
        if lod >= 1 { m = Trees.matchSilhouette(m, to: variant(style, index, lod: 0)) }
        cache[key] = m
        return m
    }

    /// Silhouette numbers of a tree mesh above the ground: its height, its widest radius, and its radius at half height.
    static func silhouette(_ m: MeshBuilder) -> (top: Float, rad: Float, mid: Float) {
        var top: Float = 0, rad: Float = 0, mid: Float = 0
        for v in m.vertices where v.position.y > -0.5 { top = max(top, v.position.y) }
        for v in m.vertices where v.position.y > -0.5 {
            let r = simd_length(SIMD2(v.position.x, v.position.z))
            rad = max(rad, r)
            if v.position.y >= 0.4 * top && v.position.y <= 0.6 * top { mid = max(mid, r) }
        }
        return (top, rad, mid)
    }

    /// F02 R2 (user note #26: distant details "jump back" as you walk toward them): each level of detail of a tree must have the same size as the near one, or the
    /// swap is a visible change of size. Measured before this: the far cone silhouette (LOD2) was about HALF the width of the full tree (pine radius 2.1 m against
    /// 4.3 m, 1.4 m against 3.6 m at half height) and the mid level 20 % wider. This scales a level about the trunk axis so its widest radius and its half-height radius
    /// are, on average, those of level 0, and its height the same (normals are corrected for the non-uniform scale).
    static func matchSilhouette(_ lod: MeshBuilder, to ref: MeshBuilder) -> MeshBuilder {
        let a = silhouette(lod), b = silhouette(ref)
        guard a.rad > 0.01, a.mid > 0.01, a.top > 0.01 else { return lod }
        let sxz = min(max(0.5 * (b.rad / a.rad + b.mid / a.mid), 0.5), 3.0), sy = min(max(b.top / a.top, 0.8), 1.25)
        var out = lod
        out.adjust { v in
            v.position.x *= sxz; v.position.z *= sxz; v.position.y *= v.position.y > 0 ? sy : 1
            let n = SIMD3(v.normal.x / sxz, v.normal.y / sy, v.normal.z / sxz)
            let l = max(simd_length(n), 1e-6)
            v.normal.x = n.x / l; v.normal.y = n.y / l; v.normal.z = n.z / l
        }
        return out
    }
    private static var snagCache: [Int: MeshBuilder] = [:]
    /// `buried` false for a trunk that lies on its side: it has no root to carry into the ground (the extension would stick out of its base end as a stub).
    static func snagVariant(_ index: Int, lod: Int, buried: Bool = true) -> MeshBuilder {
        let key = index * 10 + lod + (buried ? 0 : 100_000)
        if let c = snagCache[key] { return c }
        let m = snag(seed: UInt32(9100 + index * 71), lod: lod, buried: buried)
        snagCache[key] = m
        return m
    }

    /// A conifer's frame: the trunk curve and radius, the crown's size and the layout of its branches. Shared by the stylised sprays (`conifer`) and the needle cards
    /// (`needleCards`), so both always sit on the same branches.
    struct Branch { var base: SIMD3<Float>; var mid: SIMD3<Float>; var tip: SIMD3<Float>; var ang: Float; var len: Float; var t: Float }
    struct Skeleton {
        var n: Noise
        var H: Float, pine: Bool
        var trunkAt: (Float) -> SIMD3<Float>
        var trunkR: (Float) -> Float
        var tStart: Float, crownR: Float, droop: Float
        var branches: [Branch]
        func r(_ i: Int, _ j: Int) -> Float { n.unit(Int32(i), Int32(j)) }
        static func make(seed: UInt32, style: Style) -> Skeleton {
            let n = Noise(seed: seed)
            func r(_ i: Int, _ j: Int) -> Float { n.unit(Int32(i), Int32(j)) }
            let H = nominalHeight, pine = style == .pine
            // Trunk: slight curve, strong taper, root flare.
            let bend = SIMD2<Float>(r(1, 1) - 0.5, r(1, 2) - 0.5) * 0.9
            func trunkAt(_ t: Float) -> SIMD3<Float> {
                SIMD3(bend.x * t * t * 0.9 + 0.08 * sin(t * 6 + r(1, 3) * 6), t * H * 0.97, bend.y * t * t * 0.9 + 0.08 * cos(t * 5 + r(1, 4) * 6))
            }
            let r0 = H * 0.034 * (0.85 + 0.3 * r(1, 5))
            func trunkR(_ t: Float) -> Float { r0 * (1 - 0.84 * t) * (1 + 0.6 * exp(-t * 16)) }
            // Crown: whorls of branches, shorter toward the top.
            let tStart: Float = pine ? 0.27 : 0.15
            let crownR = H * (pine ? 0.27 : 0.135) * (0.85 + 0.3 * r(2, 2))
            let whorls = pine ? 9 : 11
            let perWhorl = pine ? 5 : 4
            let droop: Float = (pine ? 0.26 : 0.12) * (0.8 + 0.4 * r(2, 3))
            var branches: [Branch] = []
            for w in 0..<whorls {
                let t = tStart + (0.97 - tStart) * (Float(w) + 0.5) / Float(whorls)
                let p0 = trunkAt(t)
                let taper = pow(max(1 - (t - tStart) / (1 - tStart), 0.05), pine ? 0.8 : 0.95)
                let reach = crownR * taper * (0.75 + 0.5 * r(w, 3)) + 0.25
                let phase = r(w, 4) * 2 * .pi
                for k in 0..<perWhorl {
                    let ang = phase + (Float(k) + 0.3 * (r(w * 7 + k, 5) - 0.5)) * 2 * .pi / Float(perWhorl)
                    let dir = SIMD3<Float>(cos(ang), 0, sin(ang))
                    let len = reach * (0.8 + 0.4 * r(w * 7 + k, 6))
                    let mid = p0 + dir * len * 0.5 + SIMD3(0, -droop * len * 0.30 + 0.05 * len, 0)
                    let tip = p0 + dir * len + SIMD3(0, -droop * len * 0.5 + 0.12 * len, 0)
                    branches.append(Branch(base: p0, mid: mid, tip: tip, ang: ang, len: len, t: t))
                }
            }
            return Skeleton(n: n, H: H, pine: pine, trunkAt: trunkAt, trunkR: trunkR, tStart: tStart, crownR: crownR, droop: droop, branches: branches)
        }
    }

    /// One conifer of height `nominalHeight`, standing on y = 0 at the origin.
    static func conifer(seed: UInt32, style: Style, lod: Int) -> MeshBuilder {
        if lod >= 2 { return style == .pine ? Props.pine(seed: seed, height: nominalHeight) : Props.cypress(seed: seed, height: nominalHeight) }
        let sk = Skeleton.make(seed: seed, style: style)
        let n = sk.n
        func r(_ i: Int, _ j: Int) -> Float { sk.r(i, j) }
        let H = sk.H, pine = sk.pine
        let trunkAt = sk.trunkAt, trunkR = sk.trunkR
        let tStart = sk.tStart, crownR = sk.crownR, droop = sk.droop, branches = sk.branches
        var b = MeshBuilder()

        // ---- Trunk: bark material at full detail.
        let bark = Surface(color: SIMD3(0.21, 0.145, 0.10) * (0.85 + 0.3 * r(1, 6)), roughness: 0.95, material: lod == 0 ? .bark : .standard)
        let ts: [Float] = lod == 0 ? [0, 0.03, 0.08, 0.18, 0.35, 0.55, 0.75, 0.9, 1.0] : [0, 0.12, 0.5, 1.0]
        // F02 G1: the trunk simply carries on straight down below y = 0 (same radius as its base, same bark): the terrain hides the buried part, so no
        // footing or collar is needed and no gap can show on a slope.
        let b0 = trunkAt(0)
        b.tube(points: [SIMD3(b0.x, -buriedDepth, b0.z)] + ts.map(trunkAt), radii: [trunkR(0)] + ts.map(trunkR), sides: lod == 0 ? trunkSides : 5, surface: bark)

        // (The litter at the foot, cones and twigs, is no longer baked in here: on a slope it floated. See Trees.litterCone / litterTwig and Island.addTrees,
        // which place each piece on the terrain under it.)

        // The mid level keeps the near level's branch layout (same whorls, same branches), only with fewer and larger sprays, so the crown's mass
        // and outline match across the dithered cross-fade (R09).
        if lod == 0 {
            for br in branches {
                let rb = trunkR(br.t) * 0.4
                b.tube(points: [br.base, br.mid, br.tip], radii: [rb, rb * 0.55, 0.012], sides: 4, surface: bark)
            }
        }
        // ---- Foliage: flattened, noise-displaced clumps on the branches; normals bent outward, interior dark, tips light.
        let fStart = b.vertices.count
        let hue = r(3, 1)
        let leaf = Surface(color: SIMD3(0.044 + 0.02 * hue, 0.108 + 0.04 * hue, 0.048 + 0.012 * r(3, 2)), roughness: 0.9, material: .foliage)
        // Sprays: each is a flattened, pointed, serrated, drooping fan along its branch. Conifer foliage is layered, drooping and ragged,
        // not rounded blobs. 60-140 of them near the camera, a few large ones at mid range.
        var sprayId = 0
        func spray(at p: SIMD3<Float>, dir: SIMD3<Float>, length: Float, width: Float, droop: Float, detail: Int? = nil) {
            if Trees.skipSprays { return }
            sprayId += 1
            Trees.addSpray(&b, origin: p, dir: dir, length: length, width: width, droop: droop, seed: Int(seed) &+ sprayId * 31, detail: detail ?? lod, surface: leaf, noise: n)
        }
        for (i, br) in branches.enumerated() {
            let out = SIMD3<Float>(cos(br.ang), 0, sin(br.ang))
            let side = SIMD3<Float>(-out.z, 0, out.x)
            let sl = max(br.len * 0.55, 0.9)
            if lod == 0 {
                let fr: [Float] = pine ? [0.45, 0.72, 1.0] : [0.55, 1.0]
                for (k, f) in fr.enumerated() {
                    let at = br.base + (br.mid - br.base) * min(f * 2, 1) + (br.tip - br.mid) * max(f * 2 - 1, 0)
                    let yaw = (r(i * 5 + k, 21) - 0.5) * 0.7
                    spray(at: at, dir: simd_normalize(out + side * yaw), length: sl * (1.05 - 0.2 * Float(k) / 2), width: sl * 0.31, droop: droop * 1.6 + 0.12 * r(i, k + 40))
                    if k > 0 { for sgn: Float in [-1, 1] where r(i * 5 + k, 25 + Int(sgn + 1)) > 0.35 {
                        spray(at: at, dir: simd_normalize(out + side * sgn * (0.55 + 0.3 * r(i, 50 + k))), length: sl * 0.62, width: sl * 0.22, droop: droop * 1.8, detail: 1)
                    } }
                }
            } else {
                spray(at: br.base + (br.tip - br.base) * 0.5, dir: out, length: br.len * 1.12 + 0.45, width: br.len * 0.62 + 0.25, droop: droop * 1.5)
            }
        }
        let top = trunkAt(0.985)
        spray(at: top, dir: SIMD3(0.05, 1, 0.04), length: crownR * 0.55 + 0.5, width: crownR * 0.13 + 0.12, droop: 0)
        if lod == 0 { spray(at: top - SIMD3(0, 0.5, 0), dir: SIMD3(0.4, 0.7, -0.3), length: crownR * 0.4 + 0.3, width: crownR * 0.11 + 0.1, droop: 0.1) }
        let centre = trunkAt(tStart + (1 - tStart) * 0.45)
        b.adjust(from: fStart) { v in
            let p = SIMD3(v.position.x, v.position.y, v.position.z)
            let nrm = SIMD3(v.normal.x, v.normal.y, v.normal.z)
            let away = simd_normalize(p - centre)
            let bent = simd_normalize(simd_mix(nrm, away, SIMD3(repeating: 0.8)))
            v.normal = SIMD4(bent, v.normal.w)
            let dist = simd_length(SIMD2(p.x - centre.x, p.z - centre.z)) / max(crownR, 0.5)
            let lightness = simd_mix(0.5, 1.25, smoothstep(0.08, 1.0, dist)) * (0.85 + 0.3 * (bent.y * 0.5 + 0.5)) * (0.9 + 0.2 * (p.y / H))
            v.color = SIMD4(v.color.x * lightness, v.color.y * lightness, v.color.z * lightness, v.color.w)
        }
        return b
    }

    /// The full-detail trunk's sides (F03 G3: 12, so its outline is round and not an octagon).
    static let trunkSides = 12
    /// Debug (`--no-foliage`): build conifers without their spray foliage (trunk and branches only), to measure what the trunk alone does.
    nonisolated(unsafe) static var skipSprays = false
    static let cardScale: Float = 1.5, cardWidth: Float = 0.47
    private static var needleCache: [Int: MeshBuilder] = [:]
    static func needleVariant(_ style: Style, _ index: Int) -> MeshBuilder {
        let key = (style == .pine ? 0 : 1000) + index
        if let c = needleCache[key] { return c }
        let m = needleCards(seed: UInt32(7000 + index * 131 + (style == .pine ? 17 : 0)), style: style)
        needleCache[key] = m
        return m
    }

    /// The needle-level foliage of a conifer (F02 T66.13, the user's decision: needle-level conifers now that TAA is in, near level only): hundreds of small cards along every
    /// branch, two crossed pairs per station, each carrying a procedural herringbone of needles that the fragment shader turns into ALPHA (material 23, stochastic alpha-test
    /// so the temporal resolve anti-aliases the needle edges). Card coordinates travel with the vertices: u along the card (0...1) in the colour's alpha, v across (-1...1) in
    /// the fraction of the material id (23 + 0.4 v). Sits on the same branches as the stylised sprays (`Skeleton`), which stay as the foliage of the other levels and give way to
    /// these inside about 16 m (see the fragment shader's needle_weight).
    static func needleCards(seed: UInt32, style: Style) -> MeshBuilder {
        let sk = Skeleton.make(seed: seed, style: style)
        let n = sk.n
        func r(_ i: Int, _ j: Int) -> Float { n.unit(Int32(i), Int32(j)) }
        let hue = sk.r(3, 1)
        let leaf = SIMD3<Float>(0.105 + 0.03 * hue, 0.255 + 0.06 * hue, 0.085 + 0.02 * sk.r(3, 2))
        let centre = sk.trunkAt(sk.tStart + (1 - sk.tStart) * 0.45)
        let up = SIMD3<Float>(0, 1, 0)
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = [], uv: [SIMD2<Float>] = [], tint: [SIMD3<Float>] = []
        var card = 0
        func addCard(at p: SIMD3<Float>, dir: SIMD3<Float>, width: Float, length: Float, tilt: Float) {
            let d = simd_normalize(dir)
            var w = simd_cross(d, up); w = simd_length(w) < 1e-3 ? SIMD3(1, 0, 0) : simd_normalize(w)
            let nrmCard = simd_cross(w, d)                                               // roughly up
            w = simd_normalize(w * cos(tilt) + nrmCard * sin(tilt))                      // the second card of a pair is tipped up out of the first's plane
            var nc = simd_cross(d, w); if nc.y < 0 { nc = -nc }
            let away = simd_normalize(p + d * length * 0.5 - centre)
            let normal = simd_normalize(simd_mix(simd_normalize(nc), away, SIMD3(repeating: 0.7)))
            let jitter = 0.78 + 0.5 * r(card, 7)
            let dist = simd_length(SIMD2(p.x - centre.x, p.z - centre.z)) / max(sk.crownR, 0.5)
            let light = simd_mix(0.5, 1.25, smoothstep(0.08, 1.0, dist)) * (0.85 + 0.3 * (normal.y * 0.5 + 0.5)) * (0.9 + 0.2 * (p.y / sk.H))
            let base = UInt32(pos.count)
            for (u, v) in [(Float(0), Float(-1)), (0, 1), (1, 1), (1, -1)] {
                pos.append(p + d * length * u + w * width * v); nrm.append(normal); uv.append(SIMD2(u, v)); tint.append(leaf * jitter * light)
            }
            idx += [base, base + 1, base + 2, base, base + 2, base + 3]
            card += 1
        }
        for (bi, br) in sk.branches.enumerated() {
            let out = SIMD3<Float>(cos(br.ang), 0, sin(br.ang)), side = SIMD3<Float>(-out.z, 0, out.x)
            let dirB = simd_normalize(br.tip - br.base)
            let stations = max(4, Int(br.len / (sk.pine ? 0.14 : 0.12)))
            for i in 0..<stations {
                let f = 0.22 + 0.98 * Float(i) / Float(stations - 1)                       // past the branch tip (the sprays reach beyond it too)
                let at = f < 0.5 ? br.base + (br.mid - br.base) * (f * 2) : (f < 1 ? br.mid + (br.tip - br.mid) * (f * 2 - 1) : br.tip + dirB * br.len * (f - 1) * 1.0)
                for sgn: Float in [-1, 1] {
                    let yaw = sgn * (0.75 + 0.45 * r(bi * 31 + i, 11))
                    let d = dirB * 0.5 + side * yaw + SIMD3(0, -(0.18 + 0.30 * r(bi * 31 + i, 12)), 0)
                    // F03 G4 (#41): the cards were about 40 % short of the sprays' greenery (the crown lost a third of its mass at the swap), so they are longer and wider
                    // (`cardScale`, `cardWidth`) and a little more of each branch carries them; SelfTestNeedles measures the match against the far sprays.
                    let len = (sk.pine ? 0.52 : 0.38) * cardScale * (0.75 + 0.5 * r(bi * 31 + i, 13)) * (1.1 - 0.4 * f)
                    addCard(at: at, dir: d, width: len * cardWidth, length: len, tilt: 0)
                    addCard(at: at, dir: d + SIMD3(0, 0.30, 0), width: len * cardWidth, length: len * 0.9, tilt: 0.9)
                }
            }
        }
        // The leader: a tuft of upward cards along the top of the trunk (the sprays have one too), so the needle crown reaches the height of the spray crown.
        for k in 0..<10 {
            let t = 0.84 + 0.145 * Float(k) / 9
            let at = sk.trunkAt(t)
            let a = Float(k) * 2.4 + 0.7
            let q = Float(k) / 9
            let d = SIMD3<Float>(cos(a) * 0.55 * (1 - 0.8 * q), 0.85 + 0.15 * q, sin(a) * 0.55 * (1 - 0.8 * q))
            let len = 0.45 + 0.9 * q * q
            addCard(at: at, dir: d, width: len * 0.34, length: len, tilt: Float(k % 3) * 0.7)
        }
        var b = MeshBuilder()
        b.addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.9, material: .needles), transform: matrix_identity_float4x4)
        var i = 0
        b.adjust { v in
            let q = uv[i], c = tint[i]
            v.normal.w = MaterialID.needles.rawValue + 0.4 * q.y
            v.color = SIMD4(c.x, c.y, c.z, q.x)                                          // alpha channel = u along the card
            i += 1
        }
        return b
    }

    /// One conifer spray: a flattened lens that starts at `origin`, runs along `dir` (curving down by `droop`), widens then tapers to a point,
    /// with a serrated edge (every other station is narrower), a ridge on top, and edges that hang lower than the middle. Four vertices per
    /// station (left, right, top spine, bottom spine); smooth normals; `detail` 0 = 9 stations, otherwise 5.
    static func addSpray(_ b: inout MeshBuilder, origin: SIMD3<Float>, dir: SIMD3<Float>, length: Float, width: Float, droop: Float, seed: Int,
                         detail: Int, surface: Surface, noise n: Noise) {
        let up = SIMD3<Float>(0, 1, 0)
        let d = simd_normalize(dir)
        var side = simd_cross(d, up)
        side = simd_length(side) < 1e-3 ? SIMD3(1, 0, 0) : simd_normalize(side)
        let ns = detail == 0 ? 7 : 5
        var pos: [SIMD3<Float>] = [], spine: [SIMD3<Float>] = []
        for i in 0..<ns {
            let t = Float(i) / Float(ns - 1)
            let sp = origin + d * length * t + SIMD3(0, -droop * length * t * t * 0.9, 0)
            let jitter = 0.78 + 0.44 * n.unit(Int32(i), Int32(seed & 0xFFFF))
            var w = width * pow(max(t, 0.001), 0.55) * pow(max(1 - t, 0), 0.7) * 2.1 * jitter
            if detail == 0 && i % 2 == 1 { w *= 0.62 }                                    // serrated edge
            let thick = 0.16 * w + 0.012
            let hang = 0.28 * w
            pos.append(sp - side * w - SIMD3(0, hang, 0)); pos.append(sp + side * w - SIMD3(0, hang, 0))
            pos.append(sp + up * thick); pos.append(sp - up * thick * 0.5)
            spine.append(sp)
        }
        var tris: [UInt32] = []
        func tri(_ a: Int, _ b2: Int, _ c: Int, _ st: Int) {
            var (i1, i2) = (b2, c)
            let n0 = simd_cross(pos[i2] - pos[a], pos[i1] - pos[a])
            _ = n0
            let nrm = simd_cross(pos[b2] - pos[a], pos[c] - pos[a])
            let centroid = (pos[a] + pos[b2] + pos[c]) / 3
            if simd_dot(nrm, centroid - spine[st]) < 0 { swap(&i1, &i2) }
            tris.append(contentsOf: [UInt32(a), UInt32(i1), UInt32(i2)])
        }
        for i in 0..<(ns - 1) {
            let (L0, R0, T0, B0) = (i * 4, i * 4 + 1, i * 4 + 2, i * 4 + 3)
            let (L1, R1, T1, B1) = (L0 + 4, R0 + 4, T0 + 4, B0 + 4)
            tri(L0, T0, L1, i); tri(T0, T1, L1, i); tri(T0, R0, T1, i); tri(R0, R1, T1, i)          // top surface
            tri(L0, B0, L1, i); tri(B0, B1, L1, i); tri(B0, R0, B1, i); tri(R0, R1, B1, i)          // bottom surface
        }
        var nrm = [SIMD3<Float>](repeating: .zero, count: pos.count)
        for t in stride(from: 0, to: tris.count, by: 3) {
            let (a, b2, c) = (Int(tris[t]), Int(tris[t + 1]), Int(tris[t + 2]))
            let fn = simd_cross(pos[b2] - pos[a], pos[c] - pos[a])
            nrm[a] += fn; nrm[b2] += fn; nrm[c] += fn
        }
        let normals = nrm.map { simd_length($0) > 1e-9 ? simd_normalize($0) : SIMD3<Float>(0, 1, 0) }
        var s = surface
        let jitter = 0.86 + 0.28 * n.unit(Int32(seed & 0x7FFF), 7)
        s.color = surface.color * jitter
        b.addIndexed(positions: pos, indices: tris, smoothNormals: normals, surface: s, transform: matrix_identity_float4x4)
    }

    /// A dead snag: a bare trunk broken off short, with a few broken limbs and stubs.
    static func snag(seed: UInt32, lod: Int, buried: Bool = true) -> MeshBuilder {
        let n = Noise(seed: seed)
        func r(_ i: Int, _ j: Int) -> Float { n.unit(Int32(i), Int32(j)) }
        let H = nominalHeight * (0.7 + 0.2 * r(1, 1))
        var b = MeshBuilder()
        let bark = Surface(color: SIMD3(0.27, 0.235, 0.20), roughness: 0.95, material: lod == 0 ? .bark : .standard)
        let r0 = nominalHeight * 0.032
        let ts: [Float] = [0, 0.05, 0.2, 0.45, 0.75, 1.0]
        let lean = SIMD2<Float>(r(1, 2) - 0.5, r(1, 3) - 0.5) * 0.6
        let rad = { (t: Float) in r0 * (1 - 0.7 * t) * (1 + 0.5 * exp(-t * 14)) }
        b.tube(points: (buried ? [SIMD3(0, -buriedDepth, 0)] : []) + ts.map { SIMD3(lean.x * $0 * $0, $0 * H, lean.y * $0 * $0) },
               radii: (buried ? [rad(0)] : []) + ts.map(rad), sides: lod == 0 ? 7 : 5, surface: bark)
        for i in 0..<(lod == 0 ? 6 : 3) {
            let t = 0.35 + 0.55 * Float(i) / 6 + 0.05 * r(i, 4)
            let a = r(i, 5) * 2 * .pi
            let p0 = SIMD3(lean.x * t * t, t * H, lean.y * t * t)
            let len = 0.5 + 1.6 * r(i, 6) * (1 - 0.5 * t)
            let dir = SIMD3<Float>(cos(a), 0.55 + 0.4 * r(i, 7), sin(a))
            let tip = p0 + simd_normalize(dir) * len
            b.tube(points: [p0, (p0 + tip) * 0.5 + SIMD3(0, 0.08, 0), tip], radii: [r0 * 0.34 * (1 - 0.5 * t), r0 * 0.2, r0 * 0.12], sides: 4, surface: bark)
        }
        return b
    }
}
