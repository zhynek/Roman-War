class_name CampaignMiniatures
## Original procedural miniatures, drawn only at close zoom. Cosmetic hashes
## come from stable ids; no textures, scene state or campaign random draws.
## World-space dimensions stay small so zoom reveals detail, not bigger icons.

const SHADOW := Color(0.05, 0.09, 0.07, 0.20)
const STONE := Color(0.77, 0.73, 0.60)
const STONE_DARK := Color(0.40, 0.40, 0.33)
const ROOF := Color(0.65, 0.29, 0.18)
const LEAF := Color(0.22, 0.36, 0.20)
const BRONZE := Color(0.77, 0.66, 0.38)


static func terrain(canvas: CanvasItem, at: Vector2, kind: String, seed_id: String, salt: int) -> void:
	var jitter := UiStyle.jitter(seed_id, salt)
	match kind:
		"forest":
			for i in range(7):
				var offset := Vector2((UiStyle.jitter(seed_id, salt + i * 7) - 0.5) * 25,
					(UiStyle.jitter(seed_id, salt + i * 7 + 2) - 0.5) * 18)
				_tree(canvas, at + offset, 0.65 + UiStyle.jitter(seed_id, i + salt + 3) * 0.5)
		"hills":
			_ellipse(canvas, at + Vector2(3, 3), Vector2(12, 5), Color(0.36, 0.40, 0.26, 0.13))
			_ellipse(canvas, at, Vector2(12, 5), Color(0.56, 0.57, 0.35, 0.32))
			_ellipse(canvas, at + Vector2(-2, -2), Vector2(9, 3.6), Color(0.73, 0.69, 0.43, 0.30))
			canvas.draw_arc(at, 9, PI * 1.1, PI * 1.8, 14, Color(0.81, 0.75, 0.48, 0.40), 0.45, true)
			if jitter > 0.35:
				_tree(canvas, at + Vector2(-8, -1), 0.55)
		"mountains":
			var peak := 15.0 if kind == "mountains" else 7.0
			var a := at + Vector2(-16, 5)
			var b := at + Vector2(-2 + jitter * 4, -peak)
			var c := at + Vector2(19, 7)
			canvas.draw_colored_polygon(PackedVector2Array([a + Vector2(4, 4), b + Vector2(6, 5), c + Vector2(6, 3)]), SHADOW)
			canvas.draw_colored_polygon(PackedVector2Array([a, b, at + Vector2(2, 7)]), Color(0.56, 0.56, 0.44))
			canvas.draw_colored_polygon(PackedVector2Array([b, c, at + Vector2(2, 7)]), Color(0.40, 0.44, 0.36))
			canvas.draw_polyline(PackedVector2Array([a, b, c]), Color(0.68, 0.66, 0.52), 0.6, true)
			if kind == "mountains":
				canvas.draw_colored_polygon(PackedVector2Array([b + Vector2(-4, 6), b,
					b + Vector2(5, 6), b + Vector2(1, 4)]), Color(0.87, 0.87, 0.78))
		"marsh":
			_ellipse(canvas, at, Vector2(10, 3), Color(0.25, 0.43, 0.40, 0.32))
			for i in range(5):
				var reed := at + Vector2(i * 3 - 6, i % 2 * 2)
				canvas.draw_line(reed, reed + Vector2(1, -4), LEAF, 0.5, true)
		"desert", "steppe":
			canvas.draw_polyline(PackedVector2Array([at + Vector2(-12, 2), at + Vector2(-2, -2), at + Vector2(12, 1)]), Color(0.71, 0.63, 0.42, 0.55), 0.7, true)
		_:
			if jitter > 0.55:
				_tree(canvas, at, 0.6)
			else:
				for i in range(5):
					var p := at + Vector2(i * 3 - 6, i % 3)
					canvas.draw_line(p, p + Vector2(1, -1.6), Color(0.42, 0.51, 0.29, 0.6), 0.4, true)


static func _tree(canvas: CanvasItem, at: Vector2, scale: float) -> void:
	_ellipse(canvas, at + Vector2(3, 2) * scale, Vector2(6, 2.5) * scale, SHADOW)
	canvas.draw_line(at, at + Vector2(0, -7) * scale, Color(0.31, 0.25, 0.17), 1.1 * scale, true)
	canvas.draw_circle(at + Vector2(0, -7) * scale, 4.0 * scale, LEAF)
	canvas.draw_circle(at + Vector2(-2, -8.5) * scale, 3.1 * scale, Color(0.32, 0.44, 0.23))
	canvas.draw_circle(at + Vector2(-2.5, -10) * scale, 1.8 * scale, Color(0.43, 0.53, 0.28))


static func settlement(canvas: CanvasItem, at: Vector2, params: Dictionary) -> void:
	var tier := int(params["level"])
	var radius := 12.0 + tier * 1.5
	var roof: Color = SettlementIcons.ROOF.get(params["culture"], ROOF)
	_ellipse(canvas, at + Vector2(3, 4), Vector2(radius + 4, radius * 0.64), SHADOW)
	_ellipse(canvas, at, Vector2(radius + 2, radius * 0.68), Color(0.64, 0.62, 0.43, 0.65))
	# A cross of streets and little wards. The footprint grows with the real tier.
	canvas.draw_line(at + Vector2(-radius, 0), at + Vector2(radius, 0), Color(0.77, 0.71, 0.52), 2, true)
	canvas.draw_line(at + Vector2(0, -radius * 0.6), at + Vector2(0, radius * 0.6), Color(0.77, 0.71, 0.52), 1.8, true)
	for row in range(-2, 3):
		for col in range(-3, 4):
			if col == 0 or row == 0 or abs(col) + abs(row) > 3 + mini(tier, 2):
				continue
			var seed := UiStyle.jitter(params["region_id"], row * 31 + col)
			_house(canvas, at + Vector2(col * 4.2, row * 4.0), Vector2(3.2 + seed, 2.2), 2.2 + seed * 2, roof)
	# Civic hall with a pediment and columns, kept inside the same footprint.
	_house(canvas, at + Vector2(-2, -1), Vector2(7, 4), 4.6, roof)
	for i in range(4):
		var column := at + Vector2(-4.5 + i * 1.6, -1)
		canvas.draw_line(column, column + Vector2(0, -3.8), Color(0.93, 0.87, 0.70), 0.7, true)
	if int(params["wall_level"]) > 0:
		var wall := PackedVector2Array()
		for i in range(17):
			var angle := TAU * i / 16.0
			wall.append(at + Vector2(cos(angle) * radius, sin(angle) * radius * 0.63))
		canvas.draw_polyline(wall, STONE_DARK, 2.8, true)
		var crest := PackedVector2Array()
		for point in wall:
			crest.append(point + Vector2(0, -2))
		canvas.draw_polyline(crest, STONE, 1.8, true)
		for i in [1, 3, 5, 7, 9, 11, 13, 15]:
			_house(canvas, wall[i], Vector2(2.3, 2), 4, STONE)
		# Gate facing the open foreground.
		canvas.draw_rect(Rect2(at + Vector2(-1.5, radius * 0.63 - 3), Vector2(3, 3)), STONE_DARK)
	var standard := at + Vector2(radius * 0.75, -radius * 0.45)
	_flag(canvas, standard, params["owner_color"], 0)
	if params["is_capital"]:
		canvas.draw_arc(standard + Vector2(0, -12), 3, 0.4, PI - 0.4, 12, UiStyle.CAPITAL_GOLD, 0.8, true)
	if params["has_wonder"]:
		_house(canvas, at + Vector2(-radius - 4, 0), Vector2(4, 3), 7, UiStyle.ACCENT)
	if int(params["port_level"]) > 0:
		var quay := at + (params["seaward"] as Vector2) * (radius + 5)
		canvas.draw_line(at, quay, STONE_DARK, 2.2, true)
		for i in range(3):
			canvas.draw_line(quay + Vector2(i * 3 - 3, 0), quay + Vector2(i * 3 - 3, 6), STONE, 1.2, true)
	if params["under_siege"]:
		for i in range(4):
			var camp := at + Vector2(cos(i * PI / 2) * (radius + 9), sin(i * PI / 2) * (radius * 0.65 + 7))
			_tent(canvas, camp, UiStyle.SIEGE_RED)
		canvas.draw_arc(at, radius + 5, 0.1, PI - 0.1, 28, Color(UiStyle.SIEGE_RED, 0.85), 0.7, true)


static func farms(canvas: CanvasItem, at: Vector2, seed_id: String, extent: float) -> void:
	for i in range(4):
		var p := at + Vector2(-extent - 9 + (i % 2) * 8, 4 + floori(i / 2.0) * 7)
		var shade := UiStyle.jitter(seed_id, i)
		var rect := Rect2(p, Vector2(7, 5))
		canvas.draw_rect(rect, Color(0.61 + shade * 0.12, 0.59 + shade * 0.09, 0.31, 0.65))
		for furrow in range(5):
			canvas.draw_line(p + Vector2(furrow * 1.4, 0), p + Vector2(furrow * 1.4, 5), Color(0.40, 0.43, 0.24, 0.45), 0.35, true)


static func army(canvas: CanvasItem, at: Vector2, summary: Dictionary, color: Color,
		classes: Array, phase: float, moving: bool, selected: bool, direction: Vector2, looks: Array = [], commander: Dictionary = {}) -> void:
	var count := clampi(int(summary["units"]) * 3, 6, 30)
	if selected:
		_ellipse(canvas, at + Vector2(0, 1), Vector2(15, 10), Color(UiStyle.CAPITAL_GOLD, 0.08))
		var ring := PackedVector2Array()
		for i in range(33):
			var a := TAU * i / 32.0
			ring.append(at + Vector2(cos(a) * 15, sin(a) * 10))
		canvas.draw_polyline(ring, Color(UiStyle.CAPITAL_GOLD, 0.8), 0.65, true)
	if not moving:
		_tent(canvas, at + Vector2(-13, -6), Color(0.74, 0.68, 0.48))
		_tent(canvas, at + Vector2(-13, 1), Color(0.68, 0.62, 0.45))
	else:
		for i in range(6):
			var dust := fposmod(phase * 0.6 + i * 0.17, 1.0)
			var offset := -direction * (7 + dust * 16) + Vector2(0, sin(i * 3.2) * 4)
			_ellipse(canvas, at + offset, Vector2(2 + dust * 3, 1 + dust), Color(0.83, 0.75, 0.54, (1 - dust) * 0.12))
	for i in range(count):
		var row := i / 5
		var col := i % 5
		var offset := Vector2((col - 2) * 3.6, (row - 2) * 3.2)
		if moving:
			# Columns turn into the road and keep formation around their commander.
			var across := Vector2(-direction.y, direction.x)
			offset = across * ((col - 2) * 2.6) - direction * (row * 3.4 + 3)
		var bounce := sin(phase * 11 + i * 1.7) * 0.35 if moving else 0.0
		var kind := String(classes[i % classes.size()]) if not classes.is_empty() else "infantry"
		_soldier(canvas, at + offset + Vector2(0, bounce), color, kind, phase + i, moving, looks[i % looks.size()] if not looks.is_empty() else {})
	if summary["general"] != null:
		# The mounted commander is a recognisable leader at the head of the men.
		_soldier(canvas, at + direction * 7 if moving else at + Vector2(8, -10), color.lightened(0.15), "commander", phase, moving, commander)
	_flag(canvas, at + Vector2(2, -8), color, phase if moving else phase * 0.35)


static func _soldier(canvas: CanvasItem, at: Vector2, color: Color, kind: String, phase: float, moving: bool, look: Dictionary = {}) -> void:
	var mounted := kind in ["cavalry", "general_bodyguard", "commander", "horse_archer"]
	var leader := kind == "commander"
	var metal: Color = look.get("accent", BRONZE) if leader else BRONZE
	var cloak: Color = look.get("cape", color) if leader else Color.html(look.get("tunic", "#9b7651"))
	var horse: Color = look.get("horse", Color("#805131"))
	var stride := sin(phase * 9) * 0.75 if moving else 0.0
	_ellipse(canvas, at + Vector2(0.6, 0.6), Vector2(4.0 if mounted else 1.8, 0.95), SHADOW)
	if kind == "siege":
		# Timber frame, wheels, throwing arm and rope: artillery reads as a train.
		canvas.draw_line(at+Vector2(-3,0), at+Vector2(3,0), Color("#674a28"), 2.0, true)
		for x in [-2,2]:
			canvas.draw_circle(at+Vector2(x,1), 1.1, STONE_DARK)
			canvas.draw_arc(at+Vector2(x,1), 0.7, 0, TAU, 10, BRONZE, 0.4, true)
		canvas.draw_line(at+Vector2(-2,-1), at+Vector2(2,-5), Color("#997342"), 0.85, true)
		canvas.draw_line(at+Vector2(-2,-3), at+Vector2(3,-2), Color("#d4ba87"), 0.45, true)
		return
	if kind == "elephant":
		_ellipse(canvas, at+Vector2(0,-2), Vector2(4,2.6), Color("#777b6c"))
		for x in [-2,2]:
			canvas.draw_line(at+Vector2(x,-1), at+Vector2(x+stride,2), Color("#555d55"), 1.3, true)
		canvas.draw_circle(at+Vector2(3,-3), 2, Color("#868878"))
		canvas.draw_polyline(PackedVector2Array([at+Vector2(4,-3),at+Vector2(5,0),at+Vector2(6,1)]), Color("#777b6c"), 1.1, true)
		canvas.draw_line(at+Vector2(4,-2), at+Vector2(6,-2.7), STONE, 0.6, true)
		canvas.draw_rect(Rect2(at+Vector2(-1,-5),Vector2(3,3)), color)
		return
	if kind == "chariot":
		_ellipse(canvas, at+Vector2(3,-2), Vector2(2.5,1.1), horse)
		canvas.draw_line(at+Vector2(0,-1),at+Vector2(3,-1), BRONZE, 0.65, true)
		canvas.draw_rect(Rect2(at+Vector2(-2,-3),Vector2(3,3)), color)
		canvas.draw_circle(at+Vector2(-1,1),1.5,STONE_DARK)
	if mounted:
		var size := 1.35 if leader else 1.0
		for x in [-2,2]:
			canvas.draw_line(at+Vector2(x,-1)*size, at+Vector2(x+stride,1.6)*size, horse.darkened(0.3), 0.75*size, true)
		_ellipse(canvas, at+Vector2(0,-1.8)*size, Vector2(3.2,1.5)*size, horse)
		canvas.draw_polyline(PackedVector2Array([at+Vector2(2,-2)*size,at+Vector2(3,-4.5)*size,at+Vector2(4.5,-4)*size]), horse.lightened(0.1), 1.35*size, true)
		canvas.draw_line(at+Vector2(-3,-2)*size,at+Vector2(-4.5,-0.4+stride)*size, horse.darkened(0.4), 0.65, true)
		canvas.draw_line(at+Vector2(0,-3)*size,at+Vector2(4,-4)*size, metal.darkened(0.3), 0.3, true)
		at += Vector2(0,-2.0)*size
	else:
		canvas.draw_line(at+Vector2(-0.7,-1), at+Vector2(-0.9+stride,1), STONE_DARK, 0.65, true)
		canvas.draw_line(at+Vector2(0.7,-1), at+Vector2(0.9-stride,1), STONE_DARK, 0.65, true)
	var armour := String(look.get("armour", "mail"))
	var body := Color("#818577") if armour in ["mail","scale","segmented"] else Color("#c8bea0") if armour == "linen" else cloak
	canvas.draw_line(at+Vector2(0,-0.8),at+Vector2(0,-3.6),body,2.1 if leader else 1.8,true)
	canvas.draw_line(at+Vector2(-0.8,-1.2),at+Vector2(0.8,-1.2),metal.darkened(0.25),0.4,true)
	canvas.draw_circle(at+Vector2(0,-4),1.0 if leader else 0.82,look.get("face",Color("#c5a071")))
	var helmet := String(look.get("helmet", "cap"))
	if helmet != "none":
		canvas.draw_arc(at+Vector2(0,-4),1.0,PI,TAU,10,metal,0.9,true)
		if helmet in ["crest","plume"]:
			canvas.draw_line(at+Vector2(-0.5,-5.2),at+Vector2(0.7,-5.7),cloak.lightened(0.3),1.0,true)
		elif helmet == "conical":
			canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(-1,-4.8),at+Vector2(0,-6.5),at+Vector2(1,-4.8)]),metal)
		elif helmet == "horned":
			canvas.draw_line(at+Vector2(-0.8,-4.8),at+Vector2(-1.4,-5.8),STONE,0.45,true)
			canvas.draw_line(at+Vector2(0.8,-4.8),at+Vector2(1.4,-5.8),STONE,0.45,true)
	else:
		canvas.draw_arc(at+Vector2(0,-4),1,PI,TAU,10,look.get("hair",Color("#714a27")),0.9,true)
	var weapon := String(look.get("weapon", "spear"))
	if weapon == "bow" or kind == "horse_archer":
		canvas.draw_arc(at+Vector2(1.6,-2.7),2,-PI/2,PI/2,12,BRONZE,0.4,true)
		canvas.draw_line(at+Vector2(1.6,-4.7),at+Vector2(1.6,-0.7),STONE,0.2,true)
	else:
		var length := 9.5 if kind == "pike" else 6.5 if weapon in ["spear","pike","lance"] else 3.5
		canvas.draw_line(at+Vector2(1.8,-0.8),at+Vector2(2.1,-length),Color("#5c4b30"),0.4,true)
		canvas.draw_line(at+Vector2(2.1,-length+0.8),at+Vector2(2.1,-length-0.6),STONE,0.55,true)
	if not leader:
		var shield := String(look.get("shield", "round"))
		if shield in ["scutum","tower"]:
			canvas.draw_rect(Rect2(at+Vector2(-2,-3.6),Vector2(1.7,3)),cloak)
			canvas.draw_rect(Rect2(at+Vector2(-2,-3.6),Vector2(1.7,3)),metal,false,0.25)
		elif shield != "none":
			_ellipse(canvas,at+Vector2(-1.4,-2.2),Vector2(1.1,1.5 if shield == "oval" else 1.1),cloak)
		canvas.draw_circle(at+Vector2(-1.4,-2.2),0.4,metal)
	else:
		canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(-0.6,-3.5),at+Vector2(-3.3,-2.2+stride*0.3),at+Vector2(-4,0.5),at+Vector2(-1.3,-0.4)]),cloak)
		canvas.draw_line(at+Vector2(-0.6,-3.5),at+Vector2(-3.3,-2.2),metal,0.35,true)


static func watchpost(canvas: CanvasItem, at: Vector2, level: int, color: Color) -> void:
	_ellipse(canvas, at+Vector2(2,3),Vector2(10,5),SHADOW)
	if level >= 2:
		canvas.draw_polyline(PackedVector2Array([at+Vector2(-8,3),at+Vector2(-8,-3),at+Vector2(7,-3),at+Vector2(8,4),at+Vector2(-8,3)]),STONE_DARK,2.4,true)
		canvas.draw_line(at+Vector2(-8,1),at+Vector2(8,2),STONE,1.3,true)
	_house(canvas,at,Vector2(5,4),9,STONE if level >= 2 else Color("#a38351"))
	for i in [-2,0,2]:
		canvas.draw_rect(Rect2(at+Vector2(i-0.6,-11),Vector2(1.1,2)),STONE if level >= 2 else Color("#775938"))
	_flag(canvas,at+Vector2(2,-7),color,0)


static func _flag(canvas: CanvasItem, base: Vector2, color: Color, phase: float) -> void:
	canvas.draw_line(base, base + Vector2(0, -10), Color(0.33, 0.28, 0.18), 0.65, true)
	var flutter := sin(phase * 3) * 0.6
	canvas.draw_colored_polygon(PackedVector2Array([base + Vector2(0, -9.5), base + Vector2(5, -9 + flutter),
		base + Vector2(4.8, -5.3 + flutter), base + Vector2(0, -6)]), color)
	canvas.draw_line(base + Vector2(0, -9.5), base + Vector2(5, -9 + flutter), color.lightened(0.3), 0.4, true)
	canvas.draw_circle(base + Vector2(0, -10.5), 0.65, BRONZE)


static func _house(canvas: CanvasItem, at: Vector2, footprint: Vector2, height: float, roof: Color) -> void:
	var rect := Rect2(at - footprint * 0.5, footprint)
	canvas.draw_rect(Rect2(rect.position + Vector2(1.5, 1.5), footprint), SHADOW)
	canvas.draw_rect(Rect2(rect.position + Vector2(0, -height), Vector2(footprint.x, footprint.y + height)), STONE_DARK)
	canvas.draw_rect(Rect2(rect.position + Vector2(0, -height), Vector2(footprint.x * 0.7, footprint.y + height)), STONE)
	var top := rect.position + Vector2(0, -height)
	canvas.draw_colored_polygon(PackedVector2Array([top, top + Vector2(footprint.x * 0.5, -1.7),
		top + Vector2(footprint.x, 0), top + footprint, top + Vector2(0, footprint.y)]), roof)
	canvas.draw_line(top + Vector2(0, 0), top + Vector2(footprint.x * 0.5, -1.7), roof.lightened(0.2), 0.45, true)
	canvas.draw_rect(Rect2(at + Vector2(-0.4, -0.7), Vector2(0.8, 1.1)), STONE_DARK)


static func _tent(canvas: CanvasItem, at: Vector2, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, 1), at + Vector2(0, -3),
		at + Vector2(5, -1), at + Vector2(3, 3)]), color)
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, 1), at + Vector2(0, -3),
		at + Vector2(1.5, 2)]), color.darkened(0.25))
	canvas.draw_line(at + Vector2(0, -3), at + Vector2(5, -1), color.lightened(0.25), 0.45, true)


static func _ellipse(canvas: CanvasItem, at: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(16):
		var a := TAU * i / 16.0
		points.append(at + Vector2(cos(a), sin(a)) * radii)
	canvas.draw_colored_polygon(points, color)
