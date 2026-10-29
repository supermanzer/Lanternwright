# Project status and how to resume

**Paused 2026-10-28 at the end of F04** (user request). `main` = `origin/main` (code last changed at `a7bed9a`, docs at `2994270`); selftest green at the F04 merge; `Lanternwright.app` in the integration checkout was bundled after the last code commit (07:44 vs 07:43). Both builders are idle with clean, pushed worktrees.

## Phases done (tags on `main`)
| Tag | What |
|---|---|
| `f03-done` | F03: notes #33-#51 (artifacts, trunks and needles, audio, dropped pages, shore physics, step fix). |
| `m10-done`, `m10-pace` | M10 guided movement: calmer look, pace 2.6 / 4.4 m/s, navigation corridors with soft confinement, vantage stations, reachable-region audit, Guidance setting (Guided / Loose / Free). |
| `g10-s0` | G10 stream 0: per-pass GPU timer (`--bench`, `pass ms` in the F-key context), shimmer attribution (`--shimmer-layers`), banding probe. Baselines in `docs/shots/`. |
| `g10-s1` | G10 stream 1: the frame is a list of passes, `RenderTargets`, per-pass uniforms, Lit shader split. 27 frames byte-identical (`scripts/stream1-check.sh`). |
| `g10-g1` | G10.G.1 (builder B): grass compute culling and indirect draw; grass cost about 0.5 ms to about zero, frames byte-identical. |
| `f04-done` | F04: notes #52-#59 that were bugs: the shore waterline decided per pixel (#52), decoy loose sheets removed (#53-55), page 3 wording restored (#56), light sources cast no shadow (#57). Plan: `docs/plans/F04-fourth-playtest.md`. |

## Not merged (on pushed branches)
- **`b/s03-1`** (builder B): S03.1 "pages as data, route flags and story block in the save", implemented, **review pending**. Also contains `13aa7ac`: restores the `runGrassCull` registration in `SelfTest.swift` that the F04 L1 merge dropped from `main` (a test, not behaviour; **main currently does not run the grass-cull selftest**). `docs/TASKS-B.md` with the resume note lives on this branch.
- **`a/g10-stream2`** (builder A): the G10.2.2 pre-check, bark investigation tools (`--no-foliage`, `SHIMMER_HEAT`, `SHIMMER_STEP`, `SHIMMER_SCENES`), `PropAudit.materialName` fix, gate script printing alternate hashes. Needs a rebase onto main (expect a conflict on the selftest registration line). `a/g10-resume` is A's current worktree branch (docs only).

## Resume: in this order
1. **Playtest what is bundled** (F04 + everything before). The user has not yet played the F04 build. Look for: the shore from the dock and the east beach (no polygons in the shallows, no ripples on the sand bar), one sheet per page, page 3 reads as it originally did, no shadow from the altar's light column. Notes with F as before (they record guidance mode, pace and pass ms).
2. **Builder A** (pane `w1:p1`, worktree `../lanternwright-a`): follow the RESUME NOTE at the top of the G10 section of `docs/TASKS.md`: rebase `a/g10-stream2`; then bark/trunk-edge band-limit, tree LOD dither, the shared `thin_coverage` helper (post on board topic `ownership` when on main: builder B's G10.G.2 waits for it), then **G10 stream 3 efficiency** (the user's pass ms shows 13-17 ms frames at full resolution: overdraw check on opaque + sky, AO copy, shadow cache, MetalFX below render scale 1), then the rest of stream 2 (dither, water/glass specular, shadows measured-no-action, velocity buffer last). Also look at the faint pale streak on the sand in the high-side shore view (`--camera 150,14,172,-1.2,-0.6`).
3. **Builder B** (pane `w1:p5`, worktree `../lanternwright-b`): merge the `13aa7ac` registration fix first, finish S03.1's review, then S03.2 onward per `docs/plans/S03-phase1-fork.md` (the story fork). G10.G.3 was dropped; G10.G.2 (grass far-field coverage) waits for A's helper.
4. **Re-brief both panes** (they kept their worktrees; their context is old): point them at this file and their resume notes.

## Open decisions for the user (builders must not decide these)
- S03's three questions: (1) is moving Oren's decisive act (turning the beam to open the dock arch) from the shore into the lighthouse's lens room what notes #58/#59 mean? (2) Is "3 pages of each author" the right gate now that pages are overlookable? (3) Warn on sealing the other exit, or only dim it (default: only dim)?
- Page revisions R1-R4 (S02 appendix) are **held** until the user has seen the text (`S03.10` produces a review file); the user has twice reacted to page wording.
- (none of the earlier items remain open; see Decided below)

## Decided by the user (do not reopen without asking)
- 2026-10-28: S03 questions: both exits at the original lighthouse (Oren's is a lens portal in the lens room, not the dock arch); a note nailed to the lighthouse door and a changed beam pattern signal the return; the gate is 3 pages of each sibling; sealing the other exit is a visible dimming only (irreversibility is not announced); page revisions R1-R3 applied (page 3 stays as restored, page 8 unchanged).
- 2026-10-28: **the hidden reconciling third ending (S02 section 8) is approved in approach**: found only by noticing, completed between the two stands by the beat of both tones, with its cost (two keepers, the player the third).
- 2026-10-28: **the needle-level conifer look is kept** (about 13 m, then the stylised sprays). Performance work must not shorten that range or shrink the cards; speed it up another way.
- 2026-10-28: **the guided corridors are kept** (default Guidance = Guided, coverage about 10-13%). Loose stays available.
- Earlier: the locked lighthouse door became the Ilse exit; Maren's fate stays ambiguous; slip on steep slopes is on; the story ending's other details are in S02 section 8.

## Known issues
- Intermittent TAA frame-hash flake (about 2 in 25 renders of the same build, also before the refactor; cause unknown, maybe a race). `stream1-check.sh` retries and now prints the alternate hash.
- The grass cull margin (10 m) has about 1 m of headroom against a 5.2 m Glass Wood tuft in a full gust; if grass gets taller the margin must grow.
- Effort measured so far says: shimmer is mostly tree trunks/branches/bark and the tree LOD dither, then props and water, not grass.

## How the team works (details: `docs/GIT-WORKFLOW.md`, `docs/plans/X00-roadmap-and-coordination.md`)
Reviewer session (research, plan, review) plus two builders in herdr panes: A = `w1:p1` (owns `Render/**`, `Audio/**`, `World/**`), B = `w1:p5` (movement, navigation, story/Game, grass files). One git worktree per builder, `main` integration-only with ff-only merges, push and tag at the end of each phase, the merging builder bundles in the integration checkout. The reviewer says when a build is ready to play.

## Plans
`docs/plans/`: F01-F04 (playtests), S01/S02 (story, the fork), S03 (story phase 1: the return, the lighthouse as the place of choice, the gate, interior, tone-plate door, dock portal), G10 (graphics audit), M10 (guided movement), M10-puzzle-notes, X00 (coordination).
