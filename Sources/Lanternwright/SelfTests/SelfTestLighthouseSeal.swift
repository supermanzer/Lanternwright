import Foundation
import Metal
import simd

/// F09.5 (#93, #105): the lighthouse's inside is watertight, and a player cannot leave it.
///  1. SWEEP: a capsule (the player's radius and height) is pushed outward through the real wall colliders from eight places across the stair's width, at every step of the stair, round the lens room's
///     floor and round the ground room's floor (less the doorway), straight out and 0.5 rad either side; it must stay inside the shaft (its centre inside `innerR`) and over a floor.
///  2. RAYS: from points on the stair, in the lens room and in the ground room, 300 directions are cast against the tower's triangles as the renderer sees them (a back face is not drawn, so a ray
///     passes it): none may escape to the sky except through the doorway (the door leaf counts as a wall from both sides) or the lantern's glass (also).
/// Mutation: the sweep is also run on the colliders as they were before F09.5 (`legacyDoorGap`), and it must find the leak (#105).
extension SelfTestRunner {
    /// Heights (tower frame, 0.25 m bins) where a player pushed outward gets out, and how many pushes were made.
    private func sealLeaks(_ cols: Colliders, _ o: LighthouseInterior) -> (leaks: [Float], pushes: Int, skipped: Int, adjusted: Int) {
        typealias I = LighthouseInterior
        let lh = Layout.lighthouse
        var leaks: [Float] = [], n = 0, skipped = 0, adjusted = 0
        func push(angle a: Float, from r0: Float, feet h: Float) {
            for skew: Float in [-0.5, 0, 0.5] {
                let dir = SIMD2(cos(a + skew), sin(a + skew))
                var pos = SIMD2(lh.x, lh.z) + SIMD2(cos(a), sin(a)) * r0
                let feetY = lh.y + h
                var out = false
                // A start that overlaps a collider (against the wall, on a hatch post) is first moved to where the controller would put the player; one that resolves to outside the tower is no place a player can be.
                var probe = pos
                cols.resolve(position: &probe, radius: Player.radius, feetY: feetY, height: Player.eyeHeight)
                if simd_length(probe - pos) > 1e-3 { adjusted += 1 }
                if simd_length(probe - SIMD2(lh.x, lh.z)) > I.innerR(h) || o.height(x: probe.x, z: probe.y, feetY: feetY) == nil { skipped += 1; continue }
                pos = probe
                for _ in 0..<80 {
                    pos += dir * 0.05
                    cols.resolve(position: &pos, radius: Player.radius, feetY: feetY, height: Player.eyeHeight)
                    let r = simd_length(pos - SIMD2(lh.x, lh.z))
                    if r > I.innerR(h) + 0.02 || o.height(x: pos.x, z: pos.y, feetY: feetY) == nil { out = true; break }
                }
                n += 1
                if out { leaks.append((h * 4).rounded() / 4); if name == "lhseal" && h > 20 && leaks.count < 6 { print("lhseal: leak at h \(h) angle \(a) skew \(skew) r0 \(r0) final \(pos) r \(simd_length(pos - SIMD2(lh.x, lh.z)))") } }
            }
        }
        var phi = I.startAngle
        while phi < I.endAngle {
            let h = I.stairY(phi)
            for k in 0..<8 {
                let r0 = I.stairInner(h) + (I.innerR(h) - I.stairInner(h)) * (Float(k) + 0.5) / 8
                push(angle: phi, from: r0, feet: h)
            }
            phi += 0.02
        }
        // The lens room's floor all round (the hatch's angles too: the stair comes up there, the wall is the same) and the ground room's, less the doorway (south, angle pi/2).
        for k in 0..<180 {
            let a = Float(k) / 180 * 2 * .pi
            push(angle: a, from: 1.5, feet: I.lensFloorY)
            var da = abs(a - .pi / 2); if da > .pi { da = 2 * .pi - da }
            if da > 0.9 { push(angle: a, from: 2.5, feet: I.floorY) }
        }
        return (leaks, n, skipped, adjusted)
    }

    func runLighthouseSeal() {
        guard name == "all" || name == "lhseal" else { return }
        typealias I = LighthouseInterior
        let o = LighthouseInterior()
        let lh = Layout.lighthouse

        // 1. The sweep, on the colliders the game adds when the door opens.
        let fixed = sealLeaks(Colliders(cylinders: o.wallColliders(legacyDoorGap: false)), o)
        let legacy = sealLeaks(Colliders(cylinders: o.wallColliders(legacyDoorGap: true)), o)
        let legacyBins = Set(legacy.leaks).sorted()
        if name == "lhseal" { print("lhseal: sweep \(fixed.pushes) pushes; leaks now at \(Set(fixed.leaks).sorted()); the pre-F09.5 colliders leak at \(legacyBins.first.map { "\($0)" } ?? "-")...\(legacyBins.last.map { "\($0)" } ?? "-") m (\(legacy.leaks.count) pushes)") }
        check(legacy.leaks.count > 0, "lhseal: mutation: with the door gap as it was before F09.5 the sweep finds the way out (#105: \(legacy.leaks.count) of \(legacy.pushes) pushes leave the tower, at \(legacyBins.first.map { String(format: "%.2f", $0) } ?? "-")-\(legacyBins.last.map { String(format: "%.2f", $0) } ?? "-") m)")
        check(fixed.pushes > 2000 && fixed.skipped * 4 < fixed.pushes && fixed.leaks.isEmpty, "lhseal: a capsule pushed outward from eight places across the stair at every step, round the lens room and round the ground room never leaves the tower (\(fixed.pushes) pushes, \(fixed.adjusted) starts moved off a collider first, \(fixed.skipped) skipped as outside the tower, \(fixed.leaks.count) leaks, at \(Set(fixed.leaks).sorted()))")
        let game = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
        game.state.set(Game.doorOpenFlag)
        var clock = 5000.0
        var idle = InputState(); idle.move = .zero
        for _ in 0..<2 { clock += 0.05; game.advance(now: clock, input: idle) }
        let live = sealLeaks(game.scene.colliders, o)
        check(game.interiorApplied && live.leaks.isEmpty, "lhseal: and the same in the running game with the door open (\(live.pushes) pushes, \(live.leaks.count) leaks)")

        // 2. Rays.
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "lhseal: no Metal device"); return }
        let sc = Scene.makeWorld(device: device)
        let twoSided: Set<String> = ["lh_door_leaf", "lighthouse_glass"]
        let names = ["lighthouse", "lh_door_leaf", "lighthouse_glass", I.wallName, I.stairName, I.fittingsName]
        struct Tri { var a: SIMD3<Float>, e1: SIMD3<Float>, e2: SIMD3<Float>, n: SIMD3<Float>, both: Bool }
        var tris: [Tri] = []
        for nm in names {
            guard let item = sc.items.first(where: { $0.name == nm }) else { check(false, "lhseal: no item \(nm)"); return }
            let verts = item.mesh.vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: item.mesh.vertexBuffer.length / MemoryLayout<Vertex>.stride)
            let idx = item.mesh.indexBuffer.contents().bindMemory(to: UInt32.self, capacity: item.mesh.indexCount)
            let m = item.uniforms.model
            func w(_ i: UInt32) -> SIMD3<Float> { let p = m * SIMD4(verts[Int(i)].position.x, verts[Int(i)].position.y, verts[Int(i)].position.z, 1); return SIMD3(p.x, p.y, p.z) - lh }
            for t in stride(from: 0, to: item.mesh.indexCount, by: 3) {
                let a = w(idx[t]), b = w(idx[t + 1]), c = w(idx[t + 2])
                let n = simd_cross(b - a, c - a)
                if simd_length(n) < 1e-9 { continue }
                tris.append(Tri(a: a, e1: b - a, e2: c - a, n: n, both: twoSided.contains(nm)))
            }
        }
        /// Distance to the first drawn surface along the ray (tower frame), or nil.
        func cast(_ o: SIMD3<Float>, _ d: SIMD3<Float>) -> Float? {
            var best: Float?
            for t in tris {
                if !t.both && simd_dot(t.n, d) >= 0 { continue }                       // a back face is not drawn
                let p = simd_cross(d, t.e2), det = simd_dot(t.e1, p)
                if abs(det) < 1e-12 { continue }
                let inv = 1 / det, s = o - t.a, u = simd_dot(s, p) * inv
                if u < 0 || u > 1 { continue }
                let q = simd_cross(s, t.e1), v = simd_dot(d, q) * inv
                if v < 0 || u + v > 1 { continue }
                let dist = simd_dot(t.e2, q) * inv
                if dist > 1e-4 && (best == nil || dist < best!) { best = dist }
            }
            return best
        }
        let dirs: [SIMD3<Float>] = (0..<300).map { i in
            let y = 1 - 2 * (Float(i) + 0.5) / 300, r = (1 - y * y).squareRoot(), g = Float(i) * 2.399963
            return SIMD3(r * cos(g), y, r * sin(g))
        }
        var origins: [SIMD3<Float>] = []
        var phi = I.startAngle
        while phi < I.endAngle { let h = I.stairY(phi), r = (I.stairInner(h) + I.innerR(h)) / 2; origins.append(SIMD3(cos(phi) * r, h + Player.eyeHeight, sin(phi) * r)); phi += 0.35 }
        for a in stride(from: Float(0), to: 2 * .pi, by: 1.0) { origins.append(SIMD3(cos(a) * 1.2, I.lensFloorY + Player.eyeHeight, sin(a) * 1.2)); origins.append(SIMD3(cos(a) * 2.5, I.floorY + Player.eyeHeight, sin(a) * 2.5)) }
        origins.append(SIMD3(0, I.floorY + Player.eyeHeight, 0))
        var escapes: [(y: Float, from: SIMD3<Float>)] = []
        for org in origins {
            for d in dirs where cast(org, d) == nil {
                // Where it leaves the shaft: march along it until its radius passes the inside radius at its height.
                var t: Float = 0, y = org.y
                while t < 40 { let p = org + d * t; if simd_length(SIMD2(p.x, p.z)) > I.innerR(max(p.y, I.floorY)) { y = p.y; break }; t += 0.05 }
                escapes.append((y, org)); if name == "lhseal" && escapes.count < 4 { print("lhseal: escape from \(org) dir \(d) exits at y \(y)") }
            }
        }
        let rings = Set(escapes.map { ($0.y * 2).rounded() / 2 }).sorted()
        if name == "lhseal" { print("lhseal: \(origins.count) origins x \(dirs.count) rays over \(tris.count) triangles: \(escapes.count) escape; at heights \(rings)") }
        check(!tris.isEmpty && escapes.isEmpty, "lhseal: from \(origins.count) points on the stair and in both rooms, \(origins.count * dirs.count) rays all strike a drawn surface (\(escapes.count) escape to the sky, at heights \(rings))")
    }
}
