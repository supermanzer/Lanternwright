# R09: detail must arrive gradually, never suddenly (user requirement)

**This comes from the user directly.** The user's words: "Texture should not suddenly appear at a specific distance. It should be hinted at from further away and gradually reveal itself as you get closer."

This is a design rule for the whole renderer, not a tweak to one surface. Call it **continuous detail**: every layer of detail is present, faintly, at a larger distance than where it becomes sharp, and its contrast rises smoothly as the player approaches. No feature may switch on, switch off, or change character within a few metres.

Same rules as before: triage into TASKS.md, before/after evidence, selftests and bots green, commit at each pausing point, INSPECT.md updated, story ending left to the user. Frame budget +0.5 ms.

## What the code does now (from reading it)

Good: the materials in `Render/Shaders/Materials.swift` already band-limit by pixel footprint. `fpix` (metres per pixel, from `dfdx(P)`) drives `fadeBelow(fpix, a, b)` = `1 - smoothstep(a, b, fpix)`, and the comments say each feature fades to its average. That is the right mechanism, and because it works in footprint (not raw distance) it also adapts to render scale and look-closer zoom.

Likely problems (check each; some may already be fine):
1. **Hard LOD swaps for meshes.** Conifers and crystal trees have three LODs, "merged per 60 m cell and switched by eye distance" (`CrystalTrees.swift`, `GlassWood.swift`, the conifer equivalent). A switch is instantaneous and per **cell**, so a whole 60 m patch of trees changes shape at once. That is exactly the "suddenly appears" the user describes.
2. **Fade thresholds were tuned by eye, in absolute footprints, per feature.** For a 90-degree lens at 1600 px, `fpix = distance x 0.00125`. So `fadeBelow(fpix, 0.02, 0.08)` runs from about 16 m (full) to 64 m (gone), and `fadeBelow(fpix, 0.002, 0.01)` (paper fibre) from 1.6 m to 8 m. The ramps are smooth, but each is a narrow band chosen separately, and the hierarchy is not guaranteed: the coarse structure (block courses, plank joints) should still be hinted at 100 m or more, while only the finest grain (pits, fibres) should be limited to under 10 m.
3. **Anything with a hard radius**: the 40 m grass field, the pebbles, shells and driftwood clutter, the forest-floor litter, per-prop detail that is placed only near the player. Check each for a visible boundary.
4. **Detail that fades to nothing instead of to its average.** If an octave or a groove fades to zero while its mean contribution (average darkening from joints, average roughness change from grain) is dropped, the surface changes brightness or glossiness at the transition. This is the subtle kind of pop: a faint brightness or sheen shift where detail vanishes.
5. **Bump and roughness not tied together.** When the normal-detail fades with distance, the specular highlight gets cleaner and brighter unless roughness rises to compensate (the Toksvig / normal-variance idea: widen the roughness by the variance of the normals that were filtered out).

## The fix, in principle

**Scale-space hierarchy.** Give every material three tiers and make each one a function of *feature size / pixel footprint*, not of an absolute distance:
- **Macro** (metres to decimetres: block courses, plank joints, band weathering, colour patches, drip streaks): visible as a faint tint or line at 100 m to 300 m and growing in contrast as you approach.
- **Meso** (decimetres to centimetres: block faces, board grain, mortar width, cobble shapes, chips): hinted at 30 m to 100 m and fully sharp by about 5 m.
- **Micro** (centimetres to millimetres: pits, fibres, sparkle, fine grain): hinted at about 10 m to 20 m and sharp only inside a couple of metres.
Use one visibility function for every feature: `vis = smoothstep(lo, hi, featureSize / fpix)` with `featureSize / fpix` in pixels (about 0.5 px = invisible, about 2 to 4 px = fully resolved). That one rule gives gradual reveal for free, scales with FOV and render scale, and makes the ranges easy to reason about. Replace the per-feature magic numbers with the feature size where you can.

**Fade to the average.** Each feature's contribution is `mix(mean, value, vis)`, where `mean` is its average effect on albedo, roughness and ambient occlusion. Verify with a luma check that the mean colour of a surface patch stays within a small tolerance across the whole fade (see tests).

**Roughness follows detail.** As the bump fades, raise roughness by the lost normal variance, so highlights do not change character.

**Geometry LOD without pops.** Do not switch meshes instantly:
- Overlap each LOD's distance range and **cross-fade with screen-door dithering** (interleaved gradient noise in the fragment shader against a per-object `fade` value, discarding fragments; draw both LODs during the overlap band, complementary thresholds). The band should be about 15% of the switch distance, and hysteresis stops flicker at the boundary. This needs only a fade value in `ObjectUniforms` (see the shared-struct rule in CLAUDE.md) and no MSAA.
- Do it per **cell** only if the cell pop is hidden by the dither band; better, stagger the switch distance per tree with a seeded random offset (about +/-10 m), so a cell never changes all at once.
- Far LODs must keep the silhouette and the mean colour of the near LOD (same bounding shape, same average albedo), so the dissolve is nearly invisible.

**Grass and clutter fade like terrain.** Instead of a hard outer radius: thin the density with distance by dithering (a per-blade random threshold against a smooth density falloff), and taper blade height and width over the last 10 to 15 m. Far grass should already be present as streaky colour in the terrain albedo (grass-blade-like noise stretched vertically at fine scale, fading in as the blades fade out), so the transition is a cross-dissolve of the same information. Pebbles, shells, driftwood and litter: same dithered density falloff, or scale them up from zero over the last few metres.

**Shadows and AO.** Confirm the cascade cross-fade and SSAO radius do not create a visible band as the player walks (they appear to blend already; verify, do not rewrite).

## How to verify (this must be measured, not argued)

Add a `--approach <target> <out.png>` mode (and a selftest that uses it) that moves the camera toward a fixed target in geometric steps (distance x 0.85 per step, from about 150 m to 0.5 m, about 25 steps) and renders a fixed crop around the target each step. Targets: the dock planks, the lighthouse door and the lower granite shaft, a resonance stone, the cobble path, a conifer, the Varrow meadow, a Glass Wood crystal tree and its grass, the beach sand.
1. Write a **contact sheet** PNG (steps left to right) and Read it: detail should appear to grow, with no step where it clearly arrives.
2. Compute per step: mean luma of the crop, and a high-frequency measure (mean absolute Laplacian or gradient energy) of the crop. Assert:
   - mean luma changes by less than a few percent between consecutive steps (no brightness jump when detail fades), apart from the unavoidable perspective change; compare against a flat-colour reference crop if needed;
   - the high-frequency measure is non-decreasing as distance falls (within noise), and the ratio between consecutive steps stays below a bound (a pop shows as one big ratio); report the largest ratio per target in the done-note;
   - at 4x the distance at which the micro tier reaches full strength, the macro tier is already above a small threshold (the "hinted from further away" check), as a measured fraction of its close-range energy.
3. A **mesh LOD** test: render the approach sequence for a tree and confirm there is no single step where the silhouette-pixel count or mean luma jumps by more than a few percent; the dither band should spread that change over several steps.
4. Re-run the existing band-limiting checks and the shimmer test (small camera motion) to make sure the extra visibility does not reintroduce crawling.

## Report

In the final report list each pop you found (what, where, at what distance), what you changed, and the worst-case jump metric per target before and after. If a pop cannot be removed within budget, say so with the measurement.

## Important context for the user's current experience

The user was playing a stale app bundle (built before M5.5), so what they saw is mostly the old flat look. Run `scripts/bundle.sh` after this work so the playable app matches HEAD, and say so in the report.
