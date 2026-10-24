# R03: real structure and material for the lighthouse and the trees (user request)

**This one comes from the user directly, not only the reviewer.** The user's words: "I find the structure of the lighthouse to be just blocks. Similarly, the trees are mostly just cones without real structure. The lighthouse should have real texture and detail. I should be able to see it in clear enough detail that I can understand what materials it is made of and how it would feel under my fingers." Treat this as higher priority than the remaining R02 backlog (finish the R02 defect items you are mid-way through, then do this).

Same rules as before: triage into TASKS.md, before/after screenshots Read and compared (use close-up views, see below), selftests green, commit at each pausing point, INSPECT.md updated, leave the story ending to the user. Frame-time budget: at most +1.5 ms total for this brief.

## Why it looks like blocks (from reading the code)

- `Vertex` carries one albedo and one roughness per vertex (48 bytes: position, normal + material id, colour + roughness). No UVs, no tangents, no prop textures. So a prop surface is a flat colour unless its material id has a procedural function in the fragment shader. Only terrain does (`terrain_surface`).
- The lighthouse is `MaterialID.standard` throughout: stone, paint and iron are all flat colour with a roughness number.
- Its tower is an 8-segment, flat-shaded frustum stack. No courses, no joints, no plinth steps, brackets or arches. Cypress = 6 smooth cones on a 6-sided trunk.
- There is no metalness: F0 is a fixed 0.04, so iron and brass read as plastic.
- Runtime shader compilation is NOT the limit (`makeLibrary(source:)` is the same compiler and language as an offline build). Do not spend effort on `.metal` files.

## T-A. A real material system (do this first)

1. Add material ids: `masonry`, `paint` (lime-washed plaster / painted render), `iron`, `copper` (brass/verdigris), `wood`, `bark`. Keep `GPUTypes.swift`, `Shaders/Common.swift`, `expectedStride`, selftest and TASKS.md section 0 in step if any shared struct changes. Prefer NOT changing `Vertex` stride at first: derive pattern coordinates in the fragment shader from world position (the lighthouse is static: use cylindrical coordinates about its axis, angle and height; for other props add a `float4 mapping` to `ObjectUniforms` giving an object origin/axis, or reconstruct local position from a stored inverse model).
2. **Metalness.** Treat `iron` and `copper` as metallic: no diffuse, F0 = albedo, tinted specular, and image-based reflection of the sky LUT at the right roughness. This alone removes much of the plastic look.
3. **Procedural masonry** as a function `masonry(P) -> {albedo, roughness, height}`: running-bond courses (course heights vary 0.28 to 0.45 m), per-block hash for tone, roughness and height offset, mortar joints recessed 1-2 cm, chips and pits (small-scale noise), lichen in the splash zone and on north/sea-facing faces and in the joints, rain streaks running down from sills, ledges and the gallery (stretched vertical noise), salt/damp darkening near the base. Derive the shading normal from the height function (finite differences are fine) and add a cheap parallax or height-based AO so joints read as depth at grazing sun. The low golden-hour sun is a gift for relief detail: use it.
3b. **Painted render** for the upper tower: chalky, slightly rough, with the red bands weathered (fading to pink, flaking to expose stone, drip stains below the bands and windows), plus hairline cracks.
4. **Iron**: dark blue-black with rust blooming at joints and drip points, tiny roughness variation, a few bright worn edges.
5. **Band-limit everything with `fwidth`**: fade each octave and the joint lines by the pixel footprint, or they will shimmer (we have no anti-aliasing). If shimmer is still visible at 1600x900 after band-limiting, do not just accept it: write the specific problem in INSPECT.md and the final report, because it argues for revisiting MSAA 4x, which the earlier review proposed and you rejected before there was fine detail to protect. That is a decision for the reviewer and the user, not a silent addition.
6. Optional second step if the procedural cost is too high: bake a tileable masonry/bark texture (albedo, normal, roughness+height packed) at launch with a compute kernel or on the CPU from the seeded noise, and sample it triplanar or cylindrical in the shader. Textures give hardware mipmapping and anisotropic filtering, which fixes shimmer for free. Only adopt this if band-limited procedural detail shimmers or costs too much.

## T-B. MeshBuilder additions

`lathe(profile:segments:)` (revolve a profile curve: bases, plinth steps, string courses, cornices, domes, finials), `arch(width:height:depth:)` with voussoir-style joints, `extrude(path:)` / `sweep` for rails and brackets, smooth shading with at least 32 segments for round forms (an octagonal tower is the main reason it reads as "a block"). No change to the triangle budget concerns: the island draws in a few ms.

## T-C. The lighthouse, rebuilt

Round (not octagonal) tapered tower, 32+ segments, with a slight entasis. In order from the ground:
- Stepped granite plinth (2-3 steps) sitting into the ground with a rough irregular top edge; the terrain pad blend must not show a hard ring.
- Lower tower (to about 3 m): rough-hewn granite masonry, large blocks, strong relief.
- Upper tower: lime-washed render in white and red bands, weathered as above, with a projecting string course at each band change and at the gallery.
- Door: arched, with a stone surround and voussoirs, a recessed plank door (wood material: vertical planks, iron strap hinges and studs, a ring handle), a worn threshold step.
- Windows: splayed reveals (the opening is deeper than the wall face), stone sills with drip grooves, dark glazing with thin iron bars.
- Gallery: a corbelled stone deck on visible brackets, an iron balustrade with posts, a top rail and a mid rail (sweep), a hatch.
- Lantern room: glazed with thin iron glazing bars (mullions), a sloped copper roof with verdigris, ribs and a ventilator cowl with weathervane, a lightning rod. Keep the existing lens, glow, beams and the puzzle hooks working (`lighthouse_lens`, `lighthouse_glass`, `capstoneBase`, the beam attachment points). Do not change the lighthouse's position, collider or pad (they live in `Layout.swift`).

**Detail follows reach.** The player can only get close to the base, door and lower tower. Spend the detail budget there (it should hold up at 0.5 to 1 m), then mid-detail up the shaft (read at 5 to 30 m), then silhouette detail at the gallery and lantern (read from the summit path at 10 to 40 m). Fade the micro detail out by distance/footprint.

**Close-up viewpoints to add to Config.swift** (so you can verify what the user asked for): `lh-door` (0.8 m from the door, eye height), `lh-base` (1 m from the wall, looking along it with the low sun raking across), `lh-mid` (about 15 m away, looking at the bands), `lh-top` (from the summit path looking up at the gallery and lantern room), `lh-glass` (the lantern room from the gallery height or the nearest reachable point).

**Accept:** in `lh-door` and `lh-base` at 1600x900 a viewer can tell, without a label, which parts are granite, painted render, wood, iron and glass, and the block coursing, joints, weathering and rust are clearly visible; `lh-mid` and `lh-top` read as a real masonry tower, not a stack of blocks; the silhouette is round with a real gallery, brackets and lantern; no hard flat-colour faces remain; metal surfaces show metallic reflection; band-limiting keeps the detail from crawling when the camera moves 2 mm between frames (render two frames and compare); puzzle behaviour, beams, lens glow and all selftests still work; frame time within budget. If any part does not visibly improve its frame, revert that part and say so.

## T-D. The trees, rebuilt

Real structure, not stacked cones:
- **Trunk** with taper, a root flare, slight curve and lean, procedural bark (long vertical fissures: ridged noise stretched along the axis, a little moss on the north/windward side), a few broken branch stubs.
- **Branching skeleton**: for the conifers, whorls of branches that droop slightly and shorten toward the top (a small deterministic L-system or branch-whorl generator from the seeded noise); each branch a tapered tube.
- **Foliage as bough clusters, not tiers of cones.** Many small clumps (irregular ellipsoids or small cone fans, 20 to 60 per tree) carried on the branches, each with an irregular silhouette from noise displacement. Standard trick: bend each clump's normals toward the direction away from the tree's centre so the whole crown shades as one soft volume instead of showing hard facets. Bake a darker interior and lighter tips into vertex colour (cheap ambient occlusion). Keep the existing wrap lighting and backlit translucency; they are good.
- Variation per tree (shape, height, lean, density, colour) driven by the seeded noise; combine with the Poisson-disc placement from R02 item 1. Also a dead snag with real broken limbs and a fallen log with bark.
- **LOD**: near (under ~40 m) full structure; mid a simplified skeleton plus fewer, larger clumps; far (beyond ~120 m) the existing cone silhouette or a cheap crossed-card stand-in. Check the draw-call count (instancing, or merge near trees); stay inside the budget.
- Glass Wood crystal trees: give them the same treatment (real branching, faceted crystal clusters with the refractive pass kept).

**Accept:** a `tree-close` view (about 4 m from a conifer, at eye height) and the `dock`/`overview` shots before and after: individual boughs and branches are visible, bark has fissures, the crown reads as a mass of foliage with a ragged silhouette, no two neighbouring trees are the same shape; frame time within budget (report the numbers).

## What not to do

No photoscanned or downloaded assets, no third-party packages (project rules). No GPU tessellation or ray tracing. No changes to the story ending. Do not weaken the shipped look elsewhere: confirm `dock`, `overview`, `shore` and `gw-arrival` are no worse after the material system lands.

## Reviewer's honest expectation

Procedural masonry and a branching conifer will read as convincing, tactile and painterly at 1 m, not photographic. If you hit a limit (shimmer, cost, a material you cannot make convincing in code), report it plainly with a screenshot; that is useful information for the user.
