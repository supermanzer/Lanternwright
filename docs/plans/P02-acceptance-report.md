# P02.7 acceptance prep: the no-knowledge bot, route by route (builder B, phase B6, tag `s05-b3`, 2026-11-15)

**What this is.** A scripted player that knows nothing (`SelfTests/NoKnowledge/`: a `Perception` that gives it only what is on the screen and in the speakers, and a brain that a selftest proves names no puzzle, constant, flag or answer) plays the game from a fresh start at the end of the dock to the drained gallery, on each route, with no teleport. The tables between the markers below are generated from that run; this part is the builder's reading. **Nothing was heard or seen by a person**: a sound is an identity to the bot, a lit thing a number.

## Headline

| | Ilse | Oren |
|---|---|---|
| reaches the drained gallery from a fresh game | yes, 145 min of play, 413 manipulations | yes, 103 min of play, 381 manipulations |
| puzzles solved **blind** (feedback only, no text, no diagram, no rhythm) | stones, chime pool, altar, door plates, tide marks, catalogue, bell pipes (7 of 8) | stones, chime pool, altar, door plates, tide marks, orrery (6 of 9) |
| puzzles that needed the **knowing helper** | the mirror court (and the stair, a bot limit) | the mirror court, Oren's lens ring (up the stair), the prism ring |
| stall points | 18 | 11 |

**Reading the numbers.** A "blind" solve means the game's feedback alone was enough for a patient program that tries things: it does **not** mean a person would find the puzzle easy, and it does not measure clue quality (a person has the page and the diagram, the bot has neither). A "helped" puzzle means this bot, with these hands, did not get there in a bounded effort (400 s per visit at a dial, three tries); it is **bot-limited evidence**: it says where a feedback-only player *of this kind* is stuck, not that the puzzle is broken. The run is sensitive: a small change (the plate glow gate, the dial's walk back) moved the orrery from helped to blind and a pipe from solved to missed during this phase. `SelfTestNoKnowledge` pins the lists; read a change in them as "the bot's luck moved", then check why.

## What the bot found (each is a Q; defaults taken, nothing changed except the two cheap fixes below)

Each finding is marked **game** (a property of the game the run shows), **bot** (an artefact of how this bot plays, noted so nobody reads it as a defect) or **both**.

1. **Every ordering puzzle is solvable by trial** (stones 18 presses, chime pool 16, plates 23 over four visits, catalogue 29: 3 to 5 things in a row). A wrong press names exactly the part that held, at no cost beyond 0.8 s, so the clue is a shortcut, not a requirement. *Game.* Q100.
2. **The door plates answer before they can open the door.** Struck blind at the lighthouse before the altar, the plates ring true, bloom, show the gate's cue and reset; the bot solved them a second time after the return and the door opened. As of this phase's review fix the plates' new glow is **not** shown before they would be answered (so an early solve gives no sight of being right either). *Game.* Q101.
3. **The mirror court did not settle under a coordinate ascent** (184 clicks, two passes). *Bot-limited:* the ascent moves one dial at a time and trusts glow near the court, so on a flat stretch it cannot tell a move that helps from one that does not; B2's greedy solver, which *knows* the beam, needs 6 clicks from the start (graph report G8). Whether the cause is the plateau (a hypothesis: the receivers light only when the whole beam reaches them) was **not measured**. Q102.
4. **Dormant machines answer with nothing.** On Ilse's route the orrery's collar clicks (47 and 47 presses) and does nothing; on Oren's the bays, the sluice gates' wheels and the bell pipes take presses and answer nothing. S05 section 4: the other site is "a visible problem it cannot yet reach". *Game.* Q103.
5. **The orrery** was solved blind on this run (two visits, 67 presses in 6 min, "watch and press as it brightens") and helped on an earlier build of the bot: the notch has to be right at the moment, so for a player without the beam rhythm it is luck over a few tides. *Both.* Q104.
6. **The prism ring was not solved blind** even with the arrow keys now used (25 presses in 8 min, helped): it needs the dome's windows lit and each gate's tide, and nothing in the glow near the ring says which of three dark ghosts to turn to. *Both* (a longer wait or a smarter bot might). Q105, with Q70.
7. **Stones before the quay** ring and answer nothing (F09.8's design); the bot spent its first 14 min mostly on that and walking. *Game, by design.* Q106.
8. **The spiral stair is on no trail**: the bot (and the whole-game bots) must be helped up it. *Bot:* a person walks up. Q107.
9. **Time.** A feedback-only player needed 103 to 145 minutes of play. The tables give when each puzzle was *recorded* solved; the largest blocks are the walk round the island before the first lens (34 min to the first lens touch: the bot visits every trail point before it leaves a place) and the tide waits at the pipes (390 to 680 s of holding). *Both.* Q108.

## The two fixes made in this phase (cheap G7 breaks that were mine)

- **`door-plates` (sight was binary):** once the plates would be answered (back from the Glass Wood with the gate ready: the same condition as their glint), each right strike held makes the whole set glow a step brighter and a wrong one drops it back (`Game.plateHeldStep` = 0.08, on the one `tone_plates` mesh). Struck earlier they only ring (a review fix: the early glow contradicted Q101; `SelfTestPlateGlow` checks it). Frames `shots/b6/plates-none.png`, `plates-platesheld1.png`, `plates-platesheld.png` (`--view lh-plates3 --state platesheld`), looked at: the black glyphs wash to grey and the faces lighten, step by step. One mesh, so the glow is the set's, not each plate's (A could split it: Q109).
- **`archive-marks` (sight was binary):** A's gauge (Q97) glows a bar as the water crosses it; B now holds a counted mark lit (`TideMarks.set` from `IlseRoute.updateVisuals`, both routes, again after a load). The graph's feedback line for A0 says so. (A's pulse marks a crossing and B's hold marks "counted": "how close" is thin, and the G7 break is cleared by the declared line plus the `plateglow` mark test.)

The graph report is regenerated: 17 rule breaks (was 19). The seventeen left are logged, with who owns each, in `docs/OPEN-QUESTIONS.md` Q109 and Q110.

<!-- nokbot:begin -->
### Generated by `NOKBOT_REPORT=docs/plans/P02-acceptance-report.md .build/release/Lanternwright --selftest nokbot` (regenerate after any change to a puzzle; the text outside the markers is the builder's)

## What the bot is, and is not
A scripted player that holds only a **`Perception`** (`SelfTests/NoKnowledge/Perception.swift`) and never the game: what is in sight (a thing, the words the crosshair shows on it, whether the crosshair shows it done, how brightly the place around it glows), the guide light and the lamps, the trails (where the lanterns' path goes), what it hears (each sound reduced to a tone by identity, a sour note, a held tone, a full chord, a rumble), and its hands (walk, face, click, arrow keys, wait). `SelfTests/NoKnowledge/BlindPlayer.swift` is the brain; a selftest reads its text and fails if it names any puzzle, layout constant, flag or answer (`nokbot: the brain's file names no puzzle ...`).

It plays from a **fresh game at the spawn** at the end of the dock, with no teleport, through Varrow, the Glass Wood, the return, the lighthouse and the Archive, until the gallery drains (`routeSolved`). It works what it finds with three generic hands:
- **a row** of presses (strike, ring, touch): try each, keep what rings true and stays lit, learn from a sour note (everything resets, so it replays what held) and rule out what did nothing;
- **a dial** (turn, change): for each element click round its cycle watching how bright the place gets, settle on the brightest, go round again; and for a single dial that nothing answered, watch it and press as it brightens;
- **hold and wait** (the fork at a pipe): press, then wait a tide for the thing to say it is done; and **wait and listen** at the guide light where nothing can be pressed (the tide marks).

It reads **no page text, no diagram and no beam rhythm** (a page is opened and shut). It chooses its sibling at the fork as a player would (one exit's words name Ilse, the other's Oren).

**A step** is one press, click or arrow press (a manipulation); a walk or a wait is not. **A stall** is a stretch of 150 s of play in which nothing new comes into sight, nothing new sounds and nothing new lights, or a machine worked for a while with no answer, or a machine in sight that no trail leads to. At a stall the harness may **help**: the same knowing walk the whole-game bots use, run from wherever the bot stood, and counted below ("helped"). A puzzle marked *helped* was **not** solved blind; the helps are the findings.

**Not modelled:** a player's patience (the bot never gives up on its own account), a player's eyes (a thing is "in sight" if it is within 250 m and in front or within 5 m: nothing hides it), the page text (the bot cannot read, so every puzzle that is solved here is solved without text, and a puzzle that is helped may have a page that would help a person), and sound as a person hears it (a tone is an identity and a sour note is a sour note).

## Ilse's route: the gallery drains after 145 min of play, 413 manipulations, 18 stalls, 5 helps

| # | puzzle | verb / channel | designer's least | blind presses | blind time at it | solved at | how |
|---|---|---|---|---|---|---|---|
| 1 | stones | strike / hear | 3 | 18 | 487 s | 17 min | blind, by trial and the feedback |
| 2 | mirror-court | turn+change / aim | 6 | 184 | 543 s | 44 min | **helped** (the bot stalled: went round 2 time(s), 184 clicks; the light never settled) |
| 3 | chime-pool | strike / hear | 3 | 16 | 55 s | 46 min | blind, by trial and the feedback |
| 4 | altar | touch / touch | 2 | 2 | 1 s | 49 min | blind, by trial and the feedback |
| 5 | door-plates | strike / watch | 3 | 23 | 57 s | 61 min | blind, by trial and the feedback |
| 6 | archive-marks | count / count | 3 | 0 | 0 s | 88 min | by waiting and listening |
| 7 | archive-catalogue | ring / see | 3 | 29 | 126 s | 106 min | blind, by trial and the feedback |
| 8 | archive-pipes | hold fork / hear | 3 | 5 | 677 s | 145 min | blind, by trial and the feedback |

**Helps** (what the knowing helper did, and when):

- 44 min: sets the mirrors and panes of the court (solution known)
- 69 min: climbs the spiral stair (on no trail)
- 72 min: climbs the spiral stair (on no trail)
- 76 min: climbs the spiral stair (on no trail)
- 82 min: climbs the spiral stair (on no trail)

**Stall points** (each is 150 s with nothing new, or a machine worked without an answer; `at` is where the bot stood):

| at (min) | where | what it was at | why |
|---|---|---|---|
| 8 | (-26, -43) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 8 | (-27, -42) | plate_tide, plate_wind, plate_stone | the whole row rang true and nothing said it was done |
| 14 | (-26, -44) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 44 | (-78, 15) | gw_mirror_0, gw_pane_1, gw_pane_0, ... | went round 2 time(s), 184 clicks; the light never settled |
| 69 | (-28, -52) | lh_lens_touch | in sight 26 m overhead; no trail leads up to it |
| 72 | (-31, -52) | (nothing in sight) | nothing in sight to press, nowhere new to walk |
| 76 | (-28, -52) | lh_lens_touch | in sight 26 m overhead; no trail leads up to it |
| 82 | (170, 198) | (nothing in sight) | nothing in sight to press, nowhere new to walk |
| 91 | (75, 110) | ti_sluice_2, ti_sluice_0, ti_sluice_1 | the whole row rang true and nothing said it was done |
| 98 | (0, 124) | ti_pipe_2, ti_pipe_0, ti_pipe_1 | no progress working 3 hold machine(s) |
| 103 | (-11, 123) | ti_pipe_2, ti_pipe_0, ti_pipe_1 | no progress working 3 hold machine(s) |
| 106 | (-64, 27) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 107 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 110 | (4, 117) | ti_sluice_0, ti_sluice_2, ti_sluice_1 | the whole row rang true and nothing said it was done |
| 118 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 121 | (48, -37) | ti_tableau_light_oren | no progress working 1 press machine(s) |
| 131 | (4, -89) | ti_orrery_collar | went round 1 time(s), 47 clicks; the light never settled |
| 139 | (4, -89) | ti_orrery_collar | went round 1 time(s), 47 clicks; the light never settled |

**Every machine worked, in order** (a record is one visit; a row of presses is one record):

| at (s) | what the player read | how | presses | time (s) | outcome |
|---|---|---|---|---|---|
| 40 | Touch the stone (2) | press | 2 | 52 | stalled: the whole row rang true and nothing said it was done |
| 94 | Touch the stone (3) | press | 3 | 114 | stalled: the whole row rang true and nothing said it was done |
| 308 | Touch the stone (1) | press | 1 | 4 | stalled: the whole row rang true and nothing said it was done |
| 313 | Touch the stone (3) | press | 3 | 72 | stalled: the whole row rang true and nothing said it was done |
| 488 | Touch the plate (3) | press | 5 | 9 | stalled: the whole row rang true and nothing said it was done |
| 501 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 502 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 503 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 504 | Touch the plate (3) | press | 8 | 17 | stalled: the whole row rang true and nothing said it was done |
| 534 | Touch the stone (3) | press | 3 | 75 | stalled: the whole row rang true and nothing said it was done |
| 779 | The quay is not raised (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 780 | The quay is not raised (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 875 | Touch the plate (3) | press | 5 | 14 | stalled: the whole row rang true and nothing said it was done |
| 891 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 905 | Touch the stone (3) | press | 6 | 167 | solved by trial |
| 2052 | Touch the lens (1) | press | 1 | 0 | pressed once |
| 2117 | Turn the mirror (6) | dial | 184 | 543 | stalled (helped): went round 2 time(s), 184 clicks; the light never settled |
| 2762 | Strike the glass (5) | press | 16 | 55 | solved by trial |
| 2953 | Touch Ilse's light (1) | press | 1 | 0 | pressed once |
| 2957 | Touch Oren's light (1) | press | 1 | 0 | pressed once |
| 3521 | Return through the lens (1) | press | 1 | 0 | pressed once |
| 3655 | Touch the plate (3) | press | 5 | 14 | solved by trial |
| 4199 | Ilse’s way: touch the lens (1) | press | 0 | 24 | stalled: in sight 26 m overhead; no trail leads up to it |
| 4563 | Ilse’s way: touch the lens (1) | press | 0 | 24 | stalled: in sight 26 m overhead; no trail leads up to it |
| 5142 | Ilse’s way: touch the lens (1) | press | 1 | 0 | pressed once |
| 5193 | Touch the gate (3) | press | 3 | 101 | stalled: every press was ruled out at position 3 |
| 5320 | Touch the gate (3) | press | 4 | 197 | stalled: the whole row rang true and nothing said it was done |
| 5586 | Hold the fork to the pipe (3) | hold | 1 | 302 | stalled: held 300 s, nothing answered |
| 5890 | Hold the fork to the pipe (3) | hold | 1 | 302 | stalled: held 300 s, nothing answered |
| 6275 | Ring the bell (5) | press | 19 | 86 | stalled: the whole row rang true and nothing said it was done |
| 6384 | Take the rod (1) | press | 1 | 11 | pressed once |
| 6405 | Ring the bell (5) | press | 5 | 18 | stalled: the whole row rang true and nothing said it was done |
| 6484 | Touch the gate (3) | press | 4 | 170 | stalled: the whole row rang true and nothing said it was done |
| 6686 | Hold the fork to the pipe (3) | hold | 1 | 6 | waited for |
| 6808 | Light the lantern (1) | press | 1 | 0 | pressed once |
| 6917 | Hold the fork to the pipe (2) | hold | 1 | 33 | waited for |
| 6953 | Touch the gate (3) | press | 3 | 89 | stalled: the whole row rang true and nothing said it was done |
| 7107 | Ring the bell (5) | press | 5 | 21 | stalled: the whole row rang true and nothing said it was done |
| 7236 | Light the lantern (1) | press | 1 | 59 | stalled: every press was ruled out at position 1 |
| 7350 | Light the lantern (1) | press | 1 | 59 | stalled: every press was ruled out at position 1 |
| 7473 | Turn the collar (1) | dial | 47 | 439 | stalled: went round 1 time(s), 47 clicks; the light never settled |
| 7913 | Turn the collar (1) | dial | 47 | 439 | stalled: went round 1 time(s), 47 clicks; the light never settled |
| 8381 | The ring is empty (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 8572 | Hold the fork to the pipe (1) | hold | 1 | 32 | waited for |
| 8607 | Touch the gate (3) | press | 3 | 107 | stalled: every press was ruled out at position 3 |

## Oren's route: the gallery drains after 103 min of play, 381 manipulations, 11 stalls, 4 helps

| # | puzzle | verb / channel | designer's least | blind presses | blind time at it | solved at | how |
|---|---|---|---|---|---|---|---|
| 1 | stones | strike / hear | 3 | 18 | 487 s | 17 min | blind, by trial and the feedback |
| 2 | mirror-court | turn+change / aim | 6 | 184 | 543 s | 44 min | **helped** (the bot stalled: went round 2 time(s), 184 clicks; the light never settled) |
| 3 | chime-pool | strike / hear | 3 | 16 | 55 s | 46 min | blind, by trial and the feedback |
| 4 | altar | touch / touch | 2 | 2 | 1 s | 49 min | blind, by trial and the feedback |
| 5 | door-plates | strike / watch | 3 | 23 | 57 s | 61 min | blind, by trial and the feedback |
| 6 | lens-ring | turn / aim | 3 | 0 | 42 s | 62 min | **helped** (the bot stalled: in sight 24 m overhead; no trail leads up to it) |
| 7 | archive-marks | count / count | 3 | 0 | 0 s | 67 min | by waiting and listening |
| 8 | archive-orrery | turn collar / watch | 3 | 67 | 358 s | 93 min | blind, by trial and the feedback |
| 9 | archive-gates-beam | turn / aim | 15 | 25 | 468 s | 103 min | **helped** (the bot stalled: went round 2 time(s), 25 clicks; the light never settled) |

**Helps** (what the knowing helper did, and when):

- 44 min: sets the mirrors and panes of the court (solution known)
- 62 min: climbs the spiral stair (on no trail)
- 62 min: turns Oren's lens ring onto its receiver
- 102 min: turns the prism ring onto each gate's mark (marks and tides known)

**Stall points** (each is 150 s with nothing new, or a machine worked without an answer; `at` is where the bot stood):

| at (min) | where | what it was at | why |
|---|---|---|---|
| 8 | (-26, -43) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 8 | (-27, -42) | plate_tide, plate_wind, plate_stone | the whole row rang true and nothing said it was done |
| 14 | (-26, -44) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 44 | (-78, 15) | gw_mirror_0, gw_pane_1, gw_pane_0, ... | went round 2 time(s), 184 clicks; the light never settled |
| 62 | (-29, -43) | lens_ring | in sight 24 m overhead; no trail leads up to it |
| 74 | (73, 116) | ti_pipe_1, ti_pipe_2, ti_pipe_0 | no progress working 3 hold machine(s) |
| 79 | (64, 116) | ti_pipe_1, ti_pipe_2, ti_pipe_0 | no progress working 3 hold machine(s) |
| 81 | (-64, 33) | ti_bay_2, ti_bay_1, ti_bay_3, ... | every press was ruled out at position 1 |
| 81 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | every press was ruled out at position 1 |
| 84 | (48, -37) | ti_tableau_light_oren | no progress working 1 press machine(s) |
| 102 | (0, -130) | ti_prism_ring | went round 2 time(s), 25 clicks; the light never settled |

**Every machine worked, in order** (a record is one visit; a row of presses is one record):

| at (s) | what the player read | how | presses | time (s) | outcome |
|---|---|---|---|---|---|
| 40 | Touch the stone (2) | press | 2 | 52 | stalled: the whole row rang true and nothing said it was done |
| 94 | Touch the stone (3) | press | 3 | 114 | stalled: the whole row rang true and nothing said it was done |
| 308 | Touch the stone (1) | press | 1 | 4 | stalled: the whole row rang true and nothing said it was done |
| 313 | Touch the stone (3) | press | 3 | 72 | stalled: the whole row rang true and nothing said it was done |
| 488 | Touch the plate (3) | press | 5 | 9 | stalled: the whole row rang true and nothing said it was done |
| 501 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 502 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 503 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 504 | Touch the plate (3) | press | 8 | 17 | stalled: the whole row rang true and nothing said it was done |
| 534 | Touch the stone (3) | press | 3 | 75 | stalled: the whole row rang true and nothing said it was done |
| 779 | The quay is not raised (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 780 | The quay is not raised (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 875 | Touch the plate (3) | press | 5 | 14 | stalled: the whole row rang true and nothing said it was done |
| 891 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 905 | Touch the stone (3) | press | 6 | 167 | solved by trial |
| 2052 | Touch the lens (1) | press | 1 | 0 | pressed once |
| 2117 | Turn the mirror (6) | dial | 184 | 543 | stalled (helped): went round 2 time(s), 184 clicks; the light never settled |
| 2762 | Strike the glass (5) | press | 16 | 55 | solved by trial |
| 2953 | Touch Ilse's light (1) | press | 1 | 0 | pressed once |
| 2957 | Touch Oren's light (1) | press | 1 | 0 | pressed once |
| 3521 | Return through the lens (1) | press | 1 | 0 | pressed once |
| 3655 | Touch the plate (3) | press | 5 | 14 | solved by trial |
| 3737 | Oren’s way: turn the ring  ‹ › (1) | dial | 0 | 42 | stalled (helped): in sight 24 m overhead; no trail leads up to it |
| 3802 | Oren’s way: step into the light (1) | press | 1 | 0 | pressed once |
| 3948 | Touch the gate (3) | press | 3 | 112 | stalled: every press was ruled out at position 3 |
| 4067 | Touch the gate (3) | press | 3 | 99 | stalled: the whole row rang true and nothing said it was done |
| 4187 | Hold the fork to the pipe (3) | hold | 1 | 306 | stalled: held 300 s, nothing answered |
| 4495 | Hold the fork to the pipe (3) | hold | 1 | 302 | stalled: held 300 s, nothing answered |
| 4861 | Take the fork (1) | press | 1 | 7 | pressed once |
| 4882 | Ring the bell (5) | press | 5 | 19 | stalled: every press was ruled out at position 1 |
| 4901 | Ring the bell (5) | press | 5 | 15 | stalled: every press was ruled out at position 1 |
| 5020 | Light the lantern (1) | press | 1 | 59 | stalled: pressed, nothing answered |
| 5149 | Light the lantern (1) | press | 1 | 55 | stalled: pressed, nothing answered |
| 5267 | Turn the collar (1) | dial | 39 | 216 | solved by trial: watched and pressed as it brightened: 14 presses in 141 s |
| 5497 | Turn the collar (1) | dial | 28 | 142 | solved by trial: watched and pressed as it brightened: 16 presses in 102 s |
| 5668 | Turn the ring  ‹ › (1) | dial | 25 | 468 | stalled (helped): went round 2 time(s), 25 clicks; the light never settled |

<!-- nokbot:end -->

## Method notes (for whoever reads the tables)

**How generous the bot's senses are (it is a fair test of feedback, not of a person's eyes and ears):**
- *Sight:* an interactable is "in sight" within 250 m when it is in front of the camera or within 5 m; walls and distance do not hide it. `glow(near:)` and `lit(near:)` sum the drawn glow of every scene item near a point, through walls and out of frame, with no threshold of what an eye would notice. The guide light is a global position (an always-on compass). The trails are the whole network of the world, not just the lit part near the player.
- *Sound:* every game event is heard, at full strength, with no distance, no mix and no masking. Tones are named by identity, **but** Perception reduces the lens chime to `tone("answer")` and the full chord to `bloom`, and the brain tests for them: those two carry meaning the ear would have to learn.
- *The brain's priors* are a player's: it reads the prompt words ("read", "hold", "turn", "change", "lens", "return", "step into"), waits up to 300 s at a "hold" (a tide), expects a sour note to reset a row, and prefers a floating light's way. A person's priors are similar but not these.
- *Choices the harness makes for it:* which sibling to be at the fork (it is told to avoid the other exit's named words).
- *Helped* means the same knowing walk the whole-game bots use (the court's solution, the stair, the ring's receiver angle, the collar's notches, the prism's marks), run from wherever the bot stood.
- *Solved at* is the clock when the harness first saw the game's flag set **after a record ended**, so it is an upper bound and the order of the rows can be off by a record.

**Hands:** the real `Game.advance` input (walk, aim, click, arrow keys on a prompt with "‹ ›"), the same trails as the whole-game bots; it never teleports. A stall's 150 s, a dial visit's 400 s, three tries and the give-up after three repeated stalls are the bot's patience (`BlindPlayer.swift`).

**Runtime:** `nokbot` plays two runs of 100 to 145 simulated minutes in about 35 s of wall time; it is part of `--selftest` (not a separate gate).

**Brittleness:** the run depends on trails, geometry, hover and feedback, so unrelated changes by A can flip the pinned lists (`pinnedBlindSolved`, `pinnedHelped` in `SelfTestNoKnowledge.swift`); that is intended: look at why, then move the pin on purpose. The forbidden-name check on the brain is a denylist, not a proof (a determined cheat gets past it); the brain holds only a `Perception`.
