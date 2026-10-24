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
        JournalPage(number: 3, text: "I tune the lamp each evening the way I first climbed this island: from the water, through the wind, to the stone. Out of order, they only argue."),
        JournalPage(number: 4, text: "Oren has asked again for the lens. He says light that can fold can also carry. Carry what, brother? He did not answer, and I did not like the silence."),
    ]
}

struct JournalState {
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
