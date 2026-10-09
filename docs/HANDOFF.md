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

## Local integration with advisor development — October 8, 2026

This local checkout combines the waterways phase described below with the
existing Marcus/Lucius advisors, seasonal council, divine patronage and private
launcher. Naval changes were developed and verified from `origin/main`; the
advisor work remains on the local advisor branch. The detailed advisor milestone
records are preserved in [the handoff history](HANDOFF-HISTORY.md#advisor-development-before-local-waterways-integration).

The advisor branch's outstanding provider permission remains outstanding:
ElevenAgents Read cannot mint signed sessions without `convai_write`; do not
broaden provider access without the user's answer. The naval work does not
change that integration or its private credentials.

## Waterways and shipping — October 8, 2026

The parent campaign now has player-issued multi-season fleet routes, river
landings and transport flotillas, buildable river bridges, troop embarkation and
landing, recurring trade deliveries, and resolver-based automatic naval
encounters. Existing port construction supplies maritime endpoints. The Tiber,
Nile and Danube are data-authored overlays; coast/open-water route choices and
seasonal ETA appear in the fleet panel and on the map. See
[controls, rules, architecture and direct evidence](WATERWAYS.md).

New saves remain version 2 with additive waterworks/fleet fields. Carried armies
leave the land index but retain identities, general lifecycle and upkeep. Direct
army sea teleportation is disabled; unopposed amphibious landings require ships.
Bridge state feeds shared terrain rules and AI land paths. No AI naval strategy,
blockades, tactical naval scene or independent village changes are included.

The work started from current origin/main in an isolated checkout to preserve
unfinished advisor/patronage work. Data validated with zero errors/warnings;
Godot import and rendered planning/sailing/arrival/max-zoom/bridge/trade inspection
completed. Parsed live/resumed campaign state matched after a carried voyage.

Verified by: data/schema validation, Godot import and an isolated rendered shipping walkthrough. Tests: not run (weekly review policy).

## Weekly testing policy — adopted October 8, 2026

`AGENTS.md` now carries Zach's shared weekly review policy, which takes
precedence over older test-before-handoff instructions. The sole Actions
workflow is `.github/workflows/weekly-tests.yml`: Mondays at 13:00 UTC and manual
dispatch, with no push or pull-request trigger. It retains full parent/village
data and headless gates and failure evidence. Do not poll CI after a push.

The integration checks below were explicitly requested and completed before this
policy arrived. Further repeated verification and CI monitoring were stopped.
The redundant final render repetition was interrupted and is not a completed
gate; its earlier completed walkthroughs remain the evidence. The inherited
parent hosted timing failure remains open with its 600 ms guard unchanged.
No speculative performance candidate was merged. No release was built.

Verified by: Ruby/Psych parse of weekly-tests.yml and direct trigger inspection. Tests: not run (weekly review policy).

That line applies to the policy/workflow change; the earlier requested test
results are recorded separately in the integration verification.

## City progression and warfare integration — October 2026

The city-progression audit (`8589fe9`) and the complete warfare checkpoint
(`5e4a441`) were merged as `a88ca25`, preserving the civic/service factor split,
shaping-suspension explanation and every local defense change. Implementation
commits `7024feb`, `4ab4811` and `ad38185` add authoritative parent knowledge
explanations, the combined village fixes, reproducible measurements and village
CI gates. Read the [per-finding audit follow-up](reviews/2026-10-city-progression-coherence-audit.md),
[combined plan](reviews/2026-10-city-warfare-integration.md),
[implemented tutorial log](TUTORIAL_WALKTHROUGH_LOG.md) and
[source verification record](reviews/2026-10-city-warfare-verification.md).

The legacy achievement says **Town support** when lifecycle is active. Reserve
priority, Town civic/service staffing, real equipment/repair consumers and
illustrative household practice are explained. Watch practice and additional
home watch have separate factors without changing totals. Provision service is
discoverable from Homes and Stores without changing its published owner or hash.
**How to play** has eleven data-driven lessons; explicit adoption stays separate.
The default reserve and workforce priorities are unchanged. Paid 0.11 saves and
published profile hashes are preserved; warfare is wrapper 10 and does not
require lifecycle. Parent `BattleResolver` and campaign rules are unchanged.

Town remains the highest playable civic rank. Warfare adds local preparation,
paid defenses, recurring threats and recovery, without recruitment, conquest,
Large town or a parent-campaign bridge. Measured equipment/training reduced
recovery, and maintained screens shortened the matched fight without guaranteeing
fewer wounds. Mature Town still refills food in one season: warfare does not solve
the surplus-food or civic-ceiling gaps. All measured recipes use public commands.
No integration release or export was built. Launch updated source using the
verification record; the earlier 0.14 local app is unchanged.

## Village warfare 0.14.0 local milestone — 2026-10-08

All four phases extend the preserved `codex/village-defense` work, checkpointed
as `5e4a441` before integrating the city-progression audit.
No parent campaign engine or BattleResolver changes. The independent warfare
profile is explicit adoption (wrapper10); older defense/lifecycle/town profiles
retain their original hashes. See [WARFARE.md](../Castles%20and%20Cities/sites/yenikapi_6000_bce/experience/WARFARE.md)
for architecture and [the controls guide](../Castles%20and%20Cities/sites/yenikapi_6000_bce/experience/WARFARE-CONTROLS.md).

Tactical groups navigate actual paid village geometry with spacing, filing,
yielding, facing, fatigue, morale, observed contacts and bounded objectives.
Two paid low woven screens preserve open ordinary entrances and derive protection
from existing watch maintenance. Five saved plan positions and finite additional
watch requests use ordinary construction and workforce systems. Three repeating
threats have warning seasons, resource/recovery deferral and eight quiet seasons
after acceptance. Direct, delegated and quick modes share fixed ticks and
serialized orders; quick progress/cancellation is resumable and rendering is
suppressed only during batching.

Named reports persist injury/care seasons, actual kit losses and paid repair,
engaged combat experience, household stress and participation history. Finite
care and missing adults affect ordinary work. Outcomes commit exactly once;
combat incapacitation remains recoverable and natural lifecycle history remains
intact. The normal interface retains aftermath, care and equipment controls.

Final delivery evidence belongs in
[VERIFICATION-WARFARE.md](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-WARFARE.md),
including complete village/parent gates, rendered map/control checks, exact-app
verification, timings, local launch instructions, frozen source and checksums.
QA images stay outside the repository. That local delivery did not replace an
existing release. The subsequent integration task authorizes source commits and
a push to main after verification, but no release build or publication.

## First village defense (local 0.13.0, October 2026)

**Defend the village** integrates actual home-watch adults and existing wooden
kits with one fictional live supply-raid scenario. Preparation, deployment,
seven spatial orders, pause/speed, independent worker ticks, active saves,
exactly-once reports and seasonal injury/kit/supply recovery form one continuing
loop. Practice uses a detached copy. Parent BattleResolver and campaign saves
remain unchanged; village adoption uses wrapper 9 and preserves older profiles.
Read [DEFENSE.md](../Castles%20and%20Cities/sites/yenikapi_6000_bce/experience/DEFENSE.md)
and [the delivery verification](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-DEFENSE.md).

## Sites, plans and village oversight (0.10.0, October 2026)

The village derives partial structures, committed-material piles, status icons and
physical plans from the existing project queue and finite asset allocator. The
shared working room hosts an explicitly interpretive board/easel; site, dock and
room open the same authoritative review and controls. No new economy, save wrapper
or historical claim. Paused sites and their paid investment survive both incidents,
including save/load replay. Read [CONSTRUCTION.md](../Castles%20and%20Cities/sites/yenikapi_6000_bce/experience/CONSTRUCTION.md)
and [0.10 verification](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.10.md).

Numeric footprint comparison avoids needless full builds. Actual footprint changes
patch local terrain and retain unchanged buildings; collision-valid cached routes
are reused. Cold-build geometry equivalence and full path walking guard this seam.
The release builder adds exact-app construction acceptance and five separate model
specimens while retaining every earlier gate and 36 prior model bytes.

Frozen payload `60d9106` passes **13,006 assertions** on both source and the exact
universal Mac app; **185 captures** were inspected, including 34 construction
views and 672 actual-input checks. Parent data, **705 tests** and map rendering
pass. All 36 retained GLBs are byte-identical; five new specimens bring the total
to 41. On the local M3 Max, comparable adaptation completion fell from 3.062 s to
0.668 s. New-building completion remains 1.452 s; commissioning rose to 0.509 s.
The verification record reports every measured operation and remaining limits.

The [0.10.0 prerelease](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v 0.10.0) is public. All twelve anonymous downloads match
tested bytes and GitHub digests; all ten ZIPs pass integrity checks. All fifteen
previous releases / 97 assets and stable latest `v0.14.2` remain unchanged.
The tag pins the frozen payload; main also holds the acceptance/publication record.

## A Town That Works (verified local 0.12.0, October 7, 2026)

Slice C continues the existing large village through a paid alteration of the
assembly shelter into a civic house. Town unlocks separately paid material
preparation and local provision. Two civic adults replace the earlier one; the
optional provision service needs another adult. Benefits stop under staffing or
store-maintenance shortages without erasing rank or paid work. No housing density,
new clock, project manager, compulsory trade or free promotion upgrade is added.

The original lifecycle profile/hash and wrapper 8 are retained. Explicit town
adoption adds a separate semantic profile. Recognized older towns retain rank
and pay through missing civic fabric. Contacts, incidents, household relationships,
ordered fabric revisions and earlier land costs continue. Read
[LIFECYCLE.md](../Castles%20and%20Cities/sites/yenikapi_6000_bce/experience/LIFECYCLE.md)
and [0.12 verification](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.12.md)
for controls, compatibility, public-command fixtures and delivery evidence.

Frozen payload `b6e387d` passes **36,908 checks on source and exact universal Mac
app**, plus all parent data/import/**705-test**/map gates. Exact-app walkthroughs
pass **6,981 checks**; all **267 app and 82 source captures** were reviewed. The
87-command town UI recipe and all 60 fixture/recipe JSON files match exactly.
Both compact and outward public-command strategies sustain town through season 100.

The verified output is `build/yenikapi-early-settlement-0.12.0-local/`: app, editable
source, nine model archives, provenance, checksums and logs. All 11 ZIPs pass; all
41 retained GLBs match the verified 0.11 archives, with three new Town models.
The 0.11 build and all 16 published releases / 109 assets remain unchanged.
No public release was created; stable latest remains `v0.14.2`. The app is ad-hoc
signed, with both architectures verified and execution tested on M3 Max.

Village route reuse reduced matched source assembly commissioning from 2.01 s to
0.50 s. The exact app's town commissioning is 0.38 s, season refresh 1.13 s and
civic completion 0.98 s; material pauses remain. The parent CI 652 ms
failure occurred on the unchanged baseline; retain its 600 ms guard. Read
[the separate investigation](reviews/2026-10-ai-ci-performance.md). Timing
diagnostics now identify successful samples too; runner cause remains unproven.
Hosted [run 37705757701](https://github.com/zhynek/Roman-War/actions/runs/37705757701)
at `7153211` passed all 705 tests: AI average **378.933 ms**, peak **527 ms**, with
the unchanged 600 ms budget. This documentation-only follow-up records that pass;
it does not alter the frozen build or resolve future shared-runner variability.

## City lifecycle (0.11.0 local build, October 7, 2026)

[CITY_LIFECYCLE.md](CITY_LIFECYCLE.md) maps small village through metropolis.
Slices A+B now provide ordered building revisions, explicit site successors,
lifecycle adoption, sustained readiness, a paid assembly shelter and two separately
paid store/workroom improvements. The first civic transition is playable; later
stages are planned. Earlier land choices, people, resources, condition and paid
contracts continue. Legacy town achievement receives explicit recognition without
free civic fabric; the older town-support milestone remains unchanged.

Active lifecycle saves use wrapper 8, with a semantic profile hash and explicit
assets → land → living adoption requirements. Read
[LIFECYCLE.md](../Castles%20and%20Cities/sites/yenikapi_6000_bce/experience/LIFECYCLE.md)
for controls, authoring, save boundaries and isolated stage recipes. New data,
negative, rule/save, lineage and rendered gates are integrated into the clean-source
builder for source and exact app. Frozen payload `227eca3` passes **25,334 checks
on each**, plus the parent **705-test**/data/import/map gates. The exact app passes
**5,268 rendered checks**; all **214 app captures and 29 source lifecycle captures**
were reviewed. All 41 previous GLBs are byte-identical and ten ZIPs pass integrity
checks. Read [0.11 verification](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.11.md)
for artifacts, generated stage saves and measured scene-rebuild pauses. The local
universal Mac app is in `build/yenikapi-early-settlement-0.11.0-local/`; no public
release was created. The dated Yenikapı and medieval city studies remain separate.
Neighboring-city expansion follows local progression.

## Earlier Yenikapı releases (summary)

Each release below is a separately adopted chapter of the same independent
settlement; its full handoff narrative is in [the handoff history](HANDOFF-HISTORY.md)
and its evidence in its verification record.

| Version | Added | Record |
|---|---|---|
| 0.9.0 | Illustrated bottom dock, building improvements, growth guide | [VERIFICATION-0.9](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.9.md) |
| 0.8.0 | Warning, response and recovery incidents (wrapper 7) | [VERIFICATION-0.8](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.8.md) |
| 0.7.0 | Living village: woodland, preparation, household practice, watch kits (wrapper 6) | [VERIFICATION-0.7](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.7.md) |
| 0.6.0 | Land planning: compact vs outward homes, access upkeep (wrapper 5) | [VERIFICATION-0.6](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.6.md) |
| 0.5.0 | Asset governance: principles and the finite automatic allocator (wrapper 4) | [VERIFICATION-0.5](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.5.md) |
| 0.4.0 | Household life chapter (wrapper 3) | [VERIFICATION-0.4](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.4.md) |
| 0.3.0 | Neighboring communities: finite exchange and aid (wrapper 2) | [VERIFICATION-0.3](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.3.md) |
| 0.2.0 | Seasonal tutorial and the reversible town milestone (wrapper 1) | [VERIFICATION-0.2](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION-0.2.md) |
| 0.1.0 | The dated circa-6000 BCE reference village | [VERIFICATION](../Castles%20and%20Cities/sites/yenikapi_6000_bce/VERIFICATION.md) |

## Independent Constantinople city study

`Castles and Cities/` also holds the standalone **Constantinople circa 1200**
Godot project (latest 0.3.0, Pantokrator lanes and courts). It shares no
campaign code or saves. Start at its
[experience guide](../Castles%20and%20Cities/realms/byzantine_empire/cities/constantinople_1200/experience/README.md)
and [release builder](../Castles%20and%20Cities/BUILDING.md); the release
narrative is in [the handoff history](HANDOFF-HISTORY.md).

## Roma city development

**City-to-country navigation (October 2026).** Roma now opens in an aerial
survey, with scroll/pinch inspection and an outward transition into the shared
campaign. The map spans 0.18×–40× and offers **City / Countryside / Country**
framing plus explicit **Enter Roma**. Procedural settlement miniatures grow
their wards, completed buildings, walls and gates from public architectural
reports. The additive `settlement_memory` field preserves dated appearances
and ownership outside current sight; unseen troops remain governed by the
existing reconnaissance/forest rules. Geography treaties do not confer live
city intelligence. Street-level entry remains Roma-only; campaign miniatures
and Roma's authored district are distinct presentations of the same campaign.
Read the [city-to-country review](reviews/2026-10-city-country.md) and
[play guide](../PLAYING.md#one-campaign-city-and-map). The local universal Mac
preview, ZIP and frozen source are in `build/city-country-20261003/`.
Verified: **705 tests, 0 failures**, clean data/import gates, rendered
planning/marching/arrival/40× map acceptance, and the complete city-to-country
acceptance in both source and the exact exported Mac app.

**Current command phase (October 2026).** Roma battles now support battalion
splitting into three independent platoons, frontage dragging, explicit facing,
line/column/phalanx commands and directional combat. **Defend Roma → Formation
command drill** supplies trained hoplites, cavalry and archers for immediate
practice. Continuous battles still run through the deterministic worker, and
platoon survivors recombine into original campaign units through BattleResolver.
Old active battles retain their original rules. Read the
[command review](reviews/2026-10-siege-command.md) and
[play guide](CITY_BATTLES.md#formation-command-phase-october-2026).
Verified: **688 tests, 0 failures**, clean data/import gates, rendered map and
exact exported-app command checks. The universal `0.21.0-preview.20261003` app,
ZIP and frozen source are in `build/roma-tactics-20261003/`.


Earlier Roma previews (0.15–0.20: civic phases, live battles, unified campaign, fortress, swordplay) are summarized in [the handoff history](HANDOFF-HISTORY.md) and documented in their `docs/reviews/2026-09-roma-*.md` records.

## Current terrain and visual direction

**Current approved Mac standard: 0.14.2 — one Roman War app.** The owner
requested merging the campaign and Alpine Route apps. The start menu now
launches either mode, and Options → Return to main menu permits switching
without quitting. See [`releases/0.14.2.md`](releases/0.14.2.md).
Both published Mac save locations remain intact; a screen owns its save path,
so embedding the route never changes global storage. Custom test/preview
storage stays isolated. Release builds ship only the campaign/menu entry.
The two-app 0.14.1 release and earlier development checkpoints below are
historical, superseded by this merged release.

**2026-09-26 audit and Mac feedback build:** read
[`reviews/2026-09-26-release-audit.md`](reviews/2026-09-26-release-audit.md),
[`ROADMAP.md`](ROADMAP.md), and
[`releases/0.14.1-preview.20260926.md`](releases/0.14.1-preview.20260926.md).
The local preview includes the route work below, safer save replacement/backup
recovery, and a stale-hover fix. Use `tools/build_macos_playtest.py` for distinct
full-campaign and route apps; their identities, native versions and persistent
save folders are isolated from production. The older preview builder's mode
names no longer reliably distinguish its entry scenes. GitHub main and the
published production release remain 0.14.0. Actions now executes; its latest tag
run failed the fixed 600 ms timing guard at 603 ms, superseding the older
account-blocked warning later in this handoff.

Earlier route, terrain-preview and 0.14.0 production notes are in [the handoff history](HANDOFF-HISTORY.md).

## 1. Where things stand

**`main` is the trunk. Use it.** Until 2026-09-01 this repository had no `main`
at all: eight sessions each branched off `9026730` and none merged back, so
every build contained only that session's work and nothing else. That is why a
build could ship without the map you remembered writing. `main` now carries the
integration of five of those branches, Phase 7 on top of them, and the military
strategy layer on top of that (PR #2, fast-forwarded into `main` on 2026-09-05),
and is the only branch worth building.

**Default branch corrected:** GitHub now reports `main` as the default branch
(verified 2026-09-05 during the Codex map review). Older sessions branched from
`claude/new-session-3g3s4m` (`9026730`), which explains the superseded branches
below. Check `git status`, fetch `origin/main`, and create new work from that
trunk; do not reset an occupied worktree to recover from an old session.

**History.** How the trunk was assembled from eight parallel sessions in
August–September 2026, the merge table and the superseded branches are in
[the handoff history](HANDOFF-HISTORY.md). The superseded `claude/*` branches
with unmerged commits are preserved as `archive/claude/*` tags on GitHub.


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

The gates (see the weekly testing policy at the top of this file: during a
dev cycle verify the change directly; the full suite runs weekly in
`.github/workflows/weekly-tests.yml` and in the weekly review):

```sh
python3 tools/validate_data.py                                # 0 errors, 0 warnings
godot --headless --path . --script res://tests/run_tests.gd   # full suite, 0 failures (705+ tests in October 2026)
godot --headless --path . --quit-after 5                      # boots clean: no errors after the version banner
```

The suite takes several minutes — `test_ai_campaign` (60 AI turns, replayed,
then save-and-resumed) and `test_society_longrun` dominate it, and it prints
nothing until it finishes, so a quiet terminal is not a hang.

`pip install jsonschema` if the validator can't import. **Targeted test runs** use `-- suite=pathfinding,ui_smoke` after the runner
command (exact suite names, comma-separated). Omitting the filter runs every
`tests/test_*.gd`; the full suite remains the release gate.

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
| `campaign_screen.gd` (the shell) | `end_turn`, `day_beats`, `move_army`, `march_army`, `embark_army`, `disembark_army`, `sail_fleet`, `dock_fleet`, `attack_army`, `besiege`, `assault_settlement`, `disband_unit`, `force_summary`, `reachable_regions`, `targets_for`, `reachable_zones`, `forces_awaiting_orders`, `guided_enabled`/`set_guided`, `move_agent`, `agent_scout/_assassinate/_bribe/_steal_technique`, `visible_regions`, `victory_progress`, `save_to`, `load_from`. Selection is hoisted here (`selected_army`, `selected_fleet`, `selected_agent`; `select_force`, `deselect`, `cycle_selection`); a LEFT click selects, a RIGHT click with a force selected is `_on_order_target` |
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
- **Earlier builds** (the pre-`main` line and 0.10–0.11) are listed in [the handoff history](HANDOFF-HISTORY.md).

## 7. Known gaps (verified, not guesses)

- **AI targets come from `AiAssess.choose_target` only.** The unused
  persistent-objective planner in `AiStrategy` was deleted in the October 2026
  cleanup (recover it from git history if objectives are ever wanted again);
  the module now holds only the live force estimators.
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
- **The AI cannot invade a hostile island.** Players can carry armies on a
  fleet and make an unopposed landing. AI land planning excludes sea crossings
  until an autonomous transport planner can assign actual ships.
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
  Harbours, launching, docking and shipping assignments remain player-controlled.
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
- **Naval follow-up**: autonomous AI fleet strategy/shipbuilding, port blockades,
  dedicated naval balance and richer cargo economics. Player embarkation,
  automatic encounters and multi-season routes are implemented in WATERWAYS.md.
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
- **Art fidelity remains unfinished.** The development branch now has real
  forest concealment, contact halts and patrol reveal in campaign play; it does
  not implement automatic ambush combat or individual tactical battles. See
  the campaign-route review before extending the art pass.

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

**Naval follow-up.** The player now uses actual fleets for troop transport,
persistent voyages and shipping services, with automatic encounters. The next
naval phase is AI shipbuilding/assignment, blockades and dedicated naval balance;
`blockade_port` missions remain authored and allowlisted. See WATERWAYS.md.

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
