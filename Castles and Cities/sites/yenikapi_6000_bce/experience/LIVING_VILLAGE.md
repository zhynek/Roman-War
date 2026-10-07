# A Living, Readable Village — 0.7.0

**0.9.0 — A Village at Your Fingertips:** illustrated bottom commands, building improvements, current/planned models and a connected growth guide. Choose **New village** or **Load saved village**. [Controls and unchanged save contract](VISUAL_COMMANDS.md).

**0.8.0 — Preparedness Put to the Test:** [Gameplay, warning, recovery and wrapper-7 save contract](PREPAREDNESS.md). Choose **Begin warning, response and recovery**. Older living saves adopt explicitly from Incidents; earlier chapters remain available.

Choose **Begin living village** from the management introduction. This begins the
same 30 residents, 100 provisions and 30 timber. Existing chapters remain available.
For an existing land-planning save, **Village → Adopt work and preparedness** is an
explicit change of resource semantics. Save a backup before adopting. No supplies,
finished equipment, expert individuals or completed projects are granted.

## Govern and observe

The Village overview exposes woodland allocation, preparation, watch focus,
training, kit maintenance, projects, finite assignments and a seasonal forecast.
Use ordinary reserve, care and project priorities from Assets and Principles.
You can remain here and govern effectively. The seven-step Guide connects this
work to the existing land growth-readiness review and town milestone; there is
no new population threshold.

Choose a woodland, household, working room, store or post and **Ask about current
work**. Clicking the same place in the world dispatches the same deterministic
`living_inspect` command. People retain their household relationship and their
routine panel links to household knowledge. **Visit** changes only the camera.
Discoveries enter a persistent planning record in Village. Repeating an inspection
cannot earn resources, practice, work or another reward. A later staffed meeting
can change what there is to learn from the same subject.

## One seasonal material chain

| Step | Requirement | Result and limit |
|---|---|---|
| West woodland | Existing automatic timber crew | 3 timber per adult, capped by 60 standing units; 6 recover per season |
| Upper woodland | Same crew, selected through standing area order | 5 timber per adult less 2 for its unsupported approach; 72 standing units; 6 recover |
| Northern support | Completed northern observation initiative, northern focus, two ordinary home watch adults and adequate watch condition | Removes the upper approach loss; gathering above recovery depletes the stand |
| Household fuel | 2 opening timber each season | Competes with every other use; shortfall contributes −4 wellbeing target |
| Ordinary preparation | One adult, one working place, 2 opening timber | One prepared set: selected/shaped wood and collected/worked plant bindings |
| Shared preparation | Completed shared-room project, two adults from the complementary households, two working places, 2 timber plus 1 support timber | Initially one set. Recognized cooperation supported for two seasons produces two sets per active season |
| Watch kit initiative | Existing watch shelter; 2 timber and 2 prepared sets paid at commissioning; 12 finite project work | Four serviceable wooden watch kits: shaped staffs, bindings and repair pieces |
| Kit upkeep | Enabled order, one adult, one prepared set and one opening timber | Restores one missing kit, capped at four |
| Watch practice | One additional adult; existing serviceable equipment | Adds one readiness, capped at four; equipment contributes up to 3 protection per ordinary watch adult equipped |

All numbers are game units. Recovery is aggregate usable material, not a claim
that a mature tree regrows each season. No species, elapsed travel time, bow recipe
or individual hauling ledger is represented. Bindings have an explicit labor
requirement inside preparation; there is no separate unlimited supplies market.
Prepared sets are bounded at 12. They support a real decision about preparing
material ahead of construction, procurement or repair without a large item catalogue.

Fuel is reserved first from opening timber, then existing access/asset upkeep and
preparation requests compete in the normal priority allocator. Future harvest
cannot pay those opening bills. There is exactly one adult assignment and one
material ledger. Children do not join crews. A partially staffed preparation or
repair request releases its workers and buys no result. Shared sessions consume
construction places; a compact layout retains its existing space costs. Care,
food reserves, travel parties and projects keep their existing requirements.

Commissioned material is paid immediately. Standing preparation, area, training,
repair and patrol orders remain revisable before resolution. Cancelling unfinished
kit work refunds the same unused fraction of prepared sets as of timber; completed
work is never refunded. The forecast shows current assignments, expected output,
opening commitments and next standing woodland. The report records actual results.
Watching citizens walk, work or arrive never resolves any of these quantities.

## Households and cooperation

Every authored household has persistent woodland and shaping experience (0–8).
The west yard household starts with woodland experience, the upper household with
shaping experience. These are fictional starting circumstances, not ancestral
abilities or permanent professions. Adults rotate through ordinary duties. Actual
timber or preparation/repair duty adds at most one relevant household experience
per season. The shared-session allocator automatically includes an adult from each
participating household, without giving the player individual orders.

The causal sequence is: inspect practical interests; commission the 8-timber,
12-work adaptation of `yk_house_06`; schedule a real two-adult session; inspect the
working room or participating household to recognize cooperation; authorize its
continuing support; sustain two supported seasons. Only then does an active shared
session gain its extra prepared set. The room alone provides no production bonus.
Switching it off releases the ongoing material, labor and space cost; experience
and the planning record persist. If either household has no active adult, shared
sessions wait. The adaptation adds portable sorting arrangements to the existing
room and retains its older objects, door, identity and land adaptation.

Discoveries cover woodland experience, shaping, the relationship, northern access
and recurring kit wear. Their prerequisites use saved work and knowledge; there
is no random treasure, pixel hunt, camera reward or automatic expert unlock.
Targeted overview investigation can find all the same information as exploration.

## Local preparedness

The watch leader controls post initiatives, focus, training, maintenance and kit
procurement. The steward controls wood allocation, preparation and shared support.
God coordinates both with the same costs. Named authorizations and current office
responsibility use the existing decision record and survive succession.

The landing shelter and northern observation point provide four named protection
when staffed and adequately maintained. Northern access additionally needs two
ordinary watch adults. A training adult is separate; carriers and escorts cannot
also cover a post. Equipment allocation is limited by ordinary home watch staffing
and available kits. Every fourth active-phase season with equipment deployed wears
one serviceable kit. Repairs use opening prepared material, so newly prepared sets
cannot repair equipment in that same season. Training knowledge persists, but
unmaintained or absent equipment contributes no equipment protection.

Bows and arrows are deferred. The reviewed archery evidence is geographically and
chronologically distant and documents components beyond timber. This phase uses
explicitly hypothetical wooden watch kits, not a local archaeological weapon
reconstruction. There are no tactical attacks, soldier commands, standing-army
simulation or calls into the parent campaign's BattleResolver.

## Recovery and comparison

The competent overview strategy protects reserves, improves cultivation and
storage, commissions the watch shelter, uses ordinary preparation and maintains
and trains the watch. The attentive example pays for the shared room and northern
post, investigates the relationship, supports it and rotates woodland when upper
standing material becomes low. Both start identically and use public commands.
Forty seasons produce full food stores and equal serviceable equipment/readiness;
the attentive example retains more timber after its additional investment. This
is a reproducible example, not proof of a globally optimal strategy. The actual
numbers and exact-app evidence are in `../VERIFICATION-0.7.md`.

Overcommitment is recoverable: stop preparation/training, pause project crews,
raise reserve priority and retain ordinary care/watch. Unfinished commissions can
be cancelled; completed buildings and land costs persist. No rescue grants are
needed. Woodland recovers during rest. Compact and outward development retain
their different working-space/access requirements and the original town review.

## Save, content and presentation contract

Old saves backfill only `living: {}` and keep their previous resource semantics.
Active living rules use wrapper **6**, base rules/state version 1 and living
extension version 1. Wrappers 1–5 retain their meanings. Atomic validation,
readback and rename remain the save boundary. Reference bookmarks, medieval
creative saves and campaign saves are never opened or migrated by these rules.

The extension stores version/start, area, preparation/cooperation/training/repair/
patrol standing orders, per-area standing material, household experience,
inspected subjects, dated discovery IDs, meetings/cooperative practice, prepared
sets, kits/readiness/wear, tutorial step and the last resolved report. Completed
projects, construction progress and paid material remain in the original ledger.
No routes, meshes, individual destinations, animation clocks or camera state have
simulation authority. Unknown/invalid IDs, impossible inventories and malformed
reports are rejected.

`living.json` owns prose, stable relationships, area limits and project definitions;
`balance.living` owns shared rates. Closed schemas and `validate_living.py` check
references and tuning readers. `living_rules.gd` remains scene-free.
`living_panel.gd` and `living_view.gd` adapt the same commands/state. Living work
uses existing household routing, original procedural props, drawn/picked work
bounds and the same collision shapes as walking. Woodland bands represent stored
seasonal state; every gesture is illustrative.

Terrain queries cache exact samples. Unchanged ground footprints permit individual
fabric replacement while retaining the surrounding world and citizen presentation.
Footprint changes still use the full terrain rebuild. Collider changes invalidate
navigation caches, and all old model exports must remain byte-identical. There is
no asynchronous economy; long synchronous work remains a measured limitation.

Run all old gates plus `validate_living.py`, `test_living_data.py`,
`living_checks.gd` and actual `living_preview.gd`. The release builder repeats the
checks and rendered chapter inside the exact universal Mac application. Preserve
prior releases and stable campaign latest. Keep QA imagery outside the repository.
