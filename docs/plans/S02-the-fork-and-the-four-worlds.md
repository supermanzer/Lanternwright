# S02: the fork, and four more worlds (supersedes S01 sections 2, 4, 6 and 9)

Decided by the user on 2026-10-25, answering S01:
1. **The lighthouse's purpose is the Chain of Lights** (S01 option A): each lantern is a fixed point holding a pocket of world in place, and travel through the lens is a side-effect of a lantern being tuned to a pocket.
2. **The Long Fog and the lost teacher** are the backstory (S01 section 3). The teacher's name Maren is still a placeholder.
3. **The choice is how the player advances after the Glass Wood**, not a finale menu. On returning to Varrow after solving the Glass Wood, there are two ways out: **the Lighthouse (Ilse's story)** or **a portal on the dock (Oren's story)**. Both lead to the same worlds, but the chosen exit decides **whose perspective** the player meets each world through.
4. **Four more worlds**, each revealing more of the siblings' character and motivation.
5. **Shadow-play tableaux: yes.** 6. **The Contradictions notebook: yes.** 7. **The gate: yes** (both siblings must have been heard before the fork). 8. **Page revisions R1 to R4: approved** (S01 section 7; drafts in the appendix below).

S01's research, sibling profiles and Long Fog backstory stand. Its choice mechanisms M-A, M-B and M-C are replaced by the fork below, and its roadmap by section 3.

## 1. The shape of the game

```
Act I   Varrow (done) ─ lamp, three stones, lens ─► Glass Wood (done, Oren's first world) ─► return
The Return   Varrow changes; the gate is checked; TWO exits appear
           ┌─ the Lighthouse door answers  ──► Ilse's perspective ─┐
           └─ the dock portal turns open   ──► Oren's perspective ─┤
Act II  Tide Archive ► Salt Flats of the Two Lamps ► The Drift ► The Lamp at the End of the Chain
        (same four worlds either way; each is met through the chosen sibling's eyes)
```

**Hub.** Varrow stays the hub: the player can return between worlds. The exit not chosen is **sealed for good** (user decision): the lamp has answered, or the portal has turned, and the other cannot be undone. It stays visible, so the player knows what they did not take, and the only way to take it is to start a new game.

## 2. The fork

### 2.1 The gate (user-approved)
The two exits appear only when **all** are true: the Glass Wood altar is solved; the player has collected at least **3 of Ilse's pages and 3 of Oren's** (pages are tagged by author); and at least **one Contradiction** has been resolved (section 4). If something is missing, a quiet cue says what kind of thing (for example "You have heard only one of them"), never a quest marker.

### 2.2 The Lighthouse (Ilse's exit)
The door that has been locked since the start ("The keeper took the key with her", which worked as a mystery and should now pay off) **opens by answering, not by a key**: three tone plates beside the door (tide, wind, stone) must be struck **in order of altitude and held until the lamp answers**, as Ilse taught. The door opens onto the **lighthouse interior for the first time**: a stair, her workshop, and at the top the lens room with the lens ring and the lamp. Entering the lens room and touching the lens ring begins Ilse's route. Interior content is new work (stair, workshop props, lens room, the lamp mechanism, collision, lighting, audio).

### 2.3 The dock portal (Oren's exit)
A freestanding arch at the end of the dock, dormant since the start (visible from the first frame, unexplained). It opens when the player **turns the lighthouse's sweep beam onto it**: two or three mirror stands on the shore (Glass Wood skill) redirect the beam to a receiver on the arch. Stepping through begins Oren's route.

### 2.4 After choosing
The choice is saved (`path_ilse` or `path_oren`). The player may still walk Varrow, read all pages and use the Contradictions notebook. **After the ending the game invites the player to start again** and make different decisions (user decision, 2026-10-25). There is no Second Reading mode and no carry-over: the invitation is a quiet closing line and a New Game option, and the choice is sealed for good in a playthrough (section 6).

## 3. How "perspective" works (same worlds, different eyes)

Cost control: the **geometry and puzzle logic of each world are shared**. Perspective is five cheap-to-moderate levers, all procedural:

1. **Arrival and first sight.** Ilse's route enters each world at the **lamp end** (where a lantern still burns and you see the pocket as something fragile to be held); Oren's route enters at the **open end** (where the pocket's edge looks like a road). Same place, different first view.
2. **Narrator.** Each world holds new pages **in the chosen sibling's present-tense voice** (the main journal for that route), and the other sibling's traces appear as found objects the narrator interprets. Ilse reads Oren's chalk marks as worrying; Oren reads Ilse's rule-plates as walls she built.
3. **Whom you follow.** The same event reads in opposite directions. On Ilse's route you **follow Oren's lantern** at a distance, always a little ahead (her account: "he left me"). On Oren's route you **follow lamps Ilse left lit for you**, one at every stand (his account: "she would not follow", yet the lamps are there). Neither can be reached; they are guides, not characters.
4. **Tools.** Ilse's route gives the **tuning fork** (play and hold a tone to open or keep a gate); Oren's gives the **turning lens** (redirect and split beams). **Each world has one key puzzle with two valid solutions**, one by held tones and one by turned light. The chosen tool makes its solution the obvious one; the other is discoverable and, if found, teaches the other sibling's way (and counts toward the optional ending, section 5).
5. **Mood.** Drone key and tint: Ilse's route is warm amber lamp-light and a steady, patient drone built on the stone tones in ordered pulses; Oren's is cool glass-white and a drifting drone that modulates between the same tones. All pitches still come from `ToneTable` (pillar 5), and each world still has its own base tones (the user's F02 answer 2).
6. **Shadow-play tableaux** (user-approved): a lit lantern casts a flat silhouette scene on a wall. **Each tableau is the same remembered moment seen from each sibling's side** (the same night, with the two figures in different places and different postures), so the route determines which version appears first, and the other can be seen by lighting the lantern from the other side. Flat cut-out meshes and light only: no voice, no animation beyond a slow shift.

## 4. The Contradictions notebook (user-approved)
A third journal tab. It lists claims that conflict ("Hers: I left her." "His: she would not follow."), each tied to physical evidence found in the worlds (a tide table, a boat log, two sets of footprints, a scorched lantern stand). The player sets which claim the evidence supports. The game **confirms only in groups of three** (Obra Dinn) and never marks a single answer, so guessing does not work and nothing is punished. Resolved contradictions unlock margin lines (in glyphs, see Literacy) and change a sentence in the epilogue. It is optional depth except for the gate's one resolved contradiction.

**Literacy** (Heaven's Vault lesson): the player learns more glyphs (answer, carry, hold, turn, chain), driven by an integer `glyphsKnown`. Earlier pages gain margin lines when the player understands more.

## 5. The four worlds

Each has **one optical or tonal property**, one **key puzzle with two solutions**, and a **beat for each perspective**. Honest about scope: each is about the size of the Glass Wood.

| # | World | Property | Ilse's route (arrive at the lamp end, follow Oren's lantern) | Oren's route (arrive at the open end, follow Ilse's lamps) | Reveals |
|---|---|---|---|---|---|
| 3 | **The Tide Archive**: a flooded ledger-observatory | **Dispersion** (a prism splits one beam into tide, wind, stone) | Her sanctuary: ledgers, the Roll of Keepers, the chain drawn as a map; she logged every lantern's pocket. | The same ledgers read as a cage of rules; he finds his own lantern recorded as "lost". | What a Lanternwright is, the guild and its charter, **the chain** shown as a map for the first time, and the lighthouse's real purpose. |
| 4 | **The Salt Flats of the Two Lamps** | **Interference** (two beams in phase brighten, in antiphase cancel) | Her lamp stand, a rule scratched into it; evidence of the night she dimmed the lamp. | His lantern stand, scorch marks; evidence he saw the boat and did not turn back. | **The Long Fog reconstructed** from physical evidence; first strong Contradictions. |
| 5 | **The Drift**: a pocket that has come loose | **Absorption / polarisation** (only some light passes; navigation by tone alone) | Why a lamp must answer: a pocket drifting because its keeper stopped. | Why a lantern must carry: the way out exists only if someone goes first. | What happens when a lantern goes out; the teacher's fate (decision 3, section 6). |
| 6 | **The Lamp at the End of the Chain** | **The final tuning**, needing Ilse's order and Oren's turn together | The chain's last stand where she would hold. | The chain's far end where he would walk on. | Truth of the Long Fog, what it means to be the last Lanternwright, and the ending. |

**Difficulty ramp.** The slice taught one order. The Glass Wood added reflection. The Tide Archive adds time (tide levels) and a held tone; the Salt Flats two simultaneous systems; the Drift removes the hints the player has come to rely on (darkness, tone only); the finale asks for both skills together. Observable cause and effect always: a failed attempt changes something seen or heard.

**Endings (decided):** three, and the player is told about only two. The chosen sibling's perspective determines the epilogue world state and the closing page, which is written by the **other** sibling and reveals what they omitted. A **third, reconciling ending** exists and is deliberately **not obvious or clear right away** (user decision): it is drafted in section 8. It is a consequence of how much the player understood, not a trap, and it must not make either chosen path feel wrong.

## 6. Decisions (all answered by the user, 2026-10-25)
1. **Replay:** after the ending the game invites the player to start again and play with different decisions. No Second Reading mode.
2. **Endings:** two routes plus a reconciling third that is **not obvious or clear right away** (section 8).
3. **The teacher (Maren):** **left ambiguous.** The Drift must show a pocket with a lantern still faintly burning and no conclusion: no body, no voice, no confirmation either way. Every account of her fate is a belief, never a fact.
4. **Exits:** the unchosen exit is **sealed for good**; the player must replay to choose differently.

Still open: nothing blocking Phase 1. Section 8's details (the third ending's clues) are drafts for the user to react to.

## 7. Build order (phases; one plan per phase; each ends with a playtest by the user)
**Phase 1 (ready for the builder after F02): story infrastructure and the fork.** Data-driven pages with author tags; journal tabs (Ilse, Oren, Notebook) and unread markers; `path_*` and `glyphsKnown` in the save; the gate; the **Lighthouse interior** and the **tone-plate door**; the **dock portal** and the **beam-turning receiver**; the two route entries into the existing Glass Wood world reused as a placeholder destination so the fork is testable now; revisions R1 to R4 and the early Ilse page; the Contradictions notebook with two or three contradictions already available from existing pages; reachability bots for both routes; save-version bump. No new world yet.
**Phase 2:** The Tide Archive. **Phase 3:** The Salt Flats. **Phase 4:** The Drift. **Phase 5:** The Lamp at the End of the Chain and the endings. Each phase gets its own plan written by the reviewer after the user plays the previous one.

**Hard requirements for all story content:** pages may be overlooked (user, F03 #43: "pay attention to details"), so no critical path may require every page: the gate asks for 3 of each author and says what is missing (superseded 2026-10-28; see S03); no cutscenes, no voice, no external assets; no fail state; the existing eight pages are canon plus the approved revisions; both siblings are defensible, each right about something and wrong about something; story reachability is a selftest.

## 8. The reconciling third ending (APPROVED in approach by the user, 2026-10-28; details still drafts)

**Principle.** No menu, no marker, no page that says it exists. A player on either route can finish the game without ever suspecting it. It is found by *noticing*, which fits fair mystery (every clue is in the world, near where it is used), and it is not the "good ending": it has its own cost, and the two sibling endings stay fully valid.

**What it is.** At the Lamp at the End of the Chain two stands are tuned an interval apart: Ilse's stand (patient, in order) and Oren's (turned, reflected). Each ending is completed at its own stand. The third ending is completed **between them**: the two tones played together make a third tone that neither stand makes alone (the interference property from the Salt Flats, a **beat** that only exists when both sound). The chain is then tuned by both siblings' ways at once.

**Requirements (all silent):**
1. **Both ways known.** The player has solved the *other* sibling's solution in at least three of the four worlds' key puzzles (the optional second solutions of section 3, lever 4). On Ilse's route, that means having turned light; on Oren's, having held tones.
2. **The three Long Fog contradictions resolved** in the Contradictions notebook toward "neither was at fault: they were apart" (the three-at-a-time confirmation applies).
3. **Noticing the place.** The midpoint between the stands is marked only by sound: standing there, a faint third tone beats against the drone. The player has been trained to listen for beats in the Salt Flats and the Drift, and the shadow-play tableaux of the Long Fog show the two figures' lamps overlapping once. No prompt tells the player to stand there.

**The cost (so it is not a "best" ending).** The chain holds *and* it can carry, but only as far as two keepers can walk and only while two keep it: neither sibling can leave the other again, and the player, having shown how, is the third who must keep the pair's lamps. The closing page is written by both siblings, in two hands, and says what each gave up. The epilogue world state shows both lamps lit and a path that leads nowhere in particular.

**Risks and checks.** (a) A player who never finds it must still feel the two endings are complete: so nothing in them mentions it. (b) It must not become a walkthrough meme with no weight: the cost keeps it a choice. (c) Selftests: the third ending is reachable from a save that has met all requirements and unreachable otherwise; the beat tone exists only when both stands sound.

## Appendix: drafts for the approved page revisions (for the user to edit)
- **Page 5, new first sentence (R1):** "The week before the fog, I went through the lens first."
- **New page 9, Ilse, on the dock (R2):** "Rule the first: keepers do not run on the shingle. Rule the second: keepers run when the lamp is going out. I have broken the second only twice, and I would break it again."
- **Page 4, added half-line (R3):** after "He did not answer, and I did not like the silence," add "I told him the lens room is not a place for the impatient, which is not what he asked."
- **Page 8:** unchanged.
