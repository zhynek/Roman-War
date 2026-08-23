class_name ArmyRules
## Army lifecycle shared by the player UI and the AI: fielding a garrison (or
## part of one) as a marching army. The reverse — merging an army back into a
## garrison — lives in CombatRules.garrison_army.


static func form_army(data: GameData, state: Dictionary, region_id: String, unit_indices: Array = [], general_id: String = "") -> String:
	## Pull garrison units out into a new field army. Empty unit_indices takes
	## the whole garrison. A newly mustered army marches next season
	## (movement_left 0), which keeps field/garrison shuffling honest.
	## Returns the new army id, or "" if nothing could be fielded.
	if not state["settlements"].has(region_id):
		return ""
	var settlement: Dictionary = state["settlements"][region_id]
	var garrison: Array = settlement["garrison"]
	if garrison.is_empty():
		return ""

	var indices: Array = []
	if unit_indices.is_empty():
		for i in range(garrison.size()):
			indices.append(i)
	else:
		var seen := {}
		for raw_index in unit_indices:
			var index := int(raw_index)
			if index < 0 or index >= garrison.size() or seen.has(index):
				return ""
			seen[index] = true
			indices.append(index)
	indices.sort()

	var units: Array = []
	for index in indices:
		units.append(garrison[index])
	for i in range(indices.size() - 1, -1, -1):
		garrison.remove_at(indices[i])

	var general = null
	if general_id != "" and _can_lead(data, state, settlement["owner"], region_id, general_id):
		general = general_id

	var army_id := "army_%d" % state["next_id"]
	state["next_id"] += 1
	state["armies"][army_id] = {
		"owner": settlement["owner"],
		"region": region_id,
		"units": units,
		"general": general,
		"movement_left": 0.0,
		"forced_march": false,
	}
	return army_id


static func transfer_garrison_to_army(state: Dictionary, region_id: String, army_id: String, unit_index: int, unit_cap: int) -> bool:
	## Move one garrison unit into a friendly army standing in the region.
	if not state["settlements"].has(region_id) or not state["armies"].has(army_id):
		return false
	var settlement: Dictionary = state["settlements"][region_id]
	var army: Dictionary = state["armies"][army_id]
	if army["owner"] != settlement["owner"] or army["region"] != region_id:
		return false
	if unit_index < 0 or unit_index >= settlement["garrison"].size():
		return false
	if army["units"].size() >= unit_cap:
		return false
	army["units"].append(settlement["garrison"][unit_index])
	settlement["garrison"].remove_at(unit_index)
	return true


static func _can_lead(data: GameData, state: Dictionary, owner: String, region_id: String, char_id: String) -> bool:
	## Only a co-located adult male of the owning house takes command, and never
	## one already at the head of another army.
	var character: Dictionary = state["characters"].get(char_id, {})
	if character.is_empty() or not character["alive"]:
		return false
	if character["faction"] != owner or character.get("location", "") != region_id:
		return false
	if character["role"] not in ["leader", "heir", "family"]:
		return false
	if character.get("gender", "male") != "male":
		return false
	if int(character["age"]) < int(data.balance["characters"]["come_of_age"]):
		return false
	for army in state["armies"].values():
		if army["general"] == char_id:
			return false
	return true
