class_name RegionPanel
extends VBoxContainer
## The right-hand context panel: everything about the selected region — the
## settlement (with the factor breakdowns the engine exposes), its garrison
## and harbour with the regrouping orders (raise, transfer, launch, disband),
## the armies and agents standing there, and every settlement action. The
## selected force itself is described by the ForcePanel above this one.

signal action_taken
signal army_selected(army_id: String)
signal army_raised(army_id: String)
signal fleet_launched(fleet_id: String)
signal disband_requested(force_id: String, indices: Array)
signal refused(error: String)
signal unit_info_requested(template_id: String)
signal building_info_requested(chain_id: String)
signal drawer_requested(tab: String, chain_id: String)
signal agent_selected(agent_id: String)
signal scout_requested(agent_id: String)
signal assassinate_requested(agent_id: String, target_char_id: String)
signal bribe_requested(agent_id: String, army_id: String)
signal steal_requested(agent_id: String, technique_id: String)

var game: Game
var region_id := ""
var selected_army := ""
var selected_agent := ""
var _garrison_checks: Array = []   # CheckBox per garrison unit, in order
var _harbour_checks: Array = []    # CheckBox per harbour ship, in order


func garrison_checked_indices() -> Array:
	var indices: Array = []
	for i in range(_garrison_checks.size()):
		if (_garrison_checks[i] as CheckBox).button_pressed:
			indices.append(i)
	return indices


func set_garrison_checked(indices: Array) -> void:
	for i in range(_garrison_checks.size()):
		(_garrison_checks[i] as CheckBox).button_pressed = indices.has(i)


func harbour_checked_indices() -> Array:
	var indices: Array = []
	for i in range(_harbour_checks.size()):
		if (_harbour_checks[i] as CheckBox).button_pressed:
			indices.append(i)
	return indices


func set_harbour_checked(indices: Array) -> void:
	for i in range(_harbour_checks.size()):
		(_harbour_checks[i] as CheckBox).button_pressed = indices.has(i)


func show_region(current_game: Game, new_region_id: String, army_id: String = "", agent_id: String = "") -> void:
	game = current_game
	region_id = new_region_id
	selected_army = army_id
	selected_agent = agent_id
	_rebuild()


func clear_panel() -> void:
	region_id = ""
	selected_army = ""
	selected_agent = ""
	_clear_children()


func show_idle_hint(current_game: Game) -> void:
	## Nothing selected: instead of an empty column, the three things a new
	## player needs to know, and the count of forces still awaiting orders.
	game = current_game
	clear_panel()
	_header("Nothing selected", 13)
	_label(String(game.data.effects_glossary["map_commands"]["map_intro"]), Color(0.7, 0.8, 0.9))
	_label(String(game.data.effects_glossary["map_commands"]["idle_controls"]), Color(0.7, 0.8, 0.9))
	_label("Esc deselects; Tab or N jumps to the next force awaiting orders. Options ▾ (top bar) lists every control and the mode switches.", Color(0.7, 0.8, 0.9))
	var waiting := game.forces_awaiting_orders()
	if not waiting.is_empty():
		_label("%d force%s still ha%s orders to give this season." % [waiting.size(),
			"" if waiting.size() == 1 else "s", "s" if waiting.size() == 1 else "ve"], UiStyle.PARCHMENT)


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

	var words: Dictionary = game.data.effects_glossary["map_commands"]
	if not game.known_regions().has(region_id):
		_header(words["chart_unknown"], 16)
		_label(words["uncharted"])
		return
	if not is_visible:
		_header(region["name"], 16)
		_label(words["chart_known"])
		_terrain_details(region)
		return

	_header("%s — %s" % [region["name"], region["settlement_name"]], 16)
	_terrain_details(region)
	var resources: Array = region.get("resources", [])
	if not resources.is_empty():
		_label("Goods: " + ", ".join(resources))
	var site := _unexplored_site()
	if not site.is_empty():
		_label("A place worth searching: %s" % site["name"], Color(0.9, 0.8, 0.5))

	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if not settlement.is_empty():
		_build_settlement_section(settlement)
	_build_armies_section()
	_build_agents_section()


func _terrain_details(region: Dictionary) -> void:
	var words: Dictionary = game.data.effects_glossary["map_commands"]
	var report := game.terrain_report(region_id)
	var profile: Dictionary = game.data.terrain_content.get("terrains", {}).get(region["terrain"], {})
	_label(String(words["ground_report"]).format({"name": profile.get("name", region["terrain"]),
		"cost": String.num(report.get("movement", 0.0), 2), "defense": roundi((float(report.get("defense", 1.0)) - 1.0) * 100)}))
	_label(profile.get("description", ""), UiStyle.TEXT_DIM)
	for neighbor in region.get("adjacent", []):
		if not game.known_regions().has(neighbor):
			continue
		var kind := TerrainRules.crossing_kind(game.data, region_id, neighbor)
		if kind == "":
			continue
		var crossing: Dictionary = game.data.terrain_content["crossing_types"][kind]
		_label("%s · %s" % [game.data.regions[neighbor]["name"], crossing["name"]], UiStyle.PARCHMENT)
		_label(crossing["description"], UiStyle.TEXT_DIM)


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
		var words: Dictionary = game.data.effects_glossary.get("map_commands", {})
		_label(String(words.get("garrison_map", "{men} / {walls}")).format({"men": CombatRules.soldiers_in(game.data, settlement["garrison"]),
			"walls": int(SettlementRules.effect_max(game.data, settlement, "wall_level"))}), UiStyle.PARCHMENT)
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
	tax_options.focus_mode = Control.FOCUS_NONE
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

	# Garrison — tick units to raise them as an army, move them into an army
	# standing here, or send them home; right-click a row for the unit's card.
	var garrison: Array = settlement["garrison"]
	var harbour: Array = settlement.get("harbour", [])
	if not garrison.is_empty():
		_header("Garrison (%d) — tick units to raise or move" % garrison.size(), 12)
		for unit in garrison:
			_garrison_checks.append(_unit_check_row(unit))
		_garrison_actions(settlement)
	# Harbour — ships waiting in port; tick them to put a fleet to sea.
	if not harbour.is_empty():
		_header("Harbour (%d) — tick ships to launch" % harbour.size(), 12)
		for ship in harbour:
			_harbour_checks.append(_unit_check_row(ship))
		_harbour_actions()
	if not garrison.is_empty() or not harbour.is_empty():
		_action_button("Retrain garrison%s" % (" and harbour" if not harbour.is_empty() else ""), func():
			game.retrain_garrison(region_id)
			action_taken.emit())

	# Construction. Unaffordable actions render disabled instead of silently
	# doing nothing when clicked.
	var treasury := int(game.state["factions"][player]["treasury"])
	_header("Construction", 12)
	for job in settlement["construction_queue"]:
		_label("  building %s — %d turns left" % [_chain_name(job["chain"]), int(job["turns_left"])])
	var projects: Array = game.available_buildings(region_id)
	_action_button("Open the building yard — %d project%s"
		% [projects.size(), "" if projects.size() == 1 else "s"],
		func(): drawer_requested.emit("construction", ""))
	var purse := int(game.state["factions"][game.state["player_faction"]]["treasury"])
	var affordable: Array = []
	for project in projects:
		if int(project["cost"]) <= purse:
			affordable.append(project)
	affordable.sort_custom(func(a, b): return int(a["cost"]) < int(b["cost"]))
	for i in mini(affordable.size(), 3):
		var project: Dictionary = affordable[i]
		var build_chain: String = project["chain"]
		_action_button("Build %s (%d, %dt)"
			% [project["name"], int(project["cost"]), int(project["build_turns"])],
			func():
				game.queue_building(region_id, build_chain)
				action_taken.emit(),
			func(): building_info_requested.emit(build_chain))

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
				action_taken.emit(),
			func(): building_info_requested.emit(chain_id))

	# Recruitment
	_header("Recruitment", 12)
	for job in settlement["recruitment_queue"]:
		_label("  mustering %s" % _template_name(job["template"]))
	_action_button("Open the muster hall",
		func(): drawer_requested.emit("units", ""))
	for unit in game.available_units(region_id):
		var recruit_id: String = unit["id"]
		# What this recruit will carry out of this town: chevrons and kit.
		var profile := game.recruit_profile(region_id, recruit_id)
		var issue := _kit_text(profile)
		if int(profile["experience"]) > 0:
			issue = ("xp%d" % int(profile["experience"])) + (" " + issue if issue != "" else "")
		_action_button("Recruit %s [%s] (%d)%s" % [unit["name"], String(unit.get("class", "")).replace("_", " "),
				int(unit["cost"]), " — " + issue if issue != "" else ""],
			func():
				game.queue_unit(region_id, recruit_id)
				action_taken.emit(),
			func(): unit_info_requested.emit(recruit_id))

	# Agents train here too, behind their building gates.
	var agent_count := 0
	for agent in game.state["agents"].values():
		if agent["owner"] == player:
			agent_count += 1
	var at_cap: bool = agent_count >= int(game.data.balance["agents"]["max_per_faction"])
	var agent_kind_ids: Array = game.data.agent_kinds.keys()
	agent_kind_ids.sort()
	for kind in agent_kind_ids:
		var template: Dictionary = game.data.agent_kinds[kind]
		if not AgentRules.building_gate_met(game.data, settlement, template):
			continue
		var label := "Train %s (%d)" % [template["name"], int(template["cost"])]
		if at_cap:
			label += " — all hands employed"
		var button := _action_button(label,
			func():
				game.recruit_agent(region_id, kind)
				action_taken.emit(),
			Callable(), at_cap or treasury < int(template["cost"]))
		button.tooltip_text = String(template.get("description", ""))


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
			# Toggles the selection; the roster and every order — attack,
			# siege, march, regroup — live on the force card above.
			var button := Button.new()
			button.text = ("▶ " if army_id == selected_army else "") + title
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func(): army_selected.emit(army_id))
			add_child(button)
		else:
			_label(title, Color.html(faction.get("color", "#808080")))


func _unit_check_row(unit: Dictionary) -> CheckBox:
	## A garrison or harbour row: a tick box for the regrouping orders and the
	## unit line, which answers a right-click with the unit's card.
	var row := HBoxContainer.new()
	add_child(row)
	var check := CheckBox.new()
	check.focus_mode = Control.FOCUS_NONE
	check.custom_minimum_size = Vector2(22, 0)
	row.add_child(check)
	var label := Label.new()
	label.text = _unit_line(unit)
	label.add_theme_font_size_override("font_size", 11)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var template_id := String(unit["template"])
	_info_on_rightclick(label, func(): unit_info_requested.emit(template_id))
	row.add_child(label)
	return check


func _garrison_actions(settlement: Dictionary) -> void:
	var here := region_id
	var player: String = game.state["player_faction"]
	if settlement["siege"] != null:
		_label("    the city is invested — nobody marches out past the siege lines", Color(1, 0.5, 0.4))
		return

	# Raise the ticked units as an army under ▾
	var candidates := game.candidate_generals(here)
	var leaders: Array = [""]
	var leader_names: Array = ["a captain"]
	for char_id in candidates:
		leaders.append(char_id)
		leader_names.append(game.state["characters"][char_id]["name"])
	var raise_row := HBoxContainer.new()
	add_child(raise_row)
	var raise := Button.new()
	raise.text = "Raise army under →"
	raise.focus_mode = Control.FOCUS_NONE
	raise.add_theme_font_size_override("font_size", 11)
	raise_row.add_child(raise)
	var leader_options := _dropdown(raise_row)
	for leader_name in leader_names:
		leader_options.add_item(String(leader_name))
	raise.pressed.connect(func():
		var choice: String = leaders[maxi(leader_options.selected, 0)]
		var result := game.raise_units(here, garrison_checked_indices(), choice)
		if result["ok"]:
			army_raised.emit(result["army_id"])
		else:
			refused.emit(result["error"]))
	_action_button("Raise the whole garrison into the field", func():
		var army_id := game.raise_army(here)
		if army_id != "":
			army_raised.emit(army_id)
		else:
			action_taken.emit())

	# Transfer the ticked units into an army standing here ▾
	var armies: Array = []
	for army_id in ForceRules.armies_in(game.state, here):
		if game.state["armies"][army_id]["owner"] == player:
			armies.append(army_id)
	if not armies.is_empty():
		var row := HBoxContainer.new()
		add_child(row)
		var move := Button.new()
		move.text = "Transfer ticked →"
		move.focus_mode = Control.FOCUS_NONE
		move.add_theme_font_size_override("font_size", 11)
		row.add_child(move)
		var options := _dropdown(row)
		for army_id in armies:
			var army: Dictionary = game.state["armies"][army_id]
			var leader := "captain"
			if army["general"] != null and game.state["characters"].has(army["general"]):
				leader = game.state["characters"][army["general"]]["name"]
			options.add_item("%s's army (%d units)" % [leader, army["units"].size()])
		move.pressed.connect(func():
			if options.selected < 0:
				return
			var result := game.transfer_units("garrison:" + here, armies[options.selected], garrison_checked_indices())
			if result["ok"]:
				action_taken.emit()
			else:
				refused.emit(result["error"]))

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
	launch.focus_mode = Control.FOCUS_NONE
	launch.add_theme_font_size_override("font_size", 11)
	row.add_child(launch)
	var options := _dropdown(row)
	for zone_id in zones:
		options.add_item(String(game.data.sea_zones.get(zone_id, {}).get("name", zone_id)))
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


func _dropdown(row: HBoxContainer) -> OptionButton:
	var options := OptionButton.new()
	options.focus_mode = Control.FOCUS_NONE
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.clip_text = true
	options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	options.add_theme_font_size_override("font_size", 11)
	row.add_child(options)
	return options


func _unexplored_site() -> Dictionary:
	var site: Dictionary = game.data.sites_by_region.get(region_id, {})
	if site.is_empty() or game.state.get("sites_explored", []).has(site["id"]):
		return {}
	return site


func _build_agents_section() -> void:
	var player: String = game.state["player_faction"]
	var here := game.agents_in(region_id)
	if here.is_empty():
		return
	_separator()
	_header("Agents here", 13)
	for entry in here:
		var agent: Dictionary = entry["agent"]
		var agent_id: String = entry["id"]
		var faction: Dictionary = game.data.factions.get(agent["owner"], {})
		var kind_name: String = game.data.agent_kinds.get(agent["kind"], {}).get("name", agent["kind"])
		var title := "%s %s (skill %d)" % [kind_name, agent["name"], int(agent["skill"])]
		if agent["owner"] == player:
			var button := Button.new()
			button.text = ("◆ " if agent_id == selected_agent else "") + title
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 11)
			button.pressed.connect(func(): agent_selected.emit(agent_id))
			add_child(button)
			if agent_id == selected_agent:
				_build_selected_agent_detail(agent_id, agent)
		else:
			_label("%s — %s" % [faction.get("name", agent["owner"]), title],
				Color.html(faction.get("color", "#808080")))


func _build_selected_agent_detail(agent_id: String, agent: Dictionary) -> void:
	_label("Movement left: %.1f" % float(agent["movement_left"]))
	_label("Click an adjacent region to travel — any border is open to him.", Color(0.7, 0.8, 0.9))

	match String(agent["kind"]):
		"spy":
			if game.state["settlements"].has(region_id):
				_action_button("Scout the settlement", func(): scout_requested.emit(agent_id))
				_build_steal_options(agent_id, agent)
		"assassin":
			var targets: Array = []
			var char_ids: Array = game.state["characters"].keys()
			char_ids.sort()
			for char_id in char_ids:
				var character: Dictionary = game.state["characters"][char_id]
				if character["alive"] and character.get("location", "") == region_id \
						and character["faction"] != game.state["player_faction"]:
					targets.append(char_id)
			if not targets.is_empty():
				var picker := OptionButton.new()
				picker.focus_mode = Control.FOCUS_NONE
				for char_id in targets:
					var character: Dictionary = game.state["characters"][char_id]
					var odds := AgentRules.assassination_chance(game.data, game.state, agent, character)
					picker.add_item("%s (%d%%)" % [character["name"], int(round(odds * 100))])
				add_child(picker)
				_action_button("Send the blade", func():
					if picker.selected >= 0:
						assassinate_requested.emit(agent_id, targets[picker.selected]))
		"diplomat":
			var bands: Array = []
			var army_ids: Array = game.state["armies"].keys()
			army_ids.sort()
			for army_id in army_ids:
				var army: Dictionary = game.state["armies"][army_id]
				if army["region"] == region_id and army["owner"] != game.state["player_faction"] \
						and army["general"] == null:
					bands.append(army_id)
			for army_id in bands:
				var army: Dictionary = game.state["armies"][army_id]
				var cost := AgentRules.bribe_cost(game.data, army)
				var owner_name: String = game.data.factions.get(army["owner"], {}).get("name", army["owner"])
				_action_button("Bribe the %s band — %d units (%d)" % [owner_name, army["units"].size(), cost],
					func(): bribe_requested.emit(agent_id, army_id))


func _build_steal_options(agent_id: String, agent: Dictionary) -> void:
	## Crafts the city's owner practices and our court has never heard of —
	## the spy can bring the drawings home, with the odds shown up front.
	var owner: String = game.state["settlements"][region_id]["owner"]
	var player: String = game.state["player_faction"]
	if owner == player:
		return
	var ours: Dictionary = game.state["factions"][player].get("knowledge", {})
	var theirs: Dictionary = game.state["factions"].get(owner, {}).get("knowledge", {})
	var stealable: Array = []
	var tids: Array = theirs.keys()
	tids.sort()
	for tid in tids:
		if String(theirs[tid].get("stage", "")) == "adopted" and not ours.has(tid):
			stealable.append(tid)
	if stealable.is_empty():
		return
	var odds := AgentRules.steal_chance(game.data, game.state, agent)
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for tid in stealable:
		picker.add_item(String(game.data.techniques.get(tid, {}).get("name", tid)))
	add_child(picker)
	_action_button("Steal the craft (%d%%)" % int(round(odds * 100)), func():
		if picker.selected >= 0:
			steal_requested.emit(agent_id, stealable[picker.selected]))


## --- Small builders -------------------------------------------------------

func _header(text: String, font_size: int, color: Color = UiStyle.PARCHMENT) -> void:
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
	options.focus_mode = Control.FOCUS_NONE   # Tab must always reach the map's force cycling
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
	_label(title, UiStyle.PARCHMENT)
	for factor in factors:
		var value := float(factor["value"])
		var color := Color(0.55, 0.85, 0.55) if value >= 0 else Color(0.9, 0.55, 0.5)
		_label("    %s  %+.1f" % [String(factor["label"]).replace("_", " "), value], color)


func _action_button(text: String, handler: Callable, info: Callable = Callable(),
		unaffordable: bool = false) -> Button:
	## One button builder for both branches' conventions: `info` wires the
	## right-click "what is this?" card, `unaffordable` greys it out so the
	## button can explain itself instead of going dead.
	var button := Button.new()
	button.text = text
	# Focus stays off the panel so the arrow keys always drive the map.
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(handler)
	if info.is_valid():
		_info_on_rightclick(button, info)
	button.disabled = unaffordable
	add_child(button)
	return button


func _info_on_rightclick(control: Control, info: Callable) -> void:
	## R2's gesture on panel rows: right-click asks "what is this?".
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT \
				and (event as InputEventMouseButton).pressed:
			info.call())


func _info_label(text: String, template_id: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	## A unit row that answers a right-click with its card.
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_on_rightclick(label, func(): unit_info_requested.emit(template_id))
	add_child(label)


func _separator() -> void:
	add_child(HSeparator.new())


func settlement_display_name() -> String:
	return game.data.regions.get(region_id, {}).get("settlement_name", region_id)


static func odds_text(estimate: Dictionary) -> String:
	## "odds 1.42:1 — 78% to win", from BattleResolver.estimate's paper ratio.
	## A chance that is not exactly certain never shows as 0% or 100%.
	if int(estimate.get("defender", {}).get("soldiers", 1)) <= 0:
		return "undefended"
	var chance := float(estimate.get("attacker_win_chance", 0.5))
	var percent := int(round(chance * 100.0))
	if chance > 0.0 and chance < 1.0:
		percent = clampi(percent, 1, 99)
	return "odds %.2f:1 — %d%% to win" % [float(estimate.get("ratio", 1.0)), percent]


func _unit_line(unit: Dictionary) -> String:
	## "Hastati [infantry]  100%  xp2  w1/a1" — class always, kit only when issued.
	var template: Dictionary = game.data.units.get(unit["template"], {})
	var line := "%s [%s]  %d%%  xp%d" % [_unit_name(unit), String(template.get("class", "?")).replace("_", " "),
		int(unit["strength_pct"]), int(unit["experience"])]
	var kit := _kit_text(unit)
	return line + ("  " + kit if kit != "" else "")


func _kit_text(holder: Dictionary) -> String:
	var weapon := int(holder.get("weapon", 0))
	var armor := int(holder.get("armor", 0))
	if weapon == 0 and armor == 0:
		return ""
	return "w%d/a%d" % [weapon, armor]


func _unit_name(unit: Dictionary) -> String:
	return _template_name(unit["template"])


func _template_name(template_id: String) -> String:
	return game.data.units.get(template_id, {}).get("name", template_id)


func _chain_name(chain_id: String) -> String:
	return game.data.chains.get(chain_id, {}).get("name", chain_id)
