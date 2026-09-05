# AGENTS.md — Roman War

**This file is the single source of truth for anyone, human or machine, changing
this repository.** Claude Code reads it via `CLAUDE.md`; OpenAI Codex and most
other coding agents read `AGENTS.md` directly. Do not duplicate these rules
anywhere else — edit them here.

Humans should also read [`CONTRIBUTING.md`](CONTRIBUTING.md) for the review and
pull-request process. Agents: read that too, then come back here.

Original clean-room grand-strategy game (Godot 4.4, GDScript). Campaign layer
first; battles behind a `BattleResolver` interface. Full design rationale:
`docs/research/rtw-research-report.md` and `docs/DESIGN.md`.

## Architecture rules (do not violate)

- **Engine is thin, content is data.** Game content (buildings, units, factions,
  regions, traits, events, campaign setup) belongs in `data/*.json`, validated by
  `schemas/*.schema.json`. Never hardcode content in GDScript.
- **All tunable constants live in `data/balance.json`** — never scatter magic
  numbers through rules modules.
- **`src/core/` must stay scene-free and deterministic.** No `Node`, no UI, no
  wall-clock time, no unseeded randomness. Every random draw goes through the
  RNG stored in the game state (`state.rng_state` / `CampaignRng` helper) —
  and any loop whose iteration order can steer an RNG draw must sort its keys
  first, so a loaded save replays exactly like the live game. GameState is a
  plain Dictionary so save/load is JSON round-tripping.
- **Growth, public order and every societal flow are summed factor lists**
  returning named breakdowns, not opaque numbers — the UI renders them directly.
- **The societal layer is the core of the game** (`docs/DESIGN.md` §4;
  `src/core/rules/society.gd`). Eight slow stocks are the only part of the engine
  with memory, and they are what makes a decision weigh something. Two rules
  govern changes to it: it must consume **no randomness** (its uncertainty is
  delay, hysteresis, coupled feedback and partial observability — never dice),
  and any continuous float stored in the state must go through
  `SocietyRules.quantize()`, because Godot's JSON writer does not round-trip an
  arbitrary double and a loaded save would drift from the live game.
- **Every building must buy something and cost something.** The six societal
  effect keys (`civic, coercion, burden, assimilation_pull, knowledge, martial`)
  carry the cost; `civic` is the only one that may be negative. A new effect key
  with no engine reader fails the validator.
- **Turn beats carry ids and numbers, never prose.** Everything the end-turn
  sequence and the Daily Dispatch put on screen comes from `data/dispatch.json`,
  keyed by beat kind. `TurnJournal.KINDS` and that file are checked against each
  other in both directions by the validator.
- **Campaign code may only call `BattleResolver.resolve(...)`** — plus the
  interface's shared `BattleResolver.force_strength(...)` estimate — and never
  assume auto-resolve specifics.
- **Faction-wide effects have four accessors, all the same shape**: buildings
  (`SettlementRules.effect_total` / `effect_max`), wonders
  (`SettlementRules.faction_owns_wonder_effect`), practiced techniques
  (`KnowledgeRules.faction_effect_total`), enacted edicts
  (`EdictRules.faction_effect_total`). A new effect source adds a fifth in that
  shape. Percentages combine **additively on a base component**, never
  compounding — and these run on the per-turn breakdown hot paths, so read them
  with null-checks, not `.get(key, {})` default allocations.
- **Save compatibility is additive.** A new state key is created in
  `NewGame.build`, back-filled in `NewGame.ensure_state_keys`, added to
  `tests/fixtures.gd`, and tolerated via `.get` by every reader — *and emitted
  at every entity-creation site* (births in `family.gd`, mercenaries, senate
  grants). Miss one and a resumed save silently diverges from a live game.
- **The chronicle records where things happen, never in the UI.**
  `ChronicleRules.record(...)` is called at the choke point (combat, capture,
  revolt, knowledge, edicts, `apply_offer`); `ChronicleRules.collect` at the end
  of the turn derives only what needs a before/after diff. Entries are stable
  ids + scalars — the narrator contract in
  `schemas/chronicle_entry.schema.json`. Prose lives in `data/annals.json`.

## Workflow

- **After adding any `class_name` file, re-run
  `godot --headless --path . --import`** — a stale `.godot/` class cache reports
  bogus "not declared in the current scope" / "nonexistent function" errors on
  globals that plainly exist. When confused, `rm -rf .godot` and import cold.
- Validate data: `python3 tools/validate_data.py` (schema + cross-reference checks).
- Run tests: `godot --headless --path . --script res://tests/run_tests.gd`
  (CI downloads Godot 4.4.1; locally any 4.4+ works).
- Both must pass before committing. New data tables need a schema and
  cross-reference checks in `tools/validate_data.py`; new rules need tests.
- `data/map_geometry.json` is **generated** — never hand-edit it. After any
  change to region positions/adjacency or sea-zone anchors in
  `data/regions.json`, rerun `python3 tools/generate_map_geometry.py`
  (fixed seed, byte-stable) and commit the result, or the validator fails.
- Map work is invisible to headless CI: eyeball it with
  `xvfb-run -a godot --path . --script res://tools/screenshot.gd`.

## Conventions

- ids: lowercase `snake_case`, unique within their table; building *level* ids
  are globally unique across all chains.
- Cultures: `roman, greek, eastern, carthaginian, egyptian, barbarian, neutral`.
- Settlement levels (ordered): `village, town, large_town, minor_city,
  large_city, huge_city`.
- Building chains have a `kind` (e.g. `government, walls, barracks, farms,
  temple, armoury`); units reference requirements by `kind` + level, never by
  chain id. A chain may carry `requires_building: {kind, level}`.
- Every unit `class` and `attributes` token needs a record in
  `data/unit_classes.json` (the counter matrix the battle model reads).
- Military techniques keep flat, summed keys in `effects` and per-class tables
  in a `war` block (`schemas/techniques.schema.json`); prerequisites may read
  the faction's `war_record`. Every effect key needs an engine reader.
- **Player-facing sentences are content**: they live in `data/effects_glossary.json`,
  not in GDScript. `src/core/` returns `{kind, params}` and never authors English.
- **There are no image files and none may be added.** Buildings and units are
  drawn at runtime from `data/building_art.json` and `data/unit_art.json` by
  `BuildingArt`/`UnitArt` (resolve) and `ArtPainter` (draw). Never `randf()` in
  art: hash from the id, as `MapGeometry` does, or the picture changes run to run.
- The content tables include `techniques.json` (crafts that spread by contact),
  `edicts.json` (standing policies and decrees), `epithets.json` and
  `annals.json` (the chronicle's names and prose). Each technique, edict and
  epithet carries a `historical_basis`: original prose citing its REAL
  provenance. Invented history is a bug — see `docs/DESIGN.md` §12.
- Clean-room: original names/descriptions/values only; historical terms
  (hastati, Latium, Jupiter) are fine, copied game text/data/assets are not.

## Contributing (agents and humans alike)

This repository is publicly readable but **closed to direct pushes to `main`.**
Every change — including changes made by the repository owner — lands through a
pull request that `@zhynek` reviews and merges. No exceptions, no self-merges.

**The loop:**

1. Branch from the latest `main`. Name it `<topic>` or `<tool>/<topic>`, e.g.
   `society-hysteresis-fix`, `claude/senate-seat-rebalance`, `codex/validator-speedup`.
2. Make the change. Keep it to one coherent idea — a PR that fixes a bug *and*
   rebalances three tables is three PRs.
3. Run **both** gates locally and make them pass:
   ```sh
   python3 tools/validate_data.py
   godot --headless --path . --script res://tests/run_tests.gd
   ```
   A PR that has not run these is not ready, whatever the diff looks like.
4. Open the PR against `main`. Fill in the template honestly — especially the
   box that says which gates you actually ran. "I believe it passes" is not
   the same as "I ran it and it passed"; say which one is true.
5. Wait for review. Do not merge your own pull request.

**Commit messages** in this repository are descriptive sentences, not
Conventional Commits. Look at `git log` and match it: *"Phase 7 review round:
the fixes three adversarial reviews asked for"*, not *"fix(senate): review"*.
Say what changed and why; the diff already says how.

**Attribution.** If a commit was authored with the material help of an AI tool,
record it in a trailer so the history stays honest:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```

Use whatever trailer your tool conventionally emits. Do not put model names,
version strings or session URLs in code comments, data files, or documentation
— trailers and the PR description are the place for that.

## Things an agent must never do here

- **Never push directly to `main`,** and never merge a pull request.
- **Never force-push a branch you did not create.** It invalidates other
  people's checkouts and can destroy review history.
- **Never add an image, audio or font file.** There are none, and none may be
  added — see the art rule in Conventions above. If a change seems to need one,
  it needs a runtime painter instead. Say so in the PR rather than adding a binary.
- **Never hand-edit `data/map_geometry.json`.** It is generated; regenerate it.
- **Never disable, skip or delete a failing test to get a green run.** A red
  test is information. Fix the cause, or explain in the PR why the test itself
  is wrong.
- **Never weaken the clean-room policy.** If you cannot write a description,
  name or value from scratch, leave it blank and flag it. Copied game text is
  the one mistake this project cannot take back.
- **Never commit a secret,** and never add a credential, token or personal file
  path to any tracked file. This repository is public.
- **Never widen a pull request beyond what was asked.** Drive-by refactors in
  an unrelated file make review slower and get PRs rejected.

## When you are unsure

Say so in the pull request rather than guessing. A PR that says *"I could not
tell whether `civic` should be allowed negative here, so I assumed yes — see
line 42"* is far more useful than one that quietly picks an answer. The rules
above are load-bearing: a change that breaks determinism or save compatibility
can be invisible for weeks and then corrupt every save at once.
