class_name AdvisorTutorialRules
extends RefCounted
## Campaign-owned invitations: authoritative commands and season resolution
## record evidence; rendering and reading never advance this ledger or RNG.

static func fresh(turn: int = 0, legacy: bool = false) -> Dictionary:
	var result := {"baseline_turn":turn,"last_checked_turn":turn,
		"strain_active":legacy,"milestones":{}}
	if legacy and turn > 0:
		result.milestones.first_season = {"status":"acknowledged","turn":turn,
			"params":{"region":"","subject":"","value":0},"postponed_until":turn}
	return result

static func ensure(data: GameData, state: Dictionary) -> void:
	if state.has("advisor_tutorial"):return
	state.advisor_tutorial = fresh(int(state.turn),true)
	if data != null:
		state.advisor_tutorial.strain_active = not _strain(data,state).is_empty()

static func blocked(data: GameData, state: Dictionary) -> String:
	if CityBattleRules.locked(state):return "battle_active"
	for region in state.get("settlements",{}):
		if CityBattleRules.pending_defense(data,state,region):return "defense_pending"
	return ""

static func status(data: GameData, state: Dictionary) -> Dictionary:
	if CityBattleRules.locked(state):return {"blocked":"battle_active","eligible":[],"milestones":[]}
	var ledger: Dictionary = state.get("advisor_tutorial",fresh(int(state.turn),true))
	var result := {"blocked":blocked(data,state),"turn":int(state.turn),"baseline_turn":int(ledger.baseline_turn),
		"eligible":[],"milestones":[]}
	for profile in data.reactive_tutorial.get("milestones",[]):
		var card: Dictionary = profile.duplicate(true)
		var record: Dictionary = ledger.milestones.get(profile.id,{})
		card.status = record.get("status","unseen")
		card.turn = int(record.get("turn",ledger.baseline_turn))
		card.params = record.get("params",{}).duplicate(true)
		card.postponed_until = int(record.get("postponed_until",0))
		result.milestones.append(card)
		if result.blocked == "" and card.status == "pending" and card.postponed_until <= int(state.turn):
			result.eligible.append(card.duplicate(true))
	return result

static func record(data: GameData, state: Dictionary, id: String, params: Dictionary = {}) -> void:
	if not _known(data,id):return
	ensure(data,state)
	var ledger: Dictionary = state.advisor_tutorial
	if ledger.milestones.has(id):return
	ledger.milestones[id] = {"status":"pending","turn":int(state.turn),
		"params":{"region":String(params.get("region","")),
			"subject":String(params.get("subject","")),"value":int(params.get("value",0))},
		"postponed_until":int(state.turn)}

static func respond(data: GameData, state: Dictionary, id: String, action: String) -> bool:
	if blocked(data,state) != "" or not _known(data,id):return false
	if action not in ["acknowledge","dismiss","postpone"]:return false
	var ledger: Dictionary = state.get("advisor_tutorial",{})
	var item: Dictionary = ledger.get("milestones",{}).get(id,{})
	if item.get("status","") != "pending":return false
	if action == "postpone":
		var until := int(state.turn) + int(data.balance.advisor_tutorial.postpone_turns)
		if int(item.postponed_until) >= until:return false
		item.postponed_until = until
	else:
		item.status = "acknowledged" if action == "acknowledge" else "dismissed"
	return true

static func reconcile(data: GameData, state: Dictionary, journal: Array) -> void:
	ensure(data,state)
	var ledger: Dictionary = state.advisor_tutorial
	var turn := int(state.turn)
	if turn <= int(ledger.last_checked_turn):return
	ledger.last_checked_turn = turn
	record(data,state,"first_season")
	var player := String(state.player_faction)
	for beat in journal:
		var ours: bool = beat.get("faction","") == player
		var involved: bool = ours or beat.get("other","") == player
		var kind := String(beat.get("kind",""))
		var params := {"region":String(beat.get("region","")),
			"subject":String(beat.get("subject","")),"value":int(beat.get("value",0))}
		if ours and kind == "building_completed":record(data,state,"construction",params)
		elif ours and kind == "unit_mustered":record(data,state,"army",params)
		elif ours and kind in ["march_arrived","march_onward","march_halted"]:
			if not beat.get("extra",{}).get("traversed",[]).is_empty():record(data,state,"army",params)
		elif involved and kind in ["war_declared","battle_fought","assault_repelled","settlement_captured"]:
			record(data,state,"war",params)
	var strain := _strain(data,state)
	if not strain.is_empty() and not bool(ledger.strain_active):record(data,state,"strain",strain)
	ledger.strain_active = not strain.is_empty()

static func _known(data: GameData, id: String) -> bool:
	for profile in data.reactive_tutorial.get("milestones",[]):
		if profile.id == id:return true
	return false

static func _strain(data: GameData, state: Dictionary) -> Dictionary:
	var tuning: Dictionary = data.balance.get("advisor_tutorial",{})
	if tuning.is_empty():return {}
	var player := String(state.player_faction)
	var treasury := int(state.factions[player].treasury)
	if treasury < int(tuning.strain_treasury_below):
		return {"region":"","subject":"treasury","value":treasury}
	var regions: Array = state.settlements.keys()
	regions.sort()
	for region in regions:
		if state.settlements[region].owner != player:continue
		var order := PublicOrderRules.total(data,state,region)
		if order < float(tuning.strain_order_below):
			return {"region":region,"subject":"public_order","value":int(floor(order))}
	return {}
