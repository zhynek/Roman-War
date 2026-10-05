# Governing the village through buildings and shared assets · 0.5.0

Choose **Manage village assets → Begin asset governance**. Ordinary village life
starts immediately, without an attacker. Walk or fly to observe; every decision
is also available from **Assets**. Clicking actual building or shared-space
geometry opens the same panel. The list and guided tutorial use the same
`settlement_rules.command` boundary. Residents can be inspected but have no
command or possession controls. Only the explicitly fictional steward and watch
leader are individually selected as offices; God oversees both. No monarchy,
standing army, tactical battle or continuous history into Constantinople is claimed.

## A complete season

Inspect shared stores, read provisions and the reserve objective, and choose a
standing principle. Commission an affordable initiative through its target asset.
Its timber is committed once, using the existing stock and project queue. Set a
crew budget and priority; the settlement assigns eligible adults automatically.
Read allocated/requested work, unmet needs and the food/stock forecast. Resolve a
season deliberately, then compare actual results, condition, construction progress
and household memory. Explore the resulting activities and interiors at any time.
Watching, arriving, clicking or animating never produces work or supplies.

Seven stable management assets group existing places: stores, households, fields,
landing, workroom, decision yard, and watch/refuge. Grouping is an interface and
institutional interpretation, not excavated ownership. Condition is simulated at
this asset-group level; individual wall damage and household inventories are not.
Household occupancy and memories still use their existing individual IDs. The
panel displays the responsible named office, current commitments, material and
labor requirements, beneficiaries, prerequisites, seasonal effects and refusal
reasons. It does not invent building throughput or vessel-capacity statistics.

## Six standing principles

- **Reserves:** target one, two or three seasons of current population's food,
  bounded by real storage. Additional gathering attempts to close a deficit over
  two seasons. Two/three-season targets allocate earlier than the one-season
  target. The target grants no provisions and does not eliminate winter shortages.
- **Maintenance/expansion:** maintenance first gives a repair crew priority 3;
  expansion first gives it priority 8. The weakest enabled asset below 85 condition
  is considered, with stable asset ID resolving ties. One adult and one available
  timber repair 18 condition; every season wears one, plus one in warning/danger.
- **Care:** ordinary household support reserves two adults. Shared care reuses the
  existing six-timber preparation and those two workers. Store preparation requires
  an additional worker; learning requires two more. These full duties do not overlap.
- **Watch:** productive emphasis requests one home worker at priority 6; ready
  watch requests two at priority 2, beyond any committed escorts. The separate
  existing safe-route preparation requires two home watch workers to operate.
- **Welcoming:** the existing spring arrival policy and its housing, wellbeing,
  cooperation and enlarged-population reserve requirements remain authoritative.
- **Learning:** the existing four-timber preparation needs two dedicated care
  workers and four food of gathering opportunity. During warning/danger its crew
  request waits and releases capacity. Households retain differing learned practices.

Existing rationing remains one policy. Existing store/route preparations remain
one order each; the principles do not duplicate them or their investments.
Neglect below 50 condition reduces store capacity by 30%, food by six for each of
fields/landing, wellbeing by six for homes, cooperation by four for the yard,
protection by eight for watch, or construction yield by one per worker for the
workroom. Named factors expose the social effects. Durable project bonuses and
maintenance costs coexist. Condition never silently demolishes a home.

## Allocation and initiatives

An adult has exactly one full seasonal job; children are excluded. Committed
neighbor carriers/escorts have first call. Essential food follows, then two care
workers and ready-watch requests. Remaining requests sort by priority, then stable
request ID. Existing leaders' skills affect protection and one construction
coordination bonus per season. Adults rotate through the sorted requests by
stable citizen ID offset by turn. Assignment contains duty and asset IDs; it does
not add individual item inventory. A resident cannot be a carrier and a home
worker simultaneously.

Essential food requests the greater of average-year feeding needs or the current
season's uncovered consumption/spoilage/disruption need. Reserve effort, store
preparation and maintenance-first requests have priority 3. Initiative priorities
1–3 map to allocation ranks 4–6. Timber has rank 5; learning rank 6. Remaining
adults gather food. Requests show allocated/wanted counts and why work waits.
Partial care/order crews may contribute ordinary care but cannot activate a
preparation needing its full crew. Special orders use separate counted crews.
Food reserve calculations are objectives, and forecasted pressure losses can
still reduce the resulting stock. Scarce workforce, timber and provisions remain
real constraints.

The existing project ID is its initiative identity and has exactly one target
asset. Active mode adds priority, crew budget, paused flag, authorizing office,
author's citizen ID and authorization turn. Each project receives only its own
allocated work. The steward coordination bonus goes to the first staffed project,
not every project. Pausing preserves progress/material investment and requests no
crew. Cancellation retains the decision record and refunds the same unused timber
fraction as before. Recommissioning pays again and records the new authorization.
Completed benefits and fabric remain in the original completed-project ledger.

**Prepare sustainable housing** coordinates the existing cultivation, north lane,
north home and east home IDs. Each next eligible step uses the same commission
command. Access and housing require at least one season of current provisions
through every interface; cultivation can still be commissioned during shortage. All steps need real timber,
prerequisites and a queue slot. Stopping coordination stops new commissions;
existing ones remain individually pausable/cancellable. This is a multistep
objective across productive land, access, homes and stores, not a parallel ledger.
Its readiness review requires two seasons of supplies for enlarged households.
The existing 40-resident/eight-dwelling town milestone and sustained stock tests
remain the only town milestone; the guide never grants an automatic upgrade.

## Leadership, pressure and presentation

Changing selected office keeps every order. Appointments and automatic succession
retain institutions, projects, resources and household memory. Project metadata
and the decision history retain who authorized work; current responsibility follows
the office's present holder. Abilities and tenure are visible. Citizens are
inspectable autonomous participants in deterministic seasonal allocation; there
is no direct civilian command interface or full character-possession mode.

The optional warning chapter begins through Guide as God. Its existing two-season
warning/danger/recovery/renewal sequence runs once. End of danger is an authored
transition, never a simulated military victory. Beginning it preserves household
memories and paid preparations. In recovery, care and learning compete with
construction and reserves. Unequal household uptake persists.

Store rack contents reflect bounded supply bands and are empty at zero food.
Prepared covers, care rolls and learning pieces express actual preparations.
Repair mats and shallow wall finishes respond to repair/condition. Paid project
materials and partial frames show construction progress. These are original
procedural geometries; none is a second stock ledger. Doors and circulation use
the existing walking collision. The reference and all earlier model exports keep
their original inventories and geometry. Detailed product recipes, emotional
models, military AI, object-by-object hauling and local crowd avoidance remain
outside scope. The authored routines illustrate authoritative duties; citizens
can pass one another and do not block player movement.

## Compatibility and authoring

Old saves add **`assets: {}`** only. They retain manual workforce semantics,
including the earlier shared-care thresholds, until the player explicitly chooses
**Adopt asset governance** in Rules. Activation preserves the manual plan in
`assets.manual_plan`, people, stocks, queue progress, completed fabric, contacts,
paid orders and memories. It recalculates `state.plan` as the current automatic
allocation. There is no implicit migration when opening a save, and this release
does not offer switching active mode back to manual. Keep an older backup if that
comparison is needed. Older save wrappers 1/2/3 remain accepted.

Active assets require save wrapper **4**. Base rules/state versions remain 1;
asset extension version is 1. The extension stores activation turn, preserved
manual plan, reserve/upkeep/watch principles, pressure start (-1 for ordinary
life), conditions, maintenance toggles, initiative metadata, decisions, tutorial
progress and evidence counters, housing coordination, and the last allocation
report. Existing welcome/ration booleans and household orders remain their single
sources of truth. Offices and projects use stable references. Saves contain no
animation clock, mesh, route or camera authority. Readback and atomic replacement
remain required. Older binaries refuse wrapper 4. Parent campaign, reference
bookmarks and medieval creative saves are independent.

`data/assets.json` owns asset relationships, six principles, tutorial conditions,
UI text and coordinated project IDs. `balance.assets` owns rates and thresholds.
Closed schemas plus `validate_assets.py` check references/authority and reject
unused tuning fields. `asset_rules.gd` owns scene-free allocation and commands;
`assets_panel.gd` adapts them to all player surfaces. Every new tuning value must
have an engine reader. Additive future fields need defaults and save tests.

Run `test_asset_data.py`, `asset_checks.gd` and actual `asset_preview.gd`, plus all
retained village, governance, neighbor, household and parent campaign gates.
The rendered guide uses real viewport clicks and real finite stocks. Benchmark
with `benchmark.gd -- assets out_dir=...` separately from captures. The release
builder repeats checks against the exact universal Mac application. Review all
captures outside the repository before publication; record measured stalls and
remaining limitations rather than inferring performance from headless tests.
