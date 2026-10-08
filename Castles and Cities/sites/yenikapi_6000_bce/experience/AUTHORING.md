# Village authoring contract and save boundary

**0.8.0 — Preparedness Put to the Test:** [Gameplay, warning, recovery and wrapper-7 save contract](PREPAREDNESS.md). Choose **Begin warning, response and recovery**. Older living saves adopt explicitly from Incidents; earlier chapters remain available.

**0.7.0:** [A Living, Readable Village](LIVING_VILLAGE.md) connects wood, household knowledge, shared work and local preparedness. Old saves adopt explicitly; active rules use wrapper 6.

**New in 0.6.0:** [Land, Growth, and Lasting Consequences](LAND_GROWTH.md) adds explicit spatial planning. Begin land planning, or adopt it deliberately from Land. Older layouts and semantics remain inactive until adoption; active land uses wrapper 5.

**New in 0.5.0:** [Governing the village through buildings and shared assets](ASSET_GOVERNANCE.md)
is the primary management path. Choose Manage village assets. Older saves retain
their existing manual workforce until explicit adoption; active assets use wrapper 4.
The earlier chapters and instructions below remain available in their original mode.

`data/settlement.json` is the only dated reference snapshot. Its closed JSON schema and
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


## Optional contact authoring (0.3.0)

`neighbors.json` and its closed schema define fictional community identities,
seasonal stocks, offers, aid conditions and speaker profiles. `balance.neighbors`
contains rates and thresholds; `neighbors_ui.json` contains all contact prose.
The meeting commission adds `growth_exchange_house` and `growth_exchange_lane`
without moving old objects. Furnishings remain namespaced by building ID and
explicitly interpretive. Build it through completed project state, never by
editing the dated reference or letting a UI timer change fabric.

See GOVERNANCE.md for contact version 1, mission escrow/IDs, additive old-save
backfill and the version-2 wrapper used after contact activation. New downloadable
models are separated from the original village and hypothetical town. All three
modes receive standalone performance measurements; all exact-app captures need
human visual review before publication.

## Optional household circumstances (0.4.0)

[HOUSEHOLD_LIFE.md](HOUSEHOLD_LIFE.md) describes the village-scale adversity and
renewal chapter: finite preparations, seasonal care/watch staffing, household
stress and uneven learning, plus procedural interiors and illustrative routines.
The eight-season fictional episode is separate from the dated snapshot and does
not reconstruct an army or siege. Settled recovery continues afterward without
automatically restarting danger or upgrading every building.

`households.json`, its closed schema and `balance.households` own authored content
and tuning; scene-free rules own decisions and memory. Preserve household IDs
when adding circumstances or activity destinations, and retain existing reference
geometry/inventories. Animation and routing must never mutate seasonal state.
Learning requires both care staffing and enough gathering to pay its opportunity
cost. The presentation respects readiness; indexed route queries retain the same
collision shapes as walking and invalidate caches when those shapes change.
Old saves backfill inactive `households: {}`; active chapters require wrapper 3,
with versions 1/2 still accepted for inactive households. Keep validation,
save/replay, actual interior navigation, rendered variants and exact-app release
checks together when extending this seam.


## Visual command interface (0.9.0)

Read [VISUAL_COMMANDS.md](VISUAL_COMMANDS.md) for the presentation contract. Place
icons and growth links reference existing assets/projects. Validate the closed
visual-command data, including prerequisite arrows. Keep all economy and costs
behind public rules; canonicalize data-driven choices before dispatch. Model
previews use production geometry in an isolated viewport and cannot alter state.
No image assets or new save wrapper are introduced. Retain the detailed ledger
and old chapters; never make opening a saved village adopt later rules.


## Construction and planning presentation (0.10.0)

Read [CONSTRUCTION.md](CONSTRUCTION.md) before changing site geometry, plan
objects or status labels. `construction.json` and its closed schema describe
25 existing projects using seven treatments; they do not own costs or rules.
The pure read model takes payment, work, crews and blockers from existing
project/asset/land/living/incident records. Never introduce a delivery ledger,
architectural institution or construction-damage system for visual effect.

The planning board is portable interpretive furniture in the existing working
room. Validate its collision and every entrance against citizen routes, including
adaptations. Keep metadata opt-in for gameplay presentation: retained neutral
model exports must not silently acquire plan furniture or construction overlays.
Five new Construction models show the four unfinished care-shelter stages and
planning furniture in the working room; their provenance uses normal public
commands and calls out the gameplay interpretation. Retain all 36 prior GLBs.


## City lifecycle (0.11 retained contract)

[LIFECYCLE.md](LIFECYCLE.md) defines the implemented small-to-large-village
transition, paid individual upgrades and wrapper-8 adoption contract. Its town
extension is described below; stages after Town remain metadata for future work. The dated snapshot and parent level enums stay
unchanged; no ordinary frame, preview or load can advance civic achievement.

Keep the lifecycle profile's semantics stable. Prices, work and reserves come
from `balance.lifecycle`; stages, closed predicates and explicit project/fabric
links come from `lifecycle.json`. An active save carries the semantic definition
hash. Retain a published profile or write an explicit migration before changing
paid contracts. Copy-only edits do not require a migration.

Each lifecycle change declares every expected predecessor revision, including an
empty map for additions. Ordered project replay must pass at the command and save
boundaries, before rendering. Preserve unique project IDs, full predecessor
furnishings and coordinates. Store effects are incremental, while successor land
uses replace the earlier site's contribution with an authored total. Neither
path repairs condition or restores compact development's occupied working ground.

Use the public-command compact/outward recipes and temporary saves for isolated
stage work. Extend data/negative, rule/save, lineage and rendered checks together.
The release builder includes these gates on source and exact app; existing neutral
model exports remain unchanged. No later stage is accepted until its full entry,
operation, stress/recovery and continuation path work from the preceding stage.


## Town responsibilities (0.12.0)

Never edit the published base lifecycle's prices, work, predicates or geometry to
add town. `lifecycle.town` and `balance.town_lifecycle` form a separately adopted
semantic profile; the original hash is computed before merging the extension.
UI text is not part of either semantic hash. The base profile's stage list,
including `town` with `status: "planned"`, is part of the published hash, so that
status is deliberately left unchanged; the interface derives Town's availability
from the presence and adoption of the town extension, and later stages must use
the same explicit-extension pattern rather than editing the hashed stage status. Save adoption preserves the original
profile, paid contracts, completed ledger and all unrelated chapters.

The only town projects are the civic-house alteration, material preparation and
local provision. Their `effects` stay empty: actual benefits are implemented in
`Lifecycle.apply_allocation` and seasonal spoilage, avoiding passive double
counting. Civic duty replaces the earlier request under the same stable ID.
Service requests a separate finite adult; preparation consumes actual extra
wood and a spare work place after ordinary allocation. Reuse the existing
condition threshold and town-support factors instead of copying balance values.
Project text renders real incremental/total values from these readers.

Town alterations retain use, footprint, entrance/yaw, household association and
all predecessor furniture. They add no dwelling or density. The civic project
names the paid assembly predecessor and the site successor; work retains the
previous site use. Validators combine both profile graphs, inspect physical
revisions, check pre-town reachability and require real tuning readers. Negative
cases cover erased furniture, changed use/density, bad revisions, dependency
bypass, successor mismatch, passive duplicate effects and unrendered quantities.

Civic, preparation and service workers derive destinations from these same
buildings. Near-endpoint route reuse is presentation only: retain a searched
route from the exact same origin only when the endpoint is within four metres
and its connector passes the existing collision test. Revalidate paths on world
geometry changes; never chain reused connectors or alter assignments/RNG.
The UI keeps unchanged controls when its full state/presentation signature agrees.
Both optimizations must pass retained cold-geometry and whole-route walking gates.

Retain `tools/fixtures/lifecycle-0.11-paid.json` byte-for-byte as a published
compatibility fixture. Generate new town fixture saves through public commands,
never by assigning stock, work or rank. Store QA captures outside the repository.
The exporter adds only `town-*.glb` and provenance; verify every old model against
the preserved 0.11 build. Do not rewrite any previous release artifact.
