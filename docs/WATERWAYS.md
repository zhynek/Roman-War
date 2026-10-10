# Campaign waterways and shipping

This phase adds player-controlled naval logistics to the parent Roman War campaign.
It uses the existing seasonal clock, port buildings, harbours, force controls and
BattleResolver. The independent Yenikapı village remains a separate experience.

## Contested waterways — October 10, 2026

Naval AI now commissions, groups, launches and repairs ships; assigns recurring
freight services between owned ports; responds to visible threats to home ports;
and establishes nearby hostile blockades. It uses the existing rule commands,
seasonal movement budgets, recruitment queue and BattleResolver. Its choices are
sorted and deterministic. Naval targeting observes faction visibility even though
the older land AI still has its documented omniscience. Rebels receive no new
naval planner. AI amphibious invasion/army transport planning remains deferred.

Select an owned fleet in a waterway touching a hostile completed port. The fleet
panel quotes **Blockade** terms: military readiness, required coverage, movement,
and the station fee. Resolve hostile fleets already in contact first; end any
voyage/service and unload passengers before committing a station. Transport and
freight vessels cannot supply blockade coverage. An owned blockaded port shows a
security notice in its settlement panel and Daily Dispatch. **Enter port**, select
the security overview entry, and prepare relief at the repair yard, shipyard and
berth. The arsenal/office/commercial/berth panels offer eligible owned fleets for
local engagement or a quoted voyage to the blocking waterway. All commands go
through Game. A new launch still spends the season.

### Station rules and counterplay

- One explicit station targets one port, including all its shipping anchors.
  It needs `1 + 0.04 × harbor defense percent` full-readiness military hull
  equivalents. Thus a 35% defended imperial port needs 2.4 equivalents: three
  fully ready military ship cards. Hull groups remain campaign abstractions.
- Beginning requires at least one movement point and spends the fleet's remaining
  movement. Each ship in the fleet costs **40 denarii per season** for the
  station, in addition to ordinary ship upkeep. The first season is paid at
  commitment; subsequent seasons are prepaid after movement resets and before
  shipping continues. The order holds movement at zero. Withdrawal has no refund;
  movement refreshes next season. Insufficient funds end the station.
- A live blockade pauses dedicated services and background sea-trade routes at
  either endpoint. Friendly troop loading/unloading and docking are refused.
  Land trade, construction, repairs and relief launches continue. Suspended
  capacity is labeled in the district. Physical port capacity is not destroyed.
- A service retains its route, heading and last-payment season while paused. It
  resumes at the next seasonal voyage after both endpoints regain access, with
  at most one payment per fleet per season. Arrival/payment is revalidated at
  the transaction boundary, including an already-arrived saved service.
- A relief engagement uses only the injected BattleResolver. Both participants
  spend their movement and may fight at most once that season. Defeat cancels
  that fleet's station. Surviving losers withdraw to the cheapest legal adjacent
  waterway with no hostile fleet, ties by stable zone ID; without a safe edge
  they remain in contact. No extra casualties are invented during withdrawal.
  Other blockading fleets must still be relieved separately. Damage that reduces
  the victor below the station threshold also breaks its effective blockade.
- Peace, changed ownership, departure, destroyed ships, insufficient readiness
  or an invalid station immediately remove the blockade's derived effects.
  Seasonal maintenance cleans up invalid orders. Active stations count as
  prosecution in the existing AI war-staleness ledger.

### Bounded AI policy

All tuning lives in `balance.json → naval_operations`; vessel roles live in
`ports.json`. The planner preserves 1,500 denarii and 150 projected seasonal net
income, accounting for queued upkeep before another commission. It seeks at most
four military hulls during war and two trading hulls (also capped by useful port
count), and makes at most one new naval commission or port investment per faction
per season. Idle compatible military fleets combine up to three hulls. Repairs
start below 65% readiness and launches require at least 85%; repair eligibility,
crew and seasonal limits remain ordinary port rules. Idle guards prioritize
visible threats to owned ports, then nearby observed enemy ports. Offensive
routes are bounded to three estimated seasons; freight contracts to five.
Known opposition is estimated through BattleResolver, with a 1.2 strength margin.
Merchants avoid observed hostile routes. Unseen fleets can still intercept them.
Existing assigned services remain saved while paused; there is no omniscient
route search that evades hidden opposition. Debt shedding preserves passengers,
assigned services and stations instead of deleting their ships arbitrarily.

### Persistence and boundaries

Save version 2 adds optional per-fleet `blockade: {region, paid_turn}` and
`naval_battle_turn` fields. Empty stations and `-1` battle turns migrate through
`WaterwayRules.ensure_fleet` in new games, loads, launch/split and fixtures.
The save boundary validates their shape, dates and incompatible orders. There
is no saved district copy of blockade status, no presentation receipt ledger,
and no AI job ledger. Quotes, snapshots, navigation and animation consume no
campaign RNG. Closing the district or loading cannot replay a fee or battle.
Game keeps ownership and active city-battle locks. Public PortLayout battle sites
remain free of fleet data; owner-scoped PortOperations exposes only the observed
blockaders' IDs, factions and waterway locations.

This is campaign naval strategy. Local inspection remains independent of armies.
Tactical port assaults, naval battle scenes, autonomous amphibious invasions,
Senate blockade missions, weather, supply and broader naval balance remain future
work. There is no new combat resolver or real-time port economy.

### Direct evidence

Godot 4.4.1 imported the new rules and the validator reported **0 errors,
0 warnings**. Disposable native walkthroughs in `/private/tmp/roman-naval-qa`
used a funded Egyptian campaign and the actual district/fleet buttons. Three AI
patrol hulls established a 120-denarii blockade against a 2.4-coverage imperial
port. The district serviced a 60%-ready relief squadron for 380 denarii and
64 crew, launched it with zero movement, then engaged next season. The existing
resolver awarded victory with the squadron at 83% readiness; surviving enemy
ships withdrew. The retained merchant contract resumed with a 620-denarii
arrival. Live and saved continuations matched campaign state, losses and RNG.
Repeated station maintenance, relief commands and seasonal delivery could not
repeat their effects. Closing/reopening the district preserved the transaction.

The remaining direct cases covered a river station; civilian/understrength and
unaffordable refusals; peace/capture; docking/loading restrictions; active battle
locks; multiple blockade targets; AI home-port relief, repairs, one-vessel
commissioning and service assignment; an unseen fleet leaving AI choices
unchanged; and a real full campaign season replaying identically after loading.
Background trade in the isolated example fell from 460.8 to 115.2 while land
trade remained. A genuine previous-phase save loaded with additive defaults;
malformed station metadata was refused. The final saved-arrival check confirmed
that a merchant waiting at a spent hostile contact earns no delivery and resolves
that contact next season before payment. Final operation controls were visually
inspected. No full suite, CI polling, sustained balance soak or release build was
performed. An initial compiler error from an overly broad text edit was corrected
before the successful import and walkthroughs.

Verified by: data/schema validation, Godot import and isolated rendered blockade/relief and naval boundary walkthroughs. Tests: not run (weekly review policy).

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
- The original October 8 phase deferred naval AI and blockades. The contested
  waterways update above now implements them. Autonomous army transport, tides,
  currents, weather, naval supply and tactical naval combat remain deferred.

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
