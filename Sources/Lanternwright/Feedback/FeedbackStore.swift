import Foundation

/// One piece of player feedback with enough context to act on it without asking "where were you standing?".
struct FeedbackEntry: Codable, Equatable {
    var id: String
    var date: String
    var text: String
    var screenshot: String?          // file name inside the feedback folder
    var context: [String: String]
}

/// Feedback lives in plain files so the developer (or an agent) can read it with `Lanternwright --feedback`:
///   <dir>/feedback.jsonl   one JSON object per line, append-only
///   <dir>/<id>.png         what the player was looking at when they pressed F
enum FeedbackStore {
    /// `LANTERNWRIGHT_FEEDBACK_DIR` overrides the default (used by tests).
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["LANTERNWRIGHT_FEEDBACK_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lanternwright/feedback", isDirectory: true)
    }

    static var logURL: URL { directory.appendingPathComponent("feedback.jsonl") }
    static func screenshotURL(id: String) -> URL { directory.appendingPathComponent("\(id).png") }
    static var pendingScreenshotURL: URL { directory.appendingPathComponent("pending.png") }

    static func newID(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: now)
    }

    /// Save an entry. If a pending screenshot exists it is adopted (renamed to `<id>.png`).
    @discardableResult
    static func save(text: String, context: [String: String], now: Date = Date()) throws -> FeedbackEntry {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var id = newID(now: now)
        var n = 2
        while fm.fileExists(atPath: screenshotURL(id: id).path) || loadAll().contains(where: { $0.id == id }) { id = newID(now: now) + "-\(n)"; n += 1 }
        var shot: String?
        if fm.fileExists(atPath: pendingScreenshotURL.path) {
            try fm.moveItem(at: pendingScreenshotURL, to: screenshotURL(id: id))
            shot = "\(id).png"
        }
        let entry = FeedbackEntry(id: id, date: ISO8601DateFormatter().string(from: now),
                                  text: text.trimmingCharacters(in: .whitespacesAndNewlines), screenshot: shot, context: context)
        var line = try JSONEncoder().encode(entry)
        line.append(0x0A)
        if fm.fileExists(atPath: logURL.path) {
            let h = try FileHandle(forWritingTo: logURL)
            defer { try? h.close() }
            try h.seekToEnd(); try h.write(contentsOf: line)
        } else {
            try line.write(to: logURL)
        }
        return entry
    }

    static func discardPending() { try? FileManager.default.removeItem(at: pendingScreenshotURL) }

    static func loadAll() -> [FeedbackEntry] {
        guard let data = try? Data(contentsOf: logURL), let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(FeedbackEntry.self, from: Data($0.utf8)) }
    }

    /// Human/agent-readable listing for `--feedback`.
    static func formatted(_ entries: [FeedbackEntry]) -> String {
        if entries.isEmpty { return "No feedback yet. (folder: \(directory.path))" }
        return entries.enumerated().map { i, e in
            var s = "#\(i + 1)  \(e.id)  (\(e.date))\n  \"\(e.text)\"\n"
            for (k, v) in e.context.sorted(by: { $0.key < $1.key }) { s += "    \(k): \(v)\n" }
            if let shot = e.screenshot { s += "    screenshot: \(screenshotURL(id: String(shot.dropLast(4))).path)\n" }
            return s
        }.joined(separator: "\n")
    }
}
