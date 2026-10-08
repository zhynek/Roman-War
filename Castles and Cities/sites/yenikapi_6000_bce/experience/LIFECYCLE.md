# City lifecycle: one continuing settlement

The playable sequence is **Small village → Large village → Town**. Pay for the
assembly shelter, then adapt that same building into a civic house after sustained
town support. Both promotions open separately paid investments. Large town, Small
city, Large city and Metropolis remain planned; town adds no residential density.

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
that experience. Each season one household gains one point of shaping experience
when one of its adults actually prepares or repairs; the factor reads the best
household. When prepared sets are full (12), the preparation order does no work
and practice stops; the factor then says so. Spend sets on watch equipment,
repairs or incident preparations to continue. Meet the food, housing, community
and foundation requirements, then maintain them for the required resolved seasons.

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

## A Town That Works — 0.12.0

After adopting the lifecycle, choose **Enable town development**. This explicitly
extends an existing wrapper-8 profile; merely loading or inspecting it changes
nothing. You can enable it before promotion. The planning room remains available
through the earlier working-room adaptations.

The town readiness panel reads the existing local town-support rules directly:
40 residents, eight six-person dwelling equivalents, two seasons of provisions,
65 wellbeing/cooperation/security, and all seven foundational capabilities
(including their compact/outward equivalents), sustained for four resolved
seasons. These are current balance values, not a second definition. A failed
support season resets the counter; restoring the named factor and sustaining it
reopens commissioning. Neither overseas supplies nor foreign trade is required.

Pay **22 timber and 36 work** to adapt the assembly shelter into a civic house.
Commissioning must leave the existing lifecycle food/fuel reserves. The quote
shows payment, remaining stocks, work and named blockers. This is revision 1 → 2
of `lifecycle_assembly_shelter`, on the same assembly-ground successor chain.
The doorway, footprint, mat and shared-household association remain. Ordinary
crew limits, priorities, pause and proportional cancellation refunds still apply.

The completed house earns Town and replaces the earlier one-adult civic duty
with **two adults in total** from the existing finite allocator. It does not
construct the following facilities, grant supplies, repair condition or relocate
households. Those choices are optional:

| Separate investment | Price / work | Implemented benefit and reason to choose it |
|---|---|---|
| Material-preparation store | 16 timber / 24 work | Adapt the existing small store `yk_house_04` without discarding containers. An active preparation order produces **+1 prepared set**: 2 total for basic work, up to 3 with practiced shared work. Each extra set consumes **1 additional timber and 1 additional work place**; existing storage capacity still caps output. Choose it first for equipment and incident preparation. |
| Shared provision service | 14 timber / 24 work | Fit the existing care shelter `growth_care_shelter`; retain its care use and furnishings. **1 additional adult** protects up to **6 provisions per season** from actual spoilage (6 total reduction, capped at the loss). Choose it first to preserve a substantial reserve. It never creates food. |

Both benefits require the completed civic house, fully staffed civic duty and
stores condition at least the existing maintenance threshold (currently 50).
The preparation order also needs its ordinary workers/materials/places; switching
it off produces nothing. The service must staff its own additional adult.
Requested duty may remain unfilled because essential food, watch, production,
maintenance or a higher-priority project uses the same adults. The panel shows
actual civic staffing, store condition and next-season extra output/saved food.

Civic duty and the provision service are allocated as care-class work, so each
staffed adult also counts in the wellbeing and cooperation factors at the ordinary
care rates (6 and 3 per adult). The forecast shows that contribution under its own
**Civic and service duty** factor rather than under household care. This is the
existing allocator convention, not a separately authored benefit; it is recorded in
the 2026-10 progression audit as a balance question. The provision service only
protects provisions from spoilage below the storage cap; at full stores the same
provisions become overflow, so its measured value is during recovery.

An understaffed town keeps its earned rank, buildings and paid work, while these
benefits stop. Reduce construction crews or pause optional work to release adults.
Enable store maintenance and retain repair timber if condition is the blocker.
The existing priority numbers are visible in the allocation review. Town duty
has priority 6 and service 7; large-village duty retains its original priority 4.
Rank is an achievement; reversible economic support remains a separate measure.

Older saves with recognized town achievement retain that rank. Once they enable
town development, the readiness view directs them through any missing assembly
shelter and civic-house fabric in order. They pay the ordinary prices and work;
recognition waives repeating the earned readiness milestone. Dependencies still
apply. Recognition supplies no building, duty or duplicate promotion benefit.

## Content and persistence

`data/lifecycle.json` defines profile `village_lifecycle_v1`, stage metadata, the
retained first transition, an explicit civic-project reference, closed all-of/any-of
predicates, three bounded projects,
site successors and interface copy. Structured benefit targets validate cumulative
effects and successor capacity; interface quantities derive from the actual
effects and site records, including both incremental and total values.
`balance.lifecycle` supplies prices, work,
incremental effects, readiness thresholds, reserves and finite civic staffing.
Projects reuse the existing queue and ordered completion ledger.

The optional `lifecycle.town` **content** block and `balance.town_lifecycle` define
`town_responsibilities_v1`: one transition referencing `town_support`, three paid
projects, two additional neutral sites and explicit successor proposals. The
runtime resolves `town_support` through the same factor function as legacy town
support; the original values and behavior stay unchanged.

The optional **saved** `lifecycle` extension stores profile/version identity, a hash
of semantic definitions, adoption turn, explicit legacy recognition and the
next-transition readiness memory. Civic stage and unlocks are derived from
recognition plus completed civic projects. The counter is bound to a transition
and evaluated only after a resolved season. Adoption and promotion reset it;
queries, saving, loading and rendered frames do not advance it.

A saved lifecycle without town adoption retains the exact published
`village_lifecycle_v1` semantic hash
`a4694114cc755d8f5a2113daabf71370a8b85824acc1317dbe973c3555f1fe35`.
`lifecycle_town_begin` adds only `{version, profile, definition_hash, started}` in
`saved_state.lifecycle.town`, records the adoption event, and selects/resets the
next transition's existing readiness memory if needed. Its separate semantic
hash includes the retained base hash, town definitions/tuning and authoritative
town-support values, land equivalents and directly read maintenance/preparation
values. No paid queue entry or original profile hash is rewritten.
An actual frozen 0.11 paused paid save is retained as a compatibility fixture.
Old 0.11 applications reject adopted town saves. Town-only saves require 0.12
or newer; subsequently adopted warfare saves require 0.14 or newer. Do not open
an adopted wrapper-10 save in an older local app.

Lifecycle/town adoption alone still uses **wrapper 8**; no new wrapper is needed
for those profiles. Explicit defense adoption selects wrapper 9; warfare selects
wrapper 10. Wrappers 1–7 retain their earlier meanings. An older save gains only inactive `lifecycle: {}` until adoption.
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
checkout, fresh parent logs, exact-app checks and manual image inspection. The verified 0.11 build remains preserved. Town acceptance and 0.12 delivery
are recorded in [the town verification record](../VERIFICATION-0.12.md).
This work does not publish a release.

Town adds `validate_town.py`, `test_town_data.py`, `town_checks.gd`,
`town_preview.gd`, `lifecycle_profile.gd` and `town_profile.gd` to those retained
gates. `town_driver.gd` supplies compact/outward 100-season public-command recipes.
The checks write saves and replayable recipes for readiness, commissioning,
partial work, promotion, both investments, civic labor stress and recovery under
`out_dir=/tmp/yenikapi-town-states`. Every recipe is replayed from the ordinary
initial state and compared exactly, including its SHA-256 digest. The rendered
walkthrough records its actual UI commands, rolls back its trace on explicit Load,
and replays the resulting continuing game. Source and exact-app recipes/digests
must match. The build retains all 41 existing GLBs and adds three separately named
Town models of the paid finished rooms.

## October 2026 warfare integration

The lifecycle-active interface calls the legacy reversible milestone **Town
support**, including contracted support after a shortage. Earned Town remains
separate. Town civic duty stays at priority 6 and provision service at 7; both
retain the existing care-class social contribution (+6 wellbeing/+3 cooperation
per allocated adult), named **Civic and service duty** in the breakdown. This is
community coordination, not an additional assignment as a household carer.

Warfare does not require this lifecycle. Its explicit wrapper-10 profile needs
Living village and its earlier chapters. It uses the same finite allocator for
ordinary watch, priority-4 training and additional watch, priority-2 treatment,
food, civic duty and paid work. Training and additional watch have their own
security factors; their sum preserves the existing watch-class total. No adult
can be both mobilized and assigned to civic duty or treatment.

The material-preparation facility can supply paid kit replacement and repair
after a battle. The provision service offsets actual spoilage during recovery;
when storage is full its benefit can become overflow. These are situational
consumers, not a new population tier or a guarantee that every facility pays back
in a quiet village. The provision card is accessible from Homes (its physical
care room) and Stores (its retained published project association); both quote
and execute the same single project. Household learning-circle participation is
explicitly illustrative; practical shaping, watch readiness and engaged combat
experience remain the separate rule-bearing skills.

The expanded **How to play** dock guide explains civic and defense choices
without issuing them. Setup/adoption remains explicit; opening a lesson changes
no village state. Large town and conquest remain future content. See the
[integration review](../../../../docs/reviews/2026-10-city-warfare-integration.md)
for the combined plan and evidence.
