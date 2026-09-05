class_name RegionPanel
extends VBoxContainer
## The right-hand context panel: everything about the selected region — the
## settlement (with the factor breakdowns the engine exposes), the armies
## standing there, and every settlement action the player can take from
## here. The selected force itself is described by the ForcePanel above.

signal action_taken
signal army_selected(army_id: String)
signal attack_requested(defender_army_id: String)
signal siege_requested(region_id: String)
signal army_raised(army_id: String)
signal fleet_launched(fleet_id: String)
signal disband_requested(force_id: String, indices: Array)
signal refused(error: String)

var game: Game
var region_id := ""
var selected_army := ""
var _garrison_checks: Array = []   # CheckBox per garrison unit, in order
var _harbour_checks: Array = []    # CheckBox per harbour ship, in order


func harbour_checked_indices() -> Array:
	var indices: Array = []
	for i in range(_harbour_checks.size()):
		if (_harbour_checks[i] as CheckBox).button_pressed:
			indices.append(i)
	return indices


func set_harbour_checked(indices: Array) -> void:
	for i in range(_harbour_checks.size()):
		(_harbour_checks[i] as CheckBox).button_pressed = indices.has(i)


func garrison_checked_indices() -> Array:
	var indices: Array = []
	for i in range(_garrison_checks.size()):
		if (_garrison_checks[i] as CheckBox).button_pressed:
			indices.append(i)
	return indices


func set_garrison_checked(indices: Array) -> void:
	for i in range(_garrison_checks.size()):
		(_garrison_checks[i] as CheckBox).button_pressed = indices.has(i)


func show_region(current_game: Game, new_region_id: String, army_id: String = "") -> void:
	game = current_game
	region_id = new_region_id
	selected_army = army_id
	_rebuild()


func clear_panel() -> void:
	region_id = ""
	selected_army = ""
	_clear_children()


func _clear_children() -> void:
	## remove_child before queue_free: freed rows linger until end of frame
	## otherwise, doubling the panel for anything reading it the same frame.
	_garrison_checks.clear()
	_harbour_checks.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _rebuild() -> void:
	_clear_children()
	if game == null or region_id == "":
		return
	var region: Dictionary = game.data.regions[region_id]
	var visible_set := game.visible_regions()
	var is_visible := visible_set.has(region_id)

	if not is_visible:
		_header(region["name"], 16)
		_label("Beyond our maps: no reports come from this land.")
		return

	_header("%s — %s" % [region["name"], region["settlement_name"]], 16)
	_label("Terrain: %s   Fertility: %.1f" % [region["terrain"], float(region["fertility"])])
	var resources: Array = region.get("resources", [])
	if not resources.is_empty():
		_label("Goods: " + ", ".join(resources))

	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if not settlement.is_empty():
		_build_settlement_section(settlement)
	_build_armies_section()


func _build_settlement_section(settlement: Dictionary) -> void:
	var owner: String = settlement["owner"]
	var faction: Dictionary = game.data.factions.get(owner, {})
	var player: String = game.state["player_faction"]
	_separator()
	_header(String(faction.get("name", owner)), 13, Color.html(faction.get("color", "#808080")))
	var level := SettlementRules.settlement_level(game.data, settlement)
	_label("%s · population %d" % [level.capitalize().replace("_", " "), int(settlement["population"])])
	if settlement["siege"] != null:
		_label("UNDER SIEGE — turn %d" % int(settlement["siege"]["turns"]), Color(1, 0.5, 0.4))

	if owner != player:
		return

	if settlement["governor"] != null:
		var sheet := game.character_sheet(settlement["governor"])
		_label("Governor: %s (mgmt %d, infl %d)" % [sheet["name"], sheet["management"], sheet["influence"]])
	else:
		_label("No governor", Color(0.9, 0.8, 0.5))

	# Taxes
	var tax_row := HBoxContainer.new()
	add_child(tax_row)
	var tax_label := Label.new()
	tax_label.text = "Taxes:"
	tax_row.add_child(tax_label)
	var tax_options := OptionButton.new()
	for tax_level in Constants.TAX_LEVELS:
		tax_options.add_item(tax_level.capitalize().replace("_", " "))
	tax_options.selected = Constants.TAX_LEVELS.find(String(settlement["tax_level"]))
	tax_options.item_selected.connect(func(index: int):
		game.set_tax_level(region_id, Constants.TAX_LEVELS[index])
		action_taken.emit())
	tax_row.add_child(tax_options)

	var capital: String = game.state["factions"][player]["capital"]
	if capital != region_id:
		_action_button("Make this the capital", func():
			game.move_capital(region_id)
			action_taken.emit())

	_breakdown("Public order: %d%%" % int(PublicOrderRules.total(game.data, game.state, region_id)),
		game.order_breakdown(region_id))
	_breakdown("Growth: %+.1f%%" % GrowthRules.total_pct(game.data, game.state, region_id),
		game.growth_breakdown(region_id))
	_breakdown("Income: %d" % int(EconomyRules.settlement_income(game.data, game.state, region_id)),
		game.income_breakdown(region_id))

	# Garrison — tick units to raise an army, move them to an army here, or send them home.
	var garrison: Array = settlement["garrison"]
	if not garrison.is_empty():
		_header("Garrison (%d) — tick units to raise or move" % garrison.size(), 12)
		for unit in garrison:
			var row := HBoxContainer.new()
			add_child(row)
			var check := CheckBox.new()
			check.custom_minimum_size = Vector2(22, 0)
			row.add_child(check)
			_garrison_checks.append(check)
			var label := Label.new()
			label.text = "%s  %d%%  xp%d" % [_unit_name(unit), int(unit["strength_pct"]), int(unit["experience"])]
			label.add_theme_font_size_override("font_size", 11)
			row.add_child(label)
		_garrison_actions()
	# Harbour — ships waiting in port; launch them as a fleet into a touching sea.
	var harbour: Array = settlement.get("harbour", [])
	if not harbour.is_empty():
		_header("Harbour (%d) — tick ships to launch" % harbour.size(), 12)
		for ship in harbour:
			var row := HBoxContainer.new()
			add_child(row)
			var check := CheckBox.new()
			check.custom_minimum_size = Vector2(22, 0)
			row.add_child(check)
			_harbour_checks.append(check)
			var label := Label.new()
			label.text = "%s  %d%%  xp%d" % [_unit_name(ship), int(ship["strength_pct"]), int(ship["experience"])]
			label.add_theme_font_size_override("font_size", 11)
			row.add_child(label)
		_harbour_actions()
	if not garrison.is_empty() or not harbour.is_empty():
		_action_button("Retrain garrison and harbour", func():
			game.retrain_garrison(region_id)
			action_taken.emit())

	# Construction
	_header("Construction", 12)
	for job in settlement["construction_queue"]:
		_label("  building %s — %d turns left" % [_chain_name(job["chain"]), int(job["turns_left"])])
	for project in game.available_buildings(region_id):
		_action_button("Build %s (%d, %dt)" % [project["name"], int(project["cost"]), int(project["build_turns"])],
			func():
				game.queue_building(region_id, project["chain"])
				action_taken.emit())

	# Demolition — the way a conqueror works off a foreign culture penalty.
	var demolishable: Array = []
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = game.data.chains.get(chain_id, {})
		if chain.is_empty() or chain.get("indestructible", false) or chain["kind"] == "government":
			continue
		demolishable.append(chain_id)
	demolishable.sort()
	for chain_id in demolishable:
		_action_button("Demolish %s" % _chain_name(chain_id),
			func():
				game.demolish_building(region_id, chain_id)
				action_taken.emit())

	# Recruitment
	_header("Recruitment", 12)
	for job in settlement["recruitment_queue"]:
		_label("  mustering %s" % _template_name(job["template"]))
	for unit in game.available_units(region_id):
		_action_button("Recruit %s (%d)" % [unit["name"], int(unit["cost"])],
			func():
				game.queue_unit(region_id, unit["id"])
				action_taken.emit())


func _garrison_actions() -> void:
	var here := region_id
	var player: String = game.state["player_faction"]

	# Raise an army under ▾
	var candidates := game.candidate_generals(here)
	var leaders: Array = [""]
	var leader_names: Array = ["a captain"]
	for char_id in candidates:
		leaders.append(char_id)
		leader_names.append(game.state["characters"][char_id]["name"])
	var raise_row := HBoxContainer.new()
	add_child(raise_row)
	var leader_options := OptionButton.new()
	leader_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader_options.clip_text = true
	leader_options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for leader_name in leader_names:
		leader_options.add_item(String(leader_name))
	raise_row.add_child(leader_options)
	var raise := Button.new()
	raise.text = "Raise army under →"
	raise.add_theme_font_size_override("font_size", 11)
	raise.pressed.connect(func():
		var choice: String = leaders[maxi(leader_options.selected, 0)]
		var result := game.raise_army(here, garrison_checked_indices(), choice)
		if result["ok"]:
			army_raised.emit(result["army_id"])
		else:
			refused.emit(result["error"]))
	raise_row.add_child(raise)
	raise_row.move_child(raise, 0)

	# Transfer ticked to an army standing here ▾
	var armies: Array = []
	for army_id in ForceRules.armies_in(game.state, here):
		if game.state["armies"][army_id]["owner"] == player:
			armies.append(army_id)
	if not armies.is_empty():
		var row := HBoxContainer.new()
		add_child(row)
		var options := OptionButton.new()
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.clip_text = true
		options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for army_id in armies:
			var army: Dictionary = game.state["armies"][army_id]
			var leader := "captain"
			if army["general"] != null and game.state["characters"].has(army["general"]):
				leader = game.state["characters"][army["general"]]["name"]
			options.add_item("%s's army (%d units)" % [leader, army["units"].size()])
		row.add_child(options)
		var move := Button.new()
		move.text = "Transfer ticked →"
		move.add_theme_font_size_override("font_size", 11)
		move.pressed.connect(func():
			if options.selected < 0:
				return
			var result := game.transfer_units("garrison:" + here, armies[options.selected], garrison_checked_indices())
			if result["ok"]:
				action_taken.emit()
			else:
				refused.emit(result["error"]))
		row.add_child(move)
		row.move_child(move, 0)

	_action_button("Disband ticked units", func():
		var indices := garrison_checked_indices()
		if indices.is_empty():
			refused.emit(ForceRules.ERR_EMPTY_SELECTION)
		else:
			disband_requested.emit("garrison:" + here, indices))


func _harbour_actions() -> void:
	var here := region_id
	var zones: Array = NavalRules.zones_touching(game.data, here)
	if zones.is_empty():
		return
	var row := HBoxContainer.new()
	add_child(row)
	var launch := Button.new()
	launch.text = "Launch fleet into →"
	launch.add_theme_font_size_override("font_size", 11)
	row.add_child(launch)
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.clip_text = true
	options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for zone_id in zones:
		options.add_item(String(game.data.sea_zones.get(zone_id, {}).get("name", zone_id)))
	row.add_child(options)
	launch.pressed.connect(func():
		var zone: String = zones[maxi(options.selected, 0)]
		var result := game.launch_fleet(here, harbour_checked_indices(), zone)
		if result["ok"]:
			fleet_launched.emit(result["fleet_id"])
		else:
			refused.emit(result["error"]))
	_action_button("Disband ticked ships", func():
		var indices := harbour_checked_indices()
		if indices.is_empty():
			refused.emit(ForceRules.ERR_EMPTY_SELECTION)
		else:
			disband_requested.emit("harbour:" + here, indices))


func _build_armies_section() -> void:
	var player: String = game.state["player_faction"]
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	var local: Array = []
	for army_id in army_ids:
		if game.state["armies"][army_id]["region"] == region_id:
			local.append(army_id)
	if local.is_empty():
		return

	_separator()
	_header("Armies here", 13)
	for army_id in local:
		var army: Dictionary = game.state["armies"][army_id]
		var faction: Dictionary = game.data.factions.get(army["owner"], {})
		var general_name := "captain"
		if army["general"] != null and game.state["characters"].has(army["general"]):
			general_name = game.state["characters"][army["general"]]["name"]
		var title := "%s — %d units (%s)" % [faction.get("name", army["owner"]), army["units"].size(), general_name]
		if army["owner"] == player:
			var button := Button.new()
			button.text = ("▶ " if army_id == selected_army else "") + title
			button.pressed.connect(func(): army_selected.emit(army_id))
			add_child(button)
		else:
			_label(title, Color.html(faction.get("color", "#808080")))
			# A beaten enemy can be stacked in our own region; the map click
			# cannot reach him there, so the order lives here.
			if selected_army != "" and game.state["armies"].has(selected_army) \
					and game.state["armies"][selected_army]["region"] == region_id:
				_action_button("Attack the %s" % faction.get("name", army["owner"]),
					func(): attack_requested.emit(army_id))


## --- Small builders -------------------------------------------------------

func _header(text: String, font_size: int, color: Color = Color(0.95, 0.9, 0.75)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


func _label(text: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


func _breakdown(title: String, factors: Array) -> void:
	_label(title, Color(0.95, 0.9, 0.75))
	for factor in factors:
		var value := float(factor["value"])
		var color := Color(0.55, 0.85, 0.55) if value >= 0 else Color(0.9, 0.55, 0.5)
		_label("    %s  %+.1f" % [String(factor["label"]).replace("_", " "), value], color)


func _action_button(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(handler)
	add_child(button)


func _separator() -> void:
	add_child(HSeparator.new())


func settlement_display_name() -> String:
	return game.data.regions.get(region_id, {}).get("settlement_name", region_id)


func _unit_name(unit: Dictionary) -> String:
	return _template_name(unit["template"])


func _template_name(template_id: String) -> String:
	return game.data.units.get(template_id, {}).get("name", template_id)


func _chain_name(chain_id: String) -> String:
	return game.data.chains.get(chain_id, {}).get("name", chain_id)
