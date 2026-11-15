# P02.7 acceptance prep: the no-knowledge bot, route by route (builder B, first run B6 `s05-b3`, re-run B7 `s05-b4`, 2026-11-15)

**What this is.** A scripted player that knows nothing (`SelfTests/NoKnowledge/`: a `Perception` that gives it only what is on the screen and in the speakers, and a brain that a selftest proves names no puzzle, constant, flag or answer) plays the game from a fresh start at the end of the dock to the drained gallery, on each route, with no teleport. The tables between the markers below are generated from that run; this part is the builder's reading. **Nothing was heard or seen by a person**: a sound is an identity to the bot, a lit thing a number.

## Headline (B7 re-run, with the first run in brackets)

| | Ilse | Oren |
|---|---|---|
| reaches the drained gallery from a fresh game | yes, 148 min of play (145), 433 manipulations (413) | yes, 99 min of play (103), 384 manipulations (381) |
| puzzles solved **blind** (feedback only, no text, no diagram, no rhythm) | stones, chime pool, altar, door plates, tide marks, catalogue, bell pipes (7 of 8; same) | stones, chime pool, altar, door plates, tide marks, **prism ring** (6 of 9; the orrery was blind in the first run) |
| puzzles that needed the **knowing helper** | the mirror court (and the stair, a bot limit; same) | the mirror court, Oren's lens ring (up the stair), **the orrery** (the prism ring was helped in the first run) |
| stall points | 17 (18) | 12 (11) |

**What B7 changed in these numbers.** The prism ring's step went from 15 to 45 degrees (five clicks, was fifteen: Q118) and the bot now solves it blind in 70 s (it did not in 8 min). The orrery moved the other way: its "watch and press as it brightens" did not catch an arm this time (49 clicks in two tries); that solve is timing luck (Q104, Q119) and it moves with any change to the world's clocks. The plates, stones and court rows moved by seconds only (the plates' early glow and the quay light are for a person; this bot does not follow a guide light while a stone is in sight to press).

**Reading the numbers.** A "blind" solve means the game's feedback alone was enough for a patient program that tries things: it does **not** mean a person would find the puzzle easy, and it does not measure clue quality (a person has the page and the diagram, the bot has neither). A "helped" puzzle means this bot, with these hands, did not get there in a bounded effort (400 s per visit at a dial, three tries); it is **bot-limited evidence**: it says where a feedback-only player *of this kind* is stuck, not that the puzzle is broken. The run is sensitive: a small change (the plate glow gate, the dial's walk back) moved the orrery from helped to blind and a pipe from solved to missed during this phase. `SelfTestNoKnowledge` pins the lists; read a change in them as "the bot's luck moved", then check why.

## What the bot found (each is a Q; defaults taken, nothing changed except the two cheap fixes below)

Each finding is marked **game** (a property of the game the run shows), **bot** (an artefact of how this bot plays, noted so nobody reads it as a defect) or **both**.

1. **Every ordering puzzle is solvable by trial** (stones 18 presses, chime pool 16, plates 23 over four visits, catalogue 29: 3 to 5 things in a row). A wrong press names exactly the part that held, at no cost beyond 0.8 s, so the clue is a shortcut, not a requirement. *Game.* Q100.
2. **The door plates answer before they can open the door.** Struck blind at the lighthouse before the altar, the plates ring true, bloom, show the gate's cue and reset; the bot solved them a second time after the return and the door opened. Since B7 the plates' held-strike glow **is** shown before they would be answered (a step per right strike, no glint, the door does not open), so an early solver sees they were right (Q112). *Game, fixed.*
3. **The mirror court did not settle under the bot's ascent** (207 clicks this run, 184 before) and **B7 measured why: the plateau was not real.** The bot sums every glow within 22 m of the dials (about 37.5, flickering by 0.3 to 0.7), so it climbed the flicker; a climb that watches only the three crystals solves the court from all 41 starts tried (median 49 clicks, 45 from the court's own start), with or without the new faint 'nearly' glow (38 from the start with it). *Bot-limited.* Q102 and Q117.
4. **Dormant machines answered with nothing.** On Ilse's route the orrery's collar clicked (47 and 47 presses) and did nothing; on Oren's the bays, the sluice gates' wheels and the bell pipes took presses and answered nothing. B7 fires `GameEvent.dormant` for each (Q115); it is **silent until A's voice is mapped**, so the bot's run (which hears `.dull` as nothing new) is unchanged. *Game, half fixed.*
5. **The orrery** was solved blind in the first run (67 presses in 6 min) and **helped in this one** (49 clicks, two tries): the notch has to be right at the moment, so for a player without the beam rhythm it is luck over a few tides. B7 exposes the notch that has an arm (`GameEvent.collar(armHere:)`) so A can click louder on it (Q116). *Both.* Q104.
6. **The prism ring** was not solved blind in the first run (25 presses in 8 min, helped, fifteen clicks designed) and **is now** (25 presses in 70 s, five clicks designed: the step is 45 degrees, Q118). *Game, fixed.* Q105, Q70.
7. **Stones before the quay** rang and answered nothing (F09.8's design); the bot spent its first 14 min mostly on that and walking. Since B7 a stone struck early lights a guide light toward the quay (Q113); this bot works every site in sight before it follows a light, so its time (17 min) did not change. *Game, fixed for a person; bot-limited evidence.*
8. **The spiral stair is on no trail**: the bot (and the whole-game bots) must be helped up it. *Bot:* a person walks up. Q107.
9. **Time.** A feedback-only player needed 103 to 145 minutes of play. The tables give when each puzzle was *recorded* solved; the largest blocks are the walk round the island before the first lens (34 min to the first lens touch: the bot visits every trail point before it leaves a place) and the tide waits at the pipes (390 to 680 s of holding). *Both.* Q108.

## The two fixes made in B6 (cheap G7 breaks that were mine)

- **`door-plates` (sight was binary):** once the plates would be answered (back from the Glass Wood with the gate ready: the same condition as their glint), each right strike held makes the whole set glow a step brighter and a wrong one drops it back (`Game.plateHeldStep` = 0.08, on the one `tone_plates` mesh). Struck earlier they only rang in B6; **B7 (Q112) shows the held glow before the altar too** (the quiet glint stays gated; `SelfTestPlateGlow` checks both). Frames `shots/b6/plates-none.png`, `plates-platesheld1.png`, `plates-platesheld.png` (`--view lh-plates3 --state platesheld`), looked at: the black glyphs wash to grey and the faces lighten, step by step. One mesh, so the glow is the set's, not each plate's (A could split it: Q109).
- **`archive-marks` (sight was binary):** A's gauge (Q97) glows a bar as the water crosses it; B now holds a counted mark lit (`TideMarks.set` from `IlseRoute.updateVisuals`, both routes, again after a load). The graph's feedback line for A0 says so. (A's pulse marks a crossing and B's hold marks "counted": "how close" is thin, and the G7 break is cleared by the declared line plus the `plateglow` mark test.)

The graph report is regenerated: 14 rule breaks (was 19 at B6's start, 17 at its end; B7's G6 exemption removed two and the 45-degree ring step removed one: Q114, Q118). The fourteen left are logged, with who owns each, in `docs/OPEN-QUESTIONS.md` Q109, Q110 and Q114.

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

## Ilse's route: the gallery drains after 148 min of play, 433 manipulations, 17 stalls, 5 helps

| # | puzzle | verb / channel | designer's least | blind presses | blind time at it | solved at | how |
|---|---|---|---|---|---|---|---|
| 1 | stones | strike / hear | 3 | 18 | 487 s | 17 min | blind, by trial and the feedback |
| 2 | mirror-court | turn+change / aim | 6 | 207 | 596 s | 45 min | **helped** (the bot stalled: went round 2 time(s), 207 clicks; the light never settled) |
| 3 | chime-pool | strike / hear | 3 | 16 | 55 s | 47 min | blind, by trial and the feedback |
| 4 | altar | touch / touch | 2 | 2 | 1 s | 50 min | blind, by trial and the feedback |
| 5 | door-plates | strike / watch | 3 | 22 | 57 s | 61 min | blind, by trial and the feedback |
| 6 | archive-marks | count / count | 3 | 0 | 0 s | 88 min | by waiting and listening |
| 7 | archive-catalogue | ring / see | 3 | 29 | 126 s | 108 min | blind, by trial and the feedback |
| 8 | archive-pipes | hold fork / hear | 3 | 5 | 716 s | 148 min | blind, by trial and the feedback |

**Helps** (what the knowing helper did, and when):

- 45 min: sets the mirrors and panes of the court (solution known)
- 70 min: climbs the spiral stair (on no trail)
- 73 min: climbs the spiral stair (on no trail)
- 76 min: climbs the spiral stair (on no trail)
- 83 min: climbs the spiral stair (on no trail)

**Stall points** (each is 150 s with nothing new, or a machine worked without an answer; `at` is where the bot stood):

| at (min) | where | what it was at | why |
|---|---|---|---|
| 8 | (-28, -42) | plate_tide, plate_wind, plate_stone | the whole row rang true and nothing said it was done |
| 8 | (-28, -42) | plate_tide, plate_wind, plate_stone | the whole row rang true and nothing said it was done |
| 14 | (-26, -44) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 45 | (-78, 15) | gw_mirror_0, gw_pane_1, gw_pane_0, ... | went round 2 time(s), 207 clicks; the light never settled |
| 70 | (-28, -52) | lh_lens_touch | in sight 26 m overhead; no trail leads up to it |
| 73 | (-31, -52) | (nothing in sight) | nothing in sight to press, nowhere new to walk |
| 76 | (-28, -52) | lh_lens_touch | in sight 26 m overhead; no trail leads up to it |
| 83 | (170, 198) | (nothing in sight) | nothing in sight to press, nowhere new to walk |
| 93 | (73, 109) | ti_sluice_2, ti_sluice_0, ti_sluice_1 | the whole row rang true and nothing said it was done |
| 99 | (0, 126) | ti_pipe_2, ti_pipe_0, ti_pipe_1 | no progress working 3 hold machine(s) |
| 105 | (-11, 122) | ti_pipe_2, ti_pipe_0, ti_pipe_1 | no progress working 3 hold machine(s) |
| 108 | (-64, 27) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 109 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 121 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 124 | (48, -37) | ti_tableau_light_oren | no progress working 1 press machine(s) |
| 134 | (4, -89) | ti_orrery_collar | went round 1 time(s), 47 clicks; the light never settled |
| 142 | (4, -89) | ti_orrery_collar | went round 1 time(s), 47 clicks; the light never settled |

**Every machine worked, in order** (a record is one visit; a row of presses is one record):

| at (s) | what the player read | how | presses | time (s) | outcome |
|---|---|---|---|---|---|
| 40 | Touch the stone (2) | press | 2 | 52 | stalled: the whole row rang true and nothing said it was done |
| 94 | Touch the stone (3) | press | 3 | 114 | stalled: the whole row rang true and nothing said it was done |
| 308 | Touch the stone (1) | press | 1 | 4 | stalled: the whole row rang true and nothing said it was done |
| 313 | Touch the stone (3) | press | 3 | 72 | stalled: the whole row rang true and nothing said it was done |
| 488 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 492 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 493 | Touch the plate (3) | press | 6 | 13 | stalled: the whole row rang true and nothing said it was done |
| 507 | Touch the plate (3) | press | 6 | 13 | stalled: the whole row rang true and nothing said it was done |
| 533 | Touch the stone (3) | press | 3 | 75 | stalled: the whole row rang true and nothing said it was done |
| 778 | The quay is not raised (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 779 | The quay is not raised (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 874 | Touch the plate (3) | press | 5 | 14 | stalled: the whole row rang true and nothing said it was done |
| 890 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 904 | Touch the stone (3) | press | 6 | 167 | solved by trial |
| 2052 | Touch the lens (1) | press | 1 | 0 | pressed once |
| 2116 | Turn the mirror (6) | dial | 207 | 596 | stalled (helped): went round 2 time(s), 207 clicks; the light never settled |
| 2808 | Strike the glass (5) | press | 16 | 55 | solved by trial |
| 3000 | Touch Ilse's light (1) | press | 1 | 0 | pressed once |
| 3003 | Touch Oren's light (1) | press | 1 | 0 | pressed once |
| 3567 | Return through the lens (1) | press | 1 | 0 | pressed once |
| 3701 | Touch the plate (3) | press | 5 | 14 | solved by trial |
| 4245 | Ilse’s way: touch the lens (1) | press | 0 | 24 | stalled: in sight 26 m overhead; no trail leads up to it |
| 4609 | Ilse’s way: touch the lens (1) | press | 0 | 24 | stalled: in sight 26 m overhead; no trail leads up to it |
| 5188 | Ilse’s way: touch the lens (1) | press | 1 | 0 | pressed once |
| 5239 | Touch the gate (3) | press | 3 | 100 | stalled: the whole row rang true and nothing said it was done |
| 5406 | Touch the gate (3) | press | 4 | 198 | stalled: the whole row rang true and nothing said it was done |
| 5660 | Hold the fork to the pipe (3) | hold | 1 | 302 | stalled: held 300 s, nothing answered |
| 6021 | Hold the fork to the pipe (3) | hold | 1 | 302 | stalled: held 300 s, nothing answered |
| 6407 | Ring the bell (5) | press | 19 | 86 | stalled: the whole row rang true and nothing said it was done |
| 6516 | Take the rod (1) | press | 1 | 11 | pressed once |
| 6537 | Ring the bell (5) | press | 5 | 18 | stalled: the whole row rang true and nothing said it was done |
| 6623 | Touch the gate (3) | press | 3 | 117 | stalled: the whole row rang true and nothing said it was done |
| 6822 | Hold the fork to the pipe (3) | hold | 1 | 49 | waited for |
| 6986 | Light the lantern (1) | press | 1 | 0 | pressed once |
| 7095 | Hold the fork to the pipe (2) | hold | 1 | 33 | waited for |
| 7131 | Touch the gate (3) | press | 3 | 92 | stalled: the whole row rang true and nothing said it was done |
| 7288 | Ring the bell (5) | press | 5 | 21 | stalled: the whole row rang true and nothing said it was done |
| 7417 | Light the lantern (1) | press | 1 | 59 | stalled: every press was ruled out at position 1 |
| 7531 | Light the lantern (1) | press | 1 | 59 | stalled: every press was ruled out at position 1 |
| 7654 | Turn the collar (1) | dial | 47 | 439 | stalled: went round 1 time(s), 47 clicks; the light never settled |
| 8094 | Turn the collar (1) | dial | 47 | 439 | stalled: went round 1 time(s), 47 clicks; the light never settled |
| 8562 | The ring is empty (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 8745 | Hold the fork to the pipe (1) | hold | 1 | 29 | waited for |
| 8777 | Touch the gate (3) | press | 3 | 107 | stalled: every press was ruled out at position 3 |

## Oren's route: the gallery drains after 99 min of play, 384 manipulations, 12 stalls, 4 helps

| # | puzzle | verb / channel | designer's least | blind presses | blind time at it | solved at | how |
|---|---|---|---|---|---|---|---|
| 1 | stones | strike / hear | 3 | 18 | 487 s | 17 min | blind, by trial and the feedback |
| 2 | mirror-court | turn+change / aim | 6 | 207 | 596 s | 45 min | **helped** (the bot stalled: went round 2 time(s), 207 clicks; the light never settled) |
| 3 | chime-pool | strike / hear | 3 | 16 | 55 s | 47 min | blind, by trial and the feedback |
| 4 | altar | touch / touch | 2 | 2 | 1 s | 50 min | blind, by trial and the feedback |
| 5 | door-plates | strike / watch | 3 | 22 | 57 s | 61 min | blind, by trial and the feedback |
| 6 | lens-ring | turn / aim | 3 | 0 | 42 s | 63 min | **helped** (the bot stalled: in sight 24 m overhead; no trail leads up to it) |
| 7 | archive-marks | count / count | 3 | 0 | 0 s | 69 min | by waiting and listening |
| 8 | archive-orrery | turn collar / watch | 3 | 49 | 483 s | 97 min | **helped** (the bot stalled: went round 2 time(s), 49 clicks; the light never settled) |
| 9 | archive-gates-beam | turn / aim | 5 | 25 | 70 s | 99 min | blind, by trial and the feedback |

**Helps** (what the knowing helper did, and when):

- 45 min: sets the mirrors and panes of the court (solution known)
- 63 min: climbs the spiral stair (on no trail)
- 63 min: turns Oren's lens ring onto its receiver
- 97 min: catches the three orrery arms (notch and moment known)

**Stall points** (each is 150 s with nothing new, or a machine worked without an answer; `at` is where the bot stood):

| at (min) | where | what it was at | why |
|---|---|---|---|
| 8 | (-28, -42) | plate_tide, plate_wind, plate_stone | the whole row rang true and nothing said it was done |
| 8 | (-28, -42) | plate_tide, plate_wind, plate_stone | the whole row rang true and nothing said it was done |
| 14 | (-26, -44) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 45 | (-78, 15) | gw_mirror_0, gw_pane_1, gw_pane_0, ... | went round 2 time(s), 207 clicks; the light never settled |
| 63 | (-29, -43) | lens_ring | in sight 24 m overhead; no trail leads up to it |
| 69 | (75, 110) | ti_sluice_2, ti_sluice_0, ti_sluice_1 | the whole row rang true and nothing said it was done |
| 76 | (-71, 110) | ti_pipe_0, ti_pipe_2, ti_pipe_1 | no progress working 3 hold machine(s) |
| 81 | (-71, 110) | ti_pipe_0, ti_pipe_2, ti_pipe_1 | no progress working 3 hold machine(s) |
| 83 | (-64, 33) | ti_bay_2, ti_bay_1, ti_bay_3, ... | every press was ruled out at position 1 |
| 83 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | every press was ruled out at position 1 |
| 86 | (48, -37) | ti_tableau_light_oren | no progress working 1 press machine(s) |
| 97 | (4, -89) | ti_orrery_collar | went round 2 time(s), 49 clicks; the light never settled |

**Every machine worked, in order** (a record is one visit; a row of presses is one record):

| at (s) | what the player read | how | presses | time (s) | outcome |
|---|---|---|---|---|---|
| 40 | Touch the stone (2) | press | 2 | 52 | stalled: the whole row rang true and nothing said it was done |
| 94 | Touch the stone (3) | press | 3 | 114 | stalled: the whole row rang true and nothing said it was done |
| 308 | Touch the stone (1) | press | 1 | 4 | stalled: the whole row rang true and nothing said it was done |
| 313 | Touch the stone (3) | press | 3 | 72 | stalled: the whole row rang true and nothing said it was done |
| 488 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 492 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 493 | Touch the plate (3) | press | 6 | 13 | stalled: the whole row rang true and nothing said it was done |
| 507 | Touch the plate (3) | press | 6 | 13 | stalled: the whole row rang true and nothing said it was done |
| 533 | Touch the stone (3) | press | 3 | 75 | stalled: the whole row rang true and nothing said it was done |
| 778 | The quay is not raised (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 779 | The quay is not raised (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 874 | Touch the plate (3) | press | 5 | 14 | stalled: the whole row rang true and nothing said it was done |
| 890 | Try the door (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 904 | Touch the stone (3) | press | 6 | 167 | solved by trial |
| 2052 | Touch the lens (1) | press | 1 | 0 | pressed once |
| 2116 | Turn the mirror (6) | dial | 207 | 596 | stalled (helped): went round 2 time(s), 207 clicks; the light never settled |
| 2808 | Strike the glass (5) | press | 16 | 55 | solved by trial |
| 3000 | Touch Ilse's light (1) | press | 1 | 0 | pressed once |
| 3003 | Touch Oren's light (1) | press | 1 | 0 | pressed once |
| 3567 | Return through the lens (1) | press | 1 | 0 | pressed once |
| 3701 | Touch the plate (3) | press | 5 | 14 | solved by trial |
| 3783 | Oren’s way: turn the ring  ‹ › (1) | dial | 0 | 42 | stalled (helped): in sight 24 m overhead; no trail leads up to it |
| 3848 | Oren’s way: step into the light (1) | press | 1 | 0 | pressed once |
| 3970 | Touch the gate (3) | press | 4 | 198 | stalled: the whole row rang true and nothing said it was done |
| 4168 | Touch the gate (3) | press | 3 | 120 | stalled: the whole row rang true and nothing said it was done |
| 4291 | Hold the fork to the pipe (3) | hold | 1 | 302 | stalled: held 300 s, nothing answered |
| 4593 | Hold the fork to the pipe (3) | hold | 1 | 302 | stalled: held 300 s, nothing answered |
| 4953 | Take the fork (1) | press | 1 | 0 | pressed once |
| 4967 | Ring the bell (5) | press | 5 | 19 | stalled: every press was ruled out at position 1 |
| 4986 | Ring the bell (5) | press | 5 | 15 | stalled: every press was ruled out at position 1 |
| 5105 | Light the lantern (1) | press | 1 | 59 | stalled: pressed, nothing answered |
| 5234 | Light the lantern (1) | press | 1 | 55 | stalled: pressed, nothing answered |
| 5353 | Turn the collar (1) | dial | 49 | 483 | stalled (helped): went round 2 time(s), 49 clicks; the light never settled |
| 5869 | Turn the ring  ‹ › (1) | dial | 25 | 70 | solved by trial: something big moved while it was turned (new things came into sight) |

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
