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
	for formation in _battle["formations"]:
		if int(formation["unit"]["strength_pct"]) <= 0:
			continue
		var output: Array = attacker_units if formation["side"] == "attacker" else defender_units
		output.append(formation["unit"].duplicate(true))
	return _battle["result"].duplicate(true)
