# S03.10: the page revisions that were applied (user decision 6, 2026-10-28)

The user approved S02's appendix drafts R1 to R3 and asked for them to be applied as data with pinning selftests. Page 3 stays exactly as restored in F04 T1 and page 8 is unchanged. Source of truth: `Game/StoryPages.swift`; the pins are SHA-256 prefixes in `SelfTests/SelfTestStory.swift` (plus the spelled-out R1 to R3 checks there and the page 3 literal in `SelfTestPages`). To change a page again: change the text, change its pin in the same commit, and say so in the commit message.

| Id | Draft | Before | After |
|---|---|---|---|
| 5 (Oren) | R1: new first sentence | "I went through the lens first. Ilse will say I stole it, ..." | "**The week before the fog, I went through the lens first.** Ilse will say I stole it, ..." (the rest as before) |
| 9 (Ilse), new | R2: a new page on the dock | (none) | "Rule the first: keepers do not run on the shingle. Rule the second: keepers run when the lamp is going out. I have broken the second only twice, and I would break it again." |
| 4 (Ilse) | R3: an added half-line | "... He did not answer, and I did not like the silence." | "... He did not answer, and I did not like the silence. **I told him the lens room is not a place for the impatient, which is not what he asked.**" |
| 3, 8 | unchanged | | |

Notes: the appendix says to add the half-line "after 'He did not answer, and I did not like the silence,'" but the sentence ends with a full stop, so the half-line follows the full stop. Page 9 lies on the boards at the seaward end of the dock, on the left-hand side (page 1 is 13 m from the landward end, on the right), one paper object, 2.6 m from the spawn and 27 m from page 1; it counts as an Ilse page (so Ilse has five pages and Oren four; the gate still asks for 3 of each, and the contradiction's evidence is pages 4, 5 and 8).
