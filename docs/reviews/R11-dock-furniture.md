# R11: dock furniture (frame: `--view dock-close`)

F02 G4 fixed the boards, which now read as sawn, weathered timber. The furniture on them did not get the same treatment. Four defects, all visible in `dock-close`:

1. **Mooring post is still a smooth faceted cylinder** with a plain cap, in the same orange-brown as new timber. This was R10 item 3 and is not done. Required: end-grain splits and radial checks on the top face, weathered grey toward the top, darker and greener where it meets the water, vertical grain streaks down the shaft, a slightly irregular silhouette (not a perfect prism: a lean of a degree or two, a worn cap edge). Use the same plank/grain material function as the boards so the two read as one timber.
2. **The rope coil floats.** It is a ring standing clear of the post on the water side. Required: the turns wrap the post and touch it (inner radius = post radius + rope radius), sit in slightly sagging helices rather than stacked flat rings, with a loose end hanging down. Rope needs a twist pattern in its albedo, not a flat tan.
3. **The cleat is a flat black slab.** Required: a horn cleat shape with two tapered horns, wood or iron with visible wear, seated on the plank (small bolt heads, contact darkening).
4. **Check TAA softness** in `overview` and `ground-trees`: the island looks hazy at distance. Render with TAA off and on at the same frame, compare, and say whether the CAS sharpen strength needs raising. Report the numbers, change only if the on-frame is visibly softer.

Not in scope: boards, planks, anything else on the dock. Budget +0.1 ms.

Acceptance: a frame of `dock-close` that shows the post with visible grain and a grey-to-dark gradient, rope touching the post, a recognisable cleat; selftest still green; the reviewer step run per `docs/REVIEW-STEP.md`. Run `scripts/bundle.sh` and commit at the end.
