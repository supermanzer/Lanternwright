# R10: after F01 (frames: dock, shore, lh-base, overview)

Landed well: the dock now reads as old boards (varied width, tone, warp, end grain); beach litter sits on the sand; rocks are no longer icospheres; the beam, locked door and journal tab are fixed. Bundle is current (13:49). Remaining defects, all visible in frames:

1. **Lighthouse masonry still reads as ceramic tile** (`lh-base`). Every block has the same bevel, the same dark rim, the same flat face, and the courses are dead straight with uniform joints. Real ashlar has: slightly different block heights per course, joints of varying width, faces that are slightly proud or recessed (a per-block height offset that the shading sees as a soft step), chipped arrises (the rim breaks up, not a clean outline), and rain-washed vertical streaks below ledges. Drive bevel width and depth from a per-block random so some arrises are sharp and some worn. The plinth steps have visible overlapping slab edges at the corner: check they are intentional.
2. **Grass in `shore` is still a flat green felt with scattered specks.** The specks are the new micro-detail but there is no mid-scale variation (patches of different height, clover, bare earth, drift lines). Add a low-frequency patchiness (two or three noise bands at 2 m, 8 m, 30 m) to albedo and to blade length, and a darker earthy tone in hollows. Also the grass/sand boundary should be a ragged ecotone, not a clean line.
3. **Dock**: from a distance the boards are good; the two near posts and the cleats are still smooth, rounded, orange-brown shapes. Give the post tops end-grain splits and a weathered grey, and darken them where they meet water.
4. **Ground on steep faces at 0.3 m reads mud-cracked** (builder's own note). Reduce crack contrast on slopes above ~30 degrees, or blend toward the scree layer there.
5. Carry-over the builder listed as not done: shared `weather()` function, per-object seeds, islet ground, prop-gallery sheet, three flagged flat props (arrival plate, buoy, lens sphere). Do the islet ground and the three flat props; skip the rest unless cheap.

Frame cost is +0.3 to +1.6 ms; keep new work inside +0.3 ms or trim something earlier (grass tuft density first).

Stopping note: after this, further rounds are mostly art direction (user decides). The four open questions are in INSPECT.md. Run `scripts/bundle.sh` at the end and commit.
