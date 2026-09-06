# Roman War — Game Design Document

**Status:** living document. Describes both the design intent and what the engine
in `src/core/` actually implements today — Phases 0–7 of the roadmap (the
Senate's politics are §8.1), the Phase-8 campaign UI, the societal layer
(§4), the guided trail (§10) and the Deep Strategy layer (§12). Section 13's
status table is the single source of truth; where a system is planned but not
built, this document says so explicitly. Design rationale and genre research:
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
| 1 | AI turns | Every non-player faction plays (`FactionAi`, §9): peace/war decisions, armies (raise, merge, march, attack, besiege, assault, defend), then economy. `begin_round` ages the war ledger once for the world |
| 2 | Diplomacy upkeep | Tribute schedules pay out, remembered grudges and favors decay, stale offers to the player lapse (`DiplomacyRules.process_turn`) |
| 3 | Governors re-derived | Governorship follows character presence, so it is refreshed before anything reads it |
| 4 | Sieges progress | Starve-outs force a final battle through the `BattleResolver`; an automatic capture always *occupies* (the player's own assaults ask) |
| 5 | Queues advance | Construction and recruitment, per settlement; one head-of-queue job ticks per turn |
| 6 | Edicts tick | Standing orders take hold and are billed — a freshly issued edict starts both in the same turn (§4.10) |
| 7 | Treasuries resolve | Per faction: income − upkeep (armies, fleets, garrisons, agents); deep debt disbands the costliest field unit; then standing drips, cooldowns, and the insolvency rule that collapses the dearest policy the turn the silver runs out |
| 8 | Population | Growth applied, plague rolled and progressed, slave & conquest counters tick down |
| 9 | Society | The eight stocks integrate (§4); surveys are taken where due; advances are gained or forgotten |
| 10 | Public order | Riots damage settlements; sustained collapse — or a province in open revolt — secedes to the rebels |
| 11 | Events | Scripted, date and condition events, disasters |
| 12 | Knowledge | Awareness spreads by contact, adoption programs advance, reform pressure decays (§12) |
| 13 | Senate | Each summer the magistracies are refilled (§8.1); once the Senate has fallen the Republic's offices dissolve, its charges are void and its civil war is settled. Then per Roman house, in sorted order: popular standing drifts; the charge is judged and a new one issued — the Senate's demand for the patriarch's life outranks whatever charge stood, and a refused demand outlaws the house; Ambition past its threshold forces a civil war on its own |
| 14 | Character triggers | `CharacterRules.process_turn`: governing / campaigning / idle triggers fire for every living family member |
| 15 | Guided trail | `GuidedRules.process_turn` (§10) judges the turn's final world: stages complete or expire, rewards pay, new stages open |
| 16 | Date & bookkeeping | Event happiness, war moods (§3.3) and modifiers tick, mercenary pools replenish, turn and season advance; on a year change `FamilyRules.process_year` runs (aging, deaths, births, succession, marriage, adoption); movement resets |

`end_turn` returns a report dictionary (`ai`, `diplomacy`, `sieges`,
`completed_buildings`, `completed_units`, `rioted`, `revolted`, `society`,
`advances`, `events`, `knowledge`, `senate`, `characters`, `guided`, `winner`)
and writes the day's journal into `state["journal"]` (§2.3.1), which is what the
UI actually plays and recaps.

### 2.3.1 The turn journal

Every notable step above appends a **beat** to `TurnJournal`
(`src/core/turn_journal.gd`). A beat is deliberately content-free — ids and
numbers only:

```gdscript
{kind, faction, other, region, subject, value, extra}
```

Every word the player reads comes from `data/dispatch.json`, keyed by `kind`.
`TurnJournal.KINDS` is the single source of truth for the kinds that exist, and
`tools/validate_data.py` parses it and requires it to match `dispatch.json`
exactly **in both directions** — a beat with no prose, or prose for a beat
nothing emits, fails the build.

The journal lives in the game state and holds **one turn**, rebuilt every
`end_turn`. That bounds it (a 568-turn campaign never accumulates), lets a save
reopen on exactly the day it was taken, and makes it comparable byte for byte in
the determinism tests.

Three things are reported by **photographing the world before and after** the
turn rather than by instrumenting the code that changes them
(`TurnJournal.snapshot` / `TurnJournal.diff`): diplomatic stances, settlement
tiers, and each faction's treasury, capital and regions held. Stances in
particular change hands in the player's own panel, inside the AI, and implicitly
whenever an army attacks (`CombatRules.attack_army` declares war by drawing
blood) — a diff catches all three paths with no plumbing, and it is why a war
beat reads *"War between X and Y"* rather than naming an aggressor the engine
cannot honestly identify.

### 2.3.2 The day, on screen

The turn resolves in a single synchronous call; everything after it is replay.
`DispatchRules.visible_beats` (`src/core/rules/dispatch.gd`) filters the journal
to what the player is entitled to know — the rule per beat kind is authored in
`dispatch.json` as `own`, `region`, `own_or_region` or `public`. Wars and
alliances are `public`: they are proclaimed, not discovered. Army movements are
`region`-gated, so scouting still matters.

`TurnSequence` (`src/ui/turn_sequence.gd`) then plays the filtered beats over the
map — a dawn frame, the day's business with the camera panning to each beat under
a light that runs from cold morning to red evening, a dusk frame — with a speed
control and SKIP. `DispatchPanel` closes the day with the recap, sectioned by the
chapters `dispatch.json` declares. Playback is presentation only:
`CampaignScreen.playback_enabled = false` resolves the identical turn with no
animation, which is how the headless suite drives twenty-five turns in a loop.
### 2.4 The map

The campaign map is a **region graph**, not a tile grid. Each region has exactly one
settlement, a terrain type (`plains, forest, hills, mountains, desert, steppe,
marsh`), a fertility rating (0–3), resources, land adjacencies, and the sea zones it
touches (non-empty = coastal). Sea zones form their own adjacency graph for fleets.
Every region also carries a **`position`** (`x` 0–100 west→east, `y` 0–100
north→south) placing it at its real geographic location, which is what the campaign
map draws; sea zones carry anchor positions the map uses for its sea labels.
`MapRules` provides BFS hop counts (cached per map, used for distance-to-capital and
corruption), adjacency, shared-sea-zone and coastal queries. Fog of war (`VisibilityRules`): a
faction sees its towns and ordinary armies plus one hop out; pure mounted
columns and spies see two hops. Watchtowers see two and fortified posts three.
Fleets reveal the coastal regions of their current sea zone. These radii live
in `balance.reconnaissance`.

The 0.12 presentation keeps that graph and adds three map scales. At close
zoom (1.8×–5.5×), original procedural miniatures show settlement wards, fields,
camps, troop ranks and mounted commanders; territory view retains aggregate
markers. `MapOrderRules` provides a read-only order intent with season-labelled
legs and fog-aware costs. The map order strip can pin that intent before
execution, while conventional right-click orders remain available. March
animation consumes the execution's traversed ids, never advances the engine,
and shares its displayed positions with hit testing. Retained detail chunks
are culled outside the viewport; only the small army layer animates. See
`docs/reviews/2026-09-map-experience.md` and PLAYING's 0.12 controls.

The 0.13 layer adds `ReconRules`, additive `watchposts` and `recon` state,
slowest-unit movement budgets, explicit observation posts, and field-fort
strength through the existing BattleResolver context. Watchposts require
friendly provincial ownership; losing it disables the post. `MovementRules`,
field-battle advances and siege entry record observed enemy steps at the
moment of relocation. The journal's `army_sighted` payload contains only
public counts, commander identity and observed endpoints. A later visibility
change cannot disclose a hidden endpoint; replay works even if the force has
since merged or disappeared. Last-known contacts expire after three seasons.

`CommanderArt` resolves stable cosmetic character features and the 21 faction
styles in `unit_art.commanders`. Owned troop miniatures use the existing unit
kits and overrides; rivals use cultural dress without inspecting their hidden
roster. Portrait layout and miniature picking share displayed coordinates.
Direct army clicking and army dragging order travel, empty-land/Space/middle
dragging pan, and a distant journey is pinned for review before it is queued.
See `docs/reviews/2026-09-v13-map-overhaul.md` for implementation boundaries and
release verification.

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
| levy_strain | −0.05% per strain point (§3.3) — men marched off to the levy are men not at the plough |
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
| garrison | (policing ÷ population) × 400, capped at +80; policing = Σ soldiers × class `garrison_weight` × (1 + 5%/chevron), × (1 + 10% per `drill` level in the town) × practiced warcraft (`garrison_order_pct`) — a cohort of veterans keeps a city quieter than a mob of levies twice its size (§6.7) |
| governor | +5 per influence point; −5 if ungoverned |
| squalor | −population ÷ 3,000, capped at −25 |
| distance_to_capital | −8% per hop beyond 2 free hops, capped at −80 (§3.4) |
| culture_penalty | −((100 − Belonging) ÷ 100 × 40) — now a drifting stock, not a building census (§3.5, §4) |
| recently_conquered | up to −30, decaying 5 per turn |
| levy_strain | −strain; recruiting or refilling adds (men ÷ population) × 100 points, softened 15% per drill level, capped at 30, fading 2 per turn (`RecruitmentRules.add_levy_strain`) |
| war_mood | +5 for 4 turns in every town of a faction that has just won a **decisive** battle (a triumph); −8 for 4 turns after a decisive defeat. Decisive = ≥1,500 men engaged and the loser destroyed, or ≥50% lost against ≤20%. The strongest standing mood wins; an equal or stronger one replaces it and restarts the clock (`CombatRules.record_battle`) |
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
**offices** (government tiers across the empire — and, for a Roman house, every seat
it holds in the Senate's magistracies, by rank: §8.1) and by **military commands**
(armies in the field). That single choice makes the model fail symmetrically:

- **Militarist** — martial spirit raises the conscription load in every province, drags the
  legitimacy target down, and puts armies in the hands of ambitious men.
- **Pacifist** — nothing absorbs ambitious sons but politics, so a wealthy demilitarised
  state eats itself from the inside.

A legitimate state damps the growth of claimants (`elite_legitimacy_damping`): one its own
elite believes in turns them into servants rather than factions. Above
`elite_civil_war_threshold` a Roman house is forced into civil war on ambition alone,
alongside the Senate's demand in §8.1; other cultures get the generic path through
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
population** (which may never fall below 400) and leaves **levy strain** behind
(§3.3). One unit completes per turn from the head of the queue and joins the
garrison carrying the settlement's **recruit profile**
(`RecruitmentRules.recruit_profile`): starting experience from the best
`recruit_xp` building (drill halls, war temples) plus practiced techniques,
edicts and boons, and `weapon` / `armor` levels summed from its forges,
armouries and forge temples plus practiced metallurgy, capped by
`balance.recruitment.upgrade_max` (§6.7). The region panel shows what recruits
will receive before you pay.

**Harbours.** A ship finishes in its port's `harbour`, a second unit list on
the settlement beside the garrison (`RecruitmentRules.deliver_unit` routes by
class; `NewGame` and `ensure_state_keys` create the key, so a pre-harbour save
loads). Harbour ships pay upkeep like any unit and are re-armed by retraining.
`NavalRules` launches ticked ships as a fleet into a sea the port touches
(the fleet sails from the next season), docks a fleet at one of its owner's
ports on its sea for one lane of movement, and merges or splits fleets;
`NavalRules.normalise` on load sends any ship that somehow stands in a land
garrison back to the harbour. The AI never queues a ship and never uses a
harbour — the sea is still the player's alone (§13, Phase 3).

### 6.2 Experience, retraining, merging

- Units carry **experience 0–9** (chevrons); each grants +10% effective strength.
  Winners of a battle gain +1, or +2 when they were the paper underdog (§6.6).
- **Retraining** in a settlement with the required building refits every
  garrison unit to the town's current kit standard (weapon and armour levels
  are never taken away) and refills depleted units to 100%, costing half the
  pro-rata recruitment price and drawing the missing men from the population.
- **Merging** combines depleted same-template units, keeping the higher
  experience and the better kit.

### 6.3 Movement and forced march

Armies get **2 movement points** per turn. Entering a region costs its terrain
rate (plains/steppe 1.0; forest/hills/desert 1.5; mountains/marsh 2.0) reduced by
the destination's road tier (×1.0 / 0.75 / 0.6 / 0.5). **Forced march** doubles
the budget but marks the army fatigued — a −20% battle strength malus until next
turn, unless the men (`hardy`) or their practiced warcraft (camp discipline)
shrug it off. An army cannot *move* into a region containing a hostile army or a hostile
settlement: that is an attack or a siege, taken as an explicit action. Fleets move
between adjacent sea zones at 1 point per lane.

**Pathfinding and marches** (`PathfindingRules`): a deterministic Dijkstra over
`step_cost` prices whole routes, so the cheap plains road genuinely beats the
short mountain pass; a step no full turn's budget could ever pay for is never
offered. `reachable` bounds a turn's reach (the UI's range overlay), `best_path`
returns legs/cost/turns (the UI's hover preview) — turns are estimated by
walking the legs exactly as marching spends them, wasted remainders included —
and a destination beyond one step becomes a **march order**: `march_path`
queued on the army, resumed by the turn engine after movement resets, in sorted
army order, drawing no randomness, and cancelled by any other explicit order
(a besieger never walks away from its own siege). A march only ever replays
legal `move_army` steps: a step that has become illegal cancels the rest, so a
march can never attack, besiege, or declare war. Previews are blocked only by
hostile armies and at-war settlements the owner can *see* — a route that
swerved around an unseen ambush, or an unexplored enemy town, would paint
allegiances through the fog; execution still halts against hidden reality when
the army gets there. A visibly barred destination halts the path in the
cheapest region beside it.
The abstracted sea crossing (a coastal region to another on the same or an
adjacent sea zone, spending the whole turn) may land on the shore of a faction
the army's owner is **at war** with — an amphibious invasion — provided no
hostile field army contests the beach; the garrison waits behind its walls for
the siege. Without this rule, island regions with no land link (rebel-held
Creta and Cyprus among them) could never change hands, and Egypt's long
campaign could never be won. Landing on any other shore follows the same rules
as before.

**Attacks cost the season, and generals cannot be stranded.** An attack across
a border needs movement enough for the step into the defender's region (the
winner ends up there) and spends all of it; a storm needs movement and spends
the season too (`Game.attack_army`, `Game.assault_settlement`). A siege laid
from the neighbouring region pays the same step (`SiegeRules.begin_siege`),
and a field army standing before the walls — an enemy's, or the city's own
owner's, since investing a neutral city is the declaration — must be beaten
before the city can be invested; a besieger that merges into reinforcements
at the same walls hands the siege and its clock over rather than lifting it.
The attack rule is enforced in the player facade only: `AiMilitary` attacks
through `CombatRules.attack_army` directly and still pays nothing, a
documented asymmetry to close when the AI is next tuned. Debt disbandment
(`EconomyRules._disband_costliest_unit`) skips a general's last unit, so a
commander is never left without a single man.

**Regrouping** (`ForceRules`, behind `Game.raise_units` / `transfer_units` /
`merge_armies` / `split_army` / `disband_unit` / `attach_general` /
`detach_general` / `consolidate_units`, each returning `{ok, error, …}` and
mirrored by `Game.check(action, args)` for greying buttons): armies are raised
from ticked garrison units under a captain or an eligible character standing in
the city; units are transferred between co-located forces of one owner or into
an own city's garrison; whole armies merge; ticked units split off under a
chosen leader. Movement — and forced-march fatigue — are conserved through
every transfer: a unit remembers the least movement of any force it stood in
this season (`muster_march_left`, `muster_sail_left`, `muster_fatigued`,
`general_march_cap`; ships making port by transfer pay the lane a docking
fleet pays), so shuffling men between stacks can never gain a step or shed
weariness, and nobody walks into an invested city from the field or from
another stack (`garrison_army`, `transfer_units`). Disbanding returns the men to the local population
(`balance.forces.disband_population_return_pct`). The stack cap is
`balance.recruitment.army_unit_cap`; a general keeps at least one unit; two
generals cannot share a camp in the field. An emptied army dissolves, releasing
its siege and refreshing governorships. Every rule module here draws no
randomness and iterates sorted ids.

### 6.4 Sieges

A besieging army invests a hostile settlement (`SiegeRules`), immobilizing itself:

- After **2 turns** (`siege.equipment_turns`, less what the besieger's practiced
  siegecraft shaves off — `siege_equipment_turns_delta` — never below
  `siege.min_equipment_turns`) siege equipment is ready and an assault may be
  launched; the panel says how many turns remain and quotes the odds.
- Defenders hold out for **2 / 3 / 4 / 5 / 6 / 8 turns** by settlement level;
  when supplies run out the garrison fights a desperate final sally (walls count
  one tier less, sally strength +10%).
- Assaults resolve through the `BattleResolver` with the settlement's **wall tier**
  multiplying defender strength (×1.0 → ×3.0 across the six wall levels).
- A captured settlement goes through the occupy/enslave/exterminate choice; the
  turn engine's automatic starve-outs default to occupation.
- The besieger always gets one full turn with the engines ready before the
  garrison's supplies decide the matter (`starve_at = max(supplies,
  equipment_turns + 1)`); peace lifts a siege the next turn; every path that
  moves, garrisons, merges, dissolves or destroys the besieger calls
  `SiegeRules.release`, so no settlement is marked invested by an army that is
  no longer at its walls. A besieged city neither recruits, retrains nor
  builds, and raises no army — nobody marches out past the siege lines.

### 6.5 The BattleResolver contract

The single seam between campaign and battle, `src/core/rules/battle/battle_resolver.gd`
(the file's header comment is authoritative):

```
resolve(data, rng, attacker_units, defender_units, context) -> BattleResult

unit:    {template, experience 0-9, strength_pct 1-100, weapon, armor}
         (arming levels stamped at recruitment, 0..recruitment.upgrade_max and one
          more with a cap-raising technique; mutated in place: casualties,
          destruction, experience)
context: {terrain, wall_level, attacker_general, defender_general,
          attacker_fatigued, sally, attacker_martial, defender_martial,
          attacker_mods?, defender_mods?}
         *_martial = the owner's martial ethos 0-100 (SocietyRules)
         *_mods = ArmyMods, a pre-merged dict of faction-wide modifiers
         (class stat deltas, matchup / terrain percentages, scalar bonuses)
         built campaign-side by KnowledgeRules.army_mods so the resolver
         never reads game state.
BattleResult: {winner, attacker_casualty_pct, defender_casualty_pct (men actually lost),
               attacker_general_died, defender_general_died, experience_gained,
               attacker_destroyed, defender_destroyed, walkover,
               breakdown: {attacker: SideEstimate, defender: SideEstimate,
                           ratio, fortune: {attacker, defender}},
               rounds: [...], attacker_report / defender_report: [...]}  (playback, optional)
```

Campaign code treats every key but `winner` as optional: it derives destruction
from the mutated unit arrays when a resolver omits the flags, and a `walkover`
(one side had no strength — an empty garrison) is neither recorded nor mourned.

`BattleResolver.estimate(data, attacker_units, defender_units, context)` is the
shared, **RNG-free** half of the model. It returns both sides' `SideEstimate`
— strength, a multiplicative factor list `[{label, value}]` (`base` carries the
raw soldiers × quality sum; every other entry is a multiplier), per-class rows,
per-unit profiles — plus the paper `ratio` and an analytic `attacker_win_chance`.
Every resolver, the UI's odds preview and the battle report read the same
numbers from it, and `BattleResolver.force_strength(data, units, general)` —
the one-sided estimate the faction AI (§9) plans with — is the same model with
no opponent in sight, so the AI's expectations track whatever resolver actually
fights the battle. Campaign modules (`CombatRules`, `SiegeRules`, `TurnEngine`)
consume only this contract. A future real-time battle scene implements the same
`resolve`; the campaign never learns which ran.

### 6.6 Auto-resolve model

Per unit, in order (each stage is a named factor in the breakdown):

1. **base** — soldiers × class `mass` × quality, quality = attack + missile×0.5 +
   defense + morale×0.5 + charge×0.25. `mass` (unit_classes.json) is a soldier's
   fighting weight relative to a foot soldier: a horseman and his horse 2, a
   horse archer 2, a chariot 3, an elephant 8, an artillery crew 2, a general's
   escort 2.5 — so a 60-strong squadron is not a third of a 160-strong phalanx.
2. **upgrades** — the arming stamp: each weapon level scales what the unit deals
   (attack and missile) by `battle.weapon_upgrade_attack_pct`, each armour
   level what it takes (defense) by `armor_upgrade_defense_pct`; morale and
   the charge stand outside both.
3. **techniques** — class stat deltas from the side's `ArmyMods` (plus its
   `battle_strength_pct` / `attacking_pct` scalars, merged into the same factor).
4. **experience** — +10% per chevron.
5. **matchups** — `1 + (Σ enemy_share × M[my class][their class] − 1) × matchup_weight`,
   where enemy shares are *slot* shares (one unit card = one slot, scaled by
   strength) and `M` is `data/unit_classes.json` times the unit's attribute and
   warcraft percentages. Pikes and spears stop cavalry, cavalry rides down
   infantry and foot missiles, missiles shred elephants, chariots and slow pike
   blocks, horse archers kite infantry but lose to light horse and slingers.
6. **class_terrain** — the per-class terrain table (cavalry and pikes suffer in
   woods and mountains, missiles like high ground), for both sides.
7. **assault / wall_defense** — when `wall_level > 0`, each class's storming or
   wall-holding multiplier (cavalry 0.5 / 0.6, artillery 1.6 / 1.3 …).
8. **attacking** — attribute bonuses that fire only when charging (war cry).
9. **fatigue** — forced-march malus unless the unit or its warcraft is immune.

Then side-wide: **general** (command 5%/pt, troop morale 2%/pt), **martial**
(a society oriented toward war fields better soldiers:
`martial_ethos_strength_pct_at_full` at full ethos — what militarisation buys,
against everything it costs in §4), the defender's **terrain** ground bonus and
**walls** tier multiplier, **combined_arms** (+6% when line, shock and missile
roles each hold ≥15% of the cards), and **sally**. Both sides then roll fortune
(`battle.randomness_pct`, ±20%) and the higher strength wins; `win_chance`
integrates those two rolls analytically so the UI can say "72% to win".

An empty garrison or a phantom army is a **walkover**: the paper ratio is
pinned to `battle.walkover_ratio`, nothing is rolled, nobody is lost, nobody
learns, and the round log is empty.

**Casualties** come in two parts. The *melee* pool is set by the post-fortune
ratio (base 25% each side, ratio floored at `melee_ratio_floor`, clamped
2–95%) and shared out so that units the enemy countered bleed more and units
that countered him bleed less — each unit's weight is
`matchup^−casualty_matchup_weight`, clamped 0.5–2.0 and soldier-normalised so
the side's mean melee loss is the pool. The *rout* falls on the loser only:
`loser_extra_casualty_pct × (1 + (winner pursuit − 1) × pursuit_scale)`, where a
side's pursuit is the slot-weighted mean of its units' speed-derived pursuit
factors (a mounted victor runs the beaten down harder), divided per losing unit
by its own escape factor (fast units get away; speed `neutral_speed` is the
pivot for both). One ±30% scatter draw per unit; units under
`unit_destroyed_below_pct` strength are destroyed. The result reports the men
**actually** lost, `attacker_destroyed` / `defender_destroyed`, and the
per-unit `*_report` and synthesized `rounds` the animated playback reads — the
log is retold from the totals and adds no die (the draw count is exactly two
fortune rolls, one scatter per unit and the loser's one general-death die).
Winners gain +1 experience, or +2 when they were the paper underdog by ≥1.3;
a losing side's general dies with 10% probability. The model is a paper one by
design — it exists to be replaced behind the same interface.

### 6.7 The arms industry

Military buildings shape the men they produce, and the towns that hold them:

- **Barracks** tiers carry `drill` (1/1/2/2 from the drill grounds up; tribal
  1/1) and, from the third tier, `law` (2/3/4) — a garrison headquarters polices
  the streets. Top-tier stables and archery ranges add `drill` 1.
- **Armouries** (`kind: armoury`, one chain per culture group, `requires_building:
  barracks ≥ 2`) issue `weapon_upgrade` and `armor_upgrade`: smithy → armoury →
  state arms works (weapon 1 / 1+armour 1 / 2+armour 1; tribal forges stop at the
  second tier). Barracks L4–5, the great engine works, forge temples and practiced
  metallurgy (mail armour, Noric steel) add to the same pool; the sum is capped at
  `recruitment.upgrade_max` (3), one more with an armourers' guild.
- In battle each weapon level is worth `battle.weapon_upgrade_attack_pct` of the
  unit's attack and each armour level `armor_upgrade_defense_pct` of its defence
  (§6.6 stage 2) — an armoury is worth roughly a chevron.
- `requires_building` is a general chain prerequisite: a chain is offered only
  where the settlement already holds the named kind at the named tier
  (`ConstructionRules.blockers_for` names it, the glossary words it).
- Like every chain, an armoury costs its town something (`burden`, `martial` —
  §4).

### 6.8 Warcraft — military techniques

Military technology is a matter of **techniques** (§12): the `warcraft` domain
(drill, formations, the traditions of the arms — 30 at ship) and its neighbours
(military engineering, metallurgy). They follow the same aware → adopting →
adopted life as every other craft — heard of by origination, contact, conquest
or a spy; institutionalized for denarii and seasons, one program at a time,
discounted by the reform pressure that defeats build up — with two additions:

- A `war` block beside the flat `effects`: per-class stat deltas, matchup and
  terrain percentages, upkeep percentages, recruit experience and the fatigue
  flag, merged in sorted order by `KnowledgeRules.war_effects` into the
  `ArmyMods` dict the resolver receives (`army_mods`). Flat battle scalars
  (`battle_strength_pct`, `attacking_pct`, `assault_pct`, `wall_defense_pct`,
  `pursuit_pct`, `escape_pct`) and campaign scalars (`upgrade_cap`,
  `siege_equipment_turns_delta`, `garrison_order_pct`, `levy_strain_pct`,
  `movement_points`, `mercenary_cost_pct`) stay in `effects` and reach their
  readers through `faction_effect_total` like any other key.
- Prerequisites that read the faction's **war record**
  (`{battles_won, battles_lost, faced: {class: n}}`, kept by
  `CombatRules.record_battle` after every field battle and assault): `era`,
  `battles_won`, `battles_lost`, `faced {class, battles}` — how a people
  *learns from whom it fights*: the Iberian sword after facing infantry, the
  woodland ambush after meeting legions, the thureophoroi after a defeat. A
  technique naming `factions` is a **closed tradition**: only those courts may
  originate, hear of, or take it up (the Seleucid elephant corps, Britain's
  chariots); rumour and conquest pass it to nobody else.

The 270 BC endowments (`start_adopted.factions`: Rome's manipular drill,
Macedon's sarissa, Parthia's composite bow, Numidia's horsemanship …) are
practiced from turn one. The AI adopts by persona priorities like every other
craft. `KnowledgeRules.unmet_prerequisites` returns `{kind, params}` blockers
(building, resource, technique, era, battles_won, battles_lost, faced,
tradition) the knowledge scroll words. The catalogue, with historical notes,
is laid out for the player in `docs/MILITARY_STRATEGY.md`.

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
  `settlement_exterminated`, `came_of_age`, and `office_gained`, fired by the summer
  elections (§8.1). The validator warns about any unfired kind so dead content
  cannot ship silently.
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
  `campaign.json`. Stances gate movement, trade routes and grain imports;
  attacking or besieging declares war. Stances change through the negotiation
  layer (§7.2); `DiplomacyRules.set_stance` remains the mechanical primitive
  underneath. The AI declares wars of its own and lets stalled AI-to-AI wars
  gutter out into white peace (§9).

### 7.2 Attitude, negotiation, agents

- **The attitude model** (`DiplomacyRules.attitude_breakdown`): how faction *a*
  regards faction *b*, as a named factor list the UI renders like growth and
  order — current stance, cultural kinship, border tension, fear of the
  stronger, temptation of the weaker, the persona's ambition, remembered
  history, senate rivalry between Roman houses, and (toward the player only) a
  difficulty bias. **Memory** is a clamped per-pair number that decays toward
  zero each turn: war declarations are remembered against the declarer, a
  broken alliance doubly so, gifts and tribute warm it.
- **Offers** are priced in denarii from the receiver's chair
  (`evaluate_offer`, a factor breakdown of its own): payments, recurring
  tribute (`state.tributes` pays out at step 1.5), region cessions
  (`cede_region` — the garrison marches home, the family flee ahead, no loot,
  a mild unrest penalty), and stance changes. Peace is cheap for the losing
  side and costs the winner (`peace value` scales with relative strength);
  alliances demand real regard, not just coin. Hard floors no price overrides:
  the capital, the last settlement, promises that cannot be paid. The
  negotiation dialog previews the appraisal live (hard vetoes are shown by
  name); AI↔AI offers resolve immediately; AI→player offers wait in
  `state.pending_offers` with an expiry, and are honored only while they
  still stand (proposer alive and solvent, land still held, no war begun
  since). A concluded peace banks decaying goodwill on both sides — a truce
  that stops the winner re-declaring the same season; an unpayable tribute
  schedule collapses in default, remembered against the debtor.
- **Agents** (`AgentRules`, `data/agents.json`, `state.agents`): diplomats,
  spies and assassins walk the terrain map across **any** border, cost hire
  and upkeep, and grant sight where they stand. A **spy** reads a settlement
  (garrison, works, mood) and reduces the wall tier of his owner's assault by
  an opened gate. A **diplomat** sweetens his owner's offers at the host's
  court and can buy a *leaderless* band off the map, priced per head — men
  under a general refuse. An **assassin** kills with odds =
  base + skill − personal_security − counter-intelligence (clamped), success
  settling the succession at once and sharpening his skill, failure risking
  the blade. The two long-dormant authored effects finally have engine
  readers: `personal_security` (target's traits/retinue) defends against the
  knife, and `agent_skill` on a **governor's** retinue is counter-intelligence
  hardening his whole city.
- **Deliberately deferred:** the AI does not recruit or use agents yet (it is
  omniscient, so spies would add nothing, and AI assassins without counterplay
  UI are pure feel-bad; governor counter-intelligence already defends its
  cities). Sabotage and map-information trading likewise wait.

### 7.3 The campaign AI

Every non-player faction plays the full game through the modules under
`src/core/rules/ai/`. **§9 is the authoritative account** — what each module
owns, how wars start and end, and what the AI deliberately does not do.

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

### 8.1 The cursus honorum and the road to civil war

Roman houses carry `senate_standing` (starts 5, range −10…10) and
`popular_standing` (drifting toward 0.3 per held region, never assigned). The
Senate is the faction flagged `is_senate`, looked up by flag rather than id;
everything below runs only while it lives.

**Charges.** Each turn `SenateRules` keeps one charge per house: a mission with
a deadline, treasury/standing rewards (+1, plus unit grants mustered in the
capital) and standing penalties (−2) — *take_region* against rebel regions
bordering the house, *make_alliance* and *reach_trade_agreement* courting a
bordering foreign power (an alliance carries trade rights, so it satisfies
either), *assassinate_leader* naming the crowned head of a foreign power the
house is at war with (by blade, battle or misadventure), and the demand below.
One judge decides every kind; `SenateRules.LIVE_KINDS` names what is judged and
the validator fails any authored kind that is neither live nor
forward-allowlisted (`blockade_port`, the naval remainder, is the only one left).

**Offices.** `data/offices.json` holds the six magistracies of the cursus:
quaestor (rank 1, four seats, from age 20), aedile (2, four seats, 24), praetor
(3, two, 28), pontifex maximus (4, one, 32, held for life), consul (5, two, 32)
and censor (6, two, 36) — fifteen seats. Each carries attribute effects (`command`,
`management`, `influence`) that `CharacterRules.effect_total` adds to the
holder, so an office reaches governance, battle odds and the choice of heir
exactly as a trait does. Every **summer** the Senate refills every seat. The
candidates are every living man of every living house not at civil war who has
reached the office's age; his score is his house's senate standing ×
`election_standing_weight` plus his own effective influence with the office he
already holds wiped (the un-officed baseline); ties break on age, then id;
seats fill from the censorship down, and a man never stands for a rank below
the highest he has held — the cursus climbs. The pontifex maximus, the one
`for_life` office, keeps his seat until death and stands for nothing else. The
ladder is enforced through
`requires_prior_rank` against a man's `offices_held` (aedile and praetor want a
quaestorship, the consulship a praetorship, the censorship a consulship) and
**waived when no remaining candidate satisfies it**, so a lean year seats men
out of turn and the 270 BC start bootstraps itself. Taking a seat appends
`offices_held`, credits the `offices_held` deed, records `office_taken` in the
chronicle from the praetorship up (`annals_office_min_rank`), fires the
`office_gained` trigger (four traits and three ancillaries hang on it) and the
`office_gained` journal beat — and the consulship, the one `eponymous` office,
is proclaimed to every court as `consuls_elected`. Death vacates a seat; a
house at civil war is stripped of its seats and barred from the ballot; when
the Senate falls every office dissolves.

**Why offices matter.** `SocietyRules.apply_faction_turn` drains a Roman
house's Ambition by `elite_office_absorption_per_seat_rank` per rank held
(§4.4) — calibrated so a quaestorship absorbs twice what one provincial
government tier does and a consulship what two and a half army commands do;
the soak's first reading, at a third of that, showed a house holding five
seats boil over all the same. A house in good standing seats its sons and its claimants have
somewhere to go; a house shut out of the curia — its standing collapsed by
failed charges — loses the drain, and its Ambition climbs toward
`elite_civil_war_threshold`, the automatic road to civil war.

**The Senate's demand.** The standings road no longer fires a war by itself.
When a house's `senate_standing` has sunk to `leader_suicide_standing` (−5)
while its `popular_standing` has risen to `leader_suicide_popular_min` (5) —
too great and too hated — the Senate voids whatever charge stood (no penalty)
and issues *The Senate Demands Your Life*, naming the patriarch, with the
charge's four-turn deadline. **Comply** (`Game.comply_senate_demand`; an AI
house does so on the demand's last turn) and the patriarch dies by his own
hand, succession runs, and the charge pays (+6 standing — a life buys the house
back above the gate, so the Senate does not name the heir next). **Refuse**
until the deadline falls and the house pays the penalty (−5), is marked
`outlawed`, and is at civil war; the outlawry is the verdict, so no failed-charge
beat is printed beside it.

**A civil war with sides.** `_declare_civil_war` sets the rebel's
`at_civil_war`, declares war on the Senate and lets every other living house
choose by its own standing: at or below `civil_war_join_standing` (1) it joins
— an alliance with the rebel, war on the Senate, its own `at_civil_war` — and
otherwise it stays loyal and declares on the rebel. The player's house is never
conscripted into another's rebellion: it stands with the Senate unless it is
the rebel itself (joining by choice is a follow-up). Every house in arms is
allied with every other, and a house that joins is a rebel in its own right —
its war ends with its death or the Senate's fall, never with the first rebel's.
Rebels lose their seats and their place on the ballot; the war is chronicled
(`civil_war`, magnitude 8, with its joiners and its cause), the journal names
the road (`civil_war` for outlawry, `civil_war_ambition` for the break), and
the `first_civil_war` event fires on the first. Two engine predicates keep the Republic's wars honest.
`DiplomacyRules.roman_war_forbidden`: no war among the houses and the Senate
outside a civil war, enforced inside `declare_war` and therefore in every
attack and siege — nobody marches on Rome on turn 1. `roman_peace_forbidden`:
a civil war is **never talked away** — a named veto in `evaluate_offer`,
queued envoys voided by `offer_still_stands`, the AI's peace and white-peace
passes skipping the pair, `Game.set_stance` refusing. **The end** is the
Senate's fall: `at_civil_war` and `outlawed` clear, Roman-internal wars go
neutral (alliances kept; the ledger closes those wars with a summary and no
oath of peace), the offices dissolve, every standing charge is voided, and
`civil_war_over` is proclaimed. From then on no charge is issued or judged and
no house can break — there is nothing left to break with. A rebel house
destroyed ends its wars by death as any faction does. Roman long-campaign victory still requires the Senate destroyed; a
joiner that outlives it and holds Rome may claim it.

**The AI.** `AiPolitics` is the houses' one political act: comply with the
demand on its last turn (`ai.senate_comply_turns_left`). `AiDiplomacy` also
presses the Senate's courtship charges — a house holding one sends its envoy to
the named power before any other, and that court judges the offer as it judges
every other, so a hated neighbour can still fail the charge. In the core rules an AI house therefore reaches civil
war only by Ambition. Defiance as a persona knob, canvassing (buying an
election with silver at the cost of Ambition), a player-declared crossing of
the Rubicon, and proscriptions are the follow-ups (`docs/HANDOFF.md` §8).

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

## 9. AI Opponents

Every non-player faction is played by a modular AI (`src/core/rules/ai/`), run
at the top of each end-turn. It is **deliberately mechanical**: every decision
is a deterministic threshold or priority read from balance data (the `ai` section, plus
`movement.sea_move_cost` for sea routing), evaluated in sorted order, with no
randomness outside the shared battle resolution. Difficulty stays economic
(§4.3) — the AI never gets smarter, only richer.

| Module | Owns |
|---|---|
| `FactionAi` | Orchestration: capital housekeeping → diplomacy → politics → target choice → military → economy → policy; `begin_round` ages the war ledger and prices the world's strengths once per world turn |
| `AiAssess` | Pure queries: force power (via `BattleResolver.force_strength`, part of the resolver interface), threat levels (`interior/frontier/threatened`), traversal maps (land hops + sea crossings), expansion target scoring |
| `AiDiplomacy` | Deliberate war (full war chest, favorable odds, neutral neighbors only, capped simultaneous wars, a cooldown after a peace; neither the Roman houses nor the senate open on each other — the civil-war rules own that), white peace for stalled AI-to-AI wars, and a Roman house's envoy pressing the Senate's courtship charge on the power it names (§8.1) |
| `AiMilitary` | Laying sieges only with the strength to survive the eventual sally, assaulting at `assault_odds` (else starving them out), lifting hopeless sieges, relieving besieged settlements, field battles by odds, fighting open a road blocked by a hostile army, retreats, marching on the target (crossing by sea when that is the cheaper or only open road), merging co-located waves, raising armies from garrison surpluses with the best free general |
| `AiStrategy` | The shared force estimators — paper strength of a stack, settlement defense behind walls, whole-faction weight, priced once per world turn and handed to every house. (Its persistent-objective machinery is not driven on main; see the module docstring) |
| `AiPolicy` | The court's statecraft step: which craft the house takes up next, scored by persona group priority and need against adoption cost (§12) |
| `AiPolitics` | A Roman house's one political act: on the last turn of the Senate's demand for its patriarch's life, comply (§8.1). Every other charge is answered by what the modules above already do |
| `AiRules` | The persona table, and nothing else |
| `AiEconomy` | Capital relocation when lost, taxes as high as order safely bears (with hysteresis against flapping), retraining, debt-shedding (fleets first), garrison floors by threat — raised for rioting cities and for very rich factions — and priority-scored construction |

Behavioral notes:

- **Personas are content** (`data/ai.json`, wired by `factions.json →
  ai_persona` with a `default` fallback, read through `AiRules.persona_for`):
  aggression, expansion drive, peace willingness, occupation choice, build
  weights by kind-group, garrison floors, army size. Five ship — default,
  imperial, expansionist, mercantile, custodial (the senate). Every numeric
  knob outside the personas lives in `balance.json → ai` and `→ diplomacy`.
- **The AI is deliberately omniscient**: it reads true state, not
  `VisibilityRules`. Determinism is identical either way, fog-respecting
  targeting only makes factions wander with no player-visible benefit, and
  difficulty stays "richer, never smarter" — income and order bonuses plus a
  colder attitude toward the player, never information it could not have had.
  The decision is isolated behind `AiRules` and is revisitable.

- **Targets are recomputed, not remembered**: the nearest reachable enemy
  settlement (the least defended — garrison scaled by terrain and walls —
  breaks ties), preferring the senate mission target. Distance is measured
  from the faction's own territory, so a marching expedition never
  flip-flops its goal.
- **Wars end in three bands.** The staleness ledger (`state.ai.war_turns`)
  resets on physical prosecution — a siege between the pair, or an army on
  the other's ground. A quiet war nobody aims at any more ends after
  `peace_min_war_turns`; one still being mustered against holds out for
  `peace_stale_war_turns`; when either treasury is too empty to make the
  intent credible, `peace_exhausted_war_turns` suffices. A fresh peace is
  protected by a re-declaration cooldown (`peace_cooldown_turns`).
- **Wars against the player never end by themselves** — ending them is Phase
  5's negotiation table, and the player's own business.
- **Rebels are a garrison, not a power**: they defend, retrain and recruit at
  home, abandon sieges inherited from dead factions' defecting armies, and
  never expand, declare, or make peace.
- **AI captures always occupy** — enslavement and extermination stay player
  decisions.
- **Single-region islands sit outside the AI's war planning** (Sardinia,
  Britannia, Crete, Rhodes, Cyprus). The *player* can take one: an amphibious
  landing on a hostile shore is legal as long as no field army contests the
  beach (`MovementRules.sea_move_army`). The AI's traversal deliberately will
  not — `AiAssess.distance_map` refuses to expand sea edges out of a hostile
  region, because those edges advertised approaches its armies never finished
  and froze whole coastal campaigns. So the AI neither targets islands nor
  counts them reachable, and island factions expand only if war finds them.
  Teaching it the landing is Phase 6 follow-up work, not a missing rule.

## 10. The Guided Trail & Points of Interest

An onboarding-and-engagement layer added after Phase 6: a **guided campaign
trail** of data-driven stages, and **points of interest** the player explores
on the map. Both are pure content (`data/guided_campaign.json`,
`data/sites.json`): the trail is judged by one RNG-free rules module
(`src/core/rules/guided.gd`), while exploration resolves in
`Game.explore_site` through the campaign RNG.

### 10.1 The trail

- **Stages** carry a trigger, objectives, a completion rule (`all`/`any` —
  the flexibility knob), optional expiry and cooldowns, and a reward.
  Sixteen tutorial-arc stages chain by `after` triggers from setting a tax
  level through raising armies, exploration, first blood, and conquest;
  four **reactive stages** recur all campaign with cooldowns whenever war
  and misfortune reach the player — a war under way with anyone (stances
  are symmetric and record no declarer, so the stage answers wars the
  player starts too), a city besieged (target-bound: it pays only if
  *that* city is saved), intruders at the borders, a debt spiral.
- **Objectives** are deterministic: counter-based deeds (taxes set,
  buildings queued — optionally by kind, units recruited, armies raised and
  marched, mercenaries hired, sites searched, battles won, regions
  captured, senate missions) or live state reads (regions held, treasury,
  a governor in the capital, no siege on the recorded target, clear
  borders). Player-intent deeds count in the `Game` facade (the AI never
  calls it); field battles and captures count at `CombatRules` choke
  points and siege battles in `SiegeRules.assault`, so defensive victories,
  repelled walls, and starve-outs all count. One-shot tutorial stages
  credit deeds from the whole campaign (a battle won before its stage
  opened still counts); **repeatable stages demand fresh deeds**, measured
  from their opening snapshot. Start stages open at campaign creation, so
  turn-zero setup already counts.
- **Evaluation is two-phase** inside `GuidedRules.process_turn` (end-turn
  step 9): active stages are judged first, then new stages open — a
  reactive stage can never open and pay in the same turn. Expiry closes a
  stage without failing the trail (`after` accepts done-or-expired).
- **Rewards**: treasury gold; all-faction unit grants mustering in the
  capital (the senate-mission rule — silently lost with a lost capital);
  experience for the field armies; and **boons** — small permanent faction
  modifiers (`+recruit XP`, `+income %`, `+movement`) stored on the
  faction and read at three engine points. Repeatable stages may not grant
  boons (validator-enforced).
- The trail is chosen at campaign start (default on) and lives in
  `state.guided`; a pre-trail save simply has none and every read is
  defensive.

### 10.2 Points of interest

Twenty-two authored sites — caches, ruins, deserters' camps, shrines,
watchposts — each in its own region, spread so every playable faction can reach one
in its opening turns and the rest reward ranging out (several sit in
rebel lands, conquest-gated). A player army standing on a site searches it
(`Game.explore_site`): one weighted outcome per site, ever — gold, soldiers
who join the column (overflow musters at the capital), or experience —
drawn from the campaign RNG through the same state round-trip as battles.
Searching spends the season's movement. **Sites are player-only** by
design: they are the reward for exploring, and the AI deliberately marches
past them. Searching a site inside a neutral faction's region is allowed
and draws no diplomatic reaction — deliberate, so every faction can reach
finds beyond its own borders without a war. Unexplored sites show as gold diamonds on the map; the quest
panel lights objective targets up through the map's highlight ring.

The trail also introduced a player ability the engine previously reserved
for the AI: **raising a field army** from a garrison
(`Game.raise_army` — the whole garrison marches out under the best free
general present).

## 11. Data Architecture

### 11.1 Tables and schemas

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
| unit_classes.json | the unit-class counter matrix, per-class terrain / assault / wall / policing weights and fighting mass, attribute effects | battle estimator, public order |
| regions.json | region graph + sea zones, terrain, fertility, resources, hidden resources | map, economy, growth |
| map_geometry.json | generated coastlines, province polygons, road paths (`tools/generate_map_geometry.py`, seeded, byte-stable — regenerate, never hand-edit) | map rendering only |
| campaign.json | the 270 BC start: factions' treasuries, capitals, settlements, armies, fleets, characters, diplomacy; rebel holdings | NewGame |
| traits.json / ancillaries.json | trigger-driven character content | Phase 4 engine (loaded now) |
| events.json | scripted events + disasters | EventRules |
| wonders.json | wonders and their faction-wide effects | settlements, economy, construction |
| missions.json | the Senate's charges: mission templates with deadlines, rewards and penalties, the demand for a patriarch's life among them | SenateRules |
| offices.json | the six magistracies of the cursus honorum: rank, seats, minimum age, the prior rank required, attribute effects, the eponymous consulship, the pontificate held for life | SenateRules elections (§8.1), CharacterRules.effect_total |
| win_conditions.json | per-faction long/short goals | VictoryRules |
| names.json | per-culture name pools | Phase 4 character generation |
| mercenaries.json | regional hire pools | Active — `MercenaryRules` (field hiring, per-pool replenishment) |
| glossary.json | UI vocabulary: unit classes, attributes, effects, building kinds (id, name, blurb each) | info cards, map dossier (`Game.unit_profile` / `building_profile`) |
| advances.json | what a society works out, and can forget | Active — `AdvanceRules`, unlocked and lost from the Craft stock |
| society.json | axis names, unrest states, historical patterns, clarity levels | Active — the pedagogy surface: `pattern` on a crisis event resolves here |
| edicts.json | one standing provincial order — the player's fast lever | Active — `EdictRules`, folded into `SettlementRules.effect_total` |
| sites.json | 22 explorable points of interest with weighted outcomes | Active — `Game.explore_site`, quest UI, map markers (§10.2) |
| guided_campaign.json | the guided trail's 20 stages: triggers, objectives, rewards | Active — `GuidedRules` (§10.1) |
| effects_glossary.json | player-facing wording for the 13 effect keys, the blockers, and the standing captions | `BuildingInfo` → the building yard |
| building_art.json | 20 procedural recipes, 18 materials, 7 culture tracks: the drawn buildings | `BuildingArt` → `ArtPainter` |
| unit_art.json | 12 class templates, 7 culture kits, per-unit signatures, attribute cues | `UnitArt` → `ArtPainter` |

Structural rules the schemas enforce: lowercase `snake_case` ids; building *level*
ids globally unique; units reference building requirements by **kind + level**,
never by chain id (so every culture's barracks satisfies "barracks ≥ 2"); building
effects use a closed key vocabulary — the original thirteen (`law, happiness, growth,
health, trade_pct, farm_income, mine_income, recruit_xp, weapon_upgrade, armor_upgrade,
wall_level, road_level, port_level`), `drill` (the military layer's one addition:
summed, feeding garrison policing and softening the levy), plus the six societal keys that carry what a building
*costs* (`civic, coercion, burden, assimilation_pull, knowledge, martial`; `civic` is the
only one that may be negative, and it is what makes an amphitheatre a trade-off rather
than a free good); every level's effects are **standing totals at that
tier** — a level-3 market's `trade_pct` replaces level 2's rather than stacking
on it (`SettlementRules.effect_total` reads only the built tier per chain and
sums across chains), and tier effects (`wall_level`, `road_level`, `port_level`)
take the maximum across chains.

### 11.2 The validator

`tools/validate_data.py` runs every schema, then the cross-file checks JSON Schema
cannot express — including map-position sanity (no two region tokens closer than
1.2 world units; a warning when land-adjacent regions sit more than 35 apart),
map-geometry coherence (every region has territory containing its own position;
every land adjacency has exactly one road ending at its two positions), balance
terrain coverage (`movement.terrain_cost` and `battle.terrain_defense_multiplier`
keys pinned to the terrain enum — a missing key was a runtime crash) and
cannot express — including that **every effect key authored in the data has an engine
reader**, the check that would have caught `weapon_upgrade` and `armor_upgrade` sitting
dead in 34 building levels across two phases, and that each unrest ignition threshold sits
above its extinction threshold, because without that gap there is no hysteresis and a
crisis simply reverses when its cause does — including map-position sanity (no two region tokens closer than
1.2 world units; a warning when land-adjacent regions sit more than 35 apart) and
trigger liveness (any trait/ancillary trigger kind no engine call site fires is
reported as dead content; the forward allowlist emptied when the elections began
firing `office_gained`) and the same liveness discipline for **mission kinds**
(`blockade_port` alone stays forward-allowlisted, for the naval remainder), the
office ladder's shape (ranks unique and contiguous from 1, a first rung open to
any man of age, a required prior rank that exists below the office's own, exactly
one eponymous office, no office that buys nothing, an annals threshold that names
a rank on the ladder): id references
across tables; exactly
one rebel and one senate
faction; exactly one government chain per culture with tier count matching the
culture's cap; monotonic `min_settlement_level` within chains; temple chains carry
god + archetype; every unit's requirement satisfiable by some chain of its
culture; every faction able to recruit ≥ 3 unit types; a unit-class and an
attribute record for every value the units schema admits (and no others), with
matchup pair products inside the 0.85–1.15 authoring band; every building and
technique effect key in the schemas' closed vocabularies read by some rules
module (dead content fails the build, or is listed in `FORWARD_EFFECTS`
deliberately); a chain's `requires_building` satisfiable by every culture it
serves and never its own kind, and met at the campaign start wherever the chain
stands; warcraft techniques that do something (effects or a war block), closed
traditions naming real courts and endowed to nobody else, no starting technique
behind the post-marian era, a null-purchase warning for a technique whose only
effects name classes a court never fields; every **AI persona**
referenced by factions existing (with a required `default`) and every **agent
kind**'s building gate satisfiable per culture; land and sea adjacency
symmetric and the whole map connected; wonders and regions back-reference each
other; the campaign start settles every region exactly once, capitals owned,
government tier consistent with starting population, exactly one leader per house,
father/general/trait references resolving, and **household sanity** (no child
past coming of age, no impossible father ages, a warning for a house seeded
without women); long and short win conditions present
for every playable and unlockable faction. CI runs the validator and the headless
test suite (`tests/run_tests.gd` auto-discovers `tests/test_*.gd`; suites cover
growth, order, economy, construction, recruitment, movement/visibility, battle,
characters, diplomacy/war, the faction AI, the guided trail and exploration,
UI smoke, and a multi-turn campaign integration run) on every push.
diplomacy and offers, the campaign AI, agents, UI smoke, and multi-turn campaign
integration and AI-campaign harnesses) on every push. `tools/soak.gd` runs
longer manual balance soaks and prints the world that comes out.

### 11.3 Determinism & save model

- `GameData` (content) is loaded once and never mutated. `GameState` is a **plain
  Dictionary** — JSON-serializable and deep-comparable — whose full shape is
  documented at the top of `src/core/new_game.gd`.
- Saving is `JSON.stringify({version, state})`; loading is the reverse with a
  version gate (`src/core/save.gd`). Save compatibility is **additive**: a save
  from before a feature lacks its keys, `NewGame.ensure_state_keys(state, data)`
  fills them on load (the war record, war mood and levy strain among them), and
  the version stays 2. Data tables are content, not state, so only the state
  travels.
- All randomness flows through `CampaignRng`; its integer state is persisted in
  `state.rng_state` and threaded through every resolution step, so identical
  (seed, actions) sequences produce identical campaigns — the property the
  integration tests and future replay/debugging tools rely on.

## 12. Knowledge, Edicts & the Chronicle (the Deep Strategy layer)

The 2004-era genre template had no technology system — one hardcoded army
reform and a building tree. Instead of bolting on an abstract research
counter, this layer models how ancient innovation actually worked, which is
also the more interesting game. Every entry in its three content tables
carries a `historical_basis` field: original prose naming the real origin of
the thing — the "real history only" rule enforced at the data level.

### Techniques: knowledge moves by contact

A technique (`data/techniques.json`, 37 at ship) is a real craft of the age
— the boarding bridge, torsion artillery, Punic estate husbandry, census
registration, monsoon navigation. It exists somewhere in the world at 270 BC
(`start_adopted` per culture or faction) and moves along CONTACT, not a
beaker counter:

- **Aware ≠ adopted.** Awareness is free and travels — by origination
  (education buildings and practiced scholarship raise the odds), diffusion
  (one rng draw per contact pair per turn; alliance > trade > border > war
  as channels, same-culture quicker), conquest (the victor walks the fallen
  city's archives: awareness of everything its owner practiced, with a
  discount — the Senate kept nothing of Carthage but Mago's books), and
  espionage (a spy steals awareness plus a head-start discount, against the
  governor's counter-intelligence). ADOPTION is the investment: paid up
  front, seasons of institutionalization, one program at a time, priced by
  culture resistance.
- **Crisis drives military reform.** Defeats and lost cities accumulate
  `reform_pressure`, which discounts military-group adoption and quickens
  origination — Rome built the corvus because she was losing at sea. The one
  reform the old genre hardcoded is here a general law of the world.
- **Effects are faction-wide** through `KnowledgeRules.faction_effect_total`
  (the fourth effect accessor) and legible: growth and order carry a named
  `knowledge` factor; farm/mine/trade/corruption take percentages; armies
  march and fleets sail faster; siege works build quicker and ramparts
  defend a tier above the stones; units and building levels accept
  `requires_technique` gates beside the era gate. Weapon/armor upgrades
  stamp units AT RECRUIT TIME from city forges and armouries plus practiced
  techniques — the stamp travels with the unit for life, retraining is
  re-arming, merges keep the better arms, and the battle model prices it
  (§6.6). **Warcraft** techniques (§6.8) add a `war` block the battle
  estimator reads and prerequisites drawn from the war record.

### Edicts: policy, one province at a time

Edicts are the statecraft lever beside the building queue, and they are
**provincial** — one standing order per settlement, not a faction-wide book of
policies. §4.10 is the full account; what belongs here is why they sit in the
Deep Strategy layer at all.

`data/edicts.json` (9 at ship) shares the building chains' closed effect
vocabulary, so `SettlementRules.effect_total` folds an edict into public order,
growth, income, corruption, the load, the legitimacy target, provision and
therefore expectation, belonging, martial spirit and craft — without any of
those readers knowing edicts exist. Only five keys need their own reader,
because they are not additive settlement effects: `grievance_relief`,
`elite_pressure`, `income_pct`, `clarity_bonus` and `build_cost_pct`. Effects
flow through named `edict:<id>` factors, so every consequence is legible in the
breakdowns the player already reads.

The asymmetry is the design: taking hold is gradual (effects scale by
`turns_held / settle_turns`), letting go is instant, and whatever the edict
moved decays at its own stock's pace. That is what makes the Corn Dole a trap
rather than a toggle — the provision vanishes the turn you revoke it and the
expectation it created does not. A cooldown after revoking stops the player
flipping orders to farm the transient. Standing policies bill upkeep per
thousand mouths, so a dole gets dearer exactly as it gets harder to end.

One-time moods (a games, an event's aftermath) live in the stacking modifier
container `state.modifiers` — the generalization of the old single event slot —
which `ModifierRules` ticks down and `PublicOrderRules` sums.

### The chronicle: the campaign writes its own history

Everything notable lands in `state.chronicle` as a structured entry —
`schemas/chronicle_entry.schema.json` is the **narrator contract**: stable
resolvable ids, scalar details, no prose. Entries record at the same choke
points that serve player and AI alike; a collect pass derives what needs
before-and-after comparison: the running war ledger (opened by the first
battle if the fighting outruns the scribes, closed into war summaries
counted from the ledger), reigns tracked by leader id (kill-path deaths
emit no notices), faction destruction from the alive-set diff. Characters
accrue deeds — battles, sieges, cities, crafts, laws — and earn EPITHETS
from them (`data/epithets.json`, 12): one name per man, ever, the
Hellenistic convention, each citing its real pattern (Poliorketes, Soter,
Felix, Cunctator, Nikator, pater patriae…).

In-game, `data/annals.json` renders entries as prose (variant by entry id —
stable, no rng) in the Annals panel. The FUTURE optional online narrator
reads the same feed (`ChronicleRules.resolved()` — display names resolved
from the save alone, dead characters included) and may replace the prose;
it can never replace the entries. Structured data first; prose is flavor.

### Divergence is the point — and a number

Ten players should end in ten different worlds. The soak prints the claim
as a measurement: distinct adopted-set signatures among living courts
(18/18 at 100 turns, seed 42) and the cross-seed mean Jaccard distance of
adopted sets — `divergence: 0.xx`. Tuning raises the number; the harness
asserts adoption, signature divergence, enacted policy, and the narrator
contract on every entry, inside the bounded annals.

## 13. Roadmap

Phases 0–8 follow the research report (§17). Everything after Phase 8 was
requested during play and is listed by name, because three separate work
streams each called their own layer "Phase 9". Status as of this document:

| Phase | Scope | Status |
|---|---|---|
| 0 — Design & setup | Schemas for every data table, repo, CI, save format, this document | **Done** |
| 1 — Campaign map & turns | Region graph, sea zones, movement & forced march, fog of war, end-turn loop, seasons | **Done** |
| 2 — Settlements & economy | Growth/order factor lists, squalor, plague, buildings & queues, taxes, trade, corruption, treasury, riots/revolts, capture options | **Done** |
| 3 — Armies & battles | Recruitment, experience, retrain/merge, garrisons, sieges, mercenary hiring, sea transport (abstracted crossing, including amphibious landing on a hostile shore), **BattleResolver interface + AutoResolver**, debt disbandment | **Done at foundation depth**, plus the **military strategy layer** (§6.5–6.8, §3.3): unit-class counters and per-class terrain/walls in an RNG-free estimator with odds and named factors, kit from armouries and drill, the casualty/rout model, garrison quality, levy strain, war mood, and warcraft techniques learned from buildings, resources and the enemies faced. Remaining: embark-on-fleet transport, naval battles & port blockades, forts/watchtowers, ambush |
| 4 — Characters | Trait/ancillary trigger engine, family tree, succession, marriage/adoption, natural death, hero-of-the-field | **Done.** Trait points with anti-trait erosion, triggers (governing/campaigning/idle/battle/siege/occupation), retinue acquisition & transfer, effective attributes wired into order/income/growth/movement/battles; yearly aging, natural death, succession & set-heir, coming of age, births, seeded households, marriage suitors, adoption, man-of-the-hour. `office_gained` triggers fire from the summer elections (§8.1) |
| 5 — Agents & diplomacy | Envoys/spies/assassins, negotiation offers, AI attitude model | **Done.** Attitude factor model with decaying memory; offers priced in denarii (payments, tribute schedules, region cessions, stance changes) with live appraisal in the negotiation dialog; AI→player envoys with expiry; diplomats/spies/assassins on the map reading the two formerly-dormant effects (`personal_security`, `agent_skill`); senate courtship & assassination missions. Deferred: AI agent use, sabotage |
| 6 — AI opponents | Modular economy/expansion/diplomacy/war behaviors, difficulty tuning | **Done** (§9). Persona-driven (`data/ai.json`) modular AI: economy, objectives/muster, armies (raise/merge/attack/besiege/assault/defend, land & sea movement), war-and-peace initiative with war hunger and a war ledger; difficulty wired as income/order bonuses plus player-attitude bias. Verified by a 60-turn harness (map changes hands, byte-identical replay, save/resume lockstep) and 100-turn soaks. Deferred: AI use of agents, AI retinue management, fleet operations, invading a hostile island (§9) |
| 7 — Politics, events, victory | Full senate offices & mission variety, civil war depth, richer event scripting | **Done** (§8.1). Standings and charges (take a region, win an alliance, open a market, remove a rival king, the Senate's demand for the patriarch's life); the cursus honorum — six magistracies in `data/offices.json` (the pontificate held for life), summer elections by standing and influence with the ladder's prerequisites, no stepping down, and lean-year seats out of turn, office effects through `effect_total`, seats that absorb Ambition; compliance or outlawry; a civil war in which the other houses pick sides, that can never be talked away, and that ends when the Senate falls; the Senate scroll, five journal beats, a trail stage; wonders, victory checks. Deferred: canvassing, a player-declared civil war, joining a rebellion by choice, AI defiance, proscriptions, offices for other cultures |
| 8 — Polish | Campaign UI, balancing pass, tutorial, save robustness | **Campaign UI playable**: start menu (house/difficulty/seed/guided mode); a geographic terrain map generated from the region graph (`data/map_geometry.json` — coastlines, province polygons, meandering roads) rendered in retained layers with terrain fills and topography glyphs, culture- and wall-tier-styled settlement icons, army and fleet banners (owner badges when zoomed out), agent diamonds, fog veil, hover tooltips, reach/forced/strike rings and terrain-priced path previews with multi-turn march orders; camera by drag, wheel, trackpad, on-map buttons and keyboard; a two-row header that wraps to the 1280×800 design canvas; settlement panel with live factor breakdowns/taxes/queues/edicts; army orders by right-click and from the force card (march, sail/land, attack and assault confirmed with their paper odds, besiege, occupation choice, mercenaries, garrison, raise), unit rows with class, chevrons and kit, a battle report naming the deciding factors; agent orders (travel, scout, assassinate with live odds, bribe, steal); diplomacy, knowledge, annals and family scrolls; an Options menu (day playback, guided mode, controls); world-news turn log; save/load; unified dark theme, responsive window. Balancing pass and tutorial pending |
| Army command ("Phase 9") | Banners, the force card, regrouping, harbours and fleets on the map | **Done** (§6.1 harbours, §6.3 regrouping). Left-click selects a banner or province, right-click orders; `ForceRules` (raise under a chosen leader, transfer, merge, split, disband, attach/detach generals, consolidate) and `NavalRules` (launch, dock, merge, split) with movement conserved through transfers; attacks and sieges pay the season; besieged cities raise nothing; a keyboard cycle through forces awaiting orders. Ported by hand from `roman-war-gameplay-review-ou72vk` onto the trunk's renderer and facade. Remaining: the AI's attacks still pay no movement and it builds no ships |
| Society & consequence | Eight societal stocks, the coercion asymmetry, the euergetism ratchet, elite overproduction, plunder's share, belonging as diffusion, craft and advances, legibility, authored crises naming their historical pattern, and a real trade-off on all 81 building chains | **Done** (§4), including provincial edicts (§4.10) as the player's fast lever. Remaining: an AI that understands any of it, and an empire-wide policy slot alongside the provincial one |
| Visual & command layer | Building/unit art, right-click detail and garrison views, troop classes tied to their buildings, click-to-attack with animated battle playback | **Done.** Procedural illustrations, unit/building info cards, right-click map dossiers over rebound left/middle-drag panning, the building yard and muster hall, and an animated battle playback driven by AutoResolver's additive round log |
| The day at court | A watchable end turn: a deterministic turn journal, fog-filtered, played out over the map | **Done** (§2.3.2). Content-free beats in `state.journal`, prose in `data/dispatch.json`, dawn-to-dusk playback with speed and skip, a treasury ticker, the Senate's standing charge in the top bar, and the Daily Dispatch recap |
| Deep Strategy | Knowledge (techniques), edicts, the chronicle — §12 | **Done.** 37 techniques with real provenance spreading by contact/conquest/espionage; awareness→adoption lifecycle with culture resistance and crisis-driven reform pressure; effect keys wired (weapon/armor recruit stamping wakes 45 dormant building effects); AI adoption by persona priorities; the structured chronicle with war/reign ledgers, deeds, epithets, rendered annals; divergence measured in the soak (`divergence: 0.xx`). Deferred: the optional online narrator (contract shipped) |
| Guided trail & exploration | Stage-driven onboarding + reactive objectives, rewards & boons, 22 explorable sites, quest UI | **Done at foundation depth** (§10). Remaining: per-faction trail flavor, more site variety, site respawns/late-game chains |
| Future — Real-time battles | A battle scene implementing `BattleResolver` | By design, a drop-in |

## 14. Clean-Room Policy

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


## Campaign terrain and cartography revision — September 2026

`TerrainRules` adds physical land connectivity to the region graph without
changing political adjacency. Data-authored crossings distinguish bridges,
causeways, passes, unbridged rivers, unbroken ridges and open-water borders.
Movement, path previews, field attacks, siege entry, agents, land trade/grain
routes and AI traversal consult this seam. Bridge/pass defense is passed through
`CombatRules.battle_context` to the shared `BattleResolver` factor list; existing
terrain/class advantages remain in effect.

`CartographyRules` maintains additive `cartography` and directional `map_access`
state. Geographic reports persist. Visibility remains a separate live-observation
query. Accepted diplomacy terms grant map access; a war revokes future updates.
No query or rendering frame writes reports, movement, combat, or RNG state.
Older saves initialize geographic knowledge from their current observers.

`CampaignLandscape` is the normal rendered map. It uses the retained map geometry,
terrain profiles and route table, and consumes only filtered force presentation
caches. Detailed troops follow already-resolved march positions. The camera and
picking use the same terrain mesh; the classic view remains available for review.
The visual target is realism; current assets remain original procedural geometry.
