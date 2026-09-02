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
  siege_workshop, armoury, naval, market, farms, roads, port, mines, health,
  entertainment, execution, education, temple`. A chain may carry
  `requires_building: {kind, level}` — buildable only where the settlement
  already holds that kind at that tier (armouries need a barracks).
- Settlement `effects` keys: `law, happiness, growth, health, trade_pct,
  farm_income, mine_income, recruit_xp, drill, weapon_upgrade, armor_upgrade,
  wall_level, road_level, port_level` (`law`/`happiness`/`growth`/`health` are
  percentage points; `*_income` are denarii per turn; `recruit_xp` is the best
  tier's value, `weapon_upgrade`/`armor_upgrade` sum across chains up to
  `balance.recruitment.upgrade_max`, `drill` sums and feeds garrison policing).
- Unit classes: `infantry, spear, pike, missile, cavalry, horse_archer, chariot,
  elephant, siege, ship, general_bodyguard, peasant` — each needs a record in
  `unit_classes.json` (matchups, terrain, assault, wall_defense, garrison_weight).
- Unit attributes: `can_hide_forest, warcry, phalanx, testudo, frighten_infantry,
  frighten_cavalry, can_sap, hardy, fast_moving, shield_wall` — each needs an
  effects record in `unit_classes.json` (percentages, additive).
- Years are astronomical integers: 270 BC = `-270`, AD 14 = `14`.

Cross-file references (checked by `tools/validate_data.py`, not by JSON Schema):
region ids, faction ids, culture ids, unit template ids, building level ids,
building chain kinds, sea zone ids, trait/ancillary ids, name pools.
