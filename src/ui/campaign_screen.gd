class_name CampaignScreen
extends Control
## The campaign in play: top bar (treasury, date, standings, end turn), the
## map in the middle, the region context panel and turn log on the right.
## All rules go through the Game facade — this screen never touches state
## except to read it for display.
##
## Selection and orders: a LEFT click selects (a banner selects its force, a
## token its province); a RIGHT click, with one of our forces selected, is an
## order for it — march, sail, attack, besiege, dock. Shift makes a march a
## forced march; Esc deselects; Tab or N cycles the forces awaiting orders.
##
## Ending a turn is a DAY: the engine resolves the whole turn in one call, then
## TurnSequence replays the journal over the map from dawn to dusk and the
## Daily Dispatch closes it. Playback is presentation only — set
## playback_enabled = false and the same turn resolves synchronously, which is
## what the headless suite does when it drives twenty-five turns in a loop.

const SAVE_PATH := "user://roman_war_save.json"
const OPTIONS_PATH := "user://roman_war_options.json"

const OPTION_PLAYBACK := 1
const OPTION_GUIDED := 2
const OPTION_CONTROLS := 3
const OPTION_MOTION := 4
const OPTION_REALISM := 5
const OPTION_LANDSCAPE := 6

var realism_development_enabled := false
var realism_study: RealismStudy

var game: Game

var map_view: MapView
var force_panel: ForcePanel
var region_panel: RegionPanel
var side_scroll: ScrollContainer
var options_menu: MenuButton
var command_bar: MapCommandBar
var _planning_order := false
var _pinned_target := ""
var _order_preview: Dictionary = {}
var _forced_order := false
var _selection_key := ""
var _selected_region_shown := ""
var quest_panel: QuestPanel
var build_drawer: BuildDrawer
var family_panel: FamilyPanel
var diplomacy_panel: DiplomacyPanel
var knowledge_panel: KnowledgePanel
var annals_panel: AnnalsPanel
var senate_panel: SenatePanel
var senate_button: Button
var report_log: RichTextLabel
var turn_sequence: TurnSequence
var dispatch_panel: DispatchPanel
var top_labels := {}
var top_swatch: ColorRect
var selected_army := ""
var selected_fleet := ""
var info_card: InfoCard
var map_menu: MapContextMenu
var battle_screen: BattleScreen
var _card_catcher: Control
var playback_enabled := true
# The drawer's selection is hoisted here, exactly like selected_army: RegionPanel
# destroys and rebuilds all its children on every refresh, so nothing stateful
# can live inside it.
var drawer_open := false
var drawer_tab := "construction"
var drawer_chain := ""
var drawer_tier := 0
var selected_agent := ""
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
	# set_anchors_AND_OFFSETS_preset, not set_anchors_preset: the latter KEEPS
	# the control's current rect, and a freshly built Control is 0x0. The screen
	# then rendered at its minimum size in the top-left corner of the window and
	# grew only by the DELTA of a resize, leaving Godot's grey clear colour over
	# the rest. Pinned by test_campaign_screen_fills_its_window.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.build_theme()

	var background := ColorRect.new()
	background.color = UiStyle.BG_DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)


	# set_anchors_AND_OFFSETS_preset, not set_anchors_preset: the latter keeps
	# the control's current rect (0x0 for a freshly built Control), so the whole
	# screen would render at its minimum size in the top-left corner and grow
	# only by the DELTA of a window resize. Verified in-engine.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	map_view.region_context_requested.connect(open_map_menu)
	map_view.force_clicked.connect(_on_force_clicked)
	map_view.background_clicked.connect(_on_background_clicked)
	map_view.order_target.connect(_on_order_target)
	map_view.tooltip_provider = _tooltip_for
	split.add_child(map_view)
	_build_command_bar()

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

	side_scroll = ScrollContainer.new()
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(side_scroll)
	var panels := VBoxContainer.new()
	panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(panels)

	# The force card sits above the province panel; hidden when no force is
	# selected. Its orders go through the same handlers as the map's.
	force_panel = ForcePanel.new()
	force_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_panel.action_taken.connect(_after_order)
	force_panel.attack_requested.connect(attack_army_order)
	force_panel.siege_requested.connect(besiege_order)
	force_panel.assault_requested.connect(assault_order)
	force_panel.explore_requested.connect(_explore_order)
	force_panel.march_requested.connect(func(region_id: String, forced: bool):
		_on_order_target("region", region_id, forced))
	force_panel.sail_requested.connect(func(zone_id: String):
		_on_order_target("zone", zone_id, false))
	force_panel.sheet_requested.connect(func(char_id: String):
		family_panel.open_for(game, char_id))
	force_panel.unit_info_requested.connect(open_unit_card)
	force_panel.force_replaced.connect(select_force)
	force_panel.disband_requested.connect(disband_order)
	force_panel.refused.connect(_on_refused)
	force_panel.hide()
	panels.add_child(force_panel)

	region_panel = RegionPanel.new()
	region_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_panel.action_taken.connect(refresh)
	region_panel.army_selected.connect(_on_army_selected)
	region_panel.army_raised.connect(_on_army_raised)
	region_panel.fleet_launched.connect(_on_fleet_launched)
	region_panel.disband_requested.connect(disband_order)
	region_panel.refused.connect(_on_refused)
	region_panel.unit_info_requested.connect(open_unit_card)
	region_panel.building_info_requested.connect(open_building_card)
	region_panel.drawer_requested.connect(open_drawer)
	region_panel.agent_selected.connect(_on_agent_selected)
	region_panel.scout_requested.connect(_scout_order)
	region_panel.assassinate_requested.connect(_assassinate_order)
	region_panel.bribe_requested.connect(_bribe_order)
	region_panel.steal_requested.connect(_steal_order)
	panels.add_child(region_panel)

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

	turn_sequence = TurnSequence.new()
	turn_sequence.finished.connect(_on_day_played)
	add_child(turn_sequence)

	dispatch_panel = DispatchPanel.new()
	dispatch_panel.dismissed.connect(_on_dispatch_dismissed)
	add_child(dispatch_panel)

	_treasury_shown = float(game.state["factions"][game.state["player_faction"]]["treasury"])
	set_process(true)
	knowledge_panel = KnowledgePanel.new()
	knowledge_panel.knowledge_changed.connect(refresh)
	add_child(knowledge_panel)


	annals_panel = AnnalsPanel.new()
	add_child(annals_panel)

	senate_panel = SenatePanel.new()
	senate_panel.senate_changed.connect(refresh)
	add_child(senate_panel)

	_load_options()
	_log("[b]The year is 270 BC.[/b] Your house awaits its orders.")
	_log(String(game.data.effects_glossary["map_commands"]["welcome_controls"]))
	# Centering must wait for the first layout, or it centers on the map's
	# minimum size rather than the window it actually gets.
	var capital: String = game.state["factions"][game.state["player_faction"]]["capital"]
	map_view.center_on.call_deferred(capital)
	refresh()


func _build_top_bar() -> PanelContainer:
	## Two rows that WRAP instead of overflowing: the readings, with END TURN
	## pinned at the right, and the scrolls. One HBox once set the screen's
	## minimum width past 2000 px, and on any smaller window the last buttons
	## and the whole side column were simply off-screen.
	var chrome := PanelContainer.new()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	chrome.add_child(rows)

	var readings := HBoxContainer.new()
	readings.add_theme_constant_override("separation", 8)
	rows.add_child(readings)
	var faction: Dictionary = game.data.factions[game.state["player_faction"]]
	var swatch := ColorRect.new()
	swatch.color = Color.html(faction.get("color", "#808080"))
	swatch.custom_minimum_size = Vector2(6, 0)
	readings.add_child(swatch)
	top_swatch = ColorRect.new()
	top_swatch.custom_minimum_size = Vector2(18, 18)
	top_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	readings.add_child(top_swatch)

	var labels := HFlowContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("h_separation", 4)
	labels.add_theme_constant_override("v_separation", 0)
	readings.add_child(labels)
	for key in ["faction", "treasury", "date", "society", "senate", "victory", "mission"]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		if key == "faction":
			label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
		else:
			label.add_theme_color_override("font_color", UiStyle.TEXT)
		labels.add_child(label)
		top_labels[key] = label

	var end_turn := _bar_button("END TURN", _end_turn)
	end_turn.theme_type_variation = &"EndTurnButton"
	end_turn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	readings.add_child(end_turn)

	var scrolls := HFlowContainer.new()
	scrolls.add_theme_constant_override("h_separation", 4)
	scrolls.add_theme_constant_override("v_separation", 2)
	rows.add_child(scrolls)
	scrolls.add_child(_bar_button("Dispatch", _show_dispatch))
	scrolls.add_child(_bar_button("Family", func(): family_panel.open_for(game)))
	scrolls.add_child(_bar_button("Diplomacy", func(): diplomacy_panel.open_for(game)))
	# Roman houses only — refresh() re-derives that, since a loaded save may
	# belong to another house.
	senate_button = _bar_button("Senate", func(): senate_panel.open_for(game))
	scrolls.add_child(senate_button)
	scrolls.add_child(_bar_button("Knowledge", func(): knowledge_panel.open_for(game)))
	# The house-wide Book of Policies lived here. main holds edicts PER
	# PROVINCE, so they are issued and revoked from the region panel, where the
	# province they bind is the thing you are already looking at.
	scrolls.add_child(_bar_button("Annals", func(): annals_panel.open_for(game)))
	scrolls.add_child(_bar_button("Save", _save_game))
	scrolls.add_child(_bar_button("Load", _load_game))
	options_menu = _build_options_menu()
	scrolls.add_child(options_menu)
	return chrome


func _build_options_menu() -> MenuButton:
	## The switches players kept asking for: whether the day plays out over
	## the map after End Turn, and whether the guided trail is on. Both can
	## be flipped at any point of a campaign; the first is remembered between
	## sessions, the second travels with the save.
	var menu := MenuButton.new()
	menu.text = "Options ▾"
	menu.focus_mode = Control.FOCUS_NONE
	var popup := menu.get_popup()
	popup.add_check_item("Play the day out over the map after End Turn", OPTION_PLAYBACK)
	popup.add_check_item("Guided mode — objectives, rewards and a helping hand", OPTION_GUIDED)
	popup.add_check_item(String(game.data.effects_glossary.get("map_commands", {}).get("motion", "")), OPTION_MOTION)
	popup.add_separator()
	popup.add_item("Controls…", OPTION_CONTROLS)
	popup.add_check_item(String(game.data.effects_glossary["map_commands"]["realism_toggle"]), OPTION_LANDSCAPE)
	if realism_development_enabled or OS.get_cmdline_user_args().has("realism-preview"):
		popup.add_separator()
		popup.add_item(String(RealismStudy.read_settings().copy.menu), OPTION_REALISM)
	popup.id_pressed.connect(_on_option_pressed)
	popup.about_to_popup.connect(_sync_options)
	return menu


func _process(delta: float) -> void:
	## The coffers count up (or down) to the day's new figure, so the player
	## watches the money move instead of reading a number that has changed.
	map_view.camera_input_enabled = not (turn_sequence.is_playing() or dispatch_panel.visible or drawer_open
		or family_panel.visible or diplomacy_panel.visible or senate_panel.visible or knowledge_panel.visible or annals_panel.visible
		or (realism_study != null and realism_study.visible)
		or (battle_screen != null and battle_screen.visible) or (_card_catcher != null and _card_catcher.visible))
	for child in get_children():
		if child is Window and child.visible:
			map_view.camera_input_enabled = false
	if command_bar.visible:
		command_bar.fit_to(map_view.size)
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
	var seed_value := int(game.state.get("world_seed", 0))
	top_labels["date"].text = "%s, %s · seed %s   " % [year_text,
		String(game.state["season"]).capitalize(), str(seed_value) if seed_value != 0 else "?"]
	# The three things about your own people you can always see, whatever the
	# state of your provincial administration.
	var society: Array = game.faction_society()
	var readings: Array = []
	for factor in society:
		readings.append("%s %.0f" % [String(factor["label"]).replace("_", " ").capitalize(),
			absf(float(factor["value"]))])
	top_labels["society"].text = "%s   " % "  ·  ".join(PackedStringArray(readings))

	# The whole identity re-derives here, not just at build time — a loaded
	# save may belong to a different house than the campaign that was running.
	# The treasury and the date are NOT re-set here: the ticker above owns the
	# treasury label so it can count the day's swing rather than snap to it.
	var faction_info: Dictionary = game.data.factions[game.state["player_faction"]]
	top_swatch.color = Color.html(faction_info.get("color", "#808080"))
	top_labels["faction"].text = " %s   " % faction_info["name"]
	if faction_info.get("is_roman_house", false):
		top_labels["senate"].text = "Senate %.0f · People %.0f   " \
			% [float(faction["senate_standing"]), float(faction["popular_standing"])]
	else:
		top_labels["senate"].text = ""
	if senate_button != null:
		senate_button.visible = bool(faction_info.get("is_roman_house", false))
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

	_refresh_selection()
	_render_drawer()

	# The trail's checklist and its map guidance travel together: every
	# active stage with a target lights that region up.
	var overview := GuidedRules.overview(game.data, game.state)
	quest_panel.render(game, overview)
	_refresh_highlights(overview)
	# Ownership or fog may have moved: rebake the cached land layer. Selection
	# clicks deliberately skip this — they change nothing the land shows.
	map_view.refresh_state()
	map_view.queue_redraw()
	_update_command_bar()

	# The banner waits for the day to finish: an age that ends mid-sequence
	# should still get its dawn-to-dusk telling before the campaign is called.
	if game.state["winner"] != null and not _victory_shown \
			and not turn_sequence.is_playing() and not dispatch_panel.visible:
		_show_victory_banner(String(game.state["winner"]))


func _unhandled_key_input(event: InputEvent) -> void:
	if realism_study != null and realism_study.visible:
		return
	## Keyboard camera: the whole map is reachable without a mouse. Arrows or
	## WASD walk the view, +/- zoom, Home returns to the capital.
	if map_view == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	# Escape shuts what is open, then deselects: the yard, a card, the force,
	# the province. Tab (or N) walks the forces still awaiting orders. The
	# arrow/WASD camera contract below is untouched.
	if key.keycode == KEY_ESCAPE:
		deselect()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_TAB or key.keycode == KEY_N:
		cycle_selection()
		get_viewport().set_input_as_handled()
		return
	if not map_view.camera_input_enabled:
		return
	var handled := true
	match key.keycode:
		KEY_M:
			_begin_map_order()
		KEY_F:
			map_view.focus_force()
		KEY_V:
			map_view.set_zoom_level(1.2 if map_view._zoom >= MapView.DETAIL_ZOOM else 3.5)
			map_view.focus_force()
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
	## Selecting a column arms direct orders; Alt-click remains inspection.
	if _planning_order and selected_army != "":
		_pinned_target = region_id
		_preview_destination(region_id)
		return
	if selected_army != "" and game.state["armies"].has(selected_army) and not Input.is_key_pressed(KEY_ALT):
		_on_order_target("region", region_id, Input.is_key_pressed(KEY_SHIFT))
		return
	if selected_agent != "" and game.state["agents"].has(selected_agent) \
			and region_id != game.state["agents"][selected_agent]["region"]:
		_agent_order(region_id)
		return
	_clear_force_selection()
	selected_agent = ""
	map_view.selected_region = region_id
	_refresh_selection()
	_refresh_highlights()
	# This path does not go through refresh(), so without this the drawer would
	# keep showing the previous city's ladder after a click on the map.
	if drawer_open:
		drawer_chain = ""
		drawer_tier = 0
		_render_drawer()
	map_view.queue_redraw()


func _on_army_selected(army_id: String) -> void:
	## The province panel's army buttons toggle the selection.
	if selected_army == army_id:
		_clear_force_selection()
		_refresh_selection()
		_refresh_highlights()
		map_view.queue_redraw()
	else:
		select_force("army", army_id)


## --- Selection ----------------------------------------------------------------

func selected_force() -> String:
	return selected_army if selected_army != "" else selected_fleet


func select_force(kind: String, force_id: String) -> void:
	## The one entry point for selecting one of our forces: banner click,
	## panel button, keyboard cycling, a freshly raised or split-off force.
	_clear_force_selection()
	selected_agent = ""
	if kind == "army" and game.state["armies"].has(force_id):
		selected_army = force_id
		map_view.selected_region = game.state["armies"][force_id]["region"]
	elif kind == "fleet" and game.state["fleets"].has(force_id):
		selected_fleet = force_id
	map_view.selected_force = selected_force()
	refresh()
	_show_queued_route()


func _clear_force_selection() -> void:
	_cancel_map_order()
	selected_army = ""
	selected_fleet = ""
	map_view.selected_force = ""
	map_view.selected_sea_zone = ""
	map_view.highlight_zones = {}
	map_view.path_preview = {}


func _drop_stale_selection() -> void:
	## A selected force that was destroyed, garrisoned, merged away, docked
	## or lost stops being selected; the province it stood in stays.
	var player: String = game.state["player_faction"]
	if selected_army != "" and game.state["armies"].get(selected_army, {}).get("owner", "") != player:
		selected_army = ""
	if selected_fleet != "" and game.state["fleets"].get(selected_fleet, {}).get("owner", "") != player:
		selected_fleet = ""
		map_view.selected_sea_zone = ""
		map_view.highlight_zones = {}
	if selected_agent != "" and game.state["agents"].get(selected_agent, {}).get("owner", "") != player:
		selected_agent = ""
	# The province follows a selected army wherever it has got to — a queued
	# march advances it during End Turn without any order of ours.
	if selected_army != "":
		map_view.selected_region = game.state["armies"][selected_army]["region"]
	map_view.selected_force = selected_force()
	if selected_army == "":
		_cancel_map_order()


func _refresh_selection() -> void:
	## The side column follows the selection: the force card for a selected
	## army or fleet, the province panel for the selected region. The scroll
	## position survives the rebuild, or every action would jump to the top.
	_drop_stale_selection()
	var force := selected_force()
	# A new selection starts at the top of the column, so the force card is
	# actually in view; a refresh of the same selection keeps its place.
	var selection_key := "%s|%s|%s" % [force, map_view.selected_region, selected_agent]
	var scroll_before := side_scroll.scroll_vertical if selection_key == _selection_key else 0
	if map_view.selected_region != _selected_region_shown and drawer_open:
		drawer_chain = ""
		drawer_tier = 0
	_selection_key = selection_key
	_selected_region_shown = map_view.selected_region
	if force != "":
		force_panel.show_force(game, force)
		force_panel.show()
	else:
		force_panel.clear_panel()
		force_panel.hide()
	if map_view.selected_region != "":
		region_panel.show_region(game, map_view.selected_region, selected_army, selected_agent)
	elif force == "":
		region_panel.show_idle_hint(game)
	else:
		region_panel.clear_panel()
	side_scroll.set_deferred("scroll_vertical", scroll_before)


func _refresh_highlights(overview: Dictionary = {}) -> void:
	## The rings: the trail's target provinces, and over them everything the
	## selected force can do from where it stands — computed once per
	## selection or order, never per draw.
	var highlights := {}
	if overview.is_empty():
		overview = GuidedRules.overview(game.data, game.state)
	for stage in overview["active"]:
		if stage["target_region"] != "":
			highlights[stage["target_region"]] = "trail"
	if selected_army != "" and game.state["armies"].has(selected_army):
		highlights.merge(_army_options(selected_army), true)
	else:
		map_view.path_preview = {}
	map_view.highlight_regions = highlights
	if selected_fleet != "" and game.state["fleets"].has(selected_fleet):
		map_view.selected_sea_zone = game.state["fleets"][selected_fleet]["sea_zone"]
		var lanes := {}
		for zone_id in game.reachable_zones(selected_fleet):
			lanes[zone_id] = "sail"
		map_view.highlight_zones = lanes
	else:
		map_view.highlight_zones = {}


func _army_options(army_id: String) -> Dictionary:
	## {region_id: "march"|"forced"|"attack"|"siege"}: everywhere the army can
	## reach this season (gold), by forced march only (orange), and the
	## visible enemies it can strike from where it stands (red). Fog is
	## respected: nothing hidden ever changes a ring.
	var options := {}
	var plan := game.reachable_regions(army_id)
	for region_id in plan["reach"]:
		options[region_id] = "forced" if plan["reach"][region_id]["forced"] else "march"
	var visible := game.visible_regions()
	var targets := game.targets_for(army_id)
	for region_id in targets:
		if visible.has(region_id):
			options[region_id] = targets[region_id]
	return options


func _on_force_clicked(kind: String, force_id: String) -> void:
	var summary := game.force_summary(force_id)
	if summary.is_empty():
		return
	if summary["owner"] == game.state["player_faction"]:
		select_force(kind, force_id)
		return
	if _planning_order and kind == "army":
		_on_region_clicked(summary["region"])
		return
	if kind == "army" and selected_army != "" and not Input.is_key_pressed(KEY_ALT):
		_on_order_target("army", force_id, Input.is_key_pressed(KEY_SHIFT))
		return
	# A foreign banner: look, do not command — not even an agent's walk, so
	# the agent is stood down first. An army shows through its province.
	selected_agent = ""
	if kind == "army":
		_on_region_clicked(summary["region"])
	else:
		_clear_force_selection()
		selected_agent = ""
		_refresh_selection()
		_refresh_highlights()
		map_view.queue_redraw()
	_log(map_view.banner_tooltip(summary))


func _on_background_clicked() -> void:
	## Open sea with nothing under it: the force is dropped, the province stays.
	_clear_force_selection()
	_refresh_selection()
	_refresh_highlights()
	map_view.queue_redraw()


func _on_sea_zone_clicked(zone_id: String) -> void:
	## A left click on a sea's anchor takes the helm of one of our fleets
	## there — the next one on a second click, and the only route when the
	## map is zoomed out and the banners have given way to badges. An empty
	## sea just drops the force.
	var ours: Array = []
	for fleet_id in ForceRules.fleets_in(game.state, zone_id):
		if game.state["fleets"][fleet_id]["owner"] == game.state["player_faction"]:
			ours.append(fleet_id)
	if ours.is_empty():
		_clear_force_selection()
		map_view.selected_sea_zone = zone_id
		_refresh_selection()
		_refresh_highlights()
		map_view.queue_redraw()
		return
	var next_index := 0
	var current := ours.find(selected_fleet)
	if current >= 0:
		next_index = (current + 1) % ours.size()
	select_force("fleet", ours[next_index])


func _on_region_hovered(region_id: String) -> void:
	if _pinned_target != "":
		return
	if region_id == "":
		_order_preview = {}
		_show_queued_route()
		_update_command_bar()
		return
	_preview_destination(region_id)


func deselect() -> void:
	if _planning_order:
		_cancel_map_order()
		_show_queued_route()
		return
	## Esc: the yard first, then an open card, then the force, then the province.
	if drawer_open:
		close_drawer()
		return
	if _card_catcher != null and _card_catcher.visible:
		close_info_card()
		return
	if selected_force() != "" or selected_agent != "":
		_clear_force_selection()
		selected_agent = ""
	else:
		map_view.selected_region = ""
		map_view.selected_sea_zone = ""
	_refresh_selection()
	_refresh_highlights()
	map_view.queue_redraw()


func cycle_selection() -> void:
	## Tab / N: the next of our forces that still has orders to give.
	var candidates := game.forces_awaiting_orders()
	if candidates.is_empty():
		_log("Every force has its orders for the season.")
		return
	var next_index := 0
	var current := candidates.find(selected_force())
	if current >= 0:
		next_index = (current + 1) % candidates.size()
	var pick: String = candidates[next_index]
	var kind := ForceRules.kind_of(pick)
	select_force(kind, pick)
	if kind == "army":
		map_view.center_on(game.state["armies"][pick]["region"])
	else:
		map_view.center_on_zone(game.state["fleets"][pick]["sea_zone"])


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
		var forced := Input.is_key_pressed(KEY_SHIFT)
		var preview := game.army_path_preview(selected_army, region_id, forced)
		if not preview.is_empty() and not (preview["path"] as Array).is_empty():
			var turns := int(preview["turns"])
			lines.append("%s: %.1f points · %s" % [
				"Forced march" if forced else "March", float(preview["cost"]),
				"arrives this turn" if turns <= 1 else "%d turns" % turns])
	return "\n".join(lines)


func _on_agent_selected(agent_id: String) -> void:
	selected_agent = "" if selected_agent == agent_id else agent_id
	_clear_force_selection()
	_refresh_selection()
	_refresh_highlights()
	map_view.queue_redraw()


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


func _steal_order(agent_id: String, technique_id: String) -> void:
	var technique_name: String = game.data.techniques.get(technique_id, {}).get("name", technique_id)
	_confirm("Send our informer after the secrets of %s? Failure may cost us the man." % technique_name, func():
		var result := game.agent_steal_technique(agent_id, technique_id)
		if result.get("success", false):
			_log("[color=#80a0c0][b]The drawings of %s are ours.[/b] Taking it up will come cheaper now (Knowledge).[/color]"
				% technique_name)
		elif result.get("agent_lost", false):
			_log("[color=#e0a060]Our informer was taken copying the secrets of %s.[/color]" % technique_name)
		elif result.get("attempted", false):
			_log("Our informer came away empty-handed; the %s secrets are still kept." % technique_name)
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


## --- Orders ---------------------------------------------------------------------

func _on_order_target(kind: String, target_id: String, forced: bool) -> void:
	forced = forced or _forced_order
	## A right click on the map with one of our forces selected — and the
	## force card's "March to" and "Sail to" dropdowns, which say the same.
	var player: String = game.state["player_faction"]
	if selected_army != "" and game.state["armies"].has(selected_army):
		match kind:
			"region":
				if target_id != game.state["armies"][selected_army]["region"]:
					var preview := game.army_order_preview(selected_army, target_id, forced)
					if preview.get("action", "") == "march" and int(preview.get("turns", 0)) > 1:
						_begin_map_order()
						_pinned_target = target_id
						_preview_destination(target_id)
					else:
						_army_order(target_id, forced)
				elif game.targets_for(selected_army).has(target_id) or game.force_summary(selected_army).get("besieging") == target_id:
					_army_order(target_id, forced)
				else:
					open_map_menu(target_id)
			"army":
				var other: Dictionary = game.state["armies"].get(target_id, {})
				if other.is_empty():
					return
				if other["owner"] == player:
					select_force("army", target_id)
				elif game.visible_regions().has(other["region"]):
					attack_army_order(target_id)
			"fleet":
				if game.state["fleets"].get(target_id, {}).get("owner", "") == player:
					select_force("fleet", target_id)
	elif selected_fleet != "" and game.state["fleets"].has(selected_fleet):
		match kind:
			"zone":
				if target_id != game.state["fleets"][selected_fleet]["sea_zone"]:
					_fleet_order(target_id)
			"region":
				_dock_order(target_id)
			"fleet":
				if game.state["fleets"].get(target_id, {}).get("owner", "") == player:
					select_force("fleet", target_id)
			"army":
				if game.state["armies"].get(target_id, {}).get("owner", "") == player:
					select_force("army", target_id)


func _fleet_order(zone_id: String) -> void:
	var zone_name: String = game.data.sea_zones.get(zone_id, {}).get("name", zone_id)
	var result := game.sail_fleet(selected_fleet, zone_id)
	if result.get("arrived", false):
		_log("The fleet sails for the %s." % zone_name)
	elif result.get("ok", false):
		var halt: String = String(result.get("stopped_at", ""))
		_log("The fleet makes for the %s and halts in the %s — no lanes left this season."
			% [zone_name, game.data.sea_zones.get(halt, {}).get("name", halt)])
	else:
		_log("The fleet cannot reach the %s this season." % zone_name)
	_after_order()


func _dock_order(region_id: String) -> void:
	## A right click on one of our ports with a fleet selected makes port:
	## the ships wait in the harbour until launched again.
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != game.state["player_faction"]:
		_log("A fleet makes port only in one of our own harbours.")
		return
	var result := game.dock_fleet(selected_fleet, region_id)
	if result["ok"]:
		_log("The fleet makes port at %s; its ships wait in the harbour."
			% game.data.regions[region_id]["settlement_name"])
		map_view.selected_region = region_id
	else:
		_on_refused(result["error"])
	_after_order()


func _army_order(target_region: String, forced_march: bool = false) -> void:
	var army_id := selected_army
	var preview := game.army_order_preview(army_id, target_region, forced_march)
	if preview.is_empty():
		return
	var action := String(preview["action"])
	var reason := String(preview["reason"])
	if reason != "" and reason != "unreachable":
		_log(command_bar.words(reason))
		return
	match action:
		"attack":
			attack_army_order(preview["defender"])
			return
		"siege":
			besiege_order(target_region)
			return
		"assault":
			assault_order(target_region, "occupy")
			return
		"inspect":
			open_map_menu(target_region)
			return
	var from := String(preview["from"])
	var target_name: String = game.data.regions[target_region]["name"]
	var march: Dictionary = {}
	if action == "withdraw":
		if game.move_army(army_id, target_region, forced_march):
			march = {"moved": 1, "arrived": true, "traversed": [target_region]}
	else:
		# Use one route execution result for immediate and queued movement,
		# including the actual legs the presentation should animate.
		march = game.march_army(army_id, target_region, forced_march)
	if march.is_empty() and game.sea_move_army(army_id, target_region):
		_log("The army takes ship for %s." % target_name)
	elif march.is_empty():
		_log(command_bar.words("unreachable"))
	elif march.get("halted", false):
		_log(command_bar.words("barred"))
	elif march.get("arrived", false):
		_log("The army marches to %s." % target_name)
		if preview["blocked"]:
			_log(command_bar.words("approach_warning"))
	else:
		_log(command_bar.words("queued", {"town": target_name, "steps": game.state["armies"][army_id].get("march_path", []).size()}))
	if forced_march and int(march.get("moved", 0)) > 0:
		_log(command_bar.words("forced_warning"))
	map_view.play_march(army_id, from, march.get("traversed", []))
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
	## Every attack is confirmed with its paper odds first (BattleResolver.
	## estimate — the same model the battle will use); attacking a faction we
	## are not yet at war with additionally declares war, and says so.
	var defender: Dictionary = game.state["armies"].get(defender_id, {})
	if defender.is_empty():
		return
	var player: String = game.state["player_faction"]
	var owner_at_order := String(defender["owner"])
	var faction_name: String = game.data.factions.get(owner_at_order, {}).get("name", owner_at_order)
	var estimate := game.battle_estimate(selected_army, defender_id)
	if estimate.is_empty():
		_log("The army cannot come to grips with the enemy from here.")
		return
	var text := "Attack the %s?" % faction_name
	if not DiplomacyRules.at_war(game.state, player, owner_at_order):
		text = "This will declare war on %s. " % faction_name + text
	text += "\n" + RegionPanel.odds_text(estimate)
	var attacker_at_order := selected_army
	_confirm(text, func(): _resolve_attack(defender_id, owner_at_order, attacker_at_order))


func _resolve_attack(defender_id: String, expected_owner: String, expected_attacker: String = "") -> void:
	if expected_attacker != "" and selected_army != expected_attacker:
		return
	# The world can move between the dialog and the OK: re-validate, so a
	# stale confirmation can never attack a different foe than it named.
	if not game.state["armies"].has(selected_army) \
			or not game.state["armies"].has(defender_id) \
			or String(game.state["armies"][defender_id]["owner"]) != expected_owner:
		_log("The moment has passed.")
		_after_order()
		return
	if float(game.state["armies"][selected_army]["movement_left"]) <= 0.0001:
		_log("[color=#e0a060]The men have marched themselves out — the battle waits for next season.[/color]")
		_after_order()
		return
	var result := game.attack_army(selected_army, defender_id)
	_log_battle(result, "Battle")
	if not result.is_empty():
		_show_battle(result, _faction_display_name(game.state["player_faction"]),
			_faction_display_name(expected_owner))
	_after_order()


func assault_order(region_id: String, occupation: String) -> void:
	## Storming a city is confirmed like any attack, with the odds and the fate
	## chosen for the townsfolk spelled out — extermination is not a mis-click.
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return
	var holder_at_order := String(settlement["owner"])
	var settlement_name: String = game.data.regions.get(region_id, {}).get("settlement_name", region_id)
	var text := "Storm the walls of %s and %s the city?" % [settlement_name, occupation]
	var estimate := game.assault_estimate(selected_army, region_id)
	if not estimate.is_empty():
		text += "\n" + RegionPanel.odds_text(estimate)
	var attacker_at_order := selected_army
	_confirm(text, func(): _resolve_assault(region_id, occupation, holder_at_order, attacker_at_order))


func _resolve_assault(region_id: String, occupation: String, expected_owner: String, expected_attacker: String = "") -> void:
	if expected_attacker != "" and selected_army != expected_attacker:
		return
	# The same stale-confirmation guard as _resolve_attack: the city must still
	# be the one the dialog named, under our own siege.
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if settlement.is_empty() or String(settlement["owner"]) != expected_owner \
			or settlement.get("siege") == null or settlement["siege"]["besieger"] != selected_army:
		_log("The moment has passed.")
		_after_order()
		return
	var settlement_name: String = game.data.regions.get(region_id, {}).get("settlement_name", region_id)
	var holder_name := _faction_display_name(expected_owner)
	var result := game.assault_settlement(selected_army, region_id, occupation)
	_log_battle(result, "Assault on %s" % settlement_name)
	if not result.is_empty():
		_show_battle(result, _faction_display_name(game.state["player_faction"]), holder_name)
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
	if result.get("walkover", false):
		line = "[b]%s![/b] No one stood in the way." % title
	elif result.get("defender_destroyed", false):
		line += " The defenders are destroyed."
	elif result.get("attacker_destroyed", false):
		line += " The attackers are destroyed."
	_log(line)
	var breakdown = result.get("breakdown")
	if breakdown is Dictionary and not breakdown.is_empty() and not result.get("walkover", false):
		_log("    " + battle_summary(breakdown))
	var capture = result.get("capture")
	if capture is Dictionary and not capture.is_empty():
		_log("[color=#e0a060]The city is taken and %s — %d denarii of loot%s.[/color]" % [
			{"occupy": "occupied", "enslave": "its people enslaved", "exterminate": "its people put to the sword"}.get(
				capture.get("occupation", "occupy"), "occupied"),
			int(capture.get("loot", 0)),
			", %d slaves sent to your cities" % int(capture["slaves"]) if int(capture.get("slaves", 0)) > 0 else ""])


## How the estimator's factor labels read in the log.
const FACTOR_NAMES := {
	"upgrades": "kit", "matchups": "matchups", "class_terrain": "ground by arm", "terrain": "defender's ground",
	"walls": "walls", "assault": "storming walls", "wall_defense": "holding walls", "general": "general",
	"techniques": "warcraft", "martial": "martial ethos", "combined_arms": "combined arms",
	"attacking": "the charge", "fatigue": "fatigue", "sally": "sally", "experience": "experience",
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
	var holder_at_order := String(settlement["owner"])
	if not DiplomacyRules.at_war(game.state, player, holder_at_order):
		var faction_name: String = game.data.factions.get(holder_at_order, {}).get("name", holder_at_order)
		_confirm("This will declare war on %s. Lay siege?" % faction_name,
			func(): _resolve_siege(target_region, holder_at_order))
		return
	_resolve_siege(target_region, holder_at_order)


func _resolve_siege(target_region: String, expected_owner: String) -> void:
	# Same stale-confirmation guard as _resolve_attack: never declare war on
	# a faction the dialog did not name.
	if not game.state["armies"].has(selected_army) \
			or String(game.state["settlements"].get(target_region, {}).get("owner", "")) != expected_owner:
		_log("The moment has passed.")
		_after_order()
		return
	var from := String(game.state["armies"][selected_army]["region"])
	if game.besiege(selected_army, target_region):
		if from != target_region:
			map_view.play_march(selected_army, from, [target_region])
		_log("Siege laid to %s." % game.data.regions[target_region]["settlement_name"])
	elif MovementRules.hostile_army_in(game.state, game.state["player_faction"], target_region):
		_log("[color=#e0a060]A field army stands before the walls — it must be beaten before the city can be invested.[/color]")
	elif float(game.state["armies"][selected_army]["movement_left"]) <= 0.0001:
		_log("[color=#e0a060]Investing a city takes the season; the men have marched themselves out.[/color]")
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
	dialog.confirmed.connect(dialog.hide)
	dialog.confirmed.connect(on_accept)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _after_order() -> void:
	_cancel_map_order()
	## The selection follows a surviving force; a force that is gone (beaten,
	## garrisoned, merged away, docked) leaves its province selected instead.
	_drop_stale_selection()
	if selected_army != "":
		map_view.selected_region = game.state["armies"][selected_army]["region"]
	map_view.path_preview = {}
	refresh()
	_show_queued_route()


func _end_turn() -> void:
	## The engine resolves the entire turn here and now — everything after this
	## line is replay. Guarding on the sequence keeps a double-click from
	## running two days at once.
	if turn_sequence.is_playing() or dispatch_panel.visible:
		return
	var faction: Dictionary = game.state["factions"][game.state["player_faction"]]
	var treasury_before := int(faction["treasury"])

	_cancel_map_order()
	map_view.finish_marches()
	game.end_turn()

	_day_beats = game.day_beats()
	_treasury_delta = int(faction["treasury"]) - treasury_before
	_treasury_shown = float(treasury_before)
	_treasury_ticking = _treasury_delta != 0
	# The selection survives the turn if the force does; its rings are
	# recomputed by the refresh because the movement points are back.
	_log_day()
	refresh()

	if not playback_enabled or _day_beats.is_empty():
		_on_day_played()
		return
	turn_sequence.play(game, DispatchRules.sequence_beats(game.data, _day_beats), map_view)
	selected_agent = ""
	refresh()


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


## --- battle playback (R4) ---------------------------------------------------

func _show_battle(result: Dictionary, attacker_label: String, defender_label: String) -> void:
	## The fight replayed after the fact. Opens only when the result carries
	## a round log; it never touches the war-confirmation path — by the time
	## the curtain rises the battle is already resolved and logged.
	if result.is_empty() or (result.get("rounds", []) as Array).is_empty():
		return
	if battle_screen != null and is_instance_valid(battle_screen):
		battle_screen.queue_free()
	# The lambda captures THIS screen instance, never the member: a Close
	# double-fired in one frame stays idempotent, and if a new battle has
	# already replaced this one, closing the old must not touch the new.
	var screen := BattleScreen.create(game, result, attacker_label, defender_label)
	battle_screen = screen
	screen.closed.connect(func():
		screen.queue_free()
		if battle_screen == screen:
			battle_screen = null)
	add_child(screen)


func _on_battle_fought(result: Dictionary, defender_label: String) -> void:
	_show_battle(result, _faction_display_name(game.state["player_faction"]), defender_label)


func _faction_display_name(faction_id: String) -> String:
	return String(game.data.factions.get(faction_id, {}).get("name", faction_id))


## --- info cards & the map dossier (R1-R3) ----------------------------------

func open_unit_card(template_id: String) -> void:
	_ensure_card_host()
	map_menu.visible = false
	info_card.visible = true
	info_card.show_unit(game, template_id)
	_place_card()


func open_building_card(chain_id: String) -> void:
	_ensure_card_host()
	map_menu.visible = false
	info_card.visible = true
	info_card.show_building(game, chain_id, _selected_owner_culture())
	_place_card()


func open_map_menu(region_id: String) -> void:
	## The right-click gesture on the map: a province's dossier, its rows
	## opening the same cards the panel's right-clicks do.
	_ensure_card_host()
	info_card.visible = false
	map_menu.visible = true
	map_menu.open_for(game, region_id)
	_pop_at_mouse(map_menu)


func close_info_card() -> void:
	if _card_catcher != null:
		_card_catcher.visible = false


func _selected_owner_culture() -> String:
	## Building art tints to whoever's town the card was opened from.
	var region_id := map_view.selected_region
	if region_id != "" and game.state["settlements"].has(region_id):
		var owner: String = game.state["settlements"][region_id]["owner"]
		return String(game.data.factions.get(owner, {}).get("culture", ""))
	return ""


func _ensure_card_host() -> void:
	if _card_catcher == null:
		# A full-screen catcher behind the card: any click outside dismisses.
		_card_catcher = Control.new()
		_card_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
		_card_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		_card_catcher.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				close_info_card())
		add_child(_card_catcher)
		info_card = InfoCard.new()
		info_card.closed.connect(close_info_card)
		_card_catcher.add_child(info_card)
		map_menu = MapContextMenu.new()
		map_menu.unit_info_requested.connect(open_unit_card)
		map_menu.building_info_requested.connect(open_building_card)
		_card_catcher.add_child(map_menu)
	_card_catcher.visible = true
	_card_catcher.move_to_front()


func _place_card() -> void:
	info_card.sized_for(size.y)
	_pop_at_mouse(info_card)


func _pop_at_mouse(control: Control) -> void:
	control.reset_size()
	var at := get_local_mouse_position() + Vector2(16, -24)
	control.position = Vector2(
		clampf(at.x, 8.0, maxf(8.0, size.x - control.size.x - 16.0)),
		clampf(at.y, 8.0, maxf(8.0, size.y - control.size.y - 16.0)))


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
		map_view.finish_marches()
		_clear_force_selection()
		selected_agent = ""
		map_view.selected_region = ""
		region_panel.clear_panel()
		_victory_shown = false
		map_view.center_on(game.state["factions"][game.state["player_faction"]]["capital"])
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
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button


## --- Regrouping, refusals, options -----------------------------------------------

func _on_army_raised(army_id: String) -> void:
	var region_id: String = game.state["armies"][army_id]["region"]
	_log("An army musters in %s." % game.data.regions[region_id]["settlement_name"])
	select_force("army", army_id)


func _on_fleet_launched(fleet_id: String) -> void:
	var zone_id: String = game.state["fleets"][fleet_id]["sea_zone"]
	_log("A fleet puts to sea into the %s; it sails next season."
		% game.data.sea_zones.get(zone_id, {}).get("name", zone_id))
	select_force("fleet", fleet_id)


func _on_refused(error: String) -> void:
	_log("[color=#e0a060]%s[/color]" % ForcePanel.explain(error))


func disband_order(force_id: String, indices: Array) -> void:
	## Sending men home is irreversible, so it is confirmed first.
	_confirm("Disband %d unit%s? The men go back to the fields; no money comes back."
		% [indices.size(), "" if indices.size() == 1 else "s"],
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
		_log("%d unit%s disbanded; %d men return to the fields."
			% [disbanded, "" if disbanded == 1 else "s", returned])
	_after_order()


func _sync_options() -> void:
	if options_menu == null:
		return
	var popup := options_menu.get_popup()
	popup.set_item_checked(popup.get_item_index(OPTION_PLAYBACK), playback_enabled)
	popup.set_item_checked(popup.get_item_index(OPTION_GUIDED), game.guided_enabled())
	popup.set_item_checked(popup.get_item_index(OPTION_MOTION), map_view.motion_enabled)
	popup.set_item_checked(popup.get_item_index(OPTION_LANDSCAPE), map_view.realism_enabled)


func _on_option_pressed(id: int) -> void:
	match id:
		OPTION_PLAYBACK:
			set_playback(not playback_enabled)
		OPTION_GUIDED:
			set_guided(not game.guided_enabled())
		OPTION_MOTION:
			map_view.motion_enabled = not map_view.motion_enabled
			map_view.finish_marches()
			_save_options()
		OPTION_CONTROLS:
			show_controls()
		OPTION_LANDSCAPE:
			map_view.set_realism_enabled(not map_view.realism_enabled)
		OPTION_REALISM:
			open_realism_study()


func set_playback(enabled: bool) -> void:
	## Whether End Turn plays the day out over the map or resolves it at once
	## (the Dispatch and the log tell the same day either way).
	playback_enabled = enabled
	_sync_options()
	_save_options()
	_log("End Turn will %s." % ("play the day out over the map" if enabled
		else "resolve the day at once — read it in the Dispatch"))


func set_guided(enabled: bool) -> void:
	## The guided mode, switchable mid-campaign: off, the trail stops issuing
	## objectives and rewards; on again, it resumes where it was.
	game.set_guided(enabled)
	_sync_options()
	_log("Guided mode %s." % ("on: the trail's objectives are back on the map" if enabled
		else "off: no objectives, no rewards, no helping hand"))
	refresh()


func show_controls() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Controls"
	dialog.dialog_text = command_bar.words("controls_help")
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _save_options() -> void:
	var file := FileAccess.open(OPTIONS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"playback": playback_enabled, "march_motion": map_view.motion_enabled}))


func _load_options() -> void:
	if not FileAccess.file_exists(OPTIONS_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(OPTIONS_PATH))
	if parsed is Dictionary:
		playback_enabled = bool(parsed.get("playback", true))
		map_view.motion_enabled = bool(parsed.get("march_motion", true))


func _build_command_bar() -> void:
	command_bar = MapCommandBar.new()
	command_bar.game = game
	map_view.add_child(command_bar)
	command_bar.hide()
	command_bar.planning_requested.connect(_begin_map_order)
	command_bar.cancel_requested.connect(_cancel_map_order)
	command_bar.issue_requested.connect(_issue_map_order)
	command_bar.halt_requested.connect(func():
		game.halt_march(selected_army)
		_after_order())
	command_bar.focus_requested.connect(map_view.focus_force)
	command_bar.post_requested.connect(func():
		var result := game.build_watchpost(selected_army)
		if result["ok"]:
			_log(command_bar.words("post_built", {"sight": result["sight"]}))
			_after_order()
		else:
			_log(command_bar.words(result["reason"])))
	command_bar.sight_changed.connect(func(enabled: bool):
		map_view.show_sight = enabled
		map_view._overlay_layer.queue_redraw())
	command_bar.follow_changed.connect(func(enabled: bool):
		map_view.follow_marches = enabled
		if not enabled:
			map_view._follow_force = "")
	command_bar.forced_changed.connect(func(enabled: bool):
		_forced_order = enabled
		var target := _pinned_target if _pinned_target != "" else String(_order_preview.get("target", ""))
		if target != "":
			_preview_destination(target))


func _begin_map_order() -> void:
	if selected_army == "":
		return
	close_drawer()
	_planning_order = true
	_pinned_target = ""
	_order_preview = {}
	map_view.path_preview = {}
	_update_command_bar()


func _cancel_map_order() -> void:
	_planning_order = false
	_pinned_target = ""
	_order_preview = {}
	if map_view != null:
		map_view.path_preview = {}
	_update_command_bar()


func _preview_destination(target: String) -> void:
	if selected_army == "":
		return
	var forced := _forced_order or Input.is_key_pressed(KEY_SHIFT)
	_order_preview = game.army_order_preview(selected_army, target, forced)
	map_view.path_preview = _order_preview
	_update_command_bar()


func _issue_map_order() -> void:
	if not _planning_order or _pinned_target == "" or selected_army == "":
		return
	# Requote against current state; a pinned destination is not authority
	# to act using the old movement, siege or ownership values.
	var target := _pinned_target
	var forced := bool(_order_preview.get("forced", _forced_order))
	var fresh := game.army_order_preview(selected_army, target, forced)
	if fresh.is_empty() or fresh["reason"] != "":
		_preview_destination(target)
		return
	if fresh != _order_preview:
		_order_preview = fresh
		map_view.path_preview = fresh
		_update_command_bar()
		return
	_cancel_map_order()
	_army_order(target, forced)


func _show_queued_route() -> void:
	map_view.path_preview = {}
	if selected_army == "" or not game.state["armies"].has(selected_army):
		return
	map_view.path_preview = game.queued_march_preview(selected_army)


func _update_command_bar() -> void:
	if command_bar != null:
		command_bar.render(selected_army, _order_preview, _planning_order, _pinned_target != "")
		command_bar.fit_to(map_view.size)


func open_realism_study() -> void:
	if not (realism_development_enabled or OS.get_cmdline_user_args().has("realism-preview")):
		return
	if turn_sequence.is_playing() or (battle_screen != null and battle_screen.visible):
		return
	map_view.camera_input_enabled = false
	if realism_study == null:
		realism_study = RealismStudy.new()
		add_child(realism_study)
	else:
		realism_study.show()
	move_child(realism_study,-1)
