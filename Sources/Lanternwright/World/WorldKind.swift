import simd

/// The places you can be. Each has its own `Scene` (ground, props, puzzles) and its own `WorldParams` (light, sky, palette).
enum WorldKind: String, CaseIterable, Codable {
    case varrow        // The Isle of Varrow: golden-hour island with the lighthouse
    case glassWood     // The Glass Wood: a moonlit crystal forest, reached through the lens
}

/// Everything about a world's atmosphere that the renderer needs. The renderer treats the main light as "the sun"
/// even in a night world, where it is really the bigger moon: same direction/colour/irradiance machinery, different numbers.
struct WorldParams {
    var name: String
    var sunElevation: Float          // degrees above the horizon
    var sunAzimuth: Float            // degrees clockwise from north
    var sunIrradiance: Float         // 22 = a low evening sun; about 3 = bright moonlight (exposure compensates)
    var lightTint: SIMD3<Float>?     // nil = filter the light through the atmosphere (orange at a low sun); otherwise fixed
    var exposure: Float
    var bloom: Float
    var fogDensity: Float
    var fogFalloff: Float
    var godRays: Float
    var starAmount: Float            // 0 = no stars
    var lightDiskScale: Float        // brightness of the main light's disc in the sky
    var lightDiskRadius: Float       // its angular radius in radians (the sun is 0.00465; a moon looks much bigger here)
    var secondMoon: (elevation: Float, azimuth: Float, radius: Float)?
    var palette: Float               // 0 = Varrow's greens/sands, 1 = the Glass Wood's teals and violets
    var spawn: (position: SIMD3<Float>, yaw: Float)

    static func make(_ kind: WorldKind, options: LaunchOptions) -> WorldParams {
        switch kind {
        case .varrow:
            return WorldParams(name: "The Isle of Varrow", sunElevation: options.sunElevation, sunAzimuth: options.sunAzimuth,
                               sunIrradiance: Atmosphere.sunIrradiance, lightTint: nil, exposure: LookDefaults.exposure,
                               bloom: LookDefaults.bloomStrength, fogDensity: LookDefaults.fogDensity, fogFalloff: LookDefaults.fogHeightFalloff,
                               godRays: LookDefaults.godRayStrength, starAmount: 0, lightDiskScale: 1, lightDiskRadius: 0.00465,
                               secondMoon: nil, palette: 0, spawn: (Layout.dockEnd, Layout.spawnYaw))
        case .glassWood:
            return WorldParams(name: "The Glass Wood", sunElevation: 38, sunAzimuth: 118, sunIrradiance: 3.2,
                               lightTint: SIMD3(0.55, 0.72, 1.0), exposure: 2.6, bloom: 0.10, fogDensity: 0.0022, fogFalloff: 0.012,
                               godRays: 0.12, starAmount: 1, lightDiskScale: 0.22, lightDiskRadius: 0.034,
                               secondMoon: (elevation: 21, azimuth: 214, radius: 0.019), palette: 1,
                               spawn: (GlassLayout.arrival, 0))
        }
    }
}
