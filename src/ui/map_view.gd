class_name MapView
extends Control
## The campaign map: geographic terrain rendered from data/map_geometry.json
## in retained Node2D layers (terrain, political tint, fog, units, overlays)
## under one world-root transform, so panning and zooming move a transform
## instead of re-recording draw commands. Screen-space labels and the force
## BANNERS sit on top: one banner per army and fleet, its fill the stack size
## out of the cap, the bar beneath the men's strength, a gold finial for a
## general, a white sail for a fleet.
##
## Input contract: a LEFT click (a release that never travelled) SELECTS —
## a banner selects its force, a token its region, a sea anchor its sea; a
## RIGHT press with one of our forces selected is an ORDER for it (the
## screen decides what it means), and with nothing selected it asks for the
## province dossier; left- and middle-drag pan; the wheel zooms.
##
## Contracts the test suite pins: world_pos/to_screen/_region_at/center_on/
## _zoom_at share one transform (_camera_offset, _zoom); selected_region and
## the region_clicked signal keep their semantics; fixture worlds without
## positions or geometry still render tokens and pick by anchor distance;
## banner_layout() feeds both drawing and picking, so they cannot disagree.

signal region_clicked(region_id: String)
signal region_hovered(region_id: String)
signal sea_zone_clicked(zone_id: String)
signal region_context_requested(region_id: String)
signal force_clicked(kind: String, id: String)             # left-click on an army or fleet banner
signal background_clicked()                                 # left-click on open sea, nothing under it
signal order_target(kind: String, id: String, forced: bool) # right press with a force selected; kind in army/fleet/region/zone

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

# Banner geometry at zoom 1 (everything scales with _zoom).
const BANNER_W := 12.0
const BANNER_H := 20.0
const BAR_H := 2.0
const SLOT_PITCH := 14.0
const MAX_SLOTS := 4              # beyond this a "+N" chip stands in the last slot
const COMPACT_ZOOM := 0.6         # below this banners give way to owner badges
const ZONE_PICK_RADIUS := 55.0
const BANNER_BG := Color(0.10, 0.10, 0.12, 0.92)
const BANNER_OUTLINE := Color(0, 0, 0, 0.8)
const FATIGUE_COLOR := Color(0.95, 0.60, 0.20)
const FINIAL_COLOR := Color(1.0, 0.85, 0.35)
const SAIL_COLOR := Color(0.95, 0.95, 0.95)
const BAR_BG := Color(0.15, 0.15, 0.17)
const BAR_LOW := Color(0.85, 0.25, 0.20)
const BAR_FULL := Color(0.35, 0.80, 0.35)

var game: Game
var selected_region := "":
	set(value):
		selected_region = value
		if _overlay_layer != null:
			_overlay_layer.queue_redraw()
var selected_force := "":
	set(value):
		selected_force = value
		if _banner_layer != null:
			_banner_layer.queue_redraw()
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
var hover_force := ""
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
var visible_zones: Dictionary = {}
var owner_colors: Dictionary = {}
var army_groups: Dictionary = {}
var fleet_groups: Dictionary = {}
var force_summaries: Dictionary = {}
var road_levels: Dictionary = {}

var _camera_offset := Vector2(-200, -200)
var _pan_target: Vector2 = Vector2.ZERO
var _pan_seconds := 0.0
var _panning := false
## center_on before the first layout has no size to centre against, so the
## request is held until the map is laid out. Without this the camera lands on
## -world_pos + 0/2 and the player opens on empty sea.
var _pending_center := ""
## The last size the camera was framed for: a late maximize (macOS applies
## it a frame after the window opens) keeps the same world point centred.
var _last_size := Vector2.ZERO
var _zoom := 1.0
var _compact := false
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
var _banner_layer: MapLayers.BannerLayer
var _banner_entries: Array = []
var _banner_camera := Transform2D(0.0, Vector2.ONE * NAN, 0.0, Vector2.ZERO)
var _banner_dirty := true
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
	_banner_layer = MapLayers.BannerLayer.new()
	_banner_layer.view = self
	add_child(_banner_layer)

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
	visible_zones = game.visible_sea_zones()

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
		# Fleets are drawn only in seas the player has eyes on.
		if not visible_zones.has(fleet["sea_zone"]):
			continue
		fleet_groups[fleet["sea_zone"]] = int(
			fleet_groups.get(fleet["sea_zone"], 0)) + fleet["ships"].size()

	# One summary per force the player can see, for the banners and their
	# tooltips — computed here, once per world change, never per frame.
	force_summaries = {}
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		if visible_cache.has(game.state["armies"][army_id]["region"]):
			force_summaries[army_id] = game.force_summary(army_id)
	var fleet_ids: Array = game.state["fleets"].keys()
	fleet_ids.sort()
	for fleet_id in fleet_ids:
		if visible_zones.has(game.state["fleets"][fleet_id]["sea_zone"]):
			force_summaries[fleet_id] = game.force_summary(fleet_id)
	_banner_dirty = true

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

	for layer in [_terrain_layer, _political_layer, _fog_layer, _units_layer, _overlay_layer, _label_layer, _banner_layer]:
		layer.queue_redraw()


## --- Coordinates -----------------------------------------------------------

func world_pos(region: Dictionary) -> Vector2:
	var position_data: Dictionary = region.get("position", {"x": 50, "y": 50})
	return Vector2(float(position_data["x"]), float(position_data["y"])) * WORLD_SCALE


func zone_world_pos(zone: Dictionary) -> Vector2:
	## Sea zones carry an authored anchor; a zone without one (fixture worlds)
	## sits at the centroid of its coastal regions.
	if zone.has("position"):
		return world_pos(zone)
	var total := Vector2.ZERO
	var count := 0
	if game != null:
		for region in game.data.regions.values():
			if region.get("sea_zones", []).has(zone.get("id", "")):
				total += world_pos(region)
				count += 1
	return total / float(maxi(count, 1))


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


func center_on_zone(zone_id: String) -> void:
	if game == null or not game.data.sea_zones.has(zone_id):
		return
	_panning = false
	_camera_offset = -zone_world_pos(game.data.sea_zones[zone_id]) + size / (2.0 * _zoom)
	queue_redraw()


func _on_resized() -> void:
	if _pending_center != "":
		var pending := _pending_center
		_pending_center = ""
		_last_size = size
		center_on(pending)
		return
	# The window grew or shrank under us (a late maximize, a dragged
	# splitter): keep the world point that was in the middle in the middle.
	if _last_size != Vector2.ZERO and size != _last_size and not _panning:
		_camera_offset += (size - _last_size) / (2.0 * _zoom)
	_last_size = size


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
		_banner_layer.queue_redraw()
	# Crossing the compact threshold swaps banners for badges: the retained
	# units layer must repaint for that, though nothing in the world changed.
	var compact := _zoom < COMPACT_ZOOM
	if compact != _compact:
		_compact = compact
		if _units_layer != null:
			_units_layer.queue_redraw()
	if not _state_fresh and game != null:
		refresh_state()
	if (hover_region != "" or hover_force != "") and not _tooltip_shown and not _tooltip_suppressed:
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


## --- Input --------------------------------------------------------------------

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
			# The right button is an order when one of our forces is selected,
			# and a question ("what stands here?") otherwise. Never mid-chord:
			# while a left press or a drag is live it stays silent — the
			# pending click would otherwise fire underneath the opening dossier
			# (mouse focus keeps routing the release here, past the menu's
			# click-away catcher).
			if not _left_down and not _dragging:
				_hide_tooltip()
				_tooltip_suppressed = true
				_right_press(mouse_event.position)
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_hide_tooltip()
				_tooltip_suppressed = true
				if mouse_event.double_click:
					# The second press of a double-click only centers — its
					# own first press's release already delivered the click,
					# and one camera gesture must never issue two orders.
					_center_on_pick(mouse_event.position)
				else:
					_left_down = true
					_left_dragged = false
					_press_at = mouse_event.position
			else:
				# The click rides on the release: a press that travelled was
				# a pan, and must not order anything when it lets go. The hit
				# is taken at the PRESS point — the sub-threshold tolerance
				# forgives a wobbling hand, so the wobble must never re-aim
				# the click across a border.
				var was_click := _left_down and not _left_dragged
				_left_down = false
				_left_dragged = false
				if was_click:
					_emit_select(_press_at)
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


func _emit_select(screen_point: Vector2) -> void:
	var hit := _pick(screen_point)
	match String(hit["kind"]):
		"army", "fleet":
			force_clicked.emit(hit["kind"], hit["id"])
		"more":
			# The overflow chip stands for its anchor: the panel lists everyone.
			if game.data.regions.has(hit["id"]):
				region_clicked.emit(hit["id"])
			else:
				sea_zone_clicked.emit(hit["id"])
		"region":
			region_clicked.emit(hit["id"])
		"zone":
			sea_zone_clicked.emit(hit["id"])
		_:
			background_clicked.emit()


func _right_press(screen_point: Vector2) -> void:
	var hit := _pick(screen_point)
	var kind := String(hit["kind"])
	if selected_force != "":
		match kind:
			"army", "fleet", "region", "zone":
				order_target.emit(kind, hit["id"], Input.is_key_pressed(KEY_SHIFT))
			"more":
				order_target.emit("region" if game.data.regions.has(hit["id"]) else "zone",
					hit["id"], Input.is_key_pressed(KEY_SHIFT))
		return
	match kind:
		"region":
			region_context_requested.emit(hit["id"])
		"army":
			region_context_requested.emit(game.state["armies"][hit["id"]]["region"])
		"more":
			if game.data.regions.has(hit["id"]):
				region_context_requested.emit(hit["id"])


func _center_on_pick(screen_point: Vector2) -> void:
	var hit := _pick(screen_point)
	match String(hit["kind"]):
		"army":
			center_on(game.state["armies"][hit["id"]]["region"])
		"fleet":
			center_on_zone(game.state["fleets"][hit["id"]]["sea_zone"])
		"region":
			center_on(hit["id"])
		"zone":
			center_on_zone(hit["id"])
		"more":
			if game.data.regions.has(hit["id"]):
				center_on(hit["id"])
			else:
				center_on_zone(hit["id"])


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


func _camera_button(text: String, tooltip_text_value: String, font_size: int, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip_text_value
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


## --- Picking ------------------------------------------------------------------

func _pick(screen_point: Vector2) -> Dictionary:
	## Front to back: banners and chips (they sit inside the token's pick
	## radius, so they must win), then territory, then sea anchors.
	## Returns {kind: "army"|"fleet"|"more"|"region"|"zone"|"", id}.
	if game == null:
		return {"kind": "", "id": ""}
	var entries := banner_layout()
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if (entry["rect"] as Rect2).grow(2.0 * _zoom).has_point(screen_point):
			return {"kind": entry["kind"], "id": entry["id"]}
	var region := _region_at(screen_point)
	if region != "":
		return {"kind": "region", "id": region}
	var zone := _sea_zone_at(screen_point)
	if zone != "":
		return {"kind": "zone", "id": zone}
	return {"kind": "", "id": ""}


func _sea_zone_at(screen_point: Vector2) -> String:
	## Nearest sea-zone anchor within reach — clicking open water near a sea
	## name addresses that sea (fleet orders).
	if game == null:
		return ""
	var best := ""
	var best_distance := ZONE_PICK_RADIUS * _zoom
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


## --- Banner layout ---------------------------------------------------------------

func banner_layout() -> Array:
	## Every banner and overflow chip on screen as
	## {kind: "army"|"fleet"|"more", id, rect: Rect2 (screen), anchor, summary}.
	## One function feeds both drawing and picking, so the two cannot disagree
	## and picking survives zoom and pan by construction. Re-laid only when the
	## camera or the cached state moved.
	if game == null or _zoom < COMPACT_ZOOM:
		return []
	if not _state_fresh:
		refresh_state()
	var camera := Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _camera_offset * _zoom)
	if not _banner_dirty and camera == _banner_camera:
		return _banner_entries
	_banner_dirty = false
	_banner_camera = camera
	var entries: Array = []
	var player := String(game.state["player_faction"])

	var region_ids: Array = visible_cache.keys()
	region_ids.sort()
	for region_id in region_ids:
		if not game.data.regions.has(region_id):
			continue
		var armies := _ordered_forces(ForceRules.armies_in(game.state, region_id), player)
		if armies.is_empty():
			continue
		var anchor := to_screen(world_pos(game.data.regions[region_id]) + Vector2(22.0, -30.0))
		_place_row(entries, "army", armies, region_id, anchor)

	var zone_ids: Array = visible_zones.keys()
	zone_ids.sort()
	for zone_id in zone_ids:
		if not game.data.sea_zones.has(zone_id):
			continue
		var fleets := _ordered_forces(ForceRules.fleets_in(game.state, zone_id), player)
		if fleets.is_empty():
			continue
		var shown := mini(fleets.size(), MAX_SLOTS)
		var origin := to_screen(zone_world_pos(game.data.sea_zones[zone_id])) \
			+ Vector2(-(shown * SLOT_PITCH - 2.0) / 2.0, 4.0) * _zoom
		_place_row(entries, "fleet", fleets, zone_id, origin)
	_banner_entries = entries
	return entries


func _place_row(entries: Array, kind: String, ids: Array, anchor: String, origin: Vector2) -> void:
	var count := ids.size()
	var shown := count if count <= MAX_SLOTS else MAX_SLOTS - 1
	var size_px := Vector2(BANNER_W, BANNER_H + BAR_H + 1.0) * _zoom
	for i in range(shown):
		var force_id: String = ids[i]
		if not force_summaries.has(force_id):
			force_summaries[force_id] = game.force_summary(force_id)
		var rect := Rect2(origin + Vector2(i * SLOT_PITCH * _zoom, 0.0), size_px)
		entries.append({"kind": kind, "id": force_id, "rect": rect, "anchor": anchor,
			"summary": force_summaries[force_id]})
	if count > MAX_SLOTS:
		var rect := Rect2(origin + Vector2(shown * SLOT_PITCH * _zoom, 0.0), Vector2(BANNER_W, BANNER_H) * _zoom)
		entries.append({"kind": "more", "id": anchor, "rect": rect, "anchor": anchor,
			"summary": {"count": count - shown}})


func _ordered_forces(ids: Array, player: String) -> Array:
	## The player's own forces first (nearest the token), then allies and
	## protectorates, then everyone else by owner; numeric id order within.
	var ranked: Array = []
	for force_id in ids:
		var owner := ForceRules.owner_of(game.state, force_id)
		var group := 2
		if owner == player:
			group = 0
		elif DiplomacyRules.stance_between(game.state, player, owner) in ["alliance", "protectorate"]:
			group = 1
		ranked.append({"id": force_id, "group": group, "owner": owner})
	ranked.sort_custom(func(a, b):
		if a["group"] != b["group"]:
			return a["group"] < b["group"]
		if a["owner"] != b["owner"]:
			return a["owner"] < b["owner"]
		return ForceRules.id_less(a["id"], b["id"]))
	var ordered: Array = []
	for entry in ranked:
		ordered.append(entry["id"])
	return ordered


func banner_tooltip(summary: Dictionary) -> String:
	var who := "Fleet"
	if summary["kind"] == "army":
		who = "Captain's army"
		if summary["general"] != null:
			who = String(summary["general"]["name"])
	var owner_name: String = game.data.factions.get(summary["owner"], {}).get("name", summary["owner"])
	var line := "[b]%s[/b] (%s)\n%d units · %d men (%d%%) · %.2f movement" % [who, owner_name,
		int(summary["units"]), int(summary["soldiers"]), int(summary["strength_pct"]),
		float(summary["movement_left"])]
	if summary["besieging"] != null:
		line += "\nbesieging %s" % game.data.regions.get(summary["besieging"], {}).get("settlement_name", summary["besieging"])
	if bool(summary["forced_march"]):
		line += "\nfatigued"
	if summary["owner"] == game.state["player_faction"]:
		if summary["kind"] == "army":
			line += "\n[i]left-click to select, right-click a ringed province to order[/i]"
		else:
			line += "\n[i]left-click to select, right-click a ringed sea to sail or your port to dock[/i]"
	return line


func draw_banner(canvas: CanvasItem, entry: Dictionary) -> void:
	var rect: Rect2 = entry["rect"]
	var z := _zoom
	if entry["kind"] == "more":
		canvas.draw_rect(rect, BANNER_BG)
		canvas.draw_rect(rect, BANNER_OUTLINE, false, 1.0 * z)
		if _font != null:
			canvas.draw_string(_font, rect.position + Vector2(0.0, rect.size.y * 0.72),
				"+%d" % int(entry["summary"]["count"]),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, maxi(int(9.0 * z), 6), Color.WHITE)
		return

	var summary: Dictionary = entry["summary"]
	var frame := Rect2(rect.position, Vector2(BANNER_W, BANNER_H) * z)
	var shadow := frame.grow(1.0 * z)
	shadow.position += Vector2(1.0, 1.5) * z
	canvas.draw_rect(shadow, Color(0, 0, 0, 0.35))
	canvas.draw_rect(frame, BANNER_BG)

	# Fill from the bottom: units out of the cap, in the owner's colour;
	# dimmed once the force has spent its movement for the season.
	var owner_color := Color.html(game.data.factions.get(summary["owner"], {}).get("color", "#808080"))
	if float(summary["movement_left"]) <= 0.0001:
		owner_color.a = 0.55
	var inner_h := BANNER_H - 2.0
	var fill_h := ceilf(inner_h * float(summary["fill"]))
	if fill_h > 0.0:
		canvas.draw_rect(Rect2(frame.position + Vector2(1.0, 1.0 + inner_h - fill_h) * z,
			Vector2(BANNER_W - 2.0, fill_h) * z), owner_color)

	# Strength bar beneath: how many of the men are still standing.
	var bar_origin := frame.position + Vector2(0.0, BANNER_H + 1.0) * z
	canvas.draw_rect(Rect2(bar_origin, Vector2(BANNER_W, BAR_H) * z), BAR_BG)
	var strength := clampf(float(summary["strength_pct"]) / 100.0, 0.0, 1.0)
	if strength > 0.0:
		canvas.draw_rect(Rect2(bar_origin, Vector2(roundf(BANNER_W * strength), BAR_H) * z),
			BAR_LOW.lerp(BAR_FULL, strength))

	# State outline: besieging (red) beats fatigued (orange) beats plain.
	var outline := BANNER_OUTLINE
	var width := 1.0
	if summary["besieging"] != null:
		outline = UiStyle.SIEGE_RED
		width = 2.0
	elif bool(summary["forced_march"]):
		outline = FATIGUE_COLOR
		width = 1.5
	canvas.draw_rect(frame, outline, false, width * z)

	if entry["kind"] == "army":
		if summary["general"] != null:
			var finial := frame.position + Vector2(BANNER_W / 2.0, -3.0) * z
			canvas.draw_circle(finial, 3.0 * z, FINIAL_COLOR)
			if bool(summary["general"]["is_leader"]):
				canvas.draw_arc(finial, 4.0 * z, 0, TAU, 16, Color.WHITE, 1.0 * z)
	else:
		var p := frame.position
		canvas.draw_colored_polygon(PackedVector2Array([
			p + Vector2(2.0, -1.0) * z, p + Vector2(BANNER_W - 2.0, -1.0) * z, p + Vector2(BANNER_W / 2.0, -6.0) * z,
		]), SAIL_COLOR)

	if entry["id"] == selected_force:
		canvas.draw_rect(frame.grow(2.0 * z), UiStyle.SELECTION, false, 2.0 * z)
	elif entry["id"] == hover_force:
		canvas.draw_rect(frame.grow(2.0 * z), Color(1, 1, 1, 0.6), false, 1.0 * z)


## --- Hover and tooltips ---------------------------------------------------------

func _update_hover(screen_point: Vector2) -> void:
	_mouse_at = screen_point
	_tooltip_suppressed = false  # real mouse motion re-arms the tooltip
	var hit := _pick(screen_point)
	var kind := String(hit["kind"])
	var force := String(hit["id"]) if kind in ["army", "fleet", "more"] else ""
	var region := String(hit["id"]) if kind == "region" else ""
	_set_cursor(Control.CURSOR_POINTING_HAND if (region != "" or force != "") else Control.CURSOR_ARROW)
	if force != hover_force:
		hover_force = force
		_hover_time = 0.0
		_hide_tooltip()
		if _banner_layer != null:
			_banner_layer.queue_redraw()
	if region == hover_region:
		return
	hover_region = region
	_hover_time = 0.0
	_hide_tooltip()
	if _overlay_layer != null:
		_overlay_layer.queue_redraw()
	region_hovered.emit(region)


func _clear_hover() -> void:
	if hover_force != "":
		hover_force = ""
		if _banner_layer != null:
			_banner_layer.queue_redraw()
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


func _tooltip_text() -> String:
	if hover_force != "":
		for entry in banner_layout():
			if entry["id"] == hover_force:
				if entry["kind"] == "more":
					if game.data.regions.has(entry["anchor"]):
						return "%d more forces here — click for the province's list" % int(entry["summary"]["count"])
					return "%d more fleets here — click the sea to take the helm of your next one" % int(entry["summary"]["count"])
				return banner_tooltip(entry["summary"])
		return ""
	if tooltip_provider.is_valid():
		return String(tooltip_provider.call(hover_region))
	return ""


func _show_tooltip() -> void:
	var text := _tooltip_text()
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
		if _banner_layer != null:
			_banner_layer.queue_redraw()
