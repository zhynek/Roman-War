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
- **Growth and public order are summed factor lists** returning named
  breakdowns, not opaque numbers — the UI will render the breakdowns.
- **Campaign code may only call `BattleResolver.resolve(...)`** — never assume
  auto-resolve specifics.

## Workflow

- Validate data: `python3 tools/validate_data.py` (schema + cross-reference checks).
- Run tests: `godot --headless --path . --script res://tests/run_tests.gd`
  (CI downloads Godot 4.4.1; locally any 4.4+ works).
- Both must pass before committing. New data tables need a schema and
  cross-reference checks in `tools/validate_data.py`; new rules need tests.

## Conventions

- ids: lowercase `snake_case`, unique within their table; building *level* ids
  are globally unique across all chains.
- Cultures: `roman, greek, eastern, carthaginian, egyptian, barbarian, neutral`.
- Settlement levels (ordered): `village, town, large_town, minor_city,
  large_city, huge_city`.
- Building chains have a `kind` (e.g. `government, walls, barracks, farms,
  temple`); units reference requirements by `kind` + level, never by chain id.
- Clean-room: original names/descriptions/values only; historical terms
  (hastati, Latium, Jupiter) are fine, copied game text/data/assets are not.
