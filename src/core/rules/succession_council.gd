class_name SuccessionCouncilRules
extends RefCounted
## One saved invitation and frozen handover for the current ruler. Only the
## authoritative season close captures facts; reads and responses consume no RNG.

static func fresh(state: Dictionary) -> Dictionary:
	var turn := int(state.get("turn",0))
	return {"baseline_turn":turn,"last_checked_turn":turn,
		"leader":_leader(state),
		"detected_turn":turn,"status":"silent","postponed_until":turn,"briefing":{}}

static func ensure(state: Dictionary) -> void:
	if not state.has("advisor_succession"):state.advisor_succession = fresh(state)

static func blocked(data: GameData, state: Dictionary) -> String:
	if CityBattleRules.locked(state):return "battle_active"
	if state.get("winner") != null:return "campaign_finished"
	for region in state.get("settlements",{}):
		if CityBattleRules.pending_defense(data,state,region):return "defense_pending"
	return ""

static func status(data: GameData, state: Dictionary) -> Dictionary:
	var reason := blocked(data,state)
	var result := {"blocked":reason,"available":false,"eligible":false,"key":"",
		"status":"silent","postponed_until":0,"briefing":{},"turn":int(state.get("turn",0))}
	if reason != "":return result
	var ledger: Dictionary = state.get("advisor_succession",{})
	if ledger.is_empty():return result
	var leader := _leader(state)
	if leader == "" or leader != ledger.get("leader",""):
		result.status = "stale"
		return result
	result.status = ledger.get("status","silent")
	result.postponed_until = int(ledger.get("postponed_until",0))
	if result.status == "silent" or ledger.get("briefing",{}).is_empty():return result
	result.available = true
	result.eligible = result.status == "pending" and result.postponed_until <= result.turn
	result.key = _key(state,ledger)
	result.briefing = ledger.briefing.duplicate(true)
	return result

static func respond(data: GameData, state: Dictionary, key: String, action: String) -> bool:
	if action not in ["acknowledge","dismiss","postpone"]:return false
	var page := status(data,state)
	if not page.available or page.key != key or page.status != "pending":return false
	var ledger: Dictionary = state.advisor_succession
	if action == "postpone":
		var until := int(state.turn) + int(data.balance.succession_council.postpone_turns)
		if int(ledger.postponed_until) >= until:return false
		ledger.postponed_until = until
	else:
		ledger.status = "acknowledged" if action == "acknowledge" else "dismissed"
	return true

static func reconcile(data: GameData, state: Dictionary, resolved: Dictionary) -> void:
	ensure(state)
	var ledger: Dictionary = state.advisor_succession
	if int(state.turn) <= int(ledger.last_checked_turn):return
	ledger.last_checked_turn = int(state.turn)
	var leader := _leader(state)
	# Preserve the last ruler during a vacancy. The first ever ruler establishes
	# a silent baseline, including character-free fixtures and older campaigns.
	if leader == "" or leader == ledger.leader:return
	if ledger.leader == "":
		ledger.leader = leader
		return
	var previous := String(ledger.leader)
	ledger.leader = leader
	ledger.detected_turn = int(state.turn)
	ledger.status = "pending"
	ledger.postponed_until = int(state.turn)
	ledger.briefing = _capture(data,state,resolved,previous,leader)

static func _key(state: Dictionary, ledger: Dictionary) -> String:
	return JSON.stringify([state.player_faction,state.get("world_seed",0),ledger.leader,int(ledger.detected_turn)]).sha256_text()

static func _capture(data: GameData, state: Dictionary, resolved: Dictionary, previous: String, leader: String) -> Dictionary:
	var tuning: Dictionary = data.balance.succession_council
	var player := String(state.player_faction)
	var faction: Dictionary = state.factions[player]
	var ruler := _person(state,leader,tuning)
	var reign: Dictionary = faction.get("reign",{})
	ruler.since_turn = null
	if reign.get("leader","") == leader and AdvisorMemoryRules._whole(reign.get("since_turn"),0,int(state.turn)):
		ruler.since_turn = int(reign.since_turn)
	var result := {"scope":"first_resolved_season_of_reign","facts_source":"resolved_campaign_state",
		"resolved_season":{"turn":int(resolved.turn),"year":int(resolved.year),"season":String(resolved.season)},
		"captured_turn":int(state.turn),"faction":{"id":player,"name":_short(data.factions.get(player,{}).get("name",player),tuning)},
		"predecessor":_person(state,previous,tuning),"ruler":ruler,"treasury":int(faction.treasury),
		"wars":[],"taxes":[],"edicts":[],"patron":{},"history":[],"history_complete":false,
		"omitted":{"wars":0,"edicts":0,"history":0}}
	var enemies: Array = faction.get("diplomacy",{}).keys()
	enemies.sort()
	for other in enemies:
		if faction.diplomacy[other] != "war" or not data.factions.has(other):continue
		if result.wars.size() >= int(tuning.max_wars):
			result.omitted.wars += 1
			continue
		result.wars.append({"id":other,"name":_short(data.factions[other].name,tuning),"source_ref":"diplomacy:" + player + ":" + String(other)})
	var taxes := {}
	var regions: Array = state.settlements.keys()
	regions.sort()
	for region in regions:
		var city: Dictionary = state.settlements[region]
		if city.owner != player:continue
		var level := String(city.tax_level)
		if level in Constants.TAX_LEVELS:taxes[level] = int(taxes.get(level,0)) + 1
		var edict := EdictRules.of(city)
		if edict.id == "" or not data.edicts.has(edict.id):continue
		if result.edicts.size() >= int(tuning.max_edicts):
			result.omitted.edicts += 1
			continue
		result.edicts.append({"region":region,"city":_short(data.regions.get(region,{}).get("settlement_name",region),tuning),
			"id":edict.id,"name":_short(data.edicts[edict.id].name,tuning),"turns_held":int(edict.turns_held)})
	for level in Constants.TAX_LEVELS:
		if taxes.has(level):result.taxes.append({"level":level,"count":int(taxes[level])})
	var patron := PatronageRules.status(data,state)
	if data.patrons.has(patron.get("chosen","")):
		var chosen := String(patron.chosen)
		result.patron = {"id":chosen,"name":_short(data.patrons[chosen].name,tuning),
			"progress":int(patron.progress),"target":int(patron.target),"completed":patron.completed.has(chosen)}
	var memory := AdvisorMemoryRules.project(data,state,"marcus")
	var records: Array = memory.get("records",[])
	result.history = records.slice(0,int(tuning.max_history))
	var reigns: Array = memory.get("previous_reigns",[])
	if not reigns.is_empty():result.history.append(reigns[0].duplicate(true))
	result.omitted.history = int(memory.get("eligible_count",0)) + reigns.size() + int(memory.get("previous_reigns_omitted",0)) - result.history.size()
	# Byte cap includes metadata and all frozen labels. Trim complete records,
	# preserving honest omission counts; never truncate a source into a claim.
	while JSON.stringify(result).to_utf8_buffer().size() > int(tuning.snapshot_bytes):
		if not result.history.is_empty():
			result.history.pop_back()
			result.omitted.history += 1
		elif not result.edicts.is_empty():
			result.edicts.pop_back()
			result.omitted.edicts += 1
		elif not result.wars.is_empty():
			result.wars.pop_back()
			result.omitted.wars += 1
		else:break
	return result

static func _leader(state: Dictionary) -> String:
	var id := ChronicleRules.leader_of(state,String(state.player_faction))
	# Unknown oversized legacy identifiers cannot become an unbounded snapshot.
	return id if id.to_utf8_buffer().size() <= 128 else ""

static func _person(state: Dictionary, id: String, tuning: Dictionary) -> Dictionary:
	var person: Dictionary = state.get("characters",{}).get(id,{})
	return {"id":id,"name":_short(person.get("name",id),tuning)}

static func _short(value: Variant, tuning: Dictionary) -> String:
	return String(value).left(int(tuning.max_name_chars))
