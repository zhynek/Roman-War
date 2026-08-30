class_name MapView
extends Control
## The campaign map. Two cached Node2D layers paint the world behind this
## Control — deep sea, then the procedural landmass from MapGeometry:
## terrain-coloured province polygons, coastline and shelf, relief glyphs,
## borders, roads and sea lanes. The layers rebake only when ownership, fog
## or the relief LOD band changes; panning just moves them. The Control's own
## _draw adds the live tokens on top every frame: settlement seats, army
## badges, siege rings, wonders, labels and fog. Emits region_clicked for the
## campaign screen to interpret.
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
const GLYPH_OFF := 0.62           # zoom below this draws no relief glyphs
const GLYPH_FINE := 1.50          # zoom at or above this adds the fine infill
const FOG_COLOR := Color(0.16, 0.16, 0.18)
const FOG_OUTLINE := Color(0.28, 0.28, 0.30)
const SEA_DEEP := Color(0.043, 0.086, 0.133)
const SHELF_COLOR := Color(0.125, 0.235, 0.320)
const SHOAL_COLOR := Color(0.180, 0.330, 0.420)
const LAND_BASE := Color(0.42, 0.42, 0.33)
const COAST_INK := Color(0.86, 0.80, 0.66, 0.85)
const FRONTIER_INK := Color(0.30, 0.28, 0.24, 0.40)
const UNSURVEYED := Color(0.263, 0.252, 0.231)
const UNSURVEYED_EDGE := Color(0.180, 0.172, 0.157)
const BORDER_QUIET := Color(0.16, 0.13, 0.10, 0.30)
const ROAD_CASING := Color(0.184, 0.149, 0.114, 0.55)
const ROAD_CORE := Color(0.847, 0.788, 0.643, 0.50)
const LANE_COLOR := Color(0.435, 0.659, 0.776, 0.30)
const TERRAIN_BASE := {
	"plains": Color(0.494, 0.549, 0.337),
	"hills": Color(0.612, 0.518, 0.314),
	"mountains": Color(0.541, 0.510, 0.478),
	"forest": Color(0.310, 0.420, 0.271),
	"desert": Color(0.769, 0.663, 0.435),
	"steppe": Color(0.702, 0.682, 0.475),
	"marsh": Color(0.392, 0.459, 0.376),
}
const LUSH := Color(0.435, 0.604, 0.306)
const ARID := Color(0.725, 0.647, 0.455)
const SNOW := Color(0.906, 0.894, 0.855, 0.88)

var game: Game
var selected_region := ""
var highlight_regions: Dictionary = {}

var _camera_offset := Vector2(-200, -200)
var _zoom := 1.0
var _pending_center := ""   # centred once the map has its real size
var _centered_on := ""      # last programmatic centre, re-applied on resize
var _camera_touched := false  # the player moved the camera: stop recentring
var _dragging := false
var _left_press_at := Vector2.ZERO
var _left_dragging := false
var _left_moved := false
var _font: Font
var _sea_layer: Node2D
var _land_layer: Node2D
var _baked_band := -1
var _fills := {}
var _unsurveyed := {}
var _fog_shades := {}
var _shades := {}
var _borders_quiet := PackedVector2Array()
var _borders_hot := PackedVector2Array()
var _border_colors := PackedColorArray()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	_sea_layer = Node2D.new()
	_sea_layer.show_behind_parent = true
	_sea_layer.draw.connect(_paint_sea)
	add_child(_sea_layer)
	_land_layer = Node2D.new()
	_land_layer.show_behind_parent = true
	_land_layer.draw.connect(_paint_land)
	add_child(_land_layer)
	_build_camera_controls()
	resized.connect(_on_resized)


func _sync_camera() -> void:
	## The land layer IS the camera: to_screen(w) == (w + offset) * zoom, which
	## is exactly a Node2D at position offset*zoom with scale zoom. Every write
	## to _camera_offset or _zoom must be followed by this call.
	if _land_layer == null:
		return
	_land_layer.position = _camera_offset * _zoom
	_land_layer.scale = Vector2(_zoom, _zoom)
	_check_lod()


func _lod_band() -> int:
	## 0: tokens on bare terrain · 1: + shelf and quiet borders · 2: + coarse
	## relief · 3: + fine relief. The land layer rebakes only when the band
	## changes — never per zoom tick, never on a pan.
	if _zoom < 0.5:
		return 0
	if _zoom < GLYPH_OFF:
		return 1
	if _zoom < GLYPH_FINE:
		return 2
	return 3


func _check_lod() -> void:
	if _land_layer != null and _lod_band() != _baked_band:
		_baked_band = _lod_band()
		_land_layer.queue_redraw()


func _paint_sea() -> void:
	_sea_layer.draw_rect(Rect2(Vector2.ZERO, size), SEA_DEEP)


func repaint_land() -> void:
	_fills.clear()
	if _land_layer != null:
		_land_layer.queue_redraw()
	if _sea_layer != null:
		_sea_layer.queue_redraw()


func _on_resized() -> void:
	if _sea_layer != null:
		_sea_layer.queue_redraw()
	## The first layout is the first time this view knows how big it is, and
	## centring maths needs that size. Anything requested earlier waits here.
	if _pending_center != "":
		var region_id := _pending_center
		_pending_center = ""
		center_on(region_id)
	elif not _camera_touched and _centered_on != "":
		# Boot-time layout arrives in waves (split offsets, maximize, stretch).
		# Until the player moves the camera, every new size recentres the view,
		# so the capital cannot drift into a corner while the window settles.
		center_on(_centered_on)
	queue_redraw()


func world_pos(region: Dictionary) -> Vector2:
	var position_data: Dictionary = region.get("position", {"x": 50, "y": 50})
	return Vector2(float(position_data["x"]), float(position_data["y"])) * WORLD_SCALE


func to_screen(world: Vector2) -> Vector2:
	return (world + _camera_offset) * _zoom


func center_on(region_id: String) -> void:
	if game == null or not game.data.regions.has(region_id):
		return
	if size.x <= 1.0 or size.y <= 1.0:
		# Asked before the first layout: remember it and centre when sized.
		_pending_center = region_id
		return
	_centered_on = region_id
	_camera_touched = false
	_camera_offset = -world_pos(game.data.regions[region_id]) + size / (2.0 * _zoom)
	_sync_camera()
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
	_camera_touched = true
	_camera_offset -= look_delta / _zoom
	_sync_camera()
	queue_redraw()


func reset_view() -> void:
	_zoom = 1.0
	center_on_capital()
	_sync_camera()
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
			_camera_touched = true
			_camera_offset += motion.relative / _zoom
			_sync_camera()
			queue_redraw()
		elif _left_dragging:
			if not _left_moved \
					and motion.position.distance_to(_left_press_at) > DRAG_THRESHOLD:
				_left_moved = true
			if _left_moved:
				_camera_touched = true
				_camera_offset += motion.relative / _zoom
				_sync_camera()
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
	_camera_touched = true
	var before := screen_point / _zoom - _camera_offset
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_camera_offset = screen_point / _zoom - before
	_sync_camera()
	queue_redraw()


func _build_camera_controls() -> void:
	## Zoom and recenter buttons in the map's bottom-right corner: the visible
	## affordance for players who never discover the wheel or the keys.
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


func _region_at(screen_point: Vector2) -> String:
	if game == null:
		return ""
	# The token wins first, so two close cities stay separable at any zoom.
	var best := ""
	var best_distance := 26.0 * _zoom
	for region_id in game.data.regions:
		var distance := to_screen(world_pos(game.data.regions[region_id])).distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = region_id
	if best != "":
		return best
	# Otherwise the province itself is the target: the map paints whole
	# territories now, so clicking anywhere inside one must select it.
	var world := screen_point / _zoom - _camera_offset
	var geo := MapGeometry.for_data(game.data)
	for region_id in geo.ids:
		var cell: PackedVector2Array = geo.cells[region_id]
		if cell.size() >= 3 and Geometry2D.is_point_in_polygon(world, cell):
			return region_id
	return ""


func _draw() -> void:
	if game == null:
		return
	if _zoom <= 0.95 and _font != null:
		_draw_sea_names()
	var visible_set := game.visible_regions()
	for region_id in game.data.regions:
		_draw_region(region_id, visible_set.has(region_id))


func _draw_sea_names() -> void:
	## Letter-spaced sea names, the classic cartographic water label — and only
	## at a distance, because up close the map is about the land.
	var ink := Color(0.52, 0.66, 0.76, 0.42)
	var zone_ids: Array = game.data.sea_zones.keys()
	zone_ids.sort()
	for zone_id in zone_ids:
		var zone: Dictionary = game.data.sea_zones[zone_id]
		var pos: Dictionary = zone.get("position", {})
		if pos.is_empty():
			continue
		var label: String = String(zone.get("name", zone_id)).to_upper()
		var widths: Array = []
		var total := 0.0
		for i in label.length():
			var w := _font.get_string_size(label[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			widths.append(w)
			total += w + 3.0
		var world := Vector2(float(pos["x"]), float(pos["y"])) * WORLD_SCALE
		var pen := to_screen(world) - Vector2(total * 0.5, 0.0)
		for i in label.length():
			draw_string(_font, pen, label[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
			pen.x += widths[i] + 3.0


func _paint_land() -> void:
	if game == null:
		return
	var ci: CanvasItem = _land_layer
	var visible_set := game.visible_regions()
	var geo := MapGeometry.for_data(game.data)
	if _fills.is_empty():
		_rebuild_ownership(geo)

	var band := _lod_band()
	_baked_band = band
	var shown: Array = []
	for id in geo.ids:
		if geo.cells[id].size() >= 3:
			shown.append(id)

	# 1. Shelf: two concentric wide strokes along the shore, so land never meets
	#    the deep at a hard edge. Shore only — a landlocked region's frontier is
	#    the edge of the known world, and must not glow like a beach.
	for id in shown:
		for run in geo.coast_runs[id]:
			ci.draw_polyline(run, SHELF_COLOR, 20.0, true)
	for id in shown:
		for run in geo.coast_runs[id]:
			ci.draw_polyline(run, SHOAL_COLOR, 8.0, true)
	# 2. Land underlay: hides the sub-pixel seams between neighbouring cells.
	for id in shown:
		ci.draw_polyline(geo.closed[id], LAND_BASE, 4.0, true)
	# 3. Province fills.
	for id in shown:
		var ring: PackedVector2Array = geo.cells[id]
		if not visible_set.has(id):
			ci.draw_colored_polygon(ring, _unsurveyed[id])
		else:
			ci.draw_polygon(ring, _fills[id])
	# 4. Relief glyphs.
	if band >= 2:
		for id in shown:
			_draw_relief(ci, geo, id, visible_set.has(id))
	# 5. Coast, frontier, borders.
	ci.draw_multiline(geo.coast_lines, COAST_INK, -1.0)
	ci.draw_multiline(geo.frontier_lines, FRONTIER_INK, -1.0)
	if band >= 1:
		ci.draw_multiline(_borders_quiet, BORDER_QUIET, -1.0)
	if _border_colors.size() > 0:
		ci.draw_multiline_colors(_borders_hot, _border_colors, 2.2)
	# 6. Roads and lanes.
	for lane in geo.lanes:
		if visible_set.has(lane["ia"]) and visible_set.has(lane["ib"]):
			ci.draw_dashed_line(lane["a"], lane["b"], LANE_COLOR, -1.0, 10.0)
	var open_roads: Array = []
	for road in geo.roads:
		if visible_set.has(road["a"]) and visible_set.has(road["b"]):
			open_roads.append(road)
	for road in open_roads:
		ci.draw_polyline(road["pts"], ROAD_CASING, 4.2, true)
	for road in open_roads:
		ci.draw_polyline(road["pts"], ROAD_CORE, 2.2, true)


func _draw_relief(ci: CanvasItem, geo: MapGeometry, id: String, surveyed: bool) -> void:
	var region: Dictionary = game.data.regions[id]
	var terrain: String = region.get("terrain", "plains")
	var shade: Dictionary = _shades[id] if surveyed else _fog_shades[id]
	var fine := _baked_band >= 3
	var north: bool = float(region["position"]["y"]) < 55.0
	for glyph in geo.glyphs[id]:
		if glyph["fine"] and not fine:
			continue
		var p: Vector2 = glyph["p"]
		var roll: float = glyph["roll"]
		var s: float = 1.0 if not glyph["fine"] else 0.78
		match terrain:
			"mountains": _glyph_mountain(ci, p, s, roll, shade, north)
			"forest": _glyph_tree(ci, p, s, roll, shade)
			"hills": _glyph_hill(ci, p, s, roll, shade)
			"desert": _glyph_dune(ci, p, s, roll, shade)
			"marsh": _glyph_reed(ci, p, s, roll, shade)
			"steppe": _glyph_tuft(ci, p, s, roll, shade)
			_: _glyph_furrow(ci, p, s, roll, shade)


func _glyph_mountain(ci, p: Vector2, s: float, roll: float, shade: Dictionary, north: bool) -> void:
	var half := 12.0 * s * (0.86 + roll * 0.30)
	var high := 20.0 * s * (0.80 + roll * 0.44)
	var skew := (roll - 0.5) * 0.6
	var apex := p + Vector2(skew * half, -high)
	var foot_l := p + Vector2(-half, 0.0)
	var foot_r := p + Vector2(half, 0.0)
	var foot_m := p + Vector2(skew * half * 0.34, 0.0)
	ci.draw_colored_polygon(PackedVector2Array([foot_l, apex, foot_m]), shade["lit"])
	ci.draw_colored_polygon(PackedVector2Array([foot_m, apex, foot_r]), shade["shadow"])
	if north and roll > 0.62 and shade.get("snow", true):
		var cap := high * 0.30
		ci.draw_colored_polygon(PackedVector2Array([
			apex,
			apex + Vector2(-half * 0.36, cap),
			apex + Vector2(-half * 0.10, cap * 0.62),
			apex + Vector2(half * 0.14, cap * 0.94),
			apex + Vector2(half * 0.34, cap * 0.55),
		]), SNOW)
	ci.draw_polyline(PackedVector2Array([foot_l, apex, foot_r]), shade["ink"], -1.0)


func _glyph_tree(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	var r := 8.0 * s * (0.82 + roll * 0.36)
	ci.draw_line(p, p + Vector2(0.0, -r * 0.55), shade["ink"], -1.0)
	for tier in 3:
		var ty := -r * (0.42 + 0.40 * float(tier))
		var tw := r * (0.98 - 0.24 * float(tier))
		var mid := p + Vector2(0.0, ty)
		var col: Color = shade["shadow"]
		if tier == 1:
			col = shade["mid"]
		elif tier == 2:
			col = shade["lit"]
		ci.draw_colored_polygon(PackedVector2Array([
			mid + Vector2(-tw, 0.0), mid + Vector2(tw, 0.0),
			mid + Vector2(0.0, -r * 0.66)]), col)


func _glyph_hill(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	var half := 9.0 * s * (0.82 + roll * 0.38)
	var high := 5.4 * s * (0.80 + roll * 0.45)
	var arc := PackedVector2Array()
	for k in 7:
		var t := float(k) / 6.0
		arc.append(p + Vector2(lerpf(-half, half, t), -high * sin(PI * t)))
	ci.draw_polyline(arc, shade["lit"], 1.6 * s, true)
	var under := PackedVector2Array()
	for point in arc:
		under.append(point + Vector2(0.0, 1.8 * s))
	ci.draw_polyline(under, shade["shadow"], 1.2 * s, true)


func _glyph_dune(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	var half := 15.0 * s * (0.80 + roll * 0.45)
	var sag := 5.0 * s
	var crest := PackedVector2Array()
	for k in 7:
		var t := float(k) / 6.0
		crest.append(p + Vector2(lerpf(-half, half, t), -sag * sin(PI * t)))
	ci.draw_polyline(crest, shade["lit"], 2.2 * s, true)
	var lee := PackedVector2Array()
	for point in crest:
		lee.append(point + Vector2(0.0, sag * 0.45))
	ci.draw_polyline(lee, shade["shadow"], 1.4 * s, true)


func _glyph_reed(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	ci.draw_line(p + Vector2(-5.5 * s, 1.2 * s), p + Vector2(4.5 * s, 1.2 * s),
		shade["water"], 1.4 * s)
	for k in 3:
		var base := p + Vector2((float(k) - 1.0) * 3.4 * s, 0.0)
		var high := 7.0 * s * (0.7 + roll * 0.6)
		ci.draw_line(base, base + Vector2((roll - 0.5) * 4.0 * s, -high), shade["lit"], -1.0)


func _glyph_tuft(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	for k in 3:
		var ang := -PI * 0.5 + (roll - 0.5) * 0.7 + (float(k) - 1.0) * 0.44
		ci.draw_line(p, p + Vector2(cos(ang), sin(ang)) * 5.6 * s, shade["lit"], -1.0)


func _glyph_furrow(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	var ang := roll * PI
	var dir := Vector2(cos(ang), sin(ang))
	var nrm := dir.orthogonal()
	for k in 3:
		var off := nrm * (float(k) - 1.0) * 3.2 * s
		ci.draw_line(p + off - dir * 5.6 * s, p + off + dir * 5.6 * s, shade["furrow"], -1.0)


func _rebuild_ownership(geo: MapGeometry) -> void:
	_fills.clear()
	_unsurveyed.clear()
	_fog_shades.clear()
	_shades.clear()
	_borders_quiet = PackedVector2Array()
	_borders_hot = PackedVector2Array()
	_border_colors = PackedColorArray()
	for id in geo.ids:
		var ring: PackedVector2Array = geo.cells[id]
		if ring.size() < 3:
			continue
		var region: Dictionary = game.data.regions[id]
		var terrain: Color = TERRAIN_BASE.get(region.get("terrain", "plains"),
			TERRAIN_BASE["plains"])
		var f := clampf(float(region.get("fertility", 1.5)) / 3.0, 0.0, 1.0) - 0.5
		var target: Color = LUSH if f > 0.0 else ARID
		var base := terrain.lerp(target, absf(f) * 0.30)
		var owner: String = game.state["settlements"].get(id, {}).get("owner", "rebels")
		var raw := Color.html(game.data.factions.get(owner, {}).get("color", "#808080"))
		var tint := _house_key(raw)
		base = base.lerp(tint, 0.18)
		_shades[id] = {
			"lit": base.lightened(0.30),
			"mid": base.lightened(0.08),
			"shadow": base.darkened(0.34),
			"ink": Color(base.darkened(0.62), 0.55),
			"water": Color(0.259, 0.400, 0.451, 0.55),
			"furrow": Color(base.darkened(0.30), 0.22),
		}
		var here: Vector2 = geo.world_of(id)
		var reach := maxf(geo.bounds[id].size.length() * 0.5, 1.0)
		var shades := PackedColorArray()
		shades.resize(ring.size())
		for i in ring.size():
			var t := clampf(here.distance_to(ring[i]) / reach, 0.0, 1.0)
			shades[i] = base.lightened(0.10 * (1.0 - t)).darkened(0.22 * t)
		_fills[id] = shades
		# Unsurveyed: geography is public knowledge, intelligence is not. Terrain
		# shows, heavily muted; owner, settlement, roads and names stay hidden.
		var raw_terrain: Color = TERRAIN_BASE.get(region.get("terrain", "plains"),
			TERRAIN_BASE["plains"])
		_unsurveyed[id] = raw_terrain.lerp(UNSURVEYED, 0.62).darkened(0.10)
		var fb: Color = _unsurveyed[id]
		_fog_shades[id] = {
			"lit": fb.lightened(0.16), "mid": fb.lightened(0.05),
			"shadow": fb.darkened(0.22), "ink": Color(fb.darkened(0.50), 0.40),
			"water": Color(0.22, 0.28, 0.30, 0.40),
			"furrow": Color(fb.darkened(0.25), 0.14), "snow": false,
		}

		var tag_list: PackedStringArray = geo.tags[id]
		for i in ring.size():
			var tag: String = tag_list[i]
			if tag == MapGeometry.COAST or tag == MapGeometry.FRONTIER:
				continue
			var pair := tag.split("|")
			var other: String = pair[1] if pair[0] == id else pair[0]
			if other < id:
				continue
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			var neighbour: String = game.state["settlements"].get(other, {}).get("owner", "rebels")
			if neighbour == owner:
				_borders_quiet.append(a)
				_borders_quiet.append(b)
			else:
				_borders_hot.append(a)
				_borders_hot.append(b)
				# One colour per segment: draw_multiline_colors wants
				# colors.size() * 2 == points.size(), and rejects anything else.
				_border_colors.append(tint.lerp(Color.BLACK, 0.40))


static func _house_key(c: Color) -> Color:
	if c.s < 0.08:
		return Color(c.v, c.v, c.v).lerp(Color(0.86, 0.87, 0.90), 0.35)
	return Color.from_hsv(c.h, clampf(c.s, 0.40, 0.92), clampf(c.v, 0.52, 0.92))


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

	# A dark seat under the token, so it reads against any terrain behind it.
	draw_circle(screen, radius * 1.24, Color(0.02, 0.03, 0.05, 0.34))
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

	# One of the seven wonders stands here: a small ivory monument.
	if region.has("wonder"):
		_draw_wonder(screen + Vector2(-radius - 13.0 * _zoom, 2.0 * _zoom))

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
		var anchor := screen + Vector2(-text_size.x / 2.0, radius + 13.0 * _zoom)
		# The halo keeps names readable over mountains and desert. Mind the
		# signature: the outline size is the int argument BEFORE modulate.
		draw_string_outline(_font, anchor, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
			3, Color(0.03, 0.04, 0.06, 0.9))
		draw_string(_font, anchor, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
			Color(0.92, 0.88, 0.78))


func _draw_wonder(at: Vector2) -> void:
	## A tiny temple front — stylobate, two columns, architrave, pediment — for
	## the handful of regions whose data carries a wonder.
	var z := _zoom
	var ivory := Color(0.93, 0.89, 0.78)
	var shade := Color(0.72, 0.67, 0.55)
	draw_rect(Rect2(at + Vector2(-5.0 * z, 3.0 * z), Vector2(10.0 * z, 1.6 * z)), shade)
	draw_rect(Rect2(at + Vector2(-3.4 * z, -1.4 * z), Vector2(1.4 * z, 4.4 * z)), ivory)
	draw_rect(Rect2(at + Vector2(2.0 * z, -1.4 * z), Vector2(1.4 * z, 4.4 * z)), ivory)
	draw_rect(Rect2(at + Vector2(-4.4 * z, -2.6 * z), Vector2(8.8 * z, 1.2 * z)), ivory)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-5.0 * z, -2.6 * z),
		at + Vector2(0.0, -5.4 * z),
		at + Vector2(5.0 * z, -2.6 * z),
	]), ivory)
