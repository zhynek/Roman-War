class_name SettlementIcons
extends RefCounted
## Procedural settlement and unit iconography. icon_params is pure (engine
## state in, plain dictionary out) so headless tests can pin it; the draw_*
## functions turn those params into canvas primitives. All cosmetic jitter
## comes from an FNV-1a hash of stable ids — never from state.rng_state.

const CULTURE_ROUND := ["greek", "eastern", "carthaginian", "egyptian"]


static func icon_params(game: Game, region_id: String) -> Dictionary:
	## Everything the map needs to draw one settlement, computed from rules,
	## never guessed: tier from the government chain, walls from built
	## effects, port from built effects on a coastal region.
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return {}
	var owner: String = settlement["owner"]
	var culture: String = game.data.factions.get(owner, {}).get("culture", "neutral")
	var level := Constants.level_index(SettlementRules.settlement_level(game.data, settlement))
	return {
		"region": region_id,
		"owner": owner,
		"culture": culture,
		"level": level,
		"wall_level": int(SettlementRules.effect_max(game.data, settlement, "wall_level")),
		"port": MapRules.coastal(game.data, region_id)
			and SettlementRules.effect_max(game.data, settlement, "port_level") >= 1.0,
		"capital": game.state["factions"].get(owner, {}).get("capital", "") == region_id,
		"player_capital": owner == game.state["player_faction"]
			and game.state["factions"][owner].get("capital", "") == region_id,
		"siege": settlement.get("siege") != null,
		"wonder": game.data.regions.get(region_id, {}).has("wonder"),
	}


static func footprint_radius(level: int, zoom_scale: float = 1.0) -> float:
	## Shared by drawing and picking fallbacks: how much room a settlement
	## icon of a tier occupies.
	return (7.0 + 2.1 * level) * zoom_scale


## --- settlements -----------------------------------------------------------

static func draw_settlement(canvas: CanvasItem, center: Vector2, params: Dictionary,
		owner_color: Color) -> void:
	var level := int(params["level"])
	var radius := footprint_radius(level)
	var seed_hash := _fnv(String(params["region"]))
	var culture := String(params["culture"])

	# Ground pad under the buildings, in the owner's color family.
	var pad := owner_color.darkened(0.25)
	pad.a = 0.9
	canvas.draw_circle(center, radius * 0.92, pad)

	if params["port"]:
		_draw_quay(canvas, center, radius, seed_hash)

	_draw_buildings(canvas, center, radius, level, culture, owner_color, seed_hash)

	var wall_level := int(params["wall_level"])
	if wall_level > 0:
		_draw_walls(canvas, center, radius + 2.0, wall_level, culture, seed_hash)

	if params["siege"]:
		_draw_siege(canvas, center, radius + 5.0, seed_hash)

	if params["wonder"]:
		canvas.draw_circle(center + Vector2(radius * 0.9, -radius * 0.9), 2.6, Color(0.95, 0.85, 0.35))
		canvas.draw_arc(center + Vector2(radius * 0.9, -radius * 0.9), 2.6, 0, TAU, 12, Color(0.4, 0.3, 0.05), 0.8)

	# Banner pole with the owner's colors.
	var pole_base := center + Vector2(-radius * 0.85, radius * 0.15)
	canvas.draw_line(pole_base, pole_base + Vector2(0, -radius - 5.0), Color(0.25, 0.2, 0.15), 1.2)
	var flag_top := pole_base + Vector2(0, -radius - 5.0)
	canvas.draw_colored_polygon(PackedVector2Array([
		flag_top, flag_top + Vector2(6.5, 1.8), flag_top + Vector2(0, 3.8),
	]), owner_color)

	if params["player_capital"]:
		canvas.draw_arc(center, radius + 4.6, 0, TAU, 40, Color(0.95, 0.85, 0.4, 0.9), 1.6)
		canvas.draw_circle(center + Vector2(0, -radius - 7.0), 2.4, Color(1.0, 0.9, 0.4))


static func _draw_buildings(canvas: CanvasItem, center: Vector2, radius: float,
		level: int, culture: String, owner_color: Color, seed_hash: int) -> void:
	var roof := owner_color.lightened(0.35)
	var wall_tint := Color(0.88, 0.84, 0.72)
	if culture == "barbarian":
		wall_tint = Color(0.62, 0.52, 0.38)
	var count := 2 + level
	for i in range(count):
		var angle := TAU * float(i) / float(count) + float(seed_hash % 628) / 100.0
		var distance := radius * (0.28 + 0.34 * float(_fnv_step(seed_hash, i) % 100) / 100.0)
		var spot := center + Vector2.from_angle(angle) * distance
		var half := 1.7 + 0.45 * level
		canvas.draw_rect(Rect2(spot - Vector2(half, half), Vector2(half, half) * 2.0), wall_tint)
		canvas.draw_rect(Rect2(spot - Vector2(half, half), Vector2(half * 2.0, half * 0.8)), roof)
	# Central structure from large_town up, carrying the culture finial.
	if level >= 2:
		var core_half := 2.6 + 0.5 * level
		canvas.draw_rect(Rect2(center - Vector2(core_half, core_half), Vector2(core_half, core_half) * 2.0),
			wall_tint.lightened(0.08))
		_draw_finial(canvas, center + Vector2(0, -core_half), core_half, culture, owner_color)


static func _draw_finial(canvas: CanvasItem, top: Vector2, width: float, culture: String,
		owner_color: Color) -> void:
	var stone := Color(0.8, 0.76, 0.62)
	match culture:
		"roman":
			canvas.draw_colored_polygon(PackedVector2Array([
				top + Vector2(-width, 0), top + Vector2(width, 0), top + Vector2(0, -width * 0.9),
			]), stone)  # pediment
		"greek":
			for i in range(3):
				var x := -width * 0.7 + width * 0.7 * i
				canvas.draw_line(top + Vector2(x, 0), top + Vector2(x, -width * 0.8), stone, 1.1)
			canvas.draw_line(top + Vector2(-width * 0.9, -width * 0.8),
				top + Vector2(width * 0.9, -width * 0.8), stone, 1.1)  # columns
		"eastern":
			canvas.draw_colored_polygon(PackedVector2Array([
				top + Vector2(-width * 0.35, 0), top + Vector2(width * 0.35, 0),
				top + Vector2(0, -width * 1.25),
			]), stone)  # spire
		"carthaginian":
			canvas.draw_arc(top + Vector2(0, -width * 0.45), width * 0.42, PI * 0.15, PI * 1.85, 12, stone, 1.3)  # crescent
		"egyptian":
			canvas.draw_colored_polygon(PackedVector2Array([
				top + Vector2(-width * 0.22, 0), top + Vector2(width * 0.22, 0),
				top + Vector2(0.0, -width * 1.4),
			]), stone.lightened(0.1))  # obelisk
		_:
			canvas.draw_colored_polygon(PackedVector2Array([
				top + Vector2(-width * 0.6, 0), top + Vector2(width * 0.6, 0),
				top + Vector2(0, -width * 0.7),
			]), owner_color.darkened(0.2))  # gable


static func _draw_walls(canvas: CanvasItem, center: Vector2, radius: float, wall_level: int,
		culture: String, seed_hash: int) -> void:
	var stone := Color(0.55, 0.52, 0.46)
	var width := 1.2 + 0.5 * wall_level
	var ring := _wall_ring(center, radius, culture, seed_hash)
	if wall_level == 1:
		# Palisade: tick marks around the circuit, no continuous curtain.
		for i in range(ring.size()):
			if i % 2 == 0:
				var out := (ring[i] - center).normalized()
				canvas.draw_line(ring[i] - out * 1.1, ring[i] + out * 1.1, Color(0.5, 0.4, 0.28), 1.1)
		return
	canvas.draw_polyline(ring + PackedVector2Array([ring[0]]), stone, width)
	if wall_level >= 3:
		var towers := 4 + wall_level
		for i in range(towers):
			var point := ring[int(float(i * ring.size()) / float(towers))]
			canvas.draw_circle(point, 1.5 + 0.3 * wall_level, stone.darkened(0.15))
	if wall_level >= 4:
		var inner := _wall_ring(center, radius * 0.62, culture, seed_hash)
		canvas.draw_polyline(inner + PackedVector2Array([inner[0]]), stone.darkened(0.1), width * 0.7)


static func _wall_ring(center: Vector2, radius: float, culture: String, seed_hash: int) -> PackedVector2Array:
	var ring := PackedVector2Array()
	if culture == "roman":
		# Rounded square circuit.
		var segments := 20
		for i in range(segments):
			var angle := TAU * float(i) / float(segments)
			var direction := Vector2.from_angle(angle)
			var square := maxf(absf(direction.x), absf(direction.y))
			ring.append(center + direction * radius / lerpf(1.0, square, 0.72))
		return ring
	if culture in CULTURE_ROUND:
		var segments := 22
		for i in range(segments):
			ring.append(center + Vector2.from_angle(TAU * float(i) / float(segments)) * radius)
		return ring
	# Tribal: an irregular polygon, jittered by the region hash.
	var segments := 9
	for i in range(segments):
		var wobble := 0.8 + 0.34 * float(_fnv_step(seed_hash, i) % 100) / 100.0
		ring.append(center + Vector2.from_angle(TAU * float(i) / float(segments)) * radius * wobble)
	return ring


static func _draw_quay(canvas: CanvasItem, center: Vector2, radius: float, seed_hash: int) -> void:
	var seaward := Vector2.from_angle(TAU * float(seed_hash % 360) / 360.0)
	var quay_base := center + seaward * (radius + 1.0)
	var along := seaward.orthogonal()
	canvas.draw_colored_polygon(PackedVector2Array([
		quay_base + along * 3.2, quay_base - along * 3.2,
		quay_base - along * 3.2 + seaward * 4.6, quay_base + along * 3.2 + seaward * 4.6,
	]), Color(0.5, 0.42, 0.3))


static func _draw_siege(canvas: CanvasItem, center: Vector2, radius: float, seed_hash: int) -> void:
	canvas.draw_arc(center, radius, 0, TAU, 36, Color(0.9, 0.25, 0.15, 0.9), 2.2)
	for i in range(3):
		var angle := TAU * float(i) / 3.0 + float(seed_hash % 100) / 50.0
		var foot := center + Vector2.from_angle(angle) * (radius + 1.0)
		var head := center + Vector2.from_angle(angle) * (radius - 3.4)
		canvas.draw_line(foot, head, Color(0.75, 0.6, 0.4), 1.4)
		canvas.draw_line(foot + Vector2(1.4, 0), head + Vector2(1.4, 0), Color(0.75, 0.6, 0.4), 1.4)


## --- units -----------------------------------------------------------------

static func draw_army_token(canvas: CanvasItem, position: Vector2, color: Color, unit_count: int,
		has_general: bool, fatigued: bool, font: Font) -> void:
	## A shield roundel carrying its unit count — the number the old map
	## computed and dropped.
	canvas.draw_circle(position, 7.2, color.darkened(0.35))
	canvas.draw_circle(position, 6.2, color)
	canvas.draw_arc(position, 6.2, 0, TAU, 20, Color(0, 0, 0, 0.55), 1.1)
	canvas.draw_line(position + Vector2(-4.4, 0), position + Vector2(4.4, 0), color.darkened(0.4), 1.0)
	if font != null:
		var text := str(mini(unit_count, 99))
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
		canvas.draw_string(font, position + Vector2(-text_size.x / 2.0, 3.2), text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 9, _contrast_ink(color))
	if has_general:
		_draw_star(canvas, position + Vector2(0, -9.0), 3.0, Color(0.98, 0.9, 0.45))
	if fatigued:
		canvas.draw_rect(Rect2(position + Vector2(-2.4, 8.0), Vector2(4.8, 1.6)), Color(0.85, 0.3, 0.2))


static func draw_fleet_token(canvas: CanvasItem, position: Vector2, color: Color, ship_count: int,
		font: Font) -> void:
	## A hull-and-sail silhouette on open water.
	canvas.draw_colored_polygon(PackedVector2Array([
		position + Vector2(-6.5, 2.0), position + Vector2(6.5, 2.0),
		position + Vector2(4.0, 5.2), position + Vector2(-4.0, 5.2),
	]), color.darkened(0.25))
	canvas.draw_colored_polygon(PackedVector2Array([
		position + Vector2(0.6, 1.2), position + Vector2(0.6, -6.8), position + Vector2(5.6, -1.2),
	]), Color(0.92, 0.88, 0.78))
	canvas.draw_line(position + Vector2(0.6, 2.0), position + Vector2(0.6, -6.8), color.darkened(0.4), 1.0)
	if font != null:
		var text := str(mini(ship_count, 99))
		canvas.draw_string(font, position + Vector2(-8.6 - 3.0 * text.length(), 4.0), text,
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(0.9, 0.92, 0.95))


static func _draw_star(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 10.0) * r)
	canvas.draw_colored_polygon(points, color)


static func _contrast_ink(background: Color) -> Color:
	return Color(0.08, 0.08, 0.1) if background.get_luminance() > 0.5 else Color(0.95, 0.94, 0.9)


static func _fnv(text: String) -> int:
	## FNV-1a over the id's bytes: the one sanctioned source of UI jitter.
	var hash_value := 2166136261
	for byte in text.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * 16777619) & 0xFFFFFFFF
	return hash_value


static func _fnv_step(seed_hash: int, step: int) -> int:
	return ((seed_hash ^ (step * 2654435761)) * 16777619) & 0xFFFFFFFF
