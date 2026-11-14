import Foundation
import simd

/// S03.6: the lighthouse's door opens by answering, not by a key (S02 section 2.2). Three plates beside it (tide, wind, stone) are struck in the order the lighthouse beam flashes them (P02.3; it was the stones' own order before);
/// each right strike keeps its tone sounding (held: the same sustained voices as the stones), a wrong one resets everything softly. When the third is struck the chord blooms and, if the
/// gate is ready (S03.3), the lamp answers and the door is open (`door_open`: the inside becomes real, S03.5). If the gate is NOT ready the chord blooms and fades, the gate's quiet
/// cue is shown (what KIND of thing is missing, never a marker) and the plates reset: nothing is lost and nothing is blocked for good.
///
/// Like the stones it speaks to the world only through events and flags. The held tones reuse the stones' drone events, so the audio side needs nothing new; builder A may give the
/// plates a voice of their own later (board topic `story`).
final class TonePlatePuzzle: WorldPuzzle {
    /// P02.3 (Q50, Q78): the answer is DATA read from the lighthouse beam, not a constant of this file. The beam flashes three groups (`Layout.Navigation.SignalPattern.groupSeconds`); the plates are
    /// struck in the order flashed, a group's LENGTH naming its plate by rank: the shortest = tide (plate 0), the middle = wind (1), the longest = stone (2). Today: stone, tide, wind.
    static var order: [Int] { order(fromGroupSeconds: Layout.Navigation.SignalPattern.groupSeconds) }
    /// The order a player reads from three watched lengths, by RANK and never by exact seconds (the beam's ramps trim a group by about 0.15 s, and a player counts nothing): each group's plate is the
    /// number of groups shorter than it. Ties are not a pattern (they would read the same plate twice).
    static func order(fromGroupSeconds seconds: [Float]) -> [Int] { seconds.map { g in seconds.filter { $0 < g }.count } }
    /// The order the stones were learned in (tide, wind, stone: the climb). Since P02.3 it is NOT the answer; it is the Notebook's fallback hint (`hintLine`), kept as data so the graph can say so.
    static let legacyOrder = [0, 1, 2]
    /// After this many wrong strikes in a game the Notebook gains `Story.platesHint`, once (never blocks, never states the answer).
    static let wrongsBeforeHint = 3
    enum Timing {
        static let wrongResetDelay: Float = 0.8
        /// From the third strike to the lamp's answer, and from the answer to the door being open.
        static let answerDelay: Float = 1.6, openDelay: Float = 1.2
        /// How long the bloom lasts before an unanswered set of plates resets.
        static let unansweredResetDelay: Float = 3.0
    }

    let world: WorldKind = .varrow
    private let state: PuzzleState
    private let animator: Animator
    private let emit: (GameEvent) -> Void
    private let gateReady: () -> Bool
    private let gateCue: () -> String?
    private let say: (String) -> Void
    /// True once Oren's route has begun: Ilse's exit is sealed for good and the plates only ring (S03.8).
    private let sealed: () -> Bool
    /// The Notebook line for a player who keeps missing (set by the game; a no-op until then).
    var hint: () -> Void = {}
    private(set) var wrongStrikes = 0

    private(set) var sequence: [Int] = []
    private var busy = false

    init(state: PuzzleState, animator: Animator, emit: @escaping (GameEvent) -> Void, gateReady: @escaping () -> Bool, gateCue: @escaping () -> String?, say: @escaping (String) -> Void, sealed: @escaping () -> Bool = { false }) {
        self.state = state; self.animator = animator; self.emit = emit; self.gateReady = gateReady; self.gateCue = gateCue; self.say = say; self.sealed = sealed
    }

    var isOpen: Bool { state.has(Game.doorOpenFlag) }

    // MARK: WorldPuzzle
    var persistentFlags: [String] { [] }                                  // the door's own flag is the game's (Game.ownFlags)
    func restore(from flags: Set<String>) { sequence = []; busy = false }
    func handles(_ id: String) -> Bool { TonePlates.names.contains(id) }
    func activate(_ id: String) { if let k = TonePlates.names.firstIndex(of: id) { strike(k) } }
    func updateVisuals(time: Float) {}

    private func chime(_ k: Int) -> ChimeKind { k == 0 ? .tide : (k == 1 ? .wind : .stone) }

    func strike(_ k: Int) {
        emit(.chime(chime(k)))
        guard !isOpen, !busy, !sealed() else { return }                  // after the door is open, once the exit is sealed, or while the chord blooms, the plates just ring
        if k == TonePlatePuzzle.order[sequence.count] {
            sequence.append(k)
            emit(.drone(k, true))
            if sequence.count == TonePlatePuzzle.order.count { complete() }
        } else {
            busy = true
            wrongStrikes += 1
            if wrongStrikes == TonePlatePuzzle.wrongsBeforeHint { hint() }
            emit(.chime(.fail))
            emit(.droneSour)
            animator.after(Timing.wrongResetDelay) { [weak self] in self?.reset() }
        }
    }

    private func reset() { sequence = []; busy = false }

    private func complete() {
        busy = true
        emit(.droneBloom)
        if gateReady() {
            animator.after(Timing.answerDelay) { [weak self] in
                self?.emit(.chime(.lens))                                 // the lamp answers
                self?.animator.after(Timing.openDelay) { [weak self] in
                    self?.state.set(Game.doorOpenFlag)
                    self?.sequence = []; self?.busy = false
                }
            }
        } else {
            if let cue = gateCue() { animator.after(Timing.answerDelay) { [weak self] in self?.say(cue) } }
            animator.after(Timing.unansweredResetDelay) { [weak self] in self?.reset() }
        }
    }
}
