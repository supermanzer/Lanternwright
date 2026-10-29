import Foundation

/// Which account an object supports (S02 section 4: "Hers: I left her. His: she would not follow").
enum Claim: String, Codable, CaseIterable {
    case hers, his
    var title: String { self == .hers ? "Hers" : "His" }
    var next: Claim { self == .hers ? .his : .hers }
}

/// One thing found in the worlds that bears on a contradiction: here, a journal page. `supports` is what the story says it supports (the truth the player is asked to work out);
/// `excerpt` is the few words the Notebook shows for it once the page is in the journal.
struct Evidence: Equatable {
    let page: Int
    let supports: Claim
    let excerpt: String
}

/// A contradiction (S03.9, first slice): two claims, and pieces of evidence the player sets, one by one, against one claim or the other. The game confirms only in GROUPS (S02: Obra Dinn's
/// rule): it says nothing until `groupSize` (three) found pieces are set; then it settles if every one set agrees with the story, and otherwise says only that the pages disagree, never WHICH
/// one is wrong. There are MORE pieces of evidence than the group (S03.10b), so any three found settle it and a player who overlooked one still has a way. There is no penalty (F05 S2, Q19): a wrong group
/// just stays as it is, with a quiet line, and the player may change any page. It does not gate anything (F05 S1); settled, it is kept (saved).
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
            Evidence(page: 4, supports: .his, excerpt: "He asked again for the lens. He did not answer."),
            Evidence(page: 5, supports: .hers, excerpt: "I went through the lens first."),
            Evidence(page: 8, supports: .his, excerpt: "I will be waiting where the wood ends."),
            Evidence(page: 9, supports: .hers, excerpt: "I would break it again."),         // S03.10b: the fourth; two for each account, so no all-the-same guess is right
        ]),
    ]
    static func find(_ id: String) -> Contradiction? { all.first { $0.id == id } }

    /// How many found pieces must be set before anything is said (Obra Dinn's group).
    static let groupSize = 3

    enum Verdict: Equatable {
        /// Fewer than `groupSize` found pieces are set: nothing is said.
        case incomplete
        /// A group is set and they do not all agree with the story: said quietly, without saying which.
        case notYet
        case settled
    }

    /// The verdict on a set of assignments (page -> claim) for `c`, given which pages are found: only the pieces that are found AND set count; with at least `groupSize` of them, every one must
    /// agree with the story to settle it.
    static func judge(_ c: Contradiction, assignments: [Int: Claim], found: Set<Int>) -> Verdict {
        let set = c.evidence.filter { found.contains($0.page) && assignments[$0.page] != nil }
        guard set.count >= groupSize else { return .incomplete }
        return set.allSatisfy { assignments[$0.page] == $0.supports } ? .settled : .notYet
    }
}

extension Game {
    /// The contradictions the Notebook shows: those with at least one piece of evidence in the journal (nothing appears before something is found).
    var visibleContradictions: [Contradiction] {
        let found = Set(journal.collectedPages.map(\.number))
        return Contradictions.all.filter { c in c.evidence.contains { found.contains($0.page) } }
    }

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
    /// settled contradiction is kept as it is. When `groupSize` or more found pieces are set and all agree with the story it is settled and saved; a wrong
    /// group is left as it is (the verdict says only 'not yet'). Returns false if nothing was changed.
    @discardableResult
    func setClaim(_ id: String, page: Int, to side: Claim) -> Bool {
        guard let c = Contradictions.find(id), c.evidence.contains(where: { $0.page == page }), !isSettled(id),
              journal.collectedPages.contains(where: { $0.number == page }) else { return false }
        story.claims[claimKey(id, page)] = claim(id, page: page) == side ? nil : side.rawValue
        switch verdict(id) {
        case .settled: story.contradictionsResolved.append(id); journal.addNotebookEntry()
        case .notYet, .incomplete: break
        }
        return true
    }
}
