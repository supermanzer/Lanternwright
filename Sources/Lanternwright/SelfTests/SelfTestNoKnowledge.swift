import Foundation
import Metal
import simd

/// B6 (P02.7 groundwork): the no-knowledge bot (`NoKnowledge/BlindPlayer.swift`, which sees only `Perception`) plays a fresh game on each route, from the spawn at the end of the dock to the Archive's drained gallery, with no
/// teleport, no constant read from puzzle code and no page read. This file is the HARNESS and the REFEREE: it starts the game, answers the bot's stalls with a "knowing helper" where one exists (and counts every help),
/// judges each puzzle by the game's own flag (the `PuzzleGraph`'s `sets`), and writes `docs/plans/P02-acceptance-report.md`.
///
/// Run: `--selftest nokbot` (this suite only); it is in `--selftest` as well. `NOKBOT_REPORT=docs/plans/P02-acceptance-report.md .build/release/Lanternwright --selftest nokbot` rewrites the report.
struct NokRun {
    var route: PageAuthor
    var solved = false
    var clock: Float = 0
    var presses = 0
    var records: [BlindPlayer.Record] = []
    var stalls: [BlindPlayer.Stall] = []
    var helps: [(clock: Float, what: String, node: String?)] = []
    var flagAt: [String: Float] = [:]
    var graph: PuzzleGraph
    var gaveUp: String?
    var endedIn = ""
}

extension SelfTestRunner {
    /// The knowing helper for the spiral stair: it is on no trail, so a bot that follows trails cannot climb it (a player just walks up). The same walk as the whole-game bot's.
    func climbStair(_ bot: PlaythroughBot) -> Bool {
        typealias I = LighthouseInterior
        let lh = Layout.lighthouse
        func pt(_ a: Float, _ r: Float) -> (x: Float, z: Float) { (lh.x + cos(a) * r, lh.z + sin(a) * r) }
        func band(_ phi: Float) -> Float { let h = I.stairY(phi); return (I.stairInner(h) + I.innerR(h)) / 2 }
        var toDoor = true
        if simd_length(SIMD2(bot.feet.x - lh.x, bot.feet.z - lh.z)) > 6 {                       // from outside: round to the door; from inside (the bot is already on the ground floor) straight to the stair
            toDoor = bot.walk(to: SIMD3(lh.x - 11, lh.y, lh.z), within: 3.0, timeout: 240)
            toDoor = toDoor && bot.walk(to: SIMD3(lh.x - 10, lh.y, lh.z + 9), within: 1.5, timeout: 60, straight: true)
            toDoor = toDoor && bot.walk(to: Layout.Navigation.signalDoorPoint, within: 2.0, timeout: 60, straight: true)
        }
        var climbed = toDoor && bot.walk(to: SIMD3(lh.x, 0, lh.z + 5), within: 0.5, straight: true) && bot.walk(to: SIMD3(lh.x, 0, lh.z + 3.0), within: 0.5, straight: true) && bot.walk(to: SIMD3(lh.x - 0.9, 0, lh.z + 2.3), within: 0.5, straight: true)
        var phi = I.startAngle
        while climbed && phi < I.endAngle + 0.5 { let q = pt(phi, band(min(phi, I.endAngle))); climbed = bot.walk(to: SIMD3(q.x, 0, q.z), within: 0.55, straight: true); phi += 0.3 }
        let top = pt(I.endAngle + 1.2, 1.2)
        return climbed && bot.walk(to: SIMD3(top.x, 0, top.z), within: 0.5, straight: true)
    }

    /// One fresh game, one route, the blind player; the referee's notes.
    func playNoKnowledge(_ route: PageAuthor) -> NokRun {
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)])
        let eyes = Perception(g), me = BlindPlayer(eyes)
        var run = NokRun(route: route, graph: PuzzleGraph.today(game: g))
        me.avoid = route == .ilse ? ["oren\u{2019}s way"] : ["ilse\u{2019}s way"]                  // the choice at the fork is the player's own: one sibling's way, named on the thing itself
        let stairLow = { eyes.feet.y < Layout.lighthouse.y + LighthouseInterior.lensFloorY - 1 }
        func help(_ what: String, node: String? = nil) { run.helps.append((eyes.clock, what, node)) }
        me.onRecord = { _ in
            for n in run.graph.puzzles { if let f = n.sets, g.state.has(f), run.flagAt[f] == nil { run.flagAt[f] = eyes.clock } }
        }
        me.onStall = { st, handles in
            // The knowing helpers: each does what the whole-game bots do for that machine, from wherever the blind player left it.
            if handles.isEmpty, g.state.has(Game.doorOpenFlag), g.chosenPath == nil, g.world == .varrow, stairLow() {
                help("climbs the spiral stair (on no trail)"); return self.climbStair(eyes.harnessHands)
            }
            if handles.contains("lh_lens_touch") {                                                       // the stair, then the touch itself (the exit is the bot's own choice)
                let hands = eyes.harnessHands
                if stairLow() { help("climbs the spiral stair (on no trail)"); _ = self.climbStair(hands) }
                _ = hands.walk(to: SIMD3(Layout.lighthouse.x - 1.5, 0, Layout.lighthouse.z - 0.8), within: 0.5, timeout: 20, straight: true)
                _ = hands.click("lh_lens_touch"); hands.wait(0.5)
                return g.isTraveling || g.chosenPath != nil
            }
            if handles.contains("lens_ring") {                                                           // the stair, then the ring's touches that put it on the receiver, held until the doorway opens
                let hands = eyes.harnessHands
                if stairLow() { help("climbs the spiral stair (on no trail)"); _ = self.climbStair(hands) }
                help("turns Oren's lens ring onto its receiver", node: "lens-ring")
                _ = hands.walk(to: SIMD3(Layout.lighthouse.x - 0.2, 0, Layout.lighthouse.z - 1.45), within: 0.3, timeout: 30, straight: true)
                let cycle = Int((2 * Float.pi / LensPortalProps.ringStep).rounded())
                let n = ((Int(((LensPortalProps.receiverAngle - g.lensPortal.ringAngle) / LensPortalProps.ringStep).rounded()) % cycle) + cycle) % cycle
                for _ in 0..<n { _ = hands.click("lens_ring"); hands.wait(0.3) }
                hands.wait(LensPortalProps.holdSeconds + 0.6)
                return g.state.has(Game.portalOpenFlag)
            }
            if route == .oren, handles.contains("ti_orrery_collar") {                                                    // the collar one notch before each arm's, the last turn as its bead brightens
                help("catches the three orrery arms (notch and moment known)", node: "archive-orrery")
                return self.orenPrerequisites(g, eyes.harnessHands)
            }
            if route == .oren, handles.contains("ti_prism_ring") {                                                       // the ring at each gate's mark, by the arrow keys, in the gate's tide
                help("turns the prism ring onto each gate's mark (marks and tides known)", node: "archive-gates-beam")
                var ok = true
                for k in 0..<3 where (g.tideArchive?.opened ?? 3) <= k { ok = self.orenRing(k, g, eyes.harnessHands) && ok }
                return ok
            }
            if handles.contains("gw_mirror_0") || handles.contains("gw_pane_0") {                       // the court's reference solution from wherever the player left the glass
                help("sets the mirrors and panes of the court (solution known)", node: "mirror-court")
                let hands = eyes.harnessHands
                for k in 0..<3 { let n = (MirrorCourt.solutionMirrors[k] - (g.glass?.mirrors ?? MirrorCourt.initialMirrors)[k] + 4) % 4; for _ in 0..<n { _ = hands.walk(to: GlassPuzzleProps.mirrorPosition(k), within: 3.0, timeout: 60); _ = hands.click("gw_mirror_\(k)"); hands.wait(0.5) } }
                for k in 0..<3 { let n = (MirrorCourt.solutionPanes[k] - (g.glass?.panes ?? MirrorCourt.initialPanes)[k] + 3) % 3; for _ in 0..<n { _ = hands.walk(to: GlassPuzzleProps.panePosition(k), within: 3.0, timeout: 60); _ = hands.click("gw_pane_\(k)"); hands.wait(0.5) } }
                hands.wait(3)
                return true
            }
            return false
        }
        me.play(until: { g.routeSolved }, limit: 25000)
        run.solved = g.routeSolved; run.clock = eyes.clock; run.presses = me.presses
        run.records = me.records; run.stalls = me.stalls; run.gaveUp = me.gaveUp
        run.endedIn = "\(g.world)"
        for n in run.graph.puzzles { if let f = n.sets, g.state.has(f), run.flagAt[f] == nil { run.flagAt[f] = eyes.clock } }
        return run
    }

    /// The puzzles this route meets, in the order the bot solved them (by when the game's own flag was first seen), then those it never solved.
    func nokNodes(_ run: NokRun) -> [PuzzleNode] {
        run.graph.puzzles.filter { $0.kind != .transit && $0.sets != nil && ($0.route == nil || $0.route == run.route) && !($0.optional && run.flagAt[$0.sets ?? ""] == nil) }
            .sorted { (run.flagAt[$0.sets ?? ""] ?? .infinity) < (run.flagAt[$1.sets ?? ""] ?? .infinity) }
    }
    /// What the blind player did at one puzzle: the presses and seconds its machines took, and whether anyone helped.
    struct NokRow { var node: PuzzleNode; var solvedAt: Float?; var presses: Int; var seconds: Float; var visits: Int; var helped: Bool; var notes: [String] }
    func nokRow(_ run: NokRun, _ n: PuzzleNode) -> NokRow {
        let mine = run.records.filter { r in r.handles.contains { n.machineIDs.contains($0) } }
        let helped = mine.contains { $0.helped } || run.helps.contains { $0.node == n.id }
        return NokRow(node: n, solvedAt: n.sets.flatMap { run.flagAt[$0] }, presses: mine.reduce(0) { $0 + $1.manipulations }, seconds: mine.reduce(0) { $0 + $1.seconds }, visits: mine.count, helped: helped, notes: Array(Set(mine.map { $0.note }.filter { !$0.isEmpty })).sorted())
    }

    func nokReport(_ runs: [NokRun]) -> String {
        func t(_ s: Float) -> String { s.isFinite ? "\(Int(s / 60)) min" : "never" }
        var md = """
        <!-- nokbot:begin -->
        ### Generated by `NOKBOT_REPORT=docs/plans/P02-acceptance-report.md .build/release/Lanternwright --selftest nokbot` (regenerate after any change to a puzzle; the text outside the markers is the builder's)

        ## What the bot is, and is not
        A scripted player that holds only a **`Perception`** (`SelfTests/NoKnowledge/Perception.swift`) and never the game: what is in sight (a thing, the words the crosshair shows on it, whether the crosshair shows it done, how brightly the place around it glows), the guide light and the lamps, the trails (where the lanterns' path goes), what it hears (each sound reduced to a tone by identity, a sour note, a held tone, a full chord, a rumble), and its hands (walk, face, click, arrow keys, wait). `SelfTests/NoKnowledge/BlindPlayer.swift` is the brain; a selftest reads its text and fails if it names any puzzle, layout constant, flag or answer (`nokbot: the brain's file names no puzzle ...`).

        It plays from a **fresh game at the spawn** at the end of the dock, with no teleport, through Varrow, the Glass Wood, the return, the lighthouse and the Archive, until the gallery drains (`routeSolved`). It works what it finds with three generic hands:
        - **a row** of presses (strike, ring, touch): try each, keep what rings true and stays lit, learn from a sour note (everything resets, so it replays what held) and rule out what did nothing;
        - **a dial** (turn, change): for each element click round its cycle watching how bright the place gets, settle on the brightest, go round again; and for a single dial that nothing answered, watch it and press as it brightens;
        - **hold and wait** (the fork at a pipe): press, then wait a tide for the thing to say it is done; and **wait and listen** at the guide light where nothing can be pressed (the tide marks).

        It reads **no page text, no diagram and no beam rhythm** (a page is opened and shut). It chooses its sibling at the fork as a player would (one exit's words name Ilse, the other's Oren).

        **A step** is one press, click or arrow press (a manipulation); a walk or a wait is not. **A stall** is a stretch of 150 s of play in which nothing new comes into sight, nothing new sounds and nothing new lights, or a machine worked for a while with no answer, or a machine in sight that no trail leads to. At a stall the harness may **help**: the same knowing walk the whole-game bots use, run from wherever the bot stood, and counted below ("helped"). A puzzle marked *helped* was **not** solved blind; the helps are the findings.

        **Not modelled:** a player's patience (the bot never gives up on its own account), a player's eyes (a thing is "in sight" if it is within 250 m and in front or within 5 m: nothing hides it), the page text (the bot cannot read, so every puzzle that is solved here is solved without text, and a puzzle that is helped may have a page that would help a person), and sound as a person hears it (a tone is an identity and a sour note is a sour note).

        """
        for run in runs {
            let name = run.route == .ilse ? "Ilse" : "Oren"
            md += "\n## \(name)'s route: \(run.solved ? "the gallery drains" : "NOT finished (ended in \(run.endedIn), gave up: \(run.gaveUp ?? "-"))") after \(t(run.clock)) of play, \(run.presses) manipulations, \(run.stalls.count) stalls, \(run.helps.count) helps\n\n"
            md += "| # | puzzle | verb / channel | designer's least | blind presses | blind time at it | solved at | how |\n|---|---|---|---|---|---|---|---|\n"
            var order = 0
            for n in nokNodes(run) {
                let row = nokRow(run, n)
                order += 1
                let how: String
                if row.solvedAt == nil { how = "**never solved**" }
                else if row.helped { how = "**helped** (the bot stalled: \(row.notes.joined(separator: "; ").isEmpty ? "see stalls" : row.notes.joined(separator: "; ")))" }
                else if n.machineIDs.isEmpty { how = "by waiting and listening" }
                else { how = "blind, by trial and the feedback" }
                md += "| \(order) | \(n.id) | \(n.verb) / \(n.channel) | \(n.manipulations == 0 ? "-" : "\(n.manipulations)") | \(row.presses) | \(Int(row.seconds)) s | \(row.solvedAt.map(t) ?? "-") | \(how) |\n"
            }
            md += "\n**Helps** (what the knowing helper did, and when):\n\n"
            for h in run.helps { md += "- \(t(h.clock)): \(h.what)\n" }
            if run.helps.isEmpty { md += "- none\n" }
            md += "\n**Stall points** (each is 150 s with nothing new, or a machine worked without an answer; `at` is where the bot stood):\n\n| at (min) | where | what it was at | why |\n|---|---|---|---|\n"
            for s in run.stalls {
                let what = s.handles.isEmpty ? "(nothing in sight)" : s.handles.prefix(3).joined(separator: ", ") + (s.handles.count > 3 ? ", ..." : "")
                md += "| \(Int(s.clock / 60)) | (\(Int(s.at.x)), \(Int(s.at.z))) | \(what) | \(s.reason) |\n"
            }
            md += "\n**Every machine worked, in order** (a record is one visit; a row of presses is one record):\n\n| at (s) | what the player read | how | presses | time (s) | outcome |\n|---|---|---|---|---|---|\n"
            for r in run.records where !r.prompt.lowercased().hasPrefix("read") {
                md += "| \(Int(r.started)) | \(r.prompt.replacingOccurrences(of: "|", with: "/")) (\(r.handles.count)) | \(r.hand) | \(r.manipulations) | \(Int(r.seconds)) | \(r.outcome.rawValue)\(r.helped ? " (helped)" : "")\(r.note.isEmpty ? "" : ": " + r.note) |\n"
            }
        }
        md += "\n<!-- nokbot:end -->\n"
        return md
    }

    /// Replace the generated block between the markers of an existing report (the builder's reading around it stays); a file without the markers gets the block appended.
    func nokWrite(_ block: String, to path: String) throws {
        let begin = "<!-- nokbot:begin -->", end = "<!-- nokbot:end -->"
        if let old = try? String(contentsOfFile: path, encoding: .utf8), let a = old.range(of: begin), let b = old.range(of: end) {
            try (String(old[..<a.lowerBound]) + block.trimmingCharacters(in: .whitespacesAndNewlines) + String(old[b.upperBound...])).write(toFile: path, atomically: true, encoding: .utf8)
        } else { try block.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    /// The words the blind player's brain must not use: the game's puzzles, layouts, tables, flags' prefixes and the handles that reach past `Perception`. Comments (whole-line or trailing) are not code.
    static func brainForbidden(in source: String) -> [String] {
        let code = source.split(separator: "\n").map { line -> String in
            let l = String(line); if let r = l.range(of: "//") { return String(l[..<r.lowerBound]) }; return l
        }.joined(separator: "\n")
        let forbidden = ["LighthousePuzzle", "MirrorCourt", "GlassWoodLogic", "TonePlatePuzzle", "IlseRoute", "OrenRoute", "TideArchivePuzzle", "ArchiveLayout", "ShelfBays", "Tide.", "Orrery", "Layout", "state.set", "restorePage", "setClaim", "simulate", "Game", "harnessHands", "PlaythroughBot", "GameEvent", "ChimeKind", "TideSpots", "LensPortalProps", "TonePlates", "GlassPuzzleProps", "LighthouseInterior", "TideMarks", "IlseTones", "ToneTable", "PuzzleGraph", "Mirror(", "stone_", "gw_", "ti_", "plate_", "lh_", "lens_ring", "page_", ".state", "StoryPages", "Notebook"]
        return forbidden.filter { code.contains($0) }
    }

    func runNoKnowledge() {
        guard name == "all" || name == "nokbot" else { return }
        GlassWoodLogic.nearStandIn = ProcessInfo.processInfo.environment["NOKBOT_NEAR"] == "1"          // B7 (Q102): measure the court with the receivers' "nearly" glow drawn (off in the game until A's `near:` lands)
        defer { GlassWoodLogic.nearStandIn = false }
        // ---- The brain's file may name nothing of the game's: not a puzzle, not a layout constant, not a flag, not an answer. (A denylist: a determined cheat can get past it; it catches the honest slip, and the brain holds
        // only a `Perception` in any case.)
        let brainPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("NoKnowledge/BlindPlayer.swift").path
        if let brain = try? String(contentsOfFile: brainPath, encoding: .utf8) {
            let hits = Self.brainForbidden(in: brain)
            check(hits.isEmpty, "nokbot: the brain's file names no puzzle, layout constant, flag or answer (found: \(hits))")
        } else { check(false, "nokbot: could not read the brain's file at \(brainPath)") }
        // The check itself can fail: the REAL filter, run on lines of code that cheat, finds them; on a comment it does not.
        check(!Self.brainForbidden(in: "let x = 1\n    eyes.click(handle: \"stone_tide\")\n").isEmpty && !Self.brainForbidden(in: "    let g = Game.shared\n").isEmpty && !Self.brainForbidden(in: "    let t = TideSpots.gate(0) // fine\n").isEmpty, "nokbot mutation: the real forbidden-name filter finds a flag, `Game.` and a spots table in lines of code")
        check(Self.brainForbidden(in: "    /// the stones: stone_tide, Layout.lighthouse\n    let ok = 1 // gw_ is a flag prefix\n").isEmpty, "nokbot: the filter ignores comments (a doc line and a trailing note)")

        var runs: [NokRun] = []
        for route in [PageAuthor.ilse, .oren] { runs.append(playNoKnowledge(route)) }
        for run in runs {
            let who = run.route == .ilse ? "Ilse" : "Oren"
            check(run.solved, "nokbot: \(who): from a fresh game, with no teleport, the blind player reaches the drained gallery (\(Int(run.clock / 60)) min of play, \(run.presses) manipulations, \(run.stalls.count) stalls, \(run.helps.count) helps; ended \(run.endedIn))")
        }
        nokMetrics(runs)
        if let path = ProcessInfo.processInfo.environment["NOKBOT_REPORT"] {
            do { try nokWrite(nokReport(runs), to: path); print("nokbot: report written to \(path)") } catch { check(false, "nokbot: could not write the report: \(error)") }
        }
    }

    /// B6 (3): per-route metrics, pinned. What the blind player solved without help, what needed help, how many presses the blind solves took, and what the graph says about choice and feedback. A change in any of them
    /// is a change in how the game plays for someone who knows nothing, so it fails here until the pin is moved on purpose (and `P02-acceptance-report.md` regenerated).
    static let pinnedBlindSolved: [PageAuthor: [String]] = [
        .ilse: ["altar", "archive-catalogue", "archive-marks", "archive-pipes", "chime-pool", "door-plates", "stones"],
        .oren: ["altar", "archive-gates-beam", "archive-marks", "chime-pool", "door-plates", "stones"],
    ]
    static let pinnedHelped: [PageAuthor: [String]] = [
        .ilse: ["mirror-court"],
        .oren: ["archive-orrery", "lens-ring", "mirror-court"],
    ]
    /// The most presses a puzzle the blind player solved may have taken (its designed least is 3 to 6): a row of three to five things found by trial costs a few dozen, not a few hundred.
    static let blindPressBudget = 40
    /// A timed puzzle watched and pressed as it brightens costs more presses (each arm's window comes round once a tide): the orrery's budget.
    static let blindPressBudgetTimed = 90

    func nokMetrics(_ runs: [NokRun]) {
        for run in runs {
            let who = run.route == .ilse ? "Ilse" : "Oren"
            let rows = nokNodes(run).filter { $0.sets != nil }.map { nokRow(run, $0) }
            let blind = rows.filter { $0.solvedAt != nil && !$0.helped }.map { $0.node.id }.sorted()
            let helped = rows.filter { $0.helped }.map { $0.node.id }.sorted()
            let never = rows.filter { $0.solvedAt == nil }.map { $0.node.id }
            check(blind == Self.pinnedBlindSolved[run.route]!, "nokbot metrics: \(who): the puzzles solved blind are exactly the pinned list (found \(blind); pinned \(Self.pinnedBlindSolved[run.route]!))")
            check(helped == Self.pinnedHelped[run.route]!, "nokbot metrics: \(who): the puzzles that needed a knowing helper are exactly the pinned list (found \(helped); pinned \(Self.pinnedHelped[run.route]!))")
            check(never.isEmpty, "nokbot metrics: \(who): every puzzle was solved, blind or helped (never solved: \(never))")
            let heavy = rows.filter { !$0.helped && $0.solvedAt != nil && $0.presses > ($0.node.id == "archive-orrery" ? Self.blindPressBudgetTimed : Self.blindPressBudget) }.map { "\($0.node.id) \($0.presses)" }
            check(heavy.isEmpty, "nokbot metrics: \(who): each puzzle solved blind took \(Self.blindPressBudget) presses or fewer (the timed orrery \(Self.blindPressBudgetTimed)) (over: \(heavy); most: \(rows.filter { !$0.helped }.map { $0.presses }.max() ?? 0))")
            check(run.stalls.count <= 30, "nokbot metrics: \(who): the stalls stay under thirty (\(run.stalls.count))")
        }
        // The graph's own measures per route: two puzzles open at once off the first world, and a continuous feedback named for every puzzle.
        let graph = runs[0].graph
        for r in [PageAuthor.ilse, .oren] {
            let steps = PuzzleRules.timeline(graph, route: r)
            let second = steps.first { $0.world != steps[0].world }
            check((second?.open.count ?? 0) >= 2, "nokbot metrics: \(r == .ilse ? "Ilse" : "Oren"): off the first world at least two puzzles are open at once (\(second?.open ?? []))")
        }
        let noProgress = PuzzleRules.feedback(graph).filter { $0.subject.hasSuffix(" progress") }
        let counted = graph.puzzles.filter { $0.kind == .puzzle && !$0.optional }
        check(noProgress.isEmpty && counted.allSatisfy { n in n.feedback.contains { $0.kind == .progress } }, "nokbot metrics: every puzzle names a continuous (progress) feedback (\(counted.count) puzzles; missing: \(noProgress.map(\.subject)))")
        let off = counted.filter { !(3...6).contains($0.manipulations) }.map { "\($0.id) \($0.manipulations)" }
        check(off.isEmpty, "nokbot metrics: every puzzle's designed least is 3 to 6 manipulations (the prism ring is 5 since B7, Q105; off: \(off))")
    }
}
