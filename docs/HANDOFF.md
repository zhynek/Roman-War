# Handoff — picking up Roman War in a fresh session

Everything an assistant (or a human) needs to be productive here within five
minutes. It deliberately does **not** repeat the other docs:

| For | Read |
|---|---|
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
