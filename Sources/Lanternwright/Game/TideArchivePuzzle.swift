import Foundation
import simd

/// S04.6: the Tide Archive's key puzzle (S02 section 3.4, S04): open three sluices in the stones' order (tide, wind, stone) to drain the Great Ledger gallery. Each sluice answers only at its own water
/// level (`Tide.windows`). Two solutions, one machine:
///  - **Ilse's way (held tones):** with the tuning fork, touch a sluice: its tone sounds and is held for `toneHold` seconds; if the water is at that sluice's level when the hold ends, and it is the
///    next sluice in order, the gate opens.
///  - **Oren's way (turned beam):** with the lens, turn the ring in front of the prism until the beam's component for a sluice falls on it (`beamTargets`), and keep it there for `beamHold` seconds:
///    the same two conditions.
/// A sluice out of order closes them all again (a soft fail chime, the tones sour: nothing is lost); a sluice at the wrong water level just does not answer (the soft fail). Nothing is ever said: the
/// water, the tones and the gates are the whole feedback. Each route starts with its own tool; the other tool lies in the world (`ti_find_fork`, `ti_find_lens`) and teaches the other way: using a
/// way successfully at least once marks it (`ti_way_tone`, `ti_way_beam`), which the optional third ending counts (S02 section 8).
/// Behind `Game.tideArchiveEnabled` until the world (builder A, S04.1) lands; its landmarks are `TideStandIn` until then.
final class TideArchivePuzzle: WorldPuzzle {
    enum Timing {
        static let toneHold: Float = 3.0, beamHold: Float = 2.0
        static let wrongResetDelay: Float = 0.8
        /// From the third gate to the gallery being drained (the solved flag), and how long the drain takes to show.
        static let drainDelay: Float = 2.5, drainDuration: Float = 6.0
    }
    static let sluiceFlags = ["ti_sluice_0", "ti_sluice_1", "ti_sluice_2"]
    static let forkFlag = "ti_tool_fork", lensFlag = "ti_tool_lens", wayTone = "ti_way_tone", wayBeam = "ti_way_beam", drainedFlag = "ti_drained"
    static let ringName = "ti_prism_ring", findForkName = "ti_find_fork", findLensName = "ti_find_lens"
    static let sluiceNames = ["ti_sluice_0", "ti_sluice_1", "ti_sluice_2"]
    /// The ring's turn: 15 degrees a touch, the same as the lighthouse's; the beam angle that feeds each sluice (multiples of a step), and how near it must be.
    static let ringStep: Float = .pi / 12
    static let beamTargets: [Float] = [-6 * ringStep, -2 * ringStep, 3 * ringStep]
    static let beamTolerance: Float = 3 * .pi / 180
    static let initialRing: Float = 0

    var world: WorldKind { Game.routeWorldOverride ?? .glassWood }
    private let state: PuzzleState
    private let animator: Animator
    private let emit: (GameEvent) -> Void
    private let level: () -> Float
    private let scene: () -> Scene?
    private let solved: () -> Bool
    private(set) var ringAngle: Float = TideArchivePuzzle.initialRing
    private var busy = false
    private var ringSerial = 0

    init(state: PuzzleState, animator: Animator, emit: @escaping (GameEvent) -> Void, level: @escaping () -> Float, scene: @escaping () -> Scene?, solved: @escaping () -> Bool) {
        self.state = state; self.animator = animator; self.emit = emit; self.level = level; self.scene = scene; self.solved = solved
    }

    // MARK: State
    /// How many gates are open, in order (they only ever open in order, so this is also the next one's index).
    var opened: Int { TideArchivePuzzle.sluiceFlags.prefix { state.has($0) }.count }
    var hasFork: Bool { state.has(TideArchivePuzzle.forkFlag) }
    var hasLens: Bool { state.has(TideArchivePuzzle.lensFlag) }
    var knowsTones: Bool { state.has(TideArchivePuzzle.wayTone) }
    var knowsBeam: Bool { state.has(TideArchivePuzzle.wayBeam) }
    var isSolved: Bool { solved() }

    // MARK: WorldPuzzle
    var persistentFlags: [String] { TideArchivePuzzle.sluiceFlags + Array(TideArchivePuzzle.tableauFlags.values) + [TideArchivePuzzle.forkFlag, TideArchivePuzzle.lensFlag, TideArchivePuzzle.wayTone, TideArchivePuzzle.wayBeam, TideArchivePuzzle.drainedFlag] }
    func restore(from flags: Set<String>) {
        tableauShown = nil
        for f in persistentFlags where flags.contains(f) { state.set(f) }
        busy = false; ringSerial += 1; ringAngle = TideArchivePuzzle.initialRing
        syncVisuals(drain: state.has(TideArchivePuzzle.drainedFlag) ? 1 : 0)
        // A save taken between the third gate and the drain (the 2.5 s delay) has all three gates open and the world not yet solved: finish it, or nothing ever would.
        if opened == TideArchivePuzzle.sluiceFlags.count && !state.has(Game.routeSolvedFlag) { complete() }
    }
    func handles(_ id: String) -> Bool { TideArchivePuzzle.sluiceNames.contains(id) || TideArchivePuzzle.tableauLightNames.contains(id) || id == TideArchivePuzzle.ringName || id == TideArchivePuzzle.findForkName || id == TideArchivePuzzle.findLensName }
    func activate(_ id: String) {
        if let k = TideArchivePuzzle.sluiceNames.firstIndex(of: id) { touchSluice(k) }
        else if id == TideArchivePuzzle.ringName { turn(1) }
        else if let side = [PageAuthor.ilse, .oren].first(where: { TideArchivePuzzle.tableauLightName($0) == id }) { lightTableau(from: side) }
        else if id == TideArchivePuzzle.findForkName { state.set(TideArchivePuzzle.forkFlag); emit(.chime(.lens)) }
        else if id == TideArchivePuzzle.findLensName { state.set(TideArchivePuzzle.lensFlag); emit(.chime(.lens)) }
    }
    func updateVisuals(time: Float) { syncVisuals(drain: nil) }

    private func chime(_ k: Int) -> ChimeKind { k == 0 ? .tide : (k == 1 ? .wind : .stone) }

    // MARK: The shadow-play tableau (optional, S04)
    /// The version on the wall now (nil: dark), and whether each has been seen.
    private(set) var tableauShown: PageAuthor?
    func tableauSeen(_ side: PageAuthor) -> Bool { TideArchivePuzzle.tableauFlags[side].map { state.has($0) } ?? false }
    /// Which sides' lanterns can be reached: the route's own from the start, the other once the first version has been seen.
    func tableauSideAvailable(_ side: PageAuthor, route: PageAuthor?) -> Bool { side == route || (route != nil && tableauSeen(route!)) }
    /// Light the lantern from `side`: that side's version of the moment falls on the wall (the other goes dark), and it is remembered as seen.
    func lightTableau(from side: PageAuthor) {
        guard side == .ilse || side == .oren, let flag = TideArchivePuzzle.tableauFlags[side] else { return }
        emit(.chime(.lens))
        tableauShown = side
        state.set(flag)
        syncVisuals(drain: nil)
    }

    // MARK: Ilse's way: the held tone
    func touchSluice(_ k: Int) {
        emit(.chime(chime(k)))                                                       // a touch always rings, with the fork or without
        guard hasFork, !isSolved, !busy, k >= opened, TideArchivePuzzle.sluiceNames.indices.contains(k) else { return }
        busy = true
        emit(.drone(k, true)); emit(.forkTone(k, true))
        animator.after(Timing.toneHold) { [weak self] in self?.endAttempt(k, .tone) }
    }

    // MARK: Oren's way: the turned beam
    /// Turn the ring `steps` quarter-twelfths (positive: clockwise seen from above). The beam is where the ring points; resting on a sluice's mark for `beamHold` s tries that sluice.
    func turn(_ steps: Int) {
        guard hasLens, !isSolved, steps != 0 else { return }
        var a = ringAngle + Float(steps) * TideArchivePuzzle.ringStep
        while a > .pi { a -= 2 * .pi }
        while a <= -.pi { a += 2 * .pi }
        ringAngle = a
        ringSerial += 1
        syncVisuals(drain: nil)
        guard !busy, let k = aimedSluice else { return }
        let serial = ringSerial
        animator.after(Timing.beamHold) { [weak self] in
            guard let self, self.ringSerial == serial, self.aimedSluice == k else { return }
            self.endAttempt(k, .beam)
        }
    }
    /// The sluice the beam's component is on now, if any.
    var aimedSluice: Int? {
        TideArchivePuzzle.beamTargets.indices.first { k in
            var d = abs(ringAngle - TideArchivePuzzle.beamTargets[k]).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            return d <= TideArchivePuzzle.beamTolerance
        }
    }

    // MARK: The attempt
    private enum Way { case tone, beam }
    private func endAttempt(_ k: Int, _ way: Way) {
        busy = false
        emit(.drone(k, false)); if way == .tone { emit(.forkTone(k, false)) }
        guard !isSolved, k == opened || !state.has(TideArchivePuzzle.sluiceFlags[k]) else { return }
        guard Tide.inWindow(k, level: level()) else {                                // the water is not at that gate's level: it hears nothing and goes on holding
            emit(.chime(.fail))
            return
        }
        guard k == opened else {                                                     // out of order: every gate closes again, softly
            busy = true
            emit(.chime(.fail)); emit(.droneSour)
            animator.after(Timing.wrongResetDelay) { [weak self] in self?.closeAll() }
            return
        }
        state.set(TideArchivePuzzle.sluiceFlags[k])
        emit(.sluice(k, true))
        state.set(way == .tone ? TideArchivePuzzle.wayTone : TideArchivePuzzle.wayBeam)
        emit(.chime(.ignite))
        syncVisuals(drain: nil)
        if opened == TideArchivePuzzle.sluiceFlags.count { complete() }
    }

    private func closeAll() {
        for (k, f) in TideArchivePuzzle.sluiceFlags.enumerated() where state.has(f) { emit(.sluice(k, false)) }
        for f in TideArchivePuzzle.sluiceFlags { state.set(f, false) }
        busy = false
        syncVisuals(drain: nil)
    }

    private func complete() {
        busy = true
        emit(.droneBloom)
        animator.after(Timing.drainDelay) { [weak self] in
            guard let self else { return }
            self.state.set(Game.routeSolvedFlag)
            self.state.set(TideArchivePuzzle.drainedFlag)
            self.animator.tween(duration: Timing.drainDuration, ease: .inOutCubic) { [weak self] t in self?.syncVisuals(drain: t) }
            self.busy = false
        }
    }

    // MARK: Visuals (named items; the stand-in world has none of them, builder A's Archive does)
    private func syncVisuals(drain: Float?) {
        guard let sc = scene() else { return }
        for (k, name) in TideArchivePuzzle.sluiceNames.enumerated() {
            let open = state.has(TideArchivePuzzle.sluiceFlags[k])
            sc.update(name) { $0.uniforms.emissive = open ? SIMD4(0.55, 0.85, 1.0, 1.4) : SIMD4(0, 0, 0, 0) }                  // the stand-in's gate glows
            sc.update(ArchiveProps.gateName(k)) { $0.uniforms.model = ArchiveProps.sluiceGateModel(k, open: open ? 1 : 0) }      // A's gate lifts and its wheel has turned twice
            sc.update(ArchiveProps.wheelName(k)) { $0.uniforms.model = ArchiveProps.sluiceWheelModel(k, turns: open ? 2 : 0) }
            sc.update(ArchiveProps.beamOutName(k)) { $0.uniforms.emissive.w = open || aimedSluice == k ? 1.6 : 1.0 }             // the dispersed beam of the sluice the ring rests on, or has opened, brightens
        }
        for side in [PageAuthor.ilse, .oren] { sc.update(ShadowTableaux.archive.lanternItems[side]!) { $0.uniforms.emissive = self.tableauShown == side ? SIMD4(1.0, 0.72, 0.3, 2.2) : SIMD4(0, 0, 0, 0) } }
        if let d = drain { sc.update("ti_gallery_water") { $0.uniforms.model = translation(SIMD3(0, -3.5 * d, 0)) } }
    }
}
