class_name MapView
extends Control
## The campaign map. World geometry (generated coastlines, region cells,
## roads) renders in retained Node2D layers under a single world-root
## transform, so panning and zooming never re-record a draw call; state
## changes mark only the affected layers dirty via refresh_state(). Picking
## is a polygon test against the region cells, falling back to the classic
## nearest-anchor scan for worlds without geometry (the test fixtures).
## Emits region_clicked for the campaign screen to interpret.

signal region_clicked(region_id: String)
signal sea_zone_clicked(zone_id: String)

const WORLD_SCALE := 14.0
const SEA_COLOR := Color(0.09, 0.15, 0.22)
const WORLD_MIN := Vector2(-2, -2) * WORLD_SCALE
const WORLD_MAX := Vector2(102, 102) * WORLD_SCALE
const KEY_PAN_SPEED := 700.0

var game: Game
var selected_region := ""
var hover_region := ""
var highlight_regions: Dictionary = {}
var highlight_zones: Dictionary = {}
var preview_army := ""
var tooltip: PanelContainer

var _camera_offset := Vector2(-200, -200)
var _zoom := 1.0
var _dragging := false
var _font: Font
var _geometry: MapGeometry
var _world_root: Node2D
var _terrain_layer: Node2D
var _political_layer: Node2D
var _fog_layer: Node2D
var _units_layer: Node2D
var _overlay_layer: Node2D
var _label_layer: Node2D

var _visible_cache := {}
var _icon_cache := {}
var _zone_anchors := {}
var _sorted_regions: Array = []
var _political_sig := ""
var _units_sig := ""
var _roads_sig := ""
var _overlay_sig := ""
var _zoom_bucket_cache := -1
var _path_preview := PackedVector2Array()
var _path_blocked := PackedVector2Array()
var _path_chips: Array = []
var _hover_summary := ""
var _tooltip_text: RichTextLabel


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	if game != null:
		_geometry = MapGeometry.load_for(game.data, WORLD_SCALE)
		_sorted_regions = game.data.regions.keys()
		_sorted_regions.sort()
		_build_zone_anchors()
	_world_root = Node2D.new()
	add_child(_world_root)
	_terrain_layer = _add_layer(MapLayers.TerrainLayer.new(), _world_root)
	_political_layer = _add_layer(MapLayers.PoliticalLayer.new(), _world_root)
	_fog_layer = _add_layer(MapLayers.FogLayer.new(), _world_root)
	_overlay_layer = _add_layer(MapLayers.OverlayLayer.new(), _world_root)
	_units_layer = _add_layer(MapLayers.UnitsLayer.new(), _world_root)
	_label_layer = _add_layer(MapLayers.LabelLayer.new(), self)
	_build_tooltip()
	_sync_camera()
	refresh_state()


func _build_tooltip() -> void:
	tooltip = PanelContainer.new()
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.custom_minimum_size = Vector2(230, 0)
	_tooltip_text = RichTextLabel.new()
	_tooltip_text.bbcode_enabled = true
	_tooltip_text.fit_content = true
	_tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_text.custom_minimum_size = Vector2(230, 0)
	tooltip.add_child(_tooltip_text)
	add_child(tooltip)


func _add_layer(layer, parent: Node) -> Node2D:
	layer.view = self
	parent.add_child(layer)
	return layer


## --- shared coordinate math (pinned by the test suite) ---------------------

func world_pos(region: Dictionary) -> Vector2:
	var position_data: Dictionary = region.get("position", {"x": 50, "y": 50})
	return Vector2(float(position_data["x"]), float(position_data["y"])) * WORLD_SCALE


func to_screen(world: Vector2) -> Vector2:
	return (world + _camera_offset) * _zoom


func center_on(region_id: String) -> void:
	if game == null or not game.data.regions.has(region_id):
		return
	_camera_offset = -world_pos(game.data.regions[region_id]) + size / (2.0 * _zoom)
	_sync_camera()


func _region_at(screen_point: Vector2) -> String:
	if game == null:
		return ""
	if _geometry != null:
		return _geometry.region_at_world(screen_point / _zoom - _camera_offset)
	var best := ""
	var best_distance := 26.0 * _zoom
	for region_id in game.data.regions:
		var distance := to_screen(world_pos(game.data.regions[region_id])).distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = region_id
	return best


## --- input -----------------------------------------------------------------

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
			if mouse_event.double_click:
				if hit != "":
					center_on(hit)
			elif hit != "":
				region_clicked.emit(hit)
			else:
				var zone := _zone_at(mouse_event.position)
				if zone != "":
					sea_zone_clicked.emit(zone)
	elif event is InputEventMouseMotion:
		if _dragging:
			_camera_offset += (event as InputEventMouseMotion).relative / _zoom
			_clamp_camera()
			_sync_camera()
		else:
			_update_hover((event as InputEventMouseMotion).position)


func _process(delta: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x -= 1.0
	if pan != Vector2.ZERO:
		_camera_offset += pan * KEY_PAN_SPEED * delta / _zoom
		_clamp_camera()
		_sync_camera()


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := screen_point / _zoom - _camera_offset
	_zoom = clampf(_zoom * factor, 0.35, 3.0)
	_camera_offset = screen_point / _zoom - before
	_clamp_camera()
	_sync_camera()


func _clamp_camera() -> void:
	## Input paths only — never applied to direct field writes, which the
	## test suite performs to prove picking follows the raw transform.
	var view_center := size / (2.0 * _zoom) - _camera_offset
	var clamped := view_center.clamp(WORLD_MIN, WORLD_MAX)
	_camera_offset += view_center - clamped


func _sync_camera() -> void:
	if _world_root != null:
		_world_root.transform = Transform2D(
			Vector2(_zoom, 0), Vector2(0, _zoom), _camera_offset * _zoom)
	if _label_layer != null:
		_label_layer.queue_redraw()
	var bucket := zoom_bucket()
	if bucket != _zoom_bucket_cache:
		_zoom_bucket_cache = bucket
		if _terrain_layer != null:
			_terrain_layer.queue_redraw()
	queue_redraw()


## --- state-driven redraw ---------------------------------------------------

func refresh_state() -> void:
	## Called by the campaign screen whenever game state may have changed:
	## recompute the fog set and icon parameters once, then redraw only the
	## layers whose inputs actually differ.
	if game == null or _world_root == null:
		return
	_visible_cache = game.visible_regions()
	_icon_cache.clear()
	var settled_ids: Array = game.state["settlements"].keys()
	settled_ids.sort()
	for region_id in settled_ids:
		var params := SettlementIcons.icon_params(game, region_id)
		if not params.is_empty():
			_icon_cache[region_id] = params

	var political := PackedStringArray()
	var visible_ids: Array = _visible_cache.keys()
	visible_ids.sort()
	for region_id in visible_ids:
		var params: Dictionary = _icon_cache.get(region_id, {})
		political.append("%s=%s/%d/%d/%s/%s/%s" % [region_id, params.get("owner", ""),
			int(params.get("level", -1)), int(params.get("wall_level", -1)),
			params.get("siege", false), params.get("port", false), params.get("capital", false)])
	_mark_if_changed("political", ";".join(political))

	var units := PackedStringArray()
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = game.state["armies"][army_id]
		units.append("%s@%s/%d/%s/%s" % [army_id, army["region"], army["units"].size(),
			army["general"] != null, army.get("forced_march", false)])
	var fleet_ids: Array = game.state["fleets"].keys()
	fleet_ids.sort()
	for fleet_id in fleet_ids:
		var fleet: Dictionary = game.state["fleets"][fleet_id]
		units.append("%s@%s/%d" % [fleet_id, fleet["sea_zone"], fleet["ships"].size()])
	_mark_if_changed("units", ";".join(units))

	var roads := PackedStringArray()
	for region_id in settled_ids:
		roads.append("%s:%d" % [region_id, road_level(region_id)])
	_mark_if_changed("roads", ";".join(roads))

	var overlay_bits := PackedStringArray([selected_region, hover_region])
	for region_id in sorted_highlight_ids():
		overlay_bits.append(String(region_id) + ":" + str(highlight_regions[region_id]))
	for zone_id in sorted_zone_highlight_ids():
		overlay_bits.append(String(zone_id) + ":" + str(highlight_zones[zone_id]))
	overlay_bits.append(str(_path_preview) + str(_path_blocked))
	_mark_if_changed("overlay", ";".join(overlay_bits))


func _mark_if_changed(which: String, signature: String) -> void:
	match which:
		"political":
			if signature != _political_sig:
				_political_sig = signature
				_political_layer.queue_redraw()
				_fog_layer.queue_redraw()
				_label_layer.queue_redraw()
		"units":
			if signature != _units_sig:
				_units_sig = signature
				_units_layer.queue_redraw()
		"roads":
			if signature != _roads_sig:
				if _roads_sig != "":
					_terrain_layer.queue_redraw()
				_roads_sig = signature
		"overlay":
			if signature != _overlay_sig:
				_overlay_sig = signature
				_overlay_layer.queue_redraw()


func set_path_preview(points: PackedVector2Array, blocked: PackedVector2Array) -> void:
	_path_preview = points
	_path_blocked = blocked
	if _overlay_layer != null:
		_overlay_layer.queue_redraw()


func set_hover(region_id: String) -> void:
	if region_id == hover_region:
		return
	hover_region = region_id
	if _overlay_layer != null:
		_overlay_layer.queue_redraw()


func hover_at(region_id: String) -> void:
	## Headless-testable hover: route preview and tooltip as if the pointer
	## sat on the region's anchor.
	set_hover(region_id)
	_rebuild_preview(region_id)
	var at := Vector2.ZERO
	if game != null and game.data.regions.has(region_id):
		at = to_screen(world_pos(game.data.regions[region_id]))
	_update_tooltip(region_id, at)


func _update_hover(screen_point: Vector2) -> void:
	var hit := _region_at(screen_point)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hit != "" \
		else Control.CURSOR_ARROW
	set_hover(hit)
	_rebuild_preview(hit)
	_update_tooltip(hit, screen_point)


func _rebuild_preview(hover_target: String) -> void:
	## The route overlay for the selected army: solid to wherever it can
	## march, red-dashed on a final leg it may not enter, cost chips per leg.
	var points := PackedVector2Array()
	var blocked := PackedVector2Array()
	var chips: Array = []
	_hover_summary = ""
	if game != null and preview_army != "" and game.state["armies"].has(preview_army) \
			and hover_target != "" \
			and hover_target != game.state["armies"][preview_army]["region"]:
		var forced := Input.is_key_pressed(KEY_SHIFT)
		var route := game.army_path_preview(preview_army, hover_target, forced)
		if route.get("reachable", false) or route.get("blocked_destination", false):
			var walk: Array = [game.state["armies"][preview_army]["region"]]
			walk.append_array(route.get("path", []))
			for i in range(walk.size() - 1):
				var leg := _leg_points(String(walk[i]), String(walk[i + 1]))
				for j in range(1 if not points.is_empty() else 0, leg.size()):
					points.append(leg[j])
			for leg_info in route.get("legs", []):
				chips.append({
					"at": world_pos(game.data.regions[leg_info["region"]]),
					"text": "%.1f" % float(leg_info["cost"]),
				})
			if route.get("blocked_destination", false):
				blocked = _leg_points(String(walk[walk.size() - 1]), hover_target)
				_hover_summary = "The way in is barred — the army can only approach."
			elif route.get("reachable", false):
				var turns := int(route["turns"])
				_hover_summary = "Arrives this turn." if turns <= 1 else "%d turns' march." % turns
		else:
			_hover_summary = "No road leads there."
	_path_chips = chips
	set_path_preview(points, blocked)
	if _label_layer != null:
		_label_layer.queue_redraw()


func _leg_points(from_region: String, to_region: String) -> PackedVector2Array:
	## The generated road between two adjacent regions, oriented from -> to;
	## a straight line when no geometry covers this world.
	if _geometry != null:
		var stored := _geometry.edge_path(from_region, to_region)
		if stored.size() >= 2:
			if from_region < to_region:
				return stored
			var reversed := stored.duplicate()
			reversed.reverse()
			return reversed
	return PackedVector2Array([
		world_pos(game.data.regions[from_region]), world_pos(game.data.regions[to_region]),
	])


func _update_tooltip(region_id: String, screen_point: Vector2) -> void:
	if tooltip == null:
		return
	if region_id == "" or game == null or not game.data.regions.has(region_id):
		tooltip.visible = false
		return
	var region: Dictionary = game.data.regions[region_id]
	var lines: Array = []
	if _visible_cache.has(region_id) and game.state["settlements"].has(region_id):
		var settlement: Dictionary = game.state["settlements"][region_id]
		var owner: Dictionary = game.data.factions.get(settlement["owner"], {})
		lines.append("[b]%s[/b] — %s" % [region["settlement_name"], region["name"]])
		lines.append("[color=%s]%s[/color]" % [owner.get("color", "#a0a0a0"), owner.get("name", settlement["owner"])])
	else:
		lines.append("[b]%s[/b]" % region["name"])
		if not _visible_cache.has(region_id):
			lines.append("[color=#8a8f98]Unscouted — no reports come from this land.[/color]")
	lines.append("%s — march cost %.1f" % [String(region["terrain"]).capitalize(),
		MovementRules.step_cost(game.data, game.state, region_id)])
	if _visible_cache.has(region_id):
		lines.append("Fertility %.1f" % float(region.get("fertility", 0.0)))
		var resources: Array = region.get("resources", [])
		if not resources.is_empty():
			lines.append("Goods: " + ", ".join(resources))
	if _hover_summary != "":
		lines.append("[color=#e8dca0]%s[/color]" % _hover_summary)
	var description: String = region.get("description", "")
	if description != "" and _visible_cache.has(region_id):
		lines.append("[i][color=#9aa4a8]%s[/color][/i]" % description)
	_tooltip_text.text = "\n".join(lines)
	tooltip.visible = true
	tooltip.reset_size()
	var at := screen_point + Vector2(18, 22)
	tooltip.position = Vector2(
		clampf(at.x, 0.0, maxf(0.0, size.x - tooltip.size.x)),
		clampf(at.y, 0.0, maxf(0.0, size.y - tooltip.size.y)))


func _zone_at(screen_point: Vector2) -> String:
	## The sea-zone anchor within clicking range of a screen point, for fleet
	## orders on open water.
	var best := ""
	var best_distance := 26.0
	var zone_ids: Array = _zone_anchors.keys()
	zone_ids.sort()
	for zone_id in zone_ids:
		var distance := to_screen(_zone_anchors[zone_id]).distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = zone_id
	return best


## --- accessors for the layers ----------------------------------------------

func geometry() -> MapGeometry:
	return _geometry


func visible_cache() -> Dictionary:
	return _visible_cache


func icon_cache() -> Dictionary:
	return _icon_cache


func sorted_region_ids() -> Array:
	return _sorted_regions


func sorted_highlight_ids() -> Array:
	var ids: Array = highlight_regions.keys()
	ids.sort()
	return ids


func sorted_zone_highlight_ids() -> Array:
	var ids: Array = highlight_zones.keys()
	ids.sort()
	return ids


func path_chips() -> Array:
	return _path_chips


func map_font() -> Font:
	return _font


func zoom_bucket() -> int:
	if _zoom < 0.55:
		return 0
	if _zoom < 1.25:
		return 1
	return 2


func faction_color(faction_id: String) -> Color:
	return Color.html(game.data.factions.get(faction_id, {}).get("color", "#808080"))


func road_level(region_id: String) -> int:
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return 0
	return int(SettlementRules.effect_max(game.data, settlement, "road_level"))


func zone_anchor(zone_id: String) -> Vector2:
	return _zone_anchors.get(zone_id, Vector2.ZERO)


func path_preview_points() -> PackedVector2Array:
	return _path_preview


func path_preview_blocked() -> PackedVector2Array:
	return _path_blocked


func _build_zone_anchors() -> void:
	for zone_id in game.data.sea_zones:
		var zone: Dictionary = game.data.sea_zones[zone_id]
		if zone.has("position"):
			_zone_anchors[zone_id] = Vector2(
				float(zone["position"]["x"]), float(zone["position"]["y"])) * WORLD_SCALE
			continue
		# No authored anchor: average the coastal members.
		var total := Vector2.ZERO
		var count := 0
		for region_id in game.data.regions:
			if game.data.regions[region_id].get("sea_zones", []).has(zone_id):
				total += world_pos(game.data.regions[region_id])
				count += 1
		if count > 0:
			_zone_anchors[zone_id] = total / float(count)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA_COLOR)
