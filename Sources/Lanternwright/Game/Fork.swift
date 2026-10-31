import Foundation
import simd

/// S03.8: the fork. Two ways to begin a route, both at the lighthouse, each only with the gate ready (S03.3):
///  - Ilse's: touch the lens above the ring in the lens room (S02 2.2: "touching the lens begins Ilse's route"; the RING is Oren's turning mechanism, so the lens itself is what Ilse touches);
///  - Oren's: with the lens portal open (S03.7), step into its doorway in the north window.
/// Beginning one sets `path_ilse` / `path_oren` (S03.1; the route's mood for builder A's later levers is `Game.chosenPath`) and SEALS the other exit for good: its plates or its receiver go
/// dark and stop answering (dimming only: no text, no warning; user decision 5). The player then enters the Glass Wood, which stands in for the route's world until it is built: at its
/// arrival pad for Ilse's route, at the altar end ("where the wood ends") for Oren's.
extension Game {
    static let lampLensName = "lh_lens_touch"
    /// How close to the glass, and how near the doorway's axis, the player must stand to be IN the portal: the player's feet reach 1.75 m from the axis, so 1.68 m is walking up to the glass
    /// (a player turning the ring stands about 1.3 to 1.5 m out and is not in it), and the doorway is `portalWidth` (1.1 m) wide: 0.32 rad either side of its axis at that radius.
    static let portalZone: (minRadius: Float, halfAngle: Float) = (1.68, 0.32)

    /// Ilse's exit is sealed once Oren's route has begun, and Oren's once Ilse's has.
    var platesSealed: Bool { chosenPath == .oren }
    var portalSealed: Bool { chosenPath == .ilse }

    /// S04.5: the world a route enters, and where the lens and the doorway lead back to until it is solved. It is the Tide Archive (S04.1, builder A); until that world exists it is the Glass Wood,
    /// which stands in for it (the one switch: set `routeWorldOverride` when the Archive's scene is passed to `Game(scenes:)`).
    nonisolated(unsafe) static var routeWorldOverride: WorldKind?
    var routeWorld: WorldKind { Game.routeWorldOverride ?? .glassWood }
    /// Set by the route world's puzzle when it is solved (S04.6; for the stand-in, a test or tool sets it): the lens and the doorway then no longer lead there, and the next lens on the ring is shown dim.
    static let routeSolvedFlag = "route_solved"
    var routeSolved: Bool { state.has(Game.routeSolvedFlag) }

    /// Where the route world is entered for a route: its pose (position, yaw): the lamp end for Ilse, the open end for Oren (S02 section 3, lever 1). The stand-in's two ends are its arrival pad and its altar end.
    static func routeEntry(_ author: PageAuthor) -> (position: SIMD3<Float>, yaw: Float) {
        author == .oren ? (GlassLayout.altar + SIMD3(0, 0, 7), 0) : (GlassLayout.arrival, 0)
    }

    /// Begin the route of `author` if the gate is ready and the other route has not been begun: seal the other exit, then fade through to the Glass Wood.
    @discardableResult
    func beginRoute(_ author: PageAuthor) -> Bool {
        guard world == .varrow, !isTraveling, scenes[routeWorld] != nil, gate.ready, choosePath(author) else { return false }
        pendingEntry = author
        syncSeals()
        fadeThrough(to: routeWorld)
        return true
    }

    /// S04.5: back from the route world before it is solved, the way in is the same one: Ilse's lens, Oren's open doorway. It leads there again (to the same end) until `routeSolved`; nothing is chosen
    /// again and the sealed exit stays sealed. Returns false if it does not (not on Varrow, travelling, no route, already solved, or no such world).
    @discardableResult
    func reenterRoute() -> Bool {
        guard tideArchive != nil, world == .varrow, !isTraveling, let route = chosenPath, !routeSolved, scenes[routeWorld] != nil else { return false }           // behind the flag: with it off nothing sets route_solved, so the old end state (the lens does nothing once a route is begun) stays
        pendingEntry = route
        fadeThrough(to: routeWorld)
        return true
    }

    /// Touching the lens in the lens room: Ilse's route if the gate is ready; otherwise the gate's quiet line (nothing before the altar), and nothing once a route is begun.
    func touchLampLens() {
        if let route = chosenPath {
            if route == .ilse { reenterRoute() }                                       // S04.5: Ilse's lens opens her world again until it is solved; once solved it does nothing
            return
        }
        if gate.ready { beginRoute(.ilse) } else if let cue = gate.cue { showBanner(cue) }
    }

    /// The player standing in the open portal's doorway steps through (checked every frame).
    func checkPortalStep() {
        guard lensPortal.isOpen, chosenPath == nil || (chosenPath == .oren && !routeSolved && tideArchive != nil), world == .varrow, !isTraveling, !journal.isOpen else { return }
        let p = player.position - Layout.lighthouse
        let r = (p.x * p.x + p.z * p.z).squareRoot()
        var d = abs(atan2(p.z, p.x) - LighthouseInterior.portalAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d = 2 * .pi - d }
        guard r >= Game.portalZone.minRadius, d <= Game.portalZone.halfAngle, abs(p.y - LighthouseInterior.lensFloorY) < 0.3 else { return }
        if chosenPath == nil { beginRoute(.oren) } else { reenterRoute() }               // S04.5: Oren's doorway stays open and leads back in until the world is solved
    }

    /// The sealed exit is dimmed (and dead: the plates and the ring check `platesSealed` / `portalSealed`): the plates' stone darkens, the receiver and its lamps go dark.
    func syncSeals() {
        guard let sc = scenes[.varrow] else { return }
        let dim = SIMD4<Float>(0.35, 0.35, 0.35, 1), normal = SIMD4<Float>(1, 1, 1, 1)
        sc.update("tone_plates") { $0.uniforms.tint = self.platesSealed ? dim : normal }
        sc.update(LensPortalProps.receiverName) { $0.uniforms.tint = self.portalSealed ? dim : normal }
    }
}
