class_name CampaignScreen
extends Control
## The campaign in play: top bar (treasury, date, standings, end turn), the
## map in the middle, the region context panel and turn log on the right.
## All rules go through the Game facade — this screen never touches state
## except to read it for display.
##
## Ending a turn is a DAY: the engine resolves the whole turn in one call, then
## TurnSequence replays the journal over the map from dawn to dusk and the
## Daily Dispatch closes it. Playback is presentation only — set
## playback_enabled = false and the same turn resolves synchronously, which is
## what the headless suite does when it drives twenty-five turns in a loop.

const SAVE_PATH := "user://roman_war_save.json"

var game: Game

var map_view: MapView
var region_panel: RegionPanel
var family_panel: FamilyPanel
var diplomacy_panel: DiplomacyPanel
var report_log: RichTextLabel
var turn_sequence: TurnSequence
var dispatch_panel: DispatchPanel
var top_labels := {}
var selected_army := ""
var playback_enabled := true
var _victory_shown := false
var _day_beats: Array = []
var _treasury_shown := 0.0
var _treasury_delta := 0
var _treasury_ticking := false


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

	turn_sequence = TurnSequence.new()
	turn_sequence.finished.connect(_on_day_played)
	add_child(turn_sequence)

	dispatch_panel = DispatchPanel.new()
	dispatch_panel.dismissed.connect(_on_dispatch_dismissed)
	add_child(dispatch_panel)

	_treasury_shown = float(game.state["factions"][game.state["player_faction"]]["treasury"])
	set_process(true)

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

	for key in ["faction", "treasury", "date", "senate", "victory", "mission"]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		bar.add_child(label)
		top_labels[key] = label
	top_labels["faction"].text = " %s   " % faction["name"]

	bar.add_child(_spacer())
	bar.add_child(_bar_button("Dispatch", _show_dispatch))
	bar.add_child(_bar_button("Family", func(): family_panel.open_for(game)))
	bar.add_child(_bar_button("Diplomacy", func(): diplomacy_panel.open_for(game)))
	bar.add_child(_bar_button("Save", _save_game))
	bar.add_child(_bar_button("Load", _load_game))
	var end_turn := _bar_button("END TURN", _end_turn)
	end_turn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	bar.add_child(end_turn)
	return bar


func _process(delta: float) -> void:
	## The coffers count up (or down) to the day's new figure, so the player
	## watches the money move instead of reading a number that has changed.
	if not _treasury_ticking:
		return
	var target := float(game.state["factions"][game.state["player_faction"]]["treasury"])
	if is_equal_approx(_treasury_shown, target):
		_treasury_ticking = false
		return
	var seconds := float(game.data.balance["dispatch"]["treasury_ticker_seconds"])
	_treasury_shown = lerpf(_treasury_shown, target, clampf(delta / maxf(seconds, 0.01), 0.0, 1.0))
	if absf(target - _treasury_shown) < 1.0:
		_treasury_shown = target
		_treasury_ticking = false
	_draw_treasury()


func _draw_treasury() -> void:
	var text := "Treasury: %d" % int(round(_treasury_shown))
	if _treasury_delta != 0:
		var color := "#8ccb80" if _treasury_delta > 0 else "#e06050"
		text += "  (%s%d)" % ["+" if _treasury_delta > 0 else "", _treasury_delta]
		top_labels["treasury"].add_theme_color_override("font_color", Color.html(color))
	else:
		top_labels["treasury"].remove_theme_color_override("font_color")
	top_labels["treasury"].text = text + "   "


func refresh() -> void:
	var faction: Dictionary = game.state["factions"][game.state["player_faction"]]
	# Only the day's own swing is animated. Spending money on a building should
	# show immediately, and a loaded game should never tick up from a stale
	# figure belonging to a campaign the player has left behind.
	if not _treasury_ticking:
		_treasury_shown = float(faction["treasury"])
	_draw_treasury()
	var year := int(game.state["year"])
	var year_text := "%d BC" % -year if year < 0 else "AD %d" % year
	top_labels["date"].text = "%s, %s   " % [year_text, String(game.state["season"]).capitalize()]
	if game.data.factions[game.state["player_faction"]].get("is_roman_house", false):
		top_labels["senate"].text = "Senate %.0f · People %.0f   " \
			% [float(faction["senate_standing"]), float(faction["popular_standing"])]
	var progress := game.victory_progress()
	if not progress.is_empty():
		top_labels["victory"].text = "Regions %d/%d   " \
			% [int(progress["regions_held"]), int(progress["regions_needed"])]
	var mission = faction["mission"]
	if mission == null:
		top_labels["mission"].text = ""
	else:
		top_labels["mission"].text = "Charge: %s (%d)   " % [
			game.data.missions.get(String(mission["template"]), {}).get("name", mission["template"]),
			int(mission["turns_left"])]

	if map_view.selected_region != "":
		region_panel.show_region(game, map_view.selected_region, selected_army)
	map_view.queue_redraw()

	# The banner waits for the day to finish: an age that ends mid-sequence
	# should still get its dawn-to-dusk telling before the campaign is called.
	if game.state["winner"] != null and not _victory_shown \
			and not turn_sequence.is_playing() and not dispatch_panel.visible:
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
	## The engine resolves the entire turn here and now — everything after this
	## line is replay. Guarding on the sequence keeps a double-click from
	## running two days at once.
	if turn_sequence.is_playing() or dispatch_panel.visible:
		return
	var faction: Dictionary = game.state["factions"][game.state["player_faction"]]
	var treasury_before := int(faction["treasury"])

	game.end_turn()

	_day_beats = game.day_beats()
	_treasury_delta = int(faction["treasury"]) - treasury_before
	_treasury_shown = float(treasury_before)
	_treasury_ticking = _treasury_delta != 0
	selected_army = ""
	_log_day()
	refresh()

	if not playback_enabled or _day_beats.is_empty():
		_on_day_played()
		return
	turn_sequence.play(game, DispatchRules.sequence_beats(game.data, _day_beats), map_view)


func _on_day_played() -> void:
	if playback_enabled:
		_show_dispatch()
	map_view.center_on_selected()


func _on_dispatch_dismissed() -> void:
	refresh()  # picks up the victory banner if the age closed today


func _show_dispatch() -> void:
	## Also reachable from the top bar: the journal lives in the game state, so
	## the day just closed can be re-read until the next one begins.
	dispatch_panel.open_for(game, _day_beats)


func _log_day() -> void:
	## The side log, the day's sequence and the Dispatch all read the same
	## filtered journal, so there is one account of the day rather than three
	## hand-written ones that can disagree.
	_log("[b]— %s —[/b]" % DispatchFormat.date_line(game.state))
	if _day_beats.is_empty():
		_log("[color=#707070]Nothing worth the ink.[/color]")
		return
	for beat in _day_beats:
		_log(DispatchFormat.bbcode_line(game.data, game.state, beat))


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
		# The loaded campaign brings its own day with it: the journal travels in
		# the save, so the Dispatch reopens on the turn that was actually last
		# resolved rather than on whatever this session happened to play.
		_day_beats = game.day_beats()
		_treasury_ticking = false
		_treasury_delta = 0
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
