# S05: the sibling choice changes the journey

Written 2026-11-14 by the reviewer. Source: the user's note #106 ("I chose Ilse's way. I am placed in the exact same location as when I chose Oren's way. We should have the siblings path fork result in the players traveling to different locations, in the same worlds, and having to solve different puzzles. This expands the game play and makes repeating with another sibling's choice more interesting."). The direction is approved by the user (Q40); the specifics below are defaults. Built on `docs/plans/P02-puzzle-restructure.md` (verbs, channels, keys, the `PuzzleGraph`): **read P02 sections 2 and 3.2 first.** Nothing here is built.

## 1. Today (so the change is measurable)
Both routes enter the Tide Archive at different ends (`Game.routeEntry`: the lamp end for Ilse, the open end for Oren) but then walk the same corridor to the same three sluice gates and the same gallery, open them at the same tide levels, read pages 10-15 (two voices of the same six pages), and end at the same quay ring. The only differences are the tool (Ilse's tuning fork holds a gate's tone; Oren's lens turns a prism beam onto a gate's mark) and the guide (Oren's lantern ahead of Ilse; Ilse's lamps on Oren's route). That is one puzzle with two tools, which is why a second play feels like the first.

## 2. The design in one paragraph
Each route world is split into **two sites**: Ilse's site (the interior and the instruments) and Oren's site (the exterior and the elements). The entry, the guide, the middle of the journey and the finale are shared; each sibling's route spends most of its time at its own site, solving that site's puzzles, and sees the other site's machines across the water as **dormant, visible problems it cannot yet reach** (the Myst rule: visible problem, hidden solution). Each route holds **two puzzles of its own, one shared puzzle and one finale** (so about 2 of 5 are the other's), and the two sites meet at the gallery and the chain map, where each player sees what the other did.

### 2.1 The two sibling channels (from the tools they already carry)
| | Ilse | Oren |
|---|---|---|
| Tool | tuning fork (HEAR) | lens (AIM) |
| Site | the stacks and ledger rooms: interior, shelves, bells, brass | the prism chamber, the outer quays and the dome: exterior, water, glass |
| Verbs | listen, read, compare, tune | aim, time, watch, align |
| Keys she imports | the stones' tones (HEAR), a catalogue diagram (SEE) | the beam rhythm (WATCH), the chime heights (SEE) |
| Feel | warm lamplight, paper, low bells | cool light, open water, prisms |

Shared puzzles use a channel neither sibling owns: **COUNT** (the tide marks, the dark-lantern count) and **SEE** (the chain map's shape).

## 3. The Archive, phase 1 (specified)
Names refer to `World/Layout.swift` `ArchiveLayout` and `Game/TideSpots.swift`.

| # | Puzzle | Who | Where | Verb / channel | What it asks (3-6 manipulations) | Key | Feedback | Consequence |
|---|---|---|---|---|---|---|---|---|
| A0 | **The tide marks** | both (shared) | the entry quay and the first gallery | COUNT | read the water's level against three brass marks as the tide rises; count which mark the water passes in which order and note the three levels | the dark-lantern count from Varrow gives the first mark | each mark chimes when the water passes it | the guide parks at the first site and the way to it opens |
| I1 | **The catalogue** | Ilse | the stacks (the fork's ledgers, `TideSpots.fork`) | READ + HEAR | each shelf bay carries a glyph and a bell; a catalogue page (a diagram, not a sentence) shows which bays form a sequence; ring the bays in that order with the fork | the stones' tones (carried from Varrow) identify the bells | a right bay rings and stays warm; a wrong one sours, no penalty | the locked ledger room opens (its page and the sluice-room key tone) |
| I2 | **The bell pipes** | Ilse | the three sluice rooms | HEAR (beats) | hold the fork at a gate's pipe: the pipe's pitch depends on its water level; when pipe and fork agree the beats slow to nothing and the gate answers; do it for the three gates as the tide passes their levels | the three heights (from the Glass Wood's chime pool) tell the player which level each gate wants | beats slow as you approach the right level (a continuous channel) | gates open; the gallery drains (shared consequence) |
| O1 | **The orrery** | Oren | the dome's brass instrument (`ta_dome`) | WATCH | a brass tide-orrery shows the three levels as three arms moving over one cycle; wait and mark the moments the arms line up with the dome's windows (turn a brass collar to stop an arm) | the beam rhythm (carried from Varrow) sets the collar's detent count | an arm that is stopped at the right moment lights its window | three windows lit = the prism's three components are available |
| O2 | **The prism ring** | Oren | the prism chamber (`TideSpots.prismRing`) | AIM | turn the ring until each lit window's component rests on a gate's mark and hold it (exists, with the F09 changes) | the three lit windows from O1 decide which components exist | the charge meter (P02.4), a coloured lamp in each sluice room | gates open; the gallery drains |
| F | **The gallery and the chain** | both | the Great Ledger gallery, the chain map | SEE | after the drain, page 15 and the tableau; the map's last empty ring is the shape the Salt Flats' first lamp needs | the map's shape (an export key) | the tableau shows the other sibling's version | the route's quay ring takes you back; the other site's dormant machines are now visible as what you did not do |

So Ilse's route is A0, I1, I2, F; Oren's is A0, O1, O2, F. Each has **two puzzles of its own**, shares A0 and F, and both end by draining the gallery (the same world-state change), which keeps the later story (the third ending needs both siblings' ways known) intact.

## 4. How the other site shows as a problem, not a gap
- From the route's own quays you can see across the water: Ilse sees the dome's orrery and the prism chamber's glass (dark, unreachable until the gallery drains); Oren sees the stacks' bells (dark) and lit windows of the ledger room.
- After the finale, the route's quay ring takes you back to Varrow as today; the other route stays unlit. A second playthrough starts with the other site's dormant machines already familiar from across the water.
- Nothing says "play again". The Notebook's Roll of Keepers evidence line (existing) and the tableau's other version are the only prompts.

## 5. Template for the later worlds
For the Salt Flats, the Drift and the finale: the world has one signature mechanic (interference, polarisation, final tuning) with **two expressions**, one per sibling, one shared puzzle and one finale; each sibling's site uses their channels (2.1). The `PuzzleGraph` rule "no two puzzles share an answer" and "each puzzle names a continuous feedback" apply. Do not build a later world's second site until the Archive's two routes have been played by the user.

## 6. Work packages (reviewer sends each when the previous is merged)
| # | Package | Owner | Depends | Size |
|---|---|---|---|---|
| S05.0 | Put the Archive's A0, I1, I2, O1, O2, F into the `PuzzleGraph` with their keys and consequences, and run the graph checks (acyclic, keys consumed, no shared answers, two open at a time) | B | P02.0 | S |
| S05.1 | Ilse's site: props and geometry for the stacks' bays and bells, the ledger room (door, page spot), the sluice rooms' pipes with a visible water level; the catalogue diagram page art; audio for bells and beat feedback | A (world, audio), B (diagram page art) | S05.0 | L |
| S05.2 | Oren's site: the dome's orrery (three arms, collar), the windows that light, the prism's inputs from the windows, the outer quays' dormant view of the stacks | A (world, light), B (logic) | S05.0 | L |
| S05.3 | Puzzle logic: A0 tide marks, I1, I2, O1; O2 (the existing ring) takes the lit windows as its inputs; routes gated by `routeChosen`; saves | B | S05.1/2 stubs | L |
| S05.4 | Dormant-from-afar views (sight lines from each route's quays, unlit models of the other site's machines), vantage stations for them | A | S05.1/2 | M |
| S05.5 | Pages: each site needs one page per sibling (a lectern in the stacks; a note at the orrery). **Drafts only** in `docs/plans/P02-page-drafts.md`; the user approves wording; the puzzles must work without them | B | none | S |
| S05.6 | Bots: both routes from a fresh game, no teleport, using only what is in view; the player-path doc rows for the new steps; the graph's metrics for both routes | B | S05.3 | M |
| S05.7 | Acceptance: reviewer frame review of both sites, sound as numbers, then the user plays both routes | reviewer, user | all | S |

## 7. Risks and defaults
- **Cost.** The Archive's second site is new geometry (the largest item in the game since the Archive itself). The plan spends it on the Archive only and waits for the user's play before copying it to other worlds.
- **Fairness.** The bell pipes' beats and the orrery's timing are the two new continuous-feedback mechanics; the beats must be audible on laptop speakers (use 300-1200 Hz tones, not sub-bass; see the F09 wind lesson) and the orrery arms must be visible from the collar.
- **Page wording stays the user's;** the clues are diagrams and machine feedback so the puzzles do not depend on new text.
- **Defaults taken (Q40 and Q54+ as builders log them):** two sites per route world; 2 of 5 shared; Ilse = interior/instruments, Oren = exterior/elements; Archive first; later worlds follow the template after the user plays.
- The stopping rule applies: if most of a package would be detrimental to the pillars in DESIGN.md section 2, stop and tell the user.
