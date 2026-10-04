# Seasons of the first settlement — playable tutorial 0.2.0

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
land abandonment, trade, diplomacy, resource depletion, disease and varied
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
animated workers, separately from the unchanged reference cameras. The model
bundle contains 16 GLBs: the retained ten reference models, a clearly named
hypothetical town, four new buildings and the revised store. No citizen animation
or gameplay is baked into the interchange models. Parent campaign data/import,
full regression and actual map rendering remain the release gate.
