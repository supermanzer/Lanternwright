import Metal
import simd

/// F07 A-fold (#74: "That these pages appear after each puzzle is solved feels odd. Is it because Oren's pages are folded in the light?"): Oren's pages 6, 7 and 8 are in the Glass Wood from the start, as a pale
/// sheet folded in half and standing on its fold in the glass of the thing that holds it (the mirror court's receiver, the chime ring, the altar's dais): not readable, not collectable, one object each (two
/// panels). When their puzzle is solved the fold opens over `duration` seconds with a point of light running along the crease, and the readable page lies where the folded sheet was. A is the visual (this file) and
/// `Game` (builder B's page state) calls `begin` / `update` / `restFolded`: the hook is `PageFold.State`.
enum PageFold {
    static let numbers = [6, 7, 8]
    /// Seconds the fold takes to open, and how far each panel stands from the ground when folded (radians): a tent.
    static let duration: Float = 2.0, tentAngle: Float = 0.80
    static let panelWidth: Float = 0.34, panelDepth: Float = 0.23
    static func panelNames(_ n: Int) -> [String] { ["oren_fold_\(n)_a", "oren_fold_\(n)_b"] }
    static func lightName(_ n: Int) -> String { "oren_foldlight_\(n)" }
    static var allNames: [String] { numbers.flatMap { panelNames($0) + [lightName($0)] } }

    /// The panels' and the light's models for a fold `opened` 0 (closed tent) ... 1 (flat), the page's rest pose `base` (the hinge is the sheet's local z = 0 line). Panel a lies on +z, b on -z.
    static func panelModels(base: float4x4, opened: Float) -> (a: float4x4, b: float4x4) {
        let e = opened * opened * (3 - 2 * min(max(opened, 0), 1))                       // ease
        let angle = tentAngle * (1 - min(max(e, 0), 1))
        let rise = translation(SIMD3(0, panelDepth * sin(angle), 0))
        // Each panel is built with its hinge edge at z = 0 and its far edge at +-panelDepth; tilting by `angle` about the hinge (x axis) drops the far edge, so the crease is raised by depth x sin(angle).
        return (base * rise * rotationX(angle), base * rise * rotationX(-angle))
    }
    /// The point of light that runs along the crease: from one end of the sheet to the other as the fold opens (and gone by the time it is flat).
    static func lightModel(base: float4x4, opened: Float) -> float4x4 {
        let e = min(max(opened, 0), 1)
        let x = (e * 1.15 - 0.075 - 0.5) * panelWidth                                    // runs a little past each end
        let crease = panelDepth * sin(tentAngle * (1 - e * e * (3 - 2 * e)))
        return base * translation(SIMD3(x, crease + 0.012, 0))
    }

    /// Build the closed-fold items for page `n`, resting at `base` (the page's lie): two emissive pale panels and the running light (hidden until the fold opens).
    static func build(into scene: Scene, device: MTLDevice, page n: Int, base: float4x4) {
        let pale = Surface(color: SIMD3(0.86, 0.90, 0.97), roughness: 0.7, material: .paper)
        for (k, name) in panelNames(n).enumerated() {
            var b = MeshBuilder()
            b.box(size: SIMD3(panelWidth, 0.004, panelDepth), surface: pale, transform: translation(SIMD3(0, 0, (k == 0 ? 1 : -1) * panelDepth / 2)))
            var u = ObjectUniforms(model: panelModels(base: base, opened: 0).a, tint: SIMD4(1, 1, 1, 1))
            u.emissive = SIMD4(0.62, 0.78, 1.0, 0.55)                                    // light held in the fold: a faint cold glow, no bloom to speak of
            scene.add(name, mesh: b.build(device: device, label: "page fold"), uniforms: u, hidden: false)
        }
        var l = MeshBuilder()
        l.box(size: SIMD3(0.035, 0.012, 0.03), surface: pale, transform: matrix_identity_float4x4)
        var lu = ObjectUniforms(model: base)
        lu.emissive = SIMD4(1.0, 0.97, 0.88, 7)
        scene.add(lightName(n), mesh: l.build(device: device, label: "page fold light"), uniforms: lu, hidden: true)
    }

    /// Set the fold items of page `n` for `state`: `.folded` (the closed tent, shown), `.opening(p)` (the panels opening, the light running) or `.gone` (the readable page is there; nothing of the fold is shown).
    enum State: Equatable { case folded, opening(Float), gone }
    static func apply(_ state: State, page n: Int, base: float4x4, in scene: Scene) {
        let names = panelNames(n)
        switch state {
        case .folded:
            let m = panelModels(base: base, opened: 0)
            scene.update(names[0]) { $0.hidden = false; $0.uniforms.model = m.a }
            scene.update(names[1]) { $0.hidden = false; $0.uniforms.model = m.b }
            scene.update(lightName(n)) { $0.hidden = true }
        case .opening(let p):
            let m = panelModels(base: base, opened: p)
            scene.update(names[0]) { $0.hidden = false; $0.uniforms.model = m.a }
            scene.update(names[1]) { $0.hidden = false; $0.uniforms.model = m.b }
            let fade = min(1, (1 - p) * 4)                                                // the light dies away as the last of the fold opens
            scene.update(lightName(n)) { $0.hidden = false; $0.uniforms.model = lightModel(base: base, opened: p); $0.uniforms.emissive = SIMD4(1.0, 0.97, 0.88, 7 * max(fade, 0.02)) }
        case .gone:
            for name in names { scene.update(name) { $0.hidden = true } }
            scene.update(lightName(n)) { $0.hidden = true }
        }
    }
}
