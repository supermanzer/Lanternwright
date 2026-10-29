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
| `s03-done` | S03 (builder B): journal tabs by author, the gate (3 + 3 pages, altar, a contradiction), the return (a note nailed to the lighthouse door), the lighthouse interior (a stair, a workshop, the lens room), the tone-plate door, Oren's lens portal, the fork with the other exit sealed by dimming, the Notebook's first contradiction, page revisions R1 to R3 and page 9. Plan: `docs/plans/S03-phase1-fork.md`; user-facing notes in `docs/INSPECT.md` ("From builder B"). The beam signal, lantern chain and chime are builder A's. |

## Not merged (on pushed branches)
- **`a/g10-stream2`** (builder A): the G10.2.2 pre-check, bark investigation tools (`--no-foliage`, `SHIMMER_HEAT`, `SHIMMER_STEP`, `SHIMMER_SCENES`), `PropAudit.materialName` fix, gate script printing alternate hashes. Needs a rebase onto main (expect a conflict on the selftest registration line). `a/g10-resume` is A's current worktree branch (docs only).

## Resume: in this order
1. **Playtest what is bundled** (F04 + everything before). The user has not yet played the F04 build. Look for: the shore from the dock and the east beach (no polygons in the shallows, no ripples on the sand bar), one sheet per page, page 3 reads as it originally did, no shadow from the altar's light column. Notes with F as before (they record guidance mode, pace and pass ms).
2. **Builder A** (pane `w1:p1`, worktree `../lanternwright-a`): follow the RESUME NOTE at the top of the G10 section of `docs/TASKS.md`: rebase `a/g10-stream2`; then bark/trunk-edge band-limit, tree LOD dither, the shared `thin_coverage` helper (post on board topic `ownership` when on main: builder B's G10.G.2 waits for it), then **G10 stream 3 efficiency** (the user's pass ms shows 13-17 ms frames at full resolution: overdraw check on opaque + sky, AO copy, shadow cache, MetalFX below render scale 1), then the rest of stream 2 (dither, water/glass specular, shadows measured-no-action, velocity buffer last). Also look at the faint pale streak on the sand in the high-side shore view (`--camera 150,14,172,-1.2,-0.6`).
3. **Builder B** (pane `w1:p5`, worktree `../lanternwright-b`): S03 is done (tag `s03-done`; hand-off in `docs/INSPECT.md` under "From builder B", resume note at the top of `docs/TASKS-B.md`). Next for B: **G10.G.2** (chunked grass fade using A's `thin_coverage` helper, now on `main`), then whatever the user's S03 playtest asks for. G10.G.3 was dropped.
4. **Re-brief both panes** (they kept their worktrees; their context is old): point them at this file and their resume notes.

## Open decisions for the user (builders must not decide these)
- (S03's three questions were answered by the user on 2026-10-28: both exits at the lighthouse, the gate 3 + 3, sealing is dimming only; see `docs/plans/S03-phase1-fork.md`, USER DECISIONS.) **Open and the user's to judge:** S03's consequence that pages 4, 5 and 8 are now required for the gate (the contradiction's evidence; cheap alternatives in `docs/TASKS-B.md` S03.9), the contradiction's sides (an interpretation), "touch the lens" as Ilse's start (Q12), the page 4 half-line placed after the full stop, page 9's place on the dock (Q15). Everything else builder B defaulted is a Q in `docs/OPEN-QUESTIONS.md`.
- Page revisions R1 to R3 were APPLIED in S03.10 (page 5's first sentence, page 4's half-line, new page 9; pages 3 and 8 unchanged; `docs/plans/S03-page-revisions-applied.md`); R4 and any further wording stay the user's (they have changed their mind about wording before).
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

## Progress note, 2026-10-28 evening (reviewer usage limit reached)
- **Builder B** (S03): S03.1 to S03.4 and S03.5a merged to `main` (pages as data, journal tabs, the gate, the return with the door note and corridor route, the lighthouse interior with stair and collision); its usage limit hit at 8:43 pm and it resumes by itself at 11:40 pm. Next for B: S03.5b (workshop, lens ring and lamp, rail, footsteps), S03.6 tone-plate door, S03.7 lens portal, S03.8 fork, S03.9 contradictions, S03.10 page revisions R1-R3, S03.11 tag `s03-done`; then G10.G.2 (A's `thin_coverage` helper is on main). B waits on four items from builder A (board topic `ownership`/`story`): door-leaf split, interior light model, footstep hook, exact lens centre; plus the beam signal pattern (S03.4a) and the lens-portal render item (S03.7).
- **Builder A** (G10): stream 3 partly merged (terrain-shader cost cut 8-31%, bark band-limit, `thin_coverage` helper); queue in order: output dither, water/glass specular AA, velocity buffer then MetalFX, region consumers (pinned LOD, shadow bounds, terrain mesh density, margin cue), CPU encode time, and A's S03 asks (beam signal, lens portal, interior light) as soon as posted; tags g10-s2, g10-s3, g10-s4 at phase ends.
- **Reviewer (this session):** hit its usage limit. On resume: `herdr agent list`, read both panes, re-direct any idle builder from the queues above, check `docs/OPEN-QUESTIONS.md` (Q1-Q8 logged, none blocking), and verify main (selftest, bundle after HEAD) before saying the build is ready to play. Standing rule: do not block on the user except hard forks.
