import Foundation
import simd

/// P02.0: the puzzle structure as DATA (P02 section 2.3). Today the structure lives in flags spread over `Game`, `Gate`, `LighthousePuzzle`, `GlassWoodLogic`, `TonePlatePuzzle`,
/// `LensPortalPuzzle`, `TideArchivePuzzle` and the player-path doc; this file lifts it into one table that tests and the reviewer can query without playing the game.
///
/// Two halves, kept apart on purpose:
///  1. **The rules** (`PuzzleRules`): pure functions over a `PuzzleGraph` value. Each takes a graph and returns the rule breaks it finds. They are proved on synthetic graphs (`SelfTestPuzzleGraph`):
///     one fixture that breaks exactly that rule must be flagged, a clean fixture must pass every rule. They know nothing about Lanternwright.
///  2. **Today's graph** (`PuzzleGraph.today(game:)`): built FROM the live game, not retyped. Answers come from the puzzles' own constants (`LighthousePuzzle.order`, `TonePlatePuzzle.order`,
///     `MirrorCourt.solutionPanes`, `GlassWoodLogic.chimeSolution` through `ToneTable`, `TideArchivePuzzle.sluiceFlags`); positions are the centres of the game's own interactable boxes (so the graph
///     moves when the boxes do: typed coordinates were what broke F09.1); the manipulation counts are computed (a search over the mirror court's 1728 settings, the ring's steps); which pages
///     state the order is read from the page text. What stays declared by the builder (and is said so in the report) is the structure the code cannot say about itself: which flag a puzzle
///     needs and sets, which pages and memories are its clues, and what feedback each machine gives.
///
/// The selftest does NOT require today's graph to be clean: P02.0 reports and fixes nothing. It pins today's list of rule breaks, so a new break fails and so does a break that disappears
/// unnoticed (a fix must update the pin on purpose). That is how "fail on a rule break" and "commit only on 0 FAIL" are both true.

/// How the player learns an answer or what the machine's information is: P02 section 2.1, rule 1. `touch` is a story beat with no datum.
enum PuzzleChannel: String, CaseIterable { case see, hear, count, watch, aim, touch }

enum FeedbackSense: String { case sight, sound }
/// `binary`: only says solved or not. `live`: moves with the player's input but does not say how close the answer is. `progress`: says how much of the answer is right (lights that accumulate, a held
/// tone that sours, a beam that visibly reaches the receiver). P02 section 2.1, rule 4: a machine answers on two senses within a second with something that is not binary.
enum FeedbackKind: String { case binary, live, progress }
struct PuzzleFeedback: Equatable {
    var sense: FeedbackSense
    var kind: FeedbackKind
    var seconds: Float
    var note: String
}

enum PuzzleKind: String { case puzzle, story, transit }

enum ClueSource: Equatable {
    case page(Int)
    /// What the player carries from another puzzle's solve (the stones' tones and order).
    case memory(of: String)
    /// A key of `PuzzleGraph.keys` (P02.5): something learned at one place and carried to this puzzle.
    case key(String)
}
struct PuzzleClue: Equatable {
    var source: ClueSource
    var world: WorldKind
    /// Where the clue lies (a page's box centre); nil for a memory, whose place is its source puzzle's machine.
    var position: SIMD3<Float>?
    var label: String
}

/// P02 section 3.2: what a player carries from one place to another, as data. `learnedAt` names a puzzle (the key is what its solve or its machine teaches) or a place (a planted clue, `planted`: no page states
/// it and nothing flags it). `usedAt` are the puzzles that take it as a clue. A key is `built` when both ends exist in the game today; `planned` ones are listed with who builds them and are not scored.
struct PuzzleKey: Equatable {
    enum Status: Equatable { case built, planned(String) }
    var id: String
    var title: String
    var channel: PuzzleChannel
    var learnedAt: String
    var learnedWorld: WorldKind
    var learnedPosition: SIMD3<Float>?
    var usedAt: [String]
    var planted = false
    var status: Status = .built
    /// The datum in words, for the report (a count, a relation).
    var value: String
}

struct PuzzleNode {
    var id: String
    var title: String
    var world: WorldKind
    var kind: PuzzleKind = .puzzle
    /// Optional puzzles (the contradiction, Oren's exit ring) are reported but never counted as "open" and never gate anything.
    var optional = false
    /// Alternative ways of one machine (Ilse's held tone, Oren's turned beam) share a group: they count once, and may share an answer.
    var group: String?
    var verb: String
    var channel: PuzzleChannel
    /// The answer as glyph tokens ("tide", "wind", "stone", "angle:-45"...), in the order it is given. Empty for a story beat.
    var answer: [String] = []
    var manipulations = 0
    var requires: [String] = []
    var sets: String?
    /// Where the machine stands: the centres of its interactables. Empty when the machine is the Notebook.
    var machine: [SIMD3<Float>] = []
    var machineIDs: [String] = []
    var clues: [PuzzleClue] = []
    var feedback: [PuzzleFeedback] = []
}

/// What a page says about the answer, read from its text (both voices for the Archive's pages).
struct PageFact: Equatable {
    var id: Int
    var world: WorldKind
    var position: SIMD3<Float>?
    /// The answer the page's words give ("tide", "wind", "stone" in order), or empty when it gives none.
    var states: [String]
    var statesOrder: Bool { !states.isEmpty }
}

struct PuzzleGraph {
    var puzzles: [PuzzleNode]
    var pages: [PageFact]
    /// Flags the player's own walking grants (standing near the quay, collecting the gate's pages): no puzzle sets them.
    var external: Set<String>
    var keys: [PuzzleKey] = []
    func node(_ id: String) -> PuzzleNode? { puzzles.first { $0.id == id } }
}

struct PuzzleBreak: Equatable {
    var rule: String
    var subject: String
    var detail: String
    /// What the pin compares: the rule and who breaks it, never the numbers in the detail.
    var key: String { "\(rule) \(subject)" }
}

struct OpenStep { var id: String; var world: WorldKind; var open: [String]; var firstInWorld: Bool }

enum PuzzleRules {
    static let clueMinDistance: Float = 40
    static let manipulationBudget = 3...6
    static let clueBudget = 1...2
    static let minOpen = 2
    static let feedbackWithin: Float = 1.0

    static let ruleTitles: [(String, String)] = [
        ("G1", "the graph is acyclic and every puzzle can be reached"),
        ("G2", "every flag a puzzle needs is set by something (or by walking)"),
        ("G3", "every page that states an answer is a clue of some puzzle"),
        ("G4", "every clue is 40 m or a world away from its machine"),
        ("G5", "no two puzzles share an answer"),
        ("G6", "at least two puzzles are open when a player chooses (after the first of a world)"),
        ("G7", "every machine answers with progress, on two senses, within 1 s"),
        ("G8", "3 to 6 manipulations; 1 to 2 clue sources"),
        ("G9", "every puzzle has its own verb and channel"),
        ("G10", "the answer is not handed over as a sentence"),
        ("G11", "every built key is learned somewhere, used by a puzzle that lists it, and carried across a world or 40 m"),
    ]

    /// All rule breaks of a graph, in rule order.
    static func breaks(_ g: PuzzleGraph) -> [PuzzleBreak] {
        acyclic(g) + flagsProvided(g) + clueConsumers(g) + clueDistance(g) + sharedAnswer(g) + openAtOnce(g) + feedback(g) + budgets(g) + verbChannel(g) + answerAsSentence(g) + keyRule(g)
    }

    /// The puzzles every rule but G6 scores: real puzzles (not story beats or transits), optional ones included (Oren's exit ring is a machine a player works).
    private static func scored(_ g: PuzzleGraph) -> [PuzzleNode] { g.puzzles.filter { $0.kind == .puzzle } }

    // MARK: G1, G2: the flag graph

    /// An edge from each puzzle to the puzzles that set a flag it needs. A cycle means nothing in it can ever open.
    static func acyclic(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var out: [PuzzleBreak] = []
        func producers(of flag: String) -> [PuzzleNode] { g.puzzles.filter { $0.sets == flag } }
        var state: [String: Int] = [:]                       // 1 in progress, 2 done
        var found: Set<String> = []
        func visit(_ n: PuzzleNode, _ path: [String]) {
            if state[n.id] == 2 { return }
            if state[n.id] == 1 { found.insert((path.drop { $0 != n.id } + [n.id]).sorted().joined(separator: ",")); return }
            state[n.id] = 1
            for f in n.requires { for p in producers(of: f) { visit(p, path + [n.id]) } }
            state[n.id] = 2
        }
        for n in g.puzzles { visit(n, []) }
        for c in found.sorted() { out.append(PuzzleBreak(rule: "G1", subject: "cycle", detail: "puzzles that wait for each other: \(c)")) }
        // Reachable: simulate from the external flags; whatever never opens is cut off.
        var flags = g.external, done: Set<String> = []
        var progressed = true
        while progressed {
            progressed = false
            for n in g.puzzles where !done.contains(n.id) && n.requires.allSatisfy({ flags.contains($0) }) {
                done.insert(n.id); if let s = n.sets { flags.insert(s) }; progressed = true
            }
        }
        for n in g.puzzles where !done.contains(n.id) { out.append(PuzzleBreak(rule: "G1", subject: n.id, detail: "can never open: it needs \(n.requires.filter { !flags.contains($0) })")) }
        return out
    }

    static func flagsProvided(_ g: PuzzleGraph) -> [PuzzleBreak] {
        let made = Set(g.puzzles.compactMap(\.sets)).union(g.external)
        return g.puzzles.flatMap { n in n.requires.filter { !made.contains($0) }.map { PuzzleBreak(rule: "G2", subject: "\(n.id) needs \($0)", detail: "no puzzle sets the flag \($0) and walking does not grant it") } }
    }

    // MARK: G3: stated answers without a consumer

    static func clueConsumers(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var out: [PuzzleBreak] = []
        for p in g.pages where p.statesOrder {
            if !g.puzzles.contains(where: { $0.clues.contains { $0.source == .page(p.id) } }) {
                out.append(PuzzleBreak(rule: "G3", subject: "page \(p.id)", detail: "page \(p.id) states the order and no puzzle lists it as a clue: a clue with no consumer, or an answer given away for nothing"))
            }
        }
        for n in g.puzzles { for c in n.clues { if case .memory(let of) = c.source, g.node(of) == nil { out.append(PuzzleBreak(rule: "G3", subject: "\(n.id) clue \(of)", detail: "the clue points at a puzzle that is not in the graph")) } } }
        return out
    }

    // MARK: G11: keys (P02.5)

    static func keyRule(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var out: [PuzzleBreak] = []
        for k in g.keys {
            if case .planned = k.status { continue }
            if k.usedAt.isEmpty { out.append(PuzzleBreak(rule: "G11", subject: "\(k.id) consumer", detail: "the key \(k.id) is learned and never used")) }
            if g.node(k.learnedAt) == nil && !k.planted { out.append(PuzzleBreak(rule: "G11", subject: "\(k.id) source", detail: "the key \(k.id) says it is learned at \(k.learnedAt), which is no puzzle of the graph")) }
            for u in k.usedAt {
                guard let n = g.node(u) else { out.append(PuzzleBreak(rule: "G11", subject: "\(k.id) \(u)", detail: "\(u) is no puzzle of the graph")); continue }
                guard let c = n.clues.first(where: { $0.source == .key(k.id) }) else { out.append(PuzzleBreak(rule: "G11", subject: "\(k.id) \(u)", detail: "\(u) does not list the key as a clue")); continue }
                if let d = distance(c, to: n, in: g), d < clueMinDistance { out.append(PuzzleBreak(rule: "G11", subject: "\(k.id) \(u) distance", detail: String(format: "the key is %.0f m from the machine that uses it", d))) }
            }
        }
        for n in g.puzzles { for c in n.clues { if case .key(let id) = c.source, !g.keys.contains(where: { $0.id == id }) { out.append(PuzzleBreak(rule: "G11", subject: "\(n.id) clue \(id)", detail: "the clue names a key that the table does not have")) } } }
        return out
    }

    // MARK: G4: distance

    static func distance(_ clue: PuzzleClue, to n: PuzzleNode, in g: PuzzleGraph) -> Float? {
        if clue.world != n.world { return .infinity }
        let from: [SIMD3<Float>]
        switch clue.source {
        case .page: from = clue.position.map { [$0] } ?? []
        case .memory(let of): from = g.node(of)?.machine ?? []
        case .key: from = clue.position.map { [$0] } ?? []
        }
        guard !from.isEmpty, !n.machine.isEmpty else { return nil }
        return from.flatMap { a in n.machine.map { simd_length($0 - a) } }.min()
    }

    static func clueDistance(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var out: [PuzzleBreak] = []
        for n in scored(g) where n.channel != .aim {
            for c in n.clues {
                guard let d = distance(c, to: n, in: g), d < clueMinDistance else { continue }
                out.append(PuzzleBreak(rule: "G4", subject: "\(n.id) \(c.label)", detail: String(format: "%@ is %.0f m from the machine (the rule is %.0f m or another world)", c.label, d, clueMinDistance)))
            }
        }
        return out
    }

    // MARK: G5: shared answers

    static func sharedAnswer(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var byAnswer: [String: [PuzzleNode]] = [:]
        for n in g.puzzles where n.kind == .puzzle && !n.answer.isEmpty { byAnswer[n.answer.joined(separator: " ") , default: []].append(n) }
        var out: [PuzzleBreak] = []
        for (answer, nodes) in byAnswer.sorted(by: { $0.key < $1.key }) {
            let ways = Set(nodes.map { $0.group ?? $0.id })
            if ways.count > 1 { out.append(PuzzleBreak(rule: "G5", subject: ways.sorted().joined(separator: "+"), detail: "\(ways.count) puzzles are all answered by \"\(answer)\"")) }
        }
        return out
    }

    // MARK: G6: what is open when the player chooses

    /// Play the graph as a player who always takes the first open puzzle: transits and story beats happen as soon as their flags are there; before each choice, how many (non-optional) puzzles
    /// are open. A puzzle that is open together with its alternative way counts once.
    static func timeline(_ g: PuzzleGraph) -> [OpenStep] {
        var flags = g.external, done: Set<String> = [], doneGroups: Set<String> = [], seenWorlds: Set<WorldKind> = []
        var out: [OpenStep] = []
        func ready(_ n: PuzzleNode) -> Bool { !done.contains(n.id) && n.requires.allSatisfy { flags.contains($0) } }
        for _ in 0..<(g.puzzles.count + 2) * 2 {
            var moved = true
            while moved {
                moved = false
                for n in g.puzzles where n.kind != .puzzle && ready(n) { done.insert(n.id); if let s = n.sets { flags.insert(s) }; moved = true }
            }
            let open = g.puzzles.filter { $0.kind == .puzzle && !$0.optional && ready($0) && !($0.group.map { doneGroups.contains($0) } ?? false) }
            guard let pick = open.first else { break }
            let ways = Array(Set(open.map { $0.group ?? $0.id })).sorted()
            out.append(OpenStep(id: pick.id, world: pick.world, open: ways, firstInWorld: !seenWorlds.contains(pick.world)))
            seenWorlds.insert(pick.world)
            done.insert(pick.id); if let gr = pick.group { doneGroups.insert(gr) }; if let s = pick.sets { flags.insert(s) }
        }
        return out
    }

    /// The first puzzle of each world and the last of the game are exempt: nothing can be open beside the very last one, and a player entering a world has not had its first ten minutes yet.
    static func openAtOnce(_ g: PuzzleGraph) -> [PuzzleBreak] {
        let steps = timeline(g)
        return steps.enumerated().filter { !$0.element.firstInWorld && $0.offset < steps.count - 1 && $0.element.open.count < minOpen }.map(\.element)
            .map { PuzzleBreak(rule: "G6", subject: $0.id, detail: "when \($0.id) is chosen only \($0.open) is open: a chain, not a web") }
    }

    // MARK: G7: feedback

    static func feedback(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var out: [PuzzleBreak] = []
        for n in scored(g) {
            let useful = n.feedback.filter { $0.kind != .binary && $0.seconds <= feedbackWithin }
            if !n.feedback.contains(where: { $0.kind == .progress }) { out.append(PuzzleBreak(rule: "G7", subject: "\(n.id) progress", detail: "nothing tells the player how close they are (only live or binary answers)")) }
            let senses = Set(useful.map(\.sense))
            if senses.count < 2 { out.append(PuzzleBreak(rule: "G7", subject: "\(n.id) senses", detail: "within \(feedbackWithin) s it answers on \(senses.map(\.rawValue).sorted()) and not on two senses")) }
        }
        return out
    }

    // MARK: G8, G9, G10

    static func budgets(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var out: [PuzzleBreak] = []
        for n in scored(g) {
            if !manipulationBudget.contains(n.manipulations) { out.append(PuzzleBreak(rule: "G8", subject: "\(n.id) manipulations", detail: "\(n.manipulations) manipulations (budget \(manipulationBudget))")) }
            if n.channel != .aim, !clueBudget.contains(n.clues.count) { out.append(PuzzleBreak(rule: "G8", subject: "\(n.id) clues", detail: "\(n.clues.count) clue sources (budget \(clueBudget))")) }
        }
        return out
    }

    static func verbChannel(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var by: [String: [PuzzleNode]] = [:]
        for n in scored(g) { by["\(n.verb)/\(n.channel.rawValue)", default: []].append(n) }
        return by.sorted { $0.key < $1.key }.compactMap { key, nodes in
            let ways = Set(nodes.map { $0.group ?? $0.id })
            return ways.count > 1 ? PuzzleBreak(rule: "G9", subject: ways.sorted().joined(separator: "+"), detail: "\(ways.count) puzzles share the verb and channel \(key)") : nil
        }
    }

    static func answerAsSentence(_ g: PuzzleGraph) -> [PuzzleBreak] {
        var out: [PuzzleBreak] = []
        for n in scored(g) where !n.answer.isEmpty {
            for c in n.clues { if case .page(let id) = c.source, g.pages.first(where: { $0.id == id })?.states == n.answer { out.append(PuzzleBreak(rule: "G10", subject: "\(n.id) page \(id)", detail: "page \(id) says the order in words")) } }
        }
        return out
    }

    // MARK: Reading a page for a stated answer

    /// The answer the text gives when it names the three glyphs in the stones' order close together ("from the water, through the wind, to the stone"), else empty. `water` counts as tide; `stones`
    /// (the island's things) does not count as `stone`.
    static func statedAnswer(_ text: String, window: Int = 120) -> [String] {
        let t = text.lowercased()
        func positions(_ pattern: String) -> [Int] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            return re.matches(in: t, range: NSRange(t.startIndex..., in: t)).map { $0.range.location }
        }
        let tide = positions(#"\b(tide|water)\b"#), wind = positions(#"\bwind\b"#), stone = positions(#"\bstone\b"#)
        for a in tide { for b in wind where b > a { for c in stone where c > b && c - a <= window { return ["tide", "wind", "stone"] } } }
        return []
    }
}

// MARK: - Today's graph, built from the live game

extension PuzzleGraph {
    /// The graph of the game as it is. `game` must hold all three worlds (`Game(scenes:)` with Varrow, the Glass Wood and the Archive).
    static func today(game: Game) -> PuzzleGraph {
        func centre(_ id: String, _ w: WorldKind) -> SIMD3<Float>? { game.interactables(in: w).first { $0.id == id }.map { ($0.min + $0.max) / 2 } }
        func centres(_ ids: [String], _ w: WorldKind) -> [SIMD3<Float>] { ids.compactMap { centre($0, w) } }

        // Pages: where each lies (the world whose boxes hold `page_n`) and whether its text states the order, in either voice.
        var pages: [PageFact] = []
        for id in StoryPages.varrowIDs + StoryPages.glassIDs + StoryPages.archiveIDs {
            let w = WorldKind.allCases.first { game.interactables(in: $0).contains { $0.id == "page_\(id)" } } ?? .varrow
            let texts = [PageAuthor.ilse, .oren].compactMap { StoryPages.text(id, route: $0) }
            pages.append(PageFact(id: id, world: w, position: centre("page_\(id)", w), states: texts.map { PuzzleRules.statedAnswer($0) }.first { !$0.isEmpty } ?? []))
        }
        func pageClue(_ n: Int, _ label: String? = nil) -> PuzzleClue {
            let p = pages.first { $0.id == n }
            return PuzzleClue(source: .page(n), world: p?.world ?? .varrow, position: p?.position, label: label ?? "page \(n)")
        }
        func memory(_ of: String, _ w: WorldKind, _ label: String) -> PuzzleClue { PuzzleClue(source: .memory(of: of), world: w, position: nil, label: label) }

        // Answers, from the puzzles' own constants.
        let stoneTokens = ["tide", "wind", "stone"]
        let stonesAnswer = LighthousePuzzle.order.map { stoneTokens[$0.rawValue] }
        let platesAnswer = TonePlatePuzzle.order.map { stoneTokens[$0] }
        let mirrorsAnswer = MirrorCourt.solutionPanes.map { stoneTokens[$0] }
        let chimesAnswer = GlassWoodLogic.chimeSolution.map { k in stoneTokens[ToneTable.stoneHz.firstIndex(of: ToneTable.glassHz[k]) ?? 0] }
        let gatesAnswer = TideArchivePuzzle.sluiceFlags.indices.map { stoneTokens[$0] }

        // Manipulations, computed.
        let mirrors = mirrorSearch()
        let lensSteps = Int((abs(LensPortalProps.receiverAngle - LensPortalProps.initialRingAngle) / LensPortalProps.ringStep).rounded())
        let beamSteps = ringSteps(from: TideArchivePuzzle.initialRing, through: TideArchivePuzzle.beamTargets, step: TideArchivePuzzle.ringStep)

        let sight: (FeedbackKind, Float, String) -> PuzzleFeedback = { PuzzleFeedback(sense: .sight, kind: $0, seconds: $1, note: $2) }
        let sound: (FeedbackKind, Float, String) -> PuzzleFeedback = { PuzzleFeedback(sense: .sound, kind: $0, seconds: $1, note: $2) }

        // P02.5: the keys of plan section 3.2. Positions are the real ones (the stones' machine, the chime ring, the first dock lantern).
        let dockLantern: SIMD3<Float>? = game.scenes[.varrow]?.placed.first { $0.kind == "lantern" }.map { l in l.low.reduce(SIMD3<Float>.zero, +) / Float(max(l.low.count, 1)) }
        let keys: [PuzzleKey] = [
            PuzzleKey(id: "stones-tones", title: "the stones' tones", channel: .hear, learnedAt: "stones", learnedWorld: .varrow, learnedPosition: centre("stone_tide", .varrow), usedAt: ["chime-pool"],
                      value: "tide D4, wind A4, stone D5: the three of the pool's five chimes that are not decoys"),
            PuzzleKey(id: "three-heights", title: "the three heights", channel: .see, learnedAt: "chime-pool", learnedWorld: .glassWood, learnedPosition: centre("gw_chime_0", .glassWood), usedAt: ["archive-gates-tone", "archive-gates-beam"], planted: true,
                      status: .planned("the gates' water marks (builder A, Q76): until they exist nothing at the gates uses it, so the gates do not list it as a clue"),
                      value: "the non-decoy chimes hang in the order of the sluice rooms' floors (tide highest): an ORDER today, not a scale, and the gates carry no mark for it yet (Q76)"),
            PuzzleKey(id: "lantern-count", title: "the lit-lantern count", channel: .count, learnedAt: "dock-lanterns", learnedWorld: .varrow, learnedPosition: dockLantern, usedAt: ["archive-gates-beam"], planted: true,
                      value: "\(PlantedClues.litCount) of the first \(PlantedClues.lanternSpan) dock lanterns are lit = \(PlantedClues.firstRingMarkSteps) steps to the prism ring's first mark (Oren's way; Ilse's fork has no counterpart yet, Q75)"),
            PuzzleKey(id: "stones-order", title: "the stones' altitude order", channel: .see, learnedAt: "the island-profile diagram on page \(PageArt.islandProfilePage)", learnedWorld: .varrow, learnedPosition: pages.first { $0.id == PageArt.islandProfilePage }?.position, usedAt: ["stones", "door-plates"], planted: true,
                      value: "a drawn profile of the climb with a mark at each stone's real height (\(PageArt.stonesByAltitude.map(\.name).joined(separator: " < "))); a mark shows its rubbing once the stone has been looked at closely (Q51); the plates use it to name a flash's length (short = low = tide)"),
            PuzzleKey(id: "beam-rhythm", title: "the beam rhythm", channel: .watch, learnedAt: "the lighthouse beam at dusk, from the dock", learnedWorld: .varrow, learnedPosition: Layout.dockEnd, usedAt: ["door-plates"], planted: true,
                      value: "three groups of flashes of \(Layout.Navigation.SignalPattern.groupSeconds.map { String(format: "%.1f", $0) }.joined(separator: ", ")) s, read by RANK (short = tide, middle = wind, long = stone): the plates are struck in the order flashed, \(TonePlatePuzzle.order.map { stoneTokens[$0] }.joined(separator: ", "))"),
            PuzzleKey(id: "map-shape", title: "the map's empty last ring", channel: .see, learnedAt: "the chain map (Archive)", learnedWorld: .tideArchive, learnedPosition: nil, usedAt: [],
                      status: .planned("the Salt Flats' first lamp (not built)"), value: "the shape of the last ring"),
        ]
        func keyClue(_ id: String) -> PuzzleClue {
            let k = keys.first { $0.id == id }
            return PuzzleClue(source: .key(id), world: k?.learnedWorld ?? .varrow, position: k?.learnedPosition, label: k?.title ?? id)
        }

        var nodes: [PuzzleNode] = []
        nodes.append(PuzzleNode(
            id: "stones", title: "the three resonance stones (Varrow)", world: .varrow, verb: "strike", channel: .hear, answer: stonesAnswer, manipulations: LighthousePuzzle.order.count,
            requires: [Game.quaySeenFlag], sets: "solved", machine: centres(StoneID.allCases.map { "stone_\($0.name)" }, .varrow), machineIDs: StoneID.allCases.map { "stone_\($0.name)" },
            clues: [pageClue(2), pageClue(3), keyClue("stones-order")],
            feedback: [sight(.progress, LighthousePuzzle.Timing.litFade, "each right stone lights and stays lit; a wrong one dims all three"), sound(.progress, 0.0, "each strike rings and the right ones hold their drone")]))
        nodes.append(PuzzleNode(id: "to-glass-wood", title: "touch the islet's lens", world: .varrow, kind: .transit, verb: "touch", channel: .touch, requires: ["solved"], sets: "lensTouched",
                                machine: centres(["lens"], .varrow), machineIDs: ["lens"]))
        nodes.append(PuzzleNode(
            id: "mirror-court", title: "the mirror court (Glass Wood)", world: .glassWood, verb: "turn+change", channel: .aim, answer: mirrorsAnswer, manipulations: mirrors.cheapest,
            requires: ["lensTouched"], sets: "gw_mirrors", machine: centres((0..<3).flatMap { ["gw_mirror_\($0)", "gw_pane_\($0)"] }, .glassWood), machineIDs: (0..<3).flatMap { ["gw_mirror_\($0)", "gw_pane_\($0)"] },
            clues: [pageClue(5), memory("stones", .varrow, "the stones' order")],
            feedback: [sight(.progress, 0.35, "the beam is retraced on the turn; each receiving crystal lights the moment the beam reaches it in its colour and goes dark when it is lost (a wrong colour flutters dully)"), sound(.progress, 0.0, "a glass tick on every turn, and a lit crystal rings its own stone tone")]))
        nodes.append(PuzzleNode(
            id: "chime-pool", title: "the chime pool (Glass Wood)", world: .glassWood, verb: "strike", channel: .hear, answer: chimesAnswer, manipulations: GlassWoodLogic.chimeSolution.count,
            requires: ["lensTouched"], sets: "gw_chimes", machine: centres((0..<GlassPuzzleProps.chimeCount).map { "gw_chime_\($0)" }, .glassWood), machineIDs: (0..<GlassPuzzleProps.chimeCount).map { "gw_chime_\($0)" },
            clues: [keyClue("stones-tones")],
            feedback: [sight(.progress, 0.3, "a right chime lights and stays lit; a wrong one sours and resets"), sound(.progress, 0.0, "each chime rings its tone; a wrong one sours")]))
        nodes.append(PuzzleNode(id: "altar", title: "the altar of two accounts (Glass Wood)", world: .glassWood, kind: .story, verb: "touch", channel: .touch, manipulations: 2,
                                requires: ["gw_mirrors", "gw_chimes"], sets: "gw_end", machine: centres(["gw_altar_ilse", "gw_altar_oren"], .glassWood), machineIDs: ["gw_altar_ilse", "gw_altar_oren"]))
        nodes.append(PuzzleNode(id: "return", title: "return through the lens", world: .glassWood, kind: .transit, verb: "touch", channel: .touch, requires: ["gw_end"], sets: "returned",
                                machine: centres(["gw_return"], .glassWood), machineIDs: ["gw_return"]))
        nodes.append(PuzzleNode(
            id: "door-plates", title: "the lighthouse door plates (Varrow)", world: .varrow, verb: "strike", channel: .watch, answer: platesAnswer, manipulations: TonePlatePuzzle.order.count,
            requires: ["returned", "gate_pages"], sets: Game.doorOpenFlag, machine: centres(TonePlates.names, .varrow), machineIDs: TonePlates.names,
            clues: [keyClue("beam-rhythm"), keyClue("stones-order")],
            feedback: [sight(.binary, 0.0, "the plates glint only while they would be answered"), sound(.progress, 0.0, "a right strike holds its tone; a wrong one sours and resets")]))
        nodes.append(PuzzleNode(
            id: "lens-ring", title: "the lens-room ring and receiver (Oren's exit)", world: .varrow, optional: true, verb: "turn", channel: .aim, answer: ["angle:\(Int((LensPortalProps.receiverAngle * 180 / .pi).rounded()))"],
            manipulations: lensSteps, requires: [Game.doorOpenFlag], sets: Game.portalOpenFlag, machine: centres(["lens_ring"], .varrow), machineIDs: ["lens_ring"],
            feedback: [sight(.progress, 0.0, "a beam preview runs from the ring's pointer, and the receiver takes a light while the gate is ready"), sound(.binary, 0.0, "a stone-on-brass grind with a detent click")]))
        nodes.append(PuzzleNode(id: "enter-archive", title: "take an exit from the lens room (Ilse touches the lens; Oren walks into the opened doorway)", world: .varrow, kind: .transit, verb: "touch", channel: .touch,
                                requires: [Game.doorOpenFlag], sets: "route_begun", machine: centres([Game.lampLensName], .varrow), machineIDs: [Game.lampLensName]))
        nodes.append(PuzzleNode(
            id: "archive-gates-tone", title: "the three sluice gates by the held tone (Archive, Ilse's way)", world: .tideArchive, group: "archive-gates", verb: "touch+hold", channel: .hear, answer: gatesAnswer,
            manipulations: TideArchivePuzzle.sluiceFlags.count, requires: ["route_begun"], sets: Game.routeSolvedFlag,
            machine: centres(TideArchivePuzzle.sluiceNames, .tideArchive), machineIDs: TideArchivePuzzle.sluiceNames,
            clues: [memory("stones", .varrow, "the stones' order"), pageClue(13)],
            feedback: [sight(.progress, 0.0, "the gate lifts and its wheel turns; the water over the room's floor shows whether it can answer"), sound(.progress, 0.0, "the held tone, souring if wrong")]))
        nodes.append(PuzzleNode(
            id: "archive-gates-beam", title: "the three sluice gates by the prism ring (Archive, Oren's way)", world: .tideArchive, group: "archive-gates", verb: "turn", channel: .aim, answer: gatesAnswer,
            manipulations: beamSteps, requires: ["route_begun"], sets: Game.routeSolvedFlag, machine: centres([TideArchivePuzzle.ringName], .tideArchive), machineIDs: [TideArchivePuzzle.ringName],
            clues: [pageClue(13), keyClue("lantern-count")],
            feedback: [sight(.progress, 0.0, "the component brightens on its mark and the matching room's lamp lights"), sound(.progress, 0.0, "the held drone")]))
        nodes.append(PuzzleNode(
            id: "contradiction", title: "the Notebook's two accounts (optional)", world: .varrow, kind: .story, optional: true, verb: "set", channel: .see,
            manipulations: Contradictions.groupSize, requires: ["returned"], sets: "contradiction",
            clues: Contradictions.all.first.map { c in c.evidence.map { pageClue($0.page) } } ?? [], feedback: [sight(.binary, 0.0, "a quiet \"Settled.\" or silence")]))

        return PuzzleGraph(puzzles: nodes, pages: pages, external: [Game.quaySeenFlag, "gate_pages"], keys: keys)
    }

    /// Every setting of the mirror court (4 turns each, 3 pane colours each), the ones that solve it, and the fewest clicks from where the player finds it (a click moves one mirror or one pane on by one).
    static func mirrorSearch() -> (solutions: Int, cheapest: Int) {
        var solutions = 0, cheapest = Int.max
        for m0 in 0..<4 { for m1 in 0..<4 { for m2 in 0..<4 { for p0 in 0..<3 { for p1 in 0..<3 { for p2 in 0..<3 {
            let m = [m0, m1, m2], p = [p0, p1, p2]
            guard MirrorCourt.trace(mirrors: m, panes: p).solved else { continue }
            solutions += 1
            let cost = zip(m, MirrorCourt.initialMirrors).map { ($0 - $1 + 4) % 4 }.reduce(0, +) + zip(p, MirrorCourt.initialPanes).map { ($0 - $1 + 3) % 3 }.reduce(0, +)
            cheapest = min(cheapest, cost)
        } } } } } }
        return (solutions, cheapest)
    }

    /// Clicks to turn a ring through each target angle in turn, taking the shorter way round each time.
    static func ringSteps(from start: Float, through targets: [Float], step: Float) -> Int {
        var at = start, total = 0
        for t in targets {
            var d = (t - at).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d -= 2 * .pi }; if d <= -.pi { d += 2 * .pi }
            total += Int((abs(d) / step).rounded()); at = t
        }
        return total
    }
}
