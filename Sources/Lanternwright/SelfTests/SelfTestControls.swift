import AppKit
import Foundation
import simd

/// Self-tests: the Controls table (R08). The table feeds the intro screen, the pause menu hint, the Help menu and the README, so these checks
/// make sure what the screens promise is what `Input` and the menu really do, in both directions.
extension SelfTestRunner {
    func runControls() {
        guard name == "all" || name == "controls" else { return }
        func sampled(_ setup: (Input) -> Void) -> InputState { let i = Input(); setup(i); return i.sample(captured: true) }
        func changed(_ s: InputState) -> Bool {
            simd_length(s.move) > 0 || s.run || simd_length(s.look) > 0 || s.click || s.journalPressed || s.escapePressed || s.feedbackPressed
                || s.zoom || s.autoRunPressed || s.tabPressed || s.pageFlip != 0
        }
        let menu = MainActor.assumeIsolated { AppDelegate.makeMenu() }
        func allItems(_ m: NSMenu) -> [NSMenuItem] { m.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) } }
        let items = allItems(menu)

        // Forward: every trigger of every row does what the row says.
        var bad: [String] = []
        var tableCodes = Set<UInt16>()
        for row in Controls.rows {
            for t in row.triggers {
                var ok = false
                switch t {
                case .key(let c): tableCodes.insert(c); ok = row.check(sampled { $0.keyDown(c) })
                case .shift: ok = row.check(sampled { $0.shift = true })
                case .rightMouse: ok = row.check(sampled { $0.rightMouseDown = true })
                case .leftClick: ok = row.check(sampled { $0.click() })
                case .mouseMove: ok = row.check(sampled { $0.addMouse(dx: 6, dy: 0) })
                case .menu(let key, let mods): ok = items.contains { $0.keyEquivalent == key && $0.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift]) == mods }
                }
                if !ok { bad.append("\(row.action) [\(t)]") }
            }
        }
        check(bad.isEmpty, "every row of the controls table is really handled (\(Controls.rows.count) rows; failing: \(bad))")
        // Backward: every key code that the input layer reacts to appears in the table, so the screens cannot be missing a key.
        let undocumented = (UInt16(0)..<128).filter { c in changed(sampled { $0.keyDown(c) }) && !tableCodes.contains(c) }
        check(undocumented.isEmpty, "every key the game reacts to is listed in the controls table (undocumented codes: \(undocumented))")
        check(Controls.rows.contains { $0.keys.contains(.cap(FeedbackShortcut.label)) && $0.triggers.contains { if case .key(FeedbackShortcut.keyCode) = $0 { return true } else { return false } } },
              "the feedback key is one constant (FeedbackShortcut) and the table follows it")
        check(Controls.pauseHint.contains(FeedbackShortcut.label) && Controls.groups.count == 4 && Controls.groups.allSatisfy { !$0.1.isEmpty }, "the pause hint names the feedback key and every group has rows")
        // The README table is generated from the same rows.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if let readme = try? String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8),
           let a = readme.range(of: "<!-- controls:begin"), let b = readme.range(of: "<!-- controls:end -->"),
           let nl = readme[a.upperBound...].firstIndex(of: "\n") {
            let body = readme[readme.index(after: nl)..<b.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            check(body == Controls.markdownTable(), "the README controls table equals the generated one (run Lanternwright --controls-md)")
        } else {
            check(true, "README controls table: file not found from here, skipped")
        }
        // Menus: Help has Controls and Send Feedback; Send Feedback shows F but has no key equivalent (a plain f would fire while typing in the panel).
        let controlsItem = items.first { $0.title.hasPrefix("Controls") }, feedbackItem = items.first { $0.title.hasPrefix("Send Feedback") }
        check(controlsItem != nil && feedbackItem != nil && feedbackItem!.title.contains(FeedbackShortcut.label) && feedbackItem!.keyEquivalent.isEmpty, "Help > Controls… and Send Feedback… (F) exist; feedback has no typing-clashing key equivalent")
        // The intro screen: Enter, keypad Enter, Space and Esc close it, other keys do not, and it reports where it was opened from.
        MainActor.assumeIsolated {
            let v = OverlayView(frame: NSRect(x: 0, y: 0, width: 1600, height: 900))
            var done: [Bool] = []
            v.onIntroDone = { done.append($0) }
            check(!v.handleKey(36), "with no intro open, Enter is not consumed")
            v.showIntro(fromTitle: true)
            check(v.introOpen && v.hitTest(NSPoint(x: 800, y: 450)) === v, "the intro screen takes the mouse while it is open (a click cannot reach the world)")
            check(!v.handleKey(Input.Key.w) && !v.handleKey(Input.Key.j) && v.introOpen, "other keys do not close it")
            check(v.handleKey(36) && !v.introOpen && done == [true], "Enter closes it and reports it came from the title")
            v.showIntro(fromTitle: false); check(v.handleKey(Input.Key.space) && done == [true, false], "Space closes it, reporting it came from the pause menu")
            v.showIntro(fromTitle: false); check(v.handleKey(Input.Key.escape) && done.count == 3, "Esc closes it")
            v.showIntro(fromTitle: true); check(v.handleKey(76) && done.count == 4, "keypad Enter closes it")
            v.showIntro(fromTitle: true); v.dismissIntro(); v.dismissIntro()
            check(done.count == 5, "closing twice reports once")
            v.showIntro(fromTitle: true); v.step(dt: 0.3)
            check(v.introFade > 0.3 && v.introFade < 0.8, "it fades in softly (\(v.introFade))")
        }
        // Settings: introSeen persists, and settings saved before the field existed still load with their values.
        var st = Settings(); st.introSeen = true; st.sensitivity = 0.004
        let round = try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(st))
        check(round?.introSeen == true && round?.sensitivity == 0.004, "introSeen survives a save and load")
        let legacy = try? JSONDecoder().decode(Settings.self, from: Data(#"{"sensitivity":0.003,"invertY":true,"volume":0.2,"renderScale":0.8}"#.utf8))
        check(legacy != nil && legacy!.introSeen == false && legacy!.invertY && legacy!.sensitivity == 0.003 && legacy!.volume == 0.2, "settings saved before introSeen existed keep their values and show the intro once")
    }
}
