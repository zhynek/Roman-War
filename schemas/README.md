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
- Settlement `effects` keys, benefits: `law, happiness, growth, health, trade_pct,
  farm_income, mine_income, recruit_xp, drill, weapon_upgrade, armor_upgrade,
  wall_level, road_level, port_level` (`law`/`happiness`/`growth`/`health` are
  percentage points; `*_income` are denarii per turn; `recruit_xp` is the best
  tier's value; `weapon_upgrade`/`armor_upgrade` sum across chains up to
  `balance.recruitment.upgrade_max` plus any cap-raising technique; `drill` sums
  and feeds garrison policing and softens levy strain).
- Unit classes: `infantry, spear, pike, missile, cavalry, horse_archer, chariot,
  elephant, siege, ship, general_bodyguard, peasant` — each needs a record in
  `unit_classes.json` (matchups, terrain, assault, wall_defense, garrison_weight,
  mass). A `ship` may only stand in a settlement's `harbour` (coastal regions
  only) or in a fleet; any other class may only stand in a `garrison` or an
  army; `general_bodyguard` is never recruitable — it comes with the man.
  Armies and fleets hold at most `balance.recruitment.army_unit_cap` units.
- Unit attributes: `forest_ambusher, war_cry, phalanx, testudo, terrifies_foot,
  terrifies_horse, sapper, hardy, fast_moving, shield_wall` — each needs an
  effects record in `unit_classes.json` (percentages, additive), a glossary
  entry and a `unit_art.json` cue.
- Techniques (`techniques.json`): flat `effects` keys are summed faction-wide
  (`KnowledgeRules.faction_effect_total`); military techniques may add a `war`
  block of per-class tables (`class_stats`, `matchups`, `terrain`, `upkeep_pct`,
  `recruit_xp`, `fatigue_immune`) and prerequisites drawn from the faction's war
  record (`era`, `battles_won`, `battles_lost`, `faced {class, battles}`); an
  optional `factions` list closes a tradition to those courts. Every effect key
  must have an engine reader, which the validator checks.
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
