# City lifecycle: one continuing settlement

The first lifecycle slice implements **Small village → Large village** through a
paid assembly shelter, followed by separately commissioned store and workroom
improvements. The ladder also names Town, Large town, Small city, Large city and
Metropolis as planned stages. Those later transitions are not playable yet.

This is the hypothetical village scenario. It does not connect the dated Yenikapı
reference to medieval Constantinople or establish a continuous historical sequence.
The civic institution, balance values and construction choices are game design.

## Play the first transition

Open **City lifecycle** in the village commands, or its section in the growth
view. God can choose **Begin city lifecycle**. Older saves must explicitly adopt
Asset governance, Land planning and Living village first, through their existing
chapters. Loading a save, inspecting a place or opening this view adopts nothing.

The readiness view shows named current and required values, including sustained
support and practical wood-shaping experience earned by actual household work.
Prepare wood through the ordinary living orders; inspection alone cannot create
that experience. Meet the food, housing, community and foundation requirements,
then maintain them for the required resolved seasons.

Review **Build an assembly shelter** and commission it when eligible. The quote
uses the authoritative project price, remaining work, assigned crew, reserves and
civic obligation. Timber is paid immediately. The ordinary finite adult allocator
completes the work; priority, crew limits, pause and cancellation use the existing
construction controls. A shortage does not confiscate paid progress. Cancellation
refunds only the existing unused-work share of the original timber payment.

Completing the shelter earns Large village. From the following season, civic duty
requests an adult from the same finite workforce. Then choose either improvement:

| Commission | Carryover and change |
|---|---|
| Organize the enlarged store | Requires the existing enlarged store. `yk_store_01` keeps its identity, coordinates and furnishings and moves from revision 2 to 3. Only the declared incremental storage effect is added. |
| Organize the adapted working room | Requires the existing land adaptation. `yk_house_06` moves from revision 2 to 3, retaining its doorway, furnishings and condition. The site supplies its newly authored total construction places. |

Neither improvement is granted by promotion. Existing provisions, woodland,
people, households, practice, offices, principles, paid projects and history remain.
Asset condition does not reset. Compact homes continue occupying former working
ground; outward homes retain their access obligations. No household is displaced.
The price, work, readiness and staffing values live in `data/balance.json`.

The older reversible **town support** milestone continues to serve its existing
readers and optional contacts. It is separate from civic achievement. A settlement
can lose support without losing an earned civic rank. An older save that already
achieved town receives explicit town recognition on adoption; this grants no
physical civic building, people, materials or free improvements.

## Content and persistence

`data/lifecycle.json` defines profile `village_lifecycle_v1`, stage metadata, the
one active transition, an explicit civic-project reference, closed all-of/any-of
predicates, three bounded projects,
site successors and interface copy. Structured benefit targets validate cumulative
effects and successor capacity; interface quantities derive from the actual
effects and site records, including both incremental and total values.
`balance.lifecycle` supplies prices, work,
incremental effects, readiness thresholds, reserves and finite civic staffing.
Projects reuse the existing queue and ordered completion ledger.

The optional `lifecycle` extension stores only profile/version identity, a hash
of semantic definitions, adoption turn, explicit legacy recognition and the
next-transition readiness memory. Civic stage and unlocks are derived from
recognition plus completed civic projects. The counter is bound to a transition
and evaluated only after a resolved season. Adoption and promotion reset it;
queries, saving, loading and rendered frames do not advance it.

Active lifecycle saves use **wrapper 8**. Wrappers 1–7 retain their earlier
meanings. An older save gains only inactive `lifecycle: {}` until adoption.
Atomic validation, temporary-file readback and rename remain the save boundary.
The reference bookmark, medieval study and parent campaign keep separate saves.

Active profiles reject a changed semantic definition hash. Future authors must
retain the published profile or implement an explicit migration for changes to
costs, work, prerequisites, effects, fabric or site semantics. Interface prose
and presentation labels are excluded from that hash. Do not reinterpret an
in-flight paid project by silently changing its price or predecessor.

## Ordered physical continuity

`src/core/fabric_projection.gd` replays each completed project as one transaction.
New changes state `expected_revisions` for every predecessor; additions use an
empty map. Duplicate mutation inside a transaction, stale revisions and competing
queue claims are rejected. A later paid transaction may alter the same object
again. Provenance records the project and revision, while immutable authored data
reconstructs the history; meshes are never saved.

Commands, quotes and save validation check this projection before accepting an
active state. Presentation uses the same projection. Legacy fabric outputs remain
unchanged. Land successor proposals name their completed predecessor and retain
the previous use during work when authored to do so. The latest completed use
supplies the site total; earlier entries remain in history.

## Reproduce and verify

Run from this independent experience with Python `jsonschema` and Godot 4.4+:

```sh
python3 tools/validate_lifecycle.py
python3 tools/test_lifecycle_data.py
godot --headless --path . --import
godot --headless --path . --script res://tools/fabric_lifecycle_checks.gd
godot --headless --path . --script res://tools/lifecycle_checks.gd -- out_dir=/tmp/yenikapi-lifecycle-states
godot --path . --max-fps 10 --script res://tools/lifecycle_preview.gd -- out_dir=/tmp/yenikapi-lifecycle-render
```

`lifecycle_driver.gd` replays ordinary public commands for compact and outward
strategies. Rule checks save canonical entry, partial-work, promotion and upgraded
states through the actual save writer, with reproducible command recipes and
state digests. These temporary fixtures let a stage be inspected without editing
a player's rank or save. Continue from the preceding stage to check equivalence.

Inspect the rendered requirements, commission, paid work, civic completion and
individual upgrades at 1280×800. Check the same buildings, furnishing continuity,
doors, picking and citizen paths; idle frames and previews must preserve state.
All QA images remain outside the repository. These gates supplement every retained
village suite and the parent's data/import/full-suite/map gates.

The release builder runs lifecycle data/negative checks before export, then both
new rule suites and the rendered sequence on source and the exact app. It preserves
the existing 41 neutral model exports. Packaging requires a clean committed
checkout, fresh parent logs, exact-app checks and manual image inspection. This
implementation does not itself publish a release or claim packaged verification.
