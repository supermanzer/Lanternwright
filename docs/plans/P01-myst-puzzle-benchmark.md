# P01: How hard Myst's puzzles are, how Myst prompts the player, and what that means for Lanternwright

Written 2026-11-12 by the reviewer (w1:p4) in response to the user: "the puzzles in this game are trivial in complexity but also rather opaque and unclear how to proceed. Gather the details of the level of complexity for puzzles in Myst and how the game prompted the player to solve them. We should strive for a similar level of game play here."
Sources are listed at the end. **Confidence note:** the quoted design statements come from Rand and Robyn Miller (interviews) and Gregory Weir's Game Developer analysis. The per-puzzle numbers (voltages, times, code lengths) come from fan walkthroughs of the 1993 original and vary between versions (the 2021 remake changed values); treat them as orders of magnitude, not facts to copy. No source gives an official "step count"; the counts below are my reading of the walkthroughs.

## 1. What a Myst puzzle is, in numbers

Mechanics of Magic's critical-play review puts it in one line: Myst has essentially one puzzle mechanic, "click a pre-rendered graphic to gain raw information", and everything else (dials, switches, sliders, buttons) is a way to set a short code on one machine.

| Puzzle (Myst 1993) | Manipulations on the machine | Code / state to find | Where the answer comes from | Machine feedback |
|---|---|---|---|---|
| Dock marker switch + imager | ~4 | a count (switches on the island) | the island itself: you count | indicator lights, imager turns on |
| Tower rotation (map) | 1 (rotate until a line goes red) | one heading | a flashing symbol on the map | the line changes colour |
| Clock tower | 3 (two wheels, a button) | a time (reported as 2:40) | a key/note found elsewhere | gears move, the tower opens |
| Generator | 4 button presses | a target voltage (reported as 59 V) | a diagram by the exit + a key | a volt readout; breakers trip if too high |
| Rocket ship organ | 5 notes, 5 sliders | a melody and slider positions | a library book + the organ's sound | the ship's linking book appears |
| Planetarium | 3 date settings + 3 pillar presses | 3 dates and 3 constellations | a key from the tower + the Stoneship book | a constellation shows; the model ship rises with a sound |
| Fireplace | one 6 x 8 grid | a pattern | a burnt book page, number from a brother's page | a hidden room opens |
| Stoneship lighthouse (pumps, chest, battery, compass) | ~12 across the age | a bearing, a pump order | a telescope sighting (you see it), drawers, notes | water drains, battery charge, a compass that goes light or dark |
| Channelwood (pipes, valves, lifts) | ~4 per lift | which valve sends water where | book diagrams you copy | you HEAR water; lifts move |
| Selenitic (sound receiver, door sliders, ship) | 5 sounds, then ~14 headings | a sequence of tones/directions | sounds recorded across the age + a simulator in another age | blinking buttons, the tone itself |
| Mechanical (fortress, simulator, symbols) | ~6 | 4 symbols + 2 tones | experimenting with levers; symbols on islands | the fortress rotates, a hologram answers |

What this says about complexity:
1. **Each puzzle is small.** One machine, 1-5 manipulations, a code of 3-14 values. There is almost no deduction chain inside a puzzle.
2. **The difficulty is information logistics, not reasoning.** The answer lives somewhere else (a key in another Age, a book in the library, a sound at a far island). The player must notice it, decide it belongs to something, carry it, and apply it. Gregory Weir: the best puzzles need "all of the challenges surpassed so far".
3. **Parallel, not serial.** On Myst Island, six or seven machines are available at once. The player holds loose clues ("a number, a symbol") that do not yet have a home. This is where the sense of mystery comes from.
4. **Instant, legible feedback; cheap failure.** Every machine responds within a second (light, sound, motion). Nothing kills the player or locks a run; a wrong code is retried in seconds. The only complaints in the sources are tedious resets (the submarine) and pixel-hunting movement (clicking empty space to move).
5. **Chains cross Ages.** The tones in the Mechanical simulator are needed in the Selenitic ship; the tower key opens the clock; the Stoneship book decodes the planetarium. This is the "continuous trail of logic" Weir asks for.

## 2. How Myst prompts the player (the "prompting" answer)

Myst has no tutorial, no objective text, no hint, no waypoint (the Masterpiece Edition later added a three-level optional hint map because players asked for one). Yet players are not lost. It is done by these devices:
1. **Visible problem, hidden solution.** A locked door, a dead machine, a missing bridge: the player always sees WHAT is blocked. The game never says HOW to unblock it. Rand Miller's test: when the player finds the solution they should say "Oh, yes. I should have gotten that"; "if they blame us, then we haven't done a good job."
2. **Information is in the world, in physical forms.** Books and notes (names the player), diagrams next to the machine, sounds that are literally laid out on the map (Miller: the Maze Runner "is laid out along with the sounds"), a flashing light, a diagram on the wall. The player does the recording (pen and paper); the game stores nothing for them.
3. **Machine feedback is the teacher.** The generator's volt readout and tripping breakers tell you "closer/over" without words. The compass goes light or dark. Water is heard before it is seen.
4. **Repetition teaches the language.** Small puzzle, small puzzle, bigger puzzle (Miller). A symbol or a number seen once is seen again.
5. **Nudges are placed after testing, never as prose.** Miller on Obduction: the first power lines were "too subtle", so they were made "just blatant", and a beetle flies down them: "a small nudge." He also says the sound cues in Myst "could have been louder." The fix for a missed clue is to strengthen the in-world cue, not to add a pop-up.
6. **Integration with the setting.** Robyn Miller: a good puzzle "shouldn't feel like a puzzle"; the Channelwood pumps feel like powering a village. Weir: "At the very least, a puzzle should make sense in the game world."
7. **Fairness bar (Weir):** "A fair puzzle is one which can be solved using information and tools provided in the game, without depending on guesswork, specialized knowledge, or a walkthrough," with "a continuous trail of logic from the clues to the solution."

## 3. Lanternwright against that yardstick

Based on `docs/plans/S03-player-path.md` (steps 1-41) and the user's notes.

| Dimension | Myst | Lanternwright today | Gap |
|---|---|---|---|
| Size of a puzzle | 1-5 manipulations, code of 3-14 | The stones: 3 strikes. Mirrors: 25 cells x orientations (1 solution of 1728), chimes: 3 of 5, plates: 3, gates: 3, ring: a few turns | Sizes are fine. They are NOT the problem. The user's word "trivial" is about discovery, not the code length |
| Where answers live | Far from the machine, in another place or Age | Stones: the stones, their pages and the path to them are all on the one route (#113: "directly on your path ... trivially easy") | Clue and machine are co-located and unavoidable |
| Variety of verb | Sliders, counting, listening, routing water, aiming, timing, memory | The same three-in-order answer (tide, wind, stone) is used by the stones, mirrors, chimes, plates, gates and ring | Six puzzles, one answer; after the first, nothing is discovered. Reusing the glyph language is good (Riven does it); reusing the same solution is not |
| Parallelism | 6-7 open at once | Mostly a single chain (dock, stones, quay, lens, wood, return, plates, door, exits, Archive); the Glass Wood has two parallel puzzles | One thing at a time; no loose clues to carry |
| Visible problem | Always | The quay is not obviously a problem (#112: the "barrier" water is wadeable); the lighthouse door has no stated problem after the lamp is lit (#114); several prompts name a thing the player cannot see (#107 #109 #115); several visible things have no use (#95 #96 #99 #102 #116) | **This is the biggest gap** and is mostly a defect, not a design choice: F09.1 |
| Visible consequence | Always | Archive gates lowered the water "but it is unclear how I have gained from this" (#101); after the prism lights a panel the ring locks and nothing says what is next (#111); no way out/no puzzle visible (#104) | Solved state needs to be seen (and heard) |
| Feedback speed | Immediate, physical | Strong in Varrow (stones ring and light, beam to lens); weaker in the Archive | Fix with F09.1/F09.7 |
| Navigation help | None | Guided corridors, lantern trail, guide light, many prompts | The user decided to keep the corridors. Keep them, but guide the BODY, not the MIND (rule below) |
| Hint layers | None (Masterpiece: 3 optional levels) | The Notebook; the F key is feedback only | Optional hint layer is a candidate (P01.5) |

### The reconciling rule: guide where to go, hide how it works
The user wants two things that look opposed: more guidance on what to do next (#104, #114, #101: "unclear", "no clear indication") and more opacity in the puzzles (#113: "make references more opaque so users can get down to the quay, find out they need to raise it, and search for the stones"). Myst does both with one rule, and this rule should be written at the top of the puzzle chapter of DESIGN.md:

> **Every puzzle presents a visible problem, hides its solution in the world, and shows a visible consequence when solved.**
> 1. *Problem*: the player can see that something is blocked or dormant, and can reach it (quay that does not rise, door that will not open, ring that does nothing yet). If the problem is not in view, the guide light parks there.
> 2. *Search*: the way to unblock it is NOT in view from the problem, and not on the way to it. Clues are physical (a page, a tone, a diagram, a marking) and live somewhere else, 40-200 m away or in another world.
> 3. *Consequence*: the world visibly and audibly changes where the player is standing or at once afterwards (a light, a sound, something moves), and the guide light parks at the next problem.

By this rule: #113 (stones before the quay) breaks step 1-2; #114 (lit lighthouse, no problem pointer) breaks step 1; #101/#104/#111 break step 3. F09 contains the fixes for those instances; P01.2 below makes the check systematic.

## 4. Complexity budget to aim for (recommended; Q37)

| Property | Target | Why |
|---|---|---|
| Manipulations per puzzle | 3-6 | Myst's range |
| Code length | 3-5 values (up to 8 for one "big" puzzle per Age) | Memorable without a notebook; Myst goes to 14 only for the ship |
| Clue sources per puzzle | 1-2, never at the machine | Weir's trail; forces carrying |
| Distance clue to machine | at least one separate area or world | creates the "carry" step |
| Open puzzles at once | at least 2 after the first 10 minutes of each world | loose clues, curiosity |
| Reuse | glyphs and tones reused across worlds, but each puzzle needs a different VERB or a different INFORMATION CHANNEL (sound, sight, reading, counting, timing) | variety without breaking Riven-style consistency |
| Failure | none; retry cost under 10 s | Myst; matches the game's no-fail rule |
| Feedback | within 1 s, on at least two channels (sight + sound) | Myst |
| First-time solve time per world | 15-25 min including walking | Myst Age pacing; check with the player-path bot x human factor 3 |

## 5. Work packages (after F09 lands; builders pick up in this order)

**P01.1 Re-seat clues away from machines (B):** audit every puzzle for "clue and machine within sight of each other or on the same forced route". Move or hide until the budget holds. Start with the Varrow stones (F09.8 is the first instance) and the Glass Wood altar, where the stones' tones are the answer (that one already crosses worlds: good, keep).
**P01.2 Problem / search / consequence table (B, extends the F09.1 audit):** for each of the ~15 puzzles list: what shows the problem (frame), what the clue is and where it lives (distance), what shows solved (frame + sound). A selftest renders the three frames per puzzle through the existing `--screenshot` views and checks the interactable and guide-light state for each stage. Fix every row with a blank.
**P01.3 Give the plates a different verb (B, with A for the beam):** after the altar the lighthouse beam flashes a signal pattern (builder A's work). Default decision: the three door plates must be struck in the order the beam pattern shows (long-short-short style, mapped to the three glyphs by something learned earlier), so the information comes from watching the lighthouse from OUTSIDE (the beam, at dusk) and applying it at the plates, not from re-reading the stones' order a fourth time. Logged as Q38; the old order remains the Notebook's fallback hint. Also vary the Archive's second puzzle so the gate order is not tide-wind-stone again unless the water levels dictate it (they do: keep).
**P01.4 A loose clue (B):** plant one early, unexplained physical clue per world that pays off two puzzles later (a symbol on a plinth in Varrow that is meaningless until the Glass Wood altar, or a number of lanterns on the dock that is the Archive's ring step). Myst's marker switches and the dock count are the model.
**P01.5 Optional hint layer (B, design to be approved by the user):** a Notebook page "If you are stuck", off by default, three levels per puzzle (where to look, what to look for, the answer), Masterpiece-style. It is for people who want the Myst experience without a walkthrough; the default is opaque. Because the user wants opacity, do NOT build before they say yes (Q39).
**P01.6 Measure (A or B):** extend the player-path bot to report minutes of first-time play per world from a no-knowledge bot with a 3x factor, and the count of simultaneously open puzzles; compare with the budget.
**P01.7 S05: make the sibling choice change the journey (the user's #106) (APPROVED DIRECTION: the user asked for it; the reviewer writes `S05-divergent-routes.md` next, right after F09 is handed out; specifics are Q40):** the user played Ilse's and Oren's routes and arrived at the same spot with the same puzzles; they want "different locations, in the same worlds, and different puzzles" so the second playthrough is worth it. Proposed default (nothing built): each route world has two SITES; the entry, the guide light and 2 of 5 puzzles are shared, and each sibling's route covers a different site with its own two puzzles and its own pages. Ilse = the interior and the instruments (stacks, ledgers, dome; puzzles listen and read: tuning, a catalogue); Oren = the exterior and the elements (quays, tide, prism, glass; puzzles aim and time). The two sites meet at the final chain map, where each player sees the other site's lamp as the thing they did not do (the hidden third ending's cost). Cost is large (new puzzles, props and pages for every route world), so the plan is phased: Archive first. The user's specifics are logged as Q40 and the default proceeds.

## 6. Notes for the user (decisions I made on your behalf, change if wrong)
- The word "trivial" is taken to mean easy to find and to resolve, not short; the code lengths stay near Myst's.
- The corridors, the guide light and the prompts stay (you approved them); what changes is that they only point at problems and places, never at solutions.
- Nothing in P01 is started; F09 is the work in flight. P01.1 and P01.2 will go to the builders as the next plan once F09 merges.

## Sources
- Gregory Weir, "Analysis: Puzzle Design in the Myst Series", Game Developer (2009): https://gamedeveloper.com/design/analysis-puzzle-design-in-the-i-myst-i-series
- Rand Miller interview (AV Club, 2016): https://avclub.com/myst-creator-rand-miller-on-his-favorite-puzzle-that-ev-1798251819
- Robyn Miller at GDC 2013, summarised: https://play.breakthrought1d.org/news/the-story-behind-myst/ ; Atlas Obscura "Exploring Myst 25 years later": https://atlasobscura.com/articles/exploring-myst-25-years-later
- Mechanics of Magic, "Myst (Critical Play: Puzzles)": https://mechanicsofmagic.com/2026/05/08/myst-critical-play-puzzles/
- Walkthrough used for step counts: https://fisicx.com/myst/walkthrough.htm ; puzzle index https://mystjourney.com/myst/puzzles/
- Reception, Masterpiece Edition hint system: Giant Bomb user review https://Www.giantbomb.com/myst/3030-3970/user-reviews/2200-17868/ ; Wikipedia "Myst".
- The project's own earlier references: docs/DESIGN.md section 2 (pillars) and its sources [1], [2], [9], [11].
