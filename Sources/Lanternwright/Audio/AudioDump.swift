import Foundation

/// `--dump-audio out.wav`: render 24 s of the soundscape to a 16-bit stereo WAV so it can be auditioned with
/// `afplay` without launching the game. 0-8 s wind only, 8 s surf joins, then 5 s of walking footsteps on grass,
/// 5 s running on grass, then five walking steps on each surface in turn (dock planks, dry sand, wet sand, packed earth, stone, rock),
/// then a walk off the end of the dock onto sand (the planks fade out over a few steps).
enum AudioDump {
    static func write(to path: String) throws {
        let sr = 44100
        let total = sr * 46
        let synth = AmbienceSynth(sampleRate: Float(sr))
        var left = [Float](repeating: 0, count: total), right = [Float](repeating: 0, count: total)
        let tour: [StepMaterial] = [.wood, .drySand, .wetSand, .earth, .stone, .rock]
        var done = 0, nextStep = sr * 12, stepIndex = 0
        // Cadences match the Player: walking about 2.2 steps/s, running about 3.0 steps/s.
        func stepInterval(_ i: Int) -> Float { i < 11 ? 1 / 2.2 : (i < 26 ? 1 / 3.0 : 0.6) }
        while done < total {
            let t = Float(done) / Float(sr)
            synth.windGain = 0.4 + 0.2 * min(t / 24, 1)
            synth.surfGain = t < 8 ? 0 : 0.6
            if done >= nextStep && stepIndex < 26 + 5 * 6 + 6 {
                if stepIndex < 26 { synth.stepSurface = .grass; synth.stepMix = nil }
                else if stepIndex < 26 + 30 { let k = stepIndex - 26; synth.stepMix = FootstepRecipe.pure(tour[k / 5]); synth.stepPlank = 40 + k; synth.stepPebble = tour[k / 5] == .earth ? 0.5 : 0 }
                else {                                                    // off the dock: planks 1.0, 0.7, 0.4, 0.2, 0.05, 0 against sand
                    let wood: [Float] = [1, 0.7, 0.4, 0.2, 0.05, 0]
                    var m = StepMix(repeating: 0); let w = wood[stepIndex - 56]; m[StepMaterial.wood.rawValue] = w; m[StepMaterial.drySand.rawValue] = 1 - w
                    synth.stepMix = m; synth.stepPlank = 70 + stepIndex
                }
                synth.stepRun = stepIndex >= 11 && stepIndex < 26
                synth.stepPan = stepIndex % 2 == 0 ? -0.3 : 0.3
                synth.stepCounter += 1
                nextStep += Int(Float(sr) * (stepIndex >= 26 ? 0.5 : stepInterval(stepIndex)))
                stepIndex += 1
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
