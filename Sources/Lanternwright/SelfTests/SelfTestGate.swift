import Foundation
import Metal

/// Self-tests: the gate (S03.3). Fixed numbers throughout (3 pages of each, 1 contradiction), not read back from the constants under test.
extension SelfTestRunner {
    func runGate() {
        guard name == "all" || name == "gate" || name == "story" else { return }
        func gate(altar: Bool = true, pages: [Int], resolved: [String] = [], known: Set<String> = [], waived: Bool = true) -> GateState {
            GateState.evaluate(altarSolved: altar, pages: pages, resolved: resolved, known: known, waived: waived)
        }
        check(GateState.pagesNeeded == 3 && GateState.contradictionsNeeded == 1, "gate: it asks for 3 pages of each sibling and one resolved contradiction (the user's numbers, 2026-10-28)")
        // Ilse wrote pages 1-4, Oren 5-8.
        check(gate(pages: [1, 2, 3, 5, 6, 7]).ready && gate(pages: [1, 2, 3, 5, 6, 7]).missing.isEmpty, "gate: altar solved, 3 + 3 pages, contradiction waived: ready")
        check(gate(pages: [1, 2, 5, 6, 7]).missing == [.ilsePages], "gate: two of Ilse's pages are not enough")
        check(gate(pages: [1, 2, 3, 5, 6]).missing == [.orenPages], "gate: two of Oren's pages are not enough")
        check(gate(pages: [1, 2, 3, 4, 5, 6, 7, 8]).ready && gate(pages: [1, 2, 3, 4]).missing == [.orenPages], "gate: all four of one sibling do not stand in for the other")
        check(gate(pages: [1, 1, 1, 5, 6, 7]).missing == [.ilsePages] && gate(pages: [1, 2, 2, 2, 5, 6, 7]).missing == [.ilsePages], "gate: a page counts once however many times it is listed")
        check(gate(pages: [1, 2, 3, 5, 6, 7, 99]).ready, "gate: a page id that does not exist counts for nobody (and does no harm)")
        check(gate(altar: false, pages: [1, 2, 3, 5, 6, 7]).missing == [.altar], "gate: without the altar it is not ready, whatever the pages")
        check(gate(altar: false, pages: []).missing == [.altar, .ilsePages, .orenPages], "gate: a fresh game is missing the altar and both sets of pages, in that order")
        // The contradiction: waived until S03.9; when it is not, one resolved (and existing) contradiction is needed, counted once.
        let full = [1, 2, 3, 5, 6, 7]
        check(gate(pages: full, waived: false).missing == [.contradiction], "gate: with the waiver off a resolved contradiction is needed")
        check(gate(pages: full, resolved: ["a"], known: ["a", "b"], waived: false).ready, "gate: one resolved contradiction satisfies it")
        check(gate(pages: full, resolved: ["a", "a"], known: ["a", "b"], waived: false).contradictionsResolved == 1, "gate: the same contradiction twice counts once")
        check(gate(pages: full, resolved: ["z"], known: ["a", "b"], waived: false).missing == [.contradiction], "gate: an id that is not a contradiction counts for nothing")
        // The waiver guard: the gate cannot ship without its contradiction condition the day contradictions exist (S03.9 must turn the waiver off).
        check(GateState.contradictionWaived == Contradictions.all.isEmpty, "gate: the contradiction condition is waived exactly while there are no contradictions (S03.9: set GateState.contradictionWaived = false when you add one)")
        // The quiet cues, by category, never a marker; none while the altar is what is missing.
        check(GateState.cue(for: [.altar, .ilsePages, .orenPages]) == nil && GateState.cue(for: []) == nil, "gate: no cue when ready, and none while the altar is still to do")
        check(GateState.cue(for: [.ilsePages]) == "You have heard only him." && GateState.cue(for: [.orenPages]) == "You have heard only her.", "gate: with one sibling's pages missing the cue says only the other has been heard")
        check(GateState.cue(for: [.ilsePages, .orenPages]) == "You have heard too little of either." && GateState.cue(for: [.contradiction]) == "Two accounts, and nothing yet that tells them apart.", "gate: too little of both, and the contradiction, each have their line")
        // In the game: the altar is `gw_end`, the pages are the journal's, restored from a save.
        let g = Game(scene: Scene.makeWorld(device: device))
        check(g.gate.missing == [.altar, .ilsePages, .orenPages] && !g.gate.ready, "gate: a new game is missing the altar and both sets of pages")
        for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
        check(g.gate.missing == [.altar], "gate: with 3 + 3 pages collected only the altar is missing")
        g.state.set("gw_end")
        check(g.gate.ready && g.gate.cue == nil, "gate: and with the altar solved the gate is ready")
        // Saved and loaded in the real two-world game (the altar's flag belongs to the Glass Wood's puzzle, which only a game with that world has).
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        let w = twoWorlds()
        for n in [1, 2, 3, 5, 6, 7] { w.restorePage(n) }
        w.state.set("gw_end")
        let again = twoWorlds()
        again.restore(w.makeSave())
        check(w.gate.ready && again.gate.ready && again.gate.missing.isEmpty, "gate: it is still ready after a save and a load")
        let partial = twoWorlds(); partial.restorePage(1); partial.state.set("gw_end")
        let partialAgain = twoWorlds(); partialAgain.restore(partial.makeSave())
        check(partialAgain.gate.missing == [.ilsePages, .orenPages], "gate: a save with the altar solved and one page loads with both page sets still missing")
    }
}
