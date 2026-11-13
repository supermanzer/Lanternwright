import Foundation
import Metal
import simd

/// F09.1: the interaction contract. What you can touch must be what you can see.
///  (a) every Interactable has a visible prop that the reticle ray really hits, inside (or touching) its box, from somewhere the player can stand;
///  (b) that standing place is inside the guided corridor (connected to the spawn) and within the box's `reach`;
///  (c) every visible readable/usable prop (a page, a ring, a map, a lens...) is covered by an Interactable.
/// `--audit-interactables [out.txt]` prints the table for every world; the selftest `interactables` requires all PASS and shows the audit can fail (a box moved 3 m).
/// A disabled interactable (a page that only appears later, the ring before the gates) is still audited, against the scene with its hidden items counted: it is the state the player reaches next.
enum InteractableAudit {
    struct Row {
        var kind: WorldKind
        var id: String
        var centre: SIMD3<Float>
        var nearest: String            // nearest scene mesh (by vertex) and its distance
        var nearestDistance: Float
        var reachable: Bool            // a corridor standing place within reach exists
        var seen: Bool                 // from some corridor standing place the reticle ray hits a prop inside the box first
        var stand: SIMD2<Float>?
        var hit: String                // what the best ray hit
        var eye: SIMD3<Float>?         // the eye at the standing place that sees it
        var enabled: Bool
        var verdict: Bool { reachable && seen }
    }
    struct Orphan { var kind: WorldKind; var item: String; var centre: SIMD3<Float>; var nearestBox: String; var distance: Float }
    struct Result { var rows: [Row] = []; var orphans: [Orphan] = [] ; var ok: Bool { rows.allSatisfy(\.verdict) && orphans.isEmpty } }

    // MARK: Ray casting against the drawn scene

    struct Hit { var t: Float; var item: String }

    /// The nearest drawn thing along the ray: a triangle of any item that is not hidden (unless `includeHidden`) or a water body, or the terrain. Glass is skipped (see through).
    static func cast(scene: Scene, origin o: SIMD3<Float>, dir d: SIMD3<Float>, maxT: Float, includeHidden: Bool) -> Hit? {
        var best: Hit?
        var limit = maxT
        // Terrain: march in 0.25 m steps (it is a heightfield; the props that stand on it come out of it).
        var t: Float = 0.25
        while t < limit {
            let q = o + d * t
            if scene.groundHeight(x: q.x, z: q.z) > q.y { best = Hit(t: t, item: "terrain"); limit = t; break }
            t += 0.25
        }
        for item in scene.items {
            if (item.hidden && !includeHidden) || item.refractive || item.isWaterBody { continue }
            let (lo, hi) = item.worldBounds
            guard let tb = Interaction.rayBox(origin: o, dir: d, min: lo - SIMD3(repeating: 0.02), max: hi + SIMD3(repeating: 0.02)), tb <= limit else { continue }
            if let th = hitTriangles(item, origin: o, dir: d, maxT: limit), th < limit { limit = th; best = Hit(t: th, item: item.name) }
        }
        return best
    }

    private static func hitTriangles(_ item: DrawItem, origin o: SIMD3<Float>, dir d: SIMD3<Float>, maxT: Float) -> Float? {
        let m = item.uniforms.model, inv = m.inverse
        let lo4 = inv * SIMD4(o, 1), ld4 = inv * SIMD4(d, 0)
        let lo = SIMD3(lo4.x, lo4.y, lo4.z), ld = SIMD3(ld4.x, ld4.y, ld4.z)         // the ray in the mesh's own space (t is the same, the model is rigid or uniform)
        let mesh = item.mesh
        let vp = mesh.vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
        let ip = mesh.indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
        var best: Float?
        var k = 0
        while k + 2 < mesh.indexCount {
            let a = vp[Int(ip[k])].position, b = vp[Int(ip[k + 1])].position, c = vp[Int(ip[k + 2])].position
            k += 3
            let p0 = SIMD3(a.x, a.y, a.z), e1 = SIMD3(b.x, b.y, b.z) - p0, e2 = SIMD3(c.x, c.y, c.z) - p0
            let pv = simd_cross(ld, e2), det = simd_dot(e1, pv)
            if abs(det) < 1e-9 { continue }                                          // two-sided: a page's underside counts too
            let inv = 1 / det, tv = lo - p0
            let u = simd_dot(tv, pv) * inv
            if u < 0 || u > 1 { continue }
            let qv = simd_cross(tv, e1), v = simd_dot(ld, qv) * inv
            if v < 0 || u + v > 1 { continue }
            let t = simd_dot(e2, qv) * inv
            if t > 1e-3, t <= maxT, best == nil || t < best! { best = t }
        }
        return best
    }

    // MARK: The audit

    /// The 27 aim points in a box (corners, edge and face middles, centre): the reticle can be on any of them.
    static func samples(_ it: Interactable) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for i in 0..<3 { for j in 0..<3 { for k in 0..<3 {
            out.append(it.min + (it.max - it.min) * SIMD3(Float(i) * 0.5, Float(j) * 0.5, Float(k) * 0.5))
        } } }
        return out
    }

    /// A prop is a drawn mesh that is not the ground and not a building-sized shell: the thing a player would call "the page", "the ring", "the map".
    static func isProp(_ item: DrawItem) -> Bool {
        if item.name.hasPrefix("terrain_") || item.isWaterBody { return false }
        let (lo, hi) = item.worldBounds
        return simd_reduce_max(hi - lo) <= 8
    }

    /// The small prop (if any) whose box holds the point `q`: a plate on a wall is a prop even though the ray meets the wall's own mesh at the same spot.
    static func propAt(_ q: SIMD3<Float>, scene: Scene, includeHidden: Bool) -> String? {
        for item in scene.items where isProp(item) && (!item.hidden || includeHidden) && !item.refractive {
            let (lo, hi) = item.worldBounds
            if q.x >= lo.x - 0.12 && q.x <= hi.x + 0.12 && q.y >= lo.y - 0.12 && q.y <= hi.y + 0.12 && q.z >= lo.z - 0.12 && q.z <= hi.z + 0.12 { return item.name }
        }
        return nil
    }

    /// Does a reticle ray from `eye` pick this box AND first hit a drawn prop at the box (not terrain, not something in front)?
    static func rayShowsProp(eye: SIMD3<Float>, it: Interactable, scene: Scene) -> String? { reticle(eye: eye, it: it, scene: scene)?.item }

    /// The prop the eye sees in the box and the point to put the reticle on (a vertex of it, or the spot the ray met it).
    static func reticle(eye: SIMD3<Float>, it: Interactable, scene: Scene) -> (item: String, point: SIMD3<Float>)? {
        let pad: Float = 0.3
        // The player cannot stand inside the box (its centre is not inside the footprint; the body may touch its edge).
        let nx = simd_clamp(eye.x, it.min.x, it.max.x), nz = simd_clamp(eye.z, it.min.z, it.max.z)
        if simd_length(SIMD2(eye.x - nx, eye.z - nz)) < 0.05 { return nil }
        // The props in the box (a thin ring or a sheet of paper is missed by a grid of aim points): aim at their own vertices and ask whether that vertex is the first thing the eye meets.
        for item in scene.items where isProp(item) && (!item.hidden || !it.enabled) && !item.refractive {
            let (lo, hi) = item.worldBounds
            guard lo.x <= it.max.x + pad, hi.x >= it.min.x - pad, lo.y <= it.max.y + pad, hi.y >= it.min.y - pad, lo.z <= it.max.z + pad, hi.z >= it.min.z - pad else { continue }
            let vp = item.mesh.vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
            let n = item.mesh.vertexBuffer.length / MemoryLayout<Vertex>.stride
            for i in stride(from: 0, to: n, by: max(1, n / 120)) {
                let w4 = item.uniforms.model * vp[i].position, w = SIMD3(w4.x, w4.y, w4.z)
                let inside = w.x >= it.min.x - 0.02 && w.x <= it.max.x + 0.02 && w.y >= it.min.y - 0.02 && w.y <= it.max.y + 0.02 && w.z >= it.min.z - 0.02 && w.z <= it.max.z + 0.02
                guard inside else { continue }
                let dv = w - eye, len = simd_length(dv)
                guard len > 0.05 else { continue }
                let d = dv / len
                guard let tb = Interaction.rayBox(origin: eye, dir: d, min: it.min, max: it.max), tb <= it.reach else { continue }
                // Pull the aim point a hair towards the eye so the vertex's own surface counts as the hit.
                if let h = cast(scene: scene, origin: eye, dir: d, maxT: len + 0.05, includeHidden: !it.enabled), h.t >= len - 0.08 { return (item.name, w) }
            }
        }
        for s in samples(it) {
            let dv = s - eye, len = simd_length(dv)
            guard len > 0.05 else { continue }
            let d = dv / len
            guard let tb = Interaction.rayBox(origin: eye, dir: d, min: it.min, max: it.max), tb <= it.reach else { continue }
            guard let h = cast(scene: scene, origin: eye, dir: d, maxT: it.reach + 1.0, includeHidden: !it.enabled) else { continue }
            guard h.item != "terrain", !h.item.hasPrefix("terrain_") else { continue }
            let q = eye + d * h.t
            let inside = q.x >= it.min.x - pad && q.x <= it.max.x + pad && q.y >= it.min.y - pad && q.y <= it.max.y + pad && q.z >= it.min.z - pad && q.z <= it.max.z + pad
            guard inside else { continue }
            if let item = scene.items.first(where: { $0.name == h.item }), isProp(item) { return (h.item, q) }
            if let p = propAt(q, scene: scene, includeHidden: true) { return (p, q) }
        }
        return nil
    }

    static func nearestMesh(to c: SIMD3<Float>, scene: Scene) -> (String, Float) {
        var best = ("none", Float.infinity)
        for item in scene.items where isProp(item) {
            let (lo, hi) = item.worldBounds
            if simd_length(c - simd_clamp(c, lo, hi)) > 8 { continue }
            let vp = item.mesh.vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
            let n = item.mesh.vertexBuffer.length / MemoryLayout<Vertex>.stride
            for i in 0..<n {
                let w = item.uniforms.model * vp[i].position
                let dd = simd_length(SIMD3(w.x, w.y, w.z) - c)
                if dd < best.1 { best = (item.name, dd) }
            }
        }
        return best
    }

    /// Items that are readable or usable and so need a box: pages, rings, maps, lenses, tools, the tableau's lanterns.
    static func isUsable(_ name: String) -> Bool {
        if name.range(of: #"^(ti_)?page_\d+$"#, options: .regularExpression) != nil { return true }
        return name == "ti_chain_map" || name.hasPrefix("ti_find_") || name.hasPrefix("ti_tableau_lantern_") || name == "ti_prism_ring_visual" || name == "gw_return_ring" || name == "lens_core"
            || name == "ta_return_ring_ilse" || name == "ta_return_ring_oren"
    }

    static func orphans(_ kind: WorldKind, scene: Scene, interactables: [Interactable]) -> [Orphan] {
        var out: [Orphan] = []
        for item in scene.items where isUsable(item.name) && !item.hidden {        // a hidden prop is not in the world yet: its box is audited as dormant
            let (lo, hi) = item.worldBounds
            let c = (lo + hi) / 2
            let covered = interactables.contains { it in
                it.min.x <= hi.x + 0.4 && it.max.x >= lo.x - 0.4 && it.min.y <= hi.y + 0.4 && it.max.y >= lo.y - 0.4 && it.min.z <= hi.z + 0.4 && it.max.z >= lo.z - 0.4 }
            if covered { continue }
            let near = interactables.min { simd_length((($0.min + $0.max) / 2) - c) < simd_length((($1.min + $1.max) / 2) - c) }
            out.append(Orphan(kind: kind, item: item.name, centre: c, nearestBox: near?.id ?? "none", distance: near.map { simd_length((($0.min + $0.max) / 2) - c) } ?? .infinity))
        }
        return out
    }

    static func audit(_ kind: WorldKind, scene: Scene, interactables: [Interactable]) -> Result {
        var res = Result()
        let net = Layout.Navigation.network(for: kind)
        for it in interactables {
            let centre = (it.min + it.max) / 2
            let (nm, nd) = nearestMesh(to: centre, scene: scene)
            let reach = NavigationAudit.standingPlace(for: it, scene: scene, net: net)
            var hit = "-"
            var lastEye: SIMD3<Float>?, seenEye: SIMD3<Float>?
            let seen = NavigationAudit.standingPlace(for: it, scene: scene, net: net, eyeOK: { eye in
                lastEye = eye
                if let h = rayShowsProp(eye: eye, it: it, scene: scene) { hit = h; seenEye = eye; return true }
                return false
            })
            if seen == nil, reach != nil, let eye = lastEye {                                                      // say what the player sees instead: the first thing the centre ray hits
                let d = simd_normalize(centre - eye)
                let h = cast(scene: scene, origin: eye, dir: d, maxT: it.reach + 1, includeHidden: !it.enabled)
                hit = h.map { "\($0.item) at \(String(format: "%.1f", $0.t)) m" } ?? "nothing"
            }
            res.rows.append(Row(kind: kind, id: it.id, centre: centre, nearest: nm, nearestDistance: nd, reachable: reach != nil, seen: seen != nil, stand: (seen ?? reach)?.point, hit: hit, eye: seenEye, enabled: it.enabled))
        }
        res.orphans = orphans(kind, scene: scene, interactables: interactables)
        return res
    }

    static func run(device: MTLDevice) -> [WorldKind: Result] {
        let scenes: [WorldKind: Scene] = [.varrow: Scene.make(.varrow, device: device), .glassWood: Scene.make(.glassWood, device: device), .tideArchive: Scene.make(.tideArchive, device: device)]
        let game = Game(scenes: scenes)
        var out: [WorldKind: Result] = [:]
        for which in 0..<2 { scenes[.glassWood]!.update("gw_altar_\(which == 0 ? "ilse" : "oren")") { $0.uniforms.model = GlassPuzzleProps.pedestalModel(which, rise: 1) } }          // the pedestals audited where they stand once risen
        for kind in WorldKind.allCases {
            if game.world != kind { game.travel(to: kind) }
            out[kind] = audit(kind, scene: scenes[kind]!, interactables: game.interactables)
        }
        return out
    }

    static func text(_ results: [WorldKind: Result]) -> String {
        var out = ["Interactable audit (F09.1): every interactable has a visible prop the reticle ray hits from the corridor, within reach.", ""]
        for kind in WorldKind.allCases {
            guard let r = results[kind] else { continue }
            let bad = r.rows.filter { !$0.verdict }.count
            out.append("== \(kind.rawValue): \(bad == 0 && r.orphans.isEmpty ? "ALL PASS" : "\(bad) FAIL, \(r.orphans.count) unboxed props")  (\(r.rows.count) interactables)")
            for row in r.rows {
                let c = String(format: "(%.1f, %.1f, %.1f)", row.centre.x, row.centre.y, row.centre.z)
                let s = row.stand.map { String(format: "stand (%.1f, %.1f)", $0.x, $0.y) } ?? "no stand"
                out.append("  \(row.verdict ? "PASS" : "FAIL")  \(row.id)\(row.enabled ? "" : " [dormant]")  box \(c)  nearest mesh \(row.nearest) \(String(format: "%.2f", row.nearestDistance)) m  reach \(row.reachable ? "ok" : "NO")  ray \(row.seen ? "hits \(row.hit)" : "NO PROP IN VIEW (centre ray meets \(row.hit))")  \(s)\(row.eye.map { String(format: " eye %.2f,%.2f,%.2f", $0.x, $0.y, $0.z) } ?? "")")
            }
            // F09.7 (#104): "no way out of this world": the exit back, and what the player's first visible goal is.
            let exits: [String] = kind == .glassWood ? ["gw_return"] : (kind == .tideArchive ? TideSpots.returnIDs : [])
            if exits.isEmpty { out.append("  exit to the previous world: none (the first world)") }
            else { out.append("  exit to the previous world: " + exits.map { id in "\(id) \(r.rows.first { $0.id == id }?.verdict == true ? "PASS" : "FAIL")" }.joined(separator: ", ")) }
            switch kind {
            case .varrow: out.append("  first visible goal: the lantern path to the stones (S03-player-path A4); after the lighthouse is lit, the note at its door and the guide light at Oren's lens (F09.8)")
            case .glassWood: out.append("  first visible goal: the mirror court's beam and the chimes (S03-player-path B); the ring at the arrival pad is the way back")
            case .tideArchive:
                let g = TideSpots.gate(0)
                out.append(String(format: "  first visible goal: Ilse: the guide light leads to the first gate at (%.0f, %.0f), then the next, the gallery door %@, the quay's lens; Oren: Ilse's lamps up the route to the prism ring at (%.0f, %.0f)", g.x, g.z, "(\(Int(TideSpots.galleryDoor.x)), \(Int(TideSpots.galleryDoor.y)))", TideSpots.prismRing.x, TideSpots.prismRing.z))
            }
            for o in r.orphans { out.append(String(format: "  FAIL  unboxed prop '%@' at (%.1f, %.1f, %.1f): nearest box '%@' %.1f m", o.item, o.centre.x, o.centre.y, o.centre.z, o.nearestBox, o.distance)) }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    static func main(device: MTLDevice, out: String?) -> Bool {
        let results = run(device: device)
        let t = text(results)
        print(t)
        if let out { try? t.write(toFile: out, atomically: true, encoding: .utf8); print("wrote \(out)") }
        return results.values.allSatisfy(\.ok)
    }
}
