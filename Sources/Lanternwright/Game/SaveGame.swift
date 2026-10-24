import Foundation
import simd

/// What survives between sessions. Partial progress through the stone sequence is deliberately NOT saved: a half-struck
/// sequence means nothing after a restart, whereas solving the puzzle, the pages you found and where you stand do.
struct SaveData: Codable, Equatable {
    static let currentVersion = 1
    var version = SaveData.currentVersion
    var flags: [String]                 // puzzle flags worth keeping (see Game.persistentFlags)
    var pages: [Int]
    var position: [Float]               // x, y, z (feet)
    var yaw: Float
    var pitch: Float
    var playTime: Float
    var world: String? = nil            // absent in saves from before the second world: means Varrow
}

enum SaveStore {
    /// `LANTERNWRIGHT_SAVE_DIR` overrides the default (used by tests).
    static var directory: URL {
        if let o = ProcessInfo.processInfo.environment["LANTERNWRIGHT_SAVE_DIR"] { return URL(fileURLWithPath: o, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lanternwright", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("save.json") }

    static func save(_ data: SaveData) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Write to a temp file and rename, so a crash mid-write can never leave a half-written save.
        let tmp = directory.appendingPathComponent("save.json.tmp")
        try enc.encode(data).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// nil if there is no save, it is unreadable, or it comes from a newer version we do not understand.
    static func load() -> SaveData? {
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(SaveData.self, from: d),
              s.version <= SaveData.currentVersion, s.position.count == 3 else { return nil }
        return s
    }

    static func delete() { try? FileManager.default.removeItem(at: url) }
}

extension Game {
    /// Flags that make sense to restore directly.
    static let persistentFlags = ["solved", "lighthouseLit", "causewayUp", "lensTouched", "gw_mirrors", "gw_chimes", "gw_altar", "gw_ilse_heard", "gw_oren_heard", "gw_end"] + Notebook.flags

    func makeSave() -> SaveData {
        SaveData(flags: Game.persistentFlags.filter { state.has($0) },
                 pages: journal.collectedPages.map(\.number),
                 position: [player.position.x, player.position.y, player.position.z],
                 yaw: player.yaw, pitch: player.pitch, playTime: time, world: world.rawValue)
    }

    /// Bring a freshly created game to the saved state.
    func restore(_ s: SaveData) {
        if s.flags.contains("solved") { puzzle.forceSolved() }
        if s.flags.contains("lensTouched") { state.set("lensTouched") }
        if s.flags.contains("gw_mirrors") { glass?.forceMirrorsSolved() }
        if s.flags.contains("gw_chimes") { glass?.forceChimesSolved() }
        if s.flags.contains("gw_altar") { glass?.forceAltar() }
        for f in ["gw_ilse_heard", "gw_oren_heard", "gw_end"] where s.flags.contains(f) { state.set(f) }
        for f in Notebook.flags where s.flags.contains(f) { state.set(f) }
        for n in s.pages { restorePage(n) }
        if let w = s.world.flatMap(WorldKind.init(rawValue:)), w != world { travel(to: w) }
        let p = SIMD3(s.position[0], s.position[1], s.position[2])
        // A save from an older world layout could put you in the sea or inside a hill: fall back to the world's arrival point.
        if scene.groundHeight(x: p.x, z: p.z) > Player.minGround && abs(p.y - scene.groundHeight(x: p.x, z: p.z)) < 3 {
            player = Player(position: p, yaw: s.yaw)
            player.pitch = s.pitch
        }
        simulate(seconds: 0.05)          // let visuals (lens glow, slab heights) settle
        _ = drainEvents()
    }
}
