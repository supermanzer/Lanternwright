import Foundation
import simd

/// The Glass Wood's puzzles. Like Varrow's, it talks to the world only through named scene items, flags and events.
///  - The mirror court (P02.1): turn mirrors and change panes until all three receiving crystals are lit at once (each lights, with its own tone, the moment the beam reaches it in its own colour; any order).
///  - (T5.5) The chimes by the pool.
final class GlassWoodLogic: WorldPuzzle {
    private let scene: Scene
    private let state: PuzzleState
    private let animator: Animator
    private let emit: (GameEvent) -> Void
    /// Make a hidden journal page visible and readable (implemented by Game, which owns interactables).
    /// (page number, announce): `announce` is true when the page appears live (sound and banner), false when a saved game restores it.
    private let revealPage: (Int, Bool) -> Void
    /// Show a line of text over the world for a few seconds, and enable/disable an interactable by id (both provided by Game).
    private let showBanner: (String) -> Void
    private let setEnabled: (String, Bool) -> Void

    // MARK: Mirror court state
    private(set) var mirrors = MirrorCourt.initialMirrors
    private(set) var panes = MirrorCourt.initialPanes
    /// Animated plate angle in units of 45 degrees (so a turn is a smooth +1, never a long way round).
    private var mirrorTurns = MirrorCourt.initialMirrors.map { Float($0) }
    private var mirrorTarget = MirrorCourt.initialMirrors.map { Float($0) }
    private var columnGrowth: Float = 0
    private var trace = MirrorCourt.trace(mirrors: MirrorCourt.initialMirrors, panes: MirrorCourt.initialPanes)
    /// How lit each receiving crystal looks (0...1, eased toward the trace each tick); drives A's `ReceiverGlow`.
    private var receiverGlow = [Float](repeating: 0, count: MirrorCourt.receivers.count)
    /// Receivers lit by the court as it stands (the live reading the tests and the graph use).
    var receiversLit: [Bool] { (0..<MirrorCourt.receivers.count).map(trace.lit) }
    /// B7 (Q102): per receiver, 0...1, how nearly the beam reaches it (one click away 1, two 0.4, lit or further 0: `MirrorCourt.nearness`). For builder A's faint glow (`ReceiverGlow.set(..., near:)`); the solved rule does not read it.
    var receiverNear: [Float] {
        let key = mirrors + panes
        if key != nearKey { nearKey = key; nearCache = MirrorCourt.nearness(mirrors: mirrors, panes: panes) }
        return nearCache
    }
    private var nearKey: [Int] = [], nearCache = [Float](repeating: 0, count: MirrorCourt.receivers.count)
    /// B7 (Q102, A10 Q128): the near-miss channel of A's crystals is drawn (`ReceiverGlow.set(..., near:)`); a switch only so the court climb can be measured with and without it.
    nonisolated(unsafe) static var nearGlow = true

    static let columnHeight: Float = 46

    // MARK: Chime state
    /// The three tones of the Varrow stones, as chime indices: tide = D4 (0), wind = A4 (2), stone = D5 (4).
    /// The other two chimes (F#4, C5) are decoys; only your memory of how the stones sounded tells them apart.
    static let chimeSolution = [0, 2, 4]
    private(set) var chimeSequence: [Int] = []
    private var chimeResetting = false
    private var chimeLit = [Float](repeating: 0, count: GlassPuzzleProps.chimeCount)
    private var chimeSwing = [Float](repeating: 0, count: GlassPuzzleProps.chimeCount)
    private var chimeColumn: Float = 0
    var chimesSolved: Bool { state.has("gw_chimes") }

    init(scene: Scene, state: PuzzleState, animator: Animator, emit: @escaping (GameEvent) -> Void, revealPage: @escaping (Int, Bool) -> Void,
         showBanner: @escaping (String) -> Void, setEnabled: @escaping (String, Bool) -> Void) {
        self.scene = scene
        self.state = state
        self.animator = animator
        self.emit = emit
        self.revealPage = revealPage
        self.showBanner = showBanner
        self.setEnabled = setEnabled
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
        for k in 0..<GlassPuzzleProps.chimeCount {
            let p = GlassPuzzleProps.chimePosition(k)
            list.append(Interactable(id: "gw_chime_\(k)", min: SIMD3(p.x - 0.8, p.y, p.z - 0.8), max: SIMD3(p.x + 0.8, p.y + GlassPuzzleProps.chimeHeights[k] + 1.0, p.z + 0.8),
                                     prompt: "Strike the glass", reach: 6))
        }
        for (i, name) in ["ilse", "oren"].enumerated() {
            let p = GlassPuzzleProps.pedestalPosition(i)
            list.append(Interactable(id: "gw_altar_\(name)", min: SIMD3(p.x - 1.1, p.y, p.z - 1.1), max: SIMD3(p.x + 1.1, p.y + 3.0, p.z + 1.1),
                                     prompt: i == 0 ? "Touch Ilse's light" : "Touch Oren's light", reach: 5, enabled: false))
        }
        return list
    }

    func click(_ id: String) {
        if id == "gw_altar_ilse" { touchAltar(0); return }
        if id == "gw_altar_oren" { touchAltar(1); return }
        if id.hasPrefix("gw_chime_"), let k = Int(id.dropFirst(9)), k < GlassPuzzleProps.chimeCount { strikeChime(k); return }
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
        let before = receiversLit
        trace = MirrorCourt.trace(mirrors: mirrors, panes: panes)
        refreshBeams()
        // Live feedback (P02.1): a receiver that lights now rings its own tone (the stones' tone for its colour: tide, wind, stone), once, at the turn that lit it.
        if !mirrorsSolved && !trace.solved {                       // the last one to light is answered by the wood's own chord instead (solveMirrors)
            for k in 0..<MirrorCourt.receivers.count where trace.lit(k) && !before[k] {
                emit(.chime([ChimeKind.tide, .wind, .stone][MirrorCourt.receiverColors[k]]))
            }
        }
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
            scene.update("gw_pane_\(k)_marker") { $0.uniforms.tint = SIMD4(col, 1); $0.uniforms.emissive = SIMD4(col, 1.2) }
        }
    }

    // MARK: Chimes

    private func chimeKind(_ k: Int) -> ChimeKind { [ChimeKind.glass0, .glass1, .glass2, .glass3, .glass4][k] }

    /// Strike chime k. Like the stones of Varrow: the right tone lights it; a wrong one rings dissonantly, then everything resets.
    func strikeChime(_ k: Int) {
        emit(.chime(chimeKind(k)))
        swing(k)
        guard !chimesSolved, !chimeResetting else { return }
        if k == GlassWoodLogic.chimeSolution[chimeSequence.count] {
            chimeSequence.append(k)
            fadeChime(k, to: 1)
            if chimeSequence.count == GlassWoodLogic.chimeSolution.count { solveChimes() }
        } else {
            chimeResetting = true
            emit(.chime(.fail))
            animator.after(0.8) { [weak self] in
                guard let self else { return }
                for i in 0..<GlassPuzzleProps.chimeCount where self.chimeLit[i] > 0 { self.fadeChime(i, to: 0) }
                self.chimeSequence = []
                self.chimeResetting = false
            }
        }
    }

    private func fadeChime(_ k: Int, to target: Float) {
        let from = chimeLit[k]
        animator.tween(duration: 0.5, ease: .outCubic) { [weak self] t in self?.chimeLit[k] = from + (target - from) * t }
    }

    /// A struck glass tube rocks and settles: a damped swing over about a second.
    private func swing(_ k: Int) {
        animator.tween(duration: 1.3, ease: .linear) { [weak self] t in
            self?.chimeSwing[k] = 0.09 * exp(-3.2 * t) * sin(t * 28)
        }
    }

    private func solveChimes() {
        state.set("gw_chimes")
        // The three tones sound together as a chord, then the ignition shimmer.
        animator.after(0.5) { [weak self] in
            self?.emit(.chime(.glass0)); self?.emit(.chime(.glass2)); self?.emit(.chime(.glass4))
        }
        animator.after(1.3) { [weak self] in self?.emit(.chime(.ignite)) }
        scene.update("gw_column_chimes") { $0.hidden = false }
        animator.tween(delay: 0.8, duration: 3.0, ease: .inOutCubic) { [weak self] t in self?.chimeColumn = t }
        animator.after(2.0) { [weak self] in self?.revealPage(7, true) }
        animator.after(3.5) { [weak self] in self?.checkAltar() }
    }

    func forceChimesSolved() {
        state.set("gw_chimes")
        chimeSequence = GlassWoodLogic.chimeSolution
        for k in GlassWoodLogic.chimeSolution { chimeLit[k] = 1 }
        chimeColumn = 1
        scene.update("gw_column_chimes") { $0.hidden = false }
        revealPage(7, false)
    }

    // MARK: The altar of two accounts

    private var altarRise: Float = 0
    private var altarColumn: Float = 0
    var altarAwake: Bool { state.has("gw_altar") }

    /// The altar wakes when BOTH puzzles are solved.
    func checkAltar() {
        guard mirrorsSolved, chimesSolved, !altarAwake else { return }
        state.set("gw_altar")
        emit(.chime(.ignite))
        showBanner("Both lights answer. Something has woken at the end of the wood.")
        for name in ["ilse", "oren"] { scene.update("gw_altar_\(name)") { $0.hidden = false } }
        scene.update("gw_column_altar") { $0.hidden = false }
        animator.tween(delay: 0.5, duration: 3.5, ease: .inOutCubic) { [weak self] t in self?.altarRise = t }
        animator.tween(delay: 1.0, duration: 3.0, ease: .inOutCubic) { [weak self] t in self?.altarColumn = t }
        animator.after(4.0) { [weak self] in
            self?.revealPage(8, true)
            self?.setEnabled("gw_altar_ilse", true); self?.setEnabled("gw_altar_oren", true)
        }
    }

    /// The setup for the choice to come: hear each sibling's account. Nothing is decided here.
    func touchAltar(_ which: Int) {
        guard altarAwake else { return }
        emit(.chime(.lens))
        if which == 0 {
            state.set("gw_ilse_heard")
            showBanner(Story.ilseAccount)
        } else {
            state.set("gw_oren_heard")
            showBanner(Story.orenAccount)
        }
        if state.has("gw_ilse_heard") && state.has("gw_oren_heard") && !state.has("gw_end") {
            state.set("gw_end")
            // After the second account has been on screen for its whole time (a newer banner replaces an older one, and Ilse's runs 9 s), not at a fixed 7 s that cut it off.
            let shown = which == 0 ? Story.ilseAccount : Story.orenAccount
            animator.after(Game.bannerSeconds(shown) + 0.4) { [weak self] in
                self?.showBanner(Story.endOfWorldLine)
            }
        }
    }

    func forceAltar() {
        state.set("gw_altar")
        altarRise = 1; altarColumn = 1
        for name in ["ilse", "oren"] { scene.update("gw_altar_\(name)") { $0.hidden = false } }
        scene.update("gw_column_altar") { $0.hidden = false }
        revealPage(8, false)
        setEnabled("gw_altar_ilse", true); setEnabled("gw_altar_oren", true)
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
        animator.after(2.0) { [weak self] in self?.revealPage(6, true) }
        animator.after(3.5) { [weak self] in self?.checkAltar() }
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
        revealPage(6, false)
    }

    // MARK: WorldPuzzle

    var world: WorldKind { .glassWood }
    static let storyFlags = ["gw_ilse_heard", "gw_oren_heard", "gw_end"]
    var persistentFlags: [String] { ["gw_mirrors", "gw_chimes", "gw_altar"] + GlassWoodLogic.storyFlags }
    func handles(_ id: String) -> Bool { id.hasPrefix("gw_") && id != "gw_return" }
    func activate(_ id: String) { click(id) }
    func restore(from flags: Set<String>) {
        if flags.contains("gw_mirrors") { forceMirrorsSolved() }
        if flags.contains("gw_chimes") { forceChimesSolved() }
        if flags.contains("gw_altar") { forceAltar() }
        for f in GlassWoodLogic.storyFlags where flags.contains(f) { state.set(f) }
    }

    // MARK: Visuals (every tick)

    /// Drives builder A's three receiving crystals (`ReceiverGlow`): dormant, flickering with the colour that arrived if it is the wrong one, lit in its own colour, all blazing when solved.
    private func applyReceiverGlow(_ k: Int, time: Float) {
        let level = receiverGlow[k]
        let near = GlassWoodLogic.nearGlow && !mirrorsSolved ? receiverNear[k] : 0
        if mirrorsSolved { ReceiverGlow.set(scene, k, level: 1, blaze: true); return }
        if level > 0.02 { ReceiverGlow.set(scene, k, level: level, color: GlassPuzzleProps.color(MirrorCourt.receiverColors[k]), near: near); return }
        if let a = trace.arrivals[k].last {                    // reached by the wrong colour: a dull, uneven flutter of what arrived
            ReceiverGlow.set(scene, k, level: 0.22 + 0.08 * sin(time * 9), color: GlassPuzzleProps.color(a), near: near)
        } else { ReceiverGlow.set(scene, k, level: 0, color: GlassPuzzleProps.color(MirrorCourt.receiverColors[k]), near: near) }
    }

    func updateVisuals(time: Float) {
        if altarRise > 0 {
            for (i, name) in ["ilse", "oren"].enumerated() {
                let col = i == 0 ? GlassPuzzleProps.ilseColor : GlassPuzzleProps.orenColor
                let heard = state.has(i == 0 ? "gw_ilse_heard" : "gw_oren_heard")
                let m = GlassPuzzleProps.pedestalModel(i, rise: altarRise)
                scene.update("gw_altar_\(name)") {
                    $0.uniforms.model = m
                    $0.uniforms.emissive = SIMD4(col, (heard ? 1.5 : 0.9) + 0.25 * sin(time * 1.8 + Float(i) * 3) * altarRise)
                }
            }
        }
        if altarColumn > 0 {
            let h = max(altarColumn * 30, 0.01)
            scene.update("gw_column_altar") {
                $0.uniforms.model = translation(GlassLayout.altar) * scaling(SIMD3(1, h, 1))
                $0.uniforms.emissive = SIMD4(1.0, 0.92, 0.8, 5 + sin(time * 1.4))
            }
        }
        for k in 0..<GlassPuzzleProps.chimeCount {
            let lit = chimeLit[k]
            let idle = 0.35 + 0.15 * sin(time * 2.0 + Float(k))              // gentle pulse: strike me
            let model = GlassPuzzleProps.chimeModel(k, swing: chimeSwing[k])
            scene.update("gw_chime_\(k)") {
                $0.uniforms.model = model
                $0.uniforms.emissive = SIMD4(0.5 + 0.4 * lit, 0.8, 1.0 - 0.3 * lit, idle * (1 - lit) + 2.6 * lit)
            }
        }
        if chimeColumn > 0 {
            let h = max(chimeColumn * GlassWoodLogic.columnHeight, 0.01)
            let c = GlassLayout.chimeRing
            scene.update("gw_column_chimes") {
                $0.uniforms.model = translation(c) * scaling(SIMD3(1, h, 1))
                $0.uniforms.emissive = SIMD4(1.0, 0.75, 0.4, 6 + 1.5 * sin(time * 1.9))
            }
        }
        for k in 0..<3 {
            let m = GlassPuzzleProps.mirrorModel(k, turns: mirrorTurns[k])
            scene.update("gw_mirror_\(k)") { $0.uniforms.model = m }
        }
        // The receivers: dark (tinted with the colour each is tuned to) until light arrives; a wrong colour shows a dull flutter of the colour that arrived;
        // the right colour LIGHTS the crystal in its own colour and holds it for as long as the beam stays; all lit and solved: they blaze.
        for k in 0..<MirrorCourt.receivers.count {
            let target: Float = mirrorsSolved || trace.lit(k) ? 1 : 0
            receiverGlow[k] += (target - receiverGlow[k]) * min(1, 8 * Game.tick)
            applyReceiverGlow(k, time: time)
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
