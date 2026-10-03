class_name CityBattleResolver
extends BattleResolver
## A completed tactical fight adapts to the existing siege aftermath contract.
## No second casualty roll, random draw, or change to campaign combat callers.

var _battle: Dictionary


func _init(battle: Dictionary) -> void:
	_battle = battle.duplicate(true)


func resolve(_data: GameData, _rng: CampaignRng, attacker_units: Array, defender_units: Array, _context: Dictionary) -> Dictionary:
	attacker_units.clear()
	defender_units.clear()
	for side in ["attacker","defender"]:
		var output: Array=attacker_units if side=="attacker" else defender_units
		for unit in CityBattleTactics.survivors(_battle,side):
			if int(unit["strength_pct"])>0:output.append(unit)
	return _battle["result"].duplicate(true)
