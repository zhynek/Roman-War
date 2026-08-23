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
var negotiation_panel: NegotiationPanel
var senate_panel: SenatePanel
var report_log: RichTextLabel
var top_labels := {}
var selected_army := ""
var selected_agent := ""
var _victory_shown := false


static func create(new_game: Game) -> CampaignScreen:
	var screen := CampaignScreen.new()
	screen.game = new_game
	return screen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	var ground := ColorRect.new()
	ground.color = UiTheme.INK
	add_child(ground)
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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
	region_panel.negotiate_requested.connect(_open_negotiation)
	region_panel.log_message.connect(_log)
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
	diplomacy_panel.negotiate_requested.connect(_open_negotiation)
	add_child(diplomacy_panel)

	negotiation_panel = NegotiationPanel.new()
	negotiation_panel.deal_made.connect(refresh)
	add_child(negotiation_panel)

	senate_panel = SenatePanel.new()
	senate_panel.senate_changed.connect(refresh)
	add_child(senate_panel)

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
	bar.add_child(_bar_button("Help", _show_help))
	bar.add_child(_bar_button("Family", func(): family_panel.open_for(game)))
	bar.add_child(_bar_button("Diplomacy", func(): diplomacy_panel.open_for(game)))
	if game.data.factions[game.state["player_faction"]].get("is_roman_house", false):
		bar.add_child(_bar_button("Senate", func(): senate_panel.open_for(game)))
	bar.add_child(_bar_button("Save", _save_game))
	bar.add_child(_bar_button("Load", _load_game))
	var end_turn := _bar_button("END TURN", _end_turn)
	end_turn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	bar.add_child(end_turn)
	return bar


func refresh() -> void:
	var faction: Dictionary = game.state["factions"][game.state["player_faction"]]
	var projection := EconomyRules.faction_turn_breakdown(game.data, game.state, game.state["player_faction"])
	var net := float(projection["net"])
	top_labels["treasury"].text = "Treasury: %d (%s%d)   " % [int(faction["treasury"]),
		"+" if net >= 0 else "", int(round(net))]
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
		region_panel.show_region(game, map_view.selected_region, selected_army, selected_agent)
	map_view.queue_redraw()

	if game.state["winner"] != null and not _victory_shown:
		_show_victory_banner(String(game.state["winner"]))


func _on_region_clicked(region_id: String) -> void:
	# With one of our armies selected, a click on another region is an order.
	# Shift makes it a forced march: double range, weary men.
	if selected_army != "" and game.state["armies"].has(selected_army) \
			and region_id != game.state["armies"][selected_army]["region"]:
		_army_order(region_id, Input.is_key_pressed(KEY_SHIFT))
		return
	# With an agent selected, a click sends him traveling.
	if selected_agent != "" and game.state.get("agents", {}).has(selected_agent) \
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
	var reached := game.move_agent_towards(selected_agent, target_region)
	if reached == target_region:
		_log("Our agent reaches %s." % game.data.regions[target_region]["name"])
	elif reached != "":
		_log("Our agent travels as far as %s." % game.data.regions[reached]["name"])
	map_view.selected_region = reached if reached != "" else map_view.selected_region
	region_panel.show_region(game, map_view.selected_region, "", selected_agent)
	refresh()


func _open_negotiation(faction_id: String) -> void:
	negotiation_panel.open_for(game, faction_id)


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
		var senate_kind := String(notice.get("kind", ""))
		if senate_kind == "office_gained":
			if notice.get("faction", "") == player:
				var who_name: String = game.state["characters"].get(notice.get("character", ""), {}).get("name", "")
				_log("[color=#9090d0]Senate: %s is elected %s.[/color]" % [who_name,
					game.data.offices.get(notice.get("office", ""), {}).get("name", notice.get("office", ""))])
			continue
		if senate_kind in ["civil_war", "joins_rebellion", "outlawed"]:
			_log("[color=#e06050][b]%s: %s![/b][/color]" % [senate_kind.replace("_", " ").capitalize(),
				_faction_name(str(notice.get("faction", "")))])
			continue
		if notice.get("faction", "") == player:
			var mission_id: String = str(notice.get("mission", ""))
			var mission_name: String = game.data.missions.get(mission_id, {}).get("name", mission_id)
			_log("[color=#9090d0]Senate: %s%s[/color]" % [senate_kind.replace("_", " "),
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

	var visible_set := game.visible_regions()
	for notice in report.get("world", []):
		match String(notice.get("kind", "")):
			"war_declared":
				_log("[color=#e08060]%s declares war on %s![/color]"
					% [_faction_name(notice["faction"]), _faction_name(notice["other"])])
			"peace":
				_log("[color=#80b0d0]%s and %s have made peace.[/color]"
					% [_faction_name(notice["faction"]), _faction_name(notice["other"])])
			"battle":
				if visible_set.has(notice.get("region", "")):
					_log("Battle at %s — the %s prevail." % [
						game.data.regions[notice["region"]]["name"],
						"attackers" if notice.get("winner", "") == "attacker" else "defenders"])
			"captured":
				if visible_set.has(notice.get("region", "")) or notice.get("from", "") == player:
					_log("[color=#e0a060]%s has taken %s from %s![/color]" % [
						_faction_name(notice["faction"]),
						game.data.regions[notice["region"]]["settlement_name"],
						_faction_name(notice["from"])])
			"agent_caught":
				if notice.get("faction", "") == player:
					_log("[color=#e08060]Our %s was caught and killed in %s.[/color]" % [
						String(notice.get("agent_kind", "agent")),
						game.data.regions.get(notice.get("region", ""), {}).get("settlement_name", "a foreign town")])
				elif notice.get("by", "") == player:
					_log("We caught a foreign %s skulking in %s." % [
						String(notice.get("agent_kind", "agent")),
						game.data.regions.get(notice.get("region", ""), {}).get("settlement_name", "our town")])
			"assassination":
				var victim: Dictionary = game.state["characters"].get(notice.get("character", ""), {})
				if notice.get("faction", "") == player:
					_log("[color=#e06050][b]%s has been murdered![/b][/color]" % victim.get("name", "One of ours"))
	for faction_id in report.get("destroyed_factions", []):
		_log("[color=#e06050][b]%s is no more.[/b][/color]" % _faction_name(faction_id))


func _is_player_character(char_id: String) -> bool:
	return game.state["characters"].get(char_id, {}).get("faction", "") == game.state["player_faction"]


func _faction_name(faction_id: String) -> String:
	return game.data.factions.get(faction_id, {}).get("name", faction_id)


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


func _show_help() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "How the campaign is played"
	var help := RichTextLabel.new()
	help.bbcode_enabled = true
	help.custom_minimum_size = Vector2(560, 480)
	help.text = """[b][color=#d4a938]The map[/color][/b]
Left-click a settlement to inspect it. Right/middle-drag pans; the wheel zooms.

[b][color=#d4a938]Settlements[/color][/b]
Set taxes, queue buildings and troops, and watch the public order, growth and income breakdowns — every number is a sum of named causes. Riots come below 75 order; three ruinous turns below 50 and the town rises in revolt.

[b][color=#d4a938]Armies[/color][/b]
Select one of your armies, then click a region to march (Shift = forced march — double range, weary men). March onto an enemy or their city to attack or lay siege; assault once equipment is ready, or starve them out. \"Field the garrison\" turns a garrison into a marching army; it moves next season.

[b][color=#d4a938]Agents[/color][/b]
Train an [b]envoy[/b] and walk him onto a foreign power's soil to open negotiation — peace, trade, alliances, gifts, tribute, even buying a border town. An [b]informer[/b] reveals what fog hides and opens gates when you assault the town he is inside — but governors hunt him. A [b]hired blade[/b] kills generals, governors, and kings, if their bodyguards fail.

[b][color=#d4a938]The Senate[/color][/b]
Roman houses answer to the Senate: missions bring standing and rewards; offices go to houses in favor each summer. Expand too fast with too little favor and the Republic will break — be ready to win the civil war that follows.

[b][color=#d4a938]The family[/color][/b]
Your generals and governors are your family. Traits and retinues grow from what they do; name an heir; marry daughters well; the man on the spot governs.

[b][color=#d4a938]Winning[/color][/b]
Hold the regions your victory condition demands (the counter sits in the top bar) before AD 14 closes the age."""
	dialog.add_child(help)
	add_child(dialog)
	dialog.popup_centered()
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())


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
