class_name RegionPanel
extends VBoxContainer
## The right-hand context panel: everything about the selected region — the
## settlement (with the factor breakdowns the engine exposes), the armies
## standing there, and every action the player can take from here.

signal action_taken
signal army_selected(army_id: String)
signal attack_requested(defender_army_id: String)
signal siege_requested(region_id: String)

var game: Game
var region_id := ""
var selected_army := ""


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

	_edict_section()

	var capital: String = game.state["factions"][player]["capital"]
	if capital != region_id:
		_action_button("Make this the capital", func():
			game.move_capital(region_id)
			action_taken.emit())

	_breakdown("Public order: %d%%" % int(PublicOrderRules.total(game.data, game.state, region_id)),
		game.order_breakdown(region_id))
	_society_section()
	_breakdown("Growth: %+.1f%%" % GrowthRules.total_pct(game.data, game.state, region_id),
		game.growth_breakdown(region_id))
	_breakdown("Income: %d" % int(EconomyRules.settlement_income(game.data, game.state, region_id)),
		game.income_breakdown(region_id))

	# Garrison
	var garrison: Array = settlement["garrison"]
	if not garrison.is_empty():
		_header("Garrison (%d)" % garrison.size(), 12)
		for unit in garrison:
			_label("  %s  %d%%" % [_unit_name(unit), int(unit["strength_pct"])])
		_action_button("Retrain garrison", func():
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
			if army_id == selected_army:
				_build_selected_army_detail(army_id, army)
		else:
			_label(title, Color.html(faction.get("color", "#808080")))
			# A beaten enemy can be stacked in our own region; the map click
			# cannot reach him there, so the order lives here.
			if selected_army != "" and game.state["armies"].has(selected_army) \
					and game.state["armies"][selected_army]["region"] == region_id:
				_action_button("Attack the %s" % faction.get("name", army["owner"]),
					func(): attack_requested.emit(army_id))


func _build_selected_army_detail(army_id: String, army: Dictionary) -> void:
	_label("Movement left: %.1f" % float(army["movement_left"]))
	for unit in army["units"]:
		_label("  %s  %d%%  xp%d" % [_unit_name(unit), int(unit["strength_pct"]), int(unit["experience"])])
	_label("Click an adjacent region to march, attack, or besiege.", Color(0.7, 0.8, 0.9))

	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if not settlement.is_empty() and settlement["owner"] == game.state["player_faction"]:
		_action_button("Garrison the army in the city", func():
			game.garrison_army(army_id)
			action_taken.emit())
	elif not settlement.is_empty() and settlement.get("siege") == null:
		# Standing in a hostile settlement's region: the siege starts from here.
		_action_button("Lay siege to %s" % settlement_display_name(),
			func(): siege_requested.emit(region_id))

	if not settlement.is_empty() and settlement.get("siege") != null \
			and settlement["siege"]["besieger"] == army_id:
		var occupation_options := OptionButton.new()
		for choice in ["occupy", "enslave", "exterminate"]:
			occupation_options.add_item(choice.capitalize())
		add_child(occupation_options)
		var can_assault: bool = settlement["siege"].get("equipment_ready", false)
		_action_button("Assault the walls!" if can_assault else "Assault (equipment not ready)", func():
			var choice: String = ["occupy", "enslave", "exterminate"][occupation_options.selected]
			game.assault_settlement(army_id, region_id, choice)
			action_taken.emit())

	var offers := game.mercenaries_available(region_id)
	if not offers.is_empty():
		_header("Mercenaries for hire", 12)
		for offer in offers:
			_action_button("Hire %s (%d)" % [_template_name(offer["template"]), int(offer["cost"])],
				func():
					game.hire_mercenary(army_id, offer["template"])
					action_taken.emit())


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


func _edict_section() -> void:
	## The province's one standing order, and the player's only fast lever on
	## stocks that otherwise move over decades. Mirrors the tax selector: one
	## choice per settlement, changed in place.
	##
	## While an order stands — or while the last one is still unwinding — the
	## list collapses to the choice actually on offer. Every other edict is
	## unavailable for the same reason, and saying so nine times over teaches
	## nobody anything; one line does it.
	var status: Dictionary = game.edict_status(region_id)
	var standing: bool = status["id"] != EdictRules.NONE
	var record := EdictRules.of(game.state["settlements"][region_id])

	var row := HBoxContainer.new()
	add_child(row)
	var caption := Label.new()
	caption.text = "Edict:"
	row.add_child(caption)

	var options := OptionButton.new()
	var choices: Array = []
	if standing:
		choices.append({"id": status["id"], "name": String(status["name"]), "allowed": true, "reason": ""})
		choices.append({"id": EdictRules.NONE, "name": "— revoke —", "allowed": true, "reason": ""})
	else:
		choices.append({"id": EdictRules.NONE, "name": "— none —", "allowed": true, "reason": ""})
		# While a cooldown runs, nothing is available and all for the same
		# reason, which the line below states once.
		if int(record["cooldown"]) == 0:
			choices.append_array(game.available_edicts(region_id))

	for i in range(choices.size()):
		var entry: Dictionary = choices[i]
		var label: String = entry["name"]
		if not entry["allowed"]:
			label += "  (%s)" % entry["reason"]
		options.add_item(label)
		options.set_item_disabled(i, not entry["allowed"])
	options.selected = 0
	options.item_selected.connect(func(index: int):
		var chosen: String = choices[index]["id"]
		if chosen == EdictRules.NONE:
			game.revoke_edict(region_id)
		elif chosen != String(status["id"]):
			game.set_edict(region_id, chosen)
		action_taken.emit())
	row.add_child(options)

	if not standing:
		if int(record["cooldown"]) > 0:
			_label("    the last order is still being unwound — %d turns" % int(record["cooldown"]),
				Color(0.8, 0.75, 0.6))
		return

	# How far the order has taken hold, what it is costing, and what it is doing.
	var held := int(status["turns_held"])
	var settle := int(status["settle_turns"])
	if held < settle:
		_label("    taking hold: %d of %d turns" % [held, settle], Color(0.8, 0.75, 0.6))
	if float(status["upkeep"]) > 0.0:
		_label("    costing %d a turn" % int(round(float(status["upkeep"]))), Color(0.9, 0.55, 0.5))
	var effects: Dictionary = status["effects"]
	var keys: Array = effects.keys()
	keys.sort()
	var factors: Array = []
	for key in keys:
		factors.append({"label": key, "value": float(effects[key]) * float(status["strength"])})
	_breakdown("    in force: %s" % status["name"], factors)
	_label("    another order can be given once this one is revoked and unwound",
		Color(0.7, 0.7, 0.7))


func _society_section() -> void:
	## The three provincial stocks — and, just as importantly, how well you can
	## actually see them. A province with roads, records and a resident governor
	## reports exact figures; a distant one reports a rounded survey some turns
	## old; one you barely govern reports only what is said about it.
	var report: Dictionary = game.society_report(region_id)
	var level := String(report["level"])
	var unrest := LegibilityRules.unrest_name(game.data, String(report["unrest_state"]))
	var title := "Society — %s" % unrest
	if level != LegibilityRules.LEVEL_EXACT:
		var stale := int(report["stale_turns"])
		title += "  (%s" % LegibilityRules.clarity_name(game.data, level)
		title += ", %d turns old)" % stale if stale > 0 else ")"

	var factors: Array = game.society_breakdown(region_id)
	if factors.is_empty():
		_label(title, Color(0.95, 0.9, 0.75))
		_label("    no road, no records, no one of yours standing there —", Color(0.7, 0.7, 0.7))
		_label("    you have opinions about this province, not information.", Color(0.7, 0.7, 0.7))
		return
	_breakdown(title, factors)
	_strain_line()


func _strain_line() -> void:
	## The comparison the model turns on, shown UNNETTED. A garrison keeps public
	## order high while the coerced remainder goes on charging grievance, and the
	## only way the player can see that happening is to see both numbers at once.
	var strain: Dictionary = game.strain_reading(region_id)
	_label("    asked of it  %.1f" % float(strain["asked"]), Color(0.85, 0.8, 0.7))
	if strain["granted"] == null:
		return
	_label("    granted willingly  %.1f" % float(strain["granted"]), Color(0.55, 0.85, 0.55))
	var coerced := float(strain["coerced"])
	if coerced <= 0.0:
		_label("    nothing has to be compelled here", Color(0.55, 0.85, 0.55))
	else:
		_label("    compelled  %.1f  — this is what grievance is charging on" % coerced,
			Color(0.9, 0.55, 0.5))


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
