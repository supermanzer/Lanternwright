# Git workflow for several agents

Remote: `origin` = https://github.com/supermanzer/Lanternwright.git. The user's standing instruction (2026-10-27): **at the end of each plan phase, commit and push.**

## The model: one worktree per agent, `main` is integration-only

```
~/Projects/games/lanternwright      branch main        INTEGRATION checkout: merges, bundles for the user. Nobody edits code here.
~/Projects/games/lanternwright-a    branch a/<topic>   builder A's worktree
~/Projects/games/lanternwright-b    branch b/<topic>   builder B's worktree
(reviewer scratch worktrees live in the scratchpad, detached, and are removed after use)
```

Why: agents sharing one directory step on each other (a `swift build` locks `.build`, `git add -A` sweeps up the other agent's half-edited files, a checkout changes files under a running build). Separate worktrees share one repository (one object store, one set of branches) but each has its own files and its own `.build`, so nothing can collide until the deliberate merge. The integration checkout stays clean, so it is always safe to build the user's playable app from it.

Create yours once: `git worktree add ../lanternwright-a -b a/<topic> main` (builder B: `../lanternwright-b`, `b/<topic>`). Builder A moves out of the integration checkout at its next pausing point: commit there, create the worktree from `main`, carry on in it.

## Branches and names
- `main`: always builds, `--selftest` 0 FAIL. Only fast-forward merges. Never force-pushed, never committed to directly (except docs-only reviewer commits).
- Work branches: `a/<topic>`, `b/<topic>`, one per plan stream or phase (`a/g10-stream1`, `b/m10-grass`). Short-lived: delete after merge. Reuse of one long branch for many phases is how branches drift; start the next from the new `main`.
- Phase tags on `main` when a phase is done and pushed: `f03-done`, `m10-done`, `g10-s0`, `g10-s1`... (annotated: `git tag -a g10-s0 -m "..."`).

## Commits
- Small, one task per commit, message `<plan id> <task id>: what and why` (as the log already reads). Add the attribution line the session was given.
- Stage by path (`git add Sources/... docs/...`), never `git add -A` / `git commit -a`, and look at `git status` and `git diff --stat` before committing. Do not commit generated files (`shots/`, `.build/`, `*.app` are ignored; keep it that way). `docs/shots/*` is ignored except the baseline text files that were added on purpose: add those with `git add -f` only when the plan asks for a committed baseline.
- Never commit with a failing `--selftest`. Gate the commit command on 0 FAIL.

## Integrating (at a pausing point)
1. `git fetch origin` then `git rebase main` in your worktree (rebase, not merge: a straight history is what makes `--ff-only` possible). Resolve conflicts only in files you own; a conflict in a file you do not own: stop and post to the agent board, topic `ownership`.
2. `swift build -c release` and `--selftest` on the rebased tree: 0 FAIL. For render changes, the byte-identical frame check where the plan demands it.
   *Optional, for any change that touches `Render/Shaders/**` or the MSL strings:* `scripts/validate-shaders.sh` compiles the whole Metal source (`.build/release/Lanternwright --dump-shaders <path>`, no device or window) with Xcode's `metal` through `DEVELOPER_DIR` (the default developer directory stays Command Line Tools: never `xcode-select -s`) and reports errors and the warning count (4 unused-variable warnings at `shaders-validate`). It is an extra check beside the selftest, not a replacement; it exits 2 and skips if Xcode's Metal toolchain is not installed.
3. Take the **merge lock**: post to the agent board topic `merge` "A merging <branch>"; if the last post there is an unreleased lock by someone else, wait. Then from the integration checkout: `git merge --ff-only <branch>`. If it refuses (main moved), go back to step 1.
4. `git push origin main` (and your branch: `git push -u origin <branch>`; after a rebase use `--force-with-lease` on **your own branch only**, never on `main`).
5. Release the lock (board post "merge done <hash>"). If it was a phase end, tag and `git push origin <tag>`.
6. Delete the merged branch: `git branch -d <branch>` and `git push origin --delete <branch>`.

## Who bundles the playable app
The user plays `Lanternwright.app` in the integration checkout. After a phase-end merge the merging builder runs `scripts/bundle.sh` *in the integration checkout* (clean tree, built from `main`). Builders never bundle from their worktrees into the integration checkout.

## Reviewer
Reviews the branch before the builder merges (frames, numbers, the soft-lock audit where relevant) and says "ready to merge" on the board; docs-only reviewer commits (plans, reviews) may go straight to `main` by path. Pull requests are optional: use `gh pr create` if the user wants a review trail on GitHub; the local rule above is the minimum.

## Safety
- Never force-push `main`. Never rewrite a pushed commit on `main`.
- Never delete a branch or worktree that has unmerged commits (`git branch -d` refuses; do not use `-D` without the user).
- Nothing secret goes in the repo (it is on GitHub). Feedback screenshots and the save file live outside the repo; keep it so.
- If anything about the repository looks wrong (a dirty integration checkout, a diverged `main`, an unexpected branch), stop and tell the reviewer.
