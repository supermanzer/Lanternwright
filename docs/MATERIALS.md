# Materials

Every procedural material is a function in `Sources/Lanternwright/Render/Shaders/Materials.swift` (props) or `Ground.swift` + `Lit.swift` (terrain).
A material gets a position and returns albedo, roughness, metalness, a bumped normal and an occlusion factor: no UVs, no textures. `--view material-sheet`
shows a sphere and a slab of every prop material under the same light; `--view ground-grass|sand|edge|slope|islet` (add `-1m` or `-5m`) shows the ground.

## The rules every material follows

1. **Noise.** Gradient noise in a rotated frame (`vnoise3`, `fbm3`, `rfbm3`, `warp3`, `ridged3`, `billow3` in `Common.swift`), never a threshold on raw value
   noise: value noise has an axis-aligned lattice that shows as blocks (pits, flaking, the path, the ground: found four times). The cheap `vnoiseV`/`fbmV`
   exist for low-frequency fields whose lattice can never be seen (clouds, water, metre-scale patches).
2. **Continuous detail (R09).** Every feature is `featVis(size, fpix)` = `smoothstep(0.6, 2.5, size / fpix)`: invisible below 0.6 px, resolved above 2.5 px.
   Macro (0.2-1 m: courses, plank joints, patches, drips) is hinted at 100-400 m, meso (5-15 cm: cobbles, pits, board grain, moss clumps) at 20-130 m, micro
   (0.5-3 cm: fibres, grains, sparkle) at 3-30 m. Every feature fades to its mean (`mix(mean, value, vis)`); lines narrower than a pixel keep their average
   darkness (`lineAmp`); roughness rises as bump is lost.
3. **Boundaries by height.** Where two layers meet (`height_blend`), the choice follows their relief plus a mask, so moss creeps over stones and sand drifts into
   grass; a boundary is never one smoothstep of one noise.

## Table

| Material (id) | Used on | Macro | Meso | Micro |
|---|---|---|---|---|
| masonry (5) | lighthouse shaft base | courses, block tone, drip stains | blocks, pits, lichen | speckle |
| paint (6) | lighthouse bands | bands, flakes (0.3 m), drips | cracks | grain |
| iron (7) | straps, bars, cleats, finials | rust blooms | wear | pits |
| copper (8) | roof | verdigris | streaks | grain |
| wood (9) | the lighthouse door | planks | grain rings | fibres |
| bark (10) | conifer trunks | plates | fissures (12 / 5 cm) | |
| dressed (11) | arch, quoins, steps, lanterns, stones | tone | pits, lichen | chisel marks, speckle |
| deck plank (12) | the dock | board tone, edges | grain | fibres |
| timber (13) | piles, posts | tide bands, silvering | barnacles | fibres |
| glyph stone (14, 20) | resonance stones, murals | tone | the carved glyph (shader SDF) | |
| paper (15) | journal pages | foxing, crease | ink rows | fibres |
| pebble (16) | the weight on a page | | | |
| glass stone (17) | Glass Wood stone | tone | pits | frost glints |
| mirror (18) | Glass Wood mirrors | | | |
| pale metal (19) | Glass Wood frames, inlays | | | brushed grain |
| terrain (1) | ground | patches (2.5 m), moisture | moss, clover, cobbles | turf fibres, grains |

## Ground (Ground.swift)

- **Meadow floor** (`ground_meadow`): a turf mat of combed fibres in a slowly turning direction field, moss mats in damp low places (soft domes, velvet),
  sparse clover, soil specks, straw. Built so its mean is the old flat colour.
- **Sand** (`ground_sand`): grains of several tones, shell grit, pebbles in clusters, soft ripples. **Scree** (`ground_scree`): angular plates and stones
  from a 3D F1/F2 Worley (no projection, no stretching), per-stone tone, lichen, damp crevices.
- The grass/sand boundary is `height_blend(grass relief, sand relief, coarse mask)`.

## Weathering and per-object variation (partial)

Each prop material carries its own weathering terms (lichen low and windward on stone, rust and drips on iron, silvering, tide bands). A shared
`weather()` pass and per-object seeds (so no two planks, posts or slabs match) are scheduled with W2 and W3 (docs/TASKS.md T64.8, T64.11).
