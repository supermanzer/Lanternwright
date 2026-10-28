import Foundation

struct JournalPage {
    let number: Int
    let text: String
}

/// The keeper's journal: pages are found in the world and kept here for rereading.
enum JournalContent {
    static let pages: [JournalPage] = [
        JournalPage(number: 1, text: "Day one of the last season. The lamp has gone quiet again. Oren says I fuss over it like a child. Perhaps. But a lighthouse that does not answer is only a tower."),
        JournalPage(number: 2, text: "The stones remember the sea best. I strike the tide-stone first, always: everything on this island begins at the water."),
        JournalPage(number: 3, text: "I tune the lamp each evening the way I first climbed this island: from the water, through the wind, to the stone. Out of order, they only argue."),          // F04 T1 (#56): restored exactly as first written (the 2026-10-23 reword told the order outright; the world already carries it in its rank notches)
        JournalPage(number: 4, text: "Oren has asked again for the lens. He says light that can fold can also carry. Carry what, brother? He did not answer, and I did not like the silence."),
        // The Glass Wood: Oren's journal.
        JournalPage(number: 5, text: "I went through the lens first. Ilse will say I stole it, and she will be right about the lens and wrong about the reason. The wood on this side is made of glass, and it hums. I wrote down what the stones taught us: water, wind, stone. They mean something here too."),
        JournalPage(number: 6, text: "Light is not carried, Ilse. It is turned. Three mirrors, three panes of glass: I set them by the order on the wall, the way the keeper climbs. Water, wind, stone. When the beam arrives in that order, the wood answers."),
        JournalPage(number: 7, text: "The chimes at the pool are tuned to the same three tones as the stones on the island. I did not need a mural for these. I only had to remember how each stone sounded when we were children, and she let me strike them first."),
        JournalPage(number: 8, text: "Two accounts will reach you, and they will not agree. Hers says I left her. Mine says she would not follow. Read both, then choose whose light you carry. I will be waiting where the wood ends. — O."),
    ]
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
