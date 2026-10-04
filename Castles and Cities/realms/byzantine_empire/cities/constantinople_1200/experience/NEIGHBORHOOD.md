# Pantokrator lanes and courts · 0.3.0

Reference year: **circa 1200**. Neighborhood layout version: **1**.
This is an original interpretive neighborhood beside a documented foundation,
not a recovered medieval cadastral survey. Read [SOURCES.md](../SOURCES.md#phase-3--pantokrator-neighborhood-accessed-2026-10-04)
before altering the evidence statements in the application.

## Why this district

Pantokrator has a surviving twelfth-century church group and the detailed 1136
foundation document. Its service provisions give a stronger basis for a bounded
study of baking, storage, gardens and maintenance than an invented generic
commercial quarter. The document establishes activities at the institution;
it does not locate the modeled private premises or certify every condition in
1200. Corinth supplies a separately labeled eleventh-century court/stair analogy.
All local lanes, parcel boundaries, household identities and furnishing designs
remain interpretation. Later Frankish and Ottoman forms are excluded.

## What is implemented

The approximately 6.4-hectare authoring envelope contains six irregular convex
blocks, 108 occupied trapezoidal parcels, twelve open passages and five connected
lane runs. Frontages share boundaries, follow changing street directions and
vary their widths and one/two-storey heights. Rear doors reach common courts,
low yard partitions, shelters, wells and a garden. The main lane joins the
existing `pantokrator_shore` route at its unchanged `[-2550, 1030]` waypoint.
No named landmark, historical route record or peninsula terrain was relocated.

Each room has 0.52 m walls constructed around real door/window cutouts, recessed
reveals, sills/lintels and open door leaves. Level floors sit on foundations
reaching the original terrain; threshold stairs avoid broad rectangular pads.
Roofs have sloping tile surfaces, underside decks, closed gables, ridges and
rafters. Plaster shades, small masonry repairs and filtered weathering are
procedural. Shallow runoff strips follow terrain triangles without slope gaps.
These dimensions and construction details are design assumptions, not measured
Pantokrator domestic fabric.

The principal home, baking workshop and store have furnished ground floors.
The home's back door leads to a stair, gallery and furnished upper room. Five
walking starts are available in the exploration menu. Walking uses the same
wall pieces, furniture boxes, floor polygons and stair treads as the renderer;
0.12 m swept substeps prevent tunneling at larger frame deltas. The camera's
near plane is 0.08 m and eye height 1.68 m. Ground picking now uses the actual
rendered terrain triangles. Fast flight and all district jumps are retained.

## Authoring contract

- `data/neighborhood.json` owns the origin, boundary, blocks, lane centerlines,
  dimensions, passages, stop references and classified evidence. Coordinates
  are local `[east, north]` metres relative to `[-2710, 1110]`. Godot uses
  `[east, height, -north]`. Elevations remain in the existing city datum.
- `schemas/neighborhood.schema.json` and `tools/validate_city.py` reject unknown
  keys, chronology changes, bad sources, invalid/clockwise/concave block polygons,
  missing walking targets, invalid passage slots and a disconnected main gateway.
- `src/neighborhood.gd` insets each block by its configured room depth, divides
  each edge into deterministic unequal frontages, and builds a perimeter of
  parcels. Shared boundary vertices feed wall geometry, floor geometry and
  collision together. Stable IDs have the form `north_west_e0_p3`.
- The current loader reads one district file. The block, opening, roof, threshold,
  furnishing and collision routines can be reused for further authored districts;
  a multiple-district manager is a future extension. Do not duplicate this exact
  layout across the city or substitute an unsupported street plan for evidence.
- Keep block IDs, ordered vertices, frontage counts and passage slots stable once
  published. Changing them changes parcel identities and needs a new layout
  version with an explicit migration map. Add new blocks/IDs instead when possible.
- Test the generated inset and intersections, every door, continuous routes and
  actual renders after changes. A valid schema alone cannot prove walkability.
- Two material-batched meshes keep this bounded district resident at all distances.
  There is no district detail pop at a batch-origin range. Existing whole-city
  architectural LOD remains intact. Shadow-casting lamps are limited to three
  principal interiors; there is no per-house light or per-frame regeneration.

## Reversible layout migration from 0.2.0

`Layout.generate` is unchanged. All **17,561 baseline plot records**, IDs and
architectural assignments remain byte-identical, including when returning from
hypothetical infill states. With detailed fabric enabled, 78 local building
presentations (including their aprons and coarse walking obstacles) are masked,
as are local procedural lane fragments and trees in the authoring envelope.
The district inserts 108 new presentation parcels; these counts are not household
or population estimates. Named route and landmark records are preserved.

**Use v0.2 neighborhood fabric** reverses the visual replacement. Version-1
creative saves are not rewritten: IDs, coordinates, rotation and scale retain
the same meaning. Loading a design with an addition inside the district or its
object-footprint margin automatically restores legacy fabric and explains this
in the status line. Re-entering the detailed neighborhood explicitly restores
its current presentation; additions may then overlap new geometry. The save
format remains version 1, with no campaign fields or world-simulation coupling.
The old presentation checkbox is a viewing choice, not a historical period.

## Verification and performance

Source verification includes eight negative data tests and **374 neighborhood
checks**: every street entrance, parcel non-overlap, high-displacement wall
blocking, the continuous arrival/home/workshop/store walk, rear court and both
directions on the stair/gallery route, repeated generation/mesh hashes, creative
save round trips, preserved baseline records and flight speed. The existing
city scene/editor, navigation, landmark and terrain gates also run during the
release build, then repeat against the exact universal Mac application.

Actual source inspection covered aerial, street, home, workshop, store, garden,
gallery and upper-room/roof views. Corrections made during inspection included
street-normal door approaches on skewed plots, stair-foot terrain height,
gallery-to-door continuity, ceiling winding, roof underside enclosure, resident
interior details, the outer ground blend and terrain-following drainage.
The packaged app produces **32 captures**, including all 23 previous views.
QA images stay outside the repository. Release provenance identifies their
external directory and source commit.

The required parent campaign gates passed on 2026-10-04: data validation (zero
errors/warnings), headless import, **705 tests, zero failures**, and rendered
planning, marching, arrival and maximum-zoom map inspection. Campaign code and
save contracts were not changed.

Measured sequentially on **Apple M3 Max**, Godot 4.4.1 Forward+, 1600 × 1000,
normal enhanced atmosphere, daytime 14:00, VSync disabled. The identical
`tools/benchmark.gd` was run against the frozen published v0.2 source and current
v0.3 source: 120 warm-up frames then 180 process-frame intervals per fixed
camera, excluding screenshot readback. These are one-machine observations,
not portable minimum requirements or a statistically established speedup.

| Fixed view | v0.2 median / p95 ms | v0.3 median / p95 ms |
|---|---:|---:|
| City | 12.181 / 13.279 | 11.549 / 12.902 |
| District | 13.270 / 14.411 | 12.493 / 14.321 |
| Street | 7.871 / 8.640 | 8.332 / 8.629 |

Startup was 10.607 s before and 10.919 s after.
Street median cost grew about 0.46 ms; p95 stayed effectively unchanged. District
draw calls increased from 17,592 to 17,657 and primitives from 21.54M to 22.54M.
The whole-city view remained responsive. Faster aerial medians should be treated
as run variance, not an optimization claim. The builder additionally benchmarks
the exact packaged app and embeds those measurements/hardware in provenance.


## Remaining limits

This is a detailed procedural district with functional access, not photorealism
or a measured reconstruction. Most ordinary rooms are empty; upper floors outside
the featured home do not yet have circulation stairs. The yards remain generous
shared spaces with limited activity/detail, and further domestic diversity needs
additional research. There are no people, animated crafts, soundscape, working
water network, operable doors or physics objects. The oven's mouth is a visual
recess. Plant species and household inventories are not historically verified.

The rest of the city retains v0.2 exterior prototypes and coarser walking
obstacles. Flight is the practical mode for whole-city travel. Collision is an
analytic walking controller for this authored geometry, not general rigid-body
physics; alternate starting points inside arbitrary geometry are not guaranteed
safe. GLBs retain mesh geometry and neutral PBR materials, not the application's
procedural shader appearance, lights, walking controller or CAD solids. Only
Apple Silicon rendering was exercised locally; Intel executable architecture
and signing are checked, but Intel performance is unmeasured.
