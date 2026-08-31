# Roman War — Game Design Document

**Status:** living document. Describes both the design intent and what the engine in
`src/core/` actually implements today — Phases 0–4 of the roadmap, the Phase-7
senate foundation loop, and the Phase-8 campaign UI. Section 11's status table is
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
- **Consequence, not bookkeeping.** The societal layer (§4) is the only part of the engine
  with memory, and it is what makes a decision weigh something. Its uncertainty is
  structural — delay, hysteresis, coupled feedback and partial observability — never a
  dice roll: no part of it consumes randomness. Outcomes should be hard to predict in
  advance and obvious in hindsight.
- **Legible math.** Population growth, public order and every societal flow are *summed
  lists of named factors*, never opaque numbers. The rules return breakdowns
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
assault, garrison, move the capital. Then they end the turn.

### 2.3 End-turn resolution order

`TurnEngine.end_turn(data, state, resolver)` (`src/core/turn_engine.gd`) resolves
the world in a **fixed order** so campaigns are reproducible:

| # | Step | Notes |
|---|------|-------|
| 1 | AI turns | Every non-player faction acts (currently `AiStub`: passive settlement management) |
| 2 | Sieges progress | Starve-outs force a final battle through the `BattleResolver`; AI captures default to *occupy* |
| 3 | Queues advance | Construction and recruitment, per settlement; one head-of-queue job ticks per turn |
| 4 | Edicts & treasuries | Standing orders tick (a new one starts taking hold and is billed the same turn), then per faction: income − upkeep − edict upkeep; deep debt forces unit disbandment |
| 5 | Population | Growth applied, plague rolled/progressed, slave & conquest counters tick down |
| 6 | Society | The eight stocks integrate (§4); surveys are taken where due; advances are gained or forgotten. Faction stocks resolve before provincial ones, because militarisation and ambition are inputs to every province's load |
| 7 | Public order | Riots damage settlements; sustained collapse — or a province in open revolt — triggers secession to the rebels |
| 8 | Events | Scripted/date/condition events, disasters, then senate politics |
| 9 | Character triggers | `CharacterRules.process_turn`: governing / campaigning / idle triggers fire for every living family member |
| 10 | Date & bookkeeping | Turn/season advance; on a year change `FamilyRules.process_year` runs (aging, deaths, births, succession); movement points reset, victory checked |

Governorship is re-derived from character presence (`SettlementRules.refresh_governors`)
at the top of the resolution, before anything reads it.

`end_turn` returns a report dictionary (`sieges`, `completed_buildings`,
`completed_units`, `rioted`, `revolted`, `events`, `society`, `advances`, `senate`,
`characters`, `winner`) that the UI presents as the start-of-turn event log.

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
faction sees its own regions and armies plus one hop out, and every coastal region
of any sea zone one of its fleets occupies.

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
| unrest | −1.5% restive, −3% in open revolt — fields go unworked, and those who can leave do |

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
suppresses corruption (§5.3).

| Factor | Value |
|---|---|
| law | Σ `law` building effects |
| happiness_buildings | Σ `happiness` effects (temples, entertainment) |
| taxes | +15 / +5 / 0 / −5 / −15 by tax level |
| garrison | (soldiers ÷ population) × 400, capped at +80 |
| governor | +5 per influence point; −5 if ungoverned |
| squalor | −population ÷ 3,000, capped at −25 |
| distance_to_capital | −8% per hop beyond 2 free hops, capped at −80 (§3.4) |
| culture_penalty | −((100 − Belonging) ÷ 100 × 40) — now a drifting stock, not a building census (§3.5, §4) |
| recently_conquered | up to −30, decaying 5 per turn |
| wonders | faction-wide happiness wonders |
| population_boom | +5 when growth ≥ +2.5% |
| standing | (Standing − 50) × 0.30 — consent read as order (§4) |
| grievance | −Grievance × 0.35 — accumulated resentment read as order |
| coercion | +Σ `coercion` effects × 1.5, scaled by martial spirit — order bought with force |
| restive / in_revolt | −12 / −30 once the province has crossed its unrest threshold |

Order is therefore as much a **readout** of the societal layer as a thing in itself, and
the `grievance` and `coercion` factors are deliberately left unnetted: seeing both at once
is the only way a player can notice that a province is calm because it is held down.

**Riots:** order below **75** riots the settlement — 1% of the population dies and
there is a 25% chance a random building loses a tier.
**Revolts:** two roads. Order below **50** for **3 consecutive turns**, as before — or a
province that has been in open revolt for `rebellious_turns_to_revolt`, which fires
**regardless of the order number**. Coercion buys time, not immunity.

### 3.4 Taxes, distance, and the capital

Five tax levels (`very_low … very_high`) trade income (×0.5 → ×1.5 on a base of
100 denarii per 1,000 population) against happiness (+15 → −15) and growth
(+1 → −1). Per-settlement tax policy is the primary order/income lever.

Distance to capital is measured in BFS hops over land adjacency: the first 2 hops
are free, then 8% order penalty per hop, capped at 80%. Regions unreachable by land
from the capital pay the cap. The player may **move the capital** at any time to
re-center the empire; corruption (§5.3) uses the same distances.

### 3.5 Culture penalty and conquest

Order suffers by **((100 − Belonging) ÷ 100) × 40**, where Belonging is the drifting
assimilation stock (§4.1) rather than a building census taken this turn. A province
becomes yours over decades or not at all.

The old census survives as the friction term: `SettlementRules.foreign_building_share` is
the share of standing chains belonging to another culture, and it scales down the
assimilation contact your own buildings provide. Demolishing foreign buildings a tier at a
time (farms and government chains excepted) therefore still helps — it clears the way for
your culture to spread, rather than deleting a penalty outright. One wonder can still
excuse one culture's buildings faction-wide. A resentful province does not assimilate at
all, whatever you build in it.

On capture the victor chooses (`CombatRules.capture_settlement`):

| Option | Population | Loot | Unrest counter |
|---|---|---|---|
| **Occupy** | kept | 0.1 ⋅ population | 30 order penalty (6 turns) |
| **Enslave** | −50%, sent as +0.5% growth for 20 turns to your governed cities | 0.5 ⋅ enslaved | 20 (4 turns) |
| **Exterminate** | −75% | 1.0 ⋅ killed | 10 (2 turns) |

Losing its last settlement destroys a faction; its field armies defect to the
rebels.

## 4. Society — the weight of decisions

The strategy layer's other systems are instantaneous: order, growth and income are
recomputed from scratch every turn. That is why, before this layer existed, no decision
could ever come due. The societal layer is the only part of the engine with memory, and
that memory is what gives a choice its weight.

It is deliberately small — eight stocks, each moving by a summed list of named factors in
exactly the shape growth and public order already use — and it consumes **no randomness at
all**. Everything that makes an outcome hard to predict is structural: delay, hysteresis,
coupled feedback, and the fact that you cannot see your own empire without building the
means to.

### 4.1 The stocks

Per settlement, under `state.settlements[id].society`:

| Stock | In game | Range | What it is |
|---|---|---|---|
| `legitimacy` | Standing | 0–100 | Consent: rule accepted rather than enforced. Relaxes toward a target set by what you have built |
| `grievance` | Grievance | 0–100 | Accumulated coerced obligation. Hysteretic — it does not unwind when its cause does |
| `assimilation` | Belonging | 0–100 | Cultural convergence with the ruling culture. Diffusion, with resentment as friction |
| `expectation` | What the City Expects | 0–60 | What the city has come to believe it is owed |

Per faction, under `state.factions[id].society`:

| Stock | In game | Range | What it is |
|---|---|---|---|
| `elite_pressure` | Ambition | 0–100 | Claimants measured against the offices and commands that exist to absorb them |
| `martial_ethos` | Martial Spirit | 0–100 | What a people has come to believe it is for |
| `knowledge` | Craft | 0–100 | Accumulated practice. Decays every year it is not taught |
| `spoils` | Plunder's Share | 0–100 | How much of the income was taken rather than made |

Plus `unrest_state` (`calm` / `restive` / `rebellious`) with `unrest_turns`, a `survey`
snapshot for partial observability, `plunder_pending` as a within-turn loot buffer, and
`civic_shock`, a decaying empire-wide reputation penalty.

### 4.2 The one asymmetry the model turns on

Each province is asked to bear a **load** — taxes, squalor, conscription, quartered troops,
the burden of what has been built there, corruption, elite exactions, foreign rule, broken
promises. Against that stands its **consent**, which is the legitimacy stock. Whatever
consent does not cover has to be **coerced**, and only the coerced share charges grievance:

```
grievance += grievance_charge_rate  * max(0, load - legitimacy)
           - grievance_relief_rate  * max(0, legitimacy - load)
```

Coercion — garrisons, walls, execution grounds, a militarised state — raises public order
and appears **nowhere** in that equation. So a garrisoned province reads perfectly calm
while the pressure builds underneath it, and the settlement panel shows both numbers at
once precisely because netting them is what hides the problem:

```
Public order: 134%
    garrison  +70.4
Society — Settled
    grievance  -52.7
    asked of it  57.9
    granted willingly  9.7
    compelled  48.2  — this is what grievance is charging on
```

Coercion buys time, not immunity. A province that has withdrawn its consent entirely
secedes after `rebellious_turns_to_revolt` whatever the order number says.

### 4.3 The civic counterpart

Provision — games, festivals, baths, clean water — raises order the moment it arrives, and
the city slowly stops experiencing it as generosity. `expectation` rises toward provision
in about twelve years and falls back over forty-five, and the shortfall enters the load as
`broken_promises`. Withdrawing a bath house therefore leaves a city worse off than never
having built one: public generosity is a standing commitment, not a purchase. Expectation
is seeded at whatever a province already receives, so nothing is ever retroactively owed.

### 4.4 Both extremes of ambition fail

`elite_pressure` grows with income and with every province taken, and is drained by
**offices** (government tiers across the empire) and by **military commands** (armies in
the field). That single choice makes the model fail symmetrically:

- **Militarist** — martial spirit raises the conscription load in every province, drags the
  legitimacy target down, and puts armies in the hands of ambitious men.
- **Pacifist** — nothing absorbs ambitious sons but politics, so a wealthy demilitarised
  state eats itself from the inside.

A legitimate state damps the growth of claimants (`elite_legitimacy_damping`): one its own
elite believes in turns them into servants rather than factions. Above
`elite_civil_war_threshold` a Roman house is forced into civil war on ambition alone,
alongside the standing-based route in §8; other cultures get the generic path through
society-triggered events.

### 4.5 Conquest reaches the conqueror

`spoils` is a long-memory average of how much of each turn's income was taken rather than
made. It drags the legitimacy target in **every** province the faction holds and amplifies
corruption everywhere. Because it is an average with a long constant, it outlives the
conquest that raised it — which is why the reckoning arrives in peacetime, in a province
that never saw a soldier.

### 4.6 Legibility

A state can only act on what it can see, and seeing is infrastructure. `clarity` is
**derived, never stored**, from distance to the capital, `road_level`, the government tier,
the governor's management, and the `clarity_bonus` of any advances held. It decides what
the player is told:

- **exact** — live figures, this turn;
- **banded** — a survey rounded to `clarity_band_size` and several turns old;
- **rumour** — no figures at all, only the unrest state.

This is **lag, not lying**: the reported number is a real reading from a real earlier turn.
It is fully deterministic, replays identically from a save, and consumes no randomness —
which matters, because these queries are called from the UI arbitrarily often and must
never touch `state.rng_state`.

### 4.7 Craft and advances

`knowledge` accrues from schools, markets, harbours and forges — scaled by how well the
society they sit in is functioning — and decays proportionally. `data/advances.json`
unlocks from it at thresholds and is **lost again** below `threshold ×
advance_retention_factor`. Nothing is destroyed; it simply stops being taught.

### 4.8 Where it runs, and determinism

`SocietyRules.apply_turn` runs between growth and public order (§2.3): faction stocks
resolve first because militarisation and ambition are inputs to every province's load. All
three settlement stocks are integrated **simultaneously** from one snapshot of the previous
turn, so the breakdown the UI shows is the one the engine used.

Every stored stock is quantized onto a four-decimal grid. Godot's `JSON.stringify` does not
round-trip an arbitrary double, so continuous state would make a loaded save drift from the
live game — the exact failure the determinism contract forbids. `snappedf()` is **not**
equivalent: it can land on a double adjacent to the grid point, which then prints and
re-parses as a different number.

### 4.9 What the player is meant to learn

Every flow is a named factor, so a breakdown is always readable. When a crisis fires, the
event names the historical mechanism it illustrates — `pattern` resolves into
`data/society.json`, and the turn log prints the in-world text and then the scholarship
underneath it: elite overproduction, the placation trap, rule by fear, the Malthusian
ceiling, asabiyya at the frontier, the slow dividend of public works, forgotten craft,
conquest indigestion, and ruling in the dark.

### 4.10 Edicts — the fast lever

Every stock above moves on a 17-to-90 turn constant, which is the point, and it leaves the
player with nothing to do in the year they notice a problem: building is slow, demolishing
is slower, and retaxing nudges one term. Edicts are the answer — one standing order per
province, chosen from `data/edicts.json`, each trading one thing for another.

An edict is deliberately shaped like **a building you can raise and pull down in a few
turns**. Its effects use the same closed vocabulary the building chains use, and
`SettlementRules.effect_total` folds them in, so an edict reaches public order, growth,
income, corruption, the load, the legitimacy target, provision, belonging, martial spirit
and craft without any of those readers knowing edicts exist. Only five keys need their own
reader, because they are not additive settlement effects: `grievance_relief`,
`elite_pressure`, `income_pct`, `clarity_bonus` and `build_cost_pct`.

**Taking hold is gradual; letting go is instant.** Effects scale by
`turns_held / settle_turns`, so an order bites over two to six turns. Revoking stops it the
same turn, while whatever it moved decays at the stock's own pace, and `cooldown_turns`
stops the player flip-flopping to farm the ramp. That asymmetry is what makes the Corn Dole
a promise rather than a purchase: the provision vanishes at once and the `expectation` it
created does not, so the shortfall lands in the load as `broken_promises` (§4.3).

| Edict | Buys | Costs |
|---|---|---|
| The Corn Dole | `happiness`, `civic` | denarii per 1,000 people — and it becomes expected |
| Public Works | `civic`, `growth` | denarii per 1,000 people, `burden` |
| A Grant of Citizenship | `assimilation_pull`, `civic` | `elite_pressure`, `income_pct` down |
| The Census | `clarity_bonus`, `law` | `burden`: being counted is being taxed properly |
| The Amnesty | `grievance_relief` | `elite_pressure`, `law` down |
| Martial Law | `coercion`, `law` | `civic` heavily, `burden`, `trade_pct` down |
| The Labour Levy | `build_cost_pct` down, here only | `burden` heavily, `civic` down |
| The Tax Farmers | `income_pct` up sharply | `civic` down, `law` down, `burden` |
| The Legion Levy | `martial` | `burden`, `growth` down, `civic` down |

Two of them carry the layer's lessons directly. **Martial Law** is the coercion trap in one
click and is meant to be tempting: it raises order immediately and visibly while the
legitimacy target collapses, and the settlement panel shows both in the same breath.
**The Amnesty** is the way out of a crisis — the one direct hand the player has on a stock —
and it is a decision rather than an undo: it empties the ledger of grievances in about
fourteen turns and leaves you with the men you pardoned.

The validator enforces the premise: an edict that costs nothing, in denarii or in a
societal stock, fails the build.

## 5. Economy

### 5.1 Income streams

Per-settlement income (`EconomyRules.settlement_income_breakdown`):

- **Taxes** — population ÷ 1,000 × 100 × tax multiplier.
- **Farming** — fertility × 80 + building `farm_income` effects, ± 20% harvest
  variance (rolled only at resolution; UI previews show the expected value), plus
  a farm-income wonder bonus.
- **Trade** — see §5.2.
- **Mines** — building `mine_income`, buildable only where an ore resource exists.
- **Corruption** — subtracts a percentage of the gross (§5.3).

One-off income: loot from conquest, event treasury effects, senate mission rewards.

### 5.2 Trade model

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

### 5.3 Corruption, upkeep, debt

- **Corruption:** 1.5% of gross settlement income per hop beyond the 2 free
  capital hops, capped at 30%, then reduced by local Law (×(1 − law ⋅ 0.01)).
  High-law buildings therefore pay for themselves on the frontier.
- **Upkeep:** every unit costs denarii per turn — field armies, fleets, and
  garrisons alike. Upkeep is designed to dominate late-game budgets; army size
  versus treasury is the campaign's central economic tension.
- **Construction and recruitment are paid in full at queue time**, so the treasury
  can never be surprised by a backlog.
- **Debt:** the treasury may go negative. Below **−5,000** the faction is forced to
  disband its costliest field unit each turn until it recovers.
- Non-player factions receive a difficulty income multiplier
  (0.8 / 1.0 / 1.2 / 1.4 for easy → very hard) and, at higher difficulties, a flat
  order bonus — the AI gets richer, never smarter.

## 6. Military

### 6.1 Recruitment

Unit availability (`RecruitmentRules.available_units`) is gated by:

1. **Faction** — `units.json` lists owning factions (`all` for universal,
   `mercenary` for hire-only pools).
2. **Era** — `pre_marian` / `post_marian` / `any`; the army-reform event flips
   every Roman-culture faction to the professional era (§9).
3. **Buildings** — requirements name a building *kind* and level (never a chain
   id), e.g. `barracks ≥ 3`; temple-recruited elites additionally require a
   specific god.

Recruiting pays the unit's cost **and deducts its soldiers from the settlement's
population** (which may never fall below 400). One unit completes per turn from
the head of the queue and joins the garrison, with starting experience from any
forge-type `recruit_xp` building effects.

### 6.2 Experience, retraining, merging

- Units carry **experience 0–9** (chevrons); each grants +10% effective strength.
  Winners of a battle gain +1.
- **Retraining** in a settlement with the required building refills a depleted
  unit to 100%, costing half the pro-rata recruitment price and drawing the
  missing men from the population.
- **Merging** combines depleted same-template units, keeping the higher
  experience.

### 6.3 Movement and forced march

Armies get **2 movement points** per turn. Entering a region costs its terrain
rate (plains/steppe 1.0; forest/hills/desert 1.5; mountains/marsh 2.0) reduced by
the destination's road tier (×1.0 / 0.75 / 0.6 / 0.5). **Forced march** doubles
the budget but marks the army fatigued — a −20% battle strength malus until next
turn. An army cannot *move* into a region containing a hostile army or a hostile
settlement: that is an attack or a siege, taken as an explicit action. Fleets move
between adjacent sea zones at 1 point per lane.

### 6.4 Sieges

A besieging army invests a hostile settlement (`SiegeRules`), immobilizing itself:

- After **2 turns** siege equipment is ready and an assault may be launched.
- Defenders hold out for **2 / 3 / 4 / 5 / 6 / 8 turns** by settlement level;
  when supplies run out the garrison fights a desperate final sally (walls count
  one tier less, sally strength +10%).
- Assaults resolve through the `BattleResolver` with the settlement's **wall tier**
  multiplying defender strength (×1.0 → ×3.0 across the six wall levels).
- A captured settlement goes through the occupy/enslave/exterminate choice; the
  turn engine's automatic starve-outs default to occupation.

### 6.5 The BattleResolver contract

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

### 6.6 Auto-resolve model

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

## 7. Characters, Agents & Diplomacy

### 7.1 Built now (Phase 4)

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
  or besieging declares war, and `DiplomacyRules.set_stance` changes them directly.

### 7.2 Planned (Phase 5)

- **Agents:** envoys, spies, and assassins (infiltration, gate-opening,
  counter-espionage, sabotage, assassination as skill-vs-security probability).
  The `personal_security` and `agent_skill` ancillary effects are authored for
  them and lie dormant until then.
- **Diplomacy engine:** offer/counter-offer negotiation, tribute, region deals,
  bribery, and an AI attitude model. Because stances are already the single source
  of truth, the negotiation layer bolts on without retrofits — today's UI simply
  sets a stance directly.

## 8. Factions & Cultures

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
region). Each turn `SenateRules` issues *take_region* missions against rebel
regions bordering the house, with deadlines, treasury/standing rewards (+1,
plus unit grants mustered in the capital) and standing penalties (−2). When
popular standing reaches **6** while senate standing
has sunk to **−5**, the house enters **civil war**: war is declared on the other
houses and the senate, and the `first_civil_war` event fires. Roman long-campaign
victory requires the senate destroyed. Offices, punitive late-game missions, and
a richer standing economy are Phase 7 content — the state fields and mission
plumbing require no retrofit.

## 9. Events, Wonders, Victory

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

## 10. Data Architecture

### 10.1 Tables and schemas

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
| campaign.json | the 270 BC start: factions' treasuries, capitals, settlements, armies, fleets, characters, diplomacy; rebel holdings | NewGame |
| traits.json / ancillaries.json | trigger-driven character content | Phase 4 engine (loaded now) |
| events.json | scripted events + disasters | EventRules |
| wonders.json | wonders and their faction-wide effects | settlements, economy, construction |
| missions.json | senate mission templates | SenateRules |
| win_conditions.json | per-faction long/short goals | VictoryRules |
| names.json | per-culture name pools | Phase 4 character generation |
| mercenaries.json | regional hire pools | Active — `MercenaryRules` (field hiring, per-pool replenishment) |
| advances.json | what a society works out, and can forget | Active — `AdvanceRules`, unlocked and lost from the Craft stock |
| society.json | axis names, unrest states, historical patterns, clarity levels | Active — the pedagogy surface: `pattern` on a crisis event resolves here |
| edicts.json | one standing provincial order — the player's fast lever | Active — `EdictRules`, folded into `SettlementRules.effect_total` |

Structural rules the schemas enforce: lowercase `snake_case` ids; building *level*
ids globally unique; units reference building requirements by **kind + level**,
never by chain id (so every culture's barracks satisfies "barracks ≥ 2"); building
effects use a closed key vocabulary — the original thirteen (`law, happiness, growth,
health, trade_pct, farm_income, mine_income, recruit_xp, weapon_upgrade, armor_upgrade,
wall_level, road_level, port_level`) plus the six societal keys that carry what a building
*costs* (`civic, coercion, burden, assimilation_pull, knowledge, martial`; `civic` is the
only one that may be negative, and it is what makes an amphitheatre a trade-off rather
than a free good); every level's effects are **standing totals at that
tier** — a level-3 market's `trade_pct` replaces level 2's rather than stacking
on it (`SettlementRules.effect_total` reads only the built tier per chain and
sums across chains), and tier effects (`wall_level`, `road_level`, `port_level`)
take the maximum across chains.

### 10.2 The validator

`tools/validate_data.py` runs every schema, then the cross-file checks JSON Schema
cannot express — including that **every effect key authored in the data has an engine
reader**, the check that would have caught `weapon_upgrade` and `armor_upgrade` sitting
dead in 34 building levels across two phases, and that each unrest ignition threshold sits
above its extinction threshold, because without that gap there is no hysteresis and a
crisis simply reverses when its cause does — including map-position sanity (no two region tokens closer than
1.2 world units; a warning when land-adjacent regions sit more than 35 apart) and
trigger liveness (any trait/ancillary trigger kind no engine call site fires is
reported as dead content, except the deliberately forward-authored `office_gained`): id references across tables; exactly one rebel and one senate
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
and a multi-turn campaign integration run) on every push.

### 10.3 Determinism & save model

- `GameData` (content) is loaded once and never mutated. `GameState` is a **plain
  Dictionary** — JSON-serializable and deep-comparable — whose full shape is
  documented at the top of `src/core/new_game.gd`.
- Saving is `JSON.stringify({version, state})`; loading is the reverse with a
  version gate (`src/core/save.gd`). Data tables are content, not state, so only
  the state travels.
- All randomness flows through `CampaignRng`; its integer state is persisted in
  `state.rng_state` and threaded through every resolution step, so identical
  (seed, actions) sequences produce identical campaigns — the property the
  integration tests and future replay/debugging tools rely on.

## 11. Roadmap

Phases follow the research report (§17). Status as of this document:

| Phase | Scope | Status |
|---|---|---|
| 0 — Design & setup | Schemas for every data table, repo, CI, save format, this document | **Done** |
| 1 — Campaign map & turns | Region graph, sea zones, movement & forced march, fog of war, end-turn loop, seasons | **Done** |
| 2 — Settlements & economy | Growth/order factor lists, squalor, plague, buildings & queues, taxes, trade, corruption, treasury, riots/revolts, capture options | **Done** |
| 3 — Armies & battles | Recruitment, experience, retrain/merge, garrisons, sieges, mercenary hiring, sea transport (abstracted crossing), **BattleResolver interface + AutoResolver**, debt disbandment | **Done at foundation depth.** Remaining: embark-on-fleet transport, naval battles & port blockades, forts/watchtowers, ambush |
| 4 — Characters | Trait/ancillary trigger engine, family tree, succession, marriage/adoption, natural death, hero-of-the-field | **Done.** Trait points with anti-trait erosion, triggers (governing/campaigning/idle/battle/siege/occupation), retinue acquisition & transfer, effective attributes wired into order/income/growth/movement/battles; yearly aging, natural death, succession & set-heir, coming of age, births, marriage suitors, adoption, man-of-the-hour. `office_gained` triggers await Phase 7 offices |
| 5 — Agents & diplomacy | Envoys/spies/assassins, negotiation offers, AI attitude model | Pending; symmetric stances + war declaration live (`DiplomacyRules`), hostile acts auto-declare war |
| 6 — AI opponents | Modular economy/expansion/diplomacy/war behaviors, difficulty tuning | Pending; `AiStub` manages settlements passively, difficulty constants live in balance.json |
| 7 — Politics, events, victory | Full senate offices & mission variety, civil war depth, richer event scripting | **Foundation loop built** (standings, take-region missions, civil-war trigger, army reform, wonders, victory checks); depth pending |
| 8 — Polish | Campaign UI, balancing pass, tutorial, save robustness | **Campaign UI playable**: start menu (house/difficulty/seed), pannable geographic map (owner tokens, adjacency roads & sea lanes, army badges, siege rings, fog), settlement panel with live factor breakdowns/taxes/queues, army orders (march, sail, attack, besiege, assault with occupation choice, mercenaries, garrison), family scroll (heir, retinue transfer), turn log, save/load. Balancing pass and tutorial pending |
| 9 — Society & consequence | Eight societal stocks, the coercion asymmetry, the euergetism ratchet, elite overproduction, plunder's share, belonging as diffusion, craft and advances, legibility, authored crises naming their historical pattern, and a real trade-off on all 81 building chains | **Done**, including provincial edicts (§4.10) as the player's fast lever. Remaining: AI that understands any of it (Phase 6), and an empire-wide policy slot alongside the provincial one |
| Future — Real-time battles | A battle scene implementing `BattleResolver` | By design, a drop-in |

## 12. Clean-Room Policy

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
