# Castles and Cities

An independent city-design workspace for Roman War. Start with
**Constantinople, circa 1200 CE**, in the Byzantine Empire. The objective is a
historically defensible, eventually hyper-realistic city: terrain, streets,
buildings, interiors, infrastructure and everyday occupation, not just a skyline.

This folder establishes the research and authoring foundation. **It does not yet
contain a finished CAD model, a 3D city, or a renderer.** The first modeling task
is defined in the city's work plan. No new playable faction, campaign map,
balance rule or save field has been introduced.

## Start here

| Resource | Use |
|---|---|
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
        models/README.md                # future original parametric source
        variants/README.md              # future creative alternatives
```

Each city owns its research, model source, review notes and future variants.
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
remains available for comparison. This is an authoring organization now; an
interactive creative-mode editor remains future work.

Development stages describe visible city fabric: retained streets, new wards,
repaired walls, water access, larger institutions and changed densities. Historical
dates are not the game's settlement levels. Capability records describe the
physical space required for trade, governance, defense or craft, without assigning
gameplay bonuses.

## Independence from the game

The repository's [architecture contract](../CLAUDE.md) remains authoritative.
The `.gdignore` marker keeps this workspace outside Godot's resource import.
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
These design-only files do not require starting Godot. Any later runtime/map
integration must pass all gates in the repository's `AGENTS.md`.
