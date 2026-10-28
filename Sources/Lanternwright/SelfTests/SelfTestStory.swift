import Foundation
import CryptoKit
import Metal

/// Self-tests: the story's data and its save (S03.1). The page text is the user's to change (they changed their mind once already, #56), so it is pinned: a hash of every page's UTF-8
/// bytes as it stood on `main` when S03.1 began. If you MEANT to change a page, change its hash here in the same commit and say so in the commit message.
extension SelfTestRunner {
    func runStory() {
        guard name == "all" || name == "story" else { return }
        func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description }
        let pinned: [Int: String] = [1: "1d6b37740915dbc7", 2: "e272f0ff6d62259b", 3: "2243ff480bc14b15", 4: "e03b471a0681bf00",
                                     5: "e86587d10ca93831", 6: "1ab3060595cf8ae5", 7: "602ddb09393e0d31", 8: "87ac886b7d441cbe"]
        let drifted = StoryPages.all.filter { pinned[$0.id] != sha($0.text) }.map(\.id)
        check(StoryPages.all.map(\.id) == Array(1...8) && drifted.isEmpty, "story: the eight pages are in order and every text is byte-identical to main at the start of S03.1 (changed: \(drifted))")
        check(JournalContent.pages.map(\.number) == StoryPages.all.map(\.id) && JournalContent.pages.map(\.text) == StoryPages.all.map(\.text), "story: the journal's pages are the story data, number for number and word for word")
        check(StoryPages.ids(by: .ilse) == [1, 2, 3, 4] && StoryPages.ids(by: .oren) == [5, 6, 7, 8] && StoryPages.ids(by: .neutral).isEmpty, "story: Ilse wrote the four Varrow pages, Oren the four Glass Wood pages")
        check(Set(StoryPages.all.map(\.location)).count == 8 && StoryPages.all.allSatisfy { !$0.location.isEmpty && $0.glyphLevel == 0 }, "story: every page has its own location key and no page has margin lines yet")

        func fresh() -> Game { Game(scene: Scene.makeWorld(device: device)) }
        // Round trip: pages by id, the route, glyphs, contradictions, through the JSON the save file holds.
        let g = fresh()
        g.restorePage(1); g.restorePage(5)
        check(g.chosenPath == nil && g.choosePath(.oren) && g.chosenPath == .oren, "story: a route can be begun once")
        g.story.glyphsKnown = 2; g.story.contradictionsResolved = ["her-or-his"]
        let saved = g.makeSave()
        let decoded = try? JSONDecoder().decode(SaveData.self, from: JSONEncoder().encode(saved))
        check(decoded == saved, "story: the save survives a JSON round trip unchanged")
        let h = fresh(); h.restore(decoded ?? saved)
        check(h.journal.collectedPages.map(\.number) == [1, 5] && h.chosenPath == .oren && !h.state.has(Game.pathIlseFlag) && h.story == g.story && h.story.glyphsKnown == 2 && h.story.contradictionsResolved == ["her-or-his"],
              "story: restore brings back the pages by id, the route, the glyphs and the resolved contradictions")

        // Old saves load: version 2 without the story block, and a version 1 flat flag list.
        let v2 = #"{"version":2,"worldFlags":{"varrow":["solved"]},"pages":[1,2],"position":[175,0.8,205],"yaw":0,"pitch":0,"playTime":10}"#
        let v1 = #"{"version":1,"flags":["solved","lensTouched"],"pages":[3],"position":[175,0.8,205],"yaw":0,"pitch":0,"playTime":10}"#
        let old2 = try? JSONDecoder().decode(SaveData.self, from: Data(v2.utf8)), old1 = try? JSONDecoder().decode(SaveData.self, from: Data(v1.utf8))
        let o2 = fresh(); if let s = old2 { o2.restore(s) }
        let o1 = fresh(); if let s = old1 { o1.restore(s) }
        check(old2 != nil && old2?.story == nil && o2.story == StoryState() && o2.chosenPath == nil && o2.journal.collectedPages.map(\.number) == [1, 2] && o2.state.has("solved"), "story: a version 2 save from before S03.1 loads with the story at its defaults")
        check(old1 != nil && o1.story == StoryState() && o1.chosenPath == nil && o1.journal.collectedPages.map(\.number) == [3] && o1.state.has("lensTouched"), "story: a version 1 save still loads, with the story at its defaults")

        // Exclusivity: whichever route is begun first stays; the other cannot be begun, in play or from a save.
        let e = fresh()
        check(!e.choosePath(.neutral) && e.chosenPath == nil, "story: neutral is not a route")
        check(e.choosePath(.ilse) && !e.choosePath(.oren) && e.chosenPath == .ilse && !e.state.has(Game.pathOrenFlag) && e.choosePath(.ilse), "story: with Ilse's route begun, Oren's cannot be (and beginning Ilse's again changes nothing)")
        let both = SaveData(worldFlags: [SaveData.gameBucket: [Game.pathIlseFlag, Game.pathOrenFlag]], pages: [], position: [175, 0.8, 205], yaw: 0, pitch: 0, playTime: 0)
        let b = fresh(); b.restore(both)
        check(b.chosenPath == nil && !b.state.has(Game.pathIlseFlag) && !b.state.has(Game.pathOrenFlag), "story: a save claiming both routes is treated as undecided, not as either")
        let kept = fresh(); kept.restore(e.makeSave())
        check(kept.chosenPath == .ilse && !kept.choosePath(.oren), "story: a route begun, saved and restored is still sealed against the other")
    }
}
