class_name MapView
extends Control
## The campaign map: geographic terrain rendered from data/map_geometry.json
## in retained Node2D layers (terrain, political tint, fog, units, overlays)
## under one world-root transform, so panning and zooming move a transform
## instead of re-recording draw commands. Screen-space labels sit on top.
## Emits region_clicked (a left release that never travelled) and
## region_context_requested (a right press) for the campaign screen to
## interpret; left- and middle-drag pan the camera.
##
## Contracts the test suite pins: world_pos/to_screen/_region_at/center_on/
## _zoom_at share one transform (_camera_offset, _zoom); selected_region and
## the region_clicked signal keep their semantics; fixture worlds without
## positions or geometry still render tokens and pick by anchor distance.

signal region_clicked(region_id: String)
signal region_hovered(region_id: String)
signal sea_zone_clicked(zone_id: String)
signal region_context_requested(region_id: String)

const WORLD_SCALE := 14.0
## A left press only becomes a pan once the mouse has travelled this far —
## under it, the release still counts as the click. A hand's wobble is not
## an order to move the camera.
const DRAG_START_DISTANCE := 6.0

## Camera controls are deliberately redundant, because plenty of players have
## no mouse: the keyboard and the on-map buttons reach the same zoom_by /
## pan_by / reset_view as the wheel and the drag do.
const ZOOM_STEP := 1.15
const KEY_PAN_STEP := 90.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 3.0

var game: Game
var selected_region := "":
	set(value):
		selected_region = value
		if _overlay_layer != null:
			_overlay_layer.queue_redraw()
var highlight_regions: Dictionary = {}:
	set(value):
		highlight_regions = value
		if _overlay_layer != null:
			_overlay_layer.queue_redraw()
var path_preview: Dictionary = {}:
	set(value):
		path_preview = value
		if _overlay_layer != null:
			_overlay_layer.queue_redraw()
var hover_region := ""
var tooltip: PanelContainer
var tooltip_provider: Callable
var selected_sea_zone := "":
	set(value):
		selected_sea_zone = value
		if _overlay_layer != null:
			_overlay_layer.queue_redraw()
var highlight_zones: Dictionary = {}:
	set(value):
		highlight_zones = value
		if _overlay_layer != null:
			_overlay_layer.queue_redraw()

var geometry: MapGeometry
var map_font: Font

## Campaign-state caches, recomputed only by refresh_state() — never per
## frame. Layers read these instead of calling the fog query on every draw.
var visible_cache: Dictionary = {}
var owner_colors: Dictionary = {}
var army_groups: Dictionary = {}
var fleet_groups: Dictionary = {}
var road_levels: Dictionary = {}

var _camera_offset := Vector2(-200, -200)
var _pan_target: Vector2 = Vector2.ZERO
var _pan_seconds := 0.0
var _panning := false
## center_on before the first layout has no size to centre against, so the
## request is held until the map is laid out. Without this the camera lands on
## -world_pos + 0/2 and the player opens on empty sea.
var _pending_center := ""
var _zoom := 1.0
var _dragging := false
var _left_down := false
var _left_dragged := false
var _press_at := Vector2.ZERO
var _font: Font
var _world_root: Node2D
var _terrain_layer: MapLayers.TerrainLayer
var _political_layer: MapLayers.PoliticalLayer
var _fog_layer: MapLayers.FogLayer
var _units_layer: MapLayers.UnitsLayer
var _overlay_layer: MapLayers.OverlayLayer
var _label_layer: MapLayers.LabelLayer
var _decor_cache := {}
var _state_fresh := false
var _drawn_camera := Transform2D(0.0, Vector2.ONE * NAN, 0.0, Vector2.ZERO)
var _tooltip_label: RichTextLabel
var _hover_time := 0.0
var _tooltip_shown := false
var _tooltip_suppressed := false
var _mouse_at := Vector2.ZERO
var _last_shift := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	map_font = _font
	geometry = MapGeometry.load_from()
	resized.connect(_on_resized)

	_world_root = Node2D.new()
	add_child(_world_root)
	_terrain_layer = MapLayers.TerrainLayer.new()
	_political_layer = MapLayers.PoliticalLayer.new()
	_fog_layer = MapLayers.FogLayer.new()
	_units_layer = MapLayers.UnitsLayer.new()
	_overlay_layer = MapLayers.OverlayLayer.new()
	for layer in [_terrain_layer, _political_layer, _fog_layer, _units_layer, _overlay_layer]:
		layer.view = self
		_world_root.add_child(layer)
	_label_layer = MapLayers.LabelLayer.new()
	_label_layer.view = self
	add_child(_label_layer)

	tooltip = PanelContainer.new()
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.custom_minimum_size = Vector2(240, 0)
	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.custom_minimum_size = Vector2(240, 0)
	tooltip.add_child(_tooltip_label)
	add_child(tooltip)

	_build_camera_buttons()
	mouse_exited.connect(_clear_hover)


func refresh_state() -> void:
	## Re-cache everything the layers draw from and repaint them. Called by
	## the campaign screen whenever the world may have changed; panning and
	## zooming never come through here.
	if game == null:
		return
	_state_fresh = true
	visible_cache = game.visible_regions()

	owner_colors = {}
	for region_id in game.state["settlements"]:
		var owner: String = game.state["settlements"][region_id]["owner"]
		owner_colors[region_id] = Color.html(
			game.data.factions.get(owner, {}).get("color", "#808080"))

	army_groups = {}
	for army in game.state["armies"].values():
		var groups: Dictionary = army_groups.get(army["region"], {})
		var entry: Dictionary = groups.get(army["owner"],
			{"stacks": 0, "units": 0, "has_general": false, "fatigued": false})
		entry["stacks"] = int(entry["stacks"]) + 1
		entry["units"] = int(entry["units"]) + army["units"].size()
		entry["has_general"] = entry["has_general"] or army["general"] != null
		entry["fatigued"] = entry["fatigued"] or bool(army.get("forced_march", false))
		groups[army["owner"]] = entry
		army_groups[army["region"]] = groups

	fleet_groups = {}
	for fleet in game.state["fleets"].values():
		if fleet["owner"] != game.state["player_faction"]:
			continue  # foreign fleets stay unseen: fog has no naval eye yet
		fleet_groups[fleet["sea_zone"]] = int(
			fleet_groups.get(fleet["sea_zone"], 0)) + fleet["ships"].size()

	road_levels = {}
	if geometry != null:
		for key in geometry.edges:
			var ends: PackedStringArray = String(key).split("|")
			var level := 0
			for end in ends:
				# Built road tiers are state, not geography: an unscouted
				# settlement's paving must not render through the fog.
				if not visible_cache.has(end):
					continue
				if game.state["settlements"].has(end):
					level = maxi(level, int(SettlementRules.effect_max(
						game.data, game.state["settlements"][end], "road_level")))
			road_levels[key] = level

	for layer in [_terrain_layer, _political_layer, _fog_layer, _units_layer, _overlay_layer, _label_layer]:
		layer.queue_redraw()


func world_pos(region: Dictionary) -> Vector2:
	var position_data: Dictionary = region.get("position", {"x": 50, "y": 50})
	return Vector2(float(position_data["x"]), float(position_data["y"])) * WORLD_SCALE


func to_screen(world: Vector2) -> Vector2:
	return (world + _camera_offset) * _zoom


func center_on(region_id: String) -> void:
	if game == null or not game.data.regions.has(region_id):
		return
	if size.x <= 1.0 or size.y <= 1.0:
		_pending_center = region_id
		return
	_panning = false
	_camera_offset = _offset_centering(region_id)
	queue_redraw()


func _on_resized() -> void:
	if _pending_center == "":
		return
	var pending := _pending_center
	_pending_center = ""
	center_on(pending)


func center_on_selected() -> void:
	## Returns the camera to what the player was looking at, so a day that
	## wandered off across the map does not leave them lost when it ends.
	if selected_region != "":
		pan_to(selected_region, 0.35)


func pan_to(region_id: String, seconds: float) -> void:
	## Glide rather than snap: during the day's sequence the map is the stage,
	## and a cut between beats loses the player's place on it.
	if game == null or not game.data.regions.has(region_id):
		return
	if seconds <= 0.0:
		center_on(region_id)
		return
	_pan_target = _offset_centering(region_id)
	_pan_seconds = seconds
	_panning = true


func _offset_centering(region_id: String) -> Vector2:
	return -world_pos(game.data.regions[region_id]) + size / (2.0 * _zoom)


func _advance_pan(delta: float) -> void:
	## The day's sequence glides the camera between beats rather than cutting,
	## so the player keeps their place on the map. Folded into the renderer's
	## own _process: that one drives every world layer and must always run.
	if not _panning:
		return
	# Exponential ease: fast at first, settling rather than stopping dead.
	var step := clampf(delta / maxf(_pan_seconds, 0.01), 0.0, 1.0)
	_camera_offset = _camera_offset.lerp(_pan_target, step)
	if _camera_offset.distance_to(_pan_target) < 1.0:
		_camera_offset = _pan_target
		_panning = false


func decor_points(region_id: String) -> PackedVector2Array:
	## Deterministic topography-glyph anchors inside a region's territory:
	## a jittered grid, jitter hashed from the region id — never the game RNG.
	if _decor_cache.has(region_id):
		return _decor_cache[region_id]
	var points := PackedVector2Array()
	if geometry != null and geometry.cells.has(region_id) and game != null:
		var terrain: String = game.data.regions.get(region_id, {}).get("terrain", "plains")
		var spacing: float = {
			"mountains": 40.0, "forest": 36.0, "hills": 46.0, "marsh": 54.0,
			"desert": 66.0, "steppe": 70.0, "plains": 88.0,
		}.get(terrain, 80.0)
		var cell: Dictionary = geometry.cells[region_id]
		var bounds: Rect2 = cell["bounds"]
		var anchor := world_pos(game.data.regions[region_id])
		var row := 0
		var y := bounds.position.y + spacing * 0.5
		while y < bounds.end.y and points.size() < 400:
			var x := bounds.position.x + spacing * (0.25 + 0.5 * (row % 2))
			var column := 0
			while x < bounds.end.x and points.size() < 400:
				var salt := row * 97 + column
				var point := Vector2(
					x + (UiStyle.jitter(region_id, salt) - 0.5) * spacing * 0.8,
					y + (UiStyle.jitter(region_id, salt + 41) - 0.5) * spacing * 0.8)
				if point.distance_to(anchor) > 34.0:
					for polygon in cell["polys"]:
						if Geometry2D.is_point_in_polygon(point, polygon):
							points.append(point)
							break
				x += spacing
				column += 1
			y += spacing * 0.85
			row += 1
	_decor_cache[region_id] = points
	return points


func _process(_delta: float) -> void:
	_advance_pan(_delta)
	# One transform carries pan/zoom for every world layer; catching direct
	# _camera_offset writes here keeps the pinned camera contract intact.
	var camera := Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _camera_offset * _zoom)
	if _world_root != null and camera != _drawn_camera:
		_drawn_camera = camera
		_world_root.transform = camera
		_label_layer.queue_redraw()
	if not _state_fresh and game != null:
		refresh_state()
	if hover_region != "" and not _tooltip_shown and not _tooltip_suppressed:
		_hover_time += _delta
		if _hover_time >= 0.35:
			_show_tooltip()
	# Shift toggles forced march: refresh the hover preview so the sketched
	# route and turns always match the order a click would give.
	var shift := Input.is_key_pressed(KEY_SHIFT)
	if shift != _last_shift:
		_last_shift = shift
		if hover_region != "":
			region_hovered.emit(hover_region)
	_keyboard_pan(_delta)


func _keyboard_pan(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x += 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x -= 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y -= 1
	if direction != Vector2.ZERO:
		_camera_offset += direction * 700.0 * delta / _zoom
		_clamp_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_at(mouse_event.position, 1.15)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_at(mouse_event.position, 1.0 / 1.15)
		elif mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mouse_event.pressed
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			# The right button is a question now, not a camera handle: what
			# stands here? The campaign screen answers with the dossier menu.
			# Never mid-chord: while a left press or a drag is live it stays
			# silent — the pending click would otherwise fire underneath the
			# opening dossier (mouse focus keeps routing the release here,
			# past the menu's click-away catcher).
			if not _left_down and not _dragging:
				_hide_tooltip()
				_tooltip_suppressed = true
				var hit := _region_at(mouse_event.position)
				if hit != "":
					region_context_requested.emit(hit)
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_hide_tooltip()
				_tooltip_suppressed = true
				if mouse_event.double_click:
					# The second press of a double-click only centers — its
					# own first press's release already delivered the click,
					# and one camera gesture must never issue two orders.
					var hit := _region_at(mouse_event.position)
					if hit != "":
						center_on(hit)
				else:
					_left_down = true
					_left_dragged = false
					_press_at = mouse_event.position
			else:
				# The click rides on the release: a press that travelled was
				# a pan, and must not order anything when it lets go. The hit
				# is taken at the PRESS point — the sub-threshold tolerance
				# forgives a wobbling hand, so the wobble must never re-aim
				# the click across a border (with an army selected, a click
				# is an order).
				var was_click := _left_down and not _left_dragged
				_left_down = false
				_left_dragged = false
				if was_click:
					var hit := _region_at(_press_at)
					if hit != "":
						region_clicked.emit(hit)
					else:
						var zone := _sea_zone_at(_press_at)
						if zone != "":
							sea_zone_clicked.emit(zone)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _left_down and not _left_dragged \
				and motion.position.distance_to(_press_at) > DRAG_START_DISTANCE:
			_left_dragged = true
		if _dragging or _left_dragged:
			_camera_offset += motion.relative / _zoom
			_clamp_camera()
			_clear_hover()
		else:
			_update_hover(motion.position)


func _build_camera_buttons() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	column.offset_left = -44.0
	column.offset_top = -112.0
	column.offset_right = -10.0
	column.offset_bottom = -10.0
	column.add_theme_constant_override("separation", 4)
	# Only the buttons swallow clicks; the gaps between them stay map.
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.add_child(_camera_button("+", "Zoom in   (+ key)", 18,
		func(): zoom_by(ZOOM_STEP)))
	column.add_child(_camera_button("-", "Zoom out   (- key)", 18,
		func(): zoom_by(1.0 / ZOOM_STEP)))
	column.add_child(_camera_button("Home", "Back to your capital   (Home key)", 10,
		func(): reset_view()))


func _camera_button(text: String, tooltip: String, font_size: int, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(34, 30)
	button.add_theme_font_size_override("font_size", font_size)
	# Never take keyboard focus, or the arrow keys would drive the buttons
	# instead of the map.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button


func zoom_by(factor: float) -> void:
	## Zoom about the middle of the view — what a key press or a button means,
	## as opposed to the wheel, which zooms about the pointer.
	_zoom_at(size * 0.5, factor)


func pan_by(look_delta: Vector2) -> void:
	## Move the view in the given screen direction: pan_by(RIGHT) looks further
	## east. Distances are screen pixels, so panning feels the same at any zoom.
	## Unclamped, like every other direct write to _camera_offset.
	_panning = false
	_camera_offset -= look_delta / _zoom
	queue_redraw()


func reset_view() -> void:
	## Home: back to the player's capital at a readable zoom.
	_panning = false
	_zoom = 1.0
	if game != null:
		var capital: String = String(
			game.state["factions"][game.state["player_faction"]].get("capital", ""))
		if game.data.regions.has(capital):
			center_on(capital)
			return
	queue_redraw()


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	_panning = false
	var before := screen_point / _zoom - _camera_offset
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_camera_offset = screen_point / _zoom - before


func _clamp_camera() -> void:
	## Keep the world on screen. Lives only in the input paths — tests that
	## write _camera_offset directly stay unclamped, per the pinned contract.
	var world := Rect2(Vector2.ZERO, Vector2(100, 100) * WORLD_SCALE)
	if geometry != null and geometry.world_rect.size.x > 0:
		world = geometry.world_rect
	world = world.grow(220.0)
	var view_size := size / _zoom
	var low := -world.end + view_size * 0.5
	var high := -world.position - view_size * 0.5
	if low.x < high.x:
		_camera_offset.x = clampf(_camera_offset.x, low.x, high.x)
	if low.y < high.y:
		_camera_offset.y = clampf(_camera_offset.y, low.y, high.y)


func _sea_zone_at(screen_point: Vector2) -> String:
	## Nearest sea-zone anchor within reach — clicking open water near a sea
	## name addresses that sea (fleet orders).
	if game == null:
		return ""
	var best := ""
	var best_distance := 55.0 * _zoom
	for zone_id in game.data.sea_zones:
		var anchor_data: Dictionary = game.data.sea_zones[zone_id].get("position", {})
		if anchor_data.is_empty():
			continue
		var at := to_screen(Vector2(
			float(anchor_data["x"]), float(anchor_data["y"])) * WORLD_SCALE)
		if at.distance_to(screen_point) < best_distance:
			best_distance = at.distance_to(screen_point)
			best = zone_id
	return best


func _region_at(screen_point: Vector2) -> String:
	if game == null:
		return ""
	if geometry != null:
		var hit := geometry.region_at_world(screen_point / _zoom - _camera_offset)
		if hit != "" and game.data.regions.has(hit):
			return hit
	# No territory under the cursor (fixture worlds; a click just off a tiny
	# island): fall back to the nearest settlement anchor.
	var best := ""
	var best_distance := 26.0 * _zoom
	for region_id in game.data.regions:
		var distance := to_screen(world_pos(game.data.regions[region_id])).distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = region_id
	return best


func _update_hover(screen_point: Vector2) -> void:
	_mouse_at = screen_point
	_tooltip_suppressed = false  # real mouse motion re-arms the tooltip
	var hit := _region_at(screen_point)
	_set_cursor(Control.CURSOR_POINTING_HAND if hit != "" else Control.CURSOR_ARROW)
	if hit == hover_region:
		return
	hover_region = hit
	_hover_time = 0.0
	_hide_tooltip()
	if _overlay_layer != null:
		_overlay_layer.queue_redraw()
	region_hovered.emit(hit)


func _clear_hover() -> void:
	if hover_region != "":
		hover_region = ""
		if _overlay_layer != null:
			_overlay_layer.queue_redraw()
		region_hovered.emit("")
	_hide_tooltip()
	_set_cursor(Control.CURSOR_ARROW)


func _set_cursor(shape: Control.CursorShape) -> void:
	## Godot 4.4.1's headless DisplayServer faults at teardown once a cursor
	## shape has been set, and the gesture tests drive real motion events
	## through the hover path — so headless runs never touch the cursor.
	if DisplayServer.get_name() != "headless":
		mouse_default_cursor_shape = shape


func _show_tooltip() -> void:
	var text := ""
	if tooltip_provider.is_valid():
		text = String(tooltip_provider.call(hover_region))
	if text == "":
		return
	_tooltip_shown = true
	_tooltip_label.text = text
	tooltip.visible = true
	tooltip.reset_size()
	var at := _mouse_at + Vector2(18, 20)
	at.x = clampf(at.x, 4.0, maxf(4.0, size.x - tooltip.size.x - 4.0))
	at.y = clampf(at.y, 4.0, maxf(4.0, size.y - tooltip.size.y - 4.0))
	tooltip.position = at


func _hide_tooltip() -> void:
	_tooltip_shown = false
	_hover_time = 0.0
	if tooltip != null:
		tooltip.visible = false


func _draw() -> void:
	# The open sea: a vertical depth gradient behind every layer.
	if size.x <= 0 or size.y <= 0:
		return
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([UiStyle.SEA_SHALLOW, UiStyle.SEA_SHALLOW, UiStyle.SEA_DEEP, UiStyle.SEA_DEEP]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		if _label_layer != null:
			_label_layer.queue_redraw()
