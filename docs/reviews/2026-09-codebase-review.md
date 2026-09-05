# Roman War — codebase review, September 2026

**Scope.** The whole repository at commit `9026730` (the state the owner
playtested): engine rules, determinism and save/load, armies and fleets,
gameplay strategy, historical realism, the campaign UI, data and balance,
performance and code quality, tests and documentation. The review was asked
for alongside the decision to make army command (clickable banners, moving
armies from the map, seeing what is in an army, merging forces) the next
phase; that phase's design and its first six increments are on this branch
(`docs/plans/phase-9-army-command.md`), so §2 records which findings it
already fixes.

**Method.** Nine reviewers, each with one lens, read the code and data and
ran headless probes against the engine (187 raw findings). A deduplication
pass merged the overlap between lenses into **124 unique issues**. Each unique
issue was then handed to an adversarial verifier told to refute it from the
code; **26 verdicts came back before the session's usage limit stopped the
run: 24 confirmed, 2 refuted.** The remaining **98 are reported but not
independently verified** (§4); where I had confirmed one myself with a probe
during the session it is marked *(confirmed by probe)*. Everything in §3 is
verified.

**Baseline.** Validator 0 errors / 0 warnings; 69 tests / 0 failures; clean
boot. On this branch: 100 tests / 0 failures, validator clean.

---

## 1. The short version

The engine is sound where it has been exercised and the architecture rules
hold (scene-free core, data-driven content, one battle seam, sorted
iteration where it matters). The defects cluster in four places:

1. **Armies were unmanageable.** Nothing could create, split, merge or
   disband a field army after turn 0; ships were recruited into the land
   garrison; fleets were invisible and controlled from a dialog; attacks and
   sieges cost no movement. *All of this is fixed on this branch* (§2).
2. **A handful of rules leak state across a turn or a save**: debt
   disbandment picked its victim by dictionary order, siege records went
   stale, governorship lagged a general's march, the save version was never
   bumped, mercenary pools drift through a JSON round trip, sieges outlive
   peace. Most are fixed here; the open ones are small (§3.1).
3. **The economy and public order do not bite.** Income snowballs, order
   sits at 150–220 % in core cities, extermination strictly dominates,
   plague is endemic and invisible, huge cities (and with them the Marian
   reform and the whole post-reform roster) are unreachable, six minor
   factions start insolvent. These are balance-pass items (§4.2–4.3).
4. **Realism gaps are mostly data**: the 270 BC political map, Ptolemaic
   Egypt modelled as pharaonic, a Roman corvus fleet a decade early,
   anachronistic units, seasons and attrition that do nothing, straits as
   land, march speed. Each is a data or small-rule change (§4.4).

Recommended order of work after this branch: finish Phase 9 (embark,
naval combat, blockade), then the open verified bugs (§3.1, all small), then
a balance pass driven by §4.2–4.3, then the realism data pass.

---

## 2. Verified findings already fixed on this branch

| Finding (verified) | Severity | Fixed in |
|---|---|---|
| No engine action could raise, split, merge, transfer or disband a field army; `garrison_army` was a one-way sink; `merge_units` had no caller | critical | `ForceRules` — raise, transfer, merge, split, disband, attach/detach, consolidate (inc. 4) |
| `attack_army` ignored movement (unlimited attacks per turn, free hop into the defender's region); `begin_siege` was a free hop and walked past relieving armies | high | movement required and spent by attacks; siege pays the step and refuses with a hostile army present (inc. 0) |
| Warships recruited into the land garrison, counted as wall soldiers, fought in assaults; no code path ever created a fleet | high | harbours, `launch_fleet`, `dock_fleet`, `normalise` on load (inc. 5) |
| Debt disbandment left zero-unit ghost armies that kept a general, blocked roads and could besiege | high | emptied armies are erased, sieges released (inc. 0) |
| Debt disbandment picked its victim by dictionary order (a loaded save disbands a different unit) | medium | sorted iteration (inc. 0) |
| Siege records went stale when the besieger marched away or died | medium | `SiegeRules.release` from every relocating or erasing path (inc. 0) |
| Governorship was stale for the rest of the turn after a general marched | medium | `Game._after_relocation` refreshes governors after every move (inc. 2) |
| `SAVE_VERSION` never bumped across state-shape changes | medium | version 2 with a version-1 upgrade path; newer saves refused (inc. 5) |
| The 20-unit stack cap was a literal in mercenary hiring only | medium | `balance.forces.max_units_per_force`, read by every path, validator-tied to the schema (inc. 0) |
| No canonical army constructor (`NewGame._add_army` vs `Fixtures.add_army`) | low | partly: `ForceRules._new_army` is the constructor for raised and split armies; `NewGame._add_army` still builds its own literal (see §3.4) |

Reported (unverified by the workflow) findings that this branch also closes,
each confirmed by my own probe or screenshot: general bodyguards cost 0 and
were recruitable everywhere (and were the AI stub's favourite unit); armies
drawn as unclickable owner squares with wrong hit-testing; fleets absent from
the map and sailed from the Diplomacy dialog; the army list buried under the
whole settlement panel; no reachability query and single-step moves; "with an
army selected every click is an order"; no force summary on the facade; a
test file with a parse error hung the whole suite; the Pharos
`naval_movement_pct` effect had no reader; fleets entirely untested; the
campaign screen laid out at minimum size in a corner of the window (my own
finding: `set_anchors_preset` without offsets).

---

## 3. Verified findings still open

### 3.1 Engine

| # | Finding | File | Effort | Fix |
|---|---|---|---|---|
| E1 | **The `Game` facade never checks ownership**: `set_tax_level`, `queue_building`, `queue_unit`, `move_army`, `attack_army`, `besiege`, `garrison_army` … accept any id, so a caller can command enemy armies and tax enemy cities. The UI only ever offers own forces (banners and buttons are filtered), so the player cannot reach it today, but every new UI path must re-implement the guard. | `src/core/game.gd` | S | Add `_own_army/_own_fleet/_own_settlement` helpers and return `false`/`{}` early in every player action, as `move_capital` and `transfer_ancillary` already do; keep the rules modules caller-agnostic for the Phase 6 AI; one facade test that each action refuses a foreign id. |
| E2 | **`AutoResolver` charges 25 % casualties for attacking an empty garrison** and awards victory experience for a fight that never happened; empty garrisons occur after every capture and revolt. | `src/core/rules/battle/auto_resolver.gd:34` | S | Short-circuit in `resolve` when either side is empty: the other side wins, no casualties, no experience, no general-death roll; document it in the contract. |
| E3 | **Faction destruction is half-handled**: defecting armies keep their family general (his bonuses and campaigning triggers keep firing for a dead house) and the *player's* defeat is never reported — they can keep ending turns. | `src/core/rules/combat.gd:230` | S | On faction death null the generals (or kill/retire the house); have `VictoryRules.check` return `"defeat"` when the player faction is dead and the screen show it. |
| E4 | **Village and town starve-outs resolve on the same end turn the siege equipment becomes ready**, so the player never gets a turn in which an assault (and the occupation choice) is possible. | `data/balance.json` siege, `siege.gd:41` | S | Raise the low starve thresholds (e.g. `[4,5,6,7,8,10]`) and add a validator check that each exceeds `equipment_turns`. |
| E5 | **Sieges continue and capture cities after peace is made.** | `src/core/rules/siege.gd:25` | S | Lift a siege in `advance_sieges` (and refuse `assault`) when the two factions are no longer at war; or lift in `set_stance`. |
| E6 | **Conquered cities carry a permanent culture penalty**: the old owner's government chain can never be demolished and always counts as foreign, contrary to DESIGN.md's "until the new owner outgrows it". | `construction.gd:78`, `settlements.gd:93` | S | Erase a foreign government chain once the owner's own chain reaches its tier, or exclude government/indestructible chains from the penalty ratio. |
| E7 | **Besieged settlements keep recruiting, retraining and completing units** into the garrison every turn (the AI stub does it automatically). | `turn_engine.gd:52`, `recruitment.gd` | S | Refuse `queue_unit`/`retrain` while besieged and pause queue progress. |
| E8 | **Legacy facade actions crash with a script error on unknown or stale ids** (`set_tax_level`, `move_army`, `besiege`, `attack_army`, `queue_building`, `queue_unit`, `move_fleet`) instead of refusing; the Phase 9 actions use `.get()` and refuse cleanly. | `game.gd`, several rules | S | Give the legacy entry points the same contract (`.get()`, return `false`/`{}`); one facade test with bogus ids. |
| E9 | **Mercenary pool counts are float accumulators**: ten replenishes of 0.1 reach 0.999… (unit re-hireable on turn 11, not 10) and a JSON round trip rounds the accumulator, so a loaded save offers the unit a turn earlier than the live game — a determinism violation. | `mercenaries.gd:58` | S | Store pool counts as integer hundredths (or `snappedf(x, 0.01)` on store and before the gate); add a replay-with-save test. |
| E10 | **Succession notices are dropped when a leader dies in battle** (`CharacterRules.kill` writes them into a throwaway array at every combat call site) and battle `character_notices` are never logged by the UI. | `characters.gd:160`, `campaign_screen.gd` | S | Thread the caller's notices array through the kill sites and log `result["character_notices"]` after battles and assaults. |
| E11 | **Unmarried adult daughters stay role `child` forever** (37 women aged 16–29 labelled Child by turn 60 in a probe). | `family.gd:26` | S | Promote daughters at coming of age and roll suitors for any adult unmarried woman. |

### 3.2 Gameplay (verified)

| # | Finding | Fix |
|---|---|---|
| G1 | **Island and overseas holdings pay the maximum distance-to-capital penalty and 28.5 % corruption from turn 1** because capital distance is a land-only BFS: Rhodes starts at order 71 (below the riot line) and riots every turn with no player action; Sicily and Sardinia hover at the threshold. | Walk sea links in `MapRules.hops_from` at a balance-driven cost (e.g. `distance_to_capital.sea_hop_cost`), or add strait adjacencies consistently; add a start-state test that no owned settlement begins below the riot threshold. |

### 3.3 UI and tests (verified)

| # | Finding | Fix |
|---|---|---|
| U1 | Loading a save from another house leaves the top bar showing the previous faction's name, colour and senate standings. | Rebuild the top bar in `refresh()` from the current `player_faction`; recentre on the loaded capital. |
| T1 | The save round-trip test compares canonical JSON, which collapses `1.9999999999999998` and `2.0`, so it cannot detect the divergence class it guards (the mercenary-pool drift above is masked on the very turn it runs); it also plays one action-free turn. | An exact recursive diff helper, a scripted action list on both sides, and the mercenary fix. `Fixtures.round_trip_equal` (added on this branch) does the scripted half for the Phase 9 actions. |

### 3.4 Code quality (verified)

| # | Finding | Fix |
|---|---|---|
| Q1 | The army record is still built in two literals (`NewGame._add_army`, `Fixtures.add_army`) beside `ForceRules._new_army`. | Route both through `ForceRules._new_army` (make it public) and update the state-shape comment. |

### 3.5 Refuted

- *"`sea_move_army` is a teleport"* — true as stated but it is the documented,
  deliberately deferred abstract crossing; fleet transport (Phase 9 inc. 6)
  is its replacement and the crossing stays switchable by data.
- *"The player can ally or trade with the rebels"* — the engine allows it, but
  the only caller (the Diplomacy panel) never offers rebels or dead factions;
  worth a one-line guard in `DiplomacyRules.set_stance`, not a bug today.

---

## 4. Reported, not yet verified

98 unique issues did not reach a verifier. They are grouped here by theme
with the reporting lens count in brackets; treat each as a lead to confirm
before acting. Items marked *(confirmed by probe)* were reproduced during the
session.

### 4.1 Engine and determinism

- **Field armies cannot be retrained** — `retrain_garrison` covers the
  garrison and, now, the harbour, but an army standing in its own city has to
  be garrisoned to heal; consolidation of depleted units is now reachable. Add
  `Game.retrain_army` reusing the garrison loop. [2]
- **Relief victory leaves the siege standing** when the beaten besieger
  survives in place. Lift the siege when the recorded besieger loses a battle
  in that region. [1]
- **Debt strips only field armies**; garrisons and fleets are immune, there is
  no interest or unrest, and (before this branch) the player could disband
  nothing. Extend forced disbandment to fleets then garrisons; consider a debt
  order factor. [2]
- **An army general in his own city is at once governor, commander and the
  garrison's defending general**; `turn_end_governing` fires instead of
  `turn_end_campaigning`. Decide the model (army inside the city, or generals
  excluded from governor claims). [1]
- **Forced-march fatigue never applies to a fatigued army that is attacked**
  (no `defender_fatigued` in the resolver context). [1]
- **A failed assault wipes the siege including the starvation clock**; a
  repulsed escalade fully resupplies the city. Keep the record with a
  cooldown. [1]
- **Condition-triggered events pick the first match over an unsorted
  dictionary** (`events.gd:44,64`), so the reported faction can differ after a
  load; trade income and grain routes sum in dictionary order (float order).
  Sort. [2]
- `siege_won` notices from starve-outs are dropped by the turn engine. [1]
- `CharacterRules.kill` has an inverted signature and optional succession. [1]
- `MapRules._hops_cache` is process-global and hands out cached dicts by
  reference; move it onto `GameData`. [1]
- The load path conflates "no save", "corrupt" and "wrong version";
  `new_campaign` accepts unknown faction ids. [1]
- Dead characters are never pruned (171 of 459 dead by turn 160). [1]
- The passive rebel faction runs a unified 33-city economy and the AI stub,
  banking millions and fully developing every independent city *(confirmed by
  probe: rebels net +19,386 denarii per turn at turn 0)*. Skip the stub and the
  treasury for `is_rebel` factions. [3]
- The AI stub keeps rebel garrisons at two cheap units while walls climb, so
  every assault is a near-certain win. [1]

### 4.2 Economy, order and balance

- **The economy has no tension**: income snowballs to 4–6× upkeep, treasury
  reaches 500k by turn 60; land trade routes are uncapped while sea routes are
  capped by port level. Cap land routes by market level, lower the route base,
  consider scaling costs. [1]
- **Public order never bites at home**: base 100 + governor + a garrison bonus
  that caps at +80 leaves core cities at 150–220 % *(confirmed by probe:
  Latium 182 %, Campania 154 %)* and very-high tax is a free lunch. Lower the
  base and the garrison scale, sharpen tax penalties. The panel also prints
  the unclamped total. [2]
- **Exterminate strictly dominates occupy** (7.5× the loot, +26 better order,
  a growth boom). Rebalance loot and penalties; add a lasting growth malus. [1]
- **Huge City is unreachable** under the plague/squalor model, so the Marian
  reform and the whole post-reform Roman roster are dead content. Add a
  date-based trigger path and raise plague capacity. [3]
- **Plague is endemic from turn 1** (52 of 70 starting settlements exceed
  health capacity; no starting settlement has a health building) and it is
  invisible to the player. Scale capacity with tier, seed health buildings,
  report outbreaks. [2]
- **Six factions start in structural deficit** and are bankrupt within 20–50
  turns *(confirmed by probe, turn-0 net at medium difficulty: Armenia −165,
  Britannia −449, Dacia −109, Germania −220, Scythia −407, Thracia −221)*.
  Rebalance `campaign.json`; add a turn-0 sanity test. [1]
- **Distance-to-capital makes far conquests auto-revolt while moving the
  capital is free and instant.** Charge the move; soften the per-hop rate. [1]
- **The auto-resolver is soldiers × stats only**: elephants, chariots,
  artillery and bodyguards are near-worthless, 200-man warbands ten times
  more cost-effective than elites; `attributes`, `speed` and `class` are never
  read. Add class multipliers and attribute modifiers in `balance.battle`. [1]
- **The Senate is toothless**: standing has no reader, a dead Senate keeps
  issuing missions, attacking Rome is free; **five of nine mission kinds are
  never issued**; **senate missions are unplayable** because the target and
  deadline are never shown. [3]
- `weapon_upgrade`/`armor_upgrade` building effects are never read; several
  military building tiers unlock nothing for the factions that can build them;
  `growth.farm_level_pct` is dead; every unit trains in exactly one turn. [4]
- Tunables hardcoded outside `balance.json`: the 400 population floor (three
  sites), the resolver's 0.35 ratio floor and 10 % destruction threshold,
  mercenary hire experience, AI reserves. [3]

### 4.3 UI

- Battle and assault outcomes are not reported (casualties, generals lost,
  loot, character notices); the turn log leaks fog (revolts and sieges in
  unseen regions), never says who won a siege, persists across loads and
  grows unbounded. [2]
- The UI discards every facade result: unaffordable builds and recruits,
  failed retrains and stance changes fail silently (the Phase 9 actions now
  explain refusals; the legacy buttons still do not). [2]
- Every dialog is exclusive/modal; the victory banner is re-created after a
  load. [1]
- No trackpad pan/magnify gestures, no camera bounds, no recenter button;
  settlement labels are a fixed 12 px and collide at the zoom-out cutoff. [2]
- The short campaign cannot be chosen (the start menu never passes
  `campaign_mode`) although PLAYING.md advertises it. [3]
- Character consequences are invisible in the family panel (no location, no
  post, no trait effect values). [1]
- END TURN has no unspent-movement warning and keeps resolving after the
  campaign is decided. [1]
- `RegionPanel` is rebuilt twice per order (now once via `refresh()`, but the
  whole panel still rebuilds on every action); the end turn costs ~100 ms with
  growth/order breakdowns recomputed 100–170× per turn; `CharacterRules.
  process_turn` re-sorts settlement keys per character. [3]

### 4.4 Historical realism (data)

- **March speed is ~6× too slow for a half-year turn** (Rome to Antioch takes
  three game years); define what a hop represents or raise the budget. [1]
- **Seasons are cosmetic** (no winter effect on movement, sailing, harvest or
  sieges; "winter storms" strike in summer); **no attrition or supply**. [2]
- **Siege timings** on a half-year calendar (rams take a year, a huge city
  four years; an ungarrisoned city cannot be walked into); **a besieged city
  keeps full taxes and trade**. [2]
- **Recruitment is one unit per turn regardless of city size.** [1]
- **The 270 BC political map**: the Seleucid and Ptolemaic empires
  understated, Parthia independent 23 years early, **Syracuse a Roman city
  with a corvus fleet a decade before Rome built a navy**, every faction at
  peace, Roman Italy without the Via Appia, Scythia seated at Greek Olbia,
  Thracia building Greek temples. [6]
- **Ptolemaic Egypt modelled as a New Kingdom pharaonic state** (chariots,
  "Pharaoh", Egyptian dynastic names). [1]
- Unit anachronisms (Numidian camel scouts, Germanic "berserkers", Pontic
  scythed chariots and bronze-shield phalanx in 270 BC, Punic heptereme);
  mercenary pools that hire hoplites in Britain and lack Iberians, Thracians
  and Galatians; three sea straits modelled as land adjacency; flat slave
  economics; name generation mixing every tribal culture in one pool and
  Roman sons not inheriting their gens; dated-event nits (Epicurus, Archimedes
  in a city that is Roman from turn 1). [6]

### 4.5 Tests, tooling and docs

- The runner reports `ok` for a test that hits a runtime error after its first
  assertion; CI inspects only the exit code and `--import || true` swallows
  import failures. Capture output and fail on `SCRIPT ERROR`. [2]
- The validator does not enforce id uniqueness despite the docs saying so;
  balance sections are free-form so a renamed key surfaces only at runtime;
  no liveness check for building effects, unit attributes, wonder effects or
  mission kinds; the trigger-liveness check detects call sites by substring. [3]
- No tests for the successful assault/capture path, battle-context modifiers
  (terrain, fatigue, sally, generals), the senate, events, disasters, victory,
  the AI stub, wonders, plague, faction destruction; several tests are guarded
  so their key assertion can be skipped. [4]
- Docs: the GameState shape comment (`new_game.gd`) and DESIGN §9.3 are stale
  in places (rng_state typed as int, `traits` vs `trait_points`); DESIGN's
  natural-death and turn-order sentences; HANDOFF's JSON-ordering claim should
  say *why* (saves are written with sorted keys). [3]

---

## 5. Recommendations, in order

1. **Finish Phase 9** (embark/disembark, naval combat through the resolver
   seam, explicit blockades, docs closure) — the spec is in
   `docs/plans/phase-9-army-command.md` §5–7.
2. **Close the open verified bugs** (§3.1, all effort S): facade ownership
   and id guards (E1, E8), the empty-garrison resolver case (E2), faction
   death and player defeat (E3), starve-out overlap and sieges after peace
   (E4, E5), the permanent culture penalty (E6), besieged recruiting (E7),
   the mercenary float drift with a real replay test (E9, T1), succession
   notices (E10), daughters (E11), the top bar after load (U1), the island
   capital distance (G1).
3. **Balance pass** from §4.2: economy tension, public order, occupy vs
   exterminate, plague and the reachability of huge cities, the six insolvent
   starts, the resolver's class multipliers, the Senate. Verify each lead with
   a 60-turn headless probe before and after.
4. **Realism data pass** from §4.4: the 270 BC map and Egypt first (largest
   payoff, pure data), then march speed and seasons, then units and
   mercenaries.
5. **Tooling**: CI failing on script errors, validator id uniqueness and
   liveness checks, the missing module tests.
