import Foundation
import Metal
import simd

/// Self-tests: the tone plates beside the lighthouse door (S03.6): the order, a wrong strike, a partial set, repeats, the gate, a save, real picking and a bot.
extension SelfTestRunner {
    func runPlates() {
        guard name == "all" || name == "plates" || name == "story" else { return }
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        func readyGame() -> Game {
            let g = twoWorlds()
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end")
            _ = g.drainEvents()
            return g
        }
        let names = TonePlates.names
        var clock = 4000.0
        func step(_ g: Game) { for _ in 0..<2 { clock += 0.05; g.advance(now: clock, input: InputState()) } }
        func strike(_ g: Game, _ ks: [Int]) { for k in ks { g.activate(names[k]) } }
        func chimes(_ evs: [GameEvent]) -> [ChimeKind] { evs.compactMap { if case .chime(let c) = $0 { return c }; return nil } }

        // The right order, with the gate ready: the tones are held, the chord blooms, the lamp answers, the door opens.
        let g = readyGame()
        strike(g, [0, 1, 2])
        let evs = g.drainEvents()
        check(chimes(evs) == [.tide, .wind, .stone] && evs.contains(.droneBloom) && evs.contains(.drone(0, true)) && evs.contains(.drone(1, true)) && evs.contains(.drone(2, true)), "plates: tide, wind, stone in order: each rings and is held, and the chord blooms")
        check(!g.state.has(Game.doorOpenFlag), "plates: the door is not open at the third strike: the lamp has yet to answer")
        g.simulate(seconds: TonePlatePuzzle.Timing.answerDelay + 0.3)
        check(chimes(g.drainEvents()).contains(.lens) && !g.state.has(Game.doorOpenFlag), "plates: then the lamp answers (the lens's chime), and the door is not yet open")
        g.simulate(seconds: TonePlatePuzzle.Timing.openDelay + 0.3)
        check(g.state.has(Game.doorOpenFlag), "plates: and then the door is open")
        step(g)
        check(g.interiorApplied && g.interactables.first { $0.id == "lh_door" }?.enabled == false, "plates: the inside is real, and the door is no longer there to try")
        // After it is open the plates only ring.
        _ = g.drainEvents(); strike(g, [2, 0])
        check(chimes(g.drainEvents()) == [.stone, .tide] && g.tonePlates.sequence.isEmpty, "plates: once the door is open the plates only ring")

        // A wrong strike resets softly, and the set can then be done.
        let w = readyGame()
        strike(w, [1])
        let wevs = w.drainEvents()
        check(chimes(wevs) == [.wind, .fail] && wevs.contains(.droneSour) && w.tonePlates.sequence.isEmpty, "plates: wind first is wrong: a soft fail, the tones sour, nothing is held")
        strike(w, [0])
        check(w.tonePlates.sequence.isEmpty, "plates: while the reset is under way a strike only rings")
        w.simulate(seconds: TonePlatePuzzle.Timing.wrongResetDelay + 0.2)
        strike(w, [0, 1, 2]); w.simulate(seconds: 5)
        check(w.state.has(Game.doorOpenFlag), "plates: after the reset the right order opens the door")
        // Out of order half way.
        let h = readyGame()
        strike(h, [0, 2]); h.simulate(seconds: 1.2)
        strike(h, [0, 1, 2]); h.simulate(seconds: 5)
        check(h.state.has(Game.doorOpenFlag), "plates: tide then stone is wrong half way; after the reset the order is whole again")

        // A partial set stays (no time limit), and completes later.
        let p = readyGame()
        strike(p, [0, 1]); p.simulate(seconds: 30)
        check(p.tonePlates.sequence == [0, 1] && !p.state.has(Game.doorOpenFlag), "plates: two plates struck and left for 30 s: still two, no door")
        strike(p, [2]); p.simulate(seconds: 5)
        check(p.state.has(Game.doorOpenFlag), "plates: the third, much later, completes it")
        // Repeating a plate is a wrong strike.
        let r = readyGame()
        strike(r, [0, 0])
        check(chimes(r.drainEvents()).contains(.fail), "plates: the same plate twice is wrong (a soft fail)")
        r.simulate(seconds: TonePlatePuzzle.Timing.wrongResetDelay + 0.2)
        check(r.tonePlates.sequence.isEmpty, "plates: and the set starts again")

        // The gate: the chord blooms, but the lamp does not answer until the gate is ready; the cue says what kind of thing is missing, and the plates reset.
        let n = twoWorlds()
        n.state.set("gw_end"); n.restorePage(1); n.restorePage(5)
        _ = n.drainEvents()
        strike(n, [0, 1, 2])
        let nevs = n.drainEvents()
        check(nevs.contains(.droneBloom), "plates: with too little read, the right order still blooms the chord")
        n.simulate(seconds: TonePlatePuzzle.Timing.answerDelay + 0.3)
        check(n.banner == GateState.cueTooLittle && !n.state.has(Game.doorOpenFlag), "plates: and the gate's quiet line is shown, the door stays shut (\(n.banner ?? "no banner"))")
        n.simulate(seconds: TonePlatePuzzle.Timing.unansweredResetDelay + 0.5)
        check(n.tonePlates.sequence.isEmpty && !n.state.has(Game.doorOpenFlag), "plates: unanswered, they reset")
        for k in [2, 3, 6, 7] { n.restorePage(k) }
        strike(n, [0, 1, 2]); n.simulate(seconds: 5)
        check(n.state.has(Game.doorOpenFlag), "plates: once the gate is ready the same order opens the door")
        let early = twoWorlds()                                                          // before the Glass Wood: no altar, nothing said
        strike(early, [0, 1, 2]); early.simulate(seconds: 6)
        check(!early.state.has(Game.doorOpenFlag) && early.banner == nil, "plates: before the Glass Wood the right order does nothing and says nothing")

        // The door note goes with the door when it opens.
        let nn = readyGame()
        step(nn)
        check(nn.scene.items.first { $0.name == DoorNote.itemName }?.hidden == false, "plates: the note is on the door while it is shut")
        strike(nn, [0, 1, 2]); nn.simulate(seconds: 5); step(nn)
        check(nn.scene.items.first { $0.name == DoorNote.itemName }?.hidden == true, "plates: and gone when the door is open")

        // Saved open, loaded open.
        let back = twoWorlds(); back.restore(g.makeSave()); step(back)
        check(back.state.has(Game.doorOpenFlag) && back.interiorApplied, "plates: a game saved with the door open loads with it open")

        // The plates are on the wall east of the door in the order of altitude, and a ray on each picks it (not the door).
        let lh = Layout.lighthouse
        let xs = (0..<3).map { TonePlates.world($0).x - lh.x }
        check(xs == xs.sorted() && xs[0] > 1.4 && xs[2] < 3.0, "plates: they are east of the door in order, tide nearest (\(xs))")
        let pg = readyGame(); step(pg)
        var picks: [String?] = []
        for k in 0..<3 {
            let c = TonePlates.world(k)
            for d: Float in [0.8, 1.5, 3.0] {
                let eye = SIMD3(c.x + 0.0, c.y, c.z + d)
                picks.append(Interaction.pick(origin: eye, dir: SIMD3(0, 0, -1), in: pg.interactables)?.id)
            }
        }
        check(picks == (0..<3).flatMap { k in [String?](repeating: names[k], count: 3) }, "plates: a ray at each plate picks that plate from 0.8, 1.5 and 3 m (\(picks))")
        check(TonePlates.names.allSatisfy { pg.scene.has($0) == false } && pg.scene.has("tone_plates"), "plates: they are one scene item, and need no hidden pieces")

        // The bot: walks to the plates, touches them in order with real clicks, and the door opens.
        let b = readyGame()
        let bot = PlaythroughBot(b)
        b.player = Player(position: SIMD3(lh.x + 2.1, lh.y + 0.9, lh.z + 9), yaw: .pi)
        b.player.position.y = b.scene.groundHeight(x: b.player.position.x, z: b.player.position.z)
        var ok = bot.walk(to: SIMD3(lh.x + 2.1, 0, lh.z + 5.4), within: 0.7, straight: true)
        for k in 0..<3 { ok = ok && bot.click(names[k]); bot.wait(0.4) }
        bot.wait(TonePlatePuzzle.Timing.answerDelay + TonePlatePuzzle.Timing.openDelay + 1)
        check(ok && b.state.has(Game.doorOpenFlag), "plates: a bot walks up, touches tide, wind, stone with real clicks, and the door opens")
        let bw = readyGame()
        let bbot = PlaythroughBot(bw)
        bw.player = Player(position: SIMD3(lh.x + 2.1, lh.y + 0.9, lh.z + 9), yaw: .pi)
        bw.player.position.y = bw.scene.groundHeight(x: bw.player.position.x, z: bw.player.position.z)
        _ = bbot.walk(to: SIMD3(lh.x + 2.1, 0, lh.z + 5.4), within: 0.7, straight: true)
        for k in [1, 0, 1, 2] { _ = bbot.click(names[k]); bbot.wait(0.4) }
        bbot.wait(6)
        check(!bw.state.has(Game.doorOpenFlag), "plates: a bot touching them wrongly (wind, tide, wind, stone) does not open the door")
    }
}
