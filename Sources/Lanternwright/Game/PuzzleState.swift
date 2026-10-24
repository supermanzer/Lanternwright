import Foundation

/// Things that happened that the outside world (audio, overlay) should react to. The game logic never touches the
/// speakers or the UI directly: it emits events, which keeps it testable without either.
enum GameEvent: Equatable {
    case chime(ChimeKind)
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
