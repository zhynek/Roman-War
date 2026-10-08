# City progression coherence audit — October 2026

Integration audit of the settlement-progression work on `origin/main`
`2885f38` (the verified 0.12 town delivery), run on October 8, 2026 in a clean
worktree on `codex/city-progression-audit`. The working checkout's uncommitted
village-defense branch was left untouched. Relevant paths are relative to the
repository root; `experience/` means
`Castles and Cities/sites/yenikapi_6000_bce/experience/`. The companion
planning record is [`docs/TUTORIAL_WALKTHROUGH_LOG.md`](../TUTORIAL_WALKTHROUGH_LOG.md).

The design goal under audit: developing a settlement and advancing practical
knowledge should expand its economic capability, support stronger defenders or
armies and eventually enable conquest, with early decisions having
understandable, lasting consequences.

## 1. Summary

- **The implemented ladder is coherent and reproducible.** Small village →
  Large village → Town plays through ordinary public commands in compact,
  outward and mixed layouts, from fresh games, from frozen 0.11 paid saves and
  from a pure 0.2-style tutorial save. Every recorded 0.12 milestone, stock and
  fixture digest reproduced byte for byte on this checkout (section 7).
- **Confirmed defects: three, all fixed with regression coverage.** A
  prepared-set cap silently froze the knowledge gate with no explanation (D-1);
  civic and service adults were credited to the player as "Care workers" and
  quietly lift wellbeing by up to 18 points (D-2, explanation fixed, balance
  question logged); `STAGES.md` still described Town as planned (D-3).
- **The actual playable limit is Town** at about season 40–46. After it the
  settlement sits at hard caps (48 residents, 360 provisions), overflows about
  146 provisions a season, accumulates timber with no sink, and has no next
  transition. Large town onward exists only as planned metadata (G-1).
- **Knowledge → capability is real but small and local.** Three practiced
  skills have rule consumers (wood shaping gates the civic ladder, cooperation
  adds a prepared set, woodland experience relieves an incident); household
  learning-circle practice has none (H-7). The settlement has no recruitment,
  army or conquest; those exist only in the parent campaign, which the
  settlement never touches (section 5).

## 2. Baseline and method

Read before editing: `AGENTS.md`, `CLAUDE.md`, `docs/HANDOFF.md`,
`docs/reviews/2026-09-map-experience.md`, `docs/CITY_LIFECYCLE.md`, the
experience's `LIFECYCLE.md`, `CONSTRUCTION.md`, `LIVING_VILLAGE.md`,
`LAND_GROWTH.md`, `GOVERNANCE.md`, `VISUAL_COMMANDS.md`, `AUTHORING.md`,
`README.md`, `STAGES.md`, and `VERIFICATION-0.11.md` / `VERIFICATION-0.12.md`.
`origin/main` equals the checkout commit `2885f38`; commits `227eca3` (village
civic progression), `e344d81` (working town), `b6e387d`, `7153211` and
`2885f38` were diffed and verified rather than trusted.

Method: every claim below was checked in code, then reproduced with ordinary
public commands through the rules API (`settlement_rules.gd::command` /
`advance`) using the retained drivers and four throw-away probe scripts kept
outside the repository (session scratchpad). No stock, rank, progress or save
field was edited to manufacture an outcome; the two labelled "state-edited"
cases in the retained suites (`stressed` store condition 0, `food = 0`) are
rule-boundary checks, not progression claims. Gates: the parent data
validator, Godot import, the complete 705-test suite, boot, and the rendered
map playtest; the experience's twelve validators, ten negative test modules,
import, fourteen headless suites and both rendered walkthroughs; stderr was
inspected alongside exit codes.

## 3. Integration map (evidence-backed)

### 3.1 Content, schemas, balance, cross-reference validation

| Layer | Authority | Validation | Notes |
|---|---|---|---|
| Base scenario, legacy projects, households, citizens | `experience/data/governance.json` (10 projects with additive `effects`) | `tools/validate_governance.py`, `test_governance_data.py` | Effects are **summed** across completed projects (`settlement_rules.gd::effect`), unlike the parent's per-tier totals |
| Shared assets, principles, housing steps | `data/assets.json` | `validate_assets.py` | `project_assets` maps every project (incl. lifecycle/town) to a place |
| Land sites, proposals, alternatives | `data/land.json` | `validate_land.py` | `alternatives` make compact/outward equivalents satisfy the seven legacy foundations |
| Living (woodland, posts, discoveries, 3 projects) | `data/living.json`, `balance.living` | `validate_living.py` | Per-household experience 0–8; prepared sets capped at 12 |
| Incidents (2 authored, 4 projects) | `data/incidents.json` | `validate_incidents.py` | Severity factors read living/land/household state |
| Lifecycle profile `village_lifecycle_v1` | `data/lifecycle.json` + `balance.lifecycle` | `validate_lifecycle.py` (graph reachability, revision chains, benefit targets, tuning readers), `test_lifecycle_data.py` | Semantic hash `a4694114…` pins stages (incl. `town: planned`), transitions, projects, sites, proposals, tuning |
| Town extension `town_responsibilities_v1` | `lifecycle.json` `town` + `balance.town_lifecycle` | `validate_town.py`, `test_town_data.py` | Separate hash includes the base hash, town definitions, tuning and the referenced support/maintenance/preparation values |
| Presentation copy | `visual_commands.json`, `construction.json`, `governance_ui.json`, `lifecycle.json` `strings` | `validate_visual_commands.py`, `validate_construction.py`, closed schemas | UI text is outside both semantic hashes |

Cross-reference checks that matter for progression: the lifecycle validator's
monotonic closure proves every lifecycle/town project reachable from the
initial stage without self-unlock (`validate_lifecycle.py` lines 182–200);
`validate_town.py` re-runs it with the town transition and the seven
foundation alternatives merged in.

### 3.2 Authoritative rules, commands, seasonal order, effect readers

`settlement_rules.gd` is the single command/season boundary. Order inside
`advance()`: forecast → stocks/food → assignments → (assets active) asset
advance incl. project completion → land → living → incidents → neighbors →
households → turn+1 → succession → effective plan → legacy town milestone →
`lifecycle.advance` (readiness counter, promotion events) → fabric projection
validation. The allocator (`asset_rules.gd::allocation`) is the only labor
model: requests sorted by priority then id, each filled from the finite adult
pool; `living.requests` and `lifecycle.requests` append their requests;
`lifecycle.apply_allocation` adds the town preparation bonus after all
requests are filled.

Request priorities (lower first): food essentials 1; care/refuge 2; watch 2 or
6 by principle; secure stores, reserve (if ≥ two seasons), access, repair 3;
living preparation/training 4; **village civic duty 4**; projects 3 + priority
(4–6); timber 5; learning 6; **town civic duty 6; provision service 7**;
reserve under a one-season principle 7.

Effect readers: `storage` → `storage()`; `housing` → `capacity()`;
`food_yield`, `wellbeing`, `cooperation`, `security` → `forecast()`. Town
projects deliberately carry empty effects; their benefits are
`lifecycle_rules.gd::operation` (spoilage saved) and `apply_allocation`
(extra prepared set), both consumed in `forecast()` and `living.advance`.

### 3.3 Save creation, validation, loading, adoption, compatibility

`campaign_save.gd::write` validates, writes a temporary file, reads it back and
renames; `read` bounds size, requires wrapper/extension agreement (1–8), runs
`ensure_state_keys` then `validate_state`. Wrapper 8 = lifecycle active; town
adoption adds `lifecycle.town` under the same wrapper (older 0.11 apps reject it
by field count, `lifecycle_rules.gd::validate` line 220). Adoption is explicit
and ordered: `asset_begin` (auto-runs `household_begin`) → `land_begin` →
`living_begin` → `lifecycle_begin` (God only; refuses with the missing
extension named) → `lifecycle_town_begin`. Each adoption copied the state and
changed no stock, person, queue or completed entry (probe 3, all five steps).
The frozen fixture `experience/tools/fixtures/lifecycle-0.11-paid.json`
(paused assembly shelter at 14/24 work) loads, adopts town and keeps its paid
progress (`town_checks.gd` lines 14–22; generated save `adopted-old-paid`).

### 3.4 Physical building revisions, site succession, rendering, picking

`fabric_projection.gd::resolve` replays the completed ledger as one strict
transaction per lifecycle project (`expected_revisions`, duplicate-mutation and
stale-revision rejection) and keeps the legacy reuse guard for old projects;
`pending()` rejects queue claims on the same object. The same projection feeds
`campaign_view.gd::snapshot` (rendering) and `validate_state` (saves), so an
invalid successor fails at the command boundary first. `land_rules.gd::use_at`
projects the latest completed use per site with explicit successor links
(`predecessor`), retaining the prior yield during work when `retain` is set.
Rendering/picking: `construction_view.gd` builds sites and badges from the
same read model (`project_presentation.gd::describe`); `main.gd::pick_asset`
ray-tests the drawn meshes; the town walkthrough verifies drawn mesh picking of
the paid material pile and cold-build geometry equality (`town_preview.gd`).

### 3.5 UI requirements, quotes, controls, growth guidance, reports

Every button quotes `rules.quote(state, action)` — the exact command path
including the fabric projection — and disables with the error copy
(`visual_commands.gd::command_button`). Prices come from `rules.projects[id]`
which the lifecycle fills from `balance` at load (`lifecycle_rules.gd::_init`),
so quote and execution cannot disagree. Readiness is one pure query
(`lifecycle_rules.gd::status`) rendered by `visual_commands.gd::lifecycle_factors`
with the same current/required numbers the command uses in `blocked()`; the
Town gate reads `settlement_rules.gd::town_factors`, the legacy support
function, rather than a copy. Reports: `state.report` is the resolved forecast;
factor lists are rendered verbatim with `governance_ui.json` `factor_names`.
The detailed ledger has no lifecycle tab; the civic ladder is reachable only
through the illustrated dock (and its land-tab proposals).

### 3.6 Tests, public-command recipes, build gates, documentation

Retained suites (`experience/tools/*_checks.gd`) are driven by public-command
drivers (`tutorial_`, `land_`, `living_`, `incident_`, `neighbor_`,
`lifecycle_`, `town_driver.gd`). `lifecycle_checks.gd` and `town_checks.gd`
save canonical states through the real writer, replay every recipe from the
new-game state and compare exact state and SHA-256 digests; saves at seasons
15/39/60 and 20/45/75 are resumed in lockstep with the uninterrupted run. The
release builder (`Castles and Cities/tools/build_early_settlement.py`) runs all
of it plus both rendered walkthroughs on source and the exact app.
Documentation of record: `docs/CITY_LIFECYCLE.md` (plan and status),
`experience/LIFECYCLE.md` (contract), `VERIFICATION-0.11/0.12.md` (evidence).

### 3.7 Boundaries between experiences

| Experience | Rules and saves | Connection to the others |
|---|---|---|
| Independent Yenikapı settlement | `experience/src/core/*`, `early_settlement_campaign.json` wrappers 1–8 | None at runtime. Imports no parent class; the parent imports nothing from it (`Castles and Cities/.gdignore` keeps it out of the campaign import). `docs/CITY_LIFECYCLE.md` §11 reserves a future pure "settlement-development report" adapter |
| Parent campaign | `src/core/*`, `roman_war_save.json` (version 2 + additive keys) | Settlement level = government tier gated by population (`construction.gd::blockers_for`); knowledge via `knowledge.gd`; recruitment via `recruitment.gd` |
| Roma city | `src/core/rules/city*.gd` on the same campaign state | One save; civic work days and recruitment share the facade; battles through `BattleResolver` |
| Dated studies (Yenikapı reference, Constantinople 1200) | Separate projects/bookmarks | No rule or save link; `STAGES.md` forbids inferring ancestry |

These boundaries are intentional and documented; the missing connection is
the reserved report adapter (section 5, G-5).

## 4. Progression matrix — one continuing game

Measured from identical opening conditions (30 residents, 100 provisions, 30
timber) with the retained strategies and audit variants (probe 1; all runs
100 seasons). "Civic" is the paid civic project completion season.

| Strategy (public commands only) | Large village | Town | Season-100 people / food / timber / places | Notes |
|---|---:|---:|---|---|
| Compact (clay court + hearth yard homes, adapted workroom) | 28 | 39 | 48 / 360 / 225 / 8 | Matches `VERIFICATION-0.12.md` exactly |
| Outward (northern path, two outer homes) | 33 | 46 | 48 / 360 / 121 / 14 | Pays one adult + one timber per season for access |
| Mixed (clay-court home + outer east home) | 33 | 45 | 48 / 360 / 129 / 11 | Equivalent prerequisites hold for mixed layouts |
| Compact, one-season reserve principle | 20 | 32 | 48 / 360 / 229 / 8 | 7–8 seasons faster; early food 10–20 lower; no measured penalty in a quiet game (H-2) |
| Compact, three-season reserve | 28 | 39 | identical to compact | Reserve priority, not the target, is the mechanism |
| Compact, preparation order never used | never | never | 48 / 300 / 329 / 6 | Knowledge gate (shaping 2/4) blocks the whole ladder; legacy town support still reached at 24 |
| Compact, store maintenance off | 27 | 38 | 48 / 252 / 233 / 8 | Condition 0: storage 252, both town benefits suspended, rank kept; slightly faster because no repair timber |
| Compact, provision service bought first | 28 | 39 | identical | Order of the two facilities is irrelevant at steady state |
| Compact, civic house only (no facilities) | 28 | 39 | 48 / 360 / 255 / 8 | Same food and people as with both facilities (H-4) |
| Legacy route (no lifecycle; exchange place) | — | — | 48 / 300 / 296 / 6 | Legacy town support at season 23; 12 prepared sets idle |
| Welcoming off (births only) | never by 120 | never | 47 / 300 / 384 / 6 | 40 residents at season 61; shaping gate frozen at 3/4 by the full set store (D-1) |
| Pure 0.2 tutorial save, all chapters adopted at 21 | 23 | **26** | 48 / 360 / 199 / 8 | Recognized rank waives readiness; pays 14 + 22 timber and work |

Binding constraints for the first transition in the compact run, by season
(probe 1, `blocked` reasons from the readiness query): shaping met at 10;
`council_ground` complete at 21; cooperation ≥ 60 at 22 (the hearth-yard home
costs four until the meeting ground adds eight); two qualifying seasons at 24;
then **timber** (insufficient at 24, below the two-timber reserve at 25);
commissioned at 26, finished at 28. For Town: four supported seasons at 32,
then timber until 35, finished at 39. Timber and the cooperation stock, not the
knowledge gate, pace the ladder in every recorded strategy.

Checklist from the brief, with the verifying evidence:

| Requirement | Result | Evidence |
|---|---|---|
| Readiness, civic achievement, upgrades and operating condition distinct and explained | Yes, with one wording overlap (H-1) | `lifecycle_rules.gd::status`/`stage`/`operation`; tight rations dropped cooperation to 64 → legacy phase "Village" while civic stage stayed Town and duty/output continued; support recovered in four seasons (probe 2; new check `legacy_support_contraction`) |
| Sustained readiness advances only through resolved seasons | Yes | `lifecycle_rules.gd::advance` guards `last_turn`; ten repeated `status`/`quote`/`forecast` calls leave state identical (`lifecycle_checks.gd` "all queries leave authoritative state unchanged") |
| Quotes and execution share requirements and prices | Yes | `command_button` quotes the command path; `town_preview.gd` compares the rendered "After payment" line with the actual paid state ("visible remaining reserves agree with actual public payment") |
| Promotion grants nothing free | Yes | `lifecycle_checks.gd` "civic upgrade grants no free buildings"; `town_checks.gd` "rank unlocks purchases without free facilities", "purchase creates no supplies or people" |
| Identity, revisions, furnishings, households, paid work, land costs, depletion survive | Yes | `fabric_lifecycle_checks.gd` (66), rendered captures 21–23 and 33–35; `lifecycle_store` keeps `yk_store_01` at revision 3 with every furnishing; outward access cost persists to season 100 |
| Incremental benefits without double-counting | Yes | `effect()` sums declared increments; validator asserts cumulative storage 180 = 120 + 60; town effects are empty and applied once in operation/allocation |
| Civic staffing competes; Town replaces, never stacks; services pay their way | Yes | One request id `lifecycle_civic` with count 1 or 2 (`lifecycle_rules.gd::requests`); `town_checks.gd` "no duplicate civic duty"; service requests its own adult, preparation bonus costs one timber and one place |
| Shortages disable benefits without erasing rank or progress | Yes | Store condition 0 → storage 252, saved 0, prepared 0, rank Town (probe 1); understaffed duty → outputs 0, rank Town (`town_preview.gd` capture 21) |
| Recovery through understandable decisions | Yes | Pause the competing project (capture 22); restore rations (probe 2); spend prepared sets (probe 4) |
| Equivalent compact/outward prerequisites valid | Yes | All three layouts reach Town; `land.alternatives` cover four household combinations |
| No cycle or future-only requirement | Yes | Validator closure; every transition reached in every strategy that practices shaping |
| Later stages not presented as playable | Yes, after D-3 | Ladder labels "Planned stage · not yet playable"; `status()` returns no transition at Town; `STAGES.md` corrected |

## 5. Knowledge, technology and military development

Chain under audit: settlement investment → learning/research → productive
capability → equipment/recruitment → army capacity and sustainment → expansion.

### 5.1 Independent settlement (implemented, connected, local)

| Mechanic | Discover | Practice | Adopt | Effect (reader) | Explained in UI |
|---|---|---|---|---|---|
| Wood shaping experience (per household 0–8) | `living_inspect` discoveries (`shaping_interest`) | +1/season for the household whose adult prepares or repairs (`living_rules.gd::advance`) | — | Gates `establish_village` (`lifecycle_rules.gd::_factor` kind `knowledge`) | Readiness row; after D-1 also names suspension causes |
| Woodland experience | `woodland_interest` | +1/season for the timber crew's household | — | Approach-incident relief and earlier signs (`incident_rules.gd::experience`) | Incident factors |
| Cooperation (meeting + supported sessions, practice 0–2) | `cooperation` discovery needs meetings and both interests | shared sessions with `cooperate` on | the `cooperate` order | +1 prepared set per shared session; +2 repair work (`living_rules.gd::allocate`, `incident_rules.gd::work_bonus`) | Workshop orders and discoveries |
| Watch kits + practice (readiness 0–4) | — | training adult with kits | — | `equipment_security` up to +3 per equipped adult; incident equipment relief | Watch orders; incident factors |
| Household learning circle (`homes[id].practice`) | — | accrues when the learning order is staffed | — | **None** (presentation only: `assets_panel.gd`, `household_view.gd`) — H-7 | Shown as a number with no stated effect |

Productive capability: cultivation (+8), storage (+60/+120/+60), places (+4,
+2), preparation (+1 set), spoilage (−6). No research tree, no currency, no
technique adoption; prerequisites are attainable with starting content
(probe 1, probe 4 recovery). Equipment and army: wooden watch kits only; no
recruitment, roster, battle or conquest, by design (`GOVERNANCE.md`,
`LIVING_VILLAGE.md`). Trade (neighbors) is optional and never required by any
gate (`lifecycle.json` has no contact predicate; `validate_town.py` only
merges foundation alternatives).

### 5.2 Parent campaign (implemented within a separate experience)

| Link | Code | Test |
|---|---|---|
| Buildings → settlement level (government tier gated by population) | `construction.gd::blockers_for`, `settlements.gd::settlement_level` | `test_construction.gd`, `test_settlements.gd` |
| Buildings → Craft stock → advances with effects (build cost, farm income, health capacity, trade, build turns) | `society.gd` `knowledge` accrual, `advances.gd::refresh`, readers in `construction.gd`, `economy.gd`, `growth.gd` | `test_advances.gd` ("advance effects reach the rules") |
| Techniques: aware → adopting → adopted; effects faction-wide; war blocks into `army_mods` | `knowledge.gd` | `test_knowledge.gd` (17), `test_warcraft.gd` (8) |
| Buildings + techniques → recruit profile (experience, weapon/armor) stamped at muster; retraining re-arms | `recruitment.gd::recruit_profile`, `upgrade_level` | `test_recruitment.gd` ("recruits are stamped…", "upgrade cap", "retrain refits…") |
| Recruitment → levy strain → order and growth | `recruitment.gd::add_levy_strain`, `growth.gd`, `public_order.gd` | `test_recruitment.gd` "levy strain from the muster" |
| Techniques → upkeep per class, movement, siege, walls | `knowledge.gd::upkeep_pct_by_class`, readers in `economy.gd`, `movement`, `siege` | `test_warcraft.gd` "war effects reach upkeep/order/siege/march" |
| War record → warcraft prerequisites; conquest teaches | `knowledge.gd::unmet_prerequisites`, `process_turn` | `test_warcraft.gd` "war record unlocks learning", `test_knowledge.gd` "conquest teaches the victor" |
| `requires_technique` on a building level and a unit | `construction.gd::available_projects`, `recruitment.gd::available_units` | `test_construction.gd`, `test_recruitment.gd` "technique gates the roster" |

The parent chain is complete from investment to conquest and is tested at each
link; the 705-test suite passed here. UI: the knowledge scroll shows the war
record, moods and blockers (`game.gd::technique_overview`), but the blocker
sentences are authored in `src/ui/panels/knowledge_panel.gd` lines 130–160
rather than in `data/effects_glossary.json` (parent observation P-1; not
changed here).

### 5.3 Classification

| Status | Items |
|---|---|
| Implemented and connected (settlement) | Shaping → civic ladder; cooperation → prepared sets and repairs; woodland experience and kits/practice → incident relief and security; paid civic fabric → obligations and facilities |
| Implemented within a separate experience | Everything from recruitment to conquest (parent campaign); Roma's civic work days and live battles behind `BattleResolver` |
| Planned | Large town and later stages (`docs/CITY_LIFECYCLE.md` §4, §10 rows D–F); the pure settlement-development report and regional adapter (§11) |
| Missing or contradictory | Household learning-circle practice has no consumer (H-7); civic adults' hidden social contribution (D-2, now explained); the knowledge gate's silent suspension (D-1, now explained) |

Recommended smallest coherent bridge (not built): a pure, versioned
settlement-development report produced by the settlement rules — scenario and
settlement ids, civic stage, population and capacity, completed foundations,
best practiced experience per skill, kits and readiness — that a reviewed
parent adapter could later map read-only onto `village`/`town` levels. No save
merge, no shared rules, no local conquest or trade requirement.

## 6. Findings

Severity: **High** blocks or misleads progression; **Medium** misleads
explanation or balance; **Low** cosmetic/documentation.

### 6.1 Confirmed defects (fixed in this audit)

**D-1 (High) — Full prepared stores silently freeze the wood-shaping gate.**
Files: `experience/src/core/living_rules.gd::requests` (line 83 drops the
preparation request when `blanks ≥ blank_capacity`), `lifecycle_rules.gd::_factor`
(kind `knowledge`), `visual_commands.gd::lifecycle_factors`. Mechanism: shaping
experience accrues only to the household of an adult actually assigned to
preparation or repair; when sets reach 12 and nothing consumes them, the
request disappears, the standing order still reads "Ordinary", the allocation
review lists no preparation, and the readiness row shows e.g. "3 / 4" with no
cause. Reproduction (probe 4): new living village, lifecycle adopted,
preparation on, welcoming off → sets full at season 15, factor frozen at 3/4
for 25 seasons; commissioning watch equipment (two sets) reopened practice and
the gate was met two seasons later. Player impact: a Small village can be
stuck indefinitely without being told why; the readiness list is the only
explanation surface. Fix: the factor now carries `suspended: sets_full |
order_off` with `{blanks, capacity}`, the review renders the cause
(`practice_sets_full`, `practice_order_off` strings), `LIFECYCLE.md` explains
the rule, and `lifecycle_checks.gd::practice_gate_checks` pins suspension,
purity, recovery and attainability. The balance rule itself is unchanged.

**D-2 (Medium) — Civic and service adults were credited as "Care workers".**
Files: `experience/src/core/asset_rules.gd::_request` (civic/service jobs are
`care`), `settlement_rules.gd::forecast` (care factor = `plan.care × 6` for
wellbeing, `× 3` for cooperation). Mechanism: the five-job plan is the
accounting basis of the social factors, so one village civic adult, two town
civic adults and one service adult add +6/+3 each. Measured (probe 1,
compact): wellbeing 75 → 81 → 87 → 93 and cooperation 65 → 68 → 71 → 74 across
assembly, civic house and service; the assembly adult alone lifts cooperation
from exactly the 65 Town-support threshold to 68. Player impact: the breakdown
says "Care workers +30" when three of five are clerks and a provisioner;
`LIFECYCLE.md` described civic duty only as an obligation, so Town looked
costlier than it is and its support looked self-sustained for no visible
reason. Fix (balance-neutral): the forecast shows a separate **Civic and
service duty** factor (inserted after care so the last factor stays the
land-access penalty that `land_checks.gd` asserts), `governance_ui.json` and
its schema name it, `LIFECYCLE.md` documents it, and `town_checks.gd` pins the
split and the unchanged total. Whether civic adults *should* count as care is
logged as design gap G-3 for the owner.

**D-3 (Low) — `STAGES.md` still said "Town through Metropolis remain planned
lifecycle metadata."** Town has been playable since 0.12. Fixed to describe the
three implemented stages and the planned remainder.

### 6.2 Hypotheses and design observations (not changed)

**H-1 (Medium, UI clarity) — Two things are called "Town".** The detailed
ledger header shows the legacy phase ("Town milestone" / "Village",
`governance_ui.json` `phase_town`, `complete`, `recovery`) while the dock's
civic button shows the lifecycle stage. Under tight rations the ledger reads
"Village … contracted" while the civic review reads "Town" (probe 2). Both are
correct and `LIFECYCLE.md` explains the distinction, but a player reads two
contradicting words. Recommendation: label the legacy milestone "Town support"
when the lifecycle is active (copy only; `visual_commands.json`'s
`growth_review` button already says "Town readiness").

**H-2 (Medium, balance/explanation) — The reserve principle is a priority
switch, not a target.** `asset_rules.gd::allocation` requests extra gathering
at priority 3 when the principle is ≥ two seasons and 7 otherwise; the target
itself is usually already met. The default two-season principle delays the
whole ladder by 7–8 seasons for 10–20 provisions of early buffer and no
measured benefit in a quiet game (probe 1). The principle copy
(`assets.json` `reserve`) should say that it also ranks gathering above timber
and projects; whether the default should change is a balance decision.

**H-3 (Low, design) — Town civic duty is easier to drop than village duty.**
Village duty requests at priority 4; town duty at 6, after timber (5) and all
projects (4–6). Documented in `LIFECYCLE.md`; the player cannot change it.
Intended ("obligation competes") but worth a conscious decision.

**H-4 (Medium, design) — The two town facilities have no measured steady-state
effect.** The provision service saves up to 6 provisions of spoilage, which at
the 360-provision cap becomes overflow (season-100 food 360 with or without the
facilities; probe 1). The preparation bonus applies only while preparation is
on and sets are below 12, and the recorded strategies switch preparation off
once shaping is met. Their value is situational: recovery after a loss and
equipment/incident preparation. `LIFECYCLE.md` now says so. Large town needs
an outlet for both.

**H-5 (High, roadmap) — Town is a hard ceiling with waste.** From about season
30 every strategy sits at 48 residents (housing cap) and 360 provisions
(storage cap); about 146 provisions a season overflow while 38 of 48 adults
gather food; timber accumulates (121–296 at season 100) with nothing to buy
except kits and repairs; the neighbors chapter is the only resource outlet.
This is the actual playable limit and the strongest argument for Slice D
(housing, service coverage) and for giving knowledge a productive outlet.

**H-6 (Low, compatibility) — Legacy 0.2 saves keep both central work ground
and the legacy homes** (8 places, no access upkeep, 48 housing) — strictly
better than either land strategy. Intended compatibility (`LAND_GROWTH.md`),
but note it when comparing strategies.

**H-7 (Medium, section 5) — Household learning-circle practice has no rule
consumer.** `household_rules.gd::advance` accumulates `homes[id].practice`;
only `assets_panel.gd` and `household_view.gd` read it (poses and a number).
"Craft uptake varies by household" is therefore illustration. Either document
it as such or give it one reader (for example, a later Large-town service).

**H-8 (Low) — A training adult counts as a watch worker** in the security
factor (`living_training` job `watch`, +8) although `LIVING_VILLAGE.md` calls
training "separate". Same job-class convention as D-2.

**H-9 (Low, UI) — The provision service is listed under Stores** while its
building (`growth_care_shelter`) belongs to Homes, so clicking the finished
room opens Homes, where the card is absent.

**H-10 (Low, docs) — `experience/project.godot` and `export_presets.cfg` say
0.10.0** while the source implements 0.12; the release builder overrides the
version at freeze, so development runs show a stale version.

**H-11 (Medium, tutorial) — No in-game guidance covers the civic ladder.** The
five dock lessons and every chapter guide predate 0.11; the lifecycle review
is the only explanation. Handled in the tutorial log.

**P-1 (parent, Low) — Knowledge blocker sentences live in UI code.**
`src/ui/panels/knowledge_panel.gd` lines 130–160 author English for unmet
prerequisites instead of `data/effects_glossary.json`. Outside this audit's
scope; recorded for the parent's content rule.

### 6.3 Design preferences (for the owner)

**G-1 — Large town is the next stage and nothing exists for it** beyond
metadata; `docs/CITY_LIFECYCLE.md` §4 row D is the brief. **G-2 — The reserve
default** (H-2). **G-3 — Should civic adults count as care?** Removing the
contribution would change the recorded strategies (compact cooperation would sit
exactly at the Town threshold) and the fixture digests; keeping it should be
stated in the civic project copy. **G-4 — A resource sink at Town** (H-5).
**G-5 — The settlement-development report** (section 5.3). **G-6 — Rename the
legacy milestone** (H-1).

## 7. Verified fixes and test evidence

### 7.1 Baseline gates on `origin/main` `2885f38` (unmodified)

| Gate | Result |
|---|---|
| Parent `python3 tools/validate_data.py` | 0 errors, 0 warnings, 35 tables |
| Parent `godot --headless --import` | clean |
| Parent `tests/run_tests.gd` | **705 tests, 0 failures**; AI campaign average 312.9 ms, peak 440 ms against the 600 ms budget (M3 Max, Godot 4.4.1) |
| Parent boot `--quit-after 5` | clean |
| Parent `tools/map_playtest.gd` | PASS: pinned route, read-only planning, issued march, arrival, 40× maximum detail; six captures inspected (territories, commander, planned route, column on the road, arrival beside the allied army, troop ranks under the canopy) |
| stderr | one inherited anchor/size warning in a UI layout test, documented at baseline; no `ERROR`/`SCRIPT ERROR` |
| Experience validators (12) | 0 errors each; visual 6/6 and construction 8/8 negative cases rejected |
| Experience negative test modules (10) | 82 tests OK |
| Experience import | clean |
| Experience headless suites (14) | **36,908 checks, 0 failures** (visual 81, construction 894, village 248, governance 712, neighbors 302, households 310, assets 608, land 779, land geometry 438, living 2,374, incidents 6,323, fabric lifecycle 66, lifecycle 12,247, town 11,526) |
| `lifecycle_preview.gd` | 29 captures, 437 checks, 0 failures |
| `town_preview.gd` | 53 captures, 1,713 checks, 0 failures |
| Fixture digests | all seven state digests listed in `VERIFICATION-0.12.md` reproduced exactly; strategy outcomes identical |

### 7.2 Gates after the fixes

Every experience gate was rerun on the patched tree. Parent sources were not
modified (the diff touches only `Castles and Cities/…` and `docs/`), so the
parent gates above stand.

| Gate (patched tree) | Result |
|---|---|
| Experience validators (12) and negative test modules (10) | 0 errors; 82 tests OK (the governance UI schema now requires the `civic` factor name) |
| Experience import | clean |
| Experience headless suites (14) | **36,933 checks, 0 failures**: unchanged counts except lifecycle 12,258 (+11, `practice_gate_checks`) and town 11,540 (+14, civic factor invariants and `legacy_support_contraction`) |
| `lifecycle_preview.gd` | 29 captures, 437 checks, 0 failures; capture 01 now shows the practice explanation under "Practiced wood shaping: 2 / 4" |
| `town_preview.gd` | 53 captures, 1,713 checks, 0 failures; the same 87-public-command UI recipe ends at turn 49 and replays exactly |
| Strategy outcomes | identical to the baseline (compact 39/41/43 and 48 / 360 / 225 / 8; outward 46/51/56 and 48 / 360 / 121 / 14) — the fixes change explanations, not balance |
| Fixture digests | all 22 regenerated town digests differ from the 0.12 record because every lifecycle-active saved report now carries the inserted `civic` factor; turns, milestones, stocks and recipes are unchanged. The frozen `lifecycle-0.11-paid.json` fixture is byte-identical and still loads |
| stderr | no `ERROR`/`SCRIPT ERROR` in any suite or walkthrough log |

### 7.3 Probe evidence (outside the repository)

Four throw-away probe scripts replayed public commands through the rules API
(progression matrix, reserve/preparation/maintenance variants, legacy
contraction, prepared versus neglected incidents, mixed layout, outward access
impairment, pure legacy adoption, welcome-off growth, set-cap suspension). Key
measurements are quoted in sections 4–6. Prepared versus neglected incidents
from the same town-entry state: approach severity 2 vs 5 (access impaired only
when neglected), stores severity 1 vs 7 with 0 vs 28 provisions lost, security
97 vs 75. QA images and probe outputs are in the session scratchpad, not in
the repository.

### 7.4 Not verified

- The exact packaged Mac app was not rebuilt; this audit changes source only
  and does not create a release. The next release must rerun the builder.
- Intel execution, the hosted CI runner and the medieval study were not run.
- Balance of the parent campaign beyond its existing suite was not re-soaked.
- The defense branch in the working checkout (`codex/village-defense`,
  uncommitted) was not audited; it was preserved untouched.


## 8. Follow-up — 2026-10-08: merged city progression and warfare

This follow-up integrates audit `8589fe9` with the complete preserved defense and
warfare checkpoint `5e4a441`, merged as `a88ca25`. The original sections above are
historical measurements. The prioritized [combined implementation plan](2026-10-city-warfare-integration.md)
was written before the fixes. No historical branch replaced the working village,
no published hashed profile was edited and no release was built in this follow-up.

### 8.1 Finding-by-finding disposition

| Finding | Effect of the warfare work | Combined decision and evidence |
|---|---|---|
| D-1 | Partly alleviated: paid kits and post-combat repairs consume prepared sets, but a quiet full store can still suspend shaping. | Preserve the audit's `sets_full`/`order_off` explanation. Civic guidance names the actual preparation/repair reader. Existing gate and recovery checks remain. |
| D-2 | Unchanged for civic/service duties; the new watch duties exposed the same presentation convention. | Preserve the civic factor split and unchanged social total; split watch practice and additional home watch separately. Finite named-assignment checks cover all combined duties. |
| D-3 | Unchanged. | Keep the corrected playable-stage documentation. Town is implemented; later stages remain planned. |
| H-1 | Unchanged; another gameplay loop made the two Town labels more confusing. | Lifecycle-active headers, support messages, events and guide use **Town support**. Earned civic rank remains a separate value; no phase rule changes. |
| H-2 | Warfare adds a reason to value reserves but does not overturn the quiet progression measurement. | Keep default two seasons. Principle copy explicitly names priority 3 for two/three-season reserve gathering, before timber (5) and ordinary projects (4–6), versus priority 7 for one season. No rebalance. |
| H-3 | More optional priority-4 watch duties can displace civic work. | Retain Town civic priority 6 and service 7; show those obligations and competition in civic project copy. No duplicate duty or changed allocation. |
| H-4 | Partly addressed: paid equipment manufacture/replacement and post-battle condition repair consume prepared sets. Provision losses create occasional reserve demand. | Explain actual consumers and conditions. Full stores can still turn provision-service savings into overflow; idle/full prepared stores still produce nothing. No invented steady-state yield. |
| H-5 | The economic ceiling is unchanged, but Town now supports continuing local encounters and recovery. | Keep Town/48-resident/360-provision limits. Paid screens and recurring repair/care are bounded sinks; measured mature-town food still refills rapidly. Large town is deliberately not implemented. |
| H-6 | Unchanged. | Preserve the advantageous legacy layout as compatibility. Compare legacy adoption separately from compact/outward choices; do not rewrite old buildings. |
| H-7 | Not fixed mechanically by warfare: household learning score remains distinct from real shaping, watch readiness and engaged combat experience. | Relabel the score as illustrative participation with no civic/production/combat bonus. The staffed learning order retains its labor, food and cooperation effects. No new hidden bonus or profile migration. |
| H-8 | Broadened: additional watch joins the same watch job class as training and ordinary watch. | Separate **Watch practice duty** and **Additional home watch** factors, subtracting their filled adults from **Watch workers** so the old total is unchanged. The allocation remains exclusive. |
| H-9 | Unchanged. | Show the provision-service card from Homes and Stores through presentation-only related assets. Retain the published `town_provision.asset=stores`, project ID, one quote/queue/completion and semantic hash. |
| H-10 | Already fixed by warfare. | Development project is `0.14.0-local`; export metadata is `0.14.0`. No export or release is produced here. |
| H-11 | Broadened to include the new defense choices. | Expand **How to play** from five to eleven data-driven lessons with direct civic/preparation/aftermath destinations. Setup/adoption has a separate note; lessons do not command the game. Tutorial log records implemented scope. |
| P-1 | Unchanged and independent of village warfare. | Fixed narrowly in parent `KnowledgePanel`: render actual unmet facade blockers from validated glossary templates. Six Godot tests and six Python negative tests cover all kinds, grammar, satisfied requirements and read-only rendering. No parent rules changed. |
| G-1 | Warfare does not supply Large town. | Remains open and expressly out of scope. Local battles are not another civic tier. |
| G-2 | No measured evidence justifies changing the reserve default. | Retain two seasons, explain the priority tradeoff and record one/two/three-season results. |
| G-3 | New treatment makes the distinction between social coordination and medical care more important. | Keep civic adults' existing +6 wellbeing/+3 cooperation contribution per allocated adult and explain it as civic/service coordination. They do not become extra carers or mobilizable residents. |
| G-4 | Partly addressed by paid screens, mobilization, repair and care; mature-town overflow persists. | Record real costs and finite labor. Future growth still needs an economic outlet; no claim that warfare balances the full Town economy. |
| G-5 | New local capability and consequence data broaden a future report's possible fields. | Still unimplemented by instruction. A future pure versioned report may expose actual equipment condition, preparedness, participation and recovery alongside civic capability. No parent call, shared save, military transfer or battle authority is introduced. |
| G-6 | Unchanged. | Apply the H-1 Town support wording while preserving earned rank and legacy mechanics. |

### 8.2 Reverse audit: warfare against the city contract

| Lens | Finding and verification boundary |
|---|---|
| One authority; quote equals execution | Seasonal decisions enter `settlement_rules.command/advance`; mobilization quotes use the same finite assignments and actual kit/ration state as execution. Paid screens use existing commission/queue/allocator/fabric rules. Town benefits use existing operation/allocation readers. |
| Finite adults | Food, care/treatment, ordinary watch, training, extra watch, repair, civic duty, service and construction share one sorted request list. Named assignments are unique; mobilization takes only available watch-class residents. Training/muster factors are an explanation split, not added workers or bonuses. |
| Additive saves | Defense is wrapper 9; explicitly adopted warfare is wrapper 10. Lifecycle alone remains wrapper 8. Loading adds inactive extension dictionaries only. Lifecycle is optional for warfare; Living village and its prerequisites are required. Frozen paid 0.11 adoption and active/ended/resumed warfare are exercised. |
| Semantic compatibility | Lifecycle, town, original defense and warfare semantic inputs are unchanged from the merge. Presentation aliases/copy/guide data do not change the paid contracts. The 0.11 paid fixture SHA-256 remains `b0e0af7a47ffe5febe15d189bce0d4ffcb988180112dbf0412da293d607ae872`. |
| Determinism | Integer 100 ms tactical steps, saved orders, navigation, morale, fatigue, contacts, objectives and director decisions own outcomes. Worker batching changes pacing; normal/quick/save-resume equivalence remains tested. Rendering, animation and camera work consume no simulation RNG. |
| Reconciliation and recovery | Pending reports lock seasonal/spending/workforce changes. Acceptance applies named consequences exactly once. One recovery ledger excludes injured adults; finite fed treatment and paid ordinary repair restore capability without deleting household history. |
| Parent boundary | No settlement core calls the parent campaign. Parent `BattleResolver` remains untouched. P-1 changes only presentation/data validation. |
| Playable versus planned | Civic Town plus repeatable independent village warfare are playable. Large town, permanent combat deaths, army recruitment, conquest and the report/military bridge remain outside this implementation. |

### 8.3 Reproduced measurements and final gates

The retained `integration_audit_driver.gd` and `integration_audit_checks.gd`
record public-command recipes and per-season snapshots, then replay them. Their
matched warfare branches use the same reached Town, preparation duration,
pre-mobilization stop-work orders and delegated policy, with real constructed
navigation. No rank, stock, roster, skill or saved ledger is edited to create a
comparison. The resulting comparisons are below; gate results follow in section 8.4.


All quiet comparisons explicitly adopt warfare but leave recurring threats off
while measuring the civic ladder. All remain fed. Every route starts from the
ordinary opening and retains its exact replayable command recipe.

| Choice | Immediate and opportunity cost | Delayed result | Persistence / ordinary recovery |
|---|---|---|---|
| Compact | Paid court/hearth homes and working-room adaptation consume central work ground. | Large village 28, Town 39; season 100: 48 people / 360 food / 225 timber / 8 places. | Identities and completed fabric persist; later paid workroom investment supplies its authored places. |
| Outward | Pay access and outer homes; access uses one adult and one timber each supported season. | Large 33, Town 46; 48 / 360 / 121 / 14. | More places retain the seasonal access obligation. |
| Mixed | This retained recipe builds access, court home, east home, then workroom adaptation. | Large 33, Town 45; 48 / 360 / 127 / 11. | The original temporary probe reported 129 timber with different ordering; the new exact recipe is retained, not presented as a balance change. |
| Reserve one season | Free principle change puts extra gathering at priority 7, releasing earlier labor for projects/timber. | Large 20, Town 32; food 141 versus 151 at season 4 and 282 versus 300 at season 10; timber 229 at 100. | Reversible policy; no observed quiet-game hunger, but not proof of safety against every future loss. |
| Reserve two / three seasons | Extra gathering stays at priority 3 before projects and timber. | Both Large 28 / Town 39 and timber 225 at 100. | Three has no further measured penalty in this route; retain default two. |
| Preparation off | Avoid preparation labor and material spending. | Shaping 2; no civic transition through 100, food 300 / timber 329. | Ordinary preparation restores shaping to 5 over the next ten seasons. |
| Store maintenance off | Avoid repair timber and workers. | Town 38 but condition 0, storage 252, town outputs disabled; timber 233 at 100. | Maintenance restores condition 95 and operations within twelve measured seasons without removing rank. |
| Welcome off | Forgo newcomer arrivals. | First 40 residents at 59; 47 at 120, shaping 3 still blocks civic progression. | Slow births continue. The old temporary recipe reached 40 at 61; both show the full-set practice stall. |
| Civic house without optional facilities | Save 16 + 14 timber and both project crews. | Same Town 39 / food 360 at 100; timber 255; no extra preparation or provision service. | Facilities remain optional situational investments, not mandatory rank purchases. |

Prepared and neglected ordinary incidents start at the same reached Town at
season 60 and receive paid recovery. Approach severity is **2 versus 5**; store
severity **1 versus 7**, losing **0 versus 28 provisions**. Both recover their
approach by season 70 and stores by 88. Preparation ends with 140 rather than 176
timber and uses 856 rather than 938 food-worker seasons over those 28 seasons,
including paid equipment, observation, preparations and repairs. This is a real
preparation cost, not free incident relief; both branches retain Town and fabric.

The warfare comparison prepares the same reached Town from seasons 60–100. All
branches then issue the same public stop-preparation/training/repair orders and
request four extra watch adults. All mobilize the **same six named residents**
(`citizen_0018`–`citizen_0023`), pay six provisions and use the same delegated
store-defense policy. Geometry changes only through actual paid screens.

| Watch investment | Forty-season cost | Fight and consequence |
|---|---|---|
| No kits or training | No kit/training/screen investment; prebattle timber 225. | Victory at 571 ticks; three incapacitations and one wound; six actual treatment-worker seasons, all available by season 103. |
| Equipped and trained | Kit project: 2 timber + 2 sets + 12 work. Across preparation: 12 timber/4 worker seasons preparing sets, 9 timber/9 workers repairing, 4 training workers, 3 project workers. Total **23 extra timber and 20 worker seasons** versus untrained; timber 202. | Three serviceable kits after ordinary wear; readiness 4. Victory at 367 ticks, one wound; one treatment-worker season, available at 101. Kit condition 90. |
| Equipped, maintained screens | Additional **22 timber and 11 actual construction-worker seasons** for the two screens (12/16 and 10/16 timber/work); timber 180. Watch condition 96. | Victory at 317 ticks, two wounds; one treatment-worker season, available at 101. Kit condition 95. |
| Same screens, maintenance off | Saves three maintenance timber and three worker seasons; timber 183, watch condition 44. | Prepared-position protection is disabled; paid geometry remains. Victory at 367 ticks, one wound; one treatment-worker season. |

Maintained screens shortened this encounter but **did not guarantee fewer
wounds**. These are deterministic outcomes for one objective and policy, not
universal odds. Every active save resumes identically; pending outcomes commit
once. Residents, household history, Town, paid fabric, land and contacts survive.
Ordinary repair returns kit condition to 100 during the eight-season recovery
window. Reenabled watch maintenance raises condition 44 → 61 → 78 → 95 over
three seasons. Equipped and fortified recovery each consume three preparation
timber, two repair timber and two repair-worker seasons; treatment consumes
finite adults without inventing a medicine resource.

All branches refill food **354 → 360 in one season**; quiet mature Town still
overflows about 146 provisions per season. Warfare gives preparation and recovery
real downstream value, but this evidence does not establish sustained food
scarcity or solve the Town economic ceiling.

Older-profile checks load the unchanged paid 0.11 fixture, explicitly adopt town
and warfare, and preserve its stocks, paid queue, completed fabric, people,
households, land, living state and contacts. The original tutorial-route adoption
also preserves stocks and paid work and replays from its public commands.

### 8.4 Final integration verification

The [integration verification record](2026-10-city-warfare-verification.md)
records source hashes, final suite totals, rendered inspection, hosted CI,
reproduction commands and source launch. All 17 village validators, 106 Python
tests and 16 embedded negative cases pass. The final frozen village import and
all 32 headless suites pass **53,586 checks**, with unchanged source hashes and
empty stderr. The current parent passes all 711
tests locally, plus data, import, boot and the four required map views. Village
walkthroughs pass 3,892 checks, with all 148 captures inspected; parent map has
six inspected captures. Godot stderr was checked, with only the inherited parent
anchored-control warning. Hosted timing evidence remains separate from local
results. No integration release or exported app was built.
