# Lanternwright

An original first-person exploration and puzzle game for macOS, in the spirit of *Myst*. Swift, with a hand-built Metal renderer and procedural everything: no engine, no asset files.

**Status:** the vertical slice, *The Isle of Varrow*, is playable end to end. Wake on a dock at golden hour, follow the lantern path past three resonance stones, read the keeper's journal, strike the stones in the right order, and walk the causeway that rises from the sea to the islet. See `docs/DESIGN.md` for the vision and `docs/TASKS.md` for the work queue (M4 polish and M5 the second world are planned).

![overview](docs/shots/m1-overview.png)

## Play
```bash
scripts/bundle.sh && open Lanternwright.app
```
Requires macOS 15+ and the Swift toolchain (Command Line Tools are enough; Xcode is not needed).

| Control | Action |
|---|---|
| Click | capture the mouse / interact with what the ring highlights |
| W A S D (or arrows to turn) | move; **Shift** runs |
| Mouse | look |
| J | journal (← → turn pages) |
| Esc | release the mouse / close the journal |

## Developer tools
```bash
swift build -c release
.build/release/Lanternwright --selftest                      # 124 headless checks
.build/release/Lanternwright --screenshot shots/a.png --view dock --size 1600x900
.build/release/Lanternwright --screenshot shots/b.png --view dock --state solved
.build/release/Lanternwright --bench 60 --size 2560x1440      # GPU time per view
.build/release/Lanternwright --dump-audio shots/ambience.wav  # then: afplay shots/ambience.wav
.build/release/Lanternwright --dump-overlay shots/overlay     # journal / crosshair layouts
.build/release/Lanternwright --help
```
Debug views for the renderer: `--debug depth|shadow|albedo|ambient`.

## Not yet verified by a human
Mouse capture feel, whether the ambient sound is pleasant (`afplay shots/ambience.wav`), and whether the puzzle can be deduced without hints. Everything else is covered by the self-tests or by looking at rendered frames.
