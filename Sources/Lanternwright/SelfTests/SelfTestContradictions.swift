import Foundation
import Metal

/// Self-tests: the Notebook's contradiction (S03.9): the grouping rule (confirms only a complete group, never marks a single answer), what the Notebook shows, settling, and the gate.
extension SelfTestRunner {
    func runContradictions() {
        guard name == "all" || name == "contradictions" || name == "story" else { return }
        let c = Contradictions.find("who-left")!
        let all = Set([4, 5, 8])

        // The data: one contradiction, a group of three pieces of evidence (pages 4, 5, 8) with a story-side each; the answer is mixed so "all the same" is not it.
        check(Contradictions.all.count == 1 && c.evidence.map(\.page) == [4, 5, 8] && c.evidence.map(\.supports) == [.his, .hers, .his] && Set(c.evidence.map(\.supports)).count == 2, "contradictions: one contradiction, three pieces of evidence (pages 4, 5, 8), supporting His, Hers, His")
        check(c.hers == "He left me." && c.his == "She would not follow.", "contradictions: the two accounts are the book's own (Hers: He left me. His: She would not follow.)")

        // The grouping rule (pure): nothing is judged until the whole group is found AND set; then only agreed or not yet, never which.
        let right: [Int: Claim] = [4: .his, 5: .hers, 8: .his]
        check(Contradictions.judge(c, assignments: right, found: all) == .settled, "contradictions: all three found and set right: settled")
        check(Contradictions.judge(c, assignments: [4: .his], found: all) == .incomplete && Contradictions.judge(c, assignments: [4: .his, 5: .hers], found: all) == .incomplete, "contradictions: one right answer, or two, is never confirmed or marked (incomplete)")
        check(Contradictions.judge(c, assignments: [4: .hers, 5: .hers], found: all) == .incomplete, "contradictions: nor are two wrong ones: nothing is said until the group is set")
        check(Contradictions.judge(c, assignments: right, found: [4, 5]) == .incomplete, "contradictions: all set but one page not found: incomplete")
        var oneWrong = right; oneWrong[5] = .his
        var allWrong: [Int: Claim] = [4: .hers, 5: .his, 8: .hers]
        check(Contradictions.judge(c, assignments: oneWrong, found: all) == .notYet && Contradictions.judge(c, assignments: allWrong, found: all) == .notYet, "contradictions: a full group with one wrong, or all wrong, is just 'not yet': the same verdict, so it never says which")
        allWrong[4] = .his
        check(Contradictions.judge(c, assignments: allWrong, found: all) == .notYet, "contradictions: and one more right (two of three) is still the same 'not yet'")

        // In the game.
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        let g = twoWorlds()
        check(g.visibleContradictions.isEmpty && g.verdict("who-left") == .incomplete, "contradictions: nothing appears in the Notebook before a piece of evidence is found")
        check(!g.cycleClaim("who-left", page: 4), "contradictions: evidence not found cannot be set")
        g.restorePage(4)
        check(g.visibleContradictions.map(\.id) == ["who-left"], "contradictions: the first piece of evidence found brings the contradiction into the Notebook")
        check(g.claim("who-left", page: 4) == nil && g.cycleClaim("who-left", page: 4) && g.claim("who-left", page: 4) == .hers && g.cycleClaim("who-left", page: 4) && g.claim("who-left", page: 4) == .his && g.cycleClaim("who-left", page: 4) && g.claim("who-left", page: 4) == .hers, "contradictions: pressing a piece of evidence cycles unset, Hers, His, Hers ...")
        check(!g.cycleClaim("who-left", page: 6) && !g.cycleClaim("nothing", page: 4), "contradictions: a page that is not evidence, or a contradiction that does not exist, changes nothing")
        g.cycleClaim("who-left", page: 4)          // now His (right)
        g.restorePage(5); g.restorePage(8)
        g.cycleClaim("who-left", page: 5); g.cycleClaim("who-left", page: 5)       // 5: Hers, then His (wrong)
        g.cycleClaim("who-left", page: 8)                                           // 8: Hers (wrong)
        check(g.verdict("who-left") == .notYet && !g.isSettled("who-left") && g.story.contradictionsResolved.isEmpty, "contradictions: three set, not all right: 'not yet', nothing settled")
        g.cycleClaim("who-left", page: 8)          // 8: His (right)
        check(g.verdict("who-left") == .notYet, "contradictions: two of three right is still 'not yet'")
        g.cycleClaim("who-left", page: 5)          // 5: Hers (right)
        check(g.verdict("who-left") == .settled && g.isSettled("who-left") && g.story.contradictionsResolved == ["who-left"], "contradictions: all three right: settled and kept")
        check(g.journal.hasUnread(.notebook), "contradictions: and the Notebook tab is marked (a line arrived)")
        let before = g.story.claims
        check(!g.cycleClaim("who-left", page: 4) && g.story.claims == before && g.story.contradictionsResolved == ["who-left"], "contradictions: once settled it is kept as it is")

        // The gate counts it, and it is saved.
        for n in [1, 2, 3, 6, 7] { g.restorePage(n) }
        g.state.set("gw_end")
        check(g.gate.ready && g.gate.missing.isEmpty, "contradictions: with the altar, the pages and the settled contradiction the gate is ready")
        let back = twoWorlds(); back.restore(g.makeSave())
        check(back.isSettled("who-left") && back.gate.contradictionsResolved == 1 && back.claim("who-left", page: 5) == .hers && back.verdict("who-left") == .settled, "contradictions: a save keeps the settled contradiction and what was set")
        let unsettled = twoWorlds(); for n in [1, 2, 3, 5, 6, 7, 4, 8] { unsettled.restorePage(n) }
        unsettled.state.set("gw_end")
        check(unsettled.gate.missing == [.contradiction] && unsettled.gate.cue == GateState.cueContradiction, "contradictions: without it the gate asks only for it, in its quiet line")
        // An older save (no claims) loads, and an unknown contradiction id in a save counts for nothing.
        let old = #"{"version":2,"worldFlags":{},"pages":[4],"position":[175,0.8,205],"yaw":0,"pitch":0,"playTime":1,"story":{"glyphsKnown":0,"contradictionsResolved":["no-such-thing"],"notes":[]}}"#
        let decoded = try? JSONDecoder().decode(SaveData.self, from: Data(old.utf8))
        let o = twoWorlds(); if let s = decoded { o.restore(s) }
        check(decoded != nil && o.story.claims.isEmpty && o.gate.contradictionsResolved == 0, "contradictions: a save without claims loads, and an id that is not a contradiction counts for nothing at the gate")
    }
}
