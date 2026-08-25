class_name CampaignScreen
extends Control
## The campaign in play: top bar (treasury, date, standings, end turn), the
## map in the middle, the region context panel and turn log on the right.
## All rules go through the Game facade — this screen never touches state
## except to read it for display.

const SAVE_PATH := "user://roman_war_save.json"

var game: Game

var map_view: MapView
var region_panel: RegionPanel
var family_panel: FamilyPanel
var diplomacy_panel: DiplomacyPanel
var report_log: RichTextLabel
var top_labels := {}
var top_swatch: ColorRect
var selected_army := ""
var selected_agent := ""
var _victory_shown := false


static func create(new_game: Game) -> CampaignScreen:
	var screen := CampaignScreen.new()
	screen.game = new_game
	return screen


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_top_bar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	map_view = MapView.new()
	map_view.game = game
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.custom_minimum_size = Vector2(600, 400)
	map_view.region_clicked.connect(_on_region_clicked)
	split.add_child(map_view)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	split.add_child(side)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	region_panel = RegionPanel.new()
	region_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_panel.action_taken.connect(refresh)
	region_panel.army_selected.connect(_on_army_selected)
	region_panel.attack_requested.connect(attack_army_order)
	region_panel.siege_requested.connect(besiege_order)
	region_panel.agent_selected.connect(_on_agent_selected)
	region_panel.scout_requested.connect(_scout_order)
	region_panel.assassinate_requested.connect(_assassinate_order)
	region_panel.bribe_requested.connect(_bribe_order)
	scroll.add_child(region_panel)

	report_log = RichTextLabel.new()
	report_log.custom_minimum_size = Vector2(0, 160)
	report_log.scroll_following = true
	report_log.bbcode_enabled = true
	side.add_child(report_log)

	family_panel = FamilyPanel.new()
	family_panel.family_changed.connect(refresh)
	add_child(family_panel)

	diplomacy_panel = DiplomacyPanel.new()
	diplomacy_panel.stance_changed.connect(refresh)
	add_child(diplomacy_panel)

	_log("[b]The year is 270 BC.[/b] Your house awaits its orders.")
	# Centering must wait for the first layout, or it centers on the map's
	# minimum size rather than the window it actually gets.
	var capital: String = game.state["factions"][game.state["player_faction"]]["capital"]
	map_view.center_on.call_deferred(capital)
	refresh()


func _build_top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 34)

	top_swatch = ColorRect.new()
	top_swatch.custom_minimum_size = Vector2(18, 18)
	bar.add_child(top_swatch)

	for key in ["faction", "treasury", "date", "senate", "victory"]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		bar.add_child(label)
		top_labels[key] = label

	bar.add_child(_spacer())
	bar.add_child(_bar_button("Family", func(): family_panel.open_for(game)))
	bar.add_child(_bar_button("Diplomacy", func(): diplomacy_panel.open_for(game)))
	bar.add_child(_bar_button("Save", _save_game))
	bar.add_child(_bar_button("Load", _load_game))
	var end_turn := _bar_button("END TURN", _end_turn)
	end_turn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	bar.add_child(end_turn)
	return bar


func refresh() -> void:
	var faction: Dictionary = game.state["factions"][game.state["player_faction"]]
	# The whole identity re-derives here, not just at build time — a loaded
	# save may belong to a different house than the campaign that was running.
	var faction_info: Dictionary = game.data.factions[game.state["player_faction"]]
	top_swatch.color = Color.html(faction_info.get("color", "#808080"))
	top_labels["faction"].text = " %s   " % faction_info["name"]
	top_labels["treasury"].text = "Treasury: %d   " % int(faction["treasury"])
	var year := int(game.state["year"])
	var year_text := "%d BC" % -year if year < 0 else "AD %d" % year
	top_labels["date"].text = "%s, %s   " % [year_text, String(game.state["season"]).capitalize()]
	if faction_info.get("is_roman_house", false):
		top_labels["senate"].text = "Senate %.0f · People %.0f   " \
			% [float(faction["senate_standing"]), float(faction["popular_standing"])]
	else:
		top_labels["senate"].text = ""
	var progress := game.victory_progress()
	if not progress.is_empty():
		top_labels["victory"].text = "Regions %d/%d" \
			% [int(progress["regions_held"]), int(progress["regions_needed"])]

	if map_view.selected_region != "":
		region_panel.show_region(game, map_view.selected_region, selected_army, selected_agent)
	map_view.queue_redraw()

	if game.state["winner"] != null and not _victory_shown:
		_show_victory_banner(String(game.state["winner"]))


func _on_region_clicked(region_id: String) -> void:
	# With one of our armies (or agents) selected, a click on another region is
	# an order. Shift makes an army's march forced: double range, weary men.
	if selected_army != "" and game.state["armies"].has(selected_army) \
			and region_id != game.state["armies"][selected_army]["region"]:
		_army_order(region_id, Input.is_key_pressed(KEY_SHIFT))
		return
	if selected_agent != "" and game.state["agents"].has(selected_agent) \
			and region_id != game.state["agents"][selected_agent]["region"]:
		_agent_order(region_id)
		return
	map_view.selected_region = region_id
	selected_army = ""
	selected_agent = ""
	region_panel.show_region(game, region_id)
	map_view.queue_redraw()


func _on_army_selected(army_id: String) -> void:
	selected_army = "" if selected_army == army_id else army_id
	selected_agent = ""
	region_panel.show_region(game, map_view.selected_region, selected_army)


func _on_agent_selected(agent_id: String) -> void:
	selected_agent = "" if selected_agent == agent_id else agent_id
	selected_army = ""
	region_panel.show_region(game, map_view.selected_region, "", selected_agent)


func _agent_order(target_region: String) -> void:
	if game.move_agent(selected_agent, target_region):
		_log("Our agent slips away toward %s." % game.data.regions[target_region]["name"])
	else:
		_log("Our agent cannot reach %s this season." % game.data.regions[target_region]["name"])
	if game.state["agents"].has(selected_agent):
		map_view.selected_region = game.state["agents"][selected_agent]["region"]
	region_panel.show_region(game, map_view.selected_region, "", selected_agent)
	refresh()


func _scout_order(agent_id: String) -> void:
	var report := game.agent_scout(agent_id)
	if report.is_empty():
		return
	var lines := "Population %d, public order %d%%.\n" \
		% [int(report["population"]), int(report["public_order"])]
	if report["under_siege"]:
		lines += "The city is under siege.\n"
	lines += "\nGarrison (%d):\n" % report["garrison"].size()
	for unit in report["garrison"]:
		lines += "  %s — %d%%\n" % [unit["name"], int(unit["strength_pct"])]
	lines += "\nWorks:\n"
	for building in report["buildings"]:
		lines += "  %s\n" % building
	var dialog := AcceptDialog.new()
	dialog.title = "The informer's report: %s" \
		% game.data.regions[report["region"]]["settlement_name"]
	dialog.dialog_text = lines
	add_child(dialog)
	dialog.popup_centered()
	_log("Our informer reports from %s." % game.data.regions[report["region"]]["settlement_name"])


func _assassinate_order(agent_id: String, target_char_id: String) -> void:
	var target: Dictionary = game.state["characters"].get(target_char_id, {})
	if target.is_empty():
		return
	_confirm("Send the blade against %s? Failure may cost us the man." % target["name"], func():
		var result := game.agent_assassinate(agent_id, target_char_id)
		if result.get("success", false):
			_log("[color=#e06050][b]%s is dead.[/b] No one knows whose coin paid for it.[/color]"
				% target["name"])
		elif result.get("agent_lost", false):
			_log("[color=#e0a060]The attempt on %s failed — our blade was taken.[/color]"
				% target["name"])
		elif result.get("attempted", false):
			_log("The attempt on %s failed; our man slipped away." % target["name"])
		refresh())


func _bribe_order(agent_id: String, army_id: String) -> void:
	var army: Dictionary = game.state["armies"].get(army_id, {})
	if army.is_empty():
		return
	var cost := AgentRules.bribe_cost(game.data, army)
	_confirm("Pay %d to send this band home?" % cost, func():
		var result := game.agent_bribe(agent_id, army_id)
		if result.get("success", false):
			_log("The band took our %d and scattered." % int(result["cost"]))
		elif result.get("refused_loyal", false):
			_log("They follow their general, not our purse.")
		else:
			_log("Our purse cannot meet their price.")
		refresh())


func _army_order(target_region: String, forced_march: bool = false) -> void:
	var army: Dictionary = game.state["armies"][selected_army]
	var player: String = game.state["player_faction"]

	# Only an army we are ALREADY at war with is a target — marching past a
	# neutral must never start a war by accident. Deliberate first strikes go
	# through the explicit Attack button in the region panel.
	var defender := _enemy_army_in(target_region)
	if defender != "":
		attack_army_order(defender)
		return

	# A settlement of a faction we are at war with can be invested.
	var settlement: Dictionary = game.state["settlements"].get(target_region, {})
	if not settlement.is_empty() and settlement["owner"] != player \
			and DiplomacyRules.at_war(game.state, player, settlement["owner"]) \
			and MapRules.are_adjacent(game.data, army["region"], target_region):
		besiege_order(target_region)
		return

	# Otherwise: march (or sail).
	if game.move_army(selected_army, target_region, forced_march):
		var suffix := " by forced march — the men will be weary." if forced_march else "."
		_log("The army marches to %s%s" % [game.data.regions[target_region]["name"], suffix])
	elif game.sea_move_army(selected_army, target_region):
		_log("The army takes ship for %s." % game.data.regions[target_region]["name"])
	else:
		_log("The army cannot reach %s this season." % game.data.regions[target_region]["name"])
	_after_order()


func _enemy_army_in(region_id: String) -> String:
	## An at-war army we can actually see. Invisible armies must not influence
	## orders at all, or the log itself leaks their presence.
	var player: String = game.state["player_faction"]
	if not game.visible_regions().has(region_id):
		return ""
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var other: Dictionary = game.state["armies"][army_id]
		if other["region"] == region_id and DiplomacyRules.at_war(game.state, player, other["owner"]):
			return army_id
	return ""


func attack_army_order(defender_id: String) -> void:
	## Attacking a faction we are not yet at war with is a decision, not a
	## mis-click, so it is confirmed first.
	var defender: Dictionary = game.state["armies"].get(defender_id, {})
	if defender.is_empty():
		return
	var player: String = game.state["player_faction"]
	if not DiplomacyRules.at_war(game.state, player, defender["owner"]):
		var faction_name: String = game.data.factions.get(defender["owner"], {}).get("name", defender["owner"])
		_confirm("This will declare war on %s. Attack?" % faction_name,
			func(): _resolve_attack(defender_id))
		return
	_resolve_attack(defender_id)


func _resolve_attack(defender_id: String) -> void:
	var result := game.attack_army(selected_army, defender_id)
	if result.is_empty():
		_log("The army cannot come to grips with the enemy from here.")
	else:
		_log("[b]Battle![/b] The %s prevail." % ("attackers" if result["winner"] == "attacker" else "defenders"))
	_after_order()


func besiege_order(target_region: String) -> void:
	var settlement: Dictionary = game.state["settlements"].get(target_region, {})
	if settlement.is_empty():
		return
	var player: String = game.state["player_faction"]
	if not DiplomacyRules.at_war(game.state, player, settlement["owner"]):
		var faction_name: String = game.data.factions.get(settlement["owner"], {}).get("name", settlement["owner"])
		_confirm("This will declare war on %s. Lay siege?" % faction_name,
			func(): _resolve_siege(target_region))
		return
	_resolve_siege(target_region)


func _resolve_siege(target_region: String) -> void:
	if game.besiege(selected_army, target_region):
		_log("Siege laid to %s." % game.data.regions[target_region]["settlement_name"])
	else:
		_log("No siege can be laid there.")
	_after_order()


func _confirm(text: String, on_accept: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = text
	dialog.confirmed.connect(on_accept)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _after_order() -> void:
	if game.state["armies"].has(selected_army):
		map_view.selected_region = game.state["armies"][selected_army]["region"]
	else:
		selected_army = ""
	region_panel.show_region(game, map_view.selected_region, selected_army)
	refresh()


func _end_turn() -> void:
	var report := game.end_turn()
	_log_report(report)
	selected_army = ""
	selected_agent = ""
	refresh()


func _log_report(report: Dictionary) -> void:
	var year := int(game.state["year"])
	var year_text := "%d BC" % -year if year < 0 else "AD %d" % year
	_log("[b]— %s, %s —[/b]" % [year_text, String(game.state["season"]).capitalize()])

	var player: String = game.state["player_faction"]
	for region_id in report["completed_buildings"]:
		if game.state["settlements"].has(region_id) and game.state["settlements"][region_id]["owner"] == player:
			for level_id in report["completed_buildings"][region_id]:
				_log("Completed in %s: %s" % [game.data.regions[region_id]["settlement_name"],
					game.data.building_levels.get(level_id, {}).get("level", {}).get("name", level_id)])
	for region_id in report["completed_units"]:
		if game.state["settlements"].has(region_id) and game.state["settlements"][region_id]["owner"] == player:
			for template_id in report["completed_units"][region_id]:
				_log("Mustered in %s: %s" % [game.data.regions[region_id]["settlement_name"],
					game.data.units.get(template_id, {}).get("name", template_id)])
	for region_id in report["rioted"]:
		if game.state["settlements"][region_id]["owner"] == player:
			_log("[color=#e0a060]Riots in %s![/color]" % game.data.regions[region_id]["settlement_name"])
	for region_id in report["revolted"]:
		_log("[color=#e06050]%s has risen in revolt![/color]" % game.data.regions[region_id]["settlement_name"])
	for event in report["events"]:
		if event["kind"] == "event":
			var event_def := {}
			for candidate in game.data.events:
				if candidate["id"] == event["id"]:
					event_def = candidate
			_log("[color=#c0b060][b]%s[/b][/color] %s" % [event_def.get("name", event["id"]), event_def.get("text", "")])
		else:
			var struck: String = event.get("region", "")
			_log("[color=#e06050]Disaster strikes %s![/color]"
				% game.data.regions.get(struck, {}).get("settlement_name", struck))
	for notice in report["senate"]:
		if notice["faction"] == player:
			var mission_id: String = str(notice.get("mission", ""))
			var mission_name: String = game.data.missions.get(mission_id, {}).get("name", mission_id)
			_log("[color=#9090d0]Senate: %s%s[/color]" % [String(notice["kind"]).replace("_", " "),
				"" if mission_name == "" else " — " + mission_name])
	for notice in report["characters"]:
		if notice.get("faction", "") != player and not _is_player_character(notice.get("character", "")):
			continue
		var who: String = game.state["characters"].get(notice.get("character", ""), {}).get("name", "")
		var detail := ""
		if notice.has("name"):
			detail = " — " + String(notice["name"])
		elif notice.has("ancillary"):
			detail = " — " + String(game.data.ancillaries.get(notice["ancillary"], {}).get("name", notice["ancillary"]))
		_log("[color=#80b080]%s: %s%s[/color]" % [String(notice["kind"]).replace("_", " "), who, detail])
	_log_starved_sieges(report)
	_log_world_news(report)


func _log_starved_sieges(report: Dictionary) -> void:
	## Starve-out resolutions, with the outcome stated — and only the ones the
	## player can see or is party to (fogged sieges stay unheard of).
	var player: String = game.state["player_faction"]
	var visible_set := game.visible_regions()
	for siege_event in report["sieges"]:
		var region_id: String = siege_event["region"]
		var result: Dictionary = siege_event.get("result", {})
		var captured: bool = result.get("captured", false)
		var new_owner: String = result.get("capture_pending_owner", "")
		var previous_owner: String = siege_event.get("previous_owner", "")
		if new_owner != player and previous_owner != player and not visible_set.has(region_id):
			continue
		var settlement_name: String = game.data.regions[region_id]["settlement_name"]
		if captured and new_owner == player:
			_log("[color=#80c080][b]%s has starved out — the city is ours.[/b][/color]" % settlement_name)
		elif captured and previous_owner == player:
			_log("[color=#e06050][b]%s has fallen — starved out by %s.[/b][/color]"
				% [settlement_name, _faction_name(new_owner)])
		elif captured:
			_log("%s starved out and fell to %s." % [settlement_name, _faction_name(new_owner)])
		else:
			_log("The defenders of %s broke the siege at the walls." % settlement_name)


func _log_world_news(report: Dictionary) -> void:
	## The living world: wars, conquests, treaties and envoys. World-shaking
	## news is always heard; skirmish detail only when it touches the player.
	var player: String = game.state["player_faction"]
	for event in report["ai"]:
		match String(event.get("kind", "")):
			"war_declared":
				var color := "#e06050" if event["on"] == player else "#d0a0a0"
				_log("[color=%s][b]%s declares war on %s![/b][/color]"
					% [color, _faction_name(event["by"]), _faction_name(event["on"])])
			"ai_conquest":
				_log("[color=#d0a0a0]%s has taken %s from %s.[/color]"
					% [_faction_name(event["faction"]),
						game.data.regions.get(event["region"], {}).get("settlement_name", event["region"]),
						_faction_name(event["from"])])
			"peace_made":
				_log("[color=#a0c0a0]Peace between %s and %s.[/color]"
					% [_faction_name(event["between"][0]), _faction_name(event["between"][1])])
			"trade_agreed":
				_log("[color=#a0c0a0]%s and %s open their markets to each other.[/color]"
					% [_faction_name(event["between"][0]), _faction_name(event["between"][1])])
			"offer_sent":
				if event["to"] == player:
					_log("[color=#c0b060][b]An envoy from %s awaits our answer (Diplomacy).[/b][/color]"
						% _faction_name(event["from"]))
			"ai_attack":
				if event["defender"] == player:
					_log("[color=#e06050][b]%s attacks our army near %s — the %s prevail.[/b][/color]"
						% [_faction_name(event["faction"]),
							game.data.regions.get(event["region"], {}).get("name", event["region"]),
							"attackers" if event.get("winner", "") == "attacker" else "defenders"])
			"ai_siege":
				if event["owner"] == player:
					_log("[color=#e06050][b]%s lays siege to %s![/b][/color]"
						% [_faction_name(event["faction"]),
							game.data.regions.get(event["region"], {}).get("settlement_name", event["region"])])
	for event in report["diplomacy"]:
		match String(event.get("kind", "")):
			"tribute_paid":
				if event["from"] == player:
					_log("We pay %d in tribute to %s." % [int(event["amount"]), _faction_name(event["to"])])
				elif event["to"] == player:
					_log("[color=#a0c0a0]Tribute of %d arrives from %s.[/color]"
						% [int(event["amount"]), _faction_name(event["from"])])
			"offer_expired":
				_log("The envoy from %s departs unanswered." % _faction_name(event["from"]))


func _faction_name(faction_id: String) -> String:
	return game.data.factions.get(faction_id, {}).get("name", faction_id)


func _is_player_character(char_id: String) -> bool:
	return game.state["characters"].get(char_id, {}).get("faction", "") == game.state["player_faction"]


func _show_victory_banner(winner: String) -> void:
	_victory_shown = true
	var dialog := AcceptDialog.new()
	dialog.title = "The campaign is decided"
	if winner == "time_up":
		dialog.dialog_text = "AD 14 has come. The age closes with no master of the world."
	elif winner == game.state["player_faction"]:
		dialog.dialog_text = "Your house rules the world. The campaign is won!"
	else:
		dialog.dialog_text = "%s has won the age." % game.data.factions.get(winner, {}).get("name", winner)
	add_child(dialog)
	dialog.popup_centered()


func _save_game() -> void:
	_log("Game saved." if game.save_to(SAVE_PATH) else "Save failed.")


func _load_game() -> void:
	if game.load_from(SAVE_PATH):
		selected_army = ""
		selected_agent = ""
		map_view.selected_region = ""
		region_panel.clear_panel()
		_victory_shown = false
		_log("Game loaded.")
		refresh()
	else:
		_log("No saved game to load.")


func _log(text: String) -> void:
	report_log.append_text(text + "\n")


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _bar_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button
