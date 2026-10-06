# Land, Growth, and Lasting Consequences — 0.6.0

Choose **Manage village assets → Begin land planning**. This starts the same
30-person hypothetical village with its original 100 provisions and 30 timber.
God governs both fictional offices; a selected steward governs civic land and
projects, and the watch leader keeps watch authority. Citizens receive automatic
seasonal assignments. Inspecting a person never gives movement or work commands.

Open **Land**, inspect a footprint in the world, or follow **Guide**. All three
surfaces use the same command boundary. Compare sites before commissioning; the
panel shows existing uses, stable object and connection IDs, beneficiaries,
prerequisites, timber/work requirements, changes and blocked reasons. **Visit**
moves only the viewpoint. Resolving a season is the only way to produce work.

## Choices on the existing landscape

The bounded plan contains seven sites and eight initiatives, alongside retained
storage, care, watch, cultivation-extension and meeting projects. Dimensions and
positions are authored metre coordinates, not excavated parcels or travel-time
statistics. There is no unrestricted placement tool.

| Choice | Benefit | Lasting cost or alternative forgone |
|---|---|---|
| Clay-court home | Six places; 14 timber, 24 work; existing craft approach | Closes three shared construction places; outdoor clay preparation is removed |
| Hearth-yard home | Six places; 14 timber, 24 work; existing yard approach | Closes three construction places and loses four cooperation; shared hearth is removed |
| Outer west / east home | Six places each; 20 timber, 28 work; central work areas survive | Requires the northern connection and its continuing support |
| Northern connection | Access to both outer homes; 12 timber, 20 work | One adult and one timber every season, including while unused |
| Renew west cultivation | Eight more provisions each season with food workers; 12 timber, 20 work | Commits the west field, preventing conversion to a provisioning yard |
| Provisioning yard | Four construction places and sixty storage; 10 timber, 18 work | Removes the entire west crop plot: eight fewer provisions each staffed harvest |
| Repair/adapt working room | Four additional construction places; 10 timber, 16 work | Uses real materials and crews; existing workroom maintenance still applies |

The west-household choices are mutually exclusive, as are the east-household
choices. Mixed layouts are allowed. These are bounded additions of two household
places, not arbitrary repeated house purchases. Existing older fixed-location
homes remain separate and are never deleted or moved by adoption.

The initial eight construction places represent shared preparation ground:
three at the clay court, three at the hearth yard, and two in the working room.
These limit the **sum of all project crews**, after ordinary finite adult
allocation. Maintenance and access crews are separate duties in that same adult
pool. An adapted workroom provides six places in place of its former two.
A compact settlement with both new homes and the adaptation therefore has six
construction places; an outward settlement retaining the original ground has
eight. Places are seasonal crew support, not archaeological room occupancy.

## Seasons, land and access

A paid conversion reserves its whole site immediately. The displaced field or
shared working place stops contributing and disappears beneath staging. Pausing
retains the reservation, paid materials and work; cancellation releases it and
returns only the original ledger's unused timber fraction. Previous use resumes
when unfinished staging is cleared. Work already performed is not refunded.
Adaptations explicitly marked as retaining use keep that contribution while
work proceeds. Completion makes the new use permanent. There is no completed
project cancellation, demolition or automatic rebuilding in this phase.

The northern connection must be completed before either outer home is
commissioned. Its enabled maintenance duty requests one adult at priority 3 and
one timber from opening stores. It precedes project crews (ranks 4–6). The same
timber cannot also pay an asset repair. A season's future timber production
cannot pay either opening maintenance bill. Disabled or unfunded support stops
outer construction. Occupied outer homes remain six-place homes; they impose a
named eight-point wellbeing target penalty while unsupported. Restoring staff
and timber removes that penalty. Physical footpaths remain walkable: this is a
seasonal access-support rule, not a locked door or object-by-object hauling model.

Households, group conditions, care, supply pressure, recovery, learning, neighbor
carriers and escorts retain their existing rules. Children never enter the adult
workforce. Project priorities, budgets and pauses still use `asset_project`;
commissioning/cancellation use the original commands and single queue. Every
citizen starts from their actual household. Current duties direct cultivation,
construction, repair and access routines. Animations, arrival, camera movement
and frame rate have no authority over stocks, construction or household memory.

The proposal's provision requirement means holding one season of food for the
existing population before commissioning; it is not a second construction-food
bill. Workers consume the same household rations as everyone else. Land harvest
adjustments occur only with food workers, participate in reserve allocation and
learning readiness, and appear in the forecast and seasonal report. All benefits
and losses are explicit game units; no unimplemented distance or risk score is shown.

## Compare, recover and grow

The connected five-step planning guide teaches inspection, useful preparation,
commissioning, forecast comparison and growth readiness. It accepts alternative
layouts and does not secretly supply materials. Try adapting the workroom before
compact homes, or preparing northern access before outward homes. Retaining the
west field and improving stores provides a useful reserve margin for either.

A provisioning yard is a deliberately recoverable opportunity cost. It keeps
its storage and working-space benefit but permanently loses the field's eight
provisions. Raise the reserve principle, pause competing expansion, retain care,
or commission the existing cultivation extension using real timber and labor.
Unused staging can also be cancelled. Recovery does not erase completed land use.
Likewise, an overstretched outer initiative can wait while its crew is paused and
access maintenance and household reserves regain priority.

Growth readiness still asks whether enlarged households have two seasons of
provisions. The original town milestone still needs 40 residents, eight dwellings,
its social/protection stocks, foundations and four sustained seasons. Spatial
cultivation/access/homes satisfy the matching original foundation requirements;
there is no second population threshold or automatic village-wide upgrade.
The QA strategies in `tools/land_driver.gd` both reach town in season 24 and remain
fed and playable through season 80 from the identical initial state. They are
examples using public commands, not hidden gameplay automation.

## Save and authoring contract

Older saves backfill only **`land: {}`**. Their existing workforce mode, old fixed
projects, completed fabric, paid queue, contacts, principles and household memories
keep their previous semantics. Opening the Land tab does not adopt new rules.
**Adopt land planning** is an explicit God action after asset governance; its
explanation states the new working-space and access rules. Existing paid legacy
projects finish at their original locations. New commissions of the former
north-lane/north-home/east-home sequence require selecting spatial alternatives.
There is no active-to-legacy switch; retain a backup for that comparison.

Active land uses wrapper **5**, with base rules/state version 1 and land extension
version 1. Wrappers 1–4 retain their previous meanings. Older binaries refuse 5.
The extension contains exactly `version`, `started`, `inspected`, `tutorial`,
`access_enabled`, and `report`. The report stores resolved turn, land food
adjustment, access timber, construction places and access readiness. Land use,
reservations, buildings and occupants are derived from the existing completed
projects, queue, initiatives and citizens; they are never a second ledger.
Conflicting sites/household choices fail save validation. No route or mesh is saved.
Atomic validation/readback/rename remains the save boundary. Dated bookmarks,
medieval creative saves, and the parent campaign are independent.

`land.json` contains stable sites, footprints, existing objects, explicit
connections, proposals, household relationships, authored fabric changes, guide
and interface prose. `balance.land` owns seasonal access/provision rules.
`land_rules.gd` is scene-free and deterministic. `land_panel.gd` is a command
adapter; `land_view.gd` draws/picks the same bounded footprints. The normal fabric
resolver preserves the repaired `yk_house_06` as revision 2 with predecessor
`yk_house_06@1`, and retains removed work/field objects as inactive history.
No occupied dwelling is removed; the rule boundary refuses an unaccommodated
residential removal. General relocation and residential redevelopment need a
future explicit accommodation workflow.

Run land schema/negative cases and `land_checks.gd`, plus every retained village,
asset, household, neighbor, tutorial and parent campaign gate. `land_preview.gd`
uses actual input for comparison/commission/pause/recovery and reviews both
layouts, doors, automatic routes and small-window controls. The release builder
repeats the suites and rendered acceptance inside the exact universal Mac app.
Three new neutral GLBs show both 32-season layouts and the adapted workroom;
all 27 earlier model bytes remain preserved. QA captures remain outside git.

This is a hypothetical growth exercise, not a continuous development into medieval
Constantinople. Material vocabulary comes from the existing evidence ledger;
land rights, capacities, institutions, yields and upkeep schedules are explicit
gameplay interpretation. There is no monarchy, dynasty, character possession,
individual hauling, soldier command or tactical combat. Parent BattleResolver
remains untouched. Path maintenance is aggregate; household negotiation, general
land abandonment, resource depletion and crowd avoidance remain future work.
