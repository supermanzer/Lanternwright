import Foundation
import simd

/// S05.3 (builder B): Ilse's route through the Tide Archive, the interior half of the sibling split (docs/plans/S05-divergent-routes.md section 3). Three puzzles and the shared opening:
///  - **A0, the tide marks (COUNT, shared):** the water passes three levels on its way up and down (the three sluice rooms' own levels, `IlseTones.matchLevel`). A player who stands within `markRadius` of the
///    quay they arrived at when the water crosses a level has COUNTED that mark: it chimes (the stones' tones, tide / wind / stone). All three counted = the way to the stacks is open (`marksFlag`).
///    No prop marks the levels yet (A's, Q80): the chime and the water are the only signs.
///  - **I1, the catalogue (READ + HEAR):** five shelf bays, each a glyph and a bell. The catalogue diagram (page art on page 10) draws three of them in order; ring them in that order with the fork.
///    A right bay rings and stays warm; a wrong one sours (and the bays go dormant again: the sequence starts over, nothing is lost). Rung right in full, the ledger room's door sinks and the brass
///    rod on its desk (the sluice-room key tone) can be taken.
///  - **I2, the bell pipes (HEAR, beats):** with the rod in hand, touch a sluice room's pipe to hold the fork to it. The pipe's pitch follows the tide (`IlseTones.pipeHz`); the fork holds the stones' tone;
///    the beats slow as the water nears the gate's level, and the gate answers at the moment they agree to within `IlseTones.agreeHz` (a CROSSING, not a timer: the match lasts about half a second at
///    mid-tide). Only the next gate in the stones' order answers; a pipe that agrees out of turn stays quiet and its crown glows (no penalty).
/// The old wheel-touch (the held tone) and the lens ring do not work on this route (`TideArchivePuzzle.touchHolds`, `ringWorks`): their gates are the pipes' now.
/// Everything is gated by `chosenPath == .ilse` except A0, which both routes share (nothing waits on it for Oren until his site is built). Nothing here is said in words: the bells, the glow, the beats and
/// the gate are the whole feedback. Builder A made the props and the sound; this file makes the rules.
final class IlseRoute: WorldPuzzle {
    // MARK: Data (the graph, the tests and the page art read these)
    static let marksFlag = "ti_marks", markFlags = ["ti_mark_0", "ti_mark_1", "ti_mark_2"]
    static let catalogueFlag = "ti_catalogue", keyFlag = "ti_rod"
    /// The catalogue's order: the bays to ring, first to last. It is NOT the stones' order (bays 0, 2, 4 ring the stones' tones): bay 3 is a decoy tone, then the tide's, then the stone's.
    static let sequence = [3, 0, 4]
    static let bayNames = (0..<ShelfBays.count).map { "ti_bay_\($0)" }
    static let pipeNames = (0..<3).map { "ti_pipe_\($0)" }
    static let keyName = "ti_rod_item"
    /// The water levels the three marks stand at (0...1): the middle of each sluice room's window, so a player who counted a mark knows when that room's gate hears its pipe.
    static var markLevels: [Float] { (0..<3).map(IlseTones.matchLevel) }
    /// A mark is counted from within this many metres of the quay the player arrived at (the quay and the first plaza).
    static let markRadius: Float = 40
    /// How long a wrong bay stays sour; how far from a pipe a held fork is let go; how long a bay's bell swings.
    static let sourSeconds: Float = 1.2, releaseDistance: Float = 7, swingSeconds: Float = 1.6
    /// The chime a mark gives: the stones' own tones, the highest level (the tide room's gate) first.
    static func markChime(_ k: Int) -> ChimeKind { k == 0 ? .tide : (k == 1 ? .wind : .stone) }

    var world: WorldKind { .tideArchive }
    private let state: PuzzleState
    private let animator: Animator
    private let emit: (GameEvent) -> Void
    private let scene: () -> Scene?
    private let tide: TideArchivePuzzle
    private let route: () -> PageAuthor?
    private let level: () -> Float
    private let player: () -> SIMD3<Float>
    private let inArchive: () -> Bool

    /// How many of the catalogue's bays have been rung right so far (0...3); the bays' looks now.
    private(set) var progress = 0
    private var looks = [ShelfBays.Look](repeating: .dormant, count: ShelfBays.count)
    private var swings = [Float](repeating: 0, count: ShelfBays.count)
    private var sourSerial = 0
    /// The pipe the fork is held at (nil: none).
    private(set) var holding: Int?
    private var lastLevel: Float?
    private var doorOpen: Float = 0

    init(state: PuzzleState, animator: Animator, emit: @escaping (GameEvent) -> Void, scene: @escaping () -> Scene?, tide: TideArchivePuzzle, route: @escaping () -> PageAuthor?, level: @escaping () -> Float,
         player: @escaping () -> SIMD3<Float>, inArchive: @escaping () -> Bool) {
        self.state = state; self.animator = animator; self.emit = emit; self.scene = scene; self.tide = tide; self.route = route; self.level = level; self.player = player; self.inArchive = inArchive
    }

    // MARK: State
    var isActive: Bool { route() == .ilse }
    var marksCounted: Int { Self.markFlags.filter { state.has($0) }.count }
    var marksDone: Bool { state.has(Self.marksFlag) }
    var catalogueDone: Bool { state.has(Self.catalogueFlag) }
    var hasRod: Bool { state.has(Self.keyFlag) }

    // MARK: WorldPuzzle
    var persistentFlags: [String] { Self.markFlags + [Self.marksFlag, Self.catalogueFlag, Self.keyFlag] }
    func restore(from flags: Set<String>) {
        for f in persistentFlags where flags.contains(f) { state.set(f) }
        progress = 0; holding = nil; lastLevel = nil; sourSerial += 1
        looks = [ShelfBays.Look](repeating: catalogueDone ? .warm : .dormant, count: ShelfBays.count)
        swings = [Float](repeating: 0, count: ShelfBays.count)
        doorOpen = catalogueDone ? 1 : 0
        syncBays(); syncDoor(); syncRod()
    }
    func handles(_ id: String) -> Bool { Self.bayNames.contains(id) || Self.pipeNames.contains(id) || id == Self.keyName }
    func activate(_ id: String) {
        guard isActive else { return }
        if let k = Self.bayNames.firstIndex(of: id) { ring(k) }
        else if let k = Self.pipeNames.firstIndex(of: id) { touchPipe(k) }
        else if id == Self.keyName { takeRod() }
    }

    // MARK: I1: the catalogue
    /// Ring bay k with the fork. Before the marks are counted a bay only rings (plain); after, it is the sequence; once the catalogue is done every bay rings warm and nothing changes.
    func ring(_ k: Int) {
        guard tide.hasFork, Self.bayNames.indices.contains(k) else { return }
        if catalogueDone { emit(.bell(k, false)); swing(k); return }
        guard marksDone else { emit(.bell(k, false)); swing(k); return }                       // the water has not been counted yet: the bell rings, nothing is asked of it
        if k == Self.sequence[progress] {
            emit(.bell(k, false)); progress += 1; looks[k] = .warm; swing(k); syncBays()
            if progress == Self.sequence.count { openCatalogue() }
        } else {
            emit(.bell(k, true)); swing(k)
            looks[k] = .sour; syncBays()
            sourSerial += 1; let serial = sourSerial
            animator.after(Self.sourSeconds) { [weak self] in
                guard let self, self.sourSerial == serial, !self.catalogueDone else { return }
                self.progress = 0; self.looks = [ShelfBays.Look](repeating: .dormant, count: ShelfBays.count); self.syncBays()
            }
        }
    }
    private func openCatalogue() {
        state.set(Self.catalogueFlag)
        animator.after(0.6) { [weak self] in self?.emit(.chime(.lens)) }
        animator.tween(duration: 3.0, ease: .inOutCubic) { [weak self] t in self?.doorOpen = t; self?.syncDoor() }
    }
    private func swing(_ k: Int) {
        animator.tween(duration: Self.swingSeconds, ease: .outCubic) { [weak self] t in
            guard let self else { return }
            self.swings[k] = (1 - t) * (k % 2 == 0 ? 1 : -1)
            self.syncBays(only: k)
        }
    }
    private func takeRod() {
        guard catalogueDone, !hasRod else { return }
        state.set(Self.keyFlag); emit(.chime(.lens)); syncRod()
    }

    // MARK: I2: the bell pipes
    /// Touch pipe k: hold the fork to it (or let it go, touching the same one again). Needs the rod.
    func touchPipe(_ k: Int) {
        guard tide.hasFork, hasRod, !tide.isSolved, Self.pipeNames.indices.contains(k) else { return }
        if holding == k { release(); return }
        if let h = holding { emit(.forkTone(h, false)) }
        holding = k
        emit(.forkTone(k, true))
    }
    private func release() { if let h = holding { emit(.forkTone(h, false)) }; holding = nil }
    /// The pipe's tone and the fork's, now (Hz), when the fork is held at pipe k.
    func pipeHz(_ k: Int) -> Float { IlseTones.pipeHz(k, level: level()) }
    func forkHz(_ k: Int) -> Float { ToneTable.stoneHz[k] }
    /// What the audio engine is fed while the fork is held: nil when it is not.
    var pipeInput: ArchiveAudio.Pipe? {
        guard let k = holding, isActive else { return nil }
        let d = simd_length(player() - BellPipes.holdPoint(k))
        return ArchiveAudio.Pipe(hz: pipeHz(k), gain: IlseTones.pipeGain(distance: d))
    }

    // MARK: Each tick
    func updateVisuals(time: Float) {
        guard inArchive(), let sc = scene() else { lastLevel = nil; return }
        let now = level(), me = player()
        // A0: a mark is counted when the water crosses its level while the player stands near their quay.
        if let was = lastLevel, route() != nil, !marksDone {
            let quay = route() == .oren ? ArchiveLayout.openEnd : ArchiveLayout.lampEnd
            if simd_length(SIMD2(me.x - quay.x, me.z - quay.z)) <= Self.markRadius {
                for (k, l) in Self.markLevels.enumerated() where !state.has(Self.markFlags[k]) && (was - l) * (now - l) <= 0 && was != now {
                    state.set(Self.markFlags[k]); emit(.chime(Self.markChime(k)))
                }
                if Self.markFlags.allSatisfy({ state.has($0) }) { state.set(Self.marksFlag); animator.after(1.2) { [weak self] in self?.emit(.chime(.lens)) } }
            }
        }
        lastLevel = now
        guard isActive else { release(); return }
        // I2: the pipes show the sea; the held one shows how well the fork agrees; the gate answers at the crossing.
        var agrees = [Float](repeating: 0, count: 3)
        if let k = holding {
            if simd_length(SIMD2(me.x, me.z) - SIMD2(ArchiveLayout.pipe(k).x, ArchiveLayout.pipe(k).z)) > Self.releaseDistance || tide.isSolved { release() }
            else {
                agrees[k] = IlseTones.agreement(pipeHz: pipeHz(k), forkHz: forkHz(k))
                if abs(pipeHz(k) - forkHz(k)) <= IlseTones.agreeHz, k == tide.opened, tide.answerByPipe(k) { release() }
            }
        }
        for k in 0..<3 { BellPipes.set(sc, k, level: now, agree: agrees[k]) }
    }

    // MARK: Visuals
    private func syncBays(only: Int? = nil) {
        guard let sc = scene() else { return }
        for k in (only.map { [$0] } ?? Array(0..<ShelfBays.count)) { ShelfBays.set(sc, k, look: looks[k], swing: swings[k]) }
    }
    private func syncDoor() { if let sc = scene() { LedgerRoom.setDoor(sc, open: doorOpen) } }
    private func syncRod() { scene()?.update(LedgerRoom.keyName) { $0.hidden = self.hasRod } }
}
