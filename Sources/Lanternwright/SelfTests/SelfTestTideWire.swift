import Foundation
import simd

/// Self-tests: the Tide Archive puzzle wired to builder A's real world (S04 wiring): the routes begin at the right quays, the sluices, ring, tools, quay rings and floors are at A's landmarks, and both routes
/// can be played by clicks from the quay to the drained gallery in the three-scene game. (The stand-in's tests are in SelfTestTideArchive.)
extension SelfTestRunner {
    func runTideWire() {
        guard name == "all" || name == "tidewire" || name == "tidearchive" else { return }
        Game.tideArchiveEnabled = true
        defer { Game.tideArchiveEnabled = false }
        let archive = TideArchive.build(device: device)
        func world3() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: archive]) }
        func routeGame(_ route: PageAuthor) -> Game {
            let g = world3()
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end"); g.state.set(Game.doorOpenFlag)
            g.simulate(seconds: 0.1)
            check(g.beginRoute(route), "tide wire: the route begins (\(route))")
            g.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
            _ = g.drainEvents()
            return g
        }
        func flat(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, p.z) }
        let ig = routeGame(.ilse), og = routeGame(.oren)
        check(ig.world == .tideArchive && og.world == .tideArchive && ig.routeWorld == .tideArchive, "tide wire: with the Archive built, both routes lead to it")
        check(simd_length(flat(ig.player.position) - flat(ArchiveLayout.lampEnd)) < 1 && simd_length(flat(og.player.position) - flat(ArchiveLayout.openEnd)) < 1, "tide wire: Ilse arrives at the lamp end, Oren at the open end")
        check(ig.tideArchive?.hasFork == true && ig.tideArchive?.hasLens == false && og.tideArchive?.hasLens == true && og.tideArchive?.hasFork == false, "tide wire: each route arrives holding its own tool")
        let ids = Set(ig.interactables.map(\.id))
        let want = Set(TideArchivePuzzle.sluiceNames + [TideArchivePuzzle.ringName, TideArchivePuzzle.findForkName, TideArchivePuzzle.findLensName, ChainMap.interactableName] + TideSpots.returnIDs + StoryPages.archiveIDs.map { "page_\($0)" })
        check(want.isSubset(of: ids), "tide wire: the Archive's interactables exist (missing: \(want.subtracting(ids)))")
        var onGround = true
        for it in ig.interactables {
            let c = (it.min + it.max) / 2, g = archive.groundHeight(x: c.x, z: c.z)
            if c.y < g - 0.1 || c.y > g + 4 { onGround = false; print("tide wire: \(it.id) at y \(c.y), ground \(g)") }
        }
        check(onGround, "tide wire: every interaction box sits within reach above A's floor")
        // Floors and water follow A's rooms and A's tide.
        let sluice = ArchiveLayout.sluiceSites[0]
        ig.player = Player(position: SIMD3(sluice.x, archive.groundHeight(x: sluice.x, z: sluice.y), sluice.y), yaw: 0)
        check(ig.archiveFloor == .grating && ig.archiveWaterDepth == Tide.depth(ground: ig.scene.groundHeight(x: sluice.x, z: sluice.y), time: ig.time), "tide wire: a sluice room is brass grating and its water is the tide's depth over A's floor")
        let quay = ArchiveLayout.lampEnd
        ig.player = Player(position: SIMD3(quay.x, archive.groundHeight(x: quay.x, z: quay.z), quay.z), yaw: 0)
        check(ig.archiveFloor == .slate && ig.archiveWaterDistance > 0, "tide wire: the quay is wet slate and away from the sluice rooms' water")
        // Playing it: Ilse's gates by the fork at each window, then the return ring.
        let bot = PlaythroughBot(ig)
        for k in 0..<3 {
            let c = TideSpots.gate(k)
            ig.player = Player(position: SIMD3(c.x, archive.groundHeight(x: c.x, z: c.z + 1.8), c.z + 1.8), yaw: 0)
            bot.tick()
            bot.wait(Tide.wait(for: k, from: ig.time) + 0.5)
            _ = bot.click(TideArchivePuzzle.sluiceNames[k]); bot.wait(TideArchivePuzzle.Timing.toneHold + 0.3)
        }
        bot.wait(TideArchivePuzzle.Timing.drainDelay + 0.5)
        check(ig.routeSolved && ig.tideArchive?.opened == 3, "tide wire: Ilse, by clicks on the three gates in A's rooms, drains the gallery")
        let gate0 = archive.items.first { $0.name == ArchiveProps.gateName(0) }?.uniforms.model
        check(gate0 != nil && abs(gate0!.columns.3.y - ArchiveProps.sluiceGateModel(0, open: 1).columns.3.y) < 1e-4, "tide wire: A's gate 0 has lifted when its sluice opened")
        check(ig.interactables.first { $0.id == "page_15" }?.enabled == true, "tide wire: the Great Ledger page is on offer once the water is drained")
        let r = TideSpots.quayReturn(.ilse)
        ig.player = Player(position: SIMD3(r.x, archive.groundHeight(x: r.x, z: r.z + 1), r.z + 1), yaw: 0)
        ig.activate(TideSpots.returnIDs[0]); ig.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        check(ig.world == .varrow, "tide wire: the quay's ring returns the player to Varrow")
        // Oren's way: the ring turned onto each mark.
        let ring = TideSpots.prismRing
        og.player = Player(position: SIMD3(ring.x, archive.groundHeight(x: ring.x, z: ring.z + 1.8), ring.z + 1.8), yaw: 0)
        let puzzle = og.tideArchive!
        for k in 0..<3 {
            og.simulate(seconds: Tide.wait(for: k, from: og.time) + 0.4)
            let steps = Int(((TideArchivePuzzle.beamTargets[k] - puzzle.ringAngle) / TideArchivePuzzle.ringStep).rounded())
            puzzle.turn(steps); og.simulate(seconds: TideArchivePuzzle.Timing.beamHold + 0.3)
        }
        og.simulate(seconds: TideArchivePuzzle.Timing.drainDelay + 0.5)
        check(og.routeSolved && puzzle.opened == 3, "tide wire: Oren, by the ring turned onto each mark in the prism chamber, drains the gallery")
        // A save in the Archive restores there.
        let loaded = world3(); loaded.restore(og.makeSave()); loaded.simulate(seconds: 0.3)
        check(loaded.routeSolved && loaded.tideArchive?.opened == 3, "tide wire: a solved Archive loads solved")
    }
}
