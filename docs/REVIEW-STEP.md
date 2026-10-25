# Per-task review step

Every task gets an independent review by a separate agent before its box is ticked. The reviewer has not seen your reasoning, so the brief you give it has to stand alone.

## When
After the build is clean and your own verification (selftest, frames) is done, and **before** you tick the box or write the `> done:` note.

## Who
Spawn the `task-reviewer` agent (`.claude/agents/task-reviewer.md`). If that agent type is not available in your session, spawn a general-purpose agent and paste that file's body as its instructions. One reviewer per task, fresh each time.

## The brief (all five parts are required)
1. **The task, verbatim:** the full text of the TASKS.md entry, including its Accept line and listed files.
2. **Where it fits:** the path of the plan or review it comes from (for example `docs/plans/F02-second-playtest.md`, or `docs/reviews/R10-...`), the section or item number, and two or three sentences on what that section is trying to achieve and why. Name the tasks before and after it that depend on it.
3. **What you changed:** the commit range or the list of changed files, and what you believe each change does.
4. **How to verify:** the exact commands and views that exercise it (`--selftest`, `--screenshot ... --view ...`, any measurement flag such as `--shimmer` or `--parallax`), and the numbers or look you expect.
5. **Constraints to hold it to:** the hard rules in CLAUDE.md, plus any acceptance numbers or user-stated requirements in the plan item (quote them).

Do not tell the reviewer your conclusion ("this passes"). Give it the evidence to find out.

## What happens with the verdict
* **PASS:** tick the box and write the `> done:` note. Add one line: `review: pass`, plus any optional note worth keeping.
* **CHANGES NEEDED:** fix every numbered item, re-run your verification, and send the **same** reviewer a follow-up (SendMessage) saying what changed. Repeat at most twice. If it still fails, or you disagree with an item, stop, leave the box unticked, write the disagreement in the `> done:` note as `review: unresolved - <item> - <your reason>`, and carry on to your report so the human reviewer sees it.
* Never tick a box over an open required change.

## Scope
The reviewer judges this one task against its plan. It does not re-open design decisions the user has made, and it does not ask for extra features. Larger observations go in its optional notes and into your report, not into the task.
