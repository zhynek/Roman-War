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
var reforms_panel: ReformsPanel
var report_log: RichTextLabel
var top_labels := {}
var selected_army := ""
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
	region_panel.assault_requested.connect(assault_order)
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

	reforms_panel = ReformsPanel.new()
	reforms_panel.reform_adopted.connect(refresh)
	add_child(reforms_panel)

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
	bar.add_child(_bar_button("Reforms", func(): reforms_panel.open_for(game)))
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
	map_view.selected_region = region_id
	selected_army = ""
	region_panel.show_region(game, region_id)
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
	## Every attack is confirmed with its paper odds first; attacking a faction
	## we are not yet at war with additionally declares war, and says so.
	var defender: Dictionary = game.state["armies"].get(defender_id, {})
	if defender.is_empty():
		return
	var player: String = game.state["player_faction"]
	var faction_name: String = game.data.factions.get(defender["owner"], {}).get("name", defender["owner"])
	var text := "Attack the %s?" % faction_name
	if not DiplomacyRules.at_war(game.state, player, defender["owner"]):
		text = "This will declare war on %s. " % faction_name + text
	var estimate := game.battle_estimate(selected_army, defender_id)
	if estimate.is_empty():
		_log("The army cannot come to grips with the enemy from here.")
		return
	text += "\n" + RegionPanel.odds_text(estimate)
	_confirm(text, func(): _resolve_attack(defender_id))


func _resolve_attack(defender_id: String) -> void:
	_log_battle(game.attack_army(selected_army, defender_id), "Battle")
	_after_order()


func assault_order(region_id: String, occupation: String) -> void:
	## Storming a city is confirmed like any attack, with the odds and the fate
	## chosen for the townsfolk spelled out — extermination is not a mis-click.
	var settlement_name: String = game.data.regions.get(region_id, {}).get("settlement_name", region_id)
	var text := "Storm the walls of %s and %s the city?" % [settlement_name, occupation]
	var estimate := game.assault_estimate(selected_army, region_id)
	if not estimate.is_empty():
		text += "\n" + RegionPanel.odds_text(estimate)
	_confirm(text, func(): _resolve_assault(region_id, occupation))


func _resolve_assault(region_id: String, occupation: String) -> void:
	var settlement_name: String = game.data.regions.get(region_id, {}).get("settlement_name", region_id)
	_log_battle(game.assault_settlement(selected_army, region_id, occupation), "Assault on %s" % settlement_name)
	_after_order()


func _log_battle(result: Dictionary, title: String) -> void:
	## The battle report: who prevailed, what it cost, what fell, and — from
	## the resolver's breakdown — the factors that decided it. Every key is
	## optional: a future resolver may report less.
	if result.is_empty():
		_log("%s: the enemy could not be brought to battle." % title)
		return
	var attacker_won: bool = result.get("winner", "") == "attacker"
	var line := "[b]%s![/b] The %s prevail — attackers lose %d%%, defenders %d%%." % [title,
		"attackers" if attacker_won else "defenders",
		int(round(float(result.get("attacker_casualty_pct", 0.0)))),
		int(round(float(result.get("defender_casualty_pct", 0.0))))]
	if result.get("defender_destroyed", false):
		line += " The defenders are destroyed."
	elif result.get("attacker_destroyed", false):
		line += " The attackers are destroyed."
	_log(line)
	var breakdown = result.get("breakdown")
	if breakdown is Dictionary and not breakdown.is_empty():
		_log("    " + battle_summary(breakdown))
	var capture = result.get("capture")
	if capture is Dictionary and not capture.is_empty():
		_log("[color=#e0a060]The city is taken and %s — %d denarii of loot%s.[/color]" % [
			{"occupy": "occupied", "enslave": "its people enslaved", "exterminate": "its people put to the sword"}.get(
				capture.get("occupation", "occupy"), "occupied"),
			int(capture.get("loot", 0)),
			", %d slaves sent to your cities" % int(capture["slaves"]) if int(capture.get("slaves", 0)) > 0 else ""])
	_log_character_notices(result.get("character_notices", []))


const FACTOR_NAMES := {
	"upgrades": "kit", "matchups": "matchups", "class_terrain": "ground by arm", "terrain": "defender's ground",
	"walls": "walls", "assault": "storming walls", "wall_defense": "holding walls", "general": "general",
	"doctrines": "doctrines", "combined_arms": "combined arms", "attacking": "the charge", "fatigue": "fatigue",
	"sally": "sally", "experience": "experience",
}


static func battle_summary(breakdown: Dictionary) -> String:
	## "Attackers ×1.21 matchups, ×0.85 ground by arm · Defenders ×2.00 walls ·
	##  paper odds 1.42:1, fortune att 1.05 / def 0.93"
	var parts: Array = []
	for side in ["attacker", "defender"]:
		var side_estimate = breakdown.get(side, {})
		var factors: Array = side_estimate.get("factors", []) if side_estimate is Dictionary else []
		var top := _decisive_factors(factors, 3)
		if not top.is_empty():
			parts.append("%s %s" % ["Attackers" if side == "attacker" else "Defenders", ", ".join(top)])
	var fortune = breakdown.get("fortune", {})
	if not (fortune is Dictionary):
		fortune = {}
	parts.append("paper odds %.2f:1, fortune att %.2f / def %.2f" % [float(breakdown.get("ratio", 1.0)),
		float(fortune.get("attacker", 1.0)), float(fortune.get("defender", 1.0))])
	return " · ".join(parts)


static func _decisive_factors(factors: Array, count: int) -> Array:
	var candidates: Array = []
	for factor in factors:
		if factor["label"] == "base":
			continue
		candidates.append(factor)
	candidates.sort_custom(func(a, b):
		var swing_a: float = absf(float(a["value"]) - 1.0)
		var swing_b: float = absf(float(b["value"]) - 1.0)
		return swing_a > swing_b if swing_a != swing_b else String(a["label"]) < String(b["label"]))
	var lines: Array = []
	for factor in candidates.slice(0, count):
		var label := String(factor["label"])
		lines.append("×%.2f %s" % [float(factor["value"]), FACTOR_NAMES.get(label, label.replace("_", " "))])
	return lines


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
	_log_character_notices(report["characters"])
	for faction_id in report.get("reforms", {}):
		if faction_id == player:
			for doctrine_id in report["reforms"][faction_id]:
				_log("[color=#c0b060]Reform complete: %s[/color]"
					% game.data.doctrines.get(doctrine_id, {}).get("name", doctrine_id))
	# Starve-outs are full battles; report the ones we can see like any other.
	var visible := game.visible_regions()
	for siege_event in report["sieges"]:
		if not visible.has(siege_event["region"]):
			continue
		var settlement_name: String = game.data.regions[siege_event["region"]]["settlement_name"]
		var siege_result: Dictionary = siege_event.get("result", {})
		var outcome := "the starving garrison sallies and the city falls." \
			if siege_result.get("captured", false) else "the starving garrison sallies and breaks the siege."
		_log("The siege of %s is decided: %s" % [settlement_name, outcome])
		if not siege_result.is_empty():
			_log_battle(siege_result, "Sally at %s" % settlement_name)


func _log_character_notices(notices: Array) -> void:
	## Trait and retinue news for our own people (and anyone in our service).
	var player: String = game.state["player_faction"]
	for notice in notices:
		if notice.get("faction", "") != player and not _is_player_character(notice.get("character", "")):
			continue
		var who: String = game.state["characters"].get(notice.get("character", ""), {}).get("name", "")
		var detail := ""
		if notice.has("name"):
			detail = " — " + String(notice["name"])
		elif notice.has("ancillary"):
			detail = " — " + String(game.data.ancillaries.get(notice["ancillary"], {}).get("name", notice["ancillary"]))
		_log("[color=#80b080]%s: %s%s[/color]" % [String(notice.get("kind", "news")).replace("_", " "), who, detail])

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
