import Foundation
import Metal
import simd

/// Self-tests: world.
extension SelfTestRunner {
    func runWorld() {
        if name == "all" || name == "trees" {
            func tris(_ b: MeshBuilder) -> Int { b.indices.count / 3 }
            func mat(_ b: MeshBuilder, _ m: MaterialID) -> Int { b.vertices.filter { abs($0.normal.w - m.rawValue) < 0.01 }.count }
            let pine0 = Trees.variant(.pine, 0, lod: 0), pine1 = Trees.variant(.pine, 0, lod: 1), pine2 = Trees.variant(.pine, 0, lod: 2)
            let cyp0 = Trees.variant(.cypress, 0, lod: 0)
            check(tris(pine0) > 1500 && tris(pine0) < 14000 && tris(cyp0) > 1500 && tris(cyp0) < 14000, "a full-detail conifer is a few thousand triangles (pine \(tris(pine0)), cypress \(tris(cyp0)))")
            check(tris(pine1) > 100 && tris(pine1) < tris(pine0) / 2 && tris(pine2) > 0, "the mid level is far cheaper (\(tris(pine1)) triangles) and a far level exists (\(tris(pine2)))")
            check(mat(pine0, .bark) > 100 && mat(pine0, .foliage) > 500 && mat(pine1, .bark) == 0 && mat(pine1, .foliage) > 50, "full detail has bark and foliage materials; the mid level skips the bark pattern")
            // Structure: a trunk that flares at the root and tapers, a crown that is a mass of clumps wider than the trunk by an order of magnitude.
            // The trunk is the first tube built: 10 rings of `Trees.trunkSides` vertices, a buried ring first (F02 G1: the trunk runs straight down into the ground), then base to top (see Trees.conifer).
            func ringR(_ k: Int) -> Float {
                let ns = Trees.trunkSides
                let ring = pine0.vertices[(k * ns)..<(k * ns + ns)]
                let cx = ring.map(\.position.x).reduce(0, +) / Float(ns), cz = ring.map(\.position.z).reduce(0, +) / Float(ns)
                return ring.map { simd_length(SIMD2($0.position.x - cx, $0.position.z - cz)) }.reduce(0, +) / Float(ns)
            }
            let buriedR = ringR(0), rootR = ringR(1), midR = ringR(5), topR = ringR(9)
            check(rootR > 0.3 && rootR > midR * 1.5 && midR > topR * 1.5 && topR > 0.02 && abs(pine0.vertices[Trees.trunkSides].position.y) < 0.1 && pine0.vertices[0].position.y < -1, "the trunk flares at the root and tapers to a slender top (rings: root \(rootR) m, mid \(midR) m, top \(topR) m)")
            check(abs(buriedR - rootR) < 0.05 * rootR, "G1: the buried part of the trunk is no wider than the trunk at the ground (\(buriedR) m vs \(rootR) m): no collar, no flare")
            let crownW = pine0.vertices.filter { abs($0.normal.w - MaterialID.foliage.rawValue) < 0.01 }.map { simd_length(SIMD2($0.position.x, $0.position.z)) }.max() ?? 0
            let height = pine0.vertices.map(\.position.y).max() ?? 0
            check(crownW > 1.2 && crownW < 4.5 && height > 8 && height < 11.5, "the crown is a wide mass of boughs on a tall tree (crown radius \(crownW) m, height \(height) m)")
            check(pine0.vertices.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite && abs(simd_length(SIMD3($0.normal.x, $0.normal.y, $0.normal.z)) - 1) < 1e-2 }, "all vertices finite, all normals unit (including the bent foliage normals)")
            // Foliage normals are bent outward from the crown centre (soft volume shading), and shaded dark inside, light at the tips.
            let foliage = pine0.vertices.filter { abs($0.normal.w - MaterialID.foliage.rawValue) < 0.01 }
            let outward = foliage.filter { simd_length(SIMD2($0.position.x, $0.position.z)) > 1.5 }
            let facing = outward.filter { simd_dot(SIMD2($0.normal.x, $0.normal.z), simd_normalize(SIMD2($0.position.x, $0.position.z))) > 0 }.count
            check(!outward.isEmpty && Float(facing) / Float(outward.count) > 0.85, "foliage normals point away from the trunk (\(facing) of \(outward.count) outer vertices)")
            let lum = { (v: Vertex) in v.color.x + v.color.y + v.color.z }
            let inner = foliage.filter { simd_length(SIMD2($0.position.x, $0.position.z)) < 0.9 }.map(lum), tips = foliage.filter { simd_length(SIMD2($0.position.x, $0.position.z)) > 2.0 }.map(lum)
            check(!inner.isEmpty && !tips.isEmpty && tips.reduce(0, +) / Float(tips.count) > inner.reduce(0, +) / Float(inner.count) * 1.15, "baked shading: the crown is darker inside and lighter at the tips")
            // Variation: sixteen seeds give clearly different trees.
            let sigs = Set((0..<Trees.variantCount).map { i -> Int in let m = Trees.variant(.pine, i, lod: 0); return m.vertices.count * 31 + Int((m.vertices.map(\.position.x).reduce(0, +)) * 100) })
            check(sigs.count >= 14, "16 pine variants are genuinely different shapes (\(sigs.count) distinct)")
            check(tris(Trees.snagVariant(0, lod: 0)) > 100 && mat(Trees.snagVariant(0, lod: 0), .bark) > 50 && mat(Trees.snagVariant(0, lod: 0), .foliage) == 0, "a dead snag is bare bark with broken limbs")
            // Forest floor: litter under every placed conifer, none far from trees, and the meadow keeps its grass elsewhere.
            let terr = Scene.makeWorld(device: device).terrain!
            let sitesNow = Island.treeSites(terrain: terr).prefix(420)
            check(sitesNow.allSatisfy { terr.duffAt(x: $0.x, z: $0.y) > 0.9 }, "every conifer stands in full needle litter")
            let farFromTrees = (0..<80).map { k in SIMD2<Float>(-40 + Float(k % 10) * 9, 150 + Float(k / 10) * 9) }.filter { p in sitesNow.allSatisfy { simd_length($0 - p) > 14 } }
            check(!farFromTrees.isEmpty && farFromTrees.allSatisfy { terr.duffAt(x: $0.x, z: $0.y) < 0.01 }, "there is no litter away from trees (\(farFromTrees.count) places checked)")
            let radii = Island.duffDiscs(terrain: terr).map(\.r)
            check(radii.min()! > 3 && radii.max()! < 9, "litter discs follow the trees' size (radius \(radii.min()!)-\(radii.max()!) m)")
            // LOD selection in a real scene: exactly one level of each group is visible, chosen by distance to its footprint.
            let sc = Scene.makeWorld(device: device)
            check(sc.lodGroups.count > 10 && sc.lodGroups.allSatisfy { $0.names.count == 3 }, "tree cells have three levels each (\(sc.lodGroups.count) cells)")
            let g0 = sc.lodGroups[sc.lodGroups.count / 2]
            func visibleLevel(_ eye: SIMD3<Float>) -> [Int] {
                sc.applyLOD(eye: eye)
                return g0.names.enumerated().filter { n in !(sc.items.first { $0.name == n.element }?.hidden ?? true) }.map(\.offset)
            }
            let c = (g0.min + g0.max) / 2
            check(visibleLevel(SIMD3(c.x, 0, c.y)).contains(0) && !visibleLevel(SIMD3(c.x, 0, c.y)).contains(2), "standing in a cell shows its full-detail trees (and the mid level for its far corner), never the cones")
            check(visibleLevel(SIMD3(c.x + 60 + 80, 0, c.y)).contains(1) && !visibleLevel(SIMD3(c.x + 60 + 80, 0, c.y)).contains(0), "80 m beyond a cell's edge shows the mid level, not the full-detail one")
            check(visibleLevel(SIMD3(c.x + 60 + 400, 0, c.y)) == [2], "far away shows only the cone silhouettes")
            var oneEach = true
            for k in 0..<40 {
                let eye = SIMD3<Float>(-300 + Float(k) * 17, 0, -300 + Float(k * k % 600))
                sc.applyLOD(eye: eye)
                for grp in sc.lodGroups { // at least one level, and no gap (a cell's trees span ~85 m, so all three can be needed)
                let vis = grp.names.enumerated().filter { n in !(sc.items.first { $0.name == n.element }?.hidden ?? true) }.map(\.offset); if vis.isEmpty || vis.last! - vis.first! != vis.count - 1 { oneEach = false } }
            }
            check(oneEach, "from any eye position every tree cell draws at least one level and the drawn levels are contiguous")
            // The cross-fade itself: complementary by construction (a pixel belongs to exactly one level), and it moves from level 0 to 2 with distance.
            let lv: (Float) -> Float = { d in smoothstep(45 - 3.4, 45 + 3.4, d) + smoothstep(130 - 9.75, 130 + 9.75, d) }
            check(lv(20) == 0 && lv(90) == 1 && lv(200) == 2 && lv(30) < lv(45) && lv(45) < lv(60), "the level coordinate rises 0 to 2 with distance (45 m and 130 m, each over a band)")
            let drawnNear = Scene.lodLevelsDrawn(boxDistance: 0, diagonal: 85), drawnFar = Scene.lodLevelsDrawn(boxDistance: 300, diagonal: 85)
            check(drawnNear == [true, true, false] && drawnFar == [false, false, true], "a cell draws the levels its trees can need (near: full+mid, far: cones only)")
            sc.applyLOD(eye: SIMD3(0, 0, 0))
        }
        if name == "all" || name == "dock" {
            // F01 W2: the dock is weathered and chaotic, and deterministic (the same seed gives the same boards).
            func dockMesh(_ sc: Scene) -> Mesh { sc.items.first { $0.name == "dock" }!.mesh }
            let a = Scene.makeWorld(device: device), b2 = Scene.makeWorld(device: device)
            check(dockMesh(a).indexCount == dockMesh(b2).indexCount && dockMesh(a).indexCount > 3000, "the dock is built identically every time (\(dockMesh(a).indexCount / 3) triangles)")
            var rebuilt = MeshBuilder(); _ = rebuilt
            let probe = Scene.makeWorld(device: device)
            check(probe.items.first { $0.name == "dock" } != nil, "the dock exists")
            check(!probe.items.contains { $0.name == "material_sheet" } && Props.includeMaterialSheet == false, "F03 R1: the debug material sheet (a gallery floating 900 m north, visible from the north shore as a strip of colour) is not in the game; only --view material-sheet builds it")
        }
        if name == "all" || name == "dockfurniture" {
            let src = MaterialShaders.source
            // R11: the mooring post is not a clean cylinder, the rope touches it, the cleat is a horn cleat. Several posts, as the dock builds them.
            var posts: [DockFurniture.Post] = []
            for i in 0..<6 {
                let sx: Float = i % 2 == 0 ? -1.1 : 1.1
                posts.append(DockFurniture.Post(x: sx, z: 0.8 + 8 * Float(i / 2), top: 1.55 - 0.1 * Float(i), seed: Int32(i)))
            }
            let meshes = posts.map { DockFurniture.postMesh($0) }
            func finite(_ b: MeshBuilder) -> Bool { b.vertices.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite && abs(simd_length(SIMD3($0.normal.x, $0.normal.y, $0.normal.z)) - 1) < 1e-2 } }
            check(meshes.allSatisfy(finite), "post meshes have finite positions and unit normals")
            check(meshes.allSatisfy { $0.vertices.allSatisfy { Int($0.normal.w + 0.5) == 24 } } && meshes.allSatisfy { $0.vertices.contains { $0.normal.w > 24.3 } && $0.vertices.contains { $0.normal.w < 23.7 } },
                  "post vertices use material 24 and carry the angle round the shaft (-1...1) in the id fraction")
            // Silhouette: radius varies round and along the shaft by well over the facet error of a cylinder, and the axis leans a degree or two.
            var worstRatio: Float = 99, bestRatio: Float = 0
            for p in posts {
                var lo: Float = 9, hi: Float = 0
                var y: Float = 0.2; while y < p.top - 0.1 { for k in 0..<36 { let r = p.radius(y, Float(k) / 36 * 2 * .pi); lo = min(lo, r); hi = max(hi, r) }; y += 0.1 }
                worstRatio = min(worstRatio, hi / lo); bestRatio = max(bestRatio, hi / lo)
            }
            check(worstRatio > 1.08, "every post's silhouette is irregular: max/min shaft radius at least 1.08 (least \(String(format: "%.3f", worstRatio)))")
            let leans = posts.map { atan(simd_length($0.lean)) * 180 / .pi }
            check(leans.allSatisfy { $0 >= 0.95 && $0 <= 2.05 }, "posts lean one to two degrees (\(leans.map { String(format: "%.2f", $0) }.joined(separator: ", ")))")
            // Smooth silhouette: neighbouring samples differ by millimetres, so no stair-steps in the outline.
            var worstStep: Float = 0
            for p in posts {
                var y: Float = 0.1; while y < p.top - 0.1 {
                    for k in 0..<64 {
                        let th = Float(k) / 64 * 2 * .pi
                        worstStep = max(worstStep, abs(p.radius(y, th) - p.radius(y, th + 2 * .pi / 64)), abs(p.radius(y, th) - p.radius(y + 0.05, th)))
                    }
                    y += 0.05
                }
            }
            check(worstStep < 0.003, "the radius changes smoothly round and along the shaft (largest step \(String(format: "%.2f", worstStep * 1000)) mm between neighbouring samples)")
            // The cap: end grain in the vertex alpha (0 at the middle, up to 1 at the rim), a worn irregular top, splinter-free but never flat.
            let capHeights = posts.map { p -> Float in
                let ys = (0..<36).map { p.capY(Float($0) / 36 * 2 * .pi, 0.95) }; return ys.max()! - ys.min()!
            }
            check(capHeights.allSatisfy { $0 > 0.015 }, "the cap's rim is uneven by at least 1.5 cm (least \(String(format: "%.1f", capHeights.min()! * 100)) cm)")
            var alphaOK = true
            for m in meshes {
                let al: [Float] = m.vertices.map { $0.color.w }
                if !(al.contains(0) && al.contains { $0 > 1.5 } && al.allSatisfy { $0 >= 0 }) { alphaOK = false }
            }
            check(alphaOK, "cap vertices carry radius fractions from 0, shaft vertices carry 1 + depth below the cap")
            // The rope: every turn touches the shaft (centreline at post radius + rope radius, within 5 mm of the true surface offset), the turns touch each other.
            var worstGap: Float = 0, worstTurn: Float = 0, turnsN = 0
            for p in posts {
                let coil = DockFurniture.coilCentreline(p)
                turnsN += coil.points.count
                for c in coil.points.dropFirst(8) {                                                          // (the first few samples sink into the shaft on purpose)
                    var best: Float = 9
                    var y = c.y - 0.05; while y <= c.y + 0.05 { for k in 0..<180 { best = min(best, simd_distance(c, p.surfacePoint(y, Float(k) / 180 * 2 * .pi))) }; y += 0.005 }
                    worstGap = max(worstGap, abs(best - DockFurniture.ropeRadius))
                }
                for k in 0..<(coil.points.count - coil.perTurn) {                                          // the same angle one turn lower
                    let a = coil.points[k], b = coil.points[k + coil.perTurn]
                    worstTurn = max(worstTurn, simd_length(a - b) - 2 * DockFurniture.ropeRadius)
                }
            }
            check(turnsN > 300 && worstGap < 0.006, "the rope touches the post all the way round: its centreline lies one rope radius off the surface, worst error \(String(format: "%.1f", worstGap * 1000)) mm")
            check(worstTurn < 0.012, "each turn lies against the one below it (gap at most \(String(format: "%.1f", worstTurn * 1000)) mm)")
            let rope = DockFurniture.ropeMesh(posts[0])
            let ys: [Float] = rope.vertices.map { $0.position.y }
            let ropeVerts = rope.vertices.filter { Int($0.normal.w + 0.5) == 25 }
            let ropeAlphaOK = ropeVerts.allSatisfy { $0.color.w >= 0 && $0.color.w <= 1.0001 }
            check(finite(rope) && !ropeVerts.isEmpty && ropeAlphaOK, "the rope is material 25 with its length along it in the alpha (never above 1 = \(DockFurniture.ropeScale) m)")
            check(ys.min()! < posts[0].top - 0.118 - 0.25, "the loose end hangs at least 25 cm below the first turn")
            // Seam: duplicated columns leave no gap in the surface.
            let nuPlus1 = 17, pv = meshes[0].vertices
            var seamGap: Float = 0
            for j in 0..<(pv.count / nuPlus1) {
                let a = pv[j * nuPlus1].position, b = pv[j * nuPlus1 + 16].position
                seamGap = max(seamGap, simd_length(SIMD3(a.x - b.x, a.y - b.y, a.z - b.z)))
            }
            check(pv.count % nuPlus1 == 0 && seamGap < 1e-4, "the post's seam closes: the first and last columns of every ring coincide")
            // The cleat: two horns on a bolted foot, about 27 cm long, low, tapering toward the tips.
            let cleat = DockFurniture.cleatMesh(seed: 1)
            let czs = cleat.vertices.map(\.position.z), cys = cleat.vertices.map(\.position.y)
            let barWidth = { (lo: Float, hi: Float) -> Float in
                let xs = cleat.vertices.filter { $0.position.y > 0.03 && abs($0.position.z) >= lo && abs($0.position.z) < hi }.map(\.position.x); return (xs.max() ?? 0) - (xs.min() ?? 0) }
            check(finite(cleat) && czs.max()! - czs.min()! > 0.25 && czs.max()! - czs.min()! < 0.32 && cys.max()! < 0.075,
                  "the cleat is a horn cleat about 27 cm long and under 7.5 cm tall")
            check(barWidth(0, 0.03) > 1.5 * barWidth(0.115, 0.14), "the horns taper: the bar is at least 1.5x wider at the waist than near the tips")
            check(cleat.vertices.filter { Int($0.normal.w + 0.5) == 7 && $0.position.y > 0.007 && $0.position.y < 0.013 && abs($0.position.z) > 0.055 && abs($0.position.z) < 0.085 }.count > 20,
                  "bolt heads and washers sit on both ends of the foot")
            // One grain function serves the deck boards and the posts (so both read as the same timber).
            check(src.components(separatedBy: "wood_grain(").count - 1 >= 3 && src.contains("id == 24") && src.contains("id == 25"), "the plank and post materials share wood_grain; ids 24 and 25 are dispatched")
            check(MaterialID.post.rawValue == 24 && MaterialID.rope.rawValue == 25, "post and rope material ids are 24 and 25")
        }
        if name == "all" || name == "dockboards" {
            // F02 G4 (#32): the deck boards are sawn by hand, not drawn with a ruler.
            let surf = Surface(color: SIMD3(0.3, 0.2, 0.1), roughness: 0.5, material: .plank)
            var wobbly = 0, skewed = 0, chipped = 0, lifted = 0, encoded = 0, total = 0
            var minNormW: Float = 99, maxNormW: Float = -99
            for k in 0..<80 {
                let depth: Float = 0.15 + 0.12 * Island.noise.unit(Int32(k), 101), w: Float = 2.3
                let bd = Landmarks.sawnBoard(k: Int32(k), w: w, depth: depth, thick: 0.05, chamfer: 0.016, cup: 0.003, bow: 0.002, surface: surf)
                total += 1
                // the +z long edge: the z of the perimeter points whose z is near +depth/2, along the board
                let longEdge = bd.outline.filter { $0.y > depth / 2 - 0.02 && abs($0.x) < w / 2 - 0.1 }.map(\.y)
                if let lo = longEdge.min(), let hi = longEdge.max(), hi - lo >= 0.002 { wobbly += 1 }
                let leftEnd = bd.outline.filter { $0.x < -w / 2 + 0.04 }.map(\.x), rightEnd = bd.outline.filter { $0.x > w / 2 - 0.04 }.map(\.x)
                if (leftEnd.max() ?? 0) - (leftEnd.min() ?? 0) > 0.004 || (rightEnd.max() ?? 0) - (rightEnd.min() ?? 0) > 0.004 { skewed += 1 }
                if (leftEnd.max() ?? -w / 2) > -w / 2 + 0.02 || (rightEnd.min() ?? w / 2) < w / 2 - 0.02 { chipped += 1 }
                if bd.lift >= 0.004 { lifted += 1 }
                for v in bd.mesh.vertices { minNormW = min(minNormW, v.normal.w); maxNormW = max(maxNormW, v.normal.w) }
                if bd.mesh.vertices.contains(where: { $0.normal.w > 12.2 }) && bd.mesh.vertices.contains(where: { $0.normal.w < 11.8 }) { encoded += 1 }
                if k == 0 { check(bd.mesh.indices.count / 3 > 200 && bd.mesh.indices.count / 3 < 700, "a deck board is a few hundred triangles (\(bd.mesh.indices.count / 3))") }
            }
            check(wobbly >= 70, "the long edges are sawn, not ruled: at least 2 mm of wobble along them on \(wobbly) of \(total) boards")
            check(skewed >= 50, "the ends are cut off square on \(skewed) of \(total) boards (over 4 mm across the width)")
            check(chipped >= 15 && chipped <= 60, "corners are splintered off on \(chipped) of \(total) boards (over 2 cm)")
            check(lifted >= 3 && lifted <= 14, "a corner is lifted 4 mm or more on \(lifted) of \(total) boards")
            check(minNormW >= 11.55 && maxNormW <= 12.45 && encoded >= 60, "every board vertex carries its cross coordinate in the material id (12 +- 0.4: \(minNormW) to \(maxNormW)), so the grain runs along its own board")
            let gaps = (0..<400).map { Landmarks.deckGap(Int32($0)) }
            let jammed = gaps.filter { $0 == 0 }.count, sprung = gaps.filter { $0 >= 0.03 }.count
            check(Float(jammed) / 400 > 0.07 && Float(jammed) / 400 < 0.17 && Float(sprung) / 400 > 0.04 && Float(sprung) / 400 < 0.12 && Set(gaps.map { Int($0 * 1000) }).count > 15,
                  "the gaps are uneven: \(jammed) of 400 boards jammed tight, \(sprung) sprung 3 cm or more, and many sizes between")
            let kinds = (0..<400).map { Landmarks.nailRoll(Int32($0)) }
            let nk = [kinds.filter { $0 < 0.5 }.count, kinds.filter { $0 >= 0.5 && $0 < 0.75 }.count, kinds.filter { $0 >= 0.75 && $0 < 0.88 }.count, kinds.filter { $0 >= 0.88 }.count]
            check(nk.allSatisfy { $0 > 15 }, "nails are round-headed, square-cut, worked loose or sunk (\(nk) of 400), never one repeated octagon")
            let src = MaterialShaders.source
            check(src.lowercased().contains("flat-sawn") && src.contains("float dpt =") && !src.contains("ringPos += knot * 5.0"), "the plank grain is the flat-sawn arch model (a pith depth that varies along the board), not the old concentric-ring one with swirling knots")
        }
        if name == "all" || name == "needles" {
            // F02 T66.13: needle-level conifer foliage (near level only; the stylised sprays stay as the foliage of every other level).
            func finite(_ b: MeshBuilder) -> Bool { b.vertices.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite && abs(simd_length(SIMD3($0.normal.x, $0.normal.y, $0.normal.z)) - 1) < 1e-2 } }
            for style in [Trees.Style.pine, .cypress] {
                let nd = Trees.needleVariant(style, 0), l0 = Trees.variant(style, 0, lod: 0)
                let cards = nd.vertices.count / 4
                check(cards >= 600 && cards <= 6000 && nd.indices.count / 3 == cards * 2, "\(style) needle level: \(cards) cards (\(nd.indices.count / 3) triangles), a few hundred to a few thousand")
                check(nd.vertices.allSatisfy { $0.normal.w >= 22.55 && $0.normal.w <= 23.45 && $0.color.w >= -1e-4 && $0.color.w <= 1 + 1e-4 } && finite(nd), "\(style) needles: every vertex is material 23 with its card coordinates (v in the id's fraction, u in the alpha), finite and unit normals")
                let sn = Trees.silhouette(nd), s0 = Trees.silhouette(l0)
                check(sn.rad < 1.2 * s0.rad && sn.rad > 0.82 * s0.rad && sn.top < 1.1 * s0.top && sn.top > 0.9 * s0.top, "\(style) needles sit on the same branches: widest radius \(String(format: "%.2f", sn.rad)) m against the sprays' \(String(format: "%.2f", s0.rad)) m, height \(String(format: "%.2f", sn.top)) vs \(String(format: "%.2f", s0.top)) m")
            }
            let sc = Scene.makeWorld(device: device)
            let needleItems = sc.items.filter { $0.name.hasPrefix("needles_") }
            let treeCells = sc.items.filter { $0.name.hasPrefix("trees_L0_") }
            check(needleItems.count > 10 && needleItems.count <= treeCells.count && needleItems.allSatisfy { $0.uniforms.lod.w > 0.5 && $0.uniforms.lod.x > 0.5 && $0.uniforms.lod.y < 0.5 }, "every tree cell has its needle cards as a near-level extra flagged lod.w = 1 (\(needleItems.count) of \(treeCells.count) cells)")
            check(sc.lodGroups.allSatisfy { g in g.extras.filter { $0.hasPrefix("needles_") }.count <= 1 } && sc.lodGroups.contains { $0.extras.contains { $0.hasPrefix("needles_") } }, "the needles are drawn wherever level 0 is (they are in the cell's extras)")
            // The dissolve: spray foliage of level 0 and the needle cards are dithered complementarily with one noise value, and needles are two-sided, alpha-tested, never in the shadow pass.
            let lit = LitShaders.source, common = CommonShaders.source
            check(lit.contains("ign(px2) >= nW") && lit.contains("ign(px2) < nW") && lit.contains("midN == 3") && lit.contains("needle_cover(") && lit.contains("needle_threshold(") && common.contains("needle_weight"), "the shader dissolves needles and the level-0 sprays complementarily (one noise value, opposite tests) and alpha-tests the needle pattern")
            let r = try? String(contentsOfFile: "Sources/Lanternwright/Render/Renderer.swift", encoding: .utf8)
            check(r?.contains("item.uniforms.lod.w < 0.5, sunFrustum") == true && r?.contains("item.uniforms.lod.w > 0.5 ? .none : .back") == true, "needle cards are drawn two-sided and cast no shadow")
            // needle_weight in Swift terms: 1 inside about 13 m, 0 beyond about 17 m, for the nominal tree.
            func nw(_ d: Float) -> Float { 1 - smoothstep(13 - 2, 13 + 2, d) }
            check(nw(5) == 1 && nw(20) == 0 && nw(13) > 0.4 && nw(13) < 0.6, "the needle level covers the first 13 m and is gone by 17 m")
        }
        if name == "all" || name == "placement" {
            // F01 W3.5/W3.6: nothing placed on the ground floats. Every recorded piece (cones, twigs, pebbles, shells, driftwood, rocks, lantern and trunk
            // footings) has its lowest vertices within a few centimetres of the terrain under them, or embedded by no more than the kind allows.
            let sc = Scene.makeWorld(device: device)
            // `touching` = the least embedded of a piece's lowest vertices (must not be in the air, and only shallowly buried); the uphill side may be deeper.
            let tol: [String: Float] = ["cone": 0.10, "twig": 0.10, "pebble": 0.15, "shell": 0.10, "driftwood": 0.15, "rock": 1.2, "lantern": 0.45, "trunk": 4.0, "pillar": 0.25]
            let hover: [String: Float] = ["cone": 0.05, "twig": 0.05, "pebble": 0.08, "shell": 0.05, "driftwood": 0.05, "rock": 0.07, "lantern": 0.03, "trunk": -0.3, "pillar": 0.03]     // how far the least embedded low vertex may be in the air
            var worstUp: [String: Float] = [:], worstDown: [String: Float] = [:], counts: [String: Int] = [:]
            for p in sc.placed {
                let g = Placement.contact(p, terrain: sc.terrain)
                counts[p.kind, default: 0] += 1
                worstUp[p.kind] = max(worstUp[p.kind] ?? -9, g.touching)
                worstDown[p.kind] = min(worstDown[p.kind] ?? 9, g.touching)
            }
            check(["cone", "twig", "pebble", "shell", "driftwood", "rock", "lantern", "trunk"].allSatisfy { (counts[$0] ?? 0) > 5 } && (counts["pillar"] ?? 0) == 1, "every kind of placed piece is recorded (\(counts))")
            for (kind, t) in tol.sorted(by: { $0.key < $1.key }) {
                let up = worstUp[kind] ?? 0, down = worstDown[kind] ?? 0
                check(up <= (hover[kind] ?? 0.03) && down >= -t, "\(kind): nothing hovers (largest gap \(up) m) and the downhill side is embedded by at most \(t) m (deepest \(down) m) over \(counts[kind] ?? 0) pieces")
            }
        }
        if name == "treelod" {
            func ext(_ m: MeshBuilder) -> (top: Float, rad: Float, r50: Float, base: SIMD2<Float>) {
                let pts = m.vertices.map { SIMD3($0.position.x, $0.position.y, $0.position.z) }.filter { $0.y > -0.5 }
                let top = pts.map(\.y).max() ?? 0
                func radAt(_ lo: Float, _ hi: Float) -> Float { pts.filter { $0.y >= lo * top && $0.y <= hi * top }.map { simd_length(SIMD2($0.x, $0.z)) }.max() ?? 0 }
                let low = pts.filter { $0.y < 0.2 }
                let c = low.isEmpty ? SIMD2<Float>(0, 0) : low.reduce(SIMD2<Float>(0, 0)) { $0 + SIMD2($1.x, $1.z) } / Float(low.count)
                return (top, radAt(0, 1), radAt(0.4, 0.6), c)
            }
            for style in [Trees.Style.pine, .cypress] {
                for v in 0..<Trees.variantCount {
                    var line = "\(style) v\(v): "
                    for lod in 0..<3 { let e = ext(Trees.variant(style, v, lod: lod)); line += String(format: "L%d top %.2f rad %.2f r@50%% %.2f | ", lod, e.top, e.rad, e.r50) }
                    print(line)
                }
            }
        }
        if name == "poolprofile" {
            let gw = Scene.make(.glassWood, device: device)
            for deg in stride(from: 0, to: 360, by: 45) {
                let a = Float(deg) * .pi / 180
                var line = "dir \(deg): "
                for r in stride(from: 14, through: 48, by: 2) {
                    let x = GlassTerrain.pool.x + cos(a) * Float(r), z = GlassTerrain.pool.y + sin(a) * Float(r)
                    line += String(format: "%.1f ", gw.terrain.sampleHeight(x: x, z: z))
                }
                print(line)
            }
        }
        if name == "all" || name == "pillar" {
            // F02 G2: the broken islet pillar. Flat ground and a 12 % slope: the fallen piece never overlaps the stump or its footing (2 cm clear), its lowest
            // vertex is within 2 cm of the ground, and the break is a real fracture (not a flat cap) that both pieces share.
            for (label, slope) in [("flat", Float(0)), ("sloped", Float(0.12))] {
                let ground: (Float, Float) -> Float = { x, z in slope * x }
                let centre = SIMD3<Float>(-4.0, ground(-4.0, 3.0), 3.0)
                let rb: Float = 0.6, rt: Float = 0.4, h: Float = 3.0, yaw: Float = 0.7
                let r = BrokenPillar.build(index: 3, centre: centre, yaw: yaw, h: h, rb: rb, rt: rt, outward: 2.5, ground: ground)
                let inv = (translation(centre) * rotationY(yaw)).inverse
                var inside = 0, lowest: Float = .infinity
                for v in r.fallen.vertices {
                    let w = SIMD3(v.position.x, v.position.y, v.position.z)
                    let q = inv * SIMD4(w, 1)
                    let footing = abs(q.x) < r.footingHalf + 0.02 && abs(q.z) < r.footingHalf + 0.02 && q.y > -0.195 && q.y < 0.195
                    let stump = simd_length(SIMD2(q.x, q.z)) < rb + 0.02 && q.y > 0.0 && q.y < r.stumpTopY + 0.1
                    if footing || stump { inside += 1 }
                    lowest = min(lowest, w.y - ground(w.x, w.z))
                }
                check(inside == 0, "pillar (\(label) ground): no vertex of the fallen piece lies inside the stump or its footing (\(inside) of \(r.fallen.vertices.count))")
                check(abs(lowest + 0.015) < 0.02, "pillar (\(label) ground): the fallen piece's lowest vertex rests on the ground (gap \(lowest) m)")
            }
            let r = BrokenPillar.build(index: 3, centre: SIMD3(-4, 0, 3), yaw: 0.7, h: 3, rb: 0.6, rt: 0.4, outward: 2.5, ground: { _, _ in 0 })
            let top = r.stump.vertices.map(\.position.y).filter { $0 > 1.0 }
            check(top.max()! - top.min()! > 0.06 && top.max()! - top.min()! < 0.45, "the stump's top is a rough, oblique fracture, not a flat cap (relief \(top.max()! - top.min()!) m)")
            let facets = Set(r.stump.vertices.filter { $0.position.y > 1.0 }.map { String(format: "%.3f", $0.position.y) }).count
            check(facets > 30, "the break has many distinct heights (\(facets)): jagged, not laser-cut")
            check(r.fallen.vertices.contains { abs($0.normal.w - MaterialID.rock.rawValue) < 0.01 } && r.chips.vertices.count > 50, "fresh break faces use the rough pale rock material and chips lie around")
        }
        if name == "all" || name == "r06" {
            func tris(_ b: MeshBuilder) -> Int { b.indices.count / 3 }
            func finite(_ b: MeshBuilder) -> Bool { b.vertices.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite && abs(simd_length(SIMD3($0.normal.x, $0.normal.y, $0.normal.z)) - 1) < 1e-2 } }
            // The new procedural materials are dispatched by id in the shader (Materials.swift), so the ids must match the Swift enum.
            let src = MaterialShaders.source
            let ids: [(MaterialID, Float)] = [(.plank, 12), (.timber, 13), (.glyphStone, 14), (.paper, 15), (.pebble, 16), (.glassStone, 17), (.mirror, 18), (.paleMetal, 19), (.glyphGlass, 20)]
            check(ids.allSatisfy { $0.0.rawValue == $0.1 }, "material ids 12-20 are what the shader expects")
            check([12, 13, 15, 17, 18, 19].allSatisfy { src.contains("id == \($0)") } && src.contains("id == 14") && src.contains("id == 16") && src.contains("id == 20"), "the shader dispatches every new material id")
            // The journal page: a thin sheet with a curled corner, a pebble, finite normals; shared by both worlds.
            let page = PuzzleProps.pageMesh()
            let xs = page.vertices.map(\.position.x), ys = page.vertices.map(\.position.y), zs = page.vertices.map(\.position.z)
            check(finite(page) && xs.min()! > -0.2 && xs.max()! < 0.2 && zs.min()! > -0.26 && zs.max()! < 0.26, "the page is a 34 x 46 cm sheet")
            check(ys.max()! - ys.min()! > 0.02 && ys.max()! - ys.min()! < 0.08, "it is curled and creased, not flat and not a tent (relief \(ys.max()! - ys.min()!) m)")
            check(page.vertices.contains { abs($0.normal.w - MaterialID.paper.rawValue) < 0.01 } && page.vertices.contains { abs($0.normal.w - MaterialID.pebble.rawValue) < 0.01 }, "it has paper and a pebble weighting it")
            // Crystal trees: three LODs, strictly cheaper, a self-lit vein near, different variants, sane size.
            let t0 = CrystalTrees.variant(0, lod: 0), t1 = CrystalTrees.variant(0, lod: 1), t2 = CrystalTrees.variant(0, lod: 2)
            check(tris(t0) > tris(t1) && tris(t1) > tris(t2) && tris(t2) > 40 && tris(t0) < 6000, "crystal tree LODs get cheaper (\(tris(t0)) / \(tris(t1)) / \(tris(t2)) triangles)")
            check(finite(t0) && finite(t1) && finite(t2), "crystal tree vertices and normals are finite and unit")
            let veinNear = t0.vertices.filter { $0.color.w > 0.5 }.count, veinFar = t2.vertices.filter { $0.color.w > 0.5 }.count
            check(veinNear > 20 && veinFar == 0, "the trunk vein is self-lit up close (vertex alpha) and absent at the far level")
            let top = t0.vertices.map(\.position.y).max()!, spread = t0.vertices.map { simd_length(SIMD2($0.position.x, $0.position.z)) }.max()!
            check(top > 7 && top < 14 && spread > 1.5 && spread < 6, "a crystal tree is a tall tree with a spreading crown (height \(top), crown radius \(spread) m)")
            let sigs = Set((0..<CrystalTrees.variantCount).map { i -> Int in let m = CrystalTrees.variant(i, lod: 0); return m.vertices.count * 31 + Int(m.vertices.map(\.position.x).reduce(0, +) * 100) })
            check(sigs.count >= 8, "the crystal tree variants are genuinely different (\(sigs.count) distinct of \(CrystalTrees.variantCount))")
            // The Glass Wood forest uses LOD cells like the conifers, and the stones' faces are their own objects carrying the glyph glow.
            let gw = GlassWood.build(device: device)
            check(gw.lodGroups.count > 3 && gw.lodGroups.allSatisfy { $0.names.count == 3 && $0.names.allSatisfy { n in gw.items.first { $0.name == n }?.refractive == true } }, "crystal tree cells have three refractive levels each (\(gw.lodGroups.count) cells)")
            check(gw.has("gw_tufts") && gw.has("gw_altar_glow") && gw.has("gw_mural_glyph_0") && gw.has("gw_chime_mural_glyph_2"), "the path tufts, altar glow and both murals' carved panels exist")
            let island = Scene.makeWorld(device: device)
            check(StoneID.allCases.allSatisfy { island.has("stone_\($0.name)_face") && island.has("stone_\($0.name)") }, "each resonance stone is a plinth plus a face object (the face carries the glyph glow)")
            let faceOf = { (id: StoneID) in island.items.first { $0.name == "stone_\(id.name)_face" }!.uniforms }
            check(faceOf(.tide).tint.w == 0 && faceOf(.wind).tint.w == 1 && faceOf(.summit).tint.w == 2, "the face object's tint.w selects its glyph (tide 0, wind 1, summit 2)")
        }
        if name == "all" || name == "surfacemix" {
            let sc = Scene.makeWorld(device: device)
            func mixAt(_ x: Float, _ z: Float) -> StepMix { sc.surfaceMix(x: x, z: z).mix }
            func dominant(_ m: StepMix) -> StepMaterial { StepMaterial.allCases.max { m[$0.rawValue] < m[$1.rawValue] }! }
            let strip = Layout.dockStrip()
            let dir = simd_normalize(strip.b - strip.a)
            func onDock(_ s: Float) -> SIMD2<Float> { strip.a + dir * s }
            let mid = onDock(simd_length(strip.b - strip.a) * 0.5)
            check(mixAt(mid.x, mid.y)[StepMaterial.wood.rawValue] > 0.99 && dominant(mixAt(mid.x, mid.y)) == .wood, "surface mix: the middle of the dock is all planks")
            // Walking off the dock's landward end: wood fades out over a metre or two, sand/grass fades in, never an abrupt flip.
            var woodRamp: [Float] = []
            for k in 0..<12 { let q = onDock(-0.2 + Float(k) * 0.25 + 0.0); woodRamp.append(mixAt(q.x, q.y)[StepMaterial.wood.rawValue]) }
            check(zip(woodRamp, woodRamp.dropFirst()).allSatisfy { $0 <= $1 + 1e-4 } && woodRamp.first! < 0.1 && woodRamp.last! > 0.6, "surface mix: planks fade in over the first metres of the dock (\(woodRamp.map { String(format: "%.2f", $0) }.joined(separator: " ")))")
            check(zip(woodRamp, woodRamp.dropFirst()).allSatisfy { abs($1 - $0) < 0.45 }, "surface mix: no single step on the dock's end changes the planks' weight by more than 45 %")
            // The beach: wet sand near the waterline, dry sand higher.
            var wetPt: SIMD2<Float>?, dryPt: SIMD2<Float>?
            for xi in stride(from: Float(100), to: 280, by: 1) { for zi in stride(from: Float(120), to: 320, by: 1) {
                let h = sc.terrain.sampleHeight(x: xi, z: zi)
                if wetPt == nil && h > 0.12 && h < 0.3 && sc.surface(x: xi, z: zi) == .sand { wetPt = SIMD2(xi, zi) }
                if dryPt == nil && h > 1.3 && h < 1.5 && sc.surface(x: xi, z: zi) == .sand && sc.terrain.pathWeight(x: xi, z: zi) < 0.1 { dryPt = SIMD2(xi, zi) }
            } }
            if let w = wetPt, let d = dryPt {
                check(dominant(mixAt(w.x, w.y)) == .wetSand && dominant(mixAt(d.x, d.y)) == .drySand, "surface mix: wet sand at the waterline, dry sand above it")
            } else { check(false, "surface mix: found wet and dry sand sample points") }
            let pathMid = (Layout.tideStone + Layout.windStone) * 0.5
            check(dominant(mixAt(pathMid.x, pathMid.z)) == .earth || mixAt(pathMid.x, pathMid.z)[StepMaterial.earth.rawValue] > 0.4, "surface mix: the lantern path is packed earth")
            check(dominant(mixAt(Layout.summitStone.x + 12, Layout.summitStone.z + 30)) != .wood, "surface mix: the hillside is not planks")
            // Stone: the lighthouse plinth and doorstep, and the Glass Wood's inlaid plate.
            let doorStep = Layout.lighthouse + SIMD3(0, 0, Lighthouse.wallR(2.0) + 1.5)
            check(mixAt(doorStep.x, doorStep.z)[StepMaterial.stone.rawValue] > 0.99 && sc.surface(x: doorStep.x, z: doorStep.z) == .stone, "surface mix: the lighthouse doorstep is stone")
            let gw = GlassWood.build(device: device)
            check(gw.surfaceMix(x: GlassLayout.arrival.x, z: GlassLayout.arrival.z).mix[StepMaterial.stone.rawValue] > 0.99 && gw.surfaceMix(x: GlassLayout.arrival.x + 9, z: GlassLayout.arrival.z).mix[StepMaterial.stone.rawValue] < 0.1, "surface mix: the Glass Wood's inlaid plate is stone and the ground around it is not")
            // The weights always add up to one, everywhere.
            var worstSum: Float = 1
            for k in 0..<600 {
                let x = -250 + Float(k % 30) * 17, z = -300 + Float(k / 30) * 28
                let m = mixAt(x, z); let s = (0..<7).map { m[$0] }.reduce(0, +)
                if abs(s - 1) > abs(worstSum - 1) { worstSum = s }
            }
            check(abs(worstSum - 1) < 0.02, "surface mix: the weights add up to 1 wherever you stand (worst \(worstSum))")
            // Plank index: the dock's boards are 0.275 m apart, so stepping along it changes the plank.
            let i0 = sc.plankIndex(x: onDock(5).x, z: onDock(5).y), i1 = sc.plankIndex(x: onDock(5.6).x, z: onDock(5.6).y), i2 = sc.plankIndex(x: onDock(5.05).x, z: onDock(5.05).y)
            check(i1 - i0 == 2 && (i2 == i0 || i2 == i0 + 1) , "surface mix: each 0.275 m along the dock is another plank (\(i0) -> \(i1))")
            // currentSurface is unchanged, and agrees with the mix in the pure cases.
            check(sc.surface(x: mid.x, z: mid.y) == .wood && sc.surface(x: pathMid.x, z: pathMid.z) == .earth, "the single-surface answer is unchanged (dock = wood, path = earth)")
        }
        if name == "all" || name == "terrain" || name == "terrain-map" {
            let t = Terrain()
            for (label, p) in [("tideStone", Layout.tideStone), ("windStone", Layout.windStone), ("summitStone", Layout.summitStone),
                               ("lighthouse", Layout.lighthouse), ("causewayStart", Layout.causewayStart), ("isletCenter", Layout.isletCenter),
                               ("dockShore", Layout.dockShore)] {
                let h = t.sampleHeight(x: p.x, z: p.z)
                check(abs(h - p.y) < 1, "\(label) ground \(String(format: "%.2f", h)) vs layout y \(p.y)")
            }
            let de = t.sampleHeight(x: Layout.dockEnd.x, z: Layout.dockEnd.z)
            check(de < -0.5, "dock end is over water (\(String(format: "%.2f", de)) m)")
            check(abs(t.sampleHeight(x: 33.3, z: -71.7) - t.height(x: 33.3, z: -71.7)) < 1.0, "cache agrees with analytic height")
            if ProcessInfo.processInfo.environment["TERRAIN_DEBUG"] != nil {
                let a = SIMD2(Layout.dockShore.x, Layout.dockShore.z), b = SIMD2(Layout.dockEnd.x, Layout.dockEnd.z)
                let dir = normalize(b - a), side = SIMD2(-dir.y, dir.x)
                for k in stride(from: 0, through: 40, by: 5) {
                    let c = a + dir * Float(k)
                    print("along dock +\(k) m: centre \(String(format: "%.2f", t.sampleHeight(x: c.x, z: c.y)))  left 6m \(String(format: "%.2f", t.sampleHeight(x: c.x + side.x * 6, z: c.y + side.y * 6)))  right 6m \(String(format: "%.2f", t.sampleHeight(x: c.x - side.x * 6, z: c.y - side.y * 6)))")
                }
            }
            let nrm = t.normal(x: 40, z: 55)
            check(abs(length(nrm) - 1) < 1e-4 && nrm.y > 0.3, "normal is unit and points upward on the ridge (y=\(nrm.y))")
            // The sampler is the mesh: compare against the triangles actually uploaded to the GPU at 5000 seeded random points.
            do {
                let chunks = TerrainMesh.buildChunks(terrain: t, device: device)
                var byName: [String: DrawItem] = [:]; for c in chunks { byName[c.name] = c }
                let per = (Terrain.gridCount - 1) / TerrainMesh.chunksPerSide
                var seed: UInt64 = 0x9E3779B97F4A7C15
                func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) }
                var worst: Float = 0, worstNormal: Float = 1, tested = 0
                for _ in 0..<5000 {
                    let x = -400 + rnd() * 800, z = -400 + rnd() * 800
                    let gx = (x - Terrain.origin) / Terrain.spacing, gz = (z - Terrain.origin) / Terrain.spacing
                    let ci = Int(gx) / per, cj = Int(gz) / per
                    guard let item = byName["terrain_\(ci)_\(cj)"] else { continue }
                    let li = Int(gx) - ci * per, lj = Int(gz) - cj * per
                    let verts = item.mesh.vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
                    let idx = item.mesh.indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
                    let base = (lj * per + li) * 6
                    for tri in 0..<2 {
                        let p = (0..<3).map { SIMD3(verts[Int(idx[base + tri * 3 + $0])].position.x, verts[Int(idx[base + tri * 3 + $0])].position.y, verts[Int(idx[base + tri * 3 + $0])].position.z) }
                        // barycentric weights of (x, z) in this triangle's footprint
                        let d = (p[1].z - p[2].z) * (p[0].x - p[2].x) + (p[2].x - p[1].x) * (p[0].z - p[2].z)
                        let w0 = ((p[1].z - p[2].z) * (x - p[2].x) + (p[2].x - p[1].x) * (z - p[2].z)) / d
                        let w1 = ((p[2].z - p[0].z) * (x - p[2].x) + (p[0].x - p[2].x) * (z - p[2].z)) / d
                        let w2 = 1 - w0 - w1
                        if w0 >= -1e-4 && w1 >= -1e-4 && w2 >= -1e-4 {
                            let meshY = w0 * p[0].y + w1 * p[1].y + w2 * p[2].y
                            worst = max(worst, abs(meshY - t.sampleHeight(x: x, z: z)))
                            let fn = normalize(cross(p[1] - p[0], p[2] - p[0])); let fnUp = fn.y < 0 ? -fn : fn
                            worstNormal = min(worstNormal, dot(fnUp, t.faceNormal(x: x, z: z)))
                            tested += 1
                            break
                        }
                    }
                }
                check(tested > 4500 && worst < 0.001, "terrain sampleHeight equals the mesh triangle height at \(tested) random points (worst difference \(worst * 1000) mm)")
                check(worstNormal > 0.9999, "faceNormal equals the mesh triangle's normal (worst dot \(worstNormal))")
            }
            var maxSlopeOnPath: Float = 0, worstAt = ""
            for k in 0..<(Layout.route.count - 1) {
                let a = Layout.route[k], b = Layout.route[k + 1]
                var prev = t.sampleHeight(x: a.x, z: a.z)
                for s in 1...100 {
                    let q = a + (b - a) * (Float(s) / 100)
                    let h = t.sampleHeight(x: q.x, z: q.z)
                    let sl = abs(h - prev) / (length(SIMD2(b.x - a.x, b.z - a.z)) / 100)
                    if sl > maxSlopeOnPath { maxSlopeOnPath = sl; worstAt = "leg \(k) step \(s) at (\(Int(q.x)), \(Int(q.z))) h \(String(format: "%.1f", h))" }
                    prev = h
                }
            }
            print("steepest slope along the straight-line lantern path: \(String(format: "%.2f", maxSlopeOnPath)) (rise/run) \(worstAt)")
            check(maxSlopeOnPath < 1.0, "lantern path stays walkable (steepest < 1.0 rise/run; player limit is 1.19)")
            if name == "terrain-map" {
                // ASCII overview, 4 m per column: ' ' deep, '.' shallow, '~' awash, then land bands by height.
                for j in stride(from: -400, to: 260, by: 10) {
                    var row = ""
                    for i in stride(from: -300, to: 280, by: 5) {
                        let h = t.sampleHeight(x: Float(i), z: Float(j))
                        row.append(h < -8 ? " " : h < -1 ? "." : h < 0.3 ? "~" : h < 4 ? "," : h < 15 ? ":" : h < 35 ? "o" : h < 55 ? "O" : "@")
                    }
                    print(row)
                }
            }
        }
        if name == "all" || name == "birds" {
            let scene = Scene.makeWorld(device: device)
            check((0..<Birds.count).allSatisfy { scene.has("bird_\($0)") }, "all \(Birds.count) gulls exist in the scene")
            var lowest: Float = 1e9, worstHeading: Float = 0
            for k in 0..<Birds.count {
                for step in 0..<400 {
                    let t = Float(step) * 0.5
                    let p = Birds.pose(k, time: t), q = Birds.pose(k, time: t + 0.05)
                    lowest = min(lowest, p.position.y - scene.groundHeight(x: p.position.x, z: p.position.z))
                    let v = SIMD2(q.position.x - p.position.x, q.position.z - p.position.z)
                    var diff = abs(atan2(v.x, v.y) - p.heading)
                    if diff > .pi { diff = 2 * .pi - diff }
                    worstHeading = max(worstHeading, diff)
                }
            }
            check(lowest > 6, "no gull ever flies lower than 6 m above ground or sea (lowest \(String(format: "%.1f", lowest)) m)")
            check(worstHeading < 0.12, "every gull faces the way it flies (worst heading error \(String(format: "%.3f", worstHeading)) rad)")
            check(Birds.pose(3, time: 17.5).position == Birds.pose(3, time: 17.5).position, "flight paths are deterministic")
            let g = Game(scene: scene)
            let before = scene.items.first { $0.name == "bird_0" }!.uniforms.model
            g.simulate(seconds: 2)
            check(scene.items.first { $0.name == "bird_0" }!.uniforms.model != before, "gulls move as the game runs")
        }
        if name == "all" || name == "worlds" {
            let scenes = Dictionary(uniqueKeysWithValues: WorldKind.allCases.map { ($0, Scene.make($0, device: device)) })
            check(scenes.count == WorldKind.allCases.count && scenes.values.allSatisfy { !$0.items.isEmpty }, "every world builds a non-empty scene")
            let glass = scenes[.glassWood]!

            // The Glass Wood's ground.
            let arrival = GlassLayout.arrival
            check(abs(glass.terrain.sampleHeight(x: arrival.x, z: arrival.z) - arrival.y) < 0.6 && arrival.y > 2, "the arrival pad is dry land at its layout height (\(String(format: "%.1f", arrival.y)) m)")
            let poolDepth = glass.terrain.sampleHeight(x: GlassTerrain.pool.x, z: GlassTerrain.pool.y)
            check(poolDepth < -1, "the pool in the middle is a water-filled hollow (\(String(format: "%.1f", poolDepth)) m)")
            var lowestOnPath: Float = 99, steepest: Float = 0
            for k in 0..<(GlassLayout.path.count - 1) {
                let a = GlassLayout.path[k], b = GlassLayout.path[k + 1]
                let len = length(SIMD2(b.x - a.x, b.z - a.z))
                var prev = glass.terrain.sampleHeight(x: a.x, z: a.z)
                for i in 1...80 {
                    let q = a + (b - a) * (Float(i) / 80)
                    let h = glass.terrain.sampleHeight(x: q.x, z: q.z)
                    lowestOnPath = min(lowestOnPath, h)
                    steepest = max(steepest, abs(h - prev) / (len / 80)); prev = h
                }
            }
            check(lowestOnPath > 1.0, "the whole route stays on dry land (lowest \(String(format: "%.1f", lowestOnPath)) m)")
            check(steepest < 1.0, "the route is walkable (steepest \(String(format: "%.2f", steepest)) rise/run)")
            for (label, pad) in [("mirror court", GlassLayout.mirrorCourt), ("chime ring", GlassLayout.chimeRing), ("altar", GlassLayout.altar), ("junction", GlassLayout.junction)] {
                check(abs(glass.terrain.sampleHeight(x: pad.x, z: pad.z) - pad.y) < 0.6 && pad.y > 1.5, "\(label) sits on level dry ground at \(String(format: "%.1f", pad.y)) m")
            }

            // Travelling: lens -> Glass Wood -> return -> Varrow.
            let g = Game(scenes: scenes)
            g.puzzle.forceSolved()
            check(g.world == .varrow && g.interactables.contains { $0.id == "lens" }, "the game starts in Varrow with its own interactables")
            g.activate("lens")
            check(g.isTraveling && g.world == .varrow, "touching the lens starts the fade, still in Varrow")
            var input = InputState(); input.move = SIMD2(0, 1)
            let startPos = g.player.position
            g.simulate(seconds: 0.5, input: input)
            check(distance(g.player.position, startPos) < 0.05, "the player stands still while the world folds")
            g.simulate(seconds: Game.fadeOutSeconds - 0.4)
            check(g.world == .glassWood && g.whiteout > 0.99, "at full white the world has changed to the Glass Wood (whiteout \(String(format: "%.2f", g.whiteout)))")
            check(distance(SIMD2(g.player.position.x, g.player.position.z), SIMD2(arrival.x, arrival.z)) < 0.01 && abs(g.player.position.y - arrival.y) < 0.6, "you arrive on the arrival pad")
            check(g.interactables.map(\.id).contains("gw_return") && !g.interactables.map(\.id).contains("lens") && g.drainEvents().contains(.worldChanged(.glassWood)), "the Glass Wood has its own interactables (and not Varrow's) and a worldChanged event was emitted")
            g.simulate(seconds: Game.holdSeconds + Game.fadeInSeconds + 0.2)
            check(g.whiteout == 0 && !g.isTraveling && g.whiteCaption == nil, "the white fades away and control returns")
            g.simulate(seconds: 2, input: input)
            check(distance(g.player.position, arrival) > 3, "you can walk in the Glass Wood")

            g.player = Player(position: GlassLayout.returnLens - SIMD3(0, 2.3, 0) + SIMD3(0, 0, 3), yaw: 0)     // 3 m south of the ring, facing it
            g.player.pitch = 0.0
            g.player.position.y = g.scene.groundHeight(x: g.player.position.x, z: g.player.position.z)
            g.updateHover()
            check(g.hovered?.id == "gw_return", "standing before the return ring, it is hoverable (\(g.hovered?.id ?? "nothing"))")
            g.activate("gw_return")
            g.simulate(seconds: Game.fadeOutSeconds + 0.1)
            check(g.world == .varrow && distance(SIMD2(g.player.position.x, g.player.position.z), SIMD2(Layout.isletCenter.x, Layout.isletCenter.z + 5)) < 0.1, "the return ring takes you back to the islet in Varrow")
            g.simulate(seconds: 3)
            check(g.state.has("solved") && g.whiteout == 0, "Varrow's progress is intact after the round trip")

            // Without the Glass Wood scene (Varrow-only games) the lens simply does nothing.
            let lone = Game(scene: scenes[.varrow]!)
            lone.puzzle.forceSolved(); lone.activate("lens"); lone.simulate(seconds: 3)
            check(lone.world == .varrow && lone.whiteout == 0, "a Varrow-only game ignores the lens rather than breaking")

            // Saving in the second world.
            let tmp = NSTemporaryDirectory() + "lw-worlds-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            let h = Game(scenes: scenes); h.puzzle.forceSolved(); h.travel(to: .glassWood)
            h.player = Player(position: GlassLayout.point(-20, 102), yaw: 0.7)          // M10.4: on the western path (a spot off the corridors would be moved onto them)
            h.player.position.y = h.scene.groundHeight(x: -20, z: 102)
            try? SaveStore.save(h.makeSave())
            let k = Game(scenes: scenes)
            if let save = SaveStore.load() { k.restore(save) }
            check(k.world == .glassWood && abs(k.player.position.x + 20) < 0.01 && k.state.has("solved"), "a save made in the Glass Wood resumes there")
            let old = SaveData(worldFlags: ["varrow": ["solved"]], pages: [], position: [175, 0.8, 205], yaw: 0, pitch: 0, playTime: 1, world: nil)
            let m = Game(scenes: scenes); m.restore(old)
            check(m.world == .varrow, "a save without a world field (from before the second world) resumes in Varrow")
        }
        if name == "all" || name == "mirrors" {
            let sol = MirrorCourt.trace(mirrors: MirrorCourt.solutionMirrors, panes: MirrorCourt.solutionPanes)
            check(sol.solved && sol.panesMet == [0, 1, 2], "the intended arrangement solves it (panes met \(sol.panesMet))")
            let start = MirrorCourt.trace(mirrors: MirrorCourt.initialMirrors, panes: MirrorCourt.initialPanes)
            check(!start.solved && !start.reachedReceiver, "the starting arrangement is not solved and the beam misses the receiver")
            check(sol.points.count >= 6 && sol.segmentColor.count == sol.points.count - 1, "a trace has one colour per segment (\(sol.points.count) points)")
            check(sol.segmentColor.first == -1 && sol.segmentColor.last == 2, "the light starts as plain moonlight and ends amber (the last pane is stone)")

            // Exhaustive: all 4^3 mirror states x 3^3 pane colours terminate, and exactly ONE of the 1728 solves it.
            var solutions: [([Int], [Int])] = [], reached = 0
            for a in 0..<4 { for b in 0..<4 { for c in 0..<4 {
                for x in 0..<3 { for y in 0..<3 { for z in 0..<3 {
                    let t = MirrorCourt.trace(mirrors: [a, b, c], panes: [x, y, z])
                    if t.reachedReceiver { reached += 1 }
                    if t.solved { solutions.append(([a, b, c], [x, y, z])) }
                } } }
            } } }
            check(solutions.count == 1 && solutions[0].0 == MirrorCourt.solutionMirrors && solutions[0].1 == MirrorCourt.solutionPanes,
                  "exactly one of the 1728 arrangements solves it (\(solutions.count) found); the beam reaches the receiver in \(reached) of them")
            check(reached > 1 && reached < 400, "reaching the receiver is possible with wrong colours, so the colour order really matters (\(reached) arrangements reach it)")

            // Any single click away from the solution is not solved (so there are no cheap near-misses).
            var oneAway = 0
            for k in 0..<3 {
                var m = MirrorCourt.solutionMirrors; m[k] = (m[k] + 1) % 4
                if MirrorCourt.trace(mirrors: m, panes: MirrorCourt.solutionPanes).solved { oneAway += 1 }
                var p = MirrorCourt.solutionPanes; p[k] = (p[k] + 1) % 3
                if MirrorCourt.trace(mirrors: MirrorCourt.solutionMirrors, panes: p).solved { oneAway += 1 }
            }
            check(oneAway == 0, "no arrangement one click from the solution also solves it")
            // Reflection rules.
            check(MirrorCourt.reflect((1, 0), state: 3) == (0, -1) && MirrorCourt.reflect((0, -1), state: 1) == (-1, 0) && MirrorCourt.reflect((-1, 0), state: 3) == (0, 1), "the three solution mirrors turn the beam east->north->west->south")
            check(MirrorCourt.reflect((1, 0), state: 0) == (1, 0) && MirrorCourt.reflect((1, 0), state: 2) == (-1, 0), "an axis mirror passes a parallel beam and bounces a perpendicular one back")
            // Geometry: the whole court fits on the flat pad.
            let corners = [MirrorCourt.world((0, 0)), MirrorCourt.world((4, 4)), MirrorCourt.world((0, 4)), MirrorCourt.world((4, 0))]
            let farthest = corners.map { distance(SIMD2($0.x, $0.z), SIMD2(GlassLayout.mirrorCourt.x, GlassLayout.mirrorCourt.z)) }.max()!
            check(farthest < GlassLayout.pads[1].radius - 4, "the court fits inside its flat pad (corner \(String(format: "%.1f", farthest)) m from the centre, pad radius \(GlassLayout.pads[1].radius))")
        }
        if name == "all" || name == "mirrorgame" {
            // Each game gets freshly built scenes, because the puzzle mutates scene items.
            func fresh() -> Game {
                let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
                g.travel(to: .glassWood); _ = g.drainEvents()
                return g
            }
            func item(_ g: Game, _ name: String) -> DrawItem { g.scenes[.glassWood]!.items.first { $0.name == name }! }
            func visibleBeams(_ g: Game) -> Int { (0..<GlassPuzzleProps.beamSegments).filter { !item(g, "gw_beam_\($0)").hidden }.count }
            func chimes(_ e: [GameEvent]) -> [ChimeKind] { e.compactMap { if case .chime(let k) = $0 { return k } else { return nil } } }

            var g = fresh()
            let ids = g.interactables.map(\.id)
            check(["gw_mirror_0", "gw_mirror_1", "gw_mirror_2", "gw_pane_0", "gw_pane_1", "gw_pane_2", "gw_return"].allSatisfy(ids.contains), "the court's mirrors, panes and the return ring are interactable")
            check(g.interactables.first { $0.id == "page_5" }?.enabled == true && ["page_6", "page_7", "page_8"].allSatisfy { id in g.interactables.first { $0.id == id }?.enabled == false }, "page 5 is readable at once; 6-8 wait to be earned")
            check(item(g, "page_6").hidden && item(g, "page_7").hidden && item(g, "page_8").hidden && !item(g, "page_5").hidden, "pages 6-8 are not visible in the world yet")
            check(visibleBeams(g) >= 1, "a beam is already visible in the court at the start (\(visibleBeams(g)) segment(s))")

            // A wrong arrangement that nonetheless reaches the receiver: panes in the wrong order do not solve it.
            g.glass!.click("gw_mirror_0"); g.glass!.click("gw_mirror_0"); g.glass!.click("gw_mirror_0")     // M1: 0 -> 3
            for _ in 0..<3 { g.glass!.click("gw_mirror_1") }                                                  // M2: 2 -> 1
            for _ in 0..<2 { g.glass!.click("gw_mirror_2") }                                                  // M3: 1 -> 3
            check(g.glass!.mirrors == MirrorCourt.solutionMirrors && !g.state.has("gw_mirrors"), "right mirrors, wrong glass: not solved")
            check(MirrorCourt.trace(mirrors: g.glass!.mirrors, panes: g.glass!.panes).reachedReceiver, "...but the beam does reach the receiver, which shows the wrong colour instead of the win")
            g.glass!.click("gw_pane_0")                                                                         // A: 2 -> 0 (tide)
            check(!g.state.has("gw_mirrors"), "one pane right is still not enough")
            g.glass!.click("gw_pane_1")                                                                         // B: 0 -> 1 (wind)
            g.glass!.click("gw_pane_2")                                                                         // C: 1 -> 2 (stone)
            check(g.state.has("gw_mirrors") && g.glass!.panes == MirrorCourt.solutionPanes, "tide, wind, stone in the right order solves the mirror court")

            // The reward plays out over a few seconds.
            check(item(g, "page_6").hidden, "the page does not appear in the same instant")
            g.simulate(seconds: 4)
            check(chimes(g.drainEvents()).filter { [.tide, .wind, .stone, .ignite].contains($0) }.prefix(4) == [.tide, .wind, .stone, .ignite], "the wood answers with tide, wind, stone, then the chord")
            check(!item(g, "page_6").hidden && g.interactables.first { $0.id == "page_6" }?.enabled == true, "Oren's page 6 appears at the receiver")
            check(!item(g, "gw_column").hidden && item(g, "gw_column").uniforms.model.columns.1.y > 40, "a tall column of light rises from the receiver (height \(String(format: "%.0f", item(g, "gw_column").uniforms.model.columns.1.y)) m)")

            // Solved is permanent.
            let before = g.glass!.mirrors
            g.glass!.click("gw_mirror_0"); g.glass!.click("gw_pane_1")
            check(g.glass!.mirrors == before && g.state.has("gw_mirrors") && chimes(g.drainEvents()).filter { $0 == .glassTick }.count == 2, "after solving, clicks only tick; the solution stays")

            // Saving and restoring keeps it solved and reveals the page again.
            let tmp = NSTemporaryDirectory() + "lw-mirror-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            try? SaveStore.save(g.makeSave())
            let h = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            if let save = SaveStore.load() { h.restore(save) }
            check(h.world == .glassWood && h.state.has("gw_mirrors") && h.glass!.panes == MirrorCourt.solutionPanes && !h.scenes[.glassWood]!.items.first { $0.name == "page_6" }!.hidden, "a save resumes with the mirror court solved and page 6 available")

            // Collecting a revealed page works and hides it everywhere.
            g.activate("page_6")
            check(g.journal.collectedPages.map(\.number) == [6] && g.journal.isOpen && item(g, "page_6").hidden, "reading page 6 opens the journal on it and removes it from the world")
        }
        if name == "all" || name == "chimegame" {
            func fresh() -> Game {
                let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
                g.travel(to: .glassWood); _ = g.drainEvents(); return g
            }
            func item(_ g: Game, _ name: String) -> DrawItem { g.scenes[.glassWood]!.items.first { $0.name == name }! }
            func chimes(_ e: [GameEvent]) -> [ChimeKind] { e.compactMap { if case .chime(let k) = $0 { return k } else { return nil } } }

            var g = fresh()
            check((0..<5).allSatisfy { g.interactables.map(\.id).contains("gw_chime_\($0)") }, "all five glass chimes are interactable")
            check(GlassPuzzleProps.chimeHeights == GlassPuzzleProps.chimeHeights.sorted(by: >), "taller chimes are lower in pitch (heights fall as pitch rises)")
            let ringDist = (0..<5).map { distance(SIMD2(GlassPuzzleProps.chimePosition($0).x, GlassPuzzleProps.chimePosition($0).z), SIMD2(GlassLayout.chimeRing.x, GlassLayout.chimeRing.z)) }
            check(ringDist.allSatisfy { abs($0 - GlassPuzzleProps.chimeRadius) < 0.01 } && ringDist.max()! < GlassLayout.pads[3].radius - 2, "the chimes stand on a ring inside the flat pad")

            // A decoy first: fail, reset after 0.8 s.
            g.glass!.strikeChime(1)
            check(chimes(g.drainEvents()) == [.glass1, .fail] && g.glass!.chimeSequence.isEmpty, "a decoy chime rings and fails")
            g.simulate(seconds: 1)
            g.glass!.strikeChime(0)
            check(g.glass!.chimeSequence == [0], "after the reset the right first tone (D4 = tide) is accepted")
            g.simulate(seconds: 0.2)
            g.glass!.strikeChime(3)                                                  // decoy in the middle
            check(g.glass!.chimeSequence == [0], "a decoy mid-sequence fails without adding to it")
            g.glass!.strikeChime(2)                                                  // during the reset delay: ignored
            check(g.glass!.chimeSequence == [0], "strikes during the reset delay are ignored")
            g.simulate(seconds: 1)
            check(g.glass!.chimeSequence.isEmpty, "the whole sequence resets after a mistake")

            // The right order: D4, A4, D5 (tide, wind, stone tones).
            _ = g.drainEvents()
            for k in GlassWoodLogic.chimeSolution { g.glass!.strikeChime(k); g.simulate(seconds: 0.6) }
            check(g.state.has("gw_chimes"), "D4, A4, D5 in order solves the chimes")
            g.simulate(seconds: 4)
            let evs = chimes(g.drainEvents())
            check(evs.prefix(3) == [.glass0, .glass2, .glass4] && evs.contains(.ignite) && evs.filter { $0 == .glass0 }.count == 2, "each strike rings, then the three tones sound together and the shimmer follows (\(evs.prefix(8)))")
            check(!item(g, "page_7").hidden && g.interactables.first { $0.id == "page_7" }?.enabled == true, "Oren's page 7 appears at the chime ring")
            check(!item(g, "gw_column_chimes").hidden && item(g, "gw_column_chimes").uniforms.model.columns.1.y > 40, "an amber column of light rises from the ring")
            g.glass!.strikeChime(1)
            check(g.state.has("gw_chimes") && g.glass!.chimeSequence == GlassWoodLogic.chimeSolution, "solved stays solved; later strikes just ring")

            // Persistence.
            let tmp = NSTemporaryDirectory() + "lw-chime-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            try? SaveStore.save(g.makeSave())
            let h = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            if let save = SaveStore.load() { h.restore(save) }
            check(h.state.has("gw_chimes") && !h.scenes[.glassWood]!.items.first { $0.name == "page_7" }!.hidden && !h.state.has("gw_mirrors"), "a save keeps the chimes solved (and the mirrors unsolved)")

            // The three solution chimes really are the Varrow stones' pitches.
            let sr: Float = 44100
            func render(_ kind: ChimeKind) -> [Float] {
                let synth = AmbienceSynth(sampleRate: sr); synth.windGain = 0; synth.surfGain = 0; synth.master = 1; synth.play(kind)
                var l = [Float](repeating: 0, count: Int(sr)), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    var d = 0; while d < Int(sr) { let c = min(512, Int(sr) - d); synth.render(frames: c, left: lp.baseAddress! + d, right: rp.baseAddress! + d); d += c }
                } }
                return l
            }
            func energy(_ x: [Float], hz: Float) -> Float {
                let w = 2 * Float.pi * hz / sr, c = 2 * cos(w); var s1: Float = 0, s2: Float = 0
                for v in x { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
                return s1 * s1 + s2 * s2 - c * s1 * s2
            }
            for (glassKind, hz, name) in [(ChimeKind.glass0, Float(293.66), "D4"), (.glass1, 369.99, "F#4"), (.glass2, 440.0, "A4"), (.glass3, 523.25, "C5"), (.glass4, 587.33, "D5")] {
                let x = render(glassKind)
                check(energy(x, hz: hz) > 15 * energy(x, hz: hz * 1.12), "glass chime \(name) rings at its pitch")
            }
            let a = render(.glass0), b = render(.tide)
            check(energy(a, hz: 293.66) > 15 * energy(a, hz: 440) && energy(b, hz: 293.66) > 15 * energy(b, hz: 440), "chime 0 and Varrow's tide stone share the pitch D4 (so the player's memory of the stone is the key)")
            check(energy(render(.glass2), hz: 440) > 15 * energy(render(.wind), hz: 440 * 1.12) && energy(render(.wind), hz: 440) > 15 * energy(render(.wind), hz: 440 * 1.12), "chime 2 and the wind stone share A4")
            let tick = render(.glassTick)
            // The chime bus is an 8-line FDN reverb: no discrete echo, a faint wash from ~25 ms. The tick must leave only that.
            let early = tick[0..<4000].map { abs($0) }.max() ?? 0, dryLate = tick[Int(sr * 0.26)..<Int(sr * 0.35)].map { abs($0) }.max() ?? 1
            check(early > 0.02 && dryLate < early * 0.15, "the mirror tick is short: only a faint reverb wash is left at 0.3 s (peak \(String(format: "%.2f", early)) -> \(String(format: "%.4f", dryLate)) at 0.3 s)")
        }
        if name == "all" || name == "altar" {
            func fresh() -> Game {
                let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
                g.travel(to: .glassWood); _ = g.drainEvents(); return g
            }
            func item(_ g: Game, _ name: String) -> DrawItem { g.scenes[.glassWood]!.items.first { $0.name == name }! }
            func enabled(_ g: Game, _ id: String) -> Bool { g.interactables.first { $0.id == id }?.enabled == true }

            var g = fresh()
            check(item(g, "gw_altar_ilse").hidden && item(g, "gw_altar_oren").hidden && !enabled(g, "gw_altar_ilse") && !enabled(g, "gw_altar_oren"), "the altar's pedestals are hidden and inert at the start")
            g.glass!.touchAltar(0)
            check(g.banner == nil && !g.state.has("gw_ilse_heard"), "touching a dormant altar does nothing")

            // One puzzle is not enough, in either order.
            g.glass!.forceMirrorsSolved(); g.glass!.checkAltar(); g.simulate(seconds: 6)
            check(!g.state.has("gw_altar") && item(g, "gw_altar_ilse").hidden, "solving only the mirrors does not wake the altar")
            g = fresh()
            g.glass!.forceChimesSolved(); g.glass!.checkAltar(); g.simulate(seconds: 6)
            check(!g.state.has("gw_altar"), "solving only the chimes does not wake it either")

            // Both, by really playing the second puzzle: chimes first, then the mirrors.
            g = fresh()
            for k in GlassWoodLogic.chimeSolution { g.glass!.strikeChime(k); g.simulate(seconds: 0.6) }
            g.simulate(seconds: 5)
            check(g.state.has("gw_chimes") && !g.state.has("gw_altar"), "chimes solved first: the altar is still asleep")
            g.glass!.setArrangement(mirrors: MirrorCourt.solutionMirrors, panes: MirrorCourt.solutionPanes)
            g.simulate(seconds: 5)
            check(g.state.has("gw_mirrors") && g.state.has("gw_altar"), "then the mirrors: the altar wakes (either order works)")
            check(g.banner?.contains("woken") == true, "a line of text announces it (\"\(g.banner ?? "")\")")
            check(!item(g, "gw_altar_ilse").hidden && !item(g, "gw_altar_oren").hidden && !item(g, "gw_column_altar").hidden, "the pedestals and a column of light appear")
            check(!enabled(g, "gw_altar_ilse") && item(g, "page_8").hidden, "…but they are not touchable until they have finished rising")
            g.simulate(seconds: 5)
            check(enabled(g, "gw_altar_ilse") && enabled(g, "gw_altar_oren") && !item(g, "page_8").hidden && enabled(g, "page_8"), "once risen, both lights can be touched and Oren's last page (8) appears")
            let sunk = item(g, "gw_altar_ilse").uniforms.model.columns.3.y
            check(abs(sunk - GlassLayout.altar.y) < 0.05, "the pedestals have risen to ground level (y \(String(format: "%.2f", sunk)) vs \(String(format: "%.2f", GlassLayout.altar.y)))")

            // Hearing the two accounts.
            g.activate("gw_altar_ilse")
            check(g.state.has("gw_ilse_heard") && g.banner?.hasPrefix("Ilse:") == true && !g.state.has("gw_end"), "Ilse's account is shown; the end is not reached with only one")
            g.activate("gw_altar_oren")
            check(g.state.has("gw_oren_heard") && g.banner?.hasPrefix("Oren:") == true && g.state.has("gw_end"), "Oren's account is shown; hearing both reaches the end of the second world")
            g.simulate(seconds: 8)
            check(g.banner?.contains("choose") == true, "after a pause the closing line sets up the choice (\"\(g.banner ?? "")\")")
            g.simulate(seconds: 12)
            check(g.banner == nil, "banners clear themselves")

            // A save keeps all of it; returning to Varrow acknowledges it.
            let tmp = NSTemporaryDirectory() + "lw-altar-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            try? SaveStore.save(g.makeSave())
            let h = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            if let save = SaveStore.load() { h.restore(save) }
            check(h.state.has("gw_altar") && h.state.has("gw_end") && enabled(h, "gw_altar_oren") && !h.scenes[.glassWood]!.items.first { $0.name == "page_8" }!.hidden, "a save restores the awakened altar and the story flags")
            h.activate("gw_return"); h.simulate(seconds: Game.fadeOutSeconds + 0.1)
            check(h.world == .varrow && h.banner?.contains("two accounts") == true, "returning to Varrow after the end acknowledges it (\"\(h.banner ?? "")\")")
        }
        if name == "all" || name == "interaction" {
            let lo = SIMD3<Float>(-1, 0, -1), hi = SIMD3<Float>(1, 3, 1)
            check(Interaction.rayBox(origin: SIMD3(0, 1.5, 5), dir: SIMD3(0, 0, -1), min: lo, max: hi).map { abs($0 - 4) < 1e-4 } ?? false, "ray straight at a box hits its near face (4 m)")
            check(Interaction.rayBox(origin: SIMD3(3, 1.5, 5), dir: SIMD3(0, 0, -1), min: lo, max: hi) == nil, "ray passing beside the box misses")
            check(Interaction.rayBox(origin: SIMD3(0, 1.5, 5), dir: SIMD3(0, 0, 1), min: lo, max: hi) == nil, "ray pointing away misses (no hits behind the origin)")
            check(Interaction.rayBox(origin: SIMD3(0, 1.5, 0), dir: SIMD3(1, 0, 0), min: lo, max: hi) == 0, "ray starting inside the box reports distance 0")
            check(Interaction.rayBox(origin: SIMD3(0, 5, 5), dir: SIMD3(0, 0, -1), min: lo, max: hi) == nil, "axis-parallel ray above the box misses")
            let near = Interactable(id: "near", min: lo, max: hi, prompt: "n")
            var far = Interactable(id: "far", min: SIMD3(-1, 0, -11), max: SIMD3(1, 3, -9), prompt: "f"); far.reach = 20
            check(Interaction.pick(origin: SIMD3(0, 1.5, 4), dir: SIMD3(0, 0, -1), in: [far, near])?.id == "near", "pick returns the nearest of two boxes on the ray (near is 3 m away, far is 13 m)")
            var tooFar = near; tooFar.reach = 2
            check(Interaction.pick(origin: SIMD3(0, 1.5, 5), dir: SIMD3(0, 0, -1), in: [tooFar]) == nil, "an object beyond its reach is not hoverable")
            var off = near; off.enabled = false
            check(Interaction.pick(origin: SIMD3(0, 1.5, 5), dir: SIMD3(0, 0, -1), in: [off]) == nil, "disabled interactables are ignored")
        }
        if name == "all" || name == "interact" {
            func freshGame() -> Game { Game(scene: Scene.makeWorld(device: device)) }
            // Hover: stand where the tide stone is faced and look at it.
            var g = freshGame()
            let id = StoneID.tide
            let toward = normalize(SIMD2(id.approachFrom.x - id.position.x, id.approachFrom.z - id.position.z))
            let stand = SIMD2(id.position.x, id.position.z) + toward * 2.6
            let look = SIMD2(-toward.x, -toward.y)
            g.player = Player(position: SIMD3(stand.x, id.position.y, stand.y), yaw: atan2(look.x, -look.y))
            g.player.pitch = 0.05
            g.updateHover()
            check(g.hovered?.id == "stone_tide", "looking at the tide stone from 2.6 m hovers it (\(g.hovered?.id ?? "nothing"))")
            g.player.yaw += 1.2; g.updateHover()
            check(g.hovered == nil, "looking away un-hovers it")
            g.player.yaw -= 1.2
            g.player = Player(position: SIMD3(stand.x + toward.x * 6, id.position.y, stand.y + toward.y * 6), yaw: atan2(look.x, -look.y))
            g.updateHover()
            check(g.hovered == nil, "from 8.6 m away the stone is out of reach")

            // Clicking through the real input path strikes the stone.
            g = freshGame()
            g.player = Player(position: SIMD3(stand.x, id.position.y, stand.y), yaw: atan2(look.x, -look.y)); g.player.pitch = 0.05
            var click = InputState(); click.click = true
            g.advance(now: 100, input: InputState()); g.advance(now: 100.02, input: click)
            check(g.state.has("lit_tide"), "a click on the hovered stone strikes it")

            // Pages: collecting hides the page, opens the journal, disables the interactable.
            g = freshGame()
            g.activate("page_1")
            check(g.journal.isOpen && g.journal.collectedPages.map(\.number) == [1], "collecting page 1 opens the journal on it")
            check(g.scene.items.first { $0.name == "page_1" }?.hidden == true && g.interactables.first { $0.id == "page_1" }?.enabled == false, "the collected page disappears from the world")
            check(g.drainEvents().contains(.pageCollected(1)), "a pageCollected event is emitted")
            g.updateHover(); check(g.hovered == nil, "nothing is hoverable while the journal is open")
            g.toggleJournal(); check(!g.journal.isOpen, "J closes the journal")

            // The lens does nothing until the causeway is up (the full world-travel tests are in `worlds`).
            g = freshGame()
            g.activate("lens"); g.simulate(seconds: 2.5)
            check(!g.state.has("lensTouched") && g.whiteout == 0 && g.world == .varrow, "the lens is inert before the puzzle is solved")

            // (Where the pages lie, and that they lie ON the ground, is asserted in SelfTestPages: `--selftest pages`.)
            g = freshGame()
        }
        if name == "all" || name == "input" {
            let input = Input()
            input.keyDown(Input.Key.w); input.keyDown(Input.Key.d)
            let s1 = input.sample(captured: true)
            check(abs(length(s1.move) - 1) < 1e-5 && s1.move.x > 0 && s1.move.y > 0, "W+D is a unit-length diagonal (no faster diagonal)")
            input.addMouse(dx: 100, dy: -50)
            let s2 = input.sample(captured: true)
            check(s2.look.x > 0 && s2.look.y > 0, "mouse right turns right, mouse up looks up")
            check(input.sample(captured: true).look == .zero, "mouse delta is consumed once")
            input.keyDown(Input.Key.j)
            check(input.sample(captured: false).journalPressed, "J edge is reported even when the mouse is released")
            check(input.sample(captured: false).journalPressed == false, "edge fires once")
            check(input.sample(captured: false).move == .zero, "no movement while the mouse is released")
            input.releaseAll()
            check(input.sample(captured: true).move == .zero, "releaseAll clears held keys")
        }
        if name == "all" || name == "player" {
            let scene = Scene.makeWorld(device: device)
            let dt = Game.tick
            func ground(_ p: Player) -> Float { scene.groundHeight(x: p.position.x, z: p.position.z) }
            func flat(_ v: SIMD3<Float>) -> SIMD2<Float> { SIMD2(v.x, v.z) }

            // 1. Spawn on the dock and walk forward: we end up on the beach, never in the water.
            var p = Player(position: Layout.dockEnd, yaw: Layout.spawnYaw)
            var lowest: Float = 99
            for i in 0..<(14 * 120) {       // 41 m of dock at 3.2 m/s = 13 s
                p.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene)
                lowest = min(lowest, ground(p))
                if ProcessInfo.processInfo.environment["PLAYER_DEBUG"] != nil, i % 120 == 0 {
                    print("t=\(i / 120) pos=(\(p.position.x), \(p.position.y), \(p.position.z)) speed=\(p.speed) ground=\(ground(p))")
                }
            }
            check(lowest > -0.1 && distance(flat(p.position), flat(Layout.dockShore)) < 12,
                  "walking forward from spawn follows the dock to the beach without falling in (lowest ground \(String(format: "%.2f", lowest)), \(String(format: "%.1f", distance(flat(p.position), flat(Layout.dockShore)))) m from the dock's landward end)")

            // 2. The sea is a wall: from the end of the dock walk straight out to sea.
            p = Player(position: Layout.dockEnd, yaw: Layout.spawnYaw + .pi)
            lowest = 99
            for _ in 0..<(20 * 120) {
                p.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene)
                lowest = min(lowest, ground(p))
            }
            check(lowest > Player.minGround - 0.05, "cannot wade out to sea (lowest ground \(String(format: "%.2f", lowest)) m)")

            // 3. A bot walks the whole lantern path and reaches the lighthouse.
            p = Player(position: Layout.dockShore, yaw: 0)
            var path = Layout.lanternPath
            path.removeFirst()
            var reachedAll = true
            var worstLeg = ""
            for (i, wp) in path.enumerated() {
                let reach: Float = (i == path.count - 1) ? 8 : 2.5     // the lighthouse is solid: stop beside it
                var t: Float = 0
                var arrived = false
                while t < 150 {
                    let d = flat(wp) - flat(p.position)
                    if length(d) < reach { arrived = true; break }
                    p.yaw = atan2(d.x, -d.y)
                    p.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene)
                    t += dt
                }
                if !arrived { reachedAll = false; worstLeg = "leg \(i) stuck at (\(Int(p.position.x)), \(Int(p.position.z)))"; break }
            }
            check(reachedAll, "bot walks dock shore -> tide -> wind -> summit stone -> lighthouse \(worstLeg)")

            // 4. Walk straight at the lighthouse: stopped by the tower, not inside it.
            let lh = flat(Layout.lighthouse)
            p = Player(position: SIMD3(lh.x, Layout.lighthouse.y, lh.y + 14), yaw: 0)   // 14 m south, facing north
            p.position.y = ground(p)
            for _ in 0..<(8 * 120) { p.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene) }
            let dLH = distance(flat(p.position), lh)
            check(dLH > Lighthouse.colliderRadius + Player.radius - 0.1 && dLH < Lighthouse.colliderRadius + Player.radius + 0.5, "lighthouse is solid (stopped \(String(format: "%.2f", dLH)) m from its axis)")

            // 4b. Touch distance: the doorstep is climbed, not snagged on; you end up about 0.8 m from the door, standing on a step.
            check(p.position.y > Layout.lighthouse.y + 0.5 && p.position.y < Layout.lighthouse.y + 0.95, "walking at the door climbs the steps (feet \(String(format: "%.2f", p.position.y - Layout.lighthouse.y)) m above the pad)")
            let doorFace = Layout.lighthouse.z + Lighthouse.wallR(2.0)
            check(abs((p.position.z) - doorFace) < 1.0 && abs(p.position.x - Layout.lighthouse.x) < 0.2, "and stops within 1 m of the door, in front of it (\(String(format: "%.2f", p.position.z - doorFace)) m)")
            var around = Player(position: SIMD3(lh.x + 7, Layout.lighthouse.y, lh.y), yaw: -.pi / 2)    // east of the tower, facing west
            around.position.y = ground(around)
            for _ in 0..<(6 * 120) { around.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene) }
            check(distance(flat(around.position), lh) > Lighthouse.colliderRadius + Player.radius - 0.1 && around.position.y < Layout.lighthouse.y + 0.65, "from the east the plinth is climbed to its second tread and the wall stops you, without clipping into it")
            // 5. Speeds: walking settles at 2.6 m/s, running at 4.4 m/s (M10.2, retuned).
            p = Player(position: SIMD3(40, 34, 55), yaw: 0)
            for _ in 0..<(3 * 120) { p.step(dt: dt, input: InputState(move: SIMD2(1, 0)), scene: scene) }
            let walk = p.speed
            var r = InputState(); r.move = SIMD2(1, 0); r.run = true
            for _ in 0..<(3 * 120) { p.step(dt: dt, input: r, scene: scene) }
            check(abs(walk - 2.6) < 0.3 && abs(p.speed - 4.4) < 0.5, "walk \(String(format: "%.2f", walk)) m/s, run \(String(format: "%.2f", p.speed)) m/s (on a slope)")

            // 5b. Gait: walking is an unhurried ~1.9 steps/s; running lengthens the stride (1.25x) and quickens it (1.25x) rather than only stepping faster.
            func cadence(run: Bool) -> Float {
                let q = Player(position: SIMD3(Layout.dockShore.x, Layout.dockShore.y, Layout.dockShore.z), yaw: 3.0)
                var pl = q
                var input = InputState(); input.move = SIMD2(0, 1); input.run = run
                pl.position.y = scene.groundHeight(x: pl.position.x, z: pl.position.z)
                for _ in 0..<(2 * 120) { pl.step(dt: dt, input: input, scene: scene) }          // settle to full speed
                let start = pl.stepCount
                var travelled: Float = 0, last = SIMD2(pl.position.x, pl.position.z)
                for _ in 0..<(6 * 120) {
                    pl.step(dt: dt, input: input, scene: scene)
                    let now = SIMD2(pl.position.x, pl.position.z); travelled += distance(now, last); last = now
                }
                _ = travelled
                return Float(pl.stepCount - start) / 6
            }
            let walkCadence = cadence(run: false), runCadence = cadence(run: true)
            check(walkCadence > 1.8 && walkCadence < 2.6, "walking cadence is natural (\(String(format: "%.2f", walkCadence)) steps/s)")
            check(runCadence / walkCadence > 1.1 && runCadence / walkCadence < 1.6,      // M10.2: the run/walk speed ratio fell from 2.0 to 1.57, so the floor fell from 1.2 to 1.1 (stride and cadence each about 1.25x nominal)
                   "running is a different gait, not 2x walking (\(String(format: "%.2f", runCadence)) vs \(String(format: "%.2f", walkCadence)) steps/s = \(String(format: "%.2f", runCadence / walkCadence))x)")
            check(Player.stepLength(speed: Player.runSpeed) > 1.2 * Player.stepLength(speed: Player.walkSpeed), "the run stride is longer than the walk stride")

            // 6. Frame-rate independence: the same 4 s of "walk forward" at 30, 60 and 144 fps covers the same ground.
            var distances: [Float] = []
            for fps in [30.0, 60.0, 144.0] {
                let g = Game(scene: scene)
                g.player = Player(position: SIMD3(Layout.dockShore.x, Layout.dockShore.y, Layout.dockShore.z), yaw: 3.0)
                var input = InputState(); input.move = SIMD2(0, 1)
                var now = 1000.0
                let start = SIMD2(g.player.position.x, g.player.position.z)
                for _ in 0..<Int(fps * 4) { now += 1 / fps; g.advance(now: now, input: input) }
                distances.append(distance(SIMD2(g.player.position.x, g.player.position.z), start))
            }
            check((distances.max()! - distances.min()!) / distances.max()! < 0.03, "movement is frame-rate independent (30/60/144 fps: \(distances.map { String(format: "%.2f", $0) }) m)")
        }
    }
}
