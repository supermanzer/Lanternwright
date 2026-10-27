import Foundation
import Metal
import simd

/// Self-tests: tree trunks (F03 G3, user notes #38, #39: "I see the inside of the trunk curving away from me, rather than the outside curving towards me").
/// A trunk is only solid if its triangles are wound so that the OUTSIDE faces the viewer (the renderer culls back faces) and its normals point away from the axis.
extension SelfTestRunner {
    /// Fraction of triangles (of the given material, or all) whose winding agrees with their vertex normals, and the smallest agreeing share found.
    static func windingAgreement(_ b: MeshBuilder, material: Int? = nil) -> (agree: Int, total: Int) {
        let v = b.vertices, ix = b.indices
        var agree = 0, total = 0
        for t in stride(from: 0, to: ix.count, by: 3) {
            let a = v[Int(ix[t])], bb = v[Int(ix[t + 1])], c = v[Int(ix[t + 2])]
            if let m = material, Int(a.normal.w + 0.5) != m { continue }
            let n = simd_cross(SIMD3(bb.position.x, bb.position.y, bb.position.z) - SIMD3(a.position.x, a.position.y, a.position.z),
                               SIMD3(c.position.x, c.position.y, c.position.z) - SIMD3(a.position.x, a.position.y, a.position.z))
            let vn = SIMD3(a.normal.x, a.normal.y, a.normal.z) + SIMD3(bb.normal.x, bb.normal.y, bb.normal.z) + SIMD3(c.normal.x, c.normal.y, c.normal.z)
            total += 1
            if simd_dot(n, vn) > 0 { agree += 1 }
        }
        return (agree, total)
    }

    func runTrees() {
        guard name == "all" || name == "trees" else { return }
        // A plain tube, as the trunk builder makes one: straight, leaning and curved.
        let surf = Surface(color: SIMD3(0.3, 0.2, 0.1), roughness: 0.9, material: .bark)
        var worst = 1.0
        for pts in [[SIMD3<Float>(0, 0, 0), SIMD3(0, 3, 0)], [SIMD3(0, 0, 0), SIMD3(1, 3, 0.5)], [SIMD3(0, 0, 0), SIMD3(0.2, 1, 0), SIMD3(0.6, 2, 0.4), SIMD3(0.3, 3, 1)]] {
            var b = MeshBuilder()
            b.tube(points: pts, radii: [Float](repeating: 0.2, count: pts.count), sides: 8, surface: surf)
            let w = Self.windingAgreement(b)
            worst = min(worst, Double(w.agree) / Double(max(w.total, 1)))
        }
        check(worst > 0.999, "tube triangles are wound so the outside faces the viewer (back faces are culled): winding agrees with the vertex normals for \(String(format: "%.1f", worst * 100)) % of triangles")
        // The real trunks: every sampled trunk vertex's normal points away from the axis, at every level of detail, for pines, cypresses and snags.
        for style in [Trees.Style.pine, .cypress] {
            for lod in 0..<3 {
                let sk = Trees.Skeleton.make(seed: UInt32(1000 + 7 * lod), style: style)
                let m = Trees.conifer(seed: UInt32(1000 + 7 * lod), style: style, lod: lod)
                let axis: [(SIMD3<Float>, Float)] = (0...80).map { let t = Float($0) / 80; return (sk.trunkAt(t), sk.trunkR(t)) }
                var checked = 0, bad = 0
                for vt in m.vertices where vt.position.y > 0.1 && vt.position.y < sk.H * 0.55 {
                    let p = SIMD3(vt.position.x, vt.position.y, vt.position.z), n = SIMD3(vt.normal.x, vt.normal.y, vt.normal.z)
                    guard let a = axis.min(by: { simd_distance($0.0, p) < simd_distance($1.0, p) }), simd_distance(a.0, p) < a.1 * 1.25 + 0.02, simd_distance(a.0, p) > a.1 * 0.6 else { continue }
                    var radial = p - a.0; radial.y = 0
                    if simd_length(radial) < 1e-4 { continue }
                    checked += 1
                    if simd_dot(simd_normalize(SIMD3(n.x, 0, n.z)), simd_normalize(radial)) <= 0 { bad += 1 }
                }
                check(checked > (lod == 0 ? 20 : 1) && bad == 0, "\(style) lod \(lod): every trunk vertex's normal points away from the axis (\(checked) sampled, \(bad) pointing inward)")
                let barkId = lod == 0 ? MaterialID.bark.rawValue : MaterialID.standard.rawValue
                let w = Self.windingAgreement(m, material: Int(barkId))
                check(w.total > 0 && w.agree == w.total, "\(style) lod \(lod): trunk and branch triangles are wound outward (\(w.agree) of \(w.total))")
            }
        }
        for lod in 0..<2 {
            let m = Trees.snag(seed: 5, lod: lod)
            let w = Self.windingAgreement(m)
            check(Double(w.agree) / Double(max(w.total, 1)) > 0.999, "snag lod \(lod): triangles are wound outward (\(w.agree) of \(w.total))")
        }
    }

    /// G4 (#41): "the tree loses half its size" between the stylised far sprays and the needles. The same crown framed at the same on-screen size at several distances, once
    /// seen from the same elevation (isolating the foliage) and once from a player's eye on the ground (what the player sees).
    func runNeedles() {
        guard name == "all" || name == "needles" else { return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        func share(_ d: Float, floating: Bool, save: Bool = false) -> Float {
            Approach.foliageShare(renderer: renderer, distance: d, floating: floating, write: save && name == "needles" ? "shots/f03/g4-\(floating ? "level" : "ground")-\(Int(d)).png" : nil)
        }
        for floating in [true, false] {
            let far = share(30, floating: floating, save: true)
            var table = "30 m (sprays) \(String(format: "%.3f", far))"
            var worst: Float = 0
            for d: Float in [7, 9, 11, 13, 16, 20] {
                let s = share(d, floating: floating, save: true)
                table += ", \(Int(d)) m \(String(format: "%.3f", s))"
                if d >= 9 && d <= 13 { worst = max(worst, abs(s / max(far, 1e-4) - 1)) }
            }
            if name == "needles" { print((floating ? "level eye: " : "ground eye: ") + table) }
            let bound: Float = floating ? 0.10 : 0.16          // from the ground a steep view into a crown always shows a little less of it than the far side view does
            check(far > 0.05 && worst < bound, "the needle crown keeps the greenery of the far sprays (\(floating ? "same elevation" : "eye on the ground")): foliage share of the same crown at the same on-screen size, 9 to 13 m (needles) against 30 m (sprays), within \(Int(bound * 100)) % (worst \(String(format: "%.1f", worst * 100)) %; \(table))")
        }
    }
}
