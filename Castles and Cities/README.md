# Castles and Cities

An independent city-design workspace for Roman War. Start with
**Constantinople, circa 1200 CE**, in the Byzantine Empire. The objective is a
historically defensible, eventually hyper-realistic city: terrain, streets,
buildings, interiors, infrastructure and everyday occupation, not just a skyline.

This folder now contains an **explorable, original procedural 3D study of
Constantinople circa 1200**, in its own Godot project. It includes city-wide terrain
and urban fabric, detailed landmark assemblies, architectural inspection, visual
stages, a creative workshop and a GLB export tool. Historical identities inform
the scene; most footprints, streets, terrain, interiors and ordinary buildings
remain interpretive. This is not a surveyed reconstruction or a constraint-based
CAD model. No new playable faction, campaign rule or save field is introduced.

## Early-settlement phase

The separate [Yenikapı village, circa 6000 BCE](sites/yenikapi_6000_bce/README.md)
now explores a much earlier settlement context on the historic peninsula. Its
plan and furnishings are interpretive, its evidence is separately classified,
and its explicit object lineage is a foundation for later authored scenarios.
Only the village is implemented; no continuous development into the medieval
capital is asserted. The circa-1200 project and downloads remain available.

## Start here

| Resource | Use |
|---|---|
| [Standalone city project](realms/byzantine_empire/cities/constantinople_1200/experience/project.godot) | Open the independent 3D experience in Godot 4.4 |
| [City catalog](CATALOG.md) | Find cities by realm, period and design role |
| [Constantinople brief](realms/byzantine_empire/cities/constantinople_1200/README.md) | Understand the selected city and reconstruction boundary |
| [District atlas](realms/byzantine_empire/cities/constantinople_1200/ATLAS.md) | Work on one district and its physical capabilities |
| [Development stages](realms/byzantine_empire/cities/constantinople_1200/STAGES.md) | Compare historical snapshots and plan creative growth |
| [Evidence register](realms/byzantine_empire/cities/constantinople_1200/SOURCES.md) | Check sources and what they actually establish |
| [CAD and rendering guide](MODELING.md) | Establish scale, geometry, material and review conventions |
| [Next modeling session](realms/byzantine_empire/cities/constantinople_1200/WORKPLAN.md) | Spend a session on one concrete, reviewable piece |
| [New-city template](templates/README.md) | Add another kingdom, empire, city or castle study |

## Organization

```text
Castles and Cities/
  catalog.json                         # machine-readable research index
  schemas/                             # authoring metadata, not game schemas
  tools/validate_studies.py             # independent authoring validation
  templates/                           # reusable study starter
  realms/
    byzantine_empire/
      README.md
      cities/constantinople_1200/
        study.json                     # period, district and stage inventory
        README.md / ATLAS.md / STAGES.md / SOURCES.md / WORKPLAN.md
        experience/                    # standalone Godot app and editable source
          data/ / schemas/ / src/ / tools/
        models/README.md                # model/export map and future CAD schedules
        variants/README.md              # creative stage and workshop conventions
```

Each city owns its research, model source, review notes and creative variants.
`realm_id` is a research grouping, not a Roman War faction ID. The structure
supports kingdoms, empires and independent city-states without forcing them into
one political form. A castle can be its own study or an assembly within a city.

## Historical fidelity and freedom to design

Keep the historical baseline dated. Record evidence separately for an object's
existence, its location, its dimensions, its appearance and its condition in that
year. An extant monument can have strong evidence for its location and weak
evidence for its medieval roof, furnishings or adjacent houses.

Creative studies start as separately named variants of a baseline. They carry a
change ledger, including the reason for each addition or redesign. The baseline
remains available for comparison. Constantinople has two built-in hypothetical
infill stages and an interactive workshop for placing, transforming and saving
original design objects. These are independent city-study tools.

Development stages describe visible city fabric: retained streets, new wards,
repaired walls, water access, larger institutions and changed densities. Historical
dates are not the game's settlement levels. Capability records describe the
physical space required for trade, governance, defense or craft, without assigning
gameplay bonuses.

## Independence from the game

The repository's [architecture contract](../CLAUDE.md) remains authoritative.
The `.gdignore` marker keeps this workspace outside the parent game's Godot
resource import. The city experience has its own `project.godot`, scene and
application storage; open that project directly to run it.
The campaign's explicit content loader does not load these files. The modern
playtest packager copies selected runtime directories; the older realism preview
packager can copy the workspace as source, so do not treat `.gdignore` as a
general archival exclusion.

Keep original procedural geometry and material source here. The repository's
no-image policy still applies: reference photographs, rendered previews, video,
scans and generated binary exports belong outside the repository. Record their
sources and external artifact locations in a review note. Link a source without
copying its protected map, model or photograph.

Future game integration is a separate change through the existing content,
presentation and BattleResolver boundaries. Previewing a city must never advance
time, RNG, construction, movement or combat. No current workflow here reads or
writes campaign saves.

## Check the workspace

From the Roman War repository root, using Python with `jsonschema` installed:

```sh
python3 "Castles and Cities/tools/validate_studies.py"
```

This checks the catalog, study metadata, local file references and source/stage/
district relationships. It cannot certify historical truth or geometric accuracy.
The standalone app also has its own data, determinism and geometric-exclusion
checks in `experience/tools/validate_city.py`; pass `--godot /path/to/godot` to
exercise its generator. Inspect actual city renders separately. Any later
campaign/map integration must pass every gate in the repository's `AGENTS.md`.
