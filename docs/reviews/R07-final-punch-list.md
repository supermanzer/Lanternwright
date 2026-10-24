# R07: final punch list (the reviewer's last round)

Reviewer method: rendered `stone-close`, `gw-court`, `gw-arrival`, `lh-door` after R06. R06 landed very well: the Worley cobbles read as real stones, the carved glowing glyph grooves have depth and a halo, the paper page has character, the arch has real voussoirs, the crystal trees have faceted trunks with prism crowns and a glowing vein, the Glass Wood path and altar read as inlaid stone. What remains is small. Same rules: triage into TASKS.md, before/after frames, revert parts with no visible gain, selftests and bots green, commit, INSPECT.md updated.

Conifers: the user has NOT decided yet (an earlier note here wrongly treated a suggested prompt as their decision). Default: leave the stylised conifers as they are, do not build needle-level trees, and keep the stylised-vs-needle question open in INSPECT.md for the user to answer.

## Small defects visible in frames

1. **Hairline vertical seams above the door arch** (`lh-door`): two thin black vertical lines run up the render above the arch crown (near x = 760 and x = 918 at 1600x900). They look like cell-boundary seams in the upper shaft's pattern. Find the source and remove it.
2. **Smeared patch beside the left strap hinge** (`lh-door`, about x = 500, y = 540): a blurry ghost rectangle on the jamb. Probably a hinge leaf with a depth-bias or shadow artefact; check and fix or remove.
3. **Glass Wood panes are still flat emissive rectangles** (you noted this; `gw-court`, the white and blue standing panels). Give them the same standard as the mirrors: a frame, a glass body with a visible edge and slight thickness, a tint that reads as coloured glass (refractive pass if affordable), and a base plinth with a state marker. Puzzle hooks unchanged.
4. **The mirrors show only the sky.** That is correct physically, but in the player's first view of the puzzle they read as dim grey panels. Add a faint, deliberate cue that they are mirrors (a thin bright edge catch, or a soft moon reflection when the angle allows), without changing puzzle behaviour.
5. **Leftovers you already listed as partial, in priority order:** copper roof dark patches (use a dim roughness-biased sky tint as the reflection fallback, which I suggested in R04 and you did not try); wading splash sound (the drag exists, add a splash/slosh using the new step engine's grain layer, wet and low); the iterative sliding collision from B7 if it is a small change. Skip the rest.

## Review status: stopping point

After this punch list the reviewer will not issue further rounds unless the user asks. Reasons, applying the user's stopping rule honestly:
- Gameplay, sound and world ideas were exhausted in rounds 1 to 2; the remaining questions (is the puzzle fair, how do the footsteps and drone feel, are the glass chimes solvable by ear, the story ending) need a human playing the game.
- The graphics findings have narrowed from structural (blocks, plastic, uniform rows) to a handful of seams and polish items. The remaining larger differences are art-direction choices that belong to the user: stylised vs needle-level conifers (still open; default stylised), how thick the haze is, how dark the shade is, how bright the mirrors should be.
- Further suggestions of the kind still available (photoscanned assets, ray tracing, a volumetric cloud solver, MSAA with a re-plumbed multi-pass pipeline, a moving sun, FFT ocean) are exactly the ones this project has already rejected as detrimental to its pillars or hard rules, and most of what is left would trade complexity for invisible gains.
