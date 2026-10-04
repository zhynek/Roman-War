# City development and visual stages

The first detailed target is **Constantinople circa 1200**. It is already a major
capital. We will not label it a village simply to make a progression ladder work.

## Historical snapshots

These are separately dated reconstruction scopes, not completed maps. Only 1200
is the active reference; the others are research outlines. See the source IDs
and dates in [study.json](study.json) and [SOURCES.md](SOURCES.md).

| Snapshot | Visual questions to resolve | Guard against |
|---|---|---|
| `constantinople_330_ce` | Imperial foundation, inherited fabric, palace/Hippodrome relationship and extent | Inserting the later Theodosian land-wall system or Justinian's Hagia Sophia |
| `constantinople_565_ce` | Justinianic fabric after the 562 dome rebuilding; water and monumental ensembles | Using the original 537 dome or later medieval alterations without review |
| `constantinople_1100_ce` | Palace use, reused older fabric and changing maritime geography | Carrying later twelfth-century additions backward automatically |
| `constantinople_1200_ce` | Late twelfth-century fabric, multiple imperial precincts, inhabited wards and waterfronts | Ottoman buildings, later mosaics, modern shorelines and 1203–1204 destruction |

For every building or plot, record its stage relationship: retained, repaired,
extended, converted, newly built, removed, or uncertain. Reuse its stable ID
where identity continues. Changes of use and areas of uncertainty matter as much
as increasing building count. Do not assume uninterrupted growth between dates.

## Creative growth studies

These are **hypothetical future authoring scenarios**, not claims about the
historical city's development. Create them under [variants/](variants/README.md)
without overwriting the 1200 baseline. They let us explore the sort of visible
development the owner wants before assigning gameplay rules.

| Design state | Visible changes to author | Continuity to preserve |
|---|---|---|
| G0 — historical reference | The reviewed district as it stood in the selected baseline | Source record, dated fabric and uncertainties |
| G1 — repair and service | Repaired surfaces, restored roofs, better water/service access, occupied vacant structures where deliberately proposed | Existing street and monument identity |
| G2 — district expansion | New plots, workshops/storage, added dwellings and supporting access outside the retained core | Plausible terrain, water, delivery routes and historical boundaries identified as changed |
| G3 — civic reconstruction | A deliberately redesigned administrative precinct, larger public spaces or a new defense/harbor project | Explicit demolition, relocation, construction space and retained older landmarks |

G1–G3 can be rejected, branched or designed differently. There are no population
thresholds, construction costs, unlocks, time advancement or building effects in
these records. A town-hall-style progression in another city can use its own
cultural institutions; Constantinople's growth should not be expressed solely
by enlarging one hall.

## What to compare at each stage

Use the same camera positions and lighting for comparisons. Produce a plan,
district oblique view, street-level view and selected section. Include an overlay
or accompanying list of retained, changed, new and removed objects. Match ground
levels, entrances and routes across the transition; do not create disconnected
new buildings merely to make a stage look larger.

Review the following together: silhouette; street and plot continuity; roofscape
and density; open spaces and planting; walls and gates; water and storage;
institutional spaces; construction and repair traces. Added detail should make
the city more understandable at human scale.

For a future construction preview, define three presentation states for the
same approved project: existing, building and completed. Foundation trenches,
scaffolding or stockpiles must be authored and labeled as a proposed construction
sequence where not documented. Scrubbing these states is purely visual.

## Relationship to Roman War's levels

The current game uses `village`, `town`, `large_town`, `minor_city`, `large_city`
and `huge_city`. No historical snapshot or creative stage in this workspace is
bound to those values. A later integration should map reviewed visual content
to actual game state without turning presentation into simulation, and without
replacing the existing deterministic construction or save model.
