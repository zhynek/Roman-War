class_name WaterwayPanel
extends VBoxContainer
## Map-only shipping controls; all gameplay mutation goes through Game.
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
	if not WaterwayRules.river_access(game.data, region).is_empty() and not WaterwayRules.landing(game.data, game.state, region):
		_project(region, "landing")
	if WaterwayRules.landing(game.data, game.state, region):
		_project(region, "boat")
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
	label(words("capacity", {"used": WaterwayRules.cargo_size(fleet), "capacity": WaterwayRules.capacity(game.data, fleet)}))
	status = label("")
	var report: Dictionary = game.state.get("naval_report", {})
	if report.get("zone", "") == fleet["sea_zone"]:
		label(words("battle_result", {"winner": game.data.factions.get(report["winner"], {}).get("name", report["winner"])}))
	var path: Array = fleet.get("sail_path", [])
	if not path.is_empty():
		label(words("queued", {"destination": game.data.sea_zones[path.back()]["name"], "steps": path.size()}))
	var trade: Dictionary = fleet.get("trade_route", {})
	if not trade.is_empty():
		label(words("trade_active", {"from": _town(trade["from"]), "to": _town(trade["to"]), "status": words("trade_ready" if WaterwayRules.trade_valid(game.data, game.state, fleet, trade) else "trade_paused")}))
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
		button(words("battle", {"name": game.data.factions[game.state["fleets"][enemy]["owner"]]["name"]}), func():
			var outcome := game.naval_encounter(fleet_id, enemy_id)
			if outcome.is_empty():
				status.text = words("no_movement")
			else:
				changed.emit())
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
