# Separate dates, explicit fabric changes

`village → town → large town → small city → large city → metropolis` are authoring
categories. They are not an established Yenikapı chronology, campaign levels,
population thresholds or promises of continuous growth. The dated reference remains **village**. Release 0.2.0 adds a separate hypothetical
seasonal tutorial with a reversible **town** authoring milestone.

The dated snapshot `yenikapi_c6000_bce` and medieval `reference_1200` have separate
projects, coordinate frames, evidence ledgers and saves. Neither is a successor
record of the other. A later dated reconstruction must be researched independently,
especially through inundation, settlement movement and long chronological gaps.

`src/fabric.gd` is a scene-free deterministic resolver for **hypothetical** change
sets. A change set names its base snapshot and explicit objects. It never runs from
a timer, elapsed years, population or frame callback. Unmentioned records survive
unchanged. The 0.2.0 tutorial now exercises these explicit changes through commissioned
projects. It has its own scenario, integer simulation, save and growth UI; it is
not another historically dated reconstruction.

| Relationship | Identity and history |
|---|---|
| `added` | New ID, revision 1, no predecessor |
| `retained` | Same record and revision; no regeneration |
| `altered` | Same ID, next revision, predecessor `id@previous_revision`; can change use, form or reactivate abandoned fabric |
| `replaced` | New ID(s) point to old revision(s); old records remain inactive |
| `subdivided` | At least two new records explicitly point to parent revision(s); parents remain inactive |
| `removed` | Same ID retained as an inactive tombstone, next revision |
| `abandoned` | Inactive fabric retained with an abandonment relationship; no assumed demolition |

New paths, markets, public institutions, infrastructure or defenses would be
explicit objects with new renderers and reviewed evidence when warranted. A path
can keep its ID through widening or change of use; houses need not all change at
once. Household membership is a separate stable group ID, not an inferred person.
Furnishing identities are namespaced by their building ID.

Baseline records have `revision: 1` and `change: {kind: "added", predecessors: []}`.
“Added” means introduced to this model, **not** historically built in 6000 BCE.
Scenario inputs use `before` IDs and full `after` records. The resolver rejects
wrong bases, duplicate/missing predecessors, reused identities, alterations that
change identity and single-child subdivisions. It copies inputs and sorts results
by ID. Material, geometry and collision generation is repeatable from IDs/data.
This is a minimal authoring foundation; undo/redo, a full versioned archive,
general authoring UI remain future work. Tutorial persistence and its bounded
commissioning UI are documented in [GOVERNANCE.md](experience/GOVERNANCE.md).


Release 0.3.0 adds optional contact with two fictional aggregate communities.
A commissioned meeting room/path uses new explicit IDs; contact progress never
upgrades other buildings or asserts a new dated snapshot. The contact chapter
is a relationship achievement after town, not a large-town stage. Finite supplies,
reserves, separate office terms and mission IDs provide a reusable interaction
boundary; regional settlement geometry and multi-town growth are still future work.

Asset governance 0.5.0 changes management of the same hypothetical settlement.
Its housing coordination invokes existing project/fabric IDs and leaves the dated
reference unchanged. Maintenance conditions are group-level gameplay state, not new
archaeological phases. There is no new urban category or population threshold.

Land planning 0.6.0 introduces bounded hypothetical alternatives within the same
village. Completed projects retain their original ledger and explicit lineage.
The repaired workroom keeps its ID at revision 2; converted fields/work areas
remain inactive tombstones. Household additions do not replace occupied homes.
The original town criteria accept equivalent spatial foundations, without a new
population threshold or any claim of continuous prehistoric-to-medieval growth.
