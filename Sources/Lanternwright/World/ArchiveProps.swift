import Metal
import simd

/// S04.3: the Tide Archive's things. Everything is placed by the rules of `Placement` (upright props: the pivot at the highest ground under the footprint, the base carried straight down to the lowest), so nothing
/// floats on the terraces' slopes. Palette: wet slate, brass, dark oak and leather, pale glass; the lamps are light and cast no shadow (the same rule as everywhere).
///  - the STACKS: rows of oak shelving with ledgers on every shelf (books that look read, not pages: nothing here is collectable or readable);
///  - the DOME: a stone drum with a brass dome, its observing slit and a door;
///  - three SLUICE gates, one in each sluice room: stone piers and a wall, a gate plate that rises (its state is `sluiceGateModel`), and a brass wheel on a pedestal (`sluiceWheelModel`);
///  - the PRISM CHAMBER: a round roofless stone room with a brass pedestal and a glass prism, one white beam arriving and three coloured beams leaving it (tide, wind, stone);
///  - lanterns along the route, each with its own stone footing.
enum ArchiveProps {
    static let brass = Surface(color: SIMD3(0.64, 0.47, 0.20), roughness: 0.32, material: .paleMetal)
    static let slate = Surface(color: SIMD3(0.30, 0.33, 0.34), roughness: 0.9, material: .masonry)
    static let slateLight = Surface(color: SIMD3(0.42, 0.45, 0.45), roughness: 0.88, material: .dressed)
    static let oak = Surface(color: SIMD3(0.26, 0.17, 0.10), roughness: 0.8, material: .wood)
    static let iron = Surface(color: SIMD3(0.05, 0.055, 0.07), roughness: 0.5, material: .iron)

    static let stackUnits = 5, stackRows = 3
    static func sluiceName(_ k: Int) -> String { "ta_sluice_\(k)" }
    static func gateName(_ k: Int) -> String { "ti_sluice_\(k)" }                 // builder B drives it (emissive = open); `update` lifts it
    static func wheelName(_ k: Int) -> String { "ta_sluice_wheel_\(k)" }
    static let prismName = "ta_prism", beamInName = "ta_beam_in"
    static func beamOutName(_ k: Int) -> String { "ti_prism_beam_\(k)" }
    static func markName(_ k: Int) -> String { "ta_prism_mark_\(k)" }
    static let ringName = "ti_prism_ring_visual"
    /// The three dispersed beams (tide, wind, stone) and the direction they leave the prism in (radians about the vertical, spread either side of east).
    static let beamColours: [SIMD3<Float>] = [SIMD3(0.30, 0.70, 1.0), SIMD3(0.80, 0.95, 0.60), SIMD3(1.0, 0.58, 0.32)]
    static let beamSpread: Float = 0.20

    /// The Archive's moving state (per scene): how far each gate stands open (0...1, eased), whether its collider is in, and the clock of the last update.
    final class State {
        var gate = [Float](repeating: 0, count: 3)
        var gateCollider = [Bool](repeating: true, count: 3)                    // closed gates block the gap from the start (`addSluice` adds the colliders)
        var lastTime: Float?
    }
    static func gateCollider(_ k: Int) -> (center: SIMD2<Float>, radius: Float) { (SIMD2(ArchiveLayout.sluices[k].x, ArchiveLayout.sluices[k].z), 0.9) }

    /// Called every game tick (`Game.fixedStep`, one line) in the Archive: eases each gate toward its state (builder B's `ti_sluice_k` emissive = open), turns the wheel, takes the gate's collider out when
    /// it is open enough to walk through (and puts it back when the puzzle closes it again), and points the prism's three components by the ring.
    static func update(_ scene: Scene, time: Float, ringAngle: Float?, tableau: PageAuthor?) {
        let st = scene.archive
        let jump = st.lastTime == nil || abs(time - st.lastTime!) > 0.5 || time < st.lastTime!          // first update, a restore or a return to the Archive: the gates stand at their state at once
        let dt = min(max(time - (st.lastTime ?? time), 0), 0.25)
        st.lastTime = time
        for k in 0..<3 {
            guard let item = scene.items.first(where: { $0.name == gateName(k) }) else { continue }
            let open: Float = item.uniforms.emissive.w > 0.5 ? 1 : 0
            let step = jump ? 1 : dt * 0.4          // (B's `syncVisuals` writes a snapped pose every tick; this runs after it and the eased pose is what stays)
            st.gate[k] += min(max(open - st.gate[k], -step), step)
            let g = st.gate[k]
            scene.update(gateName(k)) { $0.uniforms.model = sluiceGateModel(k, open: g) }
            let blocking = g < 0.5, col = gateCollider(k)
            if blocking && !st.gateCollider[k] {
                scene.colliders.addCylinder(center: col.center, radius: col.radius, minY: ArchiveLayout.sluices[k].y - 1, maxY: ArchiveLayout.sluices[k].y + 4); st.gateCollider[k] = true
            } else if !blocking && st.gateCollider[k] {
                scene.colliders.cylinders.removeAll { $0.center == col.center && $0.radius == col.radius }; st.gateCollider[k] = false
            }
        }
        let g = ArchiveTerrain.gallery
        Player.galleryWater = (g.centre, g.half, ArchiveStory.waterLevel(scene, clock: time))
        updatePrism(scene, ringAngle: ringAngle ?? TideArchivePuzzle.initialRing)
        updateTableau(scene, shown: tableau, time: time)
    }

    /// S04.2 (decision on Q32, the eye under water in a sluice room): a player standing in a room the rising tide has made deeper than `floodDepth` m is walked out of it, away from the room's centre, at 1.6 m/s
    /// (never into a wall: the pit's slopes are walkable and the push stops when the water is shallow again). Rooms only: the sea elsewhere is no deeper than the route's lowest point allows.
    static let floodDepth: Float = 0.7
    static func floodPush(position p: SIMD3<Float>, sea: Float) -> SIMD2<Float>? {
        guard sea - p.y > floodDepth else { return nil }
        for s in ArchiveLayout.sluiceSites {
            let d = SIMD2(p.x, p.z) - s, r = simd_length(d)
            if r < ArchiveLayout.sluiceFlat + ArchiveLayout.sluiceBlend { return r < 0.05 ? SIMD2(0, 1) : d / r }
        }
        return nil
    }

    static func populate(_ scene: Scene, device: MTLDevice) {
        addStacks(scene, device: device)
        addDome(scene, device: device)
        for k in 0..<3 { addSluice(scene, device: device, k) }
        addPrismChamber(scene, device: device)
        addLanterns(scene, device: device)
        ArchiveStory.populate(scene, device: device)
    }

    // MARK: Placement helpers

    /// An upright footing of box shape under a prop at (x, z): the box reaches from the highest ground under `radius` down to the lowest (+ margin), recorded for the contact selftest.
    private static func footing(_ scene: Scene, x: Float, z: Float, radius: Float, yaw: Float, size: SIMD2<Float>, surface: Surface, kind: String) -> (transform: float4x4, mesh: MeshBuilder) {
        let up = Placement.upright(terrain: scene.terrain, x: x, z: z, radius: radius, yaw: yaw)
        var b = MeshBuilder()
        let drop = up.depth + 0.3
        b.chamferBox(size: SIMD3(size.x, drop + 0.12, size.y), chamfer: 0.025, surface: surface, transform: translation(SIMD3(0, 0.06 - drop / 2, 0)))
        scene.placed.append(Placement.record(kind: kind, mesh: b, transform: up.transform))
        return (up.transform, b)
    }

    // MARK: The stacks

    /// One shelving unit in its own frame (x along its width, z its depth toward the aisle, y up): oak frame, five shelves, a back panel, and the ledgers.
    private static func shelfUnit(seed: Int32, width: Float = 2.4, height: Float = 2.3, depth: Float = 0.55) -> MeshBuilder {
        var b = MeshBuilder()
        let n = Island.noise
        for sx: Float in [-1, 1] { b.box(size: SIMD3(0.07, height, depth), surface: oak, transform: translation(SIMD3(sx * (width / 2 - 0.035), height / 2, 0))) }
        b.box(size: SIMD3(width, height, 0.03), surface: oak, transform: translation(SIMD3(0, height / 2, -depth / 2 + 0.015)))                     // the back
        let shelves = 5
        let gap = (height - 0.12) / Float(shelves)
        for s in 0...shelves {
            let y = 0.06 + Float(s) * gap
            b.box(size: SIMD3(width, 0.04, depth), surface: oak, transform: translation(SIMD3(0, y, 0)))
        }
        let leathers: [SIMD3<Float>] = [SIMD3(0.30, 0.16, 0.10), SIMD3(0.18, 0.26, 0.20), SIMD3(0.36, 0.12, 0.10), SIMD3(0.22, 0.20, 0.30), SIMD3(0.40, 0.30, 0.16), SIMD3(0.14, 0.14, 0.15)]
        for s in 0..<shelves {
            let base = 0.06 + Float(s) * gap + 0.02
            var x = -width / 2 + 0.1
            var k: Int32 = 0
            while x < width / 2 - 0.12 {
                k += 1
                let u = { (c: Int32) in n.unit(seed &* 131 &+ Int32(s) &* 17 &+ k &* 7, c) }
                if u(1) < 0.07 { x += 0.12 + 0.2 * u(2); continue }                       // a gap where a ledger is out
                let w = 0.045 + 0.06 * u(3), h = gap * (0.62 + 0.3 * u(4)), d = depth * (0.62 + 0.28 * u(5))
                let lean = u(6) < 0.06 ? (u(7) - 0.5) * 0.35 : 0
                let col = leathers[Int(u(8) * 5.99)] * (0.8 + 0.4 * u(9))
                b.box(size: SIMD3(w, h, d), surface: Surface(color: col, roughness: 0.85, material: .paper),
                      transform: translation(SIMD3(x + w / 2, base + h / 2, 0.04)) * rotationZ(lean))
                x += w + 0.004 + (u(10) < 0.1 ? 0.03 : 0)
            }
        }
        return b
    }

    static func addStacks(_ scene: Scene, device: MTLDevice) {
        let c = ArchiveLayout.stacks
        var shelves = MeshBuilder()
        var unitIndex: Int32 = 0
        for row in 0..<stackRows {
            for u in 0..<stackUnits {
                unitIndex += 1
                let rowX: [Float] = [-9, -9.75, -12.8]                                      // rows 0 and 1 stand back to back; row 2 faces row 1 across a 2.3 m aisle; row 0 faces the open plaza
                let x = c.x + rowX[row], z = c.z + (Float(u) - Float(stackUnits - 1) / 2) * 2.6
                let yaw: Float = row == 1 ? -Float.pi / 2 : Float.pi / 2                    // row 1 faces west (toward row 2), rows 0 and 2 face east
                let f = footing(scene, x: x, z: z, radius: 1.3, yaw: yaw, size: SIMD2(2.55, 0.62), surface: slate, kind: "ta_shelf")
                shelves.append(f.mesh, transform: f.transform)
                shelves.append(shelfUnit(seed: unitIndex), transform: f.transform * translation(SIMD3(0, 0.3, 0)))
                scene.colliders.addCylinder(center: SIMD2(x, z - 0.9), radius: 0.7, minY: c.y - 4, maxY: c.y + 40)
                scene.colliders.addCylinder(center: SIMD2(x, z + 0.9), radius: 0.7, minY: c.y - 4, maxY: c.y + 40)
            }
        }
        scene.add("ta_stacks", mesh: shelves.build(device: device, label: "ledger stacks"), uniforms: ObjectUniforms(model: matrix_identity_float4x4))
    }

    // MARK: The dome

    static func addDome(_ scene: Scene, device: MTLDevice) {
        let c = ArchiveLayout.dome
        var b = MeshBuilder()
        let drum: Float = 9.2, drumH: Float = 4.6
        let f = Placement.upright(terrain: scene.terrain, x: c.x, z: c.z, radius: drum, yaw: 0)
        let drop = f.depth + 0.3
        let drumProfile: [SIMD2<Float>] = [
            SIMD2<Float>(drum + 0.25, -drop), SIMD2<Float>(drum + 0.25, 0.5), SIMD2<Float>(drum + 0.45, 0.55), SIMD2<Float>(drum + 0.45, 0.8), SIMD2<Float>(drum, 0.85),
            SIMD2<Float>(drum, drumH), SIMD2<Float>(drum + 0.3, drumH), SIMD2<Float>(drum + 0.3, drumH + 0.35), SIMD2<Float>(drum - 0.3, drumH + 0.4),
        ]
        b.lathe(profile: drumProfile, segments: 48, smooth: true, surface: slate)
        // The brass dome: a shallow ogive, twelve ribs, a door-wide slit facing the sky to the south, a ring at its crown.
        func domeAngle(_ k: Int) -> Float { Float(k) / 14 * Float.pi / 2 * 0.93 }
        func domePoint(_ k: Int, _ inset: Float) -> SIMD2<Float> {
            let a = domeAngle(k)
            let r = drum - inset
            return SIMD2(r * cos(a), drumH + 0.4 + (drum - 0.4) * 0.82 * sin(a))
        }
        var profile: [SIMD2<Float>] = []
        for k in 0...14 { profile.append(domePoint(k, 0.4)) }
        b.lathe(profile: profile, segments: 48, smooth: true, surface: brass)
        let top = profile[profile.count - 1]
        for i in 0..<12 {
            let a = Float(i) / 12 * 2 * Float.pi
            var pts: [SIMD3<Float>] = []
            for q in profile.dropFirst(1) { pts.append(SIMD3((q.x + 0.06) * cos(a), q.y + 0.03, (q.x + 0.06) * sin(a))) }
            b.tube(points: pts, radii: [Float](repeating: 0.07, count: pts.count), sides: 5, caps: false, surface: brass)
        }
        b.torus(major: top.x + 0.2, minor: 0.12, segments: 24, sides: 6, surface: brass, transform: translation(SIMD3(0, top.y, 0)))
        // The slit: a dark strip up the south side of the dome (in the plane x = 0, on the +z side), in twelve short bars following the dome's curve.
        for k in 0..<12 {
            let p0 = domePoint(k, 0.35), p1 = domePoint(k + 1, 0.35)
            let mid = (p0 + p1) / 2
            let pitch = atan2(p1.y - p0.y, p1.x - p0.x)                                   // the bar's direction in the (z, y) plane
            b.box(size: SIMD3(1.1, simd_length(p1 - p0) + 0.02, 0.08), surface: iron, transform: translation(SIMD3(0, mid.y, mid.x)) * rotationX(-(Float.pi / 2 - pitch)))
        }
        // The door on the south: a recess in an arch of dressed stone.
        b.box(size: SIMD3(2.0, 2.8, 0.5), surface: iron, transform: translation(SIMD3(0, 1.4, drum + 0.1)))
        for sx: Float in [-1, 1] { b.chamferBox(size: SIMD3(0.55, 3.2, 0.7), chamfer: 0.04, surface: slateLight, transform: translation(SIMD3(sx * 1.3, 1.6, drum + 0.15))) }
        b.chamferBox(size: SIMD3(3.2, 0.5, 0.7), chamfer: 0.04, surface: slateLight, transform: translation(SIMD3(0, 3.25, drum + 0.15)))
        scene.placed.append(Placement.record(kind: "ta_dome", mesh: b, transform: f.transform))
        scene.colliders.addCylinder(center: SIMD2(c.x, c.z), radius: drum + 0.4, minY: c.y - 4, maxY: c.y + 20)
        scene.add("ta_dome", mesh: b.build(device: device, label: "observatory dome"), uniforms: ObjectUniforms(model: f.transform))
    }

    // MARK: Sluices

    /// The sluice room's frame: the gate stands across the room at its centre, facing south (the sea).
    static func addSluice(_ scene: Scene, device: MTLDevice, _ k: Int) {
        let c = ArchiveLayout.sluices[k]
        let place = translation(c)
        var b = MeshBuilder()
        // A wall across the room with a 2 m gap for the gate: two piers (0.9 x 3.2 x 0.9) either side, wall blocks beyond them, a lintel beam over the gap.
        let gapHalf: Float = 1.1
        for sx: Float in [-1, 1] {
            b.chamferBox(size: SIMD3(0.9, 3.4, 0.9), chamfer: 0.04, surface: slateLight, transform: translation(SIMD3(sx * (gapHalf + 0.45), 1.7, 0)))
            b.chamferBox(size: SIMD3(2.8, 2.2, 0.7), chamfer: 0.04, surface: slate, transform: translation(SIMD3(sx * (gapHalf + 0.9 + 1.4), 1.1, 0)))
        }
        b.chamferBox(size: SIMD3(3.4, 0.45, 1.0), chamfer: 0.04, surface: slateLight, transform: translation(SIMD3(0, 3.6, 0)))
        // Guide slots (dark), the winding gear above: a brass spindle across the lintel top, and a pedestal with the wheel beside the gap (the wheel itself turns: `wheelName`).
        for sx: Float in [-1, 1] { b.box(size: SIMD3(0.1, 3.0, 0.14), surface: iron, transform: translation(SIMD3(sx * gapHalf, 1.5, 0.3))) }
        b.cylinder(radiusTop: 0.07, radiusBottom: 0.07, height: 3.0, segments: 8, smooth: true, surface: brass, transform: translation(SIMD3(0, 3.95, 0)) * rotationZ(.pi / 2) * translation(SIMD3(0, -1.5, 0)))
        b.chamferBox(size: SIMD3(0.6, 1.0, 0.6), chamfer: 0.04, surface: slateLight, transform: translation(SIMD3(gapHalf + 2.4, 0.5, 1.2)))
        scene.colliders.addCylinder(center: SIMD2(c.x - 2.6, c.z), radius: 1.1, minY: c.y - 1, maxY: c.y + 5)
        scene.colliders.addCylinder(center: SIMD2(c.x - 3.9, c.z), radius: 1.1, minY: c.y - 1, maxY: c.y + 5)
        scene.colliders.addCylinder(center: SIMD2(c.x + 2.6, c.z), radius: 1.1, minY: c.y - 1, maxY: c.y + 5)
        scene.colliders.addCylinder(center: SIMD2(c.x + 3.9, c.z), radius: 1.1, minY: c.y - 1, maxY: c.y + 5)
        let gc = gateCollider(k)
        scene.colliders.addCylinder(center: gc.center, radius: gc.radius, minY: c.y - 1, maxY: c.y + 4)                          // the closed gate (`update` takes it out when it is open)
        // The gate's own MARK (S04.3 follow-up, #35-#36): on both piers, a painted band in the gate's colour (tide blue, wind green, stone orange) from where its water window begins to where it ends (the part
        // of it above the floor), so the player can see "it is at the tide gate now" when the water stands in the band. A thin brass line caps it.
        let win = Tide.windows[k], floorY = ArchiveLayout.sluiceFloors[k]
        let lo = max(Tide.metres(level: win.lowerBound), floorY + 0.04), hi = Tide.metres(level: win.upperBound)
        if hi > lo {
            let col = beamColours[k] * 0.9
            for sx: Float in [-1, 1] {
                b.box(size: SIMD3(0.7, hi - lo, 0.1), surface: Surface(color: beamColours[k] * 1.3, roughness: 0.5, material: .paint), transform: translation(SIMD3(sx * (gapHalf + 0.45), (lo + hi) / 2 - floorY, 0.47)))
                b.box(size: SIMD3(0.8, 0.09, 0.14), surface: brass, transform: translation(SIMD3(sx * (gapHalf + 0.45), hi - floorY, 0.47)))
            }
        }
        scene.add(sluiceName(k), mesh: b.build(device: device, label: "sluice \(k)"), uniforms: ObjectUniforms(model: place))
        // The gate plate (oak with iron straps), closed: it fills the gap from the floor; open it is lifted `gateLift` m.
        var g = MeshBuilder()
        g.box(size: SIMD3(2.0, 3.0, 0.16), surface: oak, transform: translation(SIMD3(0, 1.5, 0)))
        for y in [Float(0.5), 1.5, 2.5] { g.box(size: SIMD3(2.06, 0.1, 0.2), surface: iron, transform: translation(SIMD3(0, y, 0))) }
        scene.add(gateName(k), mesh: g.build(device: device, label: "sluice gate \(k)"), uniforms: ObjectUniforms(model: sluiceGateModel(k, open: 0)))
        // The wheel on its pedestal: a brass ring with six spokes, turned about the pedestal's axis.
        var w = MeshBuilder()
        w.torus(major: 0.4, minor: 0.04, segments: 24, sides: 6, surface: brass, transform: rotationX(.pi / 2))
        for s in 0..<6 { w.box(size: SIMD3(0.8, 0.05, 0.05), surface: brass, transform: rotationY(Float(s) / 6 * .pi) * translation(.zero)) }
        w.cylinder(radiusTop: 0.07, radiusBottom: 0.07, height: 0.3, segments: 8, smooth: true, surface: brass, transform: translation(SIMD3(0, -0.15, 0)))
        scene.add(wheelName(k), mesh: w.build(device: device, label: "sluice wheel \(k)"), uniforms: ObjectUniforms(model: sluiceWheelModel(k, turns: 0)))
    }
    /// How far the gate is lifted when fully open (m).
    static let gateLift: Float = 2.7
    /// The gate plate's model for `open` 0 (closed) ... 1 (open): lifted straight up its slots.
    static func sluiceGateModel(_ k: Int, open: Float) -> float4x4 { translation(ArchiveLayout.sluices[k] + SIMD3(0, min(max(open, 0), 1) * gateLift, 0.0)) }
    /// The wheel's model after `turns` full turns: the wheel stands on its pedestal (beside the gap, facing the player), turning about the horizontal axis through the pedestal.
    static func sluiceWheelModel(_ k: Int, turns: Float) -> float4x4 { translation(ArchiveLayout.sluices[k] + SIMD3(1.1 + 2.4, 1.35, 1.2)) * rotationZ(turns * 2 * .pi) }

    // MARK: The prism chamber

    static let chamberRadius: Float = 7.0
    static let prismPosition: SIMD3<Float> = ArchiveLayout.prismChamber + SIMD3(0, 1.75, 0)

    static func addPrismChamber(_ scene: Scene, device: MTLDevice) {
        let c = ArchiveLayout.prismChamber
        let place = translation(c)
        var b = MeshBuilder()
        let r = chamberRadius, wall: Float = 0.9, h: Float = 4.6
        // The wall: outer face, top, inner face, with a doorway centred on the south (quads 10-13 of the 48-ring, 75 to 105 degrees, left out), the two jambs closed with blocks at the cut edges.
        b.lathe(profile: [SIMD2(r, -1.5), SIMD2(r, h), SIMD2(r - wall, h)], segments: 48, smooth: true, surface: slate, omit: [10, 11, 12, 13])
        b.lathe(profile: [SIMD2(r - wall, h), SIMD2(r - wall, -1.5)], segments: 48, smooth: true, surface: slate, omit: [10, 11, 12, 13])
        let jambAngles: [Float] = [75 * Float.pi / 180, 105 * Float.pi / 180]
        for a in jambAngles {
            let at = SIMD3((r - wall / 2) * cos(a), (h - 1.5) / 2, (r - wall / 2) * sin(a))
            b.chamferBox(size: SIMD3(0.6, h + 1.5, wall + 0.1), chamfer: 0.04, surface: slateLight, transform: translation(at) * rotationY(Float.pi / 2 - a))
        }
        b.chamferBox(size: SIMD3(3.9, 0.5, wall + 0.1), chamfer: 0.04, surface: slateLight, transform: translation(SIMD3(0, 3.3, (r - wall / 2) * sin(jambAngles[0]))))
        // A cornice of dressed stone round the wall's top.
        b.lathe(profile: [SIMD2(r + 0.2, h - 0.2), SIMD2(r + 0.2, h + 0.15), SIMD2(r - wall - 0.1, h + 0.15)], segments: 48, smooth: true, surface: slateLight, omit: [10, 11, 12, 13])
        // The floor: dressed slabs (a disc) and the brass pedestal with the prism's stand.
        b.cylinder(radiusTop: r - wall, radiusBottom: r - wall, height: 0.12, segments: 40, smooth: false, surface: slateLight, transform: translation(SIMD3(0, -0.06, 0)))
        b.cylinder(radiusTop: 0.42, radiusBottom: 0.55, height: 1.15, segments: 16, smooth: true, surface: brass, transform: translation(SIMD3(0, 0, 0)))
        b.torus(major: 0.55, minor: 0.05, segments: 24, sides: 6, surface: brass, transform: translation(SIMD3(0, 1.15, 0)))
        scene.colliders.addCylinder(center: SIMD2(c.x, c.z), radius: 0.7, minY: c.y - 1, maxY: c.y + 3)
        // The wall itself blocks the player outside the doorway: cylinders round it, the doorway's span left open.
        for k in 0..<24 {
            let a = Float(k) / 24 * 2 * Float.pi
            if abs(a - Float.pi / 2) < 0.35 { continue }                                  // the doorway: the jambs below carry its colliders
            scene.colliders.addCylinder(center: SIMD2(c.x + cos(a) * (r - wall / 2), c.z + sin(a) * (r - wall / 2)), radius: 1.2, minY: c.y - 2, maxY: c.y + 8)
        }
        for a in jambAngles { scene.colliders.addCylinder(center: SIMD2(c.x + cos(a) * (r - wall / 2), c.z + sin(a) * (r - wall / 2)), radius: 0.6, minY: c.y - 2, maxY: c.y + 8) }
        scene.add("ta_chamber", mesh: b.build(device: device, label: "prism chamber"), uniforms: ObjectUniforms(model: place))
        // The prism: a glass triangular prism standing on the pedestal.
        var p = MeshBuilder()
        p.cylinder(radiusTop: 0.30, radiusBottom: 0.30, height: 0.75, segments: 3, smooth: false, surface: Surface(color: SIMD3(0.80, 0.92, 1.0), roughness: 0.05, material: .emissiveGlass), transform: translation(SIMD3(0, -0.375, 0)))
        var pu = ObjectUniforms(model: translation(prismPosition), tint: SIMD4(1, 1, 1, 1))
        pu.emissive = SIMD4(0.55, 0.75, 1.0, 0.7)
        scene.add(prismName, mesh: p.build(device: device, label: "prism"), uniforms: pu, refractive: true)
        // One beam in (white, from a slit in the north-west wall to the prism) and three out (tide, wind, stone), thin emissive bars: light, so no shadow. The three components fan out of the prism
        // `beamSpread` apart and turn with the ring (`updatePrism`); a MARK on the wall for each gate stands where its component lands when the ring is on that gate's angle.
        func beam(_ name: String, from: SIMD3<Float>, to: SIMD3<Float>, colour: SIMD3<Float>, width: Float, strength: Float) {
            let d = to - from, len = simd_length(d)
            var m = MeshBuilder()
            m.box(size: SIMD3(width, len, width), surface: Surface(color: colour, roughness: 0.3, material: .emissiveGlass), transform: translation(SIMD3(0, len / 2, 0)))
            var u = ObjectUniforms(model: translation(from) * rotation(aligningYTo: d / len), tint: SIMD4(1, 1, 1, 1))
            u.emissive = SIMD4(colour, strength)
            scene.add(name, mesh: m.build(device: device, label: name), uniforms: u)
        }
        let inFrom = prismPosition + SIMD3(-r + wall + 0.4, 1.2, -2.2)
        beam(beamInName, from: inFrom, to: prismPosition, colour: SIMD3(1.0, 0.97, 0.9), width: 0.07, strength: 5)
        for k in 0..<3 { beam(beamOutName(k), from: prismPosition, to: prismPosition + SIMD3(cos(beamAngle(k, ring: TideArchivePuzzle.initialRing)), -0.02, sin(beamAngle(k, ring: TideArchivePuzzle.initialRing))) * componentLength, colour: beamColours[k], width: 0.06, strength: 5) }
        for k in 0..<3 {
            let a = markAngle(k)
            var m = MeshBuilder()
            m.chamferBox(size: SIMD3(0.7, 1.0, 0.1), chamfer: 0.02, surface: brass, transform: .init(diagonal: SIMD4(1, 1, 1, 1)))
            m.box(size: SIMD3(0.5, 0.8, 0.04), surface: Surface(color: beamColours[k] * 0.8, roughness: 0.4, material: .emissiveGlass), transform: translation(SIMD3(0, 0, 0.05)))
            let at = SIMD3(cos(a) * (r - wall - 0.04), prismPosition.y - c.y, sin(a) * (r - wall - 0.04))
            scene.add(markName(k), mesh: m.build(device: device, label: "prism mark \(k)"), uniforms: ObjectUniforms(model: translation(c + at) * rotationY(atan2(-cos(a), -sin(a)))))
        }
        // The ring round the prism's pedestal: brass, with a notch every ring step (15 degrees) and a pointer; it turns with the ring (`updatePrism`).
        var ring = MeshBuilder()
        ring.torus(major: 0.78, minor: 0.05, segments: 36, sides: 6, surface: brass, transform: .init(diagonal: SIMD4(1, 1, 1, 1)))
        for n in 0..<24 { ring.box(size: SIMD3(0.05, 0.06, 0.12), surface: iron, transform: rotationY(Float(n) / 24 * 2 * Float.pi) * translation(SIMD3(0.8, 0, 0))) }
        ring.box(size: SIMD3(0.3, 0.08, 0.1), surface: brass, transform: translation(SIMD3(0.95, 0, 0)))
        scene.add(ringName, mesh: ring.build(device: device, label: "prism ring"), uniforms: ObjectUniforms(model: translation(c + SIMD3(0, 0.55, 0)) * rotationY(-TideArchivePuzzle.initialRing)))
    }

    static let componentLength: Float = 5.5, componentSpread: Float = 0.21
    /// The world direction (radians about the vertical, x east / z south) of component `k` when the ring stands at `ring`: the fan is centred on the ring's angle.
    static func beamAngle(_ k: Int, ring: Float) -> Float { ring + (Float(k) - 1) * componentSpread }
    /// Where gate `k`'s mark stands on the wall: the direction its component takes when the ring is on that gate's target angle (`TideArchivePuzzle.beamTargets`).
    static func markAngle(_ k: Int) -> Float { beamAngle(k, ring: TideArchivePuzzle.beamTargets[k]) }
    /// True when the ring stands on gate `k`'s target (to within a fifth of a ring step): the component rests on the mark.
    static func resting(_ k: Int, ring: Float) -> Bool {
        var d = (ring - TideArchivePuzzle.beamTargets[k]).truncatingRemainder(dividingBy: 2 * Float.pi)
        if d > Float.pi { d -= 2 * Float.pi }; if d < -Float.pi { d += 2 * Float.pi }
        return abs(d) < TideArchivePuzzle.ringStep * 0.2
    }
    static func updateTableau(_ scene: Scene, shown: PageAuthor?, time: Float) { ArchiveStory.updateTableau(scene, shown: shown, time: time) }
    static func updatePrism(_ scene: Scene, ringAngle: Float) {
        for k in 0..<3 {
            let a = beamAngle(k, ring: ringAngle), lit = resting(k, ring: ringAngle)
            let dir = simd_normalize(SIMD3(cos(a), -0.02, sin(a)))
            scene.update(beamOutName(k)) { $0.uniforms.model = translation(prismPosition) * rotation(aligningYTo: dir); $0.uniforms.emissive = SIMD4(beamColours[k], lit ? 8 : 5) }
            scene.update(markName(k)) { $0.uniforms.emissive = lit ? SIMD4(beamColours[k], 3.5) : SIMD4(0, 0, 0, 0) }
        }
        scene.update(ringName) { $0.uniforms.model = translation(ArchiveLayout.prismChamber + SIMD3(0, 0.55, 0)) * rotationY(-ringAngle) }
    }

    // MARK: Lanterns

    /// Stone lanterns along the route every 20 m, alternating sides, each on its own footing (the same body as Varrow's: `Props.stoneLantern`), with a lamp core that is light only.
    static func addLanterns(_ scene: Scene, device: MTLDevice) {
        let (bodyProto, coreProto) = Props.stoneLantern()
        var body = MeshBuilder(), core = MeshBuilder()
        var side: Float = 1
        let pts = ArchiveLayout.path.map { SIMD2($0.x, $0.z) }
        var carried: Float = 10
        for k in 0..<(pts.count - 1) {
            let a = pts[k], b = pts[k + 1]
            let dir = simd_normalize(b - a), nrm = SIMD2(-dir.y, dir.x)
            let len = simd_length(b - a)
            var s = carried
            while s < len {
                let c = a + dir * s + nrm * 2.6 * side
                side = -side
                let g = ArchiveTerrain.gallery, inCourt = simd_abs(c - g.centre).x < g.half.x + 1.5 && simd_abs(c - g.centre).y < g.half.y + 1.5
                if scene.terrain.sampleHeight(x: c.x, z: c.y) > 1.2 && !inCourt {
                    let yaw = Island.noise.unit(Int32(c.x), Int32(c.y)) * 2 * .pi
                    let up = Placement.upright(terrain: scene.terrain, x: c.x, z: c.y, radius: 0.36, yaw: yaw)
                    body.append(bodyProto, transform: up.transform)
                    core.append(coreProto, transform: up.transform)
                    var foot = MeshBuilder()
                    let drop = up.depth + 0.3
                    foot.chamferBox(size: SIMD3(0.55, drop + 0.12, 0.55), chamfer: 0.025, surface: Surface(color: SIMD3(0.40, 0.43, 0.43), roughness: 0.85, material: .dressed), transform: translation(SIMD3(0, 0.06 - drop / 2, 0)))
                    body.append(foot, transform: up.transform)
                    scene.placed.append(Placement.record(kind: "ta_lantern", mesh: foot, transform: up.transform))
                    scene.colliders.addCylinder(center: c, radius: 0.3, minY: up.transform.columns.3.y - 1, maxY: up.transform.columns.3.y + 2)
                }
                s += 20
            }
            carried = s - len
        }
        scene.add("ta_lanterns", mesh: body.build(device: device, label: "archive lanterns"))
        scene.add("ta_lantern_cores", mesh: core.build(device: device, label: "archive lantern cores"), uniforms: ObjectUniforms(model: matrix_identity_float4x4, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.66, 0.30, 6)))
    }
}
