class_name BattleResolver
extends RefCounted
## THE swappable battle interface. Campaign code only ever calls resolve() —
## plus the static force_strength() estimate below, which is part of this
## interface precisely so estimates stay resolver-agnostic — and consumes the
## BattleResult dictionary. It never knows whether the battle was
## auto-resolved or fought in a (future) real-time battle scene.
##
## Contract:
##   resolve(data, rng, attacker_units, defender_units, context) -> BattleResult
##
##   attacker_units / defender_units: Arrays of unit dicts
##     {template: String, experience: int 0-9, strength_pct: int 1-100,
##      weapon: int 0-2, armor: int 0-2}
##     weapon/armor are stamped at recruitment from the raising settlement's
##     forges and armouries and travel with the unit; older units and mercenaries
##     may omit them, so read them with .get(..., 0).
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
##     attacker_martial: float,    # owner's martial ethos 0-100 (SocietyRules)
##     defender_martial: float,    # a society oriented toward war fields better
##                                 # soldiers — this is what militarisation BUYS,
##                                 # against everything it costs elsewhere
##   }
##
##   BattleResult: {
##     winner: "attacker"|"defender",
##     attacker_casualty_pct: float, defender_casualty_pct: float,
##     attacker_general_died: bool, defender_general_died: bool,
##     experience_gained: int,
##     # Optional playback keys — consumers read them with .get and must
##     # cope with their absence (a resolver may not narrate):
##     rounds: [{phase: String, attacker_casualty_pct: float,
##       defender_casualty_pct: float, attacker_morale: float,
##       defender_morale: float, breaking: ""|"attacker"|"defender"}, ...],
##     attacker_report / defender_report: per-unit fates in pre-battle
##       order: [{template, strength_before, strength_after, destroyed}, ...]
##   }


func resolve(_data: GameData, _rng: CampaignRng, _attacker_units: Array, _defender_units: Array, _context: Dictionary) -> Dictionary:
	push_error("BattleResolver.resolve is abstract; use AutoResolver or a real-time implementation")
	return {}


static func force_strength(data: GameData, units: Array, general: Variant, experience_pct_per_chevron: float) -> float:
	## Shared strength estimate: soldiers x quality x experience, led by a
	## general profile {command, troop_morale} of EFFECTIVE values (base
	## attributes plus trait and retinue modifiers — see CharacterRules).
	var battle_rules: Dictionary = data.balance["battle"]
	## A unit's weapons/armor stamp (recruit-time arming from city forges and
	## practiced techniques) scales its attack and defense respectively.
	var weapon_pct := float(battle_rules.get("weapon_upgrade_attack_pct", 0.0))
	var armor_pct := float(battle_rules.get("armor_upgrade_defense_pct", 0.0))
	var strength := 0.0
	for unit in units:
		var template: Dictionary = data.units.get(unit["template"], {})
		if template.is_empty():
			continue
		var soldiers := float(template["soldiers"]) * float(unit["strength_pct"]) / 100.0
		var weapon := float(unit.get("weapon", 0)) * weapon_pct / 100.0
		var armor := float(unit.get("armor", 0)) * armor_pct / 100.0
		# Weapons scale what a unit deals, armor what it takes. Morale and the
		# charge stand outside both: better armor does not make braver men.
		var quality := (float(template["attack"]) + float(template.get("missile_attack", 0)) * 0.5) \
				* (1.0 + weapon) \
			+ float(template["defense"]) * (1.0 + armor) \
			+ float(template["morale"]) * 0.5 \
			+ float(template.get("charge", 0)) * 0.25
		var experience_bonus := 1.0 + float(unit["experience"]) * experience_pct_per_chevron / 100.0
		strength += soldiers * quality * experience_bonus
	if general is Dictionary and not (general as Dictionary).is_empty():
		var profile := general as Dictionary
		var character_rules: Dictionary = data.balance["characters"]
		strength *= 1.0 + float(profile.get("command", 0)) \
			* float(battle_rules["general_command_bonus_pct"]) / 100.0
		strength *= 1.0 + float(profile.get("troop_morale", 0)) \
			* float(character_rules["troop_morale_strength_pct_per_point"]) / 100.0
	return strength
