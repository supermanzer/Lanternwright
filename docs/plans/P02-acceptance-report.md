# P02.7 acceptance prep: the no-knowledge bot, route by route (builder B, phase B6, tag `s05-b3`, 2026-11-15)

**What this is.** A scripted player that knows nothing (`SelfTests/NoKnowledge/`: a `Perception` that gives it only what is on the screen and in the speakers, and a brain that a selftest proves names no puzzle, constant, flag or answer) plays the game from a fresh start at the end of the dock to the drained gallery, on each route, with no teleport. The tables between the markers below are generated from that run; this part is the builder's reading. **Nothing was heard or seen by a person**: a sound is an identity to the bot, a lit thing a number.

## Headline

| | Ilse | Oren |
|---|---|---|
| reaches the drained gallery from a fresh game | yes, 139 min of play, 382 manipulations | yes, 100 min of play, 312 manipulations |
| puzzles solved **blind** (feedback only, no text, no diagram, no rhythm) | stones, chime pool, altar, door plates, tide marks, catalogue, bell pipes (7 of 8) | stones, chime pool, altar, door plates, tide marks (5 of 9) |
| puzzles that needed the **knowing helper** | the mirror court (and the stair, a bot limit) | the mirror court, Oren's lens ring (the stair), the orrery, the prism ring |
| stall points | 17 | 12 |

**Reading the numbers.** A "blind" solve means the game's feedback alone was enough for a patient player who tries things: it does **not** mean a person would find the puzzle easy, and it does not measure clue quality (a person has the page and the diagram, the bot has neither). A "helped" puzzle means the bot, working from the feedback, did not get there in a bounded effort (400 s per visit at a dial); it says where a person without the clue would be stuck, not that the puzzle is broken.

## What the bot found (each is a Q; defaults taken, nothing changed except the one cheap fix)

1. **Every ordering puzzle is solvable by trial** (stones 18 presses, chime pool 16, plates 23, catalogue 29: 3 to 5 things in a row). A wrong press names exactly the part that held ("everything resets" is also "this was wrong *there*"), and there is no cost beyond 0.8 s, so the clue (the stones' altitudes, the beam's rhythm, the catalogue diagram) is a shortcut, not a requirement. Q100.
2. **The door plates answer before they can open the door.** Struck blind at the lighthouse before the altar, the plates ring true, bloom, show the gate's cue and reset; the bot solved them (5 presses) a second time after the return and the door opened. Nothing wrong; the first solve told it nothing. Q101.
3. **The mirror court defeats a hill climb** (181 presses, never settled): the receivers light only when the whole beam reaches them, so most settings show no change at all (a plateau). A person reasons about the beam; a feedback-only player cannot. Q102.
4. **Dormant machines answer with nothing.** On Ilse's route the orrery's collar clicks and nothing happens (32 and 35 clicks pressed); on Oren's the bays, the sluice gates' wheels and the bell pipes take presses and answer nothing. S05 section 4 says the other site is a *visible problem that cannot yet be reached*; a thing that takes a press and says nothing reads as broken. Q103.
5. **The orrery** was caught blind by "watching and pressing as it brightens" on earlier runs and not on the final one (the notch has to be right at the moment): its timing is luck for a player without the beam rhythm, which is the key the puzzle is built on. Q104.
6. **The prism ring** is never reached blind: its arrow keys need the windows lit and each gate's tide, and nothing tells a feedback-only player which of three dark ghosts to turn to. Q105 (with the ring's 15 manipulations: Q70).
7. **Stones before the quay** ring and answer nothing (F09.8's design: quay, "it does not rise", then the search): the bot spent 14 minutes on that. Not a defect; a data point for the opening's pace. Q106.
8. **The spiral stair is on no trail**: the bot (and the whole-game bots) must be helped up it. Not a game defect (a person walks up), a limit of "following the lanterns' path"; the lens and the ring in the lens room are seen from the ground floor, 24 m overhead. Q107.
9. **Time**: a player who knows nothing needs 100 to 140 minutes of play; about 50 minutes of it is walking the island before the first lens (it visits every trail point before leaving a place) and 30 to 60 minutes is the tide. Q108.

## The two fixes made in this phase (cheap G7 breaks that were mine)

- **`door-plates` (sight was binary):** the plates now glow a step brighter for each right strike held and drop back on a wrong one (`Game.plateHeldStep` = 0.08, on the one `tone_plates` mesh), so the eye answers the way the ear does. Frames `shots/b6/plates-none.png`, `plates-platesheld1.png`, `plates-platesheld.png` (`--view lh-plates3 --state platesheld`): the three plates' black glyphs wash to grey and the faces lighten, step by step; looked at, one set of frames, 3 m out at dusk. The plates are one mesh, so the glow is the set's, not each plate's (A could split the mesh: Q109).
- **`archive-marks` (sight was binary):** A's gauge (Q97) glows a bar as the water crosses it; B now holds a counted mark lit (`TideMarks.set` from `IlseRoute.updateVisuals`, both routes, again after a load). The graph's feedback line for A0 says so.

The graph report is regenerated: 17 rule breaks (was 19). The other seventeen are logged, with who owns each, in `docs/OPEN-QUESTIONS.md` Q109 and Q110.

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

## Ilse's route: the gallery drains after 138 min of play, 383 manipulations, 18 stalls, 5 helps

| # | puzzle | verb / channel | designer's least | blind presses | blind time at it | solved at | how |
|---|---|---|---|---|---|---|---|
| 1 | stones | strike / hear | 3 | 18 | 487 s | 17 min | blind, by trial and the feedback |
| 2 | mirror-court | turn+change / aim | 6 | 181 | 536 s | 44 min | **helped** (the bot stalled: went round 2 time(s), 181 clicks; the light never settled) |
| 3 | chime-pool | strike / hear | 3 | 16 | 55 s | 46 min | blind, by trial and the feedback |
| 4 | altar | touch / touch | 2 | 2 | 1 s | 49 min | blind, by trial and the feedback |
| 5 | door-plates | strike / watch | 3 | 23 | 57 s | 61 min | blind, by trial and the feedback |
| 6 | archive-marks | count / count | 3 | 0 | 0 s | 88 min | by waiting and listening |
| 7 | archive-catalogue | ring / see | 3 | 29 | 180 s | 100 min | blind, by trial and the feedback |
| 8 | archive-pipes | hold fork / hear | 3 | 5 | 390 s | 138 min | blind, by trial and the feedback |

**Helps** (what the knowing helper did, and when):

- 44 min: sets the mirrors and panes of the court (solution known)
- 69 min: climbs the spiral stair (on no trail)
- 72 min: climbs the spiral stair (on no trail)
- 75 min: climbs the spiral stair (on no trail)
- 82 min: climbs the spiral stair (on no trail)

**Stall points** (each is 150 s with nothing new, or a machine worked without an answer; `at` is where the bot stood):

| at (min) | where | what it was at | why |
|---|---|---|---|
| 8 | (-26, -43) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 8 | (-27, -42) | plate_tide, plate_wind, plate_stone | the whole row rang true and nothing said it was done |
| 14 | (-26, -44) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 44 | (-78, 15) | gw_mirror_0, gw_pane_1, gw_pane_0, ... | went round 2 time(s), 181 clicks; the light never settled |
| 69 | (-28, -52) | lh_lens_touch | in sight 26 m overhead; no trail leads up to it |
| 72 | (-31, -52) | (nothing in sight) | nothing in sight to press, nowhere new to walk |
| 75 | (-28, -52) | lh_lens_touch | in sight 26 m overhead; no trail leads up to it |
| 82 | (170, 198) | (nothing in sight) | nothing in sight to press, nowhere new to walk |
| 93 | (-10, 124) | ti_pipe_2, ti_pipe_0, ti_pipe_1 | no progress working 3 hold machine(s) |
| 96 | (-11, 122) | ti_pipe_2, ti_pipe_0, ti_pipe_1 | no progress working 3 hold machine(s) |
| 100 | (-64, 27) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 101 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 104 | (4, 117) | ti_sluice_0, ti_sluice_2, ti_sluice_1 | the whole row rang true and nothing said it was done |
| 112 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | the whole row rang true and nothing said it was done |
| 115 | (48, -37) | ti_tableau_light_oren | no progress working 1 press machine(s) |
| 125 | (4, -89) | ti_orrery_collar | went round 1 time(s), 32 clicks; the light never settled |
| 132 | (4, -89) | ti_orrery_collar | went round 1 time(s), 35 clicks; the light never settled |
| 138 | (68, 106) | ti_sluice_2, ti_sluice_0, ti_sluice_1 | every press was ruled out at position 3 |

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
| 2117 | Turn the mirror (6) | dial | 181 | 536 | stalled (helped): went round 2 time(s), 181 clicks; the light never settled |
| 2756 | Strike the glass (5) | press | 16 | 55 | solved by trial |
| 2947 | Touch Ilse's light (1) | press | 1 | 0 | pressed once |
| 2950 | Touch Oren's light (1) | press | 1 | 0 | pressed once |
| 3515 | Return through the lens (1) | press | 1 | 0 | pressed once |
| 3649 | Touch the plate (3) | press | 5 | 14 | solved by trial |
| 4192 | Ilse’s way: touch the lens (1) | press | 0 | 24 | stalled: in sight 26 m overhead; no trail leads up to it |
| 4556 | Ilse’s way: touch the lens (1) | press | 0 | 24 | stalled: in sight 26 m overhead; no trail leads up to it |
| 5135 | Ilse’s way: touch the lens (1) | press | 1 | 0 | pressed once |
| 5187 | Touch the gate (3) | press | 3 | 109 | stalled: the whole row rang true and nothing said it was done |
| 5323 | Touch the gate (3) | press | 3 | 135 | stalled: the whole row rang true and nothing said it was done |
| 5484 | Hold the fork to the pipe (3) | hold | 1 | 151 | stalled: held 150 s, nothing answered |
| 5658 | Hold the fork to the pipe (3) | hold | 1 | 151 | stalled: held 150 s, nothing answered |
| 5862 | Ring the bell (5) | press | 19 | 140 | stalled: the whole row rang true and nothing said it was done |
| 6025 | Take the rod (1) | press | 1 | 11 | pressed once |
| 6046 | Ring the bell (5) | press | 5 | 18 | stalled: the whole row rang true and nothing said it was done |
| 6125 | Touch the gate (3) | press | 4 | 169 | stalled: the whole row rang true and nothing said it was done |
| 6326 | Hold the fork to the pipe (3) | hold | 1 | 6 | waited for |
| 6448 | Light the lantern (1) | press | 1 | 0 | pressed once |
| 6557 | Hold the fork to the pipe (2) | hold | 1 | 33 | waited for |
| 6593 | Touch the gate (3) | press | 3 | 89 | stalled: the whole row rang true and nothing said it was done |
| 6747 | Ring the bell (5) | press | 5 | 21 | stalled: the whole row rang true and nothing said it was done |
| 6876 | Light the lantern (1) | press | 1 | 59 | stalled: every press was ruled out at position 1 |
| 6990 | Light the lantern (1) | press | 1 | 59 | stalled: every press was ruled out at position 1 |
| 7113 | Turn the collar (1) | dial | 32 | 415 | stalled: went round 1 time(s), 32 clicks; the light never settled |
| 7529 | Turn the collar (1) | dial | 35 | 416 | stalled: went round 1 time(s), 35 clicks; the light never settled |
| 7973 | The ring is empty (1) | press | 1 | 0 | stalled: pressed, nothing answered |
| 8152 | Hold the fork to the pipe (1) | hold | 1 | 46 | waited for |
| 8200 | Touch the gate (3) | press | 4 | 127 | stalled: every press was ruled out at position 3 |

## Oren's route: the gallery drains after 100 min of play, 312 manipulations, 12 stalls, 5 helps

| # | puzzle | verb / channel | designer's least | blind presses | blind time at it | solved at | how |
|---|---|---|---|---|---|---|---|
| 1 | stones | strike / hear | 3 | 18 | 487 s | 17 min | blind, by trial and the feedback |
| 2 | mirror-court | turn+change / aim | 6 | 181 | 536 s | 44 min | **helped** (the bot stalled: went round 2 time(s), 181 clicks; the light never settled) |
| 3 | chime-pool | strike / hear | 3 | 16 | 55 s | 46 min | blind, by trial and the feedback |
| 4 | altar | touch / touch | 2 | 2 | 1 s | 49 min | blind, by trial and the feedback |
| 5 | door-plates | strike / watch | 3 | 23 | 57 s | 61 min | blind, by trial and the feedback |
| 6 | lens-ring | turn / aim | 3 | 0 | 42 s | 62 min | **helped** (the bot stalled: in sight 24 m overhead; no trail leads up to it) |
| 7 | archive-marks | count / count | 3 | 0 | 0 s | 67 min | by waiting and listening |
| 8 | archive-orrery | turn collar / watch | 3 | 24 | 437 s | 91 min | **helped** (the bot stalled: went round 1 time(s), 24 clicks; the light never settled) |
| 9 | archive-gates-beam | turn / aim | 15 | 2 | 408 s | 100 min | **helped** (the bot stalled: went round 1 time(s), 2 clicks; the light never settled) |

**Helps** (what the knowing helper did, and when):

- 44 min: sets the mirrors and panes of the court (solution known)
- 62 min: climbs the spiral stair (on no trail)
- 62 min: turns Oren's lens ring onto its receiver
- 90 min: catches the three orrery arms (notch and moment known)
- 98 min: turns the prism ring onto each gate's mark (marks and tides known)

**Stall points** (each is 150 s with nothing new, or a machine worked without an answer; `at` is where the bot stood):

| at (min) | where | what it was at | why |
|---|---|---|---|
| 8 | (-26, -43) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 8 | (-27, -42) | plate_tide, plate_wind, plate_stone | the whole row rang true and nothing said it was done |
| 14 | (-26, -44) | plate_stone, plate_wind, plate_tide | the whole row rang true and nothing said it was done |
| 44 | (-78, 15) | gw_mirror_0, gw_pane_1, gw_pane_0, ... | went round 2 time(s), 181 clicks; the light never settled |
| 62 | (-29, -43) | lens_ring | in sight 24 m overhead; no trail leads up to it |
| 72 | (63, 115) | ti_pipe_1, ti_pipe_2, ti_pipe_0 | no progress working 3 hold machine(s) |
| 75 | (64, 116) | ti_pipe_1, ti_pipe_2, ti_pipe_0 | no progress working 3 hold machine(s) |
| 77 | (-64, 33) | ti_bay_2, ti_bay_1, ti_bay_3, ... | every press was ruled out at position 1 |
| 77 | (-64, 25) | ti_bay_4, ti_bay_3, ti_bay_2, ... | every press was ruled out at position 1 |
| 80 | (48, -37) | ti_tableau_light_oren | no progress working 1 press machine(s) |
| 90 | (4, -89) | ti_orrery_collar | went round 1 time(s), 24 clicks; the light never settled |
| 98 | (0, -130) | ti_prism_ring | no progress working 1 dial machine(s) |

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
| 2117 | Turn the mirror (6) | dial | 181 | 536 | stalled (helped): went round 2 time(s), 181 clicks; the light never settled |
| 2756 | Strike the glass (5) | press | 16 | 55 | solved by trial |
| 2947 | Touch Ilse's light (1) | press | 1 | 0 | pressed once |
| 2950 | Touch Oren's light (1) | press | 1 | 0 | pressed once |
| 3515 | Return through the lens (1) | press | 1 | 0 | pressed once |
| 3649 | Touch the plate (3) | press | 5 | 14 | solved by trial |
| 3730 | Oren’s way: turn the ring  ‹ › (1) | dial | 0 | 42 | stalled (helped): in sight 24 m overhead; no trail leads up to it |
| 3795 | Oren’s way: step into the light (1) | press | 1 | 0 | pressed once |
| 3946 | Touch the gate (3) | press | 3 | 111 | stalled: every press was ruled out at position 3 |
| 4067 | Touch the gate (3) | press | 3 | 149 | stalled: the whole row rang true and nothing said it was done |
| 4216 | Hold the fork to the pipe (3) | hold | 1 | 151 | stalled: held 150 s, nothing answered |
| 4388 | Hold the fork to the pipe (3) | hold | 1 | 151 | stalled: held 150 s, nothing answered |
| 4592 | Take the fork (1) | press | 1 | 7 | pressed once |
| 4613 | Ring the bell (5) | press | 5 | 19 | stalled: every press was ruled out at position 1 |
| 4632 | Ring the bell (5) | press | 5 | 15 | stalled: every press was ruled out at position 1 |
| 4750 | Light the lantern (1) | press | 1 | 59 | stalled: pressed, nothing answered |
| 4880 | Light the lantern (1) | press | 1 | 55 | stalled: pressed, nothing answered |
| 4998 | Turn the collar (1) | dial | 24 | 437 | stalled (helped): went round 1 time(s), 24 clicks; the light never settled |
| 5507 | Turn the ring  ‹ › (1) | dial | 2 | 408 | stalled (helped): went round 1 time(s), 2 clicks; the light never settled |

<!-- nokbot:end -->

## Method notes (for whoever reads the tables)

- The bot's eyes: an interactable is "in sight" within 250 m when it is in front of the camera or within 5 m; walls and distance do not hide it. A real player misses things the bot sees, and the bot never looks for what is hidden.
- The bot's hands: the real `Game.advance` input (walk, aim, click, arrow keys) through the same trails as the whole-game bots; it never teleports.
- The helps are the knowing walks the whole-game bots already use (the court's solution, the stair, the ring's receiver angle, the collar's notches, the prism's marks): the same code, run from wherever the bot stood.
- A stall's 150 s, a dial visit's 400 s and the three-stalls-in-a-row give-up are the bot's patience, chosen so a puzzle that a person could solve by feel is not ruled out by a short fuse. They are in `BlindPlayer.swift` (`stallSeconds`, `watchAndPress`, `dial`).
- The run is deterministic for a given build (the game's clock is the bot's), but a small change in feedback can change which visit solves what: the pinned lists in `SelfTestNoKnowledge.swift` (`pinnedBlindSolved`, `pinnedHelped`) fail on a change and are moved on purpose.
