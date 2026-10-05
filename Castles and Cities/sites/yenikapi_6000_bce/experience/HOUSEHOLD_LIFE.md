# Households through adversity — optional seasonal chapter

This chapter brings decisions inside the village's home, store and work room.
An authored warning interrupts ordinary routines; care and provisioning help
households through danger, and later learning leaves different memories in each
household. It can begin at village scale. It does not require the town milestone
or neighboring-community chapter, and completing it unlocks no automatic urban
upgrade.

The setting remains a **hypothetical** settlement using the circa-6000 BCE
material vocabulary. There is no documented siege being reenacted. No attacker,
standing army, enemy identity or historical cultural revolution is reconstructed.
Read the [evidence ledger](../SOURCES.md#household-interiors-adversity-and-cultural-change)
for the distinction between local cereal/wood evidence, regional domestic
comparisons and the game's invented reactions. A future siege in another period
needs a separately researched setting and logistics.

## Play the chapter

1. Choose **Play seasonal tutorial**, then begin or load a campaign. As **God**, open
   **Households** and choose **Begin the eight-season household chapter**.
   Starting the chapter does not resolve a season or replace the existing town.
2. Review the circumstance, next-season effects and household memories. In
   **Work**, reserve enough people for food while assigning care and watch.
   These are the same finite adults used by construction and other duties.
3. As steward, prepare stores and shared care. As watch leader, maintain safe
   routes. **God** can issue both offices' orders, with the same costs and labor
   requirements. A standing order retains its setting when roles change.
4. Resolve seasons deliberately. Compare the food forecast and named stock
   factors with the next report. A paid preparation still needs assigned workers
   in every season when it operates; an understaffed order waits.
5. Click a nearby visible resident to inspect their activity; walls and furniture
   block selection. Use the three **Visit** controls to enter the home, store and work room.
   **Residents and routines** lets you select a named citizen, read the activity
   and its reason, then **Visit [name]’s activity** to reach its safe station. This is a
   viewpoint shortcut, not possession or a camera permanently tracking a person.
   Explore on foot or in flight, then return to the panel to change an order.
   Furnishings and citizens illustrate the current circumstance and decisions;
   watching them does not progress the chapter.
6. From recovery onward, enable the learning circle if food and care labor allow.
   Watch households take up the practice at different rates. Disable a standing
   order when its ongoing benefit no longer justifies its opportunity cost.
7. Use **Save campaign** before quitting. The chapter, preparations and household
   memory resume with the settlement. **Return to reference village** remains
   available and restores the original dated scene.

## Orders and costs

| Order | Office | First preparation | Continuing requirement | Effect |
|---|---|---|---|---|
| Secure shared stores | Steward | 4 wood | 1 care worker | Reduces gathering disruption during warning/danger and supports protection |
| Prepare shared care | Steward | 6 wood | 2 care workers | Supports wellbeing and reduces accumulating household stress |
| Maintain safe routes | Watch | 4 wood | 2 watch workers | Reduces gathering disruption and supports protection; adds no wall or army |
| Hold a learning circle | Steward | 4 wood | 2 care workers and sufficient gathering, from recovery onward | Supports cooperation and uneven practice uptake; forgoes 4 food each effective season |

These are reusable preparations: switching an order off and on does not charge
wood again. The counts are fictional teaching rules. Care requirements describe
thresholds within the existing care assignment, not additional citizens conjured
by an order. Safe-route staffing excludes watch workers committed as neighbor
escorts. The staffing display and forecast show whether an enabled order is
effective. A preparation does not create free food or a second seasonal workforce.

Learning also waits unless this season's gathering can cover the 4-food opportunity
cost plus the circumstance's remaining disruption (2 in recovery, otherwise 0).
Gathering uses food workers after subtracting neighbor carriers, plus idle builders,
at the seasonal yield with completed-project effects. Stored food alone does not
meet this capacity check. While waiting, learning contributes no practice or
cooperation bonus and forgoes no learning food.

## Circumstances and household memory

The authored episode has four two-season circumstances, followed by a persistent
settled state:

| Chapter seasons resolved | Circumstance | Household emphasis |
|---|---|---|
| 1–2 | Warning | Bring provisions indoors and prepare support |
| 3–4 | Danger | Restricted movement, care and provisioning |
| 5–6 | Recovery | Resume work while stress recedes |
| 7–8 | Renewal | Share a practice without replacing every household's habits |
| After 8 | Settled | Ordinary routines, continuing memory and chosen standing orders |

Danger does not repeat on a timer after the episode. Its end is authored, not a
battle victory or a promise that precautions defeated an army. The base tutorial's
existing supply-pressure cycle is a separate mechanic.

Each household retains stress and shared-practice scores from 0 to 100. Stress affects
the wellbeing/cooperation factors after the immediate warning has gone; hunger
can worsen it, while recovery and staffed care reduce it. Learning uses a stable
household-specific difference in uptake, so the same care order does not produce
identical results everywhere. Practice persists when teaching stops. These scores
are gameplay memory, not psychological diagnosis, ethnicity, belief or an
archaeological measure of cultural sophistication.

The stress increment is +8 in warning, +16 in danger, −8 in recovery, −5 in
renewal and −3 when settled. Staffed shared care contributes −7; an unmet food
need adds +10. Values clamp to the score bounds. The mean stress of occupied
households contributes negative wellbeing/cooperation factors using divisors
10 and 20. These factors feed the base tutorial's existing slow-stock system;
they are not immediate replacements of its stock values.

Effective learning adds a phase base of 3 in recovery, 6 in renewal or 2 when
settled, plus a stable household affinity of 0, 4 or 8. Affinity derives from the
household ID, consumes no RNG and makes no claim about ancestry or intelligence.
Newly occupied household IDs begin at zero; an emptied household keeps its saved
memory for later reuse. Only occupied households change during a season.

## Interiors and citizen routines

The chapter adds procedural domestic detail to three existing spaces: the home
(`yk_house_01`), shared store (`yk_store_01`) and work room (`yk_house_06`).
Interpretive portable possessions and working arrangements make their uses legible.
Circumstance variants belong to the hypothetical campaign and preserve the dated
reference's geometry and original inventories.

| Space | Everyday detail | Circumstance or order variation |
|---|---|---|
| Home | Low woven sleeping partition, wall shelf, suspended tied bundles and a repair mat | Warning/danger adds packed belongings; shared-care preparation adds spare mat rolls and a drinking bowl; recovery exposes repair work |
| Store | Slatted rear shelf, small bundles and a grain-sorting mat | Secured-store preparation shows woven jar covers and cross ties during warning/danger; otherwise the jars show grain surfaces |
| Work room | Wood/stone hand tools, a vessel being built from clay coils and a loose cord/net panel | Danger packs portable goods; later learning adds small practice pieces and repair samples |

The cord panel is not a reconstructed loom type. Shelf heights, covers, bindings,
sleeping partition, inventories and exact clay technique are interpretation, not
finds assigned to these rooms. Extra mats do not increase housing capacity; a
rendered bundle does not add inventory to the stock ledger.

Residents use household and work identities already present in the settlement.
Presentation routes connect existing approaches, thresholds and interior activity
positions. Figures show ordinary work, carrying, care or learning as appropriate;
the chapter does not simulate individual thoughts or real-time production.
Furniture collision and clear doorways matter both for the player and these
illustrations. Citizens do not become moving barriers that can trap the player.
Children appear at an appropriate illustrative scale near home, shared care or
learning; they contribute no workforce production.
Some children continue an illustrative learned practice at home after the circle
stops, using their household's retained score; this grants no new practice points.

`src/household_view.gd`, enabled by `campaign_view.gd` only for active households,
owns these overlays and routines. It exposes stable named stations, a routine per
resident, route diagnostics and completed illustrative journeys. Home routes use
exact authored doorway portals before joining a bounded outdoor A* route. A finer
interior search avoids furniture. A spatial index narrows collision candidates to
nearby boxes while preserving the walking controller's geometry, radius and
height test; terrain samples are cached. Route/edge caches survive appearance
changes when collider geometry is unchanged and reset when it changes. Movement
itself still uses the production walking controller. Failed routes remain at their origin and are
reported as unreachable, rather than moving through a wall. Route caches and
poses have no save authority.

The actor layer illustrates the current workforce plan, including committed
neighbor-party assignments, rather than leaving a newly changed order visually
stuck in the prior season. Walking, carrying, sitting, kneeling and pauses are
presentation loops. Activities respect effective staffing and gathering capacity;
prepared props can remain visible while the corresponding order waits. Household
stress can affect their visible pace/posture;
neither that display nor the practice score identifies a person's private feelings.
Residents can pass through one another; congestion, queues and local avoidance
are not yet simulated. This bounded routing system is not a city-wide logistics
solver.

## Authoring and deterministic rules

`data/households.json` owns the fictional chapter identity, stage/order/station IDs,
role authority, instructions, reports and factor labels. Its closed schema checks
the content shape; `balance.households` owns costs, staffing thresholds, stage
duration, stress/practice rates and stock effects. A new rule needs a named factor
and a reader, not merely a sentence promising an effect.

`src/core/household_rules.gd` is scene-free and deterministic. Its optional state
is advanced only through the seasonal settlement rules. Commands, forecasts,
validation and seasonal memory cannot depend on camera position, UI frames,
animation, wall-clock time or unseeded randomness. Stable household IDs anchor
memory; sorted iteration and integer values preserve save/replay behavior.

The command seam is `household_begin` (God only) and
`household_order {id, enabled}` (the order's office or God). Both go through the
settlement command boundary. Rejected orders do not spend wood or alter state.
Enabling learning early may prepare it, but it becomes effective only from
recovery onward with sufficient labor and gathering. Forecasts are pure; only explicit season resolution advances
the elapsed count and memory.

The overlay uses its own `household_interior_` owner namespace so its geometry
and colliders can be removed together on scenario changes. Do not alter a
published reference furnishing ID to make an overlay permanent. Substantial
building changes still belong in explicit fabric change sets; a saved household
order is not a replacement for the retained/altered/new-object lineage contract.

## Save compatibility

The existing file remains `early_settlement_campaign.json`, with format
`yenikapi_seasons`. Older saves gain **`households: {}`**, an inactive extension,
without changing their turn, stocks, people or completed projects. Versions 1 and
2 still load with the chapter inactive. The dated viewing bookmark, medieval
creative saves and parent campaign saves are separate and never migrated here.

After the household chapter begins, the save uses wrapper **version 3**, whether
or not contacts are active. Before activation it keeps wrapper 1 for the base
tutorial or wrapper 2 for active contacts. Wrapper/state agreement is validated;
an older app refuses wrapper 3 instead of silently discarding household memory.
Atomic temporary write, validation/readback and rename remain the persistence
boundary. The base state/rules version remains 1; the household extension carries
its own version.

The active version-1 extension has seven fields: `version`, `started` (campaign
turn), `elapsed`, `orders`, `investments`, `homes` and `report`. `orders` and
`investments` contain booleans for the four stable order IDs. The first records
standing choices, the second paid preparations. `homes` maps stable authored
household IDs to `{stress, practice}`. The last report records the resolved stage,
summed memory changes, food penalty, three stock effects and care/watch/learning
readiness. It does not save animation clocks, routes or scene nodes. Validation
requires `elapsed == turn - started`, valid household/project identities, bounded
integers and a report for the last resolved circumstance.

## Future development and present limits

The circumstance IDs, stable households and activity destinations provide a seam
for later warnings, shortages, displacement and recovery. A future campaign
adapter could supply explicitly resolved threat events and their locations;
combat must remain behind the parent **BattleResolver** interface. It must not
turn a walking animation or furniture change into combat resolution. This release
does not integrate the village with campaign armies or save files.

The episode is authored once, not a general enemy AI, siege, evacuation or
logistics simulation. Care and teaching share aggregate workforce thresholds;
individual households do not yet negotiate, refuse orders or choose destinations
autonomously. There is no modeled disease, trauma diagnosis, religious conversion,
destruction, fire spread or persistent evacuation population. The scores and
portable furnishings establish reusable state and presentation without asserting
that every future city should respond in the same way.
