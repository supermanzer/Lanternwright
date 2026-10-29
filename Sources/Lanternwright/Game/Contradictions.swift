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

/// A contradiction (S03.9, first slice): two claims, and a group of evidence the player sets, item by item, against one claim or the other. The game confirms only in GROUPS (S02: Obra
/// Dinn's rule): it says nothing while fewer than all of the group are found and set, and when they all are it says only that they agree with the story or not yet, never WHICH one is wrong,
/// so a guess is no use and nothing is punished. Settled, it is kept (saved) and is what the gate asks for.
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
        ]),
    ]
    static func find(_ id: String) -> Contradiction? { all.first { $0.id == id } }

    enum Verdict: Equatable {
        /// Some of the group is not found yet, or not set: nothing is said.
        case incomplete
        /// Every item is found and set, and they do not all agree with the story: said quietly, without saying which.
        case notYet
        case settled
    }

    /// The verdict on a set of assignments (page -> claim) for `c`, given which pages are found. Only a complete group is judged.
    static func judge(_ c: Contradiction, assignments: [Int: Claim], found: Set<Int>) -> Verdict {
        guard c.evidence.allSatisfy({ found.contains($0.page) && assignments[$0.page] != nil }) else { return .incomplete }
        return c.evidence.allSatisfy { assignments[$0.page] == $0.supports } ? .settled : .notYet
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

    /// The verdict for a contradiction as it stands: settled once kept; otherwise judged from what the player has set (only a complete group is judged).
    func verdict(_ id: String) -> Contradictions.Verdict {
        guard let c = Contradictions.find(id) else { return .incomplete }
        if isSettled(id) { return .settled }
        var assignments: [Int: Claim] = [:]
        for e in c.evidence { if let a = claim(id, page: e.page) { assignments[e.page] = a } }
        return Contradictions.judge(c, assignments: assignments, found: Set(journal.collectedPages.map(\.number)))
    }

    /// Set the evidence on `page` against the next account (unset -> Hers -> His -> Hers ...). Only found evidence can be set, and a settled contradiction is kept as it is. When the whole
    /// group is found and set and agrees with the story, it is settled and saved. Returns false if nothing was changed.
    @discardableResult
    func cycleClaim(_ id: String, page: Int) -> Bool {
        guard let c = Contradictions.find(id), c.evidence.contains(where: { $0.page == page }), !isSettled(id), journal.collectedPages.contains(where: { $0.number == page }) else { return false }
        story.claims[claimKey(id, page)] = (claim(id, page: page)?.next ?? .hers).rawValue
        if verdict(id) == .settled { story.contradictionsResolved.append(id); journal.addNotebookEntry() }
        return true
    }
}
