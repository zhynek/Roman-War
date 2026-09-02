# Roman War — Game Design Document

**Status:** living document. Describes both the design intent and what the engine in
`src/core/` actually implements today — Phases 0–4 of the roadmap, the Phase-7
senate foundation loop, and the Phase-8 campaign UI. Section 10's status table is
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
assault, garrison, move the capital. Then they end the turn.

### 2.3 End-turn resolution order

`TurnEngine.end_turn(data, state, resolver)` (`src/core/turn_engine.gd`) resolves
the world in a **fixed order** so campaigns are reproducible:

| # | Step | Notes |
|---|------|-------|
| 1 | AI turns | Every non-player faction acts (currently `AiStub`: passive settlement management) |
| 2 | Sieges progress | Starve-outs force a final battle through the `BattleResolver`; AI captures default to *occupy* |
| 3 | Queues advance | Construction and recruitment, per settlement; one head-of-queue job ticks per turn; then every faction's military reforms tick (`DoctrineRules.advance_reforms`) |
| 4 | Treasuries resolve | Per faction: income − upkeep; deep debt forces unit disbandment |
| 5 | Population | Growth applied, plague rolled/progressed, slave & conquest counters tick down |
| 6 | Public order | Riots damage settlements; sustained collapse triggers revolt to the rebels |
| 7 | Events | Scripted/date/condition events, disasters, then senate politics; war moods (§3.3) fade a turn |
| 8 | Character triggers | `CharacterRules.process_turn`: governing / campaigning / idle triggers fire for every living family member |
| 9 | Date & bookkeeping | Turn/season advance; on a year change `FamilyRules.process_year` runs (aging, deaths, births, succession); movement points reset, victory checked |

Governorship is re-derived from character presence (`SettlementRules.refresh_governors`)
at the top of the resolution, before anything reads it.

`end_turn` returns a report dictionary (`sieges`, `completed_buildings`,
`completed_units`, `reforms`, `rioted`, `revolted`, `events`, `senate`,
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
| levy_strain | −0.05% per strain point (§3.3) |

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
| garrison | (policing ÷ population) × 400, capped at +80; policing = Σ soldiers × class `garrison_weight` × (1 + 5%/chevron), × (1 + 10% per `drill` level in the town) × doctrine bonus |
| governor | +5 per influence point; −5 if ungoverned |
| squalor | −population ÷ 3,000, capped at −25 |
| distance_to_capital | −8% per hop beyond 2 free hops, capped at −80 (§3.4) |
| culture_penalty | −(foreign building share × 40) (§3.5) |
| recently_conquered | up to −30, decaying 5 per turn |
| wonders | faction-wide happiness wonders |
| population_boom | +5 when growth ≥ +2.5% |
| levy_strain | −strain; recruiting or refilling adds (men ÷ population) × 100 points, softened 15% per drill level, capped at 30, fading 2 per turn |
| war_mood | +5 for 4 turns in every town of a faction that has just won a **decisive** battle (a triumph); −8 for 4 turns after a decisive defeat. Decisive = ≥1,500 men engaged and the loser destroyed, or ≥50% lost against ≤20% |

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
  garrisons alike. Upkeep is designed to dominate late-game budgets; army size
  versus treasury is the campaign's central economic tension.
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
the head of the queue and joins the garrison carrying the settlement's **recruit
profile** (`RecruitmentRules.recruit_profile`): starting experience from the best
`recruit_xp` building (drill halls, war temples), and `weapon` / `armor` levels
summed from its forges, armouries and forge temples, capped by
`balance.recruitment.upgrade_max` (§5.7). The region panel shows what recruits
will receive before you pay.

### 5.2 Experience, retraining, merging

- Units carry **experience 0–9** (chevrons); each grants +10% effective strength.
  Winners of a battle gain +1.
- **Retraining** in a settlement with the required building refits every
  garrison unit to the town's current kit standard (weapon and armour levels
  are never taken away) and refills depleted units to 100%, costing half the
  pro-rata recruitment price and drawing the missing men from the population.
- **Merging** combines depleted same-template units, keeping the higher
  experience and the better kit.

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
- A captured settlement goes through the occupy/enslave/exterminate choice; the
  turn engine's automatic starve-outs default to occupation.

### 5.5 The BattleResolver contract

The single seam between campaign and battle, `src/core/rules/battle/battle_resolver.gd`
(the file's header comment is authoritative):

```
resolve(data, rng, attacker_units, defender_units, context) -> BattleResult

unit:    {template, experience 0-9, strength_pct 1-100, weapon? 0-3, armor? 0-3}
         (mutated in place: casualties, destruction, experience)
context: {terrain, wall_level, attacker_general, defender_general,
          attacker_fatigued, sally, attacker_mods?, defender_mods?}
         *_mods = ArmyMods, a pre-merged dict of faction-wide modifiers
         (class stat deltas, matchup / terrain percentages, scalar bonuses)
         built campaign-side so the resolver never reads game state.
BattleResult: {winner, attacker_casualty_pct, defender_casualty_pct,
               attacker_general_died, defender_general_died, experience_gained,
               breakdown: {attacker: SideEstimate, defender: SideEstimate,
                           ratio, fortune: {attacker, defender}}}
```

`BattleResolver.estimate(data, attacker_units, defender_units, context)` is the
shared, **RNG-free** half of the model. It returns both sides' `SideEstimate`
— strength, a multiplicative factor list `[{label, value}]` (`base` carries the
raw soldiers × quality sum; every other entry is a multiplier), per-class rows,
per-unit profiles — plus the paper `ratio` and an analytic `attacker_win_chance`.
Every resolver and the UI's odds preview read the same numbers from it.
Campaign modules (`CombatRules`, `SiegeRules`, `TurnEngine`) consume only this
contract. A future real-time battle scene implements the same `resolve`; the
campaign never learns which ran.

### 5.6 Auto-resolve model

Per unit, in order (each stage is a named factor in the breakdown):

1. **base** — soldiers × class `mass` × quality, quality = attack + missile×0.5 +
   defense + morale×0.5 + charge×0.25. `mass` (unit_classes.json) is a soldier's
   fighting weight relative to a foot soldier: a horseman and his horse 2, a
   horse archer 2, a chariot 3, an elephant 8, an artillery crew 2, a general's
   escort 2.5 — so a 60-strong squadron is not a third of a 160-strong phalanx.
2. **upgrades** — weapon levels add to attack, armour levels to defense
   (`battle.weapon_upgrade_attack_per_level`, `armor_upgrade_defense_per_level`).
3. **doctrines** — class stat deltas from the side's `ArmyMods` (plus its
   `strength_pct` / `attacking_pct` scalars, merged into the same factor).
4. **experience** — +10% per chevron.
5. **matchups** — `1 + (Σ enemy_share × M[my class][their class] − 1) × matchup_weight`,
   where enemy shares are *slot* shares (one unit card = one slot, scaled by
   strength) and `M` is `data/unit_classes.json` times the unit's attribute and
   doctrine percentages. Pikes and spears stop cavalry, cavalry rides down
   infantry and foot missiles, missiles shred elephants, chariots and slow pike
   blocks, horse archers kite infantry but lose to light horse and slingers.
6. **class_terrain** — the per-class terrain table (cavalry and pikes suffer in
   woods and mountains, missiles like high ground), for both sides.
7. **assault / wall_defense** — when `wall_level > 0`, each class's storming or
   wall-holding multiplier (cavalry 0.5 / 0.6, artillery 1.6 / 1.3 …).
8. **attacking** — attribute bonuses that fire only when charging (war cry).
9. **fatigue** — forced-march malus unless the unit or doctrine is immune.

Then side-wide: **general** (command 5%/pt, troop morale 2%/pt), the defender's
**terrain** ground bonus and **walls** tier multiplier, **combined_arms** (+6%
when line, shock and missile roles each hold ≥15% of the cards), and **sally**.
Both sides then roll ±15% fortune (`battle.randomness_pct`) and the higher
strength wins; `win_chance` integrates those two rolls analytically so the UI
can say "72% to win".

**Casualties** come in two parts. The *melee* pool is set by the post-fortune
ratio (base 25% each side, clamped 2–95%) and shared out so that units the
enemy countered bleed more and units that countered him bleed less — each
unit's weight is `matchup^−casualty_matchup_weight`, clamped 0.5–2.0 and
soldier-normalised so the side's mean melee loss is the pool. The *rout* falls
on the loser only: `loser_extra_casualty_pct × (1 + (winner pursuit − 1) ×
pursuit_scale)`, where a side's pursuit is the slot-weighted mean of its units'
speed-derived pursuit factors (a mounted victor runs the beaten down harder),
divided per losing unit by its own escape factor (fast units get away). One
±30% scatter draw per unit; units under 10% strength are destroyed. The result
reports the men **actually** lost, and `attacker_destroyed` / `defender_destroyed`.
Winners gain +1 experience, or +2 when they were the paper underdog by ≥1.3;
a losing side's general dies with 10% probability. The model is a paper one by
design — it exists to be replaced behind the same interface.

### 5.7 The arms industry

Military buildings shape the men they produce, and the towns that hold them:

- **Barracks** tiers carry `drill` (1/1/2/2 from the drill grounds up; tribal
  1/1) and, from the third tier, `law` (2/3/4) — a garrison headquarters polices
  the streets. Top-tier stables and archery ranges add `drill` 1.
- **Armouries** (`kind: armoury`, one chain per culture group, `requires_building:
  barracks ≥ 2`) issue `weapon_upgrade` and `armor_upgrade`: smithy → armoury →
  state arms works (weapon 1 / 1+armour 1 / 2+armour 1; tribal forges stop at the
  second tier). Barracks L4–5, the great engine works and forge temples add to
  the same pool; the sum is capped at `recruitment.upgrade_max` (3).
- In battle each weapon level adds `battle.weapon_upgrade_attack_per_level` to
  attack and each armour level `armor_upgrade_defense_per_level` to defense
  (§5.6 stage 2) — an armoury is worth roughly a chevron and a half to a line unit.
- `requires_building` is a general chain prerequisite: a chain is offered only
  where the settlement already holds the named kind at the named tier.

### 5.8 Doctrines

Military technology is a matter of **doctrines** (`data/doctrines.json`,
`DoctrineRules`): faction-wide reforms adopted for denarii and turns, one at a
time (`balance.doctrines.max_concurrent_reforms`), paid up front, behind
prerequisites that are all AND-ed:

| Prerequisite | Meaning |
|---|---|
| `doctrines` | earlier doctrines adopted (a tree, validated acyclic) |
| `building {kind, level}` | some owned settlement holds that kind at that tier |
| `resource` | some owned region yields it (`horses`, `iron`, `elephants` …) |
| `era` | the faction's era (`cohort_reform` needs `post_marian`) |
| `battles_won` / `battles_lost` | the faction's war record |
| `faced {class, battles}` | it has fought armies containing that class in ≥ n battles — how a people *learns from whom it fights*: the Iberian sword after facing infantry, woodland ambush after meeting legions |

Every faction's **war record** (`{battles_won, battles_lost, faced: {class: n}}`)
is kept by `CombatRules.record_battle` after every field battle and assault.
Doctrines are culture-scoped (`cultures`), optionally faction-scoped
(`factions`); 270 BC starting doctrines come from `campaign.json` (Rome's
manipular drill, Macedon's sarissa, Parthia's composite bow, Numidia's
horsemanship …), and a version-1 save loaded with content receives them too.

Effects use a closed vocabulary that the validator requires an engine reader
for: per-class stat deltas, matchup and terrain percentages, side-wide battle
scalars (`strength_pct`, `attacking_pct`, `assault_pct`, `wall_defense_pct`,
`pursuit_pct`, `escape_pct`, `fatigue_immune`) — all merged campaign-side into
the `ArmyMods` dict the resolver receives; and campaign scalars: `upkeep_pct`
per class (`EconomyRules`), `recruit_xp` per class (`RecruitmentRules`),
`upgrade_cap`, `siege_equipment_turns` (`SiegeRules.equipment_turns_for`),
`garrison_order_pct` (§3.3), `levy_strain_pct`, `movement`
(`MovementRules.reset_movement`), `mercenary_cost_pct`. Reforms tick in the
turn engine after the queues (§2.3) and completions appear in the turn report
under `reforms`. `AiStub` adopts the cheapest doctrine it qualifies for whenever
its treasury exceeds the cost plus `balance.doctrines.ai_reserve`, so rivals
modernise too. The catalogue (34 doctrines with historical notes: Roman,
Hellenistic, Eastern, Punic, Egyptian, tribal and shared) is laid out for the
player in `docs/MILITARY_STRATEGY.md`.

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
  or besieging declares war, and `DiplomacyRules.set_stance` changes them directly.

### 6.2 Planned (Phase 5)

- **Agents:** envoys, spies, and assassins (infiltration, gate-opening,
  counter-espionage, sabotage, assassination as skill-vs-security probability).
  The `personal_security` and `agent_skill` ancillary effects are authored for
  them and lie dormant until then.
- **Diplomacy engine:** offer/counter-offer negotiation, tribute, region deals,
  bribery, and an AI attitude model. Because stances are already the single source
  of truth, the negotiation layer bolts on without retrofits — today's UI simply
  sets a stance directly.

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
region). Each turn `SenateRules` issues *take_region* missions against rebel
regions bordering the house, with deadlines, treasury/standing rewards (+1,
plus unit grants mustered in the capital) and standing penalties (−2). When
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
| units.json | unit templates: stats, costs, requirements, era, class, attributes | recruitment, battle |
| unit_classes.json | the unit-class counter matrix, per-class terrain / assault / wall / policing weights, attribute effects | battle estimator, public order |
| doctrines.json | 34 military doctrines: cultures, cost, turns, prerequisites, effects, historical notes | `DoctrineRules` and every reader in §5.8 |
| regions.json | region graph + sea zones, terrain, fertility, resources, hidden resources | map, economy, growth |
| campaign.json | the 270 BC start: factions' treasuries, capitals, settlements, armies, fleets, characters, diplomacy, starting doctrines; rebel holdings | NewGame |
| traits.json / ancillaries.json | trigger-driven character content | Phase 4 engine (loaded now) |
| events.json | scripted events + disasters | EventRules |
| wonders.json | wonders and their faction-wide effects | settlements, economy, construction |
| missions.json | senate mission templates | SenateRules |
| win_conditions.json | per-faction long/short goals | VictoryRules |
| names.json | per-culture name pools | Phase 4 character generation |
| mercenaries.json | regional hire pools | Active — `MercenaryRules` (field hiring, per-pool replenishment) |

Structural rules the schemas enforce: lowercase `snake_case` ids; building *level*
ids globally unique; units reference building requirements by **kind + level**,
never by chain id (so every culture's barracks satisfies "barracks ≥ 2"); building
effects use a closed key vocabulary (`law, happiness, growth, health, trade_pct,
farm_income, mine_income, recruit_xp, drill, weapon_upgrade, armor_upgrade,
wall_level, road_level, port_level`); every level's effects are **standing totals at that
tier** — a level-3 market's `trade_pct` replaces level 2's rather than stacking
on it (`SettlementRules.effect_total` reads only the built tier per chain and
sums across chains), and tier effects (`wall_level`, `road_level`, `port_level`)
take the maximum across chains.

### 9.2 The validator

`tools/validate_data.py` runs every schema, then the cross-file checks JSON Schema
cannot express — including map-position sanity (no two region tokens closer than
1.2 world units; a warning when land-adjacent regions sit more than 35 apart) and
trigger liveness (any trait/ancillary trigger kind no engine call site fires is
reported as dead content, except the deliberately forward-authored `office_gained`): id references across tables; exactly one rebel and one senate
faction; exactly one government chain per culture with tier count matching the
culture's cap; monotonic `min_settlement_level` within chains; temple chains carry
god + archetype; every unit's requirement satisfiable by some chain of its
culture; every faction able to recruit ≥ 3 unit types; a unit-class and an
attribute record for every value the units schema admits (and no others), with
matchup pair products inside the 0.85–1.15 authoring band; every building and
doctrine effect key read by some rules module (dead content fails the build);
doctrine cultures / factions / prerequisite doctrines / resources valid, the
prerequisite tree acyclic, at least three doctrines per culture, and every
campaign starting doctrine open to its faction; land and sea adjacency
symmetric and the whole map connected; wonders and regions back-reference each
other; the campaign start settles every region exactly once, capitals owned,
government tier consistent with starting population, exactly one leader per house,
father/general/trait references resolving; long and short win conditions present
for every playable and unlockable faction. CI runs the validator and the headless
test suite (`tests/run_tests.gd` auto-discovers `tests/test_*.gd`; suites cover
growth, order, economy, construction, recruitment, movement/visibility, battle,
and a multi-turn campaign integration run) on every push.

### 9.3 Determinism & save model

- `GameData` (content) is loaded once and never mutated. `GameState` is a **plain
  Dictionary** — JSON-serializable and deep-comparable — whose full shape is
  documented at the top of `src/core/new_game.gd`.
- Saving is `JSON.stringify({version, state})`; loading is the reverse with a
  version gate and an **upgrade path** (`src/core/save.gd`): a save from an
  older version is accepted and `SaveGame.upgrade` fills the fields later
  versions added, with `NewGame`'s defaults and in `NewGame`'s key order, so an
  upgraded save marches in step with a live game. Data tables are content, not
  state, so only the state travels.
- All randomness flows through `CampaignRng`; its integer state is persisted in
  `state.rng_state` and threaded through every resolution step, so identical
  (seed, actions) sequences produce identical campaigns — the property the
  integration tests and future replay/debugging tools rely on.

## 10. Roadmap

Phases follow the research report (§17). Status as of this document:

| Phase | Scope | Status |
|---|---|---|
| 0 — Design & setup | Schemas for all 16 tables, repo, CI, save format, this document | **Done** |
| 1 — Campaign map & turns | Region graph, sea zones, movement & forced march, fog of war, end-turn loop, seasons | **Done** |
| 2 — Settlements & economy | Growth/order factor lists, squalor, plague, buildings & queues, taxes, trade, corruption, treasury, riots/revolts, capture options | **Done** |
| 3 — Armies & battles | Recruitment, experience, retrain/merge, garrisons, sieges, mercenary hiring, sea transport (abstracted crossing), **BattleResolver interface + AutoResolver**, debt disbandment | **Done at foundation depth**, plus the **military strategy layer** (§5.5–5.8, §3.3): unit-class counters and per-class terrain/walls in an RNG-free estimator, kit upgrades and armouries, the casualty/rout model, garrison quality, levy strain, war mood, and doctrines. Remaining: embark-on-fleet transport, naval battles & port blockades, forts/watchtowers, ambush |
| 4 — Characters | Trait/ancillary trigger engine, family tree, succession, marriage/adoption, natural death, hero-of-the-field | **Done.** Trait points with anti-trait erosion, triggers (governing/campaigning/idle/battle/siege/occupation), retinue acquisition & transfer, effective attributes wired into order/income/growth/movement/battles; yearly aging, natural death, succession & set-heir, coming of age, births, marriage suitors, adoption, man-of-the-hour. `office_gained` triggers await Phase 7 offices |
| 5 — Agents & diplomacy | Envoys/spies/assassins, negotiation offers, AI attitude model | Pending; symmetric stances + war declaration live (`DiplomacyRules`), hostile acts auto-declare war |
| 6 — AI opponents | Modular economy/expansion/diplomacy/war behaviors, difficulty tuning | Pending; `AiStub` manages settlements passively, difficulty constants live in balance.json |
| 7 — Politics, events, victory | Full senate offices & mission variety, civil war depth, richer event scripting | **Foundation loop built** (standings, take-region missions, civil-war trigger, army reform, wonders, victory checks); depth pending |
| 8 — Polish | Campaign UI, balancing pass, tutorial, save robustness | **Campaign UI playable**: start menu (house/difficulty/seed), pannable geographic map (owner tokens, adjacency roads & sea lanes, army badges, siege rings, fog), settlement panel with live factor breakdowns/taxes/queues, army orders (march, sail, attack, besiege, assault with occupation choice, mercenaries, garrison), family scroll (heir, retinue transfer), reforms scroll, attack odds preview and battle reports, turn log, save/load. Balancing pass and tutorial pending |
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
