class_name MapView
extends Control
## The campaign map: regions drawn at their geographic positions as
## owner-colored settlement tokens joined by adjacency roads, a BANNER for
## every army and fleet (its fill is the stack size out of the cap, the bar
## beneath is the men's strength, a finial marks a general), siege rings,
## sea-zone anchors and fog of war.
##
## Input contract: left-click SELECTS (a banner, a token or a sea anchor),
## right-click without dragging ORDERS, right/middle drag pans, wheel zooms.
## The screen decides what an order means; the map only reports what was hit.

signal region_clicked(region_id: String)
signal force_clicked(kind: String, id: String)   # left-click on an army or fleet banner
signal zone_clicked(zone_id: String)             # left-click on a sea-zone anchor
signal order_target(kind: String, id: String, forced: bool)   # right-click, no drag: kind in army/fleet/region/zone; Shift = forced
signal background_clicked()                     # left-click on open sea

const WORLD_SCALE := 14.0
const SEA_COLOR := Color(0.10, 0.17, 0.24)
const LAND_EDGE_COLOR := Color(0.45, 0.38, 0.28, 0.5)
const SEA_EDGE_COLOR := Color(0.25, 0.42, 0.55, 0.35)
const FOG_COLOR := Color(0.16, 0.16, 0.18)
const FOG_OUTLINE := Color(0.28, 0.28, 0.30)
const SIEGE_COLOR := Color(0.9, 0.25, 0.15)
const ZONE_MARK_COLOR := Color(0.4, 0.6, 0.8, 0.5)
const ZONE_LABEL_COLOR := Color(0.55, 0.70, 0.85, 0.7)

# Banner geometry at zoom 1 (everything scales with _zoom).
const BANNER_W := 12.0
const BANNER_H := 20.0
const BAR_H := 2.0
const SLOT_PITCH := 14.0
const MAX_SLOTS := 4              # beyond this a "+N" chip stands in the last slot
const COMPACT_ZOOM := 0.6         # below this banners give way to owner badges
const DRAG_THRESHOLD_PX := 4.0    # a right-click that moves less than this is a click
const ZONE_PICK_RADIUS := 18.0
const BANNER_BG := Color(0.10, 0.10, 0.12, 0.92)
const BANNER_OUTLINE := Color(0, 0, 0, 0.8)
const FATIGUE_COLOR := Color(0.95, 0.60, 0.20)
const FINIAL_COLOR := Color(1.0, 0.85, 0.35)
const SAIL_COLOR := Color(0.95, 0.95, 0.95)
const BAR_BG := Color(0.15, 0.15, 0.17)
const BAR_LOW := Color(0.85, 0.25, 0.20)
const BAR_FULL := Color(0.35, 0.80, 0.35)

const HIGHLIGHT_COLORS := {
	"march": Color(1, 1, 0.5, 0.8),
	"forced": Color(1.0, 0.6, 0.2, 0.8),
	"attack": Color(0.95, 0.3, 0.25, 0.9),
	"siege": Color(0.95, 0.3, 0.25, 0.9),
	"sail": Color(0.4, 0.8, 1.0, 0.8),
	"land": Color(0.4, 0.8, 1.0, 0.8),
}

var game: Game
var selected_region := ""
var selected_force := ""                 # army or fleet id
var highlight_regions: Dictionary = {}   # region_id -> kind (see HIGHLIGHT_COLORS) or true
var highlight_zones: Dictionary = {}     # zone_id -> kind

var _camera_offset := Vector2(-200, -200)
var _zoom := 1.0
var _dragging := false
var _drag_button := 0
var _drag_moved := false
var _press_pos := Vector2.ZERO
var _font: Font
var _edges: Array = []                   # [[region_a, region_b, is_land], ...] built once per map
var _edges_for := 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()


## --- Coordinates ----------------------------------------------------------

func world_pos(region: Dictionary) -> Vector2:
	var position_data: Dictionary = region.get("position", {"x": 50, "y": 50})
	return Vector2(float(position_data["x"]), float(position_data["y"])) * WORLD_SCALE


func zone_world_pos(zone: Dictionary) -> Vector2:
	## Sea zones carry an authored anchor; a zone without one sits at the
	## centroid of its coastal regions.
	if zone.has("position"):
		return world_pos(zone)
	var total := Vector2.ZERO
	var count := 0
	if game != null:
		for region in game.data.regions.values():
			if region.get("sea_zones", []).has(zone["id"]):
				total += world_pos(region)
				count += 1
	return total / float(maxi(count, 1))


func to_screen(world: Vector2) -> Vector2:
	return (world + _camera_offset) * _zoom


func center_on(region_id: String) -> void:
	if game == null or not game.data.regions.has(region_id):
		return
	_center_world(world_pos(game.data.regions[region_id]))


func center_on_zone(zone_id: String) -> void:
	if game == null or not game.data.sea_zones.has(zone_id):
		return
	_center_world(zone_world_pos(game.data.sea_zones[zone_id]))


func _center_world(world: Vector2) -> void:
	_camera_offset = -world + size / (2.0 * _zoom)
	queue_redraw()


## --- Input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mouse_event.pressed:
					_zoom_at(mouse_event.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mouse_event.pressed:
					_zoom_at(mouse_event.position, 1.0 / 1.15)
			MOUSE_BUTTON_MIDDLE:
				_dragging = mouse_event.pressed
				_drag_button = MOUSE_BUTTON_MIDDLE
			MOUSE_BUTTON_RIGHT:
				if mouse_event.pressed:
					_dragging = true
					_drag_moved = false
					_drag_button = MOUSE_BUTTON_RIGHT
					_press_pos = mouse_event.position
				else:
					_dragging = false
					if not _drag_moved:
						_emit_order(mouse_event.position)
			MOUSE_BUTTON_LEFT:
				if mouse_event.pressed:
					if mouse_event.double_click:
						_center_on_pick(mouse_event.position)
					else:
						_emit_select(mouse_event.position)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		if _drag_button == MOUSE_BUTTON_RIGHT and not _drag_moved \
				and motion.position.distance_to(_press_pos) < DRAG_THRESHOLD_PX:
			return  # a steady hand still gets a click
		_drag_moved = true
		_camera_offset += motion.relative / _zoom
		queue_redraw()


func _emit_select(screen_point: Vector2) -> void:
	var hit := _pick(screen_point)
	match hit["kind"]:
		"":
			background_clicked.emit()
		"army", "fleet":
			force_clicked.emit(hit["kind"], hit["id"])
		"more":
			# The overflow chip stands for its anchor: the panel lists everyone.
			if game.data.regions.has(hit["id"]):
				region_clicked.emit(hit["id"])
			else:
				zone_clicked.emit(hit["id"])
		"region":
			region_clicked.emit(hit["id"])
		"zone":
			zone_clicked.emit(hit["id"])


func _emit_order(screen_point: Vector2) -> void:
	var hit := _pick(screen_point)
	var forced := Input.is_key_pressed(KEY_SHIFT)
	match hit["kind"]:
		"army", "fleet", "region", "zone":
			order_target.emit(hit["kind"], hit["id"], forced)
		"more":
			order_target.emit("region" if game.data.regions.has(hit["id"]) else "zone", hit["id"], forced)


func _center_on_pick(screen_point: Vector2) -> void:
	var hit := _pick(screen_point)
	match hit["kind"]:
		"army":
			center_on(game.state["armies"][hit["id"]]["region"])
		"fleet":
			center_on_zone(game.state["fleets"][hit["id"]]["sea_zone"])
		"region", "more":
			if game.data.regions.has(hit["id"]):
				center_on(hit["id"])
			else:
				center_on_zone(hit["id"])
		"zone":
			center_on_zone(hit["id"])


func _get_tooltip(at_position: Vector2) -> String:
	if game == null:
		return ""
	var entries := _layout_banners()
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if not (entry["rect"] as Rect2).grow(2.0 * _zoom).has_point(at_position):
			continue
		if entry["kind"] == "more":
			return "%d more forces here" % int(entry["summary"]["count"])
		return banner_tooltip(entry["summary"])
	return ""


func banner_tooltip(summary: Dictionary) -> String:
	var who := "Fleet"
	if summary["kind"] == "army":
		who = "Captain's army"
		if summary["general"] != null:
			who = String(summary["general"]["name"])
	var owner_name: String = game.data.factions.get(summary["owner"], {}).get("name", summary["owner"])
	return "%s (%s) — %d units · %d men (%d%%) · %.2f mp" % [who, owner_name,
		int(summary["units"]), int(summary["soldiers"]), int(summary["strength_pct"]),
		float(summary["movement_left"])]


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := screen_point / _zoom - _camera_offset
	_zoom = clampf(_zoom * factor, 0.35, 3.0)
	_camera_offset = screen_point / _zoom - before
	queue_redraw()


## --- Picking ----------------------------------------------------------------

func _pick(screen_point: Vector2) -> Dictionary:
	## Front to back: banners and chips (they sit inside the token's pick
	## radius, so they must win), then tokens, then sea anchors.
	## Returns {kind: "army"|"fleet"|"more"|"region"|"zone"|"", id}.
	if game == null:
		return {"kind": "", "id": ""}
	var entries := _layout_banners()
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if (entry["rect"] as Rect2).grow(2.0 * _zoom).has_point(screen_point):
			return {"kind": entry["kind"], "id": entry["id"]}
	var region := _region_at(screen_point)
	if region != "":
		return {"kind": "region", "id": region}
	var zone := _zone_at(screen_point)
	if zone != "":
		return {"kind": "zone", "id": zone}
	return {"kind": "", "id": ""}


func _force_at(screen_point: Vector2) -> String:
	var hit := _pick(screen_point)
	return hit["id"] if hit["kind"] in ["army", "fleet"] else ""


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


func _zone_at(screen_point: Vector2) -> String:
	if game == null:
		return ""
	var best := ""
	var best_distance := ZONE_PICK_RADIUS * _zoom
	for zone_id in game.data.sea_zones:
		var distance := to_screen(zone_world_pos(game.data.sea_zones[zone_id])).distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best = zone_id
	return best


## --- Banner layout ------------------------------------------------------------

func _layout_banners() -> Array:
	## Every banner and overflow chip on screen as
	## {kind: "army"|"fleet"|"more", id, rect: Rect2 (screen), anchor, summary}.
	## One function feeds both drawing and picking, so the two cannot disagree
	## and picking survives zoom and pan by construction.
	var entries: Array = []
	if game == null or _zoom < COMPACT_ZOOM:
		return entries
	var player := String(game.state["player_faction"])
	var visible_set := game.visible_regions()
	var visible_zones := game.visible_sea_zones()

	var region_ids: Array = game.data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		if not visible_set.has(region_id):
			continue
		var armies := _ordered_forces(ForceRules.armies_in(game.state, region_id), player)
		if armies.is_empty():
			continue
		var region: Dictionary = game.data.regions[region_id]
		var screen := to_screen(world_pos(region))
		var radius := _token_radius(region_id)
		var origin := screen + Vector2(radius + 4.0 * _zoom, -BANNER_H * 0.75 * _zoom)
		_place_row(entries, "army", armies, region_id, origin)

	var zone_ids: Array = game.data.sea_zones.keys()
	zone_ids.sort()
	for zone_id in zone_ids:
		if not visible_zones.has(zone_id):
			continue
		var fleets := _ordered_forces(ForceRules.fleets_in(game.state, zone_id), player)
		if fleets.is_empty():
			continue
		var anchor := to_screen(zone_world_pos(game.data.sea_zones[zone_id]))
		var shown := mini(fleets.size(), MAX_SLOTS)
		var origin := anchor + Vector2(-(shown * SLOT_PITCH - 2.0) / 2.0, -BANNER_H / 2.0) * _zoom
		_place_row(entries, "fleet", fleets, zone_id, origin)
	return entries


func _place_row(entries: Array, kind: String, ids: Array, anchor: String, origin: Vector2) -> void:
	var count := ids.size()
	var shown := count if count <= MAX_SLOTS else MAX_SLOTS - 1
	var size_px := Vector2(BANNER_W, BANNER_H + BAR_H + 1.0) * _zoom
	for i in range(shown):
		var rect := Rect2(origin + Vector2(i * SLOT_PITCH * _zoom, 0.0), size_px)
		entries.append({"kind": kind, "id": ids[i], "rect": rect, "anchor": anchor,
			"summary": game.force_summary(ids[i])})
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


func _token_radius(region_id: String) -> float:
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	var tier := 1
	if not settlement.is_empty():
		tier = Constants.level_index(SettlementRules.settlement_level(game.data, settlement)) + 1
	return (7.0 + 1.8 * tier) * _zoom


## --- Drawing --------------------------------------------------------------------

func _ensure_edges() -> void:
	## The road/sea-lane graph never changes after load: build it once instead
	## of testing every pair of regions on every redraw.
	if _edges_for == game.data.get_instance_id() and not _edges.is_empty():
		return
	_edges.clear()
	_edges_for = game.data.get_instance_id()
	var region_ids: Array = game.data.regions.keys()
	region_ids.sort()
	for i in range(region_ids.size()):
		var region: Dictionary = game.data.regions[region_ids[i]]
		for j in range(i + 1, region_ids.size()):
			var other_id: String = region_ids[j]
			if region.get("adjacent", []).has(other_id):
				_edges.append([region_ids[i], other_id, true])
			elif MapRules.shared_sea_zone(game.data, region_ids[i], other_id) \
					and world_pos(region).distance_to(world_pos(game.data.regions[other_id])) < 220.0:
				_edges.append([region_ids[i], other_id, false])


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA_COLOR)
	if game == null:
		return
	_ensure_edges()
	var visible_set := game.visible_regions()

	for edge in _edges:
		var from := to_screen(world_pos(game.data.regions[edge[0]]))
		var to := to_screen(world_pos(game.data.regions[edge[1]]))
		if edge[2]:
			draw_line(from, to, LAND_EDGE_COLOR, 1.5 * _zoom)
		else:
			draw_dashed_line(from, to, SEA_EDGE_COLOR, 1.0 * _zoom, 8.0 * _zoom)

	_draw_zone_marks()

	for region_id in game.data.regions:
		_draw_region(region_id, visible_set.has(region_id))

	for entry in _layout_banners():
		_draw_banner(entry)


func _draw_zone_marks() -> void:
	## Sea anchors are geography, not intelligence: every zone shows its mark
	## (there must always be something to right-click at sea); the fleets on
	## it are what fog hides.
	for zone_id in game.data.sea_zones:
		var zone: Dictionary = game.data.sea_zones[zone_id]
		var anchor := to_screen(zone_world_pos(zone))
		draw_arc(anchor, 4.0 * _zoom, 0, TAU, 16, ZONE_MARK_COLOR, 1.0 * _zoom)
		if highlight_zones.has(zone_id):
			var kind := String(highlight_zones[zone_id])
			draw_arc(anchor, 14.0 * _zoom, 0, TAU, 24, HIGHLIGHT_COLORS.get(kind, HIGHLIGHT_COLORS["sail"]), 2.0 * _zoom)
		if _zoom >= 0.8 and _font != null:
			var label: String = zone.get("name", zone_id)
			var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
			draw_string(_font, anchor + Vector2(-text_size.x / 2.0, 14.0 * _zoom + 4.0),
				label, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, ZONE_LABEL_COLOR)


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
	var radius := _token_radius(region_id)

	draw_circle(screen, radius, owner_color)
	var outline := Color.WHITE if region_id == selected_region else Color(0, 0, 0, 0.55)
	var outline_width := 3.0 if region_id == selected_region else 1.5
	draw_arc(screen, radius, 0, TAU, 32, outline, outline_width * _zoom)

	if highlight_regions.has(region_id):
		var kind := String(highlight_regions[region_id])
		var color: Color = HIGHLIGHT_COLORS.get(kind, HIGHLIGHT_COLORS["march"])
		var width := 2.5 if kind in ["attack", "siege"] else 2.0
		draw_arc(screen, radius + 4.0 * _zoom, 0, TAU, 32, color, width * _zoom)

	if not settlement.is_empty() and settlement.get("siege") != null:
		draw_arc(screen, radius + 7.0 * _zoom, 0, TAU, 32, SIEGE_COLOR, 2.5 * _zoom)

	if game.state["factions"].get(String(game.state["player_faction"]), {}).get("capital", "") == region_id:
		draw_circle(screen + Vector2(0, -radius - 6.0 * _zoom), 3.0 * _zoom, Color(1, 0.9, 0.4))

	if _zoom < COMPACT_ZOOM:
		_draw_compact_badges(region_id, screen, radius)

	if _zoom >= 0.55 and _font != null:
		var label: String = region.get("settlement_name", region_id)
		var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		draw_string(_font, screen + Vector2(-text_size.x / 2.0, radius + 13.0 * _zoom),
			label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.92, 0.88, 0.78))


func _draw_compact_badges(region_id: String, screen: Vector2, radius: float) -> void:
	## Zoomed far out a banner is a smudge: one square per owner present, with
	## a tick per force along its base.
	var counts := {}
	for army_id in ForceRules.armies_in(game.state, region_id):
		var owner: String = game.state["armies"][army_id]["owner"]
		counts[owner] = int(counts.get(owner, 0)) + 1
	var owner_ids: Array = counts.keys()
	owner_ids.sort()
	var slot := 0
	for army_owner in owner_ids:
		var badge_color := Color.html(game.data.factions.get(army_owner, {}).get("color", "#808080"))
		var badge_pos := screen + Vector2(radius + (4.0 + slot * 11.0) * _zoom, -radius * 0.6)
		draw_rect(Rect2(badge_pos, Vector2(8, 10) * _zoom), badge_color)
		draw_rect(Rect2(badge_pos, Vector2(8, 10) * _zoom), Color(0, 0, 0, 0.6), false, 1.0 * _zoom)
		for tick in range(mini(int(counts[army_owner]), 4)):
			draw_rect(Rect2(badge_pos + Vector2(1.0 + tick * 2.0, 8.0) * _zoom, Vector2(1.0, 2.0) * _zoom), Color(1, 1, 1, 0.8))
		slot += 1


func _draw_banner(entry: Dictionary) -> void:
	var rect: Rect2 = entry["rect"]
	var z := _zoom
	if entry["kind"] == "more":
		draw_rect(rect, BANNER_BG)
		draw_rect(rect, BANNER_OUTLINE, false, 1.0 * z)
		if _font != null:
			draw_string(_font, rect.position + Vector2(0.0, rect.size.y * 0.72), "+%d" % int(entry["summary"]["count"]),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, maxi(int(9.0 * z), 6), Color.WHITE)
		return

	var summary: Dictionary = entry["summary"]
	var frame := Rect2(rect.position, Vector2(BANNER_W, BANNER_H) * z)
	draw_rect(frame, BANNER_BG)

	# Fill from the bottom: units out of the cap, in the owner's colour;
	# dimmed once the force has spent its movement for the season.
	var owner_color := Color.html(game.data.factions.get(summary["owner"], {}).get("color", "#808080"))
	if float(summary["movement_left"]) <= 0.0001:
		owner_color.a = 0.55
	var inner_h := BANNER_H - 2.0
	var fill_h := ceilf(inner_h * float(summary["fill"]))
	if fill_h > 0.0:
		draw_rect(Rect2(frame.position + Vector2(1.0, 1.0 + inner_h - fill_h) * z, Vector2(BANNER_W - 2.0, fill_h) * z), owner_color)

	# Strength bar beneath: how many of the men are still standing.
	var bar_origin := frame.position + Vector2(0.0, BANNER_H + 1.0) * z
	draw_rect(Rect2(bar_origin, Vector2(BANNER_W, BAR_H) * z), BAR_BG)
	var strength := clampf(float(summary["strength_pct"]) / 100.0, 0.0, 1.0)
	if strength > 0.0:
		draw_rect(Rect2(bar_origin, Vector2(roundf(BANNER_W * strength), BAR_H) * z), BAR_LOW.lerp(BAR_FULL, strength))

	# State outline: besieging (red) beats fatigued (orange) beats plain.
	var outline := BANNER_OUTLINE
	var width := 1.0
	if summary["besieging"] != null:
		outline = SIEGE_COLOR
		width = 2.0
	elif bool(summary["forced_march"]):
		outline = FATIGUE_COLOR
		width = 1.5
	draw_rect(frame, outline, false, width * z)

	if entry["kind"] == "army":
		if summary["general"] != null:
			var finial := frame.position + Vector2(BANNER_W / 2.0, -3.0) * z
			draw_circle(finial, 3.0 * z, FINIAL_COLOR)
			if bool(summary["general"]["is_leader"]):
				draw_arc(finial, 4.0 * z, 0, TAU, 16, Color.WHITE, 1.0 * z)
	else:
		var p := frame.position
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(2.0, -1.0) * z, p + Vector2(BANNER_W - 2.0, -1.0) * z, p + Vector2(BANNER_W / 2.0, -6.0) * z,
		]), SAIL_COLOR)

	if entry["id"] == selected_force:
		draw_rect(frame.grow(2.0 * z), Color.WHITE, false, 2.0 * z)
