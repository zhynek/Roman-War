# Seasons of the first settlement — playable tutorial 0.3.0

Choose **Play seasonal tutorial → Begin a new tutorial**. This creates a separate
hypothetical settlement; **Return to reference village** restores the unchanged
circa-6000 BCE scene. Reopen the tutorial to resume the settlement in memory.
Use **Save campaign** before quitting and **Load campaign** in a later session.
The historical scene remains a dated interpretation, not the campaign's timeline.

## What the player governs

| Role | Orders and responsibility | Tradeoff |
|---|---|---|
| God | Both offices, workforce, projects, welcoming, rations and appointments | Full authority still uses the same residents, materials and seasons |
| Settlement steward | Food, timber, care and building workers; household policy; civic projects; steward appointment | Construction and reserves compete for workers; tight rations harm wellbeing and cooperation |
| Watch leader | Watch staffing, watch shelter, refuge preparation and watch-leader appointment | Watch duty displaces food work; excessive watch/build labor burdens cooperation |

Roles can change freely without spending a season or replacing a person. Other
offices keep their standing orders; there is no hidden AI that spends resources
behind the player's back. Officeholders remain residents with a household, age
and two skills. Skill affects construction coordination or protection. Every four
years a term ends and the deterministic succession rule selects an eligible,
different resident by skill, then stable ID. Manual appointments are available.
This is one settlement with its own leaders and state. Another settlement can
use an independent rules instance and identity; a multi-town map is not shipped.

No evidence establishes these named offices, elections, terms, names or armies
at Neolithic Yenikapı. They are understandable game roles. The watch is the early
counterpart to the user's proposed military responsibility; a standing army,
conquest and field battles require a later, separately justified phase. Neither
this project nor its supply-pressure events call the parent campaign's combat
engine. Future campaign combat must remain behind BattleResolver.

## A first playthrough

1. Read **Guide** and its forecast. Open **Work** to change the workforce, or use
   **Use suggested workforce**. Food receives the adults left after the other
   four duties. Press **Assign this workforce** to commit manual changes.
2. Commission **Extend cultivation**. It costs 12 timber and 20 work points.
   A crew of three with the initial steward contributes 13 points per season,
   so the plot needs two seasons. Food production and timber gathering continue.
3. Resolve seasons deliberately. Spring/summer/autumn/winter food yields differ;
   protect winter reserves. The forecast shows actual consumption, unmet demand,
   spoilage, supply losses and overflow beyond storage, plus named social factors.
4. Improve storage, organize the watch and provide the shared care shelter.
   Projects need labor after materials are committed. Up to three commissions
   can queue; one building crew works through them in order. Cancellation returns
   the unused material share, not the value of completed labor.
5. Establish the north lane, then build the north and east households. Inspect
   their completed buildings on foot. Older homes survive, the original store
   retains its ID at revision 2, and new objects have new IDs.
6. Prepare the refuge and meeting ground to support protection and cooperation.
   In **Work**, enable **Welcome newcomers when supported**. Arrivals happen in
   spring only when housing, wellbeing, cooperation and food can support them.
7. Sustain the town criteria for four consecutive seasons. The acceptance
   playthrough reaches this at season 21 (year 6, entering summer) with 48 modeled
   residents. This is a demonstrated route, not a forced script or a population
   estimate for the archaeological settlement.

The milestone needs 40 residents, eight dwellings, two seasons of food reserves,
wellbeing/cooperation/protection of at least 65, and seven foundation projects.
The refuge and meeting ground are useful ways to meet those stocks, rather than
extra mandatory buildings. The tutorial recommends all nine projects. An example
route is in `tools/tutorial_driver.gd`; the live game does not autoplay it.

## Rules and limits

The 30 starting residents are fictional. One provision supports one resident for
one season. Timber and work points are abstract game units. An adult has one
assignment per season, and idle builders gather food. Food yields are 5/4/7/2
per food worker across the four seasons, increased by completed cultivation.
Stored food loses 3% per season, rounded down. Storage starts at 180 and the
improved store holds 300. Buildings buy durable effects at material and labor cost.

Wellbeing, cooperation and protection move at most five points toward their
factor totals per season. Care, adequate food, housing pressure, rationing,
shared projects and excess watch/build labor affect these totals. Pressure is a
predictable, repeating supply-risk scenario, not a claim about historical raids.
Protection limits its losses; there is no random battle hidden behind animation.

Welcoming admits three people in spring, including two adults, when there is
room and a two-season reserve for the enlarged population. Birth credit accrues
slowly with adequate food and wellbeing and spare housing. Children enter the
workforce at 18; residents reach the illustrative lifetime limit at 80, and
leadership eligibility ends at 65. These thresholds are game balance, not
reconstructed Neolithic demographics. The tutorial supports 200 simulated years.

Residents belong to explicit households linked to actual dwelling IDs. Newcomers
fill real vacancies; new household IDs become available only after their homes
are completed. Shortages cause departures and can return a town to the village
milestone. Surviving fabric is retained. Explicit demolition, household splitting,
land abandonment, treaties, resource depletion, disease and varied
institutions are future work. There is no automatic building upgrade with age.

The God/leader choice controls authority, not an RPG possession system or free
resource cheats. Citizens are original stylized procedural figures illustrating
the last seasonal assignments. They move through the same collision controller,
but do not obstruct the player or one another. Their local movement is not a
logistics/pathfinding simulation, and animation produces no food, labor or turns.
No sound, combat animation or person-specific historical clothing is claimed.

## Implementation and authoring

- `data/governance.json`: scenario identity, fictional residents/households,
  job sites, projects, prerequisites, effects and explicit fabric changes.
- `data/balance.json`: rates, thresholds, life course, office terms and initial
  stocks. `data/governance_ui.json`: all new player-facing copy and event prose.
- Closed schemas and `tools/validate_governance.py`: links, costs, household
  references, dependencies and inherited settlement-object validation.
- `src/core/settlement_rules.gd`: scene-free, integer, deterministic state and
  rejected-order boundary. Forecasting is pure. No random draws are consumed.
- `src/campaign_view.gd`: adapts completed projects through the existing fabric
  resolver; rebuilds geometry only when fabric changes. Original snapshot data
  is copied and preserved. Citizen animation never writes authoritative state.
- `src/governance_panel.gd`: guide, forecast, workforce/projects, role controls,
  people, appointments and a season journal. All decisions call the rules API.

The town/category milestone is reversible and describes authored game content.
It is not a new dated snapshot, a Byzantine predecessor record or an empirical
claim that these particular institutions caused urbanization.

## Campaign save version 1

The existing bundle/user directory remains compatible. The new file is
`early_settlement_campaign.json`, distinct from `early_settlement_view.json`.
Its wrapper is `{format: "yenikapi_seasons", version: 1, state: ...}`. State stores
`rules_version`, scenario/settlement IDs, turn, phase, sustained-season count,
previous milestone, resource/social stocks, fictional people, household IDs,
leaders/terms, completed project IDs and seasons, queue progress, workforce,
policies, birth credit, next-person sequence, player role, journal, last report
and citizen assignments. Projects reference versioned authored change sets.

The reader bounds file size and validates all required structures, IDs, numbers,
roles, prerequisites, assignments and version/settlement identity before replacing
live state. Integral JSON doubles are canonicalized to integers for exact replay.
The writer validates, writes a temporary file, reads it back, then renames it
atomically. Reference bookmarks cannot be saved/restored in campaign mode.
Medieval creative saves and parent campaign files are never read or migrated.
Future compatible fields must be optional/defaulted; changing rule semantics
requires an explicit rules-version migration, not silently reinterpreting saves.

## Verification

Run `validate_governance.py`, `test_governance_data.py`, Godot import,
`tools/governance_checks.gd` and the retained `tools/checks.gd`. The rules suite
checks exact save replay over 40 years, office authority, one assignment per
adult, multi-season costs/cancellation, forecasts, births, mortality, succession,
household occupancy, separate settlement identities and malformed saves.

Run `tools/governance_preview.gd` with an external `out_dir`. It routes actual
mouse events through the viewport, commissions/resolves through the public UI,
reaches town, saves/resumes, walks all 13 buildings and every curved path, checks
that animation cannot mutate state and restores/resumes the original reference.
Inspect all 12 captures, including the 1280×800 controls, plus the 14 reference
captures. The source and exact Mac application run these gates separately.

`tools/benchmark.gd -- campaign out_dir=...` measures the grown settlement with
animated workers, separately from the unchanged reference cameras. Each interval
forces one draw with the automatic render loop disabled, avoiding macOS background
render suppression. Screenshot readback is excluded from timing. The model
bundle contains 16 GLBs: the retained ten reference models, a clearly named
hypothetical town, four new buildings and the revised store. No citizen animation
or gameplay is baked into the interchange models. Parent campaign data/import,
full regression and actual map rendering remain the release gate.

## Chapter two: neighboring communities (0.3.0)

After the town milestone, Guide recommends **Prepare a meeting and exchange
place**: 18 timber, 24 work points, following the council ground. It adds the
furnished `growth_exchange_house` and `growth_exchange_lane`, both revision 1.
Older fabric survives. The village now has 14 buildings and eight paths. Choose
**Neighbors → Begin neighboring communities** when ready. Their economies do
not advance before this explicit choice. The dated reference still has nine
buildings; the original town playthrough still takes 21 seasons.

1. Review the two fictional communities, current speakers, stocks, reserves and
   offers. Reedbank offers 18 provisions for 8 timber over one season; Oakrise
   offers 10 timber for 18 provisions over two. These are game units and invented
   routes, not measured archaeological quantities or distances.
2. As watch leader, set an escort standing order of zero, one or two. As steward,
   dispatch an exchange or requested aid. God can coordinate both. An existing
   mission keeps its committed protection when the standing order changes.
3. One party can be active. Dispatch reserves both sides' cargo immediately;
   no unlimited merchant inventory exists. A food payment must leave one season
   for the home population; a neighbor protects its resource reserve plus the
   current speaker's reserve margin. Cancellation before departure returns cargo
   within storage limits. Departed parties cannot be instantly recalled.
4. Resolve seasons. Two food workers and the committed watch workers serve as
   rotating carriers/escorts, reducing home gathering and protection. They still
   consume provisions at home under this abstract relay model. If staffing is
   insufficient, the party waits with cargo reserved and no progress. Assign
   workers in Work to resume it. No citizen receives two seasonal assignments.
5. A fixed dispatch allowance equals seasonal route pressure minus escort and
   watch-leader protection, bounded to 0–60%. Both delivered cargoes lose that
   percentage, rounded down. The forecast names each factor. Incoming home cargo
   arrives after that season's meals and losses and is then capped by storage;
   it cannot retroactively prevent hunger. Arrival is credited exactly once.
6. Provide aid when requested. Aid gives no returning cargo, but increases trust
   by 15; exchange increases it by 8. Otherwise trust drifts down one toward 30.
   Each neighbor's report names food gathering, eating, unmet need, spoilage,
   overflow, timber gathering, delivered cargo and the trust factors.
7. Complete one exchange with each, one aid delivery overall, trust of at least
   40 with both and two seasons' food at home. This records a relationship
   achievement, not a city upgrade. `neighbor_driver.gd` demonstrates completion
   at turn 27 from a fresh tutorial; the rendered playthrough trades with Oakrise
   first and completes at turn 27 too. Decisions remain available afterward.

Speakers rotate every 16 seasons, with Oakrise offset by eight. Each office has
its own term, profile index and monotonically increasing speaker serial; a stable
identity can be formed as `community_id/speaker_serial`. Two reusable fictional
profiles per community cycle through differing reserve margins. These are
aggregate offices, not full neighboring family trees. Neighbor population is
fixed; starvation is reported but does not yet change that population. Home
household births, deaths, succession and contraction continue normally.

The meeting-place button switches to a safe walking viewpoint. Procedural carrying
figures illustrate recorded assignments locally. Their animation is preparation,
not an actual journey to another explorable settlement. Neighbor villages,
regional navigation, negotiated treaties, warfare, production chains and general
multi-town control remain unfinished.

### Contact state and compatibility

Old version-1 saves load additively with `contacts: {}`. No resources, terms,
completed projects or dates change during migration. Empty contacts remain inert.
The base state's `version` and `rules_version` remain 1. Once enabled, contacts
have their own version 1 and store start turn, elapsed seasons, escort policy,
next mission serial, active mission, per-community stocks/terms/trust/counters/
last report, and chapter achievement. Community IDs are `reedbank` and `oakrise`;
mission IDs are monotonic `mission_0001` etc. An active mission records kind,
community, both escrow amounts/resources, committed escorts, fixed allowance,
duration, remaining seasons and whether departure has occurred.

Active-contact saves use wrapper **version 2**, so older applications reject them
instead of silently losing escrow or neighbors. This app reads versions 1 and 2,
requires wrapper/state agreement and strictly validates extension shapes, IDs,
ranges and authored offers. Version 1 remains used before contact activation;
a new meeting project also needs 0.3.0's project definitions to load. Loading a
newer save in an older app is not supported. View bookmarks, medieval creative
saves and parent campaign saves remain separate. Atomic write/readback is retained.

`neighbor_rules.gd` owns pure quotes, orders, assignments, seasonal ledger updates
and validation. `neighbors.json` defines fictional communities; `balance.neighbors`
owns tunable rates; `neighbors_ui.json` owns prose. Closed schemas plus
`validate_neighbors.py` check IDs, project links, cargo resources, reserves, terms,
limits and optional chapter separation. To add partners, expand the schema and
content together and define migration before changing a published community ID.

Run `test_neighbor_data.py`, `neighbor_checks.gd` (302 checks) and
`neighbor_preview.gd` (10 captures, 58 checks), in addition to every retained gate.
The 80-season contact replay covers finite escrow, delays, authority, crew costs,
forecast agreement, cancellation, succession, chapter completion and in-flight
save replay. Rendered checks use actual viewport clicks, enter/exit all 14 rooms,
walk all eight curves, exercise smaller-window controls and restore the reference.
`benchmark.gd -- contacts out_dir=...` measures the enlarged settlement with workers.
The model download adds the meeting room and a separately named hypothetical
contact settlement, making 18 GLBs. No neighboring village model is claimed.
