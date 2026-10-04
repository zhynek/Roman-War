# Constantinople, circa 1200 CE

**Design target:** an inhabited Byzantine imperial capital immediately before
the upheavals of 1203–1204. The principal reference year is **1200 CE**; a
source from another date must be checked before its details enter this baseline.
The independent [3D experience](experience/project.godot) now presents an
inhabited, explorable interpretation at peninsula, neighborhood and architectural
scales. It is not a surveyed reconstruction; detailed geometry does not resolve
the historical uncertainties recorded below.

The city occupies a peninsula with the Golden Horn to the north, the Bosphorus
to the east and the Sea of Marmara to the south. Its land defenses, religious
monuments and maritime setting provide the organizing framework. See
[SOURCES.md](SOURCES.md) for the source register, including UNESCO's account of
the historic peninsula.

## What is built

The standalone Godot 4.4 project has 26 landmark/site models, eight authoring
wards, walls, three waterfront zones, interpreted terrain and a whole-city plan.
The preserved deterministic baseline contains **17,561 ordinary plot records**, with
3,264 trees and 192 neighborhood lane runs. These are modeling counts, never
population or household estimates. Density is greater in central and waterfront
wards; western open ground and gardens remain visible.

Use the place list to approach a landmark, inspect an interior or courtyard,
switch between orbit and architectural movement, and compare three visual
states. `reference_1200` is the dated interpretive baseline; `serviced` and
`expanded` are hypothetical infill alternatives. The creative workshop supports
editable design objects and a separate saved variant. Camera and stage actions
never advance Roman War gameplay.

Editable geographic parameters and source links are in
[city.json](experience/data/city.json); the original procedural geometry is in
[experience/src/](experience/src/). The
[GLB export tool](experience/tools/export_models.gd) creates a whole-city mesh and
individual landmark derivatives with neutral materials and a provenance file.
These exports do not preserve CAD solid constraints or the application's shader
appearance. High-fidelity historical and architectural refinement remains ongoing.

## What the city should feel like

The reconstruction should let a viewer understand the city through use: moving
from a landing place into commercial streets, approaching a religious precinct,
crossing changes of slope, entering a gate and encountering the service spaces
that keep a large city inhabited. This is a design objective, not evidence that
a particular undocumented route or scene existed.

Model the ordinary fabric alongside the monuments: domestic plots, workshops,
storage, food preparation, water access, drains, repaired surfaces, yards,
planting and waste handling. Their exact distribution and appearance need
district-level research. Do not fill every open area with invented houses, or
use repetitive buildings to suggest a population count we have not established.

## Reconstruction boundary

- Include dated Byzantine buildings and infrastructure supported by the evidence.
  Model survival, repair and reuse, rather than assuming everything was newly built.
- Hagia Sophia is a church in this baseline. Its Ottoman minarets and later
  additions cannot be projected backward from modern photographs. Roofs,
  buttresses, mosaics and furnishings require their own chronological checks.
- Keep the Hippodrome and palace areas distinct. Establish what survived and
  how it was used in 1200 before drawing complete sixth-century assemblies.
- Research both the southeastern palace zone and northwestern Blachernae.
  A single upgraded "city hall" cannot stand in for all imperial institutions.
- Do not include Topkapı Palace, the Blue Mosque, modern transport bridges,
  modern roads or modern reclaimed shoreline in the 1200 scene.
- The 1203–1204 fires, sack and later reconstruction are later states, not
  decorative damage in the baseline. Do not treat their absence as proof that
  every earlier structure was intact.

## Scope by scale

| Scale | Required design artifact | Current state |
|---|---|---|
| Peninsula | Terrain, historic shoreline hypotheses, wall circuits, principal routes and monument anchors | Original terrain, shore hypotheses, walls, routes and anchors rendered in a local metre frame; no survey control |
| District | Plots, street widths, slope/steps, public/private boundaries, services and sightlines | Eight research briefs plus eight procedural authoring wards; their boundaries serve different purposes |
| Building | Plans, elevations, sections, structural system, roof and material schedule | 26 original landmark/site assemblies and varied dwelling generators; most dimensions remain approximate |
| Room and street detail | Joinery, openings, paving, furniture, tools, lighting and wear tied to use | Selected interpretive interiors, openings and procedural surfaces; room-by-room evidence and construction refinement remain open |

Phase 3 builds the **Pantokrator lanes and courts**: six irregular connected
blocks, 108 occupied parcels, true interior openings, a continuous walking
circuit and a furnished home, baking workshop and store. The local plan is
interpretive; the monastery and its 1136 typikon anchor the evidence. The
[neighborhood authoring guide](experience/NEIGHBORHOOD.md) records regional
analogies, assumptions, the reversible presentation migration and validation.
The cathedral precinct remains a future research package.

## Read and continue

[ATLAS.md](ATLAS.md) defines district work and capability requirements.
[STAGES.md](STAGES.md) separates dated history from hypothetical visual growth.
[WORKPLAN.md](WORKPLAN.md) gives bounded modeling tasks and review criteria.
[study.json](study.json) indexes these records for tooling; its IDs are authoring
IDs and have no campaign meaning.

## Separate early-settlement study

The [Yenikapı village around 6000 BCE](../../../../sites/yenikapi_6000_bce/README.md)
is now a separate dated interpretation. It does not replace this circa-1200
reference or transform its plots into a prehistoric plan.
