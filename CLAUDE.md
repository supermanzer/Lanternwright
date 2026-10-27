# Lanternwright: agent guide

A Myst-like exploration and puzzle game for macOS, built in Swift with a custom Metal renderer and no engine.
- **Design and vision:** `docs/DESIGN.md`
- **Work queue:** `docs/TASKS.md`. Read §0 "Fixed conventions" before touching any code.

## Workflow for each task
1. Pick the **first unchecked task** in `docs/TASKS.md`. Do only that task, and keep within its listed files and scope.
2. Build with `swift build -c release 2>&1 | grep -E "error:|warning: [^s]|Build complete"`. Ignore the two `ld: warning: search path ... not found` lines; they come from the Command Line Tools install and are harmless.
3. Verify against the task's **Accept** line:
   - Run `.build/release/Lanternwright --selftest` and keep every check passing. Add a selftest case for any new logic.
   - For visual tasks, run `.build/release/Lanternwright --screenshot shots/<task>.png --view <name>`, then **open the PNG with the Read tool and look at it**. A clean build does not prove that a frame looks right.
4. **Independent review.** Before ticking anything, have a separate reviewer agent check the work, following `docs/REVIEW-STEP.md` (brief it fully: task text, the plan it belongs to and why, what you changed, how to verify). It must confirm the task meets its requirements and that it fits the goals of its section. Fix every required change it lists before moving on.
5. Tick the box and add the `> done:` note in TASKS.md, including the line `review: pass` (or the unresolved item). Record anything that later tasks need to know.
6. Stop. Report what changed, what you saw in the screenshot, and the reviewer's verdict.

## Player feedback
Playtest feedback is saved by the game (press **F**) to `~/Library/Application Support/Lanternwright/feedback/`. At the start of a session run `.build/release/Lanternwright --feedback` to read it (text, context, screenshot path; open the PNGs with Read). Turn anything actionable into a task in `docs/TASKS.md`, citing the entry id, and do not delete entries.

## Hard rules
- **No `.metal` files.** Put MSL in Swift string literals under `Render/Shaders/` and register each new source in `ShaderLibrary.sources`. This machine has only Command Line Tools: there is no `metal` compiler and no Xcode.
- Shared Swift⇄MSL structs use only `float4` and `float4x4`. If you change one, update `GPUTypes.swift`, `Shaders/Common.swift`, `expectedStride`, the selftest, and TASKS.md §0 together.
- Follow the coordinate conventions in TASKS.md §0 (Y up, north = −Z, yaw 0 = north). Put landmark positions only in `World/Layout.swift`.
- World generation is deterministic: use the seeded noise only.
- Never run the windowed app in the foreground from an agent shell, because it blocks. Use `--screenshot` instead. Use `scripts/bundle.sh && open Lanternwright.app` only for human play-testing.
- Git: follow `docs/GIT-WORKFLOW.md` (one worktree per agent, `main` is integration-only, ff-only merges, commit by path with selftest green, push at the end of each plan phase; the user has asked for this).
- No third-party dependencies.

## Layout
```
Sources/Lanternwright/
  main.swift, Config.swift, SelfTest.swift
  App/      AppKit window, GameView (MTKView), overlays
  Core/     math, noise, input
  Render/   Renderer (frame graph), GPUTypes, ShaderLibrary, Screenshot, Shaders/*.swift
  World/    Layout, Terrain, Ocean, Props, Colliders
  Game/     Game loop, Player, Interaction, PuzzleState, Journal, Animator, Puzzles/
  Audio/    procedural ambience and chimes
scripts/bundle.sh  → Lanternwright.app (ad hoc signed)
```
