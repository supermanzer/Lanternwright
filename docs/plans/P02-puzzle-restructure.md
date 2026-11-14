# P02: restructuring the puzzles to the Myst principles

Written 2026-11-14 by the reviewer (w1:p4), at the user's request: "plan how we could revise the structures of our puzzles to better fit the design principles discussed in Myst." Builds on `docs/plans/P01-myst-puzzle-benchmark.md` (read its sections 1-4 first: the numbers, the prompting devices and the rule "visible problem, hidden solution, visible consequence").
Status: **a plan, nothing built.** Defaults are taken per the user's standing rule and logged as Q49-Q53; the one thing that is NOT mine to decide is the page wording (see section 6).

## 1. Diagnosis: what is structurally wrong today (from `docs/plans/S03-player-path.md` and the code)

| # | Finding | Evidence | Myst principle it breaks |
|---|---|---|---|
| D1 | **One answer, six puzzles.** Tide, wind, stone is the answer to the stones, the mirror court (`GlassWoodLogic`: "meets tide, wind, stone, in that order"), the plates (`TonePlatePuzzle.order = [0,1,2]`, "the stones' own order"), the Archive gates, and is restated in pages 2, 3, 5, 6, 7 and 13 | S03-player-path steps 5, 9, 10, 19, 36 | Variety of verb; a Myst puzzle needs new data every time. Reusing the glyph LANGUAGE is fine (Riven does); reusing the ANSWER means after puzzle one nothing is discovered |
| D2 | **The answer is handed over as a sentence.** Page 3: "from the water, through the wind, to the stone"; page 6: "Water, wind, stone" | steps 5 and 9 | In Myst the player records numbers, tones or symbols from the world and carries them; text tells story, not the answer (Weir: the trail of logic is clue to solution, not a statement of it) |
| D3 | **Clue and machine together.** The stones, their pages and the route are one stretch of path | note #113 | Myst separates them by distance; the carry is the puzzle |
| D4 | **The mirror court is the odd one out.** 1 solution in 1728 settings, and the beam must hit three marks in a fixed order, so there is no partial feedback | `MirrorCourt`, step 9 | Myst machines answer continuously (the generator's voltage, breakers that trip, the compass light/dark). Search without feedback is guessing |
| D5 | **A chain, not a web.** Almost every puzzle is unlocked by the previous one's flag (stones, quay, lens, wood, altar, return, plates, door, fork, Archive) | S02 shape of the game | Myst Island opens 6-7 machines at once and the player holds clues that have no home yet |
| D6 | **The Notebook records for the player.** Rubbings appear when the player is within 9 m of a stone (`Notebook.seenRadius`), without studying it | `Journal.swift` | In Myst the player is the recorder. A little recording work is part of the carry |
| D7 | **Visible problem and consequence are inconsistent** | notes #101, #104, #111, #112, #114 | F09 fixed the instances; P01.2 makes the check systematic |
| D8 | **Escalation is uneven.** Stones: 3 strikes. Mirrors: 1/1728. Chimes: 3 of 5. Plates: 3. Gates: 3 at their levels. Miller's rule is "small, small, then bigger"; ours is small, HUGE, medium, small, medium | sizes above | Pacing |

What is already right and must not be lost: the chime pool (HEAR, memory carried from another world: the best structure we have), the Archive's gates (the three windows arrive in sequence as the water rises: observed, not stated), the per-world signature mechanics planned in S02 (interference, absorption), no fail state, the glyph language, the machine feedback in Varrow (stones ring and light, beam to the lens, causeway rises one slab at a time).

## 2. The target structure

### 2.1 Four design rules (to go at the top of DESIGN.md's puzzle section once the user agrees)
1. **Every puzzle has its own verb and its own information channel.** Channels: SEE (a diagram, a pattern, a position), HEAR (tones, rhythm, direction), COUNT (a quantity in the world), WATCH (a timing or sequence over time), AIM (geometry with live feedback). The same answer is never the solution of two puzzles. The glyphs and tones are vocabulary, not answers.
2. **The solution arrives as an observation the player records, not as a sentence.** Pages carry story and at most one oblique line per puzzle; the datum itself (a diagram, a count, a tone, a rhythm) is in the world or drawn on the page as a picture.
3. **Clue and machine are never in sight of each other**, and the clue is at least one area or one world away.
4. **Every machine answers while you work it.** A continuous channel (a light that grows, a tone that sours or sweetens, a gauge) on at least two senses within 1 s, so the player can reason their way in without a walkthrough.

### 2.2 From chain to web: the Hub and Keys model
Varrow is the Myst Island of this game: the hub that holds several dormant machines from the first minute, each waiting for a datum learned somewhere else.

```
VARROW (hub) -- machines visible from the start ----------------------------------
   Quay (needs the stones)      Lighthouse door (needs the beam signal)     Lens-room ring/lens (needs the gate: pages)
        ^ key: the stones' order,        ^ key: the beam's rhythm,                  ^ key: pages (3 + 3)
          from a DIAGRAM page              WATCHED from outside at dusk
GLASS WOOD:  mirror court (AIM)    +   chime pool (HEAR; its key is the STONES' TONES from Varrow)   -> altar
ARCHIVE:     three gates (WATCH the water level; HEAR the held tone)   +   prism (AIM)   +   tableau, map (optional)
SALT FLATS (S02): interference  = one signature mechanic, imports a datum from the Archive's chain map
THE DRIFT (S02):  polarisation  = one signature mechanic, imports a datum from the Salt Flats
```
Keys cross a boundary; a world is solved with something carried in. Three kinds of key, in order of how Myst uses them: a **tone** (HEAR), a **number or count** (COUNT), a **shape or symbol** (SEE). Each world exports at least one key and imports at least one.

### 2.3 The puzzle graph is data (new structure in code)
Today the structure lives in flags spread over `Game.swift`, `Gate.swift`, `LighthousePuzzle`, `GlassWoodLogic`, `TonePlatePuzzle`, `TideArchivePuzzle` and the player-path doc. Make it explicit: one `PuzzleGraph` data table (puzzle id, world, verb, channel, clue sources with position and channel, machine position, prerequisite flags, consequence event, feedback channels, size in manipulations). Selftests derive the metrics from it and fail on a rule break: acyclic; every clue has a consumer; every puzzle's clue is >= 40 m or a world away from its machine; no two puzzles share an answer; at least 2 puzzles open at every moment after the first 10 minutes of a world; every puzzle names a continuous feedback. This is the "blackboard of flags" the architecture already uses (DESIGN.md section 6), lifted into a declarative description, which is what lets the reviewer and the bot check design rules without playing the game, and is the one piece worth building FIRST because it also delivers P01.2 and P01.6.

## 3. Puzzle by puzzle: keep, change or replace

| Puzzle | Verb / channel now | Verdict | Proposed structure (default) | Cost |
|---|---|---|---|---|
| **Stones and the quay** (Varrow) | strike three in altitude order; order stated in pages 2 and 3 | **Change the clue, keep the machine** | The problem comes first (F09.8 did: the quay is "not raised"). The order comes from a **diagram**: a page with the island's profile sketched, three marks at three heights, each mark carrying the glyph of the stone that stands there; the player reads "low to high", walks to the stones, matches glyphs (SEE, then climb). No sentence says tide, wind, stone. The rubbing is only recorded when the player looks closely at the stone (LookCloser exists) | M (Notebook drawing + page art + pages 2, 3 text: needs the user, section 6) |
| **Mirror court** (Glass Wood) | AIM, but one solution in 1728, ordered, no feedback | **Change** | Make it a pure aim puzzle with live feedback: three receiving crystals light the instant the beam reaches them, in any order; solved when all three are lit at once. The player can reason it out from partial lights. Order no longer matters, so the court no longer repeats the answer (D1, D4). Keep the grid and the pane colours | M (`MirrorCourt` trace and solve rule, selftest "exactly one" becomes "all three lit"; the existing beam-path rendering already shows the trace) |
| **Chime pool** | HEAR, memory carried from Varrow | **Keep** | Only changes: page 7 stops stating that the chimes match the stones (Q: wording, section 6); the Notebook's "tap to hear" stays as the player's recording aid | S |
| **Altar of two accounts** | story reveal | **Keep** | Visible and dormant from arrival (it already is), consequence unchanged | none |
| **Lighthouse door plates** | three plates in tide, wind, stone, a fourth repeat | **Replace the answer (Q38)** | WATCH: after the altar the beam flashes a signal (A's beam pattern); at dusk from outside the player sees a rhythm of long and short flashes grouped in three; the plates are struck in the order the three groups' lengths imply (long = stone, middle = wind, short = tide, learned from the stones' tone durations or glyph sizes the player already met). The held tones keep sounding as feedback. The old order stays in the Notebook as a hint, never as the answer | M-L (beam pattern is A's; plate rule is B's; `TonePlatePuzzle.order` becomes data) |
| **Lens room: ring and receiver; lens** | AIM / TOUCH | **Keep, add feedback** | The ring already shows a beam resting on the receiver; add a charge meter (a soft growing light on the receiver as the beam rests), so the 2 s hold reads as a machine charging, not a timeout. No other change | S |
| **Archive gates** (Ilse: fork/tone; Oren: prism ring) | WATCH the water level + HEAR the tone; AIM the beam | **Keep, tighten the clue** | The three windows arrive in sequence in one rise of the water; keep. Page 13 stops stating "the gates answer a tone and the water together" outright; the gate marks carry a visible level line the water passes (SEE) | S-M (marks, page text: user) |
| **Prism ring** | AIM | **Keep, F09 fixes stand** | Never locks (done, Q46); add the same charge meter as the lens room's ring | S |
| **Chain map, tableau, Roll of Keepers** | optional story | **Keep** | They are the Archive's loose clues: make the map the export key of the Archive (below) | S |
| **Salt Flats, The Drift, The Lamp** (not built) | interference, absorption, final tuning | **Design to the rules before building** | One signature mechanic each (phase of two beams; filter angle), one imported key each, one exported key, 3-5 manipulations, feedback on two channels. The final tuning uses all three keys. S02 section 3 stays the roadmap; this table is the acceptance test | later |

### 3.1 New: planted loose clues (P01.4, now specified)
One unexplained, physical datum per world that pays off two puzzles later, never flagged:
- Varrow dock: the lanterns along the first 40 m of the lantern path are lit in a fixed pattern (a COUNT of how many are lit versus dark). It is the Archive ring's starting mark (the count of dark lanterns = the ring step the first gate needs).
- Glass Wood: the pool's chimes hang at five heights; the Archive's three gate water levels are the three heights that are not decoys. (SEE, then WATCH.)
- Archive: the map's empty last ring is the shape of the Salt Flats' first lamp.
Defaults: the first two are built with P02.5, the third with the Salt Flats.

### 3.2 Keys, as a table the builders can code
| Key | Learned at | Used at | Channel |
|---|---|---|---|
| stones' altitude order | the profile diagram page (Varrow) | the stones | SEE |
| stones' tones | the stones (Varrow) | the chime pool (Glass Wood) | HEAR (already built, keep) |
| beam rhythm | the lighthouse beam at dusk (Varrow, after the altar) | the door plates (Varrow) | WATCH |
| three heights | the chime pool (Glass Wood) | the gates' water marks (Archive) | SEE |
| dark-lantern count | the lantern path (Varrow) | the prism ring's first mark or the fork's first tone (Archive) | COUNT |
| map shape | the chain map (Archive) | the Salt Flats' first lamp | SEE |

## 4. How this interacts with the sibling routes (S05, Q40)
The tools already encode each sibling's channel: Ilse's tuning fork is HEAR, Oren's lens is AIM. Route puzzles should respect that: Ilse's site (interior, instruments) uses HEAR and READ keys (ledgers, tuning, a catalogue); Oren's site (exterior, elements) uses AIM and WATCH keys (prism, tide, glass). Shared puzzles use a channel neither sibling owns (COUNT, SEE). So the route divergence and this plan are one design, not two: S05 should be written AFTER the keys table above, not before. (The reviewer writes S05 next; it will use this table.)

## 5. Work packages, order and owners (nothing started)
| # | Package | Owner | Depends | Size | Output |
|---|---|---|---|---|---|
| P02.0 | `PuzzleGraph` data + metric selftests (section 2.3); load today's puzzles into it, report the metrics, fix nothing | B | none | M | table of rule breaks to drive the rest; replaces P01.2/P01.6 |
| P02.1 | Mirror court: live-feedback aim puzzle (section 3) | B (logic) with A (receiver glow) | P02.0 | M | selftest, a frame of 0, 1, 2, 3 receivers lit |
| P02.2 | Notebook records what was looked at closely; the profile diagram page; stones' clue by diagram | B (Notebook, page art) | user answer on page wording | M | new page art, selftests, frame of the diagram |
| P02.3 | Plates on the beam rhythm (Q38) | A (beam pattern) then B (rule) | P02.0 | M-L | beam signal readable at dusk from the dock; plates accept it |
| P02.4 | Charge meters on the lens-room and prism rings | A (light) | none | S | frames |
| P02.5 | Planted clues (lantern count, chime heights) and the keys wired as data | B | P02.0 | M | graph shows both keys with a consumer |
| P02.6 | S05 divergence, with this table | reviewer writes the plan, then builders | P02.0-P02.3 | L | `S05-divergent-routes.md` |
| P02.7 | Acceptance pass: a no-knowledge bot plus the reviewer, then a person plays | reviewer, user | all | S | the first time the user is asked to play |

Order: P02.0 and P02.4 now; P02.1; then P02.2 (once the user has answered on wording) and P02.3; P02.5; S05. Rules for every package: selftest 0 FAIL, a frame Read by the builder, shader validation clean if rendering changes, ff-merge, push, tag `p02-<n>`, say what to look and listen for in INSPECT.md. No package may remove the guide light, the corridors or the prompts (the user's decisions).

## 6. What needs the user (the plan proceeds on the defaults)
- **Page wording is the user's** (they have changed their mind about wording before; page revisions stay theirs). P02.2 and the chimes/gates rows need pages 2, 3, 6, 7 and 13 to stop stating answers. The builder will produce drafts in `docs/plans/P02-page-drafts.md` and **will not apply them**; the user edits and approves. Until then those pages are unchanged and P02.2 builds only the diagram, the Notebook change and the code.
- Q49 (mirror court): order stops mattering; solved when all three receivers are lit at once. Default taken.
- Q50 (plates): the door plates answer the beam's rhythm, not the stones' order (this is Q38, restated with the mechanism).
- Q51 (Notebook): rubbings and tones are recorded only after the player looks closely at the thing. Default taken, because it restores the carry step.
- Q52 (keys): the six keys in section 3.2 as the designed exchange between worlds; planted clues are unflagged.
- Q53 (scope): whether to apply the same rules to the unbuilt worlds before they are built (default yes: the table in section 3 is their acceptance test).

## 7. Risks and what would stop me
- **Mirror court partial-credit may make it too easy.** Mitigation: keep three receivers and the pane colours; measure steps-to-solve with a greedy bot; Myst puzzles are small, so the target is 4-8 manipulations.
- **Plates on a rhythm may be unfair if the beam cannot be seen from a corridor.** Mitigation: a vantage station on the dock's approach with a terrain ray test (the M10 machinery); if the beam cannot be seen at dusk from any corridor point, the plan falls back to the plates' glints.
- **Opacity can tip into pixel-hunting** (the criticism of the original). Every change here keeps the interaction audit (F09.1) as a gate, and the unchanged rule: guide the body, hide the solution.
- Stopping rule from the review loop applies: if more than half of a package would be detrimental to the pillars in DESIGN.md section 2, stop and tell the user.
