import Foundation
import Metal

/// Compiles all MSL at launch. There is no offline `metal` compiler in Command Line Tools,
/// so shaders live as Swift strings and are compiled at runtime with makeLibrary(source:).
enum ShaderLibrary {
    static var sources: [String] {
        [CommonShaders.source, WindShaders.source, Shore.mslSource, SkyShaders.source, MaterialShaders.source, GroundShaders.source, LitShaders.source, GrassShaders.source, WaterShaders.source, CrystalShaders.source, MistShaders.source, BeamShaders.source, PostShaders.source, TAAShaders.source]
    }

    static func make(device: MTLDevice) -> MTLLibrary {
        let source = sources.joined(separator: "\n")
        let options = MTLCompileOptions()
        options.mathMode = .fast
        do {
            return try device.makeLibrary(source: source, options: options)
        } catch {
            // Errors reference lines of the concatenated source; dump it so they can be located.
            let dump = FileManager.default.temporaryDirectory.appendingPathComponent("lanternwright-shaders.metal")
            try? source.write(to: dump, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("shader compile failed (source: \(dump.path)):\n\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// A fragment function specialised on the `kLodDither` function constant (index 0): only tree LOD objects pay for the dithered cross-fade's
    /// `discard_fragment`, which would otherwise cost every opaque object its early depth rejection on Apple's tile-based GPU.
    static func function(_ library: MTLLibrary, _ name: String, lodDither: Bool) -> MTLFunction {
        let values = MTLFunctionConstantValues()
        var flag = lodDither
        values.setConstantValue(&flag, type: .bool, index: 0)
        guard let f = try? library.makeFunction(name: name, constantValues: values) else {
            FileHandle.standardError.write(Data("missing shader function \(name) (lodDither \(lodDither))\n".utf8))
            exit(1)
        }
        return f
    }

    static func function(_ library: MTLLibrary, _ name: String) -> MTLFunction {
        guard let f = library.makeFunction(name: name) else {
            FileHandle.standardError.write(Data("missing shader function \(name)\n".utf8))
            exit(1)
        }
        return f
    }
}

/// The wind as Metal: generated from `Wind`'s constants so the grass, the trees, the clouds and the audio can never disagree (F02 A3).
enum WindShaders {
    static var source: String {
        Wind.mslSource + """
        // Conifer sway (F02 A3). A tree's vertices carry a sway weight q = (height above the ground) / (tree height), 0...1, packed into position.w (see Common/Lit): the
        // crown leans along the wind by q^2 and rocks a little. The SAME function runs in the main and the shadow vertex shaders, so shadows follow the bend.
        inline float3 tree_sway(float3 wp, float q, float t) {
            if (q <= 0.0) return wp;
            float s = wind_strength(wp, t);
            float q2 = q * q;
            wp.xz += WIND_DIR * (q2 * (0.06 + 0.40 * s));
            wp.xz += float2(sin(t * 0.55 + wp.x * 0.05 + wp.z * 0.03), cos(t * 0.43 + wp.z * 0.04)) * (q2 * WIND_TREE_BREEZE * (0.5 + s));          // a slow continuous sway, visible even in a lull (F03 A1)
            wp.xz += float2(sin(t * 1.7 + wp.x * 0.7 + wp.z * 0.5), cos(t * 1.3 + wp.z * 0.6)) * (q2 * 0.06 * (0.3 + s));
            return wp;
        }
        // position.w of a vertex: 1 for ordinary geometry; a tree vertex carries 3 + stagger (stagger -1...1) + 4 * round(7 q).
        inline float vertex_stagger(float w) { return w > 1.5 ? (w - 2.0) - 4.0 * floor((w - 2.0) / 4.0) - 1.0 : 0.0; }
        inline float vertex_sway(float w) { return w > 1.5 ? floor((w - 2.0) / 4.0) / 7.0 : 0.0; }

        """
    }
}
