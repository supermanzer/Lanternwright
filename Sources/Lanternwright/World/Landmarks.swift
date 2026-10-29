import Metal
import simd

enum StoneID: Int, CaseIterable {
    case tide, wind, summit

    var name: String { ["tide", "wind", "stone"][rawValue] }
    var position: SIMD3<Float> { [Layout.tideStone, Layout.windStone, Layout.summitStone][rawValue] }
    /// Glyph/capstone colour: tide = cyan, wind = pale green, stone = amber.
    var color: SIMD3<Float> { [SIMD3(0.3, 0.8, 1.0), SIMD3(0.7, 1.0, 0.8), SIMD3(1.0, 0.7, 0.3)][rawValue] }
    /// Where the player arrives from, so the stone can face them.
    var approachFrom: SIMD3<Float> { [Layout.dockShore, Layout.tideStone, Layout.windStone][rawValue] }
    static let height: Float = 3.0
}

/// The big hand-built structures: dock, lighthouse, resonance stones.
enum Landmarks {
    static let stoneHeight = StoneID.height

    static func populate(_ scene: Scene, device: MTLDevice) {
        addDock(scene, device: device)
        addBuoy(scene, device: device)
        addLighthouse(scene, device: device)
        for id in StoneID.allCases { addStone(id, scene: scene, device: device) }
    }

    // MARK: Dock

    /// A red bell buoy riding at sea; `Game` bobs it with the swell. Its bell is heard in `SonicLandmarks`.
    static func addBuoy(_ scene: Scene, device: MTLDevice) {
        let red = Surface(color: SIMD3(0.62, 0.08, 0.06), roughness: 0.5, material: .paint)
        let iron = Surface(color: SIMD3(0.10, 0.10, 0.11), roughness: 0.5, material: .iron)
        var b = MeshBuilder()
        b.cylinder(radiusTop: 0.55, radiusBottom: 0.9, height: 0.9, segments: 10, surface: red, transform: translation(SIMD3(0, -0.45, 0)))
        b.cylinder(radiusTop: 0.12, radiusBottom: 0.2, height: 1.6, segments: 8, surface: iron, transform: translation(SIMD3(0, 0.4, 0)))
        for i in 0..<4 {                                       // the bell cage: four struts and a cap
            let a = Float(i) / 4 * 2 * .pi + 0.4
            b.cylinder(radiusTop: 0.025, radiusBottom: 0.03, height: 0.9, segments: 4, surface: iron, transform: translation(SIMD3(0.3 * cos(a), 0.4, 0.3 * sin(a))))
        }
        b.cone(radius: 0.38, height: 0.35, segments: 8, surface: red, transform: translation(SIMD3(0, 1.3, 0)))
        scene.add("buoy", mesh: b.build(device: device, label: "buoy"), uniforms: ObjectUniforms(model: translation(Layout.buoy)))
    }

    static func addDock(_ scene: Scene, device: MTLDevice) {
        let strip = Layout.dockStrip()
        let ab = strip.b - strip.a
        let len = length(ab), dir = ab / len
        let slope = (strip.y1 - strip.y0) / len
        let angle = atan2(dir.x, dir.y)
        let tilt = rotationX(-atan(slope))
        let model = translation(SIMD3(strip.a.x, 0, strip.a.y)) * rotationY(angle)
        func deckY(_ z: Float) -> Float { strip.y0 + slope * z }

        var b = MeshBuilder()
        let width: Float = 2.4
        let pitch: Float = 0.275
        let deck = Surface(color: SIMD3(0.30, 0.20, 0.115), roughness: 0.85, material: .plank)
        let timber = Surface(color: SIMD3(0.20, 0.14, 0.09), roughness: 0.9, material: .timber)
        let iron = Surface(color: SIMD3(0.16, 0.15, 0.14), roughness: 0.5, material: .iron)
        // F01 W2: a deck that has stood in salt air for decades. Every board is different: width 0.15-0.27 m, gaps of 5-30 mm, a few millimetres of lift and
        // twist, cupped across its width, a bow along it; two boards are missing (the stringers and the water show), one is broken off short, one has been
        // replaced and is paler, the deck sags a little between piles. Board identity (0..1) goes into the vertex roughness channel, where the plank material
        // reads it as its seed (grain, knots, checks, tone); a value of exactly 1 marks the replacement.
        let n = Island.noise
        var z: Float = 0.12
        var k: Int32 = 0
        var missing: [Int32] = [], broken: Int32 = -1, replaced: Int32 = -1
        func plankCount() -> Int32 { var zz: Float = 0.12, kk: Int32 = 0; while zz < len - 0.1 { zz += 0.15 + 0.12 * n.unit(kk, 101) + 0.005 + 0.025 * n.unit(kk, 102); kk += 1 }; return kk }
        let total = plankCount()
        missing = [Int32(Float(total) * 0.37), Int32(Float(total) * 0.71)]
        broken = Int32(Float(total) * 0.52); replaced = Int32(Float(total) * 0.23)
        while z < len - 0.1 {
            let depth = 0.15 + 0.12 * n.unit(k, 101)                            // board width along the dock
            // Gaps are uneven (F02 G4): one board in eight is jammed tight against its neighbour, one in twelve has sprung 3-4.5 cm away, the rest 4-22 mm.
            let gap = Landmarks.deckGap(k)
            let seed = replaced == k ? 1.0 : min(n.unit(k, 103), 0.97)
            let zc = z + depth / 2
            if !missing.contains(k) {
                let tw = n.unit(k, 92) - 0.5, lift = (n.unit(k, 93) - 0.5) * 0.008
                var w = width - 0.04 * n.unit(k, 94) - (n.unit(k, 95) > 0.9 ? 0.08 : 0)
                var xoff: Float = (n.unit(k, 96) - 0.5) * 0.03
                if broken == k { w *= 0.55; xoff = 0.5 * (width - w) * (n.unit(k, 97) > 0.5 ? 1 : -1) * 0.9 }              // snapped off short
                let sag = -0.012 * sin(.pi * (zc / 4.0).truncatingRemainder(dividingBy: 1))                                   // between piles every 4 m
                let y = deckY(zc) + sag + lift
                let surf = Surface(color: (replaced == k ? SIMD3(0.46, 0.34, 0.20) : SIMD3(0.30, 0.20, 0.115)) * (0.8 + 0.4 * n.unit(k, 98)), roughness: seed, material: .plank)
                let m = translation(SIMD3(xoff, y, zc)) * tilt * rotationZ(tw * 0.02) * rotationX(tw * 0.02)
                let thick: Float = 0.045 + 0.012 * n.unit(k, 99)
                let cup = 0.002 + 0.004 * n.unit(k, 105), bow = (n.unit(k, 106) - 0.5) * 0.006
                let board = Landmarks.sawnBoard(k: k, w: w, depth: depth, thick: thick, chamfer: 0.014 + 0.01 * n.unit(k, 104), cup: cup, bow: bow, surface: surf)
                b.append(board.mesh, transform: m)
                // Nails (F02 G4): round-headed, square-cut, pulled up or sunk, never a regular octagon; each slightly oblique, rust bleeding round the head; some missing.
                // Two per end over each beam. The head sits on the board's own surface height at that spot.
                for sx: Float in [-0.95, 0.95] {
                    for dz: Float in [-1, 1] where n.unit(k * 8 + Int32(dz + 1) + (sx > 0 ? 4 : 0), 107) > 0.18 && abs(sx + xoff) < w / 2 {
                        let nk = k * 8 + Int32(dz + 1) + (sx > 0 ? 4 : 0)
                        let lx = sx - xoff, lz = dz * depth * (0.28 + 0.06 * (n.unit(nk, 122) - 0.5))
                        let surfaceY = board.height(lx, lz)
                        let rr = 0.006 + 0.006 * n.unit(nk, 108)
                        let tiltA = (n.unit(nk, 109) - 0.5) * 0.7, tiltB = (n.unit(nk, 123) - 0.5) * 0.5
                        let kind = Landmarks.nailRoll(nk)
                        let at = m * translation(SIMD3(lx, surfaceY, lz)) * rotationZ(tiltA) * rotationX(tiltB)
                        if kind < 0.50 {                                                                  // round head, half sunk in the grain
                            b.sphere(radius: rr, segments: 8, smooth: true, surface: iron, transform: at * translation(SIMD3(0, 0.0004, 0)) * scaling(SIMD3(1, 0.38, 1)))
                        } else if kind < 0.75 {                                                           // a square-cut head
                            b.box(size: SIMD3(rr * 1.8, 0.0035, rr * 1.8), surface: iron, transform: at * rotationY(n.unit(nk, 124) * 1.5) * translation(SIMD3(0, 0.0012, 0)))
                        } else if kind < 0.88 {                                                           // worked loose: the shaft shows and the head is lifted
                            let lift = 0.004 + 0.009 * n.unit(nk, 125)
                            b.cylinder(radiusTop: rr * 0.32, radiusBottom: rr * 0.38, height: lift, segments: 5, smooth: false, surface: iron, transform: at)
                            b.sphere(radius: rr, segments: 8, smooth: true, surface: iron, transform: at * translation(SIMD3(0, lift, 0)) * scaling(SIMD3(1, 0.4, 1)))
                        } else {                                                                          // driven below the surface: a dark hole
                            b.cylinder(radiusTop: rr * 0.9, radiusBottom: rr * 0.9, height: 0.0008, segments: 7, smooth: false,
                                       surface: Surface(color: SIMD3(0.03, 0.022, 0.016), roughness: 0.95), transform: at * translation(SIMD3(0, 0.0004, 0)))
                        }
                        if kind < 0.88 {                                                                  // rust bled into the wood round the head
                            b.cylinder(radiusTop: rr * (2.0 + 1.4 * n.unit(nk, 126)), radiusBottom: rr * 2.4, height: 0.0004, segments: 7, smooth: false,
                                       surface: Surface(color: SIMD3(0.10, 0.05, 0.03), roughness: 1.0), transform: at * translation(SIMD3(0, -0.0002, 0)))
                        }
                    }
                }
            }
            z += depth + gap; k += 1
        }
        // Stringers (the two beams the boards are nailed to, with a notch of rot at one end) and cross-beams every 1.1 m that show through the gaps and missing boards.
        for sx: Float in [-0.95, 0.95] {
            b.box(size: SIMD3(0.14, 0.16, len), surface: timber,
                  transform: translation(SIMD3(sx, (deckY(0) + deckY(len)) / 2 - 0.16, len / 2)) * rotationX(-atan(slope)))
        }
        var cz: Float = 0.5, ci: Int32 = 0
        while cz < len {
            b.box(size: SIMD3(2.3, 0.10, 0.12), surface: timber, transform: translation(SIMD3((n.unit(ci, 111) - 0.5) * 0.04, deckY(cz) - 0.15 - 0.008 * n.unit(ci, 112), cz)) * tilt * rotationY((n.unit(ci, 113) - 0.5) * 0.02))
            cz += 1.1; ci += 1
        }
        // Piles every 4 m on both sides, reaching well below the water; every other one stands above the deck as a mooring post (R11: its own
        // weathered, leaning, grained shaft with a worn cap, a coil of rope that touches it, and a horn cleat on the deck beside it).
        var pz: Float = 0.8, idx = 0
        while pz < len {
            for sx: Float in [-1.1, 1.1] {
                let post = idx % 2 == 0
                let pileSeed = Int32(idx * 2) + (sx > 0 ? 1 : 0)
                if post {
                    let p = DockFurniture.Post(x: sx, z: pz, top: deckY(pz) + 0.55, seed: pileSeed)
                    b.append(DockFurniture.postMesh(p))
                    b.append(DockFurniture.ropeMesh(p))
                    let side: Float = sx < 0 ? 1 : -1
                    let yaw = side * (0.35 + 0.5 * n.unit(pileSeed, 153))
                    b.append(DockFurniture.cleatMesh(seed: pileSeed), transform: translation(SIMD3(sx + side * 0.30, deckY(pz) + 0.0016, pz + (n.unit(pileSeed, 154) - 0.5) * 0.12)) * tilt * rotationY(yaw))
                } else {
                    let top = deckY(pz) - 0.12
                    let lean = (Island.noise.unit(pileSeed, 120) - 0.5) * 0.05
                    b.cylinder(radiusTop: 0.10, radiusBottom: 0.12, height: top + 3.0, segments: 10, surface: timber, transform: translation(SIMD3(sx, -3.0, pz)) * rotationZ(lean) * rotationX(lean * 0.6))
                    for q in 0..<3 { b.box(size: SIMD3(0.04, 0.05 + 0.08 * Island.noise.unit(Int32(idx) * 3 + Int32(q), 121), 0.07), surface: timber, transform: translation(SIMD3(sx + (Float(q) - 1) * 0.05, top + 0.02, pz + (Island.noise.unit(Int32(idx) * 3 + Int32(q), 122) - 0.5) * 0.06)) * rotationY(Float(q))) }   // a split, ragged top: two uneven splinters
                }
            }
            pz += 4; idx += 1
        }
        scene.add("dock", mesh: b.build(device: device, label: "dock"), uniforms: ObjectUniforms(model: model))
    }

    // MARK: Lighthouse

    static let lighthouseTop: Float = 30

    static func addLighthouse(_ scene: Scene, device: MTLDevice) {
        let lh = Layout.lighthouse
        Lighthouse.build(into: scene, device: device)
        DoorNote.build(into: scene, device: device)                 // S03.4: hidden until the altar is solved and the player is back (Game)

        // Glass of the lantern room (material 2: glossy; it glows once the lighthouse is lit).
        var glass = MeshBuilder()
        glass.cylinder(radiusTop: 2.1, radiusBottom: 2.1, height: 3.2, segments: 16, smooth: true, caps: false,
                       surface: Surface(color: SIMD3(0.35, 0.42, 0.45), roughness: 0.05, material: .emissiveGlass),
                       transform: translation(SIMD3(0, 25.4, 0)))
        scene.add("lighthouse_glass", mesh: glass.build(device: device, label: "lighthouse_glass"), uniforms: ObjectUniforms(model: translation(lh)))

        // The lens: dark until the puzzle is solved, then blazing.
        var lens = MeshBuilder()
        lens.sphere(radius: 0.85, segments: 16, surface: Surface(color: SIMD3(0.8, 0.75, 0.6), roughness: 0.2, material: .paleMetal), transform: translation(SIMD3(0, 26.9, 0)))
        scene.add("lighthouse_lens", mesh: lens.build(device: device, label: "lens"), uniforms: ObjectUniforms(model: translation(lh)))
    }

    // MARK: Resonance stones

    /// World position of the lens (where the beams converge).
    static var lensPosition: SIMD3<Float> { Layout.lighthouse + SIMD3(0, 26.9, 0) }
    /// Capstone rest position for a stone (it rises and bobs when lit).
    static func capstoneBase(_ id: StoneID) -> SIMD3<Float> { id.position + SIMD3(0, stoneHeight + 0.7, 0) }

    /// A deck board sawn by hand and aged (F02 G4, user note #32: "the lines on the dock planks are too geometric"). In its own frame: x along the board (the width of the
    /// dock), z across it, y up, centred on its top. The outline is not a rectangle: each long edge wobbles by 2-6 mm along its length, each end is cut a little off
    /// square (up to 1.5 cm over the board's width), a third of the corners are splintered off, and one board in ten has a corner lifted by 4-12 mm. The top is cupped and
    /// bowed (smooth normals); a chamfer ring, walls and an underside close the board. Every vertex carries the board's cross coordinate v (-1...1) in the fraction of its
    /// material id (12 + 0.4 v), which the plank material uses to run its grain along THIS board. `height(x, z)` is the top surface (for the nail heads).
    struct SawnBoard {
        var mesh: MeshBuilder
        var height: (Float, Float) -> Float
        var outline: [SIMD2<Float>]            // the board's perimeter (x, z) at its widest, anticlockwise from above
        var lift: Float                        // how far one corner is lifted (0 for most boards)
    }
    /// The gap (m) after deck board `k`: one board in eight is jammed against its neighbour (0), one in twelve has sprung 3-4.5 cm, the rest are 4-22 mm.
    static func deckGap(_ k: Int32) -> Float {
        let gh = Island.noise.unit(k, 102)
        return gh < 0.12 ? 0.0 : (gh > 0.92 ? 0.03 + 0.015 * (gh - 0.92) / 0.08 : 0.004 + 0.018 * gh)
    }
    /// A nail's roll (0...1): below 0.5 round head, to 0.75 square-cut, to 0.88 worked loose and lifted, above that driven below the surface.
    static func nailRoll(_ nk: Int32) -> Float { Island.noise.unit(nk, 121) }
    static func sawnBoard(k: Int32, w: Float, depth: Float, thick: Float, chamfer c: Float, cup: Float, bow: Float, surface: Surface) -> SawnBoard {
        let n = Island.noise
        let nu = 16, nv = 4
        func smooth1(_ side: Int32, _ u: Float, _ salt: Int32) -> Float {                                   // 1D value noise along the board, -1...1
            let t = (u * 0.5 + 0.5) * 5, i = floor(t), f = t - i, sm = f * f * (3 - 2 * f)
            let a = n.unit(k * 29 + side * 7 + Int32(i), salt) * 2 - 1, bb = n.unit(k * 29 + side * 7 + Int32(i) + 1, salt) * 2 - 1
            return a + (bb - a) * sm
        }
        let amp = 0.002 + 0.004 * n.unit(k, 112)
        let skewL = (n.unit(k, 113) - 0.5) * 0.03, skewR = (n.unit(k, 114) - 0.5) * 0.03
        func chip(_ i: Int32) -> Float { n.unit(k * 5 + i, 115) > 0.64 ? 0.008 + 0.03 * n.unit(k * 5 + i, 116) : 0 }
        let chips = [chip(0), chip(1), chip(2), chip(3)]                                                       // (-x,-z) (-x,+z) (+x,-z) (+x,+z)
        let liftAmt: Float = n.unit(k, 117) > 0.9 ? 0.004 + 0.008 * n.unit(k, 118) : 0
        let liftU: Float = n.unit(k, 119) > 0.5 ? 1 : -1, liftV: Float = n.unit(k, 120) > 0.5 ? 1 : -1
        func outline(_ u: Float, _ v: Float) -> SIMD2<Float> {
            let zl = -depth / 2 + amp * smooth1(0, u, 111), zr = depth / 2 + amp * smooth1(1, u, 111)
            var z = zl + (zr - zl) * (v * 0.5 + 0.5)
            let xl = -w / 2 + skewL * v, xr = w / 2 + skewR * v
            var x = xl + (xr - xl) * (u * 0.5 + 0.5)
            let wc = smoothstep(0.6, 1.0, abs(u)) * smoothstep(0.4, 1.0, abs(v))
            let ci = (u < 0 ? 0 : 2) + (v < 0 ? 0 : 1)
            x += (u < 0 ? 1 : -1) * chips[ci] * wc; z += (v < 0 ? 1 : -1) * 0.4 * chips[ci] * wc
            return SIMD2(x, z)
        }
        func hgt(_ u: Float, _ v: Float) -> Float {
            cup * (v * v) + bow * (1 - u * u) + liftAmt * smoothstep(0.2, 1.0, u * liftU) * smoothstep(0.0, 1.0, v * liftV)
        }
        let top: Float = 0.0016, bodyTop: Float = 0.0015
        // Perimeter loop of grid indices, anticlockwise from above.
        var loop: [(Int, Int)] = []
        for i in 0..<nu { loop.append((i, 0)) }
        for j in 0..<nv { loop.append((nu, j)) }
        for i in stride(from: nu, to: 0, by: -1) { loop.append((i, nv)) }
        for j in stride(from: nv, to: 0, by: -1) { loop.append((0, j)) }
        func uv(_ i: Int, _ j: Int) -> (Float, Float) { (Float(i) / Float(nu) * 2 - 1, Float(j) / Float(nv) * 2 - 1) }
        var mesh = MeshBuilder()
        // Top: the outline pulled in by the chamfer, cupped, with smooth normals.
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
        for j in 0...nv { for i in 0...nu {
            let (u, v) = uv(i, j)
            let o = outline(u, v)
            pos.append(SIMD3(o.x * (1 - c / (w / 2)), top + hgt(u, v), o.y * (1 - c / (depth / 2))))
            let e: Float = 0.05
            nrm.append(simd_normalize(SIMD3(-(hgt(u + e, v) - hgt(u - e, v)) / (2 * e * w / 2), 1, -(hgt(u, v + e) - hgt(u, v - e)) / (2 * e * depth / 2))))
        } }
        for j in 0..<nv { for i in 0..<nu {
            let a = UInt32(j * (nu + 1) + i), bb = a + 1, cc = a + UInt32(nu + 1), d = cc + 1
            idx += [a, cc, d, a, d, bb]
        } }
        mesh.addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: surface, transform: matrix_identity_float4x4)
        // Chamfer ring, walls and underside, flat-shaded, every facet turned to face outward.
        var cham: [SIMD3<Float>] = [], wall: [SIMD3<Float>] = [], under: [SIMD3<Float>] = []
        var ci: [UInt32] = [], wi: [UInt32] = [], ui: [UInt32] = []
        let m = loop.count
        for (i, j) in loop {
            let (u, v) = uv(i, j), o = outline(u, v)
            cham.append(SIMD3(o.x * (1 - c / (w / 2)), top + hgt(u, v), o.y * (1 - c / (depth / 2))))        // chamfer top = the top's edge
            cham.append(SIMD3(o.x, bodyTop - c, o.y))                                                         // chamfer bottom = the wall's top
            wall.append(SIMD3(o.x, bodyTop - c, o.y)); wall.append(SIMD3(o.x, bodyTop - thick, o.y))
            under.append(SIMD3(o.x, bodyTop - thick, o.y))
        }
        under.append(SIMD3(0, bodyTop - thick, 0))
        for q in 0..<m {
            let q1 = (q + 1) % m
            ci += [UInt32(2 * q), UInt32(2 * q + 1), UInt32(2 * q1 + 1), UInt32(2 * q), UInt32(2 * q1 + 1), UInt32(2 * q1)]
            wi += [UInt32(2 * q), UInt32(2 * q + 1), UInt32(2 * q1 + 1), UInt32(2 * q), UInt32(2 * q1 + 1), UInt32(2 * q1)]
            ui += [UInt32(m), UInt32(q), UInt32(q1)]
        }
        func orient(_ p: [SIMD3<Float>], _ ix: [UInt32], downFacing: Bool) -> [UInt32] {
            var out = ix
            for t in stride(from: 0, to: out.count, by: 3) {
                let a = p[Int(out[t])], b2 = p[Int(out[t + 1])], c2 = p[Int(out[t + 2])]
                let nn = simd_cross(b2 - a, c2 - a), mid = (a + b2 + c2) / 3
                let ok = downFacing ? nn.y < 0 : simd_dot(nn, SIMD3(mid.x, 0, mid.z)) > 0
                if !ok { out.swapAt(t + 1, t + 2) }
            }
            return out
        }
        mesh.addIndexed(positions: cham, indices: orient(cham, ci, downFacing: false), smoothNormals: nil, surface: surface, transform: matrix_identity_float4x4)
        mesh.addIndexed(positions: wall, indices: orient(wall, wi, downFacing: false), smoothNormals: nil, surface: surface, transform: matrix_identity_float4x4)
        mesh.addIndexed(positions: under, indices: orient(under, ui, downFacing: true), smoothNormals: nil, surface: surface, transform: matrix_identity_float4x4)
        let half = depth / 2
        mesh.adjust { v in v.normal.w = MaterialID.plank.rawValue + 0.4 * min(max(v.position.z / half, -1), 1) }
        let height: (Float, Float) -> Float = { x, z in
            let u = min(max(x / (w / 2), -1), 1), v = min(max(z / (depth / 2), -1), 1)
            return top + hgt(u, v)
        }
        return SawnBoard(mesh: mesh, height: height, outline: loop.map { outline(uv($0.0, $0.1).0, uv($0.0, $0.1).1) }, lift: liftAmt)
    }

    static func addStone(_ id: StoneID, scene: Scene, device: MTLDevice) {
        let p = id.position
        let from = id.approachFrom
        // Face the way the player arrives from: local +Z points toward the previous waypoint.
        let toward = SIMD2(from.x - p.x, from.z - p.z)
        let yaw = atan2(toward.x, toward.y)
        let model = translation(p) * rotationY(yaw)
        let basalt = Surface(color: SIMD3(0.30, 0.31, 0.34), roughness: 0.75, material: .dressed)

        // The plinth and the top block are plain dressed stone; the face is its own object (material 14) so only it carries the glyph glow.
        var body = MeshBuilder()
        body.chamferBox(size: SIMD3(1.12, 0.3, 0.7), chamfer: 0.05, surface: Surface(color: SIMD3(0.30, 0.31, 0.34), roughness: 0.75, material: .dressed), transform: translation(SIMD3(0.03, stoneHeight - 0.05, 0)) * rotationY(0.14))
        body.chamferBox(size: SIMD3(1.9, 0.25, 1.5), chamfer: 0.05, surface: Surface(color: SIMD3(0.40, 0.38, 0.35), roughness: 0.85, material: .dressed), transform: translation(SIMD3(0, 0.05, 0)))
        scene.add("stone_\(id.name)", mesh: body.build(device: device, label: "stone_\(id.name)"), uniforms: ObjectUniforms(model: model))

        // The face: the glyph (tide = three waves, wind = two diagonals, summit = a square) and the rank notches (1, 2 or 3 low on the
        // face = how near the sky this stone stands: with the journal's "each stone a little nearer the sky than the last" the order is
        // deduced, not read out) are carved by the shader (carve_glyph). Pulse and lit state drive the object's emissive strength.
        var face = MeshBuilder()
        face.chamferBox(size: SIMD3(1.3, stoneHeight, 0.85), chamfer: 0.06, surface: Surface(color: SIMD3(0.30, 0.31, 0.34), roughness: 0.75, material: .glyphStone),
                        transform: translation(SIMD3(0, stoneHeight / 2 - 0.1, 0)))
        scene.add("stone_\(id.name)_face", mesh: face.build(device: device, label: "stone_face"),
                  uniforms: ObjectUniforms(model: model, tint: SIMD4(1, 1, 1, Float(id.rawValue)), emissive: SIMD4(id.color, 0.3)))

        // Hovering capstone.
        var cap = MeshBuilder()
        cap.icosphere(subdivisions: 0, radius: { _ in 1 }, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.3),
                      transform: scaling(SIMD3(0.26, 0.38, 0.26)))
        scene.add("cap_\(id.name)", mesh: cap.build(device: device, label: "cap"),
                  uniforms: ObjectUniforms(model: translation(capstoneBase(id)), tint: SIMD4(id.color, 1), emissive: SIMD4(id.color, 0.5)))

        scene.colliders.addCylinder(center: SIMD2(p.x, p.z), radius: 0.85, minY: p.y - 1, maxY: p.y + stoneHeight)
    }

    /// The glyph for a stone, as thin raised bars/squares facing +Z at (0, y, z). Reused on the Glass Wood's murals so the
    /// player meets the same symbols in both worlds: tide = three waves, wind = two diagonals, stone = a solid square.
    static func glyphMesh(_ id: StoneID, z: Float, y: Float, scale: Float = 1) -> MeshBuilder {
        var g = MeshBuilder()
        let glow = Surface(color: SIMD3(1, 1, 1), roughness: 0.4)
        switch id {
        case .tide:
            let offsets: [Float] = [-0.07, 0.07, -0.07]
            for (i, dx) in offsets.enumerated() {
                g.box(size: SIMD3(0.62, 0.07, 0.03) * scale, surface: glow, transform: translation(SIMD3(dx, y + (0.24 - Float(i) * 0.24) * scale, z)))
            }
        case .wind:
            for dx: Float in [-0.17, 0.17] {
                g.box(size: SIMD3(0.07, 0.72, 0.03) * scale, surface: glow, transform: translation(SIMD3(dx * scale, y, z)) * rotationZ(0.6))
            }
        case .summit:
            g.box(size: SIMD3(0.48, 0.48, 0.03) * scale, surface: glow, transform: translation(SIMD3(0, y, z)))
        }
        return g
    }
}
