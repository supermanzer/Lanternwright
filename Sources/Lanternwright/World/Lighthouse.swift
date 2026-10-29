import Metal
import simd

/// The lighthouse (R03 / T57.3): a round, tapered, entasis-curved tower on a stepped granite plinth with a granite lower shaft, a
/// lime-rendered upper shaft in white and red bands separated by string courses, an arched stone doorway with a planked iron-strapped
/// door, splayed windows, a corbelled gallery with an iron balustrade, and a glazed lantern room under a verdigris copper roof.
/// Detail follows reach: the plinth, door and lower shaft (reachable at 1-2 m) carry the most geometry and the best materials; the
/// shaft reads at 5-30 m; the gallery and lantern are silhouette detail seen from the summit path.
///
/// Everything is built in the tower's local frame (origin on the axis at ground level; the door faces +Z, toward the approaching
/// player) and drawn as one mesh at `Layout.lighthouse`. Pattern materials use that origin as the axis (see Shaders/Materials.swift).
/// The lens, the lantern glass, the beams and the puzzle hooks (`lighthouse_lens`, `lighthouse_glass`, `Landmarks.lensPosition`)
/// are unchanged: the lens still floats at y = 26.9 inside the lantern room.
enum Lighthouse {
    static let baseY: Float = 0.9                    // top of the plinth = where the shaft begins
    static let topY: Float = 24.6                    // under the gallery
    static let segments = 48
    /// The solid core for collision: the tower wall (4.2 m at the base) plus the door surround that stands 0.4 m proud. The player's own
    /// radius is added by the collider, so the feet stop about 0.8 m from the door itself and the plinth steps are all within reach.
    static let colliderRadius: Float = 4.65

    /// Outer radius of the shaft at height y: the old taper (4.2 m to 2.8 m) plus a gentle entasis (the shaft swells slightly).
    static func wallR(_ y: Float) -> Float {
        let t = min(max((y - baseY) / (topY - baseY), 0), 1)
        return 4.2 - 1.4 * t + 0.07 * sin(.pi * t)
    }

    /// The door leaf's hinge, in the tower's local frame: its left edge (x = -0.55, the leaf is 1.1 m wide), on the line through the door's face at wallR(2.0) + 0.02.
    static var doorHinge: SIMD3<Float> { SIMD3(-0.55, baseY, wallR(2.0) + 0.02) }
    /// The model matrix of `lh_door_leaf` with the door swung `angle` radians about its hinge (0 = closed; positive swings the free edge outward, toward +z, the way the door opens to the player).
    static func doorLeafModel(open angle: Float) -> float4x4 {
        translation(Layout.lighthouse) * translation(doorHinge) * rotationY(-angle) * translation(-doorHinge)
    }

    /// The five windows' heights (local y) and angles (atan2(z, x), 0 = east, pi/2 = south): the stone frames outside, and the light shafts inside (S03.5b).
    static let windowYs: [Float] = [6.2, 10.4, 14.6, 18.2, 21.8]
    static func windowAngle(_ i: Int) -> Float { .pi / 2 + Float(i) * 1.9 + 0.5 }

    static func build(into scene: Scene, device: MTLDevice) {
        let granite = Surface(color: SIMD3(0.47, 0.44, 0.41), roughness: 0.9, material: .masonry)
        let graniteDark = Surface(color: SIMD3(0.36, 0.34, 0.32), roughness: 0.9, material: .masonry)
        let white = Surface(color: SIMD3(0.60, 0.575, 0.53), roughness: 0.88, material: .paint)
        let red = Surface(color: SIMD3(0.42, 0.085, 0.06), roughness: 0.88, material: .paint)
        let iron = Surface(color: SIMD3(0.05, 0.055, 0.07), roughness: 0.5, material: .iron)
        let wood = Surface(color: SIMD3(0.20, 0.12, 0.06), roughness: 0.8, material: .wood)
        let copper = Surface(color: SIMD3(0.5, 0.4, 0.3), roughness: 0.5, material: .copper)
        let glassDark = Surface(color: SIMD3(0.015, 0.02, 0.03), roughness: 0.08)
        var b = MeshBuilder()
        var leaf = MeshBuilder()          // S03.6: the planked door (planks, straps, studs, hinge pins, escutcheon, keyhole, ring) is its own scene item, `lh_door_leaf`, so it can swing open
        let seg = segments

        // ---- Plinth: three granite steps sunk into the ground (the base is buried, so the terrain pad shows no ring).
        b.lathe(profile: [SIMD2(5.40, -0.7), SIMD2(5.40, 0.30), SIMD2(5.40, 0.30), SIMD2(4.95, 0.30), SIMD2(4.95, 0.60),
                          SIMD2(4.65, 0.60), SIMD2(4.65, baseY), SIMD2(wallR(baseY), baseY)], segments: seg, surface: granite)

        // ---- Shaft: granite to 3.6 m, then render. Sampled every 0.6 m along the entasis curve, split at the string courses.
        func shaft(from y0: Float, to y1: Float, _ s: Surface) {
            var pts: [SIMD2<Float>] = []
            var y = y0
            while y < y1 - 1e-4 { pts.append(SIMD2(wallR(y), y)); y += 0.6 }
            pts.append(SIMD2(wallR(y1), y1))
            b.lathe(profile: pts, segments: seg, surface: s)
        }
        /// A projecting band: a cornice with a sloped top and a chamfered underside, at height y.
        func stringCourse(_ y: Float, out: Float = 0.16, _ s: Surface) {
            let r = wallR(y)
            b.lathe(profile: [SIMD2(r - 0.02, y - 0.10), SIMD2(r + out * 0.55, y - 0.10), SIMD2(r + out, y - 0.02),
                              SIMD2(r + out, y + 0.08), SIMD2(r + out * 0.4, y + 0.16), SIMD2(r - 0.02, y + 0.16)], segments: seg, surface: s)
        }
        let bands: [(y0: Float, y1: Float, s: Surface)] = [(3.76, 8.0, white), (8.16, 13.0, red), (13.16, 20.0, white), (20.16, 24.6, red)]
        // S03.6: the shaft's lower granite ring has a real DOORWAY: the two segments of the 48-segment ring that face south (15 degrees, 1.07 m at the outside) are left out from the plinth to the
        // lintel at baseY + 2.4, with radial jambs and a lintel soffit joining the outer face to the inside (`LighthouseInterior.innerR`). The planked leaf (`lh_door_leaf`) and the arch stones
        // cover it from outside, so the closed tower looks as before; with the leaf swung or hidden the room inside is there to see.
        func shaftWithDoor() {
            let n = seg
            let omit: Set<Int> = [n / 4 - 1, n / 4]                                   // the quads either side of the south axis (angle pi/2 is index n / 4)
            let ys: [Float] = (0...4).map { baseY + 0.6 * Float($0) }                 // 0.9 ... 3.3
            for k in 0..<4 {
                let p0 = SIMD2(wallR(ys[k]), ys[k]), p1 = SIMD2(wallR(ys[k + 1]), ys[k + 1])
                let d = p1 - p0
                let n2 = simd_normalize(SIMD2(d.y, -d.x))
                var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
                for pr in [p0, p1] { for i in 0..<n { let a = Float(i) / Float(n) * 2 * .pi, c = cos(a), sn = sin(a); pos.append(SIMD3(pr.x * c, pr.y, pr.x * sn)); nrm.append(SIMD3(n2.x * c, n2.y, n2.x * sn)) } }
                for i in 0..<n where !omit.contains(i) { let j = (i + 1) % n; idx.append(contentsOf: [UInt32(i), UInt32(n + i), UInt32(n + j), UInt32(i), UInt32(n + j), UInt32(j)]) }
                b.addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: granite, transform: matrix_identity_float4x4)
            }
            // Jambs: a radial plane at each edge of the gap, outer face to inner face, facing into the doorway.
            let aW = Float(n / 4 - 1) / Float(n) * 2 * .pi, aE = Float(n / 4 + 1) / Float(n) * 2 * .pi     // the gap's two edges (angle of +x east to +z south)
            for (a, side) in [(aW, Float(1)), (aE, Float(-1))] {
                let c = cos(a), sn = sin(a)
                let toward = SIMD3<Float>(-sn, 0, c) * side                                   // into the doorway
                var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
                for y in [ys[0], ys[4]] { for r in [LighthouseInterior.innerR(y), wallR(y)] { pos.append(SIMD3(r * c, y, r * sn)); nrm.append(toward) } }
                // pos: 0 = inner/low, 1 = outer/low, 2 = inner/high, 3 = outer/high
                let wind: [UInt32] = side > 0 ? [0, 1, 3, 0, 3, 2] : [0, 3, 1, 0, 2, 3]
                idx.append(contentsOf: wind)
                b.addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: granite, transform: matrix_identity_float4x4)
            }
            // The lintel's soffit: the underside between the jambs at the top of the opening.
            var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = []
            for a in [aW, aE] { for r in [LighthouseInterior.innerR(ys[4]), wallR(ys[4])] { pos.append(SIMD3(r * cos(a), ys[4], r * sin(a))); nrm.append(SIMD3(0, -1, 0)) } }
            // pos: 0 = W inner, 1 = W outer, 2 = E inner, 3 = E outer
            b.addIndexed(positions: pos, indices: [0, 3, 2, 0, 1, 3], smoothNormals: nrm, surface: granite, transform: matrix_identity_float4x4)
        }
        shaftWithDoor()
        shaft(from: baseY + 2.4, to: 3.6, granite)
        stringCourse(3.68, out: 0.20, granite)
        for band in bands { shaft(from: band.y0, to: band.y1, band.s) }
        for y: Float in [8.08, 13.08, 20.08] { stringCourse(y, out: 0.12, granite) }

        // ---- Door: a real arch (quoins, tapered voussoirs, keystone, hood) of dressed stone, the planked door standing back inside it,
        // iron straps, studs and a ring handle on an escutcheon, a worn threshold and four steps up from the ground.
        let rd = wallR(2.0)
        let doorW: Float = 1.1, doorH: Float = 2.4
        let dressed = Surface(color: SIMD3(0.47, 0.44, 0.41), roughness: 0.9, material: .dressed)
        let dressedDark = Surface(color: SIMD3(0.36, 0.34, 0.32), roughness: 0.9, material: .dressed)
        b.arch(width: doorW + 0.06, height: doorH + 0.03, depth: 0.7, voussoirs: 11, blockHeight: 0.40, surface: dressed,
               transform: translation(SIMD3(0, baseY, rd + 0.05)))
        let spring = doorH - doorW / 2
        leaf.box(size: SIMD3(doorW + 0.04, spring, 0.12), surface: wood, transform: translation(SIMD3(0, baseY + spring / 2, rd + 0.02)))
        leaf.cylinder(radiusTop: doorW / 2 + 0.02, radiusBottom: doorW / 2 + 0.02, height: 0.12, segments: 24, smooth: true, surface: wood,
                   transform: translation(SIMD3(0, baseY + spring, rd - 0.04)) * rotationX(.pi / 2) * translation(SIMD3(0, -0.12, 0)))
        for yStrap: Float in [0.35, 1.05, 1.75] {
            leaf.box(size: SIMD3(doorW + 0.06, 0.13, 0.03), surface: iron, transform: translation(SIMD3(0, baseY + yStrap, rd + 0.095)))
            for sx: Float in [-0.42, -0.21, 0, 0.21, 0.42] {
                leaf.sphere(radius: 0.028, segments: 8, surface: iron, transform: translation(SIMD3(sx, baseY + yStrap, rd + 0.115)))
            }
            for hs: Float in [-1, 1] {
                leaf.cylinder(radiusTop: 0.035, radiusBottom: 0.035, height: 0.16, segments: 8, smooth: true, surface: iron,
                           transform: translation(SIMD3(hs * (doorW / 2 + 0.03), baseY + yStrap - 0.08, rd + 0.09)))
            }
        }
        leaf.cylinder(radiusTop: 0.095, radiusBottom: 0.095, height: 0.022, segments: 20, smooth: true, surface: iron,
                   transform: translation(SIMD3(0.3, baseY + 0.95, rd + 0.085)) * rotationX(.pi / 2))                                    // escutcheon plate
        leaf.chamferBox(size: SIMD3(0.05, 0.12, 0.02), chamfer: 0.006, surface: iron, transform: translation(SIMD3(0.3, baseY + 0.72, rd + 0.088)))              // a keyhole plate
        leaf.cylinder(radiusTop: 0.012, radiusBottom: 0.012, height: 0.01, segments: 8, smooth: true, surface: Surface(color: SIMD3(0.01, 0.01, 0.01), roughness: 1), transform: translation(SIMD3(0.3, baseY + 0.74, rd + 0.099)) * rotationX(.pi / 2))
        leaf.torus(major: 0.085, minor: 0.012, segments: 24, sides: 8, surface: iron,
                transform: translation(SIMD3(0.3, baseY + 0.95, rd + 0.125)) * rotationX(.pi / 2))                                       // ring handle
        b.chamferBox(size: SIMD3(1.7, 0.14, 0.78), chamfer: 0.025, surface: dressedDark, transform: translation(SIMD3(0, baseY - 0.07, rd + 0.42)))   // worn threshold
        // Four approach steps (their tops are also registered as walkable platforms, see below).
        var stepDefs: [(w: Float, z: Float, top: Float)] = []
        for i in 0..<4 {
            let back: Float = Float(3 - i)
            let w: Float = 1.9 - 0.12 * back
            let z: Float = rd + 0.45 + 0.45 * back + 0.25
            let top: Float = 0.9 * Float(i + 1) / 4
            stepDefs.append((w: w, z: z, top: top))
        }
        for (i, st) in stepDefs.enumerated() {
            b.chamferBox(size: SIMD3(st.w, st.top, 0.5), chamfer: 0.03, surface: i == 3 ? dressedDark : dressed, transform: translation(SIMD3(0, st.top / 2, st.z - 0.25)))
            scene.platforms.append(Scene.Platform(center: SIMD2(Layout.lighthouse.x, Layout.lighthouse.z + st.z - 0.25), halfSize: SIMD2(st.w / 2 - 0.02, 0.25), top: Layout.lighthouse.y + st.top))
        }
        // The plinth steps are discs: stepping up from the ground, the tread heights 0.3 / 0.6 / 0.9 m.
        for (r, top) in [(Float(5.40), Float(0.30)), (4.95, 0.60), (4.65, 0.90)] {
            scene.platforms.append(Scene.Platform(center: SIMD2(Layout.lighthouse.x, Layout.lighthouse.z), radius: r - 0.03, top: Layout.lighthouse.y + top))
        }

        // ---- Windows (splayed reveals): a stone frame standing proud, a dark recessed pane behind iron bars, a sill with a drip groove.
        let windowYs = Lighthouse.windowYs
        for (i, wy) in windowYs.enumerated() {
            let ang = Lighthouse.windowAngle(i)
            let rw = wallR(wy)
            let place = translation(SIMD3(cos(ang) * rw, wy, sin(ang) * rw)) * rotationY(.pi / 2 - ang)
            b.bevelBox(size: SIMD3(0.14, 1.15, 0.36), bevel: 0.02, surface: granite, transform: place * translation(SIMD3(-0.4, 0, 0.08)))
            b.bevelBox(size: SIMD3(0.14, 1.15, 0.36), bevel: 0.02, surface: granite, transform: place * translation(SIMD3(0.4, 0, 0.08)))
            b.bevelBox(size: SIMD3(1.02, 0.15, 0.40), bevel: 0.025, surface: granite, transform: place * translation(SIMD3(0, 0.62, 0.09)))      // lintel
            b.bevelBox(size: SIMD3(1.1, 0.12, 0.5), bevel: 0.02, surface: granite, transform: place * translation(SIMD3(0, -0.62, 0.14)))        // sill, projecting
            b.box(size: SIMD3(0.98, 0.025, 0.04), surface: graniteDark, transform: place * translation(SIMD3(0, -0.545, 0.34)))                  // drip groove
            b.box(size: SIMD3(0.66, 1.08, 0.05), surface: glassDark, transform: place * translation(SIMD3(0, 0, 0.03)))
            for bx: Float in [-0.17, 0.17] { b.box(size: SIMD3(0.025, 1.08, 0.04), surface: iron, transform: place * translation(SIMD3(bx, 0, 0.075))) }
            b.box(size: SIMD3(0.66, 0.025, 0.04), surface: iron, transform: place * translation(SIMD3(0, 0.1, 0.075)))
        }

        // ---- Gallery: a corbelled granite deck on 24 brackets, a cornice, an iron balustrade with posts and two rails.
        let rg = wallR(topY)
        b.lathe(profile: [SIMD2(rg - 0.02, 23.95), SIMD2(rg + 0.18, 23.95), SIMD2(rg + 0.18, 24.15), SIMD2(rg + 0.55, 24.45), SIMD2(3.88, 24.50),
                          SIMD2(3.88, 24.86), SIMD2(3.70, 24.92), SIMD2(2.62, 24.92)], segments: seg, surface: granite)
        for i in 0..<24 {
            let a = Float(i) / 24 * 2 * .pi
            b.bevelBox(size: SIMD3(0.22, 0.52, 0.62), bevel: 0.03, surface: granite,
                       transform: translation(SIMD3(cos(a) * (rg + 0.35), 24.2, sin(a) * (rg + 0.35))) * rotationY(.pi / 2 - a) * rotationX(-0.45))
        }
        let postR: Float = 3.72
        for i in 0..<36 {
            let a = Float(i) / 36 * 2 * .pi
            let big = i % 3 == 0
            b.cylinder(radiusTop: big ? 0.04 : 0.022, radiusBottom: big ? 0.05 : 0.026, height: 1.1, segments: 6, smooth: true, surface: iron,
                       transform: translation(SIMD3(postR * cos(a), 24.92, postR * sin(a))))
            if big { b.sphere(radius: 0.055, segments: 8, surface: iron, transform: translation(SIMD3(postR * cos(a), 26.06, postR * sin(a)))) }
        }
        b.torus(major: postR, minor: 0.032, segments: 72, sides: 8, surface: iron, transform: translation(SIMD3(0, 26.0, 0)))         // top rail
        b.torus(major: postR, minor: 0.022, segments: 72, sides: 6, surface: iron, transform: translation(SIMD3(0, 25.45, 0)))        // mid rail
        b.torus(major: postR, minor: 0.018, segments: 72, sides: 6, surface: iron, transform: translation(SIMD3(0, 25.12, 0)))        // toe rail
        // ---- Lantern room: an iron base, sixteen glazing bars, two transom rings, a head ring, glass behind (see lighthouse_glass).
        b.lathe(profile: [SIMD2(2.62, 24.92), SIMD2(2.62, 25.40), SIMD2(2.45, 25.47), SIMD2(2.25, 25.47)], segments: seg, surface: iron)
        for i in 0..<16 {
            let a = Float(i) / 16 * 2 * .pi
            b.cylinder(radiusTop: 0.032, radiusBottom: 0.04, height: 3.0, segments: 5, smooth: true, surface: iron,
                       transform: translation(SIMD3(2.16 * cos(a), 25.6, 2.16 * sin(a))))
        }
        for y: Float in [26.7, 27.7] { b.torus(major: 2.16, minor: 0.03, segments: 64, sides: 6, surface: iron, transform: translation(SIMD3(0, y, 0))) }
        b.torus(major: 2.2, minor: 0.07, segments: 64, sides: 8, surface: iron, transform: translation(SIMD3(0, 28.6, 0)))

        // ---- Copper roof: an ogee dome with twelve ribs, a ventilator cowl, a weathervane and a lightning rod.
        var roof: [SIMD2<Float>] = [SIMD2(2.62, 28.55), SIMD2(2.74, 28.62), SIMD2(2.66, 28.76)]
        for k in 1...10 {
            let t = Float(k) / 10
            roof.append(SIMD2(2.55 * (1 - pow(t, 1.35)) + 0.42 * (1 - t), 28.76 + 1.9 * t + 0.25 * sin(.pi * t)))
        }
        b.lathe(profile: roof, segments: seg, surface: copper)
        for i in 0..<12 {
            let a = Float(i) / 12 * 2 * .pi
            let pts: [SIMD3<Float>] = roof.dropFirst(2).map { SIMD3(($0.x + 0.025) * cos(a), $0.y + 0.012, ($0.x + 0.025) * sin(a)) }
            b.tube(points: pts, radii: [Float](repeating: 0.028, count: pts.count), sides: 5, caps: false, surface: copper)
        }
        let topPt = roof.last!
        b.lathe(profile: [SIMD2(0.45, topPt.y - 0.05), SIMD2(0.52, topPt.y + 0.12), SIMD2(0.38, topPt.y + 0.34), SIMD2(0.12, topPt.y + 0.46), SIMD2(0.0, topPt.y + 0.5)],
                segments: 24, surface: copper)
        b.tube(points: [SIMD3(0, topPt.y + 0.4, 0), SIMD3(0, topPt.y + 1.5, 0)], radii: [0.03, 0.02], sides: 6, surface: iron)           // spindle / rod
        b.tube(points: [SIMD3(0, topPt.y + 1.1, 0), SIMD3(0.55, topPt.y + 1.1, 0.1)], radii: [0.02, 0.015], sides: 5, surface: iron)       // vane arm
        b.box(size: SIMD3(0.22, 0.09, 0.012), surface: iron, transform: translation(SIMD3(0.62, topPt.y + 1.1, 0.12)) * rotationY(-0.18))   // arrow head
        b.box(size: SIMD3(0.18, 0.12, 0.012), surface: iron, transform: translation(SIMD3(-0.18, topPt.y + 1.1, -0.03)))                   // tail
        b.sphere(radius: 0.035, segments: 8, surface: iron, transform: translation(SIMD3(0, topPt.y + 1.52, 0)))

        scene.add("lighthouse", mesh: b.build(device: device, label: "lighthouse"), uniforms: ObjectUniforms(model: translation(Layout.lighthouse)))
        scene.add("lh_door_leaf", mesh: leaf.build(device: device, label: "lh_door_leaf"), uniforms: ObjectUniforms(model: doorLeafModel(open: 0)))
    }
}
