class_name CommanderArt
## Original vector character studies. Identity comes from a stable person id;
## faction equipment is authored in unit_art.json. No campaign random draws.

static func profile(data: GameData, owner: String, general, force_id: String = "") -> Dictionary:
	var art := UnitArt.for_data(data)
	var culture := String(data.factions.get(owner, {}).get("culture", "neutral"))
	var kit: Dictionary = art.kits.get(culture, art.kits.get("neutral", {}))
	var style: Dictionary = art.commanders.get(owner, kit).duplicate(true)
	var id := String(general["id"]) if general != null else force_id
	style["id"] = id
	style["culture"] = culture
	style["age"] = int(general.get("age", 30)) if general != null else 30
	style["cape"] = Color.html(style.get("cape", data.factions.get(owner, {}).get("color", "#8a7550")))
	style["accent"] = Color.html(style.get("accent", "#d9b970"))
	style["face"] = Color(0.72, 0.51, 0.34).lerp(Color(0.88, 0.71, 0.51), UiStyle.jitter(id, 15))
	style["hair"] = Color(0.16, 0.12, 0.09).lerp(Color(0.44, 0.28, 0.12), UiStyle.jitter(id, 16)) if int(style["age"]) < 55 else Color(0.58, 0.55, 0.46)
	style["horse"] = [Color("#533827"), Color("#a16d42"), Color("#b8afa0"), Color("#302d2b")][int(UiStyle.jitter(id, 17) * 4) % 4]
	style["face_width"] = 0.90 + UiStyle.jitter(id, 18) * 0.22
	style["beard"] = bool(style.get("beard", false)) and UiStyle.jitter(id, 19) > 0.18
	style["scar"] = UiStyle.jitter(id, 20) > 0.65
	return style


static func portrait(canvas: CanvasItem, rect: Rect2, style: Dictionary, selected: bool = false) -> void:
	var texture := RealismPlateCache.request(canvas, style)
	if texture != null:
		canvas.draw_texture_rect(texture, rect, false)
		canvas.draw_rect(rect, UiStyle.ACCENT if selected else UiStyle.EDGE, false, 1.0)
		return
	# All marks stay inside the caller's square. Its exact rect is also a hit target.
	var origin := rect.position
	var scale := rect.size / 100.0
	canvas.draw_set_transform(origin, 0, scale)
	var cape: Color = style["cape"]
	var metal: Color = style["accent"]
	var face: Color = style["face"]
	var hair: Color = style["hair"]
	var ink := Color("#171e1e")
	canvas.draw_rect(Rect2(0, 0, 100, 100), Color("#18292c"))
	canvas.draw_circle(Vector2(50, 48), 42, cape.darkened(0.57))
	canvas.draw_arc(Vector2(50, 48), 40, PI * 0.95, TAU * 0.97, 48, Color(metal, 0.3), 1.0, true)
	_poly(canvas, [Vector2(8,100),Vector2(15,78),Vector2(36,65),Vector2(65,64),Vector2(86,78),Vector2(94,100)], cape)
	_poly(canvas, [Vector2(25,100),Vector2(31,77),Vector2(45,70),Vector2(65,75),Vector2(78,100)], Color("#62655b"))
	_poly(canvas, [Vector2(50,72),Vector2(68,79),Vector2(79,100),Vector2(53,100)], Color("#343f3e"))
	var armour := String(style.get("armour", "mail"))
	for row in range(4):
		for col in range(5):
			var at := Vector2(33 + col * 8 + (row % 2) * 2, 81 + row * 5)
			if armour in ["mail", "scale"]:
				canvas.draw_arc(at, 2.8, 0.0, PI, 7, Color(metal, 0.45), 0.8, true)
			elif armour == "linen":
				canvas.draw_line(at, at + Vector2(0, 4), Color("#b4aa89"), 2, true)
	_poly(canvas, [Vector2(38,59),Vector2(61,58),Vector2(63,73),Vector2(50,80),Vector2(37,70)], face.darkened(0.20))
	var w := float(style["face_width"])
	var left := 50 - 18 * w
	var right := 50 + 17 * w
	_poly(canvas, [Vector2(left,30),Vector2(48,24),Vector2(right,32),Vector2(right-1,55),Vector2(60,69),Vector2(48,74),Vector2(left+4,62)], face)
	_poly(canvas, [Vector2(51,26),Vector2(right,32),Vector2(right-1,55),Vector2(60,69),Vector2(49,73),Vector2(57,57)], face.darkened(0.22))
	canvas.draw_circle(Vector2(left,48), 4, face.darkened(0.13))
	_poly(canvas, [Vector2(49,40),Vector2(47,56),Vector2(54,56),Vector2(53,53)], face.lightened(0.13))
	canvas.draw_line(Vector2(left+6,42), Vector2(46,41), hair, 2, true)
	canvas.draw_line(Vector2(55,41), Vector2(right-4,43), hair, 2, true)
	canvas.draw_line(Vector2(left+7,46), Vector2(44,46), ink, 1.8, true)
	canvas.draw_line(Vector2(56,46), Vector2(right-5,47), ink, 1.8, true)
	canvas.draw_circle(Vector2(42,45), 0.7, Color("#f7ead1"))
	canvas.draw_line(Vector2(45,62), Vector2(57,62), face.darkened(0.5), 1.2, true)
	if style["beard"]:
		_poly(canvas, [Vector2(left+3,52),Vector2(43,61),Vector2(51,64),Vector2(61,58),Vector2(right-1,51),Vector2(61,72),Vector2(49,78),Vector2(left+6,64)], hair)
		canvas.draw_line(Vector2(43,61), Vector2(56,62), face.darkened(0.25), 1.3, true)
		for i in range(4):
			canvas.draw_line(Vector2(41+i*5,65), Vector2(44+i*4,72), hair.lightened(0.1), 0.7, true)
	if style["scar"]:
		canvas.draw_line(Vector2(right-7,49), Vector2(right-10,57), face.lightened(0.23), 1, true)
	if int(style["age"]) >= 50:
		canvas.draw_line(Vector2(left+5,49), Vector2(left+11,51), face.darkened(0.3), 0.7, true)
		canvas.draw_line(Vector2(58,56), Vector2(61,61), face.darkened(0.25), 0.7, true)
	var helmet := String(style.get("helmet", "cap"))
	match helmet:
		"crest", "plume":
			_poly(canvas, [Vector2(29,34),Vector2(32,23),Vector2(46,18),Vector2(63,21),Vector2(72,34)], metal.darkened(0.17))
			_poly(canvas, [Vector2(30,33),Vector2(35,24),Vector2(48,20),Vector2(51,33)], metal.lightened(0.1))
			canvas.draw_line(Vector2(28,35), Vector2(73,35), metal, 3, true)
			_poly(canvas, [Vector2(30,35),Vector2(37,39),Vector2(38,57),Vector2(32,61)], metal.darkened(0.16))
			_poly(canvas, [Vector2(64,37),Vector2(70,36),Vector2(66,59),Vector2(61,56)], metal.darkened(0.33))
			if helmet == "crest":
				_poly(canvas, [Vector2(41,20),Vector2(35,11),Vector2(44,5),Vector2(61,6),Vector2(72,15),Vector2(68,27),Vector2(58,20)], cape.lightened(0.25))
				for i in range(6):
					canvas.draw_line(Vector2(43+i*4,9), Vector2(47+i*3,21), cape.darkened(0.3), 0.8, true)
			else:
				_poly(canvas, [Vector2(46,20),Vector2(44,6),Vector2(52,3),Vector2(59,9),Vector2(59,24)], cape.lightened(0.3))
		"conical":
			_poly(canvas, [Vector2(28,36),Vector2(49,7),Vector2(73,35)], metal.darkened(0.2))
			_poly(canvas, [Vector2(29,35),Vector2(49,9),Vector2(47,34)], metal.lightened(0.10))
			canvas.draw_line(Vector2(27,36), Vector2(74,36), metal, 3, true)
			canvas.draw_line(Vector2(30,38), Vector2(28,68), Color("#6e746b"), 6, true)
		"headcloth":
			_poly(canvas, [Vector2(29,39),Vector2(24,26),Vector2(37,16),Vector2(61,17),Vector2(75,29),Vector2(69,39),Vector2(68,67),Vector2(80,77),Vector2(66,78),Vector2(62,32),Vector2(36,34),Vector2(31,77),Vector2(20,78)], metal)
			canvas.draw_line(Vector2(28,29), Vector2(70,30), cape, 3, true)
		"cap":
			_poly(canvas, [Vector2(29,34),Vector2(31,22),Vector2(51,16),Vector2(68,25),Vector2(72,36)], metal.darkened(0.25))
			canvas.draw_line(Vector2(29,36), Vector2(71,37), metal, 2, true)
		_:
			_poly(canvas, [Vector2(28,46),Vector2(28,29),Vector2(35,20),Vector2(51,16),Vector2(67,24),Vector2(71,41),Vector2(63,33),Vector2(48,29),Vector2(35,35),Vector2(34,49)], hair)
			if helmet == "diadem":
				canvas.draw_arc(Vector2(50,32), 20, PI * 1.02, TAU * 0.99, 24, metal, 3, true)
				canvas.draw_circle(Vector2(49,29), 2.5, metal.lightened(0.2))
	canvas.draw_circle(Vector2(28,80), 4, metal)
	canvas.draw_circle(Vector2(28,80), 2.3, metal.darkened(0.35))
	canvas.draw_rect(Rect2(0,0,100,100), UiStyle.CAPITAL_GOLD if selected else Color(metal,0.75), false, 2)
	canvas.draw_set_transform(Vector2.ZERO)


static func _poly(canvas: CanvasItem, points: Array, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array(points), color)
