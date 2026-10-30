import Foundation
import Metal
import simd

/// Self-tests: scripted playthroughs of both worlds (T55.B4).
extension SelfTestRunner {
    func runBots() {
        guard name == "all" || name == "bots" else { return }
        let scenes: [WorldKind: Scene] = [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]
        let g = Game(scenes: scenes)
        let bot = PlaythroughBot(g)
        let path = Layout.lanternPath

        // --- Varrow: walk the lantern path, strike the stones in the order the world teaches, collect pages on the way.
        // S03.10: page 9 lies on the boards a few metres from the spawn at the seaward end, away from page 1; the bot reads it first.
        check(bot.walk(to: PuzzleProps.pagePosition(9, scene: g.scene), within: 1.6) && bot.click("page_9") && g.journal.collectedPages.map(\.number) == [9], "bot: reads page 9 at the seaward end of the dock with a real click")
        bot.closeJournal()
        check(bot.walk(to: path[0], within: 2.5), "bot: from the spawn at the end of the dock to the shore")
        check(bot.walk(to: PuzzleProps.pagePosition(1, scene: g.scene), within: 1.6) && bot.click("page_1") && g.journal.collectedPages.map(\.number) == [1, 9], "bot: reads page 1 on the dock with a real click")
        bot.closeJournal()
        check(!g.journal.isOpen, "bot: closes the journal with J")
        check(bot.walk(to: path[0], within: 2.5), "bot: back to the shore")
        var struck = true
        for (i, id) in LighthousePuzzle.order.enumerated() {
            struck = struck && bot.walk(to: path[i + 1], within: 2.2)
            struck = struck && bot.click("stone_\(id.name)")
            bot.wait(0.9)
            if i < 2 {                                                      // F02 P0: the page beside the stone (2 by the tide stone, 3 by the wind stone)
                let n = i + 2, there = bot.walk(to: PuzzleProps.pagePosition(n, scene: g.scene), within: 2.2) && bot.click("page_\(n)")
                bot.closeJournal()
                check(there && g.journal.collectedPages.map(\.number).contains(n), "bot: finds and reads page \(n) by the \(id.name) stone with a real click")
            }
        }
        check(struck, "bot: walks to each stone in turn and clicks it")
        bot.wait(LighthousePuzzle.Timing.total + 1)
        check(g.state.has("solved") && g.state.has("lighthouseLit") && g.state.has("causewayUp"), "bot: tide, wind, stone solves the lighthouse and raises the causeway")

        // F02 P0: page 4 beside the lighthouse's door steps, reached after the stone puzzle (it used to be half buried in the lowest step).
        do {
            let p4 = PuzzleProps.pagePosition(4, scene: g.scene)
            let b4 = PuzzleProps.pageBase(4, terrain: g.scene.terrain)
            let atDoor = bot.follow([Layout.lighthouse + SIMD3(0, 0, 14)], within: 3)
            let got = atDoor && bot.walk(to: p4, within: 2.2) && bot.click("page_4")
            bot.closeJournal()
            check(got && g.journal.collectedPages.map(\.number).contains(4), "bot: finds and reads page 4 beside the lighthouse door steps (sheet at \(p4), reached \(atDoor))")
            check(!g.scene.platforms.contains { $0.contains(SIMD2(b4.x, b4.z)) }, "page 4 lies on open ground, not on or in a step")
        }

        // A wrong order from a fresh game must not solve it (the bot clicking in the wrong order fails and resets).
        let bad = Game(scenes: scenes); let badBot = PlaythroughBot(bad)
        _ = badBot.walk(to: path[0], within: 2.5)
        for id in [StoneID.wind, .tide, .summit] { _ = badBot.walk(to: path[id.rawValue + 1], within: 2.2); _ = badBot.click("stone_\(id.name)"); badBot.wait(1) }
        check(!bad.state.has("solved"), "bot: striking the stones in the wrong order does not solve it")

        // --- The causeway and the lens: walk north from its start to the islet, touch the lens, arrive in the Glass Wood.
        let plan = PuzzleProps.causewayPlan(terrain: g.scene.terrain)
        let start = SIMD3(plan.start.x, 0, plan.start.y)
        let down = simd_normalize(SIMD2(Layout.causewayStart.x - Layout.lighthouse.x, Layout.causewayStart.z - Layout.lighthouse.z))
        let leave = SIMD3(Layout.lighthouse.x + down.x * 12, 0, Layout.lighthouse.z + down.y * 12)           // on the graded descent just beyond the tower's wall
        check(bot.follow([leave, start], within: 3), "bot: walks back down the hill to the start of the causeway (along the graded descent)")
        check(bot.walk(to: PuzzleProps.lensRestPosition, within: 3.2, timeout: 90), "bot: crosses the causeway to the islet")
        check(bot.click("lens"), "bot: clicks the lens")
        let varrowSeconds = bot.elapsed                                                  // spawn to the lens click: the whole of Varrow, waits included
        bot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        let glassStart = bot.elapsed
        check(g.world == .glassWood && g.state.has("lensTouched"), "bot: the lens carries it to the Glass Wood (Varrow took \(Int(varrowSeconds.rounded())) s of play, spawn to the lens)")

        // --- The Glass Wood: mirror court by real clicks, chimes by ear-order, the altar, then home.
        let gp = GlassLayout.path
        check((g.banner ?? "") != "A page has come loose." && !g.pageWaiting, "bot: arriving in the Glass Wood does not announce the page by the arrival pad (F03 #43: no banner, no marker; the lens's own chime is the only sound)")
        func collectGW(_ n: Int) {
            let there = bot.walk(to: GlassPuzzleProps.pagePosition(n, scene: g.scenes[.glassWood]!), within: 2.2, timeout: 60) && bot.click("page_\(n)")
            bot.closeJournal()
            check(there && g.journal.collectedPages.map(\.number).contains(n), "bot: finds and reads Oren's page \(n) with a real click")
        }
        collectGW(5)
        check(bot.follow(Array(gp[0...4]), within: 2.5), "bot: follows the lit path to the mirror court")
        var turned = true
        for k in 0..<3 {
            let turns = (MirrorCourt.solutionMirrors[k] - MirrorCourt.initialMirrors[k] + 4) % 4
            turned = turned && bot.walk(to: GlassPuzzleProps.mirrorPosition(k), within: 3.0, timeout: 60)
            for _ in 0..<turns { turned = turned && bot.click("gw_mirror_\(k)"); bot.wait(0.5) }
        }
        for k in 0..<3 {
            let turns = (MirrorCourt.solutionPanes[k] - MirrorCourt.initialPanes[k] + 3) % 3
            turned = turned && bot.walk(to: GlassPuzzleProps.panePosition(k), within: 3.0, timeout: 60)
            for _ in 0..<turns { turned = turned && bot.click("gw_pane_\(k)"); bot.wait(0.5) }
        }
        check(turned, "bot: turns each mirror and changes each pane with real clicks")
        bot.wait(3)
        check(g.state.has("gw_mirrors"), "bot: the moonbeam meets tide, wind, stone in order and the court is solved")
        check(g.scenes[.glassWood]!.items.first { $0.name == "page_6" }.map { !$0.hidden } == true, "bot: Oren's page 6 appears at the orb")
        check(!g.pageWaiting && (g.banner ?? "") != "A page has come loose.", "bot: the live reveal does not announce itself (F03 #43: no banner, no marker): the page is simply there")
        collectGW(6)
        check(!g.pageWaiting, "bot: and there is no journal marker after a pickup either (the pickup opens the journal on the page)")

        check(bot.follow(Array(gp[4...8]), within: 2.5), "bot: follows the path on to the chime ring")
        var rang = true
        for k in GlassWoodLogic.chimeSolution {
            rang = rang && bot.walk(to: GlassPuzzleProps.chimePosition(k), within: 3.0, timeout: 60)
            rang = rang && bot.click("gw_chime_\(k)"); bot.wait(0.8)
        }
        check(rang, "bot: strikes the three pillars that carry the stones' tones")
        bot.wait(3)
        check(g.state.has("gw_chimes"), "bot: the chime puzzle is solved")
        collectGW(7)

        check(bot.follow(Array(gp[8...]), within: 3.0), "bot: walks on to the altar")
        bot.wait(6)
        var heard = true
        for id in ["gw_altar_ilse", "gw_altar_oren"] {
            heard = heard && bot.walk(to: (bot.interactable(id).map { ($0.min + $0.max) * 0.5 }) ?? GlassLayout.altar, within: 2.6, timeout: 45)
            heard = heard && bot.click(id); bot.wait(1)
        }
        check(heard && g.state.has("gw_end"), "bot: hears both accounts and reaches the end of the second world (the Glass Wood took \(Int((bot.elapsed - glassStart).rounded())) s of play, arrival to the second account)")
        collectGW(8)
        check(g.journal.collectedPages.map(\.number) == Array(1...9), "bot: every one of the nine pages was found by walking the normal route (\(g.journal.collectedPages.map(\.number)))")
        check(g.gate.ready && g.gate.ilsePages == 5 && g.gate.orenPages == 4, "bot: the normal route leaves the gate ready without any contradiction: altar solved, 5 Ilse pages and 4 Oren pages (it asks for 3 of each) (\(g.gate.missing))")
        // The Notebook's contradiction, settled through the real API from what the walk found: page 4 supports His, page 5 Hers, page 8 His (any three of the four pieces settle it).
        for (page, side) in [(4, Claim.his), (5, .hers), (8, .his)] { g.setClaim("who-left", page: page, to: side) }
        check(g.isSettled("who-left") && g.gate.ready, "bot: and settling the contradiction from the pages it found makes the gate ready")

        // --- Home: back to the arrival ring and through it.
        check(bot.follow(Array(gp.reversed()), within: 3.0), "bot: walks the whole path back to the arrival pad")
        check(bot.walk(to: GlassLayout.returnLens, within: 3.4, timeout: 60) && bot.click("gw_return"), "bot: clicks the return ring")
        bot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        check(g.world == .varrow && g.state.has("gw_end"), "bot: back on Varrow with the story done")

        // --- F06 B2: the end, from the same fresh game: the lighthouse door, the note, the plates, the stair, the lens room, and BOTH exits (the second from the same moment, restored from a save).
        typealias I = LighthouseInterior
        let lh = Layout.lighthouse
        func pt(_ a: Float, _ r: Float) -> (x: Float, z: Float) { (lh.x + cos(a) * r, lh.z + sin(a) * r) }
        func band(_ phi: Float) -> Float { let h = I.stairY(phi); return (I.stairInner(h) + I.innerR(h)) / 2 }
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        check(g.lighthouseSignal && g.interactables.first { $0.id == DoorNote.itemName }?.enabled == true, "bot: back on Varrow the lighthouse beam is a signal and the note on the door can be read")
        let tw0 = bot.elapsed
        // The trail brings the player to the lighthouse's plaza; the door faces south, so go round the tower by its west side.
        var toDoor = bot.walk(to: SIMD3(lh.x - 11, lh.y, lh.z), within: 3.0, timeout: 240)
        toDoor = toDoor && bot.walk(to: SIMD3(lh.x - 10, lh.y, lh.z + 9), within: 1.5, timeout: 60, straight: true)
        toDoor = toDoor && bot.walk(to: Layout.Navigation.signalDoorPoint, within: 2.0, timeout: 60, straight: true)
        check(toDoor, "bot: walks the trail from the return ring to the lighthouse door (\(Int(bot.elapsed - tw0)) s, ended at \(bot.feet), door point \(Layout.Navigation.signalDoorPoint))")
        check(bot.click(DoorNote.itemName) && g.reading == Story.doorNote && !g.journal.isOpen, "bot: clicks the note on the door: its words come up on a card, not the Notebook")
        var dismiss = InputState(); dismiss.click = true; bot.tick(dismiss)
        check(g.reading == nil, "bot: a click puts the card away")
        check(bot.click("lh_door") && !g.state.has(Game.doorOpenFlag) && g.banner == Story.doorLockedReturned, "bot: the door itself is locked, and back with the altar solved its line says the stones beside it are listening")
        var plates = true
        for k in [0, 1, 2] {
            let c = bot.interactable(TonePlates.names[k]).map { ($0.min + $0.max) * 0.5 } ?? lh
            // A player stands in front of a plate, looking at it square on: 1.6 m straight out from the tower's wall (from the side the plates in the row hide each other).
            let out = simd_normalize(SIMD2(c.x - lh.x, c.z - lh.z)), stand = SIMD3(c.x + out.x * 1.6, 0, c.z + out.y * 1.6)
            let w = bot.walk(to: stand, within: 0.3, timeout: 30, straight: true), cl = bot.click(TonePlates.names[k]); bot.wait(0.6)
            plates = plates && w && cl
        }
        bot.wait(TonePlatePuzzle.Timing.answerDelay + TonePlatePuzzle.Timing.openDelay + 1.5)
        check(plates && g.state.has(Game.doorOpenFlag), "bot: strikes the plates tide, wind, stone by real clicks: the lamp answers and the door opens (no contradiction was ever set: it does not gate)")
        var climbed = bot.walk(to: SIMD3(lh.x, 0, lh.z + 5), within: 0.5, straight: true) && bot.walk(to: SIMD3(lh.x, 0, lh.z + 3.0), within: 0.5, straight: true) && bot.walk(to: SIMD3(lh.x - 0.9, 0, lh.z + 2.3), within: 0.5, straight: true)
        var phi = I.startAngle
        while climbed && phi < I.endAngle + 0.5 { let q = pt(phi, band(min(phi, I.endAngle))); climbed = bot.walk(to: SIMD3(q.x, 0, q.z), within: 0.55, straight: true); phi += 0.3 }
        let top = pt(I.endAngle + 1.2, 1.2)
        climbed = climbed && bot.walk(to: SIMD3(top.x, 0, top.z), within: 0.5, straight: true)
        check(climbed && abs(bot.feet.y - (lh.y + I.lensFloorY)) < 0.1, "bot: walks in through the open door and up the stair to the lens room")
        check(g.gate.ready && g.chosenPath == nil, "bot: in the lens room the gate is ready and no route is chosen yet")
        let atLens = g.makeSave()
        // Exit one (Ilse): touch the lens.
        check(bot.click(Game.lampLensName) && g.chosenPath == .ilse && g.isTraveling, "bot: touches the lens above the ring: Ilse's route begins")
        bot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        check(g.world == .glassWood && g.portalSealed && !g.platesSealed, "bot: it arrives in the Glass Wood and Oren's exit is sealed")
        // Exit two (Oren): the same moment, loaded from the save, by the ring and the doorway.
        let o = twoWorlds(); o.restore(atLens)
        let obot = PlaythroughBot(o)
        obot.wait(0.5)
        var ringed = obot.walk(to: SIMD3(lh.x - 0.2, 0, lh.z - 1.45), within: 0.3, timeout: 30, straight: true)      // to the ring, as a player would
        for _ in 0..<3 { ringed = ringed && obot.click("lens_ring"); obot.wait(0.3) }
        obot.wait(LensPortalProps.holdSeconds + 0.6)
        check(ringed && o.state.has(Game.portalOpenFlag) && o.chosenPath == nil, "bot: from the save, three touches turn the ring onto the receiver and the portal opens")
        let doorway = (lh.x + cos(I.portalAngle) * 1.4, lh.z + sin(I.portalAngle) * 1.4)
        check(obot.walk(to: SIMD3(doorway.0, 0, doorway.1), within: 0.2, straight: true) && o.chosenPath == nil, "bot: walks up to the open doorway, 1.4 m from the axis, and has not stepped through yet")
        // Then on to the glass: keep walking north until the route begins (the zone starts 1.68 m from the axis, the glass stops the feet at about 1.75 m).
        for _ in 0..<90 where o.chosenPath == nil { var fwd = InputState(); fwd.move = SIMD2(0, 1); o.player.yaw = 0; obot.tick(fwd) }
        obot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.8)
        check(o.chosenPath == .oren && o.world == .glassWood && o.platesSealed && !o.portalSealed, "bot: Oren's route begins in the Glass Wood and Ilse's exit is sealed (\(String(describing: o.chosenPath)) \(o.world) plates \(o.platesSealed) portal \(o.portalSealed))")
        // The seals hold across a save and a load, in both worlds' end states.
        for (label, game, route) in [("Ilse", g, PageAuthor.ilse), ("Oren", o, PageAuthor.oren)] {
            let again = twoWorlds(); again.restore(game.makeSave()); again.travel(to: .varrow); again.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 1)
            let sealedHolds = route == .ilse ? (again.portalSealed && !again.platesSealed) : (again.platesSealed && !again.portalSealed)
            if route == .ilse { let a0 = again.lensPortal.ringAngle; again.lensPortal.turn(2); check(again.lensPortal.ringAngle == a0 && !again.state.has(Game.portalOpenFlag), "bot: and after the load Ilse's sealed ring does not turn") }
            check(again.chosenPath == route && sealedHolds && !again.beginRoute(route == .ilse ? .oren : .ilse), "bot: after a save and a load \(label)'s route is kept and the other exit is still sealed")
        }
    }
}
