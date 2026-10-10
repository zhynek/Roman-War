# Campaign waterways and shipping

This phase adds player-controlled naval logistics to the parent Roman War campaign.
It uses the existing seasonal clock, port buildings, harbours, force controls and
BattleResolver. The independent Yenikapı village remains a separate experience.

## Port evolution update — October 9, 2026

The next phase replaces flat ship-card transport and delivery allowances with
five port stages, specialist facilities, per-vessel passenger/freight capacity,
actual soldier loads and port throughput. Port and shipyard construction now
uses **Inspect waterfront & shipyards** in the shipping section. Existing
landings, port buildings and paid queues migrate additively. See [PORTS.md](PORTS.md)
for current controls, balance, restrictions and direct evidence. The original
phase description below is retained as its October 8 implementation record;
its company-space and per-card-income figures have been superseded.

## Playing

1. Select an owned province on the Tiber, Nile or Danube. **Waterways & shipping**
   offers a river landing (180 denarii, one season), then a transport flotilla
   (220 denarii, one season). Completed boats appear in the harbour. Established
   sea ports can also commission transports; shipyards retain normal warship
   recruitment. Build and upgrade sea ports in the settlement building drawer.
2. Tick harbour ships and launch into an adjoining river or sea. Launching uses
   the season; the fleet receives fresh movement next season. River landings
   launch onto their river, while maritime departures require a completed port.
3. Select the ship miniature or banner. Choose **Rivers & coast** or **Allow
   open-water passages**, choose a destination, read the distance and seasonal
   estimate, and press **Issue voyage**. The map draws the planned corridor and
   seasonal legs. Right-clicking a waterway also issues an order. A distant
   destination persists until arrival or **Halt voyage / end trade service**.
4. To transport an army, bring a friendly fleet to its owned landing or port.
   **Embark** appears in both force panels. Each ship card carries six company
   cards; the army's commander uses one more space. Loading costs half a movement
   point from the fleet and requires half a point from the army. The army spends
   its remaining movement and leaves the land-force index. Upkeep continues.
5. At a friendly landing or port, choose **Land troops**, or right-click the
   province. Landing costs the fleet half a point and gives the army zero land
   movement until next season. An unopposed enemy coast also permits landing:
   an enemy field army or an existing siege blocks it. The town and its garrison
   remain enemy-held; taking the town is a later land order. Inland enemy river
   landings cannot be used without access.
6. For shipping income, an empty fleet at an owned landing/port can select a
   second accessible endpoint and **Assign selected trade route**. The fleet
   travels back and forth automatically, making at most one delivery per season.
   It needs separate waterway anchors at the endpoints. Ordinary local port trade
   remains part of the existing settlement economy. Capture, siege or loss of
   trading access pauses the service; halt it to release the fleet.
7. An owned province bordering an authored unbridged river offers **Bridge to**
   when both banks belong to you. It costs 450 denarii and two seasons. The
   finished bridge opens that edge for armies, agents, land trade and supply,
   including land path previews and AI land planning. It does not obstruct boats.

The Julii can start with an Umbria landing and the Etruria–Umbria bridge. Egypt
can use its existing fleet and Alexandrian port, then build landings at Memphis
and Thebae to establish a Nile service.

## Operations from a port district

Completed owned ports now provide **Enter port** in the settlement's waterway
panel. Shipyard, commercial, repair, assembly and berth controls call the same
Game commands as the campaign panels. Embarkation, landing and service quotes
are shared rule functions. Local walking, camera movement and interrupted
presentation do not issue fleet voyages or spend campaign movement. See
[playable port districts](PORTS.md#architecture-saves-and-district-navigation).

## Rules and limits

- Routes use authored graph distances, not kilometres or continuous ship physics.
  The Tiber, Nile and Danube corridors are interpretive campaign geography.
  Static coast geometry is unchanged. River and fleet overlays are original
  procedural drawings; no image asset was added.
- Existing sea lanes are coastal corridors. Two open-water links offer direct
  passages across the central/eastern Mediterranean. River transports cannot
  use those links. The pathfinder chooses the cheapest legal route; choosing
  open water does not force a detour if a coastal route costs less.
- Fleets start with the existing two-point base seasonal budget, modified by
  naval knowledge and wonders. Route costs, project costs/times, carrying
  capacity, handling cost and delivery income are authored in `balance.json`.
  Armies retain their existing terrain-priced, multi-season march orders.
- A whole leg must fit the remaining movement budget. Unused movement does not
  accumulate. A leg that cannot fit even a fresh season is excluded from a
  preview and stops an existing order. Estimates count the current season.
- A fleet entering an enemy fleet's zone automatically resolves one encounter
  through the injected BattleResolver. A fleet already in contact can also
  choose **Auto-resolve naval encounter**. No tactical naval scene is opened.
  Combat spends movement and clears both sides' route/trade orders. Surviving
  fleets can meet again next season. Lost hulls reduce carrying capacity; excess
  embarked companies are lost, and a sunk fleet loses its remaining passengers.
- Loaded fleets cannot dock, merge, split, transfer ships or disband them. Land
  the army first. This avoids disappearing cargo and capacity bypasses.
- A service pays the fleet owner `(240 + 40 × destination-only resource types)`
  per ship card, capped at four ships. It is a dedicated transport contract in
  addition to background settlement trade, not a stockpile or cargo-price model.
  Service income and completed works appear in the Daily Dispatch.
- AI land planning understands built bridges. Autonomous AI shipbuilding,
  transport assignments, trade assignments and naval strategy remain future
  work. Starting enemy fleets can be encountered. Port blockades, tides,
  currents, weather, naval supply and a tactical naval simulator are not added.

## Architecture and saves

`data/waterways.json` and its schema own river nodes, region access, distances,
route types and the transport blueprint. `GameData` indexes the overlay alongside
existing sea zones without making inland provinces coastal or modifying generated
`map_geometry.json`. The validator checks node/region/unit references, duplicate
links and complete distance coverage for existing sea lanes.

`WaterwayRules` owns construction, pure weighted route previews, seasonal
continuation, transport, shipping and naval resolution. `Game` verifies player
ownership and the active city-battle lock. `TurnEngine` completes projects and
resumes voyages at the fresh seasonal movement budget in sorted fleet-id order.
Only encounter resolution draws from campaign RNG.

Save version 2 gains additive `waterworks` and `naval_report` containers. Fleets
carry `cargo`, `sail_path`, `sail_mode` and `trade_route`; creation and migration
initialize these fields. Cargo stores the original army id and full roster.
Generals' locations follow the fleet, their deaths clear carried commands, and
upkeep includes embarked troops. Save validation checks the new containers;
load retains orders and paid shipping state. The obsolete abstract army sea move
returns false and never clears a land order.

The renderer's voyage interpolation is presentation only. The ship's picking
position and its banner use the same animated coordinate. Turning off animation
or loading never advances a voyage, spends points or changes RNG.

## Direct verification — October 8, 2026

Godot 4.4.1 compiled the project without error diagnostics. Content/schema and
cross-reference validation reported **0 errors, 0 warnings**. An isolated rendered
walkthrough exercised actual fleet-panel voyage controls and inspected planning,
sailing, arrival, 40× zoom, trade and Tiber bridge/fleet views. QA images, scripts
and saves are outside the repository in `/private/tmp/roman-waterways-qa`.

The Egyptian army boarded a 12-space fleet (five spaces used), disappeared from
the land index, continued along two Nile legs on successive seasons and landed
with zero land movement. A three-season preview left campaign state unchanged.
Docking and splitting while loaded were refused. A Thebae–Memphis delivery paid
560 denarii. The Julii's bridge changed its land edge from blocked to passable
after two seasons, and a commissioned river flotilla launched successfully.
A detached hostile encounter used BattleResolver and advanced only campaign RNG.
An unopposed landing at Creta restored the army with zero movement while leaving
the rebel settlement owner unchanged. Final controls fit the 1280×800 logical
viewport, including its 360-pixel side panel.

A save made while carrying troops retained its voyage. Live and resumed campaigns
had identical parsed state after continuation, including RNG and economic values.
Raw text differed only because Godot reads JSON integers as floats; this is the
same normalization used by the repository's existing comparison helper.

Verified by: data/schema validation, Godot import and an isolated rendered shipping walkthrough. Tests: not run (weekly review policy).
