import Foundation

/// What the gate between the Glass Wood and the fork still wants (S02 section 2.1, S03.3).
enum GateMissing: Equatable, CaseIterable {
    case altar, ilsePages, orenPages, contradiction
}

/// S03.3: is the player ready to choose a route? The altar is solved, at least `pagesNeeded` pages of EACH sibling are in the journal, and at least one contradiction is resolved.
/// Pure: `GateState.evaluate` takes numbers, `Game.gate` reads them from the game, so every rule is testable without a world. It never blocks anything by itself; it reports what is
/// missing, by category, for a quiet cue at the lens room (S03.5) and the notebook (never a marker).
struct GateState: Equatable {
    /// Pages of each sibling the gate asks for (the user confirmed 3 of each, 2026-10-28; pages can be overlooked, so this is not "all four").
    static let pagesNeeded = 3
    /// The contradiction condition was waived until there was a contradiction to resolve (S03.9 shipped one, so it is asked for now). `SelfTestGate` fails if this and `Contradictions.all` disagree.
    static let contradictionWaived = false
    /// Contradictions the gate wants resolved.
    static let contradictionsNeeded = 1

    var altarSolved: Bool
    var ilsePages: Int
    var orenPages: Int
    var contradictionsResolved: Int
    var contradictionWaived: Bool

    /// What is missing, in the order a player would meet it.
    var missing: [GateMissing] {
        var m: [GateMissing] = []
        if !altarSolved { m.append(.altar) }
        if ilsePages < GateState.pagesNeeded { m.append(.ilsePages) }
        if orenPages < GateState.pagesNeeded { m.append(.orenPages) }
        if !contradictionWaived && contradictionsResolved < GateState.contradictionsNeeded { m.append(.contradiction) }
        return m
    }
    var ready: Bool { missing.isEmpty }

    /// The numbers, clamped: counts never go below 0, and a resolved contradiction counts once, and only if it is one that exists.
    static func evaluate(altarSolved: Bool, pages: [Int], resolved: [String], known: Set<String> = Set(Contradictions.all.map(\.id)), waived: Bool = GateState.contradictionWaived) -> GateState {
        func count(_ a: PageAuthor) -> Int { Set(pages.filter { StoryPages.page($0)?.author == a }).count }
        return GateState(altarSolved: altarSolved, ilsePages: count(.ilse), orenPages: count(.oren),
                         contradictionsResolved: Set(resolved).intersection(known).count, contradictionWaived: waived)
    }

    /// The quiet line for what is missing (nil when ready, or while the altar is the thing missing: the world says that itself). Never a quest marker: it says what KIND of thing.
    /// Wording is data, here only.
    static let cueOnlyOren = "You have heard only him."          // Ilse's pages are missing: only Oren has been heard
    static let cueOnlyIlse = "You have heard only her."          // Oren's pages are missing: only Ilse has been heard
    static let cueTooLittle = "You have heard too little of either."
    static let cueContradiction = "Two accounts, and nothing yet that tells them apart."
    static func cue(for missing: [GateMissing]) -> String? {
        guard !missing.contains(.altar) else { return nil }
        switch (missing.contains(.ilsePages), missing.contains(.orenPages)) {
        case (true, true): return cueTooLittle
        case (true, false): return cueOnlyOren
        case (false, true): return cueOnlyIlse
        default: return missing.contains(.contradiction) ? cueContradiction : nil
        }
    }
    var cue: String? { GateState.cue(for: missing) }
}

extension Game {
    /// The gate as the game stands: the altar is solved when both accounts have been heard (`gw_end`), the pages are the journal's, the contradictions are the story's.
    var gate: GateState {
        GateState.evaluate(altarSolved: state.has("gw_end"), pages: journal.collectedPages.map(\.number), resolved: story.contradictionsResolved)
    }
}
