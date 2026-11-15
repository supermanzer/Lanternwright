import Foundation
import simd

/// S05.3 (builder B, B5): Oren's route through the Tide Archive, the exterior half of the sibling split (docs/plans/S05-divergent-routes.md section 3). Builder A made the dome's brass tide-ORRERY, its
/// three WINDOWS and the prism's INPUTS (`World/OrenSite.swift`); this file makes the rules:
///  - **O1, the orrery (WATCH):** three brass arms sweep round the dial, one turn per tide cycle, and each lines up with one of the dome's windows once a cycle (`Orrery.alignmentClock`: as the falling
///    tide passes each gate's level, tide, wind, stone). A lined-up arm's bead brightens. The brass COLLAR has six notches (`Orrery.collarDetents`); each touch turns it one on. The beam's rhythm
///    (carried from Varrow: three flashes, the longest, the shortest, then the middle one) tells which notches count: the SHORTEST flash is the first notch and the tide's arm, the middle one the second and the wind's, the
///    longest the third and the stone's (the same ranks that strike the tone plates). Turn the collar to a notch while its arm is lined up and the arm is caught there and its window lights; the other
///    three notches, and a notch turned to at the wrong moment, do nothing (the arm runs on: no penalty). Three windows lit = the prism's three components exist (`ti_windows`).
///  - **O2, the prism ring (AIM)** is the existing ring, now fed by the windows: `TideArchivePuzzle.componentLit` lets a component rest on its gate's mark only while its window is lit (a dark
///    window's component is a dim ghost in the chamber, `PrismInputs`).
/// A0 (the tide marks) comes first on this route as on Ilse's (`IlseRoute` counts it for both): the collar answers only once the marks are counted. A player who turns it before that gets a nudge (the
/// guide light flares: Q86), not a word. Gated by `chosenPath == .oren`. Saved: the lit windows and the collar's notch are flags; a caught arm is held at its window's exact alignment (so a load puts it
/// back, a few degrees from where it was stopped), and everything A's scene holds (arms, windows, collar, prism) is re-applied after a load or a new scene.
final class OrenRoute: WorldPuzzle {
    // MARK: Data (the graph, the tests and the bots read these)
    static let windowFlags = ["ti_window_0", "ti_window_1", "ti_window_2"], windowsFlag = "ti_windows"
    static let collarName = "ti_orrery_collar"
    static let collarFlags = (0..<Orrery.collarDetents).map { "ti_collar_\($0)" }
    /// The notch that catches arm k (the beam rhythm's rank + 1: the shortest flash is the tide's), and the arm a notch catches (nil: a notch that does nothing).
    static func notch(forArm k: Int) -> Int { k + 1 }
    static func arm(atNotch n: Int) -> Int? { (1...3).contains(n) ? n - 1 : nil }
    /// B7 (Q104): the collar's notch now points at an arm that is still to be caught (a notch the right moment would answer): what makes its click louder. `Game.collarNotchHasArm` is the same for A.
    var notchHasArm: Bool { Self.arm(atNotch: notch).map { !lit($0) } ?? false }
    /// How long a window takes to come up once its arm is caught.
    static let windowSeconds: Float = 1.4
    /// The old machinery's tests (the ring on its own, with no windows) switch the windows' hold on the ring off.
    nonisolated(unsafe) static var windowsFeedRing = true

    var world: WorldKind { .tideArchive }
    private let state: PuzzleState
    private let animator: Animator
    private let emit: (GameEvent) -> Void
    private let scene: () -> Scene?
    private let route: () -> PageAuthor?
    private let clock: () -> Float
    private let nudge: () -> Void

    private(set) var notch = 0
    private var applied: [Bool]?
    private var touched = false
    /// Windows still coming up (their tween writes them), and the prism's components as shown (a lit window's component follows its light by the fade).
    private var fading = Set<Int>()
    private var shown = [false, false, false]
    private var prismShown: [Bool] { isActive && Self.windowsFeedRing ? shown : [true, true, true] }
    private weak var appliedScene: Scene?

    init(state: PuzzleState, animator: Animator, emit: @escaping (GameEvent) -> Void, scene: @escaping () -> Scene?, route: @escaping () -> PageAuthor?, clock: @escaping () -> Float, nudge: @escaping () -> Void) {
        self.state = state; self.animator = animator; self.emit = emit; self.scene = scene; self.route = route; self.clock = clock; self.nudge = nudge
    }

    // MARK: State
    var isActive: Bool { route() == .oren }
    func lit(_ k: Int) -> Bool { Self.windowFlags.indices.contains(k) && state.has(Self.windowFlags[k]) }
    var litCount: Int { Self.windowFlags.filter { state.has($0) }.count }
    var windowsDone: Bool { state.has(Self.windowsFlag) }
    /// Which components the prism has now: all three off Oren's route (as before S05), the lit windows on it.
    var prismLit: [Bool] { isActive && Self.windowsFeedRing ? (0..<3).map(lit) : [true, true, true] }

    // MARK: WorldPuzzle
    var persistentFlags: [String] { Self.windowFlags + [Self.windowsFlag] + Self.collarFlags }
    func restore(from flags: Set<String>) {
        for f in persistentFlags where flags.contains(f) { state.set(f) }
        notch = Self.collarFlags.firstIndex { state.has($0) } ?? 0
        applied = nil; fading = []
        if litCount == 3 { state.set(Self.windowsFlag) }
        reapply()
    }
    func handles(_ id: String) -> Bool { id == Self.collarName }
    func activate(_ id: String) { if id == Self.collarName { if isActive { turnCollar() } else { emit(.dormant) } } }          // B7 (Q103): on Ilse's route the collar is not hers

    // MARK: O1
    /// Turn the collar one notch on (the sixth goes back to the first). If it lands on a notch that catches an arm and that arm is lined up with its window now, the arm is caught and the window lights.
    func turnCollar() {
        guard isActive else { return }
        notch = (notch + 1) % Orrery.collarDetents
        for (n, f) in Self.collarFlags.enumerated() { state.set(f, n == notch) }
        if let sc = scene() { Orrery.setCollar(sc, detent: notch) }
        emit(.collar(armHere: notchHasArm))                                   // B7 (Q104): A's click can sound louder on a notch that has an arm
        guard let k = Self.arm(atNotch: notch), !lit(k) else { return }
        guard state.has(IlseRoute.marksFlag) else { nudge(); return }                    // the water has not been counted yet: nothing is asked of the instrument (the light flares)
        guard Orrery.aligned(k, clock: clock()) else { return }                          // the arm runs on
        catchArm(k)
    }
    private func catchArm(_ k: Int) {
        state.set(Self.windowFlags[k])
        if let sc = scene() { Orrery.hold(sc, k, at: Orrery.alignmentClock(k)) }
        emit(.chime(IlseRoute.markChime(k)))
        fading.insert(k)                                                                  // the tween below is the window's only writer until it ends (`reapply` leaves it alone)
        animator.tween(duration: Self.windowSeconds, ease: .inOutCubic) { [weak self] t in
            guard let self, let sc = self.scene() else { return }
            DomeWindows.set(sc, k, lit: t)
        }
        if litCount == 3 { state.set(Self.windowsFlag) }
        animator.after(Self.windowSeconds) { [weak self] in                                // the prism's component comes with the window's light, not before it
            guard let self else { return }
            self.fading.remove(k); self.shown[k] = true
            if let sc = self.scene() { PrismInputs.set(sc, lit: self.prismShown) }
            if self.litCount == 3 { self.emit(.chime(.lens)) }
        }
    }

    // MARK: Each tick
    func updateVisuals(time: Float) {
        let key = prismLit + [isActive]
        if key != applied || scene() !== appliedScene { reapply() }
    }
    /// Everything A's scene keeps for the orrery and the dome (it lives on the scene, not in the save): the caught arms, the windows, the collar and the prism's components.
    private func reapply() {
        guard let sc = scene() else { return }
        let active = isActive
        // Off Oren's route nothing here has changed the scene (A's own states and frames stay as they are), unless an earlier call on it did.
        if !active && !touched { applied = prismLit + [active]; appliedScene = sc; return }
        touched = true
        for k in 0..<3 {
            Orrery.hold(sc, k, at: active && lit(k) ? Orrery.alignmentClock(k) : nil)
            if !fading.contains(k) { DomeWindows.set(sc, k, lit: active && lit(k) ? 1 : 0) }
            shown[k] = lit(k) && !fading.contains(k)
        }
        Orrery.setCollar(sc, detent: active ? notch : 0)
        PrismInputs.set(sc, lit: prismShown)
        applied = prismLit + [active]; appliedScene = sc
    }
}
