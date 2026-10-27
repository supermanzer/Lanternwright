import Foundation
import Metal
import simd

/// M10.6: `--nav-audit [out.txt]`, and the soft-lock guard the selftest runs. For each world it checks that
///  (a) every place the player must be able to reach (`NavCoverage`: spawn, stones, door, lens, pages, mirrors, chimes, altar...) and every interactable has a standing place
///      inside the corridors that is connected to the spawn, close enough to click it;
///  (b) every vantage's target is visible from its position (a ray over the terrain and through the colliders);
///  (c) it reports the numbers the graphics side plans from: the region's area against the island's, the farthest reachable distance from the origin, and how many
///      props lie more than 20, 60 and 150 m from the region (`ReachableRegion.minDistance`).
/// No interactable may ever be unreachable: this is the guard that makes confinement (M10.4) safe to ship.
enum NavigationAudit {
    struct Report {
        var kind: WorldKind
        var failures: [String] = []
        var lines: [String] = []
        var regionArea: Float = 0, landArea: Float = 0, farthest: Float = 0
        var items = 0, over20 = 0, over60 = 0, over150 = 0
        var checkedPoints = 0, checkedInteractables = 0, checkedVantages = 0
        var ok: Bool { failures.isEmpty }
    }

    static func run(device: MTLDevice) -> [Report] {
        let scenes: [WorldKind: Scene] = [.varrow: Scene.make(.varrow, device: device), .glassWood: Scene.make(.glassWood, device: device)]
        let game = Game(scenes: scenes)
        return WorldKind.allCases.map { kind in
            if game.world != kind { game.travel(to: kind) }
            return audit(kind, scene: scenes[kind]!, interactables: game.interactables)
        }
    }

    static func audit(_ kind: WorldKind, scene: Scene, interactables: [Interactable]) -> Report {
        var r = Report(kind: kind)
        let net = Layout.Navigation.network(for: kind)
        let region = ReachableRegion.make(kind, scene: scene)
        func xz(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, p.z) }

        // (a) places the player must reach.
        for p in NavCoverage.points(for: kind, scene: scene) {
            r.checkedPoints += 1
            let sd = net.signedDistance(xz(p.position))
            if !net.isReachable(xz(p.position)) { r.failures.append("\(kind.rawValue): '\(p.name)' at (\(f(p.position.x)), \(f(p.position.z))) is not inside a corridor connected to the spawn (\(f(sd)) m from an edge)") }
            else if sd > -1.5 { r.failures.append("\(kind.rawValue): '\(p.name)' has only \(f(-sd)) m of corridor around it") }
        }
        // Every interactable: somewhere to stand inside the corridors, connected to the spawn, from which the eye is within its reach of the box.
        for it in interactables {
            r.checkedInteractables += 1
            if let s = standingPlace(for: it, scene: scene, net: net) { r.lines.append("  \(it.id): stand at (\(f(s.point.x)), \(f(s.point.y))), \(f(-s.sd)) m inside a corridor, eye \(f(s.eyeDistance)) m of reach \(f(it.reach))") }
            else { r.failures.append("\(kind.rawValue): interactable '\(it.id)' (box \(f(it.min.x)),\(f(it.min.z)) to \(f(it.max.x)),\(f(it.max.z)), reach \(f(it.reach)) m) cannot be clicked from anywhere inside the corridors") }
        }
        // (b) vantages.
        for v in net.vantages {
            r.checkedVantages += 1
            let eye = SIMD3(v.position.x, scene.groundHeight(x: v.position.x, z: v.position.y) + Player.eyeHeight, v.position.y)
            if let blocked = blockedAt(from: eye, to: v.target, scene: scene) { r.failures.append("\(kind.rawValue): vantage '\(v.name)' cannot see its target: blocked by \(blocked)") }
        }
        // (c) numbers.
        let lo = SIMD2<Float>(repeating: Terrain.origin), hi = SIMD2<Float>(repeating: -Terrain.origin)
        var land = 0, inside = 0, farthest: Float = 0
        var z = lo.y
        while z <= hi.y {
            var x = lo.x
            while x <= hi.x {
                let p = SIMD2(x, z)
                if scene.groundHeight(x: x, z: z) > 0 { land += 1 }
                if region.contains(p) && x >= region.bounds.min.x && x <= region.bounds.max.x { inside += 1; farthest = max(farthest, length(p)) }
                x += 2
            }
            z += 2
        }
        r.landArea = Float(land) * 4; r.regionArea = Float(inside) * 4; r.farthest = farthest
        r.items = scene.items.count
        for i in scene.items.indices {
            let d = region.minDistance(item: i)
            if d > 20 { r.over20 += 1 }; if d > 60 { r.over60 += 1 }; if d > 150 { r.over150 += 1 }
        }
        return r
    }

    private static func f(_ v: Float) -> String { String(format: "%.1f", v) }

    /// A place to stand for an interactable: the nearest spot to it (searched outward in 1 m rings) that is inside a corridor connected to the spawn (at least half a metre in),
    /// clear of every collider (the player's own radius included: the centre of a standing stone is not a place to stand), on ground that is dry enough and not steeper than the walking limit, with the eye within its reach of the box.
    static func standingPlace(for it: Interactable, scene: Scene, net: NavNetwork) -> (point: SIMD2<Float>, sd: Float, eyeDistance: Float)? {
        let centre = SIMD2((it.min.x + it.max.x) / 2, (it.min.z + it.max.z) / 2)
        var radius: Float = 0
        while radius <= it.reach + 1 {
            var best: (SIMD2<Float>, Float, Float)?
            for k in 0..<(radius == 0 ? 1 : 24) {
                let a = Float(k) / 24 * 2 * .pi
                let s = centre + SIMD2(cos(a), sin(a)) * radius
                let sd = net.signedDistance(s)
                guard sd <= -0.5, net.isReachable(s) else { continue }
                let ground = scene.groundHeight(x: s.x, z: s.y)
                // Standable: not in water deeper than the player may wade, and not on ground steeper than the walking limit.
                let rise = max(abs(scene.groundHeight(x: s.x + 1, z: s.y) - ground), abs(scene.groundHeight(x: s.x, z: s.y + 1) - ground))
                guard ground > Player.minGround, rise <= Player.maxSlope || scene.isOnPlatform(s) else { continue }
                guard scene.colliders.cylinders.allSatisfy({ simd_length(s - $0.center) >= $0.radius + Player.radius || ground >= $0.maxY || ground + Player.eyeHeight <= $0.minY }) else { continue }
                let eye = SIMD3(s.x, ground + Player.eyeHeight, s.y)
                let d = simd_length(eye - simd_clamp(eye, it.min, it.max))
                if d <= it.reach - 0.3, best == nil || sd < best!.1 { best = (s, sd, d) }
            }
            if let b = best { return (point: b.0, sd: b.1, eyeDistance: b.2) }          // the nearest ring that has one; the deepest inside on that ring
            radius += 1
        }
        return nil
    }

    /// What blocks the straight line from `eye` to `target`: the terrain or a collider (a description), or nil if it is clear. A collider the target itself stands in (the
    /// lighthouse's lantern room is on the tower's axis) does not count against the last part of the line.
    static func blockedAt(from eye: SIMD3<Float>, to target: SIMD3<Float>, scene: Scene) -> String? {
        let span = target - eye, n = max(Int(simd_length(span)), 2)
        for i in 1..<max(n - 3, 2) {
            let q = eye + span * (Float(i) / Float(n))
            if scene.groundHeight(x: q.x, z: q.z) > q.y { return "terrain near (\(Int(q.x)), \(Int(q.y)), \(Int(q.z)))" }
        }
        let d2 = SIMD2(span.x, span.z), e2 = SIMD2(eye.x, eye.z)
        for c in scene.colliders.cylinders {
            if simd_length(SIMD2(target.x, target.z) - c.center) < c.radius + 0.5 { continue }           // the target stands in it
            // |e2 + t d2 - centre|^2 = r^2, the first t in (0, 1) where the line enters the cylinder.
            let m = e2 - c.center
            let a = simd_dot(d2, d2), b = 2 * simd_dot(m, d2), cc = simd_dot(m, m) - c.radius * c.radius
            guard a > 1e-6 else { continue }
            let disc = b * b - 4 * a * cc
            guard disc >= 0 else { continue }
            let t0 = (-b - sqrt(disc)) / (2 * a), t1 = (-b + sqrt(disc)) / (2 * a)
            for t in [t0, t1] where t > 0 && t < 1 {
                let y = eye.y + span.y * t
                if y >= c.minY && y <= c.maxY { return "a collider at (\(Int(c.center.x)), \(Int(c.center.y))) radius \(String(format: "%.1f", c.radius)) m" }
            }
        }
        return nil
    }

    // MARK: Output

    static func text(_ reports: [Report]) -> String {
        var out = ["Navigation audit (M10.6): every place the player must reach, every interactable, every vantage, and the numbers for the graphics side.",
                   "Margin \(Player.marginWidth) m. Region = corridors and plazas plus the margin. Areas on a 2 m grid.", ""]
        for r in reports {
            out.append("== \(r.kind.rawValue): \(r.ok ? "ALL CLEAR" : "\(r.failures.count) PROBLEM(S)")")
            out.append("  checked \(r.checkedPoints) required places, \(r.checkedInteractables) interactables, \(r.checkedVantages) vantages")
            out.append(String(format: "  region %.0f m2 of %.0f m2 of dry land (%.1f %%)", r.regionArea, r.landArea, 100 * r.regionArea / max(r.landArea, 1)))
            out.append(String(format: "  farthest reachable point from the origin: %.0f m", r.farthest))
            out.append("  props (\(r.items) scene items) beyond the region: over 20 m \(r.over20), over 60 m \(r.over60), over 150 m \(r.over150)")
            for p in r.failures { out.append("  PROBLEM: \(p)") }
            out.append("  interactables:")
            out += r.lines
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    static func main(device: MTLDevice, out: String?) -> Bool {
        let reports = run(device: device)
        let t = text(reports)
        print(t)
        if let out { try? t.write(toFile: out, atomically: true, encoding: .utf8); print("wrote \(out)") }
        return reports.allSatisfy(\.ok)
    }
}
