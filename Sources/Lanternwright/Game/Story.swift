import Foundation

/// S03: the story's own words that are not journal pages. Each is a single constant, so the user can edit it later (they have changed their mind about wording before, #56).
enum Story {
    /// The note nailed to the lighthouse door after the Glass Wood (user decision 2, 2026-10-28). Draft wording; read at the door, logged in the Notebook, not a page.
    static let doorNote = "Whoever reads this: the lamp is waiting at the top. Bring what you have heard."

    /// Notebook lines by id (what `StoryState.notes` holds), in the order they would be shown.
    static let notes: [(id: String, text: String)] = [("door_note", doorNote)]
    static func noteText(_ id: String) -> String? { notes.first { $0.id == id }?.text }
}
