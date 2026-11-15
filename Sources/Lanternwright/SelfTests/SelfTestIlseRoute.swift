import Foundation
import Metal
import simd

/// S05.3 (builder B): Ilse's route through the Archive: A0 the tide marks, I1 the catalogue, I2 the bell pipes (Game/IlseRoute.swift). Rules on the data, then a bot that arrives at the lamp quay from a fresh
/// game's end state and plays the route by real walking and clicks (no teleport), with a save and a load in the middle.
extension SelfTestRunner {
    /// A0, I1 and the rod by real walking and clicks, from the lamp quay (the player has just arrived): the bot waits at the quay for the marks, rings the catalogue and takes the rod. Returns whether the rod is in hand.
    func ilsePrerequisites(_ g: Game, _ bot: PlaythroughBot) -> Bool {
        guard let r = g.ilseRoute else { return false }
        var w: Float = 0
        while !r.marksDone && w < 100 { bot.wait(1); w += 1 }
        for k in IlseRoute.sequence {
            let b = ShelfBays.bellPoint(g.scene, k)
            _ = bot.walk(to: SIMD3(b.x + 2.6, 0, b.z), within: 1.0, timeout: 200); _ = bot.click(IlseRoute.bayNames[k]); bot.wait(0.4)
        }
        bot.wait(4)
        let door = ArchiveLayout.ledgerDoor, rod = ArchiveLayout.ledgerKey
        _ = bot.walk(to: SIMD3(door.x, 0, door.z + 2.5), within: 1.0, timeout: 100, straight: true); _ = bot.walk(to: SIMD3(door.x, 0, door.z - 0.8), within: 0.8, timeout: 30, straight: true)
        _ = bot.walk(to: SIMD3(rod.x, 0, rod.z + 1.4), within: 1.0, timeout: 30, straight: true); _ = bot.click(IlseRoute.keyName); bot.wait(0.3)
        _ = bot.walk(to: SIMD3(door.x, 0, door.z - 0.8), within: 0.8, timeout: 30, straight: true); _ = bot.walk(to: SIMD3(door.x, 0, door.z + 2.5), within: 1.0, timeout: 30, straight: true)
        return r.hasRod
    }
    /// Pipe k: walk to its room (the stone room's edge first, then in when the water allows), hold the fork to it and wait for the gate. Returns whether the gate answered.
    func ilsePipe(_ k: Int, _ g: Game, _ bot: PlaythroughBot) -> Bool {
        guard let r = g.ilseRoute, let t = g.tideArchive else { return false }
        let p = ArchiveLayout.pipe(k)
        if k == 2 {
            _ = bot.walk(to: SIMD3(p.x + 3, 0, p.z + 10), within: 2, timeout: 300)
            var w: Float = 0; while !(Tide.inWindow(2, level: Tide.level(g.time)) && Tide.inWindow(2, level: Tide.level(g.time + 8))) && w < 100 { bot.wait(0.5); w += 0.5 }
        }
        // The shore between the rooms runs through the stone room's pit, which the high tide floods: a player who is turned back waits and tries again.
        var walked = false
        for _ in 0..<8 where !walked { walked = bot.walk(to: SIMD3(p.x, 0, p.z + 2.2), within: 1.6, timeout: 200); if !walked { bot.wait(12) } }
        let clicked = walked && bot.click(IlseRoute.pipeNames[k])
        guard walked, clicked, r.holding == k else { print("ilsePipe \(k): walked \(walked) clicked \(clicked) holding \(String(describing: r.holding)) rod \(r.hasRod) feet \(bot.feet) pipe \(p) tide \(Tide.level(g.time))"); return false }
        var s: Float = 0
        while t.opened <= k && s < 120 { bot.wait(0.25); s += 0.25 }
        return t.opened > k
    }
    func runIlseRoute() {
        guard name == "all" || name == "ilseroute" else { return }
        typealias R = IlseRoute
        let fade = Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.8

        // ---- The data. The catalogue is not the stones' order; the marks are the rooms' own levels, highest first; each pipe's agreement lasts long enough to be caught at the game's tick.
        check(R.sequence.count == 3 && Set(R.sequence).count == 3 && R.sequence.allSatisfy { (0..<ShelfBays.count).contains($0) } && R.sequence != [0, 2, 4], "ilseroute: the catalogue is three different bays and not the stones' own order (bays 0, 2, 4)")
        let marks = R.markLevels
        check(marks.count == 3 && marks[0] > marks[1] && marks[1] > marks[2] && marks.allSatisfy { $0 > 0.05 && $0 < 0.95 }, "ilseroute: the three marks are the rooms' levels, the tide room's highest (\(marks.map { String(format: "%.2f", $0) }))")
        for k in 0..<3 {
            // seconds each pass of the level through the match band lasts, over a whole tide cycle
            var best: Float = .infinity, t: Float = 0, run: Float = 0, runs: [Float] = []
            while t < Tide.period * 2 {
                let agree = abs(IlseTones.pipeHz(k, level: Tide.level(t)) - ToneTable.stoneHz[k]) <= IlseTones.agreeHz
                if agree { run += Game.tick } else if run > 0 { runs.append(run); run = 0 }
                t += Game.tick
            }
            best = runs.min() ?? 0
            check(runs.count >= 3 && best >= 0.2 && best <= 3, "ilseroute: pipe \(k) agrees with the fork for \(String(format: "%.2f", best)) s at the quickest pass (a crossing a player catches, not a hold)")
        }

        // ---- A game on Ilse's route in the Archive.
        func world3() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)]) }
        func arrive() -> (Game, PlaythroughBot)? {
            let g = world3()
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end"); g.state.set(Game.doorOpenFlag); g.simulate(seconds: 0.1)
            guard g.beginRoute(.ilse) else { return nil }
            g.simulate(seconds: fade)
            let bot = PlaythroughBot(g); bot.wait(0.5)
            return (g, bot)
        }
        guard let (g, bot) = arrive(), let route = g.ilseRoute, let tide = g.tideArchive else { check(false, "ilseroute: Ilse's route could not begin"); return }
        check(g.world == .tideArchive && route.isActive && tide.hasFork, "ilseroute: Ilse arrives in the Archive with the fork and her route's site")
        check(!tide.touchHolds() && !tide.ringWorks(), "ilseroute: on her route the wheel's held tone and the lens ring are not her ways")
        check(g.interactables.first { $0.id == R.keyName }?.enabled == false, "ilseroute: the rod cannot be taken before the catalogue is done")

        // Before the marks are counted a bay only rings.
        let stand = { (k: Int) -> SIMD3<Float> in let b = ShelfBays.bellPoint(g.scene, k); return SIMD3(b.x + 2.6, 0, b.z) }
        let toBays = bot.walk(to: stand(3), within: 1.2, timeout: 200)
        check(toBays, "ilseroute: the bot walks from the lamp quay to the bays along the route (ended \(bot.feet))")
        _ = bot.click(R.bayNames[3]); bot.wait(0.3)
        check(route.progress == 0 && !route.marksDone, "ilseroute: before the marks are counted a bay rings and asks nothing of the sequence")
        // A0: stand near the quay while the water passes the three levels. (The bot walked away from the quay: go back and wait there, as a player told to wait would.)
        let atQuay = bot.walk(to: SIMD3(ArchiveLayout.lampEnd.x + 3, 0, ArchiveLayout.lampEnd.z - 4), within: 3, timeout: 200)
        var waited: Float = 0
        while !route.marksDone && waited < 100 { bot.wait(1); waited += 1 }
        check(atQuay && route.marksDone && route.marksCounted == 3, "ilseroute: A0: standing at the quay the water crosses the three marks and all three are counted (\(Int(waited)) s)")
        // A0 does not count from far away: a second game, the bot at the bays all the while.
        if let (g2, bot2) = arrive() {
            _ = bot2.walk(to: stand(3), within: 1.2, timeout: 200)
            bot2.wait(Tide.period + 5)
            check(g2.ilseRoute?.marksCounted == 0 || (g2.ilseRoute?.marksCounted ?? 0) < 3, "ilseroute: a player who walked off to the stacks and stayed there has counted nothing (A0 is counted at the quay: \(g2.ilseRoute?.marksCounted ?? -1) of 3)")
        }

        // I1: a wrong bay sours and the sequence starts over; the right order opens the ledger room.
        check(bot.walk(to: stand(3), within: 1.2, timeout: 200), "ilseroute: back to the bays")
        _ = bot.click(R.bayNames[R.sequence[0]]); bot.wait(0.3)
        check(route.progress == 1, "ilseroute: I1: the first right bay rings and stays warm")
        let wrong = (0..<ShelfBays.count).first { !R.sequence.contains($0) }!
        func ringBay(_ k: Int) -> Bool { let w = bot.walk(to: stand(k), within: 1.0, timeout: 100); return w && bot.click(R.bayNames[k]) }
        check(ringBay(wrong), "ilseroute: the bot walks to a bay outside the catalogue and rings it"); bot.wait(R.sourSeconds + 0.5)
        check(route.progress == 0 && !route.catalogueDone, "ilseroute: I1: a wrong bay sours and the bays go dormant: the sequence starts over, nothing else is lost")
        for k in R.sequence { _ = ringBay(k); bot.wait(0.4) }
        bot.wait(4)
        check(route.catalogueDone && g.state.has(R.catalogueFlag), "ilseroute: I1: ringing the three in the catalogue's order sets it done")
        let door = g.scenes[.tideArchive]?.items.first { $0.name == LedgerRoom.doorName }
        check(door != nil && (door?.uniforms.model.columns.3.y ?? 0) < ArchiveLayout.ledgerRoom.y - 1, "ilseroute: the ledger room's door has sunk into the floor")
        // A save here, loaded into a fresh game: the catalogue is still done and the room open.
        let saved = g.makeSave()
        if let (g3, _) = arrive() {
            g3.restore(saved)
            check(g3.ilseRoute?.catalogueDone == true && g3.ilseRoute?.marksDone == true, "ilseroute: a save after the catalogue loads with the marks counted and the catalogue done")
        }

        // Rules of the pipes, on a second game placed at pipe 1 with the marks, catalogue and rod done (a rule test, not a route walk): a pipe that agrees out of turn does not answer; a held fork is let go when the player walks off.
        if let (g2, bot2) = arrive(), let r2 = g2.ilseRoute, let t2 = g2.tideArchive {
            for f in R.markFlags + [R.marksFlag, R.catalogueFlag, R.keyFlag] { g2.state.set(f) }
            let p = ArchiveLayout.pipe(1)
            g2.player.position = SIMD3(p.x, g2.scene.groundHeight(x: p.x, z: p.z + 2), p.z + 2); bot2.wait(0.3)
            _ = bot2.click(R.pipeNames[1])
            check(r2.holding == 1, "ilseroute: I2: the fork can be held at any pipe")
            var crossed = 0, was = false
            for _ in 0..<(Int(Tide.period) * 4) { bot2.wait(0.25); let near = abs(r2.pipeHz(1) - r2.forkHz(1)) <= IlseTones.agreeHz; if near && !was { crossed += 1 }; was = near }
            check(crossed >= 2 && t2.opened == 0 && !g2.state.has(TideArchivePuzzle.sluiceFlags[1]) && !g2.routeSolved, "ilseroute: I2: pipe 1 agreed with the fork \(crossed) times while gate 0 was still shut and did not answer (out of turn: no penalty, no change)")
            _ = bot2.click(R.pipeNames[1])
            check(r2.holding == nil, "ilseroute: I2: touching the same pipe again lets the fork go")
            _ = bot2.click(R.pipeNames[1]); g2.player.position = SIMD3(p.x + 30, g2.scene.groundHeight(x: p.x + 30, z: p.z), p.z); bot2.wait(0.3)
            check(r2.holding == nil, "ilseroute: I2: walking away from the pipe lets the held fork go")
            // Without the rod a pipe does nothing.
            g2.state.set(R.keyFlag, false); g2.player.position = SIMD3(p.x, g2.scene.groundHeight(x: p.x, z: p.z + 2), p.z + 2); bot2.wait(0.3); _ = bot2.click(R.pipeNames[1])
            check(r2.holding == nil, "ilseroute: I2: without the rod a pipe does nothing")
        }

        // The rod, then the pipes.
        let rodAt = ArchiveLayout.ledgerKey
        let doorAt = ArchiveLayout.ledgerDoor
        let toRod = bot.walk(to: SIMD3(doorAt.x, 0, doorAt.z + 2.5), within: 1.0, timeout: 100, straight: true) && bot.walk(to: SIMD3(doorAt.x, 0, doorAt.z - 0.8), within: 0.8, timeout: 30, straight: true) && bot.walk(to: SIMD3(rodAt.x, 0, rodAt.z + 1.4), within: 1.0, timeout: 30, straight: true)
        check(toRod, "ilseroute: the bot walks into the open ledger room (ended \(bot.feet))")
        check(bot.click(R.keyName) && route.hasRod, "ilseroute: it takes the rod")
        bot.wait(0.3)
        _ = bot.walk(to: SIMD3(doorAt.x, 0, doorAt.z - 0.8), within: 0.8, timeout: 30, straight: true); _ = bot.walk(to: SIMD3(doorAt.x, 0, doorAt.z + 2.5), within: 1.0, timeout: 30, straight: true)       // out by the door
        // A pipe does nothing for a player without the rod (checked on the second game above), and nothing answers out of turn: pipe 1 first.
        var gates = 0
        for k in 0..<3 {
            let p = ArchiveLayout.pipe(k)
            if k == 2 {                                                                        // the stone room is only wadeable near low water: wait at its edge, then walk in
                _ = bot.walk(to: SIMD3(p.x + 3, 0, p.z + 10), within: 2, timeout: 300)
                var w: Float = 0; while !(Tide.inWindow(2, level: Tide.level(g.time)) && Tide.inWindow(2, level: Tide.level(g.time + 8))) && w < 100 { bot.wait(0.5); w += 0.5 }
            }
            let there = bot.walk(to: SIMD3(p.x, 0, p.z + 2.2), within: 1.6, timeout: 600)
            if !there { print("ilseroute: could not walk to pipe \(k): \(bot.feet) for \(p), tide \(Tide.level(g.time)) window \(Tide.windows[k])") }
            check(there, "ilseroute: the bot walks to pipe \(k)")
            guard there else { break }
            _ = bot.click(R.pipeNames[k])
            check(route.holding == k, "ilseroute: I2: touching pipe \(k) holds the fork to it")
            var t: Float = 0
            while tide.opened <= k && t < 120 { bot.wait(0.25); t += 0.25 }
            check(tide.opened == k + 1, "ilseroute: I2: pipe \(k) agreed with the fork and the gate answered (\(Int(t)) s)")
            if tide.opened == k + 1 { gates += 1 }
            bot.wait(0.5)
        }
        bot.wait(TideArchivePuzzle.Timing.drainDelay + 1)
        check(gates == 3 && g.routeSolved, "ilseroute: the three gates answered in the stones' order and the gallery drains (routeSolved)")
    }
}
