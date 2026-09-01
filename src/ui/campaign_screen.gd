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
var quest_panel: QuestPanel
var build_drawer: BuildDrawer
var family_panel: FamilyPanel
var diplomacy_panel: DiplomacyPanel
var knowledge_panel: KnowledgePanel
var annals_panel: AnnalsPanel
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
	map_view.tooltip_provider = _tooltip_for
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
	region_panel.unit_info_requested.connect(open_unit_card)
	region_panel.building_info_requested.connect(open_building_card)
	region_panel.battle_fought.connect(_on_battle_fought)
	region_panel.explore_requested.connect(_explore_order)
	region_panel.drawer_requested.connect(open_drawer)
	region_panel.agent_selected.connect(_on_agent_selected)
	region_panel.scout_requested.connect(_scout_order)
	region_panel.assassinate_requested.connect(_assassinate_order)
	region_panel.bribe_requested.connect(_bribe_order)
	region_panel.steal_requested.connect(_steal_order)
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
	top_swatch = ColorRect.new()
	top_swatch.custom_minimum_size = Vector2(18, 18)
	bar.add_child(top_swatch)

	for key in ["faction", "treasury", "date", "society", "senate", "victory", "mission"]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		if key == "faction":
			label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
		else:
			label.add_theme_color_override("font_color", UiStyle.TEXT)
		bar.add_child(label)
		top_labels[key] = label

	bar.add_child(_spacer())
	bar.add_child(_bar_button("Dispatch", _show_dispatch))
	bar.add_child(_bar_button("Family", func(): family_panel.open_for(game)))
	bar.add_child(_bar_button("Diplomacy", func(): diplomacy_panel.open_for(game)))
	bar.add_child(_bar_button("Knowledge", func(): knowledge_panel.open_for(game)))
	# The house-wide Book of Policies lived here. main holds edicts PER
	# PROVINCE, so they are issued and revoked from the region panel, where the
	# province they bind is the thing you are already looking at.
	bar.add_child(_bar_button("Annals", func(): annals_panel.open_for(game)))
	bar.add_child(_bar_button("Save", _save_game))
	bar.add_child(_bar_button("Load", _load_game))
	var end_turn := _bar_button("END TURN", _end_turn)
	end_turn.theme_type_variation = &"EndTurnButton"
	bar.add_child(end_turn)
	return chrome


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
		region_panel.show_region(game, map_view.selected_region, selected_army, selected_agent)
	_refresh_range_overlay()
	_refresh_fleet_overlay()
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
	map_view.refresh_state()
	map_view.queue_redraw()

	# The banner waits for the day to finish: an age that ends mid-sequence
	# should still get its dawn-to-dusk telling before the campaign is called.
	if game.state["winner"] != null and not _victory_shown \
			and not turn_sequence.is_playing() and not dispatch_panel.visible:
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
	_deselect_fleet()
	selected_agent = ""
	region_panel.show_region(game, region_id)
	_refresh_range_overlay()
	# This path does not go through refresh(), so without this the drawer would
	# keep showing the previous city's ladder after a click on the map.
	if drawer_open:
		drawer_chain = ""
		drawer_tier = 0
		_render_drawer()
	map_view.queue_redraw()


func _on_army_selected(army_id: String) -> void:
	selected_army = "" if selected_army == army_id else army_id
	selected_agent = ""
	region_panel.show_region(game, map_view.selected_region, selected_army)
	_refresh_range_overlay()


func _refresh_range_overlay() -> void:
	## The gold wash of regions this turn's points can reach — stretched by
	## Shift, the same way the click that follows would be.
	if selected_army != "" and game.state["armies"].has(selected_army):
		map_view.highlight_regions = game.army_reachable(
			selected_army, Input.is_key_pressed(KEY_SHIFT))
	else:
		map_view.highlight_regions = {}
		map_view.path_preview = {}


func _on_region_hovered(region_id: String) -> void:
	## With an army selected, hovering sketches the march: route, per-leg
	## cost, turns to arrive. Re-fired on Shift changes, so the range wash
	## stays in step with the forced-march toggle too.
	_refresh_range_overlay()
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
		if float(fleet["movement_left"]) >= float(game.data.balance["movement"]["sea_lane_cost"]):
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


func _army_order(target_region: String, forced_march: bool = false) -> void:
	var army: Dictionary = game.state["armies"][selected_army]
	var player: String = game.state["player_faction"]

	# Only an ADJACENT army we are ALREADY at war with is a target — marching
	# past a neutral must never start a war by accident, and a distant enemy
	# is marched toward (the path halts beside him), not attacked into thin
	# air. Deliberate first strikes go through the explicit Attack button.
	var defender := _enemy_army_in(target_region)
	if defender != "" and (army["region"] == target_region
			or MapRules.are_adjacent(game.data, army["region"], target_region)):
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
		var target_name: String = game.data.regions[target_region]["name"]
		if march.is_empty():
			_log("The army cannot reach %s this season." % target_name)
		elif march.get("halted", false) and int(march.get("moved", 0)) == 0:
			_log("[color=#e0a060]The way to %s is barred.[/color]" % target_name)
		elif march.get("halted", false):
			_log("[color=#e0a060]The army marches, but the road on to %s is barred.[/color]"
				% target_name)
		elif march.get("arrived", false) and march.get("blocked_destination", false):
			_log("The army halts before %s — the way in is barred." % target_name)
		elif march.get("arrived", false):
			_log("The army marches through to %s." % target_name)
		else:
			var turns := int(march.get("turns", 2))
			var warning := " It will halt before the walls." \
				if march.get("blocked_destination", false) else ""
			_log("The army sets out for %s — %d turns' march.%s" % [target_name, turns, warning])
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
	var owner_at_order := String(defender["owner"])
	if not DiplomacyRules.at_war(game.state, player, owner_at_order):
		var faction_name: String = game.data.factions.get(owner_at_order, {}).get("name", owner_at_order)
		_confirm("This will declare war on %s. Attack?" % faction_name,
			func(): _resolve_attack(defender_id, owner_at_order))
		return
	_resolve_attack(defender_id, owner_at_order)


func _resolve_attack(defender_id: String, expected_owner: String) -> void:
	# The world can move between the dialog and the OK: re-validate, so a
	# stale confirmation can never attack a different foe than it named.
	if not game.state["armies"].has(selected_army) \
			or not game.state["armies"].has(defender_id) \
			or String(game.state["armies"][defender_id]["owner"]) != expected_owner:
		_log("The moment has passed.")
		_after_order()
		return
	var result := game.attack_army(selected_army, defender_id)
	if result.is_empty():
		_log("The army cannot come to grips with the enemy from here.")
	else:
		_log("[b]Battle![/b] The %s prevail." % ("attackers" if result["winner"] == "attacker" else "defenders"))
		_show_battle(result, _faction_display_name(game.state["player_faction"]),
			_faction_display_name(expected_owner))
	_after_order()


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
	map_view.path_preview = {}
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
		selected_army = ""
		_deselect_fleet()
		selected_agent = ""
		map_view.selected_region = ""
		map_view.path_preview = {}
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
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button
