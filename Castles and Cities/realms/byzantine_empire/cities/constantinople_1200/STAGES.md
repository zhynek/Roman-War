# City development and visual stages

The first detailed target is **Constantinople circa 1200**. It is already a major
capital. We will not label it a village simply to make a progression ladder work.

## Historical snapshots

These are separately dated reconstruction scopes. Only 1200 has a rendered
interpretive model and is the active reference; the others remain research
outlines, without modeled historical snapshots. See the source IDs
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

The experience implements three selectable visual states. The IDs below
are runtime authoring IDs; `reference_1200` corresponds to the research snapshot
`constantinople_1200_ce`. The other two are **hypothetical**, with no assigned
historical date. They are documented under [variants/](variants/README.md).

| Runtime state | Current visible behavior | Continuity |
|---|---|---|
| `reference_1200` — Constantinople · 1200 | Dated interpretive city and its documented uncertainty | Source record and stable modeled objects |
| `serviced` — Serviced city | Additional occupied plots within the same authoring wards | Every baseline house retains its ID, position, dimensions and appearance |
| `expanded` — Expanded city | Further infill over the same city framework | Existing landmarks, principal streets and baseline houses remain |

“Serviced” is a creative design label; the current implementation adds visual
infill, without calculating a working water network, repair schedule or capacity.
“Expanded” currently increases occupation within the authoring wards; it does
not attest a later historic wall circuit or a dated suburban expansion. Further
harbor projects, civic rebuilding and changes to institutions can be authored
as explicit variants. The workshop supplies placeable design objects for such
experiments and keeps their saved data separate from the baseline.

There are no population thresholds, construction costs, unlocks, time advancement
or campaign effects in these states. A town-hall-style progression in another
city can use its own cultural institutions; Constantinople's growth should not
be expressed solely by enlarging one hall.

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
