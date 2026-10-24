import Metal
import simd

/// Builds the terrain as an 8x8 grid of chunk meshes (one DrawItem each, so they can be culled individually).
/// Vertex payload for material 1 (terrain): color.r = path weight, color.g = shore wetness, color.a = roughness.
enum TerrainMesh {
    static let chunksPerSide = 8

    static func buildChunks(terrain: Terrain, device: MTLDevice) -> [DrawItem] {
        let cells = Terrain.gridCount - 1                    // 512
        let per = cells / chunksPerSide                      // 64 cells per chunk side
        var items: [DrawItem] = []
        for cz in 0..<chunksPerSide {
            for cx in 0..<chunksPerSide {
                var verts: [Vertex] = []
                var idx: [UInt32] = []
                verts.reserveCapacity((per + 1) * (per + 1))
                for j in 0...per {
                    for i in 0...per {
                        let x = Terrain.origin + Float(cx * per + i) * Terrain.spacing
                        let z = Terrain.origin + Float(cz * per + j) * Terrain.spacing
                        let y = terrain.sampleHeight(x: x, z: z)
                        let n = terrain.normal(x: x, z: z)
                        let path = terrain.pathWeight(x: x, z: z)
                        let wet = 1 - smoothstep(0.6, 2.0, y)
                        verts.append(Vertex(position: SIMD4(x, y, z, 1),
                                            normal: SIMD4(n, MaterialID.terrain.rawValue),
                                            color: SIMD4(path, wet, terrain.duffAt(x: x, z: z), 0.9)))
                    }
                }
                let row = per + 1
                for j in 0..<per {
                    for i in 0..<per {
                        let a = UInt32(j * row + i), b = UInt32(j * row + i + 1)
                        let c = UInt32((j + 1) * row + i), d = UInt32((j + 1) * row + i + 1)
                        idx.append(contentsOf: [a, c, d, a, d, b])    // CCW seen from above (+Y)
                    }
                }
                let name = "terrain_\(cx)_\(cz)"
                items.append(DrawItem(name: name,
                                      mesh: Mesh(device: device, vertices: verts, indices: idx, label: name),
                                      uniforms: ObjectUniforms()))
            }
        }
        return items
    }
}
