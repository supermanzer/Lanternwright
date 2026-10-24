# R08: an introductory controls screen (user request)

**This comes from the user directly.** The user's words: "How can I trigger the feedback mechanism while playing the game? I would like to add a keyboard shortcut for this. Also, when starting the game we should display an introductory screen telling the player how to move through the game and interact with objects. This should include any shortcut keys like J to dismiss an inspected object."

Same rules as before: triage into TASKS.md, selftests and bots green, commit, INSPECT.md updated, no changes to the story ending. Verify the layout with `--dump-overlay` and Read the PNGs (you cannot see the live window).

## 1. Feedback shortcut

The shortcut already exists and is **F** (`Input.swift` sets `feedbackEdge`, `AppDelegate` opens the panel). The user did not know, because nothing in the game says so. Do not change the key. Do these small things:
- Tell the player in the intro screen and the pause menu (below).
- Add a main-menu item **Help > Send Feedback...** (shows `F` as its hint) that triggers the same action, so it is discoverable and works from the menu bar. If adding a real key equivalent that does not clash with typing is simple, use it; otherwise leave the menu item without one.
- Keep a single `FeedbackShortcut` constant so the user can change the key in one line if they want a different one (they said they would like to add a shortcut; if they come back with a preferred key, it should be a one-line edit).

## 2. The introduction screen

**When:** on a new game (no save, or after "New game..."), shown once after "Click to begin" and before the player can move. Not shown when resuming a save, except through the pause menu. Store an `introSeen` flag in settings so it never nags. It must also be reachable at any time: add **Controls** to the pause menu (Esc), and a Help menu item.

**Look and feel:** same visual language as the journal: parchment panel, Baskerville headings, centred over the dimmed world. Small and calm (pillar 4: unhurried): no animation beyond a soft fade in. Draw the keys as small rounded keycaps, with the action beside each. Mouse actions drawn as small mouse glyphs (left, right) or plain words. It should fit at 1600x900 and also at small window sizes and fullscreen (scale the panel, wrap the text).

**Content (draw from one table, see below):**

*Moving*
- **W A S D** move. **Arrow keys** turn. **Mouse** look.
- **Shift** run (hold). **R** toggle auto-run.

*Looking and interacting*
- **Click** touch or use what the ring highlights (stones, pages, lens). The ring changes when something can be used, and looks quieter once it is finished.
- **Right mouse** (or **Z**) look closer; hold to zoom in on distant detail.

*Your journal*
- **J** open or close the journal. Pages you find are added automatically; a page you read opens in the journal and **J or Esc closes it again**.
- **← →** turn pages. **Tab** switch between Pages and Notebook. Click a struck stone's rubbing in the Notebook to hear its tone again.

*The game*
- **Esc** release the mouse / pause menu (settings, controls, new game); press again to resume.
- **F** send feedback (saves your note, a screenshot and where you were).
- **Ctrl-Cmd-F** full screen.
- A single reassuring line: there is no timer and no way to lose; the island saves automatically.

**Dismiss:** click, Enter, Space, or Esc; and a visible "Click to begin" style affordance at the bottom. Dismissing the screen must capture the mouse exactly as the title screen's click does today (see `AppDelegate.syncOverlay` / `GameView.captureMouse`) and must not leak that click into the world as an interaction. While it is open the game state is frozen (no footsteps, no ambience changes beyond what the title already does).

## 3. One source of truth for the controls

Create a small `Controls` table (for example `App/Controls.swift`): rows of (group, action text, key labels, keycode(s), where it is handled). Feed it to: the intro screen, the pause menu's Controls page, the Help menu hints, and generate the README controls table from it (or add a selftest that the README table lists exactly the same keys). Add a selftest that every row's keycode is actually consumed somewhere (`Input.swift` edge or axis) so the screen cannot drift from the code. Also fix the README table: it is missing R, Z/right mouse, Tab and ← → for pages.

## 4. Edge cases to check

- The key hint shown for toggles must reflect reality (for example J opens and closes; Esc closes the journal without opening the pause menu, as now).
- If the player opens the intro from the pause menu mid-game, closing it returns to the pause menu, not to gameplay.
- F pressed while the feedback panel is already open must not reopen it, and typing the letter F in the panel must type it (existing behaviour, keep it).
- Glass Wood: same controls; no extra screen.
- Keyboard layouts: show the keys by name, not by position (the code uses keycodes: note in the screen's source which are layout-dependent, but do not change the bindings).

## Accept

`--dump-overlay` image of the intro screen (Read it): legible, grouped, keycaps drawn, fits at 1600x900 and at a small window; first launch shows it once then never again; pause menu has a working Controls entry; Help > Send Feedback works; the controls table, README and code agree (selftest); all selftests and bots pass; frame budget unaffected (it is an AppKit overlay).
