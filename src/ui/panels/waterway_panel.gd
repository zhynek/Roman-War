class_name WaterwayPanel
extends VBoxContainer
## Map-only shipping controls; all gameplay mutation goes through Game.
signal port_requested(region: String)
signal changed
signal previewed(fleet_id: String, target: String, mode: String)
signal sailed(fleet_id: String, origin: String, path: Array)

var game: Game
var fleet_id := ""
var destination: OptionButton
var travel_mode: OptionButton
var route_label: Label
var status: Label
var destinations: Array = []

func words(key: String, values: Dictionary = {}) -> String:
	return String(game.data.effects_glossary.get("waterways", {}).get(key, key)).format(values)

func label(text: String) -> Label:
	var control := Label.new()
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.add_theme_font_size_override("font_size", 12)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(control)
	return control

func button(text: String, callback: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	control.add_theme_font_size_override("font_size", 12)
	control.pressed.connect(callback)
	add_child(control)
	return control

func result(outcome: Dictionary) -> void:
	if outcome.get("ok", false):
		changed.emit()
	else:
		status.text = words(String(outcome.get("error", "invalid")))

func setup_region(current_game: Game, region: String) -> void:
	game = current_game
	if NavalRules.zones_touching(game.data, region).is_empty():
		return
	label(words("title")).add_theme_color_override("font_color", UiStyle.CAPITAL_GOLD)
	label(words("intro"))
	status = label("")
	for project in game.state.get("waterworks", {}).get("projects", []):
		if project["region"] == region:
			label(words("project", {"name": words(project["kind"] + "_name"), "turns": project["turns"]}))
	var port_words: Dictionary = game.data.effects_glossary["ports"]
	var rank := PortRules.stage(game.data,game.state,region)
	var definition := PortRules.stage_spec(game.data,rank)
	var name: String = port_words["shore"] if rank == 0 else definition["name" if MapRules.coastal(game.data,region) else "inland_name"]
	label(String(port_words["stage"]).format({"stage":rank,"name":name}))
	var blockaders := BlockadeRules.at_port(game.data, game.state, region)
	if not blockaders.is_empty():
		label(words("blockade_summary", {"count":blockaders.size()})).add_theme_color_override("font_color", UiStyle.CAPITAL_GOLD)
	button(port_words["enter"] if rank>0 else port_words["inspect"],func(): port_requested.emit(region))
	for other in game.data.regions[region].get("adjacent", []):
		if TerrainRules.crossing_kind(game.data, region, other) == "river" and not game.state.get("waterworks", {}).get("bridges", {}).has(TerrainRules.edge_key(region, other)):
			_project(region, "bridge", other)
	if MapRules.coastal(game.data, region):
		label(words("port_hint"))

func _project(region: String, kind: String, other: String = "") -> void:
	var quote := WaterwayRules.project_quote(game.data, game.state, region, kind, other)
	var values := {"cost": quote["cost"], "turns": quote["turns"], "name": game.data.regions.get(other, {}).get("name", other)}
	var action := button(words(kind, values), func(): result(game.waterway_project(region, kind, other)))
	action.disabled = not quote["ok"]
	if action.disabled:
		action.tooltip_text = words(quote["error"])

func setup_fleet(current_game: Game, id: String) -> void:
	game = current_game
	fleet_id = id
	var fleet: Dictionary = game.state["fleets"][id]
	label(words("title")).add_theme_color_override("font_color", UiStyle.CAPITAL_GOLD)
	label(words("capacity", {"used": PortRules.passengers(game.data, fleet.get("cargo", {}).get("army", {})), "capacity": WaterwayRules.capacity(game.data, fleet)}))
	var port_words: Dictionary = game.data.effects_glossary["ports"]
	label(String(port_words["fleet_stats"]).format({"crew":CombatRules.soldiers_in(game.data,fleet["ships"]),"cargo":PortRules.fleet_capacity(game.data,fleet,"cargo"),"movement":MovementRules.fleet_movement_points_for(game.data,game.state,fleet)}))
	status = label("")
	var report: Dictionary = game.state.get("naval_report", {})
	if report.get("zone", "") == fleet["sea_zone"]:
		label(words("battle_result", {"winner": game.data.factions.get(report["winner"], {}).get("name", report["winner"])}))
	var path: Array = fleet.get("sail_path", [])
	if not path.is_empty():
		label(words("queued", {"destination": game.data.sea_zones[path.back()]["name"], "steps": path.size()}))
	var trade: Dictionary = fleet.get("trade_route", {})
	if not trade.is_empty():
		if BlockadeRules.blocked(game.data,game.state,trade["from"]) or BlockadeRules.blocked(game.data,game.state,trade["to"]):
			label(words("blockade_paused"))
		label(words("trade_active", {"from": _town(trade["from"]), "to": _town(trade["to"]), "status": words("trade_ready" if WaterwayRules.trade_valid(game.data, game.state, fleet, trade) else "trade_paused")}))
	_blockade_controls(fleet)
	if not path.is_empty() or not trade.is_empty():
		button(words("halt"), func():
			game.halt_voyage(fleet_id)
			changed.emit())

	travel_mode = OptionButton.new()
	travel_mode.add_item(words("coastal"))
	travel_mode.add_item(words("open"))
	travel_mode.select(1 if fleet.get("sail_mode", "coastal") == "open" else 0)
	add_child(travel_mode)
	destination = OptionButton.new()
	destination.fit_to_longest_item = false
	destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destinations = game.data.sea_zones.keys()
	destinations.erase(fleet["sea_zone"])
	destinations.sort()
	for zone in destinations:
		destination.add_item(game.data.sea_zones[zone]["name"])
	add_child(destination)
	if not path.is_empty():
		destination.select(destinations.find(path.back()))
	else:
		var nearest := INF
		for i in range(destinations.size()):
			var quote := game.fleet_path_preview(fleet_id, destinations[i], _mode())
			if not quote.is_empty() and float(quote["cost"]) < nearest:
				nearest = quote["cost"]
				destination.select(i)
	route_label = label("")
	destination.item_selected.connect(func(_index): _preview())
	travel_mode.item_selected.connect(func(_index): _preview())
	button(words("sail"), func():
		if destination.selected < 0:
			return
		var origin: String = game.state["fleets"][fleet_id]["sea_zone"]
		var outcome := game.sail_fleet(fleet_id, destinations[destination.selected], _mode())
		if outcome.get("ok", false):
			sailed.emit(fleet_id, origin, outcome.get("path", []))
		result(outcome))
	_preview(false)

	for enemy in WaterwayRules.hostiles(game.state, fleet):
		var enemy_id: String = enemy
		var combat := button(words("battle", {"name": game.data.factions[game.state["fleets"][enemy]["owner"]]["name"]}), func():
			var outcome := game.naval_encounter(fleet_id, enemy_id)
			if outcome.is_empty():
				status.text = words("no_movement")
			else:
				changed.emit())
		var error := WaterwayRules.encounter_error(game.state,fleet_id,enemy_id)
		combat.disabled = error != ""
		combat.tooltip_text = words(error) if error != "" else words("relief_terms")
	if not fleet.get("cargo", {}).is_empty():
		for region in game.state["settlements"]:
			if WaterwayRules.can_land(game.data, game.state, fleet, region):
				var target: String = region
				button(words("disembark", {"name": _town(target)}), func(): result(game.disembark_army(fleet_id, target)))
	else:
		for army_id in game.state["armies"]:
			var army: Dictionary = game.state["armies"][army_id]
			if army["owner"] == fleet["owner"] and WaterwayRules.access(game.data, game.state, fleet["owner"], army["region"], fleet["sea_zone"], true):
				var target: String = army_id
				button(words("embark", {"name": game.force_summary(army_id).get("general", {}).get("name", army_id) if army.get("general") != null else army_id}), func(): result(game.embark_army(fleet_id, target)))
		_trade_controls(fleet)

func _preview(emit: bool = true) -> void:
	if destination.selected < 0:
		return
	var target: String = destinations[destination.selected]
	var quote := game.fleet_path_preview(fleet_id, target, _mode())
	route_label.text = words("route_unavailable") if quote.is_empty() else words("preview", {"destination": game.data.sea_zones[target]["name"], "cost": quote["cost"], "turns": quote["turns"]})
	if emit:
		previewed.emit(fleet_id, target, _mode())

func _mode() -> String:
	return "open" if travel_mode.selected == 1 else "coastal"

func _town(region: String) -> String:
	return String(game.data.regions.get(region, {}).get("settlement_name", region))

func _trade_controls(fleet: Dictionary) -> void:
	var origins := NavalRules.own_ports_on_zone(game.state, game.data, fleet["owner"], fleet["sea_zone"])
	if origins.is_empty():
		return
	label(words("trade_note"))
	var options := OptionButton.new()
	options.fit_to_longest_item = false
	add_child(options)
	var pairs: Array = []
	var regions: Array = game.visible_regions().keys()
	regions.sort()
	for from in origins:
		for to in regions:
			if to == from:
				continue
			for zone in NavalRules.zones_touching(game.data, to):
				if zone != fleet["sea_zone"] and WaterwayRules.access(game.data, game.state, fleet["owner"], to, zone) and not game.fleet_path_preview(fleet_id, zone, _mode()).is_empty():
					pairs.append([from, to])
					options.add_item("%s ↔ %s" % [_town(from), _town(to)])
					break
	var action := button(words("assign_trade"), func():
		if options.selected >= 0:
			result(game.assign_shipping(fleet_id, pairs[options.selected][0], pairs[options.selected][1], _mode())))
	action.disabled = pairs.is_empty()

func _blockade_controls(fleet: Dictionary) -> void:
	var order: Dictionary = fleet.get("blockade", {})
	if not order.is_empty():
		label(words("blockade_active", {"name":_town(order["region"]),"cost":BlockadeRules.cost(game.data,fleet)}))
		button(words("blockade_withdraw"),func():
			game.halt_voyage(fleet_id)
			changed.emit())
		return
	label(words("blockade_patrol"))
	var regions: Array = game.visible_regions().keys()
	regions.sort()
	for region in regions:
		var town: Dictionary = game.state["settlements"].get(region,{})
		if town.is_empty() or not DiplomacyRules.at_war(game.state,fleet["owner"],town["owner"]) or not NavalRules.zones_touching(game.data,region).has(fleet["sea_zone"]) or PortRules.stage(game.data,game.state,region)==0: continue
		var target: String = region
		var offer := BlockadeRules.quote(game.data,game.state,fleet_id,target)
		var values: Dictionary = offer.duplicate()
		values["minimum"] = BlockadeRules.rules(game.data)["station_movement"]
		label(words("blockade_terms",values))
		var action := button(words("blockade_order",{"name":_town(target),"cost":offer["cost"]}),func():
			var fresh := BlockadeRules.quote(game.data,game.state,fleet_id,target)
			if JSON.stringify(fresh)!=JSON.stringify(offer):
				changed.emit()
				return
			result(game.blockade_port(fleet_id,target)))
		action.disabled = not offer["ok"]
		if not offer["ok"]: label(words(offer["error"]))
