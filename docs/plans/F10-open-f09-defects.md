# F10: defects left open by F09 (reviewer frame review 2026-11-14)

Main 62c89be: selftest 0 FAIL, bundle 20:25 after HEAD 20:21. Reviewer read the F09 frames in `../lanternwright-b/shots/f09/`. The build is NOT ready to play because of the first two items.

## Builder A (`Render/**`, `World/**`, `Audio/**`)
1. **The strait does not look deep (note #112 again).** `shots/f09/strait.png` (from the shore, B's own finding): the channel is physically deep but the water is the same light teal as the shallows, so it still reads as wadeable. Give the sea depth-based absorption: colour and transparency from the water column (sea level minus seabed height, Beer-Lambert style, red absorbed first, a darker green-blue past ~1.5 m, the seabed no longer visible past ~2 m), so the strait reads dark and the shelf near the shore reads pale. Check the shallow rim, the dock and the Archive's water are not darkened wrongly; frame hashes may change on purpose, list which. Judge by `--screenshot` from the shore, the dock and the causeway; Read them. Selftest: a probe at 0.3 m and at 2.5 m depth differs in luminance by a stated factor.
2. **The return/portal ring is blown out and faceted.** `ta_return_ilse.png`: the ring and the disc are flat white (no gradient, no rim) and the disc's silhouette is a visible polygon. Lower the emissive so it reads as brass or glass lit from within, give the disc a soft radial falloff (or enough tessellation), keep it visible at the quay distance. Same look for `ta_return_oren`, the quay lenses and the lens-portal halo in Varrow.
3. **P02.4 charge meters** (`docs/plans/P02-puzzle-restructure.md`): a soft light that grows on the lens-room receiver and the prism's mark while the 2 s hold runs, and fades when broken. The hold logic is B's; A adds only the emissive channel and a uniform B can set.

## Builder B (`Game/**`, story)
1. **P02.0**: `PuzzleGraph` data and metric selftests (P02 section 2.3). Load today's puzzles, report the metrics and every rule break, fix nothing yet. Output a table in `docs/plans/P02-graph-report.md`.
2. **#111 turning back:** F09 left "turning the ring back should dim that panel" undone (an opened gate stays open and lit, which is acceptable as a puzzle state); decide: keep as is and say so in the done note (default), or dim only the prism's component, never the gate.
3. **A's flag:** audit the guide lantern and guide lamps' route points against closed sluice gates (a path point must never land inside a closed gate's collider). Add the check to the interactable/guide selftests.
4. B's sluice-room pits push off-centre players up to 0.45 m/s (your F09.3 finding): fix if cheap (the pits are the only source), else Q.

## Process
Branch from origin/main (`a/f10`, `b/f10`), selftest 0 FAIL, shader validation clean, ff-merge under the `merge` lock, push, tag `f10-a` / `f10-b`, rebundle, INSPECT rows, new Qs from Q54. Do not ask the user to play. End with Blocked on me / Changed / Found.
