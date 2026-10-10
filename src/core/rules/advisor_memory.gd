class_name AdvisorMemoryRules
extends RefCounted
## A bounded projection of saved player history, never a second memory ledger.
## Source references are local to the loaded campaign; readers own no state.

const SUBJECTS := {
	"war_declared":["faction","other_faction"], "battle":["faction","other_faction","region"],
	"city_taken":["faction","other_faction","region"], "city_sacked":["faction","other_faction","region"],
	"city_revolted":["faction","region"], "peace_made":["faction","other_faction"],
	"alliance_made":["faction","other_faction"], "technique_originated":["faction","technique"],
	"technique_adopted":["faction","technique"], "edict_enacted":["faction","edict"],
	"edict_lapsed":["faction","edict"], "leader_died":["faction","character"],
	"succession":["faction","character"], "reign_summary":["faction","character"],
	"war_summary":["faction","other_faction"], "faction_destroyed":["faction"],
	"disaster":["faction","region"], "epithet_earned":["faction","character","epithet"],
	"office_taken":["faction","character","office"], "civil_war":["faction"]}
const DETAILS := {"leader_died":["age"],
	"reign_summary":["battles_won","cities_taken","techniques_completed","edicts_enacted"],
	"war_summary":["turns","battles"]}

static func project(data: GameData, state: Dictionary, advisor: String, region: String = "", focus_ref: String = "", compact: bool = true) -> Dictionary:
	# Do not read characters, receipts or evolving state while a battle is live.
	if CityBattleRules.locked(state):return _empty("" if advisor.length() > 64 else advisor,"battle")
	var result := _empty("" if advisor.length() > 64 else advisor,"")
	var content: Dictionary = data.advisor_memory_content
	if not content.get("roles",{}).has(advisor):
		result.blocked = "unknown_advisor"
		return result
	if advisor != "marcus" and not state.get("advisor_unlocks",{}).has(advisor):
		result.blocked = "advisor_locked"
		return result
	var player := String(state.get("player_faction",""))
	var tuning: Dictionary = data.balance.advisor_memory
	if not data.factions.has(player):
		result.blocked = "invalid_campaign"
		return result
	result.as_of = {"turn":int(state.turn),"year":int(state.year),"season":String(state.season) if state.season in ["summer","winter"] else ""}
	result.faction = {"id":player,"name":_short(String(data.factions.get(player,{}).get("name",player)),tuning)}
	result.current_ruler = _current_ruler(data,state,player)
	var selected = state.get("settlements",{}).get(region,{})
	if not selected is Dictionary or selected.get("owner","") != player:region = ""
	var candidates: Array = []
	var reigns: Array = []
	var seen := {}
	for raw in state.get("chronicle",[]):
		var item := _chronicle(data,state,raw,player)
		if item.is_empty() or seen.has(item.source_ref):continue
		seen[item.source_ref] = true
		if item.kind == "reign_summary":reigns.append(item)
		else:candidates.append(item)
	_receipts(data,state,candidates)
	var priorities: Array = content.roles[advisor].priorities
	candidates.sort_custom(func(a,b):
		if (a.source_ref == focus_ref) != (b.source_ref == focus_ref):return a.source_ref == focus_ref
		if (a.region == region and region != "") != (b.region == region and region != ""):return a.region == region and region != ""
		var pa: int = priorities.find(a.kind)
		var pb: int = priorities.find(b.kind)
		if pa < 0:pa = priorities.size()
		if pb < 0:pb = priorities.size()
		if pa != pb:return pa < pb
		return _newer(a,b))
	reigns.sort_custom(func(a,b):
		if (a.source_ref == focus_ref) != (b.source_ref == focus_ref):return a.source_ref == focus_ref
		return _newer(a,b))
	result.eligible_count = candidates.size()
	var record_limit := int(tuning.compact_records if compact else tuning.page_records)
	result.records = candidates.slice(0,record_limit)
	result.previous_reigns = reigns.slice(0,int(tuning.previous_reigns))
	result.focus_found = _has_ref(candidates,focus_ref) or _has_ref(reigns,focus_ref)
	result.focus_ref = focus_ref if result.focus_found else ""
	_update_omissions(result,candidates.size(),reigns.size())
	var budget := int(tuning.compact_bytes if compact else tuning.page_bytes)
	# Drop nonfocused previous reigns first, then the lowest-ranked regular
	# records. Recompute counts on every shrink so the entire result fits.
	while JSON.stringify(result).to_utf8_buffer().size() > budget:
		var dropped := false
		for index in range(result.previous_reigns.size()-1,-1,-1):
			if result.previous_reigns[index].source_ref != result.focus_ref:
				result.previous_reigns.remove_at(index)
				dropped = true
				break
		if not dropped and not result.records.is_empty():
			result.records.pop_back()
			dropped = true
		if not dropped and not result.previous_reigns.is_empty():
			result.previous_reigns.pop_back()
			dropped = true
		_update_omissions(result,candidates.size(),reigns.size())
		if not dropped:break # base metadata is bounded below the validated budget
	result.focus_found = _has_ref(result.records,focus_ref) or _has_ref(result.previous_reigns,focus_ref)
	if not result.focus_found:result.focus_ref = ""
	return result

static func _empty(advisor: String, blocked: String) -> Dictionary:
	return {"scope":"saved_campaign_records","blocked":blocked,"advisor":advisor,
		"as_of":{},"history_complete":false,"faction":{},"current_ruler":{},
		"previous_reigns":[],"records":[],"eligible_count":0,"omitted_count":0,
		"previous_reigns_omitted":0,"focus_ref":"","focus_found":false}

static func _current_ruler(data: GameData, state: Dictionary, player: String) -> Dictionary:
	var ids: Array = state.get("characters",{}).keys()
	ids.sort()
	for id in ids:
		if not id is String or id.to_utf8_buffer().size() > int(data.balance.advisor_memory.max_name_chars):continue
		var person = state.characters[id]
		if not person is Dictionary or person.get("alive") != true or person.get("faction","") != player or person.get("role","") != "leader":continue
		if not person.get("name") is String or String(person.name).strip_edges() == "":continue
		var result := {"id":String(id),"name":_short(person.name,data.balance.advisor_memory),"since_turn":null}
		var reign = state.factions[player].get("reign",{})
		if reign is Dictionary and reign.get("leader","") == id and _whole(reign.get("since_turn"),0,int(state.turn)):
			result.since_turn = int(reign.since_turn)
		return result
	return {}

static func _chronicle(data: GameData, state: Dictionary, raw: Variant, player: String) -> Dictionary:
	if not raw is Dictionary:return {}
	if not raw.get("kind") is String or not SUBJECTS.has(raw.kind):return {}
	if not _whole(raw.get("id"),1,2147483647) or not _whole(raw.get("turn"),0,int(state.turn)):return {}
	if not _whole(raw.get("year"),-100000,100000) or raw.get("season","") not in ["summer","winter"]:return {}
	var subjects = raw.get("subjects")
	var details = raw.get("details")
	if not subjects is Dictionary or not details is Dictionary:return {}
	# Global annals are not a fog boundary. Restrict involvement BEFORE resolving
	# any names, and never export the raw battle/capture details dictionary.
	if subjects.get("faction","") != player and subjects.get("other_faction","") != player:return {}
	var values := {}
	for key in SUBJECTS[raw.kind]:
		if not subjects.get(key) is String:return {}
		var label := _name(data,state,key,subjects[key],player)
		if label == "":return {}
		values[key] = label
	for key in DETAILS.get(raw.kind,[]):
		if not _whole(details.get(key),0,2147483647):return {}
		values[key] = int(details[key])
	var content: Dictionary = data.advisor_memory_content
	var year := int(raw.year)
	var date := String(content.ui.date).format({"season":content.ui[raw.season],
		"year":String(content.ui.year_bc if year < 0 else content.ui.year_ad).format({"year":absi(year)})})
	var summary := String(content.templates[raw.kind]).format(values)
	return _record(data,"chronicle:%d" % int(raw.id),"chronicle",raw.kind,int(raw.turn),date,summary,String(subjects.get("region","")) if "region" in SUBJECTS[raw.kind] else "")

static func _receipts(data: GameData, state: Dictionary, candidates: Array) -> void:
	var content: Dictionary = data.advisor_memory_content
	var ledger = state.get("divine_dilemmas",{})
	var resolved: Dictionary = ledger.get("resolved",{}) if ledger is Dictionary and ledger.get("resolved",{}) is Dictionary else {}
	for profile in data.divine_dilemma_content.get("dilemmas",[]):
		var receipt = resolved.get(profile.id)
		if not receipt is Dictionary or not _whole(receipt.get("turn"),0,int(state.turn)) or not receipt.get("region") is String:continue
		var region := _name(data,state,"region",receipt.region,state.player_faction)
		if region == "":continue
		var choice_label := ""
		for choice in profile.choices:
			if choice.id == receipt.get("choice",""):choice_label = _short(choice.label,data.balance.advisor_memory)
		if choice_label == "":continue
		var summary := String(content.templates.divine_choice).format({"region":region,
			"dilemma":_short(profile.title,data.balance.advisor_memory),"choice":choice_label})
		var item := _record(data,"dilemma:"+String(profile.id),"dilemma","divine_choice",int(receipt.turn),
			String(content.ui.date_turn).format({"turn":int(receipt.turn)}),summary,receipt.region)
		if not item.is_empty():candidates.append(item)
	var patronage = state.get("patronage",{})
	var completed: Dictionary = patronage.get("completed",{}) if patronage is Dictionary and patronage.get("completed",{}) is Dictionary else {}
	var ids: Array = completed.keys()
	ids.sort()
	for id in ids:
		if not id is String or not data.patrons.has(id) or not _whole(completed[id],0,int(state.turn)):continue
		var summary := String(content.templates.patron_honor).format({"patron":_short(data.patrons[id].name,data.balance.advisor_memory)})
		var item := _record(data,"honor:"+id,"honor","patron_honor",int(completed[id]),
			String(content.ui.date_turn).format({"turn":int(completed[id])}),summary,"")
		if not item.is_empty():candidates.append(item)

static func _name(data: GameData, state: Dictionary, key: String, id: String, player: String) -> String:
	var record: Dictionary = {}
	match key:
		"faction","other_faction":record = data.factions.get(id,{})
		"region":record = data.regions.get(id,{})
		"technique":record = data.techniques.get(id,{})
		"edict":record = data.edicts.get(id,{})
		"epithet":record = data.epithets.get(id,{})
		"office":record = data.offices.get(id,{})
		"character":
			var person = state.get("characters",{}).get(id)
			if not person is Dictionary or person.get("faction","") != player:return ""
			record = person
	var label = record.get("settlement_name" if key == "region" else "name")
	return _short(label,data.balance.advisor_memory) if label is String else ""

static func _record(data: GameData, ref: String, source: String, kind: String, turn: int, date: String, summary: String, region: String) -> Dictionary:
	if summary.length() > int(data.balance.advisor_memory.max_summary_chars):return {}
	return {"source_ref":ref,"source":source,"kind":kind,"turn":turn,"date":date,"summary":summary,"region":region}

static func _short(value: String, tuning: Dictionary) -> String:
	return value.replace("\n"," ").replace("\r"," ").left(int(tuning.max_name_chars))

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _newer(a: Dictionary, b: Dictionary) -> bool:
	if a.turn != b.turn:return a.turn > b.turn
	return String(a.source_ref) < String(b.source_ref)

static func _has_ref(records: Array, ref: String) -> bool:
	if ref == "":return false
	for item in records:
		if item.source_ref == ref:return true
	return false

static func _update_omissions(result: Dictionary, total: int, reigns: int) -> void:
	result.omitted_count = total - result.records.size()
	result.previous_reigns_omitted = reigns - result.previous_reigns.size()
