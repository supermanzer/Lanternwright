import simd

// Swift mirrors of the structs in Shaders/Common.swift. Only float4 / float4x4 members:
// SIMD3 is 16 bytes in Swift but packed_float3 is 12 in MSL, and that mismatch fails silently.

struct Vertex {
    var position: SIMD4<Float>   // xyz, w = 1
    var normal: SIMD4<Float>     // xyz, w = material id
    var color: SIMD4<Float>      // rgb albedo (linear), a = roughness
    static let expectedStride = 48
}

struct FrameUniforms {
    var viewProj = matrix_identity_float4x4
    var invViewProj = matrix_identity_float4x4
    var sunViewProj = matrix_identity_float4x4
    var cameraPos = SIMD4<Float>(0, 0, 0, 0)   // w = time
    var sunDir = SIMD4<Float>(0, 1, 0, 1)      // toward sun, w = illuminance
    var sunColor = SIMD4<Float>(1, 1, 1, 0)
    var fogParams = SIMD4<Float>(LookDefaults.fogDensity, LookDefaults.fogHeightFalloff, LookDefaults.exposure, LookDefaults.bloomStrength)
    var screen = SIMD4<Float>(1, 1, 1, 1)
    var misc = SIMD4<Float>(0, LookDefaults.waveStrength, 0, 0)
    // Cascaded shadows: sunViewProj above is the FAR cascade (whole island); these are the two nearer ones.
    var sunViewProj0 = matrix_identity_float4x4     // near (about 14 m radius around the camera)
    var sunViewProj1 = matrix_identity_float4x4     // mid (about 70 m)
    var casTexel = SIMD4<Float>(0, 0, 0, 0)         // world size of one shadow texel for cascades 0, 1, 2
    var casRange = SIMD4<Float>(1, 1, 1, 0)         // depth range (m) of cascades 0, 1, 2
    var casRadius = SIMD4<Float>(14, 70, 340, 0)    // radius (m) of cascades 0, 1, 2
    // Per-world sky: x = star amount, y = main-light disc brightness, z = second moon's angular radius, w = main disc radius.
    var worldA = SIMD4<Float>(0, 1, 0, 0.00465)
    var moonB = SIMD4<Float>(0, 1, 0, 0)            // xyz = direction toward the second moon
    var worldB = SIMD4<Float>(0, 0, 0, 0)           // x = terrain palette (0 Varrow, 1 Glass Wood)
    static let expectedStride = 512
}

struct ObjectUniforms {
    var model = matrix_identity_float4x4
    var tint = SIMD4<Float>(1, 1, 1, 1)
    var emissive = SIMD4<Float>(0, 0, 0, 0)
    /// R09: x = 1 for the objects that are one level of a tree LOD set (the shader dithers between levels), y = their level index 0...2.
    var lod = SIMD4<Float>(0, 0, 0, 0)
    static let expectedStride = 112
}

/// The temporal anti-aliasing pass's own uniforms (F02 R1); a mirror of `TaaUniforms` in Shaders/TAA.swift. Kept out of `FrameUniforms` so that struct stays 512 bytes.
struct TaaUniforms {
    var prevViewProj = matrix_identity_float4x4
    var invViewProj = matrix_identity_float4x4
    var params = SIMD4<Float>(0, 0, 0, 0)    // x, y = jitter in pixels, z = history valid, w = sharpen strength
    var screen = SIMD4<Float>(1, 1, 1, 1)
    var tuning = SIMD4<Float>(0.10, 0.22, 1.25, 0)   // x = blend weight of the new frame when still, y = at speed, z = colour-box width (sigma multiples)
    static let expectedStride = 176
}

enum MaterialID: Float {
    case standard = 0, terrain = 1, emissiveGlass = 2, foliage = 3, bird = 4
    /// Procedural prop materials (see Shaders/Materials.swift).
    case masonry = 5, paint = 6, iron = 7, copper = 8, wood = 9, bark = 10, dressed = 11, plank = 12, timber = 13, glyphStone = 14, paper = 15, pebble = 16, glassStone = 17, mirror = 18, paleMetal = 19, glyphGlass = 20, rock = 21, slab = 22, needles = 23, post = 24, rope = 25
}

enum GPUTypes {
    static func validateLayouts() {
        precondition(MemoryLayout<Vertex>.stride == Vertex.expectedStride, "Vertex stride mismatch")
        precondition(MemoryLayout<FrameUniforms>.stride == FrameUniforms.expectedStride, "FrameUniforms stride mismatch")
        precondition(MemoryLayout<ObjectUniforms>.stride == ObjectUniforms.expectedStride, "ObjectUniforms stride mismatch")
        precondition(MemoryLayout<TaaUniforms>.stride == TaaUniforms.expectedStride, "TaaUniforms stride mismatch")
    }
}
