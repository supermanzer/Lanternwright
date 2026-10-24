import Foundation
import Metal

/// Compiles all MSL at launch. There is no offline `metal` compiler in Command Line Tools,
/// so shaders live as Swift strings and are compiled at runtime with makeLibrary(source:).
enum ShaderLibrary {
    static var sources: [String] {
        [CommonShaders.source, SkyShaders.source, MaterialShaders.source, LitShaders.source, GrassShaders.source, WaterShaders.source, CrystalShaders.source, MistShaders.source, PostShaders.source]
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

    static func function(_ library: MTLLibrary, _ name: String) -> MTLFunction {
        guard let f = library.makeFunction(name: name) else {
            FileHandle.standardError.write(Data("missing shader function \(name)\n".utf8))
            exit(1)
        }
        return f
    }
}
