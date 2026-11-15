import Metal
import simd

/// S05.2 (builder A): Oren's site in the Tide Archive, the exterior half of the sibling split (docs/plans/S05-divergent-routes.md section 3, puzzles O1 and O2): the dome's brass tide-ORRERY on its plinth in
/// front of the dome (O1: three arms that sweep over one tide cycle and a brass collar that stops one), the three WINDOWS in the dome's drum that light when an arm is stopped at the right moment, and the
/// PRISM'S INPUTS (O2: a coloured component exists only while its window is lit). Builder B owns every rule; this file owns what is seen. The calls B makes:
///   - `Orrery.hold(scene, k, at:)`                 stop arm k where it is at tide clock `at` (nil lets it run again); the arms otherwise follow the clock every tick (`ArchiveProps.update`)
///   - `Orrery.setCollar(scene, detent:)`            turn the collar to detent n of `Orrery.collarDetents`
///   - `DomeWindows.set(scene, k, lit:)`            window k dark (0) ... lit (1), colour of its gate (tide blue, wind green, stone orange)
///   - `PrismInputs.set(scene, lit: [Bool])`        the prism's three components exist only for the lit windows (the others stay dark in the chamber); default all three, as before S05
/// What an arm shows is a PURE FUNCTION of the tide clock (`Orrery.armAngle(k, clock:)`, `Orrery.alignmentClock(k)`, `Orrery.aligned(k, clock:)`): B's logic and the selftest read the same numbers the frame draws.
/// All positions come from `ArchiveLayout` (Layout.swift). Palette as the rest of the Archive: wet slate, brass, and the three gate colours.
enum OrenSite {
    static func populate(_ scene: Scene, device: MTLDevice) {
        Orrery.add(to: scene, device: device)
        DomeWindows.add(to: scene, device: device)
        DormantViews.add(to: scene, device: device)
        Vantage.add(to: scene, device: device)       // S05.4 (A5): the two vantage stations
    }
}

// MARK: - The orrery

enum Orrery {
    static let armCount = 3
    static func armName(_ k: Int) -> String { "ta_orrery_arm_\(k)" }
    static let frameName = "ta_orrery_frame", collarName = "ta_orrery_collar"
    static var allNames: [String] { [frameName, collarName] + (0..<armCount).map(armName) }

    /// How long each arm is (m), at what height above the plinth's floor it turns, and how far the plinth stands (radius). The longest arm is the highest.
    static let armLength: [Float] = [0.75, 1.10, 1.45]
    static let armHeight: [Float] = [1.30, 1.42, 1.54]
    static let plinthRadius: Float = 1.55, dialY: Float = 1.0, collarY: Float = 1.12
    /// The collar's notches: one stop every `2 pi / collarDetents` (Q66: six, a default; the beam rhythm of Varrow is meant to set it, builder B's call).
    static let collarDetents = 6
    /// How close to the window's bearing an arm counts as lined up (radians, about 6 degrees: at one turn per tide cycle that is about 3 s either side).
    static let alignTolerance: Float = 0.105

    /// The arm's pivot in the world (the hub), and where the collar can be touched.
    static func pivot(_ k: Int) -> SIMD3<Float> { ArchiveLayout.orrery + SIMD3(0, armHeight[min(max(k, 0), 2)], 0) }
    static var collarPoint: SIMD3<Float> { ArchiveLayout.orrery + SIMD3(0, collarY, 0) }

    // MARK: Pure functions of the tide clock

    /// The compass bearing (radians, atan2(z, x): x east, z south) from the orrery's hub to dome window k: the direction arm k points in when it "lines up with" its window.
    static func bearing(_ k: Int) -> Float {
        let w = ArchiveLayout.domeWindowXZ(k), o = ArchiveLayout.orrery
        return atan2(w.y - o.z, w.x - o.x)
    }
    /// The clock (0 ..< period) at which arm k lines up with its window: when the FALLING tide passes the level gate k answers at (`IlseTones.matchLevel`), so the three alignments come in the stones' order,
    /// tide, wind, stone, as the water drops. (`Tide.level` is 0.5 - 0.5 cos: the rising limb reaches level L at P/(2 pi) acos(1 - 2L), the falling one at P minus that.)
    static func alignmentClock(_ k: Int) -> Float {
        let L = min(max(IlseTones.matchLevel(k), 0.001), 0.999)
        return Tide.period - Tide.period / (2 * .pi) * acos(1 - 2 * L)
    }
    /// Arm k's angle at tide clock `clock`: one full turn (clockwise seen from above) per cycle, lined up with its window at `alignmentClock(k)`. Pure: the same clock always gives the same angle.
    static func armAngle(_ k: Int, clock: Float) -> Float {
        let turns = (clock - alignmentClock(k)) / Tide.period
        return bearing(k) + 2 * .pi * (turns - floor(turns))
    }
    /// Signed shortest difference between two angles (radians, -pi ... pi).
    static func wrap(_ a: Float) -> Float { var d = a.truncatingRemainder(dividingBy: 2 * .pi); if d > .pi { d -= 2 * .pi }; if d < -.pi { d += 2 * .pi }; return d }
    /// True when arm k, at that clock, points at its window to within `tolerance`.
    /// A5 (Q92): the brass TICK as arm k passes its window: true if the arm's alignment moment (`alignmentClock(k)` plus whole cycles) falls in (t0, t1]. Pure, so the tick is a number a test can check
    /// (one per arm per cycle) and the game only has to ask it each step. A held arm (`hold`) is not moving, so `ticks` skips it.
    static func tickCrossed(_ k: Int, from t0: Float, to t1: Float) -> Bool {
        let a = alignmentClock(k), P = Tide.period
        return floor((t1 - a) / P) > floor((t0 - a) / P)
    }
    /// The arms that tick between two clock times (nil-held ones only).
    static func ticks(_ scene: Scene, from t0: Float, to t1: Float) -> [Int] {
        (0..<armCount).filter { scene.archive.armStops[$0] == nil && tickCrossed($0, from: t0, to: t1) }
    }
    /// How loud the tick is at `distance` m from the orrery: full inside 8 m, gone by 40 m (it is a small brass sound: heard from the dome's pad, not from the stacks).
    static func tickGain(distance d: Float) -> Float { let t = min(max((40 - d) / 32, 0), 1); return t * t * (3 - 2 * t) }
    static func aligned(_ k: Int, clock: Float, tolerance: Float = alignTolerance) -> Bool { abs(wrap(armAngle(k, clock: clock) - bearing(k))) <= tolerance }
    /// The tip of arm k in the world at that clock (what a player aims their eye at).
    static func armTip(_ k: Int, clock: Float) -> SIMD3<Float> {
        let a = armAngle(k, clock: clock)
        return pivot(k) + SIMD3(cos(a), 0, sin(a)) * armLength[min(max(k, 0), 2)]
    }

    // MARK: Driving it

    /// The arm's model at an angle: pivot, turned about the vertical so its +x runs along (cos a, sin a).
    static func armModel(_ k: Int, angle: Float) -> float4x4 { translation(pivot(k)) * rotationY(-angle) }
    static func collarModel(detent: Int) -> float4x4 { translation(collarPoint) * rotationY(-Float(detent) * 2 * .pi / Float(collarDetents)) }

    /// Stops arm k where it stands at tide clock `at` (it stays there, every tick, until `hold(scene, k, at: nil)`). Unknown k is ignored.
    static func hold(_ scene: Scene, _ k: Int, at clock: Float?) {
        guard (0..<armCount).contains(k) else { return }
        scene.archive.armStops[k] = clock
        update(scene, clock: scene.archive.lastTime ?? 0)
    }
    /// Turns the collar to detent `n` (any integer; it wraps).
    static func setCollar(_ scene: Scene, detent: Int) {
        scene.archive.collarDetent = detent
        scene.update(collarName) { $0.uniforms.model = collarModel(detent: detent) }
    }
    /// Draws the arms for tide clock `clock`, each at its held clock if it is stopped. A lined-up arm glows a little more (its bead says "here"). Called every tick by `ArchiveProps.update`.
    static func update(_ scene: Scene, clock: Float) {
        let st = scene.archive
        for k in 0..<armCount {
            let c = st.armStops[k] ?? clock
            let hot = aligned(k, clock: c)
            let m = armModel(k, angle: armAngle(k, clock: c))
            let col = ArchiveProps.beamColours[k]
            scene.update(armName(k)) { $0.uniforms.model = m; $0.uniforms.emissive = SIMD4(col, hot ? 0.8 : 0.18) }
        }
    }

    // MARK: Geometry

    static func add(to scene: Scene, device: MTLDevice) {
        let o = ArchiveLayout.orrery
        let brass = ArchiveProps.brass, iron = ArchiveProps.iron
        var b = MeshBuilder()
        // The plinth: a fluted stone drum on a stepped foot, a brass-rimmed dial plate with three tracks (one under each arm's tip) and a coloured stop at each window's bearing.
        let r = plinthRadius
        let profile: [SIMD2<Float>] = [SIMD2(r + 0.30, -0.6), SIMD2(r + 0.30, 0.15), SIMD2(r + 0.12, 0.2), SIMD2(r + 0.12, 0.32), SIMD2(r - 0.05, 0.36), SIMD2(r - 0.1, dialY - 0.16), SIMD2(r + 0.04, dialY - 0.14), SIMD2(r + 0.04, dialY)]
        b.lathe(profile: profile, segments: 32, smooth: true, surface: ArchiveProps.slate)
        b.cylinder(radiusTop: r, radiusBottom: r, height: 0.03, segments: 40, smooth: true, surface: brass, transform: translation(SIMD3(0, dialY + 0.015, 0)))
        for k in 0..<armCount {
            b.torus(major: armLength[k], minor: 0.014, segments: 40, sides: 5, surface: iron, transform: translation(SIMD3(0, dialY + 0.035, 0)))
            let a = bearing(k)
            let stop = Surface(color: ArchiveProps.beamColours[k] * 0.9, roughness: 0.5, material: .paint)
            b.chamferBox(size: SIMD3(0.20, 0.11, 0.13), chamfer: 0.02, surface: brass, transform: rotationY(-a) * translation(SIMD3(r - 0.12, dialY + 0.07, 0)))
            b.box(size: SIMD3(0.12, 0.10, 0.09), surface: stop, transform: rotationY(-a) * translation(SIMD3(r - 0.12, dialY + 0.115, 0)))
        }
        for n in 0..<48 { b.box(size: SIMD3(0.07, 0.012, 0.014), surface: iron, transform: rotationY(Float(n) / 48 * 2 * .pi) * translation(SIMD3(r - 0.08, dialY + 0.035, 0))) }
        // The stem the arms turn on (a brass column) with three brass spindle collars and a cap; the collar below turns about it.
        b.cylinder(radiusTop: 0.07, radiusBottom: 0.09, height: armHeight[2] + 0.2 - dialY, segments: 14, smooth: true, surface: brass, transform: translation(SIMD3(0, dialY, 0)))
        for k in 0..<armCount { b.cylinder(radiusTop: 0.11, radiusBottom: 0.11, height: 0.05, segments: 14, smooth: true, surface: brass, transform: translation(SIMD3(0, armHeight[k] - 0.05, 0))) }
        b.sphere(radius: 0.13, segments: 14, smooth: true, surface: brass, transform: translation(SIMD3(0, armHeight[2] + 0.22, 0)))
        scene.add(frameName, mesh: b.build(device: device, label: "orrery frame"), uniforms: ObjectUniforms(model: translation(o)))
        // The arms: a bar from the hub to its length, a bead of the gate's colour on the end, a stub counterweight behind; the bead and bar glow with the arm's colour (`update`).
        for k in 0..<armCount {
            var a = MeshBuilder()
            let L = armLength[k]
            let col = ArchiveProps.beamColours[k]
            a.box(size: SIMD3(L, 0.05, 0.05), surface: brass, transform: translation(SIMD3(L / 2, 0, 0)))
            a.sphere(radius: 0.10, segments: 12, smooth: true, surface: Surface(color: col * 0.55, roughness: 0.3, material: .emissiveGlass), transform: translation(SIMD3(L, 0.0, 0)))
            a.box(size: SIMD3(0.16, 0.05, 0.05), surface: brass, transform: translation(SIMD3(-0.12, 0, 0)))
            a.sphere(radius: 0.05, segments: 10, smooth: true, surface: brass, transform: translation(SIMD3(-0.22, 0, 0)))
            scene.add(armName(k), mesh: a.build(device: device, label: "orrery arm \(k)"), uniforms: ObjectUniforms(model: armModel(k, angle: bearing(k)), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(col, 0.18)))
        }
        // The collar: a heavy brass ring round the stem, six notches and a lever with a knob, turned by hand (`setCollar`).
        var c = MeshBuilder()
        c.torus(major: 0.2, minor: 0.065, segments: 24, sides: 8, surface: brass)
        for n in 0..<collarDetents { c.box(size: SIMD3(0.09, 0.07, 0.07), surface: iron, transform: rotationY(Float(n) / Float(collarDetents) * 2 * .pi) * translation(SIMD3(0.27, 0, 0))) }
        c.box(size: SIMD3(0.42, 0.045, 0.045), surface: brass, transform: translation(SIMD3(0.45, 0, 0)))
        c.sphere(radius: 0.075, segments: 12, smooth: true, surface: brass, transform: translation(SIMD3(0.68, 0, 0)))
        scene.add(collarName, mesh: c.build(device: device, label: "orrery collar"), uniforms: ObjectUniforms(model: collarModel(detent: 0)))
        scene.colliders.addCylinder(center: SIMD2(o.x, o.z), radius: r + 0.25, minY: o.y - 1, maxY: o.y + 2.6)
    }
}

// MARK: - The dome's windows

enum DomeWindows {
    static let count = 3
    static func name(_ k: Int) -> String { "ta_dome_window_\(k)" }
    static let bezelsName = "ta_dome_bezels"
    static var allNames: [String] { [bezelsName] + (0..<count).map(name) }
    static let radius: Float = 0.42, y: Float = 4.03
    /// The glass is dark brass-glass until lit; lit it takes the gate's colour (tide blue, wind green, stone orange) and throws a little light on the stone round it.
    static let darkTint = SIMD4<Float>(0.05, 0.07, 0.08, 1)
    static let colours: [SIMD3<Float>] = [SIMD3(0.10, 0.45, 1.0), SIMD3(0.40, 0.95, 0.22), SIMD3(1.0, 0.38, 0.08)]
    static func litLook(_ k: Int) -> SIMD4<Float> { SIMD4(colours[k], 2.4) }

    /// The drum's frame: the same footing the dome itself stands on (`ArchiveProps.addDome`).
    static func frame(_ scene: Scene) -> float4x4 {
        let c = ArchiveLayout.dome
        return Placement.upright(terrain: scene.terrain, x: c.x, z: c.z, radius: ArchiveLayout.domeDrum, yaw: 0).transform
    }
    static func model(_ scene: Scene, _ k: Int) -> float4x4 {
        let b = ArchiveLayout.domeWindowBearing[k], r = ArchiveLayout.domeDrum + 0.03
        return frame(scene) * translation(SIMD3(sin(b) * r, y, cos(b) * r)) * rotationY(b) * rotationX(.pi / 2)
    }
    /// Where window k's glass is in the world (what a player aims at; the frame's centre).
    static func point(_ scene: Scene, _ k: Int) -> SIMD3<Float> { let m = model(scene, k) * SIMD4(0, 0, 0, 1); return SIMD3(m.x, m.y, m.z) }

    /// Lights window k (the single call builder B makes): `lit` 0 dark ... 1 fully lit. Unknown k is ignored.
    static func set(_ scene: Scene, _ k: Int, lit: Float) {
        guard (0..<count).contains(k) else { return }
        let t = min(max(lit, 0), 1)
        scene.archive.windowLit[k] = t
        DormantViews.setSpire(scene, lit: scene.archive.windowLit.reduce(0, +) / Float(count))          // the spire beside the dome glows with the windows (seen from the west quay)
        let look = litLook(k)
        scene.update(name(k)) {
            $0.uniforms.emissive = SIMD4(look.x, look.y, look.z, look.w * t)
            $0.uniforms.tint = darkTint + (SIMD4(colours[k] * 0.4, 1) - darkTint) * t
        }
    }

    static func add(to scene: Scene, device: MTLDevice) {
        var bz = MeshBuilder()
        for k in 0..<count {
            let b = ArchiveLayout.domeWindowBearing[k], r = ArchiveLayout.domeDrum - 0.02
            let m = translation(SIMD3(sin(b) * r, y, cos(b) * r)) * rotationY(b) * rotationX(.pi / 2)
            bz.torus(major: radius + 0.05, minor: 0.07, segments: 24, sides: 6, surface: ArchiveProps.brass, transform: m)
            bz.box(size: SIMD3(0.12, radius * 2 + 0.16, 0.16), surface: ArchiveProps.iron, transform: translation(SIMD3(sin(b) * (r + 0.02), y, cos(b) * (r + 0.02))) * rotationY(b))
            bz.box(size: SIMD3(radius * 2 + 0.16, 0.12, 0.16), surface: ArchiveProps.iron, transform: translation(SIMD3(sin(b) * (r + 0.02), y, cos(b) * (r + 0.02))) * rotationY(b))
        }
        scene.add(bezelsName, mesh: bz.build(device: device, label: "dome window bezels"), uniforms: ObjectUniforms(model: frame(scene)))
        var g = MeshBuilder()
        g.cylinder(radiusTop: radius, radiusBottom: radius, height: 0.05, segments: 24, smooth: true, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.2, material: .emissiveGlass))
        let glass = g.build(device: device, label: "dome window glass")
        for k in 0..<count { scene.add(name(k), mesh: glass, uniforms: ObjectUniforms(model: model(scene, k), tint: darkTint, emissive: SIMD4(0, 0, 0, 0))) }
    }
}

// MARK: - The prism's inputs

enum PrismInputs {
    /// Sets which of the prism's three components exist (O2: the lit windows of O1 decide). A component without its window is a dim, thin ghost in the chamber, its mark on the wall dark; the white beam coming in
    /// is as strong as the windows lit (3 of 3 is exactly the pre-S05 look). The ring and the resting rule are unchanged (`ArchiveProps.updatePrism`).
    static func set(_ scene: Scene, lit: [Bool]) {
        scene.archive.prismLit = (0..<3).map { $0 < lit.count ? lit[$0] : false }
        ArchiveProps.updatePrism(scene, ringAngle: scene.archive.lastRing ?? TideArchivePuzzle.initialRing)
    }
    /// The dim strength of a component whose window is dark.
    static let ghostStrength: Float = 0.45
}

// MARK: - The dormant models seen from the other route's quay (S05.4, start)

enum DormantViews {
    static let mastName = "ta_bell_mast", mastLampName = "ta_bell_mast_lamp", spireName = "ta_prism_spire"
    static let mastHeight: Float = 11, spireHeight: Float = 18
    /// A dull dormant lamp (it does not glow until builder B lights it) and the spire's glow at full (all three components).
    static let dormantLamp = SIMD4<Float>(0.42, 0.34, 0.22, 0.3), warmLamp = SIMD4<Float>(1.0, 0.30, 0.03, 1.6)
    static let spireDark = SIMD4<Float>(0.05, 0.07, 0.09, 1), spireGlow = SIMD4<Float>(0.75, 0.88, 1.0, 2.2)

    /// Lights the mast's lantern (0 dormant ... 1 warm): Ilse's site answers as her puzzle is solved. Builder B's call; nothing here changes the corridor.
    static func setMast(_ scene: Scene, lit: Float) {
        let t = min(max(lit, 0), 1)
        scene.update(mastLampName) { $0.uniforms.emissive = dormantLamp + (warmLamp - dormantLamp) * t }
    }
    /// Lights the spire (0 dark ... 1 glowing). `DomeWindows.set` calls this with the share of lit windows.
    static func setSpire(_ scene: Scene, lit: Float) {
        let t = min(max(lit, 0), 1)
        scene.update(spireName) { $0.uniforms.emissive = SIMD4(spireGlow.x, spireGlow.y, spireGlow.z, spireGlow.w * t); $0.uniforms.tint = spireDark + (SIMD4(0.45, 0.5, 0.55, 1) - spireDark) * t }
    }

    static func add(to scene: Scene, device: MTLDevice) {
        let brass = ArchiveProps.brass, iron = ArchiveProps.iron, oak = ArchiveProps.oak
        // The bell mast: four iron legs leaning in, three cross-braces, a brass platform with a rail, a bell hung in a frame, a lantern on the top (its own item: it is the part that can glow).
        let m = ArchiveLayout.bellMast
        var b = MeshBuilder()
        let H = mastHeight
        for sx: Float in [-1, 1] { for sz: Float in [-1, 1] {
            b.tube(points: [SIMD3(sx * 1.2, -0.5, sz * 1.2), SIMD3(sx * 0.55, H, sz * 0.55)], radii: [0.09, 0.07], sides: 6, caps: true, surface: iron)
        } }
        for y in [Float(2.6), 5.2, 7.8] {
            let w = 1.2 - (1.2 - 0.55) * (y / H)
            for sz: Float in [-1, 1] { b.box(size: SIMD3(w * 2, 0.07, 0.07), surface: iron, transform: translation(SIMD3(0, y, sz * w))) }
            for sx: Float in [-1, 1] { b.box(size: SIMD3(0.07, 0.07, w * 2), surface: iron, transform: translation(SIMD3(sx * w, y, 0))) }
        }
        b.chamferBox(size: SIMD3(1.5, 0.16, 1.5), chamfer: 0.03, surface: oak, transform: translation(SIMD3(0, H, 0)))
        for sx: Float in [-1, 1] { b.box(size: SIMD3(0.07, 1.2, 0.07), surface: brass, transform: translation(SIMD3(sx * 0.5, H + 0.7, 0))) }
        b.box(size: SIMD3(1.1, 0.07, 0.07), surface: brass, transform: translation(SIMD3(0, H + 1.3, 0)))
        let bellProfile: [SIMD2<Float>] = [SIMD2(0.0, -0.02), SIMD2(0.12, -0.08), SIMD2(0.22, -0.28), SIMD2(0.3, -0.52), SIMD2(0.4, -0.78), SIMD2(0.52, -0.95), SIMD2(0.47, -0.98), SIMD2(0.0, -0.8)]
        b.lathe(profile: bellProfile, segments: 20, smooth: true, surface: Surface(color: SIMD3(0.55, 0.40, 0.18), roughness: 0.4, material: .paleMetal), transform: translation(SIMD3(0, H + 1.28, 0)))
        scene.add(mastName, mesh: b.build(device: device, label: "bell mast"), uniforms: ObjectUniforms(model: translation(m)))
        var l = MeshBuilder()
        l.sphere(radius: 0.28, segments: 14, smooth: true, surface: Surface(color: SIMD3(0.17, 0.14, 0.10), roughness: 0.25, material: .emissiveGlass), transform: translation(SIMD3(0, H + 1.7, 0)))
        scene.add(mastLampName, mesh: l.build(device: device, label: "bell mast lamp"), uniforms: ObjectUniforms(model: translation(m), tint: SIMD4(0.17, 0.14, 0.10, 1), emissive: dormantLamp))
        scene.colliders.addCylinder(center: SIMD2(m.x, m.z), radius: 1.5, minY: m.y - 1, maxY: m.y + H + 3)
        // The spire: a brass three-step plinth and a tall triangular pillar of dark glass with a brass cap, beside the dome.
        let p = ArchiveLayout.prismSpire
        var f = MeshBuilder()
        for (i, r) in [Float(1.8), 1.4, 1.1].enumerated() { f.chamferBox(size: SIMD3(r * 2, 0.4, r * 2), chamfer: 0.04, surface: ArchiveProps.slateLight, transform: translation(SIMD3(0, Float(i) * 0.4 - 0.2, 0))) }
        f.cone(radius: 0.75, height: 1.1, segments: 3, smooth: false, surface: brass, transform: translation(SIMD3(0, 1.0 + spireHeight, 0)))
        scene.add(spireName + "_base", mesh: f.build(device: device, label: "prism spire base"), uniforms: ObjectUniforms(model: translation(p)))
        var g = MeshBuilder()
        g.cylinder(radiusTop: 0.5, radiusBottom: 1.1, height: spireHeight, segments: 3, smooth: false, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.15, material: .emissiveGlass), transform: translation(SIMD3(0, 1.0, 0)))
        scene.add(spireName, mesh: g.build(device: device, label: "prism spire"), uniforms: ObjectUniforms(model: translation(p), tint: spireDark, emissive: SIMD4(0, 0, 0, 0)))
        scene.colliders.addCylinder(center: SIMD2(p.x, p.z), radius: 1.9, minY: p.y - 1, maxY: p.y + spireHeight + 2)
    }
}
