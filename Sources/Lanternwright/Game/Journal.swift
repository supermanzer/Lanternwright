import Foundation

struct JournalPage {
    let number: Int
    let text: String
}

/// The keeper's journal: pages are found in the world and kept here for rereading. The pages themselves are data (`StoryPages`, S03.1).
enum JournalContent {
    static let pages: [JournalPage] = StoryPages.all.map { JournalPage(number: $0.id, text: $0.text) }
}

/// The journal's tabs (S03.2): one per sibling's pages, and the notebook. A tab shows only once there is something in it (`JournalState.visibleTabs`).
enum JournalTab: CaseIterable {
    case ilse, oren, notebook
    /// The author whose pages the tab holds (nil: the notebook).
    var author: PageAuthor? { self == .ilse ? .ilse : (self == .oren ? .oren : nil) }
    /// A page goes under its author's tab; a neutral page (none exists yet) goes with the keeper's, Ilse's.
    static func holding(_ author: PageAuthor) -> JournalTab { author == .oren ? .oren : .ilse }
    /// The line above the page.
    var heading: String { self == .oren ? "Oren's Journal" : "The Keeper's Journal" }
}

/// The notebook's three glyph entries (one per resonance stone): what the player has seen and struck.
enum Notebook {
    static func seenFlag(_ id: StoneID) -> String { "seen_\(id.name)" }
    static func struckFlag(_ id: StoneID) -> String { "struck_\(id.name)" }
    static let flags: [String] = StoneID.allCases.flatMap { [seenFlag($0), struckFlag($0)] }
    /// How close you must come before a stone's glyph counts as seen (it is carved at eye height on the arrival face).
    static let seenRadius: Float = 9
}

struct JournalState {
    var tab: JournalTab = .ilse
    private(set) var collected = Set<Int>()
    /// Pages the player has had open in the journal (or loaded from a save, which counts as read): the rest are unread, and mark their tab.
    private(set) var read = Set<Int>()
    /// A notebook line (the door note, S03.4, contradictions, S03.9) arrived and the Notebook tab has not been shown since.
    private(set) var notebookUnread = false
    var isOpen = false
    /// Index into `tabPages` (the pages of the current tab) of the page being read.
    var current = 0

    /// Every collected page, in number order: what the save stores. The journal shows them by tab (`pages(in:)`).
    var collectedPages: [JournalPage] { JournalContent.pages.filter { collected.contains($0.number) } }

    /// The collected pages that belong under `tab`, in number order.
    func pages(in tab: JournalTab) -> [JournalPage] {
        guard let author = tab.author else { return [] }
        return collectedPages.filter { JournalTab.holding(StoryPages.page($0.number)?.author ?? .ilse).author == author }
    }
    var tabPages: [JournalPage] { pages(in: tab) }

    /// Tabs with something to show: Ilse's from her first page (and while the journal is still empty, so there is a page to open on), Oren's from his first, the notebook always.
    var visibleTabs: [JournalTab] {
        var v: [JournalTab] = []
        if !pages(in: .ilse).isEmpty || collected.isEmpty { v.append(.ilse) }
        if !pages(in: .oren).isEmpty { v.append(.oren) }
        v.append(.notebook)
        return v
    }

    /// What the tab says on it: Pages while nothing has been read (no name is known yet), then the author's name.
    func title(_ tab: JournalTab) -> String {
        switch tab {
        case .ilse: return collected.isEmpty ? "Pages" : "Ilse"
        case .oren: return "Oren"
        case .notebook: return "Notebook"
        }
    }

    /// Does the tab hold something the player has not had open yet? Nothing counts before it is collected.
    func hasUnread(_ tab: JournalTab) -> Bool {
        tab == .notebook ? notebookUnread : pages(in: tab).contains { !read.contains($0.number) }
    }

    /// A page was collected: it goes under its author's tab, which opens on it.
    mutating func collect(_ number: Int) {
        collected.insert(number)
        tab = JournalTab.holding(StoryPages.page(number)?.author ?? .ilse)
        current = max(0, tabPages.firstIndex { $0.number == number } ?? 0)
    }

    /// A page restored from a save has been read.
    mutating func markRead(_ number: Int) { read.insert(number) }

    /// The journal is open on the current tab: the page in front of the player is read, and the Notebook tab, once shown, has nothing unread.
    mutating func markShown() {
        guard isOpen else { return }
        if tab == .notebook { notebookUnread = false }
        else if tabPages.indices.contains(current) { read.insert(tabPages[current].number) }
    }

    /// A line was added to the notebook.
    mutating func addNotebookEntry() { notebookUnread = true }

    mutating func flip(_ delta: Int) {
        let n = tabPages.count
        guard n > 0 else { return }
        current = min(max(current + delta, 0), n - 1)
    }

    /// Show `target` (ignored if it is not visible), on its first unread page, else its first.
    mutating func select(_ target: JournalTab) {
        guard visibleTabs.contains(target) else { return }
        tab = target
        current = tabPages.firstIndex { !read.contains($0.number) } ?? 0
    }

    /// Tab key: the next visible tab, round to the first.
    mutating func cycleTab() {
        let v = visibleTabs
        guard let i = v.firstIndex(of: tab) else { select(v[0]); return }
        select(v[(i + 1) % v.count])
    }
}
