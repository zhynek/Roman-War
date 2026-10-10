# Port evolution and shipyards

The campaign now develops five waterfront stages, with river, estuary, sheltered
bay and exposed-coast settings. The stages are gameplay progression, not a claim
that all ancient ports evolved this way. Site depth is an authored campaign
abstraction rather than a reconstruction of ancient hydrography.

Select an owned waterfront province, then **Waterways & shipping → Enter port**
for a completed waterfront, or **Inspect waterfront & shipyards** to develop an
empty shore. The navigable district provides an overhead command view and a
closer exploration camera, with an independent local inspection representative.
The facility controls use the existing campaign facade and read-only rule quotes.
**Plans & previews** retains the original five-stage architectural comparison.
Detailed controls are in [the playing guide](../PLAYING.md#developing-ports-and-shipyards).

## Contested waterfronts

The [contested waterways phase](WATERWAYS.md#contested-waterways--october-10-2026)
connects this district to naval AI, explicit blockades and relief operations.
Security appears first in the operational overview and focuses an arsenal or
berth. Blocked troop handling and freight are labeled as suspended; the underlying
stage and facilities remain intact. The district shows observed hostile factions
and waterway locations separately from public architecture. Its owned-fleet relief
quotes share Game commands with the campaign's naval rules.

Walk to the repair yard, buy service, launch ships from a berth and engage or sail
to relieve the port from the security panel. Shipbuilding and repairs remain
available during a naval blockade; a land siege retains its existing restrictions.
A successful relief removes the defeated station and existing shipping services
resume on the next seasonal voyage. There is no local fleet steering, troop
formation movement or tactical port battle. The stable gates, approaches and
objectives remain the spatial foundation for that later work.

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

## Architecture, saves and district navigation

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
  and reserved routes. `walkable_at` queries those same footprints. `PortNavigation` samples these same surfaces into a deterministic local graph,
  validates complete connecting segments with pedestrian clearance, and derives
  reachable approaches. It is a district route planner, not a tactical simulation.
- `PortModel` builds original procedural 3D meshes from that layout. The close
  inspector and campaign miniature share the plan; the classic map uses stage
  ticks and distinct depot/arsenal badges. Public architecture passes through
  observed settlement reports, never hidden enemy fleet or cargo data.

The district remains a scaled architectural place, not surveyed campaign terrain.
Its representative moves locally through streets, courts, bridges and piers;
no general moves, no campaign force is created, and no campaign RNG is consumed.
Graph nodes and routes are rebuilt from shared geometry. Existing buildings keep
their footprints as stages expand; three additive access ramps connect the final
merchant pier and breakwaters. Opposite riverbanks and bay edges are now shared
shoreline footprints used by rendering and vessel clearance. Pedestrian routing
checks a clearance disk and every route segment; a separate vessel graph checks
water, hull beam, obstructions and low bridges. It does not issue fleet orders.

`PortLayout.battle_sites()` exports public stable IDs and footprint rectangles
for settlement connections, gates, bridges, ramps, berths, deployment courts,
and military/commercial objectives. `PortNavigation.battle_sites()` additionally
exports reachable facility entrances and boarding points with elevation. These
records contain no ownership, troops, queues, or fleet information. No new
combat resolver, scenery damage, siege rules, or naval battle scene is introduced.

`PortOperations.snapshot()` is a separate, owner-scoped read-only projection of
harbor ships, queue entries, pending work and nearby fleets. It assigns completed
ships to available berths suitable for their vessel stage; excess ships wait off
the pictured waterfront without changing campaign capacity. Nearby campaign
fleets are identified as offshore, not silently docked. Reference boats are
restricted to explicitly labeled development previews; the live campaign port
miniature contains only architecture. Damaged hull labels, committed seasonal
service signs, construction ribs, project stakes and already-embarked manifest
figures derive from campaign facts. They perform no work on a timer.

`PortDistrict` reuses `Game.commission_ship`, `develop_port`, `service_port`,
`embark_army`, `disembark_army`, `launch_fleet`, `dock_fleet` and `assign_shipping`.
The repair, embarkation, landing and trade commands share their pure rule quotes
with the district. A changed quote is displayed again before commitment.
Shipbuilding follows the existing head-only seasonal queue. Repair still consumes
one seasonal service action, even if fewer than the maximum hulls can be serviced.
No seasonal economy or additional operation ledger exists in the UI.

Save version 2 adds optional `port_visits`, initialized in new games, migration,
and fixtures and validated at the save boundary. Each visited settlement stores
only inspection position, camera center, mode, zoom, yaw and follow preference.
Coordinates are quantized. No route, animation, roster or transaction is saved
here. Loading a different campaign closes the old window without writing its
preferences into the new state. Architecture changes interrupt the local route;
a blocked representative moves to the nearest position in the entrance-connected
walkable area. Ownership loss or an active campaign battle closes access.

No bitmap art was added. Troop formations, tactical port combat, vessel steering,
amphibious AI strategy, tides, weather, and commodity stockpiles remain
future work. Local representative traversal is implemented.

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

## Playable district verification — October 10, 2026

Developed from `origin/main` at `13c3158` in an isolated checkout. The primary
advisor branch and its untracked notes were left intact. Godot 4.4.1 compiled
the new classes; data/schema/cross-reference validation returned **0 errors,
0 warnings**. The direct rendered walkthroughs used disposable Egyptian
campaigns and kept all scripts, screenshots and saves outside the repository,
in `/private/tmp/roman-district-qa`.

- Walked a stage-one Nile landing, then retained the original ramp through all
  five inland stages. Destinations in water and inside the shelter were
  refused. Entering and exploring preserved the entire campaign dictionary
  after excluding the explicitly local `port_visits` preference container.
- Walked the advanced maritime harbor through both defensive gates, the arsenal
  road bridge, inner quay footbridge, military boarding pier, merchant access
  ramp and breakwater access. Every selectable facility/berth/gate approach was
  connected. Vessel routing reached berth water and refused a pier, low bridge
  and an overly narrow channel; rendered river/bay shorelines blocked vessels.
- Pressed the real district commission button: **220 denarii**, exactly one
  river transport contract. Only seasonal recruitment completed it. A saved,
  interrupted inspection route was not replayed on reopening or loading;
  the committed queue and treasury remained identical.
- Pressed the yard's repair button: **44 denarii and 16 crew**, readiness
  **40% → 80%**, with a repeated service refused that season. Embarked
  **321 passengers into 1,000 spaces** from the assembly control and retained
  exactly one cargo army after reopening. District landing, berth launch and
  freight-service assignment also completed through their existing commands.
- Loaded the genuine previous-phase `completed-port-campaign.json` save.
  Entered through the actual campaign settlement button, selected the rendered
  boatbuilder by screen coordinates, walked locally, released camera follow
  with manual zoom, returned to the campaign, and reopened the district.
  The authoritative campaign state was unchanged. Development previews opened
  and returned to the same district. Malformed local preferences were refused.
- An expansion placing a warehouse over the representative moved it to valid
  connected ground and displayed the interrupted-route explanation. Ownership
  loss and an active campaign battle each closed district access.

The first walkthrough exposed road paving incorrectly blocking a carved vessel
channel, and camera buttons whose labels were squeezed away. Both were corrected
and the affected cases were checked directly. Final walkthrough logs contained
no Godot error or warning diagnostics. Screenshots cover the modest landing,
shipbuilding, advanced district, bridges, service receipt, committed passenger
manifest, final camera controls, and return to the actual campaign.

Verified by: data validation, Godot import and isolated rendered district/campaign walkthroughs. Tests: not run (weekly review policy).
