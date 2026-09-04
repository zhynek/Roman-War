# Roman War — Game Design Document

**Status:** living document. Describes both the design intent and what the engine in
`src/core/` actually implements today — Phases 0–6 of the roadmap (campaign map
through agents & diplomacy and the campaign AI), the Phase-7 senate foundation
loop, and the Phase-8 campaign UI. Section 10's status table is
the single source of truth; where a system is planned but not built, this document
says so explicitly. Design rationale and genre research:
[`docs/research/rtw-research-report.md`](research/rtw-research-report.md).

---

## 1. Vision & Pillars

Roman War is an original, clean-room, turn-based grand-strategy game of the ancient
Mediterranean. The campaign opens in 270 BC with Rome a regional power among Carthage,
the Hellenistic kingdoms, and the tribal north, and runs to AD 14. It is built in
Godot 4.4 (GDScript) and targets macOS first.

Three pillars, in priority order:

1. **Campaign first.** The strategy layer — settlements, population, public order,
   economy, armies, characters — *is* the game. It is complete, headless-testable,
   and fun on its own before any battle presentation exists.
2. **Everything is data.** All game content lives in JSON tables under `data/`,
   validated by JSON Schemas under `schemas/` plus a cross-reference validator.
   The engine under `src/core/` is a thin, deterministic rules machine that never
   hardcodes content. Content is moddable and AI-assistant-editable by construction.
3. **Battles are a swappable module.** Campaign code only ever calls
   `BattleResolver.resolve(...)`. The foundation ships a statistical auto-resolver;
   a real-time battle scene can drop in behind the same interface later without a
   single campaign-side change.

Two supporting principles enforced throughout:

- **Determinism.** `src/core/` is scene-free: no `Node`, no UI, no wall clock, no
  unseeded randomness. Every random draw goes through one `CampaignRng` whose state
  lives inside the game state, so a saved campaign replays identically.
- **Legible math.** Population growth and public order are *summed lists of named
  factors*, never opaque numbers. The rules return breakdowns
  (`[{label, value}, ...]`) the UI will render directly on settlement scrolls.

## 2. The Campaign Loop

### 2.1 Time

- The campaign runs **270 BC → AD 14** (astronomical years: `-270` → `14`; there is
  no year zero — the engine skips from −1 straight to 1).
- **Two turns per year**: summer, then winter. A turn is one season. All economic
  and growth cycles resolve every turn. Constants: `balance.json → time`.
- Characters age one year each time the year advances.

### 2.2 Structure of a turn

The player acts freely during their turn through the `Game` facade
(`src/core/game.gd`): set taxes, queue buildings and units, demolish, retrain,
move armies and fleets (each has per-turn movement points), attack, besiege,
assault, garrison, move the capital, train and move agents, put spies and
assassins to work, and make offers through envoys. Then they end the turn.

### 2.3 End-turn resolution order

`TurnEngine.end_turn(data, state, resolver)` (`src/core/turn_engine.gd`) resolves
the world in a **fixed order** so campaigns are reproducible:

| # | Step | Notes |
|---|------|-------|
| 1 | AI turns | Offers the player left unanswered lapse; then every non-player faction plays (`AiController`, §2.5): diplomacy, economy, armies, agents |
| 2 | Sieges progress | Starve-outs force a final battle through the `BattleResolver`; a starved-out city falls to the player as *occupy* and to an AI besieger by its personality's cruelty (§2.5) |
| 3 | Queues advance | Construction and recruitment, per settlement; one head-of-queue job ticks per turn |
| 4 | Treasuries resolve | Per faction: income − upkeep (armies, fleets, garrisons, agents); deep debt forces unit disbandment. Then diplomacy (`DiplomacyRules.process_turn`): opinions drift toward indifference, wars grow wearier, tributes are paid or lapse, vassals send their overlord a share of income |
| 5 | Population | Growth applied, plague rolled/progressed, slave & conquest counters tick down |
| 6 | Public order | Riots damage settlements; sustained collapse triggers revolt to the rebels |
| 7 | Events | Scripted/date/condition events, disasters, then senate politics |
| 8 | Character triggers | `CharacterRules.process_turn`: governing / campaigning / idle triggers fire for every living family member. Then `AgentRules.process_turn`: covert agents standing in foreign territory may be caught by the local counter-intelligence |
| 9 | Date & bookkeeping | Turn/season advance; on a year change `FamilyRules.process_year` runs (aging, deaths, births, succession); movement points reset, victory checked |

Governorship is re-derived from character presence (`SettlementRules.refresh_governors`)
at the top of the resolution, before anything reads it.

`end_turn` returns a report dictionary (`sieges`, `completed_buildings`,
`completed_units`, `rioted`, `revolted`, `events`, `senate`, `characters`,
`agents`, `diplomacy`, `ai`, `offers`, `winner`) that the UI presents as the
start-of-turn event log and the offers scroll.

### 2.4 The map

The campaign map is a **region graph**, not a tile grid. Each region has exactly one
settlement, a terrain type (`plains, forest, hills, mountains, desert, steppe,
marsh`), a fertility rating (0–3), resources, land adjacencies, and the sea zones it
touches (non-empty = coastal). Sea zones form their own adjacency graph for fleets.
Every region also carries a **`position`** (`x` 0–100 west→east, `y` 0–100
north→south) placing it at its real geographic location, which is what the campaign
map draws; sea zones carry optional anchor positions reserved for zone labelling.
`MapRules` provides BFS hop counts (cached per map, used for distance-to-capital and
corruption), adjacency, shared-sea-zone and coastal queries. Fog of war (`VisibilityRules`): a
faction sees its own regions and armies plus one hop out, every coastal region
of any sea zone one of its fleets occupies, and the region each of its agents
stands in (spies also see `sight` hops around them).

### 2.5 The campaign AI (Phase 6)

Every non-player faction plays through exactly the rules and facades the
player uses — the same recruitment, construction, movement, siege, combat and
diplomacy calls, the same `BattleResolver` — steered by **personality
weights** in `data/ai_personalities.json` (aggression, expansion, caution,
greed, cruelty, diplomacy, espionage, loyalty, `max_wars`, with a default
entry for any faction without one) and **thresholds** in `balance.json → ai`.
Decisions are pure functions of the game state, walking sorted ids; the only
dice are the battles, agent attempts and agent trainings (a new agent's name)
the AI starts, which draw from the turn's `CampaignRng`, so a loaded save
replays exactly. Each faction's turn
runs four behaviours in order (`src/core/rules/ai/`):

- **Diplomacy** (`AiDiplomacy`): declares war on a neighbour it does not like
  when its strength exceeds the target's by a personality-scaled margin
  (larger across a standing treaty, scaled by loyalty, and never across a
  treaty younger than `ai.min_treaty_turns_before_betrayal`; never between
  Roman houses and the Senate outside a civil war; not while already in
  `max_wars` wars, one declaration every few turns, a minimum treasury);
  seeks peace when it is
  outmatched, or when a long war is neither being won nor pressing a siege;
  keeps a peace it has made for `ai.min_peace_turns_before_war` seasons
  whatever the odds; demands submission from enemies it dwarfs when it is
  aggressive enough; and offers trade rights to neighbours and alliances
  against common enemies. Every offer is a proposal dictionary carried by an envoy in contact,
  under the same rules as the player's scroll: an offer to another AI is
  weighed at once (sweetened with a gift the purse can spare when the balance
  falls just short); an offer to the player waits in `state.pending_offers`
  for the player's answer and lapses at the end of the season.
- **Economy** (`AiEconomy`): moves a lost capital to the largest city still
  held; sets each settlement's taxes to the highest rate that keeps order a
  margin above the riot line (the greedy allow the top rate; debt allows the
  top rate, stops all spending, and sheds each garrison's costliest unit a
  season down to a floor); keeps a garrison target per settlement (base,
  population, threat, caution, and extra where the field army gathers),
  recruits the unit with the best strength per denarius toward it, and
  retrains depleted garrisons; weighs every buildable project by kind, raising
  order-restoring buildings where order is low, military ones in wartime,
  walls on a threatened frontier and health under squalor; and trains agents
  where the home watch stands — an envoy if it talks at all, a spy for the
  home watch, a capped few more for the espionage-minded, an assassin in
  wartime.
- **Military** (`AiMilitary`): musters a field army from a city's surplus
  garrison near the current target through `CombatRules.raise_army` — the
  same call the player's "Raise a field army" button makes — taking the
  strongest units, led by a family member present who is not the governor
  (never from a city under siege, nor from one that cannot hold its own
  walls); merges a captain's stack into a general's in the same region; and
  gives each army one order a season: press a siege (storming when its
  strength clears the walls by the personality's margin), attack the weakest
  enemy army within reach, run to a threatened city of its own and man the
  walls, march on the nearest independent town or enemy city within a few hops
  of its lands that *this army* could take by the siege margin and lay siege
  on arrival, or go home and stand down when the purse is thin. Cities it storms or
  starves out are occupied, enslaved or exterminated by cruelty (the player's
  starve-outs still default to occupation). Ambition scales with wealth: a
  rich house fields more armies.
- **Agents** (`AiAgents`): one spy keeps the home watch; the espionage-minded
  post the rest in the nearest enemy city, where they open the gates for their
  own besieging army; envoys walk to whichever court the diplomacy behaviour
  wants to address; assassins go for the nearest enemy city and strike when
  the odds clear the personality's bar.

**Difficulty** now touches the AI three ways, all in `balance.json → ai`: the
income multiplier and order bonus from the foundation, and an aggression
multiplier that lowers the strength margin the AI wants before it fights.
The independents' personality expands nowhere and starts nothing: they
garrison, build, and hold.

## 3. Settlements

Settlements are the heart of the game: a permanent balancing act between growth,
squalor, taxation, and unrest. All constants below live in `data/balance.json`.

### 3.1 Tiers and the government chain

There are six settlement levels with population thresholds:

| Level | Min population |
|---|---|
| village | 0 |
| town | 750 |
| large_town | 2,000 |
| minor_city | 6,500 |
| large_city | 13,000 |
| huge_city | 26,000 |

**The settlement level *is* the tier of its government building chain**
(`SettlementRules.settlement_level`) — there is no separate level variable to
desynchronize. Upgrading the government building requires the population threshold
of the next tier *and* is capped by the owner's culture
(`cultures.json → max_settlement_level`): tribal (barbarian) factions cap at
`minor_city`, independents at `large_city`, all civilized cultures reach
`huge_city`. Each culture has exactly one government chain (enforced by the
validator) with exactly as many tiers as its cap allows — e.g. `roman_government`
runs Village Forum → Imperial Curia in six tiers, while `tribal_government` stops
after four. A conquered settlement keeps its foreign government building (which
sets its effective tier) until the new owner outgrows it; government chains cannot
be demolished.

### 3.2 Population growth

Growth per turn is a summed factor list (`GrowthRules.breakdown`), clamped to
**[−10%, +6%]**:

| Factor | Value |
|---|---|
| base_fertility | region fertility, 0–3% |
| buildings | Σ `growth` effects (farms, some temples) |
| health | (Σ `health` effects ÷ 10) × 1.0% |
| taxes | +1.0 / +0.5 / 0 / −0.5 / −1.0 by tax level |
| slaves | +0.5% while a 20-turn slave influx is active |
| grain_imports | +1.5 / +3.0 / +4.0% for 1 / 2 / 3+ grain routes |
| squalor | −population ÷ 3,000 %, capped at −25 |
| plague | −10% while infected |
| recently_conquered | −1% while the counter runs |

A grain route exists to any grain-producing region owned by a trade partner (or
yourself) that is land-adjacent or reachable through a shared sea zone via a port.

**Squalor** is the central counterweight: 1% per 3,000 people, hitting both growth
and public order (each capped at 25). There is no building that removes it — only
prompt government upgrades, restrained growth, and the occasional grim solution.

**Plague** is emergent, not scripted: each settlement supports 2,000 people plus
300 per health percentage point; every 1,000 people beyond that adds a 2% outbreak
chance per turn. An outbreak lasts 2–6 turns, cutting growth by 10% and killing 2%
of the population per turn. Health buildings are the only prevention; there is no
cure. Population never drops below 400.

### 3.3 Public order

Order is **base 100 + a summed factor list** (`PublicOrderRules.breakdown`), floored
at 0. Law and Happiness are distinct axes: both feed order, but Law additionally
suppresses corruption (§4.3).

| Factor | Value |
|---|---|
| law | Σ `law` building effects |
| happiness_buildings | Σ `happiness` effects (temples, entertainment) |
| taxes | +15 / +5 / 0 / −5 / −15 by tax level |
| garrison | (soldiers ÷ population) × 400, capped at +80 |
| governor | +5 per influence point; −5 if ungoverned |
| squalor | −population ÷ 3,000, capped at −25 |
| distance_to_capital | −8% per hop beyond 2 free hops, capped at −80 (§3.4) |
| culture_penalty | −(foreign building share × 40) (§3.5) |
| recently_conquered | up to −30, decaying 5 per turn |
| wonders | faction-wide happiness wonders |
| population_boom | +5 when growth ≥ +2.5% |

**Riots:** order below **75** riots the settlement — 1% of the population dies and
there is a 25% chance a random building loses a tier.
**Revolts:** order below **50** for **3 consecutive turns** makes the settlement
secede to the rebel faction — garrison destroyed, queues cleared, governor expelled.

### 3.4 Taxes, distance, and the capital

Five tax levels (`very_low … very_high`) trade income (×0.5 → ×1.5 on a base of
100 denarii per 1,000 population) against happiness (+15 → −15) and growth
(+1 → −1). Per-settlement tax policy is the primary order/income lever.

Distance to capital is measured in BFS hops over land adjacency: the first 2 hops
are free, then 8% order penalty per hop, capped at 80%. Regions unreachable by land
from the capital pay the cap. The player may **move the capital** at any time to
re-center the empire; corruption (§4.3) uses the same distances.

### 3.5 Culture penalty and conquest

Order suffers by **(foreign-culture buildings ÷ total buildings) × 40**. It is
worked off by demolishing foreign buildings a tier at a time (farms and government
chains excepted) and building your own. One wonder can cancel the penalty for one
culture's buildings faction-wide.

On capture the victor chooses (`CombatRules.capture_settlement`):

| Option | Population | Loot | Unrest counter |
|---|---|---|---|
| **Occupy** | kept | 0.1 ⋅ population | 30 order penalty (6 turns) |
| **Enslave** | −50%, sent as +0.5% growth for 20 turns to your governed cities | 0.5 ⋅ enslaved | 20 (4 turns) |
| **Exterminate** | −75% | 1.0 ⋅ killed | 10 (2 turns) |

Losing its last settlement destroys a faction; its field armies defect to the
rebels.

## 4. Economy

### 4.1 Income streams

Per-settlement income (`EconomyRules.settlement_income_breakdown`):

- **Taxes** — population ÷ 1,000 × 100 × tax multiplier.
- **Farming** — fertility × 80 + building `farm_income` effects, ± 20% harvest
  variance (rolled only at resolution; UI previews show the expected value), plus
  a farm-income wonder bonus.
- **Trade** — see §4.2.
- **Mines** — building `mine_income`, buildable only where an ore resource exists.
- **Corruption** — subtracts a percentage of the gross (§4.3).

One-off income: loot from conquest, event treasury effects, senate mission rewards.

### 4.2 Trade model

Trade flows between settlements whose owners are the same faction or hold a
`trade`, `alliance`, or `protectorate` stance:

- **Land routes** form to every adjacent partner region: base 80 denarii plus 60
  per resource the partner has that this region lacks, multiplied by a road bonus
  (+10% per road tier).
- **Sea routes** form to partner regions sharing a sea zone when **both** sides
  have ports: base 120 plus the same resource premium. A settlement works at most
  `port_level × 2` sea routes, best-paying first; a sea-trade wonder boosts them.
- The whole trade total scales with the settlement's market `trade_pct` effects.

Resources both regions already have earn no premium, so route value is driven by
genuine exchange — the map data places grain, silver, iron, purple dye, and the
rest to make geography matter.

### 4.3 Corruption, upkeep, debt

- **Corruption:** 1.5% of gross settlement income per hop beyond the 2 free
  capital hops, capped at 30%, then reduced by local Law (×(1 − law ⋅ 0.01)).
  High-law buildings therefore pay for themselves on the frontier.
- **Upkeep:** every unit costs denarii per turn — field armies, fleets, and
  garrisons alike — and so does every agent. Upkeep is designed to dominate
  late-game budgets; army size versus treasury is the campaign's central
  economic tension.
- **Construction and recruitment are paid in full at queue time**, so the treasury
  can never be surprised by a backlog.
- **Debt:** the treasury may go negative. Below **−5,000** the faction is forced to
  disband its costliest field unit each turn until it recovers.
- Non-player factions receive a difficulty income multiplier
  (0.8 / 1.0 / 1.2 / 1.4 for easy → very hard) and, at higher difficulties, a flat
  order bonus — the AI gets richer, never smarter.

## 5. Military

### 5.1 Recruitment

Unit availability (`RecruitmentRules.available_units`) is gated by:

1. **Faction** — `units.json` lists owning factions (`all` for universal,
   `mercenary` for hire-only pools).
2. **Era** — `pre_marian` / `post_marian` / `any`; the army-reform event flips
   every Roman-culture faction to the professional era (§8).
3. **Buildings** — requirements name a building *kind* and level (never a chain
   id), e.g. `barracks ≥ 3`; temple-recruited elites additionally require a
   specific god.

Recruiting pays the unit's cost **and deducts its soldiers from the settlement's
population** (which may never fall below 400). One unit completes per turn from
the head of the queue and joins the garrison, with starting experience from any
forge-type `recruit_xp` building effects.

### 5.2 Experience, retraining, merging

- Units carry **experience 0–9** (chevrons); each grants +10% effective strength.
  Winners of a battle gain +1.
- **Retraining** in a settlement with the required building refills a depleted
  unit to 100%, costing half the pro-rata recruitment price and drawing the
  missing men from the population.
- **Merging** combines depleted same-template units, keeping the higher
  experience.

### 5.3 Movement and forced march

Armies get **2 movement points** per turn. Entering a region costs its terrain
rate (plains/steppe 1.0; forest/hills/desert 1.5; mountains/marsh 2.0) reduced by
the destination's road tier (×1.0 / 0.75 / 0.6 / 0.5). **Forced march** doubles
the budget but marks the army fatigued — a −20% battle strength malus until next
turn. An army cannot *move* into a region containing a hostile army or a hostile
settlement: that is an attack or a siege, taken as an explicit action. Fleets move
between adjacent sea zones at 1 point per lane.

### 5.4 Sieges

A besieging army invests a hostile settlement (`SiegeRules`), immobilizing itself:

- After **2 turns** siege equipment is ready and an assault may be launched.
- Defenders hold out for **2 / 3 / 4 / 5 / 6 / 8 turns** by settlement level;
  when supplies run out the garrison fights a desperate final sally (walls count
  one tier less, sally strength +10%).
- Assaults resolve through the `BattleResolver` with the settlement's **wall tier**
  multiplying defender strength (×1.0 → ×3.0 across the six wall levels).
- A **spy inside the city** can try to open a gate for the besieging army
  (§6.2): success marks the siege `gates_open`, and the assault then needs no
  equipment and meets no walls.
- A captured settlement goes through the occupy/enslave/exterminate choice; the
  turn engine's automatic starve-outs default to occupation.

### 5.5 The BattleResolver contract

The single seam between campaign and battle, quoted from
`src/core/rules/battle/battle_resolver.gd`:

```
## Contract:
##   resolve(data, rng, attacker_units, defender_units, context) -> BattleResult
##
##   attacker_units / defender_units: Arrays of unit dicts
##     {template: String, experience: int 0-9, strength_pct: int 1-100}
##     Mutated IN PLACE: casualties reduce strength_pct, destroyed units are
##     removed, survivors may gain experience.
##
##   context: {
##     terrain: String,            # terrain of the battle region
##     wall_level: int,            # 0 in the field; settlement wall tier if assault
##     attacker_general: Dictionary|null,   # character dict (command matters)
##     defender_general: Dictionary|null,
##     attacker_fatigued: bool,    # forced march
##     sally: bool,                # defenders sallying out of a siege
##   }
##
##   BattleResult: {
##     winner: "attacker"|"defender",
##     attacker_casualty_pct: float, defender_casualty_pct: float,
##     attacker_general_died: bool, defender_general_died: bool,
##     experience_gained: int,
##   }
```

Campaign modules (`CombatRules`, `SiegeRules`, `TurnEngine`) consume only this
contract. A future real-time battle scene implements the same method; the campaign
never learns which ran.

### 5.6 Auto-resolve model

`AutoResolver` estimates each side's strength as
Σ soldiers × quality × (1 + experience × 10%), where quality =
attack + missile×0.5 + defense + morale×0.5 + charge×0.25, multiplied by
(1 + general command × 0.05). The defender is then scaled by terrain
(forest ×1.15, hills ×1.2, mountains ×1.35, marsh ×1.1) and walls; fatigue and
sally modifiers apply; both sides roll ±20% randomness. Casualties derive from the
strength ratio (base 25% each, +35% for the loser, clamped 2–95%, per-unit ±30%
scatter); units falling under 10% strength are destroyed. A losing side's general
dies with 10% probability. The model is deliberately conservative — it exists to be
replaced.

## 6. Characters, Agents & Diplomacy

### 6.1 Built now (Phase 4)

- **Characters** live in the game state with faction, name, age, role
  (leader/heir/family/spouse/child), gender, father link,
  command/management/influence, `trait_points`, ancillaries, location, and an
  alive flag.
- **Traits are points, not flags.** `CharacterRules.award_points` adds points for
  a trait; a trait is active at the highest level whose `threshold` those points
  reach, and only that level's effects apply (they do not stack up the ladder).
  Positive points **erode the anti-trait first** — a brave deed spends itself
  burning off cowardice before it builds courage.
- **Triggers** follow the data tables' `when` / `condition` / `chance` / `points`
  shape. Fired kinds: `turn_end_governing`, `turn_end_campaigning`,
  `turn_end_idle`, `battle_won`, `battle_lost` (with an `odds_against` condition),
  `siege_won`, `settlement_captured` (carrying an `occupation` condition so mercy
  is only credited for a city spared), `settlement_enslaved`,
  `settlement_exterminated`, and `came_of_age`. `office_gained` is authored ahead
  of the Phase 7 senate offices; the validator warns about any *other* unfired
  kind so dead content cannot ship silently.
- **Ancillaries (retinue)** are acquired through the same trigger system, capped at
  8 per character, with `unique` members held by only one living character at a
  time. The player may **transfer** a retinue member between two living,
  co-located characters of their own faction; death releases them back into
  circulation.
- **Effective attributes** are base + trait + retinue modifiers, and they reach
  every system: influence and law/happiness traits into public order, management
  and `trade_pct` into settlement income, `growth` into population growth,
  `movement` (a flat bonus in movement points) into an army's march range, and
  `command` / `troop_morale` into the `BattleResolver` through a general profile.
- **Governorship follows presence.** An adult family member standing in a
  settlement his faction owns governs it; march him away and the seat falls
  vacant (−5 order). No one governs two cities, and the most influential claimant
  present holds the seat.
- **The family year** (`FamilyRules.process_year`): aging, natural death (rising
  after 50, certain at 85), succession (the heir takes the throne; the next heir is
  chosen by nearness to the leader's line, then influence, then age), coming of
  age at 16, births, marriage suitors who marry into the house, adoption when a
  house runs short of adult men, and **man of the hour** — a captain who wins
  badly outnumbered may be adopted and given the army he saved. The player can
  name any adult male heir; the man passed over takes the *Disinherited* trait.
- **Family caught in a fallen city** flee to the nearest settlement their house
  still holds; with nowhere to run they are lost with the city.
- **Diplomatic stances:** every faction pair holds one of
  `war / neutral / trade / alliance / protectorate`, kept symmetric, seeded from
  `campaign.json`. Stances gate movement, trade routes and grain imports; attacking
  or besieging declares war. Everything else in diplomacy (§6.3) bolts on to
  the stance graph rather than replacing it.

### 6.2 Agents (Phase 5)

Agents are state entities distinct from family characters
(`state.agents[id] = {owner, kind, name, region, skill, movement_left}`,
`AgentRules`). Their kinds live in `data/agents.json` — price, upkeep, training
requirement (a building *kind* + level, like units), starting skill, sight, and
the engine actions the kind may perform — and every probability in
`balance.json → agents`. Every faction starts with an envoy and a spy in its
capital (`campaign.json`); more are trained in a settlement that has the
building, appear at once, and step out next season.

- **Movement and the season:** agents walk any road regardless of war (3
  points a turn, terrain and road costs as for armies) and take ship coast to
  coast the same way armies do. Movement is also the action budget: every
  attempt (success or failure), every bribe and every accepted offer spends
  the rest of the season, so the odds a scroll shows are the odds of the one
  try, and a freshly trained agent waits for next season. Agents can be
  dismissed to stop their upkeep.
- **Skill contests** share one shape: success = base + skill·k − difficulty·k,
  clamped between a floor and a ceiling so nothing is ever certain. Difficulty
  is a settlement's **counter-intelligence** (base + its owner's spies inside +
  the governor's `agent_skill` retinue + law) or a character's **personal
  security** (base + trait/retinue `personal_security` + a bonus for the
  leader and heir + a bodyguard while leading an army, or a share of the
  city's watch at home). Success may raise the agent's skill; the failures
  that expose an agent kill him, and the offended court knows whose man he was.
- **Envoys** (`negotiate`, `bribe`) are the only channel for offers (§6.3): a
  court is *in contact* when the envoy stands on or beside its land or with
  its army. They also buy captain-led and rebel armies outright (family
  generals never sell out) at a price scaled from the units' cost, and buy
  independent towns, whose watch keeps its post. A bought army keeps no siege
  its new master is not at war over. Envoys travel openly and are never
  caught.
- **Spies** (`watch`, `open_gates`, `counter_espionage`) lift the fog a hop
  around them and let the settlement panel report a foreign city's garrison,
  buildings and queues; inside a city their own army is besieging they can
  unbar a gate (§5.4); at home they are the city's counter-intelligence.
- **Assassins** (`assassinate`, `sabotage`) kill foreign adult family members
  (succession settles at once) and foreign agents, or knock a tier off a
  building as a riot would (never the government seat or the farmland). A
  target who survives fires the `survived_assassination` trigger, which is
  how the *Wary* trait is earned.
- **Detection:** each turn, every covert agent standing in another faction's
  region is rolled against that settlement's counter-intelligence. A caught
  agent dies and the report says who caught him. "Covert" means *can be
  caught*, not hidden: agents of every faction are drawn on the map and listed
  in the region panel wherever the viewer's fog is lifted.

### 6.3 Diplomacy (Phase 5)

`DiplomacyRules` keeps, per faction, an **opinion** of every other faction
(−100…100, drifting one point toward indifference each turn), the length of
each current war, a **treachery** count, and an **overlord** for protectorates.
Declaring war costs opinion; tearing up a treaty to do it costs more and adds
treachery, which every court weighs against the aggressor from then on.

**Attitude** is a summed factor list (`attitude_breakdown`): the standing
stance, remembered dealings, common enemies, shared culture, the friction of a
shared border, and the other side's treachery. The UI renders it as a word
(`attitude_labels` in balance) and shows the factors.

**Offers** are plain dictionaries — a stance change (peace, trade rights,
alliance, submission as our protectorate, or stepping a treaty down), a gift
or a demand of gold, tribute per turn either way, and regions offered or
demanded — carried by an envoy of the proposer's who is in contact and free to
speak this season. `evaluate` returns the other side's balance as another
named factor list: attitude, then the term's own weight (peace depends on
relative strength and war weariness; alliances on common enemies and strength;
submission on how badly the proposer outmatches them), gold at a fixed rate
with demands weighed heavier than gifts, region values from population and
buildings, and the envoy's skill. Gold offered and demanded are netted into
one figure and region lists are deduplicated, so an offer cannot be padded.
**The evaluation never rolls dice: the other side accepts exactly when the
balance is not negative**, so the scroll can weigh an offer before it is made.
Hard refusals sit outside the sum: no trade rights or alliance while at war,
no land changing hands at war unless the same offer ends it, no capital or
last city ever, no submission demanded by the weaker side, no promising more
gold or tribute than the treasury holds, no offer to the independents. A stance
below the standing one (alliance to trade, anything to neutral) is a
dissolution: it needs no consent when nothing is demanded, costs opinion, and
teaches the envoy nothing; a vassal cannot release itself, only its overlord
can. Accepted terms apply at once: stances change (peace lifts every siege
between the two), gold moves, the first installment of a tribute changes
hands with the signatures and the rest are recorded (`state.tributes`) and
paid each turn until they run out, the payer cannot pay, or war ends them
(reneging by declaring war on the payee counts as betrayal), ceded regions
change hands peacefully (`transfer_settlement`: the garrison marches out as a
field army of the old owner, family flee as from a fallen city), and a
protectorate pays its overlord a share of what each season actually earned.
An accepted offer is the envoy's work for the season; a treaty concluded
raises his skill by one.

The AI evaluates offers with this model and, since Phase 6, makes offers of its
own with it (§2.5).

## 7. Factions & Cultures

Twenty-one factions across seven cultures (`data/factions.json`,
`data/cultures.json`). Culture determines the building tree (including which
temples exist), the unit roster's flavor, and the settlement cap; faction
determines exact recruitable units, starting position, and politics.

| Culture | Factions | Identity & asymmetry |
|---|---|---|
| roman | julii, junii, cornelii, senate | Full tree, legionary infantry, senate politics, era reform |
| greek | macedon, greek_cities, seleucia, thracia | Pike/hoplite infantry, rich cities and trade |
| eastern | parthia, armenia, pontus | Horse archers, cataphracts, open country |
| carthaginian | carthage | Naval wealth, mercenaries, elite citizen bands |
| egyptian | egypt | Unmatched fertility, dense wealthy cities |
| barbarian | gaul, germania, britannia, dacia, hispania, scythia, numidia | Cheap fierce warbands; **capped at minor_city** — squalor bites earliest |
| neutral | rebels | Independents & brigands; absorb revolts; everyone's enemy |

Playability tiers: the three Roman houses are playable at start; eight factions
are `unlockable`; the rest (and the senate) are `nonplayable`.

**Senate & civil war (hooks live now, full system Phase 7).** Roman houses carry
`senate_standing` (starts 5, range −10…10) and `popular_standing` (0.3 per held
region). Each turn `SenateRules` issues missions drawn from every template the
house can act on — *take_region* against rebel regions bordering the house,
*make_alliance* and *reach_trade_agreement* with foreign courts within a few
hops, and (from the template's `min_year`) *assassinate_leader* against a king
the house is at war with — with deadlines, treasury/standing rewards (+1, plus
unit grants mustered in the capital) and standing penalties (−2). When
popular standing reaches **6** while senate standing
has sunk to **−5**, the house enters **civil war**: war is declared on the other
houses and the senate, and the `first_civil_war` event fires. Roman long-campaign
victory requires the senate destroyed. Offices, punitive late-game missions, and
a richer standing economy are Phase 7 content — the state fields and mission
plumbing require no retrofit.

## 8. Events, Wonders, Victory

**Events** (`data/events.json`, `EventRules`) come in two kinds, all recorded in
`events_fired` so once-only events never repeat:

- **Date triggers** fire at the first summer turn of a given year (historical
  flavor and treasury effects).
- **Condition triggers** are evaluated every turn: `huge_city_with_hidden_resource`
  drives the **army reform** event — when a Roman-culture faction holds a huge city
  flagged with the right hidden resource (the home peninsula, its capital region
  excluded), every Roman faction's era flips to `post_marian`, swapping the
  recruitable roster from manipular to professional legions. `first_civil_war`
  fires The Republic Divided (a realm-wide happiness shock); `faction_destroyed`
  obituary events are Phase 7 content.

**Disasters** are probabilistic per turn (earthquake/flood/volcano/storm) over
listed regions: population loss and a chance of building damage.

**Wonders** (`data/wonders.json`) sit in specific regions; whoever owns the region
enjoys a faction-wide effect. The effect vocabulary: sea-trade %, happiness in all
settlements, religious-building cost discount, farm income %, build-time reduction
(long projects only), cancellation of one culture's penalty, and naval movement.

**Victory** (`data/win_conditions.json`, `VictoryRules`): each playable or
unlockable faction has **long** and **short** campaign conditions — hold N regions,
optionally including specific must-hold regions, optionally outliving named rivals;
Roman long campaigns additionally require civil-war victory (the senate destroyed).
The campaign ends in `time_up` past AD 14 if no one has won. The mode lives in
`state.campaign_mode` (default `long`).

## 9. Data Architecture

### 9.1 Tables and schemas

Every table in `data/` validates against the same-named schema in `schemas/`
(`buildings.json` and `temples.json` share `buildings.schema.json`). Shared
conventions (ids, enums, effect keys, astronomical years) are specified in
[`schemas/README.md`](../schemas/README.md).

| Table | Contents | Consumed by |
|---|---|---|
| balance.json | every tunable constant, one file | all rules modules |
| cultures.json | 7 cultures, settlement caps | settlements, construction |
| factions.json | 21 factions, colors, politics flags | everything |
| buildings.json | non-temple chains: government, walls, military, economy, health, entertainment, education | construction, effects |
| temples.json | temple chains (one god each, archetyped), per culture | construction, effects, elite units |
| units.json | unit templates: stats, costs, requirements, era | recruitment, battle |
| regions.json | region graph + sea zones, terrain, fertility, resources, hidden resources | map, economy, growth |
| campaign.json | the 270 BC start: factions' treasuries, capitals, settlements, armies, fleets, characters, starting agents, diplomacy; rebel holdings | NewGame |
| traits.json / ancillaries.json | trigger-driven character content | Phase 4 engine (loaded now) |
| events.json | scripted events + disasters | EventRules |
| wonders.json | wonders and their faction-wide effects | settlements, economy, construction |
| missions.json | senate mission templates | SenateRules |
| win_conditions.json | per-faction long/short goals | VictoryRules |
| names.json | per-culture name pools | Phase 4 character generation |
| mercenaries.json | regional hire pools | Active — `MercenaryRules` (field hiring, per-pool replenishment) |
| agents.json | agent kinds: price, upkeep, training requirement, skill, sight, action vocabulary | `AgentRules`, `NewGame` (starting agents come from campaign.json) |
| ai_personalities.json | per-faction behaviour weights and a default | `AiController` and the four AI behaviours |

Structural rules the schemas enforce: lowercase `snake_case` ids; building *level*
ids globally unique; units reference building requirements by **kind + level**,
never by chain id (so every culture's barracks satisfies "barracks ≥ 2"); building
effects use a closed key vocabulary (`law, happiness, growth, health, trade_pct,
farm_income, mine_income, recruit_xp, weapon_upgrade, armor_upgrade, wall_level,
road_level, port_level`); every level's effects are **standing totals at that
tier** — a level-3 market's `trade_pct` replaces level 2's rather than stacking
on it (`SettlementRules.effect_total` reads only the built tier per chain and
sums across chains), and tier effects (`wall_level`, `road_level`, `port_level`)
take the maximum across chains.

### 9.2 The validator

`tools/validate_data.py` runs every schema, then the cross-file checks JSON Schema
cannot express — including map-position sanity (no two region tokens closer than
1.2 world units; a warning when land-adjacent regions sit more than 35 apart) and
trigger liveness (any trait/ancillary trigger kind no engine call site fires is
reported as dead content, except the deliberately forward-authored `office_gained`);
agent kinds trainable by every culture and at least one kind able to negotiate;
starting agents of known kinds standing on their own faction's land; every
balance constant the engine indexes present in `balance.json`, and the
agent/diplomacy sub-tables keyed by known actions and stances; id references across tables; exactly one rebel and one senate
faction; exactly one government chain per culture with tier count matching the
culture's cap; monotonic `min_settlement_level` within chains; temple chains carry
god + archetype; every unit's requirement satisfiable by some chain of its
culture; every faction able to recruit ≥ 3 unit types; land and sea adjacency
symmetric and the whole map connected; wonders and regions back-reference each
other; the campaign start settles every region exactly once, capitals owned,
government tier consistent with starting population, exactly one leader per house,
father/general/trait references resolving; long and short win conditions present
for every playable and unlockable faction. CI runs the validator and the headless
test suite (`tests/run_tests.gd` auto-discovers `tests/test_*.gd`; suites cover
growth, order, economy, construction, recruitment, movement/visibility, battle,
characters, diplomacy and war, agents, negotiation, a multi-turn campaign
integration run, and a headless UI smoke test) on every push.

### 9.3 Determinism & save model

- `GameData` (content) is loaded once and never mutated. `GameState` is a **plain
  Dictionary** — JSON-serializable and deep-comparable — whose full shape is
  documented at the top of `src/core/new_game.gd`.
- Saving is `JSON.stringify({version, state})`; loading is the reverse with a
  version gate (`src/core/save.gd`). The format is at version 3 (Phase 5 added
  agents, tributes and the per-faction diplomatic memory; Phase 6 the pending
  offers table); older saves are upgraded in place with the defaults a new
  campaign starts from. The AI's per-faction memory (`factions[fid].ai`) is
  created lazily on a faction's first AI turn, so no save carries it until
  then. Data tables
  are content, not state, so only the state travels.
- All randomness flows through `CampaignRng`; its state is persisted as a
  decimal string in `state.rng_state` (JSON numbers are float64 and would
  round a 64-bit state) and threaded through every resolution step, so identical
  (seed, actions) sequences produce identical campaigns — the property the
  integration tests and future replay/debugging tools rely on.

## 10. Roadmap

Phases follow the research report (§17). Status as of this document:

| Phase | Scope | Status |
|---|---|---|
| 0 — Design & setup | Schemas for every data table, repo, CI, save format, this document | **Done** |
| 1 — Campaign map & turns | Region graph, sea zones, movement & forced march, fog of war, end-turn loop, seasons | **Done** |
| 2 — Settlements & economy | Growth/order factor lists, squalor, plague, buildings & queues, taxes, trade, corruption, treasury, riots/revolts, capture options | **Done** |
| 3 — Armies & battles | Recruitment, experience, retrain/merge, garrisons, sieges, mercenary hiring, sea transport (abstracted crossing), **BattleResolver interface + AutoResolver**, debt disbandment | **Done at foundation depth.** Remaining: embark-on-fleet transport, naval battles & port blockades, forts/watchtowers, ambush |
| 4 — Characters | Trait/ancillary trigger engine, family tree, succession, marriage/adoption, natural death, hero-of-the-field | **Done.** Trait points with anti-trait erosion, triggers (governing/campaigning/idle/battle/siege/occupation), retinue acquisition & transfer, effective attributes wired into order/income/growth/movement/battles; yearly aging, natural death, succession & set-heir, coming of age, births, marriage suitors, adoption, man-of-the-hour. `office_gained` triggers await Phase 7 offices |
| 5 — Agents & diplomacy | Envoys/spies/assassins, negotiation offers, AI attitude model | **Done.** Agents as state entities with data-driven kinds (`agents.json`), training, free movement, skill contests against settlement counter-intelligence and personal security, gate-opening, assassination (with succession and the `survived_assassination` trigger), sabotage, bribery of armies and towns, detection; opinion memory, attitude breakdown, deterministic offer evaluation (stance, gold, tribute, land, envoy skill), tribute streams, protectorates, peaceful region transfer, treachery. |
| 6 — AI opponents | Modular economy/expansion/diplomacy/war behaviors, difficulty tuning | **Done.** `AiController` with economy, military, diplomacy and agent behaviours (§2.5), data-driven personalities, offers to the player answered from a scroll, difficulty aggression multiplier. Remaining: naval movement (AI armies never take ship), no coordination between allies |
| 7 — Politics, events, victory | Full senate offices & mission variety, civil war depth, richer event scripting | **Foundation loop built** (standings, civil-war trigger, army reform, wonders, victory checks); missions now come in four kinds (take region, alliance, trade agreement, assassinate a leader); offices, port blockades, the suicide demand and event depth pending |
| 8 — Polish | Campaign UI, balancing pass, tutorial, save robustness | **Campaign UI playable**: start menu (house/difficulty/seed), pannable geographic map (owner tokens, adjacency roads & sea lanes, army badges, agent diamonds, siege rings, fog), settlement panel with live factor breakdowns/taxes/queues, army orders (march, sail, attack, besiege, assault with occupation choice, mercenaries, garrison), family scroll (heir, retinue transfer), agent orders (train, travel, open gates, assassinate, sabotage, bribe) with a spy's report on foreign cities, the negotiating table (terms, gold, tribute, land, weighed before the offer is made), an offers scroll for foreign proposals, a turn log that reports the other courts' wars, sieges, stormings and treaties where they touch the player, save/load. Balancing pass and tutorial pending |
| Future — Real-time battles | A battle scene implementing `BattleResolver` | By design, a drop-in |

## 11. Clean-Room Policy

Roman War is a spiritual successor at the *mechanics* level only.

- **Freely used:** game mechanics and rules (not copyrightable), historical facts,
  real place names, real historical unit types (hastati, cataphracts, hoplites…),
  real deities, and real historical figures.
- **Never copied:** names, logos, or trademarks of any commercial game; their
  description or advisor text; art, models, music, or UI assets; their data files
  or the specific values within them.
- Every name, description, and data value in this repository is original work.
  Where the research report documents a community-known anchor value (settlement
  thresholds, the squalor ratio), we adopt the mechanic's *shape* with our own
  tuned constants in `balance.json`.
- Working title "Roman War"; original visual identity to come. If open-sourced:
  permissive license for code, CC-BY/CC0 for original assets.
