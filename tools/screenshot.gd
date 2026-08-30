extends SceneTree
## Dev harness: boot the campaign screen, let it lay out, save a PNG.
## Run under a virtual display:
##   xvfb-run -a -s "-screen 0 1920x1200x24" godot --path . --script res://tools/screenshot.gd
## Env: SHOT_OUT (path), SHOT_TURNS (end turns first), SHOT_ZOOM (zoom steps),
##      SHOT_DRAWER (construction|units) and SHOT_CHAIN to open the building yard
##
## SHOT_MODE=contact renders every tier of every chain as one sheet instead —
## the only way to eyeball 312 procedural buildings at once. A SubViewport can
## be far larger than the window, so the whole sheet lands in one image.
##   SHOT_MODE=contact SHOT_KIND=walls SHOT_OUT=out/walls.png ...
## Env for that mode: SHOT_KIND (one building kind), SHOT_CULTURE, SHOT_SEASON.

var _frames := 0
var _screen
var _sheet: SubViewport


func _init() -> void:
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames == 2 and OS.get_environment("SHOT_MODE") == "contact":
		_contact_sheet()
		return
	if _frames >= 6 and _sheet != null:
		_save(_sheet.get_texture().get_image(), "user://contact.png", "SHEET")
		return
	if _frames == 2:
		var game := Game.new_campaign(
			OS.get_environment("SHOT_FACTION") if OS.get_environment("SHOT_FACTION") != "" else "cornelii",
			42)
		for i in range(int(OS.get_environment("SHOT_TURNS"))):
			game.end_turn()
		# Mirror the real app: main.tscn hosts the screen inside a full-rect Control.
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(host)
		_screen = CampaignScreen.create(game)
		host.add_child(_screen)
	if _frames == 8 and _screen != null and OS.get_environment("SHOT_DRAWER") != "":
		var region := OS.get_environment("SHOT_REGION")
		if region == "":
			region = String(_screen.game.state["factions"][
				_screen.game.state["player_faction"]]["capital"])
		_screen.map_view.selected_region = region
		_screen.region_panel.show_region(_screen.game, region)
		_screen.open_drawer(OS.get_environment("SHOT_DRAWER"),
			OS.get_environment("SHOT_CHAIN"))
	if _frames == 8 and _screen != null:
		var zoom_steps := int(OS.get_environment("SHOT_ZOOM"))
		for i in range(abs(zoom_steps)):
			_screen.map_view.zoom_by(MapView.ZOOM_STEP if zoom_steps > 0 else 1.0 / MapView.ZOOM_STEP)
		_screen.map_view.queue_redraw()
	if _frames >= 14:
		_save(root.get_texture().get_image(), "user://shot.png", "SHOT")


func _save(image: Image, fallback: String, label: String) -> void:
	var out := OS.get_environment("SHOT_OUT")
	if out == "":
		out = fallback
	image.save_png(out)
	print("%s SAVED: %s  (%dx%d)" % [label, out, image.get_width(), image.get_height()])
	quit(0)


func _contact_sheet() -> void:
	## One row per chain, one cell per tier, captioned. Rows are sorted so the
	## sheet is byte-identical run to run and two of them can be diffed.
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	var kind_filter := OS.get_environment("SHOT_KIND")
	var culture_filter := OS.get_environment("SHOT_CULTURE")
	var season := OS.get_environment("SHOT_SEASON")
	if season == "":
		season = "summer"
	var cell := Vector2(232, 145)
	var caption := 17.0
	var pad := 8.0
	var label_w := 236.0

	var chain_ids: Array = data.chains.keys()
	chain_ids.sort()
	var rows: Array = []
	var widest := 1
	for chain_id in chain_ids:
		var chain: Dictionary = data.chains[chain_id]
		if kind_filter != "" and chain["kind"] != kind_filter:
			continue
		if culture_filter != "" and not chain["cultures"].has(culture_filter):
			continue
		rows.append(chain_id)
		widest = maxi(widest, (chain["levels"] as Array).size())
	if rows.is_empty():
		print("no chains matched SHOT_KIND=%s SHOT_CULTURE=%s" % [kind_filter, culture_filter])
		quit(1)
		return

	_sheet = SubViewport.new()
	_sheet.size = Vector2i(
		int(label_w + pad + float(widest) * (cell.x + pad)),
		int(pad + float(rows.size()) * (cell.y + caption + pad)))
	_sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sheet)
	var background := ColorRect.new()
	background.color = Color(0.11, 0.11, 0.12)
	background.size = _sheet.size
	_sheet.add_child(background)

	for r in rows.size():
		var chain: Dictionary = data.chains[rows[r]]
		var culture: String = culture_filter if culture_filter != "" else String(chain["cultures"][0])
		var y := pad + float(r) * (cell.y + caption + pad)
		_sheet.add_child(_label("%s\n%s / %s" % [chain["name"], chain["kind"], culture],
			Vector2(pad, y), 12, Color(0.95, 0.9, 0.75)))
		for i in (chain["levels"] as Array).size():
			var level: Dictionary = chain["levels"][i]
			var plate := ArtPlate.new()
			plate.position = Vector2(label_w + float(i) * (cell.x + pad), y)
			plate.size = cell
			plate.set_plate(art.building_plate(data, String(level["id"]), {
				"culture": culture, "terrain": "hills", "fertility": 2.0,
				"season": season, "tint": Color(0.72, 0.24, 0.20),
				"progress": 1.0, "damaged": false, "lod": 2}))
			_sheet.add_child(plate)
			_sheet.add_child(_label("%d  %s" % [i + 1, level["name"]],
				plate.position + Vector2(2, cell.y), 11, Color(0.85, 0.85, 0.85)))


func _label(text: String, at: Vector2, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label
