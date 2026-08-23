class_name MapView
extends Control
## The campaign map: regions drawn at their geographic positions as
## owner-colored settlement tokens joined by adjacency roads, with army
## badges, siege rings, and fog of war. Pans (right/middle drag) and zooms
## (wheel). Emits region_clicked for the campaign screen to interpret.

signal region_clicked(region_id: String)

const WORLD_SCALE := 14.0
const LAND_EDGE_COLOR := Color(0.52, 0.43, 0.28, 0.45)
const SEA_EDGE_COLOR := Color(0.30, 0.48, 0.62, 0.30)
const FOG_COLOR := Color(0.13, 0.13, 0.16)
const FOG_OUTLINE := Color(0.24, 0.24, 0.28)
const ZONE_LABEL_COLOR := Color(0.42, 0.56, 0.68, 0.55)

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
	# Deep water fades toward the horizon in soft bands.
	var bands := 10
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var band_color := UiTheme.SEA_DEEP.lerp(UiTheme.SEA_SHALLOW, t * 0.8)
		draw_rect(Rect2(Vector2(0, size.y * i / bands), Vector2(size.x, size.y / bands + 1)), band_color)
	if game == null:
		return
	var visible_set := game.visible_regions()

	# The names of the seas, faint at their charted anchors.
	if _font != null and _zoom >= 0.5:
		for zone_id in game.data.sea_zones:
			var zone: Dictionary = game.data.sea_zones[zone_id]
			var anchor: Dictionary = zone.get("position", {})
			if anchor.is_empty():
				continue
			var at := to_screen(Vector2(float(anchor.get("x", 0)), float(anchor.get("y", 0))) * WORLD_SCALE)
			var zone_name: String = zone.get("name", zone_id)
			var text_size := _font.get_string_size(zone_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
			draw_string(_font, at - Vector2(text_size.x / 2.0, 0), zone_name,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 13, ZONE_LABEL_COLOR)

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

	# Token: soft ground shadow, faction disc, inner sheen, bronze rim.
	draw_circle(screen + Vector2(1.5, 2.5) * _zoom, radius, Color(0, 0, 0, 0.35))
	draw_circle(screen, radius, owner_color.darkened(0.18))
	draw_circle(screen, radius * 0.82, owner_color)
	draw_circle(screen + Vector2(-radius * 0.25, -radius * 0.3), radius * 0.36,
		Color(1, 1, 0.95, 0.16))
	var rim := Color(0, 0, 0, 0.55)
	var rim_width := 1.5
	if region_id == selected_region:
		draw_arc(screen, radius + 3.0 * _zoom, 0, TAU, 40, Color(UiTheme.GOLD, 0.35), 5.0 * _zoom)
		rim = UiTheme.GOLD
		rim_width = 2.5
	draw_arc(screen, radius, 0, TAU, 40, rim, rim_width * _zoom)
	# City tier as notches on the rim: one tick per level above village.
	for i in range(tier - 1):
		var angle := -TAU / 4.0 + TAU * float(i) / 8.0
		var tip := screen + Vector2.from_angle(angle) * (radius + 2.5 * _zoom)
		draw_circle(tip, 1.4 * _zoom, Color(0.95, 0.92, 0.8))

	if highlight_regions.has(region_id):
		draw_arc(screen, radius + 4.0 * _zoom, 0, TAU, 40, Color(1, 1, 0.5, 0.8), 2.0 * _zoom)

	if not settlement.is_empty() and settlement.get("siege") != null:
		draw_arc(screen, radius + 7.0 * _zoom, 0, TAU, 40, Color(0.9, 0.25, 0.15, 0.9), 2.5 * _zoom)
		draw_arc(screen, radius + 9.5 * _zoom, 0, TAU, 40, Color(0.9, 0.45, 0.15, 0.4), 1.5 * _zoom)

	if game.state["factions"].get(String(game.state["player_faction"]), {}).get("capital", "") == region_id:
		_draw_star(screen + Vector2(0, -radius - 7.0 * _zoom), 4.5 * _zoom, UiTheme.GOLD)

	# Army banners: one per owner present, a shield with the army count.
	var badge_offset := 0
	var army_owners := {}
	for army in game.state["armies"].values():
		if army["region"] == region_id:
			army_owners[army["owner"]] = int(army_owners.get(army["owner"], 0)) + 1
	var owner_ids: Array = army_owners.keys()
	owner_ids.sort()
	for army_owner in owner_ids:
		var badge_color := Color.html(game.data.factions.get(army_owner, {}).get("color", "#808080"))
		var badge_pos := screen + Vector2(radius + (4.0 + badge_offset * 12.0) * _zoom, -radius * 0.7)
		var badge_size := Vector2(9, 11) * _zoom
		draw_rect(Rect2(badge_pos + Vector2(1, 1.5) * _zoom, badge_size), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(badge_pos, badge_size), badge_color)
		draw_rect(Rect2(badge_pos, badge_size), Color(0, 0, 0, 0.65), false, 1.0 * _zoom)
		if _font != null and _zoom >= 0.8 and int(army_owners[army_owner]) > 1:
			draw_string(_font, badge_pos + Vector2(1.5 * _zoom, badge_size.y - 2.0 * _zoom),
				str(army_owners[army_owner]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.95))
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
		var at := screen + Vector2(-text_size.x / 2.0, radius + 13.0 * _zoom)
		draw_string_outline(_font, at, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, 3,
			Color(0, 0, 0, 0.75))
		draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.94, 0.9, 0.78))


func _draw_star(center: Vector2, size_px: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var angle := -TAU / 4.0 + TAU * float(i) / 10.0
		var reach := size_px if i % 2 == 0 else size_px * 0.45
		points.append(center + Vector2.from_angle(angle) * reach)
	draw_colored_polygon(points, color)
