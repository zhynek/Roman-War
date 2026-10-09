extends "marcus_campaign_context.gd"
## Military counsel is a view of the player's evidence, never a command path.
## A viewed battle uses only the panel's detached snapshot, not its worker.
func _init(owner_session) -> void:
	super(owner_session)
	content=JSON.parse_string(FileAccess.get_file_as_string("res://data/gaius.json"))
	lessons=content.lessons
	preference_path="user://gaius_campaign_preferences.cfg"

func create_portrait():
	return preload("res://src/ui/advisors/gaius_portrait.gd").new()

func reading_label() -> String:
	return content.ui.military_reading

func context_snapshot() -> Dictionary:
	var result: Dictionary=super()
	result.advisor={"id":"gaius","role":content.role}
	if result.has("selection"):
		result.selection.erase("factors")
		result.selection.erase("society")
	# The council still carries shared city survey metadata, but this speaker
	# does not receive a second civil-economic factor inventory.
	if result.has("council_session"):result.council_session.erase("shared_factors_key")
	result.erase("order_preview") # The military block carries the same preview once.
	result.military=_military_snapshot()
	result.advisor_reading=_reading(result.military)
	return result

func advisor_reading() -> Dictionary:
	return _reading(_military_snapshot())

func _military_snapshot() -> Dictionary:
	if _battle_visible():return _battle_snapshot()
	var game: Game=session.game
	var screen: Dictionary=_screen()
	var player: String=game.state.player_faction
	var known: Dictionary=game.known_regions()
	var selected: String=screen.get("force","")
	var region: String=screen.get("region","")
	var terrain_from: String=""
	var result: Dictionary={"scope":"visible_campaign_snapshot","force":{},"terrain":{},"order":{},"enemy_presence":[],"omitted":0}
	var own_army: bool=game.state.armies.get(selected,{}).get("owner","")==player
	var own_fleet: bool=game.state.fleets.get(selected,{}).get("owner","")==player
	if own_army or own_fleet:
		result.force=_fields(game.force_summary(selected),["id","kind","region","sea_zone","units","soldiers","upkeep","movement_left","movement_max","forced_march","besieging"])
	elif game.state.settlements.get(region,{}).get("owner","")==player:
		result.force=_fields(game.force_summary("garrison:"+region),["id","kind","region","units","soldiers","upkeep"])
	if own_army and session.active_view=="campaign":
		var preview: Dictionary={}
		var target: String=session.campaign._pinned_target
		if target!="" and known.has(target):
			preview=game.army_order_preview(selected,target,session.campaign._forced_order)
			region=target
		else:preview=game.queued_march_preview(selected)
		if not preview.is_empty():
			var route: Array=preview.get("path",[])
			var destination: String=String(preview.get("target",""))
			if known.has(destination):
				region=destination
				if not route.is_empty() and String(route.back())==region:
					terrain_from=String(route[route.size()-2]) if route.size()>1 else String(result.force.region)
				elif MapRules.are_adjacent(game.data,String(result.force.region),region):
					terrain_from=String(result.force.region)
			result.order=_fields(preview,["action","from","target","forced","cost","turns","blocked","reason","uncertain"])
			result.order.path=route.slice(0,24)
			result.order.path_omitted=maxi(0,route.size()-result.order.path.size())
	if known.has(region):
		result.terrain=_fields(game.terrain_report(region,terrain_from),["terrain","movement","defense","crossing","observed"])
		result.terrain.region=region
		result.terrain.name=game.data.regions[region].name
		if terrain_from!="":result.terrain.from=terrain_from
		else:result.terrain.erase("crossing")
		if result.terrain.has("movement") and not is_finite(float(result.terrain.movement)):result.terrain.erase("movement")
	var visible: Dictionary=game.visible_armies()
	var ids: Array=visible.keys()
	ids.sort()
	var count:=0
	for id in ids:
		var army: Dictionary=game.state.armies[id]
		if army.owner==player or not DiplomacyRules.at_war(game.state,player,String(army.owner)):continue
		count+=1
		if result.enemy_presence.size()<int(content.limits.context_forces):
			# Visible presence does not authorize the force_summary roster reader.
			result.enemy_presence.append({"id":id,"owner":army.owner,"region":army.region})
	result.omitted=maxi(0,count-result.enemy_presence.size())
	return result

func _battle_snapshot() -> Dictionary:
	var panel=session.city.battle_panel
	var snapshot: Dictionary=panel.snapshot
	var result: Dictionary={"scope":"displayed_tactical_snapshot","battle":_fields(snapshot,["active","phase","paused","elapsed_ms","gate_integrity","objective_progress","practice","tick"]),
		"selected_formations":[],"selected_formations_omitted":0,"enemy_presence":[],"omitted":0}
	var selected: Array=panel.selected_ids.duplicate()
	if panel.selected!="" and not selected.has(panel.selected):selected.append(panel.selected)
	var visible_count:=0
	var selected_count:=0
	for formation in snapshot.get("formations",[]):
		if formation.get("side","")=="defender":
			if not selected.has(formation.get("id","")):continue
			selected_count+=1
			if result.selected_formations.size()<int(content.limits.context_forces):
				var own: Dictionary=_fields(formation,["id","role","morale","routed","engaged","moving","formation","order"])
				own.name=panel.formation_name(formation)
				result.selected_formations.append(own)
		elif formation.get("side","")=="attacker" and formation.get("revealed",false):
			visible_count+=1
			if result.enemy_presence.size()<int(content.limits.context_forces):
				result.enemy_presence.append(_fields(formation,["id","position"]))
	result.omitted=maxi(0,visible_count-result.enemy_presence.size())
	result.selected_formations_omitted=maxi(0,selected_count-result.selected_formations.size())
	return result

func _reading(snapshot: Dictionary) -> Dictionary:
	var words: Dictionary=content.ui
	var result: Dictionary={"title":words.reading_title,"note":words.reading_source,"sections":[]}
	if snapshot.scope=="displayed_tactical_snapshot":
		result.note=words.reading_battle
		result.sections.append({"title":words.reading_battle_status,"lines":_lines(snapshot.battle,["phase","paused","gate_integrity","objective_progress","practice"])})
		if snapshot.selected_formations.is_empty():result.sections.append({"title":words.reading_formations,"lines":[words.reading_no_formations]})
		for formation in snapshot.selected_formations:
			result.sections.append({"title":formation.name,"lines":_lines(formation,["role","morale","routed","engaged","moving","formation","order"])})
		if snapshot.selected_formations_omitted>0:
			result.sections.append({"title":words.reading_formations,"lines":[String(words.reading_limit).format({"limit":content.limits.context_forces})]})
	else:
		result.sections.append({"title":words.reading_own_force,"lines":_lines(snapshot.force,["kind","units","soldiers","upkeep","movement_left","movement_max","forced_march","besieging"]) if not snapshot.force.is_empty() else [words.reading_no_force]})
		result.sections.append({"title":snapshot.terrain.get("name",words.reading_ground),"lines":_lines(snapshot.terrain,["from","terrain","movement","defense","crossing","observed"]) if not snapshot.terrain.is_empty() else [words.reading_no_terrain]})
		if not snapshot.order.is_empty():result.sections.append({"title":words.reading_order,"lines":_lines(snapshot.order,["action","from","target","cost","turns","blocked","reason","uncertain"])})
	var presence: Array=[String(words.reading_presence_note).format({"count":snapshot.enemy_presence.size()})]
	if snapshot.omitted>0:presence.append(String(words.reading_limit).format({"limit":content.limits.context_forces}))
	presence.append(words.reading_scope)
	result.sections.append({"title":words.reading_presence,"lines":presence})
	return result

func _lines(source: Dictionary,keys: Array) -> Array:
	var words: Dictionary=content.ui
	var lines: Array=[]
	for key in keys:
		if not source.has(key):continue
		var value=source[key]
		var display: String=String(words.reading_unknown) if value==null else str(value)
		if value is bool:display=String(words.field_true if value else words.field_false)
		elif value is String:
			if key in ["from","target"] and session.game.data.regions.has(value):display=session.game.data.regions[value].name
			else:display=String(value).replace("_"," ").capitalize()
		lines.append(String(words.reading_field).format({"label":words.get("field_"+String(key),key),"value":display}))
	return lines
