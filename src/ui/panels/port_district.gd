class_name PortDistrict
extends PortDialog
## Local exploration and campaign commands share this window, never a second sim.
var district_view: PortDistrictView
var overview: VBoxContainer
var selection := "landing_shelter"
var facts: Dictionary = {}
var layout_key := ""
var receipt := ""
var bound_state: Dictionary
var poll := 0.0
var state_key := ""
var leaving := false

func open_for(current: Game, target: String) -> void:
	game = current
	region = target
	bound_state = game.state
	if not _allowed():
		queue_free()
		return
	theme = UiStyle.build_theme()
	title = "%s — %s" % [words("district_title"),game.data.regions[region]["settlement_name"]]
	size = Vector2i(1260,790)
	min_size = Vector2i(1060,700)
	transient = true
	exclusive = true
	close_requested.connect(_close)
	var background := ColorRect.new()
	background.color = UiStyle.BG_DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,14)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",14)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	heading = label(left,"")
	heading.add_theme_font_size_override("font_size",22)
	var toolbar := HBoxContainer.new()
	left.add_child(toolbar)
	button(toolbar,words("command_view"),func(): district_view.set_mode("command"))
	button(toolbar,words("explore_view"),func(): district_view.set_mode("explore"))
	button(toolbar,words("follow"),func():
		district_view.follow = true
		district_view.pan = Vector3(district_view.representative.x,0,district_view.representative.y)
		district_view._pose()
		_save_visit())
	button(toolbar,words("stop_walk"),func():
		district_view.path.clear()
		district_view._draw_route()
		_save_visit())
	button(toolbar,words("plans"),_open_plans)
	for control in toolbar.get_children():
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.custom_minimum_size.x = 105
	district_view = PortDistrictView.new()
	view = district_view
	district_view.text = game.data.effects_glossary["ports"]
	district_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	district_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(district_view)
	district_view.selected.connect(func(id):
		selection = id
		_details())
	district_view.notice.connect(func(key): status.text = words(key))
	district_view.preferences_changed.connect(_save_visit)
	status = label(left,words("local_party"))
	label(left,words("district_controls"))
	label(left,words("district_legend"))
	button(left,words("close"),_close)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 375
	columns.add_child(right)
	var overview_scroll := ScrollContainer.new()
	overview_scroll.custom_minimum_size.y = 260
	overview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(overview_scroll)
	overview = VBoxContainer.new()
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_scroll.add_child(overview)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",8)
	scroll.add_child(details)
	_refresh()
	popup_centered()

func _allowed() -> bool:
	return game != null and is_same(game.state,bound_state) and not CityBattleRules.locked(game.state) and game.state.get("settlements",{}).get(region,{}).get("owner","") == game.state.get("player_faction","") and PortRules.stage(game.data,game.state,region)>0

func _close() -> void:
	if leaving:
		return
	leaving = true
	_save_visit()
	hide()
	queue_free()

func _open_plans() -> void:
	if not _allowed():
		return
	var inspector := PortDialog.new()
	get_parent().add_child(inspector)
	inspector.changed.connect(func():
		_refresh()
		changed.emit())
	inspector.tree_exited.connect(func():
		if _allowed():
			show()
			_refresh())
	hide()
	inspector.open_for(game,region)

func _exit_tree() -> void:
	_save_visit()

func _save_visit() -> void:
	if _allowed() and is_instance_valid(district_view) and district_view.restored:
		if not game.state.has("port_visits"):
			game.state["port_visits"] = {}
		game.state["port_visits"][region] = district_view.visit()

func _process(delta: float) -> void:
	if game == null or leaving:
		return
	if not _allowed():
		_close()
		return
	poll += delta
	if poll < 0.4:
		return
	poll = 0
	_save_visit()
	var key := _campaign_key()
	if key != state_key:
		_refresh()

func _campaign_key() -> String:
	return JSON.stringify([game.state["turn"],game.state["settlements"][region],game.state.get("ports",{}).get(region,{}),game.state["fleets"],game.state["armies"],game.state["factions"],game.state["factions"][game.state["player_faction"]]["treasury"]])

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _refresh() -> void:
	if not _allowed():
		_close()
		return
	var architecture := PortRules.snapshot(game.data,game.state,region)
	var key := JSON.stringify([architecture["stage"],architecture["facilities"],architecture["setting"]])
	if key != layout_key:
		layout_key = key
		district_view.configure(PortLayout.build(game.data,region,architecture),PortRules.rules(game.data)["district"],game.state.get("port_visits",{}).get(region,{}))
	facts = PortOperations.snapshot(game.data,game.state,region,district_view.plan)
	district_view.show_operations(facts,game.data,game.state)
	heading.text = words("stage",{"stage":architecture["stage"],"name":stage_name(architecture["stage"])})
	_overview()
	_details()
	state_key = _campaign_key()

func _target(candidates: Array) -> String:
	for id in candidates:
		for site in district_view.sites:
			if site["id"] == id:
				return id
	return "landing_shelter"

func _focus_row(caption_text: String, candidates: Array) -> void:
	var id := _target(candidates)
	var control := button(overview,caption_text,func(): district_view.focus_site(id))
	control.custom_minimum_size.y = 30

func _overview() -> void:
	_clear(overview)
	var caps := PortRules.capabilities(game.data,game.state,region)
	var setting := PortRules.site(game.data,region)
	label(overview,words("site",{"setting":words(setting["setting"]),"depth":words("deep" if setting["deep_water"] else "shallow")}))
	var built := PackedStringArray()
	for id in PortRules.facilities(game.data,game.state,region):
		built.append(_facility_name(id))
	label(overview,words("specialization",{"name":", ".join(built) if not built.is_empty() else words("general_port")}))
	_focus_row(words("blockade_clear") if facts["blockaders"].is_empty() else words("blockade_summary",{"count":facts["blockaders"].size()}),["arsenal","landing_berth"])
	var project: Dictionary = facts["project"]
	_focus_row(words("works_empty") if project.is_empty() else words("project",{"name":stage_name(project["rank"]) if project["kind"]=="stage" else _facility_name(project["kind"]),"turns":project["turns"]}),["civic_hall","customs"])
	_focus_row(words("queue_overview",{"count":facts["queue"].size()}),["boatbuilder"])
	_focus_row(words("berth_overview",{"count":game.state["settlements"][region]["harbour"].size(),"waiting":facts["waiting"].size(),"fleets":facts["fleets"].size()}),["landing_berth"])
	_focus_row(words("handling_suspended" if not facts["blockaders"].is_empty() else "handling",{"remaining":PortRules.handling_left(game.data,game.state,region),"total":caps["troop_handling"]}),["assembly","ramp"])
	var services := 0
	for fleet in game.state["fleets"].values():
		if fleet["owner"] == game.state["player_faction"] and (fleet.get("trade_route",{}).get("from")==region or fleet.get("trade_route",{}).get("to")==region):
			services += 1
	_focus_row(words("freight_suspended" if not facts["blockaders"].is_empty() else "freight_overview",{"capacity":caps["cargo_handling"],"services":services}),["warehouse_depot","warehouse","west_pier"])
	var left := 0 if int(PortRules.record(game.state,region).get("repair_turn",-1))==int(game.state["turn"]) else int(caps["support"])
	_focus_row(words("repair_overview",{"left":left,"total":caps["support"],"gain":caps["repair_pct"]}),["repair_workshop","boatbuilder"])
	_focus_row(words("defense_overview",{"cost":caps["upkeep"],"defense":caps["defense_pct"]}),["arsenal","road_gate"])

func _details() -> void:
	_clear(details)
	var site := {}
	for candidate in district_view.sites:
		if candidate["id"] == selection:
			site = candidate
	if site.is_empty():
		selection = "landing_shelter"
		for candidate in district_view.sites:
			if candidate["id"] == selection:
				site = candidate
	label(details,site.get("name",words("district_title"))).add_theme_color_override("font_color",UiStyle.CAPITAL_GOLD)
	if not site.is_empty():
		button(details,words("walk_here"),func(): district_view.focus_site(selection,true))
		label(details,words("purpose_"+_purpose(site)))
	if receipt != "":
		label(details,receipt)
	var purpose := _purpose(site)
	if purpose in ["office","arsenal","commercial","berth"]:
		_security()
	if purpose in ["shipyard","arsenal","office"]:
		_shipyard(purpose=="arsenal")
	if purpose in ["repair","shipyard","office"]:
		_repairs()
	if purpose in ["assembly","berth","office"]:
		_transport()
	if purpose in ["commercial","office"]:
		_trade()
	if purpose == "berth":
		_berth()
	if purpose in ["office","arsenal","commercial","repair"]:
		_development()
	# Compact location menu makes every facility, bridge and gate discoverable.
	var places := OptionButton.new()
	places.fit_to_longest_item = false
	places.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	places.add_item(words("locations"))
	for point in district_view.sites:
		places.add_item(point["name"])
	details.add_child(places)
	places.item_selected.connect(func(index):
		if index>0:
			district_view.focus_site(district_view.sites[index-1]["id"]))

func _purpose(site: Dictionary) -> String:
	var id: String = site.get("id","")
	if site.get("kind") == "berth": return "berth"
	if id in ["boatbuilder","slip","ship_shed"]: return "shipyard"
	if id in ["arsenal","barracks"]: return "arsenal"
	if id == "repair_workshop": return "repair"
	if id in ["assembly","ramp","military_pier","east_quay"]: return "assembly"
	if id in ["warehouse_depot","warehouse","market","west_quay","west_pier","deep_pier"]: return "commercial"
	if site.get("kind") in ["bridge","gate","tower","ramp","pier"]: return "passage"
	return "office"

func _offer(caption_text: String, quote_fn: Callable, command: Callable) -> void:
	var quote: Dictionary = quote_fn.call()
	var control := button(details,caption_text,func(): _commit(quote,quote_fn,command),quote)
	if not quote.get("ok",false):
		label(details,_reason(quote.get("error","invalid")))
	control.name = "operation_%d" % details.get_child_count()

func _reason(key: String) -> String:
	return String(game.data.effects_glossary["ports"].get(key,game.data.effects_glossary["waterways"].get(key,game.data.effects_glossary.get("forces",{}).get(key,key))))

func _commit(shown: Dictionary, quote_fn: Callable, command: Callable) -> void:
	if not _allowed():
		_close()
		return
	var fresh: Dictionary = quote_fn.call()
	if JSON.stringify(fresh) != JSON.stringify(shown):
		receipt = words("quote_changed")
		_refresh()
		return
	if not fresh.get("ok",false):
		status.text = _reason(fresh.get("error","invalid"))
		return
	# Campaign rules resolve exactly once here, before any presentation refresh.
	var result: Dictionary = command.call()
	var success: bool = result.get("ok",int(result.get("count",0))>0)
	receipt = words("committed") if success else _reason(result.get("error","no_repairs"))
	var encounter: Dictionary = result.get("battle",{})
	for resolved in result.get("battles",[]):
		if not resolved.is_empty(): encounter = resolved
	if not encounter.is_empty():
		receipt = words("relief_result",{"winner":words("relief_won" if encounter.get("winner")=="attacker" else "relief_lost")})
	if result.has("count"):
		receipt = words("repaired",result)
	_refresh()
	status.text = receipt
	changed.emit()

func _shipyard(military: bool) -> void:
	_section(words("queue"))
	if facts["queue"].is_empty(): label(details,words("queue_empty"))
	for job in facts["queue"]:
		label(details,words("work_sign",{"name":game.data.units[job["template"]]["name"],"turns":job["turns"]}))
	_section(words("shipyard"))
	var ids: Array = game.data.ports["vessels"].keys()
	ids.sort()
	for template in ids:
		var unit: Dictionary = game.data.units[template]
		var spec: Dictionary = game.data.ports["vessels"][template]
		if not unit["factions"].has("all") and not unit["factions"].has(game.state["player_faction"]): continue
		if military and not spec["facilities"].has("arsenal"): continue
		var id: String = template
		var quote := PortRules.ship_quote(game.data,game.state,region,id)
		var profile := PortRules.vessel(game.data,id)
		var needs := PackedStringArray()
		for facility in spec["facilities"]: needs.append(_facility_name(facility))
		label(details,words("ship_needs",{"stage":spec["stage"],"facilities":", ".join(needs) if not needs.is_empty() else words("none"),"waters":" / ".join(spec["waters"]),"repair":spec["repair_stage"]}))
		label(details,words("ship_stats",{"troops":profile["troops"],"cargo":profile["cargo"],"crew":unit["soldiers"],"attack":unit["attack"],"defense":unit["defense"],"speed":unit.get("speed",5),"movement":profile["movement"],"upkeep":unit["upkeep"]}))
		var eta := int(quote["turns"])
		for job in game.state["settlements"][region]["recruitment_queue"]: eta += int(job["turns_left"])
		label(details,words("completion",{"turns":eta}))
		_offer(words("ship_button",{"name":unit["name"],"cost":quote["cost"],"turns":quote["turns"]}),func(): return PortRules.ship_quote(game.data,game.state,region,id),func(): return game.commission_ship(region,id))

func _repairs() -> void:
	_section(words("repair"))
	var quote := PortRules.repair_quote(game.data,game.state,region)
	for row in quote["ships"]:
		var ship: Dictionary = game.state["settlements"][region]["harbour"][row["index"]]
		label(details,words("repair_row",{"name":game.data.units[ship["template"]]["name"],"ready":ship["strength_pct"],"gain":row["gained"],"cost":row["cost"],"crew":row["crew"]})+ ("\n"+_reason(row["error"]) if row["error"]!="" else ""))
	_offer(words("repair_commit",quote),func(): return PortRules.repair_quote(game.data,game.state,region),func(): return game.service_port(region))
	label(details,words("repair_note"))

func _transport() -> void:
	_section(words("transport"))
	label(details,words("handling_movement",{"cost":WaterwayRules.rules(game.data)["handling_cost"]}))
	if facts["fleets"].is_empty(): label(details,words("no_fleet"))
	var armies: Array = game.state["armies"].keys()
	armies.sort()
	for fleet_id in facts["fleets"]:
		var fid: String = fleet_id
		var fleet: Dictionary = game.state["fleets"][fid]
		label(details,words("fleet_row",{"id":fid,"space":WaterwayRules.capacity(game.data,fleet),"movement":fleet["movement_left"],"used":PortRules.passengers(game.data,fleet.get("cargo",{}).get("army",{}))}))
		for army_id in armies:
			var army: Dictionary = game.state["armies"][army_id]
			if army["owner"] != game.state["player_faction"] or army["region"] != region: continue
			var aid: String = army_id
			_offer(words("embark_action",{"army":aid,"count":PortRules.passengers(game.data,army),"fleet":fid}),func(): return WaterwayRules.embark_quote(game.data,game.state,fid,aid),func(): return game.embark_army(fid,aid))
		if not fleet.get("cargo",{}).is_empty():
			_offer(words("land_action",{"fleet":fid}),func(): return _landing_quote(fid),func(): return game.disembark_army(fid,region))

func _landing_quote(fid: String) -> Dictionary:
	return WaterwayRules.landing_quote(game.data,game.state,fid,region)

func _berth() -> void:
	_section(words("actual_ships"))
	var ships: Array = facts["berths"].get(selection,[])
	if ships.is_empty(): label(details,words("empty_berth"))
	for ship in ships:
		label(details,"%s · %s" % [game.data.units[ship["template"]]["name"],words("hull_condition",{"strength":ship["readiness"]})])
	var harbour: Array = game.state["settlements"][region]["harbour"]
	if not facts["waiting"].is_empty(): label(details,words("overflow_note"))
	for i in range(harbour.size()):
		var index: int = i
		for zone in NavalRules.zones_touching(game.data,region):
			var zid: String = zone
			_offer(words("launch_action",{"name":game.data.units[harbour[i]["template"]]["name"],"zone":game.data.sea_zones[zone]["name"]}),func():
				var error := NavalRules.check_launch_fleet(game.data,game.state,region,[index],zid)
				return {"ok":error=="","error":error,"ship":game.state["settlements"][region]["harbour"][index] if index<game.state["settlements"][region]["harbour"].size() else {}},func(): return game.launch_fleet(region,[index],zid))
	for fleet in facts["fleets"]:
		var fid: String = fleet
		_offer(words("dock_action",{"fleet":fid,"cost":NavalRules.lane_cost(game.data)}),func():
			var error := NavalRules.check_dock_fleet(game.data,game.state,fid,region)
			return {"ok":error=="","error":error},func(): return game.dock_fleet(fid,region))

func _trade() -> void:
	_section(words("shipping"))
	label(details,words("trade_terms"))
	if BlockadeRules.blocked(game.data,game.state,region):
		label(details,words("blockade_paused"))
	for fid in game.state["fleets"]:
		var fleet: Dictionary = game.state["fleets"][fid]
		var route: Dictionary = fleet.get("trade_route",{})
		if fleet["owner"] == game.state["player_faction"] and (route.get("from")==region or route.get("to")==region):
			label(details,words("service_row",{"fleet":fid,"from":route["from"],"to":route["to"],"capacity":PortRules.delivery_capacity(game.data,game.state,fleet,route),"state":words("service_ready" if WaterwayRules.trade_valid(game.data,game.state,fleet,route) else "service_paused")}))
	for fleet_id in facts["fleets"]:
		var fid: String = fleet_id
		var fleet: Dictionary = game.state["fleets"][fid]
		if not fleet.get("cargo",{}).is_empty():
			label(details,fid+": "+_reason("cargo_aboard"))
			continue
		var options := OptionButton.new()
		options.fit_to_longest_item = false
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var destinations: Array = game.visible_regions().keys()
		destinations.sort()
		var quotes: Array = []
		for to in destinations:
			var quote := _trade_quote(fid,to)
			if quote["ok"]:
				quotes.append(quote)
				options.add_item(words("trade_option",{"to":game.data.regions[to]["settlement_name"],"turns":quote["turns"],"capacity":quote["capacity"]}))
		details.add_child(options)
		if quotes.is_empty():
			label(details,_reason("route_unavailable"))
			continue
		button(details,words("assign_service",{"fleet":fid}),func():
			var shown: Dictionary = quotes[options.selected]
			_commit(shown,func(): return _trade_quote(fid,shown["to"]),func(): return game.assign_shipping(fid,region,shown["to"])))

func _trade_quote(fid: String, to: String) -> Dictionary:
	return WaterwayRules.trade_quote(game.data,game.state,fid,region,to)

func _development() -> void:
	_section(words("next_stage"))
	var quote := PortRules.project_quote(game.data,game.state,region)
	if PortRules.stage(game.data,game.state,region)<5:
		label(details,words("requirements",quote))
		_offer(words("upgrade",{"name":stage_name(quote["rank"]),"cost":quote["cost"],"turns":quote["turns"]}),func(): return PortRules.project_quote(game.data,game.state,region),func(): return game.develop_port(region))
	for facility in game.data.ports["facilities"]:
		var id: String = facility["id"]
		label(details,facility["description"])
		if PortRules.facilities(game.data,game.state,region).has(id):
			label(details,facility["name"]+" · "+words("built"))
		else:
			var values: Dictionary = PortRules.rules(game.data)["facilities"][id].duplicate()
			values["name"] = facility["name"]
			_offer(words("facility",values),func(): return PortRules.project_quote(game.data,game.state,region,id),func(): return game.develop_port(region,id))

func _security() -> void:
	_section(words("blockade_title"))
	if facts["blockaders"].is_empty():
		label(details,words("blockade_clear"))
		return
	label(details,words("blockade_effects"))
	for enemy in facts["blockaders"]:
		label(details,words("blockade_contact",{"faction":game.data.factions[enemy["owner"]]["name"],"zone":game.data.sea_zones[enemy["zone"]]["name"]}))
	label(details,words("relief_terms"))
	var ids: Array = game.state["fleets"].keys()
	ids.sort()
	var count := 0
	for id in ids:
		if game.state["fleets"][id]["owner"] != game.state["player_faction"]: continue
		count += 1
		var fid: String = id
		var offer := BlockadeRules.relief_quote(game.data,game.state,fid,region)
		var caption_text := words("relief_local",{"fleet":fid}) if offer.get("path",[]).is_empty() else words("relief_action",{"fleet":fid,"cost":offer.get("cost",0),"turns":offer.get("turns",0)})
		_offer(caption_text,func(): return BlockadeRules.relief_quote(game.data,game.state,fid,region),func(): return game.relieve_port(fid,region))
	if count == 0: label(details,words("relief_none"))
