import Foundation

/// Player preferences, stored in UserDefaults as one JSON blob.
struct Settings: Codable, Equatable {
    var sensitivity: Float = 0.0022      // radians of turn per mouse count
    var invertY = false
    var volume: Float = 0.5              // master volume 0...1
    var renderScale: Float = 1.0         // 0.5...1: fraction of the (already capped) native resolution
    var slipOnSteep = false              // the optional soft slip on slopes steeper than ~40 degrees (default off)
    var introSeen = false                // the controls screen has been shown on a new game (reset by "New game")

    init() {}
    /// Tolerant decoding: a settings blob saved before a field existed must keep the fields it has.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sensitivity = try c.decodeIfPresent(Float.self, forKey: .sensitivity) ?? sensitivity
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? invertY
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? volume
        renderScale = try c.decodeIfPresent(Float.self, forKey: .renderScale) ?? renderScale
        introSeen = try c.decodeIfPresent(Bool.self, forKey: .introSeen) ?? introSeen
        slipOnSteep = try c.decodeIfPresent(Bool.self, forKey: .slipOnSteep) ?? slipOnSteep
    }

    static let key = "lanternwright.settings"

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
        return s
    }
}
