class_name Illustrations
extends RefCounted
## R1's art source: near-3D procedural vector illustrations — one dimetric
## building composition per building kind, one profile figure per unit class,
## tinted by culture and scaled by tier. Everything is drawn from draw_*
## calls in a 100x100 design space fitted to the rect it is given: zero
## binary assets, byte-stable in git, clean-room by construction.
##
## THE CONTRACT IS THE TWO ENTRY POINTS. Cards and menus call only
## draw_building(canvas, rect, kind, culture, tier) and
## draw_unit(canvas, rect, unit_class, culture); a future raster art source
## replaces these bodies without touching a single call site.

const BUILDING_KINDS := [
	"government", "walls", "barracks", "stables", "archery_range", "naval",
	"siege_workshop", "armoury", "temple", "farms", "market", "mines", "port", "roads",
	"health", "entertainment", "education", "execution",
]
const UNIT_CLASSES := [
	"infantry", "spear", "pike", "missile", "cavalry", "horse_archer",
	"chariot", "elephant", "siege", "ship", "general_bodyguard", "peasant",
]

const VX := Vector2(1.0, -0.5)   # dimetric width axis (right and away)
const VZ := Vector2(-1.0, -0.5)  # dimetric depth axis (left and away)
const VY := Vector2(0.0, -1.0)   # up

const TIMBER := Color(0.44, 0.335, 0.225)
const TIMBER_DARK := Color(0.33, 0.25, 0.17)
const STEEL := Color(0.71, 0.74, 0.77)
const INK := Color(0.15, 0.13, 0.11)
const SKIN := Color(0.80, 0.62, 0.46)
const HORSE := Color(0.38, 0.28, 0.20)
const SHADOW := Color(0.10, 0.09, 0.08, 0.30)
const THATCH := Color(0.70, 0.60, 0.38)
const WATER := Color(0.30, 0.46, 0.56)


static func has_building(kind: String) -> bool:
	return BUILDING_KINDS.has(kind)


static func has_unit(unit_class: String) -> bool:
	return UNIT_CLASSES.has(unit_class)


static func culture_palette(culture: String) -> Dictionary:
	## {primary, stone, roof} — the culture's banner color, its masonry, and
	## its roofing. Barbarian builds in timber and thatch; the Mediterranean
	## cultures in pale stone and tile.
	match culture:
		"roman":
			return {"primary": Color(0.70, 0.21, 0.17), "stone": Color(0.89, 0.85, 0.77), "roof": Color(0.67, 0.35, 0.24)}
		"greek":
			return {"primary": Color(0.26, 0.44, 0.70), "stone": Color(0.91, 0.89, 0.83), "roof": Color(0.64, 0.38, 0.27)}
		"eastern":
			return {"primary": Color(0.53, 0.30, 0.58), "stone": Color(0.84, 0.75, 0.58), "roof": Color(0.42, 0.50, 0.55)}
		"carthaginian":
			return {"primary": Color(0.15, 0.52, 0.52), "stone": Color(0.87, 0.81, 0.66), "roof": Color(0.60, 0.42, 0.28)}
		"egyptian":
			return {"primary": Color(0.83, 0.64, 0.20), "stone": Color(0.92, 0.87, 0.70), "roof": Color(0.85, 0.80, 0.62)}
		"barbarian":
			return {"primary": Color(0.42, 0.52, 0.29), "stone": Color(0.55, 0.44, 0.33), "roof": THATCH}
		_:
			return {"primary": Color(0.55, 0.55, 0.55), "stone": Color(0.74, 0.72, 0.68), "roof": Color(0.55, 0.50, 0.44)}


## --- entry points ----------------------------------------------------------

static func draw_building(canvas: CanvasItem, rect: Rect2, kind: String, culture: String, tier: int = 1) -> void:
	var palette := culture_palette(culture)
	var grow := clampf(0.84 + 0.05 * float(tier), 0.89, 1.12)
	canvas.draw_set_transform_matrix(_fit(rect, grow, Vector2(50, 66)))
	_ellipse(canvas, Vector2(50, 74), 34, 9, SHADOW)
	match kind:
		"government": _government(canvas, palette, tier)
		"walls": _walls(canvas, palette, tier)
		"barracks": _barracks(canvas, palette, tier)
		"stables": _stables(canvas, palette, tier)
		"archery_range": _archery_range(canvas, palette, tier)
		"naval": _naval(canvas, palette, tier)
		"siege_workshop": _siege_workshop(canvas, palette, tier)
		"armoury": _armoury(canvas, palette, tier)
		"temple": _temple(canvas, palette, tier)
		"farms": _farms(canvas, palette, tier)
		"market": _market(canvas, palette, tier)
		"mines": _mines(canvas, palette, tier)
		"port": _port(canvas, palette, tier)
		"roads": _roads(canvas, palette, tier)
		"health": _health(canvas, palette, tier)
		"entertainment": _entertainment(canvas, palette, tier)
		"education": _education(canvas, palette, tier)
		"execution": _execution(canvas, palette, tier)
		_: _iso_box(canvas, Vector2(50, 72), 22, 14, 20, palette["stone"])
	if tier >= 3:
		_banner(canvas, Vector2(20, 72), 34 + 2.0 * tier, palette["primary"])
	canvas.draw_set_transform_matrix(Transform2D())


static func draw_unit(canvas: CanvasItem, rect: Rect2, unit_class: String, culture: String) -> void:
	var palette := culture_palette(culture)
	canvas.draw_set_transform_matrix(_fit(rect, 1.42, Vector2(50, 68)))
	_ellipse(canvas, Vector2(50, 84), 26, 7, SHADOW)
	match unit_class:
		"infantry": _u_infantry(canvas, palette)
		"spear": _u_spear(canvas, palette)
		"pike": _u_pike(canvas, palette)
		"missile": _u_missile(canvas, palette)
		"cavalry": _u_cavalry(canvas, palette)
		"horse_archer": _u_horse_archer(canvas, palette)
		"chariot": _u_chariot(canvas, palette)
		"elephant": _u_elephant(canvas, palette)
		"siege": _u_siege(canvas, palette)
		"ship": _u_ship(canvas, palette)
		"general_bodyguard": _u_bodyguard(canvas, palette)
		"peasant": _u_peasant(canvas, palette)
		_: _man(canvas, Vector2(50, 84), palette, false)
	canvas.draw_set_transform_matrix(Transform2D())


## --- shared geometry -------------------------------------------------------

static func _fit(rect: Rect2, grow: float, pivot: Vector2) -> Transform2D:
	## Map the 100x100 design space into rect (uniform, centered), then scale
	## about a design-space pivot so tiers can swell without escaping.
	var unit := minf(rect.size.x, rect.size.y) / 100.0
	var origin := rect.position + (rect.size - Vector2(100, 100) * unit) / 2.0
	var into_rect := Transform2D(Vector2(unit, 0), Vector2(0, unit), origin)
	var about_pivot := Transform2D(Vector2(grow, 0), Vector2(0, grow), pivot * (1.0 - grow))
	return into_rect * about_pivot


static func _poly(canvas: CanvasItem, points: Array, color: Color) -> void:
	var packed := PackedVector2Array()
	for point in points:
		packed.append(point)
	canvas.draw_colored_polygon(packed, color)


static func _ellipse(canvas: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(22):
		var angle := TAU * float(i) / 22.0
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	canvas.draw_colored_polygon(points, color)


static func _iso_box(canvas: CanvasItem, front: Vector2, w: float, d: float, h: float, tint: Color) -> void:
	## A dimetric cuboid from its bottom-front corner: lit top, lighter left
	## face, darker right face — the three planes that read as volume.
	var up := VY * h
	_poly(canvas, [front, front + VX * w, front + VX * w + up, front + up], tint.darkened(0.16))
	_poly(canvas, [front, front + VZ * d, front + VZ * d + up, front + up], tint.lightened(0.05))
	_poly(canvas, [front + up, front + VX * w + up, front + VX * w + VZ * d + up, front + VZ * d + up],
		tint.lightened(0.24))


static func _gable(canvas: CanvasItem, front: Vector2, w: float, d: float, h: float, rise: float, roof: Color, stone: Color) -> void:
	## A ridged roof over an _iso_box footprint (same front corner): the
	## viewer sees the right slope and the left gable end.
	var top_front := front + VY * h
	var ridge_front := top_front + VZ * (d / 2.0) + VY * rise
	_poly(canvas, [top_front, top_front + VX * w, ridge_front + VX * w, ridge_front], roof)
	_poly(canvas, [top_front, top_front + VZ * d, ridge_front], stone.lightened(0.12))
	canvas.draw_line(ridge_front, ridge_front + VX * w, roof.darkened(0.25), 1.2)


static func _column_row(canvas: CanvasItem, front: Vector2, w: float, h: float, count: int, stone: Color) -> void:
	## Columns along the right-facing front of a podium.
	for i in range(count):
		var at := front + VX * (w * (float(i) + 0.5) / float(count))
		_poly(canvas, [at + Vector2(-1.4, 0), at + Vector2(1.4, 0),
			at + Vector2(1.4, 0) + VY * h, at + Vector2(-1.4, 0) + VY * h], stone.lightened(0.18))
		canvas.draw_line(at + Vector2(-1.4, 0), at + Vector2(-1.4, 0) + VY * h, stone.darkened(0.15), 0.7)


static func _banner(canvas: CanvasItem, foot: Vector2, height: float, primary: Color) -> void:
	canvas.draw_line(foot, foot + VY * height, TIMBER_DARK, 1.3)
	_poly(canvas, [foot + VY * height, foot + VY * height + Vector2(9, 1.4),
		foot + VY * (height - 5.0)], primary)


## --- buildings -------------------------------------------------------------

static func _government(canvas: CanvasItem, p: Dictionary, tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(56, 74), 30, 22, 5, stone.darkened(0.08))       # podium
	_iso_box(canvas, Vector2(53, 71), 24, 16, 17 + tier, stone)              # hall
	_column_row(canvas, Vector2(53, 71), 24, 17 + tier, 4, stone)
	_gable(canvas, Vector2(53, 71), 24, 16, 17 + tier, 7, p["roof"], stone)
	_iso_box(canvas, Vector2(60, 76), 8, 5, 3, stone.lightened(0.05))        # steps


static func _walls(canvas: CanvasItem, p: Dictionary, tier: int) -> void:
	var stone: Color = p["stone"].darkened(0.10)
	var height := 14 + 2 * tier
	_iso_box(canvas, Vector2(78, 70), 2.0, 26, height - 4, stone)            # curtain right
	_iso_box(canvas, Vector2(30, 70), 24, 2.0, height - 4, stone)            # curtain left
	_iso_box(canvas, Vector2(44, 74), 20, 14, height, stone)                 # gatehouse
	_poly(canvas, [Vector2(50, 74), Vector2(58, 70), Vector2(58, 74 - height * 0.55),
		Vector2(54, 74 - height * 0.66), Vector2(50, 74 - height * 0.5)], INK)  # gate arch
	for i in range(4):                                                       # crenellation
		var at := Vector2(44, 74) + VY * height + VX * (2.0 + 4.5 * i)
		_iso_box(canvas, at, 2.6, 2.0, 2.4, stone.lightened(0.1))
	if tier >= 3:
		_iso_box(canvas, Vector2(38, 78), 8, 8, height + 7, stone.lightened(0.05))  # tower


static func _barracks(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(48, 72), 30, 14, 12, stone)
	_gable(canvas, Vector2(48, 72), 30, 14, 12, 6, p["roof"], stone)
	for i in range(3):                                                       # yard posts
		var at := Vector2(38 - 5 * i, 76 + 2 * i)
		canvas.draw_line(at, at + VY * 10.0, TIMBER_DARK, 1.4)
	canvas.draw_line(Vector2(38, 70), Vector2(28, 80), STEEL, 1.1)           # racked spears
	canvas.draw_line(Vector2(41, 70), Vector2(31, 80), STEEL, 1.1)
	_poly(canvas, [Vector2(52, 68), Vector2(56, 66), Vector2(56, 61), Vector2(52, 63)],
		p["primary"])                                                        # door standard


static func _stables(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(46, 72), 32, 15, 10, stone)
	_gable(canvas, Vector2(46, 72), 32, 15, 10, 5, THATCH if p["roof"] == THATCH else p["roof"], stone)
	_poly(canvas, [Vector2(52, 72), Vector2(62, 67), Vector2(62, 58), Vector2(52, 63)], INK)  # wide door
	# A horse head at the door.
	_poly(canvas, [Vector2(55, 64), Vector2(58.5, 62), Vector2(61, 63.5), Vector2(60, 65.5),
		Vector2(57.5, 65.5)], HORSE)
	canvas.draw_circle(Vector2(60.2, 64.2), 0.5, INK)
	for i in range(4):                                                       # paddock rail
		var at := Vector2(30 - 3 * i, 74 + 2.4 * i)
		canvas.draw_line(at, at + VY * 6.0, TIMBER_DARK, 1.2)
	canvas.draw_line(Vector2(30, 71), Vector2(21, 78.2), TIMBER, 1.2)


static func _archery_range(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(58, 72), 20, 12, 9, stone)                      # shed
	_gable(canvas, Vector2(58, 72), 20, 12, 9, 4, p["roof"], stone)
	canvas.draw_circle(Vector2(30, 62), 8.5, THATCH)                         # target butt
	canvas.draw_circle(Vector2(30, 62), 5.6, Color(0.88, 0.86, 0.80))
	canvas.draw_circle(Vector2(30, 62), 2.8, p["primary"])
	canvas.draw_line(Vector2(30, 70.5), Vector2(30, 76), TIMBER_DARK, 1.6)   # stand
	canvas.draw_line(Vector2(44, 52), Vector2(31.5, 61.2), TIMBER_DARK, 1.0) # an arrow in flight
	_poly(canvas, [Vector2(33.5, 59.2), Vector2(31.5, 61.2), Vector2(34.2, 61.4)], STEEL)


static func _naval(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_poly(canvas, [Vector2(40, 84), Vector2(84, 84), Vector2(84, 72), Vector2(52, 72)], WATER)  # the water
	_poly(canvas, [Vector2(18, 80), Vector2(64, 80), Vector2(56, 62), Vector2(24, 62)], TIMBER)  # slipway
	for i in range(4):                                                       # sleepers
		var y := 66.0 + 3.6 * i
		canvas.draw_line(Vector2(25 + i, y), Vector2(57 + i * 1.6, y), TIMBER_DARK, 1.0)
	# The hull on the stocks, ribs still open to the sky.
	_poly(canvas, [Vector2(26, 68), Vector2(58, 68), Vector2(53, 74), Vector2(31, 74)], TIMBER_DARK)
	for i in range(5):
		canvas.draw_arc(Vector2(31.0 + 5.6 * i, 68.0), 5.0, PI * 1.05, PI * 1.95, 10,
			stone.darkened(0.25), 1.3)
	canvas.draw_line(Vector2(24, 71), Vector2(28, 75.5), TIMBER_DARK, 1.6)   # props
	canvas.draw_line(Vector2(58, 71), Vector2(55, 76.5), TIMBER_DARK, 1.6)
	_poly(canvas, [Vector2(70, 72), Vector2(76, 70.4), Vector2(76, 66), Vector2(70, 67.4)],
		p["primary"])                                                        # dock pennant crate
	canvas.draw_line(Vector2(62, 84), Vector2(62, 74), TIMBER_DARK, 1.4)     # mooring post


static func _siege_workshop(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(46, 72), 28, 14, 11, TIMBER)                    # open frame hall
	_gable(canvas, Vector2(46, 72), 28, 14, 11, 6, TIMBER_DARK, stone)
	canvas.draw_circle(Vector2(34, 72), 6.0, TIMBER_DARK)                    # wheel
	canvas.draw_circle(Vector2(34, 72), 4.4, p["stone"])
	for i in range(4):
		var angle := TAU * float(i) / 8.0
		canvas.draw_line(Vector2(34, 72) + Vector2.from_angle(angle) * 4.4,
			Vector2(34, 72) - Vector2.from_angle(angle) * 4.4, TIMBER_DARK, 1.0)
	canvas.draw_line(Vector2(48, 64), Vector2(70, 56), TIMBER, 2.6)          # ram beam
	_poly(canvas, [Vector2(70, 56), Vector2(74, 54.4), Vector2(72, 58)], STEEL)


static func _armoury(canvas: CanvasItem, p: Dictionary, tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(50, 72), 26, 14, 11, stone)                     # the smithy hall
	_gable(canvas, Vector2(50, 72), 26, 14, 11, 5, p["roof"], stone)
	_iso_box(canvas, Vector2(64, 74), 6, 6, 18, stone.darkened(0.15))       # forge chimney
	_ellipse(canvas, Vector2(64, 56), 3.2, 1.6, Color(0.55, 0.55, 0.58, 0.55))  # smoke
	_ellipse(canvas, Vector2(66, 52), 2.4, 1.3, Color(0.6, 0.6, 0.62, 0.4))
	_poly(canvas, [Vector2(60, 71), Vector2(64, 69), Vector2(64, 67), Vector2(60, 69)],
		Color(0.95, 0.55, 0.2))                                              # the forge's glow
	_iso_box(canvas, Vector2(34, 76), 6, 4, 4, INK)                          # the anvil block
	canvas.draw_line(Vector2(31, 70), Vector2(38, 69), STEEL, 1.6)
	for i in range(mini(2 + tier, 4)):                                        # racked shields
		var at := Vector2(24 - 4 * i, 74 + 2 * i)
		canvas.draw_circle(at, 2.6, p["primary"])
		canvas.draw_circle(at, 0.8, STEEL)


static func _temple(canvas: CanvasItem, p: Dictionary, tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(58, 75), 32, 24, 6, stone.darkened(0.06))       # stylobate
	_iso_box(canvas, Vector2(54, 71), 25, 17, 15 + tier, stone)
	_column_row(canvas, Vector2(54, 71), 25, 15 + tier, 5, stone)
	_gable(canvas, Vector2(54, 71), 25, 17, 15 + tier, 8, p["roof"], stone)
	_poly(canvas, [Vector2(54, 71) + VY * (23.0 + tier) + VX * 12.5 + Vector2(-2.2, 2.2),
		Vector2(54, 71) + VY * (23.0 + tier) + VX * 12.5 + Vector2(2.2, 2.2),
		Vector2(54, 71) + VY * (26.5 + tier) + VX * 12.5], p["primary"])     # pediment mark
	canvas.draw_line(Vector2(30, 70), Vector2(28, 60), Color(0.8, 0.8, 0.82, 0.6), 1.6)  # altar smoke
	_iso_box(canvas, Vector2(29, 73), 4, 3, 3, stone.darkened(0.12))


static func _farms(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	var field := Vector2(56, 80)
	_poly(canvas, [field, field + VX * 24.0, field + VX * 24.0 + VZ * 18.0, field + VZ * 18.0],
		Color(0.48, 0.37, 0.24))                                             # tilled plane
	for i in range(4):                                                       # furrows follow the plane
		var start := field + VZ * (3.0 + 4.0 * i) + VX * 1.5
		canvas.draw_line(start, start + VX * 21.0, Color(0.36, 0.27, 0.17), 1.3)
	_iso_box(canvas, Vector2(64, 70), 14, 10, 9, stone)                      # farmhouse
	_gable(canvas, Vector2(64, 70), 14, 10, 9, 5, p["roof"], stone)
	_ellipse(canvas, Vector2(30, 72), 6.5, 2.2, THATCH.darkened(0.15))       # haystack
	_poly(canvas, [Vector2(23.5, 72), Vector2(36.5, 72), Vector2(30, 62)], THATCH)
	canvas.draw_line(Vector2(30, 62), Vector2(30, 59.5), TIMBER_DARK, 1.0)
	canvas.draw_line(Vector2(40, 76), Vector2(46, 79), TIMBER, 1.2)          # low fence
	canvas.draw_line(Vector2(40, 73.6), Vector2(40, 78.4), TIMBER_DARK, 1.2)
	canvas.draw_line(Vector2(46, 76.6), Vector2(46, 81.4), TIMBER_DARK, 1.2)


static func _market(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	for i in range(2):                                                       # two awninged stalls
		var front := Vector2(30 + 26 * i, 76 - 3 * i)
		_iso_box(canvas, front, 15, 9, 6, TIMBER)
		var eave_left := front + VY * 6.0 + Vector2(-2.5, -3.5)
		var strip := 15.0 / 4.0
		for k in range(4):                                                   # striped canopy
			var a := front + VY * 6.0 + VX * (strip * k)
			var b := front + VY * 6.0 + VX * (strip * (k + 1))
			_poly(canvas, [a, b, b + Vector2(-2.5, -3.5), a + Vector2(-2.5, -3.5)],
				p["primary"] if k % 2 == 0 else stone.lightened(0.1))
		canvas.draw_line(front, front + VY * 6.0 + Vector2(0, 0), TIMBER_DARK, 1.0)
		canvas.draw_line(front + VX * 15.0, front + VX * 15.0 + VY * 6.0, TIMBER_DARK, 1.0)
	_poly(canvas, [Vector2(24, 78), Vector2(27, 78), Vector2(26.6, 72.5), Vector2(25.8, 71.6),
		Vector2(25.2, 72.5)], Color(0.62, 0.42, 0.28))                       # amphora
	_iso_box(canvas, Vector2(58, 82), 6, 4, 3.4, TIMBER_DARK)                # crate of goods
	canvas.draw_circle(Vector2(60.4, 77.6), 1.1, p["primary"].lightened(0.2))


static func _mines(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	_poly(canvas, [Vector2(24, 76), Vector2(80, 76), Vector2(66, 50), Vector2(40, 52)],
		p["stone"].darkened(0.18))                                           # hillside
	_poly(canvas, [Vector2(44, 76), Vector2(58, 76), Vector2(56, 62), Vector2(51, 58), Vector2(46, 62)], INK)  # adit
	canvas.draw_line(Vector2(44, 76), Vector2(46, 61), TIMBER, 1.8)          # props
	canvas.draw_line(Vector2(58, 76), Vector2(56, 61), TIMBER, 1.8)
	canvas.draw_line(Vector2(46, 61.5), Vector2(56, 61.5), TIMBER, 1.8)
	_iso_box(canvas, Vector2(30, 78), 8, 5, 4, TIMBER_DARK)                  # ore cart
	canvas.draw_circle(Vector2(32, 79.4), 1.6, INK)
	canvas.draw_circle(Vector2(37, 76.9), 1.6, INK)
	for i in range(3):
		canvas.draw_circle(Vector2(32.5 + 2.2 * i, 73.4 - 1.1 * i), 1.1, STEEL)


static func _port(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_poly(canvas, [Vector2(16, 70), Vector2(84, 70), Vector2(84, 84), Vector2(16, 84)], WATER)  # water
	_iso_box(canvas, Vector2(38, 70), 34, 10, 5, stone.darkened(0.05))       # quay
	_iso_box(canvas, Vector2(58, 64), 14, 9, 9, stone)                       # warehouse
	_gable(canvas, Vector2(58, 64), 14, 9, 9, 4, p["roof"], stone)
	_poly(canvas, [Vector2(24, 80), Vector2(44, 80), Vector2(40, 74.5), Vector2(28, 74.5)], TIMBER_DARK)  # hull
	canvas.draw_line(Vector2(34, 74.5), Vector2(34, 60), TIMBER, 1.4)        # mast
	_poly(canvas, [Vector2(34, 61), Vector2(43, 66), Vector2(34, 70)], p["primary"])  # furled sail
	canvas.draw_circle(Vector2(50, 71.6), 1.2, TIMBER_DARK)                  # bollard


static func _roads(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	_poly(canvas, [Vector2(34, 84), Vector2(58, 84), Vector2(52, 52), Vector2(44, 52)],
		p["stone"].darkened(0.12))                                           # the way, receding
	canvas.draw_line(Vector2(46, 84), Vector2(47.6, 52), p["stone"].lightened(0.15), 0.9)
	for i in range(5):                                                       # paving joints
		var y := 80.0 - 6.5 * i
		var half := 11.0 - 1.6 * i
		canvas.draw_line(Vector2(46 - half, y), Vector2(46 + half, y), p["stone"].darkened(0.3), 0.8)
	_iso_box(canvas, Vector2(62, 74), 3.5, 3, 8, p["stone"])                 # milestone
	for i in range(3):
		canvas.draw_line(Vector2(24 + i, 60 + 7 * i), Vector2(30 + i, 60 + 7 * i), Color(0.45, 0.52, 0.30), 1.4)  # verge


static func _health(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(50, 72), 24, 14, 11, stone)                     # bath hall
	_gable(canvas, Vector2(50, 72), 24, 14, 11, 5, p["roof"], stone)
	for i in range(3):                                                       # aqueduct arches
		var at := Vector2(24 + 8 * i, 58)
		canvas.draw_arc(at, 3.6, PI, TAU, 10, stone.darkened(0.1), 2.2)
		canvas.draw_line(at + Vector2(-3.6, 0), at + Vector2(-3.6, 10), stone.darkened(0.1), 2.2)
	canvas.draw_line(Vector2(20.4, 55.4), Vector2(44, 55.4), stone.lightened(0.1), 2.6)  # channel
	_poly(canvas, [Vector2(54, 76), Vector2(66, 76), Vector2(64, 73), Vector2(56, 73)], WATER)  # pool


static func _entertainment(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	for i in range(3):                                                       # tiered arena arc
		var radius := 26.0 - 6.5 * i
		canvas.draw_arc(Vector2(50, 74), radius, PI + 0.35, TAU - 0.35, 26,
			stone.darkened(0.04 + 0.05 * i), 5.4)
	_ellipse(canvas, Vector2(50, 74), 13, 5.5, Color(0.83, 0.74, 0.55))      # the sand
	for i in range(5):                                                       # arcade
		var angle := PI + 0.55 + 0.5 * i
		var at := Vector2(50, 74) + Vector2(cos(angle), sin(angle) * 0.62) * 27.0
		canvas.draw_arc(at, 2.0, PI, TAU, 8, INK, 1.6)
	_banner(canvas, Vector2(74, 62), 16, p["primary"])


static func _education(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(52, 73), 28, 16, 4, stone.darkened(0.06))       # stoa floor
	_column_row(canvas, Vector2(52, 71), 28, 13, 6, stone)
	_iso_box(canvas, Vector2(52, 71) + VY * 13.0, 28, 16, 3, stone)          # architrave
	_gable(canvas, Vector2(52, 71) + VY * 13.0, 28, 16, 3, 4, p["roof"], stone)
	_poly(canvas, [Vector2(30, 74), Vector2(40, 74), Vector2(40, 71.6), Vector2(30, 71.6)],
		Color(0.93, 0.90, 0.80))                                             # unrolled scroll
	canvas.draw_circle(Vector2(30, 72.8), 1.3, TIMBER)
	canvas.draw_circle(Vector2(40, 72.8), 1.3, TIMBER)
	for i in range(3):
		canvas.draw_line(Vector2(32, 72.4 + 0.55 * i), Vector2(38, 72.4 + 0.55 * i), INK, 0.35)


static func _execution(canvas: CanvasItem, p: Dictionary, _tier: int) -> void:
	var stone: Color = p["stone"]
	_iso_box(canvas, Vector2(46, 74), 24, 16, 6, TIMBER)                     # platform
	canvas.draw_line(Vector2(52, 68), Vector2(52, 50), TIMBER_DARK, 2.0)     # post
	canvas.draw_line(Vector2(52, 50), Vector2(62, 50), TIMBER_DARK, 2.0)     # beam
	canvas.draw_line(Vector2(61, 50), Vector2(61, 55), INK, 1.0)             # rope
	_iso_box(canvas, Vector2(58, 70), 6, 4, 3.4, TIMBER_DARK)                # the block
	_poly(canvas, [Vector2(66, 64), Vector2(70, 60), Vector2(72, 62), Vector2(68, 65.4)], STEEL)  # the axe
	canvas.draw_line(Vector2(67, 64.6), Vector2(72, 69), TIMBER, 1.4)
	_banner(canvas, Vector2(30, 74), 20, p["primary"].darkened(0.2))


## --- unit figures ----------------------------------------------------------

static func _man(canvas: CanvasItem, foot: Vector2, p: Dictionary, armored: bool) -> void:
	## A soldier in profile facing right, ~34 design units tall; `foot` is
	## where his leading foot stands.
	var tunic: Color = p["primary"]
	var mail := STEEL.darkened(0.12) if armored else tunic.darkened(0.1)
	canvas.draw_line(foot + Vector2(-1, 0), foot + Vector2(1.2, -12), SKIN.darkened(0.15), 2.4)   # rear leg
	canvas.draw_line(foot + Vector2(4.5, 0), foot + Vector2(1.8, -12), SKIN.darkened(0.05), 2.4)  # front leg
	_poly(canvas, [foot + Vector2(-2.4, -11), foot + Vector2(5.4, -11),
		foot + Vector2(4.4, -22), foot + Vector2(-1.6, -22)], mail)          # torso
	_poly(canvas, [foot + Vector2(-2.6, -11), foot + Vector2(5.6, -11),
		foot + Vector2(5.0, -16), foot + Vector2(-2.2, -16)], tunic)         # skirt
	canvas.draw_circle(foot + Vector2(1.8, -25.4), 3.1, SKIN)                # head
	canvas.draw_arc(foot + Vector2(1.8, -25.9), 3.3, PI * 0.95, TAU * 1.02, 10, STEEL, 2.2)  # helmet
	if armored:
		canvas.draw_line(foot + Vector2(1.8, -29.4), foot + Vector2(0.2, -31.6), p["primary"], 2.0)  # crest


static func _shield(canvas: CanvasItem, at: Vector2, p: Dictionary, tall: bool) -> void:
	if tall:
		_poly(canvas, [at + Vector2(-3, 8), at + Vector2(3, 8), at + Vector2(3, -8), at + Vector2(-3, -8)],
			p["primary"])
		canvas.draw_circle(at, 1.4, p["stone"])
	else:
		canvas.draw_circle(at, 5.2, p["primary"])
		canvas.draw_arc(at, 5.2, 0, TAU, 16, p["stone"].darkened(0.2), 0.9)
		canvas.draw_circle(at, 1.5, p["stone"])


static func _horse(canvas: CanvasItem, foot: Vector2, coat: Color) -> void:
	## A horse in profile facing right; `foot` is under its forelegs.
	_poly(canvas, [foot + Vector2(-16, -10), foot + Vector2(1, -10), foot + Vector2(2, -16),
		foot + Vector2(-15, -17)], coat)                                     # body
	_poly(canvas, [foot + Vector2(0, -14), foot + Vector2(6.5, -20), foot + Vector2(8.5, -18.4),
		foot + Vector2(3, -12.5)], coat.lightened(0.05))                     # neck
	_poly(canvas, [foot + Vector2(6.0, -20.6), foot + Vector2(10.6, -18.8), foot + Vector2(9.4, -16.8),
		foot + Vector2(5.4, -18.2)], coat.darkened(0.06))                    # head
	canvas.draw_line(foot + Vector2(-1, -10), foot + Vector2(0.6, 0), coat.darkened(0.1), 2.0)
	canvas.draw_line(foot + Vector2(-14, -10), foot + Vector2(-15.5, 0), coat.darkened(0.16), 2.0)
	canvas.draw_line(foot + Vector2(-5, -10), foot + Vector2(-4, 0), coat.darkened(0.02), 2.0)
	canvas.draw_line(foot + Vector2(-10, -10), foot + Vector2(-9.4, 0), coat.darkened(0.2), 2.0)
	canvas.draw_line(foot + Vector2(-15.8, -16), foot + Vector2(-19.5, -8), coat.darkened(0.22), 1.5)  # tail


static func _rider(canvas: CanvasItem, seat: Vector2, p: Dictionary) -> void:
	_poly(canvas, [seat + Vector2(-2.4, 0), seat + Vector2(2.6, 0),
		seat + Vector2(2.0, -8.5), seat + Vector2(-1.8, -8.5)], p["primary"])
	canvas.draw_circle(seat + Vector2(0.2, -11.2), 2.6, SKIN)
	canvas.draw_arc(seat + Vector2(0.2, -11.6), 2.8, PI * 0.95, TAU * 1.02, 10, STEEL, 1.9)
	canvas.draw_line(seat + Vector2(1.5, -2), seat + Vector2(3.4, 4.5), SKIN.darkened(0.1), 1.8)  # leg


static func _u_infantry(canvas: CanvasItem, p: Dictionary) -> void:
	_man(canvas, Vector2(46, 84), p, true)
	canvas.draw_line(Vector2(52, 66), Vector2(58, 60), STEEL, 1.8)           # blade
	_shield(canvas, Vector2(54, 68), p, true)


static func _u_spear(canvas: CanvasItem, p: Dictionary) -> void:
	_man(canvas, Vector2(46, 84), p, true)
	canvas.draw_line(Vector2(54, 84), Vector2(54, 48), TIMBER, 1.4)          # spear
	_poly(canvas, [Vector2(53, 49), Vector2(55, 49), Vector2(54, 45)], STEEL)
	_shield(canvas, Vector2(50, 68), p, false)


static func _u_pike(canvas: CanvasItem, p: Dictionary) -> void:
	_man(canvas, Vector2(44, 84), p, true)
	canvas.draw_line(Vector2(40, 76), Vector2(70, 42), TIMBER, 1.3)          # pike, two-handed
	_poly(canvas, [Vector2(69, 44.4), Vector2(67.6, 43), Vector2(72, 40)], STEEL)
	canvas.draw_line(Vector2(46, 70), Vector2(52, 64), SKIN, 1.8)            # raised arm
	_shield(canvas, Vector2(42, 70), p, false)


static func _u_missile(canvas: CanvasItem, p: Dictionary) -> void:
	_man(canvas, Vector2(46, 84), p, false)
	canvas.draw_arc(Vector2(53, 66), 9.0, -PI * 0.42, PI * 0.42, 12, TIMBER, 1.5)  # bow
	canvas.draw_line(Vector2(56.6, 58.4), Vector2(56.6, 73.6), Color(0.85, 0.85, 0.8), 0.7)  # string
	canvas.draw_line(Vector2(48, 66), Vector2(60, 66), TIMBER_DARK, 1.0)     # nocked arrow
	_poly(canvas, [Vector2(60, 65.2), Vector2(60, 66.8), Vector2(62.4, 66)], STEEL)
	_poly(canvas, [Vector2(41, 64), Vector2(44.6, 63), Vector2(44, 72), Vector2(41, 72)],
		TIMBER)                                                              # quiver


static func _u_cavalry(canvas: CanvasItem, p: Dictionary) -> void:
	_horse(canvas, Vector2(52, 84), HORSE)
	_rider(canvas, Vector2(45, 67), p)
	canvas.draw_line(Vector2(48, 62), Vector2(60, 52), TIMBER, 1.3)          # lance
	_poly(canvas, [Vector2(59, 53.4), Vector2(58, 52), Vector2(62, 50)], STEEL)
	_shield(canvas, Vector2(41, 64), p, false)


static func _u_horse_archer(canvas: CanvasItem, p: Dictionary) -> void:
	_horse(canvas, Vector2(52, 84), HORSE.lightened(0.12))
	_rider(canvas, Vector2(45, 67), p)
	canvas.draw_arc(Vector2(38, 60), 7.0, PI * 0.58, PI * 1.42, 12, TIMBER, 1.4)  # bow turned back
	canvas.draw_line(Vector2(40.2, 53.6), Vector2(40.2, 66.4), Color(0.85, 0.85, 0.8), 0.6)
	canvas.draw_line(Vector2(46, 60), Vector2(36, 60), TIMBER_DARK, 0.9)     # the parting shot


static func _u_chariot(canvas: CanvasItem, p: Dictionary) -> void:
	_horse(canvas, Vector2(60, 84), HORSE.darkened(0.05))
	canvas.draw_circle(Vector2(36, 78), 6.2, TIMBER_DARK)                    # wheel
	canvas.draw_circle(Vector2(36, 78), 4.6, p["stone"])
	for i in range(3):
		var angle := TAU * float(i) / 6.0
		canvas.draw_line(Vector2(36, 78) + Vector2.from_angle(angle) * 4.6,
			Vector2(36, 78) - Vector2.from_angle(angle) * 4.6, TIMBER_DARK, 0.9)
	_poly(canvas, [Vector2(29, 78), Vector2(43, 78), Vector2(43, 66), Vector2(29, 68)], p["primary"])  # car
	canvas.draw_line(Vector2(43, 76), Vector2(56, 72), TIMBER, 1.3)          # yoke pole
	canvas.draw_circle(Vector2(35, 62.8), 2.5, SKIN)                         # driver
	canvas.draw_arc(Vector2(35, 62.4), 2.7, PI * 0.95, TAU * 1.02, 10, STEEL, 1.7)
	canvas.draw_line(Vector2(37, 64), Vector2(50, 68), Color(0.62, 0.5, 0.35), 0.8)  # reins


static func _u_elephant(canvas: CanvasItem, p: Dictionary) -> void:
	var hide := Color(0.52, 0.50, 0.52)
	_poly(canvas, [Vector2(34, 82), Vector2(62, 82), Vector2(64, 62), Vector2(36, 60)], hide)  # body
	_poly(canvas, [Vector2(60, 74), Vector2(70, 70), Vector2(72, 60), Vector2(62, 62)], hide.lightened(0.05))  # head
	canvas.draw_line(Vector2(70, 68), Vector2(74, 82), hide.darkened(0.1), 2.6)  # trunk
	canvas.draw_line(Vector2(69, 70), Vector2(76, 67), Color(0.92, 0.90, 0.82), 2.0)  # tusk
	for x in [39.0, 46.0, 53.0, 60.0]:
		canvas.draw_line(Vector2(x, 82), Vector2(x, 90), hide.darkened(0.14), 3.2)
	_poly(canvas, [Vector2(40, 60), Vector2(56, 60), Vector2(55, 50), Vector2(41, 50)], p["primary"])  # tower
	for i in range(3):
		canvas.draw_line(Vector2(42 + 4.5 * i, 50), Vector2(42 + 4.5 * i, 47), TIMBER_DARK, 1.2)
	canvas.draw_circle(Vector2(66, 63), 0.8, INK)                            # eye


static func _u_siege(canvas: CanvasItem, p: Dictionary) -> void:
	_poly(canvas, [Vector2(30, 82), Vector2(66, 82), Vector2(62, 76), Vector2(34, 76)], TIMBER)  # frame base
	canvas.draw_circle(Vector2(36, 82), 3.4, TIMBER_DARK)
	canvas.draw_circle(Vector2(60, 82), 3.4, TIMBER_DARK)
	canvas.draw_line(Vector2(38, 76), Vector2(50, 58), TIMBER, 2.2)          # throwing arm
	canvas.draw_line(Vector2(50, 58), Vector2(58, 52), TIMBER_DARK, 1.6)     # sling
	canvas.draw_circle(Vector2(59, 51), 2.2, p["stone"].darkened(0.25))      # the stone
	canvas.draw_line(Vector2(34, 76), Vector2(56, 70), TIMBER_DARK, 1.4)     # brace
	canvas.draw_line(Vector2(44, 76), Vector2(44, 66), TIMBER_DARK, 1.4)


static func _u_ship(canvas: CanvasItem, p: Dictionary) -> void:
	_poly(canvas, [Vector2(24, 74), Vector2(72, 74), Vector2(66, 82), Vector2(32, 82)], TIMBER_DARK)  # hull
	_poly(canvas, [Vector2(24, 74), Vector2(20, 68), Vector2(27, 72)], TIMBER_DARK)  # ram bow
	canvas.draw_line(Vector2(48, 74), Vector2(48, 46), TIMBER, 1.6)          # mast
	_poly(canvas, [Vector2(38, 48), Vector2(58, 48), Vector2(56, 62), Vector2(40, 62)], p["primary"])  # sail
	canvas.draw_line(Vector2(38, 48), Vector2(58, 48), TIMBER_DARK, 1.2)     # yard
	for i in range(6):                                                       # oars
		var x := 30.0 + 6.5 * i
		canvas.draw_line(Vector2(x, 80), Vector2(x - 3, 88), TIMBER, 1.0)
	_poly(canvas, [Vector2(70, 74), Vector2(76, 70), Vector2(74, 76)], TIMBER)  # steering oar


static func _u_bodyguard(canvas: CanvasItem, p: Dictionary) -> void:
	_horse(canvas, Vector2(52, 84), HORSE.darkened(0.15))
	_rider(canvas, Vector2(45, 67), p)
	canvas.draw_line(Vector2(50, 64), Vector2(50, 44), TIMBER_DARK, 1.4)     # standard pole
	_poly(canvas, [Vector2(50, 44), Vector2(60, 45.5), Vector2(50, 50)], p["primary"])
	canvas.draw_circle(Vector2(50, 43), 1.7, CAPITAL_GOLD_SAFE)
	_shield(canvas, Vector2(41, 64), p, false)


const CAPITAL_GOLD_SAFE := Color(1.0, 0.87, 0.42)


static func _u_peasant(canvas: CanvasItem, p: Dictionary) -> void:
	var drab := Color(0.62, 0.55, 0.42)
	var poor := {"primary": drab, "stone": p["stone"], "roof": p["roof"]}
	_man(canvas, Vector2(46, 84), poor, false)
	canvas.draw_line(Vector2(53, 84), Vector2(53, 54), TIMBER, 1.3)          # pitchfork
	for i in range(3):
		canvas.draw_line(Vector2(51.6 + 1.4 * i, 54), Vector2(51.6 + 1.4 * i, 49.5), STEEL.darkened(0.2), 0.9)
