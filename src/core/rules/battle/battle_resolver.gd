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
##     {template: String, experience: int 0-9, strength_pct: int 1-100}
##     Mutated IN PLACE: casualties reduce strength_pct, destroyed units are
##     removed, survivors may gain experience.
##
##   context: {
##     terrain: String,            # terrain of the battle region
##     wall_level: int,            # 0 in the field; settlement wall tier if assault
##     attacker_general: Dictionary|null,   # character dict (command matters)
##     defender_general: Dictionary|null,
##     attacker_fatigued: bool,    # forced march
##     sally: bool,                # defenders sallying out of a siege
##   }
##
##   BattleResult: {
##     winner: "attacker"|"defender",
##     attacker_casualty_pct: float, defender_casualty_pct: float,
##     attacker_general_died: bool, defender_general_died: bool,
##     experience_gained: int,
##   }


func resolve(_data: GameData, _rng: CampaignRng, _attacker_units: Array, _defender_units: Array, _context: Dictionary) -> Dictionary:
	push_error("BattleResolver.resolve is abstract; use AutoResolver or a real-time implementation")
	return {}


static func force_strength(data: GameData, units: Array, general: Variant, experience_pct_per_chevron: float) -> float:
	## Shared strength estimate: soldiers x quality x experience, plus command.
	var strength := 0.0
	for unit in units:
		var template: Dictionary = data.units.get(unit["template"], {})
		if template.is_empty():
			continue
		var soldiers := float(template["soldiers"]) * float(unit["strength_pct"]) / 100.0
		var quality := float(template["attack"]) + float(template.get("missile_attack", 0)) * 0.5 \
			+ float(template["defense"]) + float(template["morale"]) * 0.5 \
			+ float(template.get("charge", 0)) * 0.25
		var experience_bonus := 1.0 + float(unit["experience"]) * experience_pct_per_chevron / 100.0
		strength += soldiers * quality * experience_bonus
	if general is Dictionary and not (general as Dictionary).is_empty():
		strength *= 1.0 + float((general as Dictionary).get("command", 0)) * 0.05
	return strength
