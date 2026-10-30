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
        // F05 S3 (#65): the way back is told without a prompt: the lamp's line when the altar is solved, and the return ring brightens.
        func glow(_ g: Game, _ name: String) -> Float? { g.scenes[.glassWood]?.items.first { $0.name == name }?.uniforms.emissive.w }
        let tell = twoWorlds(); tell.travel(to: .glassWood); step(tell); tell.simulate(seconds: 6)
        check(tell.banner == nil && glow(tell, "gw_return_ring") == 2.2 && glow(tell, "gw_return_core") == 5.0, "return: before the altar the Glass Wood's return ring is at its base glow and nothing is said")
        tell.state.set("gw_end"); step(tell)
        check(tell.banner == nil, "return: the line does not replace the account the player has just read (no banner at the moment of the altar's end)")
        tell.simulate(seconds: Game.lampLineDelay + 0.5); step(tell)
        check(tell.banner == Story.lampWaitingLine, "return: once the accounts and the end line have been read the lamp's line is said (\(tell.banner ?? "nothing"))")
        check((glow(tell, "gw_return_ring") ?? 0) > 3.5 && (glow(tell, "gw_return_core") ?? 0) > 6.5, "return: and the return ring and its core are brighter from then on")
        let t1 = glow(tell, "gw_return_core"); for _ in 0..<8 { step(tell) }
        check(glow(tell, "gw_return_core") != t1 && (glow(tell, "gw_return_core") ?? 0) > 6.5, "return: and they breathe rather than sit still, never dimming back toward the base")
        let loaded = twoWorlds(); loaded.state.set("gw_end"); loaded.travel(to: .glassWood); step(loaded)
        check(loaded.banner == nil && (glow(loaded, "gw_return_core") ?? 0) > 6.5, "return: arriving in the Glass Wood with the altar already solved (a loaded save) says nothing again, but the ring is lit")
        let early = twoWorlds(); early.travel(to: .glassWood); early.state.set("gw_ilse_heard"); early.state.set("gw_oren_heard"); step(early)
        early.travel(to: .varrow); step(early)
        check(!early.hasReturned && noteHidden(early) == true, "return: hearing the accounts is not enough: the altar's own flag (gw_end) is what counts")

        // Reading it: the journal opens on the Notebook, the line is logged once, and nothing about pages changes.
        let before = g.journal.collectedPages.map(\.number), gateBefore = g.gate
        g.activate(DoorNote.itemName)
        check(!g.journal.isOpen && g.reading == Story.doorNote && g.story.notes == ["door_note"], "return: reading the note shows a card with its words (F05 S1: it does not open the Notebook) and logs the line")
        step(g)
        check(g.journal.hasUnread(.notebook), "return: and the Notebook tab is marked until the player looks at it")
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

        // Picking with the real rays: the crosshair on the note picks the note, on the door's planks picks the door (the door's box must not stand in front of the note: found by review).
        let pg = twoWorlds(); pg.state.set("gw_end"); step(pg)
        func pick(from eye: SIMD3<Float>, at target: SIMD3<Float>) -> String? { Interaction.pick(origin: eye, dir: simd_normalize(target - eye), in: pg.interactables)?.id }
        let noteC = DoorNote.worldCenter, lhp = Layout.lighthouse
        var onNote: [String?] = [], onDoor: [String?] = []
        for d: Float in [0.5, 1, 2, 3] {
            onNote.append(pick(from: SIMD3(noteC.x, noteC.y, noteC.z + d), at: noteC))
            onNote.append(pick(from: SIMD3(noteC.x + 0.2, noteC.y - 0.1, noteC.z + d), at: noteC))
            onDoor.append(pick(from: SIMD3(lhp.x + 0.25, lhp.y + Lighthouse.baseY + 0.45, noteC.z + d), at: SIMD3(lhp.x + 0.25, lhp.y + Lighthouse.baseY + 0.45, noteC.z - 0.02)))   // the lowest plank, below the lower strap
        }
        check(onNote.allSatisfy { $0 == DoorNote.itemName }, "return: a ray on the note picks the note from 0.5, 1, 2 and 3 m, straight on and from the side (\(onNote))")
        check(onDoor.allSatisfy { $0 == "lh_door" }, "return: a ray on the door's lower planks still picks the door (\(onDoor))")
        let fresh = twoWorlds(); step(fresh)
        check(Interaction.pick(origin: SIMD3(noteC.x, noteC.y, noteC.z + 1), dir: SIMD3(0, 0, -1), in: fresh.interactables)?.id == "lh_door", "return: before the altar the note is not there to pick: the ray on that spot picks the door")

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

        // The answer phrase (S03.4, builder A plays it): once on the return, again within 40 m of the door after 60 s away; never before the altar, in the Glass Wood, or once the door is open.
        func phrases(_ g: Game) -> Int { g.drainEvents().filter { $0 == .answerPhrase }.count }
        let doorPt = Layout.Navigation.signalDoorPoint
        func at(_ g: Game, _ d: Float) { g.player = Player(position: SIMD3(doorPt.x, 0, doorPt.z + d), yaw: 0); g.player.position.y = g.scene.groundHeight(x: doorPt.x, z: doorPt.z + d) }
        let ph = twoWorlds(); step(ph); _ = ph.drainEvents()
        ph.state.set("gw_end"); ph.travel(to: .glassWood); _ = ph.drainEvents()
        ph.travel(to: .varrow)
        check(phrases(ph) == 1, "phrase: the return to Varrow after the altar sounds it once")
        at(ph, 120); step(ph, 4)
        check(phrases(ph) == 0, "phrase: far from the door it is quiet")
        at(ph, 39); step(ph, 2)
        check(phrases(ph) == 1, "phrase: coming within 40 m of the door (the first time since the return) sounds it")
        step(ph, 20)
        check(phrases(ph) == 0, "phrase: staying near does not repeat it")
        at(ph, 60); ph.simulate(seconds: 20); step(ph, 2); at(ph, 30); step(ph, 2)
        check(phrases(ph) == 0, "phrase: away for 20 s only, it does not sound again")
        at(ph, 60); ph.simulate(seconds: 65); step(ph, 2); at(ph, 30); step(ph, 2)
        check(phrases(ph) == 1, "phrase: away for over a minute, coming near sounds it again")
        let nope = twoWorlds(); step(nope); _ = nope.drainEvents()
        at(nope, 20); step(nope, 4)
        check(phrases(nope) == 0, "phrase: before the altar it never sounds, near the door or not")
        nope.travel(to: .glassWood); nope.state.set("gw_end"); _ = nope.drainEvents(); step(nope, 4)
        check(phrases(nope) == 0, "phrase: in the Glass Wood it does not sound")
        let shutDoor = twoWorlds(); shutDoor.state.set("gw_end"); shutDoor.state.set(Game.doorOpenFlag); step(shutDoor); _ = shutDoor.drainEvents()
        at(shutDoor, 20); step(shutDoor, 4); shutDoor.travel(to: .glassWood); shutDoor.travel(to: .varrow)
        check(phrases(shutDoor) == 0, "phrase: once the door is open the lamp has been answered: it does not sound, on the return or near the door")
        let routed = twoWorlds(); routed.state.set("gw_end"); routed.state.set(Game.pathIlseFlag); step(routed); _ = routed.drainEvents()
        at(routed, 20); step(routed, 4)
        check(phrases(routed) == 0, "phrase: nor once a route is begun")
    }
}
