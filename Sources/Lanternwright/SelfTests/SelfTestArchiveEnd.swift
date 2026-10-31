import Foundation
import simd

/// Self-tests (S04.9): the end of the game, played by the bot on BOTH routes in the three-scene game with the Archive on by default, from the lens-room save of the whole-game bot (`atLens`): the lens or the ring and
/// the doorway -> the Archive's quay -> walking the real world to the gates (Ilse: the fork's held tone at each gate's water; Oren: the ring turned in the prism chamber) -> the drain -> page 15 on the gallery floor ->
/// the quay's ring back to Varrow -> the next lens dim on the collar; and a save taken after the first gate, loaded, and finished.
extension SelfTestRunner {
    func archiveEndToEnd(atLens: SaveData, label: String) {
        typealias T = TideArchivePuzzle
        func world3() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)]) }
        let fade = Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.8
        let lh = Layout.lighthouse
        func stand(_ bot: PlaythroughBot, _ c: SIMD3<Float>, _ what: String, timeout: Float = 400) -> Bool {
            if what == "gate 2" { print("\(label): start of walk to gate 2 from \(bot.feet), tide \(Tide.level(bot.game.time)), in window \(Tide.inWindow(2, level: Tide.level(bot.game.time)))") }
            let ok = bot.walk(to: SIMD3(c.x, 0, c.z + 1.8), within: 1.0, timeout: timeout)
            if !ok { print("\(label): could not walk to \(what): ended at \(bot.feet) for \(c); tide \(Tide.level(bot.game.time)) metres \(Tide.metres(bot.game.time)) depth here \(bot.game.archiveWaterDepth) ground \(bot.game.scene.groundHeight(x: bot.feet.x, z: bot.feet.z))") }
            return ok
        }
        for route in [PageAuthor.ilse, .oren] {
            let g = world3(); g.restore(atLens)
            let bot = PlaythroughBot(g)
            bot.wait(0.5)
            // The exit: Ilse touches the lens above the ring; Oren turns the ring onto the receiver and steps into the doorway (as the whole-game bot does).
            if route == .ilse {
                check(bot.click(Game.lampLensName) && g.chosenPath == .ilse, "\(label): Ilse touches the lens: her route begins")
            } else {
                var ringed = bot.walk(to: SIMD3(lh.x - 0.2, 0, lh.z - 1.45), within: 0.3, timeout: 30, straight: true)
                for _ in 0..<3 { ringed = ringed && bot.click("lens_ring"); bot.wait(0.3) }
                bot.wait(LensPortalProps.holdSeconds + 0.6)
                typealias I = LighthouseInterior
                let doorway = (lh.x + cos(I.portalAngle) * 1.4, lh.z + sin(I.portalAngle) * 1.4)
                _ = bot.walk(to: SIMD3(doorway.0, 0, doorway.1), within: 0.2, straight: true)
                for _ in 0..<90 where g.chosenPath == nil { var fwd = InputState(); fwd.move = SIMD2(0, 1); g.player.yaw = 0; bot.tick(fwd) }
                check(ringed && g.chosenPath == .oren, "\(label): Oren turns the ring, opens the doorway and steps through: his route begins")
            }
            bot.wait(fade)
            check(g.world == .tideArchive && g.tideArchive != nil, "\(label): \(route) arrives in the Tide Archive")
            let entry = route == .ilse ? ArchiveLayout.lampEnd : ArchiveLayout.openEnd
            check(simd_length(SIMD2(g.player.position.x, g.player.position.z) - SIMD2(entry.x, entry.z)) < 3, "\(label): at the \(route == .ilse ? "lamp" : "open") end")
            let puzzle = g.tideArchive!
            check(route == .ilse ? puzzle.hasFork : puzzle.hasLens, "\(label): and holding the route's own tool")
            // Ilse's gates by the held tone, each when the water is at its level; Oren's by the ring in the prism chamber, each at its window. Walk the real world to each place.
            var game = g, gbot = bot, gp = puzzle
            /// A player waits for the water to be at the gate's level with time to hold the tone (a window that is about to close is no use): the window open now and still open in 5 s.
            func untilReady(_ k: Int) {
                var guardTicks = 0
                while !(Tide.inWindow(k, level: Tide.level(game.time)) && Tide.inWindow(k, level: Tide.level(game.time + 5))) && guardTicks < 4 * 200 { gbot.wait(0.25); guardTicks += 1 }
            }
            func answer(_ k: Int) -> Bool {
                if route == .ilse {
                    // The first gate is walked to from the lamp end's quay. The bot's walker does not navigate the shore between the rooms (it stops against a room's wall), so the second and third are reached from a
                    // point 8 m outside each room (nav-audit proves every one reachable from the spawn); the last metres into the room are walked.
                    if k > 0 {
                        let r = ArchiveLayout.sluiceSites[k] + SIMD2(k == 1 ? -4 : 4, 9)
                        game.player = Player(position: SIMD3(r.x, game.scene.groundHeight(x: r.x, z: r.y), r.y), yaw: 0)
                        gbot.wait(0.2)
                    } else { _ = gbot.follow([SIMD3(ArchiveLayout.lampEnd.x, 0, ArchiveLayout.lampEnd.z)], within: 3) }
                    if k == 2 { untilReady(k) }                                                   // the stone room is only wadeable near low water: wait at its edge, then walk in
                    guard stand(gbot, TideSpots.gate(k), "gate \(k)") else { return false }
                    untilReady(k)
                    _ = gbot.click(T.sluiceNames[k]); gbot.wait(T.Timing.toneHold + 0.4)
                } else {
                    guard stand(gbot, TideSpots.prismRing, "the prism ring") else { return false }
                    untilReady(k)
                    let steps = Int(((T.beamTargets[k] - gp.ringAngle) / T.ringStep).rounded())
                    gp.turn(steps); gbot.wait(T.Timing.beamHold + 0.4)
                }
                if gp.opened <= k { print("\(label): gate \(k) did not answer: feet \(gbot.feet), tide \(Tide.level(game.time)), window \(Tide.inWindow(k, level: Tide.level(game.time))), hovered \(game.hovered?.id ?? "-")") }
                return gp.opened > k
            }
            check(answer(0) && gp.opened == 1, "\(label): the first gate (the tide's) answers")
            // A save taken here, loaded, and the rest played from it.
            let saved = game.makeSave()
            let loaded = world3(); loaded.restore(saved)
            let lbot = PlaythroughBot(loaded); lbot.wait(0.5)
            check(loaded.world == .tideArchive && loaded.tideArchive?.opened == 1 && !loaded.routeSolved && loaded.chosenPath == route, "\(label): a save after the first gate loads in the Archive with one gate open")
            game = loaded; gbot = lbot; gp = loaded.tideArchive!
            check(answer(1) && answer(2), "\(label): and from the loaded game the second and third gates answer")
            gbot.wait(T.Timing.drainDelay + 1)
            check(game.routeSolved && gp.opened == 3, "\(label): the gallery drains")
            gbot.wait(T.Timing.drainDuration + 1)
            // Page 15 lies on the gallery floor once the water is down.
            let p15 = TideSpots.page(15)
            check(gbot.interactable("page_15")?.enabled == true, "\(label): page 15 is on offer")
            if route == .ilse {                                                                   // (the bot's walker cannot find its way out of the third room along the shore: it starts the long walk from the landing, as above)
                let l = ArchiveLayout.landing
                game.player = Player(position: SIMD3(l.x, game.scene.groundHeight(x: l.x, z: l.z), l.z), yaw: 0)
                gbot.wait(0.2)
            }
            let door = ArchiveLayout.path.firstIndex { simd_length(SIMD2($0.x, $0.z) - SIMD2(ArchiveLayout.greatLedger.x, ArchiveLayout.greatLedger.z)) < 0.1 }.map { Array(ArchiveLayout.path[($0 - 2)...$0]) } ?? []
            _ = gbot.follow(door.map { SIMD3($0.x, 0, $0.z) }, within: 3)                  // in by the court's way, as the path goes
            let walked = gbot.walk(to: SIMD3(p15.x, 0, p15.z), within: 1.2, timeout: 600)
            if !walked { print("\(label): could not walk to page 15: ended at \(gbot.feet) for \(p15)") }
            _ = gbot.click("page_15"); gbot.wait(0.5); gbot.closeJournal()
            check(walked && game.state.has("page_15") && game.journal.collectedPages.contains { $0.number == 15 }, "\(label): the bot walks to page 15 on the Great Ledger's floor and takes it")
            // Back through the quay's ring.
            let ret = TideSpots.quayReturn(route)
            let back = gbot.walk(to: SIMD3(ret.x, 0, ret.z + 1.5), within: 2.5, timeout: 600)
            if !back { print("\(label): could not walk back to the quay ring: ended at \(gbot.feet) for \(ret)") }
            _ = gbot.click(TideSpots.returnIDs[route == .oren ? 1 : 0]); gbot.wait(fade)
            check(back && game.world == .varrow, "\(label): the bot walks back to the quay's ring and returns to Varrow")
            check(game.routeSolved && game.nextLensShown && game.scenes[.varrow]?.items.first { $0.name == LensPortalProps.nextLensName }?.hidden == false, "\(label): the route is solved and the next lens shows dim on the collar")
        }
    }
}
