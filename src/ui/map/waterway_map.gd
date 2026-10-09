class_name WaterwayMap
## Procedural map overlays. Drawing and picking share fleet_screen_position;
## interpolation never writes campaign state or consumes movement/RNG.

static func draw(canvas: CanvasItem, view: MapView) -> void:
	var data := view.game.data
	for link in data.waterways.get("links", []):
		if link["kind"] != "river" or not (view.visible_zones.has(link["a"]) or view.visible_zones.has(link["b"])):
			continue
		var a := view.to_screen(view.zone_world_pos(data.sea_zones[link["a"]]))
		var b := view.to_screen(view.zone_world_pos(data.sea_zones[link["b"]]))
		canvas.draw_line(a, b, Color(0.05, 0.17, 0.20, 0.85), 7, true)
		canvas.draw_line(a, b, Color(0.27, 0.66, 0.72, 0.9), 3, true)
	for node in data.waterways.get("river_nodes", []):
		if not view.visible_zones.has(node["id"]):
			continue
		var at := view.to_screen(view.zone_world_pos(data.sea_zones[node["id"]]))
		canvas.draw_circle(at, 5, Color(0.65, 0.92, 0.95))
	for region in view.game.state.get("waterworks", {}).get("landings", {}):
		if view.visible_cache.has(region):
			var at := view.to_screen(view.world_pos(data.regions[region])) + Vector2(-18, 18)
			canvas.draw_line(at, at + Vector2(14, 0), UiStyle.CAPITAL_GOLD, 4, true)
			canvas.draw_line(at + Vector2(3, -4), at + Vector2(3, 7), UiStyle.CAPITAL_GOLD, 2, true)
			canvas.draw_line(at + Vector2(11, -4), at + Vector2(11, 7), UiStyle.CAPITAL_GOLD, 2, true)
	for key in view.game.state.get("waterworks", {}).get("bridges", {}):
		var ends := String(key).split("|")
		if not view.known_cache.has(ends[0]) or not view.known_cache.has(ends[1]):
			continue
		var at := view.to_screen((view.world_pos(data.regions[ends[0]]) + view.world_pos(data.regions[ends[1]])) * 0.5)
		canvas.draw_line(at + Vector2(-12, -3), at + Vector2(12, -3), UiStyle.CAPITAL_GOLD, 3, true)
		canvas.draw_line(at + Vector2(-12, 3), at + Vector2(12, 3), UiStyle.CAPITAL_GOLD, 3, true)

	var quote: Dictionary = view.waterway_preview
	var fleet: Dictionary = view.game.state["fleets"].get(view.selected_force, {})
	if quote.is_empty() and not fleet.is_empty():
		quote = {"from": fleet["sea_zone"], "path": fleet.get("sail_path", [])}
	var previous: String = quote.get("from", "")
	for i in range(quote.get("path", []).size()):
		var next: String = quote["path"][i]
		if not data.sea_zones.has(previous) or not data.sea_zones.has(next):
			break
		var a := view.to_screen(view.zone_world_pos(data.sea_zones[previous]))
		var b := view.to_screen(view.zone_world_pos(data.sea_zones[next]))
		canvas.draw_dashed_line(a, b, UiStyle.CAPITAL_GOLD, 2, 9, true)
		if i < quote.get("legs", []).size():
			var leg: Dictionary = quote["legs"][i]
			canvas.draw_string(view.map_font, (a + b) * 0.5 + Vector2(4, -6), "S%d · %.2f" % [leg["turn"], leg["cost"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.CAPITAL_GOLD)
		previous = next
	for id in view.game.state["fleets"]:
		var f: Dictionary = view.game.state["fleets"][id]
		if not view.visible_zones.has(f["sea_zone"]):
			continue
		var at := view.fleet_screen_position(id)
		var color := Color.html(data.factions.get(f["owner"], {}).get("color", "#cccccc"))
		var scale_by := clampf(view._zoom, 0.75, 2)
		if id == view.selected_force:
			canvas.draw_arc(at, 21 * scale_by, 0, TAU, 32, UiStyle.CAPITAL_GOLD, 2, true)
		canvas.draw_set_transform(at, 0, Vector2.ONE * scale_by)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(-18,2),Vector2(18,2),Vector2(10,10),Vector2(-11,10)]), Color("#61472b"))
		canvas.draw_line(Vector2(-15,3),Vector2(14,3),color,3,true)
		canvas.draw_line(Vector2(0,3),Vector2(0,-21),Color("#c0a379"),2,true)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(-2,-21),Vector2(-2,0),Vector2(-15,-2)]), Color("#ece2c0"))
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(2,-19),Vector2(14,-2),Vector2(2,0)]), color.lightened(0.35))
		canvas.draw_set_transform(Vector2.ZERO)
