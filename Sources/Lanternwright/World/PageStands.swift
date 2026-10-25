import simd

/// F02 P0: every journal page stands on a small stone lectern at waist height, larger than before, with a soft glow and rising motes (the user's saves showed
/// pages 1 and 4 to 8 never collected: a 34 x 46 cm sheet lying flat on the ground is easy to walk past). The lectern's foot is `base`; the page lies on its
/// tilted top, 0.84 m above the foot, turned toward `yaw` (the side a reader stands on is local +Z).
enum PageStands {
    static let pageHeight: Float = 0.84
    static let pageScale: Float = 1.5
    static let tilt: Float = 0.30
    static let colliderRadius: Float = 0.34

    /// Waist-high lectern: a footing slab, a shaft, a tilted top slab. Local frame: y = 0 at the foot, the slope falls toward +Z.
    static func mesh(stone: Surface, trim: Surface) -> MeshBuilder {
        var b = MeshBuilder()
        b.chamferBox(size: SIMD3(0.62, 0.12, 0.62), chamfer: 0.025, surface: trim, transform: translation(SIMD3(0, 0.06 - 0.3, 0)))          // footing (carried 0.3 m down: embedded)
        b.chamferBox(size: SIMD3(0.62, 0.42, 0.62), chamfer: 0.025, surface: trim, transform: translation(SIMD3(0, -0.1, 0)))
        b.chamferBox(size: SIMD3(0.36, 0.62, 0.36), chamfer: 0.02, surface: stone, transform: translation(SIMD3(0, 0.42, 0)))
        b.chamferBox(size: SIMD3(0.84, 0.08, 0.64), chamfer: 0.02, surface: stone, transform: translation(SIMD3(0, 0.80, 0)) * rotationX(tilt))
        b.chamferBox(size: SIMD3(0.84, 0.035, 0.05), chamfer: 0.01, surface: trim, transform: translation(SIMD3(0, 0.80, 0)) * rotationX(tilt) * translation(SIMD3(0, 0.05, 0.30)))   // the lip that holds the page
        return b
    }

    static func standTransform(base: SIMD3<Float>, yaw: Float) -> float4x4 { translation(base) * rotationY(yaw) }

    /// The page's own transform (it lies on the slab: translation to the slab centre, the slab's tilt, then up by the sheet's half thickness).
    static func pageTransform(base: SIMD3<Float>, yaw: Float) -> float4x4 {
        translation(base) * rotationY(yaw) * translation(SIMD3(0, 0.80, 0)) * rotationX(tilt) * translation(SIMD3(0, 0.05, 0)) * scaling(SIMD3(repeating: pageScale))
    }

    /// Yaw that turns a stand's +Z (the reader's side) toward `target` as seen from `base` (rotationY(yaw) maps +Z to (sin yaw, 0, cos yaw)).
    static func yaw(from base: SIMD3<Float>, toward target: SIMD3<Float>) -> Float { atan2(target.x - base.x, target.z - base.z) }

    /// World centre of the page for a stand at `base` (what the interactable box and the motes use).
    static func pagePosition(base: SIMD3<Float>) -> SIMD3<Float> { base + SIMD3(0, pageHeight, 0) }

    /// The mote: a tiny bright octahedron-ish speck, animated by the game (rises 1.6 m in 3.2 s and fades, two per page, half a cycle apart).
    static func moteMesh() -> MeshBuilder {
        var m = MeshBuilder()
        m.icosphere(subdivisions: 1, smooth: true, radius: { _ in 1 }, surface: Surface(color: SIMD3(1, 0.92, 0.7), roughness: 0.3), transform: scaling(SIMD3(repeating: 0.035)))
        return m
    }
    /// A thin tapering thread of light standing over the page (3 m tall), so a page can be seen from far along the path.
    static func beaconMesh() -> MeshBuilder {
        var b = MeshBuilder()
        b.cylinder(radiusTop: 0.02, radiusBottom: 0.09, height: 3.0, segments: 8, smooth: true, caps: false, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.5))
        return b
    }
    static func beaconTransform(centre: SIMD3<Float>) -> float4x4 { translation(centre + SIMD3(0, 0.15, 0)) }
    static let motePeriod: Float = 3.2
    /// Position and brightness (0...1) of mote `k` (0 or 1) at time `t` for a page at `centre`.
    static func mote(centre: SIMD3<Float>, page n: Int, k: Int, time t: Float) -> (position: SIMD3<Float>, brightness: Float) {
        let phase = (t / motePeriod + Float(k) * 0.5 + Float(n) * 0.137).truncatingRemainder(dividingBy: 1)
        let a = (phase * 2 + Float(k) * 1.7 + Float(n)) * .pi
        return (centre + SIMD3(0.14 * cos(a) * (0.4 + phase), 0.2 + 1.6 * phase, 0.14 * sin(a) * (0.4 + phase)), sin(.pi * phase))
    }
}
