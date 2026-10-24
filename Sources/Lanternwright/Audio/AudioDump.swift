import Foundation

/// `--dump-audio out.wav`: render 24 s of the soundscape to a 16-bit stereo WAV so it can be auditioned with
/// `afplay` without launching the game. Seconds 0-8: wind only, then surf joins, then footsteps on each surface.
enum AudioDump {
    static func write(to path: String) throws {
        let sr = 44100
        let total = sr * 24
        let synth = AmbienceSynth(sampleRate: Float(sr))
        var left = [Float](repeating: 0, count: total), right = [Float](repeating: 0, count: total)
        let surfaces: [SurfaceKind] = [.grass, .sand, .earth, .rock, .wood, .stone]
        var done = 0, nextStep = sr * 12, stepIndex = 0
        while done < total {
            let t = Float(done) / Float(sr)
            synth.windGain = 0.4 + 0.2 * min(t / 24, 1)
            synth.surfGain = t < 8 ? 0 : 0.6
            if done >= nextStep && stepIndex < 12 {
                synth.stepSurface = surfaces[stepIndex % surfaces.count]
                synth.stepCounter += 1
                stepIndex += 1
                nextStep += Int(Float(sr) * 0.55)
            }
            let c = min(512, total - done)
            left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in
                synth.render(frames: c, left: l.baseAddress! + done, right: r.baseAddress! + done)
            } }
            done += c
        }
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = total * 4
        data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + bytes))
        data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr * 4)); u16(4); u16(16)
        data.append("data".data(using: .ascii)!); u32(UInt32(bytes))
        for i in 0..<total {
            u16(UInt16(bitPattern: Int16(max(-1, min(1, left[i])) * 32000)))
            u16(UInt16(bitPattern: Int16(max(-1, min(1, right[i])) * 32000)))
        }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent.isEmpty ? "." : (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
