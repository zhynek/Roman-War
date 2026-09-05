class_name ForcePanel
extends VBoxContainer
## The force card: everything about the selected army or fleet — who leads
## it, how many men it has and how many are standing, what it costs, how far
## it can still go, and every unit in it with its strength and experience —
## plus the orders that need no map click: garrison, attack, siege, assault,
## search, mercenaries, "March to" for trackpads, and the regrouping toolbox
## (transfer, merge, split, disband, generals, consolidate). Reads only
## through the Game facade; every action goes back through it, and a refused
## action reports its error code rather than doing nothing.

signal action_taken
signal attack_requested(defender_army_id: String)
signal siege_requested(region_id: String)
signal assault_requested(region_id: String, occupation: String)
signal explore_requested(army_id: String)
signal march_requested(region_id: String, forced: bool)
signal sail_requested(zone_id: String)
signal sheet_requested(char_id: String)
signal unit_info_requested(template_id: String)
signal force_replaced(kind: String, id: String)     # the selection should move to this force
signal disband_requested(force_id: String, indices: Array)
signal refused(error: String)

const HINT_COLOR := Color(0.7, 0.8, 0.9)

var game: Game
var force_id := ""
var _checks: Array = []   # CheckBox per roster row, in unit order


func show_force(current_game: Game, new_force_id: String) -> void:
	game = current_game
	force_id = new_force_id
	_rebuild()


func clear_panel() -> void:
	force_id = ""
	_clear_children()


func checked_indices() -> Array:
	var indices: Array = []
	for i in range(_checks.size()):
		if (_checks[i] as CheckBox).button_pressed:
			indices.append(i)
	return indices


func set_checked(indices: Array) -> void:
	for i in range(_checks.size()):
		(_checks[i] as CheckBox).button_pressed = indices.has(i)


func _clear_children() -> void:
	_checks.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _rebuild() -> void:
	_clear_children()
	if game == null or force_id == "":
		return
	var summary := game.force_summary(force_id)
	if summary.is_empty():
		return
	var faction: Dictionary = game.data.factions.get(summary["owner"], {})
	var owner_color := Color.html(faction.get("color", "#808080"))

	# Header: who leads, and where.
	var title := "Fleet"
	if summary["kind"] == "army":
		title = "Captain's army"
		if summary["general"] != null:
			title = String(summary["general"]["name"])
	var where := ""
	if summary["kind"] == "army":
		where = String(game.data.regions.get(summary["region"], {}).get("name", summary["region"]))
	else:
		where = String(game.data.sea_zones.get(summary["sea_zone"], {}).get("name", summary["sea_zone"]))
	var header_row := HBoxContainer.new()
	add_child(header_row)
	var swatch := ColorRect.new()
	swatch.color = owner_color
	swatch.custom_minimum_size = Vector2(12, 12)
	header_row.add_child(swatch)
	var header := Label.new()
	header.text = " %s — %s" % [title, where]
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header_row.add_child(header)
	if summary["general"] != null:
		var sheet := Button.new()
		sheet.text = "▸ sheet"
		sheet.focus_mode = Control.FOCUS_NONE
		sheet.add_theme_font_size_override("font_size", 11)
		var general_id: String = summary["general"]["id"]
		sheet.pressed.connect(func(): sheet_requested.emit(general_id))
		header_row.add_child(sheet)

	# The stats line.
	var men_word := "Men" if summary["kind"] == "army" else "Crews"
	_label("Units %d/%d · %s %d/%d (%d%%) · Upkeep %d/turn · Movement %.2f/%.2f" % [
		int(summary["units"]), int(summary["max_units"]), men_word,
		int(summary["soldiers"]), int(summary["max_soldiers"]), int(summary["strength_pct"]),
		int(summary["upkeep"]), float(summary["movement_left"]), float(summary["movement_max"])])
	if summary["general"] != null:
		_label("General: %s — command %d" % [summary["general"]["name"], int(summary["general"]["command"])])
	if bool(summary["forced_march"]):
		_label("FATIGUED — the men marched hard and will fight worse.", Color(0.95, 0.6, 0.2))
	if summary["besieging"] != null:
		_label("BESIEGING %s" % game.data.regions.get(summary["besieging"], {}).get("settlement_name", summary["besieging"]),
			Color(1, 0.5, 0.4))
	if summary["kind"] == "army":
		var army: Dictionary = game.state["armies"][force_id]
		if army.has("march_path") and not (army["march_path"] as Array).is_empty():
			var destination := String((army["march_path"] as Array).back())
			var destination_name: String = game.data.regions.get(destination, {}).get("settlement_name", destination)
			_label("Marching to %s — %d steps to go" % [destination_name, army["march_path"].size()],
				Color(0.85, 0.92, 0.75))
			_action_button("Halt the march", func():
				game.halt_march(force_id)
				action_taken.emit())

	# The roster, one row per unit with a checkbox for the regrouping orders.
	add_child(HSeparator.new())
	var units := ForceRules.units_of(game.state, force_id)
	for i in range(units.size()):
		_unit_row(units[i])

	add_child(HSeparator.new())
	if summary["kind"] == "army":
		_army_actions(summary)
	else:
		_fleet_actions(summary)


func _unit_row(unit: Dictionary) -> void:
	var template: Dictionary = game.data.units.get(unit["template"], {})
	var row := HBoxContainer.new()
	add_child(row)
	var check := CheckBox.new()
	check.focus_mode = Control.FOCUS_NONE
	check.custom_minimum_size = Vector2(22, 0)
	row.add_child(check)
	_checks.append(check)

	var name_label := Label.new()
	name_label.text = String(template.get("name", unit["template"]))
	if template.get("factions", []).has("mercenary"):
		name_label.text += " (m)"
	var kit := _kit_text(unit)
	if kit != "":
		name_label.text += "  " + kit
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.custom_minimum_size = Vector2(100, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var template_id := String(unit["template"])
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.tooltip_text = "%s · right-click for the unit card" % String(template.get("class", "")).replace("_", " ")
	name_label.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT \
				and (event as InputEventMouseButton).pressed:
			unit_info_requested.emit(template_id))
	row.add_child(name_label)

	var bar := StrengthBar.new()
	bar.fraction = clampf(float(unit["strength_pct"]) / 100.0, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(56, 8)
	bar.tooltip_text = "%d of %d men" % [
		int(ceil(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0)), int(template.get("soldiers", 0))]
	row.add_child(bar)

	var chevrons := Label.new()
	chevrons.text = " xp%d" % int(unit["experience"])
	chevrons.add_theme_font_size_override("font_size", 10)
	chevrons.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	chevrons.custom_minimum_size = Vector2(34, 0)
	row.add_child(chevrons)

	var upkeep := Label.new()
	upkeep.text = "%d/t" % int(template.get("upkeep", 0))
	upkeep.add_theme_font_size_override("font_size", 10)
	upkeep.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	row.add_child(upkeep)


func _army_actions(summary: Dictionary) -> void:
	var army_id := force_id
	var region_id: String = summary["region"]
	var player: String = game.state["player_faction"]
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	var at_home: bool = not settlement.is_empty() and settlement["owner"] == player
	var has_movement: bool = float(summary["movement_left"]) > 0.0001

	# Standing in our own city: the army can join its garrison.
	if at_home:
		_action_button("Garrison the army in the city", func():
			game.garrison_army(army_id)
			action_taken.emit())

	# A hostile army sharing the region can be attacked from here (the map
	# cannot reach a banner stacked in our own region).
	var visible := game.visible_regions()
	for other_id in ForceRules.armies_in(game.state, region_id):
		var other: Dictionary = game.state["armies"][other_id]
		if other["owner"] == player or not DiplomacyRules.at_war(game.state, player, other["owner"]):
			continue
		var enemy_name: String = game.data.factions.get(other["owner"], {}).get("name", other["owner"])
		var estimate := game.battle_estimate(army_id, other_id)
		var text := "Attack the %s here" % enemy_name
		if not estimate.is_empty():
			text += "  " + RegionPanel.odds_text(estimate)
		var attack := _action_button(text, func(): attack_requested.emit(other_id))
		if not has_movement:
			attack.disabled = true
			attack.tooltip_text = "A battle takes the rest of the season; the men have marched themselves out."

	# Standing at a foreign city's walls: lay siege, or press an assault.
	if not settlement.is_empty() and settlement["owner"] != player:
		if settlement.get("siege") == null:
			# Standing at the walls already, the army pays no step to invest
			# them — only a siege laid from next door does (SiegeRules).
			_action_button("Lay siege to %s" % _settlement_name(region_id),
				func(): siege_requested.emit(region_id))
		elif settlement["siege"]["besieger"] == army_id:
			var occupation_options := OptionButton.new()
			occupation_options.focus_mode = Control.FOCUS_NONE
			for choice in ["occupy", "enslave", "exterminate"]:
				occupation_options.add_item(choice.capitalize())
			add_child(occupation_options)
			# The storm is confirmed by the campaign screen (with its odds and the
			# fate chosen for the townsfolk); the button only says when and how likely.
			var siege: Dictionary = settlement["siege"]
			var can_assault: bool = siege.get("equipment_ready", false)
			var ready_in := SiegeRules.equipment_turns_for(game.data, game.state, String(summary["owner"])) - int(siege["turns"])
			var assault_text := "Assault the walls!" if can_assault \
				else "Assault (engines ready in %d turn%s)" % [maxi(ready_in, 1), "" if ready_in == 1 else "s"]
			var estimate := game.assault_estimate(army_id, region_id)
			if not estimate.is_empty():
				assault_text += "  " + RegionPanel.odds_text(estimate)
			var assault := _action_button(assault_text, func():
				assault_requested.emit(region_id, ["occupy", "enslave", "exterminate"][occupation_options.selected]))
			assault.disabled = not can_assault or not has_movement
			if can_assault and not has_movement:
				assault.tooltip_text = "A storm is a battle: it takes the season's movement, and the men have none left."

	# A point of interest under the army's feet.
	var site: Dictionary = game.data.sites_by_region.get(region_id, {})
	if not site.is_empty() and not game.state.get("sites_explored", []).has(site["id"]):
		_header("Point of interest")
		var search := _action_button("Search the %s" % site["name"] if has_movement
				else "Search the %s (no movement left)" % site["name"],
			func(): explore_requested.emit(army_id))
		search.disabled = not has_movement

	_regroup_actions(summary)

	# Mercenaries for hire in this region.
	var offers := game.mercenaries_available(region_id)
	if not offers.is_empty():
		_header("Mercenaries for hire")
		for offer in offers:
			var offer_template: String = offer["template"]
			_action_button("Hire %s (%d)" % [game.data.units.get(offer_template, {}).get("name", offer_template), int(offer["cost"])],
				func():
					game.hire_mercenary(army_id, offer_template)
					action_taken.emit())

	# March to ▾ — the same orders as a right-click, for trackpads and tests.
	var plan := game.reachable_regions(army_id)
	var destinations: Array = plan["reach"].keys()
	destinations.sort()
	if not destinations.is_empty():
		_header("March to")
		var row := HBoxContainer.new()
		add_child(row)
		var go := Button.new()
		go.text = "March →"
		go.focus_mode = Control.FOCUS_NONE
		go.add_theme_font_size_override("font_size", 11)
		row.add_child(go)
		var options := _dropdown(row)
		for destination in destinations:
			var entry: Dictionary = plan["reach"][destination]
			var suffix := " (forced march)" if entry["forced"] else ""
			options.add_item("%s%s" % [game.data.regions[destination]["name"], suffix])
		go.pressed.connect(func():
			if options.selected >= 0:
				var destination: String = destinations[options.selected]
				march_requested.emit(destination, bool(plan["reach"][destination]["forced"])))
	_label("Right-click a ringed region to march (Shift: forced march), a red one to attack or besiege. Esc deselects.", HINT_COLOR)


func _regroup_actions(summary: Dictionary) -> void:
	## Transfer, merge, split, disband, generals, consolidate. Buttons whose
	## legality does not depend on the ticked units are greyed with the reason
	## as their tooltip; the others explain themselves when refused.
	var army_id := force_id
	var region_id: String = summary["region"]
	var player: String = game.state["player_faction"]
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	var at_home: bool = not settlement.is_empty() and settlement["owner"] == player
	var others: Array = []
	for other_id in ForceRules.armies_in(game.state, region_id):
		if other_id != army_id and game.state["armies"][other_id]["owner"] == player:
			others.append(other_id)

	_header("Regroup (tick units above)")

	# Transfer ticked units to ▾
	var targets: Array = []
	var target_names: Array = []
	if at_home:
		targets.append("garrison:" + region_id)
		target_names.append("the garrison")
	for other_id in others:
		targets.append(other_id)
		target_names.append(_force_name(other_id))
	if not targets.is_empty():
		var row := HBoxContainer.new()
		add_child(row)
		var move := Button.new()
		move.text = "Transfer ticked →"
		move.focus_mode = Control.FOCUS_NONE
		move.add_theme_font_size_override("font_size", 11)
		row.add_child(move)
		var options := _dropdown(row)
		for target_name in target_names:
			options.add_item(String(target_name))
		move.pressed.connect(func():
			if options.selected < 0:
				return
			var result := game.transfer_units(army_id, targets[options.selected], checked_indices())
			if result["ok"]:
				action_taken.emit()
			else:
				refused.emit(result["error"]))

	# Merge into ▾ (whole army)
	if not others.is_empty():
		var row := HBoxContainer.new()
		add_child(row)
		var merge := Button.new()
		merge.text = "Merge into →"
		merge.focus_mode = Control.FOCUS_NONE
		merge.add_theme_font_size_override("font_size", 11)
		row.add_child(merge)
		var options := _dropdown(row)
		for other_id in others:
			options.add_item(_force_name(other_id))
		merge.pressed.connect(func():
			if options.selected < 0:
				return
			var into: String = others[options.selected]
			var result := game.merge_armies(army_id, into)
			if result["ok"]:
				force_replaced.emit("army", into)
			else:
				refused.emit(result["error"]))

	# Split ticked units into a new army under ▾
	var candidates := game.candidate_generals(region_id)
	var leaders: Array = [""]
	var leader_names: Array = ["a captain"]
	if summary["general"] != null:
		leaders.append("source")
		leader_names.append("%s (takes the general)" % summary["general"]["name"])
	for char_id in candidates:
		leaders.append(char_id)
		leader_names.append(game.state["characters"][char_id]["name"])
	var split_row := HBoxContainer.new()
	add_child(split_row)
	var split := Button.new()
	split.text = "Split ticked under →"
	split.focus_mode = Control.FOCUS_NONE
	split.add_theme_font_size_override("font_size", 11)
	split_row.add_child(split)
	var leader_options := _dropdown(split_row)
	for leader_name in leader_names:
		leader_options.add_item(String(leader_name))
	split.pressed.connect(func():
		var choice: String = leaders[maxi(leader_options.selected, 0)]
		var result := game.split_army(army_id, checked_indices(), choice)
		if result["ok"]:
			force_replaced.emit("army", result["army_id"])
		else:
			refused.emit(result["error"]))

	# Disband ticked (the screen confirms).
	_action_button("Disband ticked units", func():
		var indices := checked_indices()
		if indices.is_empty():
			refused.emit(ForceRules.ERR_EMPTY_SELECTION)
		else:
			disband_requested.emit(army_id, indices))

	# Generals: attach one standing here, or step down at home.
	if summary["general"] == null:
		for char_id in candidates:
			var candidate_name: String = game.state["characters"][char_id]["name"]
			_action_button("Give command to %s" % candidate_name, func():
				var result := game.attach_general(army_id, char_id)
				if result["ok"]:
					action_taken.emit()
				else:
					refused.emit(result["error"]))
	else:
		var detach_error := game.check("detach_general", [army_id])
		var detach := _action_button("Detach %s (he stays in the city)" % summary["general"]["name"], func():
			var result := game.detach_general(army_id)
			if result["ok"]:
				action_taken.emit()
			else:
				refused.emit(result["error"]))
		if detach_error != "":
			detach.disabled = true
			detach.tooltip_text = explain(detach_error)

	# Consolidate depleted units.
	var consolidate_error := game.check("consolidate", [army_id])
	var consolidate := _action_button("Consolidate depleted units", func():
		var result := game.consolidate_units(army_id)
		if result["ok"]:
			action_taken.emit()
		else:
			refused.emit(result["error"]))
	if consolidate_error != "":
		consolidate.disabled = true
		consolidate.tooltip_text = explain(consolidate_error)


func _fleet_actions(summary: Dictionary) -> void:
	var fleet_id := force_id
	var reach := game.reachable_zones(fleet_id)
	var zones: Array = reach.keys()
	zones.sort()
	if not zones.is_empty():
		_header("Sail to")
		var row := HBoxContainer.new()
		add_child(row)
		var go := Button.new()
		go.text = "Sail →"
		go.focus_mode = Control.FOCUS_NONE
		go.add_theme_font_size_override("font_size", 11)
		row.add_child(go)
		var options := _dropdown(row)
		for zone_id in zones:
			options.add_item(String(game.data.sea_zones.get(zone_id, {}).get("name", zone_id)))
		go.pressed.connect(func():
			if options.selected >= 0:
				sail_requested.emit(zones[options.selected]))

	# Other fleets of ours in the same sea: transfer ships between them, or merge.
	var others: Array = []
	for other_id in ForceRules.fleets_in(game.state, summary["sea_zone"]):
		if other_id != fleet_id and game.state["fleets"][other_id]["owner"] == game.state["player_faction"]:
			others.append(other_id)
	_header("Regroup (tick ships above)")
	if not others.is_empty():
		var row := HBoxContainer.new()
		add_child(row)
		var move := Button.new()
		move.text = "Transfer ticked →"
		move.focus_mode = Control.FOCUS_NONE
		move.add_theme_font_size_override("font_size", 11)
		row.add_child(move)
		var options := _dropdown(row)
		for other_id in others:
			options.add_item(_fleet_name(other_id))
		move.pressed.connect(func():
			if options.selected < 0:
				return
			var result := game.transfer_units(fleet_id, others[options.selected], checked_indices())
			if result["ok"]:
				action_taken.emit()
			else:
				refused.emit(result["error"]))
		var merge_row := HBoxContainer.new()
		add_child(merge_row)
		var merge := Button.new()
		merge.text = "Merge into →"
		merge.focus_mode = Control.FOCUS_NONE
		merge.add_theme_font_size_override("font_size", 11)
		merge_row.add_child(merge)
		var merge_options := _dropdown(merge_row)
		for other_id in others:
			merge_options.add_item(_fleet_name(other_id))
		merge.pressed.connect(func():
			var into: String = others[maxi(merge_options.selected, 0)]
			var result := game.merge_fleets(fleet_id, into)
			if result["ok"]:
				force_replaced.emit("fleet", into)
			else:
				refused.emit(result["error"]))
	_action_button("Split ticked ships into a new fleet", func():
		var result := game.split_fleet(fleet_id, checked_indices())
		if result["ok"]:
			force_replaced.emit("fleet", result["fleet_id"])
		else:
			refused.emit(result["error"]))

	# Dock at one of our ports on this sea.
	var ports := game.own_ports_on_zone(summary["sea_zone"])
	if not ports.is_empty():
		var row := HBoxContainer.new()
		add_child(row)
		var dock := Button.new()
		dock.text = "Dock at →"
		dock.focus_mode = Control.FOCUS_NONE
		dock.add_theme_font_size_override("font_size", 11)
		row.add_child(dock)
		var options := _dropdown(row)
		for port in ports:
			options.add_item(_settlement_name(port))
		dock.pressed.connect(func():
			var port: String = ports[maxi(options.selected, 0)]
			var result := game.dock_fleet(fleet_id, port)
			if result["ok"]:
				action_taken.emit()
			else:
				refused.emit(result["error"]))

	_action_button("Disband ticked ships", func():
		var indices := checked_indices()
		if indices.is_empty():
			refused.emit(ForceRules.ERR_EMPTY_SELECTION)
		else:
			disband_requested.emit(fleet_id, indices))
	_label("Right-click a ringed sea to sail there. Esc deselects.", HINT_COLOR)


## --- Small builders -------------------------------------------------------

func _force_name(army_id: String) -> String:
	var army: Dictionary = game.state["armies"][army_id]
	var leader := "captain"
	if army["general"] != null and game.state["characters"].has(army["general"]):
		leader = game.state["characters"][army["general"]]["name"]
	return "%s's army (%d units)" % [leader, army["units"].size()]


func _fleet_name(fleet_id: String) -> String:
	return "Fleet %s (%d ships)" % [fleet_id.trim_prefix("fleet_"), game.state["fleets"][fleet_id]["ships"].size()]


func _settlement_name(region_id: String) -> String:
	return game.data.regions.get(region_id, {}).get("settlement_name", region_id)


func _kit_text(unit: Dictionary) -> String:
	var weapon := int(unit.get("weapon", 0))
	var armor := int(unit.get("armor", 0))
	if weapon == 0 and armor == 0:
		return ""
	return "w%d/a%d" % [weapon, armor]


static func explain(error: String) -> String:
	## The error vocabulary of ForceRules in the player's words.
	match error:
		"not_found":
			return "That force is no longer there."
		"wrong_owner":
			return "Those are not our men."
		"not_colocated":
			return "They are not in the same place."
		"over_cap":
			return "An army holds twenty units at most."
		"empty_selection":
			return "Tick the units first."
		"bad_index":
			return "The roster changed — look again."
		"last_unit":
			return "A general keeps at least one unit under him."
		"not_eligible_general":
			return "That man cannot take command here."
		"has_general":
			return "The army already has a general."
		"no_general":
			return "There is no general to detach."
		"two_generals":
			return "Two generals cannot share a camp in the field — transfer units instead, or merge in one of your cities."
		"no_settlement":
			return "Only in one of our cities."
		"foreign_settlement":
			return "Not in a foreign city."
		"same_force":
			return "That is the same force."
		"is_ship":
			return "Ships do not march."
		"not_ship":
			return "Only ships join a fleet."
		"not_docked":
			return "Ships are paid off only in a sea touching one of our ports."
		"nothing_to_do":
			return "Nothing to consolidate."
		"no_zone":
			return "That port does not touch this sea."
		"besieged":
			return "The city is invested — nobody marches out past the siege lines."
		"no_movement":
			return "Making port takes a sea lane of movement; the fleet has none left."
		"bad_args":
			return "That order is incomplete."
	return "That cannot be done (%s)." % error


func _dropdown(row: HBoxContainer) -> OptionButton:
	var options := OptionButton.new()
	options.focus_mode = Control.FOCUS_NONE
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.clip_text = true
	options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	options.add_theme_font_size_override("font_size", 11)
	row.add_child(options)
	return options


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	add_child(label)


func _label(text: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


func _action_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	# Focus stays off the panel so the arrow keys always drive the map.
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(handler)
	add_child(button)
	return button


class StrengthBar:
	extends Control
	## A tiny bar in the banner's colours: how many of a unit's men still stand.
	var fraction := 1.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.2, 0.22))
		var low := Color(0.85, 0.25, 0.20)
		var full := Color(0.35, 0.80, 0.35)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * fraction, size.y)), low.lerp(full, fraction))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), false, 1.0)
