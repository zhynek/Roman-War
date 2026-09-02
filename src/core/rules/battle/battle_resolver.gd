class_name BattleResolver
extends RefCounted
## THE swappable battle interface. Campaign code only ever calls resolve() and
## consumes the BattleResult dictionary — it never knows whether the battle was
## auto-resolved or fought in a (future) real-time battle scene.
##
## Contract:
##   resolve(data, rng, attacker_units, defender_units, context) -> BattleResult
##
##   attacker_units / defender_units: Arrays of unit dicts
##     {template: String, experience: int 0-9, strength_pct: int 1-100,
##      weapon: int 0-3 (optional), armor: int 0-3 (optional)}
##     Mutated IN PLACE: casualties reduce strength_pct, destroyed units are
##     removed, survivors may gain experience.
##
##   context: {
##     terrain: String,            # terrain of the battle region
##     wall_level: int,            # 0 in the field; settlement wall tier if assault
##     attacker_general: Dictionary|null,   # {command, troop_morale}, effective values
##     defender_general: Dictionary|null,
##     attacker_fatigued: bool,    # forced march
##     sally: bool,                # defenders sallying out of a siege
##     attacker_mods: ArmyMods,    # optional; faction doctrines etc., pre-merged
##     defender_mods: ArmyMods,    #   campaign-side so the resolver stays state-free
##   }
##   ArmyMods: {
##     class_stats: {class: {attack, defense, morale, charge, missile_attack}},
##     matchup_pct: {class: {versus_class: pct}},
##     terrain_pct: {class|"all": {terrain: pct}},
##     strength_pct, attacking_pct, assault_pct, wall_defense_pct,
##     pursuit_pct, escape_pct: number,  fatigue_immune: bool
##   }  — every key optional.
##
##   BattleResult: {
##     winner: "attacker"|"defender",
##     attacker_casualty_pct: float, defender_casualty_pct: float,
##     attacker_general_died: bool, defender_general_died: bool,
##     experience_gained: int,
##     breakdown: {attacker: SideEstimate, defender: SideEstimate, ratio: float,
##                 fortune: {attacker: float, defender: float}},
##   }
##
## estimate(data, attacker_units, defender_units, context) is the shared,
## RNG-free half of the model: every resolver (and the UI's odds preview)
## reads the same strengths, factor lists and per-unit profiles from it.
##
##   SideEstimate: {
##     strength: float,            # before the fortune roll
##     soldiers: int,
##     factors: [{label, value}],  # multiplicative; "base" carries the raw
##                                 #   soldiers x quality sum, every other value
##                                 #   is a multiplier (only those != 1.0 listed)
##     rows: [{class, units, soldiers, share, matchup, terrain}],  # per class
##     units: [UnitProfile],       # aligned with the unit array
##     shares: {class: share}, pursuit: float,
##   }


func resolve(_data: GameData, _rng: CampaignRng, _attacker_units: Array, _defender_units: Array, _context: Dictionary) -> Dictionary:
	push_error("BattleResolver.resolve is abstract; use AutoResolver or a real-time implementation")
	return {}


## --- Shared estimation (no RNG, no state) -----------------------------------

static func estimate(data: GameData, attacker_units: Array, defender_units: Array, context: Dictionary) -> Dictionary:
	var attacker_shares := ArmyRules.shares(data, attacker_units)
	var defender_shares := ArmyRules.shares(data, defender_units)
	var attacker := side_estimate(data, attacker_units, defender_shares, context, true)
	var defender := side_estimate(data, defender_units, attacker_shares, context, false)
	var ratio := 1.0
	if attacker["strength"] > 0.0 and defender["strength"] > 0.0:
		ratio = attacker["strength"] / defender["strength"]
	return {
		"attacker": attacker,
		"defender": defender,
		"ratio": ratio,
		"attacker_win_chance": win_chance(attacker["strength"], defender["strength"],
			float(data.balance["battle"]["randomness_pct"])),
	}


static func side_estimate(data: GameData, units: Array, enemy_shares: Dictionary, context: Dictionary, is_attacker: bool) -> Dictionary:
	## One side's strength as a chain of named multipliers over the raw
	## soldiers x quality sum. Per-unit stages come first (so a countered
	## cavalry unit and an uncountered spear unit each carry their own number),
	## then the side-wide modifiers.
	var battle_rules: Dictionary = data.balance["battle"]
	var mods: Dictionary = _mods_of(context, is_attacker)
	var terrain: String = context.get("terrain", "plains")
	var wall_level := int(context.get("wall_level", 0))
	var fatigued: bool = is_attacker and bool(context.get("attacker_fatigued", false))
	var own_shares := ArmyRules.shares(data, units)

	var stages: Array = ["base", "upgrades", "doctrines", "experience", "matchups", "class_terrain",
		"assault" if is_attacker else "wall_defense", "attacking", "fatigue"]
	var sums: Array = []
	for stage in stages:
		sums.append(0.0)

	var profiles: Array = []
	var soldiers_total := 0
	var pursuit_weighted := 0.0
	var slots := 0.0
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var profile := unit_profile(data, unit, mods, terrain, enemy_shares, is_attacker, wall_level, fatigued)
		if profile.is_empty():
			continue
		profile["index"] = index
		profiles.append(profile)
		soldiers_total += int(profile["soldiers"])
		var weight := float(unit["strength_pct"]) / 100.0
		pursuit_weighted += float(profile["pursuit"]) * weight
		slots += weight
		var chain: Array = profile["chain"]
		for stage_index in range(chain.size()):
			sums[stage_index] = float(sums[stage_index]) + float(chain[stage_index])

	var factors: Array = [{"label": "base", "value": float(sums[0])}]
	for stage_index in range(1, stages.size()):
		var previous := float(sums[stage_index - 1])
		var value := float(sums[stage_index]) / previous if previous > 0.0 else 1.0
		if absf(value - 1.0) > 0.000001:
			factors.append({"label": stages[stage_index], "value": value})
	var strength := float(sums[sums.size() - 1])

	# --- side-wide multipliers ---
	var general = context.get("attacker_general" if is_attacker else "defender_general")
	if general is Dictionary and not (general as Dictionary).is_empty():
		var profile_general := general as Dictionary
		var character_rules: Dictionary = data.balance["characters"]
		var general_factor := (1.0 + float(profile_general.get("command", 0))
				* float(battle_rules["general_command_bonus_pct"]) / 100.0) \
			* (1.0 + float(profile_general.get("troop_morale", 0))
				* float(character_rules["troop_morale_strength_pct_per_point"]) / 100.0)
		strength = _apply_factor(factors, "general", general_factor, strength)

	if not is_attacker:
		strength = _apply_factor(factors, "terrain",
			float(battle_rules["terrain_defense_multiplier"].get(terrain, 1.0)), strength)
		var wall_multipliers: Array = battle_rules["wall_defense_multiplier"]
		strength = _apply_factor(factors, "walls",
			float(wall_multipliers[mini(wall_level, wall_multipliers.size() - 1)]), strength)

	strength = _apply_factor(factors, "combined_arms", combined_arms_factor(data, units), strength)

	var doctrine_scalar := 1.0 + float(mods.get("strength_pct", 0.0)) / 100.0
	if is_attacker:
		doctrine_scalar *= 1.0 + float(mods.get("attacking_pct", 0.0)) / 100.0
	if absf(doctrine_scalar - 1.0) > 0.000001:
		strength *= doctrine_scalar
		_merge_factor(factors, "doctrines", doctrine_scalar)

	if not is_attacker and bool(context.get("sally", false)):
		strength = _apply_factor(factors, "sally",
			1.0 + float(data.balance["siege"]["sally_strength_bonus_pct"]) / 100.0, strength)

	var rows := _class_rows(profiles, own_shares)
	return {
		"strength": strength,
		"soldiers": soldiers_total,
		"factors": factors,
		"rows": rows,
		"units": profiles,
		"shares": own_shares,
		"pursuit": pursuit_weighted / slots if slots > 0.0 else 1.0,
	}


static func unit_profile(data: GameData, unit: Dictionary, mods: Dictionary, terrain: String, enemy_shares: Dictionary, is_attacker: bool, wall_level: int, fatigued: bool = false) -> Dictionary:
	## Everything the model knows about one unit card in this battle. `chain`
	## holds the unit's strength after each per-unit stage (see side_estimate),
	## the rest are the multipliers themselves — the hook a real-time battle
	## scene reuses for effective stats. {} for an unknown template.
	var template: Dictionary = data.units.get(unit["template"], {})
	if template.is_empty():
		return {}
	var battle_rules: Dictionary = data.balance["battle"]
	var unit_class: String = template.get("class", "")
	var class_record: Dictionary = data.unit_classes.get(unit_class, {})
	var attribute_effects := _attribute_effects(data, template)
	var soldiers := float(template["soldiers"]) * float(unit["strength_pct"]) / 100.0

	# 1. base quality from the template alone.
	var base_quality := _quality(template, {}, 0.0, 0.0)
	# 2. weapon / armour upgrades stamped on the unit.
	var weapon_bonus := float(unit.get("weapon", 0)) * float(battle_rules["weapon_upgrade_attack_per_level"])
	var armor_bonus := float(unit.get("armor", 0)) * float(battle_rules["armor_upgrade_defense_per_level"])
	var upgraded_quality := _quality(template, {}, weapon_bonus, armor_bonus)
	# 3. doctrine stat deltas for this class.
	var class_stats: Dictionary = mods.get("class_stats", {}).get(unit_class, {})
	var modded_quality := _quality(template, class_stats, weapon_bonus, armor_bonus)
	# 4. experience.
	var experience_factor := 1.0 + float(unit["experience"]) \
		* float(battle_rules["experience_strength_pct_per_chevron"]) / 100.0
	# 5. matchups against the enemy's composition.
	var matchup := matchup_factor(data, unit_class, attribute_effects, mods, enemy_shares)
	# 6. per-class terrain.
	var terrain_factor := class_terrain_factor(data, unit_class, attribute_effects, mods, terrain)
	# 7. walls, by class.
	var wall_factor := 1.0
	if wall_level > 0:
		if is_attacker:
			wall_factor = float(class_record.get("assault", 1.0)) \
				* (1.0 + float(attribute_effects.get("assault_pct", 0.0)) / 100.0) \
				* (1.0 + float(mods.get("assault_pct", 0.0)) / 100.0)
		else:
			wall_factor = float(class_record.get("wall_defense", 1.0)) \
				* (1.0 + float(attribute_effects.get("wall_defense_pct", 0.0)) / 100.0) \
				* (1.0 + float(mods.get("wall_defense_pct", 0.0)) / 100.0)
	# 8. attacking (war cries and the like fire only when charging).
	var attacking_factor := 1.0
	if is_attacker:
		attacking_factor = 1.0 + float(attribute_effects.get("attacking_pct", 0.0)) / 100.0
	# 9. fatigue, unless the unit or its doctrine shrugs it off.
	var fatigue_factor := 1.0
	if fatigued and not bool(mods.get("fatigue_immune", false)) \
			and not bool(attribute_effects.get("fatigue_immune", false)):
		fatigue_factor = float(battle_rules["fatigue_multiplier"])

	var chain: Array = []
	var running := soldiers * base_quality
	chain.append(running)
	running = soldiers * upgraded_quality
	chain.append(running)
	running = soldiers * modded_quality
	chain.append(running)
	for factor in [experience_factor, matchup, terrain_factor, wall_factor, attacking_factor, fatigue_factor]:
		running *= factor
		chain.append(running)

	var speed_offset := float(template.get("speed", 5)) - 5.0
	var pursuit := 1.0 + speed_offset * float(battle_rules["pursuit_pct_per_speed_point"]) / 100.0 \
		+ float(attribute_effects.get("pursuit_pct", 0.0)) / 100.0 \
		+ float(mods.get("pursuit_pct", 0.0)) / 100.0
	var escape := 1.0 + speed_offset * float(battle_rules["escape_pct_per_speed_point"]) / 100.0 \
		+ float(attribute_effects.get("escape_pct", 0.0)) / 100.0 \
		+ float(mods.get("escape_pct", 0.0)) / 100.0
	return {
		"template": unit["template"],
		"class": unit_class,
		"soldiers": int(ceil(soldiers)),
		"quality": modded_quality,
		"experience": experience_factor,
		"matchup": matchup,
		"terrain": terrain_factor,
		"walls": wall_factor,
		"attacking": attacking_factor,
		"fatigue": fatigue_factor,
		"strength": running,
		"pursuit": maxf(pursuit, float(battle_rules["pursuit_min"])),
		"escape": maxf(escape, float(battle_rules["escape_min"])),
		"chain": chain,
	}


static func matchup_factor(data: GameData, unit_class: String, attribute_effects: Dictionary, mods: Dictionary, enemy_shares: Dictionary) -> float:
	## 1 + (Σ enemy share x matrix cell − 1) x matchup_weight. The matrix cell
	## for a pair is the class table's entry times the unit's attribute and
	## doctrine percentages against that enemy class.
	if enemy_shares.is_empty() or unit_class == "":
		return 1.0
	var class_record: Dictionary = data.unit_classes.get(unit_class, {})
	var matrix: Dictionary = class_record.get("matchups", {})
	var attribute_matchups: Dictionary = attribute_effects.get("matchups", {})
	var doctrine_matchups: Dictionary = mods.get("matchup_pct", {}).get(unit_class, {})
	var weighted := 0.0
	for enemy_class in enemy_shares:
		var cell := 1.0
		if enemy_class != unit_class:
			cell = float(matrix.get(enemy_class, 1.0))
		cell *= 1.0 + float(attribute_matchups.get(enemy_class, 0.0)) / 100.0
		cell *= 1.0 + float(doctrine_matchups.get(enemy_class, 0.0)) / 100.0
		weighted += float(enemy_shares[enemy_class]) * cell
	var weight := float(data.balance["battle"]["matchup_weight"])
	return 1.0 + (weighted - 1.0) * weight


static func class_terrain_factor(data: GameData, unit_class: String, attribute_effects: Dictionary, mods: Dictionary, terrain: String) -> float:
	var class_record: Dictionary = data.unit_classes.get(unit_class, {})
	var raw := float(class_record.get("terrain", {}).get(terrain, 1.0))
	raw *= 1.0 + float(attribute_effects.get("terrain", {}).get(terrain, 0.0)) / 100.0
	var doctrine_terrain: Dictionary = mods.get("terrain_pct", {})
	raw *= 1.0 + float(doctrine_terrain.get(unit_class, {}).get(terrain, 0.0)) / 100.0
	raw *= 1.0 + float(doctrine_terrain.get("all", {}).get(terrain, 0.0)) / 100.0
	var weight := float(data.balance["battle"]["terrain_class_weight"])
	return 1.0 + (raw - 1.0) * weight


static func combined_arms_factor(data: GameData, units: Array) -> float:
	## A line to hold, a shock arm to break the enemy and missiles to wear him
	## down, each at least a minimum share of the cards, fight better together.
	var battle_rules: Dictionary = data.balance["battle"]
	var min_share := float(battle_rules["combined_arms_min_share_pct"]) / 100.0
	var roles := ArmyRules.role_shares(data, units)
	for role in Constants.COMBINED_ARMS_ROLES:
		if float(roles.get(role, 0.0)) + 0.000001 < min_share:
			return 1.0
	return 1.0 + float(battle_rules["combined_arms_bonus_pct"]) / 100.0


static func win_chance(attacker_strength: float, defender_strength: float, randomness_pct: float) -> float:
	## Probability that attacker x X beats defender x Y for independent uniform
	## fortune rolls X, Y in [1 - p, 1 + p] — i.e. how often the dice overturn
	## the paper result. Deterministic midpoint integration, no RNG.
	if attacker_strength <= 0.0:
		return 0.0
	if defender_strength <= 0.0:
		return 1.0
	var spread := clampf(randomness_pct / 100.0, 0.0, 0.99)
	if spread <= 0.0:
		return 1.0 if attacker_strength > defender_strength else 0.0
	var low := 1.0 - spread
	var high := 1.0 + spread
	var threshold := defender_strength / attacker_strength  # attacker wins iff X > threshold * Y
	var steps := 256
	var width := (high - low) / steps
	var area := 0.0
	for i in range(steps):
		var y := low + (i + 0.5) * width
		area += maxf(0.0, high - maxf(low, threshold * y))
	return clampf(area * width / ((high - low) * (high - low)), 0.0, 1.0)


static func _quality(template: Dictionary, class_stats: Dictionary, weapon_bonus: float, armor_bonus: float) -> float:
	var attack := float(template["attack"]) + weapon_bonus + float(class_stats.get("attack", 0.0))
	var defense := float(template["defense"]) + armor_bonus + float(class_stats.get("defense", 0.0))
	var morale := float(template["morale"]) + float(class_stats.get("morale", 0.0))
	var charge := float(template.get("charge", 0)) + float(class_stats.get("charge", 0.0))
	var missile := float(template.get("missile_attack", 0)) + float(class_stats.get("missile_attack", 0.0))
	return maxf(attack, 0.0) + maxf(missile, 0.0) * 0.5 + maxf(defense, 0.0) \
		+ maxf(morale, 0.0) * 0.5 + maxf(charge, 0.0) * 0.25


static func _attribute_effects(data: GameData, template: Dictionary) -> Dictionary:
	## The unit's attribute effects merged: percentages add, flags OR.
	var merged := {"matchups": {}, "terrain": {}}
	for attribute_id in template.get("attributes", []):
		var effects: Dictionary = data.unit_attributes.get(attribute_id, {}).get("effects", {})
		for key in effects:
			var value = effects[key]
			if value is Dictionary:
				var bucket: Dictionary = merged.get(key, {})
				for sub_key in value:
					bucket[sub_key] = float(bucket.get(sub_key, 0.0)) + float(value[sub_key])
				merged[key] = bucket
			elif value is bool:
				merged[key] = bool(merged.get(key, false)) or value
			else:
				merged[key] = float(merged.get(key, 0.0)) + float(value)
	return merged


static func _mods_of(context: Dictionary, is_attacker: bool) -> Dictionary:
	var mods = context.get("attacker_mods" if is_attacker else "defender_mods", {})
	return mods if mods is Dictionary else {}


static func _apply_factor(factors: Array, label: String, value: float, strength: float) -> float:
	if absf(value - 1.0) > 0.000001:
		factors.append({"label": label, "value": value})
		return strength * value
	return strength


static func _merge_factor(factors: Array, label: String, value: float) -> void:
	for factor in factors:
		if factor["label"] == label:
			factor["value"] = float(factor["value"]) * value
			return
	factors.append({"label": label, "value": value})


static func _class_rows(profiles: Array, own_shares: Dictionary) -> Array:
	var by_class := {}
	for profile in profiles:
		var unit_class: String = profile["class"]
		var row: Dictionary = by_class.get(unit_class,
			{"class": unit_class, "units": 0.0, "soldiers": 0, "share": 0.0, "matchup": 0.0, "terrain": 0.0})
		var weight := float(profile["chain"][0]) / maxf(float(profile["quality"]), 0.000001)  # ~ soldiers
		row["units"] = float(row["units"]) + 1.0
		row["soldiers"] = int(row["soldiers"]) + int(profile["soldiers"])
		row["matchup"] = float(row["matchup"]) + float(profile["matchup"])
		row["terrain"] = float(row["terrain"]) + float(profile["terrain"])
		by_class[unit_class] = row
	var rows: Array = []
	var classes: Array = by_class.keys()
	classes.sort()
	for unit_class in classes:
		var row: Dictionary = by_class[unit_class]
		var count := float(row["units"])
		row["matchup"] = float(row["matchup"]) / count
		row["terrain"] = float(row["terrain"]) / count
		row["share"] = float(own_shares.get(unit_class, 0.0))
		rows.append(row)
	return rows
