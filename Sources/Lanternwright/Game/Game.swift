import Foundation
import simd

/// Owns the player, the puzzle and the simulation clock, and advances them at a fixed rate independent of the
/// display's frame rate.
final class Game {
    static let tick: Float = 1.0 / 120.0

    /// Every world's scene. The player is in exactly one of them (`world`).
    let scenes: [WorldKind: Scene]
    private(set) var world: WorldKind = .varrow
    var scene: Scene { scenes[world]! }
    var player: Player
    let state = PuzzleState()
    let animator = Animator()
    private(set) var puzzle: LighthousePuzzle!
    private(set) var glass: GlassWoodLogic?
    /// Every world's puzzle, in restore order. Saving, restoring, click routing and visuals all go through this list.
    private(set) var puzzles: [WorldPuzzle] = []
    private var worldInteractables: [WorldKind: [Interactable]] = [:]
    var interactables: [Interactable] { worldInteractables[world] ?? [] }
    private(set) var hovered: Interactable?
    var journal = JournalState()
    /// 0...1 white fade used when stepping through a lens to another world.
    private(set) var whiteout: Float = 0
    /// Text shown over the white (nil = none).
    private(set) var whiteCaption: String?
    /// True while a world change is in progress: the player stands still and nothing is hoverable.
    private(set) var isTraveling = false
    /// A line of text shown over the world for a few seconds (nil = none).
    private(set) var banner: String?
    private var bannerSerial = 0

    private var accumulator: Float = 0
    private var lastTime: Double?
    private(set) var time: Float = 0
    private var pending: [GameEvent] = []
    private var doorTries = 0
    private var lastDoorTry: Float = -100
    /// Footfalls since start; audio compares against the last value it saw.
    private(set) var footfalls = 0
    private(set) var lastFootWasRun = false

    init(scenes: [WorldKind: Scene]) {
        precondition(scenes[.varrow] != nil, "the game always has Varrow")
        self.scenes = scenes
        player = Player(position: Layout.dockEnd, yaw: Layout.spawnYaw)
        puzzle = LighthousePuzzle(scene: scenes[.varrow]!, state: state, animator: animator) { [weak self] in self?.pending.append($0) }
        if let gw = scenes[.glassWood] {
            glass = GlassWoodLogic(scene: gw, state: state, animator: animator, emit: { [weak self] in self?.pending.append($0) },
                                   revealPage: { [weak self] n, announce in self?.revealPage(n, announce: announce) },
                                   showBanner: { [weak self] t in self?.showBanner(t) },
                                   setEnabled: { [weak self] id, on in self?.setInteractable(id, enabled: on) })
        }
        puzzles = [puzzle] + (glass.map { [$0] } ?? [])
        buildInteractables()
    }

    /// Show text over the world; it stays for a time proportional to its length, unless replaced by a newer line.
    func showBanner(_ text: String) {
        banner = text
        bannerSerial += 1
        let serial = bannerSerial
        animator.after(3.5 + Float(text.count) * 0.055) { [weak self] in
            if self?.bannerSerial == serial { self?.banner = nil }
        }
    }

    /// Pages that are standing in their world right now (1-4 on Varrow, 5 at the Glass Wood's arrival, 6-8 once their puzzle has revealed them).
    private(set) var shownPages: Set<Int> = [1, 2, 3, 4, 5]
    /// Pages that appeared while the player was playing (not from the start) and have not been collected yet: the HUD marks the journal for these.
    private(set) var announcedPages = Set<Int>()
    var pageWaiting: Bool { !announcedPages.isEmpty }

    /// Make a hidden journal page visible and readable (puzzles call this as a reward). F02 P0: when it appears live it is announced: a soft rising chime
    /// and the line "A page has come loose."
    private func revealPage(_ n: Int, announce: Bool) {
        guard !state.has("page_\(n)") else { return }
        shownPages.insert(n)
        scenes[.glassWood]?.update("page_\(n)") { $0.hidden = false }
        for k in 0..<2 { scenes[.glassWood]?.update("page_mote_\(n)_\(k)") { $0.hidden = false } }
        scenes[.glassWood]?.update("page_beacon_\(n)") { $0.hidden = false }
        setInteractable("page_\(n)", enabled: true)
        if announce {
            announcedPages.insert(n)
            pending.append(.chime(.pageAppears))
            showBanner("A page has come loose.")
        }
    }

    /// Varrow only (most tests need nothing else).
    convenience init(scene: Scene) { self.init(scenes: [.varrow: scene]) }

    /// Home-island atmosphere that answers to what you have done: the mist thins once you have been through the lens, and
    /// a lighthouse beam fades in once the lamp is lit. Both ease slowly (the renderer reads them).
    private(set) var mistScale: Float = 1
    private(set) var beamAmount: Float = 0
    static let thinMist: Float = 0.45
    private var atmosphereTargets: (mist: Float, beam: Float) { (state.has("lensTouched") ? Game.thinMist : 1, state.has("lighthouseLit") ? 1 : 0) }
    /// Jump the slow atmosphere easing to where it is heading (loading a save, `--state`).
    func settleAtmosphere() { (mistScale, beamAmount) = atmosphereTargets }
    /// Auto-run: while on, moving means running (R toggles). Plus the one-time hint for players who never find Shift.
    private(set) var autoRun = false
    private var walkedSeconds: Float = 0
    private var hasRun = false
    /// A restored save that already showed the hint counts as having been told (the hint never repeats).
    func markHintSeen() { hasRun = true }
    static let runHintAfter: Float = 45
    static let ownFlags = ["lensTouched", "hint_run"]
    /// 0...1: how far the "look closer" zoom has eased in (right mouse button or Z).
    private(set) var zoomAmount: Float = 0
    /// 0...1: how far into a run the player is (eased), which widens the view a little: speed you can see.
    private(set) var runBlend: Float = 0
    static let runFovBoost: Float = 0.10                 // radians at a full run (about 5.7 degrees)
    var camera: Camera { var c = player.camera; c.fovY = LookCloser.fov(zoom: zoomAmount) + Game.runFovBoost * runBlend * (1 - zoomAmount); return c }

    /// The ground material under the player's feet (drives footstep sounds).
    /// The weighted version (for the footstep voice), and the dock plank under the foot.
    var surfaceMix: (mix: StepMix, pebble: Float) { scene.surfaceMix(x: player.position.x, z: player.position.z) }
    var currentPlank: Int { scene.plankIndex(x: player.position.x, z: player.position.z) }
    /// 0...1: how hollow the dock sounds under the feet (from the clearance under the planks).
    var currentHollowness: Float { scene.hollowness(x: player.position.x, z: player.position.z) }
    var currentSurface: SurfaceKind { scene.surface(x: player.position.x, z: player.position.z) }

    /// Events since the last call (audio and UI consume these).
    func drainEvents() -> [GameEvent] { defer { pending = [] }; return pending }

    // MARK: Interactables

    private func buildInteractables() {
        let varrow = scenes[.varrow]!
        var list: [Interactable] = []
        for id in StoneID.allCases {
            let p = id.position
            list.append(Interactable(id: "stone_\(id.name)",
                                     min: SIMD3(p.x - 0.95, p.y, p.z - 0.95), max: SIMD3(p.x + 0.95, p.y + StoneID.height + 1.4, p.z + 0.95),
                                     prompt: "Touch the stone"))
        }
        for n in 1...4 {
            let p = PuzzleProps.pagePosition(n, terrain: varrow.terrain)
            list.append(Interactable(id: "page_\(n)", min: p - SIMD3(0.5, 0.3, 0.5), max: p + SIMD3(0.5, 0.4, 0.5),
                                     prompt: "Read the page", reach: 3.4))
        }
        // F01 W4.2 phase 1: the lighthouse door can be tried. It is locked (what is behind it is the user's choice: see INSPECT.md).
        let lh = Layout.lighthouse, doorZ = lh.z + 4.25
        list.append(Interactable(id: "lh_door", min: SIMD3(lh.x - 0.65, lh.y, doorZ - 0.35), max: SIMD3(lh.x + 0.65, lh.y + 2.4, doorZ + 0.45), prompt: "Try the door", reach: 4))
        let l = PuzzleProps.lensRestPosition
        list.append(Interactable(id: "lens", min: l - SIMD3(1.3, 1.3, 1.3), max: l + SIMD3(1.3, 1.3, 1.3), prompt: "Touch the lens", reach: 5))
        worldInteractables[.varrow] = list

        if scenes[.glassWood] != nil {
            let r = GlassLayout.returnLens
            var gwList = [Interactable(id: "gw_return", min: r - SIMD3(1.3, 1.3, 1.3), max: r + SIMD3(1.3, 1.3, 1.3), prompt: "Return through the lens", reach: 5)]
            gwList += glass?.interactables() ?? []
            for n in 5...8 {
                let p = GlassPuzzleProps.pagePosition(n)
                gwList.append(Interactable(id: "page_\(n)", min: p - SIMD3(0.5, 0.3, 0.5), max: p + SIMD3(0.5, 0.4, 0.5),
                                           prompt: "Read the page", reach: 3.4, enabled: n == 5))     // 6-8 are revealed by the puzzles
            }
            worldInteractables[.glassWood] = gwList
        }
    }

    private func setInteractable(_ id: String, enabled: Bool) {
        for kind in worldInteractables.keys {
            if let i = worldInteractables[kind]?.firstIndex(where: { $0.id == id }) { worldInteractables[kind]![i].enabled = enabled }
        }
    }

    /// True when what the crosshair is on has already done its job (a solved stone, a heard account...): it still responds, but the
    /// crosshair looks quieter, so the player can tell the unfinished from the finished at a glance. No sound, no text.
    var hoveredFinished: Bool {
        guard let id = hovered?.id else { return false }
        if id.hasPrefix("stone_") { return state.has("solved") }
        if id.hasPrefix("gw_mirror_") || id.hasPrefix("gw_pane_") { return state.has("gw_mirrors") }
        if id.hasPrefix("gw_chime_") { return state.has("gw_chimes") }
        if id == "gw_altar_ilse" { return state.has("gw_ilse_heard") }
        if id == "gw_altar_oren" { return state.has("gw_oren_heard") }
        return false
    }

    /// What the crosshair is on right now (nil while reading or fading out).
    func updateHover() {
        hovered = (journal.isOpen || whiteout > 0 || isTraveling) ? nil : Interaction.pick(origin: camera.position, dir: camera.forward, in: interactables)
    }

    func activate(_ id: String) {
        if let owner = puzzles.first(where: { $0.handles(id) }) {
            owner.activate(id)
        } else if id.hasPrefix("page_"), let n = Int(id.dropFirst(5)) {
            collectPage(n)
        } else if id == "lh_door" {
            // The harder and longer the player tries (repeated attempts within about 4 s), the harder the door knocks and the longer it rattles (F03 A2).
            doorTries = (time - lastDoorTry < 4.0) ? doorTries + 1 : 0
            lastDoorTry = time
            pending.append(.doorTry(min(1, 0.45 + 0.2 * Float(doorTries))))
            pending.append(.chime(.doorLocked))
            showBanner("Locked. The keeper took the key with her.")
        } else if id == "lens" {
            touchLens()
        } else if id == "gw_return" {
            fadeThrough(to: .varrow)
        }
    }

    /// Mark a page as already collected (loading a save): hides it and disables it, without opening the journal.
    func restorePage(_ n: Int) {
        state.set("page_\(n)")
        journal.collect(n)
        for sc in scenes.values {                                                      // the page lives in whichever world it belongs to
            sc.update("page_\(n)") { $0.hidden = true }
            for k in 0..<2 { sc.update("page_mote_\(n)_\(k)") { $0.hidden = true } }
            sc.update("page_beacon_\(n)") { $0.hidden = true }
        }
        announcedPages.remove(n)
        setInteractable("page_\(n)", enabled: false)
    }

    private func collectPage(_ n: Int) {
        restorePage(n)
        journal.tab = .pages                       // F01 W7: a newly read page opens on the Pages tab, on that page, whatever tab was last used
        journal.isOpen = true
        pending.append(.pageCollected(n))
        pending.append(.journalOpened)
    }

    private func touchLens() {
        guard state.has("causewayUp") else { return }
        state.set("lensTouched")                      // "has travelled": kept in the save
        pending.append(.chime(.lens))
        fadeThrough(to: .glassWood)
    }

    // MARK: Travel between worlds

    static let fadeOutSeconds: Float = 1.2, holdSeconds: Float = 0.4, fadeInSeconds: Float = 2.0

    /// Step through a lens: fade to white, swap worlds while nothing can be seen, fade back in.
    func fadeThrough(to kind: WorldKind) {
        guard !isTraveling, scenes[kind] != nil, kind != world else { return }
        isTraveling = true
        whiteCaption = "The light folds…"
        pending.append(.whiteoutStarted)
        animator.tween(duration: Game.fadeOutSeconds, ease: .inOutCubic, apply: { [weak self] t in self?.whiteout = t }, completion: { [weak self] in
            guard let self else { return }
            self.travel(to: kind)
            self.animator.tween(delay: Game.holdSeconds, duration: Game.fadeInSeconds, ease: .inOutCubic, apply: { [weak self] t in self?.whiteout = 1 - t },
                                completion: { [weak self] in self?.isTraveling = false; self?.whiteCaption = nil; if kind == .glassWood { self?.cueArrivalPage() } })
        })
    }

    /// The first time you arrive in the Glass Wood, the page by the arrival pad is announced like the others (it used to be there with no sign at all).
    func cueArrivalPage() {
        guard !state.has("page_5"), !state.has("gw_page5_cued") else { return }
        state.set("gw_page5_cued")
        announcedPages.insert(5)
        pending.append(.chime(.pageAppears))
        showBanner("A page has come loose.")
    }

    /// Put the player in `kind` at its arrival point. (Instant; `fadeThrough` hides it behind white.)
    func travel(to kind: WorldKind) {
        guard scenes[kind] != nil else { return }
        world = kind
        let pose: (position: SIMD3<Float>, yaw: Float)
        switch kind {
        case .varrow: pose = (Layout.isletCenter + SIMD3(0, 0, 5), 0)          // beside the lens, facing it
        case .glassWood: pose = (GlassLayout.arrival, 0)
        }
        player = Player(position: pose.position, yaw: pose.yaw)
        player.position.y = scene.groundHeight(x: pose.position.x, z: pose.position.z)
        hovered = nil
        pending.append(.worldChanged(kind))
        if kind == .varrow && state.has("gw_end") { showBanner("The lamp still burns. You carry two accounts now.") }
    }

    /// Where the player is and what they have done, attached to every piece of feedback.
    func feedbackContext(extra: [String: String] = [:]) -> [String: String] {
        func f(_ v: Float) -> String { String(format: "%.1f", v) }
        let p = player.position
        var c: [String: String] = [
            "position": "\(f(p.x)), \(f(p.y)), \(f(p.z))",
            "yaw/pitch": "\(String(format: "%.2f", player.yaw)) / \(String(format: "%.2f", player.pitch))",
            "surface": "\(currentSurface)",
            "looking at": hovered?.id ?? "nothing interactive",
            "puzzle flags": state.flags.sorted().joined(separator: ", ").isEmpty ? "none" : state.flags.sorted().joined(separator: ", "),
            "journal pages": journal.collectedPages.map { String($0.number) }.joined(separator: ", ").isEmpty ? "none" : journal.collectedPages.map { String($0.number) }.joined(separator: ", "),
            "play time": "\(Int(time)) s",
            "build": "0.1.0",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        for (k, v) in extra { c[k] = v }
        return c
    }

    /// Tapping a struck glyph in the notebook plays that stone's tone again. Unstruck glyphs stay silent.
    func playNotebookTone(_ index: Int) {
        guard let id = StoneID(rawValue: index), state.has(Notebook.struckFlag(id)) else { return }
        pending.append(.chime([ChimeKind.tide, .wind, .stone][index]))
    }

    /// Walking up to a stone is enough to have seen its glyph.
    private func updateDiscoveries() {
        guard world == .varrow else { return }
        for id in StoneID.allCases where !state.has(Notebook.seenFlag(id)) {
            let d = id.position - player.position
            if (d.x * d.x + d.z * d.z).squareRoot() < Notebook.seenRadius && abs(d.y) < 6 { state.set(Notebook.seenFlag(id)) }
        }
    }

    func toggleJournal() {
        journal.isOpen.toggle()
        pending.append(journal.isOpen ? .journalOpened : .journalClosed)
    }

    // MARK: Simulation

    /// One fixed 1/120 s step of everything that moves.
    func fixedStep(input: InputState) {
        if player.step(dt: Game.tick, input: isTraveling ? InputState() : input, scene: scene) { footfalls += 1; lastFootWasRun = player.lastStepWasRun }
        animator.update(Game.tick)
        time += Game.tick
        let target = atmosphereTargets
        mistScale += (target.mist - mistScale) * min(1, Game.tick / 12)        // about 12 s to thin
        beamAmount += (target.beam - beamAmount) * min(1, Game.tick / 4)       // about 4 s to fade in
        if input.run && length_squared(input.move) > 0 { hasRun = true }
        if !hasRun && length_squared(input.move) > 0 && !journal.isOpen && !isTraveling { walkedSeconds += Game.tick }
        if !hasRun && walkedSeconds > Game.runHintAfter && !state.has("hint_run") && banner == nil {
            state.set("hint_run"); showBanner("Hold Shift to run, or press R to run automatically.")
        }
        runBlend += (Player.runFactor(speed: player.speed) - runBlend) * (1 - exp(-4 * Game.tick))
        zoomAmount = LookCloser.ease(zoomAmount, held: input.zoom && !journal.isOpen && !isTraveling, dt: Game.tick)
        for p in puzzles { p.updateVisuals(time: time) }
        updateDiscoveries()
        Birds.update(scene, time: time)
        // Uncollected pages glow and shed two slow motes of light, so they read as "pick me up" even in shadow and from afar (F02 P0).
        for n in (world == .varrow ? 1...4 : 5...8) where !state.has("page_\(n)") && shownPages.contains(n) {
            let centre = world == .varrow ? PuzzleProps.pagePosition(n, terrain: scene.terrain) : GlassPuzzleProps.pagePosition(n)
            scene.update("page_\(n)") { $0.uniforms.emissive.w = 2.0 + 0.5 * sin(self.time * 2.4 + Float(n)) }
            scene.update("page_beacon_\(n)") { $0.uniforms.emissive.w = 1.6 + 0.5 * sin(self.time * 1.7 + Float(n)) }
            for k in 0..<2 {
                let m = PageStands.mote(centre: centre, page: n, k: k, time: self.time)
                scene.update("page_mote_\(n)_\(k)") { $0.uniforms.model = translation(m.position); $0.uniforms.emissive.w = 7 * m.brightness }
            }
        }
        // The lens floats and turns while it waits.
        let bob = sin(time * 1.2) * 0.08
        if world == .varrow {            // the bell buoy rides the swell
            let rock = sin(time * 0.8) * 0.12
            scene.update("buoy") { $0.uniforms.model = translation(Layout.buoy + SIMD3(0, 0.1 + 0.25 * sin(self.time * 0.9), 0)) * rotationZ(rock) * rotationX(rock * 0.7) }
        }
        scene.update("lens_ring") { $0.uniforms.model = translation(PuzzleProps.lensRestPosition + SIMD3(0, bob, 0)) * rotationY(self.time * 0.4) }
        scene.update("lens_core") { $0.uniforms.model = translation(PuzzleProps.lensRestPosition + SIMD3(0, bob, 0)) }
    }

    /// Advance by wall-clock time. Frame hiccups are clamped so a stall doesn't teleport the player.
    func advance(now: Double, input rawInput: InputState) {
        var input = rawInput
        if input.autoRunPressed { autoRun.toggle(); showBanner(autoRun ? "Auto-run on (R to stop)" : "Auto-run off") }
        if autoRun && length_squared(input.move) > 0 { input.run = true }
        let dt = Float(min(max(now - (lastTime ?? now), 0), 0.1))
        lastTime = now

        // UI-level input first: the journal is modal (the mouse is released while it is open).
        if input.feedbackPressed { pending.append(.feedbackRequested) }
        if input.journalPressed { toggleJournal() }
        if input.escapePressed && journal.isOpen { journal.isOpen = false; pending.append(.journalClosed) }
        if journal.isOpen && input.tabPressed { journal.tab = journal.tab == .pages ? .notebook : .pages }
        if journal.isOpen && input.pageFlip != 0 { journal.flip(input.pageFlip) }

        player.applyLook(input.look * LookCloser.lookScale(zoom: zoomAmount))     // slower aim when zoomed, so it stays controllable
        accumulator += dt
        while accumulator >= Game.tick {
            fixedStep(input: input)
            accumulator -= Game.tick
        }
        updateHover()
        if input.click, let h = hovered { activate(h.id) }
    }

    /// Run `seconds` of simulation with the given held input (tests, `--state`).
    func simulate(seconds: Float, input: InputState = InputState()) {
        for _ in 0..<Int((seconds / Game.tick).rounded()) { fixedStep(input: input) }
    }
}
