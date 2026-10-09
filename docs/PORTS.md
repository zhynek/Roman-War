# Port evolution and shipyards

The campaign now develops five waterfront stages, with river, estuary, sheltered
bay and exposed-coast settings. The stages are gameplay progression, not a claim
that all ancient ports evolved this way. Site depth is an authored campaign
abstraction rather than a reconstruction of ancient hydrography.

Select an owned waterfront province, then **Waterways & shipping → Inspect
waterfront & shipyards**. The inspector contains the current port, future-stage
previews, construction, specialist facilities, a vessel catalogue, ship queues,
and paid repair/resupply. Drag to orbit, scroll to zoom and Shift-drag to pan.
Previews explicitly show illustrative future facilities; they spend nothing and
do not unlock ships. Return to the region's harbour controls to launch ships.

## Five stages

| Stage | Inland / coastal name | Settlement needed | Cost | Seasons | Upkeep | Troops handled / season | Freight / delivery |
|---|---|---|---:|---:|---:|---:|---:|
| 1 | River landing / Waterfront landing | Village | 180 | 1 | 10 | 600 | 80 |
| 2 | Timber wharf | Town | 550 | 2 | 30 | 1,200 | 160 |
| 3 | Inland harbor / Established harbor | Large town | 1,450 | 3 | 75 | 2,400 | 300 |
| 4 | Fortified river port / Fortified naval port | Minor city | 3,100 | 4 | 150 | 4,000 | 500 |
| 5 | Imperial river exchange / Imperial maritime center | Large city | 5,800 | 5 | 280 | 6,500 | 800 |

Each upgrade requires the previous stage; costs are incremental and maintenance
replaces the earlier stage's maintenance. One waterfront project runs at a time,
independently of ordinary settlement construction. Siege suspends work. Capture
cancels an unfinished port project at the seasonal boundary, with no refund;
completed architecture follows the settlement's ownership. The settlement's
own government level, not population alone, supplies the prerequisite.

The original ramp, shelter, towpath and mooring posts persist through every
upgrade. Timber piers and a boatbuilder are followed by quays, warehouses,
customs, a market and troop assembly court. Walls, barracks, towers and military
berths establish a defended precinct. Advanced coastal ports add breakwaters,
a beacon, deep loading berths and monumental administration. River exchanges
retain their inland bank and omit sea breakwaters and the coastal beacon.

## Specialization and servicing

| Facility | Required stage | Cost / seasons | Upkeep | Benefit |
|---|---:|---:|---:|---|
| Commercial depot | 2 | 650 / 2 | 25 | +120 freight handling; barge and merchant construction |
| Repair yard | 2 | 800 / 2 | 35 | +10 readiness points and +2 serviced hulls per season; advanced shipbuilding |
| Naval arsenal | 3 | 1,200 / 3 | 60 | Military blueprints; +10% harbor defense |

Facilities are independent investments. A civilian port can reach stage 5
without an arsenal; warships still require the military facilities specified
in the catalogue. An inland port never gains deep-water access from an upgrade.

Stages repair 10/15/20/25/30 readiness points on at most 1/2/3/4/6 hulls per
season, before yard bonuses. Repairs are explicit, paid actions on berthed
ships, with crew replacements drawn from local population. The base charge is
half the template construction cost, proportional to readiness restored.
Advanced hulls require a yard and the displayed repair stage. A successful
service consumes that port's seasonal service allowance; repeated clicking,
swapping hulls or using the old retrain button cannot provide another service.
Insufficient funds or crew leave a hull unchanged. Siege blocks servicing.

Port maintenance appears as its own settlement-income factor. Background
coastal trade recognizes the effective port stage; existing building trade
bonuses remain intact. Defenders in a waterway touching their accessible owned
port receive the best local harbor defense bonus (0/0/5/15/25%, plus arsenal),
passed as the existing `fort_defense_pct` BattleResolver context. It is a
campaign-zone abstraction, not simulated fire from individual towers.

## Vessels and balance assumptions

A ship card represents a vessel group. Passenger and freight ratings are
campaign abstractions, not historical single-hull capacities. Crew uses the
existing unit template's soldier count; surviving crew/readiness scales the
available transport capacity. Passengers use actual unit soldier counts at
current strength, rounded exactly as land forces are, plus one per commander.
Crew, passengers and freight are separate. Dedicated trade fleets cannot carry
an army simultaneously. No free passenger space is obtained from depleted
companies, and no overloaded embarkation is allowed.

| Vessel | Stage / facilities | Passengers | Freight | Crew | Base movement | Build cost / seasons | Upkeep |
|---|---|---:|---:|---:|---:|---:|---:|
| River Transport Flotilla | 1 | 600 | 80 | 40 | 2 | 220 / 1 | 45 |
| River Barge Train | 2 / depot | 1,100 | 180 | 50 | 1.5 | 360 / 2 | 65 |
| River Patrol Flotilla | 2 / yard | 180 | 20 | 65 | 2.5 | 480 / 2 | 100 |
| Coastal Troop Transports | 3 | 1,000 | 140 | 70 | 2 | 610 / 2 | 110 |
| Deep-water Merchant Convoy | 3 / depot, deep water | 1,300 | 300 | 85 | 2 | 900 / 3 | 150 |
| Heavy Troop Convoy | 4 / depot + yard, deep water | 2,400 | 240 | 110 | 2 | 1,400 / 4 | 220 |
| Heavy Arsenal Squadron | 5 / arsenal + yard, deep water | 900 | 70 | 160 | 2 | 1,900 / 5 | 340 |

Existing cultural warships receive explicit stage, facility, waterway and
repair profiles as well. For example, coastal galleys require stage 3 and an
arsenal; triremes and quinqueremes require stage 4, an arsenal and yard; the
Punic heptereme requires stage 5. Faction restrictions remain in force.

Barges are river-only. River transports and patrols use rivers and coastal
corridors; heavier transports and merchant convoys need coastal/deep-water
sites. A Nile war galley retains river access. The catalogue shows every
vessel's attack, protection and maneuver rating. These remain ordinary ship
unit stats consumed by BattleResolver, including speed-based pursuit/escape;
there is no parallel naval damage model.

A mixed fleet takes its slowest ship's base movement, then applies existing
knowledge and wonder modifiers. Merging/transferring cannot restore movement
or bypass river restrictions. Launching still consumes the season. Production
uses the existing recruitment queue, charging treasury and crew up front;
only its head advances, so a four-season transport followed by a five-season
squadron takes nine seasons. New ship contracts pause if their facilities are
lost. Completed vessels wait in the harbour and incur normal ship upkeep.

Embarking and unloading each consume the endpoint's remaining seasonal troop
handling allowance. A whole army must fit; split a force before embarking if a
small landing cannot handle it. Unopposed hostile beach landings keep the
existing rule and do not receive friendly port throughput. Landing still gives
the army zero land movement for the season.

Shipping income is `3 × delivered freight + destination resource premium`.
Delivered freight is the minimum of current ship capacity and both ports'
handling limits; the existing destination-only resource premium applies once
per delivery. Payment remains limited to one arrival per fleet per season.
This replaces flat income per ship card. It is a transport-contract economy,
not a commodity stockpile or market-price simulation.

## Architecture, saves and future traversal

- `data/ports.json` owns named stages, facilities, vessel requirements, sites,
  and stable local-meter architectural footprints. Numerical progression and
  ship capacity values live in `balance.json`; unit combat stats/costs/crew
  remain in the existing unit templates. Both new content and references are
  validated by the data validator.
- `PortRules` owns pure quotes, construction, capabilities, servicing and
  throughput. `Game` enforces player ownership and active battle locks.
  `TurnEngine` completes projects deterministically and emits `port_completed`
  journal beats. No draw, timer or animation changes campaign state or RNG.
- Additive `ports` state stores stage, facilities, pending work and seasonal
  handling/service counters. Save version remains 2. `port_navigation_version`
  marks the one-time navigation migration: pre-phase hulls already on a river
  or saved river voyage retain individual river permission, so a new depth
  rule cannot strand their old voyage. New hulls follow the new restrictions.
  Existing loaded passengers are not removed on load. Battle losses still
  reduce capacity and apply the existing passenger-loss rule.
- Legacy port levels map to stages 2/3/4; existing river landings map to stage
  1, and paid naval buildings retain yard/arsenal capabilities. Existing
  construction and recruitment queues retain their prepaid terms. New port
  construction uses the unified inspector, preventing a cheaper second
  upgrade path through the legacy building drawer. Old buildings and their
  effects are retained, not rewritten or deleted.
- `PortLayout` produces walkable surfaces, obstacle footprints, entrances,
  gates, bridges over a military access channel, ramps, berth envelopes, dock edges, land/water boundaries, objectives
  and reserved routes. `walkable_at` queries those same footprints. This is
  spatial foundation data, not a completed tactical pathfinder or navmesh.
- `PortModel` builds original procedural 3D meshes from that layout. The close
  inspector and campaign miniature share the plan; the classic map uses stage
  ticks and distinct depot/arsenal badges. Public architecture passes through
  observed settlement reports, never hidden enemy fleet or cargo data.

The inspector is a scaled architectural diorama, not a surveyed location in
the campaign terrain. Reference boats are illustrative berth fittings, not the
actual fleet roster. No bitmap art was added. Individual traversal, tactical
port combat, autonomous AI port/shipbuilding strategy, tides, weather and a
stockpile-based naval supply model remain future work.

## Direct verification — October 9, 2026

Content/schema validation reported zero errors and warnings; Godot 4.4.1
imported the scripts without error diagnostics. An isolated rendered walkthrough
used a funded Egyptian campaign with large-city prerequisites, keeping all QA
images/scripts/saves outside the repository in `/private/tmp/roman-port-qa`.
One real end-turn completed the initial landing; subsequent development was
advanced through the same seasonal construction/recruitment rules in the
isolated scenario, without waiting for autonomous foreign wars.

The walkthrough completed all five inland stages, all three facilities, and an
imperial coastal center. It commissioned river craft, launched a mixed flotilla,
carried 321 passengers in 1,700 available spaces, continued across two Nile
legs, loaded the save format, and landed the army. The barge set the fleet's
movement to 1.65 after the existing Egyptian bonus. Its return freight service
paid 860 denarii. An inland heavy-transport order and an upriver launch of a new
heavy warship were refused. Four-season heavy transports and a five-season
squadron completed in queue order. Paid service raised a hull from 40% to 80%
for 380 denarii; a second same-season service did nothing. The completed
campaign saved successfully. The follow-up confirmed a real pre-phase carried-army save loaded, kept its river
route, and advanced on a real end-turn. Shared resolver estimates were 320 for
river transports, 900 for coastal galleys and 5,280 for the heavy arsenal squadron.
Screenshots cover stages, previews, navigation
footprints and the live campaign miniature.

Verified by: data/schema validation, Godot import and the isolated rendered port walkthrough. Tests: not run (weekly review policy).
