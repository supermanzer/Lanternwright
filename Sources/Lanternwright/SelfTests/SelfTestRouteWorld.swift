import Foundation
import Metal
import simd

/// Self-tests: the route world (S04.5): both routes enter it (the stand-in until the Tide Archive lands), the lens and the doorway lead back in until it is solved, nothing is chosen twice, the sealed exit
/// stays sealed, once solved the next lens shows dim, and all of it survives a save.
extension SelfTestRunner {
    func runRouteWorld() {
        guard name == "all" || name == "routeworld" || name == "story" else { return }
        typealias I = LighthouseInterior
        let lh = Layout.lighthouse
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        var clock = 8000.0
        func step(_ g: Game, _ n: Int = 2) { for _ in 0..<n { clock += 0.05; g.advance(now: clock, input: InputState()) } }
        func lensGame() -> Game {
            let g = twoWorlds()
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end"); g.state.set(Game.doorOpenFlag); step(g)
            g.player = Player(position: SIMD3(lh.x - 0.2, lh.y + I.lensFloorY, lh.z - 1.45), yaw: .pi)
            _ = g.drainEvents()
            return g
        }
        func fade(_ g: Game) { g.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5); step(g) }
        func backToLensRoom(_ g: Game) {
            g.travel(to: .varrow); step(g, 3)
            g.player = Player(position: SIMD3(lh.x - 0.2, lh.y + I.lensFloorY, lh.z - 1.45), yaw: .pi)
        }
        func item(_ g: Game, _ n: String) -> DrawItem? { g.scene.items.first { $0.name == n } }

        check(twoWorlds().routeWorld == .glassWood && Game.routeWorldOverride == nil, "route world: until the Tide Archive lands the route world is the Glass Wood (the one switch is Game.routeWorldOverride)")

        // Ilse's route: the lens enters it; coming back, the lens enters it again until it is solved.
        let a = lensGame()
        check(a.beginRoute(.ilse) && a.isTraveling, "route world: Ilse's lens begins her route")
        fade(a)
        check(a.world == a.routeWorld && a.chosenPath == .ilse, "route world: and she is in the route world")
        backToLensRoom(a)
        check(a.world == .varrow && !a.routeSolved && !a.nextLensShown, "route world: back on Varrow, the world is not solved and no next lens is shown")
        a.touchLampLens()
        check(a.isTraveling && a.chosenPath == .ilse, "route world: touching the lens again opens her world again (nothing is chosen twice)")
        fade(a)
        check(a.world == a.routeWorld && a.chosenPath == .ilse && !a.state.has(Game.pathOrenFlag) && a.portalSealed && !a.platesSealed, "route world: she is back in it, still Ilse's route, Oren's exit still sealed")
        // Solved: the lens no longer leads there; the next lens shows, dim, no text.
        a.state.set(Game.routeSolvedFlag)
        backToLensRoom(a)
        let bannerBefore = a.banner
        a.touchLampLens()
        check(!a.isTraveling && a.world == .varrow && a.banner == bannerBefore, "route world: once solved, touching the lens does nothing and says nothing new")
        check(a.nextLensShown && item(a, LensPortalProps.nextLensName)?.hidden == false && (item(a, LensPortalProps.nextLensName)?.uniforms.emissive.w ?? 1) == 0, "route world: and the next lens is on the collar, dull, with no light of its own")
        check(!a.reenterRoute(), "route world: nor can the way in be forced")

        // Oren's route: the doorway stays open and leads back in until the world is solved.
        let o = lensGame(); let obot = PlaythroughBot(o)
        var ok = true
        for _ in 0..<3 { ok = ok && obot.click("lens_ring"); obot.wait(0.3) }
        obot.wait(LensPortalProps.holdSeconds + 0.6)
        for _ in 0..<90 where o.chosenPath == nil { var fwd = InputState(); fwd.move = SIMD2(0, 1); o.player.yaw = 0; obot.tick(fwd) }
        obot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.8)
        check(ok && o.chosenPath == .oren && o.world == o.routeWorld && o.platesSealed, "route world: Oren's doorway begins his route and enters the route world at its open end")
        check(simd_length(SIMD2(o.player.position.x - Game.routeEntry(.oren).position.x, o.player.position.z - Game.routeEntry(.oren).position.z)) < 1.5, "route world: at the end his route enters by (the open end)")
        backToLensRoom(o)
        o.player = Player(position: SIMD3(lh.x - 0.2, lh.y + I.lensFloorY, lh.z - 1.45), yaw: 0)
        for _ in 0..<90 where !o.isTraveling { var fwd = InputState(); fwd.move = SIMD2(0, 1); o.player.yaw = 0; obot.tick(fwd) }
        check(o.isTraveling && o.chosenPath == .oren, "route world: walking into the open doorway again enters his world again")
        obot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.8)
        check(o.world == o.routeWorld, "route world: and he is there")
        o.state.set(Game.routeSolvedFlag); backToLensRoom(o)
        for _ in 0..<120 { var fwd = InputState(); fwd.move = SIMD2(0, 1); o.player.yaw = 0; obot.tick(fwd) }
        check(!o.isTraveling && o.world == .varrow && o.nextLensShown, "route world: once solved the doorway no longer leads in and the next lens shows")

        // Saves: the world, the route and the solved state come back; the way in still works from a loaded save; the sealed exit stays sealed.
        let mid = lensGame(); _ = mid.beginRoute(.ilse); fade(mid)
        let loaded = twoWorlds(); loaded.restore(mid.makeSave()); step(loaded, 3)
        check(loaded.world == loaded.routeWorld && loaded.chosenPath == .ilse && loaded.portalSealed && !loaded.routeSolved, "route world: a save made in the route world loads there, on Ilse's route, unsolved")
        let solvedSave = twoWorlds(); solvedSave.restore(a.makeSave()); step(solvedSave, 3)
        check(solvedSave.routeSolved && solvedSave.chosenPath == .ilse && solvedSave.nextLensShown == (solvedSave.world == .varrow && solvedSave.interiorApplied), "route world: and a solved save keeps the solved state and the route")
        let again = twoWorlds(); again.restore(mid.makeSave()); step(again, 3)
        again.travel(to: .varrow); step(again, 3); again.player = Player(position: SIMD3(lh.x - 0.2, lh.y + I.lensFloorY, lh.z - 1.45), yaw: .pi); step(again)
        again.touchLampLens()
        check(again.isTraveling && again.chosenPath == .ilse, "route world: from a loaded save the lens still opens her world")
    }
}
