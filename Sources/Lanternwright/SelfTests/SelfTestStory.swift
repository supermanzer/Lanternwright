import Foundation
import CryptoKit
import Metal

/// Self-tests: the story's data and its save (S03.1). The page text is the user's to change (they changed their mind once already, #56), so it is pinned: a hash of every page's UTF-8
/// bytes as it stood on `main` when S03.1 began. If you MEANT to change a page, change its hash here in the same commit and say so in the commit message.
extension SelfTestRunner {
    func runStory() {
        guard name == "all" || name == "story" else { return }
        func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description }
        let pinned: [Int: String] = [1: "8d22e0f2dc14b25f", 2: "86f87e928ada0630", 3: "2243ff480bc14b15", 4: "561cfbc8deb2ffb8",
                                     5: "86e5c27c6f0cf494", 6: "1ab3060595cf8ae5", 7: "602ddb09393e0d31", 8: "87ac886b7d441cbe", 9: "8944080ea1c4554e"]
        let drifted = StoryPages.all.filter { pinned[$0.id] != sha($0.text) }.map(\.id)
        check(StoryPages.all.map(\.id) == Array(1...9) && drifted.isEmpty, "story: the nine pages are in order and every text is byte-identical to its pin: 1, 2, 3, 6, 7, 8 as on main at the start of S03.1, 4, 5 and 9 as revised in S03.10 (changed: \(drifted))")
        check(JournalContent.pages.map(\.number) == StoryPages.all.map(\.id) && JournalContent.pages.map(\.text) == StoryPages.all.map(\.text), "story: the journal's pages are the story data, number for number and word for word")
        check(StoryPages.ids(by: .ilse) == [1, 2, 3, 4, 9] && StoryPages.ids(by: .oren) == [5, 6, 7, 8] && StoryPages.ids(by: .neutral).isEmpty && StoryPages.varrowIDs == [1, 2, 3, 4, 9] && StoryPages.glassIDs == [5, 6, 7, 8], "story: Ilse wrote the five Varrow pages (page 9 on the dock), Oren the four Glass Wood pages")
        check(Set(StoryPages.all.map(\.location)).count == 9 && StoryPages.all.allSatisfy { !$0.location.isEmpty && $0.glyphLevel == 0 }, "story: every page has its own location key and no page has margin lines yet")

        // The approved revisions (S02 appendix R1 to R3, user decision 6, 2026-10-28), spelled out so a change is deliberate: page 5 begins with the new first sentence and keeps the rest, page 4
        // gains its half-line after the old ending, page 9 is the new Ilse page, and pages 3 and 8 are as they were.
        // S04.7: the Tide Archive's six pages, each in two voices, pinned as the others are (docs/plans/S04-page-drafts.md).
        let archivePins: [Int: (String, String)] = [10: ("0398a0324f3043b1", "365cb97bbe8735cc"), 11: ("50712f9717ce14c1", "2db422054fcf8bf2"), 12: ("6ebb33d4b173c1f6", "a0176a5f0866747d"), 13: ("a68c198842fdf4d8", "e90d440eed787b0f"), 14: ("671d73847cf928f1", "19a4e858b368d676"), 15: ("59143fa237fe87e5", "5ea6cb84b8896109")]
        let archiveDrift = StoryPages.archive.filter { p in guard let pin = archivePins[p.id] else { return true }; return sha(p.ilse) != pin.0 || sha(p.oren) != pin.1 }.map(\.id)
        check(StoryPages.archiveIDs == Array(10...15) && archiveDrift.isEmpty, "story: the Tide Archive's pages 10 to 15 are in order and every text, in both voices, is byte-identical to its pin (drift: \(archiveDrift))")
        check(StoryPages.archive.allSatisfy { $0.ilse != $0.oren && !$0.ilse.isEmpty && !$0.oren.isEmpty }, "story: each Archive page has its own text in each sibling's voice")
        check(StoryPages.archivePage(15)!.ilse.contains("Come on, I") && StoryPages.archivePage(11)!.ilse.contains("Come on, I") && StoryPages.archivePage(11)!.oren.contains("Hold your tone until the lamp answers") && StoryPages.archivePage(13)!.ilse.contains("chalk arrow") && StoryPages.archivePage(13)!.oren.contains("tuning fork") && StoryPages.archivePage(15)!.oren.contains("lamp is burning"), "story: pages 11, 13 and 15 carry the other sibling's trace, which the narrator quotes (Oren's chalk, Ilse's rule-plate and fork, her lamp)")
        check(!StoryPages.archive.contains { $0.ilse.lowercased().contains("maren is dead") || $0.oren.lowercased().contains("dead") || $0.oren.lowercased().contains("died") } && StoryPages.archivePage(12)!.ilse.contains("Maren") && StoryPages.archivePage(15)!.ilse.contains("\"to the\""), "story: Maren stays ambiguous: named, blank, torn, never said to be dead")
        check(Set(StoryPages.all.map(\.id)).isDisjoint(with: StoryPages.archiveIDs), "story: the Archive's pages are not among the nine the gate counts")
        let t = { (n: Int) in StoryPages.page(n)?.text ?? "" }
        check(t(5).hasPrefix("The week before the fog, I went through the lens first. Ilse will say I stole it, and she will be right about the lens and wrong about the reason."), "story: R1: page 5 begins 'The week before the fog, I went through the lens first.' and goes on as before")
        check(t(4).hasPrefix("Oren has asked again for the lens of the lighthouse lamp. He says light that can fold can also carry. Carry what, brother? He did not answer, and I did not like the silence.") && t(4).hasSuffix(" I told him the lens room is not a place for the impatient, which is not what he asked."), "story: R3: page 4 keeps its words and gains 'I told him the lens room is not a place for the impatient, which is not what he asked.' at the end")
        check(t(9) == "Rule the first: keepers do not run on the shingle. Rule the second: keepers run when the lamp in the lighthouse is going out. I have broken the second only twice, and I would break it again." && StoryPages.page(9)?.author == .ilse, "story: R2: page 9 is Ilse's, and reads as drafted (plus the lighthouse, F07 B-lamp)")
        // F07 B-lamp (#76): Ilse's pages 1, 2, 4 and 9 place the lamp in the lighthouse; pages 3 and 8 stay exactly as they were (pinned above).
        check([1, 2, 4, 9].allSatisfy { t($0).contains("lighthouse") } && [1, 2, 4, 9].allSatisfy { StoryPages.page($0)?.author == .ilse }, "story: B-lamp: Ilse's pages 1, 2, 4 and 9 each say where the lamp is (in the lighthouse)")
        check(t(3) == "I tune the lamp each evening the way I first climbed this island: from the water, through the wind, to the stone. Out of order, they only argue." && t(8).hasPrefix("Two accounts will reach you, and they will not agree."), "story: B-lamp: pages 3 and 8 are untouched")
        check(t(3) == "I tune the lamp each evening the way I first climbed this island: from the water, through the wind, to the stone. Out of order, they only argue." && t(8).hasPrefix("Two accounts will reach you, and they will not agree."), "story: page 3 is exactly as restored in F04 T1 and page 8 is unchanged")

        let numerals = StoryPages.all.map { OverlayView.roman($0.id) }
        check(Set((1...15).map { OverlayView.roman($0) }).count == 15 && OverlayView.roman(10) == "X" && OverlayView.roman(15) == "XV", "story: the page headings run to XV, all different (the Archive's pages)")
        check(Set(numerals).count == 9 && OverlayView.roman(9) == "IX" && OverlayView.roman(8) == "VIII" && !numerals.contains(""), "story: the nine page headings are all different (page 9 reads IX, not a second VIII): \(numerals)")
        check(Viewpoints.pageApproach(9) == SIMD3(Layout.dockStrip().a.x, 0, Layout.dockStrip().a.y) && Viewpoints.pageView(scene: Scene.makeWorld(device: device), name: "page-stand-9") != nil, "story: the dev page cameras know page 9 (approach from the landward end of the dock)")

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

        // S03.2: the journal's tabs. Pure state (JournalState), so none of it needs a window.
        var j = JournalState()
        check(j.visibleTabs == [.ilse, .notebook] && j.title(.ilse) == "Pages" && !j.hasUnread(.ilse) && !j.hasUnread(.oren) && !j.hasUnread(.notebook), "tabs: an empty journal shows Pages and Notebook, nothing unread")
        j.isOpen = false
        j.collect(2)
        check(j.tab == .ilse && j.visibleTabs == [.ilse, .notebook] && j.title(.ilse) == "Ilse" && j.hasUnread(.ilse) && !j.hasUnread(.oren), "tabs: Ilse's first page names her tab, which is unread until it is shown")
        j.markShown()
        check(j.hasUnread(.ilse), "tabs: a page is not read while the journal is shut")
        j.isOpen = true; j.markShown()
        check(!j.hasUnread(.ilse), "tabs: it is read once it is in front of the player in the open journal")
        j.collect(5)
        check(j.tab == .oren && j.visibleTabs == [.ilse, .oren, .notebook] && j.hasUnread(.oren) && !j.hasUnread(.ilse), "tabs: Oren's first page opens his tab and marks only his tab")
        check(j.pages(in: .oren).map(\.number) == [5] && j.pages(in: .ilse).map(\.number) == [2] && j.pages(in: .notebook).isEmpty, "tabs: each tab holds only its author's pages")
        j.collect(1); j.collect(6)
        j.flip(-9); check(j.tab == .oren && j.tabPages[j.current].number == 5, "tabs: flipping stays inside the tab")
        j.flip(9); check(j.tabPages[j.current].number == 6, "tabs: and stops at its last page")
        j.select(.ilse)
        check(j.tab == .ilse && j.tabPages[j.current].number == 1, "tabs: selecting a tab opens its first unread page (Ilse's page 1)")
        j.cycleTab(); check(j.tab == .oren, "tabs: Tab goes to the next visible tab")
        j.cycleTab(); check(j.tab == .notebook, "tabs: and on to the notebook")
        j.cycleTab(); check(j.tab == .ilse, "tabs: and round to the first")
        var few = JournalState(); few.collect(1)
        few.select(.oren); check(few.tab == .ilse, "tabs: a tab with nothing in it cannot be selected")
        few.cycleTab(); few.cycleTab(); check(few.tab == .ilse, "tabs: and Tab skips it (Ilse, Notebook, round)")
        // The notebook: a line added while it is not open marks the tab until it is shown.
        var nb = JournalState(); nb.collect(1); nb.isOpen = true; nb.markShown()
        nb.addNotebookEntry()
        check(nb.hasUnread(.notebook), "tabs: a notebook line marks the notebook tab")
        nb.markShown(); check(nb.hasUnread(.notebook), "tabs: showing the Pages tab does not clear it")
        nb.select(.notebook); nb.markShown(); check(!nb.hasUnread(.notebook), "tabs: showing the notebook does")
        // Nothing appears before the page is collected: no tab and no marker for a page that is not in the journal.
        let none = JournalState()
        check(!none.hasUnread(.ilse) && !none.hasUnread(.oren) && none.pages(in: .oren).isEmpty && !none.visibleTabs.contains(.oren), "tabs: no marker and no Oren tab before one of his pages is collected")
        // In the game: a page restored from a save is read; a page picked up is not until the journal shows it.
        let tg = fresh()
        tg.restorePage(3); tg.restorePage(5)
        check(!tg.journal.hasUnread(.ilse) && !tg.journal.hasUnread(.oren), "tabs: pages restored from a save count as read")
        tg.restorePage(6, read: false)
        check(tg.journal.hasUnread(.oren) && tg.journal.tab == .oren, "tabs: a page picked up opens its author's tab, unread")
        tg.journal.isOpen = true
        var idle = InputState(); idle.move = .zero
        tg.advance(now: 500, input: idle)
        check(!tg.journal.hasUnread(.oren), "tabs: the game marks the open page read on its next frame")
        var tabKey = InputState(); tabKey.tabPressed = true
        tg.advance(now: 500.1, input: tabKey)
        check(tg.journal.tab == .notebook, "tabs: the Tab key moves along the visible tabs (Oren to Notebook)")
    }
}
