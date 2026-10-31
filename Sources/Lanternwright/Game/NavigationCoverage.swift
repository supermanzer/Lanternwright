import simd

/// M10.3: every place the player must be able to stand in each world, taken from the game's own data (no positions of its own). If a corridor misses one of these,
/// confinement (M10.4) would be a soft lock, so the selftest checks that each is inside the network and connected to the spawn, and M10.6's `--nav-audit` extends it
/// with every interactable and the vantage lines of sight.
enum NavCoverage {
    struct Point { var name: String; var position: SIMD3<Float> }

    static func points(for kind: WorldKind, scene: Scene) -> [Point] {
        switch kind {
        case .varrow:
            var pts = [Point(name: "spawn (dock end)", position: Layout.dockEnd), Point(name: "dock shore", position: Layout.dockShore),
                       Point(name: "causeway start", position: Layout.causewayStart), Point(name: "lens", position: Layout.isletCenter),
                       Point(name: "arrival from the Glass Wood", position: Layout.isletCenter + SIMD3(0, 0, 5)),
                       Point(name: "lighthouse door", position: Layout.lighthouse + SIMD3(0, 0, Lighthouse.wallR(2.0) + 1))]
            for id in StoneID.allCases { pts.append(Point(name: "\(id.name) stone", position: id.position)) }
            for n in StoryPages.varrowIDs { pts.append(Point(name: "page \(n)", position: PuzzleProps.pageBase(n, terrain: scene.terrain))) }
            let plan = PuzzleProps.causewayPlan(terrain: scene.terrain)
            for k in 0..<PuzzleProps.slabCount { let c = plan.center(k); pts.append(Point(name: "causeway slab \(k)", position: SIMD3(c.x, 0, c.y))) }
            return pts
        case .tideArchive:
            var pts = [Point(name: "spawn (lamp end)", position: ArchiveLayout.lampEnd), Point(name: "open end", position: ArchiveLayout.openEnd), Point(name: "landing", position: ArchiveLayout.landing),
                       Point(name: "the stacks", position: ArchiveLayout.stacks), Point(name: "Great Ledger gallery", position: ArchiveLayout.greatLedger),
                       Point(name: "upper lamp", position: ArchiveLayout.upperLamp), Point(name: "dome", position: ArchiveLayout.dome), Point(name: "prism chamber", position: ArchiveLayout.prismChamber)]
            for (k, s) in ArchiveLayout.sluices.enumerated() { pts.append(Point(name: "sluice \(k)", position: s)) }
            return pts
        case .glassWood:
            var pts = [Point(name: "spawn (arrival)", position: GlassLayout.arrival), Point(name: "return lens", position: GlassLayout.returnLens),
                       Point(name: "junction", position: GlassLayout.junction), Point(name: "altar", position: GlassLayout.altar)]
            for k in 0..<3 {
                pts.append(Point(name: "mirror \(k)", position: GlassPuzzleProps.mirrorPosition(k)))
                pts.append(Point(name: "pane \(k)", position: GlassPuzzleProps.panePosition(k)))
            }
            pts.append(Point(name: "prism source", position: MirrorCourt.world(MirrorCourt.source)))
            pts.append(Point(name: "receiver", position: MirrorCourt.world(MirrorCourt.receiver)))
            for k in 0..<5 { pts.append(Point(name: "chime \(k)", position: GlassPuzzleProps.chimePosition(k))) }
            for n in StoryPages.glassIDs { pts.append(Point(name: "page \(n)", position: GlassPuzzleProps.pageBase(n))) }
            return pts
        }
    }
}
