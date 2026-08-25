# Handoff — picking up Roman War in a fresh session

Everything an assistant (or a human) needs to be productive here within five
minutes. This deliberately does **not** repeat what the other docs cover:

| For | Read |
|---|---|
| Architecture rules, conventions, clean-room policy | [`CLAUDE.md`](../CLAUDE.md) (auto-loaded by Claude Code) |
| What every system does and the phase-by-phase status table | [`docs/DESIGN.md`](DESIGN.md) — §10 is authoritative |
| What the game is like to play | [`PLAYING.md`](../PLAYING.md) |
| How to produce a downloadable app | [`BUILDING.md`](../BUILDING.md) |
| Why the design is what it is | [`docs/research/rtw-research-report.md`](research/rtw-research-report.md) |

## 1. Where things stand

An original clean-room turn-based grand-strategy game of the 270 BC
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 22
JSON tables under `data/` validated by `schemas/`, with a thin deterministic
rules engine in `src/core/`. Battles resolve behind a swappable
`BattleResolver` interface.

**Built:** Phases 0–6 — map & turns, settlements & economy, armies & sieges
(including amphibious landings on at-war shores), the full character/family
layer **with seeded households**, the Phase 5 agents & diplomacy layer
(attitude model with decaying memory, offers/tribute/cessions with a
live-appraisal negotiation UI, diplomats/spies/assassins on the map), the
Phase 6 campaign AI (persona-driven: economy, objectives, armies, war and
peace with real truces), the Phase 7 senate foundation with four live
mission kinds, the Phase 8 campaign UI with world news — and the **Phase 9
Deep Strategy layer** (DESIGN.md §12): 37 techniques spreading by
contact/conquest/espionage with an awareness→adoption lifecycle, culture
resistance and crisis reform pressure; recruit-time weapon/armor stamping
(the 45 long-dormant building effects live); 16 edicts with exclusivity
tensions, repeal shocks, the insolvency collapse and a stacking modifier
container; AI adoption + policy by persona priorities; the structured
chronicle (narrator contract in `schemas/chronicle_entry.schema.json`) with
war/reign ledgers, character deeds, 12 epithets and prose annals; event
vocabulary (repeatable events on cooldowns, faction moods, scripted
technique grants, obituaries for the great powers). A 100-turn soak
(`tools/soak.gd`) shows 139–186 adoptions with nearly every living court
holding a distinct knowledge signature, ~50 edicts held across all seven
categories, ~600-entry chronicles, and `divergence: 0.29` across seeds.

**Green as of the head of this branch:** 176 tests / 0 failures, validator 0
errors / 0 warnings, clean boot, end_turn ≈ 235 ms average over 60 turns
(the harness ceiling is 250 and this machine's variance is ±10 — if the
perf assertion flakes, re-run before touching anything). Branch
`claude/project-handoff-familiarization-565ba5`, everything pushed.

## 2. Get productive in five minutes

The container starts with **no Godot installed**. Get it:

```sh
cd /tmp && curl -sSL -o godot.zip \
  https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
unzip -q godot.zip && chmod +x Godot_v4.4.1-stable_linux.x86_64
```

> **Always run `--import` first — and again after adding any `class_name` file.**
> ```sh
> godot --headless --path . --import
> ```
> This is the single biggest time-waster in this project. A missing or stale
> `.godot/` class cache produces bogus `Identifier "X" not declared in the
> current scope` parse errors on globals that plainly exist, "Nonexistent
> function" errors on static functions that plainly exist, causes test files
> to fail to load *while the runner still prints passes for them*, and can
> make the suite look like it is hanging. When in doubt: `rm -rf .godot` and
> import cold, THEN read the first (not last) errors in the test output.

Then the three commands that must stay green:

```sh
python3 tools/validate_data.py                                   # 0 errors, 0 warnings
godot --headless --path . --script res://tests/run_tests.gd      # 176 tests, 0 failures (~2 min)
godot --headless --path . --quit-after 5                         # clean boot, no output = good
```

`pip install jsonschema` if the validator complains about the import. For
balance work, `godot --headless --path . --script res://tools/soak.gd` prints
what kind of world 100 turns produce (wars, conquests, survivors, debt, ms).

## 3. Building a playable app

`BUILDING.md` has the recipe. The four things that are painful to rediscover:

- **Export templates** are a separate ~1.2 GB download
  (`Godot_v4.4.1-stable_export_templates.tpz` from the same release page),
  unzipped into `~/.local/share/godot/export_templates/4.4.1.stable/`.
- **`textures/vram_compression/import_etc2_astc=true`** must stay in
  `project.godot`, or the macOS export dies with a configuration error.
- **macOS architecture must stay `universal`.** The stock template ships only a
  universal binary; an `arm64` export fails with "template binary not found"
  because thinning needs Apple's `lipo`, which does not exist on Linux.
- **Ad-hoc signing is mandatory for Apple Silicon** (`codesign/codesign=1`).
  arm64 macOS refuses to launch a fully unsigned binary outright rather than
  merely warning.

Delivering the build: `SendUserFile` caps at **30 MiB** and the universal zip is
~56 MB. The fix used was to extract the arm64 slice from the Mach-O fat binary in
Python (fat header at offset 0, `cputype 0x0100000c`), overwrite the executable,
re-zip → ~27 MB. **Verify `LC_CODE_SIGNATURE` (cmd `0x1d`) survives in the thinned
slice before shipping**, or the app will not launch.

## 4. Determinism and GDScript traps (all bitten in practice)

1. **Sort keys in any loop that can steer an rng draw or a first-match
   decision.** A JSON round-trip reorders dictionaries, so an unsorted
   iteration makes a loaded save diverge from the live game. Pure SUMS are
   exempt (order-free) — the AI strength functions say so in comments.
   The save-at-20/resume-in-lockstep test in `tests/test_ai_campaign.gd` is
   the tripwire.
2. **`state.rng_state` is a decimal *string*, not an int.** JSON numbers are
   float64 and silently round a 64-bit RNG state.
3. **Inside `TurnEngine.end_turn`, never call the `Game` facade.**
   `Game._rng()` rebuilds from `state["rng_state"]`, which is stale until
   end_turn writes it back — a second stream breaks save determinism. AI code
   calls rules modules directly with the threaded rng.
4. **Player actions must not steer the campaign stream** unless they say so:
   facade methods that consume rng (attack, assault, assassinate) rebuild it
   from state and write it back; anything else (agent recruiting names, for
   instance) picks deterministically without a draw.
5. **GDScript `:=` cannot infer through Variant.** `var n := dict["x"].size()`
   or `:=` from an untyped loop variable is a PARSE error that takes the whole
   class down — and then every caller reports "Nonexistent function" instead
   of the real error. Type such vars explicitly (`var n: int = ...`).
6. **Every settlement capture goes through `CombatRules.capture_settlement`
   AND `fire_occupation_triggers`** (assault, starve-out, AI, player alike).
   Peaceful cessions (`DiplomacyRules.cede_region`) are the deliberate
   exception: no loot, no triggers, garrison marches home.
7. **`NewGame.ensure_state_keys(state, data = null)` grew an optional data
   param** — pass `game.data` on load so pre-knowledge saves receive their
   culture's technique endowment; without it they get empty ledgers. Every
   new state key must appear in build + ensure + fixtures, and readers still
   tolerate its absence.
8. **`GrowthRules._plague_turn(data, state, settlement, rng)` takes state
   now** (plague_resistance is faction-wide) — a merge that drops the param
   compiles nowhere near the bug it causes.
9. **Chronicle recording happens at the CHOKE POINTS** (combat, capture,
   revolt, knowledge, edicts, apply_offer) with the LIVE pre-increment date;
   `ChronicleRules.collect` at the very end derives wars/reigns/destruction
   against the top-of-turn snapshot and stamps entries with the snapshot's
   date. Add new record calls at the acting site, never in the UI, and keep
   collect's fixed order (wars open → close → destroyed → epithets →
   reigns) — reordering changes entry ids and breaks replay byte-compares.
10. **Hot-path readers avoid `.get(key, {})` default allocations** — the
   breakdown paths (order/growth/income) run thousands of times per turn and
   the null-check pattern in `KnowledgeRules.faction_effect_total` /
   `EdictRules.faction_effect_total` / `ModifierRules.sum_for` is what keeps
   end_turn under the 250 ms harness ceiling. Copy that pattern for any new
   per-breakdown effect source; probe with the 60-turn timing in
   `tests/test_ai_campaign.gd` before and after.

## 5. Ways forward

The user has not committed to a direction. Each is self-contained.

### Balance & feel (playtest-driven)
The world is alive — the numbers in `balance.json → ai`, `→ diplomacy`,
`→ knowledge` and `→ edicts` (war hunger, attitude weights, peace pricing,
diffusion/origination odds, reform pressure, upkeep shares) plus the five
personas in `data/ai.json` shipped after soak passes, not a hundred games.
The divergence number the soak prints is a tuning target: raise
diffusion/origination variance and it climbs.

> Here is what felt wrong when I played: <notes>. Tune the balance constants
> and UI accordingly. Run tools/soak.gd before and after.

### The optional online narrator
The chronicle is the machine-readable feed
(`schemas/chronicle_entry.schema.json`, `ChronicleRules.resolved()`); the
annals templates render it offline today. An OPTIONAL online narrator —
prose only, never state — is a self-contained slice: export resolved
entries, send to a model, render the returned prose in the annals panel
with the offline templates as fallback.

### Phase 7 — Senate offices & politics depth
`office_gained` triggers and the `leader_suicide` mission are authored and
allowlisted, waiting for offices, elections, and late-game senate hostility.

> Build Phase 7: senate offices (quaestor→consul ladder with real effects),
> elections on standing, punitive late-game missions, and civil-war depth.

### Phase 3 remainder — the sea
Fleets move and watch but never fight. `blockade_port` missions are authored
and allowlisted.

> Build naval combat and port blockades behind the existing BattleResolver
> pattern, then embark-on-fleet transport replacing the abstracted crossing.

### Real-time battles
The whole game funnels combat through `BattleResolver.resolve(...)` — a battle
scene is a drop-in second implementation.

### AI agents
The engine supports agents fully; the AI deliberately does not use them yet
(§6.2 of DESIGN.md explains why). Giving the AI spies before sieges and
assassins after wars start — with counterplay surfaced in the UI — is a
self-contained slice.

If the user reports a problem, **ask for the world seed** — the same seed
reproduces their exact campaign, which makes any bug directly debuggable.

## 6. Known gaps (verified, not guesses)

- **The AI never assigns generals** to its armies (captains lead everything),
  and never shuffles retinues. Man-of-the-hour adoptions still give it the
  occasional led army.
- **AI houses can draw courtship/assassination missions they rarely complete**
  (they propose alliances only when their diplomacy module happens to want
  one) — mission failures cost them standing, which is dynamic but untuned.
- **Sea-zone anchor positions** in `regions.json` are unused — `map_view.gd`
  draws sea lanes from shared-zone membership and never renders zone labels.
- **`blockade_port` and `leader_suicide` missions are dead** until their
  systems exist; `FORWARD_MISSIONS` in `tools/validate_data.py` allowlists
  them, as `FORWARD_TRIGGERS` does `office_gained`.
- **Phase 3 remainder**: embark-on-fleet transport, naval battles, port
  blockades, forts and watchtowers, ambush.
- **Art is placeholder** — coloured circles on a geographic map.

## 7. Process notes

- **Git identity must be `noreply@anthropic.com` / `Claude`** before
  committing, or a stop hook flags the commits as unverified. Develop on the
  branch the session assigns; the one this phase used is
  `claude/project-handoff-familiarization-565ba5`.
- **Run adversarial review agents after building anything substantial.** Three
  reviewers (engine correctness & determinism, UI behaviour, data/doc
  fidelity), each given the research report plus a specific lens, told to run
  the suite themselves, findings-only output. The Phase 4 round found 37 real
  issues the tests had missed; the Phase 5+6 round found 28 more — among them
  four probe-confirmed economy exploits (gifting third-party regions, minting
  tribute from empty purses, stale envoy offers, purchasable peace with the
  rebels) and, chasing one of its test regressions, the peace↔war flap the
  truce memory now prevents. The Deep Strategy round found 24 more — among
  them the senate silently overwriting `popular_standing` every turn (which
  had made ALL edict political tensions dead code), a free enact→repeal
  standing mint, the AI freezing on the four cheapest edicts forever, and
  two epithets that were provably unreachable under one-name-ever. Budget a
  fix commit after each round.
- When adding a rules module, add tests to `tests/` **and** cross-reference
  checks to `tools/validate_data.py` if it introduces a data table. Both gates
  must pass before committing.
- **Balance changes want a soak, not just the suite** — the test harness
  asserts invariants; `tools/soak.gd` shows character. The first AI soak
  looked "green" while producing a world of shopkeepers with zero wars.
