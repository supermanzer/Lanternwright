# F05: fifth playtest (notes #60 to #68)

Source: `Lanternwright --feedback` #60-#68 (2026-10-29). First S03 playtest: the user could not get into the lighthouse and could not take the door note. **Priority: B's items first (the story is blocked).** Same rules as before (frames Read, selftest 0 FAIL, review step, commit by path, tag `f05-done`, bundle in the integration checkout).

| # | Note | Item | Owner |
|---|---|---|---|
| 67 | Door note cannot be read; clicking it opens the Notebook showing "a page missing"; the gate blocks progress | S1 | B |
| 64, 66 | "Two accounts" notebook section unclear; aligning accounts is clumsy; text crowded | S2 | B |
| 65 | Unclear that returning to the first world is necessary | S3 | B |
| 60 | Waterline: a dry sand line moves toward the shore while water still covers the sand above it | W2 | A |
| 61 | Water rings stay permanently in place around the dock | W3 | A |
| 62 | Downed tree does not support its weight: remove it | R1 | A |
| 63 | Door rattle sound is "a computer alert", research wood/stone/steel | A1 | A |
| 68 | Parts of the quay float in the air | Q1 | A |

## S1 (#67): the door note and the gate (B, first)
The user's state: pages 1,2,3,4,6,7,8,9 (page 5 missing), altar solved, `lensTouched`, looking at `door_note`. Findings to verify: the note is the very thing the plan said must be an ordinary readable object (USER DECISIONS 2: "readable with the same interaction as a page"; "not a page, does not count towards the gate"); instead interacting opens the Notebook. Fix: the door note opens a small reading card with `Story.doorNote`, and is also logged as a Notebook line; it never routes to the contradiction. Then **the contradiction no longer gates the door**: gate = altar solved + 3 pages of each sibling (the user's decision, S03 USER DECISIONS 4); the contradiction becomes an optional notebook feature with no gating (log in OPEN-QUESTIONS; reversible with one constant). Check that with the user's exact save (pages above) the tone plates are solvable and the door opens; make the nav-audit/bot do it from a save with those pages. Make the plates legible: when the gate is not met, the lamp/plates say so quietly; when it is, something tells the player the plates answer (the answer phrase), as designed.

## S2 (#64, #66): the notebook
Remove the "aligning accounts" interaction from the critical path. Keep the notebook as a place the player writes nothing in: if the contradiction stays, simplify to one tap per page (Hers/His) with plain spacing, a heading line that says what it is ("Two accounts of the same night. They disagree. Which page is whose memory?") and no penalty timer. Less text, more space. Judge by a frame at 1600x900 and 2560x1440.

## S3 (#65): return is necessary
After the altar is solved the player must be told, without a prompt, to go back. Candidates (pick one, cheap first): a journal line "The lamp is waiting." appearing at the Glass Wood exit; the Glass Wood return pad lighting up; the lighthouse beam visible from the Glass Wood sky (the beam signal toward the portal). Log the choice in OPEN-QUESTIONS.

## W2, W3, R1, A1, Q1 (A)
W2/W3: diagnose from the screenshot positions; the wet/dry line must advance and retreat monotonically per wave (no dry line inside a wet region), and ripple rings must decay and travel, never persist. R1: remove the downed tree (prop, collider, nav, selftests, PROPS audit). A1: redesign the door rattle: layered, low and short (wood on stone knock 80-300 Hz body, iron ring clank with inharmonic partials 1-4 kHz and fast decay, no pure tones, no beeping), compare spectra in a selftest (no tone above 6 dB over its neighbours). Q1: find the floating quay parts from the screenshot (position -38.5, 3.2, -262.7) and ground them.

## S4 (user question after #68: "unclear where page 5 is found") — B, after S3
Page 5 lies at the Glass Wood arrival pad and is easily overlooked (by design, F03 P1). Add a quiet, spoiler-free cue: in the journal, an empty slot per page not yet found, labelled only with its world (Varrow / Glass Wood) and the author's side, no location. No quest marker. Pages stay overlookable. Also consider whether page 5's spot should be moved a few metres onto the first path from the pad (still one object, still overlookable); log the choice.
