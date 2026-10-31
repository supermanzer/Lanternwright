import Foundation
import simd

/// Self-tests: the reachable region, the audit and the bot that follows the network (M10.6). The audit is the soft-lock guard: if an interactable, a page or a vantage
/// target ever falls outside the corridors, this fails.
extension SelfTestRunner {
    func runNavAudit() {
        guard name == "all" || name == "navaudit" else { return }
        func v(_ x: Float, _ z: Float) -> SIMD2<Float> { SIMD2(x, z) }

        // The audit itself, on both worlds: all clear, and it really looked at things.
        let reports = NavigationAudit.run(device: device)
        for r in reports {
            check(r.ok, "navaudit \(r.kind.rawValue): all clear (\(r.failures.count) problems: \(r.failures.prefix(3)))")
            if r.kind == .tideArchive {                                                                    // S04.1: the Archive has landmarks only; its interactables, vantages and props arrive with S04.3 / S04.6 / S04.8
                check(r.checkedPoints >= 11 && r.regionArea > 5_000 && r.regionArea < 40_000 && r.regionArea < r.landArea * 0.3,
                      "navaudit \(r.kind.rawValue): it checked \(r.checkedPoints) required places (0 interactables and 0 vantages until S04.3/S04.6/S04.8); region \(Int(r.regionArea)) of \(Int(r.landArea)) m2 of dry land")
                continue
            }
            check(r.checkedPoints >= 20 && r.checkedInteractables >= (r.kind == .varrow ? 9 : 18) && r.checkedVantages >= 3,
                  "navaudit \(r.kind.rawValue): it checked \(r.checkedPoints) required places, \(r.checkedInteractables) interactables and \(r.checkedVantages) vantages")
            check(r.regionArea > 5_000 && r.regionArea < 40_000 && r.regionArea < r.landArea * 0.3 && r.farthest > 150 && r.items > 100 && r.over20 > 0 && r.over20 >= r.over60 && r.over60 >= r.over150,
                  "navaudit \(r.kind.rawValue): numbers: region \(Int(r.regionArea)) of \(Int(r.landArea)) m2 of dry land, farthest \(Int(r.farthest)) m, \(r.items) items, beyond 20/60/150 m: \(r.over20)/\(r.over60)/\(r.over150)")
        }

        // The audit can fail. A network without the stones' plaza cannot reach the tide stone; a line through the tower is blocked; a line over it is not.
        let scene = Scene.makeWorld(device: device)
        let tide = Interactable(id: "stone_tide", min: Layout.tideStone - SIMD3(0.5, 0, 0.5), max: Layout.tideStone + SIMD3(0.5, 3, 0.5), prompt: "", reach: 3.5)
        let dockOnly = NavNetwork(trails: [Layout.Navigation.varrow.trails[0]], plazas: [], spawn: v(Layout.dockEnd.x, Layout.dockEnd.z))
        check(NavigationAudit.standingPlace(for: tide, scene: scene, net: dockOnly) == nil && NavigationAudit.standingPlace(for: tide, scene: scene, net: Layout.Navigation.varrow) != nil,
              "navaudit: an interactable outside the corridors is reported unreachable, and the real network reaches the tide stone")
        let lh = Layout.lighthouse
        check(NavigationAudit.blockedAt(from: SIMD3(lh.x, lh.y + 6, lh.z - 25), to: SIMD3(lh.x, lh.y + 6, lh.z + 25), scene: scene)?.contains("collider") == true,
              "navaudit: a line of sight through the lighthouse tower is reported blocked by a collider")
        check(NavigationAudit.blockedAt(from: SIMD3(lh.x, lh.y + 40, lh.z - 25), to: SIMD3(lh.x, lh.y + 40, lh.z + 25), scene: scene) == nil,
              "navaudit: the same line above the tower is clear")
        check(NavigationAudit.blockedAt(from: SIMD3(Layout.dockEnd.x, 3, Layout.dockEnd.z), to: SIMD3(lh.x, lh.y + 24, lh.z), scene: scene) == nil,
              "navaudit: the dock to the lighthouse's lantern room is clear (a collider the target stands in does not count)")

        // The region API.
        let region = ReachableRegion.make(.varrow, scene: scene)
        let net = Layout.Navigation.varrow
        var seed: UInt32 = 6_606
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) }
        var bad = 0
        for _ in 0..<2000 {
            let p = region.bounds.min - 100 + (region.bounds.max - region.bounds.min + 200) * v(rnd(), rnd())
            let d = region.distance(to: p)
            if abs(d - max(net.signedDistance(p) - Player.marginWidth, 0)) > 1e-4 || (d == 0) != region.contains(p) { bad += 1 }
        }
        check(bad == 0, "region: distance(to:) is the margin-buffered signed distance and contains(_:) means distance 0 (2000 random points)")
        check(region.contains(v(Layout.dockEnd.x, Layout.dockEnd.z)) && region.contains(v(Layout.lighthouse.x, Layout.lighthouse.z)) && !region.contains(v(0, 400)) && region.distance(to: v(0, 400)) > 100,
              "region: the spawn and the lighthouse are inside, a point at sea 400 m south is 100 m or more away")
        check(region.bounds.min.x < Layout.isletCenter.x - 30 && region.bounds.max.x > Layout.dockEnd.x && region.bounds.min.y < Layout.isletCenter.z - 30 && region.bounds.max.y > Layout.dockEnd.z,
              "region: the bounds hold the dock, the islet and everything between")
        check(region.maxEyeHeight > Layout.lighthouse.y + Player.eyeHeight - 0.5 && region.maxEyeHeight < Layout.lighthouse.y + 14,
              "region: maxEyeHeight is the highest ground in the region plus the eye (\(region.maxEyeHeight) m; the lighthouse pad is at \(Layout.lighthouse.y) m)")
        check(region.itemDistances.count == scene.items.count && region.minDistance(item: -1) == 0 && region.minDistance(item: scene.items.count) == 0, "region: there is a precomputed distance for each of the \(scene.items.count) scene items")
        // The per-item distances are exact (to the 2 m of the check's grid) and never overestimate: no point of the region is nearer to an item than its minDistance.
        var gridPoints: [SIMD2<Float>] = []
        var z = region.bounds.min.y
        while z <= region.bounds.max.y { var x = region.bounds.min.x; while x <= region.bounds.max.x { let p = v(x, z); if region.contains(p) { gridPoints.append(p) }; x += 4 }; z += 4 }
        var tooFar = 0, tooNear = 0, checked = 0
        for i in stride(from: 0, to: scene.items.count, by: 7) {
            let box = scene.items[i].worldBounds, c = (box.min + box.max) / 2, rad = simd_length(box.max - box.min) / 2
            let d = region.minDistance(item: i)
            let nearest = max(gridPoints.map { simd_length(SIMD2(c.x, c.z) - $0) - rad }.min()!, 0)          // an item that overlaps the region is at distance 0, not negative
            checked += 1
            if nearest < d - 1e-3 { tooNear += 1 }                      // a region point nearer than the reported distance: it overestimated
            if nearest > d + 6 { tooFar += 1 }                  // far more than the grid's resolution: it underestimated
        }
        check(tooNear == 0 && tooFar == 0 && checked > 40, "region: minDistance matches the geometry and never overestimates (\(checked) items checked, \(tooNear) overestimates, \(tooFar) too small)")
        let lighthouseItem = scene.items.indices.first { scene.items[$0].name.lowercased().contains("lighthouse") }
        check(lighthouseItem.map { region.minDistance(item: $0) } == 0, "region: the lighthouse itself is at distance 0 (\(lighthouseItem.map { scene.items[$0].name } ?? "no item named lighthouse"))")

        // The bot follows the trails: dock to the lighthouse door, with guidance on, never more than half a metre outside a corridor; and in the Glass Wood from the arrival to the altar.
        let g = Game(scene: scene)
        let bot = PlaythroughBot(g)
        bot.forgetStray()
        let door = SIMD3(Layout.lighthouse.x, Layout.lighthouse.y, Layout.lighthouse.z + Lighthouse.colliderRadius + Player.radius + 0.4)
        let arrived = bot.walk(to: door, within: 1.5, timeout: 400)
        check(arrived && bot.strayed <= 0.5, "bot: the spawn to the lighthouse door along the network arrives (\(arrived)) and never strays more than 0.5 m beyond a corridor edge (\(bot.strayed) m)")
        let gw = Game(scenes: [.varrow: scene, .glassWood: Scene.make(.glassWood, device: device)])
        gw.travel(to: .glassWood)
        let gbot = PlaythroughBot(gw)
        gbot.forgetStray()
        let altar = gbot.walk(to: GlassLayout.altar, within: 3, timeout: 400)
        check(altar && gbot.strayed <= 0.5, "bot: the Glass Wood arrival to the altar along the network arrives (\(altar)) and stays within the corridors (\(gbot.strayed) m)")
    }
}
