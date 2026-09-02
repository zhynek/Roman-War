# Data table schemas

Every file in `data/` validates against the schema of the same name here
(`data/units.json` ↔ `schemas/units.schema.json`). `data/buildings.json` and
`data/temples.json` both validate against `buildings.schema.json`.

Shared conventions (enforced by the schemas and `tools/validate_data.py`):

- ids: lowercase `snake_case` (`^[a-z][a-z0-9_]*$`), unique within their table.
  Building **level** ids are globally unique across every chain in every file.
- Cultures: `roman, greek, eastern, carthaginian, egyptian, barbarian, neutral`.
- Settlement levels (ordered): `village, town, large_town, minor_city,
  large_city, huge_city`.
- Terrain: `plains, forest, hills, mountains, desert, steppe, marsh`.
- Tax levels: `very_low, low, normal, high, very_high`.
- Building chain kinds: `government, walls, barracks, stables, archery_range,
  siege_workshop, naval, market, farms, roads, port, mines, health,
  entertainment, execution, education, temple`.
- Settlement `effects` keys, benefits: `law, happiness, growth, health, trade_pct,
  farm_income, mine_income, recruit_xp, weapon_upgrade, armor_upgrade,
  wall_level, road_level, port_level` (`law`/`happiness`/`growth`/`health` are
  percentage points; `*_income` are denarii per turn).
- Settlement `effects` keys, societal costs: `civic, coercion, burden,
  assimilation_pull, knowledge, martial`. These feed the societal stocks
  (`docs/DESIGN.md` §4) and are what make a building a decision rather than a
  free good. **`civic` is the only key that may be negative** — an amphitheatre
  buys order now and erodes standing slowly. Every one of these keys must have
  an engine reader; the validator fails the build if one goes dead.
- Edict `effects` keys: the settlement keys above, which reach every reader
  through `SettlementRules.effect_total`, plus five that need their own reader —
  `grievance_relief, elite_pressure, income_pct, clarity_bonus, build_cost_pct`.
  Every edict must cost something, in denarii or in a societal stock; the
  validator fails the build on a free one.
- Office `effects` keys: `command, management, influence` — the character
  attributes, added to the holder for the year through
  `CharacterRules.effect_total`. Ranks are unique and contiguous from 1,
  `requires_prior_rank` is 0 or an existing lower rank, exactly one office is
  `eponymous`, an office flagged `for_life` is kept until its holder dies, every
  office buys something, and every office carries a `historical_basis`.
- Years are astronomical integers: 270 BC = `-270`, AD 14 = `14`.

Cross-file references (checked by `tools/validate_data.py`, not by JSON Schema):
region ids, faction ids, culture ids, unit template ids, building level ids,
building chain kinds, sea zone ids, trait/ancillary ids, name pools; map
geometry ↔ regions (territory per region containing its position, one road per
land adjacency); balance terrain tables pinned to the terrain enum.
