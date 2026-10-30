import Foundation

/// S03: the story's own words that are not journal pages. Each is a single constant, so the user can edit it later (they have changed their mind about wording before, #56).
enum Story {
    /// The note nailed to the lighthouse door after the Glass Wood (user decision 2, 2026-10-28). Draft wording; read at the door, logged in the Notebook, not a page.
    /// F05 S3 (#65): the quiet line at the moment the Glass Wood's altar is solved, so the player knows to go back (no prompt, no marker); the return ring also glows brighter from then on.
    static let lampWaitingLine = "The lamp is waiting."
    /// F06 B2b: the locked door's line once the player is back with the altar solved: one short line pointing at the plates without naming them.
    static let doorLockedReturned = "Locked. The stones beside it are listening."
    /// The line after the second account at the altar (the "(end of the second world)" suffix is gone from the player's text).
    static let endOfWorldLine = "Two accounts, one light. You will have to choose whose you carry."
    static let ilseAccount = "Ilse: \"He took the lens and went through before the lamp was lit. I have kept it burning for him since.\""
    static let orenAccount = "Oren: \"She would not follow, so I went ahead, and I have waited here since.\""
    static let doorNote = "Whoever reads this: the lamp is waiting at the top. Bring what you have heard."

    /// Notebook lines by id (what `StoryState.notes` holds), in the order they would be shown.
    static let notes: [(id: String, text: String)] = [("door_note", doorNote)]
    static func noteText(_ id: String) -> String? { notes.first { $0.id == id }?.text }
}
