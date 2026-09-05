class_name CampaignScreen
extends Control
## The campaign in play: top bar (treasury, date, standings, end turn), the
## map in the middle, the region context panel and turn log on the right.
## All rules go through the Game facade — this screen never touches state
## except to read it for display.
##
## Selection and orders: a LEFT click selects (a banner selects its force, a
## token its region); a RIGHT click, with a force selected, is an order for
## it — march, sail, attack, besiege. Shift makes a march a forced march.

const SAVE_PATH := "user://roman_war_save.json"

var game: Game

var map_view: MapView
var force_panel: ForcePanel
var region_panel: RegionPanel
var side_scroll: ScrollContainer
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
	# Anchors AND offsets: a preset on anchors alone keeps the zero-size rect
	# this control was created with, and the whole screen then lays out at
	# its minimum size in a corner of the window.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	map_view.force_clicked.connect(_on_force_clicked)
	map_view.zone_clicked.connect(_on_zone_clicked)
	map_view.background_clicked.connect(_on_background_clicked)
	map_view.order_target.connect(_on_order_target)
	split.add_child(map_view)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	split.add_child(side)

	side_scroll = ScrollContainer.new()
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(side_scroll)
	var panels := VBoxContainer.new()
	panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(panels)

	# The force card sits above the region scroll; hidden when nothing is selected.
	force_panel = ForcePanel.new()
	force_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_panel.action_taken.connect(_after_order)
	force_panel.attack_requested.connect(attack_army_order)
	force_panel.siege_requested.connect(besiege_order)
	force_panel.march_requested.connect(func(region_id: String, forced: bool): _on_order_target("region", region_id, forced))
	force_panel.sail_requested.connect(func(zone_id: String): _on_order_target("zone", zone_id, false))
	force_panel.sheet_requested.connect(func(char_id: String): family_panel.open_for(game, char_id))
	force_panel.force_replaced.connect(select_force)
	force_panel.disband_requested.connect(disband_order)
	force_panel.refused.connect(_on_refused)
	force_panel.hide()
	panels.add_child(force_panel)

	region_panel = RegionPanel.new()
	region_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_panel.action_taken.connect(refresh)
	region_panel.army_selected.connect(_on_army_selected)
	region_panel.attack_requested.connect(attack_army_order)
	region_panel.siege_requested.connect(besiege_order)
	region_panel.army_raised.connect(func(army_id: String):
		_log("An army musters in %s." % game.data.regions[game.state["armies"][army_id]["region"]]["settlement_name"])
		select_force("army", army_id))
	region_panel.disband_requested.connect(disband_order)
	region_panel.refused.connect(_on_refused)
	panels.add_child(region_panel)

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
	_log("Left-click a banner to select an army; right-click a region to march it there.")
	# Centering must wait for the first layout, or it centers on the map's
	# minimum size rather than the window it actually gets.
	var capital: String = game.state["factions"][game.state["player_faction"]]["capital"]
	map_view.center_on.call_deferred(capital)
	refresh()


func _build_top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 34)

	var faction: Dictionary = game.data.factions[game.state["player_faction"]]
	var swatch := ColorRect.new()
	swatch.color = Color.html(faction.get("color", "#808080"))
	swatch.custom_minimum_size = Vector2(18, 18)
	bar.add_child(swatch)

	for key in ["faction", "treasury", "date", "senate", "victory"]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		bar.add_child(label)
		top_labels[key] = label
	top_labels["faction"].text = " %s   " % faction["name"]

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

	_drop_stale_selection()
	_refresh_highlights()
	var scroll_before := side_scroll.scroll_vertical
	if selected_force() != "":
		force_panel.show_force(game, selected_force())
		force_panel.show()
	else:
		force_panel.clear_panel()
		force_panel.hide()
	if selected_fleet != "":
		region_panel.clear_panel()
	elif map_view.selected_region != "":
		region_panel.show_region(game, map_view.selected_region, selected_army)
	side_scroll.set_deferred("scroll_vertical", scroll_before)
	map_view.queue_redraw()

	if game.state["winner"] != null and not _victory_shown:
		_show_victory_banner(String(game.state["winner"]))


## --- Selection ----------------------------------------------------------------

func selected_force() -> String:
	return selected_army if selected_army != "" else selected_fleet


func select_force(kind: String, force_id: String) -> void:
	## The one entry point for selecting one of our forces: banner click,
	## panel button, keyboard cycling.
	_clear_force_selection()
	if kind == "army" and game.state["armies"].has(force_id):
		selected_army = force_id
		map_view.selected_region = game.state["armies"][force_id]["region"]
	elif kind == "fleet" and game.state["fleets"].has(force_id):
		selected_fleet = force_id
	map_view.selected_force = selected_force()
	refresh()


func _clear_force_selection() -> void:
	selected_army = ""
	selected_fleet = ""
	map_view.selected_force = ""
	map_view.highlight_regions = {}
	map_view.highlight_zones = {}


func _drop_stale_selection() -> void:
	## A selected force that was destroyed, garrisoned or lost stops being selected.
	var player: String = game.state["player_faction"]
	if selected_army != "" and game.state["armies"].get(selected_army, {}).get("owner", "") != player:
		selected_army = ""
	if selected_fleet != "" and game.state["fleets"].get(selected_fleet, {}).get("owner", "") != player:
		selected_fleet = ""
	map_view.selected_force = selected_force()


func _on_region_clicked(region_id: String) -> void:
	# A left click inspects: it never moves anyone.
	_clear_force_selection()
	map_view.selected_region = region_id
	refresh()


func _on_zone_clicked(_zone_id: String) -> void:
	_clear_force_selection()
	refresh()


func _on_background_clicked() -> void:
	_clear_force_selection()
	refresh()


func _on_force_clicked(kind: String, force_id: String) -> void:
	var player: String = game.state["player_faction"]
	var summary := game.force_summary(force_id)
	if summary.is_empty():
		return
	if summary["owner"] == player:
		select_force(kind, force_id)
		return
	# A foreign banner: look, do not command. Armies show through their region.
	if kind == "army":
		_on_region_clicked(summary["region"])
	else:
		_clear_force_selection()
		refresh()
	_log(map_view.banner_tooltip(summary))


func _on_army_selected(army_id: String) -> void:
	# The panel's army buttons toggle.
	if selected_army == army_id:
		_clear_force_selection()
		refresh()
	else:
		select_force("army", army_id)


func _refresh_highlights() -> void:
	## Rings around what the selected force can do from where it stands —
	## computed once per selection or order, never per draw.
	map_view.highlight_regions = {}
	map_view.highlight_zones = {}
	if selected_army != "":
		map_view.highlight_regions = _army_options(selected_army)
	elif selected_fleet != "":
		for zone_id in game.reachable_zones(selected_fleet):
			map_view.highlight_zones[zone_id] = "sail"


func _army_options(army_id: String) -> Dictionary:
	## {region_id: "march"|"forced"|"attack"|"siege"}: everywhere the army can
	## reach this season (yellow), by forced march only (orange), and the
	## visible enemies it can strike from where it stands (red). Fog is
	## respected: nothing hidden ever changes a ring.
	var options := {}
	var visible := game.visible_regions()
	var plan := game.reachable_regions(army_id)
	for region_id in plan["reach"]:
		options[region_id] = "forced" if plan["reach"][region_id]["forced"] else "march"
	for region_id in game.targets_for(army_id):
		if visible.has(region_id):
			options[region_id] = game.targets_for(army_id)[region_id]
	return options


## --- Orders -----------------------------------------------------------------------

func _on_order_target(kind: String, target_id: String, forced: bool) -> void:
	## A right click on the map with one of our forces selected.
	if selected_army != "" and game.state["armies"].has(selected_army):
		match kind:
			"region":
				if target_id != game.state["armies"][selected_army]["region"]:
					_army_order(target_id, forced)
			"army":
				var other: Dictionary = game.state["armies"].get(target_id, {})
				if not other.is_empty() and other["owner"] != game.state["player_faction"]:
					attack_army_order(target_id)
	elif selected_fleet != "" and game.state["fleets"].has(selected_fleet):
		if kind == "zone":
			_fleet_order(target_id)


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

	# Otherwise: march along the cheapest road (or sail).
	var target_name: String = game.data.regions[target_region]["name"]
	var result := game.march_army(selected_army, target_region, forced_march)
	if result["arrived"]:
		var weary: bool = game.state["armies"][selected_army].get("forced_march", false)
		_log("The army marches to %s%s" % [target_name, " by forced march — the men will be weary." if weary else "."])
	elif result["ok"]:
		var halt_name: String = game.data.regions[result["stopped_at"]]["name"]
		_log("The column halts at %s — %s." % [halt_name, _halt_reason(result["reason"])])
	elif result["reason"] == "needs_forced_march":
		_log("%s is beyond a day's march — hold Shift to force the pace." % target_name)
	elif result["reason"] in ["hostile_army", "hostile_settlement"]:
		_log("The road to %s is barred — %s." % [target_name, _halt_reason(result["reason"])])
	elif game.sea_move_army(selected_army, target_region):
		_log("The army takes ship for %s." % target_name)
	else:
		_log("The army cannot reach %s this season." % target_name)
	_after_order()


func _halt_reason(reason: String) -> String:
	match reason:
		"hostile_army":
			return "enemy in sight"
		"hostile_settlement":
			return "hostile walls ahead"
		"no_movement":
			return "the men can go no further"
	return "the way is closed"


func _fleet_order(zone_id: String) -> void:
	var zone_name: String = game.data.sea_zones.get(zone_id, {}).get("name", zone_id)
	if game.sail_fleet(selected_fleet, zone_id)["arrived"]:
		_log("The fleet sails for the %s." % zone_name)
	else:
		_log("The fleet cannot reach the %s this season." % zone_name)
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
	if defender.is_empty() or selected_army == "":
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
	if settlement.is_empty() or selected_army == "":
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


func _on_refused(error: String) -> void:
	_log("[color=#e0a060]%s[/color]" % ForcePanel._explain(error))


func disband_order(force_id: String, indices: Array) -> void:
	## Sending men home is irreversible, so it is confirmed first.
	_confirm("Disband %d unit%s? The men go home; no money comes back." % [indices.size(), "" if indices.size() == 1 else "s"],
		func(): _resolve_disband(force_id, indices))


func _resolve_disband(force_id: String, indices: Array) -> void:
	# Highest index first, so the earlier indices stay valid.
	var order: Array = indices.duplicate()
	order.sort()
	order.reverse()
	var returned := 0
	var disbanded := 0
	for index in order:
		var result := game.disband_unit(force_id, int(index))
		if result["ok"]:
			disbanded += 1
			returned += int(result["returned"])
		else:
			_on_refused(result["error"])
	if disbanded > 0:
		_log("%d unit%s disbanded; %d men return to the fields." % [disbanded, "" if disbanded == 1 else "s", returned])
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
	## The selection follows a surviving force; a force that is gone (beaten,
	## garrisoned, merged away) leaves its region selected instead.
	_drop_stale_selection()
	if selected_army != "":
		map_view.selected_region = game.state["armies"][selected_army]["region"]
	refresh()


## --- Keyboard ---------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			deselect()
		KEY_TAB, KEY_N:
			cycle_selection()


func deselect() -> void:
	## Esc: first the force, then the region.
	if selected_force() != "":
		_clear_force_selection()
	else:
		map_view.selected_region = ""
		region_panel.clear_panel()
	refresh()


func cycle_selection() -> void:
	## Tab / N: the next of our forces that still has orders to give.
	var candidates := game.forces_awaiting_orders()
	if candidates.is_empty():
		_log("Every force has its orders.")
		return
	var current := selected_force()
	var next_index := 0
	for i in range(candidates.size()):
		if candidates[i] == current:
			next_index = (i + 1) % candidates.size()
			break
	var pick: String = candidates[next_index]
	var kind := ForceRules.kind_of(pick)
	select_force(kind, pick)
	if kind == "army":
		map_view.center_on(game.state["armies"][pick]["region"])
	else:
		map_view.center_on_zone(game.state["fleets"][pick]["sea_zone"])


## --- Turn, save, log ------------------------------------------------------------------

func _end_turn() -> void:
	var report := game.end_turn()
	_log_report(report)
	# The selection survives the turn if the force does; its rings are
	# recomputed because movement points are back.
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
		_clear_force_selection()
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
