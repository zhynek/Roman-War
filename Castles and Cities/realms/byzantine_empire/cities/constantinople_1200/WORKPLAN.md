# Work plan — build one defensible piece at a time

Current checkpoint, 2026-10-03: **an original, independently explorable procedural
3D city now exists** in [experience/](experience/project.godot). It contains 26
landmark/site models, interpreted interiors and architecture, a peninsula terrain
and street framework, and varied ordinary buildings. The application also has
three selectable visual states, editable creative objects and a GLB export tool.
Historical fidelity remains a research objective: the model is not a measured
map, a CAD solid assembly or a verified record of every building in 1200.

The current layout check generates 17,561 reference buildings, 18,842 in
`serviced` and 19,923 in `expanded`, with 3,264 baseline trees and 192 lane runs.
These are authored model counts, not historical statistics. The checks verify
repeatability, preserved baseline objects across creative stages, budgets,
non-overlapping house footprints, road/wall/monument exclusions, land/water
placement and level monument foundations. Passing them does not establish
historical accuracy, complete architectural construction or visual quality.

Source parameters are in [city.json](experience/data/city.json), original
geometry in [experience/src/](experience/src/), and export code in
[export_models.gd](experience/tools/export_models.gd). Application rendering,
interaction and release artifact checks belong to the standalone app's release
record; retain actual captures and binary exports outside the repository.

## Next session: refine the cathedral precinct against dated evidence

Bound the task to `cathedral_hippodrome`, circa 1200. Begin with the existing
procedural precinct and identify which parameters are estimates. Acquire and compare usable
architectural plans and historical topography; establish their rights, dates and
measurement basis. Record the source locator for every anchor and key dimension.
Read the repository's `CLAUDE.md`, `docs/HANDOFF.md` and map review first, then this
study and its sources.

Produce:

1. A source/claim/dimension schedule distinguishing existence, position, height,
   1200 condition and uncertainty. Leave unsupported fields unset.
2. A declared coordinate system and provisional or surveyed datum, with an
   explicit statement of which it is. Establish control points before calling
   a map georeferenced.
3. A dated asset inclusion list and a bounded precinct extent supported by the
   acquired sources. List excluded later additions and unresolved alternatives.
4. Revised original plan, elevations and geometry for the bounded area, with
   each changed parameter linked to a measurement or explicit inference. Retain
   the previous interpreted version for comparison; do not fabricate precision.
5. External QA captures of plan, section, oblique and street-level views for
   any geometry actually produced, with settings and evidence notes.

Completion means a reviewer can trace every major modeled dimension to a source
or labeled inference and can see the actual geometry. It does not mean a finished
photorealistic precinct. Record exactly what was verified and the next unresolved
modeling question.

## Subsequent work packages

| Package | Deliverable | Review gate |
|---|---|---|
| Site framework | Dated shoreline alternatives, relief, wall extents and principal anchors | Datum, scale, sources and uncertainty visible |
| Fortification component | One sourced gate/wall bay in editable parametric form | Plan/elevation/section dimensions; no impossible joins |
| Precinct architecture | Dated footprints, roofs, elevations and entrance relationships | Period and geometry reviews agree |
| Human-scale detail | One street frontage and supported interior/threshold | Openings, stairs, light and service access work at real scale |
| Procedural surfaces | Original material recipes for the selected buildings | Neutral-light close views; scale and wear follow construction |
| Occupied street | Supported/interpretive furnishings and use traces | Each detail has a purpose and evidence label |
| Historical comparison | One earlier snapshot of the same bounded area | Stable objects and a reviewed change ledger |
| Creative variant | A documented workshop design beyond the supplied infill alternatives | Baseline preserved; every departure explicitly creative |

Choose a package with enough evidence to improve the existing city meaningfully. High-cost renders come after geometry and period checks. Do not spend a
session polishing a roof whose form has not yet been established.

## Repeatable session request

> Continue the independent Constantinople circa-1200 study in `Castles and
> Cities/realms/byzantine_empire/cities/constantinople_1200`. Work only on
> [district/building/package]. Read its sources and modeling guide. Produce
> original editable geometry and documented evidence at the highest fidelity
> the evidence supports. Keep uncertainty explicit and all render images outside
> the repository. Do not modify campaign gameplay or the separate ongoing Roma
> work. Validate authoring metadata, inspect any actual renders, and update this
> checkpoint with the artifact locations and remaining questions.

## Checkpoint record for a completed package

Record date, authoring revision, target period, changed objects, source additions,
geometric assumptions, model files, external export/render locations, validation
results and known limits. Keep current status factual: a geometry generator that
has not been run is not a tested model, and a rendered blockout is not a finished
historical reconstruction.
