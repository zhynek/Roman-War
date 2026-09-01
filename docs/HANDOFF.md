# Handoff — picking up Roman War in a fresh session

Everything an assistant (or a human) needs to be productive here within five
minutes. It deliberately does **not** repeat the other docs:

| For | Read |
|---|---|
| Architecture rules, conventions, clean-room policy | [`CLAUDE.md`](../CLAUDE.md) (auto-loaded by Claude Code) |
| What every system does and the phase-by-phase status table | [`docs/DESIGN.md`](DESIGN.md) — §11 is authoritative |
| What every system does and the phase-by-phase status table | [`docs/DESIGN.md`](DESIGN.md) — §12 is authoritative |
| Architecture rules you must not violate, conventions, clean-room policy | [`CLAUDE.md`](../CLAUDE.md) (auto-loaded by Claude Code — read it first) |
| What every system does, and the phase-by-phase status table | [`docs/DESIGN.md`](DESIGN.md) — §10 is authoritative, §12 is the newest layer |
| What the game is like to play | [`PLAYING.md`](../PLAYING.md) |
| How to produce a downloadable app | [`BUILDING.md`](../BUILDING.md) |
| Why the design is what it is | [`docs/research/rtw-research-report.md`](research/rtw-research-report.md) |

## 0. Start here — the state of play

The **Deep Strategy layer** (DESIGN.md §12 — knowledge, edicts, the chronicle)
shipped as 17 commits, went through a three-lens adversarial review whose 24
findings were all fixed, and a macOS build was delivered to the owner.

**The owner is playtesting that build now and will report back.** The most
likely first task in a new thread is triaging those notes — read §4 before
asking them anything, because the obvious question ("what seed?") is one the
game currently cannot answer.

**One thing changed after that build was cut:** the campaign screen used
`set_anchors_preset`, which preserves a control's existing rect — so the whole
UI rendered at its minimum size in the top-left corner and grew only by the
*delta* of a window resize, leaving a large grey margin (Godot's default clear
colour). Fixed on this branch, proven in-engine, and pinned by
`test_campaign_screen_fills_its_window`. **The delivered build predates the fix
— rebuild before the next delivery.**

## 1. Where things stand

An original clean-room turn-based grand-strategy game of the 270 BC
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 18
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 19
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 21
JSON tables under `data/` validated by `schemas/`, with a thin deterministic
rules engine in `src/core/`. Battles resolve behind a swappable
`BattleResolver` interface.

**Built:** Phases 0–4 (map & turns, settlements & economy, armies & sieges at
foundation depth, the full character/family layer), the Phase 7 senate
foundation loop, and a playable Phase 8 campaign UI with a modernized map:
generated terrain geometry (`data/map_geometry.json` + `tools/
generate_map_geometry.py`), a retained-layer renderer with settlement/army
iconography, terrain-priced pathfinding with multi-turn march orders
(`src/core/rules/pathfinding.gd`), hover tooltips, range overlay and path
previews, fleets on the map, and a unified dark theme.

The map modernization landed in 10 commits, each gated, ending with a
three-reviewer adversarial pass whose 15 findings are all fixed (§7).

**Green:** 112 tests / 0 failures, validator 0 errors /
0 warnings, clean boot. Branch `claude/modernize-map-world-view-03orjy`,
pushed. An **Apple Silicon build of this branch was delivered** to the user,
who is playtesting it; the requested follow-up work is §5. Rebuild per §3
before the next playtest (arm64-only — an Intel Mac needs the x86_64 slice
instead).

**Visual QA:** `xvfb-run -a godot --path . --script res://tools/screenshot.gd
-- out_dir=/tmp/shots zooms=0.5,1.1,2.2 select_army` boots a campaign under a
real renderer and saves map screenshots — use it after any map change; CI
never renders. Regenerate geometry with `python3
tools/generate_map_geometry.py` (fixed seed, byte-stable — a re-run must
leave `git diff` empty).
foundation loop, a playable Phase 8 campaign UI, and **Phase 9 — the societal
layer**, which is now the core of the game: eight slow stocks with memory, a
real trade-off on all 81 building chains, provincial edicts as the player's fast
lever, and crises that name the historical mechanism they illustrate. Read
`docs/DESIGN.md` §4 before touching any of it.

**Green as of commit `b88a1e3`:** 123 tests / 0 failures, validator 0 errors /
0 warnings, clean boot. Branch `claude/game-decision-tradeoffs-pnixzs`, working
tree clean, everything pushed. A Mac build of an earlier state was delivered to
the user, who is playtesting.
foundation loop, a playable Phase 8 campaign UI, and **the day at court** — the
turn journal, the fog-filtered end-turn sequence and the Daily Dispatch, with a
bounded AI so the day has something to show (`docs/DESIGN.md` §2.3.1–2.3.2).

**Green:** 93 tests / 0 failures, validator 0 errors / 0 warnings, clean boot.
Branch `claude/daily-campaign-turn-sequence-8mq71d`.
foundation depth, the full character/family layer), Phase 6 AI opponents
(modular `FactionAi` — deliberate wars, white peace, sieges, defence, sea
invasions, mustering, threat-based garrisons, priority construction; DESIGN.md
§9), the Phase 7 senate foundation loop, a playable Phase 8 campaign UI, and
the **guided campaign trail + points of interest** (DESIGN.md §10): 20
data-driven stages (16 tutorial-arc + 4 reactive with cooldowns), rewards
including permanent faction boons, 22 explorable sites, a quest panel, map
markers/highlights, and the player's raise-army action. Newest: the **building
yard** (DESIGN.md §10.3) — a drawer over the map that says what a building is,
what it does, what it leads to and why it is locked, with every building and
unit **drawn at runtime** from recipe data rather than image files.

**Green as of this branch:** 148 tests / 0 failures, validator 0 errors /
0 warnings, clean boot. Branch `claude/building-details-upgrades-kiq3tt`
(fast-forwarded from `claude/ai-opponents-5y68t6`). A Mac build from the pre-AI
foundation was delivered to the user, who is playtesting.
Mediterranean, in Godot 4.4 / GDScript. 22 JSON tables under `data/` validated
by `schemas/`, a thin deterministic rules engine in `src/core/` (~9.5k lines
across 48 scripts), battles behind a swappable `BattleResolver`.

**Built:** Phases 0–6 — map & turns, settlements & economy, armies & sieges
(including amphibious landings on at-war shores), the character/family layer
with seeded households, the Phase 5 agents & diplomacy layer, the Phase 6
campaign AI (persona-driven, with real truces), the Phase 7 senate foundation
with four live mission kinds, the Phase 8 campaign UI — and the **Phase 9 Deep
Strategy layer**: 37 techniques spreading by contact/conquest/espionage with an
awareness→adoption lifecycle, culture resistance and crisis reform pressure;
recruit-time weapon/armor stamping (waking 45 dormant building effects); 16
edicts with exclusivity tensions, repeal shocks, an insolvency collapse and a
stacking modifier container; AI adoption and policy by persona priority; the
structured chronicle with war/reign ledgers, character deeds, 12 epithets and
prose annals; and a wider event vocabulary (cooldowns, faction moods, scripted
technique grants, obituaries for the great powers).

**Green at the head of this branch:** **179 tests / 0 failures**, validator 0
errors / 0 warnings, clean boot. A 100-turn soak shows 139–186 adoptions with
nearly every living court holding a distinct knowledge signature, ~50 edicts
held across all seven categories, ~600-entry chronicles, and `divergence: 0.29`
across seeds.

**Performance has thin headroom.** The 60-turn harness asserts
`average < 250 ms` (`tests/test_ai_campaign.gd`) and prints the number *only
when it fails* — so a passing run tells you nothing. Measured on this container:
**240–250 ms** over 60 turns, **250–265 ms** in the 100-turn soak. Anything you
add to a per-settlement breakdown path will blow the ceiling; probe before and
after (§5.10).

## 2. Get productive in five minutes

Godot may already be at `/tmp/Godot_v4.4.1-stable_linux.x86_64`. If not:

```sh
cd /tmp && curl -sSL -o godot.zip \
  https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
unzip -q godot.zip && chmod +x Godot_v4.4.1-stable_linux.x86_64
alias godot=/tmp/Godot_v4.4.1-stable_linux.x86_64   # the commands below assume this
ln -sf /tmp/Godot_v4.4.1-stable_linux.x86_64 /usr/local/bin/godot   # nothing below works without this
```

> **Run `--import` first — and again after adding any `class_name` file.**
> A stale `.godot/` cache invents `Identifier "X" not declared` and
> "Nonexistent function" errors on globals that plainly exist, makes test files
> fail to load *while the runner still prints passes for them*, and can look
> like a hang. When in doubt: `rm -rf .godot && godot --headless --path . --import`,
> then read the **first** errors in the output, not the last.

The two gates that must stay green — the same two CI runs on every push and PR
(`.github/workflows/ci.yml`):

```sh
python3 tools/validate_data.py                                   # 0 errors, 0 warnings
godot --headless --path . --script res://tests/run_tests.gd      # 112 tests, 0 failures (~20s)
godot --headless --path . --script res://tests/run_tests.gd      # 93 tests, 0 failures (~40s)
godot --headless --path . --script res://tests/run_tests.gd      # 100 tests, 0 failures (~35s)
godot --headless --path . --quit-after 5                         # clean boot, no output = good
python3 tools/validate_data.py                                # 0 errors, 0 warnings
godot --headless --path . --script res://tests/run_tests.gd   # 179 tests, 0 failures (~2 min)
godot --headless --path . --quit-after 5                      # boots clean: no errors after the version banner
```

`pip install jsonschema` if the validator can't import. **There is no
single-file test filter** — `tests/run_tests.gd` globs `res://tests/test_*.gd`
unconditionally and parses no arguments. It's the whole suite or a throwaway
script.

For balance work: `godot --headless --path . --script res://tools/soak.gd`
runs **two** 100-turn campaigns (~2 min) and prints what kind of world comes
out — wars, conquests, survivors, debt, adoptions and crisis adoptions,
distinct knowledge signatures, edicts by category, a chronicle histogram, ms
per turn, and the cross-seed `divergence:` figure. Seeds and length are
`const SEEDS` / `const TURNS` at the top of the file; change them there.

## 3. Map of the codebase

**Engine** (`src/core/`, scene-free and deterministic). `game.gd` is the
facade every UI and test calls; `turn_engine.gd` fixes the end-turn order;
`new_game.gd` builds and normalizes state; rules live in `src/core/rules/`
(`knowledge`, `edicts`, `modifiers`, `chronicle`, `diplomacy`, `agents`,
`combat`, `siege`, `economy`, `growth`, `public_order`, `construction`,
`recruitment`, `movement`, `characters`, `family`, `senate`, `events`,
`victory`, `mercenaries`, `settlements`, `map`, `visibility`), with the AI in
`rules/ai/` (`ai_rules` orchestrates → `ai_diplomacy`, `ai_strategy`,
`ai_military`, `ai_economy`, `ai_policy`) and battle behind
`rules/battle/battle_resolver.gd`.

**UI** (`src/ui/`) — every panel talks only to the facade:

| Panel | Facade methods |
|---|---|
| `campaign_screen.gd` (the shell) | `end_turn`, `move_army`, `sea_move_army`, `attack_army`, `besiege`, `move_agent`, `agent_scout/_assassinate/_bribe/_steal_technique`, `visible_regions`, `victory_progress`, `save_to`, `load_from` |
| `panels/region_panel.gd` (the biggest) | `growth/order/income_breakdown`, `available_buildings/units`, `queue_building/unit`, `demolish_building`, `set_tax_level`, `retrain_garrison`, `garrison_army`, `raise_army`, `move_capital`, `assault_settlement`, `hire_mercenary`, `mercenaries_available`, `recruit_agent`, `agents_in` |
| `panels/diplomacy_panel.gd` | `pending_offers`, `respond_offer`, `declare_war`, `move_fleet` — **fleets live here, not on the map** |
| `panels/negotiation_dialog.gd` | `preview_offer`, `propose_offer` |
| `panels/family_panel.gd` | `family_of`, `character_sheet`, `set_heir`, `transfer_ancillary` |
| `panels/knowledge_panel.gd` | `technique_overview`, `begin_adoption` |
| `panels/edicts_panel.gd` | `edict_overview`, `enact_edict`, `repeal_edict` |
| `panels/annals_panel.gd` | none — renders `state.chronicle` through `data/annals.json` |

**Tests** (`tests/`, 19 files over `tests/fixtures.gd`, a synthetic world that
loads the real `balance.json`). Formula units: `growth`, `economy`,
`public_order`, `construction`, `recruitment`, `battle`,
`movement_visibility`, `characters`. Systems: `agents`, `diplomacy_offers`,
`diplomacy_war`, `ai`, `knowledge`, `edicts`, `chronicle`,
`events_vocabulary`. Integration: **`test_ai_campaign.gd` is the tripwire** —
60 AI-driven turns asserting the map changes hands, byte-identical replay from
one seed, and save-at-20/resume-in-lockstep. `test_ui_smoke.gd` drives the real
screen headless.

## 4. Turning a playtest report into work

**Do not ask "what seed?" first.** The seed is entered on the start menu and
used to seed the RNG, but **it is never written into the game state** — it is
in no save file, and the UI never shows it again. A player who didn't write it
down cannot tell you. *(Worth fixing: store `seed` in `NewGame.build`'s state
dict, back-fill it in `ensure_state_keys`, and show it in the top bar. Small,
additive, and it makes every future report reproducible.)*

**Ask for the save file instead** — it pins the world exactly (`rng_state`
plus all state). One fixed slot, `user://roman_war_save.json`:

- macOS: `~/Library/Application Support/Godot/app_userdata/Roman War/roman_war_save.json`
- Linux: `~/.local/share/godot/app_userdata/Roman War/roman_war_save.json`

Then reproduce headlessly — load it the way the facade does
(`SaveGame.read_file` → `NewGame.ensure_state_keys(state, data)` → assign to a
`Game`) and step turns in a throwaway script, printing whatever the report is
about. If they *did* keep the seed, `Game.new_campaign("julii", SEED)` replays
their campaign exactly.

Balance complaints want a soak before and after, not just the suite (§9).

## 5. Determinism and GDScript traps (all bitten in practice)

`CLAUDE.md` states the standing architecture rules — the four effect
accessors and their hot-path discipline, the additive save-compat rule, the
chronicle choke-point rule, and the `--import` trap. Those are not repeated
here. What follows is the rest:

1. **Sort keys in any loop that can steer an rng draw or a first-match
   decision.** A JSON round trip reorders dictionaries, so an unsorted
   iteration makes a loaded save diverge from a live game. Pure sums are exempt
   and say so in comments. `test_save_resume_equivalence_with_ai` is the
   tripwire.
2. **`state.rng_state` is a decimal *string*.** JSON numbers are float64 and
   silently round a 64-bit RNG state.
3. **Inside `TurnEngine.end_turn`, never call the `Game` facade.** `Game._rng()`
   rebuilds from `state["rng_state"]`, stale until end_turn writes it back — a
   second stream breaks save determinism. AI code calls rules modules directly
   with the threaded rng.
4. **Player actions must not steer the campaign stream** unless they say so:
   facade methods that consume rng (attack, assault, assassinate, steal) rebuild
   it from state and write it back; everything else picks deterministically.
5. **GDScript `:=` cannot infer through Variant.** `var n := dict["x"].size()`,
   or `:=` from an untyped loop variable, is a PARSE error that takes the whole
   class down — and then every caller reports "Nonexistent function" instead of
   the real error. Type such vars explicitly.
6. **Every settlement capture goes through `CombatRules.capture_settlement` AND
   `fire_occupation_triggers`.** Peaceful cessions (`DiplomacyRules.cede_region`)
   are the deliberate exception: no loot, no triggers, garrison marches home.
7. **A new per-entity state key must be emitted at EVERY creation site**, not
   just `build` + `ensure_state_keys` + fixtures: births (`family.gd`),
   mercenaries, senate unit grants. Missing one lets a resumed save diverge
   from a live game — which is exactly how `deeds`/`epithet`/`weapons`/`armor`
   broke the lockstep test once each.
8. **`GrowthRules._plague_turn(data, state, settlement, rng)` takes `state`**
   (plague resistance is faction-wide). A merge that drops the param compiles
   nowhere near the bug it causes.
9. **The senate must DRIFT `popular_standing`, never assign it.**
   `senate.gd` moves it toward a regional baseline by `popular_drift_factor`;
   an overwrite silently turns *every* edict's political tension into dead
   code. This shipped as a bug once and the tests did not catch it —
   `test_popular_standing_survives_the_senate_drift` does now.
10. **Perf probe before and after any breakdown-path change.** Time 60
    `end_turn`s in a throwaway script; the ceiling is 250 ms and you have
    roughly 5% of margin (§1).
11. **UI Controls: `set_anchors_and_offsets_preset`, never
    `set_anchors_preset`.** The latter keeps the control's current rect (0×0 for
    a freshly built one) — see §0.

## 6. Building and delivering a playable app

`BUILDING.md` has the recipe. Presets write to `../build/` — i.e.
**`/home/user/build/`**: `RomanWar-macOS.zip` (universal, ~56 MiB),
`RomanWar-macOS-arm64.zip` (**the thinned one that fits the delivery cap**,
~27 MiB), and `RomanWar-Linux/`. What costs time to rediscover:

- **Export templates** are a separate ~1.2 GB download
  (`Godot_v4.4.1-stable_export_templates.tpz`), unzipped into
  `~/.local/share/godot/export_templates/4.4.1.stable/`.
- **`import_etc2_astc=true`** must stay in `project.godot` or the macOS export
  dies with a configuration error.
- **macOS architecture must stay `universal`.** The stock template ships only a
  universal binary; an `arm64` export fails with "template binary not found"
  because thinning needs Apple's `lipo`, absent on Linux.
- **Ad-hoc signing is mandatory for Apple Silicon** (`codesign/codesign=1`) —
  arm64 macOS refuses to launch a fully unsigned binary outright.
- **Delivery caps at 30 MiB**, so extract the arm64 slice from the Mach-O fat
  binary in Python (fat magic `0xCAFEBABE`, `cputype 0x0100000c`), overwrite the
  executable, re-zip preserving the original entry modes. **Verify
  `LC_CODE_SIGNATURE` (cmd `0x1d`) survives in the thinned slice**, or the app
  will not launch.
- **Verify the package plays** before sending: the Linux export shares the same
  `.pck`, so run it headless with a probe script that starts a campaign and
  ends a few turns.

## 7. Ways forward

Each is self-contained. The owner has not committed to one.

1. **Sort keys in any loop that can steer an RNG draw.** A JSON round-trip
   reorders dictionaries, so an unsorted iteration makes a loaded save diverge
   from the live game. This shipped as a real bug once and the save round-trip
   test caught it only after the RNG fix below.
2. **`state.rng_state` is a decimal *string*, not an int.** JSON numbers are
   float64 and silently round a 64-bit RNG state to a multiple of ~1024,
   producing a different random stream after loading.
3. **Quantize any continuous float you put in the state.** Godot's `JSON.stringify` does
   not round-trip an arbitrary double, so a loaded save drifts from the live game in the
   last digits and then diverges. `SocietyRules.quantize()` rounds onto a four-decimal grid
   — verified against 200k random values. `snappedf()` is **not** equivalent: it can land
   on a double adjacent to the grid point, which prints and re-parses as a different
   number. Symptom: `test_save_round_trip` fails after ~40 turns but passes after 4.
4. **Nothing in `SocietyRules` or `LegibilityRules` may draw from the RNG.** The UI calls
   those queries arbitrarily often; one draw would make a save replay differently. There is
   a test that asserts `state.rng_state` is untouched by every query.

## 5. The visual and command layer (requested 2026-08-26 — DELIVERED 2026-08-27)
## 4b. The building yard, and the rules it added

Four things a newcomer will trip over otherwise:

- **`ConstructionRules.blockers_for` is the only answer to "may this be built".**
  It returns `{kind, params}`, and `available_projects` offers a chain iff the
  next tier has no blockers. Add a filter there and nowhere else, or
  `tests/test_building_info.gd`'s cross-check will fail — deliberately.
- **Sentences are content.** `data/effects_glossary.json` holds the wording;
  `src/core/` returns `{kind, params}` and never authors English. Numbers stay
  in `balance.json`. The schema refuses an `inert` effect without a note, which
  is what keeps `weapon_upgrade` / `armor_upgrade` (45 uses, no engine reader)
  from being sold to the player as working bonuses.
- **Effects are standing totals at a tier, not increments**, so an upgrade is
  worth `new - old`; and the five keys read through `effect_max` must be diffed
  against the best *other* chain in the town, or a shipyard claims recruit
  experience a Field of Mars already provides.
- **There are no image files and none may be added.** `BuildingArt` / `UnitArt`
  resolve a level or a unit into a parts list in a normalised 0..1 stage;
  `ArtPainter` draws it with the map's own primitives and palette. Never
  `randf()` — hash from the id, as `MapGeometry` does. Two traps that bite:
  `Array.sort_custom` is **not stable** (parts sort on `layer * 1000 + index`),
  and the plate cache must live on the resolver keyed to `GameData`, because the
  panels holding the plates are rebuilt on every player order.

Look at the art rather than reasoning about it:

```sh
SHOT_MODE=contact SHOT_KIND=walls SHOT_OUT=/tmp/walls.png \
  xvfb-run -a -s "-screen 0 1920x1200x24" godot --path . --script res://tools/screenshot.gd
SHOT_OUT=/tmp/yard.png SHOT_TURNS=8 SHOT_DRAWER=construction SHOT_CHAIN=roman_barracks \
  xvfb-run -a -s "-screen 0 1920x1200x24" godot --path . --script res://tools/screenshot.gd
```

Every visual fix in that work came from opening the PNG, not from reading code.

## 5. Ways forward

The user set this direction after playtesting the modernized map, and every
requirement below has since shipped on this branch. The three decisions §5.4
demanded were put to the user and taken as follows:

1. **Art (R1)** — procedural vector at kind/class granularity: 29 near-3D
   compositions in `src/ui/art/illustrations.gd` (17 building kinds, 12 unit
   classes, culture palettes, tier growth), zero binary assets; the cards
   consume art through one swappable slot, so richer raster art can replace
   pieces later without touching layout.
2. **Pan rebind (R2's precondition)** — left-drag and middle-drag pan; a left
   press only counts as a click if the mouse never travels past 6px, so
   selection is untouched; the freed right button asks instead of panning.
3. **Battle depth (R4)** — the full animated field, driven by an additive
   round log; interactive battles stay out of scope, as designed.

What landed where:
### Phase 6 — AI opponents, properly
`src/core/rules/ai.gd` now marches, besieges, storms and declares war, and the
map does change hands (`tests/test_ai.gd` proves it over forty turns). What it
still does not do is listed in its own docstring: economic planning beyond
cheapest-first, negotiation, naval and fleet behaviour, agents, coordinated
multi-army operations, defensive stacking, and any plan longer than one turn.
The difficulty multipliers are read but only for income and order
(`balance.json → ai.difficulty_income_multiplier`, `ai.difficulty_order_bonus`).

> Take `AiRules` from bounded to real: split it into economy / expansion / war /
> defence behaviours that hold a plan across turns, wire the difficulty
> constants into aggression as well as income, and verify with a long headless
> campaign that a strong faction actually snowballs.

- **Glossary + readers**: `data/glossary.json` (unit classes, attributes,
  effects, building kinds — each id/name/blurb, schema-validated and
  cross-checked) read through `Game.unit_profile` / `Game.building_profile`.
- **Info cards** (`src/ui/panels/info_card.gd`): the unit card (portrait,
  stats incl. the previously unread `speed`, skills explained, the building
  that trains it) and the building card (per-level named effects, the troops
  each tier unlocks, click-through navigation into unit cards). Right-click
  answers on the panel's build, demolish, recruit, hire and unit rows.
- **Map dossier** (`src/ui/panels/map_context_menu.gd`): right-click a
  province for its garrison (skills named inline), its buildings by built
  level, and the armies present — your own troops as rows that open their
  cards; a foreign stack shows only its size. Fog discipline matches the
  tooltip and panel exactly: a fogged province gives up only its region
  name; rival cities keep their rosters and works.
- **Battle round log** (`AutoResolver`): additive `rounds[]` — skirmish,
  charge, melee, break, pursuit; per-round casualty splits that sum exactly
  to the single-shot totals; a morale track; the break naming the side that
  shatters — plus per-unit `attacker_report`/`defender_report`. ZERO
  additional RNG draws (a twin-RNG test replays the documented draw count
  and compares end states). Tunables in `balance.json → battle.round_*`,
  validator-checked; the `BattleResolver` contract documents the keys as
  optional.
- **Battle playback** (`src/ui/battle_screen.gd`): the log as an animated
  field — class-shaped blocks advance, grind, shrink, break and rout, morale
  bars drain, each phase captioned; skippable at any moment. Wired after
  `_resolve_attack` and through the region panel's `battle_fought` signal —
  the war-confirmation guards are untouched.
### Phase 5 — Agents & diplomacy
`DiplomacyRules` currently offers only symmetric stances and war declaration;
the UI sets a stance directly and the other side simply accepts. The
`personal_security` and `agent_skill` ancillary effects are authored in the data
and have **no engine reader** — they exist for this phase.

The original requirements and pre-work analysis stay below as the record.

### 5.1 The four requirements
### Phase 9 depth — an empire-wide policy slot

Provincial edicts are built (`docs/DESIGN.md` §4.10): one standing order per settlement,
folded into `SettlementRules.effect_total` so it reaches every existing reader. What is
still missing is the faction-scoped counterpart — the stocks an edict cannot touch from a
single province are Ambition, Martial Spirit, Craft and Plunder's Share.

> Add a single realm-wide policy alongside the provincial edict: a standing army law, a
> policy of enfranchisement, a settlement of the veterans. Same shape as `data/edicts.json`
> but faction-scoped, reaching `SocietyRules.apply_faction_turn` rather than
> `effect_total`. Keep it to one slot so it stays a decision.

### Phase 8 — Balance & polish
Driven by whatever the playtest surfaced. The societal constants in
`data/balance.json → society` are the newest and least playtested numbers in the file.

**R1 — Show me what I am building and training.** Visual, near-3D renderings
of the actual architectural buildings and of the troops being trained. Today
every building and unit is text plus a small procedural glyph; the player
cannot see a hastatus, a stable, or a temple. Wanted: a picture for every
building level and every unit template, visible both on the map and in the
panels where they are chosen.

**R2 — Right-click for depth.** Right-click a building for its details: what
it does, what it gains you, why it is worth building. Right-click a
settlement for its garrison at a glance — how many soldiers, of what. The
same for the skills of the troops being trained. Today all of this is
reachable only by selecting a region and reading the side panel; nothing is
one gesture away, and right-click is not used at all (it pans the map).

**R3 — Classes of troops, tied to their buildings.** Cavalry, archers,
infantry — and the buildings that produce each — legible as a system, on the
map and in the UI. The player wants to see the correspondence, not infer it.

**R4 — Click to attack, and watch the battle.** Select units, click an enemy
city or town, and have the automated battle sequence play out visually
instead of resolving into a single log line.

### 5.2 What already exists — do not rebuild it

The data layer is further along than the UI suggests. All of this is
authored, validated, and currently invisible:

| Already in the data | Where | Currently used for |
|---|---|---|
| **12 unit classes** (`infantry, spear, pike, missile, cavalry, horse_archer, chariot, elephant, siege, ship, general_bodyguard, peasant`) | `data/units.json`, enum in `schemas/units.schema.json` | nothing in the UI |
| **Class ↔ building correspondence**, exactly as R3 asks | `units[].requirements.building_kind` | recruitment gating only |
| barracks → 33 units · stables → 22 · archery_range → 11 · naval → 6 · siege_workshop → 2 · temple → 3 | same | same |
| **10 unit attributes** (`phalanx, testudo, shield_wall, warcry, frighten_cavalry, frighten_infantry, can_hide_forest, can_sap, fast_moving, hardy`) | `data/units.json` | **read by nothing** — these are R2's "skills" |
| **`speed` 2–9 per unit** | `data/units.json` | **read by nothing** |
| Per-unit `attack, charge, defense, morale, soldiers, cost, upkeep, era, description` | `data/units.json` | numbers in the panel |
| Building level `name, cost, build_turns, effects{}, description` for 46 chains + 35 temples | `data/buildings.json`, `data/temples.json` | numbers in the panel |
| Wall/road/port tiers, culture-specific chains | same | already drives map iconography |

**R3 is therefore mostly a presentation job, not a data job.** R2's "skills"
are the `attributes` array plus each level's `effects` — both authored, both
needing a reader and a renderer, not new content.

Also already built, and the natural spine for R4:

- `BattleResolver` (`src/core/rules/battle/battle_resolver.gd`) is the
  documented swappable interface; `DESIGN.md` §10 calls a real-time battle
  layer "by design, a drop-in". Campaign code only ever calls `resolve()`.
- Attack, siege, assault-with-occupation, and garrisoning already work end to
  end, with the war-confirmation guards that a past review pass exists to
  protect. R4 is a *presentation and selection* layer over these, plus the
  round data noted in §5.4.
- `tools/screenshot.gd` renders the real game under `xvfb` — the only way to
  QA any of this, since CI never draws a pixel.

### 5.3 Gaps that R1–R4 opened (all closed by the delivery above)

- **No round-by-round battle data.** `resolve()` returned one dict:
  `winner`, `attacker_casualty_pct`, `defender_casualty_pct`,
  `attacker_general_died`, `defender_general_died`, `experience_gained` —
  no sequence to animate. Closed exactly as prescribed here: the optional
  ordered round log and unit reports landed as additive keys, every
  existing caller intact.
- **Right-click was the pan gesture** (`src/ui/map_view.gd`, with
  middle-drag). Rebound per decision 2 — left/middle-drag pan now, and the
  camera-gesture pins in `tests/test_ui_smoke.gd` moved in the same commit.
- **No binary assets exist in the repo at all**, and no asset pipeline. R1 is
  the first. See §5.4.
- **No unit-info card, no building browser, no garrison popup** — the
  research report (§12) lists all three as information architecture worth
  reusing. All three now exist: the two cards and the right-click dossier.
- Foreign fleets are hidden from the map by design today (no naval fog rule);
  if R4 grows to naval assaults, that needs a decision too.

### 5.4 Three decisions that had to precede the code (all taken — see above)

**1. The art pipeline for R1 — the big one.** "Photos / almost-3D renderings"
has three honest implementations, and the clean-room policy (`DESIGN.md` §11:
original work only; no extracted assets, no third-party art) constrains all
of them:

- **(a) Richer procedural vector art, in-engine.** Extends what the map
  already does — isometric building illustrations and unit silhouettes drawn
  from `draw_*` calls, scaled by tier and culture. Zero binary assets, zero
  provenance risk, no export/licensing bookkeeping, and it stays byte-stable
  in git. Ceiling: stylized, not photoreal.
- **(b) Committed original raster art.** Hand-authored (or tooled) images
  exported to PNG and committed — the first binary assets in the repo.
  Highest fidelity per unit of effort, but every image needs a documented
  original provenance, repo size grows, and the macOS export's
  `import_etc2_astc` flag stops being inert (see §3).
- **(c) Real 3D models rendered to a `SubViewport`.** Genuine "3D renderings",
  rotatable unit and building viewers. Heaviest by far, and
  `project.godot` currently sets `gl_compatibility` (3D works, but the
  renderer choice wants revisiting).

**Count the assets before choosing — the scope swings 14×:**

| Granularity | Assets needed | Feel |
|---|---|---|
| One per **building level + unit template** | 312 + 91 = **403** | every upgrade visibly distinct |
| One per **building kind + unit class**, tinted by culture/tier | 16 + 12 = **28** | distinct *types*, shared silhouettes |

  **Recommendation: (a) now at kind/class granularity (28 pieces), with the
  card built so its art source is swappable — then (b) to replace the
  highest-traffic pieces with richer raster art** once the layout is proven
  in play. 403 bespoke assets is a content project, not a feature; it should
  only start if the user explicitly wants it and accepts the timeline.
  (c) only for a true model viewer.
  *Ask the user before starting; this decision sets the effort by an order of
  magnitude.* Note that literal photographs are out — they would be
  third-party work, and the repo's policy is original assets only.

**2. Rebinding pan to free right-click for R2.** Options: middle-drag only
(discoverability cost), left-drag on empty sea plus middle-drag
(conventional in strategy games), or space-drag. Whichever is chosen,
`tests/test_ui_smoke.gd` pins the camera contract and PLAYING.md documents
the current gesture — both must be updated in the same commit.

**3. How deep the R4 battle playback goes.** Ascending cost:
   - *Replay card*: a scripted round-by-round summary panel with unit rows,
     casualty bars, and a morale-break beat. Needs only the round log.
   - *Animated field*: unit blocks advancing and shrinking on a stylized
     battlefield, driven by the same log — a real "sequence playing out".
   - *Interactive battle*: the deferred real-time layer. Out of scope for
     this round; the interface already anticipates it.

  **Recommendation: build the round log first (core, deterministic, testable
  headlessly), then the replay card, then animate the same data.** The log is
  the contract everything else reads, and it keeps `src/core/` scene-free.

### 5.5 Suggested sequencing (followed as written)

1. **Data readers, no UI**: expose unit `attributes`/`speed` and building
   `effects` as *named, explained* breakdowns through the `Game` facade, the
   way growth/order/income already work. Pure, testable, no rendering.
2. **Unit and building info cards**: the R1/R2/R3 content, art source
   swappable per decision 1. Class ↔ building correspondence shown here.
3. **Right-click context menus** on the map (decision 2): settlement →
   garrison roster and building list; building row → its card; army → its
   units and their skills.
4. **Battle round log** in `AutoResolver` (additive keys), with tests pinning
   determinism and the unchanged single-shot result.
5. **Battle playback screen** reading that log; wire click-to-attack selection
   into it without touching the war-confirmation guards.
6. Screenshot QA at every step; adversarial review before the final push.

### 5.6 Standing alternatives (unchanged, not chosen)

- **Phase 6 — AI opponents.** `src/core/rules/ai_stub.gd` is still 33 lines of
  passive settlement management: nothing expands, declares war, or defends,
  so the world feels empty however good the map looks. Difficulty multipliers
  (`balance.json → ai.*`) are already wired and waiting. *This remains the
  single biggest gameplay gap — worth raising with the user again, since R4's
  battles land better against an opponent that fights back.*
- **Phase 5 — Agents & diplomacy.** `personal_security` and `agent_skill`
  ancillary effects are authored with no engine reader; they exist for this.
- **Phase 8 — Balance.** Driven by playtest notes. If the user reports a
  problem, **ask for the world seed** — it reproduces their exact campaign.

## 5b. Three traps the Dispatch work added

1. **`data/dispatch.json` and `TurnJournal.KINDS` are checked against each other
   in both directions** by `tools/validate_data.py`. Add a beat kind without its
   prose (or leave prose behind after removing a kind) and the validator fails.
   That is deliberate — it is what keeps content out of GDScript.
2. **The interface font is Open Sans and has no Miscellaneous Symbols block.**
   The obvious icon characters (⚔ ★ ✦ ▲) render as empty boxes. Every mark in
   `DispatchFormat.ICON_MARKS` is checked against the real font by
   `test_dispatch.gd :: test_every_icon_actually_renders` — run it before
   trusting a new icon.
3. **`CampaignScreen.playback_enabled` is the seam** that keeps `_end_turn()`
   synchronously completable. The headless suite drives twenty-five turns in a
   loop with no frames; leave playback on there and the second call is refused
   because the first day is still on screen.

### The one the user actually wants next — societal trade-offs
The user's stated ambition for the core of the game: investment in military,
public benefit, learning and infrastructure should trade off against each other
in ways that are *felt* rather than tabulated, and that teach something true
about history and societies. Guns without bread works for a while, then does
not. They explicitly want **first-principles and physics-like, not a
ten-thousand-parameter cause-and-effect weighing scale** — or a deliberate
hybrid. The building yard is the natural surface for it: it already names what
each choice buys, so it can be made to name what each choice costs.

> Design and build the societal trade-off model: a small number of conserved,
> first-principles quantities (something like legitimacy, cohesion, capacity)
> that every investment moves in more than one direction, with lags and
> thresholds rather than per-building bonuses. Keep every constant in
> balance.json, keep it deterministic, surface it in the existing breakdowns and
> the building yard, and prove the emergent claim with long headless campaigns:
> an all-military build order must actually collapse, and for a legible reason.

### Phase 6 follow-ups — deepening the AI
The AI plays the whole game but uniformly; the thresholds live in balance
data and the behaviours in `src/core/rules/ai/` (DESIGN.md §9).

> Deepen the Phase 6 AI: per-faction personalities (an `ai` block in
> `factions.json` plus schema and validator coverage), AI mercenary hiring
> when a muster stalls, and smarter target scoring (economic value, wall
> discounting). Keep every knob in data, keep it deterministic, and verify
> with long headless campaigns across several seeds and difficulties.

Hostile single-region islands (Sardinia, Britannia, Crete, Rhodes, Cyprus)
are untouchable for everyone once at war — that unlock belongs to Phase 3's
amphibious landings, not to AI work.

## 6. Known gaps (verified, not guesses)

- **Starting families are adult men only**: 20 leaders, 19 heirs, 32 family, and
  **no spouses, no children, no `gender` field set** in `campaign.json`. The
  marriage path only opens once in-game births produce daughters, so the family
  tree bootstraps slowly. Seeding real households would fix it.
- **Coastal multi-hop targets sail instead of marching**: the order chain
  tries `sea_move_army` before `march_army`, so a coastal destination in
  ship's reach is sailed to (one whole turn) even when the hover preview
  sketched a land route. Usually what the player wants; occasionally not.
- **`office_gained` triggers are dead** until Phase 7 offices exist. The
  validator knows: `FORWARD_TRIGGERS` in `tools/validate_data.py` allowlists
  them, and warns about any *other* trigger kind no engine call site fires.
- **Three mission kinds are still forward content**: `blockade_port` needs port
  blockades (Phase 3 remainder), `assassinate_leader` and `leader_suicide` need
  agents (Phase 5). `SenateRules.LIVE_KINDS` names what is actually judged, and
  `FORWARD_MISSION_KINDS` in the validator allowlists the rest — anything in
  neither list is an error.
- **Phase 3 remainder**: embark-on-fleet transport (sea movement is an
  abstracted crossing today), naval battles, port blockades, forts and
  watchtowers, ambush.
- **Art is original procedural vector work** — terrain map, walled towns,
  army roundels, all drawn from campaign data. No binary assets yet; a
  bundled licensed font and richer texture work are open polish items.
  watchtowers, ambush. Until landings exist, a hostile single-region island
  cannot be invaded by anyone — the AI knows and does not try (DESIGN.md §9).
- **The map is a procedural painting** — `src/ui/map_geometry.gd` carves the 70
  region points into province polygons (wobbled coast discs cut by half-plane
  bisectors; straits kept open between sea-sharing non-adjacent regions), and
  `map_view.gd` paints them on two cached `Node2D` layers (sea, land) that a
  pan just moves — only ownership/fog changes (`repaint_land()` from
  `refresh()`) or a zoom LOD-band change rebake the land. Tokens, labels and
  badges stay in `MapView._draw` (screen space, every frame). Determinism is
  FNV-1a hashes of region ids — no RNG. Screenshot QA:
  `SHOT_OUT=x.png SHOT_ZOOM=-8 SHOT_TURNS=30 xvfb-run -a -s "-screen 0 1600x1000x24"
  godot --rendering-driver opengl3 --path . --script res://tools/screenshot.gd`
  (SHOT_ZOOM is in 1.15× steps; shoot turn 30 as well as 0 — fog hides most
  of the world at turn 0). No portraits or battle art yet — but buildings and
  units are now drawn (§4b), so the pattern for character portraits exists.
- **`weapon_upgrade` and `armor_upgrade` still have no engine reader.** 45 uses
  across the building data, zero call sites in `src/`. The UI is honest about
  it; wiring them into `AutoResolver` would be a small, self-contained win, and
  flipping `status` to `live` in `effects_glossary.json` is the only other
  change needed.
**Balance & feel (playtest-driven — most likely next).** The numbers in
`balance.json → ai / diplomacy / knowledge / edicts` and the five personas in
`data/ai.json` shipped after soak passes, not a hundred games. Per-edict and
per-technique tuning lives in `data/edicts.json` and `data/techniques.json` —
`balance.json → edicts` holds only four global knobs. The soak's `divergence`
figure is a tuning target: raise diffusion/origination variance and it climbs.

**The optional online narrator.** The chronicle is already the
machine-readable feed (`schemas/chronicle_entry.schema.json`,
`ChronicleRules.resolved()`), rendered offline by `data/annals.json` templates.
An optional online narrator — prose only, never state — exports resolved
entries, asks a model, and renders the result with the templates as fallback.

**Phase 7 — senate offices & politics depth.** `office_gained` triggers and the
`leader_suicide` mission are authored and allowlisted, waiting for offices,
elections, and late-game senate hostility.

**Phase 3 remainder — the sea.** Fleets move and watch but never fight;
`blockade_port` missions are authored and allowlisted. The corvus technique and
its **Boarding Marines** (the first `requires_technique` unit) were written as
the hook for exactly this slice.

**AI agents.** The engine supports agents fully; the AI deliberately does not
use them (DESIGN §6.2 explains why). Spies before sieges and assassins after
wars start — with counterplay surfaced in the UI — is a contained slice.

**Real-time battles.** Everything funnels through `BattleResolver.resolve(...)`;
a battle scene is a drop-in second implementation.

## 8. Known gaps (verified, not guesses)

- **The AI never assigns generals** to its armies and never shuffles retinues —
  there is not one reference to retinues in `src/core/rules/ai/`. Only
  `FamilyRules.maybe_man_of_the_hour` ever attaches a general, so the AI's led
  armies are incidental.
- **The AI has no awareness of senate missions at all** (zero references in
  `rules/ai/`), so any completion is accidental and failures cost it standing.
  Missions are issued only to the three `is_roman_house` factions.
- **The seed is not persisted** — see §4.
- **Sea-zone `position` values** in `regions.json` (the field is `position`, not
  "anchor") are unused: `map_view.gd` draws lanes from shared-zone membership
  and never labels a zone.
- **`blockade_port` and `leader_suicide` missions are dead** until their systems
  exist — 2 of 9 authored missions can never be drawn.
  `FORWARD_MISSIONS`/`FORWARD_TRIGGERS` in `tools/validate_data.py` allowlist
  them, as with `office_gained`.
- **Phase 3 remainder**: embark-on-fleet transport, naval battles, port
  blockades, forts and watchtowers, ambush.
- **Art is placeholder** — coloured circles on a geographic map.

## 9. Process notes

- **Git identity must be `noreply@anthropic.com` / `Claude`** before committing,
  or a stop hook flags the commits as unverified and they need re-authoring.
  Develop on the branch the session names (currently `claude/modernize-map-world-view-03orjy`).
- **Run adversarial review agents after building anything substantial.** This
  has now paid off twice. The first pass (engine correctness, UI behaviour,
  data/doc fidelity) found **37 real issues** the 60-strong suite had missed —
  armies declaring war by accident on turn one, a save-determinism break,
  movement traits that silently did nothing, generals still governing cities
  they had marched away from. The second pass, after the map work, found **15
  more** against an 85-test suite: a besieger that walked away from its own
  siege next turn, path previews leaking hidden settlement allegiances through
  the fog, march ETAs that ignored wasted per-turn movement, and a
  double-click that resolved two battles from one gesture. Give each reviewer
  the research report plus a specific lens, tell them to run the suite
  themselves, let them write throwaway probe scripts in `/tmp`, and require
  findings-only output. **Budget a fix commit after every review — assume it
  will find something.**
  Develop on `claude/daily-campaign-turn-sequence-8mq71d`.
  Develop on the branch the session assigns (this phase used
  `claude/ai-opponents-5y68t6`).
- **Run adversarial review agents after building anything substantial.** Three
  reviewers (engine correctness, UI behaviour, data/doc fidelity) found **37 real
  issues** the 60-strong test suite had missed — including armies declaring war
  by accident on the first turn, a save-determinism break, movement traits that
  silently did nothing, and generals still governing cities they had marched away
  from. Give each reviewer the research report plus a specific lens, tell them to
  run the suite themselves, and require findings-only output.
- When adding a rules module, add tests to `tests/` **and** cross-reference
  checks to `tools/validate_data.py` if it introduces a data table. Both gates
  must pass before committing.
  or a stop hook flags the commits as unverified. Develop on whatever branch the
  session assigns and push to `origin`; CI runs the two gates on every push.
- **Run adversarial review agents after anything substantial.** Three reviewers,
  each with a distinct lens (determinism & save-compat; data/schema/clean-room
  and historical fidelity; balance, exploits & AI behaviour), findings-only
  output, told to verify every claim in code. Phase 4 found 37 real issues the
  tests had missed; Phase 5+6 found 28; the Deep Strategy round found 24 —
  including the senate overwriting `popular_standing` (which had made every
  edict tension dead code), a free enact→repeal standing mint, the AI freezing
  on the four cheapest edicts forever, and two epithets that were provably
  unreachable. **Budget a fix commit after each round.**
- **Verify a reviewer's mechanism before acting on it.** The layout bug in §0
  was reported with a diagnosis that contradicted the API docs; a ten-line
  in-engine probe settled it (the reviewer was right, the doc reading was
  wrong). Cheap to check, expensive to get backwards.
- **A new rules module needs tests in `tests/`**, and a new data table needs a
  schema *and* cross-reference checks in `tools/validate_data.py`. Both gates
  before committing.
- **Balance changes want a soak, not just the suite.** The harness asserts
  invariants; the soak shows character. The first AI soak looked perfectly green
  while producing a world of shopkeepers with zero wars.
