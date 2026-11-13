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
    /// The two tools lying in the world, the chain map and the pages: the boxes sit on A's props (`ArchiveLayout`), which stand on the guided route (F09.1).
    static let fork = ArchiveLayout.findFork + SIMD3(0, 0.95, 0)
    static let lens = ArchiveLayout.findLens + SIMD3(0, 0.95, 0)
    static let chainMap = ArchiveLayout.chainMap + SIMD3(0, 1.2, 0)
    /// The pages (S04.7); 15 lies on the Great Ledger gallery's floor and is only offered once the water has been drained.
    static func page(_ n: Int) -> SIMD3<Float> {
        if n == 15 { return SIMD3(ArchiveLayout.pageSpots[5].x, ArchiveTerrain.gallery.floor + 0.3, ArchiveLayout.pageSpots[5].z) }
        let i = max(0, min(4, n - 10))
        return ArchiveLayout.pageSpots[i] + SIMD3(0, 0.2, 0)
    }
    /// The tableau's two lanterns, at the shadow-play wall (west for Ilse's side, east for Oren's): the lamp item sits 1.2 m above its stand's ground.
    static func tableauLight(_ side: PageAuthor) -> SIMD3<Float> { ArchiveLayout.tableauLantern[side == .ilse ? 0 : 1] + SIMD3(0, 1.45, 0) }
    /// The ring on each quay that takes the player back to Varrow (the lamp end for Ilse's, the open end for Oren's).
    static func quayReturn(_ side: PageAuthor) -> SIMD3<Float> { (side == .oren ? ArchiveLayout.openEnd : ArchiveLayout.lampEnd) + SIMD3(side == .oren ? 3.5 : -3.5, 1.6, -3) }
    static let returnIDs = ["ta_return_ilse", "ta_return_oren"]

    /// The floor underfoot: brass grating inside a sluice room, wet slate elsewhere.
    static func floor(at p: SIMD3<Float>) -> Game.ArchiveFloor {
        ArchiveLayout.sluiceSites.contains { simd_length(SIMD2(p.x, p.z) - $0) < ArchiveLayout.sluiceFlat } ? .grating : .slate
    }

    static func interactables(scene: Scene) -> [Interactable] {
        func box(_ id: String, _ c: SIMD3<Float>, _ prompt: String, half: Float = 0.6, enabled: Bool = true, reach: Float = 3.4) -> Interactable {
            Interactable(id: id, min: c - SIMD3(half, half, half), max: c + SIMD3(half, half, half), prompt: prompt, reach: reach, enabled: enabled)
        }
        var list: [Interactable] = []
        for k in 0..<3 { list.append(box(TideArchivePuzzle.sluiceNames[k], gate(k), "Touch the gate", half: 0.9)) }
        list.append(box(TideArchivePuzzle.ringName, prismRing, "Turn the ring  \u{2039} \u{203A}", half: 0.9))
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
