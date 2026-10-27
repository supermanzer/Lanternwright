# X00: roadmap after F03, and how the two builders share the work

Written 2026-10-26 after the user's request for (1) a graphics architecture audit, (2) guided movement and a slower camera, and (3) permission to just make the changes ("the feedback key makes it easy to correct"). Reviewer role: research, plan, review. Builders: implement.

| Plan | What | Builder | Starts |
|---|---|---|---|
| `F03-third-playtest.md` | 19 playtest notes | **A** (pane w1:p1) | running now |
| `G10-graphics-audit.md` | measure, modularise, de-alias, speed up the renderer | **A**, in order, after F03 | when F03's Outcome is filled in |
| `M10-guided-movement.md` | slower camera and walk, soft path corridors, vantage points, region API | **B** (pane w1:p5) | now, M10.1 to M10.8 (touches no `Render/**` file) |
| `G10` stream 3 items G10.3.6 to G10.3.9 | consume B's region API: pinned LOD, shadow bounds, terrain/grass bounds, margin cue | **A** | after M10.6 has merged and G10 stream 1 is done |
| `G10` stream G (grass) | grass rewrite (blade coverage, compute culling) | **B**, after M10.8 | after F03 R3 has landed and A's G10 stream 1 (it moves the grass draw) |

## Rules that keep two builders from colliding

1. **Builder B works in its own git worktree**, never in builder A's directory: `cd ~/Projects/games/lanternwright && git worktree add ../lanternwright-b -b builder-b`. Its own `.build`, its own bundle. (Two `swift build` runs in one tree lock each other and mix half-edited files.)
2. **B's task list is `docs/TASKS-B.md`** (new file, same format as TASKS.md). A keeps `docs/TASKS.md`. Two builders must not both edit one tracking file. INSPECT.md: each builder appends only under its own heading (`## From builder A` / `## From builder B`).
3. **File ownership.** A owns `Render/**` (except the grass files after M10.6), `Audio/**`, `World/**` and the F03 items. B owns `Game/Player.swift`, `Core/Input.swift`, `Core/Settings.swift`, `Game/Navigation*.swift` (new), the movement part of `App/Overlay.swift` (settings sliders only), `World/Layout.swift` **only** the new `Navigation` section at its end, and the grass files from M10.6. Anything outside this list: ask the reviewer (post to the agent board, topic `ownership`) before touching it.
4. **Integration.** B merges to `main` at its own pausing points: `git fetch` is not needed (same repo), so `git rebase main` first, run `--selftest` on the rebased tree, then fast-forward `main` from the main checkout (`git merge --ff-only builder-b`). A does the same in the other direction: it is always on `main`, and B rebases onto it. Neither force-pushes or rewrites `main`. If a rebase conflicts in a file the other builder owns, stop and tell the reviewer.
5. **Selftest must be fully green before every merge** (0 FAIL), as before.
6. Both builders keep the per-task review step (`docs/REVIEW-STEP.md`) and the frame-reading rule.
7. **Bundles.** `scripts/bundle.sh` in the worktree builds `Lanternwright.app` in the worktree: the user's playable app is only ever the one in the main checkout. B never bundles into the main checkout. A bundles after merges.

## Git (supersedes rules 1, 4 and 7 above where they differ)
See `docs/GIT-WORKFLOW.md`: remote `origin` is on GitHub, one worktree per builder (A moves out of the integration checkout at its next pausing point), work branches `a/<topic>` / `b/<topic>`, `main` integration-only with ff-only merges under a board merge lock, push and tag at the end of each plan phase, the merging builder bundles in the integration checkout.

## Decisions already taken (the user asked the reviewer to proceed without approval)

- Slow camera and limited freedom are wanted; implement, make the amount of freedom a setting so the feedback key can correct it.
- Architectural changes to the renderer may be made when measured to help; each one keeps frame-for-frame equivalence unless the plan item says it is a look change, and says so in INSPECT.md.
- Story ending and the S02 fork stay untouched. S02 phase 1 is still waiting; M10 prepares the ground for it (vantage points and corridors are where the tableaux and the fork door will live).

## Order and stopping points

1. A: F03 (now). B: M10.1 to M10.5 (now, in parallel).
2. A: G10 stream 0 (measurement), then streams 1 to 4 in the order in the plan; the region consumers G10.3.6 to G10.3.9 once B's M10.6 is on `main`. B: M10.1 to M10.8, then the grass stream (G10.G.1 to G10.G.3) once A reports stream 1 done.
3. Reviewer checks each pausing point (frames, numbers), then declares **ready to play** only when: both builders idle, `main` committed, bundle built after HEAD, selftest green, reviewer's frame review clean. The user is not asked to play before then.
