import Metal
import simd

/// S05.1 (builder A): Ilse's site in the Tide Archive, the interior half of the sibling split (docs/plans/S05-divergent-routes.md section 3): the catalogue's SHELF BAYS in the stacks (I1), the LEDGER ROOM
/// behind its door (I1's consequence), and the BELL PIPES in the three sluice rooms (I2). Builder B owns every rule; this file owns what is seen. Each part has ONE call B makes:
///   - `ShelfBays.set(scene, k, look:, swing:)`   bay k's glyph dormant / warm (rung right, stays warm) / sour (rung wrong); `swing` -1...1 rocks its bell (B eases it, a strike is a 1 decaying to 0)
///   - `LedgerRoom.setDoor(scene, open:)`         the door 0 (shut, blocks the doorway) ... 1 (sunk into the floor, collider out)
///   - `BellPipes.set(scene, k, level:, agree:)`  pipe k's water column (0...1: the sea's level, `Tide.level`) and how well the held fork agrees with it (0...1: crown glows)
/// The sound (a bell strike, the pipe's tone against the fork) is `ArchiveAudio.Event.bell` / `Inputs.pipe`, with the pitches in `IlseTones` (Audio/IlseAudio.swift).
/// All positions come from `ArchiveLayout` (Layout.swift). Palette as the rest of the Archive: wet slate, brass, dark oak, a warm lamp-glow for "right" and a sick green for "wrong".
enum IlseSite {
    static func populate(_ scene: Scene, device: MTLDevice) {
        ShelfBays.add(to: scene, device: device)
        LedgerRoom.add(to: scene, device: device)
        BellPipes.add(to: scene, device: device)
    }
}

// MARK: - The shelf bays

enum ShelfBays {
    static let count = ArchiveLayout.bayCount
    enum Look: Equatable { case dormant, warm, sour }
    static func glyphName(_ k: Int) -> String { "ta_bay_glyph_\(k)" }
    static func bellName(_ k: Int) -> String { "ta_bay_bell_\(k)" }
    static let framesName = "ta_bay_frames"
    static var allNames: [String] { [framesName] + (0..<count).flatMap { [glyphName($0), bellName($0)] } }

    /// Heights in the unit's own frame (its floor = 0): the sign board on the shelf top, the glyph's centre on it, the bell's hanging pivot on its bracket and how far the bell hangs.
    static let boardY: Float = 2.78, glyphZ: Float = 0.30
    static let bellPivot = SIMD3<Float>(0.9, 2.46, 0.66), bellDrop: Float = 0.42
    /// Emissive (colour, strength) of a glyph: dormant is a dull brass-glass, warm a lamp, sour a sick green that dies down.
    static let dormantLook = SIMD4<Float>(0.42, 0.34, 0.22, 0.3), warmLook = SIMD4<Float>(1.0, 0.30, 0.03, 1.5), sourLook = SIMD4<Float>(0.28, 0.50, 0.10, 1.0)
    /// The glyph's surface colour: dull dark brass-glass dormant (a lit white surface would wash the glow out), warmer once rung.
    static let dormantTint = SIMD4<Float>(0.17, 0.14, 0.10, 1), warmTint = SIMD4<Float>(0.55, 0.42, 0.26, 1)
    static func emissive(_ look: Look) -> SIMD4<Float> { look == .warm ? warmLook : (look == .sour ? sourLook : dormantLook) }

    /// The unit's frame: the same footing the stacks' own shelf unit stands on (`ArchiveProps.addStacks`: upright on the highest ground, then 0.3 m up), facing east.
    static func frame(_ scene: Scene, _ k: Int) -> float4x4 {
        let p = ArchiveLayout.bayXZ(k)
        return Placement.upright(terrain: scene.terrain, x: p.x, z: p.y, radius: 1.3, yaw: Float.pi / 2).transform * translation(SIMD3(0, 0.3, 0))
    }
    /// Where a person touches the bay: the glyph's centre and the bell's centre, in the world (B's interaction boxes).
    static func glyphPoint(_ scene: Scene, _ k: Int) -> SIMD3<Float> { let m = frame(scene, k) * SIMD4(0, boardY, glyphZ, 1); return SIMD3(m.x, m.y, m.z) }
    static func bellPoint(_ scene: Scene, _ k: Int) -> SIMD3<Float> { let m = frame(scene, k) * SIMD4(bellPivot.x, bellPivot.y - bellDrop * 0.5, bellPivot.z, 1); return SIMD3(m.x, m.y, m.z) }
    static func bellModel(_ scene: Scene, _ k: Int, swing: Float) -> float4x4 { frame(scene, k) * translation(bellPivot) * rotationX(max(-1, min(1, swing)) * 0.42) }

    /// Drives bay k (the single call builder B makes). Unknown k is ignored.
    static func set(_ scene: Scene, _ k: Int, look: Look, swing: Float = 0) {
        guard (0..<count).contains(k) else { return }
        let e = emissive(look)
        let lit: Float = look == .dormant ? 0 : 1
        scene.update(glyphName(k)) { $0.uniforms.emissive = e; $0.uniforms.tint = dormantTint + (warmTint - dormantTint) * lit }
        let bellGlow: SIMD4<Float> = look == .warm ? SIMD4(1.0, 0.5, 0.14, 0.9) : (look == .sour ? SIMD4(0.4, 0.56, 0.22, 0.35) : SIMD4(0, 0, 0, 0))
        let m = bellModel(scene, k, swing: swing)
        scene.update(bellName(k)) { $0.uniforms.model = m; $0.uniforms.emissive = bellGlow }
    }

    /// The five glyphs in a plane facing +z, about 0.24 m from the centre: a ring, three bars, a triangle, a diamond, a cross: five silhouettes no two alike, so a sequence can be read at 8 m.
    static func glyph(_ k: Int) -> MeshBuilder {
        var b = MeshBuilder()
        let s = Surface(color: SIMD3(1, 1, 1), roughness: 0.25, material: .emissiveGlass)
        switch k {
        case 0:
            b.torus(major: 0.19, minor: 0.038, segments: 28, sides: 6, surface: s, transform: rotationX(.pi / 2))
            b.cylinder(radiusTop: 0.05, radiusBottom: 0.05, height: 0.05, segments: 10, smooth: true, surface: s, transform: rotationX(.pi / 2))
        case 1:
            for y: Float in [-0.15, 0, 0.15] { b.box(size: SIMD3(0.44, 0.07, 0.05), surface: s, transform: translation(SIMD3(0, y, 0))) }
        case 2:
            b.cylinder(radiusTop: 0.26, radiusBottom: 0.26, height: 0.05, segments: 3, smooth: false, surface: s, transform: rotationX(.pi / 2) * rotationY(.pi))
        case 3:
            b.box(size: SIMD3(0.30, 0.30, 0.05), surface: s, transform: rotationZ(.pi / 4))
        default:
            b.box(size: SIMD3(0.46, 0.08, 0.05), surface: s)
            b.box(size: SIMD3(0.08, 0.46, 0.05), surface: s)
        }
        return b
    }

    static func add(to scene: Scene, device: MTLDevice) {
        var frames = MeshBuilder()
        for k in 0..<count {
            let f = frame(scene, k)
            var b = MeshBuilder()
            // The sign board stands on the unit's top (two brass-capped posts and an oak board), a brass disc behind the glyph; the bell hangs from a bracket arm out of the unit's top rail.
            b.box(size: SIMD3(2.0, 0.78, 0.09), surface: ArchiveProps.oak, transform: translation(SIMD3(0, boardY, 0.22)))
            b.box(size: SIMD3(2.08, 0.05, 0.13), surface: ArchiveProps.brass, transform: translation(SIMD3(0, boardY + 0.415, 0.22)))
            b.cylinder(radiusTop: 0.33, radiusBottom: 0.33, height: 0.035, segments: 24, smooth: true, surface: ArchiveProps.brass, transform: translation(SIMD3(0, boardY, 0.27)) * rotationX(.pi / 2))
            for sx: Float in [-0.85, 0.85] { b.box(size: SIMD3(0.06, 0.4, 0.06), surface: ArchiveProps.oak, transform: translation(SIMD3(sx, 2.5, 0.22))) }
            b.box(size: SIMD3(0.05, 0.05, 0.42), surface: ArchiveProps.brass, transform: translation(SIMD3(bellPivot.x, bellPivot.y + 0.02, 0.45)))
            b.torus(major: 0.035, minor: 0.012, segments: 10, sides: 5, surface: ArchiveProps.brass, transform: translation(bellPivot + SIMD3(0, -0.04, 0)) * rotationX(.pi / 2))
            frames.append(b, transform: f)
        }
        scene.add(framesName, mesh: frames.build(device: device, label: "bay frames"), uniforms: ObjectUniforms(model: matrix_identity_float4x4))
        // A bell: a brass lathe from its crown (the pivot) down to a flared lip, a dark clapper under it.
        var bell = MeshBuilder()
        let bellSurface = Surface(color: SIMD3(0.72, 0.52, 0.22), roughness: 0.3, material: .paleMetal)
        let r: [SIMD2<Float>] = [SIMD2(0.0, -0.02), SIMD2(0.05, -0.04), SIMD2(0.09, -0.10), SIMD2(0.115, -0.22), SIMD2(0.14, -0.34), SIMD2(0.185, -bellDrop), SIMD2(0.165, -bellDrop - 0.01), SIMD2(0.0, -bellDrop + 0.07)]
        bell.lathe(profile: r, segments: 16, smooth: true, surface: bellSurface)
        bell.box(size: SIMD3(0.05, 0.05, 0.05), surface: ArchiveProps.iron, transform: translation(SIMD3(0, -bellDrop - 0.03, 0)))
        let bellMesh = bell.build(device: device, label: "bay bell")
        for k in 0..<count {
            let g = glyph(k).build(device: device, label: "bay glyph \(k)")
            let f = frame(scene, k)
            scene.add(glyphName(k), mesh: g, uniforms: ObjectUniforms(model: f * translation(SIMD3(0, boardY, glyphZ + 0.012)), tint: dormantTint, emissive: dormantLook))
            scene.add(bellName(k), mesh: bellMesh, uniforms: ObjectUniforms(model: f * translation(bellPivot), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0, 0, 0, 0)))
        }
    }
}

// MARK: - The ledger room

enum LedgerRoom {
    static let roomName = "ta_ledger_room", doorName = "ta_ledger_door", keyName = "ta_ledger_key"
    static let wallHeight: Float = 3.4, doorHeight: Float = 2.6
    /// The door sinks `doorDrop` m into the floor (the terrain hides it): shut is 0.
    static let doorDrop: Float = 2.8
    static func doorModel(open: Float) -> float4x4 { translation(ArchiveLayout.ledgerDoor + SIMD3(0, -min(max(open, 0), 1) * doorDrop, 0)) }
    /// The doorway's collider (while the door is shut).
    static var doorCollider: (center: SIMD2<Float>, radius: Float) { (SIMD2(ArchiveLayout.ledgerDoor.x, ArchiveLayout.ledgerDoor.z), ArchiveLayout.ledgerDoorHalf + 0.15) }

    /// Drives the door (the single call builder B makes): 0 shut ... 1 open. The collider is out from `open` 0.5 (the same rule as the sluice gates).
    static func setDoor(_ scene: Scene, open: Float) {
        let m = doorModel(open: open)
        scene.update(doorName) { $0.uniforms.model = m }
        let blocking = open < 0.5, c = doorCollider, y = ArchiveLayout.ledgerRoom.y
        let st = scene.archive
        if blocking && !st.ledgerBlocking { scene.colliders.addCylinder(center: c.center, radius: c.radius, minY: y - 1, maxY: y + doorHeight); st.ledgerBlocking = true }
        else if !blocking && st.ledgerBlocking { scene.colliders.cylinders.removeAll { $0.center == c.center && $0.radius == c.radius }; st.ledgerBlocking = false }
    }

    static func add(to scene: Scene, device: MTLDevice) {
        let rm = ArchiveLayout.ledgerRoom, half = ArchiveLayout.ledgerHalf, dh = ArchiveLayout.ledgerDoorHalf
        var b = MeshBuilder()
        let t: Float = 0.5, h = wallHeight, base: Float = -1.2
        func wall(_ size: SIMD3<Float>, _ at: SIMD3<Float>, light: Bool = false) {
            b.chamferBox(size: size, chamfer: 0.04, surface: light ? ArchiveProps.slateLight : ArchiveProps.slate, transform: translation(at))
        }
        let hh = (h - base) / 2 + base
        wall(SIMD3(t, h - base, 2 * half.y + t), SIMD3(-half.x, hh, 0))                                    // west
        wall(SIMD3(t, h - base, 2 * half.y + t), SIMD3(half.x, hh, 0))                                     // east
        wall(SIMD3(2 * half.x + t, h - base, t), SIMD3(0, hh, -half.y))                                    // north
        let seg = half.x + t / 2 - dh                                                                       // the south wall's two pieces either side of the doorway
        for sx: Float in [-1, 1] { wall(SIMD3(seg, h - base, t), SIMD3(sx * (dh + seg / 2), hh, half.y)) }
        wall(SIMD3(2 * dh + 0.5, h - doorHeight - 0.05, t + 0.1), SIMD3(0, doorHeight + 0.05 + (h - doorHeight - 0.05) / 2, half.y), light: true)   // the lintel
        for sx: Float in [-1, 1] { wall(SIMD3(0.4, doorHeight + 0.05 - base, t + 0.14), SIMD3(sx * (dh + 0.2), (doorHeight + 0.05 + base) / 2, half.y), light: true) }   // the dressed jambs
        for sx: Float in [-1, 1] { b.box(size: SIMD3(t + 0.2, 0.16, 2 * half.y + t + 0.2), surface: ArchiveProps.slateLight, transform: translation(SIMD3(sx * half.x, h + 0.08, 0))) }
        for sz: Float in [-1, 1] { b.box(size: SIMD3(2 * half.x + t + 0.2, 0.16, t + 0.2), surface: ArchiveProps.slateLight, transform: translation(SIMD3(0, h + 0.08, sz * half.y))) }
        // The floor: a dressed slab; the page's desk (a slate block with a sloped brass-edged top) and the key's stand; ledger shelves along the two side walls.
        b.chamferBox(size: SIMD3(2 * half.x - 0.1, 0.14, 2 * half.y - 0.1), chamfer: 0.03, surface: ArchiveProps.slateLight, transform: translation(SIMD3(0, 0.0, 0)))
        b.chamferBox(size: SIMD3(1.1, 0.8, 0.7), chamfer: 0.03, surface: ArchiveProps.slate, transform: translation(SIMD3(0, 0.4, -1.2)))
        b.box(size: SIMD3(1.2, 0.05, 0.8), surface: ArchiveProps.oak, transform: translation(SIMD3(0, 0.84, -1.2)) * rotationX(-0.18))
        b.box(size: SIMD3(1.24, 0.03, 0.04), surface: ArchiveProps.brass, transform: translation(SIMD3(0, 0.78, -0.82)))
        b.chamferBox(size: SIMD3(0.5, 0.8, 0.5), chamfer: 0.03, surface: ArchiveProps.slate, transform: translation(SIMD3(1.2, 0.4, -1.3)))
        for (i, sx) in [Float(-1), 1].enumerated() {
            let shelf = ArchiveProps.shelfUnit(seed: 301 + Int32(i), width: 2.4)
            b.append(shelf, transform: translation(SIMD3(sx * (half.x - t / 2 - 0.3), 0.07, 0.5)) * rotationY(sx < 0 ? .pi / 2 : -.pi / 2))
        }
        scene.add(roomName, mesh: b.build(device: device, label: "ledger room"), uniforms: ObjectUniforms(model: translation(rm)))
        // The door: oak with iron straps, in the doorway's plane; it sinks.
        var d = MeshBuilder()
        d.box(size: SIMD3(2 * dh, doorHeight, 0.18), surface: ArchiveProps.oak, transform: translation(SIMD3(0, doorHeight / 2, 0)))
        for y: Float in [0.5, 1.3, 2.1] { d.box(size: SIMD3(2 * dh + 0.06, 0.1, 0.22), surface: ArchiveProps.iron, transform: translation(SIMD3(0, y, 0))) }
        d.torus(major: 0.12, minor: 0.02, segments: 14, sides: 5, surface: ArchiveProps.brass, transform: translation(SIMD3(0.5, 1.2, 0.12)) * rotationX(.pi / 2))
        scene.add(doorName, mesh: d.build(device: device, label: "ledger door"), uniforms: ObjectUniforms(model: doorModel(open: 0)))
        // The key: a brass tuning rod standing in its stand (a plain T of brass with a ring); it is the sluice-room key B's logic hands over.
        var key = MeshBuilder()
        key.cylinder(radiusTop: 0.025, radiusBottom: 0.025, height: 0.42, segments: 8, smooth: true, surface: ArchiveProps.brass, transform: translation(SIMD3(0, 0.21, 0)))
        key.box(size: SIMD3(0.22, 0.04, 0.04), surface: ArchiveProps.brass, transform: translation(SIMD3(0, 0.42, 0)))
        scene.add(keyName, mesh: key.build(device: device, label: "ledger key"), uniforms: ObjectUniforms(model: translation(rm + SIMD3(1.2, 0.8, -1.3))))
        // A lamp in the corner: the route lanterns' own stone body and a warm core (always lit: the room is the one place in the stacks that wants reading by).
        let (lampBody, lampCore) = Props.stoneLantern()
        let lampAt = rm + SIMD3(-1.7, 0.07, -1.5)
        scene.add("ta_ledger_lamp_body", mesh: { var m = MeshBuilder(); m.append(lampBody, transform: translation(lampAt)); return m.build(device: device, label: "ledger lamp body") }(), uniforms: ObjectUniforms(model: matrix_identity_float4x4))
        scene.add("ta_ledger_lamp", mesh: { var m = MeshBuilder(); m.append(lampCore, transform: translation(lampAt)); return m.build(device: device, label: "ledger lamp") }(), uniforms: ObjectUniforms(model: matrix_identity_float4x4, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.62, 0.25, 3.0)))
        scene.colliders.addCylinder(center: SIMD2(lampAt.x, lampAt.z), radius: 0.3, minY: rm.y - 1, maxY: rm.y + 2)
        // Colliders: the walls (cylinders along them, clear of the doorway), the closed door, the desk and the stand. All stand on the room's floor level.
        let y = rm.y
        func wallCol(_ x: Float, _ z: Float) { scene.colliders.addCylinder(center: SIMD2(rm.x + x, rm.z + z), radius: 0.55, minY: y - 1.5, maxY: y + h) }
        var z = -half.y
        while z <= half.y + 0.01 { wallCol(-half.x, z); wallCol(half.x, z); z += 0.9 }
        var x = -half.x + 0.9
        while x < half.x - 0.5 { wallCol(x, -half.y); x += 0.9 }
        for sx: Float in [-1, 1] {                                                     // the south wall's two pieces: from the corner to the jamb, then the jamb itself
            var q = half.x - 0.9
            while q > dh + 0.5 + 0.2 { wallCol(sx * q, half.y); q -= 0.9 }
            wallCol(sx * (dh + 0.5), half.y)
        }
        for sx: Float in [-1, 1] { for dz: Float in [-0.6, 0.6] { scene.colliders.addCylinder(center: SIMD2(rm.x + sx * (half.x - t / 2 - 0.3 + 0.1), rm.z + 0.5 + dz), radius: 0.42, minY: y - 1, maxY: y + 2.4) } }   // the two side shelves
        let dc = doorCollider
        scene.colliders.addCylinder(center: dc.center, radius: dc.radius, minY: y - 1, maxY: y + doorHeight)
        scene.colliders.addCylinder(center: SIMD2(rm.x, rm.z - 1.2), radius: 0.62, minY: y - 1, maxY: y + 1.2)
        scene.colliders.addCylinder(center: SIMD2(rm.x + 1.2, rm.z - 1.3), radius: 0.35, minY: y - 1, maxY: y + 1.2)
    }
}

// MARK: - The bell pipes

enum BellPipes {
    static let count = 3
    static func waterName(_ k: Int) -> String { "ta_pipe_water_\(k)" }
    static func crownName(_ k: Int) -> String { "ta_pipe_crown_\(k)" }
    static let framesName = "ta_pipe_frames"
    static func frameName(_ k: Int) -> String { "\(framesName)_\(k)" }
    static var allNames: [String] { (0..<count).flatMap { [frameName($0), waterName($0), crownName($0)] } }
    /// The column: its foot, its height at level 1, its radius. The water in the pipe is the sea's level (`Tide.level`: 0 low ... 1 high).
    static let columnFoot: Float = 0.45, columnHeight: Float = 1.9, columnRadius: Float = 0.085
    static let waterColour = SIMD3<Float>(0.10, 0.36, 0.85), waterTint = SIMD4<Float>(0.10, 0.26, 0.55, 1)
    static let idleCrown = SIMD4<Float>(0.9, 0.55, 0.2, 0.25), agreeCrown = SIMD4<Float>(1.0, 0.42, 0.08, 3.2)
    static func waterModel(_ k: Int, level: Float) -> float4x4 {
        translation(ArchiveLayout.pipe(k) + SIMD3(0, columnFoot, 0)) * scaling(SIMD3(1, max(min(level, 1), 0) * columnHeight + 0.01, 1))
    }
    /// Where the fork is held to try pipe k (B's interaction box): the column's middle.
    static func holdPoint(_ k: Int) -> SIMD3<Float> { ArchiveLayout.pipe(k) + SIMD3(0, columnFoot + columnHeight * 0.5, 0) }

    /// Drives pipe k (the single call builder B makes): `level` the water's height in the column (0...1; feed it `Tide.level(clock)`), `agree` 0...1 how nearly the held fork's tone and the pipe's
    /// agree (`IlseTones.agreement`): the crown ring warms and brightens as the beats slow. Unknown k is ignored.
    static func set(_ scene: Scene, _ k: Int, level: Float, agree: Float = 0) {
        guard (0..<count).contains(k) else { return }
        let a = min(max(agree, 0), 1), u = a * a * (3 - 2 * a)
        let m = waterModel(k, level: level)
        let crown = idleCrown + (agreeCrown - idleCrown) * u
        scene.update(waterName(k)) { $0.uniforms.model = m; $0.uniforms.emissive = SIMD4(waterColour, 0.8 + 0.6 * u) }
        scene.update(crownName(k)) { $0.uniforms.emissive = crown }
    }

    static func add(to scene: Scene, device: MTLDevice) {
        let top = columnFoot + columnHeight
        var water = MeshBuilder()
        water.cylinder(radiusTop: columnRadius, radiusBottom: columnRadius, height: 1, segments: 14, smooth: true, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.1, material: .emissiveGlass), transform: translation(SIMD3(0, 0.5, 0)))
        let waterMesh = water.build(device: device, label: "pipe water")
        var crown = MeshBuilder()
        crown.torus(major: 0.19, minor: 0.03, segments: 24, sides: 6, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.2, material: .emissiveGlass), transform: translation(SIMD3(0, top + 0.16, 0)))
        let crownMesh = crown.build(device: device, label: "pipe crown")
        for k in 0..<count {
            var f = MeshBuilder()
            let p = ArchiveLayout.pipeOffset                                              // in the room's frame (the frame mesh is placed at the room's centre)
            let win = Tide.windows[k]
            // A brass foot on a slate block, four cage rods round the column, a ring at every fifth of its height, a dark organ mouth near the top, and the gate's window painted on a back plate.
            f.chamferBox(size: SIMD3(0.8, 0.28, 0.8), chamfer: 0.03, surface: ArchiveProps.slateLight, transform: translation(p + SIMD3(0, 0.14, 0)))
            f.lathe(profile: [SIMD2(0.30, 0.28), SIMD2(0.22, 0.34), SIMD2(0.16, 0.45), SIMD2(0.0, 0.45)], segments: 16, smooth: true, surface: ArchiveProps.brass, transform: translation(p))
            for a in 0..<4 {
                let ang = Float(a) / 4 * 2 * .pi + .pi / 4
                f.cylinder(radiusTop: 0.016, radiusBottom: 0.016, height: columnHeight + 0.1, segments: 6, smooth: true, surface: ArchiveProps.brass, transform: translation(p + SIMD3(cos(ang) * 0.15, columnFoot + (columnHeight + 0.1) / 2, sin(ang) * 0.15)))
            }
            for i in 0...5 { f.torus(major: 0.17, minor: i == 0 || i == 5 ? 0.026 : 0.014, segments: 20, sides: 5, surface: ArchiveProps.brass, transform: translation(p + SIMD3(0, columnFoot + columnHeight * Float(i) / 5, 0))) }
            f.box(size: SIMD3(0.20, 0.07, 0.04), surface: ArchiveProps.iron, transform: translation(p + SIMD3(0, top + 0.1, 0.19)))
            f.cylinder(radiusTop: 0.2, radiusBottom: 0.2, height: 0.06, segments: 20, smooth: true, surface: ArchiveProps.brass, transform: translation(p + SIMD3(0, top + 0.03, 0)))
            f.box(size: SIMD3(0.36, columnHeight + 0.2, 0.05), surface: ArchiveProps.slate, transform: translation(p + SIMD3(0, columnFoot + columnHeight / 2, -0.3)))
            if win.upperBound > win.lowerBound {
                f.box(size: SIMD3(0.3, (win.upperBound - win.lowerBound) * columnHeight, 0.02), surface: Surface(color: ArchiveProps.beamColours[k] * 1.3, roughness: 0.5, material: .paint), transform: translation(p + SIMD3(0, columnFoot + (win.lowerBound + win.upperBound) / 2 * columnHeight, -0.265)))
                for l in [win.lowerBound, win.upperBound] { f.box(size: SIMD3(0.36, 0.025, 0.04), surface: ArchiveProps.brass, transform: translation(p + SIMD3(0, columnFoot + l * columnHeight, -0.26))) }
            }
            let at = ArchiveLayout.pipe(k)
            scene.add("\(framesName)_\(k)", mesh: f.build(device: device, label: "pipe frame \(k)"), uniforms: ObjectUniforms(model: translation(ArchiveLayout.sluices[k])))
            scene.add(waterName(k), mesh: waterMesh, uniforms: ObjectUniforms(model: waterModel(k, level: 0), tint: waterTint, emissive: SIMD4(waterColour, 0.8)))
            scene.add(crownName(k), mesh: crownMesh, uniforms: ObjectUniforms(model: translation(at), tint: SIMD4(1, 1, 1, 1), emissive: idleCrown))
            scene.colliders.addCylinder(center: SIMD2(at.x, at.z), radius: 0.42, minY: ArchiveLayout.sluices[k].y - 1, maxY: ArchiveLayout.sluices[k].y + 3)
        }
    }
}
