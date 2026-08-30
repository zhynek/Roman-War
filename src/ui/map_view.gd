class_name MapView
extends Control
## The campaign map: regions drawn at their geographic positions as
## owner-colored settlement tokens joined by adjacency roads, with army
## badges, siege rings, and fog of war. Emits region_clicked for the campaign
## screen to interpret.
##
## Camera controls are deliberately redundant, because plenty of players have
## no mouse: drag with any button, trackpad pinch and two-finger scroll,
## on-map buttons, and the keyboard (wired in CampaignScreen) all reach the
## same zoom_by / pan_by / center_on_capital API.

signal region_clicked(region_id: String)

const WORLD_SCALE := 14.0
const ZOOM_STEP := 1.15
const ZOOM_MIN := 0.35
const ZOOM_MAX := 3.0
const KEY_PAN_STEP := 90.0        # screen pixels per arrow-key press
const PAN_GESTURE_SPEED := 24.0   # trackpad two-finger scroll to pixels
const DRAG_THRESHOLD := 5.0       # a left drag beyond this pans instead of selecting
const SEA_COLOR := Color(0.10, 0.17, 0.24)
const LAND_EDGE_COLOR := Color(0.45, 0.38, 0.28, 0.5)
const SEA_EDGE_COLOR := Color(0.25, 0.42, 0.55, 0.35)
const FOG_COLOR := Color(0.16, 0.16, 0.18)
const FOG_OUTLINE := Color(0.28, 0.28, 0.30)

var game: Game
var selected_region := ""
var highlight_regions: Dictionary = {}

var _camera_offset := Vector2(-200, -200)
var _zoom := 1.0
var _dragging := false
var _left_press_at := Vector2.ZERO
var _left_dragging := false
var _left_moved := false
var _font: Font


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	_build_camera_controls()


func world_pos(region: Dictionary) -> Vector2:
	var position_data: Dictionary = region.get("position", {"x": 50, "y": 50})
	return Vector2(float(position_data["x"]), float(position_data["y"])) * WORLD_SCALE


func to_screen(world: Vector2) -> Vector2:
	return (world + _camera_offset) * _zoom


func center_on(region_id: String) -> void:
	if game == null or not game.data.regions.has(region_id):
		return
	_camera_offset = -world_pos(game.data.regions[region_id]) + size / (2.0 * _zoom)
	queue_redraw()


func center_on_capital() -> void:
	if game == null:
		return
	var capital: String = game.state["factions"].get(
		String(game.state["player_faction"]), {}).get("capital", "")
	if capital != "":
		center_on(capital)


func zoom_by(factor: float) -> void:
	## Zoom about the middle of the view — what the buttons and keys want.
	_zoom_at(size / 2.0, factor)


func pan_by(look_delta: Vector2) -> void:
	## Move the view in the given screen direction: pan_by(RIGHT) looks further
	## east. Distances are screen pixels, so panning feels the same at any zoom.
	_camera_offset -= look_delta / _zoom
	queue_redraw()


func reset_view() -> void:
	_zoom = 1.0
	center_on_capital()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_at(mouse_event.position, ZOOM_STEP)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_at(mouse_event.position, 1.0 / ZOOM_STEP)
		elif mouse_event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mouse_event.pressed
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Left-drag pans too (a trackpad has no comfortable right-drag), so
			# the region is picked on RELEASE — only if the press never became
			# a drag.
			if mouse_event.pressed:
				_left_dragging = true
				_left_moved = false
				_left_press_at = mouse_event.position
			else:
				_left_dragging = false
				if not _left_moved:
					var hit := _region_at(_left_press_at)
					if hit != "":
						region_clicked.emit(hit)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging:
			_camera_offset += motion.relative / _zoom
			queue_redraw()
		elif _left_dragging:
			if not _left_moved \
					and motion.position.distance_to(_left_press_at) > DRAG_THRESHOLD:
				_left_moved = true
			if _left_moved:
				_camera_offset += motion.relative / _zoom
				queue_redraw()
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch: the natural zoom on a laptop with no wheel.
		var magnify := event as InputEventMagnifyGesture
		_zoom_at(magnify.position, magnify.factor)
	elif event is InputEventPanGesture:
		# Trackpad two-finger scroll walks the map.
		var gesture := event as InputEventPanGesture
		pan_by(gesture.delta * PAN_GESTURE_SPEED)


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := screen_point / _zoom - _camera_offset
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_camera_offset = screen_point / _zoom - before
	queue_redraw()


func _build_camera_controls() -> void:
	## Zoom and recenter buttons in the map's bottom-right corner: the visible
	## affordance for players who never discover the wheel or the keys.
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
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


func _region_at(screen_point: Vector2) -> String:
	if game == null:
		return ""
	var best := ""
	var best_distance := 26.0 * _zoom
	for region_id in game.data.regions:
		var distance := to_screen(world_pos(game.data.regions[region_id])).distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = region_id
	return best


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA_COLOR)
	if game == null:
		return
	var visible_set := game.visible_regions()

	# Sea-lane hints between coastal regions sharing a zone, then land roads.
	var drawn := {}
	for region_id in game.data.regions:
		var region: Dictionary = game.data.regions[region_id]
		for other_id in game.data.regions:
			if String(other_id) <= String(region_id):
				continue
			var pair: String = String(region_id) + "|" + String(other_id)
			if drawn.has(pair):
				continue
			var other: Dictionary = game.data.regions[other_id]
			if region.get("adjacent", []).has(other_id):
				drawn[pair] = true
				draw_line(to_screen(world_pos(region)), to_screen(world_pos(other)),
					LAND_EDGE_COLOR, 1.5 * _zoom)
			elif MapRules.shared_sea_zone(game.data, region_id, other_id) \
					and to_screen(world_pos(region)).distance_to(to_screen(world_pos(other))) < 220 * _zoom:
				drawn[pair] = true
				draw_dashed_line(to_screen(world_pos(region)), to_screen(world_pos(other)),
					SEA_EDGE_COLOR, 1.0 * _zoom, 8.0 * _zoom)

	for region_id in game.data.regions:
		_draw_region(region_id, visible_set.has(region_id))


func _draw_region(region_id: String, is_visible: bool) -> void:
	var region: Dictionary = game.data.regions[region_id]
	var screen := to_screen(world_pos(region))
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})

	if not is_visible:
		draw_circle(screen, 9.0 * _zoom, FOG_COLOR)
		draw_arc(screen, 9.0 * _zoom, 0, TAU, 24, FOG_OUTLINE, 1.5 * _zoom)
		return

	var owner: String = settlement.get("owner", "rebels")
	var owner_color := Color.html(game.data.factions.get(owner, {}).get("color", "#808080"))
	var tier := 1
	if not settlement.is_empty():
		tier = Constants.level_index(SettlementRules.settlement_level(game.data, settlement)) + 1
	var radius := (7.0 + 1.8 * tier) * _zoom

	draw_circle(screen, radius, owner_color)
	var outline := Color.WHITE if region_id == selected_region else Color(0, 0, 0, 0.55)
	var outline_width := 3.0 if region_id == selected_region else 1.5
	draw_arc(screen, radius, 0, TAU, 32, outline, outline_width * _zoom)

	if highlight_regions.has(region_id):
		draw_arc(screen, radius + 4.0 * _zoom, 0, TAU, 32, Color(1, 1, 0.5, 0.8), 2.0 * _zoom)

	if not settlement.is_empty() and settlement.get("siege") != null:
		draw_arc(screen, radius + 7.0 * _zoom, 0, TAU, 32, Color(0.9, 0.25, 0.15), 2.5 * _zoom)

	if game.state["factions"].get(String(game.state["player_faction"]), {}).get("capital", "") == region_id:
		draw_circle(screen + Vector2(0, -radius - 6.0 * _zoom), 3.0 * _zoom, Color(1, 0.9, 0.4))

	# An unexplored point of interest: a small gold diamond beside the token.
	var site: Dictionary = game.data.sites_by_region.get(region_id, {})
	if not site.is_empty() and not game.state.get("sites_explored", []).has(site["id"]):
		var pip := screen + Vector2(-radius - 6.0 * _zoom, -radius * 0.4)
		var arm := 3.2 * _zoom
		draw_colored_polygon(PackedVector2Array([
			pip + Vector2(0, -arm), pip + Vector2(arm, 0),
			pip + Vector2(0, arm), pip + Vector2(-arm, 0),
		]), Color(0.95, 0.8, 0.35))

	# Army badges: one square per owner present, stacked to the right.
	var badge_offset := 0
	var army_owners := {}
	for army in game.state["armies"].values():
		if army["region"] == region_id:
			army_owners[army["owner"]] = int(army_owners.get(army["owner"], 0)) + 1
	var owner_ids: Array = army_owners.keys()
	owner_ids.sort()
	for army_owner in owner_ids:
		var badge_color := Color.html(game.data.factions.get(army_owner, {}).get("color", "#808080"))
		var badge_pos := screen + Vector2(radius + (4.0 + badge_offset * 11.0) * _zoom, -radius * 0.6)
		draw_rect(Rect2(badge_pos, Vector2(8, 10) * _zoom), badge_color)
		draw_rect(Rect2(badge_pos, Vector2(8, 10) * _zoom), Color(0, 0, 0, 0.6), false, 1.0 * _zoom)
		badge_offset += 1

	if _zoom >= 0.55 and _font != null:
		var label: String = region.get("settlement_name", region_id)
		var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		draw_string(_font, screen + Vector2(-text_size.x / 2.0, radius + 13.0 * _zoom),
			label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.92, 0.88, 0.78))
