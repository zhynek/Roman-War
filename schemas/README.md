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
- Settlement `effects` keys: `law, happiness, growth, health, trade_pct,
  farm_income, mine_income, recruit_xp, weapon_upgrade, armor_upgrade,
  wall_level, road_level, port_level` (`law`/`happiness`/`growth`/`health` are
  percentage points; `*_income` are denarii per turn).
- Years are astronomical integers: 270 BC = `-270`, AD 14 = `14`.
- Agent kinds (`agents.json`) name their training requirement by building
  kind + level like units do, and list engine actions from the closed
  vocabulary `negotiate, bribe, watch, open_gates, counter_espionage,
  assassinate, sabotage`. `campaign.json` seeds each faction's starting agents
  by kind id and region.
- Character effect keys read by agents: `personal_security` (harder to
  assassinate) and `agent_skill` (a governor's retinue adds it to his city's
  counter-intelligence).

Cross-file references (checked by `tools/validate_data.py`, not by JSON Schema):
region ids, faction ids, culture ids, unit template ids, building level ids,
building chain kinds, sea zone ids, trait/ancillary ids, name pools, agent
kind ids.
