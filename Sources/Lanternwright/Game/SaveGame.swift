import Foundation
import simd

/// What survives between sessions. Partial progress through the stone sequence is deliberately NOT saved: a half-struck
/// sequence means nothing after a restart, whereas solving the puzzle, the pages you found and where you stand do.
///
/// Version 2 keeps puzzle flags **per world** (`worldFlags["varrow"]`, `["glassWood"]`, plus `["game"]` for flags the game
/// itself owns), so two worlds can never collide on a flag name and each world's puzzles restore only from their own bucket.
/// Version 1 saves (one flat `flags` list) are migrated on load.
struct SaveData: Codable, Equatable {
    static let currentVersion = 2
    static let gameBucket = "game"
    var version = SaveData.currentVersion
    var worldFlags: [String: [String]]
    var pages: [Int]
    var position: [Float]               // x, y, z (feet)
    var yaw: Float
    var pitch: Float
    var playTime: Float
    var world: String? = nil            // absent in saves from before the second world: means Varrow
    var story: StoryState? = nil        // absent in saves from before S03.1: the defaults

    /// Every saved flag, whichever bucket it is in.
    var flags: [String] { worldFlags.values.flatMap { $0 }.sorted() }

    init(worldFlags: [String: [String]], pages: [Int], position: [Float], yaw: Float, pitch: Float, playTime: Float, world: String? = nil, story: StoryState? = nil) {
        self.worldFlags = worldFlags; self.pages = pages; self.position = position
        self.yaw = yaw; self.pitch = pitch; self.playTime = playTime; self.world = world; self.story = story
    }

    private enum CodingKeys: String, CodingKey { case version, worldFlags, flags, pages, position, yaw, pitch, playTime, world, story }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decode(Int.self, forKey: .version)
        if let w = try c.decodeIfPresent([String: [String]].self, forKey: .worldFlags) {
            worldFlags = w
        } else {
            worldFlags = SaveData.migrate(legacyFlags: try c.decodeIfPresent([String].self, forKey: .flags) ?? [])
        }
        version = v
        pages = try c.decode([Int].self, forKey: .pages)
        position = try c.decode([Float].self, forKey: .position)
        yaw = try c.decode(Float.self, forKey: .yaw)
        pitch = try c.decode(Float.self, forKey: .pitch)
        playTime = try c.decode(Float.self, forKey: .playTime)
        world = try c.decodeIfPresent(String.self, forKey: .world)
        story = try c.decodeIfPresent(StoryState.self, forKey: .story)
        if v < SaveData.currentVersion { version = SaveData.currentVersion }      // migrated in memory; rewritten as v2 on the next save
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(worldFlags, forKey: .worldFlags)
        try c.encode(pages, forKey: .pages)
        try c.encode(position, forKey: .position)
        try c.encode(yaw, forKey: .yaw)
        try c.encode(pitch, forKey: .pitch)
        try c.encode(playTime, forKey: .playTime)
        try c.encodeIfPresent(world, forKey: .world)
        try c.encodeIfPresent(story, forKey: .story)
    }

    /// Sort a v1 flat flag list into worlds. This table is frozen history (v1 only ever had these flags), so it is the one
    /// place a flag list is allowed to be spelled out.
    static func migrate(legacyFlags: [String]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for f in legacyFlags {
            let bucket: String
            if f == "lensTouched" { bucket = gameBucket }
            else if f.hasPrefix("gw_") { bucket = WorldKind.glassWood.rawValue }
            else { bucket = WorldKind.varrow.rawValue }       // solved, lighthouseLit, causewayUp, seen_*, struck_*
            out[bucket, default: []].append(f)
        }
        return out
    }
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
    /// Derived from the puzzles themselves (plus the one flag the game owns: having travelled), so a new puzzle needs no edit here.
    var persistentFlags: [String] { puzzles.flatMap(\.persistentFlags) + Game.ownFlags }

    /// Each puzzle's set flags under its own world, the game's own flags under "game".
    private func savedFlagsByWorld() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for p in puzzles {
            let set = p.persistentFlags.filter { state.has($0) }
            if !set.isEmpty { out[p.world.rawValue, default: []] += set }
        }
        let own = Game.ownFlags.filter { state.has($0) }
        if !own.isEmpty { out[SaveData.gameBucket] = own }
        return out
    }

    func makeSave() -> SaveData {
        SaveData(worldFlags: savedFlagsByWorld(),
                 pages: journal.collectedPages.map(\.number),
                 position: [player.position.x, player.position.y, player.position.z],
                 yaw: player.yaw, pitch: player.pitch, playTime: time, world: world.rawValue, story: story)
    }

    /// Bring a freshly created game to the saved state.
    func restore(_ s: SaveData) {
        putAwayReading()                                                           // F05 S1: a card from before the load does not come back
        for f in Game.ownFlags where s.worldFlags[SaveData.gameBucket]?.contains(f) == true { state.set(f) }
        // The two routes exclude each other: a save that has both (only a hand-edited one can) is treated as undecided rather than guessing which came first.
        if state.has(Game.pathIlseFlag) && state.has(Game.pathOrenFlag) { state.set(Game.pathIlseFlag, false); state.set(Game.pathOrenFlag, false) }
        story = s.story ?? StoryState()
        syncInterior(snap: true)             // an open lighthouse door puts the walls and floors in place BEFORE the player is (a save made inside the tower)
        for p in puzzles { p.restore(from: Set(s.worldFlags[p.world.rawValue] ?? [])) }
        journal.route = chosenPath ?? .ilse; journal.archiveShown = chosenPath != nil
        for n in s.pages { restorePage(n) }
        if let w = s.world.flatMap(WorldKind.init(rawValue:)), w != world { travel(to: w) }
        let p = SIMD3(s.position[0], s.position[1], s.position[2])
        // A save from an older world layout could put you in the sea or inside a hill: fall back to the world's arrival point.
        // S03.5: inside the open lighthouse the floor is the interior's (a stair turn or the lens room is metres above the hill's ground at that spot).
        let floor = world == .varrow && state.has(Game.doorOpenFlag) ? interior.height(x: p.x, z: p.z, feetY: p.y) : nil
        let ground = floor ?? scene.groundHeight(x: p.x, z: p.z)
        if ground > Player.minGround && abs(p.y - ground) < 3 {
            player = Player(position: p, yaw: s.yaw)
            player.pitch = s.pitch
        }
        settleAtmosphere()
        simulate(seconds: 0.05)          // let visuals (lens glow, slab heights) settle
        _ = drainEvents()
    }
}
