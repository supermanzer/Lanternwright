# X01: builder queues (2026-11-14), written for builders starting from an empty context

You are one of two builders on **Lanternwright**, a Myst-like macOS exploration/puzzle game (Swift, hand-written Metal, no engine, no dependencies). The user plays and leaves feedback; a **reviewer** (pane w1:p4) researches, plans and reviews; **builders implement**. Builder A = pane w1:p1, worktree `~/Projects/games/lanternwright-a`. Builder B = pane w1:p5, worktree `~/Projects/games/lanternwright-b`. The integration checkout `~/Projects/games/lanternwright` stays on clean `main` (nobody edits code there; the user's `.app` is bundled there).

## Read first, in this order (about 20 minutes; do not skip)
1. `CLAUDE.md` in your worktree (rules, build and test commands, hard rules: no .metal files, never run the windowed app in the foreground, use `--screenshot` and Read the PNG).
2. `docs/GIT-WORKFLOW.md` (one branch per topic off `origin/main`, commit by path with selftest 0 FAIL, ff-only merge under the board `merge` lock, push, tag per phase, rebundle in the integration checkout after merging).
3. `docs/STATUS.md` (what is done, tags, decisions the user has made: **do not reopen "Decided by the user"**).
4. `docs/plans/X00-roadmap-and-coordination.md` (who owns which files: A owns `Render/**`, `Audio/**`, `World/**`; B owns `Game/**` movement, navigation, story, grass files; announce overlaps on board topic `ownership`).
5. `docs/plans/F09-seventh-playtest.md` and its done notes (what just landed), `docs/plans/F10-open-f09-defects.md`, `docs/plans/P01-myst-puzzle-benchmark.md`, `docs/plans/P02-puzzle-restructure.md` (the design yardstick: **visible problem, hidden solution, visible consequence**; one verb and channel per puzzle; keys carried between worlds).
6. `docs/OPEN-QUESTIONS.md` (tail), `docs/INSPECT.md` (what the user must look and listen for), `docs/plans/S03-player-path.md` (what a player must discover, in order).
7. Board (`mcp__agent-board__read_board_topic`): topics `progress-lanternwright`, `ownership`, `merge`, `story`, `learnings`. Also `~/.claude/command-failures.md` (zsh and BSD sed traps).

## Standing rules (the user's, and they apply to every phase)
- **Never block on a decision for the user.** Take the default, write it up in `docs/OPEN-QUESTIONS.md` as a Q (number: take the next free one; check `origin/main` first; builder A uses Q54-Q69, builder B uses Q70-Q89, the reviewer keeps Q37-Q53 and Q90+), say where it lives and what changes if the user answers differently, and carry on. The reviewer copies each new Q into the user's Question Log artifact; you do not need to touch the artifact.
- **Page wording is the user's.** Never edit the text of journal pages or the door notes' wording beyond what a plan explicitly tells you; write proposed text to `docs/plans/P02-page-drafts.md` and do not apply it.
- **Never ask the user to play.** The reviewer says when a build is ready. You maintain `docs/INSPECT.md` rows (what to look/listen for).
- Anything audio is untested by ear: say so plainly, and judge it in selftest by numbers.
- Judge visuals by `--screenshot` frames you actually Read (walking-distance views, not only overview). A green selftest does not prove a frame is right.
- Independent review before ticking a task: spawn a reviewer subagent per `docs/REVIEW-STEP.md`.
- Mutation-check every new test (break the thing, see the test fail, restore).
- Commit only when `--selftest` shows 0 FAIL; shader validation clean (`scripts/validate-shaders.sh`) if you touched rendering; frame-hash gate (`scripts/stream1-check.sh`) when you did not intend frames to change.
- Append non-obvious failed commands to `~/.claude/command-failures.md`; post milestones and lessons to the board (`progress-lanternwright`, `learnings`).

## The phase protocol (important)
Work is in **phases**. A phase ends when its tag is pushed and the integration checkout is rebundled. Then: write your report with exactly three headings, **Blocked on me / Changed / Found**, and STOP (go idle). The reviewer reviews, then runs `/compact` in your pane to keep your context small, then sends you the next phase. So at the end of each phase make sure everything you will need later is **in the repo** (docs, TASKS, INSPECT, OPEN-QUESTIONS, board), not only in your head: after `/compact` you will re-read `docs/plans/X01-builder-queues.md` and your phase notes. Keep a short `## Phase log` at the bottom of your TASKS file (`docs/TASKS.md` for A, `docs/TASKS-B.md` for B): date, phase, tag, what is next.

## Builder A queue (Render, World, Audio)
**A1 (tag `f10-a`):** the F10 items for A, in order: (1) the strait reads as deep water (depth-based sea absorption, see F10); (2) the return/portal ring and disc: no blown-out white, no polygon silhouette, same family for `ta_return_*`, quay lenses and the lens-portal halo; (3) P02.4 charge meters (emissive channel plus a uniform builder B sets) on the lens-room receiver and the prism mark.
**A2 (tag `p02-a1`):** mirror-court receiver glow: three receiving crystals in the Glass Wood court that light when the beam arrives (a uniform per receiver B can drive; plan P02.1), and the **beam signal pattern** work for P02.3: after the altar the lighthouse beam flashes a signal of three groups with distinct lengths, readable from a corridor vantage on the dock approach at dusk; a terrain ray test and a frame per group; hand B the group durations as constants in `World/Layout.swift`. If no corridor point can see the beam at dusk, log a Q and use the plates' glint fallback in `docs/plans/P02-puzzle-restructure.md` section 7.
**A3 and later:** the reviewer will send the S05 world work (divergent sibling sites) when `docs/plans/S05-divergent-routes.md` is written. Until it arrives, after A2 do the polish list in `docs/INSPECT.md` marked A, then stop and report.

## Builder B queue (Game, story, navigation, puzzles)
**B1 (tag `f10-b`):** the F10 items for B: P02.0 `PuzzleGraph` data and metric selftests, loading today's puzzles and reporting every rule break in `docs/plans/P02-graph-report.md` (fix nothing yet); the #111 decision; the guide lantern and lamps versus closed sluice gates check; the sluice-pit push if cheap.
**B2 (tag `p02-b1`):** P02.1 mirror-court logic (live feedback: receivers light as hit, solved when all three are lit at once; update the selftest from "exactly one" to the new rule with a greedy-solver bot measuring manipulations; A supplies the glow uniforms, stub them until A2 lands); P02.5 the planted clues and the keys table wired as data in the graph (P02 sections 3.1, 3.2).
**B3 (tag `p02-b2`):** P02.2 the Notebook records what the player looked at closely (LookCloser), and the island-profile diagram page art drawn by the overlay (code and art only; NO page text edits: drafts go to `P02-page-drafts.md`); P02.3 the plate rule on the beam rhythm using A's constants (the old order stays as the Notebook fallback hint; `TonePlatePuzzle.order` becomes data).
**B4 and later:** S05 story/puzzle work when the reviewer sends `S05-divergent-routes.md`; until then, after B3 re-run `PuzzleGraph` and fix every remaining rule break the report lists that is cheap, log the rest as Qs, then stop and report.

## Coordination
- A's glow uniforms and beam constants gate B2/B3: post on `ownership` when A2's parts are on main. B must not wait idle: stub and carry on.
- Both of you edit `docs/OPEN-QUESTIONS.md`, `docs/INSPECT.md` and TASKS files: rebase before merging, keep your sections separate, resolve conflicts by keeping both.
