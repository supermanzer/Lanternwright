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
        let freshBeam = archive.items.first { $0.name == ArchiveProps.beamOutName(0) }?.uniforms.emissive.w
        check(freshBeam == TideArchivePuzzle.beamStrength, "tide wire: the puzzle's beam strength is the one A builds the beams with (\(freshBeam ?? -1))")
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
        let bg = routeGame(.oren), bp = bg.tideArchive!
        func beamW(_ k: Int) -> Float { archive.items.first { $0.name == ArchiveProps.beamOutName(k) }?.uniforms.emissive.w ?? 0 }
        bg.simulate(seconds: 0.2)
        let idle = beamW(0)
        check(idle > 0, "tide wire: an outgoing beam keeps A's own strength at rest (\(idle))")
        bp.turn(Int(((TideArchivePuzzle.beamTargets[0] - bp.ringAngle) / TideArchivePuzzle.ringStep).rounded()))
        check(beamW(0) > idle && abs(beamW(1) - idle) < 1e-4, "tide wire: the beam the ring rests on brightens above A's strength and the others do not (\(beamW(0)) vs \(beamW(1)))")
        // The lamps: each is its beam's colour, bright while the ring rests on its gate and steady once it is open; the wheel turns over time when the gate is answered.
        func lamp(_ k: Int) -> SIMD4<Float> { archive.items.first { $0.name == SluiceLamps.name(k) }?.uniforms.emissive ?? .zero }
        let lg = routeGame(.oren), lp = lg.tideArchive!
        lg.simulate(seconds: 0.2)
        check((0..<3).allSatisfy { k in simd_length(SIMD3(lamp(k).x, lamp(k).y, lamp(k).z) - ArchiveProps.beamColours[k]) < 1e-4 && lamp(k).w == SluiceLamps.idle }, "tide wire: each sluice room's lamp is its beam's colour (tide, wind, stone) and dim at rest")
        lp.turn(Int(((TideArchivePuzzle.beamTargets[1] - lp.ringAngle) / TideArchivePuzzle.ringStep).rounded()))
        check(lamp(1).w == SluiceLamps.aimed && lamp(0).w == SluiceLamps.idle && lamp(2).w == SluiceLamps.idle, "tide wire: the lamp of the gate the beam rests on brightens, the others stay dim")
        lg.simulate(seconds: 0.1)
        let wheelY = { (k: Int) -> Float in archive.items.first { $0.name == ArchiveProps.wheelName(k) }?.uniforms.model.columns.0.y ?? 9 }
        check(wheelY(1) == 0, "tide wire: the wheel waits shut before the gate is answered")
        lg.simulate(seconds: Tide.wait(for: 1, from: lg.time) + 0.4 + TideArchivePuzzle.Timing.beamHold)
        // (the ring rested on the wind gate, but the tide gate is first in order: the wind attempt fails and the gates stay shut)
        check(lp.opened == 0 && lamp(0).w == SluiceLamps.idle, "tide wire: a beam resting on the second gate first opens nothing")
        lg.simulate(seconds: TideArchivePuzzle.Timing.wrongResetDelay + 0.3)                  // (the wrong-order reset has run)
        lg.simulate(seconds: Tide.wait(for: 0, from: lg.time) + 0.4)
        lp.turn(Int(((TideArchivePuzzle.beamTargets[0] - lp.ringAngle) / TideArchivePuzzle.ringStep).rounded()))
        lg.simulate(seconds: TideArchivePuzzle.Timing.beamHold + 0.1)
        check(lp.opened == 1 && lamp(0).w == SluiceLamps.open, "tide wire: answered, the tide room's lamp stays lit (steady)")
        lg.simulate(seconds: TideArchivePuzzle.Timing.wheelSpin)
        check(abs(wheelY(0)) < 1e-3, "tide wire: the wheel has turned its two whole turns once the gate is answered")
        let wg = routeGame(.ilse), wp = wg.tideArchive!
        wg.simulate(seconds: Tide.wait(for: 0, from: wg.time) + 0.4); wp.touchSluice(0)
        wg.simulate(seconds: TideArchivePuzzle.Timing.toneHold + TideArchivePuzzle.Timing.wheelSpin * 0.25)
        check(abs(wheelY(0)) > 0.3, "tide wire: a quarter of the way through the spin the wheel is part-turned (sin \(wheelY(0)))")
        // A save taken mid-puzzle (two gates open) restores there with its wheels, gates and lamps.
        let mg = routeGame(.ilse), mp = mg.tideArchive!
        for k in 0..<2 { mg.simulate(seconds: Tide.wait(for: k, from: mg.time) + 0.4); mp.touchSluice(k); mg.simulate(seconds: TideArchivePuzzle.Timing.toneHold + 0.2) }
        check(mp.opened == 2 && !mg.routeSolved, "tide wire: two gates open by the fork, the world not solved")
        let ms = mg.makeSave()
        for k in 0..<3 {                                                                                                   // (the scene is shared by these games: put every gate, wheel and lamp back as a fresh one is, so only the restore can raise them)
            archive.update(ArchiveProps.gateName(k)) { $0.uniforms.model = ArchiveProps.sluiceGateModel(k, open: 0) }
            archive.update(ArchiveProps.wheelName(k)) { $0.uniforms.model = ArchiveProps.sluiceWheelModel(k, turns: 0) }
            archive.update(SluiceLamps.name(k)) { $0.uniforms.emissive.w = SluiceLamps.idle }
        }
        let mr = world3(); mr.restore(ms); mr.simulate(seconds: 0.3)
        let gy = { (k: Int) -> Float in archive.items.first { $0.name == ArchiveProps.gateName(k) }?.uniforms.model.columns.3.y ?? 0 }
        check(mr.tideArchive?.opened == 2 && !mr.routeSolved && mr.chosenPath == .ilse && mr.world == .tideArchive, "tide wire: a save mid-puzzle restores in the Archive with two gates open")
        check(gy(0) > ArchiveLayout.sluices[0].y + 1 && gy(1) > ArchiveLayout.sluices[1].y + 1 && gy(2) < ArchiveLayout.sluices[2].y + 0.01 && lamp(0).w == SluiceLamps.open && lamp(2).w == SluiceLamps.idle, "tide wire: and its open gates are up, the third down, the open rooms' lamps steady")
        // Without the Archive built (two scenes) and the flag on, the route still leads to the Glass Wood stand-in and nothing of the Archive's spots is registered.
        let two = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
        for n in [1, 2, 3, 5, 6, 7] { two.restorePage(n) }
        two.state.set("gw_end"); two.state.set(Game.doorOpenFlag); two.simulate(seconds: 0.1)
        check(two.beginRoute(.ilse), "tide wire: two scenes, flag on: the route begins")
        two.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        check(two.world == .glassWood && two.routeWorld == .glassWood && !two.realArchive && two.tideArchive?.hasFork == true && !two.interactables.contains { TideSpots.returnIDs.contains($0.id) }, "tide wire: with only two scenes the flag leaves the Glass Wood as the route world, on the stand-in")
        // A save in the Archive restores there.
        let loaded = world3(); loaded.restore(og.makeSave()); loaded.simulate(seconds: 0.3)
        check(loaded.routeSolved && loaded.tideArchive?.opened == 3, "tide wire: a solved Archive loads solved")
    }
}
