# P02.0 report: today's puzzles loaded into the PuzzleGraph (builder B, 2026-11-14, phase B1, tag `f10-b`)

Nothing here was fixed: P02.0 loads the game as it is and says which of the P02 design rules (`docs/plans/P02-puzzle-restructure.md` section 2.3) it breaks. The tables below the second marker are **generated** from the live game by

```
.build/release/Lanternwright --puzzle-graph                              # print
.build/release/Lanternwright --puzzle-graph docs/plans/P02-graph-report.md   # replace the block between the markers
```

so regenerate them after any change to a puzzle; the text outside the markers is hand-written and stays.

## What is derived and what is declared

**Derived from the code, not retyped** (so the graph moves when the game does; `SelfTestPuzzleGraph` checks each): the answers (`LighthousePuzzle.order`, `TonePlatePuzzle.order`, `MirrorCourt.solutionPanes`, `GlassWoodLogic.chimeSolution` read through `ToneTable`, `TideArchivePuzzle.sluiceFlags`); where every machine and page stands (the centres of the game's own interactable boxes, so a moved box moves the graph); the manipulation counts (the mirror court by searching all 1728 settings: exactly one solves it and the fewest clicks from where it is found are 11; the rings by their steps); and which of the fifteen pages state the order in words (read from the page text, both voices: pages 3, 5, 6 and 13).

**Declared by the builder** (the structure the code cannot say about itself, written once in `PuzzleGraph.today`): which flag each puzzle needs and sets, which pages and memories are its clues, and the feedback each machine gives with the event that gives it (the "Feedback" table names the event; none was measured with a stopwatch). Cross-checks stop the declarations drifting: every machine id must be a real interactable of its world, every flag a flag the game keeps (or one of the graph's own markers `returned`, `route_begun`, `gate_pages`, `contradiction`).

## How the selftest can be green with 21 rule breaks

The rules (`PuzzleRules`, `Game/PuzzleGraph.swift`) are pure functions over a graph value. `SelfTestPuzzleGraph` proves each one on **synthetic** graphs: a clean fixture passes every rule, and a copy broken in exactly one way is flagged by exactly the rule that should flag it (mutation-checked: raising the limit of G4 to 0 m fails its fixtures; changing the plates' order in `TonePlatePuzzle` changes today's list and fails the pin). Today's real graph is not required to be clean; its list of rule breaks is **pinned** (`SelfTestRunner.pinnedPuzzleBreaks`). A new break fails the selftest, and so does a break that goes away unnoticed: whoever fixes one updates the pin and regenerates this file on purpose.

## The rules, and a reading of today's breaks

| rule | what it asks | today | which P02 package resolves it | needs the user? |
|---|---|---|---|---|
| G1 acyclic, reachable | no puzzle waits for itself; every puzzle can open | none | | |
| G2 flags provided | every flag a puzzle needs is set by something | none | | |
| G3 stated answers have a consumer | a page that says an answer is a clue of some puzzle | none | | |
| G4 clue distance | each clue is 40 m or a world away from its machine | stones pages 2 and 3 are 3 m from the stones (they lie beside them: D3); the plates' memory of the stones is 35 m | P02.2 (the stones' clue by diagram, one area away); the plates change with P02.3 | pages 2, 3: wording |
| G5 shared answer | no two puzzles share an answer | stones, mirror court, chime pool, door plates and the Archive's gates are all "tide, wind, stone" (D1) | mirror court P02.1 (order stops mattering), plates P02.3 (beam rhythm), the gates by S05 | no (defaults Q49, Q50) |
| G6 open at once | two or more puzzles open when the player chooses, after the first of a world | the chime pool and the door plates are each the only one open (D5); the Glass Wood offers two together, then one | P02.5 (planted clues give a second open puzzle), S05 (two sites) | no |
| G7 feedback | progress (how close) on two senses within 1 s | mirror court (sight only: the tick says nothing), door plates (sound only: the glint is "binary"), lens ring (sight only) | P02.1 (receivers light as hit), P02.4 (charge meters, A's glow) | no |
| G8 budgets | 3 to 6 manipulations, 1 to 2 clue sources | mirror court 11, prism ring 15 (6 + 4 + 5 clicks), plates have 4 clue sources | P02.1 (the court gets partial feedback, then measure with a greedy bot); the prism ring: Q (below); plates P02.3 | no |
| G9 verb and channel | each puzzle has its own | stones, plates and chime pool all "strike / hear"; the lens ring and the prism ring both "turn / aim" | plates P02.3; the two rings were meant to be a pair (P02 section 3 keeps both) | the rings: a decision, logged as Q70 |
| G10 sentence | the answer is not handed over as a sentence | pages 3 (stones, plates), 5 (mirror court, plates), 6 (plates), 13 (both gates) | **only the user's page wording can fix this**; drafts go in `docs/plans/P02-page-drafts.md` (P02.2), nothing is applied | **yes** |

### Cheap and not cheap
Nothing in G4, G5, G9 or G10 is a code fix: they are the design the P02 packages change. The only two that are small are G7's lens ring (A's charge meter, P02.4, plus a sound of the beam resting) and the prism ring's 15 clicks (the ring's step is 15 degrees and the three marks are 90 degrees and 60 degrees and 45 degrees apart; a coarser step is a one-constant change, `TideArchivePuzzle.ringStep`, but it moves the marks A painted, so it is not mine to do alone: Q70).

### What the graph does not see (read the numbers with this in mind)
- **The Notebook** replays the stones' tones ("tap to hear"); it is a recording aid, not a clue source, and is not counted.
- **Page availability.** Page 6 appears two seconds after the mirror court is solved and page 7 after the chimes, so they are consequences, not clues, for those puzzles; page 6 is listed as a clue of the plates only (it is there by then).
- **Oren's route.** In the code Oren's exit needs the lens ring to open the doorway (`Fork.swift`), so the ring is mandatory on his route and optional only as the alternative to Ilse's touch; the graph models the lens ring as optional and enters the Archive by the touch, so G6 never walks Oren's route.
- **Optional puzzles** (Oren's exit ring, the contradiction card) are scored by every rule but G6 (they are not counted as "open"); the contradiction is a story beat (a Notebook card with any-three-of-five evidence) and is not scored. Ilse's exit is a touch, a transit.
- **The tide.** The Archive's gates open only when the water is at their level (`Tide.windows`); that wait is not a manipulation and is not in the counts.
- **G6 is a simulation**: a player who always takes the first open puzzle; the count is what is open just before each choice (including the one chosen); the first puzzle of each world and the last of the game are exempt. It does not model the 10-minute grace of the plan.
- **The approximations** are all of the same kind: distances are straight-line between box centres (not walking distance), "a world away" is infinite.

<!-- graph:begin -->
### The graph (generated by `--puzzle-graph`, from the live game)

Kinds: puzzle (counted), story (a beat with no datum), transit (moving between worlds). `opt` = optional, never counted as open. Answers are glyph tokens; `man.` is the fewest manipulations, computed (the mirror court by searching its 1728 settings, rings by their steps).

| id | world | kind | verb / channel | answer | man. | needs | sets | clues (distance from machine) |
|---|---|---|---|---|---|---|---|---|
| stones | varrow | puzzle | strike / hear | tide, wind, stone | 3 | quay_seen | solved | page 2 (3 m); page 3 (3 m); the stones' altitude order (74 m) |
| to-glass-wood | varrow | transit | touch / touch | - | - | solved | lensTouched | none |
| mirror-court | glassWood | puzzle | turn+change / aim | wind, stone, tide | 6 | lensTouched | gw_mirrors | page 5 (141 m); the stones' order (another world) |
| chime-pool | glassWood | puzzle | strike / hear | tide, wind, stone | 3 | lensTouched | gw_chimes | the stones' tones (another world) |
| altar | glassWood | story | touch / touch | - | 2 | gw_mirrors, gw_chimes | gw_end | none |
| return | glassWood | transit | touch / touch | - | - | gw_end | returned | none |
| door-plates | varrow | puzzle | strike / watch | stone, tide, wind | 3 | returned, gate_pages | door_open | the beam rhythm (329 m); the stones' altitude order (300 m) |
| lens-ring (opt) | varrow | puzzle | turn / aim | angle:-45 | 3 | door_open | portal_open | none |
| enter-archive | varrow | transit | touch / touch | - | - | door_open | route_begun | none |
| archive-gates-tone [archive-gates] | tideArchive | puzzle | touch+hold / hear | tide, wind, stone | 3 | route_begun | route_solved | the stones' order (another world); page 13 (240 m) |
| archive-gates-beam [archive-gates] | tideArchive | puzzle | turn / aim | tide, wind, stone | 15 | route_begun | route_solved | page 13 (12 m); the lit-lantern count (another world) |
| contradiction (opt) | varrow | story | set / see | - | 3 | returned | contradiction | page 4 (no machine position); page 5 (another world); page 8 (another world); page 9 (no machine position); page 12 (another world) |

### Feedback each machine gives (declared from the code; the cell names the event)

| puzzle | sense | kind | within | what the player sees or hears |
|---|---|---|---|---|
| stones | sight | progress | 0.60 s | each right stone lights and stays lit; a wrong one dims all three |
| stones | sound | progress | 0.00 s | each strike rings and the right ones hold their drone |
| mirror-court | sight | progress | 0.35 s | the beam is retraced on the turn; each receiving crystal lights the moment the beam reaches it in its colour and goes dark when it is lost (a wrong colour flutters dully) |
| mirror-court | sound | progress | 0.00 s | a glass tick on every turn, and a lit crystal rings its own stone tone |
| chime-pool | sight | progress | 0.30 s | a right chime lights and stays lit; a wrong one sours and resets |
| chime-pool | sound | progress | 0.00 s | each chime rings its tone; a wrong one sours |
| door-plates | sight | binary | 0.00 s | the plates glint only while they would be answered |
| door-plates | sound | progress | 0.00 s | a right strike holds its tone; a wrong one sours and resets |
| lens-ring | sight | progress | 0.00 s | a beam preview runs from the ring's pointer, and the receiver takes a light while the gate is ready |
| lens-ring | sound | binary | 0.00 s | a stone-on-brass grind with a detent click |
| archive-gates-tone | sight | progress | 0.00 s | the gate lifts and its wheel turns; the water over the room's floor shows whether it can answer |
| archive-gates-tone | sound | progress | 0.00 s | the held tone, souring if wrong |
| archive-gates-beam | sight | progress | 0.00 s | the component brightens on its mark and the matching room's lamp lights |
| archive-gates-beam | sound | progress | 0.00 s | the held drone |
| contradiction | sight | binary | 0.00 s | a quiet "Settled." or silence |

### Pages that state the order in words (read from the page text, both voices)

| page | world | consumers (puzzles that list it as a clue) |
|---|---|---|
| 3 | varrow | stones |
| 5 | glassWood | mirror-court, contradiction |
| 6 | glassWood | **none** |
| 13 | tideArchive | archive-gates-tone, archive-gates-beam |

### Keys: what the player carries between places (P02 section 3.2; `built` = both ends exist in the game, `planted` = an unflagged datum no page states)

| key | channel | learned at | used at (puzzles that list it as a clue) | built? | the datum |
|---|---|---|---|---|---|
| stones-tones | hear | stones (varrow) | chime-pool | built | tide D4, wind A4, stone D5: the three of the pool's five chimes that are not decoys |
| three-heights | see | chime-pool (glassWood) | archive-gates-tone (**does not list it**), archive-gates-beam (**does not list it**) | planned: the gates' water marks (builder A, Q76): until they exist nothing at the gates uses it, so the gates do not list it as a clue | the non-decoy chimes hang in the order of the sluice rooms' floors (tide highest): an ORDER today, not a scale, and the gates carry no mark for it yet (Q76) |
| lantern-count | count | dock-lanterns (varrow) | archive-gates-beam | built, planted | 6 of the first 8 dock lanterns are lit = 6 steps to the prism ring's first mark (Oren's way; Ilse's fork has no counterpart yet, Q75) |
| stones-order | see | the island-profile diagram on page 1 (varrow) | stones, door-plates | built, planted | a drawn profile of the climb with a mark at each stone's real height (tide < wind < stone); a mark shows its rubbing once the stone has been looked at closely (Q51); the plates use it to name a flash's length (short = low = tide) |
| beam-rhythm | watch | the lighthouse beam at dusk, from the dock (varrow) | door-plates | built, planted | three groups of flashes of 2.6, 0.7, 1.5 s, read by RANK (short = tide, middle = wind, long = stone): the plates are struck in the order flashed, stone, tide, wind |
| map-shape | see | the chain map (Archive) (tideArchive) | - | planned: the Salt Flats' first lamp (not built) | the shape of the last ring |

### What is open when the player chooses (a player who always takes the first open puzzle)

| step | solves | world | open at that moment | verdict |
|---|---|---|---|---|
| 1 | stones | varrow | stones | first of its world (exempt) |
| 2 | mirror-court | glassWood | chime-pool, mirror-court | first of its world (exempt) |
| 3 | chime-pool | glassWood | chime-pool | **only 1** |
| 4 | door-plates | varrow | door-plates | **only 1** |
| 5 | archive-gates-tone | tideArchive | archive-gates | first of its world (exempt) |

### Rule breaks (15)

| rule | what it asks | subject | found |
|---|---|---|---|
| G3 | every page that states an answer is a clue of some puzzle | page 6 | page 6 states the order and no puzzle lists it as a clue: a clue with no consumer, or an answer given away for nothing |
| G4 | every clue is 40 m or a world away from its machine | stones page 2 | page 2 is 3 m from the machine (the rule is 40 m or another world) |
| G4 | every clue is 40 m or a world away from its machine | stones page 3 | page 3 is 3 m from the machine (the rule is 40 m or another world) |
| G5 | no two puzzles share an answer | archive-gates+chime-pool+stones | 3 puzzles are all answered by "tide wind stone" |
| G6 | at least two puzzles are open when a player chooses (after the first of a world) | chime-pool | when chime-pool is chosen only ["chime-pool"] is open: a chain, not a web |
| G6 | at least two puzzles are open when a player chooses (after the first of a world) | door-plates | when door-plates is chosen only ["door-plates"] is open: a chain, not a web |
| G7 | every machine answers with progress, on two senses, within 1 s | door-plates senses | within 1.0 s it answers on ["sound"] and not on two senses |
| G7 | every machine answers with progress, on two senses, within 1 s | lens-ring senses | within 1.0 s it answers on ["sight"] and not on two senses |
| G8 | 3 to 6 manipulations; 1 to 2 clue sources | stones clues | 3 clue sources (budget 1...2) |
| G8 | 3 to 6 manipulations; 1 to 2 clue sources | archive-gates-beam manipulations | 15 manipulations (budget 3...6) |
| G9 | every puzzle has its own verb and channel | chime-pool+stones | 2 puzzles share the verb and channel strike/hear |
| G9 | every puzzle has its own verb and channel | archive-gates+lens-ring | 2 puzzles share the verb and channel turn/aim |
| G10 | the answer is not handed over as a sentence | stones page 3 | page 3 says the order in words |
| G10 | the answer is not handed over as a sentence | archive-gates-tone page 13 | page 13 says the order in words |
| G10 | the answer is not handed over as a sentence | archive-gates-beam page 13 | page 13 says the order in words |

Rules with no break: G1, G2, G11
<!-- graph:end -->
