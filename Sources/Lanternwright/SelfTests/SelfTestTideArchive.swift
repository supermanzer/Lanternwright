import Foundation
import Metal
import simd

/// Self-tests: the Tide Archive's tide and key puzzle (S04.2 function, S04.6): the tide is a pure periodic function whose three windows come in the stones' order; three sluices open in order at
/// their own water levels, by held tones (Ilse's fork) or by the turned beam (Oren's lens); a wrong order, a wrong water level and a partial set each do what the plan says; tools; saves.
/// Developed against the Glass Wood as the stand-in world, behind `Game.tideArchiveEnabled`.
extension SelfTestRunner {
    func runTideArchive() {
        guard name == "all" || name == "tidearchive" || name == "story" else { return }
        typealias T = TideArchivePuzzle
        let lh = Layout.lighthouse
        Game.tideArchiveEnabled = true
        defer { Game.tideArchiveEnabled = false }

        // The tide: a pure periodic function; low at 0, high at half a period; the windows come in order in one rise.
        check(abs(Tide.level(0)) < 1e-6 && abs(Tide.level(Tide.period / 2) - 1) < 1e-6 && abs(Tide.level(Tide.period) - Tide.level(0)) < 1e-4 && abs(Tide.level(13.7) - Tide.level(13.7 + Tide.period)) < 1e-4, "tide: low water at 0, high at half the period (\(Tide.period) s), and periodic")
        let w0 = Tide.wait(for: 0, from: 0), w1 = Tide.wait(for: 1, from: 0), w2 = Tide.wait(for: 2, from: 0)
        check(w0 == 0 && w1 > 10 && w2 > w1 && w2 < 45, "tide: in one rise the tide gate answers first, then the wind gate, then the stone gate (\(w0), \(w1), \(w2) s from low water)")
        check(!Tide.inWindow(0, level: 0.5) && !Tide.inWindow(2, level: 0.3) && Tide.inWindow(1, level: 0.5) && !Tide.inWindow(1, level: 0.1) && !Tide.inWindow(5, level: 0.5), "tide: each gate answers only at its own water level, and there are only three")

        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        func routeGame(_ route: PageAuthor) -> Game {
            let g = twoWorlds()
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end"); g.state.set(Game.doorOpenFlag)
            g.simulate(seconds: 0.1)
            check(g.beginRoute(route), "archive: the route begins (\(route))")
            g.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
            _ = g.drainEvents()
            return g
        }
        var clock = 9000.0
        func frame(_ g: Game) { for _ in 0..<2 { clock += 0.05; g.advance(now: clock, input: InputState()) } }
        func to(_ g: Game, _ t: Float) { if t > g.time { g.simulate(seconds: t - g.time) } }
        func fails(_ g: Game) -> Bool { g.drainEvents().contains(.chime(.fail)) }
        let hold = T.Timing.toneHold + 0.2

        // Tools: each route starts with its own; the other lies in the world.
        let a = routeGame(.ilse), tideA = a.tideArchive!
        check(a.world == a.routeWorld && tideA.hasFork && !tideA.hasLens, "archive: Ilse's route comes with the tuning fork and not the lens")
        frame(a)
        check(a.interactables.first { $0.id == T.ringName }?.enabled == false && a.interactables.first { $0.id == T.findLensName }?.enabled == true && a.interactables.first { $0.id == T.findForkName }?.enabled == false, "archive: the ring waits for the lens, the lens lies there to be found, the fork is already in hand")

        // Ilse's way, the right way: tide gate at low water, wind at mid, stone at high, each tone held.
        to(a, 2); tideA.touchSluice(0); to(a, a.time + hold)
        check(tideA.opened == 1 && a.state.has("ti_sluice_0") && !a.routeSolved, "archive: the fork's tide tone, held at low water, opens the first gate")
        to(a, 20); tideA.touchSluice(1); to(a, a.time + hold)
        check(tideA.opened == 2, "archive: the wind tone, held at mid water, opens the second")
        to(a, 30); tideA.touchSluice(2); to(a, a.time + hold)
        check(tideA.opened == 3 && !a.routeSolved, "archive: the stone tone at high water opens the third: the gallery has yet to drain")
        a.simulate(seconds: T.Timing.drainDelay + 0.2)
        check(a.routeSolved && a.state.has(T.drainedFlag) && tideA.knowsTones && !tideA.knowsBeam, "archive: then the gallery drains and the world is solved; Ilse's way is known, Oren's is not")
        // Solved, the lens leads nowhere more (S04.5) and the next lens shows.
        a.travel(to: .varrow); a.simulate(seconds: 0.1)
        check(a.routeSolved && a.chosenPath == .ilse, "archive: back on Varrow with the Archive solved")

        // A wrong order closes everything, softly, and loses nothing else.
        let b = routeGame(.ilse), tideB = b.tideArchive!
        to(b, 2); tideB.touchSluice(0); to(b, b.time + hold)
        to(b, 20); _ = b.drainEvents(); tideB.touchSluice(2); to(b, b.time + hold)
        check(tideB.opened == 1, "archive: the stone gate at the wrong moment (the water not high yet) does not answer and nothing closes")
        to(b, 30); tideB.touchSluice(2); to(b, b.time + hold)
        let ev = b.drainEvents()
        check(ev.contains(.chime(.fail)) && ev.contains(.droneSour), "archive: the stone gate before the wind gate: a soft fail chime and the tones sour")
        b.simulate(seconds: T.Timing.wrongResetDelay + 0.2)
        check(tideB.opened == 0 && !b.routeSolved && !b.state.has("ti_sluice_0"), "archive: and every gate closes again (an order puzzle resets, nothing is lost)")

        // The wrong water level: the gate hears nothing and goes on holding.
        let c = routeGame(.ilse), tideC = c.tideArchive!
        to(c, 40); _ = c.drainEvents(); tideC.touchSluice(0); to(c, c.time + hold)
        check(tideC.opened == 0 && fails(c), "archive: the tide gate at high water does not answer, with a soft fail")
        // Without the fork a touch only rings.
        let d = routeGame(.oren), tideD = d.tideArchive!
        to(d, 2); _ = d.drainEvents(); tideD.touchSluice(0); to(d, d.time + hold)
        check(!tideD.hasFork && tideD.opened == 0, "archive: without the fork a gate only rings")
        d.activate(T.findForkName)
        check(tideD.hasFork && d.interactables.first { $0.id == T.findForkName }?.enabled == true, "archive: the fork lying in the world, taken, is in hand (Oren's route finds Ilse's way)")
        frame(d)
        check(d.interactables.first { $0.id == T.findForkName }?.enabled == false, "archive: and it is no longer there to take")
        to(d, d.time + (Tide.period - d.time.truncatingRemainder(dividingBy: Tide.period)) + 2); tideD.touchSluice(0); to(d, d.time + hold)
        check(tideD.opened == 1 && tideD.knowsTones, "archive: Oren with the fork opens the first gate by tone, and Ilse's way is known to him")

        // Oren's way: the ring turned until the beam rests on a gate's mark, held, at the right water.
        let o = routeGame(.oren), tideO = o.tideArchive!
        check(tideO.hasLens && !tideO.hasFork, "archive: Oren's route comes with the lens and not the fork")
        frame(o)
        check(o.interactables.first { $0.id == T.ringName }?.enabled == true, "archive: with the lens the prism ring answers")
        func aim(_ g: Game, _ p: T, _ k: Int) { let steps = Int(((T.beamTargets[k] - p.ringAngle) / T.ringStep).rounded()); var left = steps; while left != 0 { let s = left > 0 ? 1 : -1; p.turn(s); left -= s } }
        to(o, 2); aim(o, tideO, 0); to(o, o.time + T.Timing.beamHold + 0.2)
        check(tideO.opened == 1 && tideO.knowsBeam && !tideO.knowsTones, "archive: the beam turned onto the tide gate and held at low water opens it; Oren's way is known, Ilse's is not")
        to(o, 20); aim(o, tideO, 1); to(o, o.time + T.Timing.beamHold + 0.2)
        to(o, 30); aim(o, tideO, 2); to(o, o.time + T.Timing.beamHold + 0.2)
        o.simulate(seconds: T.Timing.drainDelay + 0.2)
        check(tideO.opened == 3 && o.routeSolved, "archive: wind at mid water and stone at high water: the gallery drains by the beam")
        // Aiming across the other marks on the way does not try them (only a rest of the full hold counts).
        let p = routeGame(.oren), tideP = p.tideArchive!
        to(p, 20); aim(p, tideP, 1); p.simulate(seconds: 0.5); aim(p, tideP, 2); p.simulate(seconds: 0.5); aim(p, tideP, 0)
        check(tideP.opened == 0, "archive: sweeping the beam across the marks without resting on one tries nothing")
        // A click on the ring turns it toward the side aimed at, like the lighthouse ring; the arrow keys either way.
        let q = routeGame(.oren), tideQ = q.tideArchive!
        let before = tideQ.ringAngle; q.activate(T.ringName)
        check(abs(tideQ.ringAngle - before) > 0.1, "archive: a click on the prism ring turns it a step")

        // Bots, with real clicks and keys (the stand-in's gates are reached by standing next to them; the walking is the world's, S04.8): both ways, from the route's start.
        func stand(_ g: Game, at c: SIMD3<Float>) {
            let sc = g.scene
            g.player = Player(position: SIMD3(c.x, sc.groundHeight(x: c.x, z: c.z + 1.8), c.z + 1.8), yaw: 0)
            frame(g)
        }
        let ib = routeGame(.ilse), ibot = PlaythroughBot(ib)
        var clicked = true
        for k in 0..<3 {
            stand(ib, at: TideStandIn.sluicePosition(k, scene: ib.scene))
            ibot.wait(Tide.wait(for: k, from: ib.time) + 0.5)                                       // the water gets to that gate's level
            clicked = clicked && ibot.click(T.sluiceNames[k]); ibot.wait(T.Timing.toneHold + 0.3)
        }
        ibot.wait(T.Timing.drainDelay + 0.5)
        check(clicked && ib.routeSolved && ib.tideArchive?.opened == 3, "archive bot: Ilse, by real clicks on the three gates with the water at each one's level, drains the gallery")
        let ob = routeGame(.oren), obot = PlaythroughBot(ob)
        var turned = true
        for k in 0..<3 {
            stand(ob, at: TideStandIn.ringPosition(scene: ob.scene))
            obot.wait(Tide.wait(for: k, from: ob.time) + 0.5)
            let want = Int(((T.beamTargets[k] - ob.tideArchive!.ringAngle) / T.ringStep).rounded())
            turned = turned && obot.click(T.ringName)                                                    // aims at the ring (the crosshair on it, so the arrow keys act on it)
            ob.tideArchive!.turn(-1)                                                                       // (the click above turned it one step: take it back)
            for _ in 0..<abs(want) { var key = InputState(); key.pageFlip = want > 0 ? 1 : -1; obot.tick(key); obot.wait(0.1) }
            obot.wait(T.Timing.beamHold + 0.4)
        }
        obot.wait(T.Timing.drainDelay + 0.5)
        check(turned && ob.routeSolved && ob.tideArchive?.opened == 3 && ob.tideArchive?.knowsBeam == true, "archive bot: Oren, by the ring turned with the arrow keys onto each gate's mark and held, drains the gallery")

        // Saves: the gates, the tools and the ways known come back; a partial set stays open.
        let r = routeGame(.ilse), tideR = r.tideArchive!
        to(r, 2); tideR.touchSluice(0); to(r, r.time + hold)
        to(r, 20); tideR.touchSluice(1); to(r, r.time + hold)
        let loaded = twoWorlds(); loaded.restore(r.makeSave()); loaded.simulate(seconds: 0.2)
        check(loaded.tideArchive?.opened == 2 && loaded.tideArchive?.hasFork == true && loaded.tideArchive?.knowsTones == true && !loaded.routeSolved && loaded.chosenPath == .ilse, "archive: a save keeps two gates open, the fork, the way known and the route")
        // The loaded game can finish it.
        to(loaded, loaded.time + (Tide.period - loaded.time.truncatingRemainder(dividingBy: Tide.period)) + 30); loaded.tideArchive?.touchSluice(2); to(loaded, loaded.time + hold)
        loaded.simulate(seconds: T.Timing.drainDelay + 0.2)
        check(loaded.routeSolved && loaded.tideArchive?.opened == 3, "archive: and from the loaded save the last gate finishes it")

        // S04.7: the Archive's pages in the journal: the route's voice, the narrator's tab, no gate, slots by world, and a save.
        let pj = twoWorlds()
        check(!pj.journal.pageSlots.map(\.world).contains("Tide Archive"), "archive pages: before a route the journal shows no Archive slots (they would give the place away)")
        let ia = routeGame(.ilse), oa = routeGame(.oren)
        frame(ia); frame(oa)
        check(ia.journal.pageSlots.map(\.world) == ["Varrow", "Glass Wood", "Tide Archive"] && ia.journal.pageSlots[2].found == [Bool](repeating: false, count: 6), "archive pages: once a route has begun the journal shows six empty slots under 'Tide Archive'")
        let gateBefore = ia.gate
        ia.activate("page_11"); oa.activate("page_11")
        check(ia.journal.collectedPages.first { $0.number == 11 }?.text == StoryPages.archivePage(11)!.ilse && oa.journal.collectedPages.first { $0.number == 11 }?.text == StoryPages.archivePage(11)!.oren, "archive pages: page 11 reads in Ilse's voice on her route and in Oren's on his (never the other's)")
        check(ia.journal.tab == .ilse && oa.journal.tab == .oren && oa.journal.visibleTabs.contains(.oren) && ia.journal.hasUnread(.ilse), "archive pages: it is filed under the narrator's tab, unread")
        check(ia.gate == gateBefore && oa.gate.ilsePages == gateBefore.ilsePages && oa.gate.orenPages == gateBefore.orenPages, "archive pages: and it counts for no gate")
        check(ia.journal.pageSlots[2].found == [false, true, false, false, false, false], "archive pages: its slot is filled")
        for n in StoryPages.archiveIDs { oa.activate("page_\(n)") }
        check(StoryPages.archiveIDs.allSatisfy { n in oa.journal.collectedPages.first { $0.number == n }?.text == StoryPages.archivePage(n)!.oren }, "archive pages: all six, collected, read in Oren's voice")
        let ol = twoWorlds(); ol.restore(oa.makeSave()); frame(ol)
        check(ol.journal.collectedPages.filter { StoryPages.archiveIDs.contains($0.number) }.count == 6 && ol.journal.collectedPages.first { $0.number == 12 }?.text == StoryPages.archivePage(12)!.oren, "archive pages: a save keeps them and they load in the same voice")

        // S04.8: the guides follow the corridor. The path maths first.
        let gp = GuidePath([SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(10, 10), SIMD2(30, 10)])
        check(abs(gp.length - 40) < 1e-4 && gp.point(at: 0) == SIMD2(0, 0) && gp.point(at: 5) == SIMD2(5, 0) && simd_length(gp.point(at: 15) - SIMD2(10, 5)) < 1e-4 && gp.point(at: 99) == SIMD2(30, 10) && gp.point(at: -4) == SIMD2(0, 0), "guides: a path knows its length (a doubled point is dropped), the point a distance along it, and clamps at both ends")
        check(abs(gp.progress(of: SIMD2(4, 3)) - 4) < 1e-4 && abs(gp.progress(of: SIMD2(12, 5)) - 15) < 1e-4 && abs(gp.progress(of: SIMD2(40, 10)) - 40) < 1e-4, "guides: and how far along it a point is (the nearest point on the path)")
        check(GuideLanterns.lanternDistance(playerProgress: 0, pathLength: 100) == GuideLanterns.ahead && GuideLanterns.lanternDistance(playerProgress: 95, pathLength: 100) == 100, "guides: Oren's lantern is always `ahead` metres in front of the player and never past the end of the path")
        check(GuideLanterns.lampCount(pathLength: 100) == 3 && GuideLanterns.lampCount(pathLength: 10) == 0 && GuideLanterns.lampCount(pathLength: 5000) == GuideLanterns.maxLamps && GuideLanterns.lampLit(0, playerProgress: 0) && !GuideLanterns.lampLit(2, playerProgress: 0) && GuideLanterns.lampLit(2, playerProgress: GuideLanterns.lampDistance(2) - GuideLanterns.litRange + 0.1) && GuideLanterns.lampLit(2, playerProgress: 500), "guides: Ilse's lamps stand every `spacing` m, the first is lit at the start, the others come on as the player draws near, and none goes out behind them")
        // In the game: each route gets its own guide, on the world's corridor, and it goes when the world is solved.
        let gi = routeGame(.ilse); frame(gi)
        check(gi.guideLantern != nil && gi.guideLamps.isEmpty && gi.scene.items.first { $0.name == GuideLanterns.lanternName }?.hidden == false, "guides: on Ilse's route there is one lantern (Oren's), ahead of her, and no lamps")
        let pathI = gi.guideLantern!, startI = SIMD2(gi.player.position.x, gi.player.position.z)
        check(simd_length(pathI - startI) > 5 && simd_length(pathI - startI) < GuideLanterns.ahead + 3, "guides: it is a little ahead (\(String(format: "%.1f", simd_length(pathI - startI))) m)")
        let net = Layout.Navigation.active(for: gi.routeWorld)!
        let far = net.route(from: startI, to: SIMD2(GlassLayout.altar.x, GlassLayout.altar.z)); let mid = far[far.count / 2]
        gi.player.position = SIMD3(mid.x, gi.scene.groundHeight(x: mid.x, z: mid.y), mid.y); frame(gi)
        check(gi.guideLantern != nil && simd_length(gi.guideLantern! - mid) > 5 && simd_length(gi.guideLantern! - pathI) > 5, "guides: walking on moves the lantern on, still ahead (it is never reached)")
        let go = routeGame(.oren); frame(go)
        check(go.guideLantern == nil && !go.guideLamps.isEmpty && go.guideLamps.count <= GuideLanterns.maxLamps && go.scene.items.first { $0.name == GuideLanterns.lanternName }?.hidden == true, "guides: on Oren's route there are lamps Ilse left, and no lantern")
        let litNow = go.guideLamps.map(\.lit)
        let oEntry = go.guideLamps.first!.position, oEnd = go.guideLamps.last!.position
        go.player.position = SIMD3(oEnd.x, go.scene.groundHeight(x: oEnd.x, z: oEnd.y), oEnd.y); frame(go)
        check(litNow.filter { $0 }.count < go.guideLamps.count && go.guideLamps.allSatisfy(\.lit) && simd_length(oEntry - oEnd) > 10, "guides: the lamps come on as he draws near and every one stays lit once passed (\(litNow.filter { $0 }.count) of \(go.guideLamps.count) at the start)")
        go.state.set(Game.routeSolvedFlag); frame(go)
        check(go.guideLamps.isEmpty && go.guideLantern == nil && go.scene.items.first { $0.name == GuideLanterns.lampName(0) }?.hidden == true, "guides: the world solved, the guides are gone")
        let gv = routeGame(.ilse); gv.travel(to: .varrow); frame(gv)
        check(gv.guideLantern == nil, "guides: back on Varrow there are none")

        // The chain map: read like the note, not the journal; no text but the first pin's name (drawn from data); put away like it.
        let cm = routeGame(.ilse); frame(cm)
        cm.activate(ChainMap.interactableName)
        check(cm.readingMap && cm.reading == nil && !cm.journal.isOpen, "map: reading the chain map shows the map card, not the journal or a note")
        var clickIn = InputState(); clickIn.click = true; clock += 0.05; cm.advance(now: clock, input: clickIn)
        check(!cm.readingMap, "map: a click puts it away")
        check(ChainMap.pins.count >= 7 && ChainMap.pins.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 } && ChainMap.firstName == "Varrow", "map: the chain has its pins, all on the card, the first named Varrow")
        cm.activate(ChainMap.interactableName); let savedMap = twoWorlds(); savedMap.restore(cm.makeSave())
        check(!savedMap.readingMap, "map: and it does not survive a load")

        // S04 (optional): the Roll of Keepers' piece of evidence lists in the Notebook only once a route has begun, reads per route, takes the player's own mapping, and gates nothing.
        let rl0 = twoWorlds(); for n in [4, 8] { rl0.restorePage(n) }
        check(rl0.visibleEvidence(Contradictions.find("who-left")!).map(\.page) == [4, 5, 8, 9], "roll: before a route the Notebook lists the four pages of the nine, not the Archive's")
        let rl = routeGame(.oren); for n in [4, 8] { rl.restorePage(n) }; frame(rl)
        check(rl.visibleEvidence(Contradictions.find("who-left")!).map(\.page) == [4, 5, 8, 9, 12] && Contradictions.find("who-left")!.evidence.last!.excerpt(route: rl.journal.route) == "Oren. Through the lens first. Lost.", "roll: once a route has begun the fifth piece is listed, in that route's reading")
        let gateRoll = rl.gate
        rl.activate("page_12")
        check(rl.setClaim("who-left", page: 12, to: .his) && rl.claim("who-left", page: 12) == .his, "roll: the found page can be set to either account")
        rl.setClaim("who-left", page: 4, to: .hers); rl.setClaim("who-left", page: 8, to: .hers)
        check(rl.isSettled("who-left") && rl.gate.ilsePages == gateRoll.ilsePages && rl.gate.orenPages == gateRoll.orenPages, "roll: pages 4, 8 and 12, mapped as the player reads them, settle it, and no gate count changed")

        // S04.4: the puzzle tells the Archive's audio what happens: the fork's tone held and let go, a gate opening and closing.
        let evG = routeGame(.ilse), tideEv = evG.tideArchive!
        to(evG, 2); _ = evG.drainEvents(); tideEv.touchSluice(0)
        let e1 = evG.drainEvents()
        to(evG, evG.time + hold)
        let e2 = evG.drainEvents()
        check(e1.contains(.forkTone(0, true)) && e2.contains(.forkTone(0, false)) && e2.contains(.sluice(0, true)), "archive audio events: touching a gate with the fork holds its tone, and letting it go and the gate opening are sent (\(e1.count + e2.count) events)")
        to(evG, 30); tideEv.touchSluice(2); to(evG, evG.time + hold + T.Timing.wrongResetDelay + 0.3)
        check(evG.drainEvents().contains(.sluice(0, false)) && tideEv.opened == 0, "archive audio events: the stone gate before the wind gate sends the open tide gate closing")

        // The shadow-play tableau (optional): data first.
        let tb = ShadowTableaux.archive
        check(tb.ilseSide.count == 2 && tb.orenSide.count == 2 && Set(tb.ilseSide.map(\.who)) == [.ilse, .oren] && Set(tb.orenSide.map(\.who)) == [.ilse, .oren], "tableau: the same two figures in both versions of the one moment")
        check(tb.figures(.ilse) != tb.figures(.oren) && tb.ilseSide.map(\.posture) != tb.orenSide.map(\.posture) && zip(tb.ilseSide.sorted { $0.who.rawValue < $1.who.rawValue }, tb.orenSide.sorted { $0.who.rawValue < $1.who.rawValue }).allSatisfy { abs($0.x - $1.x) > 0.05 && $0.posture != $1.posture }, "tableau: each figure is in a different place and a different posture in the other version")
        check(tb.ilseSide.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.height > 0.3 && $0.height <= 1 } && tb.orenSide.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.height > 0.3 && $0.height <= 1 }, "tableau: every silhouette lies on the wall and is of a sensible height")
        let gapI = abs(tb.ilseSide[0].x - tb.ilseSide[1].x), gapO = abs(tb.orenSide[0].x - tb.orenSide[1].x)
        check(gapO < gapI && tb.ilseSide[0].who == .ilse && tb.ilseSide[0].x < tb.ilseSide[1].x && tb.orenSide[0].who == .oren, "tableau: from Ilse's side the gap is wide and she stays at her lamp; from Oren's he stands nearer the middle and reaches back, the gap narrower")
        check(abs(ShadowTableaux.shift(0)) < 1e-6 && abs(ShadowTableaux.shift(10) - 1) < 1e-5 && abs(ShadowTableaux.shift(5.3) - ShadowTableaux.shift(45.3)) < 1e-4, "tableau: the slow shift is a pure periodic function of the clock")
        // Play: the route's own side first, the other once it has been seen; each shows its own version; seen is remembered; saves; nothing gates.
        let ti = routeGame(.ilse); frame(ti); let tiT = ti.tideArchive!
        func enabled(_ g: Game, _ side: PageAuthor) -> Bool { g.interactables.first { $0.id == T.tableauLightName(side) }?.enabled == true }
        check(enabled(ti, .ilse) && !enabled(ti, .oren) && ti.tableauShown == nil, "tableau: on Ilse's route her own side's lantern can be lit from the start, Oren's cannot yet, and the wall is dark")
        ti.activate(T.tableauLightName(.ilse)); frame(ti)
        check(ti.tableauShown == .ilse && tiT.tableauSeen(.ilse) && !tiT.tableauSeen(.oren) && enabled(ti, .oren), "tableau: lighting it from her side shows her version, and the other side's lantern can now be lit")
        let gateT = ti.gate
        ti.activate(T.tableauLightName(.oren)); frame(ti)
        check(ti.tableauShown == .oren && tiT.tableauSeen(.oren) && tiT.tableauSeen(.ilse) && ti.gate == gateT && !ti.routeSolved, "tableau: lighting it from his side shows his version instead; both are seen; nothing is solved or counted")
        check((ti.scene.items.first { $0.name == ShadowTableaux.archive.lanternItems[.oren]! }?.uniforms.emissive.w ?? 0) > 0 || ti.scene.items.first { $0.name == ShadowTableaux.archive.lanternItems[.oren]! } == nil, "tableau: the lit side's lantern glows (the item is builder A's: absent in the stand-in)")
        let tOren = routeGame(.oren); frame(tOren)
        check(enabled(tOren, .oren) && !enabled(tOren, .ilse), "tableau: on Oren's route his own side is the one within reach first")
        tOren.activate(T.tableauLightName(.oren)); frame(tOren)
        check(tOren.tableauShown == .oren && enabled(tOren, .ilse), "tableau: and lighting it shows his version, then hers can be lit")
        let tl = twoWorlds(); tl.restore(ti.makeSave()); frame(tl)
        check(tl.tideArchive?.tableauSeen(.ilse) == true && tl.tideArchive?.tableauSeen(.oren) == true && tl.tableauShown == nil, "tableau: a save keeps which versions have been seen, and the wall is dark again after a load")

        // A save between the third gate and the drain still finishes (the 2.5 s window).
        let w = routeGame(.ilse), tideW = w.tideArchive!
        to(w, 2); tideW.touchSluice(0); to(w, w.time + hold)
        to(w, 20); tideW.touchSluice(1); to(w, w.time + hold)
        to(w, 30); tideW.touchSluice(2); to(w, w.time + hold)
        check(tideW.opened == 3 && !w.routeSolved, "archive: all three gates open and the drain not yet done (the window)")
        let wl = twoWorlds(); wl.restore(w.makeSave())
        wl.simulate(seconds: T.Timing.drainDelay + 0.3)
        check(wl.routeSolved && wl.state.has(T.drainedFlag), "archive: a save made in that window finishes the drain after a load (it used to leave the world unsolved for good)")

        // With the flag off there is no Archive puzzle at all (the build stays as it was).
        Game.tideArchiveEnabled = false
        check(twoWorlds().tideArchive == nil, "archive: behind the flag: with it off there is no puzzle and no stand-in interactables")
        Game.tideArchiveEnabled = true
        _ = lh
    }
}
