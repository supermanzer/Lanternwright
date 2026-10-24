import AVFoundation

/// Connects `AmbienceSynth` to the speakers and drives its parameters from the game state.
final class AudioEngine {
    let synth: AmbienceSynth
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var lastUpdate = 0.0
    private var lastFootfalls = 0
    private var buoyStrikes = 0
    private var buoyNext: Double = 0

    init() {
        // Match the synth to the hardware rate so no resampling is needed (44100 if there is no device).
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        synth = AmbienceSynth(sampleRate: rate > 0 ? Float(rate) : 44100)
    }

    /// Returns false (and stays silent) if there is no usable audio device. The game must not depend on sound.
    @discardableResult
    func start() -> Bool {
        let sr = Double(engine.outputNode.outputFormat(forBus: 0).sampleRate)
        guard sr > 0, let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else { return false }
        let synth = self.synth
        let node = AVAudioSourceNode(format: format) { _, _, frames, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(frames: Int(frames), left: l, right: r)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
        do { try engine.start(); return true } catch {
            FileHandle.standardError.write(Data("audio disabled: \(error)\n".utf8))
            return false
        }
    }

    /// React to a game event (a chime, the causeway rumble).
    func handle(_ event: GameEvent) {
        switch event {
        case .chime(let kind): synth.play(kind)
        case .drone(let i, let on): synth.setDrone(i, on: on)
        case .droneSour: synth.sourDrone()
        case .droneBloom: synth.bloomDrone()
        default: break
        }
    }

    /// Called every frame; does real work about 8 times a second.
    func update(now: Double, game: Game) {
        if game.footfalls != lastFootfalls {
            lastFootfalls = game.footfalls
            synth.stepSurface = game.currentSurface
            let under = game.surfaceMix
            synth.stepMix = under.mix; synth.stepPebble = under.pebble; synth.stepPlank = game.currentPlank; synth.stepHollow = game.currentHollowness
            synth.stepRun = game.lastFootWasRun
            synth.stepPan = game.footfalls % 2 == 0 ? -0.3 : 0.3      // alternate feet
            synth.stepCounter += 1
        }
        guard now - lastUpdate > 0.125 else { return }
        lastUpdate = now
        // In the Glass Wood the breeze sets the crystal trees shimmering now and then (about once every 8 s).
        if game.world == .glassWood && Float.random(in: 0..<1) < 0.125 / 8 { synth.play(.glassAmbient) }
        let p = game.player.position
        // Wind is stronger up high and in the open.
        let sc = game.scene
        let amb = AudioSpace.ambient(at: p, ground: { sc.groundHeight(x: $0, z: $1) })
        synth.windGain = amb.windGain
        synth.windAltitude = amb.windAltitude
        let space = AudioSpace.read(listener: p, yaw: game.player.yaw, ground: { sc.groundHeight(x: $0, z: $1) })
        synth.reverbSeconds = AudioSpace.reverbTime(openness: space.openness)
        synth.surfPan = space.surfPan; synth.surfOcclusion = space.surfOcclusion
        // Surf as a line source: every shoreline direction in view contributes with an inverse-square-ish law, the air darkens it with distance, and far
        // inland it is a slow low swell (AudioSpace.surfField).
        synth.surfGain = amb.surfGain
        synth.surfFar = amb.surfFar; synth.surfAirCutoff = amb.surfAirCutoff
        // Sonic landmarks: where each source is relative to the listener.
        let lv = SonicLandmarks.levels(listener: p, yaw: game.player.yaw, world: game.world, lighthouseLit: game.state.has("lighthouseLit"))
        synth.humGain = lv.hum; synth.humPan = lv.humPan
        synth.buoyGain = lv.buoy; synth.buoyPan = lv.buoyPan
        synth.galleryGain = lv.gallery
        if game.world == .varrow && now >= buoyNext {
            if buoyNext > 0 { synth.play(.buoy) }
            buoyNext = now + Double(SonicLandmarks.buoyInterval(strike: buoyStrikes)); buoyStrikes += 1
        }
    }
}
