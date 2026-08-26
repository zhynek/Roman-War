class_name MapView
extends Control
## The campaign map: geographic terrain rendered from data/map_geometry.json
## in retained Node2D layers (terrain, political tint, fog, units, overlays)
## under one world-root transform, so panning and zooming move a transform
## instead of re-recording draw commands. Screen-space labels sit on top.
## Emits region_clicked for the campaign screen to interpret.
##
## Contracts the test suite pins: world_pos/to_screen/_region_at/center_on/
## _zoom_at share one transform (_camera_offset, _zoom); selected_region and
## the region_clicked signal keep their semantics; fixture worlds without
## positions or geometry still render tokens and pick by anchor distance.

signal region_clicked(region_id: String)

const WORLD_SCALE := 14.0

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

var geometry: MapGeometry
var map_font: Font

## Campaign-state caches, recomputed only by refresh_state() — never per
## frame. Layers read these instead of calling the fog query on every draw.
var visible_cache: Dictionary = {}
var owner_colors: Dictionary = {}
var army_groups: Dictionary = {}
var road_levels: Dictionary = {}

var _camera_offset := Vector2(-200, -200)
var _zoom := 1.0
var _dragging := false
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


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	map_font = _font
	geometry = MapGeometry.load_from()

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
		groups[army["owner"]] = int(groups.get(army["owner"], 0)) + 1
		army_groups[army["region"]] = groups

	road_levels = {}
	if geometry != null:
		for key in geometry.edges:
			var ends: PackedStringArray = String(key).split("|")
			var level := 0
			for end in ends:
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
	_camera_offset = -world_pos(game.data.regions[region_id]) + size / (2.0 * _zoom)
	queue_redraw()


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
	# One transform carries pan/zoom for every world layer; catching direct
	# _camera_offset writes here keeps the pinned camera contract intact.
	var camera := Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _camera_offset * _zoom)
	if _world_root != null and camera != _drawn_camera:
		_drawn_camera = camera
		_world_root.transform = camera
		_label_layer.queue_redraw()
	if not _state_fresh and game != null:
		refresh_state()


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


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := screen_point / _zoom - _camera_offset
	_zoom = clampf(_zoom * factor, 0.35, 3.0)
	_camera_offset = screen_point / _zoom - before


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
