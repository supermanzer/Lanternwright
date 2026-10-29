import Foundation

/// S03.1: what the story remembers beyond the puzzle flags. The two route flags (`path_ilse`, `path_oren`) are game-owned flags in `PuzzleState` (so they save and restore with the
/// others, in the "game" bucket); the rest lives here and in the save's optional `story` block (a save from before S03.1 has none: everything starts at its default).
struct StoryState: Codable, Equatable {
    /// How many of the lighthouse's glyphs the player understands (S02 section 3: answer, carry, hold, turn, chain). Pages with a `glyphLevel` above it show no margin lines yet.
    var glyphsKnown = 0
    /// Ids of the contradictions the player has resolved (S03.9 defines them); the gate wants at least one.
    var contradictionsResolved: [String] = []
    /// Ids of the notebook lines the player has read (`Story.notes`): the door note (S03.4), later the contradictions' margin lines.
    var notes: [String] = []
    /// What the player has set against each piece of evidence, `"<contradiction id>:<page>"` -> `"hers"` or `"his"` (S03.9).
    var claims: [String: String] = [:]

    init() {}
    /// Tolerant of a save written before a field existed (S03.1 saves have no `notes`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        glyphsKnown = try c.decodeIfPresent(Int.self, forKey: .glyphsKnown) ?? 0
        contradictionsResolved = try c.decodeIfPresent([String].self, forKey: .contradictionsResolved) ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        claims = try c.decodeIfPresent([String: String].self, forKey: .claims) ?? [:]
    }
    private enum CodingKeys: String, CodingKey { case glyphsKnown, contradictionsResolved, notes, claims }
}

extension Game {
    static let pathIlseFlag = "path_ilse", pathOrenFlag = "path_oren"

    /// The route the player has begun, or nil while undecided. Once set it is permanent (S02 section 1): the other exit is sealed for good.
    var chosenPath: PageAuthor? {
        if state.has(Game.pathIlseFlag) { return .ilse }
        if state.has(Game.pathOrenFlag) { return .oren }
        return nil
    }

    /// Begin a route. Returns false (and changes nothing) if the other route was begun first, or for anything but `.ilse` / `.oren`; beginning the same route again is a no-op that returns true.
    @discardableResult
    func choosePath(_ author: PageAuthor) -> Bool {
        guard author == .ilse || author == .oren else { return false }
        if let taken = chosenPath { return taken == author }
        state.set(author == .ilse ? Game.pathIlseFlag : Game.pathOrenFlag)
        return true
    }
}
