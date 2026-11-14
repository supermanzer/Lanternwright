import Metal
import simd

/// F10.2: one look for every lens ring in the game (Varrow's islet lens, the Glass Wood's return lens, the Archive quays' return lenses). F09 frames showed the ring and its core flat white
/// (emissive 2.2 and 5 over a pale glass albedo, and a 14-segment sphere for a core, so the heart was a white polygon). Now the ring is brass lit from within (a brass surface with a
/// modest tinted emissive, 64 x 16 tessellation) and the heart is a smooth disc (`MeshBuilder.softDisc`, material 26: a warm-white centre falling off radially to a dim tint; 24 x 64 tessellation, and its rim tucks under the ring's
/// inner edge) on both faces, so no polygon outline shows and nothing is a flat white shape. Builder B drives only `emissive.w` of the ring and the disc by name (`Game.returnGlow`): the strengths below are the resting values.
enum LensLook {
    /// Resting emissive strengths (the old values were 2.2 and 5).
    static let ringBase: Float = 0.75, discBase: Float = 2.0
    /// The lit state of the Glass Wood's return lens after the altar (the old 6 and 11).
    static let ringLit: Float = 1.8, discLit: Float = 3.6
    static let ringMajor: Float = 0.95, ringMinor: Float = 0.12

    static let brass = Surface(color: SIMD3(0.62, 0.43, 0.17), roughness: 0.28, material: .paleMetal)
    /// The ring's own light is always brass-warm whatever colour the disc carries (A2, a review note on A1: a cool tint made the ring read pale cream, not brass, at 6 m).
    static let ringGlow = SIMD3<Float>(1.0, 0.66, 0.30)
    static func ringLight(_ tint: SIMD3<Float>) -> SIMD3<Float> { ringGlow * 0.75 + tint * 0.25 }

    static func ringMesh() -> MeshBuilder {
        var m = MeshBuilder()
        m.torus(major: ringMajor, minor: ringMinor, segments: 72, sides: 16, surface: brass, transform: rotationX(.pi / 2))
        return m
    }
    static func discMesh(radius: Float) -> MeshBuilder {
        var m = MeshBuilder()
        m.softDisc(radius: radius)
        m.softDisc(radius: radius, transform: rotationY(.pi))          // the back face (the pass culls back faces)
        return m
    }
    /// Adds `ringName` and `coreName` at `model`. `tint` is the light's colour (warm for Ilse, cool for Oren and the islet).
    static func add(to scene: Scene, device: MTLDevice, ringName: String, coreName: String, model: float4x4, tint: SIMD3<Float>, discRadius: Float = 0.86) {
        scene.add(ringName, mesh: ringMesh().build(device: device, label: ringName), uniforms: ObjectUniforms(model: model, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(ringLight(tint), ringBase)))
        scene.add(coreName, mesh: discMesh(radius: discRadius).build(device: device, label: coreName), uniforms: ObjectUniforms(model: model, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(tint, discBase)))
    }
}
