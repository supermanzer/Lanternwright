import Foundation
import simd

/// "As the keeper climbed": strike the three resonance stones in the order the journal gives (water, wind, stone,
/// i.e. by ascending altitude). A wrong strike dims them all and resets; the right order lights the lens and raises
/// the causeway to the islet.
///
/// Design notes:
///  - Observable cause and effect: every strike changes something you can see and hear.
///  - No punishment: a mistake costs a soft chime and a reset, nothing else.
///  - The puzzle only talks to the world through named scene items, flags and events, never to rendering or audio.
final class LighthousePuzzle {
    static let order: [StoneID] = [.tide, .wind, .summit]

    /// Seconds. The whole solve sequence takes about 12 s.
    enum Timing {
        static let wrongResetDelay: Float = 0.8
        static let litFade: Float = 0.6
        static let beamStart: Float = 0.4, beamStagger: Float = 0.45, beamGrow: Float = 1.6
        static let ignitionAt: Float = 3.2, ignitionDuration: Float = 3.5
        static let causewayAt: Float = 6.5, slabStagger: Float = 0.25, slabRise: Float = 1.8
        static var total: Float { causewayAt + Float(PuzzleProps.slabCount - 1) * slabStagger + slabRise }
    }

    private let scene: Scene
    private let state: PuzzleState
    private let animator: Animator
    private let emit: (GameEvent) -> Void

    private(set) var sequence: [StoneID] = []
    private var resetting = false
    private var lit: [Float] = [0, 0, 0]
    private var beamGrowth: [Float] = [0, 0, 0]
    private var lensGlow: Float = 0
    private var slabRise = [Float](repeating: 0, count: PuzzleProps.slabCount)
    private let plan: PuzzleProps.CausewayPlan

    init(scene: Scene, state: PuzzleState, animator: Animator, emit: @escaping (GameEvent) -> Void) {
        self.scene = scene
        self.state = state
        self.animator = animator
        self.emit = emit
        plan = PuzzleProps.causewayPlan(terrain: scene.terrain)
    }

    var isSolved: Bool { state.has("solved") }

    // MARK: Interaction

    func strike(_ id: StoneID) {
        emit(.chime(chimeFor(id)))
        guard !isSolved, !resetting else { return }              // after solving, stones just ring
        if id == LighthousePuzzle.order[sequence.count] {
            sequence.append(id)
            state.set("lit_\(id.name)")
            emit(.drone(id.rawValue, true))
            fade(stone: id, to: 1)
            if sequence.count == LighthousePuzzle.order.count { solve() }
        } else {
            resetting = true
            emit(.chime(.fail))
            emit(.droneSour)
            animator.after(Timing.wrongResetDelay) { [weak self] in self?.reset() }
        }
    }

    private func chimeFor(_ id: StoneID) -> ChimeKind {
        switch id { case .tide: return .tide; case .wind: return .wind; case .summit: return .stone }
    }

    private func reset() {
        for id in StoneID.allCases where state.has("lit_\(id.name)") {
            state.set("lit_\(id.name)", false)
            fade(stone: id, to: 0)
        }
        sequence = []
        resetting = false
    }

    private func fade(stone id: StoneID, to target: Float) {
        let from = lit[id.rawValue]
        animator.tween(duration: Timing.litFade, ease: .outCubic) { [weak self] t in
            self?.lit[id.rawValue] = from + (target - from) * t
        }
    }

    // MARK: The solve sequence

    private func solve() {
        state.set("solved")
        emit(.chime(.ignite))
        emit(.droneBloom)
        // 1. Beams grow from each capstone to the lens, one after another.
        for id in StoneID.allCases {
            let i = id.rawValue
            animator.after(Timing.beamStart + Float(i) * Timing.beamStagger) { [weak self] in
                self?.scene.update("beam_\(id.name)") { $0.hidden = false }
            }
            animator.tween(delay: Timing.beamStart + Float(i) * Timing.beamStagger, duration: Timing.beamGrow, ease: .outCubic) { [weak self] t in
                self?.beamGrowth[i] = t
            }
        }
        // 2. The lens ignites.
        animator.after(Timing.ignitionAt) { [weak self] in
            self?.state.set("lighthouseLit")
            self?.emit(.chime(.lens))
        }
        animator.tween(delay: Timing.ignitionAt, duration: Timing.ignitionDuration, ease: .inOutCubic) { [weak self] t in
            self?.lensGlow = t * 40
        }
        // 3. The causeway rises from the sea, slab by slab, with a low rumble.
        animator.after(Timing.causewayAt) { [weak self] in
            self?.emit(.chime(.rumble))
            for k in 0..<PuzzleProps.slabCount { self?.scene.update("causeway_\(k)") { $0.hidden = false } }
        }
        for k in 0..<PuzzleProps.slabCount {
            animator.tween(delay: Timing.causewayAt + Float(k) * Timing.slabStagger, duration: Timing.slabRise, ease: .inOutCubic,
                           apply: { [weak self] t in self?.slabRise[k] = t },
                           completion: { [weak self] in
                               guard let self, k == PuzzleProps.slabCount - 1 else { return }
                               if let i = self.scene.causewayIndex { self.scene.walkables[i].enabled = true }
                               self.state.set("causewayUp")
                           })
        }
    }

    /// Debug/screenshot: jump straight to the solved world (`--state solved`).
    func forceSolved() {
        sequence = LighthousePuzzle.order
        for id in StoneID.allCases { state.set("lit_\(id.name)"); lit[id.rawValue] = 1; beamGrowth[id.rawValue] = 1
            scene.update("beam_\(id.name)") { $0.hidden = false } }
        state.set("solved"); state.set("lighthouseLit"); state.set("causewayUp")
        lensGlow = 40
        slabRise = [Float](repeating: 1, count: PuzzleProps.slabCount)
        for k in 0..<PuzzleProps.slabCount { scene.update("causeway_\(k)") { $0.hidden = false } }
        if let i = scene.causewayIndex { scene.walkables[i].enabled = true }
    }

    // MARK: Visuals (called every tick)

    func updateVisuals(time: Float) {
        for id in StoneID.allCases {
            let i = id.rawValue
            let l = lit[i]
            let idle = 0.3 + 0.18 * sin(time * 2.1 + Float(i) * 2)             // gentle pulse: "touch me" until used
            scene.update("glyph_\(id.name)") { $0.uniforms.emissive.w = idle * (1 - l) + 5.0 * l }
            let bob = l * 0.07 * sin(time * 1.6 + Float(i))
            let rise = 0.3 * l + bob
            let capPos = Landmarks.capstoneBase(id) + SIMD3(0, rise, 0)
            scene.update("cap_\(id.name)") {
                $0.uniforms.model = translation(capPos) * rotationY(time * 0.6 * l)
                $0.uniforms.emissive.w = 0.5 * (1 - l) + 3.5 * l
            }
            let g = beamGrowth[i]
            if g > 0 {
                scene.update("beam_\(id.name)") { $0.uniforms.model = PuzzleProps.beamModel(id, capRise: 0.3, growth: g) }
            }
        }
        if lensGlow > 0 || state.has("lighthouseLit") {
            scene.update("lighthouse_lens") { $0.uniforms.emissive = SIMD4(1.0, 0.85, 0.55, self.lensGlow) }
            scene.update("lighthouse_glass") { $0.uniforms.emissive = SIMD4(1.0, 0.8, 0.5, self.lensGlow * 0.1) }
        }
        for k in 0..<PuzzleProps.slabCount where slabRise[k] > 0 {
            let m = PuzzleProps.slabModel(plan, k, rise: slabRise[k])
            scene.update("causeway_\(k)") { $0.uniforms.model = m }
        }
    }
}
