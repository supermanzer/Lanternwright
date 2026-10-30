import Foundation
import simd

/// S03.7: Oren's exit (user decision 1, 2026-10-28): in the lens room the lens ring can be turned (a click or the arrow keys, while looking at it, a twelfth of a turn each); a faint beam
/// runs out along its pointer; when the beam has rested on the receiver on the north-east glass (within 3 degrees) for 2 seconds, a doorway of turned light opens in the north window
/// (`portal_open`). The gate (S03.3) rules it: while it is not ready the ring turns and the beam can rest on the receiver, nothing opens, and the gate's quiet line is said once per
/// attempt; three small lamps by the receiver show which parts of the gate are true (the altar, Ilse's pages, Oren's pages). Once open the ring stays where it is.
///
/// Like the other puzzles it speaks to the world only through flags, events and named scene items.
final class LensPortalPuzzle: WorldPuzzle {
    typealias P = LensPortalProps
    let world: WorldKind = .varrow
    private let scene: Scene
    private let state: PuzzleState
    private let emit: (GameEvent) -> Void
    private let gate: () -> GateState
    private let say: (String) -> Void
    /// True once Ilse's route has begun: Oren's exit is sealed for good (S03.8): the ring no longer turns, nothing opens, the lamps are dark.
    private let sealed: () -> Bool

    /// The ring's pointer, as `atan2(dz, dx)` in the tower's frame, in (-pi, pi].
    private(set) var ringAngle: Float = P.initialRingAngle
    /// How long the beam has rested on the receiver, and whether the gate's line has been said for this rest.
    private(set) var held: Float = 0
    private var cued = false

    init(scene: Scene, state: PuzzleState, emit: @escaping (GameEvent) -> Void, gate: @escaping () -> GateState, say: @escaping (String) -> Void, sealed: @escaping () -> Bool = { false }) {
        self.scene = scene; self.state = state; self.emit = emit; self.gate = gate; self.say = say; self.sealed = sealed
    }

    var isOpen: Bool { state.has(Game.portalOpenFlag) }

    /// How far the beam is from the receiver, in radians (0...pi).
    var error: Float {
        var d = abs(ringAngle - P.receiverAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d = 2 * .pi - d }
        return d
    }
    var aligned: Bool { error <= P.tolerance }

    // MARK: WorldPuzzle
    var persistentFlags: [String] { [] }                                         // the portal's own flag is the game's (Game.ownFlags)
    func restore(from flags: Set<String>) {
        held = 0; cued = false
        ringAngle = isOpen ? P.receiverAngle : P.initialRingAngle
        apply()
    }
    func handles(_ id: String) -> Bool { id == "lens_ring" }
    func activate(_ id: String) { turn(1) }
    func updateVisuals(time: Float) { apply() }

    /// Turn the ring `steps` twelfths of a turn (positive: clockwise seen from above). It does not turn once the portal is open.
    func turn(_ steps: Int) {
        guard !isOpen, !sealed(), steps != 0 else { return }
        var a = ringAngle + Float(steps) * P.ringStep
        while a > .pi { a -= 2 * .pi }
        while a <= -.pi { a += 2 * .pi }
        ringAngle = a
        held = 0; cued = false
        apply()
        emit(.chime(.ringTurn))                                                    // F06 A4: the stone-on-brass grind and its detent
    }

    /// For tools and tests: put the ring at an exact angle.
    func setAngle(_ a: Float) { ringAngle = a; held = 0; cued = false; apply() }

    /// One fixed tick: the beam resting on the receiver counts up; at `holdSeconds` the portal opens if the gate is ready, otherwise the gate's line is said once.
    func step(_ dt: Float) {
        guard !isOpen, !sealed() else { return }
        guard aligned else { held = 0; cued = false; return }
        held += dt
        guard held >= P.holdSeconds else { return }
        let g = gate()
        if g.ready {
            state.set(Game.portalOpenFlag)
            emit(.chime(.lens))                                                    // the lamp answers
            apply()
        } else if !cued {
            cued = true
            if let cue = g.cue { say(cue) }
        }
    }

    /// The scene follows the state: the ring and its beam at the ring's angle, the gate lamps by the gate, the doorway when open.
    private func apply() {
        let place = translation(Layout.lighthouse)
        scene.update(LighthouseInterior.ringName) { $0.uniforms.model = place * rotationY(-self.ringAngle) }
        scene.update(P.beamName) { $0.uniforms.model = place * rotationY(-self.ringAngle) }
        let g = gate()
        let off = sealed()
        let lit = [g.altarSolved && !off, g.ilsePages >= GateState.pagesNeeded && !off, g.orenPages >= GateState.pagesNeeded && !off]
        for (k, name) in P.lampNames.enumerated() { scene.update(name) { $0.uniforms.emissive = lit[k] ? SIMD4(1.0, 0.72, 0.28, 2.5) : SIMD4(0, 0, 0, 0) } }
        let open = isOpen
        scene.update(P.portalName) { $0.hidden = !open }
    }
}
