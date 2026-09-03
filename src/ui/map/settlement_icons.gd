class_name SettlementIcons
## Procedural settlement, army and fleet iconography for the campaign map —
## original vector work, drawn from campaign data: footprint grows with
## settlement level, the wall circuit follows wall_level and culture
## (rounded Roman circuits, round Mediterranean enceintes, jittered tribal
## stockades), a culture finial crowns the skyline, and banners, laurels,
## siege ladders, quays and wonder marks say the rest.
##
## icon_params() is pure data extraction so the headless suite can test it;
## the draw functions take any CanvasItem and world-pixel positions.

const WALL_STONE := Color(0.72, 0.675, 0.60)
const WALL_EDGE := Color(0.28, 0.245, 0.20)
const WALL_WOOD := Color(0.47, 0.36, 0.24)
const HOUSE_PLASTER := Color(0.87, 0.81, 0.70)
const HOUSE_EDGE := Color(0.30, 0.26, 0.21, 0.9)
const ROOF := {
	"roman": Color(0.70, 0.38, 0.25),
	"greek": Color(0.56, 0.52, 0.44),
	"eastern": Color(0.63, 0.54, 0.37),
	"carthaginian": Color(0.62, 0.48, 0.35),
	"egyptian": Color(0.80, 0.71, 0.47),
	"barbarian": Color(0.54, 0.45, 0.28),
	"neutral": Color(0.58, 0.54, 0.46),
}


static func icon_params(game: Game, region_id: String) -> Dictionary:
	## Everything the map needs to draw one settlement, from data alone.
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return {}
	var owner: String = settlement["owner"]
	var region: Dictionary = game.data.regions.get(region_id, {})
	var seaward := Vector2.ZERO
	var zones: Array = region.get("sea_zones", [])
	if not zones.is_empty() and region.has("position"):
		var here := Vector2(float(region["position"]["x"]), float(region["position"]["y"]))
		var best_distance := INF
		for zone_id in zones:
			var anchor: Dictionary = game.data.sea_zones.get(zone_id, {}).get("position", {})
			if anchor.is_empty():
				continue
			var there := Vector2(float(anchor["x"]), float(anchor["y"]))
			if here.distance_to(there) < best_distance:
				best_distance = here.distance_to(there)
				seaward = (there - here).normalized()
	return {
		"owner": owner,
		"owner_color": Color.html(game.data.factions.get(owner, {}).get("color", "#808080")),
		"culture": game.data.culture_of_faction(owner),
		"level": Constants.level_index(SettlementRules.settlement_level(game.data, settlement)) + 1,
		"wall_level": int(SettlementRules.effect_max(game.data, settlement, "wall_level")),
		"port_level": int(SettlementRules.effect_max(game.data, settlement, "port_level")),
		"under_siege": settlement.get("siege") != null,
		"is_capital": game.state["factions"].get(
			String(game.state["player_faction"]), {}).get("capital", "") == region_id,
		"has_wonder": region.has("wonder"),
		"seaward": seaward,
		"region_id": region_id,
	}


static func draw_settlement(canvas: CanvasItem, at: Vector2, p: Dictionary) -> void:
	var level := int(p["level"])
	var radius := 10.0 + 2.3 * level
	var culture: String = p["culture"]
	var roof: Color = ROOF.get(culture, ROOF["neutral"])

	# Grounding shadow and a soft owner-colored plinth.
	canvas.draw_circle(at + Vector2(0, 2.5), radius * 1.12, Color(0, 0, 0, 0.16))
	canvas.draw_circle(at, radius * 1.05, Color(p["owner_color"], 0.35))

	if int(p["port_level"]) > 0 and p["seaward"] != Vector2.ZERO:
		_draw_port(canvas, at, radius, p["seaward"])

	var wall_level := int(p["wall_level"])
	if wall_level > 0:
		_draw_walls(canvas, at, radius, wall_level, culture, String(p["region_id"]))

	_draw_buildings(canvas, at, radius, level, roof, culture)

	# Banner pole on the upper right, pennant in the owner's color.
	var pole_base := at + Vector2(radius * 0.75, -radius * 0.55)
	canvas.draw_line(pole_base, pole_base + Vector2(0, -12), Color(0.22, 0.19, 0.15), 1.6, true)
	var tip := pole_base + Vector2(0, -12)
	canvas.draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(8, 2.6), tip + Vector2(0, 5.2),
	]), p["owner_color"])
	canvas.draw_polyline(PackedVector2Array([
		tip, tip + Vector2(8, 2.6), tip + Vector2(0, 5.2), tip,
	]), Color(0, 0, 0, 0.55), 1.0, true)

	if p["is_capital"]:
		var crown := at + Vector2(0, -radius - 9.0)
		canvas.draw_arc(crown, 5.0, PI * 0.75, PI * 1.65, 10, UiStyle.CAPITAL_GOLD, 2.0, true)
		canvas.draw_arc(crown, 5.0, PI * 1.35, PI * 2.25, 10, UiStyle.CAPITAL_GOLD, 2.0, true)

	if p["under_siege"]:
		for start in [0.15, PI * 0.5 + 0.15, PI + 0.15, PI * 1.5 + 0.15]:
			canvas.draw_arc(at, radius + 6.5, start, start + PI * 0.5 - 0.3, 10,
				UiStyle.SIEGE_RED, 2.4, true)
		var ladder := at + Vector2(-radius - 7.0, -3.0)
		canvas.draw_line(ladder, ladder + Vector2(9, 9), UiStyle.SIEGE_RED, 1.8, true)
		canvas.draw_line(ladder + Vector2(9, 0), ladder + Vector2(0, 9), UiStyle.SIEGE_RED, 1.8, true)

	if p["has_wonder"]:
		var base := at + Vector2(-radius - 6.0, -radius * 0.3)
		canvas.draw_colored_polygon(PackedVector2Array([
			base + Vector2(-3, 6), base + Vector2(3, 6), base + Vector2(0, -8),
		]), UiStyle.CAPITAL_GOLD)
		canvas.draw_circle(base + Vector2(0, -9.5), 1.6, UiStyle.CAPITAL_GOLD)


static func _draw_walls(canvas: CanvasItem, at: Vector2, radius: float,
		wall_level: int, culture: String, region_id: String) -> void:
	var ring := _wall_ring(at, radius, culture, region_id)
	var wood := culture in ["barbarian", "neutral"]
	var stroke := WALL_WOOD if wood else WALL_STONE

	if wall_level == 1:
		# A palisade: radial stakes.
		for i in range(ring.size()):
			var out := (ring[i] - at).normalized()
			canvas.draw_line(ring[i] - out * 1.5, ring[i] + out * 2.5, WALL_WOOD, 1.7, true)
		return

	var closed := PackedVector2Array(ring)
	closed.append(ring[0])
	canvas.draw_polyline(closed, WALL_EDGE, 2.0 + 0.55 * wall_level + 1.6, true)
	canvas.draw_polyline(closed, stroke, 2.0 + 0.55 * wall_level, true)

	if wall_level >= 3:
		var towers := 4 if wall_level == 3 else (6 if wall_level == 4 else 8)
		for i in range(towers):
			var angle := TAU * i / towers - PI / 2.0
			var tower := _ring_point(at, radius, culture, region_id, angle)
			canvas.draw_rect(Rect2(tower - Vector2(2.6, 2.6), Vector2(5.2, 5.2)), stroke)
			canvas.draw_rect(Rect2(tower - Vector2(2.6, 2.6), Vector2(5.2, 5.2)), WALL_EDGE, false, 1.1)
	if wall_level >= 4:
		# Crenellation ticks between towers.
		for i in range(12):
			var angle := TAU * i / 12.0 + 0.13
			var merlon := _ring_point(at, radius, culture, region_id, angle)
			var out := (merlon - at).normalized()
			canvas.draw_line(merlon, merlon + out * 2.2, WALL_EDGE, 1.2, true)
	if wall_level >= 5:
		# Concentric inner ring and a corner keep: the citadel.
		var inner := _wall_ring(at, radius * 0.62, culture, region_id)
		var inner_closed := PackedVector2Array(inner)
		inner_closed.append(inner[0])
		canvas.draw_polyline(inner_closed, stroke, 2.2, true)
		var keep := _ring_point(at, radius * 0.62, culture, region_id, -PI * 0.25)
		canvas.draw_rect(Rect2(keep - Vector2(3.4, 3.4), Vector2(6.8, 6.8)), stroke)
		canvas.draw_rect(Rect2(keep - Vector2(3.4, 3.4), Vector2(6.8, 6.8)), WALL_EDGE, false, 1.2)


static func _wall_ring(at: Vector2, radius: float, culture: String, region_id: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := 20 if culture == "roman" else (16 if culture in ["barbarian", "neutral"] else 24)
	for i in range(count):
		points.append(_ring_point(at, radius, culture, region_id, TAU * i / count - PI / 2.0))
	return points


static func _ring_point(at: Vector2, radius: float, culture: String,
		region_id: String, angle: float) -> Vector2:
	match culture:
		"roman":
			# A rounded-square circuit: radius swells on the diagonals.
			var square := 1.0 + 0.18 * absf(sin(2.0 * angle))
			return at + Vector2(cos(angle), sin(angle)) * radius * square
		"barbarian", "neutral":
			# An irregular stockade, wobble hashed from the region id.
			var step := int(floor(angle / TAU * 16.0)) % 16
			var wobble := 0.86 + 0.26 * UiStyle.jitter(region_id, step)
			return at + Vector2(cos(angle), sin(angle)) * radius * wobble
		_:
			return at + Vector2(cos(angle), sin(angle)) * radius


static func _draw_buildings(canvas: CanvasItem, at: Vector2, radius: float,
		level: int, roof: Color, culture: String) -> void:
	# Houses fill the circuit as the settlement grows.
	var house_spots := [
		Vector2(-0.42, 0.18), Vector2(0.30, 0.28), Vector2(-0.05, 0.42),
		Vector2(0.45, -0.10), Vector2(-0.50, -0.18), Vector2(0.10, -0.05),
	]
	var houses := mini(2 + level - 1, house_spots.size())
	for i in range(houses):
		_house(canvas, at + house_spots[i] * radius, 3.2 + 0.28 * level, roof)

	if level >= 3:
		# The long hall.
		var hall := at + Vector2(-radius * 0.12, -radius * 0.30)
		var hall_size := Vector2(radius * 0.62, radius * 0.30)
		canvas.draw_rect(Rect2(hall - hall_size / 2.0, hall_size), HOUSE_PLASTER)
		canvas.draw_rect(Rect2(hall - hall_size / 2.0, hall_size), HOUSE_EDGE, false, 1.0)
		canvas.draw_colored_polygon(PackedVector2Array([
			hall + Vector2(-hall_size.x / 2.0 - 1.0, -hall_size.y / 2.0),
			hall + Vector2(hall_size.x / 2.0 + 1.0, -hall_size.y / 2.0),
			hall + Vector2(0, -hall_size.y / 2.0 - 3.5 - 0.4 * level),
		]), roof)
	if level >= 4:
		# A watchtower.
		var tower := at + Vector2(radius * 0.35, -radius * 0.42)
		canvas.draw_rect(Rect2(tower - Vector2(1.7, 0), Vector2(3.4, 8.0)), HOUSE_PLASTER)
		canvas.draw_rect(Rect2(tower - Vector2(1.7, 0), Vector2(3.4, 8.0)), HOUSE_EDGE, false, 1.0)
		canvas.draw_rect(Rect2(tower - Vector2(2.6, -0.4), Vector2(5.2, 2.4)), roof)
	if level >= 5:
		_finial(canvas, at + Vector2(0, -radius * 0.62), 1.0 + 0.12 * level, culture, roof)
	elif level >= 2:
		_finial(canvas, at + Vector2(0, -radius * 0.52), 0.8, culture, roof)


static func _house(canvas: CanvasItem, at: Vector2, size: float, roof: Color) -> void:
	canvas.draw_rect(Rect2(at - Vector2(size, size * 0.75), Vector2(size * 2, size * 1.5)), HOUSE_PLASTER)
	canvas.draw_rect(Rect2(at - Vector2(size, size * 0.75), Vector2(size * 2, size * 1.5)), HOUSE_EDGE, false, 0.9)
	canvas.draw_colored_polygon(PackedVector2Array([
		at + Vector2(-size - 0.8, -size * 0.75),
		at + Vector2(size + 0.8, -size * 0.75),
		at + Vector2(0, -size * 1.9),
	]), roof)


static func _finial(canvas: CanvasItem, at: Vector2, scale: float, culture: String, roof: Color) -> void:
	## The culture's signature crowning the skyline.
	match culture:
		"roman":
			var half := 6.0 * scale
			canvas.draw_colored_polygon(PackedVector2Array([
				at + Vector2(-half, 0), at + Vector2(half, 0), at + Vector2(0, -4.5 * scale),
			]), roof)
			canvas.draw_polyline(PackedVector2Array([
				at + Vector2(-half, 0), at + Vector2(half, 0), at + Vector2(0, -4.5 * scale), at + Vector2(-half, 0),
			]), HOUSE_EDGE, 1.1, true)
			for i in range(3):
				var x := -half * 0.6 + i * half * 0.6
				canvas.draw_line(at + Vector2(x, 0.5), at + Vector2(x, 4.0 * scale), HOUSE_EDGE, 1.1, true)
		"greek":
			for x in [-3.0 * scale, 0.0, 3.0 * scale]:
				canvas.draw_line(at + Vector2(x, 0), at + Vector2(x, -6.0 * scale), WALL_STONE, 1.8, true)
			canvas.draw_line(at + Vector2(-4.2 * scale, -6.0 * scale),
				at + Vector2(4.2 * scale, -6.0 * scale), WALL_STONE, 1.8, true)
		"eastern":
			for i in range(3):
				var w := (4.8 - 1.4 * i) * scale
				var y := -2.2 * i * scale
				canvas.draw_rect(Rect2(at + Vector2(-w / 2.0, y - 2.0 * scale), Vector2(w, 2.0 * scale)), roof)
		"carthaginian":
			canvas.draw_arc(at + Vector2(0, -3.0 * scale), 3.4 * scale, PI * 0.15, PI * 0.85 + PI, 12, roof, 1.8, true)
			canvas.draw_circle(at + Vector2(0, -6.6 * scale), 1.5 * scale, roof)
		"egyptian":
			canvas.draw_colored_polygon(PackedVector2Array([
				at + Vector2(-1.6 * scale, 0), at + Vector2(1.6 * scale, 0), at + Vector2(0, -8.0 * scale),
			]), roof)
		"barbarian":
			canvas.draw_line(at + Vector2(-3.5 * scale, 0), at + Vector2(3.5 * scale, -6.0 * scale), WALL_WOOD, 1.8, true)
			canvas.draw_line(at + Vector2(3.5 * scale, 0), at + Vector2(-3.5 * scale, -6.0 * scale), WALL_WOOD, 1.8, true)
		_:
			pass


static func _draw_port(canvas: CanvasItem, at: Vector2, radius: float, seaward: Vector2) -> void:
	var quay := at + seaward * (radius + 4.0)
	var along := Vector2(-seaward.y, seaward.x)
	canvas.draw_line(quay - along * 5.0, quay + along * 5.0, Color(0.35, 0.30, 0.24), 2.2, true)
	canvas.draw_line(quay + seaward * 3.0 - along * 3.0, quay + seaward * 3.0 + along * 3.0,
		Color(0.35, 0.30, 0.24), 1.6, true)
	var hull := quay + seaward * 7.0
	canvas.draw_arc(hull, 3.4, PI * 0.15, PI * 0.85, 8, Color(0.30, 0.25, 0.19), 2.0, true)
	canvas.draw_line(hull + Vector2(0, -0.5), hull + Vector2(0, -5.5), Color(0.30, 0.25, 0.19), 1.3, true)


static func draw_army_token(canvas: CanvasItem, at: Vector2, owner_color: Color,
		unit_count: int, has_general: bool, fatigued: bool, font: Font) -> void:
	## A shield roundel: owner color, dark rim, unit count, a general's star.
	canvas.draw_circle(at + Vector2(0.8, 1.6), 7.6, Color(0, 0, 0, 0.25))
	canvas.draw_circle(at, 7.4, owner_color)
	canvas.draw_arc(at, 7.4, 0, TAU, 20, Color(0.08, 0.07, 0.06, 0.9), 1.7)
	canvas.draw_circle(at, 2.1, Color(0.95, 0.93, 0.88, 0.9))
	if unit_count > 1 and font != null:
		var text := str(unit_count)
		var chip := at + Vector2(4.0, 8.6)
		canvas.draw_circle(chip, 4.6, Color(0.09, 0.09, 0.11, 0.92))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8).x
		canvas.draw_string(font, chip + Vector2(-width / 2.0, 2.8), text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0.97, 0.95, 0.9))
	if has_general:
		_star(canvas, at + Vector2(-5.4, -6.4), 3.4, UiStyle.CAPITAL_GOLD)
	if fatigued:
		canvas.draw_line(at + Vector2(-7.5, 7.5), at + Vector2(-3.5, 9.5), UiStyle.SIEGE_RED, 2.0, true)


static func draw_fleet_token(canvas: CanvasItem, at: Vector2, owner_color: Color,
		ship_count: int, font: Font) -> void:
	## A hull with an owner-colored sail.
	canvas.draw_colored_polygon(PackedVector2Array([
		at + Vector2(-8, 2), at + Vector2(8, 2), at + Vector2(5, 6), at + Vector2(-5, 6),
	]), Color(0.32, 0.26, 0.19))
	canvas.draw_line(at + Vector2(0, 2), at + Vector2(0, -9), Color(0.25, 0.21, 0.16), 1.5, true)
	canvas.draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.8, -9), at + Vector2(7.5, -1.5), at + Vector2(0.8, -1.5),
	]), owner_color)
	canvas.draw_polyline(PackedVector2Array([
		at + Vector2(0.8, -9), at + Vector2(7.5, -1.5), at + Vector2(0.8, -1.5), at + Vector2(0.8, -9),
	]), Color(0, 0, 0, 0.5), 0.9, true)
	if ship_count > 1 and font != null:
		var text := str(ship_count)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8).x
		canvas.draw_string(font, at + Vector2(-width / 2.0, 14.0), text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0.85, 0.90, 0.94))


static func _star(canvas: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var r := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI / 2.0 + TAU * i / 10.0
		points.append(at + Vector2(cos(angle), sin(angle)) * r)
	canvas.draw_colored_polygon(points, color)
