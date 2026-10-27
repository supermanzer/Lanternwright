# Project status and how to resume

**Paused 2026-10-27 at the end of G10 stream 1** (user request). Everything is committed, merged to `main`, and pushed to https://github.com/supermanzer/Lanternwright.git. `main` = `origin/main`; selftest 941 PASS / 0 FAIL; `Lanternwright.app` in the integration checkout was bundled after HEAD.

## Phases done (tags on `main`)
| Tag | What |
|---|---|
| `f03-done` | F03: 19 playtest notes (rendering artifacts, trunks and needles, audio, dropped pages, shore physics, step fix). Outcome at the top of `docs/plans/F03-third-playtest.md`. |
| `m10-done`, `m10-pace` | M10 guided movement: calmer look, pace 2.6 / 4.4 m/s, navigation corridors with soft confinement, vantage stations (stones pilot), reachable-region API and soft-lock audit, Guidance setting (Guided / Loose / Free roam). Hand-off notes in `docs/INSPECT.md` under "From builder B". |
| `g10-s0` | G10 stream 0 (measure): per-pass GPU timer, shimmer attribution, banding probe. Baselines in `docs/shots/` (`pass-times-baseline.txt`, `shimmer-baseline.txt`, `banding-baseline.txt`). |
| `g10-s1` | G10 stream 1 (modularise): `RenderTargets`, the frame as a list of passes (`Renderer.encode` is 8 lines), per-pass frame-uniform values, `Lit` shader split by concern. 27 frames byte-identical to `docs/shots/frame-hashes-baseline.txt`; check with `scripts/stream1-check.sh`. |

## What to do next (in order)
1. **Playtest** what is bundled (F03 + M10). Ask for the notes with F; they record guidance mode and pace. Things to judge: calm look and pace; corridor edges (use Guidance = Loose if it feels policed); stones' framing stations; deck footsteps at the slower cadence; shallows, door rattle, gravel slide, wind (by ear).
2. **Resume G10 at stream 2, task G10.2.2** (builder A). The order was re-set from the measurements: thin geometry with TREES first, then props, grass last (G10.2.2); output dither (G10.2.3); water and glass specular AA (G10.2.4); shadow seams, re-measure first (G10.2.5); velocity buffer last with a restated accept (G10.2.1); LOD dither review (G10.2.6). Then stream 3 (efficiency; pinned LOD, shadow bounds, terrain and grass bounds, margin cue now unblocked by the region API), stream 4 (MetalFX), and the grass stream for builder B (compute culling; its crawl-fix half is dropped: grass is about 1% of the crawl). Restart steps are in the RESUME NOTE at the top of the G10 section of `docs/TASKS.md`.
3. **Pending small items:** `PropAudit.materialName` lacks names for some material ids; intermittent TAA frame-hash flake (about 2 in 25 on the same build, also before the refactor; cause unknown, possibly a real race: the stream-1 gate retries and reports it; harden it to print the alternate hash); the framegraph selftest only greps for `r.frame`.
4. **User decisions still open** (`docs/INSPECT.md`): the story ending (Ilse vs Oren; S02 fork, Phase 1 not yet planned for the builders), conifers/needle look verdict, whether the corridors feel right, door interior (decided: stays locked), page findability balance (F03 P1 made pages overlookable on purpose).

## How the team works (details in `docs/GIT-WORKFLOW.md`, `docs/plans/X00-roadmap-and-coordination.md`)
Reviewer session (research, plan, review) plus two builders in herdr panes: A = `w1:p1` (owns `Render/**`, `Audio/**`), B = `w1:p5` (movement, navigation, later grass). One git worktree per builder (`../lanternwright-a`, `../lanternwright-b`), `main` integration-only with ff-only merges, push and tag at the end of each phase. The reviewer says when a build is ready to play; the user is not asked to play before that.

## Plans
`docs/plans/`: F01, F02, F03 (playtests), S01/S02 (story, the fork), G10 (graphics audit), M10 (guided movement), X00 (coordination), M10-puzzle-notes (what corridors and stations make possible for each puzzle).
