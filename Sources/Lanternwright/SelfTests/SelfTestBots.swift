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
        check(bot.walk(to: path[0], within: 2.5), "bot: from the spawn at the end of the dock to the shore")
        check(bot.walk(to: PuzzleProps.pagePosition(1, terrain: g.scene.terrain), within: 1.6) && bot.click("page_1") && g.journal.collectedPages.map(\.number) == [1], "bot: reads page 1 on the dock with a real click")
        bot.closeJournal()
        check(!g.journal.isOpen, "bot: closes the journal with J")
        check(bot.walk(to: path[0], within: 2.5), "bot: back to the shore")
        var struck = true
        for (i, id) in LighthousePuzzle.order.enumerated() {
            struck = struck && bot.walk(to: path[i + 1], within: 2.2)
            struck = struck && bot.click("stone_\(id.name)")
            bot.wait(0.9)
        }
        check(struck, "bot: walks to each stone in turn and clicks it")
        bot.wait(LighthousePuzzle.Timing.total + 1)
        check(g.state.has("solved") && g.state.has("lighthouseLit") && g.state.has("causewayUp"), "bot: tide, wind, stone solves the lighthouse and raises the causeway")

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
        check(bot.walk(to: PuzzleProps.lensRestPosition, within: 3.2, timeout: 60), "bot: crosses the causeway to the islet")
        check(bot.click("lens"), "bot: clicks the lens")
        bot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        check(g.world == .glassWood && g.state.has("lensTouched"), "bot: the lens carries it to the Glass Wood")

        // --- The Glass Wood: mirror court by real clicks, chimes by ear-order, the altar, then home.
        let gp = GlassLayout.path
        check(bot.follow(Array(gp[0...4]), within: 2.5), "bot: follows the lit path to the mirror court")
        var turned = true
        for k in 0..<3 {
            let turns = (MirrorCourt.solutionMirrors[k] - MirrorCourt.initialMirrors[k] + 4) % 4
            turned = turned && bot.walk(to: GlassPuzzleProps.mirrorPosition(k), within: 3.0, timeout: 40)
            for _ in 0..<turns { turned = turned && bot.click("gw_mirror_\(k)"); bot.wait(0.5) }
        }
        for k in 0..<3 {
            let turns = (MirrorCourt.solutionPanes[k] - MirrorCourt.initialPanes[k] + 3) % 3
            turned = turned && bot.walk(to: GlassPuzzleProps.panePosition(k), within: 3.0, timeout: 40)
            for _ in 0..<turns { turned = turned && bot.click("gw_pane_\(k)"); bot.wait(0.5) }
        }
        check(turned, "bot: turns each mirror and changes each pane with real clicks")
        bot.wait(3)
        check(g.state.has("gw_mirrors"), "bot: the moonbeam meets tide, wind, stone in order and the court is solved")
        check(g.scenes[.glassWood]!.items.first { $0.name == "page_6" }.map { !$0.hidden } == true, "bot: Oren's page 6 appears at the orb")

        check(bot.follow(Array(gp[4...8]), within: 2.5), "bot: follows the path on to the chime ring")
        var rang = true
        for k in GlassWoodLogic.chimeSolution {
            rang = rang && bot.walk(to: GlassPuzzleProps.chimePosition(k), within: 3.0, timeout: 40)
            rang = rang && bot.click("gw_chime_\(k)"); bot.wait(0.8)
        }
        check(rang, "bot: strikes the three pillars that carry the stones' tones")
        bot.wait(3)
        check(g.state.has("gw_chimes"), "bot: the chime puzzle is solved")

        check(bot.follow(Array(gp[8...]), within: 3.0), "bot: walks on to the altar")
        bot.wait(6)
        var heard = true
        for id in ["gw_altar_ilse", "gw_altar_oren"] {
            heard = heard && bot.walk(to: (bot.interactable(id).map { ($0.min + $0.max) * 0.5 }) ?? GlassLayout.altar, within: 2.6, timeout: 30)
            heard = heard && bot.click(id); bot.wait(1)
        }
        check(heard && g.state.has("gw_end"), "bot: hears both accounts and reaches the end of the second world")

        // --- Home: back to the arrival ring and through it.
        check(bot.follow(Array(gp.reversed()), within: 3.0), "bot: walks the whole path back to the arrival pad")
        check(bot.walk(to: GlassLayout.returnLens, within: 3.4, timeout: 40) && bot.click("gw_return"), "bot: clicks the return ring")
        bot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        check(g.world == .varrow && g.state.has("gw_end"), "bot: back on Varrow with the story done")
    }
}
