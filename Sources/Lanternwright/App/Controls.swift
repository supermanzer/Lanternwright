import AppKit
import simd

/// The one place that says what the player can press. The intro screen, the pause menu's hint line, the Help menu and the README table all read
/// this table, and a selftest drives every trigger below through `Input` (or the main menu) and checks the matching `InputState` change, so
/// the screens cannot drift from the code. Keys are shown by name but handled by key CODE (layout-dependent: W A S D, J, F, R, Z, Tab and the
/// arrows are physical positions of a US layout; on other layouts the printed key and the code may differ, which we accept for a game).

/// The feedback key in one line: change `keyCode` and `label` and every screen, the menu hint and the test follow.
enum FeedbackShortcut {
    static let keyCode: UInt16 = 3          // F (ANSI)
    static let label = "F"
}

enum ControlGroup: String, CaseIterable {
    case moving = "Moving", interacting = "Looking and interacting", journal = "Your journal", game = "The game"
}

/// One drawn piece of a row's key column.
enum KeyLabel: Equatable {
    case cap(String)             // a keycap
    case mouseLeft, mouseRight, mouseMove
    case or                      // the word "or" between alternatives

    var plain: String {
        switch self {
        case .cap(let s): return s
        case .mouseLeft: return "Click"
        case .mouseRight: return "Right mouse"
        case .mouseMove: return "Mouse"
        case .or: return "or"
        }
    }
}

/// How a row is exercised by the selftest.
enum ControlTrigger {
    case key(UInt16)
    case shift
    case rightMouse
    case leftClick
    case mouseMove
    case menu(equivalent: String, modifiers: NSEvent.ModifierFlags)
}

struct ControlRow {
    let group: ControlGroup
    let action: String
    let keys: [KeyLabel]
    /// Each trigger, pressed alone, must make `check` true on the sampled `InputState` (menu triggers are checked against the main menu instead).
    let triggers: [ControlTrigger]
    let check: (InputState) -> Bool
}

enum Controls {
    static let rows: [ControlRow] = [
        // Moving
        ControlRow(group: .moving, action: "Walk. The arrow keys ↑ ↓ also walk.", keys: [.cap("W"), .cap("A"), .cap("S"), .cap("D")],
                   triggers: [.key(Input.Key.w), .key(Input.Key.a), .key(Input.Key.s), .key(Input.Key.d), .key(Input.Key.up), .key(Input.Key.down)],
                   check: { simd_length($0.move) > 0.5 }),
        ControlRow(group: .moving, action: "Turn.", keys: [.cap("←"), .cap("→")],
                   triggers: [.key(Input.Key.left), .key(Input.Key.right)], check: { $0.look.x != 0 }),
        ControlRow(group: .moving, action: "Look around.", keys: [.mouseMove],
                   triggers: [.mouseMove], check: { $0.look.x != 0 }),
        ControlRow(group: .moving, action: "Run (hold).", keys: [.cap("Shift")],
                   triggers: [.shift], check: { $0.run }),
        ControlRow(group: .moving, action: "Toggle auto-run.", keys: [.cap("R")],
                   triggers: [.key(Input.Key.r)], check: { $0.autoRunPressed }),
        // Looking and interacting
        ControlRow(group: .interacting, action: "Touch or use what the ring marks: stones, pages, the lens. The ring is quieter once a thing is finished.", keys: [.mouseLeft],
                   triggers: [.leftClick], check: { $0.click }),
        ControlRow(group: .interacting, action: "Look closer (hold) to see distant detail.", keys: [.mouseRight, .or, .cap("Z")],
                   triggers: [.rightMouse, .key(Input.Key.z)], check: { $0.zoom }),
        // Journal
        ControlRow(group: .journal, action: "Open or close the journal. Pages you find are added by themselves.", keys: [.cap("J")],
                   triggers: [.key(Input.Key.j)], check: { $0.journalPressed }),
        ControlRow(group: .journal, action: "Close a page you are reading.", keys: [.cap("J"), .or, .cap("Esc")],
                   triggers: [.key(Input.Key.j), .key(Input.Key.escape)], check: { $0.journalPressed || $0.escapePressed }),
        ControlRow(group: .journal, action: "Turn pages.", keys: [.cap("←"), .cap("→")],
                   triggers: [.key(Input.Key.left), .key(Input.Key.right)], check: { $0.pageFlip != 0 }),
        ControlRow(group: .journal, action: "Switch between Pages and Notebook. In the Notebook, click a struck stone's rubbing to hear its tone again.", keys: [.cap("Tab")],
                   triggers: [.key(Input.Key.tab)], check: { $0.tabPressed }),
        // The game
        ControlRow(group: .game, action: "Free the mouse and pause (settings, controls, new game). Press again to resume.", keys: [.cap("Esc")],
                   triggers: [.key(Input.Key.escape)], check: { $0.escapePressed }),
        ControlRow(group: .game, action: "Send feedback: saves your note, a screenshot and where you were.", keys: [.cap(FeedbackShortcut.label)],
                   triggers: [.key(FeedbackShortcut.keyCode)], check: { $0.feedbackPressed }),
        ControlRow(group: .game, action: "Full screen.", keys: [.cap("Ctrl"), .cap("⌘"), .cap("F")],
                   triggers: [.menu(equivalent: "f", modifiers: [.command, .control])], check: { _ in true }),
    ]

    static var groups: [(ControlGroup, [ControlRow])] { ControlGroup.allCases.map { g in (g, rows.filter { $0.group == g }) } }

    /// The one-line reminder under the pause menu's title.
    static var pauseHint: String { "Esc resumes.  \(FeedbackShortcut.label) sends feedback.  J opens the journal." }
    static let reassurance = "There is no timer and no way to lose. The island saves by itself."

    /// The README controls table, generated (a selftest compares it to the README between its markers).
    static func markdownTable() -> String {
        // Adjacent keycaps read as a set or a chord: "W A S D", "← →", "Ctrl ⌘ F"; alternatives are joined by "or".
        func cell(_ keys: [KeyLabel]) -> String { keys.map(\.plain).joined(separator: " ") }
        var lines = ["| Control | Action |", "|---|---|"]
        for r in rows { lines.append("| \(cell(r.keys)) | \(r.action) |") }
        return lines.joined(separator: "\n")
    }
}
