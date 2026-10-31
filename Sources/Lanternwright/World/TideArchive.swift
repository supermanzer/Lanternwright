import Metal
import simd

/// S04.1: the Tide Archive's ground. A half-drowned observatory seen from the south: four terraces (plateaus joined by graded risers) climbing north from the quays at 1.8 m to the dome terrace at 22.5 m, inside
/// an oval island whose edge slips under the sea; the Great Ledger gallery is a court sunk into the second terrace's east side. The shared `Terrain` machinery does the rest (pads, the worn graded route, detail).
/// Anything below 0 m is under the ocean plane, as in the Glass Wood.
enum ArchiveTerrain {
    /// The terraces' heights, south to north (the plateaus), and where they sit along the spine from z = +southZ to -northZ.
    static let levels: [Float] = [1.8, 6.5, 12.0, 17.5, 22.5]
    static let southZ: Float = 135, northZ: Float = -140
    /// The sunken court of the Great Ledger gallery: its centre, half sizes, and floor height (above the sea, so the court is DRY until the water the gallery holds is added on top of it: S04.2).
    static let gallery = (centre: ArchiveLayout.greatLedgerXZ, half: SIMD2<Float>(22, 17), floor: Float(7.6))

    /// The large-scale shape before detail, the route's graded bench and the pads.
    static func base(_ noise: Noise, _ x: Float, _ z: Float) -> Float {
        let p = SIMD2(x, z)
        let t = min(max((southZ - z) / (southZ - northZ), 0), 1)
        let s = t * Float(levels.count - 1)
        let k = min(Int(floor(s)), levels.count - 2), f = s - Float(k)
        // A plateau for the first 72 % of each tier and then the riser (about 17 m for a 5 m rise: a slope of about 0.45 at its steepest; the route's graded bench takes it far more gently).
        var h = levels[k] + (levels[k + 1] - levels[k]) * smoothstep(0.72, 0.97, f)
        // The oval island: it falls into the sea beyond 0.8 of its half sizes and the sea floor beyond 1.
        let wobble = noise.fbm(x * 0.006 + 3, z * 0.006 - 9, octaves: 4)
        let d = length(SIMD2(x / 178, z / 178)) * (1 + 0.07 * wobble)
        h = mix(h, -3, smoothstep(0.8, 1.0, d))
        if d > 1 { h = -3 + (seaFloor + 3) * smoothstep(1.0, 1.65, d) }
        // The Great Ledger gallery: a rectangle sunk to its floor with walls blended over 5 m.
        let q = simd_abs(p - gallery.centre) - gallery.half
        let outside = simd_length(simd_max(q, SIMD2<Float>(0, 0))) + min(max(q.x, q.y), 0)
        h = mix(h, min(h, gallery.floor), 1 - smoothstep(0, 5, outside))
        // The sluice rooms: round chambers sunk to their floor (S04.2), walls blended over 10 m (slopes under 0.5); the sea's tide floods them by depth.
        for (k, c) in ArchiveLayout.sluiceSites.enumerated() {
            let r = simd_length(p - c)
            h = mix(h, min(h, ArchiveLayout.sluiceFloors[k]), 1 - smoothstep(ArchiveLayout.sluiceFlat, ArchiveLayout.sluiceFlat + ArchiveLayout.sluiceBlend, r))
        }
        return h
    }
    static let seaFloor: Float = -24
}

extension TerrainSpec {
    static let tideArchive = TerrainSpec(pads: ArchiveLayout.pads, path: ArchiveLayout.path, seaFloor: ArchiveTerrain.seaFloor, baseHeight: ArchiveTerrain.base, rollingAmplitude: 1.2, cragAmplitude: 0.5)
}

enum TideArchive {
    static func build(device: MTLDevice) -> Scene {
        let scene = Scene(kind: .tideArchive)
        scene.terrain = Terrain(spec: .tideArchive)
        for chunk in TerrainMesh.buildChunks(terrain: scene.terrain, device: device) {
            scene.add(chunk.name, mesh: chunk.mesh, uniforms: chunk.uniforms)
        }
        ArchiveProps.populate(scene, device: device)                       // S04.3
        SluiceLamps.build(into: scene, device: device)                     // S04 wiring (builder B): the lamp in each sluice room that answers the prism's beam
        return scene
    }
}
