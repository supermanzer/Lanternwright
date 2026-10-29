import Metal
import simd
import Foundation

/// S03.5a: the inside of the lighthouse: one round room at the foot (the plinth's top is its floor), a spiral stair round an open well that climbs six turns to the lens room under
/// the lantern, the wall as a ring of colliders with the door as a gap, and the floors as a FEET-AWARE query.
///
/// Why a query of its own: `Scene.groundHeight(x:z:)` gives one height per spot, and a spiral stair stacks surfaces at the same spot (the next turn is 4 m above the last). The player is
/// asked `height(x:z:feetY:)` while the interior is open: the highest surface at that spot that is no more than a step above the feet. Everything is in the tower's frame around
/// `Layout.lighthouse`; nothing here touches `Scene` or the renderer except through scene items and colliders that `Game` adds when the door opens.
///
/// The stair is a helical ramp (slope about 0.47, under the walking limit 0.84) rather than discrete risers: the feet follow a smooth surface, the treads drawn on it are 16 cm steps
/// whose tops lie within 8 cm of it, which the eye spring hides. It hugs the inner wall (no outer edge to fall from), 1.3 m wide, with a rail along its inner edge.
struct LighthouseInterior {
    // MARK: Geometry (the tower's frame: y = 0 is the ground at the tower's foot; Lighthouse.baseY = 0.9 is the plinth's top and the room's floor)
    static let floorY = Lighthouse.baseY
    /// The lens room's floor: just above the gallery (the shaft ends at `topY`).
    static let lensFloorY = Lighthouse.topY + 0.2
    static let turns: Float = 6
    /// Where the stair starts (the angle `atan2(dz, dx)` of its foot) and ends (six turns later, the same angle). The door is at angle pi/2 (south, +Z); the foot is a quarter turn round, to the
    /// west, so that the stair's opening in the lens room's floor (the 195 degrees before the end angle) lies to the south and east and the floor is whole under the north window.
    static let startAngle: Float = .pi
    static var endAngle: Float { startAngle + 2 * .pi * turns }
    /// The stair hugs the wall as a band `stairWidth` wide round an open well; the well is never narrower than `wellMin` (at the top the shaft is only 2 m across). A low rail along the
    /// band's inner edge keeps the player out of the well and from walking under the low treads.
    static let stairWidth: Float = 1.3
    static let wellMin: Float = 0.8
    static func stairInner(_ y: Float) -> Float { max(innerR(y) - stairWidth, wellMin) }
    /// Treads at the foot without a rail: the way onto the stair from the room.
    static let openTreads = 3
    static let wallThickness: Float = 0.8
    /// The inside radius under the lantern: the lantern room's glass is 2.1 m round, so the lens room is too.
    static let minInner: Float = 2.1
    // The lens room (S03.7 builds in it; the space is reserved here and measured by SelfTestInterior): the lens stands in the middle of the floor with its ring round it (`ringOuter`), and the
    // north window (`portalAngle`: the seaward side, atan2(dz, dx) = -pi/2) is where the doorway of turned light opens, so the floor must reach it: the stair's opening is on the other side.
    /// The lens (about 0.7 m across) with a 0.2 m collar round it: nothing else stands inside this radius.
    static let ringOuter: Float = 0.9
    static let portalAngle: Float = -.pi / 2
    static let portalWidth: Float = 1.1
    /// How far the stair's last stretch is cut out of the lens room's floor (it rises through the hatch): the angle over which the stair rises from head height (2 m) to the floor, so it never
    /// passes under the floor.
    static let hatch: Float = 3.2
    static let treadsPerTurn = 25
    static let treadThickness: Float = 0.16
    /// The surface may be this far above the feet and still be stepped onto (the same limit as the player's own: `Player.maxStep`).
    static let reach: Float = 0.5

    /// The inside radius of the shaft at height y (the outside radius less the wall, never less than `minInner`): the wall is thick at the foot and thin under the lantern.
    static func innerR(_ y: Float) -> Float { max(Lighthouse.wallR(y) - wallThickness, minInner) }
    /// Rise of the stair per radian of angle.
    static var rate: Float { (lensFloorY - floorY) / (2 * .pi * turns) }
    static func stairY(_ phi: Float) -> Float { floorY + (phi - startAngle) * rate }

    /// The tower's axis on the ground (x, z) and the ground's height at its foot (world).
    let origin: SIMD2<Float>
    let baseY: Float
    init(origin: SIMD2<Float> = SIMD2(Layout.lighthouse.x, Layout.lighthouse.z), baseY: Float = Layout.lighthouse.y) { self.origin = origin; self.baseY = baseY }

    /// The height of the floor under (x, z) for feet at `feetY` (world), or nil when the spot is not inside the tower (the scene's own ground applies there).
    func height(x: Float, z: Float, feetY: Float) -> Float? { floor(x: x, z: z, feetY: feetY)?.y }

    /// What the foot is on inside the tower: stone flags in the ground room, wood on the stair's treads and the lens room's boards (the footstep voice's surface).
    func surface(x: Float, z: Float, feetY: Float) -> SurfaceKind? { floor(x: x, z: z, feetY: feetY).map { $0.wood ? .wood : .stone } }

    /// The floor under (x, z): its height (world) and whether it is boards.
    func floor(x: Float, z: Float, feetY: Float) -> (y: Float, wood: Bool)? {
        let dx = x - origin.x, dz = z - origin.y
        let r = (dx * dx + dz * dz).squareRoot()
        guard r <= LighthouseInterior.innerR(LighthouseInterior.floorY) else { return nil }
        let local = feetY - baseY
        var best = LighthouseInterior.floorY                                          // the ground room's floor, wherever you are inside
        var wood = false
        let limit = local + LighthouseInterior.reach
        let a = atan2(dz, dx)
        // The stair: each turn's surface at this angle, if the spot is on the treads' band at that height.
        var u = (a - LighthouseInterior.startAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if u < 0 { u += 2 * .pi }
        for k in 0..<Int(LighthouseInterior.turns) {
            let phi = LighthouseInterior.startAngle + u + 2 * .pi * Float(k)
            let h = LighthouseInterior.stairY(phi)
            guard h <= LighthouseInterior.lensFloorY + 1e-4 else { continue }
            if r >= LighthouseInterior.stairInner(h) && r <= LighthouseInterior.innerR(h) && h <= limit && h >= best { best = h; wood = true }
        }
        // The lens room's floor, except where the stair's last stretch comes up through it.
        if r <= LighthouseInterior.innerR(LighthouseInterior.lensFloorY) && LighthouseInterior.lensFloorY <= limit {
            var ua = (a - (LighthouseInterior.endAngle - LighthouseInterior.hatch)).truncatingRemainder(dividingBy: 2 * .pi)
            if ua < 0 { ua += 2 * .pi }
            let inHatch = ua <= LighthouseInterior.hatch && r >= LighthouseInterior.stairInner(LighthouseInterior.lensFloorY)
            if !inHatch { best = LighthouseInterior.lensFloorY; wood = true }
        }
        return (baseY + best, wood)
    }

    // MARK: Colliders

    /// The ring of cylinders that replaces the tower's solid core while the door is open: the wall from `innerR` outward (in bands of 3 m, each as thin as the shaft is at the band's top),
    /// the stair's inner rail, and a door gap at the foot (the gap is 1.3 m clear between cylinders, for a player 0.7 m across and a door 1.1 m wide). Bands overlap the floor by one metre so nothing leaks.
    func wallColliders() -> [CylinderCollider] {
        var out: [CylinderCollider] = []
        let cylR: Float = 0.55
        var y0 = LighthouseInterior.floorY - 1
        while y0 < LighthouseInterior.lensFloorY + 4 {
            let y1 = y0 + 3
            let inner = LighthouseInterior.innerR(min(y1, Lighthouse.topY))
            let ringR = inner + cylR
            let n = Int((2 * .pi * ringR / 0.55).rounded(.up))
            for i in 0..<n {
                let a = 2 * .pi * Float(i) / Float(n)
                let c = SIMD2(cos(a), sin(a)) * ringR
                if y0 < LighthouseInterior.floorY + 3.2 && c.y > 0 && abs(c.x) < 1.2 { continue }      // the door, on the south side (+Z)
                out.append(CylinderCollider(center: origin + c, radius: cylR, minY: baseY + y0, maxY: baseY + y1 + 0.2))
            }
            y0 = y1
        }
        // The rail along the stair's inner edge: one post per tread, each spanning from a little below the tread to a metre above it. A body on another turn (4 m away) never overlaps it;
        // one on the floor under the low treads does, which is the point (no walking under a stair you would hit your head on). The first few treads have none: the way on.
        let total = LighthouseInterior.treadsPerTurn * Int(LighthouseInterior.turns)
        let dphi = 2 * Float.pi / Float(LighthouseInterior.treadsPerTurn)
        for i in LighthouseInterior.openTreads..<total {
            let phi = LighthouseInterior.startAngle + (Float(i) + 0.5) * dphi
            let h = LighthouseInterior.stairY(phi)
            let e = LighthouseInterior.stairInner(h) - 0.05
            out.append(CylinderCollider(center: origin + SIMD2(cos(phi), sin(phi)) * e, radius: 0.14, minY: baseY + h - 0.3, maxY: baseY + h + 1.1))
        }
        // The hatch's far edge, on the lens room's floor: a drop of two metres onto the stair below if you walk off it. Posts across the opening's width, from the floor up (a player on the
        // stair below is at the ramp's height there, 2 m lower, and passes under them).
        let edge = LighthouseInterior.endAngle - LighthouseInterior.hatch
        var rr = LighthouseInterior.stairInner(LighthouseInterior.lensFloorY)
        while rr <= LighthouseInterior.innerR(LighthouseInterior.lensFloorY) + 0.05 {
            out.append(CylinderCollider(center: origin + SIMD2(cos(edge), sin(edge)) * rr, radius: 0.14, minY: baseY + LighthouseInterior.lensFloorY - 0.05, maxY: baseY + LighthouseInterior.lensFloorY + 1.1))
            rr += 0.3
        }
        // The lens's footprint in the lens room (a pedestal and collar to `ringOuter`, less the player's own radius), and the workshop bench (two round ends).
        out.append(CylinderCollider(center: origin, radius: LighthouseInterior.ringOuter - Player.radius, minY: baseY + LighthouseInterior.lensFloorY - 0.05, maxY: baseY + LighthouseInterior.lensFloorY + 1.5))
        for end in LighthouseInterior.benchEnds {
            out.append(CylinderCollider(center: origin + end, radius: 0.3, minY: baseY + LighthouseInterior.floorY - 0.05, maxY: baseY + LighthouseInterior.floorY + 1.0))
        }
        return out
    }

    // MARK: Fittings

    static let fittingsName = "lh_interior_fittings", ringName = "lh_lens_ring"
    /// The workshop: on the south-east side of the ground room (angle `workshopAngle`, `atan2(dz, dx)`), where the stair's first turn is 2.3 m or more above the floor (it is only 1 m up at the
    /// north wall, which is why nothing stands there): the bench runs along the wall at `benchRadius`, 1.4 m long, its two ends are colliders (tower frame, x/z).
    static let workshopAngle: Float = 0.85
    static let benchRadius: Float = 2.45
    static var benchCentre: SIMD2<Float> { SIMD2(cos(workshopAngle), sin(workshopAngle)) * benchRadius }
    /// The direction along the wall at the workshop (the bench's long axis).
    static var benchTangent: SIMD2<Float> { SIMD2(-sin(workshopAngle), cos(workshopAngle)) }
    static var benchEnds: [SIMD2<Float>] { [benchCentre - benchTangent * 0.45, benchCentre + benchTangent * 0.45] }
    static let benchTopY: Float = 0.91                       // above the room's floor
    /// The lens ring's height above the lens room's floor and its radii (it turns in S03.7: its own item `ringName`, about the tower's axis).
    static let ringHeight: Float = 1.05, ringMajor: Float = 0.74, ringMinor: Float = 0.06

    // MARK: Meshes (hidden until the door opens: see Game.syncInterior)

    /// S03.5b: the two warm lamps (world positions, on the tower's axis: one over the ground room's floor, one over the lens room's floor) and their strength; the lit shader reads them
    /// for items flagged as interior (`ObjectUniforms.lod.z`).
    static var lampGround: SIMD3<Float> { Layout.lighthouse + SIMD3(0, floorY + 2.4, 0) }
    static var lampLens: SIMD3<Float> { Layout.lighthouse + SIMD3(0, lensFloorY + 1.7, 0) }
    static let lampPower: Float = 0.85
    static let wallName = "lh_interior_wall", stairName = "lh_interior_stair"
    /// Debug: `LW_LIGHTHOUSE_OPEN=1` draws the inside from the start, so a frame tool can show it without opening the door (the game keeps it hidden until `door_open`).
    static let shownForTools = ProcessInfo.processInfo.environment["LW_LIGHTHOUSE_OPEN"] == "1"

    static func build(into scene: Scene, device: MTLDevice) {
        let lime = Surface(color: SIMD3(0.62, 0.58, 0.50), roughness: 0.95, material: .masonry)
        let stone = Surface(color: SIMD3(0.40, 0.38, 0.35), roughness: 0.9, material: .masonry)
        let wood = Surface(color: SIMD3(0.30, 0.19, 0.10), roughness: 0.8, material: .wood)
        let woodDark = Surface(color: SIMD3(0.22, 0.13, 0.07), roughness: 0.85, material: .wood)
        let place = translation(Layout.lighthouse)

        // The wall, seen from inside: the inner face of the shaft as a lathe wound top to bottom (so its normals face the room), a floor disc and the lens room's floor.
        var shell = MeshBuilder()
        var profile: [SIMD2<Float>] = []
        var y = Lighthouse.topY
        while y > floorY {
            profile.append(SIMD2(innerR(y), y)); y -= 3
        }
        profile.append(SIMD2(innerR(floorY), floorY))
        shell.lathe(profile: profile, segments: 48, smooth: true, surface: lime, transform: place)
        // Flags on the ground room's floor.
        shell.cylinder(radiusTop: innerR(floorY), radiusBottom: innerR(floorY), height: 0.02, segments: 48, smooth: false, surface: stone, transform: place * translation(SIMD3(0, floorY - 0.01, 0)))
        // The lens room's floor: a disc less the hatch the stair comes up through, in six sectors (a disc over the well and the part outside the hatch).
        let sector = (2 * Float.pi - hatch) / 6
        for i in 0..<6 {
            let a0 = endAngle + Float(i) * sector, a1 = a0 + sector
            shell.ringBlock(centre: .zero, a0: -a1, a1: -a0, r0: 0.01, r1: innerR(lensFloorY), z0: lensFloorY - 0.25, z1: lensFloorY, surface: woodDark,
                            transform: place * rotationX(-.pi / 2))
        }
        scene.add(wallName, mesh: shell.build(device: device, label: "lighthouse interior wall"), uniforms: ObjectUniforms(model: matrix_identity_float4x4, lod: SIMD4(0, 0, 1, 0)), hidden: !shownForTools)

        // The stair: the treads (annular sectors, 16 cm thick, their tops on the ramp at the middle of each) and the rail along their inner edge.
        var stair = MeshBuilder()
        let total = treadsPerTurn * Int(turns)
        let dphi = 2 * .pi / Float(treadsPerTurn)
        for i in 0..<total {
            let p0 = startAngle + Float(i) * dphi, p1 = p0 + dphi
            let top = stairY((p0 + p1) / 2)
            let outer = innerR(top) - 0.02
            stair.ringBlock(centre: .zero, a0: -p1, a1: -p0, r0: stairInner(top), r1: outer, z0: top - treadThickness, z1: top, surface: i % 2 == 0 ? wood : woodDark,
                            transform: place * rotationX(-.pi / 2))
        }
        scene.add(stairName, mesh: stair.build(device: device, label: "lighthouse interior stair"), uniforms: ObjectUniforms(model: matrix_identity_float4x4, lod: SIMD4(0, 0, 1, 0)), hidden: !shownForTools)

        // The fittings: the lens's pedestal and collar, the handrail with its posts along the stair's inner edge, and Ilse's workshop (a bench, a stool, three rule-plates, a tuning fork on its
        // hook, charts pinned to the wall). Plain boxes and tubes: nothing glows, nothing is a marker.
        let iron = Surface(color: SIMD3(0.05, 0.055, 0.07), roughness: 0.5, material: .iron)
        let brass = Surface(color: SIMD3(0.55, 0.42, 0.18), roughness: 0.35, material: .paleMetal)
        let paper = Surface(color: SIMD3(0.85, 0.80, 0.66), roughness: 0.9, material: .paper)
        var fit = MeshBuilder()
        // The lens's pedestal and collar (the lens itself, a sphere 2.1 m above the floor, is `lighthouse_lens`).
        fit.cylinder(radiusTop: 0.16, radiusBottom: 0.16, height: 26.1 - lensFloorY, segments: 16, smooth: true, surface: brass, transform: place * translation(SIMD3(0, lensFloorY, 0)))
        fit.cylinder(radiusTop: 0.5, radiusBottom: 0.55, height: 0.35, segments: 24, smooth: true, surface: stone, transform: place * translation(SIMD3(0, lensFloorY, 0)))
        // The handrail: a tube along the inner edge a metre above the treads, and a post at every third tread.
        var railPoints: [SIMD3<Float>] = [], railRadii: [Float] = []
        for i in openTreads...total {
            let phi = startAngle + Float(i) * dphi
            let h = stairY(phi), e = stairInner(h) - 0.05
            railPoints.append(SIMD3(cos(phi) * e, h + 0.95, sin(phi) * e)); railRadii.append(0.025)
            if i % 3 == 0 {
                fit.cylinder(radiusTop: 0.015, radiusBottom: 0.015, height: 0.95, segments: 6, smooth: true, surface: iron, transform: place * translation(SIMD3(cos(phi) * e, h, sin(phi) * e)))
            }
        }
        fit.tube(points: railPoints, radii: railRadii, sides: 6, caps: true, surface: iron, transform: place)
        // The workshop (on the south-east wall, clear of the low treads): the bench along the wall (a plank top on two trestles), a stool facing the room, three engraved rule-plates and a charts
        // on the wall above it, the tuning fork on its hook. Everything stays below the tread overhead (2.3 m up at its lowest here).
        let bc = benchCentre
        let aw = workshopAngle
        let benchFrame = place * translation(SIMD3(bc.x, 0, bc.y)) * rotationY(-(aw + .pi / 2))        // local x along the wall, local z toward the room's axis
        fit.box(size: SIMD3(1.4, 0.06, 0.6), surface: wood, transform: benchFrame * translation(SIMD3(0, floorY + benchTopY - 0.03, 0)))
        for sx: Float in [-0.55, 0.55] { fit.box(size: SIMD3(0.08, benchTopY - 0.06, 0.5), surface: woodDark, transform: benchFrame * translation(SIMD3(sx, floorY + (benchTopY - 0.06) / 2, 0))) }
        fit.cylinder(radiusTop: 0.2, radiusBottom: 0.22, height: 0.5, segments: 12, smooth: true, surface: woodDark, transform: benchFrame * translation(SIMD3(0.3, floorY, 0.95)))
        // On the wall: a frame at angle `a` and height y, its z axis toward the axis, standing off the wall by half its thickness.
        func onWall(_ a: Float, _ y: Float, depth: Float = 0.03) -> float4x4 {
            let r = innerR(floorY + y) - depth / 2
            return place * translation(SIMD3(cos(a) * r, floorY + y, sin(a) * r)) * rotationY(atan2(-cos(a), -sin(a)))
        }
        for (k, da) in ([-0.2, 0.0, 0.2] as [Float]).enumerated() {
            let f = onWall(aw + da, 1.55)
            fit.box(size: SIMD3(0.36, 0.5, 0.03), surface: k == 1 ? stone : woodDark, transform: f)                                  // a rule-plate
            fit.box(size: SIMD3(0.24, 0.016, 0.01), surface: iron, transform: f * translation(SIMD3(0, 0.07, 0.02)))                   // an engraved line
        }
        let hook = onWall(aw - 0.45, 1.95, depth: 0.04)
        fit.cylinder(radiusTop: 0.012, radiusBottom: 0.012, height: 0.1, segments: 6, smooth: true, surface: iron, transform: hook * rotationX(.pi / 2))
        let fork = onWall(aw - 0.45, 1.62, depth: 0.04)
        fit.box(size: SIMD3(0.012, 0.3, 0.012), surface: iron, transform: fork * translation(SIMD3(0, 0.0, 0.01)))
        for sx: Float in [-0.025, 0.025] { fit.box(size: SIMD3(0.01, 0.2, 0.01), surface: iron, transform: fork * translation(SIMD3(sx, 0.24, 0.01))) }
        fit.box(size: SIMD3(0.06, 0.012, 0.01), surface: iron, transform: fork * translation(SIMD3(0, 0.15, 0.01)))
        for (k, da) in ([0.38, 0.52] as [Float]).enumerated() {
            fit.box(size: SIMD3(0.3, 0.4, 0.006), surface: paper, transform: onWall(aw + da, 1.5 + 0.06 * Float(k), depth: 0.02) * rotationZ(0.05 * (k == 0 ? 1 : -1)))
        }
        scene.add(fittingsName, mesh: fit.build(device: device, label: "lighthouse interior fittings"), uniforms: ObjectUniforms(model: matrix_identity_float4x4, lod: SIMD4(0, 0, 1, 0)), hidden: !shownForTools)

        // The lens ring: its own item, brass, with a tick every 15 degrees, centred on the tower's axis at `ringHeight` above the lens room's floor (S03.7 turns it about that axis).
        var ring = MeshBuilder()
        ring.torus(major: ringMajor, minor: ringMinor, segments: 48, sides: 8, smooth: true, surface: brass, transform: translation(SIMD3(0, lensFloorY + ringHeight, 0)))
        for k in 0..<24 {
            let a = Float(k) * .pi / 12
            ring.box(size: SIMD3(0.025, 0.05, k % 6 == 0 ? 0.14 : 0.07), surface: iron, transform: translation(SIMD3(cos(a) * (ringMajor + 0.07), lensFloorY + ringHeight, sin(a) * (ringMajor + 0.07))) * rotationY(-a))
        }
        scene.add(ringName, mesh: ring.build(device: device, label: "lighthouse lens ring"), uniforms: ObjectUniforms(model: place), hidden: !shownForTools)
        if shownForTools { scene.update("lh_door_leaf") { $0.uniforms.model = Lighthouse.doorLeafModel(open: Game.doorSwing) } }        // tools: the door open too
    }
}
