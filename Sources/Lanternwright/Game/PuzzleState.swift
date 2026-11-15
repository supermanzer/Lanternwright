import Foundation

/// Things that happened that the outside world (audio, overlay) should react to. The game logic never touches the
/// speakers or the UI directly: it emits events, which keeps it testable without either.
enum GameEvent: Equatable {
    case chime(ChimeKind)
    /// How hard the player is trying the locked door, 0...1 (rises with repeated attempts within a few seconds); sent just before its chime (F03 A2).
    case doorTry(Float)
    case pageCollected(Int)
    case journalOpened
    case journalClosed
    case whiteoutStarted
    case feedbackRequested
    case worldChanged(WorldKind)
    /// Sustained voice for stone i (a drone made of the stones' own tones) switched on/off.
    case drone(Int, Bool)
    case droneSour       // a wrong strike: the drone detunes and fades
    case droneBloom      // the puzzle is solved: the full chord blooms
    /// The lamp's answer motif (S03.4, builder A plays it): once on the return to Varrow after the altar, and again each time the player comes within `Game.answerPhraseRadius` of the lighthouse door after
    /// `Game.answerPhraseQuiet` seconds away. Never once the door is open or a route is begun.
    case answerPhrase
    /// S04.4: a sluice gate of the Tide Archive opening (true) or closing (false), and the tuning fork's tone for a stone held (true) or let go: builder B's Archive audio plays them.
    case sluice(Int, Bool)
    case forkTone(Int, Bool)
    /// S05.3: a shelf bay's bell struck on the Ilse route (bay, sour).
    case bell(Int, Bool)
    /// S05.4 / A5: orrery arm k passes its dome window (Q92); the gain 0...1 is already scaled by the listener's distance (`Orrery.tickGain`).
    case orreryTick(Int, Float)
    /// B7 (Q103): the player pressed a machine that is not theirs (the other sibling's bays, pipes and key on Oren's route; the orrery's collar on Ilse's; the sluice wheels' tuning-fork touch and the lens ring on Ilse's): one dull, quiet tick and nothing else, so it reads as "not yours", never as broken. Builder A's audio voice maps it (`ArchiveAudio.Event.dormant`); until then it is silent.
    case dormant
    /// B7 (Q104): the orrery's collar turned a notch: `armHere` is true when that notch has an arm that can be caught (the notch is right; the moment may not be), so a click can sound louder on it. Builder A's audio maps it (`Orrery.clickGain`).
    case collar(armHere: Bool)
}

/// The world's memory: named flags (a "blackboard"). Puzzles read and write these, and rendering reads them,
/// so puzzle logic never needs to know how anything looks.
final class PuzzleState {
    private(set) var flags = Set<String>()
    var onChange: ((String, Bool) -> Void)?

    func has(_ flag: String) -> Bool { flags.contains(flag) }

    func set(_ flag: String, _ on: Bool = true) {
        let changed = on ? flags.insert(flag).inserted : (flags.remove(flag) != nil)
        if changed { onChange?(flag, on) }
    }
}
