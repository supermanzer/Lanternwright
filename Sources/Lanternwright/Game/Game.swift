import Foundation
import simd

/// Owns the player, the puzzle and the simulation clock, and advances them at a fixed rate independent of the
/// display's frame rate.
final class Game {
    static let tick: Float = 1.0 / 120.0

    let scene: Scene
    var player: Player
    let state = PuzzleState()
    let animator = Animator()
    private(set) var puzzle: LighthousePuzzle!
    private(set) var interactables: [Interactable] = []
    private(set) var hovered: Interactable?
    var journal = JournalState()
    /// 0...1 white fade at the end of the slice.
    private(set) var whiteout: Float = 0

    private var accumulator: Float = 0
    private var lastTime: Double?
    private(set) var time: Float = 0
    private var pending: [GameEvent] = []
    /// Footfalls since start; audio compares against the last value it saw.
    private(set) var footfalls = 0
    private(set) var lastFootWasRun = false

    init(scene: Scene) {
        self.scene = scene
        player = Player(position: SIMD3(Layout.dockEnd.x, Layout.dockEnd.y, Layout.dockEnd.z), yaw: Layout.spawnYaw)
        puzzle = LighthousePuzzle(scene: scene, state: state, animator: animator) { [weak self] in self?.pending.append($0) }
        buildInteractables()
    }

    var camera: Camera { player.camera }

    /// The ground material under the player's feet (drives footstep sounds).
    var currentSurface: SurfaceKind { scene.surface(x: player.position.x, z: player.position.z) }

    /// Events since the last call (audio and UI consume these).
    func drainEvents() -> [GameEvent] { defer { pending = [] }; return pending }

    // MARK: Interactables

    private func buildInteractables() {
        for id in StoneID.allCases {
            let p = id.position
            interactables.append(Interactable(id: "stone_\(id.name)",
                                              min: SIMD3(p.x - 0.95, p.y, p.z - 0.95), max: SIMD3(p.x + 0.95, p.y + StoneID.height + 1.4, p.z + 0.95),
                                              prompt: "Touch the stone"))
        }
        for n in 1...4 {
            let p = PuzzleProps.pagePosition(n, terrain: scene.terrain)
            interactables.append(Interactable(id: "page_\(n)", min: p - SIMD3(0.35, 0.1, 0.35), max: p + SIMD3(0.35, 0.3, 0.35),
                                              prompt: "Read the page", reach: 3.2))
        }
        let l = PuzzleProps.lensRestPosition
        interactables.append(Interactable(id: "lens", min: l - SIMD3(1.3, 1.3, 1.3), max: l + SIMD3(1.3, 1.3, 1.3), prompt: "Touch the lens", reach: 5))
    }

    /// What the crosshair is on right now (nil while reading or fading out).
    func updateHover() {
        hovered = (journal.isOpen || whiteout > 0) ? nil : Interaction.pick(origin: camera.position, dir: camera.forward, in: interactables)
    }

    func activate(_ id: String) {
        if id.hasPrefix("stone_") {
            if let stone = StoneID.allCases.first(where: { "stone_\($0.name)" == id }) { puzzle.strike(stone) }
        } else if id.hasPrefix("page_"), let n = Int(id.dropFirst(5)) {
            collectPage(n)
        } else if id == "lens" {
            touchLens()
        }
    }

    /// Mark a page as already collected (loading a save): hides it and disables it, without opening the journal.
    func restorePage(_ n: Int) {
        state.set("page_\(n)")
        journal.collect(n)
        scene.update("page_\(n)") { $0.hidden = true }
        if let i = interactables.firstIndex(where: { $0.id == "page_\(n)" }) { interactables[i].enabled = false }
    }

    private func collectPage(_ n: Int) {
        restorePage(n)
        journal.isOpen = true
        pending.append(.pageCollected(n))
        pending.append(.journalOpened)
    }

    private func touchLens() {
        guard !state.has("lensTouched"), state.has("causewayUp") else { return }
        state.set("lensTouched")
        pending.append(.chime(.lens))
        pending.append(.whiteoutStarted)
        animator.tween(duration: 2.0, ease: .inOutCubic) { [weak self] t in self?.whiteout = t }
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

    func toggleJournal() {
        journal.isOpen.toggle()
        pending.append(journal.isOpen ? .journalOpened : .journalClosed)
    }

    // MARK: Simulation

    /// One fixed 1/120 s step of everything that moves.
    func fixedStep(input: InputState) {
        if player.step(dt: Game.tick, input: input, scene: scene) { footfalls += 1; lastFootWasRun = player.lastStepWasRun }
        animator.update(Game.tick)
        time += Game.tick
        puzzle.updateVisuals(time: time)
        Birds.update(scene, time: time)
        // Uncollected pages glow faintly so they read as "pick me up", even in shadow.
        for n in 1...4 where !state.has("page_\(n)") {
            scene.update("page_\(n)") { $0.uniforms.emissive.w = 0.25 + 0.15 * sin(self.time * 2.4 + Float(n)) }
        }
        // The lens floats and turns while it waits.
        let bob = sin(time * 1.2) * 0.08
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
        if journal.isOpen && input.pageFlip != 0 { journal.flip(input.pageFlip) }

        player.applyLook(input.look)
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
