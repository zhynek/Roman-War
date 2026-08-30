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
var quest_panel: QuestPanel
var build_drawer: BuildDrawer
var family_panel: FamilyPanel
var diplomacy_panel: DiplomacyPanel
var report_log: RichTextLabel
var top_labels := {}
var selected_army := ""
# The drawer's selection is hoisted here, exactly like selected_army: RegionPanel
# destroys and rebuilds all its children on every refresh, so nothing stateful
# can live inside it.
var drawer_open := false
var drawer_tab := "construction"
var drawer_chain := ""
var drawer_tier := 0
var _victory_shown := false


static func create(new_game: Game) -> CampaignScreen:
	var screen := CampaignScreen.new()
	screen.game = new_game
	return screen


func _ready() -> void:
	# Anchors alone leave the offsets untouched, which left this screen at size
	# (0, 0): every child then fell back to its minimum size and the whole game
	# huddled in the top-left corner of the window. Offsets must be set too.
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
	split.add_child(map_view)

	# The drawer is a child of MapView so it stops exactly at the right column's
	# edge however the user drags the splitter. An overlay on this screen with a
	# fixed right offset would be wrong the moment the divider moved, and an
	# HSplitContainer takes only two children.
	build_drawer = BuildDrawer.new()
	build_drawer.closed.connect(close_drawer)
	build_drawer.queued.connect(refresh)
	build_drawer.chain_selected.connect(_on_drawer_chain)
	build_drawer.tier_selected.connect(_on_drawer_tier)
	build_drawer.tab_selected.connect(_on_drawer_tab)
	map_view.add_child(build_drawer)
	map_view.resized.connect(func(): build_drawer.fit_to(map_view.size))

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
	region_panel.explore_requested.connect(_explore_order)
	region_panel.drawer_requested.connect(open_drawer)
	scroll.add_child(region_panel)

	quest_panel = QuestPanel.new()
	side.add_child(quest_panel)

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

	if map_view.selected_region != "":
		region_panel.show_region(game, map_view.selected_region, selected_army)
	_render_drawer()

	# The trail's checklist and its map guidance travel together: every
	# active stage with a target lights that region up.
	var overview := GuidedRules.overview(game.data, game.state)
	quest_panel.render(game, overview)
	var highlights := {}
	for stage in overview["active"]:
		if stage["target_region"] != "":
			highlights[stage["target_region"]] = true
	map_view.highlight_regions = highlights
	# Ownership or fog may have moved: rebake the cached land layer. Selection
	# clicks deliberately skip this — they change nothing the land shows.
	map_view.repaint_land()
	map_view.queue_redraw()

	if game.state["winner"] != null and not _victory_shown:
		_show_victory_banner(String(game.state["winner"]))


func _unhandled_key_input(event: InputEvent) -> void:
	## Keyboard camera: the whole map is reachable without a mouse. Arrows or
	## WASD walk the view, +/- zoom, Home returns to the capital.
	if map_view == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	# Escape closes the drawer before anything else looks at the key. Only this
	# one binding, so the existing arrow/WASD camera contract is untouched.
	if key.keycode == KEY_ESCAPE and drawer_open:
		close_drawer()
		get_viewport().set_input_as_handled()
		return
	var handled := true
	match key.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			map_view.zoom_by(MapView.ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			map_view.zoom_by(1.0 / MapView.ZOOM_STEP)
		KEY_LEFT, KEY_A:
			map_view.pan_by(Vector2(-MapView.KEY_PAN_STEP, 0))
		KEY_RIGHT, KEY_D:
			map_view.pan_by(Vector2(MapView.KEY_PAN_STEP, 0))
		KEY_UP, KEY_W:
			map_view.pan_by(Vector2(0, -MapView.KEY_PAN_STEP))
		KEY_DOWN, KEY_S:
			map_view.pan_by(Vector2(0, MapView.KEY_PAN_STEP))
		KEY_HOME, KEY_0, KEY_KP_0:
			map_view.reset_view()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func open_drawer(tab: String = "construction", chain_id: String = "") -> void:
	drawer_open = true
	drawer_tab = tab
	drawer_chain = chain_id
	drawer_tier = 0
	build_drawer.visible = true
	build_drawer.fit_to(map_view.size)
	_render_drawer()


func close_drawer() -> void:
	drawer_open = false
	build_drawer.visible = false


func _render_drawer() -> void:
	if not drawer_open:
		return
	build_drawer.visible = true
	build_drawer.fit_to(map_view.size)
	build_drawer.render(game, map_view.selected_region, drawer_tab, drawer_chain, drawer_tier)


func _on_drawer_chain(chain_id: String) -> void:
	drawer_chain = chain_id
	drawer_tier = 0
	_render_drawer()


func _on_drawer_tier(index: int) -> void:
	drawer_tier = index
	_render_drawer()


func _on_drawer_tab(tab: String) -> void:
	drawer_tab = tab
	drawer_tier = 0
	_render_drawer()


func _on_region_clicked(region_id: String) -> void:
	# With one of our armies selected, a click on another region is an order.
	# Shift makes it a forced march: double range, weary men.
	if selected_army != "" and game.state["armies"].has(selected_army) \
			and region_id != game.state["armies"][selected_army]["region"]:
		_army_order(region_id, Input.is_key_pressed(KEY_SHIFT))
		return
	map_view.selected_region = region_id
	selected_army = ""
	region_panel.show_region(game, region_id)
	# This path does not go through refresh(), so without this the drawer would
	# keep showing the previous city's ladder after a click on the map.
	if drawer_open:
		drawer_chain = ""
		drawer_tier = 0
		_render_drawer()
	map_view.queue_redraw()


func _on_army_selected(army_id: String) -> void:
	selected_army = "" if selected_army == army_id else army_id
	region_panel.show_region(game, map_view.selected_region, selected_army)


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


func _explore_order(army_id: String) -> void:
	var result := game.explore_site(army_id)
	if result.is_empty():
		_log("There is nothing here the army can search this season.")
		return
	var site: Dictionary = result["site"]
	var outcome: Dictionary = result["outcome"]
	_log("[color=#d8b878][b]%s searched.[/b] %s[/color]" % [site["name"], outcome["text"]])
	var dialog := AcceptDialog.new()
	dialog.title = site["name"]
	dialog.dialog_text = "%s\n\n%s" % [site["text"], outcome["text"]]
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
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

	# World news from the AI factions: wars, peaces and conquests travel
	# everywhere; skirmishes and sieges only reach the player's ears when they
	# happen within sight or to the player's own forces.
	var visible := game.visible_regions()
	for notice in report.get("ai", []):
		var actor: String = _faction_name(notice.get("faction", ""))
		var region: String = str(notice.get("region", ""))
		var place: String = game.data.regions.get(region, {}).get("settlement_name", region)
		match notice["kind"]:
			"war_declared":
				var upon := "your house" if notice["target"] == player else _faction_name(notice["target"])
				_log("[color=#e06050][b]%s declares war upon %s![/b][/color]" % [actor, upon])
			"peace":
				_log("[color=#80b080]%s and %s have made peace.[/color]"
					% [actor, _faction_name(notice["target"])])
			"captured":
				_log("[color=#e0a060]%s has fallen to %s.[/color]" % [place, actor])
			"siege_laid":
				if visible.has(region):
					_log("%s lays siege to %s." % [actor, place])
			"assault_repelled":
				if visible.has(region):
					_log("The walls of %s throw back %s." % [place, actor])
			"battle":
				if visible.has(region) or notice.get("against", "") == player:
					var loser: String = _faction_name(notice["against"]) if notice["winner"] == "attacker" else actor
					var victor: String = actor if notice["winner"] == "attacker" else _faction_name(notice["against"])
					if notice.get("against", "") == player:
						loser = "your army" if notice["winner"] == "attacker" else loser
						victor = "your army" if notice["winner"] != "attacker" else victor
					_log("Battle near %s: %s defeats %s." % [place, victor, loser])

	for notice in report.get("guided", []):
		var stage: Dictionary = game.data.guided_stage_index.get(notice["stage"], {})
		var stage_name: String = stage.get("name", notice["stage"])
		match notice["kind"]:
			"stage_started":
				_log("[color=#d8b878]Trail: %s — %s[/color]" % [stage_name, stage.get("text", "")])
			"stage_complete":
				_log("[color=#d8b878][b]Trail complete: %s.[/b] The reward is claimed.[/color]" % stage_name)
			"stage_expired":
				_log("[color=#a09070]Trail lapsed: %s.[/color]" % stage_name)


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
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button
