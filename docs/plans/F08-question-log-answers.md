# F08: the user's answers to the Question Log (2026-10-31)

Source: the Question Log artifact (decisions stored per Q-id). Main at 5291f15 (`s04-done`).
Owner: builder B (story, lighthouse interior, lens room). Builder A only if a Render/** change is needed.

## Confirmed, no work (record in OPEN-QUESTIONS.md as "User: keep")
Q5 keep (EDGE_K 1.0) · Q15 keep (page 9 stays on the dock, counts for the gate) · Q17 accepted (far-field fade is enough) ·
Q30 keep (grass LOD ships OFF) · Q25 works (run 5.5 m/s, hint gone) · Q20 keep ("The lamp is waiting." + brighter ring) ·
Q6 works (door note) · Q9 works (plates) · Q23 makes sense (quiet cues) · Q10 okay (interior brightness, lampPower 0.85) ·
Q27 works (rail, page wording) · Q14 **every return** (matches the default: no change).

## Work

### F08.1 The fork must say WHOSE route a click begins (Q11, Q24) — priority
User: "this works but it is not clear which sibling's choice you are making" (Q11) and "this could be more clear" (Q24).
Today: warm beads ring the lens (Ilse), cool rim frames the receiver (Oren), no words; the choice is irreversible (the other exit dims for good).
Default to take (log as a new Q35, do NOT block): attribute each exit to its sibling by what the player already knows of them.
1. **Hover prompts name the sibling.** Lens: "Ilse's way: touch the lens". Receiver/portal: "Oren's way: step into the light" (match the exact existing interaction wording; only prepend the name). Prompts show only when the gate is ready and no route is chosen.
2. **Each exit carries its sibling's motif**, already established in the world: Ilse's = her pages' ink colour / lamp-tone motif; Oren's = his pages' hand and the tide/glass motif. Reuse existing materials/colours from the Notebook tabs so the link is learned, not told.
3. **Confirm-by-consequence, not by dialog:** keep "no text banner" (Q12). The first touch of the lens/glass may still be the commit (no modal), but the prompt in (1) is the warning.
4. Update `docs/plans/S03-player-path.md` verdict for the fork step; add a bot assertion that the prompt strings contain the sibling names only in the pre-choice state.
Definition of done: a fresh player reading only the prompts and seeing the two exits can say which sibling each leads to. Render a frame of each exit (`--screenshot`) and Read it before claiming done.

### F08.2 Lighthouse interior less cramped (Q8)
User: "a little cramped but it works". Q8 default: stair ~1.3 m wide, six turns, lens room tight by design.
Default to take: widen the stair to ~1.6 m and the round ground room/ceiling clearances by ~10-15%; keep the lens room's "reach the ring, not walk round it" intent (do NOT widen the lens room's floor; the rail stays). Re-run the reachable-region audit, the stair walk bot, collision/step tests and the light-model check (lamp spacing may need re-placing so Q10 brightness stays "okay"). Constants live at the top of `LighthouseInterior`.

### F08.3 Page 9 findability (Q18) — note only
User could not find one Varrow page (the new page 9 at the dock's seaward end) but is glad the gate no longer locks. They previously asked for findability aids to be reverted (#43), and the gate needs only 3+3 pages with the contradiction waived, so **no code change**. Record in OPEN-QUESTIONS.md; if a later playtest shows the same problem, the cheapest aid is a lantern or a lighter ground patch near it.

## Process
Standing rule: never block on the user; log defaults in docs/OPEN-QUESTIONS.md (Q35 for F08.1, Q36 for F08.2), proceed. Worktree ../lanternwright-b, rebase onto main, selftest green, shader validation clean, ff-merge, push, tag `f08-b`, rebundle. End with **Blocked on me / Changed / Found**. Say when the build is final and what the user should look at (the fork prompts and the stair) per the playtest-timing rule.
