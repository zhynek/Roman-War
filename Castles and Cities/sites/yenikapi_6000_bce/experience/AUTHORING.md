# Village authoring contract and save boundary

`data/settlement.json` is the only rendered snapshot. Its closed JSON schema and
`tools/validate_settlement.py` check vocabulary, IDs, source links, furnishing
bounds, route segments and the nominal period. `tools/test_data.py` has negative
cases. Geometric and route checks are separate; schema validity cannot prove access.

Coordinates are `[east, south]` metres, rendered as `[x, height, z]`. Positive yaw
uses Godot's Y-axis rotation. Each building has an explicit footprint, orientation,
use, household ID and named furnishings. The land/water frame is local and
interpretive; zero is the authored sea, not an excavated or modern vertical datum.
The near landscape uses 2 m triangles; countryside beyond 240 m uses 8 m triangles.
Walking is bounded to 170 m, with water excluded. The same near-triangle sampling
is used for floor height and path placement. Floors level to a gently blended
local terrace. Terrain query behavior is tested against actual mesh triangles.

`src/village.gd` batches objects by material. Every structural wall/furniture box
is registered at the same transform used to draw it; a swept circular walker
substeps at 0.09 m and slides along obstacles. The eye is 1.68 m above the floor.
Roofs and vegetation are original geometry. Shader motion is only visual water.
The hash mixer is deterministic per object/detail ID and never touches RNG, time,
campaign state or saves. The geometry helper is an unchanged copy of the original
city's independent primitive utility; it imports no medieval types or layouts.
The new project has no resource paths to the medieval experience.

Do not recycle IDs to make a replacement look continuous. Preserve published
building/furnishing IDs and coordinates, or add an explicit lineage/migration
record. [STAGES.md](../STAGES.md) defines the future change-set seam. The single dated village remains the reference. Release 0.2.0 also loads a
separate hypothetical seasonal tutorial; its completed project changes pass
through this lineage seam. See [GOVERNANCE.md](GOVERNANCE.md).

## Saves

The Mac bundle ID is `com.romanwar.yenikapi.earlysettlement`. The application uses
`Roman War Yenikapi Early Settlement` as its custom Godot user directory. Its reference
viewing file is `early_settlement_view.json` (a viewing bookmark, not a world
save). **Save view** writes a temporary file then renames it into place.

Version 1 fields: `format: "yenikapi_view"`, `version: 1`,
`snapshot_id: "yenikapi_c6000_bce"`, `scenario_id: null`, `position: [x,y,z]`,
`rotation: [pitch,yaw]`, `navigation: "walk" | "fly"`, `flight_speed` in m/s.
The loader bounds file size, validates types/ranges/finite numbers and snapshot,
and rejects walking positions inside solids or water before changing the view.
Additional unrelated fields are ignored; future fields must default additively.
Unknown versions/scenarios are refused. No existing save is migrated or rewritten.
The new `early_settlement_campaign.json` uses a different wrapper and validated
version-1 simulation state; its full contract is in GOVERNANCE.md. Campaign mode
refuses reference bookmark operations, and uses Save/Load campaign instead.
The medieval v1 creative save remains in its original app with unchanged IDs,
positions, rotations, scale and Pantokrator compatibility behavior.

QA uses explicit temporary file paths and never presses Save/Load against a real
player slot. The release builder runs both source and exact-app checks, captures,
benchmark and model export. Models contain original geometry and neutral PBR
materials, not the procedural shader rendering. Keep QA imagery outside Git.

## Verification coverage

The production controller is used to enter and leave every building and traverse
a continuous approach/home/workroom/store/landing route. Every authored curved
footpath is walked, including cultivation access. Large-displacement wall tests,
matching picking, safe starts, flight recovery, terrain triangles, repeated mesh
and collision hashes, all lineage relationships and real save round trips run
headlessly. Four furnished interiors are entered with collision in rendered QA.
Landscape, plan, aerial, street, landing, fields, roof, evidence and 1280×800 UI
captures complete the 14-image inspection set. The benchmark measures 120 warm-up
and 180 process-frame intervals at each of four fixed views, excluding captures.
