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
                                   revealPage: { [weak self] n in self?.revealPage(n) },
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

    /// Make a hidden journal page visible and readable (puzzles call this as a reward).
    private func revealPage(_ n: Int) {
        guard !state.has("page_\(n)") else { return }
        scenes[.glassWood]?.update("page_\(n)") { $0.hidden = false }
        setInteractable("page_\(n)", enabled: true)
    }

    /// Varrow only (most tests need nothing else).
    convenience init(scene: Scene) { self.init(scenes: [.varrow: scene]) }

    /// 0...1: how far the "look closer" zoom has eased in (right mouse button or Z).
    private(set) var zoomAmount: Float = 0
    var camera: Camera { var c = player.camera; c.fovY = LookCloser.fov(zoom: zoomAmount); return c }

    /// The ground material under the player's feet (drives footstep sounds).
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
            list.append(Interactable(id: "page_\(n)", min: p - SIMD3(0.35, 0.1, 0.35), max: p + SIMD3(0.35, 0.3, 0.35),
                                     prompt: "Read the page", reach: 3.2))
        }
        let l = PuzzleProps.lensRestPosition
        list.append(Interactable(id: "lens", min: l - SIMD3(1.3, 1.3, 1.3), max: l + SIMD3(1.3, 1.3, 1.3), prompt: "Touch the lens", reach: 5))
        worldInteractables[.varrow] = list

        if scenes[.glassWood] != nil {
            let r = GlassLayout.returnLens
            var gwList = [Interactable(id: "gw_return", min: r - SIMD3(1.3, 1.3, 1.3), max: r + SIMD3(1.3, 1.3, 1.3), prompt: "Return through the lens", reach: 5)]
            gwList += glass?.interactables() ?? []
            for n in 5...8 {
                let p = GlassPuzzleProps.pagePosition(n)
                gwList.append(Interactable(id: "page_\(n)", min: p - SIMD3(0.35, 0.1, 0.35), max: p + SIMD3(0.35, 0.3, 0.35),
                                           prompt: "Read the page", reach: 3.2, enabled: n == 5))     // 6-8 are revealed by the puzzles
            }
            worldInteractables[.glassWood] = gwList
        }
    }

    private func setInteractable(_ id: String, enabled: Bool) {
        for kind in worldInteractables.keys {
            if let i = worldInteractables[kind]?.firstIndex(where: { $0.id == id }) { worldInteractables[kind]![i].enabled = enabled }
        }
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
        for sc in scenes.values { sc.update("page_\(n)") { $0.hidden = true } }       // the page lives in whichever world it belongs to
        setInteractable("page_\(n)", enabled: false)
    }

    private func collectPage(_ n: Int) {
        restorePage(n)
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
                                completion: { [weak self] in self?.isTraveling = false; self?.whiteCaption = nil })
        })
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
        zoomAmount = LookCloser.ease(zoomAmount, held: input.zoom && !journal.isOpen && !isTraveling, dt: Game.tick)
        for p in puzzles { p.updateVisuals(time: time) }
        updateDiscoveries()
        Birds.update(scene, time: time)
        // Uncollected pages glow faintly so they read as "pick me up", even in shadow.
        for n in (world == .varrow ? 1...4 : 5...8) where !state.has("page_\(n)") {
            scene.update("page_\(n)") { $0.uniforms.emissive.w = 0.25 + 0.15 * sin(self.time * 2.4 + Float(n)) }
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
    func advance(now: Double, input: InputState) {
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
