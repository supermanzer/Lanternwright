import Foundation
import simd

/// P02.5: the planted clues and the keys table, as data and as the game really has them. A planted clue is unflagged on purpose, so the only thing that can notice it breaking is a test that reads
/// both ends: the datum in the world and the consumer in the Archive.
extension SelfTestRunner {
    func runPlantedClues() {
        guard name == "all" || name == "planted" else { return }
        // 1. The lantern count: the lit ones of the first eight stand in the world at their base glow, the unlit ones dim; six lit = six ring steps to the prism ring's first mark.
        let varrow = Scene.make(.varrow, device: device)
        let cores = (0..<PlantedClues.lanternSpan).map { k in varrow.items.first { $0.name == "\(LanternChain.coreName)\(k)" } }
        check(cores.allSatisfy { $0 != nil }, "planted: the first \(PlantedClues.lanternSpan) dock lanterns exist as cores")
        let lit = cores.enumerated().filter { $0.element?.uniforms.emissive.w == LanternChain.baseGlow }.map(\.offset)
        let dark = cores.enumerated().filter { $0.element?.uniforms.emissive.w == PlantedClues.darkGlow }.map(\.offset)
        check(lit.count == PlantedClues.litCount && Set(dark) == PlantedClues.darkLanterns && lit.count + dark.count == PlantedClues.lanternSpan, "planted: in the built Varrow \(lit.count) of the first \(PlantedClues.lanternSpan) lanterns are lit and \(dark) are not")
        check(PlantedClues.darkGlow > 0 && PlantedClues.darkGlow < LanternChain.baseGlow / 4, "planted: an unlit lantern is dim, clearly less than a lit one, not invisible (\(PlantedClues.darkGlow) against \(LanternChain.baseGlow))")
        check(PlantedClues.litCount == PlantedClues.firstRingMarkSteps && PlantedClues.firstRingMarkSteps == 6, "planted: the lit-lantern count (\(PlantedClues.litCount)) is the prism ring's steps to its first mark (\(PlantedClues.firstRingMarkSteps))")
        let noneAdjacent = PlantedClues.darkLanterns.sorted().adjacentPairs().allSatisfy { $1 - $0 > 1 }
        check(noneAdjacent && !PlantedClues.darkLanterns.contains(0), "planted: the unlit ones are not next to each other and the first lantern by the dock is lit (the lit path still reads as a path)")
        // After the return the lanterns flare for a while and settle back to THEIR base glow (the dark ones stay dark).
        check((0..<PlantedClues.lanternSpan).allSatisfy { LanternChain.glow(index: $0, time: LanternChain.total(count: 12) + 1) == PlantedClues.baseGlow(lantern: $0) }, "planted: after the return's flare every lantern settles to its own base glow")

        // 2. The chimes' heights follow the rooms' floors.
        check(PlantedClues.heightsFollowFloors, "planted: the three non-decoy chimes hang in the order of the sluice rooms' floors (heights \(PlantedClues.solutionChimeHeights), floors \(PlantedClues.gateFloors))")
        let decoys = (0..<GlassPuzzleProps.chimeCount).filter { !GlassWoodLogic.chimeSolution.contains($0) }.map { GlassPuzzleProps.chimeHeights[$0] }
        let (lo, hi) = (PlantedClues.solutionChimeHeights.min()!, PlantedClues.solutionChimeHeights.max()!)
        check(decoys.count == 2 && decoys.allSatisfy { $0 > lo && $0 < hi }, "planted: the two decoy chimes hang BETWEEN the real ones, so height alone does not pick them (\(decoys))")

        // 3. The keys table in today's graph.
        let g = PuzzleGraph.today(game: Game(scenes: [.varrow: varrow, .glassWood: Scene.make(.glassWood, device: device), .tideArchive: Scene.make(.tideArchive, device: device)]))
        func k(_ id: String) -> PuzzleKey? { g.keys.first { $0.id == id } }
        check(g.keys.count == 7 && g.keys.filter { $0.status == .built }.map(\.id) == ["stones-tones", "lantern-count", "stones-order", "beam-rhythm", "catalogue-diagram"], "planted: the plan's six keys and S05.3's catalogue diagram are in the table, five of them built (the heights are data and a test only, until the gates have marks; the map is the Salt Flats') (\(g.keys.map(\.id)))")
        check(k("lantern-count")?.usedAt == ["archive-gates-beam"] && k("three-heights")?.usedAt == ["archive-pipes", "archive-gates-beam"] && k("three-heights")?.status != .built && k("stones-tones")?.usedAt == ["chime-pool"], "planted: each key names its consumer (the heights' is planned: the gates' marks)")
        check(g.keys.filter { $0.status == .built }.allSatisfy { key in key.usedAt.allSatisfy { u in g.node(u)?.clues.contains { $0.source == .key(key.id) } == true } }, "planted: every consumer of a built key lists it as one of its clues")
        check(PuzzleRules.keyRule(g).isEmpty, "planted: the keys rule (G11) finds nothing wrong with today's built keys (\(PuzzleRules.keyRule(g).map(\.key)))")
        check(k("lantern-count")?.learnedPosition != nil && k("three-heights")?.learnedPosition != nil && k("stones-tones")?.learnedPosition != nil, "planted: the built keys' sources have real positions in the world")
        check(g.pages.filter(\.statesOrder).allSatisfy { p in !(k("lantern-count")?.value.contains("page \(p.id)") ?? false) } && k("lantern-count")?.planted == true && k("three-heights")?.planted == true, "planted: the two planted keys are unflagged: no page is their source")
    }
}

private extension Array {
    func adjacentPairs() -> [(Element, Element)] { zip(self, self.dropFirst()).map { ($0, $1) } }
}
