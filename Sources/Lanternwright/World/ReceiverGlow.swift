import Metal
import simd

/// P02.1 / F10 A2: the mirror court's three RECEIVING CRYSTALS. Each stands on its own pedestal and lights the instant the beam reaches it (P02 section 3: live feedback, solved when all three
/// are lit at once), so the player can reason the court out from partial lights.
///
/// The contract with the court logic (builder B): once per frame call `ReceiverGlow.set(scene, k, level:, color:)` for k in 0..<3.
///   - `level` 0 = dormant (a dull cold crystal, nothing arrives), 0...1 = light arriving (1 = fully lit); a fraction can be a fade-in or a flutter, B decides;
///   - `color` is the light that arrived: `GlassPuzzleProps.color(segmentColor)` (moonlight if no pane was met), so the crystal shows the colour the pane gave the beam;
///   - `blaze: true` is the solved state: every crystal white-warm and brighter than any single hit.
/// `cells` is the ONE place the crystals' court cells live: B's trace should end a beam on `cells[k]` for receiver k (change a cell here and the crystal moves with it; the cell must not be a mirror,
/// pane or the prism cell). Nothing here touches the court logic; the old single orb `gw_receiver` is retired (B2).
enum ReceiverGlow {
    /// The three crystals' court cells: the court's own receivers (`MirrorCourt.receivers`, the one source of truth since B2 / P02.1: the beam passes through them and each lights for its own colour).
    static let cells: [MirrorCourt.Cell] = MirrorCourt.receivers
    static let count = 3
    static func name(_ k: Int) -> String { "gw_crystal_\(k)" }
    static func ringName(_ k: Int) -> String { "gw_crystal_ring_\(k)" }
    static var allNames: [String] { (0..<count).flatMap { [name($0), ringName($0)] } }
    static func position(_ k: Int) -> SIMD3<Float> { MirrorCourt.world(cells[k]) }

    /// Where the crystal's body sits above the court floor (its centre), and its emissive strength dormant / lit / blazing.
    static let crystalY: Float = 1.75
    static let dormantStrength: Float = 0.25, litStrength: Float = 3.4, blazeStrength: Float = 8.0
    static let dormantColor = SIMD3<Float>(0.22, 0.27, 0.40)
    /// The surface colour (the tint) dormant and lit: a dormant crystal is dark glass, a lit one clear.
    static let dormantTint = SIMD4<Float>(0.14, 0.17, 0.26, 1)
    static let blazeColor = SIMD3<Float>(1.0, 0.95, 0.8)

    /// The emissive (colour, strength) at a level: a dull crystal that only brightens above about a fifth of the level, so a flutter near 0 still reads as dark.
    static func emissive(level: Float, color: SIMD3<Float>, blaze: Bool) -> SIMD4<Float> {
        if blaze { return SIMD4(blazeColor, blazeStrength) }
        let l = min(max(level, 0), 1), u = l * l * (3 - 2 * l)
        // Bloom and the tonemap wash a bright hue toward white, so a lit crystal's colour is deepened (squared, as the beams are) to stay readable as the pane's colour.
        let deep = color * color * 1.3
        let c = dormantColor + (deep - dormantColor) * u
        return SIMD4(c, dormantStrength + (litStrength - dormantStrength) * u)
    }

    /// Drives crystal k (the single call builder B makes, once per frame). Unknown k is ignored. The inlaid ring round the pedestal follows the crystal.
    static func set(_ scene: Scene, _ k: Int, level: Float, color: SIMD3<Float> = GlassPuzzleProps.moonlight, blaze: Bool = false) {
        guard (0..<count).contains(k) else { return }
        let e = emissive(level: level, color: color, blaze: blaze)
        let l = min(max(level, 0), 1), u = blaze ? 1 : l * l * (3 - 2 * l)
        scene.update(name(k)) { $0.uniforms.emissive = e; $0.uniforms.tint = dormantTint + (SIMD4(1, 1, 1, 1) - dormantTint) * u }
        scene.update(ringName(k)) { $0.uniforms.emissive = SIMD4(e.x, e.y, e.z, blaze ? 3.0 : e.w * 0.45) }
    }

    /// Builds the three pedestals (fixed, one mesh) and the crystals and their rings (one item each, so each can be lit alone). Called from `GlassPuzzleProps.addMirrorCourt`.
    static func add(to scene: Scene, device: MTLDevice) {
        let stone = GlassPuzzleProps.frost(), pale = GlassPuzzleProps.pale
        var base = MeshBuilder()
        for k in 0..<count {
            let p = position(k) - GlassLayout.mirrorCourt
            // A stepped pedestal like the old receiver's but smaller: a foot, a waist, a collar that holds the crystal.
            base.lathe(profile: [SIMD2(0.80, 0), SIMD2(0.80, 0.12), SIMD2(0.62, 0.12), SIMD2(0.62, 0.2), SIMD2(0.40, 0.3), SIMD2(0.34, 0.95), SIMD2(0.46, 0.95), SIMD2(0.46, 1.04), SIMD2(0, 1.04)],
                       segments: 12, smooth: false, surface: stone, transform: translation(p))
            base.torus(major: 0.56, minor: 0.018, segments: 24, sides: 6, surface: pale, transform: translation(p + SIMD3(0, 0.205, 0)))
        }
        scene.add("gw_crystal_bases", mesh: base.build(device: device, label: "crystal bases"), uniforms: ObjectUniforms(model: translation(GlassLayout.mirrorCourt)))
        // The crystal: a six-sided double point (a cut stone standing on its edge), emissive glass; the ring: a thin torus inlaid in the pedestal's foot.
        var crystal = MeshBuilder()
        crystal.lathe(profile: [SIMD2(0, -0.62), SIMD2(0.30, -0.20), SIMD2(0.30, 0.20), SIMD2(0, 0.74)], segments: 6, smooth: false,
                      surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.05, material: .emissiveGlass))
        var ring = MeshBuilder()
        ring.torus(major: 0.70, minor: 0.03, segments: 32, sides: 6, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.2, material: .emissiveGlass), transform: translation(SIMD3(0, 0.125, 0)))
        let crystalMesh = crystal.build(device: device, label: "receiver crystal"), ringMesh = ring.build(device: device, label: "receiver ring")
        let dormant = emissive(level: 0, color: SIMD3(1, 1, 1), blaze: false)
        for k in 0..<count {
            let p = position(k)
            scene.add(name(k), mesh: crystalMesh, uniforms: ObjectUniforms(model: translation(p + SIMD3(0, crystalY, 0)), tint: dormantTint, emissive: dormant))
            scene.add(ringName(k), mesh: ringMesh, uniforms: ObjectUniforms(model: translation(p), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(dormant.x, dormant.y, dormant.z, dormant.w * 0.45)))
        }
    }
}
