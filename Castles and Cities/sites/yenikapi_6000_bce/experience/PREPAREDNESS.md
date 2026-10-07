# Preparedness Put to the Test — Warning, Response, and Recovery · 0.8.0

**0.9.0 — A Village at Your Fingertips:** illustrated bottom commands, building improvements, current/planned models and a connected growth guide. Choose **New village** or **Load saved village**. [Controls and unchanged save contract](VISUAL_COMMANDS.md).

Choose **Begin warning, response and recovery** in the management introduction.
The starting village still has 30 residents, 100 provisions and 30 timber. Use
**Incidents**, **Village**, **Assets** and **Guide** to govern through ordinary
commands. Residents remain autonomous; looking, waiting and animation produce
no resources, protection or repair.

An existing living village can explicitly **Adopt incident seasons** in Incidents.
This replaces the older abstract repeating supply-pressure loss with two local
incidents. It preserves people, layouts, paid queues, progress, principles,
contacts, household memories, discoveries, equipment and all standing orders.
The older eight-season household teaching episode must have settled first and
cannot restart after adoption. It remains available in its original chapters.

## Warning and decisions

Each incident develops for four seasons before signs can be observed. Targeted
inspection of the affected place, linked households or workroom records exactly
the information available through world inspection. Inspection pays nothing and
changes no outcome factor. Relevant maintained observation with two home watch
adults reports signs automatically. Experienced workers gathering upper woodland
can also report approach wear. Every player receives a prominent overview warning
two seasons later, with **two complete governing seasons before resolution**.
Dates are absolute campaign-season boundaries; a warning at turn 6 resolves when
advancing from turn 7 to 8. There are no surprise rolls or hidden real-time timers.

Choose relevant priorities in Village: maintain a post and focus on the correct
place, procure serviceable wooden kits, train the watch, gather and prepare real
materials. Care, food reserves, upkeep, training, preparation and projects use
one finite automatic adult allocation. Maximum watch/training has an opportunity
cost even when its extra protection is unnecessary. Prepared sets contain worked
wood and bindings; bows remain deferred.

A response initiative costs **3 timber and 1 prepared set**, paid immediately,
and **8 work** from the existing project queue. A recovery initiative costs
**4 timber and 1 prepared set**, then **16 work**. Completed preparations have no
recurring reward. Pending work has its own priority, crew budget and pause switch;
cancellation returns the unused fractional share of timber and prepared sets.
Repeated commission/cancel commands cannot pay or refund twice. Material already
paid is unavailable to fuel, kit upkeep or another initiative.

Temporary restrictions are revisable before resolution. Restricting the upper
approach redirects timber crews to western woodland and smaller loads forgo two
timber each season. Restricting waterside work forgoes four provisions of gathering.
Each reduces severity by one. Restrictions cease to affect work after resolution.
They are alternatives to more construction, not free protection.

## Two specific pressures

| Incident | Factors reducing severity | Persistent consequences |
|---|---|---|
| Upper approach wear | Staffed maintained northern access −1; woodland experience at least 4 −1; completed patch preparation −2; restricted hauling −1 | Each severity point reduces northern timber by one per season. At severity 3+, loaded outward access is impaired: outer projects wait and inhabited outer homes receive the existing access penalty. Western access and pedestrian paths remain usable. |
| Uncertain waterside activity and attempted taking | Correct maintained landing post with two watch adults −2; up to two serviceable kits with readiness at least 2, at that post, −1 each; staffed secured stores −1; completed handling preparation −2; restricted waterside work −1 | Loss is four provisions per severity, reduced by up to 12 by completed preparation and capped by actual available food after meals. Each severity point then reduces gathering by one until repair. Severity 4+ wears one available kit. |

Approach exposure starts at 6, plus 2 if outward households depend on it. Waterside
exposure starts at 7. Severity is clamped to 1–7, leaving some work even with strong
preparation. Watch equipment does not mend the approach; northern coverage does
not protect the landing. The forecast names each factor, including zeros. It
includes work that the current allocation can finish in the resolving season;
a paid but paused or unfinished preparation contributes nothing. Forecast losses
and actual capped losses are shown separately. There is no enemy roster, army,
tactical battle, casualty roll or building destruction.

Affected households gain four stress per severity at resolution, plus three strain
per season while the place remains impaired, within the existing household stock.
Ordinary settled recovery and staffed shared care still apply; home wellbeing and
cooperation read the existing memory factors. Dated incident records retain the
household relationship and original outcome after the immediate stress declines.
No incident grants expertise or a permanent production bonus.

## Recovery and the guide

Recovery has no expiry timer. Commission the essential repair, retain its prepared
materials and supply its crew. Pause lower-priority work; disable unnecessary
training/preparation, protect food/fuel, or cancel unfinished commitments to regain
their unused materials. A supported complementary household relationship with its
established two-season practice adds two work to a staffed recovery crew. The room
alone does not help. Repair restores the same place without removing dwellings,
residents, history or older fabric. Kit upkeep continues through its existing
material and labor chain.

One incident can be unresolved. The second begins only after the first is repaired
and eight quiet seasons pass; its own four-season development and two-season
warning follow. **Each type occurs once per adopted campaign in this release.**
Leaving damage unrepaired cannot spawn a failure cascade. Completing or inspecting
incidents creates no new supplies, permanent bonuses or repeatable reward loop.

The seven-step Guide connects signs, local evidence, cost comparison, paid
preparation, resolution, recovery, pausing/resuming work and retained history.
The pause lesson can also be reviewed after a repair already finished. Any layout
and ordinary affordable preparation can satisfy it. The existing town milestone
and growth-readiness review remain; there is no second population threshold or
continuous development into medieval Constantinople.

## Saves and authoring

Inactive older saves backfill only `incidents: {}` and retain their previous
resource semantics. Active incidents use wrapper **7**, base rules/state version
1 and incident extension version 1. Wrappers 1–6 retain their meanings. Atomic
validation/readback/rename is unchanged. Reference bookmarks, medieval creative
saves and parent campaign saves are independent and never migrated here.

The extension stores `version`, `started`, `records`, `tutorial`, and `paused`
(the guide's recorded pause). Each stable incident record stores `id`, `started`,
`signs`, `warning`, `due`, `known`, `inspected`, `restricted`, `outcome`, `recovered`.
Outcome includes the resolution turn, severity, named factors, expected/capped
loss, kit wear and the post-resolution productive penalties. Current penalties derive
from the retained severity and recovery status. Commitments, authorizing office,
author, paid work and completed initiatives remain in the existing project ledger.
Records enforce type/order/timing/subject references, bounded factors, one unresolved
incident, and the recovery interval. Leadership changes never reset commitments.
No random, camera, route, geometry or animation state is authoritative.

`incidents.json` owns incident identities, relationships, prose, projects and guide.
`balance.incidents` owns shared rates, closed by its schema. `validate_incidents.py`
checks project/place/household/post relationships, costs and consumed tuning.
`incident_rules.gd` is scene-free. `incident_panel.gd` and `incident_view.gd` read
the same saved state. Procedural stakes and working materials stay at the edges
of usable walking space, with drawing/picking/collision at the same coordinates.
Citizens illustrate actual assigned destinations; loaded-access impairment does
not pretend to obstruct pedestrian geometry. Store covers, material racks, kits
and shared-care rolls reflect the normal inventories and commitments.

Visible-state signatures retain unchanged geometry and navigation caches; collider
changes invalidate routes. Chapter opening constructs the state once before
refreshing the world. Seasonal UI feedback blocks duplicate input during resolution;
authoritative rules remain synchronous. Interaction timings, not only frame rates,
are recorded in [VERIFICATION-0.8.md](../VERIFICATION-0.8.md). Large physical changes
still have a visible synchronous pause; no Intel performance claim is made.

Run every retained independent/parent gate, plus incident data/negative tests,
`incident_checks.gd`, `incident_preview.gd` and `incident_profile.gd`. The release
builder repeats rules and actual-input rendered acceptance inside the exact Mac
application. Keep screenshots outside git. The 33 earlier model bytes and every
previous public release must remain unchanged; new incident models are separate.
