import Foundation
import simd

/// F09.1: the interaction contract. Every interactable of every world has a visible prop that the reticle ray hits from the guided corridor, within reach; every visible readable/usable prop has a box.
/// The audit must be able to fail: a box moved 3 m off its prop, and a box with no prop at all, are both reported.
extension SelfTestRunner {
    func runInteractables() {
        guard name == "all" || name == "interactables" else { return }
        let scenes: [WorldKind: Scene] = [.varrow: Scene.make(.varrow, device: device), .glassWood: Scene.make(.glassWood, device: device), .tideArchive: Scene.make(.tideArchive, device: device)]
        let game = Game(scenes: scenes)
        for p in 0..<2 { scenes[.glassWood]!.update("gw_altar_\(p == 0 ? "ilse" : "oren")") { $0.uniforms.model = GlassPuzzleProps.pedestalModel(p, rise: 1) } }
        var results: [WorldKind: InteractableAudit.Result] = [:]
        for kind in WorldKind.allCases {
            if game.world != kind { game.travel(to: kind) }
            let list = game.interactables
            let r = InteractableAudit.audit(kind, scene: scenes[kind]!, interactables: list)
            results[kind] = r
            let bad = r.rows.filter { !$0.verdict }.map { "\($0.id): \($0.hit)" } + r.orphans.map { "unboxed \($0.item)" }
            check(bad.isEmpty, "interactables \(kind.rawValue): every box has a visible prop the reticle ray hits from the corridor, and every usable prop has a box (\(r.rows.count) checked; \(bad.prefix(4)))")
        }
        check((results[.varrow]?.rows.count ?? 0) >= 15 && (results[.glassWood]?.rows.count ?? 0) >= 15 && (results[.tideArchive]?.rows.count ?? 0) >= 15, "interactables: the audit looked at every world's boxes")
        check(results[.varrow]?.rows.contains { $0.id == "lens_ring" && $0.verdict } == true, "interactables: the lighthouse interior's lens ring is audited from the lens room")

        // #95 (a blade of grass through a page): pages 10-14 lie on the graded route strip, where no grass grows (path weight 1 within 1.2 m of the centreline).
        let archive = scenes[.tideArchive]!
        for n in 10...14 {
            let p = TideSpots.page(n)
            check(archive.terrain.pathWeight(x: p.x, z: p.z) > 0.99, "interactables: page \(n) lies on the route's grass-free strip (path weight \(String(format: "%.2f", archive.terrain.pathWeight(x: p.x, z: p.z))) at \(Int(p.x)), \(Int(p.z)))")
        }

        // A bot that plays like a player: from the lamp end it walks the guided route to the audit's standing place for each page and tool, puts the RETICLE on a visible point of the prop (no aiming at the
        // box), and requires that what the crosshair picks is that interactable and that a click does something. No teleport.
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)])
        g.travel(to: .tideArchive)
        let bot = PlaythroughBot(g); bot.wait(1.0)
        let rows = InteractableAudit.audit(.tideArchive, scene: g.scene, interactables: g.interactables).rows
        let order = ["ta_return_ilse", "page_10", ChainMap.interactableName == "" ? "" : "page_11", TideArchivePuzzle.findForkName, "page_12", "page_13", "page_14", ChainMap.interactableName, TideArchivePuzzle.findLensName]
        for id in order where !id.isEmpty {
            guard let row = rows.first(where: { $0.id == id }), let stand = row.stand, let it = bot.interactable(id) else { check(false, "interactables bot: \(id) exists in the Archive"); continue }
            let came = bot.walk(to: SIMD3(stand.x, 0, stand.y), within: 0.8, timeout: 400)
            guard let target = InteractableAudit.reticle(eye: g.camera.position, it: it, scene: g.scene) else { check(false, "interactables bot: from \(bot.feet) (\(came ? "walked" : "stopped short")) the bot sees no prop for \(id)"); continue }
            bot.aim(at: target.point); bot.tick()
            let hover = g.hovered?.id
            check(came && hover == id, "interactables bot: walking the route to \(id), the reticle on \(target.item) picks it (hover \(hover ?? "-"), prompt \"\(g.hovered?.prompt ?? "")\")")
            if id.hasPrefix("page_") {
                _ = bot.click(id); bot.wait(0.3); bot.closeJournal()
                check(g.state.has(id) || g.journal.collectedPages.contains { "page_\($0.number)" == id }, "interactables bot: a click on the page under the reticle collects \(id)")
            }
        }

        // The audit can fail. Each Archive box moved 3 m sideways is no longer on its prop; a box in the open air has no prop; a prop with its box deleted is reported.
        game.travel(to: .tideArchive)
        let sc = scenes[.tideArchive]!
        let list = game.interactables
        for id in [TideArchivePuzzle.findForkName, "page_11", ChainMap.interactableName, "ta_return_ilse"] {
            var moved = list
            guard let i = moved.firstIndex(where: { $0.id == id }) else { check(false, "interactables mutation: \(id) exists"); continue }
            moved[i].min.x += 3; moved[i].max.x += 3
            let r = InteractableAudit.audit(.tideArchive, scene: sc, interactables: moved)
            check(r.rows.first { $0.id == id }?.verdict == false && !r.orphans.isEmpty, "interactables mutation: '\(id)' moved 3 m off its prop FAILS (and its prop is reported unboxed)")
        }
        var air = list
        air.append(Interactable(id: "nothing_here", min: SIMD3(0.5, 40, 100), max: SIMD3(1.5, 41, 101), prompt: "Touch nothing", reach: 3.4))
        check(InteractableAudit.audit(.tideArchive, scene: sc, interactables: air).rows.last?.verdict == false, "interactables mutation: a prompt box in empty air FAILS")
        let withoutMap = list.filter { $0.id != ChainMap.interactableName }
        check(InteractableAudit.audit(.tideArchive, scene: sc, interactables: withoutMap).orphans.contains { $0.item == "ti_chain_map" }, "interactables mutation: a visible chain map with no box is reported")
    }
}
