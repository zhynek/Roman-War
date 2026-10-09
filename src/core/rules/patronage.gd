class_name PatronageRules
extends RefCounted
## Optional player-only narrative mandates. No rewards, costs or random draws.
## Reads never reconcile progress; only the resolved season does so.

static func neutral() -> Dictionary:
	return {"chosen":"", "pledged_turn":0, "baseline_owned":0, "progress":0,
		"last_checked_turn":0, "completed":{}}

static func command_blocked(data: GameData, state: Dictionary) -> String:
	if CityBattleRules.locked(state):return "battle_active"
	if state.get("winner") != null:return "campaign_finished"
	for region in state.get("settlements", {}):
		if CityBattleRules.pending_defense(data,state,region):return "defense_pending"
	return ""

static func status(data: GameData, state: Dictionary) -> Dictionary:
	# Never traverse evolving economic/ownership state while a battle is active.
	if CityBattleRules.locked(state):
		return {"chosen":"", "active":{}, "options":[], "completed":{},
			"progress":0, "target":0, "command_blocked":"battle_active"}
	var saved: Dictionary = state.get("patronage", neutral())
	var result: Dictionary = saved.duplicate(true)
	result.options = []
	result.active = {}
	result.owned_count = _owned_count(state)
	result.command_blocked = command_blocked(data,state)
	result.target = 0
	result.has_matching_temple = false
	var ids: Array = data.patrons.keys()
	ids.sort()
	for id in ids:
		var option: Dictionary = data.patrons[id].duplicate(true)
		option.temples = _temples(data,state,option)
		option.eligible = not option.temples.is_empty()
		option.completed = saved.get("completed",{}).has(id)
		option.target = _target(data,option)
		option.minimum_order = data.balance.patronage.minimum_order
		option.mission = String(option.mission).format({"target":option.target,
			"minimum_order":option.minimum_order})
		result.options.append(option)
		if id == saved.get("chosen", ""):
			result.active = option.duplicate(true)
			result.target = option.target
			result.has_matching_temple = option.eligible
	return result

static func pledge(data: GameData, state: Dictionary, patron_id: String, region_id: String) -> bool:
	if command_blocked(data,state) != "" or not data.patrons.has(patron_id):return false
	var current: Dictionary = state.get("patronage", neutral())
	if current.get("chosen", "") == patron_id:return false
	var matches := false
	for temple in _temples(data,state,data.patrons[patron_id]):
		if temple.region == region_id:matches = true
	if not matches:return false
	var chosen := neutral()
	chosen.chosen = patron_id
	chosen.pledged_turn = int(state.turn)
	chosen.last_checked_turn = int(state.turn)
	chosen.baseline_owned = _owned_count(state)
	chosen.completed = current.get("completed",{}).duplicate(true)
	state.patronage = chosen
	return true

static func renounce(data: GameData, state: Dictionary) -> bool:
	if command_blocked(data,state) != "":return false
	var current: Dictionary = state.get("patronage", neutral())
	if String(current.get("chosen", "")) == "":return false
	var cleared := neutral()
	cleared.completed = current.get("completed",{}).duplicate(true)
	state.patronage = cleared
	return true

static func reconcile(data: GameData, state: Dictionary) -> void:
	var saved: Dictionary = state.get("patronage", {})
	var id := String(saved.get("chosen", ""))
	if id == "" or not data.patrons.has(id):return
	var turn := int(state.turn)
	if turn <= int(saved.get("last_checked_turn",turn)):return
	var prior_turn := int(saved.last_checked_turn)
	saved.last_checked_turn = turn
	if saved.completed.has(id):return
	var profile: Dictionary = data.patrons[id]
	var temples := _temples(data,state,profile)
	var target := _target(data,profile)
	if profile.kind == "stewardship":
		var qualified := false
		for temple in temples:
			var city: Dictionary = state.settlements[temple.region]
			if city.tax_level in data.balance.patronage.allowed_tax_levels \
				and PublicOrderRules.total(data,state,temple.region) >= float(data.balance.patronage.minimum_order):
				qualified = true
		# A skipped season is not evidence of continuous stewardship.
		var prior_progress := int(saved.progress) if prior_turn == turn - 1 else 0
		saved.progress = mini(target,prior_progress + 1) if qualified else 0
	elif profile.kind == "expansion":
		saved.progress = mini(target,maxi(0,_owned_count(state) - int(saved.baseline_owned))) if not temples.is_empty() else 0
	if int(saved.progress) >= target:
		saved.completed[id] = turn

static func _target(data: GameData, profile: Dictionary) -> int:
	return int(data.balance.patronage.stewardship_seasons if profile.kind == "stewardship" else data.balance.patronage.expansion_settlements)

static func _owned_count(state: Dictionary) -> int:
	var count := 0
	for city in state.get("settlements", {}).values():
		if city.owner == state.player_faction:count += 1
	return count

static func _temples(data: GameData, state: Dictionary, profile: Dictionary) -> Array:
	var result: Array = []
	var regions: Array = state.get("settlements", {}).keys()
	regions.sort()
	for region in regions:
		var city: Dictionary = state.settlements[region]
		if city.owner != state.player_faction:continue
		for chain_id in profile.temple_chains:
			var level := int(city.get("buildings", {}).get(chain_id,0))
			var chain: Dictionary = data.chains.get(chain_id,{})
			if level > 0 and chain.get("kind", "") == "temple" and level <= chain.get("levels",[]).size():
				result.append({"region":region,"chain":chain_id,"level":level})
	return result
