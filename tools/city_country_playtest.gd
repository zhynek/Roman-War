extends SceneTree
## Rendered city-to-country acceptance. QA outputs and storage stay outside
## the repository/player slots. Synthetic growth and scouting fixtures below
## exercise presentation; they are explicitly not a campaign balance soak.
## godot --path . --script res://tools/city_country_playtest.gd -- out_dir=/tmp/roman-war-city-country

var session: CampaignSession
var failed := false
var out := "/tmp/roman-war-city-country"


func _init() -> void:
	preload("res://tools/render_qa_storage.gd").configure("Roman War City Country QA/%d" % OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			out = arg.trim_prefix("out_dir=")
	_run.call_deferred()


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 1000)
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out)
	var game := Game.new_campaign("senate", 42, "medium", "long", false)
	session = CampaignSession.create(game, "city", "user://city-country.json")
	root.add_child(session)
	await _frames(16)
	var city := session.city
	_check(city.overview and city.survey_camera.current, "shared Roma begins at an architectural city overview")
	var original := _canon(game.state)
	var city_identity := city.get_instance_id()
	var walking_position := city.player.position
	await _shot("01-city-overview")
	var city_point := city.view_container.get_global_rect().get_center()
	for index in range(7):
		await _click_point(city_point, MOUSE_BUTTON_WHEEL_UP)
	_check(city.survey_camera.size < 80, "wheel zoom reaches detailed city architecture")
	await _shot("02-city-architecture")
	for index in range(18):
		if session.active_view == "campaign":
			break
		await _click_point(city_point, MOUSE_BUTTON_WHEEL_DOWN)
	_check(session.active_view == "campaign", "continued wheel zoom crosses from the city into the campaign")
	if session.active_view != "campaign":
		session.show_campaign_from_city()
	await _frames(12)
	var screen := session.campaign
	var view := screen.map_view
	screen.playback_enabled = false
	_check(view._zoom >= MapView.DETAIL_ZOOM and view.selected_region == "latium", "city transition frames the matching campaign settlement")
	await _shot("03-whole-city-on-map")
	await _click_text(view, String(game.data.effects_glossary["map_commands"]["countryside"]))
	_check(is_equal_approx(view._zoom, 3.5), "countryside preset provides intermediate geographic context")
	await _shot("04-countryside")
	await _click_text(view, String(game.data.effects_glossary["map_commands"]["country"]))
	_check(view._zoom <= 1.2, "country preset fits known territory")
	await _shot("05-known-country")
	var unknown := ""
	for region in game.data.regions:
		if not view.known_cache.has(region):
			unknown = region
			break
	_check(unknown != "", "the new campaign still has uncharted geography")
	if unknown != "":
		_check(not view.landscape.settlements.has(unknown), "unknown cities have no architectural model")
		_check(view._region_at(view.to_screen(view.world_pos(game.data.regions[unknown]))) == "", "uncharted geography does not become a selectable province")
	await _click_text(view, String(game.data.effects_glossary["map_commands"]["city"]))
	await _frames(6)
	# The actual settlement model, rather than an unrelated force standard,
	# supplies the pointer position used to open its ordinary commands.
	var at := view.landscape.camera.unproject_position(view.landscape.settlement_anchor("latium"))
	await _click_point(view.global_position + at)
	_check(view.selected_region == "latium", "clicking the rendered city selects its settlement")
	_check(view.city_entry_button.visible, "the selected owned city offers explicit entry")
	await _click(view.city_entry_button)
	_check(session.active_view == "city" and session.city.get_instance_id() == city_identity, "entry returns to the retained detailed Roma city")
	_check(city.player.position == walking_position, "the walking position survives zoom and city entry")
	await _shot("06-city-entered-again")
	await _click_text(city.command_bar, city.w("campaign_map"))
	_check(session.active_view == "campaign", "the explicit map command also returns to the shared campaign")
	await _frames(8)
	view.focus_settlement("latium", MapView.ZOOM_MAX)
	await _shot("07-maximum-map-detail")
	_check(_canon(game.state) == original, "zoom, picking, view switches and rendering preserve complete campaign state and RNG")

	# Fixture: the observer leaves a distant non-forest province, then foreign
	# owners grow it and bring troops in. Neither change may refresh its model.
	var region := _unseen_town(game)
	_check(region != "", "a remote town is available for remembered-intelligence acceptance")
	if region != "":
		await _remembered_town(game, view, region)

	# Fixture comparison uses a real settlement report, retaining the streets
	# while upgrading observed civic buildings. This never awards a campaign
	# achievement and does not pretend that seasons were played by the user.
	view.focus_settlement("latium", 20.0)
	screen.refresh()
	await _shot("11-growth-before")
	var old_key: String = view.landscape.settlements["latium"].key
	var settlement: Dictionary = game.state["settlements"]["latium"]
	for chain in game.data.chains.values():
		if chain.kind in ["government", "walls", "temple", "barracks", "market"] and chain.cultures.has("roman"):
			if settlement.buildings.has(chain.id):
				settlement.buildings[chain.id] = chain.levels.size()
	settlement.population = 30000
	CartographyRules.record_reports(game.data, game.state)
	screen.refresh()
	await _frames(6)
	_check(String(view.landscape.settlements["latium"].key) != old_key, "observed development rebuilds the architectural model")
	await _shot("12-growth-after-fixture")
	var before_frames := _canon(game.state)
	await _frames(30)
	_check(_canon(game.state) == before_frames, "the developed city remains presentation-only across frames")
	print("CITY COUNTRY PLAYTEST ", "FAILED" if failed else "PASSED", " · ", out)
	session.free()
	quit(1 if failed else 0)


func _unseen_town(game: Game) -> String:
	var observed := game.visible_regions()
	var ids: Array = game.state["settlements"].keys()
	ids.sort()
	for region in ids:
		if not observed.has(region) and game.data.regions[region].terrain != "forest":
			return region
	return ""


func _remembered_town(game: Game, view: MapView, region: String) -> void:
	var scout := {"owner": "senate", "region": region, "general": null, "movement_left": 0.0, "forced_march": false, "units": [{"template": "roman_town_watch", "experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0}]}
	game.state.armies["army_city_country_scout"] = scout
	ReconRules.refresh_contacts(game.data, game.state)
	game.state.armies.erase("army_city_country_scout")
	ReconRules.refresh_contacts(game.data, game.state)
	session.campaign.refresh()
	view.focus_settlement(region, 20.0)
	await _frames(6)
	var remembered: Dictionary = game.settlement_report(region)
	var old_key: String = view.landscape.settlements[region].key
	_check(not remembered.observed and view.known_cache.has(region), "departed scouts leave a dated city report and remembered geography")
	await _shot("08-remembered-town")
	var settlement: Dictionary = game.state.settlements[region]
	settlement.population = int(settlement.population) + 10000
	for chain_id in settlement.buildings:
		settlement.buildings[chain_id] = game.data.chains[chain_id].levels.size()
	var hidden_army: Dictionary = scout.duplicate(true)
	hidden_army.owner = settlement.owner
	game.state.armies["army_city_country_hidden"] = hidden_army
	game.state.turn = int(game.state.turn) + 1
	ReconRules.refresh_contacts(game.data, game.state)
	session.campaign.refresh()
	await _frames(6)
	_check(_canon(game.settlement_report(region)) == _canon(remembered), "foreign development outside sight does not refresh the report")
	_check(String(view.landscape.settlements[region].key) == old_key, "the drawn remembered city keeps its old architecture")
	_check(not view.force_summaries.has("army_city_country_hidden") and not view.landscape.armies.has("army_city_country_hidden"), "hidden troops never enter the banner or 3D army cache")
	await _shot("09-hidden-changes-still-remembered")
	game.state.armies["army_city_country_scout"] = scout
	ReconRules.refresh_contacts(game.data, game.state)
	session.campaign.refresh()
	await _frames(6)
	_check(game.settlement_report(region).observed, "returning scouts restore current observation")
	_check(String(view.landscape.settlements[region].key) != old_key, "new observation exposes the changed city architecture")
	_check(view.force_summaries.has("army_city_country_hidden"), "returning scouts discover troops on open ground")
	await _shot("10-scout-returned-new-observation")


func _click_text(node: Node, label: String) -> void:
	var button := _find_button(node, label)
	_check(button != null, "visible command exists: " + label)
	if button != null:
		await _click(button)


func _find_button(node: Node, label: String) -> Button:
	if node is Button and node.text == label and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _click(control: Control) -> void:
	await _frames(2)
	_check(control.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(control.get_global_rect()), "command fits the rendered window: " + str(control.get("text")))
	await _click_point(control.get_global_rect().get_center())


func _click_point(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	# The project stretches a 1280x800 logical canvas into the QA window.
	# push_input expects window coordinates unless explicitly told otherwise.
	point = root.get_final_transform() * point
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event)
		await _frames(2)
	await _frames(4)


func _shot(label: String) -> void:
	for index in range(6):
		await process_frame
		RenderingServer.force_draw(false)
	var path := out.path_join(label + ".png")
	_check(root.get_texture().get_image().save_png(path) == OK, "saved " + path)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _canon(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


func _check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	failed = failed or not ok
