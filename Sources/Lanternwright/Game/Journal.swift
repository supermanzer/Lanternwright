import Foundation

struct JournalPage {
    let number: Int
    let text: String
}

/// The keeper's journal: pages are found in the world and kept here for rereading. The pages themselves are data (`StoryPages`, S03.1).
enum JournalContent {
    static let pages: [JournalPage] = StoryPages.all.map { JournalPage(number: $0.id, text: $0.text) }
}

enum JournalTab { case pages, notebook }

/// The notebook's three glyph entries (one per resonance stone): what the player has seen and struck.
enum Notebook {
    static func seenFlag(_ id: StoneID) -> String { "seen_\(id.name)" }
    static func struckFlag(_ id: StoneID) -> String { "struck_\(id.name)" }
    static let flags: [String] = StoneID.allCases.flatMap { [seenFlag($0), struckFlag($0)] }
    /// How close you must come before a stone's glyph counts as seen (it is carved at eye height on the arrival face).
    static let seenRadius: Float = 9
}

struct JournalState {
    var tab: JournalTab = .pages
    private(set) var collected = Set<Int>()
    var isOpen = false
    /// Index into `collectedPages` of the page being read.
    var current = 0

    var collectedPages: [JournalPage] { JournalContent.pages.filter { collected.contains($0.number) } }

    mutating func collect(_ number: Int) {
        collected.insert(number)
        current = max(0, collectedPages.firstIndex { $0.number == number } ?? 0)
    }

    mutating func flip(_ delta: Int) {
        let n = collectedPages.count
        guard n > 0 else { return }
        current = min(max(current + delta, 0), n - 1)
    }
}
