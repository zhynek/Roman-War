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
integration of five of those branches, Phase 7 on top of them, and the military
strategy layer on top of that (PR #2, fast-forwarded into `main` on 2026-09-05),
and is the only branch worth building.

**Why sessions keep forking the wrong commit:** GitHub's *default branch* for
this repository is still `claude/new-session-3g3s4m` — the old `9026730` — so
every new Claude Code session is cloned and branched from it unless somebody
switches. Two more sessions did exactly that after `main` existed (the two
"also superseded" branches below), and so did the session that wrote this
paragraph. The fix is a repository setting only the owner can make:
**Settings → General → Default branch → `main`**. Until then, the first command
of every session is `git fetch origin main && git checkout -B <branch> origin/main`.

**Merged into `main`, in this order:**

| From | What it brought |
|---|---|
| `modernize-map-world-view` | The base. Layered terrain renderer, real coastlines and polygon provinces, iconography, hover/tooltips, movement range and route preview, info cards, the animated battle view, pathfinding, multi-turn march orders |
| `game-decision-tradeoffs` | The society engine (legitimacy, grievance, belonging, elite pressure, martial ethos, craft), provincial edicts, crisis events |
| `daily-campaign-turn-sequence` | The turn journal, the fog-filtered end-turn sequence, the Daily Dispatch |
| `building-details-upgrades` (contains `ai-opponents`) | The modular AI, the guided campaign trail, the building yard and muster hall, 312 procedural building illustrations, the no-mouse camera |
| `project-handoff-familiarization` | Campaign agents and a real negotiation model, the knowledge/technique engine, the chronicle and epithets, AI personas |
| `roman-war-next-phase` (2026-09-02) | Phase 7, the cursus honorum: Senate offices and elections, seats that absorb Ambition, the Senate's demand, outlawry, a civil war with sides and an end, the Senate scroll, journal beats, a trail stage; the world seed persisted, the version stamp, the duplicate `class_name` removed |
| `military-strategy-gameplay` (2026-09-05, PR #2) | The military strategy layer: unit-class counters, the RNG-free battle estimator with odds and named factors, kit from armouries and drill, the casualty and rout model, garrison quality / levy strain / war mood in public order, warcraft techniques folded into the knowledge engine; `docs/MILITARY_STRATEGY.md` |
| `roman-war-gameplay-review-ou72vk` (2026-09-05, **ported by hand**, not merged) | Phase 9, army command: `ForceRules` (raise under a chosen leader, transfer, merge, split, disband, attach/detach generals, consolidate — movement conserved through transfers), `NavalRules` and harbours (ships finish in port; launch, dock, merge, split), attacks and sieges that cost the season, banners on the map with left-click select / right-click order, the force card, garrison and harbour tick rows. Rewritten against the trunk's retained-layer renderer, `PathfindingRules` and facade; plus the two-row header that ended the cut-off screen and the Options menu |

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

**Also superseded: `next-roadmap-phase-rjxwas`** (six commits, 2026-09-03/04,
forked from `9026730`). A *fourth* implementation of Phases 5 and 6 — its own
`AiController` and four behaviours, `data/ai_personalities.json`, its own
agents table and negotiation model — written after `main` already carried the
modular AI, the agents and the negotiation scroll. A dry-run merge onto the
trunk conflicts in 125 paths (`git merge-tree --write-tree origin/main
origin/claude/next-roadmap-phase-rjxwas`). Its review commits did find real
rules — a peace kept for `min_peace_turns_before_war` seasons, armies that
never park under walls they cannot storm, debt shedding the costliest unit down
to a floor — and each is worth checking against `main`'s AI as an idea, not as
a file. Nothing else to take.

**Ported, not merged: `roman-war-gameplay-review-ou72vk`** (fourteen commits,
2026-09-05, forked from `9026730`; head `4293616`). It did not know `main`
existed — its Phase 9, army command, was written against the old map renderer
and the old facade, and a dry-run merge conflicted in 81 paths — so on
2026-09-05 its rules were re-implemented on the trunk by hand
(`src/core/rules/forces.gd`, `src/core/rules/naval.gd`, the facade's regroup
block, `src/ui/panels/force_panel.gd`, the banner layer in `map_view.gd`, the
tick rows in `region_panel.gd`; `tests/test_forces.gd`, `tests/test_naval.gd`,
`tests/test_ui_forces.gd`). DESIGN §6.1, §6.3 and §6.4 describe what landed.
Three decisions worth knowing, because the branch decided them differently:

- **The stack cap stays `balance.recruitment.army_unit_cap`** (`ForceRules.
  max_units`); the branch had its own `forces.max_units`. The only new balance
  key is `forces.disband_population_return_pct`.
- **"An attack costs the season" lives in `Game.attack_army` only.** The AI
  attacks through `CombatRules.attack_army` and pays nothing — deliberately,
  so the 60-turn campaign harness and the AI's tuning were left untouched.
  Close the asymmetry in `AiMilitary` when the AI is next worked on; it is a
  known gap (§7).
- **Multi-turn marches are the trunk's** (`PathfindingRules`); the branch's
  one-step `reachable_regions` was rebuilt on top of them
  (`Game.reachable_regions` → `{reach: {id: {cost, forced}}, blocked: {id:
  reason}}`, seen through the owner's fog, and answering for the player's
  own forces only).

The port's own adversarial round (three reviewers, thirty findings, the
engine's eleven and the UI's ten closed the same day; the engine ones are
pinned in `tests/test_army_command_review.gd`): fatigue laundered through a
garrison, ships docking for free by transfer, sieges laid past a not-yet-
hostile relief army, assaults and cross-border attacks costing no step,
armies walking into an invested city, legacy ships marching in field armies,
a merge lifting a siege, a bribe leaving a ghost siege, a ceded port's ships
changing hands, the two raise buttons granting different movement, the query
surface answering for foreign forces; and in the UI a right-click that could
take ship where the rings showed a road, a red ring on the army's own
province that opened the dossier instead of striking, the selection not
following a marching army across End Turn, the force card opening off-screen
under a restored scroll offset, Tab eaten by focused dropdowns, and a yard
re-rendered for the wrong city.

Its **review report** (`docs/reviews/2026-09-codebase-review.md` on the
branch: 124 deduplicated findings against `9026730`, 24 verified) was not
ported. Most engine findings predate `main`'s rewrites; the balance findings
(income snowballs, order at 150–220 % in core cities, extermination
dominating, huge cities unreachable) may or may not survive the society
layer — re-probe on `main` before acting on any of them. The branch can be
deleted once nobody needs the report.

**The military strategy layer** (from `claude/military-strategy-gameplay-ecnngs`,
reconciled onto the trunk on 2026-09-03 as PR #2, but only fast-forwarded into
`main` on 2026-09-05 — for two days `main` sat one merge behind the branch that
described itself as merged) sits on top of all of it: unit-class counters and per-class
terrain/walls in the RNG-free `BattleResolver.estimate()` (odds before every
attack, a battle report naming the deciding factors), weapon/armour kit from
armouries and drill, the casualty and rout model, garrison quality / levy strain /
war mood in public order, and **warcraft techniques** — the doctrines that branch
had built were folded into the knowledge engine as `data/techniques.json`
records with a `war` block and war-record prerequisites, so there is one
research model, not two. `docs/MILITARY_STRATEGY.md` is the player-facing guide;
DESIGN §6.5–6.8 the spec.

**Green on `main`:** 469 tests across 46 test files (0.11.0 — the Phase 9
port added `test_forces`, `test_naval`, `test_ui_forces`,
`test_army_command_review` and thirty assertions elsewhere), validator
0 errors / 0 warnings across 33 data tables, clean boot — re-run on
2026-09-05 before the fast-forward. One assertion is machine-bound: `test_ai_campaign.gd`'s 600 ms
per-turn guard (§5.12). PR #2's author measured 514 ms on the merge against
476 ms for the trunk before it; the 2026-09-05 container measured 606 ms quiet
(748 ms slowest turn) against 538 ms for `d98484d`, and 676 ms with a download
competing for CPU — so the suite there reported 414 tests / 1 failure with
every functional assertion passing, and that line is the whole failure. The
exported release build's first turns run at ~390 ms. If the guard trips on
GitHub's runners once Actions executes again, make it relative to a
calibration loop rather than raising the number.

**Phase 7 — the cursus honorum — was merged into `main` on 2026-09-02** (from
`claude/roman-war-next-phase-8ef54h`, branched at `2c9b602` per §9, six commits).
Senate offices and summer elections, seats that absorb Ambition, the Senate's
demand for a patriarch's life, outlawry, a civil war with sides that can never
be talked away and ends when the Senate falls, the Senate scroll, five journal
beats and a trail stage — `docs/DESIGN.md` §8.1 is the account. It also
carried the trunk fixes that were waiting: the world seed persisted and shown
(§4), the build version on the start menu, a dead duplicate `class_name` that
broke every suite on a fresh cache (§5.17), and a UI smoke test that had been
silently truncated.

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
godot --headless --path . --script res://tests/run_tests.gd   # 469 tests, 0 failures
godot --headless --path . --quit-after 5                      # boots clean: no errors after the version banner
```

The suite takes several minutes — `test_ai_campaign` (60 AI turns, replayed,
then save-and-resumed) and `test_society_longrun` dominate it, and it prints
nothing until it finishes, so a quiet terminal is not a hang.

> **GitHub Actions has executed nothing since 2026-09-03 01:16 UTC.** Every run
> since — on every branch, PR #2 included — fails two seconds after creation
> with no runner assigned and no logs (`runner_id: 0`, no steps). The workflow
> is unchanged; that is the account's Actions availability (a spending limit or
> a billing problem), which only the owner can fix in GitHub's billing settings.
> Until a run actually executes again, the gates are local-only and a red check
> on GitHub means nothing either way.

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
`building_info`, `army` — composition, slot shares and roles for the battle
model), with the AI in `rules/ai/`
(`faction_ai` orchestrates → `ai_diplomacy`, `ai_assess`, `ai_military`,
`ai_economy`, `ai_strategy`, `ai_policy`, `ai_politics`, `ai_rules` for personas) and battle
behind `rules/battle/battle_resolver.gd`.

**UI** (`src/ui/`) — every panel talks only to the facade:

| Panel | Facade methods |
|---|---|
| `campaign_screen.gd` (the shell) | `end_turn`, `day_beats`, `move_army`, `march_army`, `sea_move_army`, `sail_fleet`, `dock_fleet`, `attack_army`, `besiege`, `assault_settlement`, `disband_unit`, `force_summary`, `reachable_regions`, `targets_for`, `reachable_zones`, `forces_awaiting_orders`, `guided_enabled`/`set_guided`, `move_agent`, `agent_scout/_assassinate/_bribe/_steal_technique`, `visible_regions`, `victory_progress`, `save_to`, `load_from`. Selection is hoisted here (`selected_army`, `selected_fleet`, `selected_agent`; `select_force`, `deselect`, `cycle_selection`); a LEFT click selects, a RIGHT click with a force selected is `_on_order_target` |
| `panels/force_panel.gd` (the force card) | `force_summary`, `check`, `transfer_units`, `merge_armies`, `split_army`, `attach_general`, `detach_general`, `consolidate_units`, `merge_fleets`, `split_fleet`, `dock_fleet`, `own_ports_on_zone`, `candidate_generals`, `reachable_regions`, `reachable_zones`, `garrison_army`, `halt_march`, `battle_estimate`, `assault_estimate`, `mercenaries_available`, `hire_mercenary`; every refusal comes back as an error code the screen explains through `ForcePanel.explain` |
| `panels/region_panel.gd` (the biggest) | `growth/order/income_breakdown`, `available_buildings/units`, `queue_building/unit`, `demolish_building`, `set_tax_level`, `retrain_garrison`, `raise_units`, `raise_army`, `transfer_units`, `launch_fleet`, `candidate_generals`, `move_capital`, `recruit_agent`, `agents_in`, `set_edict`, `revoke_edict`, `available_edicts`, `edict_status` — the garrison and harbour are tick rows |
| `panels/diplomacy_panel.gd` | `pending_offers`, `respond_offer`, `declare_war` — fleets left this scroll for the map |
| `panels/negotiation_dialog.gd` | `preview_offer`, `propose_offer` |
| `panels/family_panel.gd` | `family_of`, `character_sheet`, `set_heir`, `transfer_ancillary` |
| `panels/senate_panel.gd` | `senate_overview`, `comply_senate_demand` — the one act the scroll takes |
| `panels/knowledge_panel.gd` | `technique_overview` (with the war record, moods and warcraft `war` blocks), `begin_adoption` |
| the battle seam | `battle_estimate`, `assault_estimate`, `army_summary`, `recruit_profile` — the region panel's odds line, assault button and recruit rows; `campaign_screen.gd` confirms every attack and storm with `RegionPanel.odds_text` and logs `_log_battle` |
| `panels/annals_panel.gd` | none — renders `state.chronicle` through `data/annals.json` |
| `panels/quest_panel.gd` | the guided trail's objectives and rewards |
| `panels/build_drawer.gd`, `panels/info_card.gd`, `panels/map_context_menu.gd` | the building yard / muster hall, the illustrated cards, the right-click dossier |
| `turn_sequence.gd` + `dispatch_panel.gd` | the day's playback and its recap, over `day_beats` |

**Tests** (`tests/`, 46 files over `tests/fixtures.gd`, a synthetic world that
loads the real `balance.json`). Formula units: `growth`, `economy`,
`public_order`, `construction`, `recruitment`, `battle`, `battle_log`,
`movement_visibility`, `pathfinding`, `characters`, `forces` (regrouping and
movement conservation), `naval` (harbours, launch/dock). Systems: `agents`, `senate_politics`,
`diplomacy_offers`, `diplomacy_war`, `ai`, `knowledge`, `edicts`, `chronicle`,
`society`, `legibility`, `advances`, `guided`, `turn_journal`, `dispatch`,
`events_vocabulary`. Presentation: `map_geometry`, `map_menu`, `illustrations`,
`building_art`, `unit_art`, `info_cards`, `battle_screen`, `profiles`,
`building_info`. Integration: **`test_ai_campaign.gd` is the tripwire** —
60 AI-driven turns asserting the map changes hands, byte-identical replay from
one seed, and save-at-20/resume-in-lockstep. `test_ui_smoke.gd` and
`test_ui_forces.gd` drive the real screen headless (banners, picking, the
left-select / right-order grammar, the force card and the regroup rows);
`test_society_longrun.gd` is the slow shape check.

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
19. **Military-layer determinism.** Every merge of technique `war` blocks
    iterates sorted ids (`KnowledgeRules.war_effects`), `war_record.faced` is
    written in sorted class order, and the estimator's per-unit stages run in
    array order; the auto-resolver draws exactly two fortune rolls, one scatter
    per unit (from the back, so removals are safe) and the loser's one
    general-death die — `test_battle_log.gd` pins that count. A **walkover**
    (a side with no strength) draws nothing at all.
20. **New per-entity keys go into `NewGame.build` AND `ensure_state_keys`.**
    `war_record` / `war_mood` (factions) and `levy_strain` (settlements) are
    the latest. A key normalized on load lands at the END of its dict while a
    live game holds it where `build` wrote it, so a lockstep test that
    compares upgraded saves must compare key-order-insensitively
    (`test_pre_warcraft_save_is_normalized` sorts keys); the plain
    save-and-resume tests never see the difference because a save carries
    every key.
21. **Warcraft techniques are heard of before they are adopted**, like every
    other craft: a court originates them (by `origin_cultures` and the
    prerequisites, including the war record), hears of them by contact or
    conquest, or steals them — a `factions`-closed tradition spreads to nobody
    else (`KnowledgeRules.open_to` guards origination, diffusion, conquest and
    adoption). The 270 BC endowments are `start_adopted.factions`; there is no
    separate doctrine list on the faction any more, and `data/doctrines.json`,
    `DoctrineRules` and the Reforms scroll were retired in the merge.
22. **Unit arming is one convention:** `weapon` / `armor` 0..`recruitment.upgrade_max`
    (+1 with `upgrade_cap`) stamped at recruit time from `SettlementRules.effect_total`
    (summed across forges and armouries) plus `KnowledgeRules.faction_effect_total`,
    read in battle as `battle.weapon_upgrade_attack_pct` /
    `armor_upgrade_defense_pct` per level. `NewGame._units` and every creation
    site write both keys (0 when unarmed).
23. **The demand template has no `min_year`, on purpose.**
    `the_senate_demands_your_life` shipped with `min_year: -60`, unreachable in
    any campaign a playtester will finish. The greatness gate
    (`leader_suicide_standing` / `leader_suicide_popular_min`) replaced the
    calendar gate; do not put the year back.
24. **The UI's whole world is a 1280×800 canvas.** `project.godot` stretches
    that canvas to the window (`stretch/mode=canvas_items`, `aspect=expand`),
    so a 1440×900 laptop shows exactly 1280×800 canvas pixels and a 1920×1080
    one 1422×800. Any control tree whose *minimum* width exceeds that overflows
    the window — no scrollbar, no clipping, the right-hand part is simply gone.
    The old one-row top bar had a minimum of ~2000 px, which is why the 0.10.0
    build showed the bar cut off after "Diplomacy" and the side column
    off-screen. The header is two wrapping `HFlowContainer` rows now, and
    `test_the_top_bar_fits_a_narrow_window` pins the root's minimum width
    under 1000 px. Anything added to the header must wrap or stay short.
25. **`tools/screenshot.gd` sizes its holder in canvas units**
    (`root.get_visible_rect().size`), not `root.size` (window pixels). With
    the pixel size it drew a grey margin on small windows and pushed the side
    column off large ones — an artefact the game never shows. Read a shot
    against that before diagnosing a layout bug from it.
26. **Godot 4.4 GDScript refuses `Rect2 + Vector2`** at parse time (and the
    whole class with it — see 7). Offset a rect by writing its `position`.

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
- **Delivery caps at 30 MiB**, so `tools/thin_macos_arm64.py` extracts the
  arm64 slice from the Mach-O fat binary (fat magic `0xCAFEBABE`, `cputype
  0x0100000c`), refuses to write unless `LC_CODE_SIGNATURE` (cmd `0x1d`)
  survives in the slice — without it the app will not launch — and re-zips
  preserving the original entry modes.
- **Verify the package plays** before sending: the Linux export shares the same
  `.pck`, so `./RomanWar.x86_64 --headless --script res://tools/build_probe.gd`
  (the probe is packed with the game) counts the data tables, starts a
  campaign, ends five turns, round-trips a save and checks the loaded game
  marches in lockstep with the live one, exiting nonzero on failure.
- **Builds delivered so far:** `97cabfd` — the old `9026730` line, Phases 0–4
  and the first campaign UI, no version stamp — on 2026-08-23; **`0.10.0`,
  the first build of `main`** (the integrated trunk plus the military layer),
  on 2026-09-05; and **`0.11.0`** the same day — army command (banners, the
  force card, regrouping, harbours), the header that fits the window, and the
  Options menu. Every playtest report from before 2026-09-05 is about the old
  line, not about anything in the table above. The first feedback on 0.10.0
  was the cut-off screen (§5.24) and "how do I switch the mode" — both fixed
  in 0.11.0.

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
  fleet banners, the sea-zone click target and sea labels; no zone is a
  first-class map object.
- **The AI's attacks pay no movement.** `Game.attack_army` (the player) needs
  movement left and spends it all; `AiMilitary` goes through
  `CombatRules.attack_army` and does not. Decided deliberately when Phase 9
  was ported (§1) so the AI harness stayed untouched; close it in `AiMilitary`
  and re-run `test_ai_campaign` (the 600 ms guard) when the AI is next tuned.
- **The AI builds no ships and uses no harbour.** `AiEconomy._recruit` skips
  the `ship` class; the only AI fleets are the campaign's starting ones.
  Harbours, launching and docking are player-only until the sea phase.
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
- **AI houses press the Senate's courtship charges now, but cannot buy the
  answer.** `AiDiplomacy._pursue_charge` sends the envoy a charge names
  (alliance or trade) every turn the charge stands; the target's attitude
  decides, so a hated neighbour still fails it. On `main` no AI house ever
  proposed an alliance, which had sunk every house to −7…−10 by turn 80 and
  made every civil war everyone-against-the-Senate. Sweetening a refused suit
  with silver is the next slice; do not paper over it with the join threshold.
- **The Senate can die of its own grievance, and the Republic's politics with it.**
  In two of five soak seeds the Senate falls by turn 80–85 without a civil war:
  its custodial AI takes rebel provinces across the sea (Spain, Crimea,
  Cyrenaica), loses its armies there, and the society layer's unrest machine
  takes the provinces — Rome itself in seed 1234 — to the rebels while
  Latium's order total still reads above 100 (`in_revolt` at grievance −30,
  legitimacy `standing` −11 after sixty turns of `coercion` +25). Pristine
  `main` survives the same five seeds, so this is the world shifting under a
  fragile faction, not a rule Phase 7 added; but once the Senate is gone the
  offices dissolve, no charge is issued, no house can break, and the long
  campaign's civil-war condition is met for free. Two contained slices: keep
  the Senate's field army home (`AiAssess` target scoring for the custodial
  persona), and look at why the Senate's legitimacy sinks in its own capital.
- **The player cannot join a rebellion.** A player house is never conscripted
  into another's civil war (it stands with the Senate unless it is the rebel);
  a `Game.join_rebellion()` act is the follow-up beside crossing the Rubicon.
- **Offices are Roman-only.** Other cultures drain Ambition by government tiers
  alone (DESIGN §4.4); a Hellenistic court or a tribal assembly has no ladder.
- **Phase 3 remainder**: embark-on-fleet transport (sea movement is an
  abstracted crossing today), naval battles, port blockades, forts and
  watchtowers, ambush. The `ship` class has no matchups (no naval battles yet).
- **Military layer edges.** Technique `escape_pct` / `pursuit_pct` are
  side-wide (the Parthian shot speeds the whole army's escape, not only the
  horse archers); the AI plans with `force_strength` (now the estimator with no
  opponent, class mass included) but does not read `estimate()` against a
  specific foe or recruit to counter what it has faced (`war_record.faced`);
  the counter matrix, `mass`, the per-level kit percentages and the warcraft
  costs have had no playtest tuning; and the 33 warcraft records nearly double
  the technique table, which dilutes the one-pick-per-success origination draw
  for civil crafts — a per-technique origination weight is the contained fix
  if soaks show civil crafts arriving late.
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
value, wall discounting); attacks judged by `BattleResolver.estimate` against
the actual defender (the odds the player sees) and recruitment that answers
the counter matrix and the arms it has faced; and either wiring or deleting the
objective machinery above. Keep every knob in data, keep it deterministic, and verify with long
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
`ai.defy_senate_ratio`, judged against the round's strength snapshot. Joining a
rebellion by choice — the player's counterpart of `house_joins_rebellion`. Then
proscriptions and army defections once a war is on, and AI canvassing.

**Phase 3 remainder — the sea.** Fleets move, dock, launch and regroup now
(harbours, `NavalRules`) but never fight and carry no armies; `blockade_port`
missions are authored and allowlisted. The corvus technique and its **Boarding
Marines** (the first `requires_technique` unit) were written as the hook for
exactly this slice, and the harbour is where an embarked army would board.

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
  whatever the container happened to clone (it clones GitHub's *default
  branch*, which is the old `9026730` line until the owner switches it to
  `main`; §1). Before finishing, merge to `main` and push it — and check that
  `main` actually moved: the military layer sat two days in an open PR whose
  own handoff said "merged". A branch that outlives its merge is sprawl.
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
- **Effect keys must have readers.** The validator fails on any building or
  technique effect key in a schema's closed vocabulary that no code under
  `src/core` reads as a quoted literal (comments do not count); add the reader
  before the data, or list the key in `FORWARD_EFFECTS` deliberately.
- **The unit-class counter matrix** is authored so any pair's two multipliers
  multiply to 0.85–1.15 (the validator warns otherwise); the net counter is
  their ratio. In `docs/MILITARY_STRATEGY.md`, `tools/military_guide.py`
  regenerates the odds table and the warcraft catalogue (§6) from the data; the
  matrix, ground, wall, kit and chain tables of §§2–5 were generated once from
  the same tables and must be refreshed by hand after retuning. Mounted and beast
  classes carry a `mass` (cavalry 2, elephants 8 …) because the roster's
  per-man stats on 60-man cards would otherwise make a squadron a third of a
  phalanx; tune mass before touching 92 unit templates.
- **`data/campaign.json` is `indent=2` JSON with no trailing newline;
  `buildings.json` and `units.json` are ASCII-escaped `indent=2` with one.**
  `json.dumps` with the matching options round-trips them byte-for-byte, so
  scripted edits keep diffs small.
- **Balance changes want a soak, not just the suite.** The harness asserts
  invariants; the soak shows character. The first AI soak looked perfectly green
  while producing a world of shopkeepers with zero wars.
