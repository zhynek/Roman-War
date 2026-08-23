class_name MapView
extends Control
## The campaign map: regions drawn at their geographic positions as
## owner-colored settlement tokens joined by adjacency roads, with army
## badges, siege rings, and fog of war. Pans (right/middle drag) and zooms
## (wheel). Emits region_clicked for the campaign screen to interpret.

signal region_clicked(region_id: String)

const WORLD_SCALE := 14.0
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
var _font: Font


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()


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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_at(mouse_event.position, 1.15)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_at(mouse_event.position, 1.0 / 1.15)
		elif mouse_event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mouse_event.pressed
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var hit := _region_at(mouse_event.position)
			if hit != "":
				region_clicked.emit(hit)
	elif event is InputEventMouseMotion and _dragging:
		_camera_offset += (event as InputEventMouseMotion).relative / _zoom
		queue_redraw()


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := screen_point / _zoom - _camera_offset
	_zoom = clampf(_zoom * factor, 0.35, 3.0)
	_camera_offset = screen_point / _zoom - before
	queue_redraw()


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

	# Our agents: small hooded marks under the token's left shoulder.
	var agent_count := 0
	for agent in game.state.get("agents", {}).values():
		if agent["owner"] == game.state["player_faction"] and agent["region"] == region_id:
			agent_count += 1
	for i in range(agent_count):
		var mark := screen + Vector2(-radius - (4.0 + i * 8.0) * _zoom, radius * 0.5)
		draw_circle(mark, 3.0 * _zoom, Color(0.85, 0.85, 0.95))
		draw_circle(mark, 1.6 * _zoom, Color(0.2, 0.2, 0.3))

	if _zoom >= 0.55 and _font != null:
		var label: String = region.get("settlement_name", region_id)
		var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		draw_string(_font, screen + Vector2(-text_size.x / 2.0, radius + 13.0 * _zoom),
			label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.92, 0.88, 0.78))
