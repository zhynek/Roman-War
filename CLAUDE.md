# Roman War — repo guide for AI assistants

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
- **The realistic procedural 3D direction is the visual standard.** The live
  campaign uses `CampaignLandscape`; characters and art plates use the shared
  procedural model/cache pipeline. Terrain visuals read the same
  `campaign_terrain.json` crossings as the engine. Keep the classic map as a
  comparison option. The separate `RealismStudy` remains a staged art example,
  never a source of campaign rules or hidden force information.
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
