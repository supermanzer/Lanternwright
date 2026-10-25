# S01: story, worlds and the sibling choice (a proposal for the user)

**Status: proposal. Nothing here is built, and it is not for the builder yet.** It needs the user's decisions (listed at the end) first. Written by the reviewer from the user's direction on 2026-10-25:

> Side with either sibling; a mechanism for the choice; expose the player to both perspectives; this still feels like the start of the game, so more levels and harder puzzles; the player goes deeper into a sibling's story and learns about Lanternwrights, the lighthouse and its purpose, and what it means to be the last Lanternwright; play on the lantern light moving between worlds (purpose or side-effect of a true purpose, perhaps inter-dimensional guideposts); each sibling needs more character before the choice.

## 0. Constraints this plan must satisfy

From `docs/DESIGN.md` and `CLAUDE.md`:
- **No cutscenes, no voice, no external assets.** Story is told by pages, architecture and the state of the world. Anything "replayed" must be buildable with the procedural renderer and synth.
- **No fail state, no timers** (pillar 4). **One internal logic** (pillar 5): the tide, wind and stone tones and glyphs recur everywhere.
- **Fair mystery** (pillar 3): the clue lives near where it is used. The choice must be informed: the player cannot reach it without meeting both accounts.
- **Canon already in the game (eight pages).** Page 1: the lamp has gone quiet; Oren says Ilse fusses; "a lighthouse that does not answer is only a tower." Page 4: Oren asks for the lens; "light that can fold can also carry"; he does not say what it would carry. Page 5 (Oren's voice): he went through the lens first, and says Ilse "will be right about the lens and wrong about the reason" (see revision R1 below). Page 6: "Light is not carried, Ilse. It is turned." Page 7: the chimes are the same three tones the children learned; Ilse let him strike them first. **Page 8: "Two accounts will reach you, and they will not agree. Hers says I left her. Mine says she would not follow. Read both, then choose whose light you carry. I will be waiting where the wood ends. — O."** Everything below builds on these. Proposed edits are listed explicitly in section 7 so nothing is rewritten silently.
- **Each sibling must be defensible.** Each is right about something and wrong about something, and each omits something that does not flatter them. That is the design rule that avoids Myst's lying brothers.

## 1. What other games do (research)

Format as in DESIGN.md section 1: lesson, source, how Lanternwright applies it. Facts below were checked against the cited pages on 2026-10-25. Several sources are fan wikis or reviews; where a claim rests on one of those I say so. Developer-origin material (GDC talks, postmortems) was not found in these searches, so design-intent statements are labelled as reviewers' readings.

| Game | What it does | Lesson for Lanternwright |
|---|---|---|
| **Myst** [1] | The player reads two imprisoned brothers (Sirrus and Achenar), each blaming the other. The ending is decided by what you do with the final pages: returning a page to a brother traps you in his book (two bad endings); a third book, which both brothers warn you away from, holds the father, Atrus, and the good ending. Sources agree the clues across the Ages imply both brothers were cruel. | The closest template, and DESIGN.md says we echo it, not copy it. Two lessons: (a) the ending is **enacted with the game's own objects** (books and pages), not a menu; (b) its weakness for us is that both brothers are villains and one answer is plainly "right". Lanternwright's siblings must both be sympathetic and both partly wrong. |
| **Riven** [2] | A father figure (Gehn) taught the hero's father the Art, then trapped him; the story is learned by traversing Gehn's own constructed world, and the ending depends on how you use the trap book you are given. | A villain or rival can be understood through **the world they built** (his workshop, his habits, his shortcuts) more than through his own words. Each sibling gets a built place that shows who they are. |
| **Return of the Obra Dinn** [3] | The player reconstructs what happened to a whole crew by deduction; the game confirms fates only in sets of three correct entries, so guessing does not work. | **Knowledge is the progression gate**, and confirmation in groups keeps it honest. Our version: the "Contradictions" notebook (section 5), where the player decides which sibling's claim the evidence supports, confirmed in small groups. |
| **Outer Wilds** [4] | Progress comes from knowledge, not gear; the ship log keeps a map of partial knowledge (a rumor graph) with open questions; no quest markers. Reviewers note that practical routes and failed hypotheses are embedded in the ancient builders' ordinary writing. | The **lighthouse's purpose is itself the mystery**, solved by reading how it was built and maintained. Build a "rumour map" page in the journal (open questions, linked clues, no objective markers). |
| **Heaven's Vault** [5] | The player slowly decodes an invented script. Translations are never confirmed (to stop brute-forcing), wrong readings are part of the design, the story responds to the readings, and replays keep surfacing new words. Some reviewers found the language closer to a cipher than a language. | The glyph language we already have (tide, wind, stone) can **deepen with literacy**: old pages gain new margin lines once more glyphs are understood, so re-reading pays off. Keep it a small, honest cipher, not a fake language. |
| **What Remains of Edith Finch** [6] | Each family member gets a separate short chapter with its own mechanic, and the mechanic mirrors the character's inner life. Different art styles for different members. | **One world per character beat, one mechanic per world.** Each sibling's chapters use a different optical or tonal verb that reveals how they think. |
| **The Talos Principle** [7] | A forbidden tower is the central choice; reviewers read the ending as a test of independent thought; the follow-up asks the player to persuade someone to leave everything behind. | A choice can come from **a rule the world gives and a reason to break it**, and its consequence can be a conversation, not a battle. It also shows the risk: if one option reads as the "good" ending, the choice stops being a choice. |
| **Obduction** (Cyan) [8] | The designers say puzzles are built into the history, culture and environment of the place, and that reading the story more closely helps you solve the puzzles; some characters affect progression. | Puzzle solutions should be **expressions of a sibling's philosophy**, so learning the story makes puzzles easier and solving puzzles reveals story. |

**Cross-cutting lessons:**
1. The best story-by-exploration games make the **player the investigator**: the game withholds the answer and lets the player assemble it (Obra Dinn, Outer Wilds, Heaven's Vault). Our current game tells the story in short journal paragraphs; the next stage should make the player connect them.
2. **Layers beat length.** Surface text, then objects and places, then a deeper reading once literacy grows (Heaven's Vault), then the world state itself.
3. **A choice must have weight in play, not only in text** (Myst's pages, Talos's tower). The decision should be made by doing something with the game's verbs.
4. **Avoid a hidden correct answer** (Myst's third book, the Talos ascension). If we have a "best" ending it must be a consequence of how much the player understood, not a trap.

## 2. The lighthouse's purpose: three options (the user's decision)

The user suggested guideposts between worlds. Options, from simplest to most connected:

**A. The Chain of Lights (recommended; the user's guidepost idea, developed).** A lantern is not a lamp for ships; it is a **fixed point in a chain**. Each Lanternwright tuned a light so that things lost between places (ships, people, worlds drifting loose) could find a way back. A Refraction is not a destination: it is a *place where a light caught*, a pocket of world held in place by a lantern, so the lantern keeps it from drifting. Travel through the lens is a side-effect of the lantern being *tuned to that pocket* (to find a way back, a light must be able to reach it). Tide, wind and stone are the three media a signal can travel through (sea, air, ground), which is why every lantern is tuned to three tones. The last Lanternwright is the keeper of the last unbroken stretch of the chain. If a lantern goes dark, its pocket drifts away. **This makes both siblings right:** Ilse's "light must answer" (a lantern keeps a place held) and Oren's "light can carry" (a lantern is a path, so it can be used to leave).

**B. The Archive.** Lenses fold light and *time*: each Refraction is a stored moment (a memory of a world). The lighthouse is a memory beacon. Rich for characters (you visit moments of the siblings' childhood), but it risks making the Refractions passive.

**C. The Lock.** The lens seals something. The lighthouse is a warden against something the siblings' ancestors folded away. Gives an antagonist, but it is the genre cliché and conflicts with pillar 4 (no threats).

**Recommendation: A**, because it generalises the existing three-tone logic, justifies puzzles (tuning), gives the player a growing sense of scale (the chain), and makes the choice natural (see section 4).

## 3. The siblings

Both are written to be sympathetic, flawed, and partly right. Each has a *verb* that matches the game's tones (Ilse keeps, Oren turns), a *built place*, and a *secret* the other account omits.

### Ilse Varrow, the keeper
- **Philosophy:** "A light must answer." A lamp exists to be there when needed; you stay.
- **Temperament:** meticulous, tender, dry-humoured about her own rules, afraid of loss. Tunes the lamp the same way every evening.
- **Right about:** a lantern left unattended loses its pocket; she has seen it happen. Oren's carelessness has a cost.
- **Wrong about:** that staying is always safe. Her rules have become a way to avoid risk; she did not teach Oren the whole craft because she feared he would leave.
- **Her omission (the secret):** the night of the Long Fog (below), when she dimmed the lamp to save the oil / to follow the rule, and a boat did not find the way home.
- **Her place:** the Lighthouse and workshop (Varrow), then the Tide Archive (a flooded ledger-observatory).
- **Her tone family:** the stones struck **in order of altitude** (tide, wind, stone): patience and sequence.

### Oren Varrow, the wayfarer
- **Philosophy:** "Light is not kept, it is turned." A lens exists to open a way; staying is also a kind of leaving.
- **Temperament:** restless, generous, funny, impatient with ritual; teaches by showing; leaves notes in margins. Took the lens first and writes as if the outcome were obvious.
- **Right about:** the chain is failing and nobody is training the next keeper; keeping a single light on an island does not save the others.
- **Wrong about:** that taking the lens early was harmless; he took it the night of the Long Fog and was not there to answer the signal. He tells himself she would not follow.
- **His omission (the secret):** the same night. He was beyond the glass wood and saw the boat's lantern, and **did not turn back**, because he was ashamed of the argument.
- **His place:** the Glass Wood (done), then the Drift (see roadmap).
- **His tone family:** the same three tones, but played **together or through mirrors**: simultaneity and reflection.

### The shared event: the Long Fog
Years ago, their teacher (the previous keeper, **Maren**, name provisional) failed to come home on a foggy evening. Ilse was at the lamp; Oren was through the lens. Each blames the other, and each blames themselves, privately. The accounts disagree on **who was supposed to be where**. The truth (reached only in the deepest layer): the lamp could only answer if it was *tuned to Maren's lantern*, and that needed both siblings' tones at once: Ilse's order and Oren's turn. The fog was nobody's fault; the *argument* meant they were not together. **The chain needs two keepers; the last Lanternwright is the last because the pair broke.** That gives "what it means to be the last Lanternwright" a concrete, human answer: **being last is not being alone by fate; it is the consequence of a choice not to reconcile.**

## 4. The choice: three candidate mechanisms

The player must choose whose light to carry. Each mechanism enacts the choice with the game's own verbs (light, tone, lens), never a menu, and is gated by having met both accounts (section 5).

**M-A. Two ways to finish the final tuning (recommended).** At the end the lighthouse lens must be tuned one last time. There are two valid solutions, both fair:
- **Ilse's way: answer.** Strike the three stones in altitude order, as she taught, and let the tones *hold* until the lamp answers. The beam fixes on the horizon and stays; the chain holds; the island and its pockets stay; Oren's Refraction slowly dims, and he remains on the far side.
- **Oren's way: turn.** Align the mirrors and panes so the beam is *turned* through the lens (the Glass Wood skill) and carried out along the chain. The lantern leaves with the player; the island goes dark; the pockets that depended on it begin to drift, but a new, longer path is opened, and Ilse stays at a lamp that no longer answers.
Both end the game with an irreversible change in the **state of the world** (the lighthouse and island seen from the final view), then a closing page by the **unchosen** sibling that reveals the thing they omitted. No cutscene.

**M-B. The Long Fog as a final puzzle.** The player re-enacts the fog night: the lamp must answer a signal that needs both siblings' tones at once, which is only possible if the player has **both** Ilse's order and Oren's turn. The choice is *which sibling's mistake to forgive*: the player ends by turning the lens toward Ilse's lamp or Oren's boat. This is more emotional but needs a more elaborate final puzzle and is the most reconciling; it can be the **hidden third reading** if the user wants one (section 8).

**M-C. The two lanterns.** The player carries one lantern the whole game and at the end places it at either sibling's stand. A simple physical choice, but it is closest to a menu with props and least tied to a puzzle.

**Recommendation: M-A**, with the option to add M-B as a reconciliation ending later. Reason: it is a real puzzle each way, both sides are expressions of a skill the player has practised, and the choice is a *doing*, which is what Myst's pages and the Talos tower do.

**Avoiding a "right" answer.** Both endings cost something visible; neither is gated behind extra effort; the epilogue page from the unchosen sibling should make the player reconsider, not punish.

## 5. How the player learns both sides (informed choice)

1. **Two voices in the journal.** Pages are tagged by author (Ilse, Oren, other). The journal gets three tabs: **Ilse**, **Oren**, **Notebook**. Today it is one list and Oren's pages are found only in the Glass Wood. (See the discoverability bug below.)
2. **A gate.** The final area opens only after the player has read at least *N* pages from each sibling (suggest 5 each of 8 to 10) and has made at least one contradiction decision.
3. **Contradictions** (Obra Dinn's confirmation in groups, Outer Wilds' rumour graph): the notebook lists claims that conflict ("Hers: I left her. His: she would not follow."), each tied to evidence the player finds in the world (a tide table, a boat log, a scorch mark on a stand). The player marks which claim the evidence supports; the game confirms **in groups of three** and never marks single answers right or wrong. Each resolved contradiction unlocks a margin line and, at the end, changes a sentence in the epilogue. It is optional depth, and nothing is lost by skipping.
4. **Literacy** (Heaven's Vault): the player learns more glyphs (the three tones plus new ones: "answer", "carry", "hold", "turn", "chain"). Earlier pages gain **margin lines in glyphs** when the player understands more, revealing what the author did not say in words (for example Ilse's pages show a crossed-out line only readable later).
5. **Places as characters** (Riven): each sibling's built places contain mechanisms that only make sense in their philosophy.
6. **Shadow plays** (optional, procedural): a lantern lit at the right place casts a **silhouette tableau** of a remembered moment on a wall (two figures at a lamp). No voice, no animation heavy lifting: flat cut-out shapes and light, in the spirit of lens-and-shadow craft, which fits the engine.

## 6. Roadmap of worlds and puzzles

The vertical slice has the Isle of Varrow (done) and the Glass Wood (done, Oren's first Refraction, optical property: **reflection**). `docs/reviews/R01-part2` proposed one optical property per Refraction. Proposed full game: **five places plus the finale.** Each Refraction gets **one sibling's chapter**, one optical/tonal verb, one new tool the player keeps, and one mechanism that carries a character beat.

| # | Place | Sibling | Verb / property | New tool kept | Beat |
|---|---|---|---|---|---|
| 1 | **Isle of Varrow** (done) | both | tune by order (altitude) | none | Establish the lamp, the stones, the lens, the siblings. Add the missing early pages (R2, R3). |
| 2 | **The Glass Wood** (done) | Oren | reflection, mirrors, turning light | the beam-turning lens (kept) | Oren's first leap; his philosophy; the pages 5 to 8. |
| 3 | **The Tide Archive** (new) | Ilse | **dispersion**: a prism splits a beam into tide/wind/stone components; flooded ledgers and tide tables | the **tuning fork** (play a tone to hold a gate) | Ilse's life's work: the Roll of Keepers; what a Lanternwright is; the guild and its charter; the chain first appears as a map. Puzzle: tide levels and tones open sluices in order. |
| 4 | **The Salt Flats of the Two Lamps** (new) | both | **interference**: two beams in phase brighten and in antiphase cancel; two lamps, two rhythms | none (uses both tools) | The Long Fog night reconstructed from physical evidence; the two siblings' accounts diverge visibly (two sets of footprints, two lantern stands); the first strong **contradiction** puzzles. |
| 5 | **The Drift** (new) | Oren | **absorption/polarisation**: dark world where only certain light passes; a pocket that has begun to drift | uses all three | What happens when a lantern goes out: the world is coming loose; the player sees a pocket drifting and a lantern that was never relit. Oren's loneliness and his reason. |
| 6 | **The Lamp at the End of the Chain** (finale) | both | **the final tuning** (choice mechanism M-A) | all | Both stands present; the choice; the epilogue state of the island; the closing page by the unchosen sibling. |

**Difficulty ramp.** The slice teaches one order (three stones, one beam). Then: 2 uses reflection plus the same order (done); 3 adds time (tide levels) and a held tone; 4 adds two simultaneous systems and a contradiction to resolve; 5 removes the hints the player has come to rely on (darkness) and asks them to carry a tone mentally; 6 asks for the same skills, twice, in different arrangements. Always with the observable-cause rule: a failed attempt changes something you can see or hear and teaches.

**Hub.** The lens room in the lighthouse becomes a hub with one lens per Refraction (a ring of lenses, each lit when its world is solved). The return lens already exists (`gw_return`).

**Estimate of work.** Each new Refraction is comparable in size to the Glass Wood (terrain, props, puzzle logic, pages, selftests): the builder has done that once in roughly one long session group. Treat each as one plan file (W-numbering as in F01), and gate each on a playtest by the user before starting the next.

## 7. Revisions to existing pages (explicit, for the user to approve)

- **R1 (page 5):** the line "Ilse will say I stole it, and she will be right about the lens and wrong about the reason" stays; add a first sentence that sets the date relative to the Long Fog ("The week before the fog,").
- **R2 (new page, Varrow, dock):** a short Ilse page near the start that gives her voice something other than worry: a dry joke and a rule ("Keepers do not run on the shingle.").
- **R3 (page 4):** the line "He did not answer, and I did not like the silence" stays; add a half-line showing her reply was a rule, not an offer to teach.
- **R4 (page 8):** unchanged. It is the promise the finale pays off. Note it is **Oren's voice** speaking about Ilse's account: the "two accounts" are Ilse's journal and Oren's, and the game must therefore contain Ilse's account of leaving. Currently her side stops at page 4. **Write Ilse's pages 9 to 12** for the Tide Archive and the Salt Flats.

## 8. Engineering hooks (for later, once approved)

- **Data-driven story.** Move `JournalContent.pages` into `Story/Pages.json` (or a Swift table) with fields: number, author, text, places-to-find, requires (flags), glyph margin lines with the literacy level that reveals them.
- **Journal tabs** by author plus the Notebook; unread markers; a rumour/contradiction view. The earlier F01 note about opening on the newly read page already exists.
- **Story reachability selftest.** A bot walks a fresh game and asserts: every page is collectable on a normal route; every contradiction has two sources; the gate is reachable; both endings are reachable from the same save; no flag set is unreachable. Extends the existing playthrough bots.
- **Save versioning** for story flags; `persistentFlags` already exists.
- **Literacy** as a small integer in the save (`glyphsKnown`) driving margin-line visibility.
- **Finale state.** The final state of the world is a flag (`ending_answer` or `ending_turn`) that the island's renderer reads (lamp on or off, beam fixed or leaving, Refraction pockets drifting). Reversible only by New Game.

**Known defect found while planning.** The user's saves show journal pages 2 and 3 only, even after solving the Glass Wood puzzles, so Oren's pages 5 to 8 and the early pages 1 and 4 were never collected. The code reveals them correctly, so the likely cause is that they are small and easy to miss with no cue when one appears. Sent to the builder as a P0 addition to F02 (2026-10-25). **Hard requirement for all story content: a page on the critical path must be impossible to miss** (size, glow, sound, a banner, an unread marker).

## 9. Decisions for the user

1. **The lighthouse's purpose.** A (Chain of Lights, recommended), B (Archive), C (Lock), or your own?
2. **The shared event.** Is the Long Fog and the lost teacher the right shape of backstory? Names (Maren is a placeholder)?
3. **The choice mechanism.** M-A (two ways to finish the tuning; recommended), M-B (the Long Fog as the final puzzle), or M-C (two lanterns)? And do you want a **hidden reconciling ending** (M-B) in addition to the two, or strictly two?
4. **How many Refractions.** The roadmap has three new worlds plus a finale (about three to five long builder sessions each). Fewer (stop at the Salt Flats and make that the finale) or more?
5. **Shadow-play tableaux** (silhouette scenes at lit lanterns): yes, no, or try one and see?
6. **The contradictions notebook** (a deduction layer, optional for the player): yes, or keep the journal as reading only?
7. **The gate** on the final choice (N pages from each sibling plus one resolved contradiction): is that gate right, or should the choice be open from the moment the player reaches the finale?
8. **Revisions R1 to R4** in section 7.

## Sources

1. [Myst, Wikipedia](https://en.wikipedia.org/wiki/Myst) and [Red Book, D'ni wiki](https://dni.fandom.com/wiki/Red_Book) (endings and the brothers; wiki and forum sources agree on three endings; later games retcon the brothers' fate [Myst IV note])
2. [Riven, Wikipedia](https://en.wikipedia.org/wiki/Riven) and [Myst (series), Wikipedia](https://en.wikipedia.org/wiki/Myst_(series)) (Gehn, Atrus, Catherine; the trap book)
3. [Return of the Obra Dinn, Wikipedia](https://en.wikipedia.org/wiki/Return_of_the_Obra_Dinn) and [GameSpot feature](https://www.gamespot.com/articles/best-games-of-2018-return-of-the-obra-dinn/1100-6463891) (fates confirmed in sets of three; no developer postmortem was found in these searches)
4. [Edge review of Outer Wilds](https://www.pressreader.com/australia/edge/20190620/282278141843961) and [Wireframe review](https://wireframe.raspberrypi.com/articles/outer-wilds-review-death-and-translation-in-the-final-frontier) (knowledge as progression; ship log; rumour map as a reviewers' description)
5. [Game Developer, Road to the IGF: Heaven's Vault](https://gamedeveloper.com/business/road-to-the-igf-inkle-s-i-heaven-s-vault-i-) and [Emily Short's review](https://emshort.blog/2019/07/23/heavens-vault-inkle/) (translations are not confirmed; story responds; some reviewers call it a cipher)
6. [Critical Play: What Remains of Edith Finch](https://mechanicsofmagic.com/2024/05/02/critical-play-what-remains-of-edith-finch-14/) and [Press Start review](https://press-start.com.au/reviews/pc-reviews/2017/05/01/remains-edith-finch-review-exploration-death-depth/) (one vignette and mechanic per family member; reviewers' reading that mechanics mirror inner lives)
7. [The Talos Principle, Wikipedia](https://en.wikipedia.org/wiki/The_Talos_Principle) and [Giant Bomb blog analysis](https://giantbomb.com/profile/nintendoeats/blog/) (the tower choice; ending as a test of independent thought is one reader's interpretation)
8. [Game Informer: Rand Miller on Obduction](https://www.gameinformer.com/games/obduction/b/macintosh/archive/2013/11/08/cyan-s-rand-miller-on-obduction-and-keeping-it-mysterious.aspx) and [Voices of VR #432](https://voicesofvr.com/?p=3474) (puzzles built into history, culture and environment)
