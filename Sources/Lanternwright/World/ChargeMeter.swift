import Metal
import simd

/// P02.4 / F10.3: the charge meters. While a receiver is being held (the lens room's ring resting on its receiver for `LensPortalProps.holdSeconds`, the Archive's prism ring resting on a
/// sluice's mark for `beamHold`) a soft light grows on it, and fades when the hold is broken, so the wait reads as a machine charging and not a timeout (P02 section 2.1 rule 4).
///
/// The contract with the hold logic (builder B): call `ChargeMeter.set(scene, name, level: x)` every frame with `x` in 0...1 (the held time over the hold time while it runs, then eased back
/// to 0 once broken; 0 hides the meter). That is the whole interface: the meter is one item per site, named below, a `softDisc` (material 26) whose size AND strength follow `level`, so a
/// NOTE: `set` does not follow the interior open/closed state: drive it to 0 when the hold ends or the lens room closes (or add `receiverName` to the hide list in `Game.syncInterior`). A level near 0 is a tiny bright spark, never a dark patch (the disc is opaque, so it is hidden at 0 rather than faded). `level` 1 is a full, bright lens.
enum ChargeMeter {
    /// The lens room's receiver (the eye of the brass plate on the lighthouse's lens-room glass).
    static let receiverName = "lh_charge_receiver"
    /// The Archive's prism chamber: one meter on each of the three marks (tide, wind, stone).
    static func prismName(_ k: Int) -> String { "ta_prism_charge_\(k)" }
    static var prismNames: [String] { (0..<3).map(prismName) }
    static var allNames: [String] { [receiverName] + prismNames }
    static func isMeter(_ name: String) -> Bool { name.hasPrefix("lh_charge_") || name.hasPrefix("ta_prism_charge_") }

    /// Full-size radius (metres) and full strength (emissive.w) of a meter at level 1, and the share of each at level 0 (the spark).
    static let receiverRadius: Float = 0.14, markRadius: Float = 0.30
    static let fullStrength: Float = 3.2, sparkShare: Float = 0.30
    static let warm = SIMD3<Float>(1.0, 0.86, 0.56)

    /// The meter's size factor (of its full radius) and emissive strength at `level`.
    static func scale(level: Float) -> Float { sparkShare * 0.15 + (1 - sparkShare * 0.15) * smooth(level) }
    static func strength(level: Float) -> Float { fullStrength * (sparkShare + (1 - sparkShare) * smooth(level)) }
    private static func smooth(_ x: Float) -> Float { let t = pow(min(max(x, 0), 1), 0.75); return t * t * (3 - 2 * t) }          // eased, and a little quicker to start so the first quarter already shows

    /// Drives one meter (the single call builder B makes). Unknown names are ignored. The model's scale is rewritten, its position and orientation are kept.
    static func set(_ scene: Scene, _ name: String, level: Float) {
        guard isMeter(name) else { return }
        scene.update(name) { item in
            guard level > 0.001 else { item.hidden = true; return }
            let s = scale(level: level)
            var m = item.uniforms.model
            func scaled(_ c: SIMD4<Float>) -> SIMD4<Float> { let n = simd_normalize(SIMD3(c.x, c.y, c.z)) * s; return SIMD4(n.x, n.y, n.z, 0) }
            m.columns = (scaled(m.columns.0), scaled(m.columns.1), scaled(m.columns.2), m.columns.3)
            item.uniforms.model = m
            item.uniforms.emissive = SIMD4(warm, strength(level: level))
            item.hidden = false
        }
    }

    private static func disc(radius: Float) -> MeshBuilder {
        var m = MeshBuilder()
        m.softDisc(radius: radius, rings: 16, segments: 48)
        return m
    }

    /// The lens room's meter: a disc on the receiver's eye, in the plate's own frame (its +z faces the room).
    static func addReceiver(to scene: Scene, device: MTLDevice, plate frame: float4x4, plateY: Float) {
        scene.add(receiverName, mesh: disc(radius: receiverRadius).build(device: device, label: receiverName),
                  uniforms: ObjectUniforms(model: frame * translation(SIMD3(0, plateY, 0.085)), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(warm, 0)), hidden: true)
    }
    /// One meter on each prism mark: `markModel` is the mark's own model (its +z faces the chamber).
    static func addPrismMark(_ k: Int, to scene: Scene, device: MTLDevice, markModel: float4x4) {
        scene.add(prismName(k), mesh: disc(radius: markRadius).build(device: device, label: prismName(k)),
                  uniforms: ObjectUniforms(model: markModel * translation(SIMD3(0, 0, 0.075)), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(warm, 0)), hidden: true)
    }
}
