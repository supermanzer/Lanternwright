import Foundation

/// Player preferences, stored in UserDefaults as one JSON blob.
struct Settings: Codable, Equatable {
    var sensitivity: Float = 0.0022      // radians of turn per mouse count
    var invertY = false
    var volume: Float = 0.5              // master volume 0...1
    var renderScale: Float = 1.0         // 0.5...1: fraction of the (already capped) native resolution
    var slipOnSteep = true               // the soft slip on slopes steeper than ~40 degrees (default ON since F02; the pause-menu checkbox turns it off)
    var metalFX = false                  // G10.4.1: with Render resolution below 1, upscale with MetalFX's temporal scaler instead of stretching the smaller image (costs about 2 ms at 1440p, keeps more detail)
    var taa = true                       // temporal anti-aliasing (F02 R1): steadier fine detail for a slight softness on fast turns
    var slipDefaultApplied = true        // a blob saved before F02 stored the old default (off): it is switched on once, then the player's choice stands
    var introSeen = false                // the controls screen has been shown on a new game (reset by "New game")
    var lookSpeed: Float = 0.7           // M10.1: turn speed as a fraction of `Settings.baseSensitivity` (0.5...1.5); the pause-menu slider (the old `sensitivity` field is kept so saved blobs decode)
    var pace: Float = 1.0                // M10.2: walking pace multiplier (0.7...1.3); scales walk and run speed together
    var guidance: Guidance = .guided     // M10.7: Guided / Loose / Free roam (the way back to the old free movement)
    var calmCamera: Float = 0.6          // M10.1: 0 = raw mouse, 1 = calmest; scales the look smoothing time and the soft limit on flicks

    init() {}
    /// Tolerant decoding: a settings blob saved before a field existed must keep the fields it has.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sensitivity = try c.decodeIfPresent(Float.self, forKey: .sensitivity) ?? sensitivity
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? invertY
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? volume
        renderScale = try c.decodeIfPresent(Float.self, forKey: .renderScale) ?? renderScale
        introSeen = try c.decodeIfPresent(Bool.self, forKey: .introSeen) ?? introSeen
        let applied = try c.decodeIfPresent(Bool.self, forKey: .slipDefaultApplied) ?? false
        slipOnSteep = applied ? (try c.decodeIfPresent(Bool.self, forKey: .slipOnSteep) ?? slipOnSteep) : true
        slipDefaultApplied = true
        taa = try c.decodeIfPresent(Bool.self, forKey: .taa) ?? taa
        metalFX = try c.decodeIfPresent(Bool.self, forKey: .metalFX) ?? metalFX
        lookSpeed = try c.decodeIfPresent(Float.self, forKey: .lookSpeed) ?? lookSpeed
        calmCamera = try c.decodeIfPresent(Float.self, forKey: .calmCamera) ?? calmCamera
        pace = try c.decodeIfPresent(Float.self, forKey: .pace) ?? pace
        guidance = (try? c.decodeIfPresent(Guidance.self, forKey: .guidance)) ?? .guided           // an unknown value falls back to Guided
    }

    static let key = "lanternwright.settings"
    /// The settings in force (the app sets it whenever they change); the feedback context reads it.
    nonisolated(unsafe) static var current = Settings()
    /// Radians of turn per mouse count at `lookSpeed` 1 (the pre-M10 default).
    static let baseSensitivity: Float = 0.0022
    /// What the input layer uses: `lookSpeed` x the base.
    var effectiveSensitivity: Float { Settings.baseSensitivity * lookSpeed }

    static func load() -> Settings {
        guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s.clamped()
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Settings.key) }
    }

    /// Clamp every field to its legal range (a hand-edited or corrupt value must not break the game).
    func clamped() -> Settings {
        var s = self
        s.sensitivity = min(max(sensitivity.isFinite ? sensitivity : 0.0022, 0.0005), 0.008)
        s.volume = min(max(volume.isFinite ? volume : 0.5, 0), 1)
        s.renderScale = min(max(renderScale.isFinite ? renderScale : 1, 0.5), 1)
        s.lookSpeed = min(max(lookSpeed.isFinite ? lookSpeed : 0.7, 0.5), 1.5)
        s.calmCamera = min(max(calmCamera.isFinite ? calmCamera : 0.6, 0), 1)
        s.pace = min(max(pace.isFinite ? pace : 1, 0.7), 1.3)
        return s
    }
}
