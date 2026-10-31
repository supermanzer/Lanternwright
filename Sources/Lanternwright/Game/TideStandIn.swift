import Foundation
import simd

/// S04.6: where the Tide Archive's gates, prism ring and two lying tools stand while the Glass Wood stands in for the Archive (behind `Game.tideArchiveEnabled`). Builder A's world (S04.1) will have its
/// own landmarks in `World/Layout.swift`; this file goes when it lands.
enum TideStandIn {
    static func sluicePosition(_ k: Int, scene: Scene) -> SIMD3<Float> { spot(8 + 2.2 * Float(k), -4, scene) + SIMD3(0, 1.2, 0) }
    static func mapPosition(scene: Scene) -> SIMD3<Float> { spot(-4, -9, scene) + SIMD3(0, 1.2, 0) }
    static func ringPosition(scene: Scene) -> SIMD3<Float> { spot(8, -9, scene) + SIMD3(0, 1.2, 0) }
    static func findPosition(_ lens: Bool, scene: Scene) -> SIMD3<Float> { spot(lens ? 12 : 4, -9, scene) + SIMD3(0, 0.6, 0) }
    private static func spot(_ dx: Float, _ dz: Float, _ scene: Scene) -> SIMD3<Float> {
        let x = GlassLayout.arrival.x + dx, z = GlassLayout.arrival.z + dz
        return SIMD3(x, scene.groundHeight(x: x, z: z), z)
    }
    static func pagePosition(_ n: Int, scene: Scene) -> SIMD3<Float> { spot(2 + 2 * Float(n - 10), -13, scene) + SIMD3(0, 0.3, 0) }
    static func interactables(scene: Scene) -> [Interactable] {
        func box(_ id: String, _ c: SIMD3<Float>, _ prompt: String, enabled: Bool = true) -> Interactable { Interactable(id: id, min: c - SIMD3(0.6, 0.6, 0.6), max: c + SIMD3(0.6, 0.6, 0.6), prompt: prompt, reach: 3.4, enabled: enabled) }
        var list = TideArchivePuzzle.sluiceNames.enumerated().map { k, n in box(n, sluicePosition(k, scene: scene), "Touch the gate") }
        list.append(box(TideArchivePuzzle.ringName, ringPosition(scene: scene), "Turn the ring  \u{2039} \u{203A}", enabled: false))
        list.append(box(TideArchivePuzzle.findForkName, findPosition(false, scene: scene), "Take the fork"))
        list.append(box(TideArchivePuzzle.findLensName, findPosition(true, scene: scene), "Take the lens"))
        list.append(box(ChainMap.interactableName, mapPosition(scene: scene), "Read the map"))
        for n in StoryPages.archiveIDs { list.append(box("page_\(n)", pagePosition(n, scene: scene), "Read the page")) }
        return list
    }
}
