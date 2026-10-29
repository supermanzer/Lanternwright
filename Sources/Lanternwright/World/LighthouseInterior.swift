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
    func height(x: Float, z: Float, feetY: Float) -> Float? {
        let dx = x - origin.x, dz = z - origin.y
        let r = (dx * dx + dz * dz).squareRoot()
        guard r <= LighthouseInterior.innerR(LighthouseInterior.floorY) else { return nil }
        let local = feetY - baseY
        var best = LighthouseInterior.floorY                                          // the ground room's floor, wherever you are inside
        let limit = local + LighthouseInterior.reach
        let a = atan2(dz, dx)
        // The stair: each turn's surface at this angle, if the spot is on the treads' band at that height.
        var u = (a - LighthouseInterior.startAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if u < 0 { u += 2 * .pi }
        for k in 0..<Int(LighthouseInterior.turns) {
            let phi = LighthouseInterior.startAngle + u + 2 * .pi * Float(k)
            let h = LighthouseInterior.stairY(phi)
            guard h <= LighthouseInterior.lensFloorY + 1e-4 else { continue }
            if r >= LighthouseInterior.stairInner(h) && r <= LighthouseInterior.innerR(h) && h <= limit { best = max(best, h) }
        }
        // The lens room's floor, except where the stair's last stretch comes up through it.
        if r <= LighthouseInterior.innerR(LighthouseInterior.lensFloorY) && LighthouseInterior.lensFloorY <= limit {
            var ua = (a - (LighthouseInterior.endAngle - LighthouseInterior.hatch)).truncatingRemainder(dividingBy: 2 * .pi)
            if ua < 0 { ua += 2 * .pi }
            let inHatch = ua <= LighthouseInterior.hatch && r >= LighthouseInterior.stairInner(LighthouseInterior.lensFloorY)
            if !inHatch { best = max(best, LighthouseInterior.lensFloorY) }
        }
        return baseY + best
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
        return out
    }

    // MARK: Meshes (hidden until the door opens: see Game.syncInterior)

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
        scene.add(wallName, mesh: shell.build(device: device, label: "lighthouse interior wall"), uniforms: ObjectUniforms(model: matrix_identity_float4x4), hidden: !shownForTools)

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
        scene.add(stairName, mesh: stair.build(device: device, label: "lighthouse interior stair"), uniforms: ObjectUniforms(model: matrix_identity_float4x4), hidden: !shownForTools)
    }
}
