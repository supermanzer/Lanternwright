import Foundation
import Metal

/// Self-tests: the Notebook's contradiction (S03.9): the grouping rule (confirms only a complete group, never marks a single answer), what the Notebook shows, settling, and the gate.
extension SelfTestRunner {
    func runContradictions() {
        guard name == "all" || name == "contradictions" || name == "story" else { return }
        let c = Contradictions.find("who-left")!
        let all = Set([4, 5, 8, 9])

        // The data: one contradiction, four pieces of evidence (pages 4, 5, 8, 9) with a story-side each, two and two, so no uniform guess is the answer; any three settle it.
        check(Contradictions.all.count == 1 && c.evidence.map(\.page) == [4, 5, 8, 9] && c.evidence.map(\.supports) == [.his, .hers, .his, .hers], "contradictions: one contradiction, four pieces of evidence (pages 4, 5, 8, 9), supporting His, Hers, His, Hers")
        check(Contradictions.groupSize == 3, "contradictions: three matched pieces judge it")
        check(c.hers == "He left me." && c.his == "She would not follow.", "contradictions: the two accounts are the book's own (Hers: He left me. His: She would not follow.)")

        // The grouping rule (pure): nothing is judged until three found pieces are set; then only agreed or not yet, never which.
        let right: [Int: Claim] = [4: .his, 5: .hers, 8: .his, 9: .hers]
        check(Contradictions.judge(c, assignments: right, found: all) == .settled, "contradictions: all four found and set right: settled")
        for skip in [4, 5, 8, 9] {
            var three = right; three[skip] = nil
            check(Contradictions.judge(c, assignments: three, found: all) == .settled, "contradictions: any three right settle it (without page \(skip))")
            check(Contradictions.judge(c, assignments: right, found: all.subtracting([skip])) == .settled, "contradictions: a player who never found page \(skip) still has a route (the other three)")
        }
        check(Contradictions.judge(c, assignments: [4: .his], found: all) == .incomplete && Contradictions.judge(c, assignments: [4: .his, 5: .hers], found: all) == .incomplete, "contradictions: one right answer, or two, is never confirmed or marked (incomplete)")
        check(Contradictions.judge(c, assignments: [4: .hers, 5: .hers], found: all) == .incomplete, "contradictions: nor are two wrong ones: nothing is said until three are set")
        check(Contradictions.judge(c, assignments: right, found: [4, 5]) == .incomplete, "contradictions: set but only two found: incomplete")
        // F07 B-contra (#80): the sides are interpretation. Every page can be read either way, so EVERY mapping of three or more found pieces is a defensible one and settles; nothing is ever 'wrong'.
        check(c.evidence.allSatisfy { $0.defensible == Set(Claim.allCases) } && c.evidence.allSatisfy { $0.defensible.contains($0.supports) }, "contradictions: the data lists, per page, the readings its words allow (both sides, each with its reason), and the author's own reading is among them")
        var settledCount = 0, anythingElse = 0
        for mask in 0..<16 {
            var a: [Int: Claim] = [:]
            for (k, e) in c.evidence.enumerated() { a[e.page] = (mask >> k) & 1 == 1 ? .his : .hers }
            let v = Contradictions.judge(c, assignments: a, found: all)
            if v == .settled { settledCount += 1 } else { anythingElse += 1 }
        }
        check(settledCount == 16 && anythingElse == 0, "contradictions: every one of the 16 ways to map the four pages settles: the player's own mapping is accepted (\(settledCount) of 16)")
        // A restriction, when the data has one, still works and still says nothing: a page whose only defensible reading is Hers, mapped to His, leaves the group unsettled, silently.
        let strict = Contradiction(id: "t", hers: "a", his: "b", evidence: [Evidence(page: 1, supports: .hers, defensible: [.hers], excerpt: ""), Evidence(page: 2, supports: .his, defensible: [.his, .hers], excerpt: ""), Evidence(page: 3, supports: .his, defensible: [.his, .hers], excerpt: "")])
        check(Contradictions.judge(strict, assignments: [1: .his, 2: .his, 3: .his], found: [1, 2, 3]) == .incomplete && Contradictions.judge(strict, assignments: [1: .hers, 2: .his, 3: .his], found: [1, 2, 3]) == .settled, "contradictions: a page with one defensible reading that is mapped the other way leaves the group unsettled, and the verdict is only 'incomplete' (silence), never 'wrong'")

        // In the game.
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        let g = twoWorlds()
        check(g.visibleContradictions.isEmpty && g.verdict("who-left") == .incomplete, "contradictions: nothing appears in the Notebook before a piece of evidence is found")
        check(!g.setClaim("who-left", page: 4, to: .his), "contradictions: evidence not found cannot be set")
        g.restorePage(4)
        check(g.visibleContradictions.map(\.id) == ["who-left"], "contradictions: the first piece of evidence found brings the contradiction into the Notebook")
        check(g.claim("who-left", page: 4) == nil && g.setClaim("who-left", page: 4, to: .hers) && g.claim("who-left", page: 4) == .hers && g.setClaim("who-left", page: 4, to: .his) && g.claim("who-left", page: 4) == .his && g.setClaim("who-left", page: 4, to: .his) && g.claim("who-left", page: 4) == nil, "contradictions: a piece is set to Hers or His directly, and setting its own side again takes it back")
        check(!g.setClaim("who-left", page: 6, to: .his) && !g.setClaim("nothing", page: 4, to: .his), "contradictions: a page that is not evidence, or a contradiction that does not exist, changes nothing")
        g.setClaim("who-left", page: 4, to: .his)
        g.restorePage(5); g.restorePage(8); g.restorePage(9)
        g.setClaim("who-left", page: 5, to: .his)
        check(g.verdict("who-left") == .incomplete, "contradictions: two set is still unjudged")
        // The third set page judges: any mapping settles (the player's own, never 'wrong'); to see the record, take it back and set another way.
        check(g.setClaim("who-left", page: 5, to: .his) && g.claim("who-left", page: 5) == nil, "contradictions: a page can be taken back at once")
        g.setClaim("who-left", page: 8, to: .hers)                                  // the player's own reading
        check(g.verdict("who-left") == .incomplete, "contradictions: two pieces set is still unjudged")
        g.setClaim("who-left", page: 9, to: .his)                                   // the third piece, mapped as the player reads it (pages 4, 8, 9: His, Hers, His)
        check(g.verdict("who-left") == .settled && g.isSettled("who-left") && g.story.contradictionsResolved == ["who-left"], "contradictions: three pieces set, in the player's own mapping, without page 5: settled and kept")
        check(g.claim("who-left", page: 4) == .his && g.claim("who-left", page: 8) == .hers && g.claim("who-left", page: 9) == .his, "contradictions: and the Notebook records the player's own mapping, not the author's")
        check(g.journal.hasUnread(.notebook), "contradictions: and the Notebook tab is marked (a line arrived)")
        let before = g.story.claims
        check(!g.setClaim("who-left", page: 4, to: .hers) && g.story.claims == before && g.story.contradictionsResolved == ["who-left"], "contradictions: once settled it is kept as it is")
        g.setClaim("who-left", page: 5, to: .hers)                                   // page 5 is found; a settled contradiction still takes nothing
        check(g.claim("who-left", page: 5) == nil, "contradictions: a settled contradiction takes no further press")

        // The gate counts it, and it is saved.
        for n in [1, 2, 3, 6, 7] { g.restorePage(n) }
        g.state.set("gw_end")
        check(g.gate.ready && g.gate.missing.isEmpty, "contradictions: with the altar, the pages and the settled contradiction the gate is ready")
        let back = twoWorlds(); back.restore(g.makeSave())
        check(back.isSettled("who-left") && back.gate.contradictionsResolved == 1 && back.claim("who-left", page: 9) == .his && back.verdict("who-left") == .settled, "contradictions: a save keeps the settled contradiction and what was set")
        let unsettled = twoWorlds(); for n in [1, 2, 3, 5, 6, 7, 4, 8] { unsettled.restorePage(n) }
        unsettled.state.set("gw_end")
        check(unsettled.gate.ready && unsettled.gate.cue == nil, "contradictions: without it the gate is still ready (F05 S1: it is optional)")
        check(GateState.evaluate(altarSolved: true, pages: [1, 2, 3, 5, 6, 7], resolved: [], waived: false).cue == GateState.cueContradiction, "contradictions: and with the gate constant turned back on it asks for it in its quiet line")
        // An older save (no claims) loads, and an unknown contradiction id in a save counts for nothing.
        let old = #"{"version":2,"worldFlags":{},"pages":[4],"position":[175,0.8,205],"yaw":0,"pitch":0,"playTime":1,"story":{"glyphsKnown":0,"contradictionsResolved":["no-such-thing"],"notes":[]}}"#
        let decoded = try? JSONDecoder().decode(SaveData.self, from: Data(old.utf8))
        let o = twoWorlds(); if let s = decoded { o.restore(s) }
        check(decoded != nil && o.story.claims.isEmpty && o.gate.contradictionsResolved == 0, "contradictions: a save without claims loads, and an id that is not a contradiction counts for nothing at the gate")
    }
}
