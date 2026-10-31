import Foundation

/// Which account an object supports (S02 section 4: "Hers: I left her. His: she would not follow").
enum Claim: String, Codable, CaseIterable {
    case hers, his
    var title: String { self == .hers ? "Hers" : "His" }
    var next: Claim { self == .hers ? .his : .hers }
}

/// One thing found in the worlds that bears on a contradiction: here, a journal page. `supports` is the side the author of the data first had in mind; `defensible` is every side the page's words can honestly be
/// read as supporting (F07 B-contra, #80: the player mapped the pages "word for word" and was told they were wrong; the sides are interpretation, so the Notebook accepts any reading the text allows and
/// never says a player is wrong). `excerpt` is the few words the Notebook shows for it once the page is in the journal.
struct Evidence: Equatable {
    let page: Int
    let supports: Claim
    let defensible: Set<Claim>
    let excerpt: String
    /// S04: the Roll of Keepers' page reads differently on each route, so its line in the Notebook does too (nil: the same on both).
    var excerptOren: String? = nil
    func excerpt(route: PageAuthor) -> String { route == .oren ? (excerptOren ?? excerpt) : excerpt }
}

/// A contradiction (S03.9, first slice): two claims, and pieces of evidence the player sets, one by one, against one claim or the other. The game confirms only in GROUPS (S02: Obra Dinn's
/// rule): it says nothing until `groupSize` (three) found pieces are set; then it settles if every one set is a DEFENSIBLE reading of its page (`Evidence.defensible`), and otherwise says nothing at all:
/// the verdict is "Settled" or silence, never "wrong", never which (F07 B-contra, Q26). There are MORE pieces of evidence than the group (S03.10b), so any three found settle it. No penalty, no timer; the
/// Notebook records the player's own mapping (`StoryState.claims`). It does not gate anything (F05 S1); settled, it is kept (saved).
struct Contradiction: Equatable {
    let id: String
    let hers: String
    let his: String
    let evidence: [Evidence]
}

enum Contradictions {
    /// The one contradiction shipped in this slice. Wording is data, here only (the user may edit it; they have changed their mind about page wording before).
    static let all: [Contradiction] = [
        Contradiction(id: "who-left", hers: "He left me.", his: "She would not follow.", evidence: [
            // Defensible readings, with why (each page can be read word for word either way):
            //  4: Ilse writes that Oren asked for the lens and did not answer her: he went his own way (Hers: he left me), or he asked and she refused (His: she would not follow).
            //  5: Oren writes that he went through the lens first: he went ahead (Hers: he left me), or he went first and she did not come (His).
            //  8: Oren writes that he will be waiting where the wood ends: he went on ahead (Hers: he left me), or he is waiting for her to follow (His).
            //  9: Ilse writes that she would break the running rule again: she ran after him (His: she did follow), or she runs for the lamp, not for him (Hers).
            Evidence(page: 4, supports: .his, defensible: [.hers, .his], excerpt: "He asked again for the lens. He did not answer."),
            Evidence(page: 5, supports: .hers, defensible: [.hers, .his], excerpt: "I went through the lens first."),
            Evidence(page: 8, supports: .his, defensible: [.hers, .his], excerpt: "I will be waiting where the wood ends."),
            Evidence(page: 9, supports: .hers, defensible: [.hers, .his], excerpt: "I would break it again."),
            // S04 (optional, the Tide Archive's page 12, the Roll of Keepers): the fifth piece, shown in the Notebook only once a route has begun. Like the others it can be read either way: the Roll names
            // Maren and leaves her line blank (Ilse's route), or records Oren as lost (Oren's route): he went through first, or he was lost and did not leave. It never says wrong and never gates.
            Evidence(page: 12, supports: .hers, defensible: [.hers, .his], excerpt: "Maren's name, and after it a blank line.", excerptOren: "Oren. Through the lens first. Lost."),
        ]),
    ]
    static func find(_ id: String) -> Contradiction? { all.first { $0.id == id } }

    /// How many found pieces must be set before anything is said (Obra Dinn's group).
    static let groupSize = 3

    enum Verdict: Equatable {
        /// Fewer than `groupSize` found pieces are set: nothing is said.
        case incomplete
        case settled
    }

    /// The verdict on a set of assignments (page -> claim) for `c`, given which pages are found: only the pieces that are found AND set count; with at least `groupSize` of them, every one must be a
    /// defensible reading of its page to settle it. Anything else is `.incomplete`: the Notebook says nothing.
    static func judge(_ c: Contradiction, assignments: [Int: Claim], found: Set<Int>) -> Verdict {
        let set = c.evidence.filter { found.contains($0.page) && assignments[$0.page] != nil }
        guard set.count >= groupSize else { return .incomplete }
        return set.allSatisfy { e in assignments[e.page].map { e.defensible.contains($0) } ?? false } ? .settled : .incomplete
    }
}

extension Game {
    /// The contradictions the Notebook shows: those with at least one piece of evidence in the journal (nothing appears before something is found).
    var visibleContradictions: [Contradiction] {
        let found = Set(journal.collectedPages.map(\.number))
        return Contradictions.all.filter { c in c.evidence.contains { found.contains($0.page) } }
    }

    /// The pieces of evidence the Notebook lists for `c` now: the Archive's (the Roll of Keepers, page 12) only once a route has begun (it would give the place away before).
    func visibleEvidence(_ c: Contradiction) -> [Evidence] { c.evidence.filter { journal.archiveShown || !StoryPages.archiveIDs.contains($0.page) } }
    private func claimKey(_ id: String, _ page: Int) -> String { "\(id):\(page)" }
    func claim(_ id: String, page: Int) -> Claim? { story.claims[claimKey(id, page)].flatMap(Claim.init(rawValue:)) }
    func isSettled(_ id: String) -> Bool { story.contradictionsResolved.contains(id) }

    /// The verdict for a contradiction as it stands: settled once kept; otherwise judged from what the player has set.
    func verdict(_ id: String) -> Contradictions.Verdict {
        guard let c = Contradictions.find(id) else { return .incomplete }
        if isSettled(id) { return .settled }
        var assignments: [Int: Claim] = [:]
        for e in c.evidence { if let a = claim(id, page: e.page) { assignments[e.page] = a } }
        return Contradictions.judge(c, assignments: assignments, found: Set(journal.collectedPages.map(\.number)))
    }

    /// Set the evidence on `page` against `side` in one step (setting the side it already has unsets it, so a page can be taken back before the group is judged). Only found evidence can be set, a
    /// settled contradiction is kept as it is. When `groupSize` or more found pieces are set and every one is a defensible reading it is settled and saved; otherwise nothing
    /// happens and nothing is said (the player's mapping is kept as set). Returns false if nothing was changed.
    @discardableResult
    func setClaim(_ id: String, page: Int, to side: Claim) -> Bool {
        guard let c = Contradictions.find(id), c.evidence.contains(where: { $0.page == page }), !isSettled(id),
              journal.collectedPages.contains(where: { $0.number == page }) else { return false }
        story.claims[claimKey(id, page)] = claim(id, page: page) == side ? nil : side.rawValue
        switch verdict(id) {
        case .settled: story.contradictionsResolved.append(id); journal.addNotebookEntry()
        case .incomplete: break
        }
        return true
    }
}
