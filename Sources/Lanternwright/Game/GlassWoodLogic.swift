import Foundation
import simd

/// The Glass Wood's puzzles. Like Varrow's, it talks to the world only through named scene items, flags and events.
///  - The mirror court: turn mirrors and change panes until the moonbeam meets tide, wind, stone, in that order.
///  - (T5.5) The chimes by the pool.
final class GlassWoodLogic {
    private let scene: Scene
    private let state: PuzzleState
    private let animator: Animator
    private let emit: (GameEvent) -> Void
    /// Make a hidden journal page visible and readable (implemented by Game, which owns interactables).
    private let revealPage: (Int) -> Void

    // MARK: Mirror court state
    private(set) var mirrors = MirrorCourt.initialMirrors
    private(set) var panes = MirrorCourt.initialPanes
    /// Animated plate angle in units of 45 degrees (so a turn is a smooth +1, never a long way round).
    private var mirrorTurns = MirrorCourt.initialMirrors.map { Float($0) }
    private var mirrorTarget = MirrorCourt.initialMirrors.map { Float($0) }
    private var columnGrowth: Float = 0
    private var trace = MirrorCourt.trace(mirrors: MirrorCourt.initialMirrors, panes: MirrorCourt.initialPanes)

    static let columnHeight: Float = 46

    init(scene: Scene, state: PuzzleState, animator: Animator, emit: @escaping (GameEvent) -> Void, revealPage: @escaping (Int) -> Void) {
        self.scene = scene
        self.state = state
        self.animator = animator
        self.emit = emit
        self.revealPage = revealPage
        refreshBeams()
    }

    var mirrorsSolved: Bool { state.has("gw_mirrors") }

    // MARK: Interactables

    func interactables() -> [Interactable] {
        var list: [Interactable] = []
        for k in 0..<3 {
            let m = GlassPuzzleProps.mirrorPosition(k) + SIMD3(0, 1.25, 0)
            list.append(Interactable(id: "gw_mirror_\(k)", min: m - SIMD3(1.0, 1.0, 1.0), max: m + SIMD3(1.0, 1.0, 1.0), prompt: "Turn the mirror", reach: 5))
            let p = GlassPuzzleProps.panePosition(k) + SIMD3(0, 1.3, 0)
            list.append(Interactable(id: "gw_pane_\(k)", min: p - SIMD3(1.1, 1.2, 1.1), max: p + SIMD3(1.1, 1.2, 1.1), prompt: "Change the glass", reach: 5))
        }
        return list
    }

    func click(_ id: String) {
        if id.hasPrefix("gw_mirror_"), let k = Int(id.dropFirst(10)), k < 3 {
            emit(.chime(.glassTick))
            guard !mirrorsSolved else { return }
            mirrors[k] = (mirrors[k] + 1) % 4
            let from = mirrorTurns[k]
            mirrorTarget[k] += 1
            let to = mirrorTarget[k]
            animator.tween(duration: 0.35, ease: .inOutCubic) { [weak self] t in self?.mirrorTurns[k] = from + (to - from) * t }
            retrace()
        } else if id.hasPrefix("gw_pane_"), let k = Int(id.dropFirst(8)), k < 3 {
            emit(.chime(.glassTick))
            guard !mirrorsSolved else { return }
            panes[k] = (panes[k] + 1) % 3
            retrace()
        }
    }

    /// Recompute the beam for the current arrangement and check for victory.
    private func retrace() {
        trace = MirrorCourt.trace(mirrors: mirrors, panes: panes)
        refreshBeams()
        if trace.solved && !mirrorsSolved { solveMirrors() }
    }

    private func refreshBeams() {
        for i in 0..<GlassPuzzleProps.beamSegments {
            if i < trace.points.count - 1 {
                let a = MirrorCourt.world(trace.points[i]) + SIMD3(0, GlassPuzzleProps.beamHeight, 0)
                let b = MirrorCourt.world(trace.points[i + 1]) + SIMD3(0, GlassPuzzleProps.beamHeight, 0)
                let d = b - a
                let len = max(length(d), 0.01)
                let col = GlassPuzzleProps.beamColor(trace.segmentColor[i])
                scene.update("gw_beam_\(i)") {
                    $0.hidden = false
                    $0.uniforms.model = translation(a) * rotation(aligningYTo: d) * scaling(SIMD3(1, len, 1))
                    $0.uniforms.tint = SIMD4(col, 1)
                    $0.uniforms.emissive = SIMD4(col, 2.2)
                }
            } else {
                scene.update("gw_beam_\(i)") { $0.hidden = true }
            }
        }
        for k in 0..<3 {
            let col = GlassPuzzleProps.color(panes[k])
            scene.update("gw_pane_\(k)") { $0.uniforms.tint = SIMD4(col, 1); $0.uniforms.emissive = SIMD4(col, 0.7) }
        }
    }

    // MARK: Reward

    private func solveMirrors() {
        state.set("gw_mirrors")
        // The stones' three tones, in order, then the chord: the wood answers.
        animator.after(0.0) { [weak self] in self?.emit(.chime(.tide)) }
        animator.after(0.5) { [weak self] in self?.emit(.chime(.wind)) }
        animator.after(1.0) { [weak self] in self?.emit(.chime(.stone)) }
        animator.after(1.6) { [weak self] in self?.emit(.chime(.ignite)) }
        scene.update("gw_column") { $0.hidden = false }
        animator.tween(delay: 0.8, duration: 3.0, ease: .inOutCubic) { [weak self] t in self?.columnGrowth = t }
        animator.after(2.0) { [weak self] in self?.revealPage(6) }
    }

    /// Put the court in a given arrangement without any animation (debug views and tests).
    func setArrangement(mirrors m: [Int], panes p: [Int]) {
        mirrors = m; panes = p
        mirrorTurns = m.map { Float($0) }; mirrorTarget = mirrorTurns
        retrace()
    }

    /// Jump straight to the solved state (loading a save, `--state`).
    func forceMirrorsSolved() {
        mirrors = MirrorCourt.solutionMirrors
        panes = MirrorCourt.solutionPanes
        mirrorTurns = mirrors.map { Float($0) }; mirrorTarget = mirrorTurns
        state.set("gw_mirrors")
        trace = MirrorCourt.trace(mirrors: mirrors, panes: panes)
        refreshBeams()
        columnGrowth = 1
        scene.update("gw_column") { $0.hidden = false }
        revealPage(6)
    }

    // MARK: Visuals (every tick)

    func updateVisuals(time: Float) {
        for k in 0..<3 {
            let m = GlassPuzzleProps.mirrorModel(k, turns: mirrorTurns[k])
            scene.update("gw_mirror_\(k)") { $0.uniforms.model = m }
        }
        // The receiver: dark until light arrives; shows the colour that arrived (pulsing unevenly if it is the wrong order); blazes when solved.
        let last = trace.segmentColor.last ?? -1
        scene.update("gw_receiver") {
            if self.mirrorsSolved {
                $0.uniforms.emissive = SIMD4(1.0, 0.95, 0.8, 9)
            } else if self.trace.reachedReceiver {
                let flutter = 1.6 + 1.2 * sin(time * 9)
                $0.uniforms.emissive = SIMD4(GlassPuzzleProps.color(last), flutter)
            } else {
                $0.uniforms.emissive = SIMD4(0.3, 0.35, 0.45, 0.5)
            }
        }
        if columnGrowth > 0 {
            let h = max(columnGrowth * GlassWoodLogic.columnHeight, 0.01)
            let pulse = 6 + 1.5 * sin(time * 1.7)
            scene.update("gw_column") {
                $0.uniforms.model = translation(MirrorCourt.world(MirrorCourt.receiver)) * scaling(SIMD3(1, h, 1))
                $0.uniforms.emissive = SIMD4(0.9, 0.95, 1.0, pulse)
            }
        }
    }
}
