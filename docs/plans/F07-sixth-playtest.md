# F07: sixth playtest (notes #69 to #83)

Source: `Lanternwright --feedback` #69-#83 (2026-10-30/31). The user got through the lighthouse, took Ilse's exit, and reached the Glass Wood placeholder: #79 and #83 ("touching the lens ... returns me to the glass trees with no new information"; "touching the lens does nothing ... I do not understand how this starts a player down a path") are the **placeholder problem**, solved by Phase 2 (`S04-phase2-tide-archive.md`), not by patching. #69 is praise ("water rising and falling is much better").
Rules as before: frames from the note's screenshot Read, selftest 0 FAIL, review step, commit by path, tag `f07-a` / `f07-b`, bundle in the integration checkout after the last merge. Do F07 before S04.

## Builder A
| # | Note | Item |
|---|---|---|
| 72 | Door sound "like a snare drum, thin and staccato, no weight of solid wood or stone" (third complaint about this sound) | A-door |
| 70 | The bell/ding on the dock "comes from everywhere"; should be directional from the buoy | A-buoy |
| 71 | Page 2 sits at an odd angle to the ground | A-page2 |
| 74 | Oren's pages appearing after each puzzle feels odd ("folded in the light?") | A-fold |
| 75 | Footsteps too loud relative to other sounds | A-steps |
| 77, 78 | Lighthouse: floor does not extend into the doorway (looks like a hole); floors and wall components do not connect, "only partially built" | A-shell |

- **A-door**: physical model of a heavy oak door (about 5 cm) shifting 1 cm against its stone jamb, with the iron ring: (1) a low thud: modal body 70-140 Hz, decays 120-250 ms; (2) a wood knock 200-500 Hz, decay about 60 ms; (3) a short friction creak as band-limited noise 300-1500 Hz; (4) the iron ring clink 1.5-3 kHz at -18 dB under the thud, decay about 150 ms. Attack 3-8 ms (not an impulse). Selftest metrics: at least 70% of the energy under 500 Hz, spectral centroid under 700 Hz, no tone more than 6 dB over its neighbours above 1 kHz, level 0.8-1.0x a stone run step. Compare against the old file's metrics in the report. The user cannot be asked to audition each guess: be conservative on weight.
- **A-buoy**: the buoy bell is a positional source at the buoy (panned and attenuated by distance and the player's yaw; a slow, slightly inharmonic bell with a decay). Selftest: pan sign follows the bearing.
- **A-page2**: pages lie on the ground following the local slope (normal aligned to terrain, with a small deliberate twist about the vertical axis); check all nine pages' rest poses against the terrain normal in a selftest (angle to the slope normal under 8 degrees unless deliberately propped by a pebble).
- **A-fold**: pages 6, 7 and 8 exist from the start as a pale folded sheet held in the glass of their mechanism (not readable, not collectable, one object each) and unfold (animation of about 2 s, light travelling along the fold) when their puzzle is solved, becoming the readable page. B owns the page state; A owns the visual and a `PageFold` hook. Frames before and after for the three.
- **A-steps**: lower footsteps by about 4 dB overall (keep relative surface differences); one constant.
- **A-shell**: Floor continues through the doorway (threshold slab flush with the interior floor, no gap to the ground-room floor); the interior shell's floors, stair, walls and the exterior shell meet with no visible gaps or open edges (the screenshot of #77 and #78 at the top of the stair: position -31.0, 92.2, -46.8). Audit with a few frames from the door, the stair and the top.

## Builder B
| # | Note | Item |
|---|---|---|
| 73 | "What is the note about running meant to convey? Feels odd here" | B-run |
| 76 | "The lamp is waiting": Ilse's notes should refer to the lamp in the lighthouse | B-lamp |
| 80 | The journal says the pages are not in the right order though the player mapped them correctly word for word | B-contra |
| 81 | Running 25% faster in ground covered | B-pace |
| 82 | A physical barrier (railing) where the player cannot advance in the lens room | B-rail |

- **B-run**: find the line (`hint_run`, position -33.4, 25.6, -158.5). If it exists only as a tutorial hint with no meaning in the world, remove it or reword it as an in-world idea (a keeper's rule: "Keepers do not run on the shingle." only where shingle is). Report what you chose; log in OPEN-QUESTIONS.
- **B-lamp**: add reference to the lamp in the lighthouse to the Ilse pages (a phrase in pages 1, 2 or 4, 9; **pages 3 and 8 stay exactly as they are**; keep the revisions R1-R3 intact; pin in selftest). Draft, then the reviewer reads the texts in a file `docs/plans/F07-page-edits.md` before/after.
- **B-contra**: the notebook must never say the player is wrong. The pages' sides are interpretation; the player mapped the pages "word for word". Accept any assignment that is defensible from the text (list the defensible sets in the data); the verdict is only "Settled" or nothing, and the notebook records the player's own mapping. No penalty, no "disagree" line. Selftest.
- **B-pace**: run speed x1.25 (4.4 -> 5.5 m/s), walk unchanged; check footstep cadence, FOV, the guided corridors' soft limits and the nav audit travel times.
- **B-rail**: a railing around the lens room's open edge (floor opening or window ledge where the soft limit stops the player), as an item with collider; no gap to walk through.
