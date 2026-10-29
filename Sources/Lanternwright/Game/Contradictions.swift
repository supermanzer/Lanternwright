import Foundation

/// The contradictions the player can resolve in the Notebook (S02 section 4). S03.9 fills this in; until then there are none, and the gate waives its contradiction condition
/// (`GateState.contradictionWaived`). `GateState.known` is this list's ids, so a resolved id that no longer exists never counts.
enum Contradictions {
    /// Stable ids, in the order the notebook lists them. Empty until S03.9.
    static let all: [String] = []
}
