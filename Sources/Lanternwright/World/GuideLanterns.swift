import Metal
import simd
import Foundation

/// S04.8: the guides of the route world (S02 section 3, lever 3). On Ilse's route there is ONE lantern, Oren's, a little ahead of her along the corridor, always ahead, never reached: "he left me". On Oren's
/// route there are LAMPS Ilse left lit, one at every stand along the corridor, each coming on as he draws near: "she would not follow", yet the lamps are there. Neither can be reached or spoken to: they
/// are light, not characters. Both follow the world's Navigation corridor (`path`), so they lead where the corridor leads and nowhere else.
///
/// The logic here is pure (a path in, positions and states out) and tested; `Game.syncGuides` drives the scene items every frame; the items are built hidden by `build` (the Archive's world calls it; until it
/// lands the stand-in Glass Wood does, behind `Game.tideArchiveEnabled`).
struct GuidePath {
    let points: [SIMD2<Float>]
    let cumulative: [Float]
    var length: Float { cumulative.last ?? 0 }

    init(_ pts: [SIMD2<Float>]) {
        var p: [SIMD2<Float>] = []
        for q in pts where p.last.map({ simd_length($0 - q) > 0.01 }) ?? true { p.append(q) }
        points = p
        var c: [Float] = [0]
        for i in 1..<max(p.count, 1) { c.append(c[i - 1] + simd_length(p[i] - p[i - 1])) }
        cumulative = p.isEmpty ? [] : c
    }

    /// The point `s` metres along the path (clamped to its ends).
    func point(at s: Float) -> SIMD2<Float> {
        guard let first = points.first else { return .zero }
        guard points.count > 1 else { return first }
        let t = min(max(s, 0), length)
        var i = 1
        while i < points.count - 1 && cumulative[i] < t { i += 1 }
        let seg = max(cumulative[i] - cumulative[i - 1], 1e-4)
        return points[i - 1] + (points[i] - points[i - 1]) * ((t - cumulative[i - 1]) / seg)
    }

    /// How far along the path the nearest point to `p` is.
    func progress(of p: SIMD2<Float>) -> Float {
        guard points.count > 1 else { return 0 }
        var best = Float.infinity, at: Float = 0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i], ab = b - a
            let t = min(max(simd_dot(p - a, ab) / max(simd_dot(ab, ab), 1e-6), 0), 1)
            let d = simd_length(p - (a + ab * t))
            if d < best { best = d; at = cumulative[i - 1] + t * simd_length(ab) }
        }
        return at
    }
}

enum GuideLanterns {
    /// Oren's lantern stays this far ahead of the player along the path (Ilse's route), and never reaches the path's end before the player does.
    static let ahead: Float = 14
    /// Ilse's lamps: one at every `spacing` m of path, lit when the player is within `litRange` m of it along the path, and kept lit once lit.
    static let spacing: Float = 26, litRange: Float = 34
    static let maxLamps = 12
    static let lanternName = "ti_guide_lantern"
    static func lampName(_ k: Int) -> String { "ti_guide_lamp_\(k)" }

    static func lanternDistance(playerProgress: Float, pathLength: Float) -> Float { min(playerProgress + ahead, pathLength) }
    static func lampCount(pathLength: Float) -> Int { min(maxLamps, max(0, Int((pathLength / spacing).rounded(.down)))) }
    static func lampDistance(_ k: Int) -> Float { spacing * Float(k + 1) }
    /// A lamp is lit while the player is nearer than `litRange` to it, or has passed it: it never goes out behind them.
    static func lampLit(_ k: Int, playerProgress: Float) -> Bool { playerProgress >= lampDistance(k) - litRange }

    /// The items: one lantern and `maxLamps` lamps, hidden until the game shows them. A small post with a cage and a core that is the light.
    static func build(into scene: Scene, device: MTLDevice, chainMap: Bool = true) {
        let hidden = true                                                  // `Game` shows what it needs: the guides while a route is on (syncGuides), the stand-in's map only when the Glass Wood stands in for the Archive
        let iron = Surface(color: SIMD3(0.05, 0.055, 0.07), roughness: 0.5, material: .iron)
        let glass = Surface(color: SIMD3(1.0, 0.82, 0.5), roughness: 0.3, material: .emissiveGlass)
        func lantern(post: Bool) -> MeshBuilder {
            var m = MeshBuilder()
            if post { m.cylinder(radiusTop: 0.03, radiusBottom: 0.04, height: 1.4, segments: 8, smooth: true, surface: iron, transform: matrix_identity_float4x4) }
            let y: Float = post ? 1.5 : 0
            m.box(size: SIMD3(0.2, 0.03, 0.2), surface: iron, transform: translation(SIMD3(0, y - 0.13, 0)))
            m.box(size: SIMD3(0.2, 0.03, 0.2), surface: iron, transform: translation(SIMD3(0, y + 0.13, 0)))
            for sx: Float in [-1, 1] { for sz: Float in [-1, 1] { m.box(size: SIMD3(0.02, 0.26, 0.02), surface: iron, transform: translation(SIMD3(sx * 0.09, y, sz * 0.09))) } }
            m.sphere(radius: 0.07, segments: 10, surface: glass, transform: translation(SIMD3(0, y, 0)))
            return m
        }
        // The chain map (S04.8, `ChainMap`): a slate slab on a post with the brass pins on it; read like the door note. Placed by the stand-in until the Archive's own spot lands.
        if chainMap {
            let slate = Surface(color: SIMD3(0.16, 0.19, 0.2), roughness: 0.8, material: .dressed)
            let brass = Surface(color: SIMD3(0.7, 0.55, 0.22), roughness: 0.35, material: .paleMetal)
            var map = MeshBuilder()
            map.cylinder(radiusTop: 0.05, radiusBottom: 0.07, height: 1.0, segments: 8, smooth: true, surface: iron, transform: matrix_identity_float4x4)
            map.box(size: SIMD3(1.1, 0.7, 0.05), surface: slate, transform: translation(SIMD3(0, 1.25, 0)) * rotationX(-0.35))
            for p in ChainMap.pins { map.sphere(radius: 0.025, segments: 8, surface: brass, transform: translation(SIMD3(Float(p.x - 0.5) * 1.0, 1.25 + Float(0.5 - p.y) * 0.6, 0.04)) * rotationX(0)) }
            let at = TideStandIn.mapPosition(scene: scene)
            scene.add(ChainMap.interactableName, mesh: map.build(device: device, label: "chain map"), uniforms: ObjectUniforms(model: translation(SIMD3(at.x, at.y - 0.5, at.z))), hidden: hidden)
        }
        var u = ObjectUniforms(model: matrix_identity_float4x4); u.emissive = SIMD4(1.0, 0.72, 0.3, 2.4)
        scene.add(lanternName, mesh: lantern(post: false).build(device: device, label: "guide lantern"), uniforms: u, hidden: hidden)
        for k in 0..<maxLamps {
            var l = ObjectUniforms(model: matrix_identity_float4x4); l.emissive = SIMD4(1.0, 0.72, 0.3, 0)
            scene.add(lampName(k), mesh: lantern(post: true).build(device: device, label: "guide lamp"), uniforms: l, hidden: hidden)
        }
    }
}
