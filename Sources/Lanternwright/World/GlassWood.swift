import Metal
import simd

/// Landmark positions in the Glass Wood. All heights derive from the base terrain function, so a pad always sits at the
/// natural height of the hills around it (no hand-tuned numbers that can drift out of agreement).
enum GlassLayout {
    static let noise = Noise(seed: 20_26)          // the seed Terrain uses by default
    static func groundY(_ x: Float, _ z: Float) -> Float { GlassTerrain.base(noise, x, z) }
    static func point(_ x: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, groundY(x, z), z) }

    static let arrival = point(0, 152)             // where the lens deposits you, facing north
    /// Inside the arrival pad (radius 10), where the ground is exactly flat at arrival.y, so the ring's height is exact.
    static let returnLens = SIMD3(arrival.x, arrival.y + 2.3, arrival.z - 6)
    static let mirrorCourt = point(-70, 20)
    static let junction = point(0, -45)
    static let chimeRing = point(70, 10)
    static let altar = point(0, -92)

    /// The walking route: arrival -> mirror court -> junction -> chime ring -> junction -> altar.
    static let path: [SIMD3<Float>] = [
        point(0, 152), point(0, 118), point(-38, 88), point(-68, 52), point(-70, 20), point(-48, -14), point(0, -45),
        point(45, -15), point(70, 10), point(45, -15), point(0, -45), point(0, -92),
    ]

    static let pads: [Layout.Pad] = [
        Layout.Pad(center: arrival, radius: 10),
        Layout.Pad(center: mirrorCourt, radius: 24),
        Layout.Pad(center: junction, radius: 8),
        Layout.Pad(center: chimeRing, radius: 16),
        Layout.Pad(center: altar, radius: 13),
    ]
}

enum GlassTerrain {
    static let center = SIMD2<Float>(0, 20)
    static let radius: Float = 215
    static let pool = SIMD2<Float>(0, 25)
    static let poolRadius: Float = 40
    static let seaFloor: Float = -24

    /// A gentle dome (11 m at the middle falling to the sea at 215 m) with a round pool dug into the middle.
    /// Anything below 0 m is under the ocean plane, so the pool is simply a depression that fills with water.
    static func base(_ noise: Noise, _ x: Float, _ z: Float) -> Float {
        let p = SIMD2(x, z)
        let wobble = noise.fbm(x * 0.006 + 11, z * 0.006 - 5, octaves: 4)
        let d = length(p - center) * (1 + 0.09 * wobble)
        var h: Float = d < radius
            ? 11 * pow(1 - smoothstep(30, radius, d), 1.2) + 2.5 * (1 - smoothstep(radius * 0.8, radius, d)) * smoothstep(0, 1, 1 - d / radius)
            : seaFloor * smoothstep(radius, radius + 110, d)
        h -= 16 * (1 - smoothstep(14, poolRadius, length(p - pool)))
        return h
    }
}

extension TerrainSpec {
    static let glassWood = TerrainSpec(pads: GlassLayout.pads, path: GlassLayout.path, seaFloor: GlassTerrain.seaFloor,
                                       baseHeight: GlassTerrain.base, rollingAmplitude: 5, cragAmplitude: 2)
}

enum GlassWood {
    static func build(device: MTLDevice) -> Scene {
        let scene = Scene(kind: .glassWood)
        scene.terrain = Terrain(spec: .glassWood)
        for chunk in TerrainMesh.buildChunks(terrain: scene.terrain, device: device) {
            scene.add(chunk.name, mesh: chunk.mesh, uniforms: chunk.uniforms)
        }
        addArrival(scene, device: device)
        return scene
    }

    /// A round stone plate where you arrive, and the ring that leads back to Varrow.
    static func addArrival(_ scene: Scene, device: MTLDevice) {
        let a = GlassLayout.arrival
        var plate = MeshBuilder()
        plate.cylinder(radiusTop: 3.6, radiusBottom: 3.9, height: 0.25, segments: 20, smooth: false,
                       surface: Surface(color: SIMD3(0.16, 0.17, 0.24), roughness: 0.4), transform: translation(SIMD3(0, -0.05, 0)))
        scene.add("gw_arrival_plate", mesh: plate.build(device: device, label: "arrival plate"), uniforms: ObjectUniforms(model: translation(a)))

        var ring = MeshBuilder()
        ring.torus(major: 0.95, minor: 0.12, segments: 36, sides: 10,
                   surface: Surface(color: SIMD3(0.8, 0.95, 1.0), roughness: 0.1, material: .emissiveGlass), transform: rotationX(.pi / 2))
        scene.add("gw_return_ring", mesh: ring.build(device: device, label: "return ring"),
                  uniforms: ObjectUniforms(model: translation(GlassLayout.returnLens), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.8, 0.5, 2.2)))
        var core = MeshBuilder()
        core.sphere(radius: 0.3, segments: 14, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.2))
        scene.add("gw_return_core", mesh: core.build(device: device, label: "return core"),
                  uniforms: ObjectUniforms(model: translation(GlassLayout.returnLens), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.85, 0.55, 5)))
    }
}
