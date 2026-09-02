# Handoff — picking up Roman War in a fresh session

Everything an assistant (or a human) needs to be productive here within five
minutes. It deliberately does **not** repeat the other docs:

| For | Read |
|---|---|
| Architecture rules you must not violate, conventions, clean-room policy | [`CLAUDE.md`](../CLAUDE.md) (auto-loaded by Claude Code — read it first) |
| What every system does, and the phase-by-phase status table | [`docs/DESIGN.md`](DESIGN.md) — §13's table is authoritative |
| What the game is like to play | [`PLAYING.md`](../PLAYING.md) |
| How to produce a downloadable app | [`BUILDING.md`](../BUILDING.md) |
| Why the design is what it is | [`docs/research/rtw-research-report.md`](research/rtw-research-report.md) |

## 1. Where things stand

**`main` is the trunk. Use it.** Until 2026-09-01 this repository had no `main`
at all: eight sessions each branched off `9026730` and none merged back, so
every build contained only that session's work and nothing else. That is why a
build could ship without the map you remembered writing. `main` now carries the
integration of five of those branches and is the only branch worth building.

**Merged into `main`, in this order:**

| From | What it brought |
|---|---|
| `modernize-map-world-view` | The base. Layered terrain renderer, real coastlines and polygon provinces, iconography, hover/tooltips, movement range and route preview, info cards, the animated battle view, pathfinding, multi-turn march orders |
| `game-decision-tradeoffs` | The society engine (legitimacy, grievance, belonging, elite pressure, martial ethos, craft), provincial edicts, crisis events |
| `daily-campaign-turn-sequence` | The turn journal, the fog-filtered end-turn sequence, the Daily Dispatch |
| `building-details-upgrades` (contains `ai-opponents`) | The modular AI, the guided campaign trail, the building yard and muster hall, 312 procedural building illustrations, the no-mouse camera |
| `project-handoff-familiarization` | Campaign agents and a real negotiation model, the knowledge/technique engine, the chronicle and epithets, AI personas |

**Deleted, not merged: `handoff-repo-familiarization-jgqty6`** (head
`bd8be2549e9a39dafe496f1cb97cd6237ace10a9`, deleted 2026-09-01 after review).
Roughly 1,470 of its lines were a third implementation of systems `main`
already has — its own AI (742), agents (308), negotiation (307) and tutorial
(113). Merging those would have been damage, not integration.

Five things it held that `main` lacked went with it. Phase 7 recovered two —
the **office ladder** (`data/offices.json`, ported and reworked rather than
merged: its senate step *assigned* `popular_standing`, which `main` guards
against) and the build-version stamp on the start menu. Three are still worth
taking if anyone wants them: the **Advisor** (in-game LLM counsel and
feedback-to-ticket, `src/ui/advisor/`, `data/advisor.json`),
`src/core/rules/armies.gd` (which duplicates `CombatRules.raise_army` /
`detach_to_garrison` — take the idea, not the file), and
`.github/workflows/claude-triage.yml`. The commit is unreachable but not
immediately garbage: `git fetch origin
bd8be2549e9a39dafe496f1cb97cd6237ace10a9` recovers it while GitHub still holds
the object. Do not resurrect the branch wholesale — take the pieces.

**Also superseded: `next-phase-roadmap-sjrj35`.** It carried eight commits that
never reached `main`, which looks alarming until you diff it: it is the earlier
draft of the same map work `modernize-map-world-view` finished, and `main`'s
copy of every source file it touches is a strict superset (`map_view.gd` 603 vs
540 lines, `settlement_icons.gd` 321 vs 255, `ui_style.gd` 155 vs 94,
`validate_data.py` 1281 vs 556). Its three map test files are absent from `main`
by absorption, not loss — `test_pathfinding.gd` and `test_ui_smoke.gd` cover
march orders across turns and saves, halts, order supersession, sieges, fog,
polygon picking and fleet orders. Nothing to take from it.

**Green on `main`:** 336 tests / 0 failures across 37 test files, validator
0 errors / 0 warnings across 31 data tables, clean boot. A turn costs ~360 ms.

**Phase 7 — the cursus honorum — is built on `claude/roman-war-next-phase-8ef54h`**
(branched from `main` at `2c9b602` per §9; un-merged until the owner says so).
Senate offices and summer elections, seats that absorb Ambition, the Senate's
demand for a patriarch's life, outlawry, a civil war with sides that can never
be talked away and ends when the Senate falls, the Senate scroll, five journal
beats and a trail stage — `docs/DESIGN.md` §8.1 is the account. The branch also
carries the trunk fixes that were waiting: the world seed persisted and shown
(§4), the build version on the start menu, a dead duplicate `class_name` that
broke every suite on a fresh cache (§5.17), and a UI smoke test that had been
silently truncated. Green: 359 tests / 0 failures across 38 test files,
validator 0 errors / 0 warnings across 32 data tables, clean boot.

**Two things the integration surfaced that are worth knowing:**

1. `EconomyRules._disband_costliest_unit` scanned armies **unsorted**. Ties are
   the common case, so a loaded save disbanded a different unit from the live
   game — same seed, same RNG state, divergent world. Two branches found this
   independently.
2. `popular_standing` and `senate_standing` now **drift** rather than being
   recomputed, and an accumulator through a lossy JSON writer diverges a turn
   after loading. Both go through `SocietyRules.quantize` now. Any new
   continuous stock must do the same.

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
godot --headless --path . --script res://tests/run_tests.gd   # 336 tests, 0 failures
godot --headless --path . --quit-after 5                      # boots clean: no errors after the version banner
```

The suite takes several minutes — `test_ai_campaign` (60 AI turns, replayed,
then save-and-resumed) and `test_society_longrun` dominate it, and it prints
nothing until it finishes, so a quiet terminal is not a hang.

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
`combat`, `siege`, `economy`, `growth`, `public_order`, `society`,
`legibility`, `construction`, `recruitment`, `movement`, `characters`,
`family`, `senate`, `events`, `guided`, `victory`, `mercenaries`,
`settlements`, `map`, `visibility`, `dispatch`, `advances`, `pathfinding`,
`building_info`), with the AI in `rules/ai/`
(`faction_ai` orchestrates → `ai_diplomacy`, `ai_assess`, `ai_military`,
`ai_economy`, `ai_strategy`, `ai_policy`, `ai_politics`, `ai_rules` for personas) and battle
behind `rules/battle/battle_resolver.gd`.

**UI** (`src/ui/`) — every panel talks only to the facade:

| Panel | Facade methods |
|---|---|
| `campaign_screen.gd` (the shell) | `end_turn`, `day_beats`, `move_army`, `sea_move_army`, `attack_army`, `besiege`, `move_agent`, `agent_scout/_assassinate/_bribe/_steal_technique`, `visible_regions`, `victory_progress`, `save_to`, `load_from` |
| `panels/region_panel.gd` (the biggest) | `growth/order/income_breakdown`, `available_buildings/units`, `queue_building/unit`, `demolish_building`, `set_tax_level`, `retrain_garrison`, `garrison_army`, `raise_army`, `move_capital`, `assault_settlement`, `hire_mercenary`, `mercenaries_available`, `recruit_agent`, `agents_in`, `set_edict`, `revoke_edict`, `available_edicts`, `edict_status` |
| `panels/diplomacy_panel.gd` | `pending_offers`, `respond_offer`, `declare_war`, `move_fleet` — **fleets live here, not on the map** |
| `panels/negotiation_dialog.gd` | `preview_offer`, `propose_offer` |
| `panels/family_panel.gd` | `family_of`, `character_sheet`, `set_heir`, `transfer_ancillary` |
| `panels/senate_panel.gd` | `senate_overview`, `comply_senate_demand` — the one act the scroll takes |
| `panels/knowledge_panel.gd` | `technique_overview`, `begin_adoption` |
| `panels/annals_panel.gd` | none — renders `state.chronicle` through `data/annals.json` |
| `panels/quest_panel.gd` | the guided trail's objectives and rewards |
| `panels/build_drawer.gd`, `panels/info_card.gd`, `panels/map_context_menu.gd` | the building yard / muster hall, the illustrated cards, the right-click dossier |
| `turn_sequence.gd` + `dispatch_panel.gd` | the day's playback and its recap, over `day_beats` |

**Tests** (`tests/`, 38 files over `tests/fixtures.gd`, a synthetic world that
loads the real `balance.json`). Formula units: `growth`, `economy`,
`public_order`, `construction`, `recruitment`, `battle`, `battle_log`,
`movement_visibility`, `pathfinding`, `characters`. Systems: `agents`, `senate_politics`,
`diplomacy_offers`, `diplomacy_war`, `ai`, `knowledge`, `edicts`, `chronicle`,
`society`, `legibility`, `advances`, `guided`, `turn_journal`, `dispatch`,
`events_vocabulary`. Presentation: `map_geometry`, `map_menu`, `illustrations`,
`building_art`, `unit_art`, `info_cards`, `battle_screen`, `profiles`,
`building_info`. Integration: **`test_ai_campaign.gd` is the tripwire** —
60 AI-driven turns asserting the map changes hands, byte-identical replay from
one seed, and save-at-20/resume-in-lockstep. `test_ui_smoke.gd` drives the real
screen headless; `test_society_longrun.gd` is the slow shape check.

## 4. Turning a playtest report into work

**Ask "what seed?" first — it is on screen.** The seed is written into the
state as `world_seed` (saves from before Phase 7 read `0`), shown beside the
date in the top bar, and `Game.new_campaign(house, seed)` replays the campaign
exactly — provided the build is the same, which is why the version is on the
start menu.

**Ask for the save file instead** — it pins the world exactly (`rng_state`
plus all state). One fixed slot, `user://roman_war_save.json`:

- macOS: `~/Library/Application Support/Godot/app_userdata/Roman War/roman_war_save.json`
- Linux: `~/.local/share/godot/app_userdata/Roman War/roman_war_save.json`

Then reproduce headlessly — load it the way the facade does
(`SaveGame.read_file` → `NewGame.ensure_state_keys(state, data)` → assign to a
`Game`) and step turns in a throwaway script, printing whatever the report is
about. If they *did* keep the seed, `Game.new_campaign("julii", SEED)` replays
their campaign exactly.

Balance complaints want a soak before and after, not just the suite (§2).

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
   silently round a 64-bit RNG state to a multiple of ~1024, producing a
   different random stream after loading.
3. **Quantize any continuous float you put in the state.** Godot's
   `JSON.stringify` does not round-trip an arbitrary double, so a loaded save
   drifts from the live game in the last digits and then diverges.
   `SocietyRules.quantize()` rounds onto a four-decimal grid — verified against
   200k random values. `snappedf()` is **not** equivalent: it can land on a
   double adjacent to the grid point, which prints and re-parses as a different
   number. Symptom: `test_save_round_trip` fails after ~40 turns but passes
   after 4.
4. **Inside `TurnEngine.end_turn`, never call the `Game` facade.** `Game._rng()`
   rebuilds from `state["rng_state"]`, stale until end_turn writes it back — a
   second stream breaks save determinism. AI code calls rules modules directly
   with the threaded rng.
5. **Player actions must not steer the campaign stream** unless they say so:
   facade methods that consume rng (attack, assault, assassinate, steal) rebuild
   it from state and write it back; everything else picks deterministically.
6. **Nothing in `SocietyRules` or `LegibilityRules` may draw from the RNG.**
   The UI calls those queries arbitrarily often; one draw would make a save
   replay differently. A test asserts `state.rng_state` is untouched by every
   query.
7. **GDScript `:=` cannot infer through Variant.** `var n := dict["x"].size()`,
   or `:=` from an untyped loop variable, is a PARSE error that takes the whole
   class down — and then every caller reports "Nonexistent function" instead of
   the real error. Type such vars explicitly.
8. **Every settlement capture goes through `CombatRules.capture_settlement` AND
   `fire_occupation_triggers`.** Peaceful cessions (`DiplomacyRules.cede_region`)
   are the deliberate exception: no loot, no triggers, garrison marches home.
9. **A new per-entity state key must be emitted at EVERY creation site**, not
   just `build` + `ensure_state_keys` + fixtures: births (`family.gd`),
   mercenaries, senate unit grants. Missing one lets a resumed save diverge
   from a live game — which is exactly how `deeds`/`epithet`/`weapons`/`armor`
   broke the lockstep test once each.
10. **`GrowthRules._plague_turn(data, state, settlement, rng)` takes `state`**
    (plague resistance is faction-wide). A merge that drops the param compiles
    nowhere near the bug it causes.
11. **The senate must DRIFT `popular_standing`, never assign it.**
    `senate.gd` moves it toward a regional baseline by `popular_drift_factor`;
    an overwrite silently turns *every* edict's political tension into dead
    code. This shipped as a bug once and the tests did not catch it —
    `test_popular_standing_survives_the_senate_drift` does now.
12. **Perf probe before and after any breakdown-path change.** Time 60
    `end_turn`s in a throwaway script. A turn costs ~360 ms on the integrated
    engine, and `test_ai_campaign.gd` fails above 600 ms — that headroom is a
    guard against pathological slowness, not spare budget. Profiling puts the
    AI at ~60% of a turn with no single hot spot.
13. **UI Controls: `set_anchors_and_offsets_preset`, never
    `set_anchors_preset`.** The latter keeps the control's current rect — 0×0
    for a freshly built one — so the whole UI rendered at its minimum size in
    the top-left corner and grew only by the *delta* of a window resize,
    leaving Godot's grey clear colour over the rest of the window. Pinned by
    `test_campaign_screen_fills_its_window`.
14. **`data/dispatch.json` and `TurnJournal.KINDS` are checked against each
    other in both directions** by `tools/validate_data.py`. Add a beat kind
    without its prose (or leave prose behind after removing a kind) and the
    validator fails. That is deliberate — it is what keeps content out of
    GDScript.
15. **The interface font is Open Sans and has no Miscellaneous Symbols block.**
    The obvious icon characters (⚔ ★ ✦ ▲) render as empty boxes. Every mark in
    `DispatchFormat.ICON_MARKS` is checked against the real font by
    `test_dispatch.gd :: test_every_icon_actually_renders` — run it before
    trusting a new icon.
16. **`CampaignScreen.playback_enabled` is the seam** that keeps `_end_turn()`
    synchronously completable. The headless suite drives twenty-five turns in a
    loop with no frames; leave playback on there and the second call is refused
    because the first day is still on screen.
17. **Two files must never share a `class_name`.** A dead `src/ui/map_geometry.gd`
    duplicated `MapGeometry` (the live one is `src/ui/map/map_geometry.gd`). On a
    warm `.godot` cache Godot happened to resolve the live one; on a fresh cache
    (CI, a new clone, after `rm -rf .godot`) it picked the corpse and every suite
    failed at parse time without naming a test. When a suite dies before printing
    a line, `grep -rn "class_name X" src/` for duplicates before anything else.
18. **A new rng draw inside the campaign stream moves every seed-pinned
    expectation.** The elections fire `office_gained` triggers, which draw
    `rng.chance`, so from the first summer on every `Game.new_campaign("julii", N)`
    world differs from the one older tests were pinned to. That is not a
    determinism failure — replay and save-resume lockstep guard determinism — but
    re-pin knowingly: read the new value, confirm the mechanism, then update the
    expectation. `test_society_longrun` moved twice this phase (elections, then
    the trail's office stage paying the house) and its horizon ended where it
    began, at sixty — the scratch probe that replays its two plays and prints
    the Julii's regions per decade is ten minutes well spent before touching it.
19. **The demand template has no `min_year`, on purpose.**
    `the_senate_demands_your_life` shipped with `min_year: -60`, unreachable in
    any campaign a playtester will finish. The greatness gate
    (`leader_suicide_standing` / `leader_suicide_popular_min`) replaced the
    calendar gate; do not put the year back.

### The building yard, and the rules it added

Four things a newcomer will trip over otherwise:

- **`ConstructionRules.blockers_for` is the only answer to "may this be built".**
  It returns `{kind, params}`, and `available_projects` offers a chain iff the
  next tier has no blockers. Add a filter there and nowhere else, or
  `tests/test_building_info.gd`'s cross-check will fail — deliberately.
- **Sentences are content.** `data/effects_glossary.json` holds the wording;
  `src/core/` returns `{kind, params}` and never authors English. Numbers stay
  in `balance.json`. The schema refuses an `inert` effect without a note, which
  is what keeps a dormant effect key from being sold to the player as a working
  bonus.
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

Look at the art rather than reasoning about it — every visual fix in that work
came from opening the PNG, not from reading code:

```sh
SHOT_MODE=contact SHOT_KIND=walls SHOT_OUT=/tmp/walls.png \
  xvfb-run -a -s "-screen 0 1920x1200x24" godot --path . --script res://tools/screenshot.gd
SHOT_OUT=/tmp/map.png SHOT_ZOOM=-8 SHOT_TURNS=30 \
  xvfb-run -a -s "-screen 0 1600x1000x24" godot --rendering-driver opengl3 \
  --path . --script res://tools/screenshot.gd
```

(`SHOT_ZOOM` is in 1.15× steps; shoot turn 30 as well as turn 0 — fog hides most
of the world at turn 0.)

## 6. Building and delivering a playable app

`BUILDING.md` has the recipe. Presets write to `../build/`:
`RomanWar-macOS.zip` (universal, ~56 MiB), `RomanWar-macOS-arm64.zip` (**the
thinned one that fits the delivery cap**, ~27 MiB), and `RomanWar-Linux/`.
What costs time to rediscover:

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
  `.pck`, so run it headless with a probe script that starts a campaign, counts
  the packaged data tables, and ends a few turns.

## 7. Known gaps (verified, not guesses)

- **`AiStrategy`'s persistent-objective machinery is dead code.**
  `refresh_objective` and `state.factions[fid].ai.objective` are called by
  nothing: `FactionAi` picks targets through `AiAssess.choose_target` instead.
  Only the force estimators in that module are live. Wire it or delete it
  deliberately — the module docstring says so, so nobody builds on a corpse.
- **No AI ever issues a provincial edict.** `EdictRules.issue` has exactly one
  caller — `Game.set_edict`, the player facade. The AI branch that chose edicts
  lost the merge (main holds them per province under a different engine; see
  `ai_policy.gd`'s docstring), so `edict_enacted` never reaches the chronicle
  and the soak's edict line always reads `0/70 provinces`. The whole fast lever
  is a player-only system today. Teaching `AiPolicy` to pick one per province
  by persona priority is a contained slice.
- **The AI never shuffles retinues** — there is not one reference to
  ancillaries in `src/core/rules/ai/`. It does assign generals (armies raised
  from a garrison take the best free commander, and merges carry a general
  over), but retinue management is a player-only lever.
- **The AI does not recruit or use agents.** Deliberate, and DESIGN §7.2 says
  why: it is omniscient, so spies would add nothing, and AI assassins without
  counterplay UI are pure feel-bad. Governor counter-intelligence already
  defends AI cities, so the player's agents can still fail.
- **The AI cannot invade a hostile island.** The *player* can — an amphibious
  landing is legal where no field army holds the beach — but `AiAssess`
  deliberately refuses to route through a hostile shore (DESIGN §9 explains
  what that fixed). Island factions therefore expand only if war finds them.
- **Sea-zone `position` values** in `regions.json` are used only to anchor
  fleet icons and sea labels; no zone is a first-class map object.
- **One mission kind is still forward content**: `blockade_port` needs port
  blockades (Phase 3 remainder). `SenateRules.LIVE_KINDS` names what is judged,
  `FORWARD_MISSION_KINDS` in the validator allowlists the rest, and
  `FORWARD_TRIGGERS` is empty — anything in neither list is an error.
- **The AI never defies the Senate.** `AiPolitics` complies with the demand on
  its last turn, every persona alike, so an AI house reaches civil war only by
  Ambition. A `defiance` knob per persona (defy when the house's strength beats
  the Senate's side by `ai.defy_senate_ratio`) is the contained slice.
- **Nobody canvasses.** Elections read standing and influence only; there is no
  lever to buy a seat, and no `Game.declare_civil_war()` — the player crosses
  the Rubicon only by Ambition or by refusing the demand.
- **A civil war has sides but no proscriptions or defections**: armies and
  cities stay with their house; only stances, seats and the ballot change.
- **AI houses fail the Senate's courtship charges, and their standing collapses.**
  `court_a_useful_friend` asks for an alliance with a bordering foreign power;
  `AiDiplomacy` never pursues an alliance a charge names, so the AI houses fail
  it every deadline (−2 each) and sit at −7 to −10 by turn 80 in the soak — on
  `main` too, where it had no consequence. Now standing decides the ballot and
  the sides in a civil war, so every civil war tends to pull every other house in
  (`civil_war_join_standing`). Teaching the AI to court the charge's target is
  the contained fix; do not paper over it with the join threshold.
- **Offices are Roman-only.** Other cultures drain Ambition by government tiers
  alone (DESIGN §4.4); a Hellenistic court or a tribal assembly has no ladder.
- **Phase 3 remainder**: embark-on-fleet transport (sea movement is an
  abstracted crossing today), naval battles, port blockades, forts and
  watchtowers, ambush.
- **No character portraits and no battle-scene art.** Buildings, units, the
  map and its towns are all drawn by code now, so the pattern exists — the
  portraits simply have not been done.

## 8. Ways forward

Each is self-contained. The owner has not committed to one.

**Take the three things `handoff-repo-familiarization-jgqty6` still uniquely
holds** (§1) as a focused change against `main`: the Advisor stack, the idea in
`armies.gd`, and the triage workflow. The office ladder and the version stamp
came across with Phase 7.

**Balance & feel (playtest-driven — most likely next).** The numbers in
`balance.json → ai / diplomacy / knowledge / edicts / society / senate` and the five
personas in `data/ai.json` shipped after soak passes, not a hundred games. The
societal constants are the newest and least playtested in the file. Per-edict
and per-technique tuning lives in `data/edicts.json` and `data/techniques.json`.
The soak's `divergence` figure is a tuning target: raise diffusion and
origination variance and it climbs. The Phase 7 numbers
(`senate.election_standing_weight`, the demand's two gates,
`civil_war_join_standing`, `society.elite_office_absorption_per_seat_rank`)
shipped after the soak's seats-and-demands line, not a hundred games.

**Deepen the AI.** It plays the whole game but uniformly. Worth doing, in
rough order of payoff: teach it the amphibious landing it already has the rules
for; mercenary hiring when a muster stalls; smarter target scoring (economic
value, wall discounting); and either wiring or deleting the objective machinery
above. Keep every knob in data, keep it deterministic, and verify with long
headless campaigns across several seeds and difficulties.

**An empire-wide policy slot.** Provincial edicts are built (DESIGN §4.10);
the stocks an edict cannot reach from a single province are Ambition, Martial
Spirit, Craft and Plunder's Share. Add one realm-wide standing law — an army
law, a policy of enfranchisement, a settlement of the veterans — shaped like
`data/edicts.json` but faction-scoped, reaching
`SocietyRules.apply_faction_turn` rather than `effect_total`. Keep it to one
slot so it stays a decision.

**Phase 7 follow-ups (each self-contained, each its own commit).** Canvassing —
`Game.canvass(char_id, denarii)` paying treasury for election score and a
quantized Ambition shock through a `SocietyRules` helper on the
`record_plunder` pattern (an office bought outright breeds claimants;
`too_many_claimants` already says so). Crossing the Rubicon —
`Game.declare_civil_war()` for a great house that would rather strike first,
gated on `popular_standing`, setting `at_civil_war` and then
`SenateRules._declare_civil_war`. AI defiance — a `defiance` persona field and
`ai.defy_senate_ratio`, judged against the round's strength snapshot. Then
proscriptions and army defections once a war is on, and AI canvassing.

**Phase 3 remainder — the sea.** Fleets move and watch but never fight;
`blockade_port` missions are authored and allowlisted. The corvus technique and
its **Boarding Marines** (the first `requires_technique` unit) were written as
the hook for exactly this slice.

**The optional online narrator.** The chronicle is already the
machine-readable feed (`schemas/chronicle_entry.schema.json`,
`ChronicleRules.resolved()`), rendered offline by `data/annals.json` templates.
An optional online narrator — prose only, never state — exports resolved
entries, asks a model, and renders the result with the templates as fallback.

**Real-time battles.** Everything funnels through `BattleResolver.resolve(...)`;
a battle scene is a drop-in second implementation, and the animated replay
already reads the round log it would produce.

## 9. Process notes

- **Branch from `main`, merge back to `main`, delete the branch.** This is the
  rule the repository did not have, and §1 is the bill: eight sessions forked
  the same commit, none merged, and every build shipped one session's work
  while the owner reasonably assumed it shipped all of it. Before starting,
  `git fetch origin main && git checkout -b <branch> origin/main` — never fork
  whatever the container happened to clone. Before finishing, merge to `main`
  and push it. A branch that outlives its merge is sprawl.
- **Check for forks before you build anything.**
  `git branch -r` plus `git rev-list --count origin/main..<branch>` for each
  takes ten seconds and tells you whether someone else has already built what
  you are about to build. Three separate AI implementations and three map
  renderers existed here because nobody ran it.
- **Never resolve a prose conflict by keeping both sides.** A merge that
  concatenates two docs produces a document that contradicts itself, and it
  will be believed. Read both, decide which is true of the merged tree, and
  write that. `ddf5f51` is what it costs to clean up afterwards.
- **Git identity must be `noreply@anthropic.com` / `Claude`** before committing,
  or a stop hook flags the commits as unverified and they need re-authoring.
  Develop on whatever branch the session assigns and push to `origin`; CI runs
  the two gates on every push.
- **Run adversarial review agents after anything substantial.** Three
  reviewers, each with a distinct lens (determinism & save-compat;
  data/schema/clean-room and historical fidelity; balance, exploits & AI
  behaviour), findings-only output, told to verify every claim in code. Phase 4
  found 37 real issues the tests had missed; Phase 5+6 found 28; the map round
  found 15; the Deep Strategy round found 24 — including the senate overwriting
  `popular_standing` (which had made every edict tension dead code), a free
  enact→repeal standing mint, the AI freezing on the four cheapest edicts
  forever, and two epithets that were provably unreachable. **Budget a fix
  commit after each round.**
- **Verify a reviewer's mechanism before acting on it.** The window-size bug in
  §5.13 was reported with a diagnosis that contradicted the API docs; a ten-line
  in-engine probe settled it (the reviewer was right, the doc reading was
  wrong). Cheap to check, expensive to get backwards.
- **A new rules module needs tests in `tests/`**, and a new data table needs a
  schema *and* cross-reference checks in `tools/validate_data.py`. Both gates
  before committing.
- **Balance changes want a soak, not just the suite.** The harness asserts
  invariants; the soak shows character. The first AI soak looked perfectly green
  while producing a world of shopkeepers with zero wars.
