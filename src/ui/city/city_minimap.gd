extends Control
## Compass and site wayfinding use the exact authored world coordinates.
var screen: RomaCityScreen
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_pick)

func _map(p: Array) -> Vector2:
	return size * 0.5 + Vector2(float(p[0]), float(p[1])) * size.x / 180.0

func _draw() -> void:
	draw_style_box(UiStyle._flat(Color(0.06, 0.09, 0.08, 0.93), 4), Rect2(Vector2.ZERO, size))
	if screen == null or screen.player == null:
		return
	for building in screen.layout.get("buildings", []):
		var center := _map(building["position"])
		var footprint := Vector2(building["size"][0], building["size"][1]) * size.x / 180.0
		draw_rect(Rect2(center - footprint * 0.5, footprint), Color("#655f4c"))
	for road in screen.layout.get("roads", []):
		var points: Array = road.get("points", [])
		for i in range(points.size() - 1):
			draw_line(_map(points[i]), _map(points[i+1]), Color("#7e7966"), 2)
	for site in screen.layout.get("sites", []):
		var at := _map(site["position"])
		draw_circle(at, 5, UiStyle.ACCENT if site["id"] == screen.destination else UiStyle.TEXT_DIM)
		var offsets := {"curia": Vector2(-18,-10), "market": Vector2(-29,-10), "barracks": Vector2(-17,-10), "tavern": Vector2(-29,19), "forum": Vector2(7,4), "fountain": Vector2(-14,27)}
		draw_string(ThemeDB.fallback_font, at + offsets.get(site["id"], Vector2(7,4)), screen.w("short_" + String(site["id"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiStyle.TEXT)
	var player_at := _map([screen.player.position.x, screen.player.position.z])
	var facing := Vector2(-sin(screen.player.rotation.y), -cos(screen.player.rotation.y))
	draw_line(player_at, player_at + facing * 11, Color.WHITE, 2)
	draw_circle(player_at, 3, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(8, 16), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.ACCENT)

func _pick(event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.pressed:
		return
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	var selected: Dictionary = {}
	var best := 13.0
	for site in screen.layout.get("sites", []):
		var distance: float = event.position.distance_to(_map(site["position"]))
		if distance < best:
			best = distance
			selected = site
	var point: Vector2 = (event.position - size * 0.5) * 180.0 / size.x
	var building_id := ""
	var site_id := String(selected.get("id", ""))
	for building in screen.layout.get("buildings", []):
		var center := Vector2(building["position"][0], building["position"][1])
		var footprint := Vector2(building["size"][0], building["size"][1])
		if Rect2(center - footprint * 0.5, footprint).has_point(point):
			building_id = String(building["id"])
			if not screen.site_by_id(building_id).is_empty():
				site_id = building_id
			break
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		screen.quick_jump(Vector3(point.x, 0, point.y), site_id, building_id)
	else:
		screen.select_target(building_id, site_id)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			screen.inspect_selection()
	accept_event()
