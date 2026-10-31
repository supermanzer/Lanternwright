import Foundation
import simd

/// S04 wiring: where the player touches things in builder A's Tide Archive (World/ArchiveProps.swift, World/Layout.swift `ArchiveLayout`), derived from A's landmarks so nothing is spelled out twice. The
/// interaction boxes are mine; the PROPS at the spots that A has not built yet (the tools, the pages, the chain map, the tableau, the quay rings) are A's: the spots are posted on the board topic `story`
/// and `docs/plans/S03-player-path.md` Part 2 lists them. If A prefers these folded into `World/Layout.swift`, they move as they are.
enum TideSpots {
    /// The wheel by each sluice gate (A's `sluiceWheelModel`): where the player turns it, touches the gate and holds the tone.
    static func gate(_ k: Int) -> SIMD3<Float> {
        let m = ArchiveProps.sluiceWheelModel(k, turns: 0).columns.3
        return SIMD3(m.x, m.y, m.z)
    }
    /// The prism's ring: on the brass pedestal under the prism.
    static let prismRing = ArchiveProps.prismPosition + SIMD3(0, -0.55, 0)
    /// The two tools lying in the world: the tuning fork among Ilse's ledgers (the stacks), the lens near the upper lamp on the way to the dome.
    static let fork = ArchiveLayout.point(-52, 34) + SIMD3(0, 0.95, 0)
    static let lens = ArchiveLayout.point(-30, -62) + SIMD3(0, 0.95, 0)
    /// The chain map: a stand beside the dome's door.
    static let chainMap = ArchiveLayout.point(7, -96) + SIMD3(0, 1.2, 0)
    /// The pages (S04.7), each by its landmark; 15 lies on the Great Ledger gallery's floor and is only there once the water has been drained.
    static func page(_ n: Int) -> SIMD3<Float> {
        switch n {
        case 10: return ArchiveLayout.point(3, 88) + SIMD3(0, 0.4, 0)                     // the landing, above the quays
        case 11: return ArchiveLayout.point(-54, 27) + SIMD3(0, 0.55, 0)                  // a lectern at the stacks
        case 12: return ArchiveLayout.point(52, -22) + SIMD3(0, 0.55, 0)                  // the Roll of Keepers' desk, on the way to the gallery
        case 13: return ArchiveLayout.point(3, -120) + SIMD3(0, 0.4, 0)                   // outside the prism chamber's doorway
        case 14: return ArchiveLayout.point(-5, -96) + SIMD3(0, 0.4, 0)                   // under the dome
        default: return SIMD3(ArchiveLayout.greatLedgerXZ.x - 4, ArchiveTerrain.gallery.floor + 0.3, ArchiveLayout.greatLedgerXZ.y)
        }
    }
    /// The tableau's two lanterns, at the gallery's west wall (north for Ilse's side, south for Oren's).
    static func tableauLight(_ side: PageAuthor) -> SIMD3<Float> {
        SIMD3(ArchiveLayout.greatLedgerXZ.x - 17, ArchiveTerrain.gallery.floor + 1.0, ArchiveLayout.greatLedgerXZ.y + (side == .ilse ? -8 : 8))
    }
    /// The ring on each quay that takes the player back to Varrow (the lamp end for Ilse's, the open end for Oren's).
    static func quayReturn(_ side: PageAuthor) -> SIMD3<Float> { (side == .oren ? ArchiveLayout.openEnd : ArchiveLayout.lampEnd) + SIMD3(side == .oren ? 3.5 : -3.5, 1.6, -3) }
    static let returnIDs = ["ta_return_ilse", "ta_return_oren"]

    /// Where the sound of water is measured from: the nearest of the sluice rooms and the gallery that hold the tide, as a distance from `p`.
    static func floor(at p: SIMD3<Float>) -> Game.ArchiveFloor {
        ArchiveLayout.sluiceSites.contains { simd_length(SIMD2(p.x, p.z) - $0) < ArchiveLayout.sluiceFlat } ? .grating : .slate
    }

    static func interactables(scene: Scene) -> [Interactable] {
        func box(_ id: String, _ c: SIMD3<Float>, _ prompt: String, half: Float = 0.6, enabled: Bool = true, reach: Float = 3.4) -> Interactable {
            Interactable(id: id, min: c - SIMD3(half, half, half), max: c + SIMD3(half, half, half), prompt: prompt, reach: reach, enabled: enabled)
        }
        var list: [Interactable] = []
        for k in 0..<3 { list.append(box(TideArchivePuzzle.sluiceNames[k], gate(k), "Touch the gate", half: 0.9)) }
        list.append(box(TideArchivePuzzle.ringName, prismRing, "Turn the ring  \u{2039} \u{203A}", half: 0.9, enabled: false))
        list.append(box(TideArchivePuzzle.findForkName, fork, "Take the fork"))
        list.append(box(TideArchivePuzzle.findLensName, lens, "Take the lens"))
        list.append(box(ChainMap.interactableName, chainMap, "Read the map"))
        for n in StoryPages.archiveIDs { list.append(box("page_\(n)", page(n), "Read the page", half: 0.5, enabled: n != 15)) }
        for side in [PageAuthor.ilse, .oren] { list.append(box(TideArchivePuzzle.tableauLightName(side), tableauLight(side), "Light the lantern", enabled: false)) }
        for (i, side) in [PageAuthor.ilse, .oren].enumerated() { list.append(box(returnIDs[i], quayReturn(side), "Return through the lens", half: 1.3, reach: 5)) }
        // The spots are written against the layout's base terrain; A's terraces and galleries lift some of it, so every box that rests on the ground is set on the real floor.
        return list.map { it in
            guard !it.id.hasPrefix("ta_sluice_"), it.id != TideArchivePuzzle.ringName, !returnIDs.contains(it.id), it.id != "page_15" else { return it }
            var o = it
            let c = (it.min + it.max) / 2, lift = scene.groundHeight(x: c.x, z: c.z) - ArchiveLayout.groundY(c.x, c.z)
            o.min.y += lift; o.max.y += lift
            return o
        }
    }
}
