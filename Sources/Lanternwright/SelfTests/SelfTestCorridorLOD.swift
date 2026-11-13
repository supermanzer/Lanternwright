import Foundation
import Metal
import simd

/// F09.9 (#103: "if we force players to use guided with enforced corridors, can we reduce rendering granularity for the parts of the world the player cannot approach?"): the measured answer.
/// A detail level decided from the CAMERA's distance (`Scene.applyLOD`: per tree cell, per frame, `lodLevelsDrawn`) already gives up every level the camera is too far from to need. The corridor can only supply a
/// LOWER BOUND on that distance (the eye is always inside it), so a level the corridor rules out is a level the camera rule already hides in every frame: pinning by corridor saves no frame time by construction.
/// What it could save is STATIC: the triangles and bytes of levels that no eye in the region can ever need (memory and build time), and only while Guided (Loose and Free would need them back, which means a
/// rebuild on a settings change). This test proves the bound over a sweep of eyes, and prints the static ceiling: `--selftest corridorlod`.
extension SelfTestRunner {
    func runCorridorLOD() {
        guard name == "all" || name == "corridorlod" else { return }
        let scene = Scene.makeWorld(device: device)
        let region = ReachableRegion.make(.varrow, scene: scene)
        func tris(_ n: String) -> Int { (scene.items.first { $0.name == n }?.mesh.indexCount ?? 0) / 3 }
        func bytes(_ n: String) -> Int { guard let m = scene.items.first(where: { $0.name == n })?.mesh else { return 0 }; return m.vertexBuffer.length + m.indexBuffer.length }
        // Eyes: every 5 m of the region (corridors and their margin), at the ground. The camera is never outside it in Guided.
        var eyes: [SIMD2<Float>] = []
        var z = region.bounds.min.y
        while z <= region.bounds.max.y { var x = region.bounds.min.x; while x <= region.bounds.max.x { if region.contains(SIMD2(x, z)) { eyes.append(SIMD2(x, z)) }; x += 5 }; z += 5 }
        check(eyes.count > 500, "corridorlod: the region holds \(eyes.count) eye positions on a 5 m grid")
        // A finer grid for the far bound: the farthest an eye of the region can be from the cell's box (the region's points are within 1.5 m of a 2 m grid point).
        var fine: [SIMD2<Float>] = []
        z = region.bounds.min.y
        while z <= region.bounds.max.y { var x = region.bounds.min.x; while x <= region.bounds.max.x { if region.contains(SIMD2(x, z)) { fine.append(SIMD2(x, z)) }; x += 2 }; z += 2 }
        func boxDistance(_ g: Scene.LODGroup, _ e: SIMD2<Float>) -> Float { let dx = max(g.min.x - e.x, 0, e.x - g.max.x), dz = max(g.min.y - e.y, 0, e.y - g.max.y); return (dx * dx + dz * dz).squareRoot() }
        struct Group { var g: Scene.LODGroup; var need: [Bool]; var diag: Float }
        var groups: [Group] = []
        for g in scene.lodGroups {
            // The nearest an eye can be: a lower bound on the region's distance to the cell's box (the smallest over a 9 x 9 grid of the box, less the farthest a point of the box can be from a grid point: the
            // distance is 1-Lipschitz). The farthest: the largest over the fine grid, plus its slack.
            let n = 9, sx = (g.max.x - g.min.x) / Float(n - 1), sz = (g.max.y - g.min.y) / Float(n - 1)
            var dmin = Float.infinity
            for i in 0..<n { for j in 0..<n { dmin = min(dmin, region.distance(to: SIMD2(g.min.x + Float(i) * sx, g.min.y + Float(j) * sz))) } }
            let lower = max(0, dmin - 0.5 * (sx * sx + sz * sz).squareRoot())
            let upper = (fine.map { boxDistance(g, $0) }.max() ?? 0) + 1.5
            let diag = ((g.max.x - g.min.x) * (g.max.x - g.min.x) + (g.max.y - g.min.y) * (g.max.y - g.min.y)).squareRoot()
            // `lodLevelsDrawn(d)` is [d < 58.4, d + diag > 31.6 && d < 149.75, d + diag > 100.25]: a level can be needed if some d in [lower, upper] satisfies it.
            let nearAny = Scene.lodLevelsDrawn(boxDistance: lower, diagonal: diag), farAny = Scene.lodLevelsDrawn(boxDistance: upper, diagonal: diag)
            let mid = Scene.lodLevelsDrawn(boxDistance: min(max(lower, 40), upper), diagonal: diag)
            groups.append(Group(g: g, need: [nearAny[0], nearAny[1] || farAny[1] || mid[1], farAny[2]], diag: diag))
        }
        var violations = 0, drawnTrisTotal = 0, drawnTrisMax = 0, wasteDrawn = 0
        for e in eyes {
            var frame = 0
            for gr in groups {
                let dx = max(gr.g.min.x - e.x, 0, e.x - gr.g.max.x), dz = max(gr.g.min.y - e.y, 0, e.y - gr.g.max.y)
                let drawn = Scene.lodLevelsDrawn(boxDistance: (dx * dx + dz * dz).squareRoot(), diagonal: gr.diag)
                for (i, name) in gr.g.names.enumerated() where drawn[min(i, 2)] {
                    frame += tris(name)
                    if !gr.need[min(i, 2)] { violations += 1; wasteDrawn += tris(name) }
                }
                if drawn[0] { for x in gr.g.extras { frame += tris(x); if !gr.need[0] { violations += 1 } } }
            }
            drawnTrisTotal += frame; drawnTrisMax = max(drawnTrisMax, frame)
        }
        // The static ceiling: levels (and the near level's extras) that no eye in the region can ever need.
        var staticTris = 0, staticBytes = 0, allTris = 0, allBytes = 0, cellsPinned = 0, levelsPinned = [0, 0, 0]
        for gr in groups {
            var any = false
            for (i, name) in gr.g.names.enumerated() {
                allTris += tris(name); allBytes += bytes(name)
                if !gr.need[min(i, 2)] { staticTris += tris(name); staticBytes += bytes(name); levelsPinned[min(i, 2)] += 1; any = true }
            }
            for x in gr.g.extras { allTris += tris(x); allBytes += bytes(x); if !gr.need[0] { staticTris += tris(x); staticBytes += bytes(x); any = true } }
            if any { cellsPinned += 1 }
        }
        let meanFrame = Float(drawnTrisTotal) / Float(max(eyes.count, 1))
        if name == "corridorlod" {
            print("corridorlod: \(groups.count) tree cells, \(allTris) triangles / \(allBytes / 1_000_000) MB in all their levels")
            print("corridorlod: levels no eye in the region can ever need: \(levelsPinned) cells at L0/L1/L2 (\(cellsPinned) cells touched): \(staticTris) triangles, \(String(format: "%.1f", Double(staticBytes) / 1e6)) MB (\(String(format: "%.1f", 100 * Double(staticTris) / Double(max(allTris, 1)))) % of the triangles)")
            print("corridorlod: per frame over \(eyes.count) eyes the camera rule draws \(Int(meanFrame)) tree triangles on average (worst \(drawnTrisMax)); of those, in levels the corridor rule would have removed: \(wasteDrawn)")
        }
        check(violations == 0, "corridorlod: no eye anywhere in the region ever draws a tree level the corridor bound rules out (\(violations) violations over \(eyes.count) eyes and \(groups.count) cells): the camera's own per-frame rule is already tighter, so pinning by corridor saves 0 triangles in any frame")
        check(staticTris >= 0 && allTris > 0, "corridorlod: the static ceiling is \(staticTris) of \(allTris) tree triangles (\(String(format: "%.1f", Double(staticBytes) / 1e6)) of \(allBytes / 1_000_000) MB): memory and build time, not frame time (measured, see docs: all trees together cost 0.1-0.6 ms of 8-10 ms at 2560x1440)")
    }
}
