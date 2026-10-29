import Foundation
import Metal
import simd

/// Self-tests: the return to Varrow after the Glass Wood (S03.4): the signal state, the note nailed to the lighthouse door, the notebook line, and the way from the lens islet to the door.
extension SelfTestRunner {
    func runReturn() {
        guard name == "all" || name == "return" || name == "story" else { return }
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        var idle = InputState(); idle.move = .zero
        var clock = 2000.0
        func step(_ g: Game, _ n: Int = 2) { for _ in 0..<n { clock += 0.05; g.advance(now: clock, input: idle) } }
        func noteHidden(_ g: Game) -> Bool? { g.scenes[.varrow]?.items.first { $0.name == DoorNote.itemName }?.hidden }
        func noteEnabled(_ g: Game) -> Bool? { g.interactables.first { $0.id == DoorNote.itemName }?.enabled }

        check(Story.doorNote == "Whoever reads this: the lamp is waiting at the top. Bring what you have heard.", "return: the door note says what the user's draft says (a single constant, Story.doorNote)")
        check(Story.noteText("door_note") == Story.doorNote && Story.noteText("nothing") == nil, "return: the notebook line is looked up by id")

        // The state: a signal (and a note) only once the altar is solved AND the player is on Varrow.
        let g = twoWorlds()
        step(g)
        check(!g.hasReturned && !g.lighthouseSignal && noteHidden(g) == true && noteEnabled(g) == false, "return: in a new game there is no signal, and the note is neither seen nor readable")
        g.state.set("gw_end")
        step(g)
        check(g.world == .varrow && g.hasReturned && g.lighthouseSignal && noteHidden(g) == false && noteEnabled(g) == true, "return: with the altar solved and the player on Varrow, the signal is on and the note is on the door")
        g.travel(to: .glassWood); step(g)
        check(!g.hasReturned && !g.lighthouseSignal && noteHidden(g) == true, "return: in the Glass Wood there is no signal and the note is hidden again")
        g.travel(to: .varrow); step(g)
        check(g.hasReturned && noteHidden(g) == false && noteEnabled(g) == true, "return: back on Varrow it is there again")
        let early = twoWorlds(); early.travel(to: .glassWood); early.state.set("gw_ilse_heard"); early.state.set("gw_oren_heard"); step(early)
        early.travel(to: .varrow); step(early)
        check(!early.hasReturned && noteHidden(early) == true, "return: hearing the accounts is not enough: the altar's own flag (gw_end) is what counts")

        // Reading it: the journal opens on the Notebook, the line is logged once, and nothing about pages changes.
        let before = g.journal.collectedPages.map(\.number), gateBefore = g.gate
        g.activate(DoorNote.itemName)
        check(g.journal.isOpen && g.journal.tab == .notebook && g.story.notes == ["door_note"], "return: reading the note opens the journal on the Notebook and logs the line")
        step(g)
        check(!g.journal.hasUnread(.notebook), "return: and showing the Notebook clears its marker")
        g.journal.isOpen = false
        g.activate(DoorNote.itemName)
        check(g.story.notes == ["door_note"], "return: reading it again does not log it twice")
        check(g.journal.collectedPages.map(\.number) == before && g.gate == gateBefore, "return: the note is not a page: nothing collected, the gate's counts unchanged")
        // A line added while the journal is shut marks the tab (S03.2's rule), which is how a later notebook line reaches the player.
        var shut = JournalState(); shut.collect(1); shut.addNotebookEntry()
        check(shut.hasUnread(.notebook), "return: a notebook line added while the journal is shut marks its tab")
        // Save and load: the line is kept, the note and the signal follow the saved state.
        let again = twoWorlds(); again.restore(g.makeSave()); step(again)
        check(again.story.notes == ["door_note"] && again.hasReturned && noteHidden(again) == false, "return: a save keeps the logged line, and a game loaded on Varrow after the altar shows the note")
        let s31 = #"{"version":2,"worldFlags":{"varrow":["solved"]},"pages":[1],"position":[175,0.8,205],"yaw":0,"pitch":0,"playTime":1,"story":{"glyphsKnown":1,"contradictionsResolved":[]}}"#
        let old = try? JSONDecoder().decode(SaveData.self, from: Data(s31.utf8))
        check(old?.story?.glyphsKnown == 1 && old?.story?.notes == [], "return: a save from S03.1 (a story block without notes) still loads")

        // Where the signal points: along the way up from the islet, and at the door. Fixed numbers (the landmarks).
        let trail = Layout.Navigation.signalTrailPoint, door = Layout.Navigation.signalDoorPoint
        check(trail == SIMD3<Float>(-35, 1.5, -225) && abs(door.x + 30) < 1e-4 && abs(door.z - (-48 + 4.147 + 1)) < 0.05, "return: the signal points at the causeway's start (-35, -225) and at the door's south face (-30, about -42.9) (\(door))")
        // The note is on the door: its centre within the door's frame (x -0.55...0.55, between the straps at 1.05 and 1.75 m above the plinth), 4.1 m south of the tower's axis.
        let nc = DoorNote.worldCenter - Layout.lighthouse
        check(abs(nc.x) < 0.55 && nc.y > Lighthouse.baseY + 1.2 && nc.y < Lighthouse.baseY + 1.65 && abs(nc.z - 4.23) < 0.05, "return: the note hangs on the door between the lower and middle straps (\(nc))")

        // The way back, from the lens islet to the lighthouse door, along the corridors and with the real controller.
        let walkGame = twoWorlds()
        walkGame.puzzle.forceSolved(); walkGame.simulate(seconds: LighthousePuzzle.Timing.total + 1)
        walkGame.state.set("gw_end")
        walkGame.travel(to: .varrow)
        let arrival = SIMD2(walkGame.player.position.x, walkGame.player.position.z)
        let route = Layout.Navigation.varrow.route(from: arrival, to: SIMD2(door.x, door.z))
        var length: Float = 0
        var last = arrival
        for p in route { length += simd_length(p - last); last = p }
        length += simd_length(SIMD2(door.x, door.z) - last)
        let bot = PlaythroughBot(walkGame)
        let t0 = bot.elapsed
        // The route arrives at the tower from the north (the north descent) and the door is on its south face: a walker goes round by the east side to the foot of the steps.
        let lh = Layout.lighthouse
        let arrived = bot.follow([lh + SIMD3(9, 0, 0), lh + SIMD3(0, 0, 7)], within: 2.5)
        let seconds = bot.elapsed - t0
        if name == "return" { print("return: from the lens islet to the door: the corridors give \(Int(length)) m (\(route.count) nodes), the bot walks it in \(Int(seconds)) s, arrived \(arrived)") }
        check(!route.isEmpty && length > 250 && length < 520, "return: a route along the corridors exists from the lens-islet arrival to the lighthouse door: \(Int(length)) m over \(route.count) centre-line nodes")
        check(arrived && seconds < 170, "return: the player walks it with the real controller: \(Int(seconds)) s (arrived \(arrived))")
    }
}
