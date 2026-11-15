import Foundation
import Metal
import simd

/// B7 (the reviewer's decisions on B6's findings, Q111): a machine that is not the player's answers with `GameEvent.dormant` (Q103), the orrery's collar says whether its notch has an arm (Q104), the mirror court's receivers
/// report a "nearly" value (Q102), and the prism ring's step is coarse enough to cross in six clicks (Q105). One file per phase keeps the new checks together.
extension SelfTestRunner {
    func runB7() {
        guard name == "all" || name == "b7" else { return }
        let fade = Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.8
        func arrive(_ route: PageAuthor) -> Game? {
            let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)])
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end"); g.state.set(Game.doorOpenFlag); g.simulate(seconds: 0.1)
            guard g.beginRoute(route) else { return nil }
            g.simulate(seconds: fade)
            _ = g.drainEvents()
            return g
        }
        func presses(_ g: Game, _ id: String) -> [GameEvent] { _ = g.drainEvents(); g.activate(id); return g.drainEvents() }
        func dormant(_ ev: [GameEvent]) -> Bool { ev.contains(.dormant) }

        // ---- Q103: on Oren's route Ilse's machines answer "not yours"; on Ilse's route Oren's do.
        if let o = arrive(.oren) {
            check(IlseRoute.bayNames.allSatisfy { dormant(presses(o, $0)) }, "dormant: on Oren's route every shelf bay answers with the dull tick")
            check(IlseRoute.pipeNames.allSatisfy { dormant(presses(o, $0)) } && dormant(presses(o, IlseRoute.keyName)), "dormant: on Oren's route the bell pipes and the rod answer with the dull tick")
            o.state.set(TideArchivePuzzle.forkFlag)
            check(!dormant(presses(o, TideArchivePuzzle.sluiceNames[0])), "dormant: on Oren's route the wheel (the fork's touch is his too, once the fork is found) is not dormant")
            let c = presses(o, OrenRoute.collarName)
            check(!dormant(c) && c.contains(.collar(armHere: true)), "dormant: Oren's own collar is not dormant, and its first notch (an arm to catch) says armHere (\(c))")
            let c2 = presses(o, OrenRoute.collarName), c3 = presses(o, OrenRoute.collarName), c4 = presses(o, OrenRoute.collarName), c5 = presses(o, OrenRoute.collarName)
            check(c2.contains(.collar(armHere: true)) && c3.contains(.collar(armHere: true)) && c4.contains(.collar(armHere: false)) && c5.contains(.collar(armHere: false)), "dormant: the collar's notches 2 and 3 have an arm, 4 and 5 do not")
            check(o.orenRoute?.notch == 5 && !o.collarNotchHasArm && presses(o, OrenRoute.collarName).contains(.collar(armHere: false)) && !o.collarNotchHasArm, "dormant: Game.collarNotchHasArm follows the notch (off the arms: false)")
            while o.orenRoute?.notch != 1 { _ = presses(o, OrenRoute.collarName) }
            check(o.collarNotchHasArm, "dormant: Game.collarNotchHasArm is true on a notch with an arm")
        } else { check(false, "dormant: Oren's route could not begin") }
        if let i = arrive(.ilse) {
            let c = presses(i, OrenRoute.collarName)
            check(dormant(c) && !c.contains { if case .collar = $0 { return true } else { return false } } && i.orenRoute?.notch == 0 && !i.collarNotchHasArm, "dormant: on Ilse's route the orrery's collar answers with the dull tick, does not turn and says no arm (\(c))")
            i.state.set(TideArchivePuzzle.forkFlag); i.state.set(TideArchivePuzzle.lensFlag)
            check(dormant(presses(i, TideArchivePuzzle.sluiceNames[0])) && dormant(presses(i, TideArchivePuzzle.ringName)), "dormant: on Ilse's route the sluice wheel's touch and the prism ring (Oren's way) answer with the dull tick")
            check(!dormant(presses(i, IlseRoute.bayNames[0])), "dormant: Ilse's own bay is not dormant")
        } else { check(false, "dormant: Ilse's route could not begin") }

        // ---- Q102: the court's "nearly" value. Pure rule: it reads the same trace as the solved rule and never changes it.
        var solving = 0, anyNear = 0, oneNear = 0, bad = 0, total = 0
        for m in 0..<64 { for p in 0..<27 {
            let mirrors = [m & 3, (m >> 2) & 3, (m >> 4) & 3], panes = [p % 3, (p / 3) % 3, (p / 9) % 3]
            let t = MirrorCourt.trace(mirrors: mirrors, panes: panes), near = MirrorCourt.nearness(mirrors: mirrors, panes: panes)
            total += 1; if t.solved { solving += 1 }
            if near.contains(where: { $0 > 0 }) { anyNear += 1 }
            if near.contains(MirrorCourt.nearOne) { oneNear += 1 }
            for k in 0..<3 where near[k] > 0 && t.lit(k) { bad += 1 }          // a lit receiver reads 0
            for k in 0..<3 where near[k] == MirrorCourt.nearOne {              // 1 means a single click lights it
                var ok = false
                for i in 0..<3 { var mm = mirrors; mm[i] = (mm[i] + 1) % 4; ok = ok || MirrorCourt.trace(mirrors: mm, panes: panes).lit(k) }
                for i in 0..<3 { var pp = panes; pp[i] = (pp[i] + 1) % 3; ok = ok || MirrorCourt.trace(mirrors: mirrors, panes: pp).lit(k) }
                if !ok { bad += 1 }
            }
        } }
        check(total == 1728 && solving == 1 && bad == 0, "nearly: over the 1728 arrangements exactly one still solves (the rule is unchanged), a lit receiver reads 0 and a 1 is always one click from lit (\(solving) solving, \(bad) bad)")
        // How often the faint glow can show at all: only a receiver nothing has reached (the ones a wrong colour reached already flutter).
        var darkNear = 0
        for m in 0..<64 { for p in 0..<27 {
            let mirrors = [m & 3, (m >> 2) & 3, (m >> 4) & 3], panes = [p % 3, (p / 3) % 3, (p / 9) % 3]
            let t = MirrorCourt.trace(mirrors: mirrors, panes: panes), near = MirrorCourt.nearness(mirrors: mirrors, panes: panes)
            if (0..<3).contains(where: { near[$0] > 0 && t.arrivals[$0].isEmpty }) { darkNear += 1 }
        } }
        print("nearly: \(darkNear) of 1728 arrangements have a DARK receiver that is nearly reached (the glow can show)")
        check(MirrorCourt.nearness(mirrors: MirrorCourt.solutionMirrors, panes: MirrorCourt.solutionPanes) == [0, 0, 0], "nearly: the solved court reads nothing (all three are lit)")
        check(MirrorCourt.nearness(mirrors: MirrorCourt.initialMirrors, panes: MirrorCourt.initialPanes) == [0, 0, MirrorCourt.nearOne] && oneNear > 500, "nearly: the court's own start has its third receiver one click from lit (and many arrangements read 1: \(oneNear))")
        let nearShare = Double(anyNear) / Double(total)
        check(nearShare > 0.15 && nearShare < 0.95, "nearly: a slope, not a flood: \(Int(nearShare * 100)) % of the arrangements show some receiver nearly reached (\(Int(Double(oneNear) / Double(total) * 100)) % within one click)")
        if let g = arrive(.ilse) {
            check(g.receiverNear == MirrorCourt.nearness(mirrors: MirrorCourt.initialMirrors, panes: MirrorCourt.initialPanes), "nearly: the game's receiverNear is the rule's value for the court as it stands (\(g.receiverNear))")
            let before = g.receiverNear
            _ = before; g.activate("gw_mirror_0")
            check(g.receiverNear == MirrorCourt.nearness(mirrors: g.glass!.mirrors, panes: g.glass!.panes) && g.glass!.receiversLit.filter { $0 }.count <= 3, "nearly: a click moves it (\(before) -> \(g.receiverNear)); it is read after the click")
        }

        // ---- Q105 / Q70: the prism ring's step. Five clicks in all from where it starts, three marks at least a step apart that no tolerance can confuse, none at the start.
        let T = TideArchivePuzzle.self
        let clicks = Int(((abs(T.beamTargets[0] - T.initialRing) + abs(T.beamTargets[1] - T.beamTargets[0]) + abs(T.beamTargets[2] - T.beamTargets[1])) / T.ringStep).rounded())
        check(clicks <= 6 && clicks == 5, "ringstep: the three marks take \(clicks) clicks in all from where the ring starts (6 or fewer)")
        let gaps = [abs(T.beamTargets[1] - T.beamTargets[0]), abs(T.beamTargets[2] - T.beamTargets[1]), abs(T.beamTargets[2] - T.beamTargets[0])]
        check(gaps.allSatisfy { $0 >= T.ringStep - 1e-4 && $0 > 6 * T.beamTolerance } && T.beamTargets.allSatisfy { abs($0 - T.initialRing) > T.beamTolerance }, "ringstep: the marks are at least one step (and six tolerances) apart and none is where the ring starts")
        check(abs(T.ringStep * 180 / .pi - 45) < 1e-3 && T.beamTargets.allSatisfy { abs(($0 / T.ringStep).rounded() - $0 / T.ringStep) < 1e-4 }, "ringstep: 45 degrees, every mark a whole number of steps from the start")

        // ---- Q102, measured: a climb that watches only the three crystals (what a person looking at the court sees), one dial at a time, from the court's own start and from 40 other arrangements; with and without the faint glow drawn.
        func climb(near: Bool, mirrors m0: [Int], panes p0: [Int]) -> (solved: Bool, clicks: Int) {
            let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            GlassWoodLogic.nearGlow = near; defer { GlassWoodLogic.nearGlow = true }
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end"); g.simulate(seconds: 0.2)
            guard let gw = g.glass else { return (false, 0) }
            var clicks = 0
            func click(_ id: String) { g.activate(id); clicks += 1 }
            for k in 0..<3 { while gw.mirrors[k] != m0[k] { click("gw_mirror_\(k)") }; while gw.panes[k] != p0[k] { click("gw_pane_\(k)") } }
            clicks = 0
            func seen() -> Float {                                               // the crystals' glow, averaged over a flutter's period so the shimmer is not read as a change
                var sum: Float = 0, n: Float = 0
                for _ in 0..<12 { g.simulate(seconds: 0.06); for k in 0..<3 { sum += g.scenes[.glassWood]!.items.first { $0.name == ReceiverGlow.name(k) }?.uniforms.emissive.w ?? 0 }; n += 1 }
                return sum / n
            }
            let dials: [(String, Int)] = (0..<3).flatMap { [("gw_mirror_\($0)", 4), ("gw_pane_\($0)", 3)] }
            for _ in 0..<6 {
                var improved = false
                for (id, n) in dials {
                    if gw.mirrorsSolved { return (true, clicks) }
                    var best = seen(), bestAt = 0
                    for s in 1..<n { click(id); let v = seen(); if v > best + 0.05 { best = v; bestAt = s } }
                    click(id)                                                    // the cycle closes (n clicks in all)
                    for _ in 0..<bestAt { click(id) }
                    if bestAt > 0 { improved = true }
                }
                if gw.mirrorsSolved { return (true, clicks) }
                if !improved { break }
            }
            return (gw.mirrorsSolved, clicks)
        }
        var starts: [([Int], [Int])] = [(MirrorCourt.initialMirrors, MirrorCourt.initialPanes)]
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func next(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(n)) }
        while starts.count < 41 { let m = (0..<3).map { _ in next(4) }, p = (0..<3).map { _ in next(3) }; if !(m == MirrorCourt.solutionMirrors && p == MirrorCourt.solutionPanes) { starts.append((m, p)) } }
        var summary: [Bool: [(Bool, Int)]] = [:]
        for near in [false, true] { summary[near] = starts.map { climb(near: near, mirrors: $0.0, panes: $0.1) } }
        func line(_ near: Bool) -> String {
            let r = summary[near]!, ok = r.filter { $0.0 }.map { $0.1 }.sorted()
            return "near glow \(near ? "on " : "off"): the climb solves \(r.filter { $0.0 }.count) of \(r.count) starts; clicks (solved ones) median \(ok.isEmpty ? 0 : ok[ok.count / 2]), most \(ok.last ?? 0); from the court's own start: \(r[0].0 ? "solved" : "not solved") in \(r[0].1) clicks"
        }
        print("mirror-court climb: \(line(false))"); print("mirror-court climb: \(line(true))")
        let offSolved = summary[false]!.filter { $0.0 }.count, onSolved = summary[true]!.filter { $0.0 }.count
        check(offSolved >= 36 && onSolved >= offSolved, "nearly (measured): a climb that watches only the crystals solves the court from \(offSolved) of 41 starts with no new glow and \(onSolved) with the faint glow: the plateau was not real (\(line(false)) | \(line(true)))")
    }
}
