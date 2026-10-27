import Foundation
import Metal
import simd

/// Self-tests: the dropped journal pages (F03 P1, notes #43 and #51). No lecterns, glow, light thread, motes; every sheet lies ON the surface under it (the lowest vertex
/// of each sheet between 0 and 5 mm above the ground under that vertex); each page is near its landmark; and each is off the player's main line of sight on the way in.
extension SelfTestRunner {
    func runPages() {
        guard name == "all" || name == "pages" else { return }
        let verbose = name == "pages"
        let home = Scene.makeWorld(device: device), glass = Scene.make(.glassWood, device: device)
        let sheet = PuzzleProps.pageMesh().vertices.map { SIMD3<Float>($0.position.x, $0.position.y, $0.position.z) }
        // No pickup aids remain.
        let aids = (home.items + glass.items).filter { $0.name.hasPrefix("page_stand") || $0.name.hasPrefix("page_beacon") || $0.name.hasPrefix("page_mote") }
        check(aids.isEmpty, "no lectern, light thread or mote remains for any page (\(aids.map(\.name)))")
        let lit = (home.items + glass.items).filter { $0.name.hasPrefix("page_") && $0.uniforms.emissive.w != 0 }
        check(lit.isEmpty, "no page or loose sheet glows (emissive 0 on every one of \((home.items + glass.items).filter { $0.name.hasPrefix("page_") }.count))")
        // Every sheet lies on what is under it, within 5 mm, and rests on it (not on stilts).
        var worst: (Float, Float) = (1, -1), tallest: Float = 0, count = 0
        for (sc, pages) in [(home, 1...4), (glass, 5...8)] {
            for n in pages {
                for item in sc.items where item.name == "page_\(n)" || item.name.hasPrefix("page_loose_\(n)_") {
                    let verts = sheet                                              // the loose sheets' own 0.9 scale is inside their model matrix
                    let c = DroppedPages.lowestClearance(vertices: verts, model: item.uniforms.model, ground: { sc.groundHeight(x: $0, z: $1) })
                    let hi = verts.map { v -> Float in let w = item.uniforms.model * SIMD4(v, 1); return w.y - sc.groundHeight(x: w.x, z: w.z) }.max() ?? 0
                    worst = (min(worst.0, c), max(worst.1, c)); tallest = max(tallest, hi); count += 1
                    if verbose && hi > 0.1 { print(String(format: "  %@ rises %.0f cm above the ground under its far edge", item.name, hi * 100)) }
                }
            }
        }
        if verbose { print(String(format: "%d sheets: lowest vertex %.1f to %.1f mm above the ground under it; highest vertex at most %.1f cm", count, worst.0 * 1000, worst.1 * 1000, tallest * 100)) }
        check(count >= 16 && worst.0 >= 0.0005 && worst.1 <= 0.005, "every dropped sheet lies ON its surface: the lowest vertex of each of \(count) sheets is \(String(format: "%.1f", worst.0 * 1000)) to \(String(format: "%.1f", worst.1 * 1000)) mm above the ground under it (0 to 5 mm; none sunk, none floating)")
        check(tallest < 0.20, "none stands on stilts or against a wall: the highest point of any sheet is \(String(format: "%.0f", tallest * 100)) cm above the ground under it")
        // Nothing is laid across a raised inlay: no sheet vertex within 6 cm (radially) of the arrival plate's rings and rim, the chime base's rings, or the altar's ring, and none over a
        // chime's foot or an altar pedestal (the inlays stand a few cm proud of the stone: a sheet across one would intersect it).
        var clash: [String] = []
        func radial(_ item: DrawItem, _ centre: SIMD3<Float>) -> [Float] { sheet.map { v in let w = item.uniforms.model * SIMD4(v, 1); return simd_length(SIMD2(w.x - centre.x, w.z - centre.z)) } }
        let altar0 = GlassLayout.altar, arrival0 = GlassLayout.arrival, ring0 = GlassLayout.chimeRing
        for item in glass.items where item.name.hasPrefix("page_") {
            let n = Int(item.name.split(separator: "_").filter { Int($0) != nil }.first ?? "0") ?? 0
            let rings: [(SIMD3<Float>, [Float])] = n == 5 ? [(arrival0, [1.15, 2.2, 3.15, 3.57])] : (n == 7 ? [(ring0, [GlassPuzzleProps.chimeRadius + 1.7, GlassPuzzleProps.chimeRadius - 1.3])] : (n == 8 ? [(altar0, [4.0, 4.6, 5.05, 5.5])] : []))
            for (c, radii) in rings { let r = radial(item, c); for rr in radii where r.contains(where: { abs($0 - rr) < 0.06 }) { clash.append("\(item.name) on the ring at \(rr)") } }
            if n == 7 { for k in 0..<GlassPuzzleProps.chimeCount { let c = GlassPuzzleProps.chimePosition(k); if radial(item, c).contains(where: { $0 < 0.75 }) { clash.append("\(item.name) on chime foot \(k)") } } }
        }
        check(clash.isEmpty, "no sheet is laid across a raised inlay, a chime's foot or the altar's ring (\(clash.isEmpty ? "none" : clash.joined(separator: "; ")))")
        // Page 8 lies on the altar dais' top step, not in it (note #51: the lectern had been set into the dais).
        let altar = GlassLayout.altar, p8 = GlassPuzzleProps.pagePosition(8, scene: glass)
        check(p8.y >= altar.y + 0.55 && p8.y <= altar.y + 0.62 && simd_length(SIMD2(p8.x - altar.x, p8.z - altar.z)) < 3.95, "page 8 lies on the dais' top step (sheet origin \(String(format: "%.3f", p8.y - altar.y)) m above the dais base, the top is 0.55 m; the sheet's own curl and lean lift the origin a few cm) and inside the glowing ring (radius 4.0): \(String(format: "%.2f", simd_length(SIMD2(p8.x - altar.x, p8.z - altar.z)))) m from its centre")
        // Near the landmark of its story.
        let dock = Layout.dockStrip()
        let dockDir = normalize(dock.b - dock.a)
        func distToDock(_ p: SIMD3<Float>) -> Float { let r = SIMD2(p.x, p.z) - dock.a; return abs(r.x * (-dockDir.y) + r.y * dockDir.x) }
        let stones = [StoneID.tide, .wind].map { SIMD3<Float>($0.position.x, 0, $0.position.z) }
        let lh = SIMD3<Float>(Layout.lighthouse.x, 0, Layout.lighthouse.z + 4.25)
        let pos = (1...8).map { $0 <= 4 ? PuzzleProps.pagePosition($0, scene: home) : GlassPuzzleProps.pagePosition($0, scene: glass) }
        func flat(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x, 0, p.z) }
        let d: [Float] = [distToDock(pos[0]), simd_length(flat(pos[1]) - stones[0]), simd_length(flat(pos[2]) - stones[1]), simd_length(flat(pos[3]) - lh),
                          simd_length(flat(pos[4]) - flat(GlassLayout.arrival)), simd_length(flat(pos[5]) - flat(MirrorCourt.world(MirrorCourt.receiver))),
                          simd_length(flat(pos[6]) - flat(GlassLayout.chimeRing)), simd_length(flat(pos[7]) - flat(altar))]
        let limit: [Float] = [1.3, 3.6, 3.6, 5.0, 3.6, 3.6, 5.2, 3.6]
        if verbose { print("distance of each page from its landmark (dock axis, tide stone, wind stone, lighthouse door, arrival, receiver, chime ring, altar): \(d.map { String(format: "%.1f", $0) })") }
        check(zip(d, limit).allSatisfy { $0 <= $1 }, "each page lies within a few metres of its landmark (\(d.map { String(format: "%.1f", $0) }) m; limits \(limit))")
        // Off the main line of sight on the way in: along the route, between 3 and 8 m from the page (where a flat sheet can be told from the ground), the page is within 10 degrees
        // of straight ahead for at most half of the steps. And the route passes close enough to see it at all.
        let route1: [SIMD3<Float>] = [Layout.dockEnd] + Layout.route
        let routes: [[SIMD3<Float>]] = [route1, route1, route1, route1, GlassLayout.path, GlassLayout.path, GlassLayout.path, GlassLayout.path]
        // Page 6 is reached by working the mirror court (the receiver is in it): the way in is the court's own mirrors and panes, not the path.
        let courtPoints: [SIMD3<Float>] = (0..<MirrorCourt.mirrorCells.count).map { GlassPuzzleProps.mirrorPosition($0) } + (0..<MirrorCourt.paneCells.count).map { GlassPuzzleProps.panePosition($0) }
        var fractions: [Float] = [], nearest: [Float] = []
        for n in 0..<8 {
            var inCone = 0, considered = 0, minD = Float.infinity
            let r = routes[n]
            for k in 0..<(r.count - 1) {
                let a = flat(r[k]), b = flat(r[k + 1]), seg = simd_length(b - a)
                guard seg > 0.01 else { continue }
                let t = (b - a) / seg
                var s: Float = 0
                while s < seg {
                    let p = a + t * s, to = flat(pos[n]) - p, dist = simd_length(to)
                    minD = min(minD, dist)
                    if dist >= 3 && dist <= 8 { considered += 1; if simd_dot(t, to / dist) > cos(10 * Float.pi / 180) { inCone += 1 } }
                    s += 0.5
                }
            }
            if n == 5 { minD = min(minD, courtPoints.map { simd_length(flat($0) - flat(pos[5])) }.min() ?? minD) }
            fractions.append(considered > 0 ? Float(inCone) / Float(considered) : 0); nearest.append(minD)
        }
        if verbose { print("share of the final approach (3-8 m) on which each page is within 10 degrees of straight ahead: \(fractions.map { String(format: "%.2f", $0) }); route passes within \(nearest.map { String(format: "%.1f", $0) }) m") }
        check(fractions.allSatisfy { $0 <= 0.5 }, "no page sits on the main line of sight: within 10 degrees of straight ahead for at most half of the last 8 m of the way in (\(fractions.map { String(format: "%.0f %%", $0 * 100) }))")
        check(nearest.enumerated().allSatisfy { $0.element < (($0.offset == 0) ? 3 : 8) }, "and the way in passes close enough to see each one (closest approach \(nearest.map { String(format: "%.1f", $0) }) m)")
        // The gust flutter is the only clue: a degree or two, never in a lull.
        let m = matrix_identity_float4x4
        let still = DroppedPages.flutter(model: m, page: 3, time: 5, gust: 0.1), blown = DroppedPages.flutter(model: m, page: 3, time: 5.4, gust: 1.0)
        var maxAngle: Float = 0
        for k in 0..<400 { let f = DroppedPages.flutter(model: m, page: 3, time: Float(k) * 0.05, gust: 1); maxAngle = max(maxAngle, abs(asin(max(-1, min(1, f.columns.1.z))))) }
        check(still == m && maxAngle < 3.5 * Float.pi / 180 && maxAngle > 0.5 * Float.pi / 180, "the only clue is faint: a page lifts at most \(String(format: "%.1f", maxAngle * 180 / .pi)) degrees in the strongest gust and is perfectly still in a lull (\(blown == m ? "no" : "some") movement at one sample)")
    }
}
