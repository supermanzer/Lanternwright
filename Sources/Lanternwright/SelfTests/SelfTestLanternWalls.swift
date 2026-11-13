import Foundation
import Metal
import simd

/// F09.6 (#97: "the lantern appears to sit inside this wall, at least partially", the Archive at (-2.1, 17.5, -91.8): the lantern stood inside the dome's drum): no lantern's lamp body is inside the ground or a solid collider. Props stand vertical and only their base and
/// footing may be sunk into a slope. The check uses the lantern's own MESH (every vertex of `Props.stoneLantern` above its base, 0.25 m up) placed where the game places it, against the terrain's surface and the Archive's colliders:
/// a vertex more than 2 cm under the ground, or inside a collider's cylinder, is inside the wall. Mutation: the placement as it was (no relocation) must show the fault.
extension SelfTestRunner {
    func runLanternWalls() {
        guard name == "all" || name == "lanternwalls" else { return }
        let archive = TideArchive.build(device: device)
        let terrain: Terrain = archive.terrain
        let body = Props.stoneLantern().body.vertices.map { SIMD3($0.position.x, $0.position.y, $0.position.z) }.filter { $0.y > 0.25 }
        // The solids: the terrain, and every cylinder collider of the Archive except the lanterns' own footings (radius 0.3 at a lantern's centre).
        let ownCentres = Set((ArchiveProps.lanternSites(terrain: terrain, relocate: false) + ArchiveProps.lanternSites(terrain: terrain)).map { SIMD2($0.centre.x, $0.centre.y) })
        let standCentres = Set(ArchiveLayout.tableauLantern.map { SIMD2($0.x, $0.z) })        // each tableau lantern's lamp sits on its own stand: that collider is the stand
        let solids = archive.colliders.cylinders.filter { !($0.radius == 0.3 && ownCentres.contains($0.center)) && !standCentres.contains($0.center) }
        func inside(_ t: float4x4, _ pts: [SIMD3<Float>]) -> (count: Int, worst: Float) {
            var n = 0, worst: Float = 0
            for p in pts {
                let w = t * SIMD4(p, 1), g = terrain.sampleHeight(x: w.x, z: w.z)
                if w.y < g - 0.02 { n += 1; worst = max(worst, g - w.y); continue }
                if let c = solids.first(where: { w.y > $0.minY && w.y < $0.maxY && simd_length(SIMD2(w.x, w.z) - $0.center) < $0.radius }) { n += 1; worst = max(worst, c.radius - simd_length(SIMD2(w.x, w.z) - c.center)) }
            }
            return (n, worst)
        }
        let old = ArchiveProps.lanternSites(terrain: terrain, solids: solids, relocate: false), new = ArchiveProps.lanternSites(terrain: terrain, solids: solids)
        let oldBad = old.filter { inside($0.transform, body).count > 0 }, newBad = new.filter { inside($0.transform, body).count > 0 }
        let spot = SIMD2<Float>(-2.1, -91.8)
        if name == "lanternwalls" {
            for st in new where simd_length(st.centre - spot) < 14 { print("lanternwalls: route lantern at (\(st.centre.x), \(st.transform.columns.3.y), \(st.centre.y)), \(simd_length(st.centre - spot)) m from the spot") }
            for it in archive.items {
                let b = it.worldBounds
                if b.min.x < spot.x + 6 && b.max.x > spot.x - 6 && b.min.z < spot.y + 6 && b.max.z > spot.y - 6 && !it.name.hasPrefix("terrain") { print("lanternwalls: item \(it.name) bounds x \(b.min.x)...\(b.max.x) y \(b.min.y)...\(b.max.y) z \(b.min.z)...\(b.max.z)") }
            }
        }
        if name == "lanternwalls" {
            let list = oldBad.map { (st: ArchiveProps.LanternSite) -> String in "(\(Int(st.centre.x)), \(Int(st.centre.y)) by \(String(format: "%.2f", inside(st.transform, body).worst)) m)" }.joined(separator: " ")
            print("lanternwalls: \(old.count) route lanterns; before the fix \(oldBad.count) have the lamp body in the ground: " + list)
        }
        let oldWorst: Float = oldBad.map { inside($0.transform, body).worst }.max() ?? 0
        check(!oldBad.isEmpty, "lanternwalls: mutation: the placement as it was puts \(oldBad.count) of \(old.count) route lanterns' lamp bodies into the ground or a wall's collider (worst \(String(format: "%.2f", oldWorst)) m): the fault of #97")
        let nearSpot = oldBad.filter { simd_length($0.centre - spot) < 12 }
        let nearText = nearSpot.map { "(\(Int($0.centre.x)), \(Int($0.centre.y)))" }.joined(separator: " ")
        check(!nearSpot.isEmpty, "lanternwalls: and one of them is within 12 m of the note's spot (-2.1, -91.8): \(nearText)")
        check(newBad.isEmpty && new.count == old.count, "lanternwalls: with the lanterns moved off the steep faces none of the \(new.count) has its lamp body in the ground (\(newBad.count) do), and none was dropped (\(old.count) before)")
        let moved = zip(old, new).filter { $0.0.centre != $0.1.centre }
        check(moved.allSatisfy { simd_length($0.0.centre - $0.1.centre) < 6 }, "lanternwalls: a lantern that moved stayed within 6 m of its old place (\(moved.count) moved, the farthest \(String(format: "%.1f", moved.map { simd_length($0.0.centre - $0.1.centre) }.max() ?? 0)) m)")
        check(new.allSatisfy { abs($0.transform.columns.1.x) < 1e-4 && abs($0.transform.columns.1.z) < 1e-4 && abs($0.transform.columns.1.y - 1) < 1e-4 }, "lanternwalls: every lantern stands vertical (props are never tilted; only their footing is sunk)")
        // The other lamps of the Archive: the sluice rooms' lamps and the tableau's two lanterns.
        for k in 0..<3 {
            let t = translation(SluiceLamps.position(k))
            check(inside(t, body).count == 0, "lanternwalls: the sluice room \(k)'s lamp is clear of the floor and walls (\(inside(t, body).count) vertices in the ground)")
        }
        for (k, p) in ArchiveLayout.tableauLantern.enumerated() {
            let f = Placement.upright(terrain: terrain, x: p.x, z: p.z, radius: 0.4, yaw: 0)
            let t = translation(SIMD3(p.x, f.transform.columns.3.y + 1.2, p.z))
            var lamp: [SIMD3<Float>] = []
            for sx: Float in [-0.17, 0.17] { for sz: Float in [-0.17, 0.17] { for y: Float in [0, 0.23, 0.46] { lamp.append(SIMD3(sx, y, sz)) } } }
            for a in 0..<4 { lamp.append(SIMD3(cos(Float(a) * .pi / 2 + .pi / 4) * 0.26, 0.46, sin(Float(a) * .pi / 2 + .pi / 4) * 0.26)) }
            check(inside(t, lamp).count == 0, "lanternwalls: the tableau lantern \(k)'s lamp is clear of the ground (\(inside(t, lamp).count) points in it)")
        }
    }
}
