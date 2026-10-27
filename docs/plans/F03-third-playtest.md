# F03: third playtest (notes #33 to #51)

## Outcome: what was actually implemented (as of the F03 closing commit; see the git log for the hash)

Added after the work landed; the plan below is kept as written. Task ids refer to `docs/TASKS.md` (the F03 section, T68.x). "Needs you" means a person must look or listen. Every task had an independent reviewer (docs/REVIEW-STEP.md); evidence, numbers and honest limits are in each `> done:` note and in `docs/INSPECT.md`. The full selftest is 785 PASS, 0 FAIL.

| # | Final solution | Task | Status |
|---|---|---|---|
| 33 | The 6 cm sand rows are gone (a faint 0.5 m swell and the 2.6 m swells remain); plank growth rings 12 cm apart instead of 4 cm, fibre contrast 24 % to 10 %, and the dashed lines were thin fibre and check lines aliasing in the relief derivative (removed from it); **the "lines in the water" were the shallow-water caustic net** (13 % of the bed's brightness), now 3.5 % and wider. | T68.13 | Needs you |
| 34 | Shore physics (World/Shore.swift, shared with the shaders): crests are delayed by shallow water (5-20 s at the contact line) and die at it; the sheet there is a swash FILM (at most 5 cm over the ground, 3.8 mm at its tip, no step over 4.5 cm; the edge runs up fast, drains slowly and draws down below the sea's contact between surges, in groups); the lee of the island is reached about 6.6 s later by waves 55 % as high; the wet sand follows the swash groups' reach. +0.08 ms. | T68.14 | Needs you |
| 35 | **The step limit was not the fault** (already 0.5 m, above the 0.35-0.4 asked). The dock's first board was refused as a steep slope because only Platforms were exempt; a deck is now a step. | T68.12 | Done, test-backed |
| 36 | Deck step pinned: `DeckPin`, +-5 %; the recipe is untouched. | T68.15 | Done |
| 37 | Wind lull -26 dB (was -14) and gust -10 dB (was -2) against the waterline surf, 89 % of its energy under 300 Hz, a faint grass-driven rustle only; grass sways 2.5 times as far, conifer crowns carry a slow breeze sway. The drone keeps its old absolute level. | T68.7 | Needs your ears |
| 38, 39, 42 | **Every `tube()` was wound inside out**: the near wall of every trunk, branch and rail was culled and you saw the inside of the far wall; the "unlit highlight" was that inner wall catching the sun on the wrong side. Fixed, selftested; new pine bark; 12-sided trunks. | T68.5 | Needs you |
| 40, 41 | Needle angle (+-4 degrees) and length (+-15 %) jitter; the near crown had a third less greenery than the far sprays: cards 1.5x longer, 1.3x wider; measured equal within 10 % from the same elevation, 16 % from the player's eye. About +0.7 ms among trees. | T68.6 | Needs you |
| 43, 51 | Dropped pages: no lectern, glow, thread, motes, chime, banner or marker; sheets settled 3 mm onto the surface under them with loose sheets beside; a gust-flutter is the only clue. **The altar lectern had been set into the dais; the arrival plate and chime base (raised slabs) were not walkable and had buried the pages there: now platforms.** | T68.11 | Needs you: the balance is yours |
| 44 | Door: knock, rattle (2-4, 16-42 ms apart), then the jangle 0.13 s later; harder with repeated tries. | T68.8 | Needs your ears |
| 45 | Gravel slide voice, level follows speed, gone in 0.2 s, grass softer. | T68.9 | Needs your ears |
| 46 | The debug material sheet, floating 900 m north, was built into every game: only built for `--view material-sheet` now. | T68.1 | Done, frames |
| 47 | The mist pass drew the ocean's indices over the last crystal tree's vertices (the ghost in the sky); fixed. The dark bars are real shard shadows (`--hide gw_tufts`). | T68.2 | Done, frames |
| 48 | NOT reproduced headlessly; most likely the flat gust flipping the whole meadow's lean in unison: front tilted and scattered, lean halved; coverage and TAA-walk selftests. | T68.3 | Needs you: tell me if it still blinks |
| 49 | Water is bubbles (3.26/r Hz, 5-30 ms, rising), a low splash body per footfall, sparse bubbles for the wash. Very quiet. | T68.10 | Needs your ears |
| 50 | Bands: 1 m ripples at full strength seen at 50 m, now broad and soft; streaks: the page-5 thread and motes. | T68.4 | Done, frames |

**Where the build differs from the plan.** R3 is "most likely cause", not "cause found". The A2 rattle impacts are 16-42 ms apart, not "a few ms". The ground-eye needle test allows 16 % (a steep view into a crown shows less), the level-eye one 10 %. The M1 limit was left at 0.5 m (the plan asked to raise it to 0.35-0.4; it was already higher). The G2 swash is a model on the existing sea plane (no real wave solver; no wave breaking foam change). The sight-line test for pages is weak (a heading test, not occlusion). Not done: a second deck-pin plank; windblown particles (F02).

**Process.** All 15 tasks went through the independent reviewer step. Changes were required on T68.2 (debug hooks I had left in; evidence for the shadows), T68.3 (a real coverage test and honest wording), T68.9 (an end-to-end slide test, a lower level), T68.15 (a tighter pin). One mistake of mine worth naming: I committed once with two full-selftest failures (the wind retune moved a level the drone and one audio test were defined against) after running only the wind group; the next full run caught it and it was fixed before any review of that commit.

**Next.** docs/plans/G10-graphics-audit.md (see docs/plans/X00-roadmap-and-coordination.md first).

Source: `Lanternwright --feedback` entries #33 to #51 (screenshots in `~/Library/Application Support/Lanternwright/feedback/`, files `20261025-1630*` to `20261026-0729*`). The reviewer read every note and opened the screenshots for #46, #47, #50 and #51.

**Triage into TASKS.md first (accept with an Accept line, or REJECT with a reason).** Some of #33 to #34 and #38 to #42 may already be covered by R11 / T67.x or F02 T66.x: check each against current code, and mark "already done" only with a frame or a test as evidence. Same rules as before: before/after frames Read and compared (0.5 m close-up from two sides for any geometry), absolute targets asserted in selftests where a number can capture it, per-task review step, selftests green before each commit, `docs/INSPECT.md` updated, `scripts/bundle.sh` at the end, story ending untouched. Fill in an "Outcome" section at the top of this file when finished, in the style of F02's.

Order: P0 rendering artifacts first (they read as bugs), then trees, then audio, then the page-pedestal redesign, then the rest.

## The user's notes, mapped to workstreams

| # | Note (short) | Workstream |
|---|---|---|
| 33 | Dock/sand lines too pronounced and coarse; waves have a longer wavelength and would not sort sand in fine rows; wood cut into planks has no such lines | G1 |
| 34 | Water rises straight out of the ground as waves progress; wave energy should propagate along the coast with delay, like real water meeting an island | G2 |
| 35 | Cannot step up onto an obstacle of modest height | M1 |
| 36 | Deck walking sound is spot on | keep unchanged (add a selftest pin on its spectrum so later work cannot regress it) |
| 37 | Wind audio far too strong for how calm the island looks; make it much softer and make grass and trees visibly respond | A1 |
| 38, 39 | Tree trunk still looks inverted: the inside of the far wall curving away, not a solid trunk curving toward the viewer; wants pine bark | G3 |
| 40 | Needles too orderly; add slight randomness in angle about the source direction | G4 |
| 41 | The far stylised-to-needle change makes the tree lose about half its size; needle count near must match the greenery in the far view | G4 |
| 42 | Highlights on a trunk with no light source (sun is the other way) | G3 |
| 43 | Page pedestals too deliberate; resume the dropped-pages approach; players may overlook pages and struggle | P1 |
| 44 | Locked door should rattle: wood on stone as well as the jangling pull | A2 |
| 45 | Sliding down a steep slope should sound like gravel giving way | A3 |
| 46 | Odd vertical lines in the sky (home island, far south, looking at the stones) | R1 |
| 47 | Strange geometric shadows in the sky around the glass trees | R2 |
| 48 | The whole grassy area blinks as the player passes | R3 |
| 49 | Walking in the shallows sounds like shag carpet, not water | A4 |
| 50 | Odd light aliasing (Glass Wood pool) | R4 |
| 51 | The page pedestal is sunk into the plinth instead of standing on it | P1 |

## P0: rendering artifacts (R1 to R4). Diagnose before fixing

The user's rule for all four: **nothing in a frame may be there unless it is intended.** Each of these needs a cause found, not a mask. Use `--screenshot` with a matching `--pos`/`--yaw`/`--pitch` (the feedback entries carry them) and bisect by turning passes off (TAA, bloom, fog, shadows, grass, sky) to find which pass draws the artifact.

- **R1 (#46, play position -37.7, 4.1, -278.2, yaw -0.01, pitch 0.11).** Reviewer saw only a tiny dark glyph just above the horizon, centred between the stones and the cloud (about x=995, y=517 of 2000). If that is the "vertical lines", it is probably a distant prop, the unread-page marker, or a far lantern/beam drawn at the wrong scale; the user may also have seen it while moving (flicker or streak). Reproduce with a camera path (a short walk toward the stones), and capture 3 consecutive frames. Name the object, then remove it or make it intentional.
- **R2 (#47, position -4.9, 8.3, 116.3, yaw 2.65, pitch -0.33).** Two things in the frame: (a) a translucent ghost structure in the haze near the horizon (about x=1010, y=190), geometric and not part of the scene; (b) hard-edged geometric shadow shapes on the cobbles and grass that read as projected from nothing. Check shadow cascade bounds and far-plane clipping of the sky/haze pass, whether shadow casters (crystal trees, lanterns) outside the visible set still cast, and whether (a) is a mirror-court reflection or an LOD proxy leaking through fog.
- **R3 (#48, position -14.5, 9.1, 105.9).** "The entire grassy area blinks as I pass." Likely a per-cell grass visibility or LOD toggle (cell snapping or hysteresis missing at the player's position), or TAA history reset when the grass pass changes coverage. Instrument: log grass cell set per frame while walking a line; assert in a selftest that the set of drawn cells never changes by more than the leading/trailing edge per step, and that total grass pixel coverage does not change by more than a few percent between consecutive frames at a 0.1 m step. Check also the F02 needle-level foliage dissolve (T66.13) and the wind field for time discontinuities.
- **R4 (#50, Glass Wood pool, position -18.7, 13.1, -17.0, yaw 2.36, pitch -0.32).** Reviewer saw: a thin bright vertical streak from the far rim down to the water (about x=795, y=270 to 540), faint diagonal streaks at the right edge (about x=1100 to 1130, y=380 to 470), and a banded moire pattern on the pale rim of the pool (right side, about x=1100 to 1900, y=430 to 600). The streaks are probably the light-thread or caustic/god-ray geometry; the bands are an unfiltered high-frequency pattern on the shelf sand. Remove the streaks unless intended, and band-limit the pattern by pixel footprint (as the other shaders do).

Each fix lands with a before/after frame pair, and a selftest or a measured number where one can capture it (R3 especially).

## M1: step height (#35)

The user could not step onto "an obstacle of such a modest height" (screenshot `20261025-163332.png`; open it and measure the obstacle). `Player.maxStep` is already 0.5 m, so the limit is probably not the controller's height test. Measure the obstacle in the screenshot, then find what actually refuses the move: a collider (`Colliders.resolve` pushing the player out of a box whose top is below `feetY + maxStep`, or the collider's height being taken from the eye instead of the feet), the slope test (`rise / run > maxSlope` on a short, tall step: `canMove` only exempts `isOnPlatform`), or the sea limit. Fix the cause, and add a selftest with a 0.2 m, 0.4 m and 0.6 m box: the first two are climbed, the third is refused.

## G1, G2: sand ripples, dock grain, coast waves (#33, #34)

- **G1.** Sand ripple pattern: lengthen the wavelength to roughly 1 to 3 m crest-to-crest in the swash zone, lower the contrast and make it break up (varied crest height, bifurcations, faded with distance from the waterline), instead of fine parallel rows. Plank grain: lower the grain contrast and stripe frequency (real sawn planks show soft, wide figure with the occasional knot, no dense regular lines). Check against the T67.1 shared wood grain from R11 before changing it.
- **G2.** The swash and wave sheet should follow the real mechanics: waves arrive as a train with a phase that depends on depth (celerity about sqrt(g*h) in shallows), the water edge runs up and back down the beach slope with a lag and loses height, and the sheet's lateral position follows the beach contour so it wraps around the island instead of rising vertically out of the sand. In practice: drive the shoreline height from a depth-dependent phase, add a thin wet-sand band that darkens and dries behind the swash, and fade the water sheet to zero thickness at the contact line. Absolute target to assert: sheet thickness at the contact line below 5 mm, and a measurable arrival delay of crests that grows toward the lee side.

## G3, G4: trunks and needles (#38 to #42)

- **G3 (#38, #39, #42): the trunk.** Two separate faults. (1) The trunk appears hollow: this is a back-face or winding problem or a flipped normal, since the user sees the inner wall curving away. Check face winding and the normal sign in the trunk tube and its LOD versions, and the depth/cull state of the pass. **Verify with a 0.5 m close-up from two sides and a cross-section selftest: for each sampled trunk vertex, the normal must point away from the axis.** Also make the shading read as pine bark: vertical furrows with plated ridges, darker in the grooves, a warm grey-brown colour; no glossy look. (2) The unlit highlight (#42): trunk specular and any rim term must come only from the sun or a named light; with the sun behind the tree there must be no bright band on the trunk's far side. Audit every specular/Fresnel/rim term on trees and remove any that is not driven by a real light direction.
- **G4 (#40, #41): the needles.** (a) Jitter each needle's angle about its source direction by a few degrees (seeded per needle, not per frame), also vary length by about 15%. (b) Match coverage between levels: the number and total area of needles at the near level should reproduce the greenery silhouette of the far stylised sprays. Measure: render the same tree at 30 m (far) and 14 m (near) with the camera scaled to match, and compare the foliage mask area. Target within 10%. The dissolve should then be unnoticeable, not a size change.

## A1 to A4: audio (#37, #44, #45, #49; #36 is a keep)

Use absolute targets and assert them in selftests, as F02 asked (F01's relative measurements were heard as wrong).

- **A1 (#37) wind.** Reduce the wind rush by a further 10 to 12 dB in lulls and about 6 dB at gust peaks; the low-frequency content (below 300 Hz) should dominate and nothing above 2 kHz except a faint leaf-rustle band that follows the grass motion. At the same time raise the visible response so that sound and sight agree: grass blade bend roughly 2 to 3 times today's amplitude on the home island, visible sway in the conifer crowns, slow cloud drift. The user's phrase to satisfy: "the audio implies a very high velocity wind", so the audio level must imply a light breeze (2 to 4 m/s) while the visuals clearly move.
- **A2 (#44) locked door.** When the player tries the door, play a composed event: a heavy wood-on-stone knock (the door shifting about 1 cm in its frame and hitting the stone reveal: a dull, low "thunk" of 80 to 200 Hz body with a short 1 to 3 kHz transient, 40 to 80 ms), a loose rattle of the planks and ironwork (2 to 4 quick damped impacts a few ms apart, decaying within 300 ms), and then the existing pull-ring jangle, slightly delayed. Scale with how hard/long the attempt is. No tonal ringing on the wood and stone part.
- **A3 (#45) slope slide.** While the player slips on a steep slope, play a loop of gravel giving way: dense grains (many 5 to 30 ms noise bursts, 1 to 6 kHz, random density rising with slide speed), a low 100 to 250 Hz bed for the moving mass, and a few larger stones clacking. Level follows speed, stops within 0.2 s of regaining footing. Surface-aware: grass slopes get a softer, mostly mass-and-slip sound.
- **A4 (#49) shallows.** The current wading sound reads as "shag carpet": a broadband noise swish. Real splashing water is made from many small bubble resonances: each bubble is a decaying sine at f = 3.26 / r Hz (r in metres: a 1 mm bubble rings near 3.3 kHz, a 3 mm bubble near 1.1 kHz), with a rising pitch glide of about 10 to 20% over its life. So synthesise wading as a stream of such bubble events (random radii 0.5 to 4 mm, 5 to 30 ms, a handful per footfall rising with speed), a low 100 to 400 Hz splash body for each step, and for a continuous wash a sparse stream of the same bubbles instead of filtered noise. Keep it quiet. Absolute check: spectral energy peak band between 800 and 4000 Hz with no more than 10 dB of noise floor above 6 kHz, and a clear temporal structure (assert a crest factor above 4).

## P1: the note pages (#43, #51)

- **#43.** The F02 P0 fix (T66.0) made the pages easy to find (lectern, glow, light thread, motes, chime, banner). The user now says that is **too deliberate**: pages should be dropped pages that a player can overlook and struggle for a while without, and the design intent is "pay attention to details". So: remove the lecterns, glow, light thread, motes, cue chime and banner as pickup aids. Return to physically placed dropped pages (a few sheets resting at an angle on the ground, a step, a ledge or a sill, partly weighted by a stone or caught in grass, in the place the story says they fell). Keep the page readable when close and keep the `--list-pages` tool and the real-click bot, which must still collect all eight in a fresh game. Findability should now come from level design only: the pages sit on routes that the puzzles already lead players along, within a couple of metres of a landmark, and off the main sight line at most 50% of the time. The `J` unread marker should only appear after a page has been picked up. A very faint clue is acceptable (a loose sheet moves slightly in the wind gust, the sound of paper), but nothing that outlines the page.
  *This reverses part of F02 P0. The user's wording ("resume the dropped pages approach") is explicit, so this is accepted, but note the earlier history: pages 1 and 4 to 8 were not found in the first playtests, and the user has now collected all eight by the end, so the balance is theirs to judge in the next playtest.*
- **#51.** The Glass Wood page pedestal (screenshot `20261026-072941.png`) is set into the plinth, not on it: its base is below the plinth top (the white inlaid ring runs through the pedestal). Check every page stand in both worlds for the same fault: rest the base exactly on the supporting surface with a thin contact lip, no interpenetration. Add a selftest that for each page stand and plinth the stand's lowest vertex is within 5 mm above the plinth top. (If #43 removes the pedestals, this applies to any piece that remains, and the altar's own plinth.)

## Out of scope for this round

Story ending, the fork (S02), new worlds. Do not start Phase 1 of S02 until F03 has landed.
