import Foundation
import simd

/// P02.5 (plan P02 section 3.1 and 3.2): the two PLANTED CLUES the plan builds first, each one unexplained physical datum that pays off a world later and is never flagged: no page states it, nothing
/// glows at it, the player has to notice it. Each is data here, the graph (`PuzzleGraph.keys`) names its consumer, and `SelfTestPlantedClues` pins that the datum and its consumer still agree.
///
///  1. **The lantern count** (Varrow, COUNT). Of the first `lanternSpan` stone lanterns along the dock path (the first 135 m, one every 18 m from 9 m) two are unlit and `litCount` = 6 are. Six is the number
///     of ring steps to the first mark of the Archive's prism ring (`TideArchivePuzzle.beamTargets[0]` is six steps from `initialRing`): a player who counted the lit lanterns on the way up knows the first
///     mark of the ring before they turn it. The plan's default was "the dark count equals the first step"; 40 m holds only two lanterns and six dark ones of eight would leave the dock looking unlit, so the
///     count is of the LIT ones (Q75).
///  2. **The chimes' heights** (Glass Wood, SEE). The pool's five glass chimes hang at five heights; the three that are not decoys (`GlassWoodLogic.chimeSolution`) are the tide, wind and stone tones, and
///     they hang in the same order as the three sluice rooms' floors in the Archive (`ArchiveLayout.sluiceFloors`: the tide room's floor is the highest, the stone room's the lowest): the tallest of the three is the gate that answers at the highest water.
///     Today that is an ORDER, not a scale (the heights' proportions are not the floors'), and the gates carry no mark for it yet (the plan's "visible level line the water passes" is builder A's, Q76).
enum PlantedClues {
    // MARK: 1. the lantern count

    /// How many lanterns along the dock path the pattern spans, which of them are unlit, and how bright an unlit one is (its stone and its empty lamp still read; `LanternChain.baseGlow` is a lit one's).
    static let lanternSpan = 8
    static let darkLanterns: Set<Int> = [2, 5]
    static let darkGlow: Float = 0.5
    static var litCount: Int { lanternSpan - darkLanterns.count }
    /// The resting glow of lantern `k` (in route order): lit unless it is one of the unlit ones.
    static func baseGlow(lantern k: Int) -> Float { darkLanterns.contains(k) ? darkGlow : LanternChain.baseGlow }
    /// The ring steps from where Oren finds the Archive's prism ring to its first mark (the number the lit lanterns count to).
    static var firstRingMarkSteps: Int { Int((abs(TideArchivePuzzle.beamTargets[0] - TideArchivePuzzle.initialRing) / TideArchivePuzzle.ringStep).rounded()) }

    // MARK: 2. the chimes' heights

    /// The three non-decoy chimes' hanging heights (m), in the order tide, wind, stone, and the three sluice rooms' floor heights (m) in the same order.
    static var solutionChimeHeights: [Float] { GlassWoodLogic.chimeSolution.map { GlassPuzzleProps.chimeHeights[$0] } }
    static var gateFloors: [Float] { ArchiveLayout.sluiceFloors }
    /// True when the chimes hang in the order of the rooms' floors (the tide chime highest like the tide room's floor, the stone chime lowest).
    static var heightsFollowFloors: Bool {
        let h = solutionChimeHeights, f = gateFloors
        return h.count == f.count && h == h.sorted(by: >) && f == f.sorted(by: >)
    }
}
