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
var selected_army := ""
var selected_fleet := ""
var _victory_shown := false


static func create(new_game: Game) -> CampaignScreen:
	var screen := CampaignScreen.new()
	screen.game = new_game
	return screen


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.build_theme()

	var background := ColorRect.new()
	background.color = UiStyle.BG_DARK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_top_bar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 920  # the map takes the room; the side keeps its 360
	root.add_child(split)

	map_view = MapView.new()
	map_view.game = game
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.custom_minimum_size = Vector2(600, 400)
	map_view.region_clicked.connect(_on_region_clicked)
	map_view.region_hovered.connect(_on_region_hovered)
	map_view.sea_zone_clicked.connect(_on_sea_zone_clicked)
	map_view.tooltip_provider = _tooltip_for
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


func _build_top_bar() -> PanelContainer:
	var chrome := PanelContainer.new()
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 30)
	bar.add_theme_constant_override("separation", 8)
	chrome.add_child(bar)

	var faction: Dictionary = game.data.factions[game.state["player_faction"]]
	var swatch := ColorRect.new()
	swatch.color = Color.html(faction.get("color", "#808080"))
	swatch.custom_minimum_size = Vector2(6, 0)
	bar.add_child(swatch)

	for key in ["faction", "treasury", "date", "senate", "victory"]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		if key == "faction":
			label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
		else:
			label.add_theme_color_override("font_color", UiStyle.TEXT)
		bar.add_child(label)
		top_labels[key] = label
	top_labels["faction"].text = " %s   " % faction["name"]

	bar.add_child(_spacer())
	bar.add_child(_bar_button("Family", func(): family_panel.open_for(game)))
	bar.add_child(_bar_button("Diplomacy", func(): diplomacy_panel.open_for(game)))
	bar.add_child(_bar_button("Save", _save_game))
	bar.add_child(_bar_button("Load", _load_game))
	var end_turn := _bar_button("END TURN", _end_turn)
	end_turn.theme_type_variation = &"EndTurnButton"
	bar.add_child(end_turn)
	return chrome


func refresh() -> void:
	var faction: Dictionary = game.state["factions"][game.state["player_faction"]]
	top_labels["treasury"].text = "Treasury: %d   " % int(faction["treasury"])
	var year := int(game.state["year"])
	var year_text := "%d BC" % -year if year < 0 else "AD %d" % year
	top_labels["date"].text = "%s, %s   " % [year_text, String(game.state["season"]).capitalize()]
	if game.data.factions[game.state["player_faction"]].get("is_roman_house", false):
		top_labels["senate"].text = "Senate %.0f · People %.0f   " \
			% [float(faction["senate_standing"]), float(faction["popular_standing"])]
	var progress := game.victory_progress()
	if not progress.is_empty():
		top_labels["victory"].text = "Regions %d/%d" \
			% [int(progress["regions_held"]), int(progress["regions_needed"])]

	if map_view.selected_region != "":
		region_panel.show_region(game, map_view.selected_region, selected_army)
	map_view.refresh_state()
	_refresh_range_overlay()

	if game.state["winner"] != null and not _victory_shown:
		_show_victory_banner(String(game.state["winner"]))


func _on_region_clicked(region_id: String) -> void:
	# With one of our armies selected, a click on another region is an order.
	# Shift makes it a forced march: double range, weary men.
	if selected_army != "" and game.state["armies"].has(selected_army) \
			and region_id != game.state["armies"][selected_army]["region"]:
		_army_order(region_id, Input.is_key_pressed(KEY_SHIFT))
		return
	map_view.selected_region = region_id
	selected_army = ""
	_deselect_fleet()
	region_panel.show_region(game, region_id)
	_refresh_range_overlay()


func _on_army_selected(army_id: String) -> void:
	selected_army = "" if selected_army == army_id else army_id
	region_panel.show_region(game, map_view.selected_region, selected_army)
	_refresh_range_overlay()


func _refresh_range_overlay() -> void:
	## The gold wash of regions this turn's points can reach.
	if selected_army != "" and game.state["armies"].has(selected_army):
		map_view.highlight_regions = game.army_reachable(selected_army)
	else:
		map_view.highlight_regions = {}
		map_view.path_preview = {}


func _on_region_hovered(region_id: String) -> void:
	## With an army selected, hovering sketches the march: route, per-leg
	## cost, turns to arrive.
	if region_id == "" or selected_army == "" or not game.state["armies"].has(selected_army) \
			or region_id == game.state["armies"][selected_army]["region"]:
		map_view.path_preview = {}
		return
	var preview := game.army_path_preview(
		selected_army, region_id, Input.is_key_pressed(KEY_SHIFT))
	if preview.is_empty() or (preview["path"] as Array).is_empty():
		map_view.path_preview = {}
		return
	map_view.path_preview = {
		"from": game.state["armies"][selected_army]["region"],
		"legs": preview["legs"],
		"turns": preview["turns"],
		"blocked": preview["blocked_destination"],
		"target": region_id,
	}


func _on_sea_zone_clicked(zone_id: String) -> void:
	## Fleets live on the map now: click a sea with one of our fleets to take
	## the helm, click a highlighted neighboring sea to sail.
	if selected_fleet != "" and game.state["fleets"].has(selected_fleet):
		var fleet: Dictionary = game.state["fleets"][selected_fleet]
		if zone_id != fleet["sea_zone"]:
			if game.move_fleet(selected_fleet, zone_id):
				_log("The fleet sails for %s." %
					game.data.sea_zones.get(zone_id, {}).get("name", zone_id))
				_refresh_fleet_overlay()
				refresh()
			else:
				_log("The fleet cannot make %s this season." %
					game.data.sea_zones.get(zone_id, {}).get("name", zone_id))
			return
	var fleet_here := ""
	var fleet_ids: Array = game.state["fleets"].keys()
	fleet_ids.sort()
	for fleet_id in fleet_ids:
		var fleet: Dictionary = game.state["fleets"][fleet_id]
		if fleet["owner"] == game.state["player_faction"] and fleet["sea_zone"] == zone_id:
			fleet_here = fleet_id
			break
	if fleet_here != "" and fleet_here != selected_fleet:
		selected_fleet = fleet_here
	else:
		selected_fleet = ""
	_refresh_fleet_overlay()


func _refresh_fleet_overlay() -> void:
	if selected_fleet != "" and game.state["fleets"].has(selected_fleet):
		var fleet: Dictionary = game.state["fleets"][selected_fleet]
		map_view.selected_sea_zone = fleet["sea_zone"]
		var lanes := {}
		if float(fleet["movement_left"]) >= 1.0:
			for zone_id in game.data.sea_zones.get(fleet["sea_zone"], {}).get("adjacent", []):
				lanes[zone_id] = true
		map_view.highlight_zones = lanes
	else:
		_deselect_fleet()


func _deselect_fleet() -> void:
	selected_fleet = ""
	map_view.selected_sea_zone = ""
	map_view.highlight_zones = {}


func _tooltip_for(region_id: String) -> String:
	var region: Dictionary = game.data.regions.get(region_id, {})
	if region.is_empty():
		return ""
	if not map_view.visible_cache.has(region_id):
		return "[b]%s[/b]\n[i]Beyond our maps.[/i]" % region.get("name", region_id)
	var lines: Array[String] = []
	lines.append("[b]%s[/b] · %s" % [region.get("settlement_name", region_id), region.get("name", "")])
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if not settlement.is_empty():
		var owner: String = settlement["owner"]
		var faction: Dictionary = game.data.factions.get(owner, {})
		lines.append("[color=%s]%s[/color] — %s, %s souls" % [
			faction.get("color", "#808080"), faction.get("name", owner),
			SettlementRules.settlement_level(game.data, settlement).capitalize().replace("_", " "),
			str(int(settlement["population"]))])
	var terrain: String = region.get("terrain", "plains")
	lines.append("%s — march cost %s · fertility %.1f" % [
		terrain.capitalize(),
		String.num(MovementRules.step_cost(game.data, game.state, region_id), 2),
		float(region.get("fertility", 0.0))])
	var goods: Array = region.get("resources", [])
	if not goods.is_empty():
		lines.append("Goods: %s" % ", ".join(goods))
	if region.has("description"):
		lines.append("[i]%s[/i]" % region["description"])
	if selected_army != "" and game.state["armies"].has(selected_army) \
			and region_id != game.state["armies"][selected_army]["region"]:
		var preview := game.army_path_preview(selected_army, region_id)
		if not preview.is_empty() and not (preview["path"] as Array).is_empty():
			var turns := int(preview["turns"])
			lines.append("March: %.1f points · %s" % [float(preview["cost"]),
				"arrives this turn" if turns <= 1 else "%d turns" % turns])
	return "\n".join(lines)


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

	# Otherwise: march (or sail). A destination beyond one step becomes a
	# queued march that resumes each turn — still nothing but move steps, so
	# it can never start a war.
	if game.move_army(selected_army, target_region, forced_march):
		var suffix := " by forced march — the men will be weary." if forced_march else "."
		_log("The army marches to %s%s" % [game.data.regions[target_region]["name"], suffix])
	elif game.sea_move_army(selected_army, target_region):
		_log("The army takes ship for %s." % game.data.regions[target_region]["name"])
	else:
		var march := game.march_army(selected_army, target_region, forced_march)
		if march.is_empty():
			_log("The army cannot reach %s this season." % game.data.regions[target_region]["name"])
		elif march.get("arrived", false):
			_log("The army marches through to %s." % game.data.regions[target_region]["name"])
		else:
			var turns := int(march.get("turns", 2))
			var warning := " The way in is barred; it will halt nearby." \
				if march.get("blocked_destination", false) else ""
			_log("The army sets out for %s — %d turns' march.%s"
				% [game.data.regions[target_region]["name"], turns, warning])
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
	map_view.path_preview = {}
	region_panel.show_region(game, map_view.selected_region, selected_army)
	refresh()


func _end_turn() -> void:
	var report := game.end_turn()
	_log_report(report)
	selected_army = ""
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
	for siege_event in report["sieges"]:
		_log("The siege of %s is decided." % game.data.regions[siege_event["region"]]["settlement_name"])
	for march in report.get("marches", []):
		if march["owner"] != player:
			continue
		var march_target: String = game.data.regions.get(march["destination"], {}).get(
			"settlement_name", march["destination"])
		if march["arrived"]:
			_log("The army arrives at %s." % march_target)
		elif march["halted"]:
			_log("[color=#e0a060]The march on %s is halted — the way is barred.[/color]" % march_target)
		else:
			_log("The army marches on toward %s." % march_target)


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
