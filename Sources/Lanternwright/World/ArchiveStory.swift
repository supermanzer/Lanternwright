import Metal
import simd

/// S04.3 follow-up (builder B's Pending-A items; names are the contract in `docs/plans/S03-player-path.md` Part 2 and the board topic `story`): the pages 10-15 lying where the route meets them (`ti_page_<n>`),
/// the chain map (`ti_chain_map`), the shadow-play wall and its two lanterns (`ti_tableau_wall`, `ti_tableau_lantern_ilse` / `_oren`, whose emissive builder B drives) with the cut-out figures and the light on the wall
/// (`ArchiveProps.updateTableau`), the two tools lying in the world (`ti_find_fork`, `ti_find_lens`), and the Great Ledger gallery: its stone lining and floor (`ta_court`) and its WATER (`ti_gallery_water`, a
/// water body drawn by the water pass; B drains it by moving its model down `drainDepth` m).
enum ArchiveStory {
    /// The gallery's water when full is this far above its floor (1 m under the rim), and B's drain lowers it by `drainDepth` (to the floor).
    static let waterDepth: Float = 3.4, drainDepth: Float = 3.5
    static var galleryFloor: Float { ArchiveTerrain.gallery.floor }
    static var galleryFull: Float { galleryFloor + waterDepth }
    /// How far the gallery's water rises and falls with the tide while it is held (m, either way).
    static let galleryTide: Float = 0.45
    static func galleryTideRise(clock: Float) -> Float { galleryTide * (2 * Tide.level(clock) - 1) }
    static let waterName = "ti_gallery_water"
    static func pageName(_ n: Int) -> String { "ti_page_\(n)" }
    static let wallName = "ti_tableau_wall", glowName = "ta_tableau_glow"
    static func lanternName(_ side: PageAuthor) -> String { "ti_tableau_lantern_\(side == .oren ? "oren" : "ilse")" }
    static func figureName(_ p: TableauPosture, _ i: Int) -> String { "ta_tableau_fig_\(p.rawValue)_\(i)" }
    static let wallHeight: Float = 3.4

    static func populate(_ scene: Scene, device: MTLDevice) {
        addPages(scene, device: device)
        addChainMap(scene, device: device)
        addTableau(scene, device: device)
        addFinds(scene, device: device)
        addGallery(scene, device: device)
    }

    // MARK: Pages

    static func addPages(_ scene: Scene, device: MTLDevice) {
        let mesh = PuzzleProps.pageMesh()
        let built = mesh.build(device: device, label: "archive page")
        let sheet = mesh.vertices.map { SIMD3<Float>($0.position.x, $0.position.y, $0.position.z) }
        for (i, n) in StoryPages.archiveIDs.enumerated() where i < ArchiveLayout.pageSpots.count {
            let s = ArchiveLayout.pageSpots[i]
            let lie = DroppedPages.settle(vertices: sheet, x: s.x, z: s.z, yaw: 0.7 + 1.3 * Float(i), lean: 0.02 + 0.01 * Float(i % 3), ground: { scene.groundHeight(x: $0, z: $1) })
            scene.add(pageName(n), mesh: built, uniforms: ObjectUniforms(model: lie.model, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(0, 0, 0, 0)))
        }
    }

    // MARK: The chain map

    /// A stone plinth with a slate plate tilted toward the reader, brass pins on it at `ChainMap.pins` and a brass chain between them; the last pin is an empty ring (the pin with no name).
    static func addChainMap(_ scene: Scene, device: MTLDevice) {
        let p = ArchiveLayout.chainMap
        let up = Placement.upright(terrain: scene.terrain, x: p.x, z: p.z, radius: 0.6, yaw: Float.pi)           // facing north? the reader stands south: the plate leans toward +z
        var b = MeshBuilder()
        let drop = up.depth + 0.3
        b.chamferBox(size: SIMD3(0.9, drop + 1.0, 0.8), chamfer: 0.03, surface: ArchiveProps.slateLight, transform: translation(SIMD3(0, (1.0 - drop) / 2, 0)))
        let plate = translation(SIMD3(0, 1.1, 0)) * rotationX(-0.45)                                               // top edge away from the reader
        b.chamferBox(size: SIMD3(1.5, 0.06, 1.0), chamfer: 0.02, surface: ArchiveProps.slate, transform: plate)
        b.chamferBox(size: SIMD3(1.56, 0.03, 1.06), chamfer: 0.01, surface: ArchiveProps.brass, transform: plate * translation(SIMD3(0, -0.035, 0)))
        let pins = ChainMap.pins.map { SIMD3<Float>((Float($0.x) - 0.5) * 1.35, 0.05, (Float($0.y) - 0.5) * 0.85) }
        for (k, q) in pins.enumerated() {
            if k == pins.count - 1 { b.torus(major: 0.045, minor: 0.012, segments: 14, sides: 5, surface: ArchiveProps.brass, transform: plate * translation(q)) }
            else { b.cylinder(radiusTop: 0.03, radiusBottom: 0.03, height: 0.05, segments: 10, smooth: true, surface: ArchiveProps.brass, transform: plate * translation(q)) }
            if k > 0 {
                let a = pins[k - 1], d = q - a
                b.tube(points: [plate.act(a + SIMD3(0, 0.01, 0)), plate.act(q + SIMD3(0, 0.01, 0))], radii: [0.008, 0.008], sides: 5, caps: true, surface: ArchiveProps.brass)
                _ = d
            }
        }
        scene.placed.append(Placement.record(kind: "ta_chain_map", mesh: b, transform: up.transform))
        scene.colliders.addCylinder(center: SIMD2(p.x, p.z), radius: 0.7, minY: p.y - 1, maxY: p.y + 2)
        scene.add("ti_chain_map", mesh: b.build(device: device, label: "chain map"), uniforms: ObjectUniforms(model: up.transform))
    }

    // MARK: The shadow-play tableau

    static func addTableau(_ scene: Scene, device: MTLDevice) {
        let w = ArchiveLayout.tableauWall, hw = ArchiveLayout.tableauHalfWidth
        // The wall: a stone screen facing south with a plinth course, its face dressed pale so the figures read as darker flat shapes on it.
        var wall = MeshBuilder()
        let up = Placement.upright(terrain: scene.terrain, x: w.x, z: w.z, radius: hw, yaw: 0)
        let drop = up.depth + 0.3
        wall.chamferBox(size: SIMD3(hw * 2 + 0.4, drop + wallHeight, 0.4), chamfer: 0.04, surface: Surface(color: SIMD3(0.62, 0.60, 0.55), roughness: 0.9, material: .dressed), transform: translation(SIMD3(0, (wallHeight - drop) / 2, 0)))
        wall.chamferBox(size: SIMD3(hw * 2 + 0.7, 0.2, 0.6), chamfer: 0.03, surface: ArchiveProps.slateLight, transform: translation(SIMD3(0, wallHeight + 0.1, 0)))
        scene.placed.append(Placement.record(kind: "ta_tableau", mesh: wall, transform: up.transform))
        for k in 0..<5 { scene.colliders.addCylinder(center: SIMD2(w.x + (Float(k) - 2) * hw / 2.2, w.z), radius: 1.1, minY: w.y - 2, maxY: w.y + 5) }
        scene.add(wallName, mesh: wall.build(device: device, label: "tableau wall"), uniforms: ObjectUniforms(model: up.transform))
        // The lanterns: a stone stand each (static) and the lamp (an item: builder B drives its emissive: lit = warm 2.2, dark 0), at each side in front of the wall.
        var stands = MeshBuilder()
        for (k, side) in [PageAuthor.ilse, .oren].enumerated() {
            let p = ArchiveLayout.tableauLantern[k]
            let f = Placement.upright(terrain: scene.terrain, x: p.x, z: p.z, radius: 0.4, yaw: 0)
            var one = MeshBuilder()
            let d = f.depth + 0.3
            one.chamferBox(size: SIMD3(0.55, d + 1.1, 0.55), chamfer: 0.03, surface: ArchiveProps.slateLight, transform: translation(SIMD3(0, (1.1 - d) / 2, 0)))
            one.chamferBox(size: SIMD3(0.7, 0.1, 0.7), chamfer: 0.02, surface: ArchiveProps.slate, transform: translation(SIMD3(0, 1.15, 0)))
            stands.append(one, transform: f.transform)
            scene.placed.append(Placement.record(kind: "ta_tableau_stand", mesh: one, transform: f.transform))
            scene.colliders.addCylinder(center: SIMD2(p.x, p.z), radius: 0.4, minY: p.y - 2, maxY: p.y + 2)
            var lamp = MeshBuilder()
            lamp.box(size: SIMD3(0.34, 0.46, 0.34), surface: Surface(color: SIMD3(0.9, 0.78, 0.5), roughness: 0.3, material: .emissiveGlass), transform: translation(SIMD3(0, 0.23, 0)))
            lamp.cone(radius: 0.26, height: 0.18, segments: 4, smooth: false, surface: ArchiveProps.iron, transform: translation(SIMD3(0, 0.46, 0)) * rotationY(Float.pi / 4))
            scene.add(lanternName(side), mesh: lamp.build(device: device, label: "tableau lantern"), uniforms: ObjectUniforms(model: translation(SIMD3(p.x, f.transform.columns.3.y + 1.2, p.z))))
        }
        scene.add("ta_tableau_stands", mesh: stands.build(device: device, label: "tableau stands"), uniforms: ObjectUniforms(model: matrix_identity_float4x4))
        // The light on the wall: a warm wash over its face while a version is shown (the lit lantern is its source), then the figures: one flat dark cut-out per posture and slot (shown by `updateTableau`).
        var glow = MeshBuilder()
        glow.box(size: SIMD3(hw * 2 - 0.2, wallHeight - 0.3, 0.02), surface: Surface(color: SIMD3(1.0, 0.82, 0.55), roughness: 0.5, material: .emissiveGlass), transform: translation(SIMD3(0, wallHeight / 2, 0.215)))
        var gu = ObjectUniforms(model: up.transform, tint: SIMD4(1, 1, 1, 1)); gu.emissive = SIMD4(1.0, 0.72, 0.38, 0.9)
        scene.add(glowName, mesh: glow.build(device: device, label: "tableau glow"), uniforms: gu, hidden: true)
        for posture in TableauPosture.allCases {
            for i in 0..<2 {
                scene.add(figureName(posture, i), mesh: silhouette(posture).build(device: device, label: "tableau figure"), uniforms: ObjectUniforms(model: up.transform, tint: SIMD4(1, 1, 1, 1)), hidden: true)
            }
        }
    }

    /// A flat dark cut-out of unit height standing on y = 0, centred on x = 0 (x along the wall), 2 cm thick: head, body, legs and arms as boxes and discs (no detail: a silhouette).
    static func silhouette(_ p: TableauPosture) -> MeshBuilder {
        var m = MeshBuilder()
        let ink = Surface(color: SIMD3(0.018, 0.018, 0.022), roughness: 1.0)
        func bar(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ w: Float) {                  // a limb: a thin box between two points
            let d = b - a, len = simd_length(d)
            m.box(size: SIMD3(w, len, 0.02), surface: ink, transform: translation(SIMD3((a.x + b.x) / 2, (a.y + b.y) / 2, 0)) * rotationZ(atan2(d.x, d.y) * -1))
        }
        func disc(_ c: SIMD2<Float>, _ r: Float) { m.cylinder(radiusTop: r, radiusBottom: r, height: 0.02, segments: 14, smooth: false, surface: ink, transform: translation(SIMD3(c.x, c.y, 0.01)) * rotationX(Float.pi / 2)) }
        let kneel = p == .kneeling
        let hip: Float = kneel ? 0.28 : 0.45, shoulder: Float = kneel ? 0.62 : 0.78
        disc(SIMD2(p == .turnedAway ? 0.02 : 0, shoulder + 0.13), 0.075)                                  // head
        bar(SIMD2(0, hip), SIMD2(0, shoulder), 0.2)                                                       // torso
        if kneel { bar(SIMD2(0, hip), SIMD2(0.22, 0.12), 0.1); bar(SIMD2(0.22, 0.12), SIMD2(0.22, 0.0), 0.08); bar(SIMD2(0, hip), SIMD2(-0.1, 0.0), 0.1) }
        else { bar(SIMD2(-0.05, hip), SIMD2(-0.07, 0.0), 0.09); bar(SIMD2(0.05, hip), SIMD2(0.07, 0.0), 0.09) }
        switch p {
        case .standing, .turnedAway: bar(SIMD2(-0.1, shoulder), SIMD2(-0.13, hip - 0.05), 0.06); bar(SIMD2(0.1, shoulder), SIMD2(0.13, hip - 0.05), 0.06)
        case .holdingLamp:
            bar(SIMD2(-0.1, shoulder), SIMD2(-0.13, hip - 0.05), 0.06); bar(SIMD2(0.1, shoulder), SIMD2(0.3, shoulder - 0.1), 0.06)
            m.box(size: SIMD3(0.1, 0.14, 0.02), surface: ink, transform: translation(SIMD3(0.33, shoulder - 0.2, 0)))                // the lamp
        case .reaching: bar(SIMD2(-0.1, shoulder), SIMD2(-0.13, hip - 0.05), 0.06); bar(SIMD2(0.1, shoulder), SIMD2(0.5, shoulder + 0.02), 0.06)
        case .raisingLens:
            bar(SIMD2(-0.1, shoulder), SIMD2(-0.13, hip - 0.05), 0.06); bar(SIMD2(0.1, shoulder), SIMD2(0.2, shoulder + 0.3), 0.06)
            m.cylinder(radiusTop: 0.13, radiusBottom: 0.13, height: 0.02, segments: 16, smooth: false, surface: ink, transform: translation(SIMD3(0.22, shoulder + 0.42, 0.01)) * rotationX(Float.pi / 2))      // the lens
        case .kneeling: bar(SIMD2(-0.1, shoulder), SIMD2(-0.2, hip), 0.06); bar(SIMD2(0.1, shoulder), SIMD2(0.3, hip - 0.05), 0.06)
        }
        return m
    }

    /// Called each game tick from `ArchiveProps.update`: the wall shows nothing while no lantern is lit; while a version is shown its two figures stand on the wall (their places from `ShadowTableaux.archive`,
    /// drifting a little with `ShadowTableaux.shift`), the wall glows warm, and nothing is drawn for the other version.
    static func updateTableau(_ scene: Scene, shown: PageAuthor?, time: Float) {
        for p in TableauPosture.allCases { for i in 0..<2 { scene.update(figureName(p, i)) { $0.hidden = true } } }
        guard let version = shown else { scene.update(glowName) { $0.hidden = true }; return }
        scene.update(glowName) { $0.hidden = false }
        let w = ArchiveLayout.tableauWall, hw = ArchiveLayout.tableauHalfWidth
        let base = Placement.upright(terrain: scene.terrain, x: w.x, z: w.z, radius: hw, yaw: 0).transform.columns.3.y
        for (i, f) in ShadowTableaux.archive.figures(version).enumerated() where i < 2 {
            let x = w.x + (f.x - 0.5) * (hw * 2 - 0.8) + 0.12 * ShadowTableaux.shift(time)
            let h = f.height * (wallHeight - 0.4) / 1.0
            scene.update(figureName(f.posture, i)) { $0.hidden = false; $0.uniforms.model = translation(SIMD3(x, base + 0.15, w.z + 0.23)) * scaling(SIMD3(h, h, 1)) }
        }
    }

    // MARK: The tools lying in the world

    static func addFinds(_ scene: Scene, device: MTLDevice) {
        // The tuning fork (`ti_find_fork`): a brass fork on a small slate stand, laid on a ledger-stack's end plinth; the lens (`ti_find_lens`): a glass disc in a brass ring on a stone block. Neither glows.
        func stand(at p: SIMD3<Float>, build: (inout MeshBuilder) -> Void, name: String, kind: String) {
            let up = Placement.upright(terrain: scene.terrain, x: p.x, z: p.z, radius: 0.5, yaw: Float(p.x))
            var b = MeshBuilder()
            let d = up.depth + 0.3
            b.chamferBox(size: SIMD3(0.7, d + 0.7, 0.5), chamfer: 0.03, surface: ArchiveProps.slateLight, transform: translation(SIMD3(0, (0.7 - d) / 2, 0)))
            build(&b)
            scene.placed.append(Placement.record(kind: kind, mesh: b, transform: up.transform))
            scene.colliders.addCylinder(center: SIMD2(p.x, p.z), radius: 0.4, minY: p.y - 2, maxY: p.y + 2)
            scene.add(name, mesh: b.build(device: device, label: name), uniforms: ObjectUniforms(model: up.transform))
        }
        stand(at: ArchiveLayout.findFork, build: { b in
            let y: Float = 0.76
            b.cylinder(radiusTop: 0.012, radiusBottom: 0.014, height: 0.16, segments: 8, smooth: true, surface: ArchiveProps.brass, transform: translation(SIMD3(0, y, 0)))
            for sx: Float in [-1, 1] { b.cylinder(radiusTop: 0.011, radiusBottom: 0.011, height: 0.26, segments: 8, smooth: true, surface: ArchiveProps.brass, transform: translation(SIMD3(sx * 0.03, y + 0.16, 0))) }
            b.torus(major: 0.03, minor: 0.011, segments: 12, sides: 6, surface: ArchiveProps.brass, transform: translation(SIMD3(0, y + 0.16, 0)) * rotationZ(Float.pi / 2) * rotationX(Float.pi / 2))
        }, name: "ti_find_fork", kind: "ta_find")
        stand(at: ArchiveLayout.findLens, build: { b in
            b.torus(major: 0.2, minor: 0.025, segments: 24, sides: 6, surface: ArchiveProps.brass, transform: translation(SIMD3(0, 0.95, 0)) * rotationX(Float.pi / 2 - 0.25))
            b.cylinder(radiusTop: 0.19, radiusBottom: 0.19, height: 0.02, segments: 24, smooth: false, surface: Surface(color: SIMD3(0.8, 0.92, 1.0), roughness: 0.05, material: .emissiveGlass), transform: translation(SIMD3(0, 0.95, 0)) * rotationX(-0.25))
            b.cylinder(radiusTop: 0.03, radiusBottom: 0.04, height: 0.3, segments: 8, smooth: true, surface: ArchiveProps.brass, transform: translation(SIMD3(0, 0.7, 0)))
        }, name: "ti_find_lens", kind: "ta_find")
    }

    // MARK: The Great Ledger gallery

    /// The court's stone lining (a wall round the pit with the ramp's opening on the west, a coping), its slate floor, and its water: the water is an item drawn by the water pass (see `DrawItem.isWaterBody`).
    static func addGallery(_ scene: Scene, device: MTLDevice) {
        let g = ArchiveTerrain.gallery
        let c = g.centre, hx = g.half.x, hz = g.half.y
        let top = ArchiveTerrain.levels[2], floorY = galleryFloor
        var b = MeshBuilder()
        let lining = Surface(color: SIMD3(0.34, 0.37, 0.37), roughness: 0.9, material: .masonry)
        let wallH = top - floorY + 0.5
        // Walls are axis-aligned boxes (no rotation: the masonry mapping streaks on a box turned about Y), each with a row of collider posts so the lining holds the player out of the court.
        func wall(from a: SIMD2<Float>, to bb: SIMD2<Float>) {
            let d = bb - a, len = simd_length(d), mid = (a + bb) / 2
            let alongX = abs(d.x) > abs(d.y)
            let t = alongX ? SIMD3<Float>(len, wallH + 3.0, 0.7) : SIMD3<Float>(0.7, wallH + 3.0, len)
            let cap = alongX ? SIMD3<Float>(len + 0.4, 0.25, 1.0) : SIMD3<Float>(1.0, 0.25, len + 0.4)
            b.chamferBox(size: t, chamfer: 0.04, surface: lining, transform: translation(SIMD3(mid.x, floorY - 3.0 + (wallH + 3.0) / 2, mid.y)))
            b.chamferBox(size: cap, chamfer: 0.03, surface: ArchiveProps.slateLight, transform: translation(SIMD3(mid.x, floorY + wallH + 0.1, mid.y)))
            let n = Int((len / 0.8).rounded(.up))
            for k in 0...n { let q = a + d * (Float(k) / Float(n)); scene.colliders.addCylinder(center: q, radius: 0.55, minY: floorY - 3, maxY: floorY + wallH + 2) }
        }
        // North, south and east walls whole; the west wall in two pieces with a 7 m opening where the route's ramp enters (at the route's z).
        let open: Float = 3.5, ramp = ArchiveLayout.greatLedger.z
        wall(from: SIMD2(c.x - hx, c.y - hz), to: SIMD2(c.x + hx, c.y - hz)); wall(from: SIMD2(c.x - hx, c.y + hz), to: SIMD2(c.x + hx, c.y + hz)); wall(from: SIMD2(c.x + hx, c.y - hz), to: SIMD2(c.x + hx, c.y + hz))
        wall(from: SIMD2(c.x - hx, c.y - hz), to: SIMD2(c.x - hx, ramp - open)); wall(from: SIMD2(c.x - hx, ramp + open), to: SIMD2(c.x - hx, c.y + hz))
        // The floor: dark slate slabs (one dressed slab, a darker joint grid of boxes).
        b.chamferBox(size: SIMD3(hx * 2, 0.12, hz * 2), chamfer: 0.02, surface: Surface(color: SIMD3(0.20, 0.23, 0.24), roughness: 0.85, material: .slab), transform: translation(SIMD3(c.x, floorY - 0.04, c.y)))
        scene.add("ta_court", mesh: b.build(device: device, label: "gallery court"), uniforms: ObjectUniforms(model: matrix_identity_float4x4))
        // The water: a flat grid over the court at its full level; B lowers it by moving the model down (`drainDepth`); the water pass draws it as a calm pool and lifts it a little with the tide.
        var w = MeshBuilder()
        let nx = Int(hx * 2), nz = Int(hz * 2)
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
        for j in 0...nz { for i in 0...nx { pos.append(SIMD3(c.x - hx + Float(i), galleryFull, c.y - hz + Float(j))); nrm.append(SIMD3(0, 1, 0)) } }
        for j in 0..<nz { for i in 0..<nx { let a = UInt32(j * (nx + 1) + i), b2 = a + 1, c2 = a + UInt32(nx + 1), d = c2 + 1; idx.append(contentsOf: [a, c2, d, a, d, b2]) } }
        w.addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: Surface(color: SIMD3(0.5, 0.7, 0.7), roughness: 0.1), transform: matrix_identity_float4x4)
        scene.add(waterName, mesh: w.build(device: device, label: "gallery water"), uniforms: ObjectUniforms(model: matrix_identity_float4x4), refractive: true)
    }

    /// The gallery water's surface height now: its full level, lowered by the drain (B moves its model down), raised a little by the tide while it is held. For the wading limit (`Player`).
    static func waterLevel(_ scene: Scene, clock: Float) -> Float {
        let y = scene.items.first { $0.name == waterName }?.uniforms.model.columns.3.y ?? 0
        let held = max(0, 1 + y / drainDepth)
        return galleryFull + y + galleryTideRise(clock: clock) * held
    }
}

extension float4x4 {
    /// The point `p` transformed by this matrix (w = 1).
    func act(_ p: SIMD3<Float>) -> SIMD3<Float> { let q = self * SIMD4(p, 1); return SIMD3(q.x, q.y, q.z) }
}
