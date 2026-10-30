import Metal
import simd
import Foundation

/// S03.7 (user decision 1, 2026-10-28: Oren's exit is a lens portal in the lens room, not an arch at the dock; no arch prop existed at the dock, so none was removed). What stands in the lens
/// room round the ring: the RECEIVER on the north-east glass with three small gate lamps, a faint BEAM PREVIEW along the ring's pointer, and the PORTAL, a doorway of turned light in the
/// north window that appears when the beam has rested on the receiver for 2 s. Everything is in the tower's frame round `Layout.lighthouse` (the numbers are the ring's own: see
/// `LighthouseInterior` for the room). All of it is hidden until the lighthouse door is open (the portal until it has opened). Builder A may restyle the portal with the beam and glass shaders
/// (asked on board topic `story`); the placeholder is a pale emissive doorway.
enum LensPortalProps {
    /// Angles are `atan2(dz, dx)` in the tower's frame (x east, z south): north is -pi/2, clockwise seen from above is increasing.
    static let initialRingAngle: Float = -.pi / 2
    static let receiverAngle: Float = -.pi / 4
    /// One click (or arrow key) turns the ring a twelfth of a turn: the receiver is three steps clockwise of where the ring starts.
    static let ringStep: Float = .pi / 12
    /// The beam counts as on the receiver within 3 degrees, for 2 seconds.
    static let tolerance: Float = 3 * .pi / 180
    static let holdSeconds: Float = 2.0
    /// Where the beam is drawn: at the ring's height; the receiver's centre and the glass it stands against.
    static let beamRadius: (inner: Float, outer: Float) = (0.92, 2.0)

    static let portalHeight: Float = 2.1
    static let receiverName = "lh_receiver", beamName = "lh_ring_beam", portalName = "lh_portal"
    static let lampNames = ["lh_gate_lamp_0", "lh_gate_lamp_1", "lh_gate_lamp_2"]
    /// F06 B3 (Q24): the two exits take a light each while the gate is ready: a ring of warm beads round the lens (Ilse's exit) and a cool lit rim on the receiver's plate (Oren's exit). Hidden otherwise.
    static let lensBeadsName = "lh_exit_lens_beads", receiverRimName = "lh_exit_receiver_rim"

    static var ringY: Float { LighthouseInterior.lensFloorY + LighthouseInterior.ringHeight }
    /// A frame at angle `a`, radius `r`, height `y` above the tower's foot, whose local z points at the tower's axis (a thing standing on the glass facing in).
    static func onGlass(_ a: Float, _ r: Float, _ y: Float) -> float4x4 {
        translation(Layout.lighthouse + SIMD3(cos(a) * r, y, sin(a) * r)) * rotationY(atan2(-cos(a), -sin(a)))
    }

    /// The halo quad's frame (see the beam shader's mode 3): its floor-centre origin a hand in front of the doorway's face, right = half its width (1.7 m), up = its height (3.4 m).
    static func haloModel() -> float4x4 {
        let f = onGlass(LighthouseInterior.portalAngle, 2.02, LighthouseInterior.lensFloorY)
        let x = SIMD3(f.columns.0.x, f.columns.0.y, f.columns.0.z), z = SIMD3(f.columns.2.x, f.columns.2.y, f.columns.2.z)
        let o = SIMD3(f.columns.3.x, f.columns.3.y, f.columns.3.z) + z * 0.05
        return float4x4(columns: (SIMD4(x * 1.7, 0), SIMD4(0, 3.4, 0, 0), SIMD4(z, 0), SIMD4(o, 1)))
    }

    static func build(into scene: Scene, device: MTLDevice) {
        let tools = LighthouseInterior.shownForTools
        let brass = Surface(color: SIMD3(0.55, 0.42, 0.18), roughness: 0.35, material: .paleMetal)
        let iron = Surface(color: SIMD3(0.05, 0.055, 0.07), roughness: 0.5, material: .iron)
        let lampSurface = Surface(color: SIMD3(0.5, 0.4, 0.2), roughness: 0.4, material: .paleMetal)

        // The receiver: a brass plate with an eye in it, on an iron post that stands on the floor against the glass.
        var rec = MeshBuilder()
        let top = ringY                                              // the plate is at the ring's height, so the beam preview ends ON it
        let f = onGlass(receiverAngle, 1.92, 0)
        rec.cylinder(radiusTop: 0.02, radiusBottom: 0.02, height: top - LighthouseInterior.lensFloorY, segments: 8, smooth: true, surface: iron, transform: f * translation(SIMD3(0, LighthouseInterior.lensFloorY, 0)))
        rec.box(size: SIMD3(0.24, 0.24, 0.035), surface: brass, transform: f * translation(SIMD3(0, top, 0.02)))
        rec.cylinder(radiusTop: 0.05, radiusBottom: 0.06, height: 0.03, segments: 20, smooth: true, surface: iron, transform: f * translation(SIMD3(0, top, 0.04)) * rotationX(.pi / 2))
        scene.add(receiverName, mesh: rec.build(device: device, label: "lens receiver"), uniforms: ObjectUniforms(model: matrix_identity_float4x4), hidden: !tools)

        // The three gate lamps above the plate: the altar, Ilse's pages, Oren's pages. Dark until what they stand for is true.
        for (k, name) in lampNames.enumerated() {
            var lamp = MeshBuilder()
            lamp.sphere(radius: 0.03, segments: 10, surface: lampSurface, transform: f * translation(SIMD3((Float(k) - 1) * 0.08, top + 0.19, 0.03)))
            scene.add(name, mesh: lamp.build(device: device, label: "gate lamp"), uniforms: ObjectUniforms(model: matrix_identity_float4x4), hidden: !tools)
        }

        // The exits' lights (F06 B3): hidden until `Game.syncExitLights` shows them. Warm beads in a ring round the lens; a cool rim round the receiver's plate.
        var beads = MeshBuilder()
        let beadSurface = Surface(color: SIMD3(1.0, 0.8, 0.45), roughness: 0.4, material: .paleMetal)
        for k in 0..<18 {
            let a = Float(k) / 18 * 2 * .pi
            beads.sphere(radius: 0.035, segments: 8, surface: beadSurface, transform: translation(SIMD3(cos(a) * 1.05, Landmarks.lensPosition.y - Layout.lighthouse.y - 0.1, sin(a) * 1.05)))
        }
        scene.add(lensBeadsName, mesh: beads.build(device: device, label: "lens beads"), uniforms: ObjectUniforms(model: translation(Layout.lighthouse)), hidden: !tools)
        var rim = MeshBuilder()
        let rimSurface = Surface(color: SIMD3(0.6, 0.8, 1.0), roughness: 0.4, material: .paleMetal)
        for s: Float in [-1, 1] {
            rim.box(size: SIMD3(0.34, 0.022, 0.02), surface: rimSurface, transform: f * translation(SIMD3(0, top + s * 0.16, 0.05)))
            rim.box(size: SIMD3(0.022, 0.34, 0.02), surface: rimSurface, transform: f * translation(SIMD3(s * 0.16, top, 0.05)))
        }
        scene.add(receiverRimName, mesh: rim.build(device: device, label: "receiver rim"), uniforms: ObjectUniforms(model: matrix_identity_float4x4), hidden: !tools)

        // The beam preview: a thin pale ribbon from the ring outward along its pointer (turned with the ring: the model is a rotation about the axis).
        var beam = MeshBuilder()
        beam.box(size: SIMD3(beamRadius.outer - beamRadius.inner, 0.012, 0.014), surface: Surface(color: SIMD3(1.0, 0.92, 0.7), roughness: 0.3, material: .paleMetal),
                 transform: translation(SIMD3((beamRadius.outer + beamRadius.inner) / 2, ringY, 0)))
        var bu = ObjectUniforms(model: translation(Layout.lighthouse) * rotationY(-initialRingAngle))
        bu.emissive = SIMD4(1.0, 0.9, 0.6, 1.2)
        scene.add(beamName, mesh: beam.build(device: device, label: "ring beam"), uniforms: bu, hidden: !tools)

        // The portal: a doorway of turned light in the north window: a door with a round head (`portalWidth` wide, `portalHeight` tall), glass-white. Its halo (BeamsPass, mode 3 of the beam shader) wraps it.
        var portal = MeshBuilder()
        let headR = LighthouseInterior.portalWidth / 2, straight = portalHeight - headR
        portal.box(size: SIMD3(LighthouseInterior.portalWidth, straight, 0.03), surface: Surface(color: SIMD3(0.92, 0.96, 1.0), roughness: 0.2, material: .emissiveGlass), transform: translation(SIMD3(0, straight / 2 - portalHeight / 2, 0)))
        portal.cylinder(radiusTop: headR, radiusBottom: headR, height: 0.03, segments: 28, smooth: true, surface: Surface(color: SIMD3(0.92, 0.96, 1.0), roughness: 0.2, material: .emissiveGlass),
                        transform: translation(SIMD3(0, straight - portalHeight / 2, 0)) * rotationX(.pi / 2) * translation(SIMD3(0, -0.015, 0)))
        var pu = ObjectUniforms(model: onGlass(LighthouseInterior.portalAngle, 2.02, LighthouseInterior.lensFloorY + portalHeight / 2))
        pu.emissive = SIMD4(0.2, 0.3, 0.45, 1.0)          // dim: the doorway's light is the halo pass's (BeamsPass), this is the slab it is drawn over
        scene.add(portalName, mesh: portal.build(device: device, label: "lens portal"), uniforms: pu, hidden: !tools)
    }
}
