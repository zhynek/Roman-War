class_name ArtPainter
extends RefCounted
## Paints a resolved plate into any Rect2 on any CanvasItem — a hero plate, a
## ladder thumbnail, or a contact-sheet cell. It never looks anything up:
## everything it needs is already in the plate, colours included.
##
## The house style is map_view.gd's: flat shapes, a lit face and a shadow face
## with the sun at the upper left, an inked silhouette, and sizes wobbled by a
## hash rather than a random number. _draw_wonder there — a temple front from
## four draw_rects and one polygon — is the seed this grew from.

const STAGE_ASPECT := 1.6
const SKIES := {
	"clear": ["#6f8fa6", "#cdc4a8"],
	"dust": ["#8a8468", "#d6c49a"],
	"overcast": ["#8c9199", "#b9bcbb"],
}
const SEA_DEEP := Color(0.043, 0.086, 0.133)
const SHELF := Color(0.125, 0.235, 0.320)
const SHOAL := Color(0.180, 0.330, 0.420)
const LAND_BASE := Color(0.42, 0.42, 0.33)
const COAST_INK := Color(0.86, 0.80, 0.66, 0.85)
const LUSH := Color(0.435, 0.604, 0.306)
const ARID := Color(0.725, 0.647, 0.455)
const SEAT := Color(0.02, 0.03, 0.05, 0.34)
const TERRAIN_BASE := {
	"plains": Color(0.494, 0.549, 0.337),
	"hills": Color(0.612, 0.518, 0.314),
	"mountains": Color(0.541, 0.510, 0.478),
	"forest": Color(0.310, 0.420, 0.271),
	"desert": Color(0.769, 0.663, 0.435),
	"steppe": Color(0.702, 0.682, 0.475),
	"marsh": Color(0.392, 0.459, 0.376),
}
const FLAME := [Color(0.949, 0.757, 0.290), Color(0.878, 0.541, 0.173), Color(0.722, 0.271, 0.165)]


static func stage_of(rect: Rect2) -> Rect2:
	## One 8:5 stage centred in whatever box the panel gives us, so a big hero
	## plate and a small ladder thumbnail place every part identically and only
	## the scale changes. Nothing is ever stretched.
	var inner := rect.grow(-maxf(2.0, rect.size.y * 0.03))
	var span := inner.size
	if span.x / maxf(span.y, 0.001) > STAGE_ASPECT:
		span.x = span.y * STAGE_ASPECT
	else:
		span.y = span.x / STAGE_ASPECT
	return Rect2(inner.position + (inner.size - span) * 0.5, span)


static func place(stage: Rect2, r: Rect2) -> Rect2:
	return Rect2(stage.position + r.position * stage.size, r.size * stage.size)


static func paint(ci: CanvasItem, plate: Dictionary, rect: Rect2, font: Font = null) -> void:
	if plate.is_empty():
		_last_resort(ci, rect, "", font)
		return
	var scene: Dictionary = plate.get("scene", {})
	var stage := stage_of(rect)
	var u := stage.size.y
	var lod := int(plate.get("lod", 2))

	_sky(ci, rect, stage, scene)
	_relief(ci, rect, stage, scene, lod)
	if float(scene.get("water", 0.0)) > 0.0:
		_water(ci, rect, stage, scene)
	_ground(ci, rect, stage, scene)

	var parts: Array = plate.get("parts", [])
	if parts.is_empty():
		_last_resort(ci, rect, String(plate.get("title", "")), font)
		return
	_seat(ci, stage, parts)
	for part in parts:
		if int(part["lod"]) > lod:
			continue
		_dispatch(ci, String(part["part"]), place(stage, part["rect"]),
			part["shade"], part["p"], u, String(part["seed"]))
	_figures(ci, stage, scene, u)
	_weather(ci, stage, scene, u)
	_state(ci, stage, scene, parts, u)
	_chrome(ci, rect)


static func _dispatch(ci: CanvasItem, name: String, b: Rect2, s: Dictionary,
		p: Dictionary, u: float, seed: String) -> void:
	match name:
		"box": _box(ci, b, s, p, u, seed)
		"podium": _podium(ci, b, s, p, u, seed)
		"steps": _steps(ci, b, s, p, u, seed)
		"column_row": _column_row(ci, b, s, p, u, seed)
		"entablature": _entablature(ci, b, s, p, u, seed)
		"pediment": _pediment(ci, b, s, p, u, seed)
		"roof": _roof(ci, b, s, p, u, seed)
		"arcade": _arcade(ci, b, s, p, u, seed)
		"crest": _crest(ci, b, s, p, u, seed)
		"bank": _bank(ci, b, s, p, u, seed)
		"posts": _posts(ci, b, s, p, u, seed)
		"mound": _mound(ci, b, s, p, u, seed)
		"awning": _awning(ci, b, s, p, u, seed)
		"stall": _stall(ci, b, s, p, u, seed)
		"vessels": _vessels(ci, b, s, p, u, seed)
		"granary": _granary(ci, b, s, p, u, seed)
		"forge": _forge(ci, b, s, p, u, seed)
		"smoke": _smoke(ci, b, s, p, u, seed)
		"well": _well(ci, b, s, p, u, seed)
		"statue": _statue(ci, b, s, p, u, seed)
		"altar": _altar(ci, b, s, p, u, seed)
		"standard": _standard(ci, b, s, p, u, seed)
		"emblem": _emblem(ci, b, s, p, u, seed)
		"crowd": _crowd(ci, b, s, p, u, seed)
		"figure": _figure(ci, b, s, p, u, seed)
		"tree": _tree(ci, b, s, p, u, seed)
		"beasts": _beasts(ci, b, s, p, u, seed)
		"field_strips": _field_strips(ci, b, s, p, u, seed)
		"hull": _hull(ci, b, s, p, u, seed)
		"quay": _quay(ci, b, s, p, u, seed)
		"mine_head": _mine_head(ci, b, s, p, u, seed)
		"canopy": _canopy(ci, b, s, p, u, seed)
		"obelisk": _obelisk(ci, b, s, p, u, seed)
		"pylon": _pylon(ci, b, s, p, u, seed)
		"stones": _stones(ci, b, s, p, u, seed)
		"trophy": _trophy(ci, b, s, p, u, seed)
		"stele": _stele(ci, b, s, p, u, seed)
		"rubble": _rubble(ci, b, s, p, u, seed)
		"scaffold": _scaffold(ci, b, s, p, u, seed)
		# An unknown name draws a plausible block rather than a hole. The schema
		# and the validator make it unreachable from authored data.
		_: _box(ci, b, s, p, u, seed)


## --- scene ----------------------------------------------------------------

static func _sky(ci: CanvasItem, rect: Rect2, stage: Rect2, scene: Dictionary) -> void:
	var pair: Array = SKIES.get(String(scene.get("sky", "clear")), SKIES["clear"])
	var top := Color.html(String(pair[0]))
	var low := Color.html(String(pair[1]))
	if String(scene.get("season", "summer")) == "winter":
		var cold := Color(0.604, 0.659, 0.722)
		top = top.lerp(cold, 0.30)
		low = low.lerp(cold, 0.22)
	var horizon := stage.position.y + stage.size.y * float(scene.get("horizon", 0.56))
	ci.draw_polygon(PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, horizon), Vector2(rect.position.x, horizon)]),
		PackedColorArray([top, top, low, low]))
	# The far plain between the horizon and the near ground. Without it the
	# panel background shows through as a dark band across the middle.
	var near := stage.position.y + stage.size.y * float(scene.get(
		"water", scene.get("ground", 0.80)))
	if near > horizon:
		var terrain := String(scene.get("terrain", "plains"))
		var far: Color = LAND_BASE.lerp(TERRAIN_BASE.get(terrain, TERRAIN_BASE["plains"]), 0.6)
		far = far.lerp(low, 0.55)
		ci.draw_polygon(PackedVector2Array([
			Vector2(rect.position.x, horizon), Vector2(rect.end.x, horizon),
			Vector2(rect.end.x, near), Vector2(rect.position.x, near)]),
			PackedColorArray([far, far, far.darkened(0.12), far.darkened(0.12)]))


static func _relief(ci: CanvasItem, rect: Rect2, stage: Rect2, scene: Dictionary, lod: int) -> void:
	## The province's own terrain on the horizon, drawn with the map's glyphs —
	## the strongest tie between a plate and the world it stands in.
	if lod < 1:
		return
	var terrain := String(scene.get("terrain", "plains"))
	var pair: Array = SKIES.get(String(scene.get("sky", "clear")), SKIES["clear"])
	var haze := Color.html(String(pair[1]))
	# Aerial perspective: distance is drawn by fading toward the sky, not by
	# shrinking. Too much contrast here and the horizon reads as floating arcs
	# in front of the building instead of hills behind it.
	var base: Color = TERRAIN_BASE.get(terrain, TERRAIN_BASE["plains"]).lerp(haze, 0.78)
	var shade := {
		"lit": Color(base.lightened(0.04), 0.55), "mid": Color(base, 0.55),
		"shadow": Color(base.darkened(0.08), 0.55),
		"ink": Color(base.darkened(0.30), 0.16), "water": Color(base, 0.40),
		"furrow": Color(base.darkened(0.14), 0.12), "snow": false,
	}
	var line := stage.position.y + stage.size.y * float(scene.get("horizon", 0.56))
	var span := stage.size.y * 0.045
	var count := 9
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var roll := ArtNoise.hash01(terrain + String(scene.get("sky", "")), i * 7 + 3)
		var p := Vector2(lerpf(rect.position.x - span, rect.end.x + span, t),
			line + span * 0.25 * ArtNoise.swing(terrain, i, 1.0))
		var s := span / 12.0 * (0.8 + roll * 0.5)
		match terrain:
			"mountains": ReliefGlyphs.mountain(ci, p, s * 1.5, roll, shade, true)
			"forest": ReliefGlyphs.tree(ci, p, s * 1.7, roll, shade)
			"hills": ReliefGlyphs.hill(ci, p, s * 2.0, roll, shade)
			"desert": ReliefGlyphs.dune(ci, p, s * 1.6, roll, shade)
			"marsh": ReliefGlyphs.reed(ci, p, s * 1.8, roll, shade)
			"steppe": ReliefGlyphs.tuft(ci, p, s * 2.0, roll, shade)
			_: ReliefGlyphs.hill(ci, p, s * 1.4, roll, shade)


static func _water(ci: CanvasItem, rect: Rect2, stage: Rect2, scene: Dictionary) -> void:
	var line := stage.position.y + stage.size.y * float(scene.get("horizon", 0.50))
	var shore := stage.position.y + stage.size.y * float(scene.get("water", 0.60))
	ci.draw_polygon(PackedVector2Array([
		Vector2(rect.position.x, line), Vector2(rect.end.x, line),
		Vector2(rect.end.x, shore), Vector2(rect.position.x, shore)]),
		PackedColorArray([SEA_DEEP, SEA_DEEP, SHOAL, SHOAL]))
	for i in 3:
		var y := lerpf(line, shore, (float(i) + 1.0) / 4.0)
		ci.draw_dashed_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y),
			Color(SHELF, 0.45), maxf(1.0, stage.size.y * 0.006), stage.size.y * 0.03)


static func _ground(ci: CanvasItem, rect: Rect2, stage: Rect2, scene: Dictionary) -> void:
	var terrain := String(scene.get("terrain", "plains"))
	var base: Color = LAND_BASE.lerp(TERRAIN_BASE.get(terrain, TERRAIN_BASE["plains"]), 0.60)
	var f := clampf(float(scene.get("fertility", 1.5)) / 3.0, 0.0, 1.0) - 0.5
	base = base.lerp(LUSH if f > 0.0 else ARID, absf(f) * 0.30)
	if String(scene.get("season", "summer")) == "winter":
		base = base.lerp(Color(0.78, 0.80, 0.82), 0.24)
	var top := stage.position.y + stage.size.y * float(scene.get("ground", 0.80))
	if scene.has("water"):
		top = stage.position.y + stage.size.y * float(scene["water"])
	ci.draw_polygon(PackedVector2Array([
		Vector2(rect.position.x, top), Vector2(rect.end.x, top),
		rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([base, base, base.darkened(0.20), base.darkened(0.20)]))
	var furrow := Color(base.darkened(0.26), 0.20)
	for i in 8:
		var y := lerpf(top, rect.end.y, (float(i) + 0.6) / 8.0)
		var wobble := stage.size.y * 0.012 * ArtNoise.noise(terrain + "g", float(i))
		ci.draw_line(Vector2(rect.position.x, y + wobble), Vector2(rect.end.x, y - wobble),
			furrow, maxf(1.0, stage.size.y * 0.004))


static func _seat(ci: CanvasItem, stage: Rect2, parts: Array) -> void:
	## The same soft ellipse map_view draws under every settlement token.
	## Without it the building floats off the ground.
	var span := Rect2()
	var first := true
	for part in parts:
		if int(part["z"]) >= 2000:
			continue
		var r: Rect2 = part["rect"]
		if first:
			span = r
			first = false
		else:
			span = span.merge(r)
	if first:
		return
	var centre := place(stage, Rect2(span.position.x, span.end.y, span.size.x, 0.001))
	var ring := PackedVector2Array()
	for k in 16:
		var a := TAU * float(k) / 16.0
		ring.append(Vector2(centre.position.x + centre.size.x * 0.5, centre.position.y)
			+ Vector2(cos(a) * centre.size.x * 0.56, sin(a) * stage.size.y * 0.022))
	ci.draw_colored_polygon(ring, SEAT)


static func _figures(ci: CanvasItem, stage: Rect2, scene: Dictionary, u: float) -> void:
	## The scale figure never changes size, which is the whole trick: a tier-5
	## wall is visibly five people tall, a tier-1 rampart is not.
	var shade := {"lit": Color(0.30, 0.28, 0.26), "mid": Color(0.22, 0.21, 0.20),
		"shadow": Color(0.15, 0.14, 0.14), "ink": Color(0.10, 0.10, 0.10, 0.65),
		"grain": Color(0, 0, 0, 0.10), "edge": 0.9}
	for spot in scene.get("figures", []):
		var at := Vector2(float(spot[0]), float(spot[1]))
		var height := 0.115
		var box := place(stage, Rect2(at.x - 0.020, at.y - height, 0.040, height))
		_figure(ci, box, shade, {"stance": "guard"}, u, "scale%f" % at.x)


static func _weather(ci: CanvasItem, stage: Rect2, scene: Dictionary, u: float) -> void:
	if String(scene.get("season", "summer")) != "winter":
		return
	ci.draw_rect(stage, Color(0.85, 0.89, 0.94, 0.10))


static func _state(ci: CanvasItem, stage: Rect2, scene: Dictionary, parts: Array, u: float) -> void:
	var progress := float(scene.get("progress", 1.0))
	if progress < 1.0:
		var span := Rect2()
		var first := true
		for part in parts:
			var r: Rect2 = part["rect"]
			span = r if first else span.merge(r)
			first = false
		if not first:
			var box := place(stage, span)
			box.size.y *= (1.0 - progress)
			_scaffold(ci, box, {"lit": Color(0.60, 0.45, 0.28, 0.55),
				"mid": Color(0.48, 0.36, 0.22, 0.55), "shadow": Color(0.30, 0.22, 0.13, 0.55),
				"ink": Color(0.20, 0.15, 0.09, 0.5), "grain": Color(0, 0, 0, 0.1), "edge": 0.7},
				{"bays": 5, "ladders": 2}, u, "scaffold")
	if bool(scene.get("damaged", false)):
		_rubble(ci, place(stage, Rect2(0.16, 0.86, 0.68, 0.08)),
			{"lit": Color(0.55, 0.52, 0.47), "mid": Color(0.42, 0.39, 0.35),
			 "shadow": Color(0.25, 0.23, 0.21), "ink": Color(0.14, 0.13, 0.12, 0.6),
			 "grain": Color(0, 0, 0, 0.1), "edge": 0.8},
			{"count": 7}, u, "rubble")


static func _chrome(ci: CanvasItem, rect: Rect2) -> void:
	var edge := maxf(1.0, rect.size.y * 0.006)
	ci.draw_rect(rect, Color(0, 0, 0, 0.10), false, edge * 3.0)
	ci.draw_rect(rect, COAST_INK, false, edge)


static func _last_resort(ci: CanvasItem, rect: Rect2, title: String, font: Font) -> void:
	## Reached only if the whole art table is missing. Even then a building
	## stands on a ground plane rather than a blank panel.
	var stage := stage_of(rect)
	var scene := {"sky": "clear", "horizon": 0.56, "ground": 0.80, "terrain": "plains",
		"fertility": 1.5, "figures": [[0.12, 0.87]]}
	_sky(ci, rect, stage, scene)
	_ground(ci, rect, stage, scene)
	var shade := {"lit": Color(0.72, 0.68, 0.58), "mid": Color(0.58, 0.55, 0.47),
		"shadow": Color(0.36, 0.34, 0.29), "ink": Color(0.20, 0.19, 0.16, 0.6),
		"grain": Color(0, 0, 0, 0.12), "edge": 0.9, "strokes": 2}
	var w := 0.30 + 0.20 * ArtNoise.hash01(title, 1)
	_box(ci, place(stage, Rect2(0.5 - w * 0.5, 0.62, w, 0.20)), shade,
		{"courses": 3, "openings": 2}, stage.size.y, title)
	_roof(ci, place(stage, Rect2(0.5 - w * 0.58, 0.52, w * 1.16, 0.10)), shade,
		{"style": "tiled", "pitch": 0.45, "ribs": 6}, stage.size.y, title)
	_figures(ci, stage, scene, stage.size.y)
	_chrome(ci, rect)


## --- masonry --------------------------------------------------------------

static func _box(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	## The workhorse: a curtain wall, a tower, a warehouse, a lighthouse and a
	## market table are all this with different params.
	var batter := float(p.get("batter", 0.0)) * b.size.x * 0.5
	var face := PackedVector2Array([
		b.position + Vector2(batter, 0.0),
		Vector2(b.end.x - batter, b.position.y),
		b.end, Vector2(b.position.x, b.end.y)])
	ci.draw_colored_polygon(face, s["mid"])
	# Sun at the upper left, the convention _glyph_mountain sets.
	var seam_top := face[1].lerp(face[0], 0.34)
	var seam_bot := face[2].lerp(face[3], 0.34)
	ci.draw_colored_polygon(PackedVector2Array([seam_top, face[1], face[2], seam_bot]), s["shadow"])
	ci.draw_rect(Rect2(face[0], Vector2(maxf(face[1].x - face[0].x, 1.0),
		maxf(1.0, u * 0.012))), s["lit"])
	var courses := int(p.get("courses", 0))
	for k in courses:
		var y := lerpf(b.position.y, b.end.y, float(k + 1) / float(courses + 1))
		ci.draw_line(Vector2(b.position.x + u * 0.010, y), Vector2(b.end.x - u * 0.010, y),
			s["grain"], maxf(1.0, u * 0.004))
	var openings := int(p.get("openings", 0))
	for k in openings:
		var ox := lerpf(b.position.x, b.end.x, (float(k) + 1.0) / (float(openings) + 1.0))
		ci.draw_rect(Rect2(ox - b.size.x * 0.05, b.position.y + b.size.y * 0.32,
			maxf(b.size.x * 0.10, 1.0), maxf(b.size.y * 0.46, 1.0)),
			Color(s["mid"].darkened(0.55), 0.85))
	var slits := int(p.get("slits", 0))
	for k in slits:
		var sx := lerpf(b.position.x, b.end.x, (float(k) + 1.0) / (float(slits) + 1.0))
		ci.draw_rect(Rect2(sx - u * 0.005, b.position.y + b.size.y * 0.22,
			maxf(u * 0.010, 1.0), maxf(b.size.y * 0.26, 1.0)), s["ink"])
	var ring := face.duplicate()
	ring.append(face[0])
	ci.draw_polyline(ring, s["ink"], maxf(1.0, u * 0.007 * float(s.get("edge", 0.8))))
	match String(p.get("cap", "none")):
		"crenel":
			_crest(ci, Rect2(b.position - Vector2(0.0, u * 0.034),
				Vector2(b.size.x, u * 0.034)), s,
				{"style": "crenel", "count": maxi(3, int(b.size.x / maxf(u * 0.055, 1.0)))}, u, seed)
		"cornice":
			ci.draw_rect(Rect2(b.position - Vector2(u * 0.012, u * 0.020),
				Vector2(b.size.x + u * 0.024, u * 0.020)), s["lit"])
		"hoard":
			ci.draw_rect(Rect2(b.position - Vector2(u * 0.020, u * 0.028),
				Vector2(b.size.x + u * 0.040, u * 0.028)), s["shadow"])


static func _podium(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	_box(ci, b, s, {"courses": p.get("courses", 2)}, u, seed)
	if bool(p.get("moulding", true)):
		ci.draw_rect(Rect2(b.position - Vector2(u * 0.010, u * 0.014),
			Vector2(b.size.x + u * 0.020, u * 0.014)), s["lit"])
		ci.draw_rect(Rect2(Vector2(b.position.x - u * 0.006, b.end.y - u * 0.012),
			Vector2(b.size.x + u * 0.012, u * 0.012)), s["shadow"])


static func _steps(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var count := maxi(1, int(p.get("count", 3)))
	for k in count:
		var inset := b.size.x * 0.06 * float(count - 1 - k)
		var y := b.position.y + b.size.y * float(k) / float(count)
		ci.draw_rect(Rect2(b.position.x + inset, y,
			maxf(b.size.x - inset * 2.0, 1.0), maxf(b.size.y / float(count), 1.0)),
			s["lit"] if k % 2 == 0 else s["mid"])
	ci.draw_line(b.position, Vector2(b.position.x, b.end.y), s["ink"], maxf(1.0, u * 0.005))


static func _column_row(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	## Doric-ish and Ionic-ish in PROPORTION only — a tapered shaft, a square
	## abacus, an echinus lip, two small volutes for ionic. No copied ornament.
	## This is _draw_wonder's pair of column rects, generalised.
	var count := clampi(int(p.get("columns", 4)), 1, 12)
	var ionic := String(p.get("order", "tuscan")) == "ionic"
	var slender := 7.4 if ionic else 6.2
	var spacing := float(p.get("spacing", 1.9))
	var diameter := minf(b.size.x / (float(count) - 1.0 + spacing), b.size.y / slender)
	diameter = maxf(diameter, 1.0)
	var gap := (b.size.x - diameter) / maxf(float(count) - 1.0, 1.0)
	var cap_h := diameter * (0.52 if ionic else 0.40)
	var base_h := diameter * 0.28
	for i in count:
		var cx := b.position.x + diameter * 0.5 + gap * float(i)
		var top := b.position.y + cap_h
		var bottom := b.end.y - base_h
		var half := diameter * 0.5
		var lean := ArtNoise.swing(seed, i, 0.010) * diameter
		var shaft := PackedVector2Array([
			Vector2(cx - half * 0.88 + lean, top), Vector2(cx + half * 0.88 + lean, top),
			Vector2(cx + half, bottom), Vector2(cx - half, bottom)])
		ci.draw_colored_polygon(shaft, s["mid"])
		ci.draw_colored_polygon(PackedVector2Array([
			shaft[0].lerp(shaft[1], 0.62), shaft[1], shaft[2],
			shaft[3].lerp(shaft[2], 0.62)]), s["shadow"])
		ci.draw_rect(Rect2(cx - half * 1.16, bottom, diameter * 1.16, maxf(base_h, 1.0)), s["mid"])
		ci.draw_rect(Rect2(cx - half * 1.22, top - cap_h * 0.42,
			diameter * 1.22, maxf(cap_h * 0.42, 1.0)), s["lit"])
		if ionic:
			ci.draw_arc(Vector2(cx - half * 0.86, top - cap_h * 0.18), diameter * 0.22,
				PI, TAU, 8, s["ink"], maxf(1.0, u * 0.006))
			ci.draw_arc(Vector2(cx + half * 0.86, top - cap_h * 0.18), diameter * 0.22,
				PI, TAU, 8, s["ink"], maxf(1.0, u * 0.006))
		if u > 150.0 and float(s.get("edge", 0.8)) > 0.8:
			for f in [-0.34, 0.34]:
				ci.draw_line(Vector2(cx + half * f, top), Vector2(cx + half * f, bottom),
					s["grain"], maxf(1.0, u * 0.003))


static func _entablature(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var third := b.size.y / 3.0
	ci.draw_rect(Rect2(b.position, Vector2(b.size.x, maxf(third, 1.0))), s["mid"])
	ci.draw_rect(Rect2(b.position + Vector2(0.0, third), Vector2(b.size.x, maxf(third, 1.0))), s["shadow"])
	if bool(p.get("cornice", true)):
		ci.draw_rect(Rect2(b.position - Vector2(u * 0.012, 0.0),
			Vector2(b.size.x + u * 0.024, maxf(third * 0.9, 1.0))), s["lit"])
	if String(p.get("order", "tuscan")) == "tuscan":
		var count := maxi(3, int(b.size.x / maxf(u * 0.055, 1.0)))
		for k in count:
			var x := lerpf(b.position.x, b.end.x, (float(k) + 0.5) / float(count))
			ci.draw_line(Vector2(x, b.position.y + third), Vector2(x, b.position.y + third * 2.0),
				s["ink"], maxf(1.0, u * 0.004))


static func _pediment(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var apex := Vector2(b.position.x + b.size.x * 0.5, b.position.y)
	var left := Vector2(b.position.x, b.end.y)
	var right := Vector2(b.end.x, b.end.y)
	ci.draw_colored_polygon(PackedVector2Array([left, apex, right]), s["mid"])
	ci.draw_colored_polygon(PackedVector2Array([
		left.lerp(apex, 0.18) + Vector2(0.0, -u * 0.004),
		apex.lerp(right, 0.82) + Vector2(0.0, -u * 0.004),
		right.lerp(left, 0.16) + Vector2(0.0, -u * 0.010)]), s["shadow"])
	ci.draw_polyline(PackedVector2Array([left, apex, right]), s["lit"], maxf(1.0, u * 0.010))
	var device := String(p.get("tympanum", "none"))
	if device != "none" and device != "":
		_emblem(ci, Rect2(apex.x - b.size.x * 0.10, b.position.y + b.size.y * 0.32,
			b.size.x * 0.20, b.size.y * 0.42), s, {"kind": device}, u, seed)
	var akroteria := int(p.get("akroteria", 0))
	if akroteria > 0:
		for spot in [apex, left, right]:
			ci.draw_circle(spot + Vector2(0.0, -u * 0.008), maxf(u * 0.008, 1.0), s["lit"])
	if akroteria >= 5:
		for f in [0.30, 0.70]:
			var mid := left.lerp(right, f)
			ci.draw_circle(Vector2(mid.x, lerpf(b.end.y, b.position.y, 0.4)),
				maxf(u * 0.006, 1.0), s["lit"])


static func _roof(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var style := String(p.get("style", "tiled"))
	var pitch := float(p.get("pitch", 0.45))
	match style:
		"thatch":
			var ridge := b.position.y
			var eaves := b.end.y
			var pts := PackedVector2Array([
				Vector2(b.position.x + b.size.x * 0.16, ridge),
				Vector2(b.end.x - b.size.x * 0.16, ridge)])
			var teeth := maxi(6, int(p.get("ribs", 8)) * 3)
			for k in range(teeth + 1):
				var t := float(k) / float(teeth)
				pts.append(Vector2(lerpf(b.end.x, b.position.x, t),
					eaves + u * 0.010 * ArtNoise.hash01(seed, k)))
			ci.draw_colored_polygon(pts, s["mid"])
			for k in int(p.get("ribs", 8)):
				var x := lerpf(b.position.x, b.end.x, (float(k) + 0.5) / float(p.get("ribs", 8)))
				ci.draw_line(Vector2(lerpf(x, b.position.x + b.size.x * 0.5, 0.6), ridge),
					Vector2(x, eaves), s["grain"], maxf(1.0, u * 0.004))
		"dome", "conical":
			var arc := PackedVector2Array()
			var steps := 14
			for k in range(steps + 1):
				var a := PI + PI * float(k) / float(steps)
				arc.append(Vector2(b.position.x + b.size.x * 0.5, b.end.y)
					+ Vector2(cos(a) * b.size.x * 0.5, sin(a) * b.size.y / maxf(pitch, 0.2) * 0.5))
			arc.append(Vector2(b.end.x, b.end.y))
			ci.draw_colored_polygon(arc, s["mid"])
			ci.draw_polyline(arc, s["ink"], maxf(1.0, u * 0.005))
			ci.draw_circle(Vector2(b.position.x + b.size.x * 0.5,
				b.end.y - b.size.y / maxf(pitch, 0.2) * 0.5), maxf(u * 0.008, 1.0), s["lit"])
		_:
			var slab := PackedVector2Array([
				Vector2(b.position.x + b.size.x * 0.14, b.position.y),
				Vector2(b.end.x - b.size.x * 0.14, b.position.y),
				Vector2(b.end.x, b.end.y), Vector2(b.position.x, b.end.y)])
			ci.draw_colored_polygon(slab, s["mid"])
			ci.draw_colored_polygon(PackedVector2Array([
				slab[0].lerp(slab[1], 0.55), slab[1], slab[2], slab[3].lerp(slab[2], 0.55)]),
				s["shadow"])
			var ribs := maxi(2, int(p.get("ribs", 7)))
			for k in range(1, ribs):
				var t := float(k) / float(ribs)
				ci.draw_line(slab[0].lerp(slab[1], t), slab[3].lerp(slab[2], t),
					s["grain"], maxf(1.0, u * 0.004))
			ci.draw_rect(Rect2(slab[0], Vector2(maxf(slab[1].x - slab[0].x, 1.0),
				maxf(u * 0.012, 1.0))), s["lit"])
			ci.draw_polyline(PackedVector2Array([slab[3], slab[0], slab[1], slab[2]]),
				s["ink"], maxf(1.0, u * 0.005))


static func _arcade(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var count := clampi(int(p.get("count", 3)), 1, 14)
	var round_arch := String(p.get("arch", "round")) == "round"
	var dark := float(p.get("dark", 0.45))
	var bay := b.size.x / float(count)
	var pier := maxf(bay * 0.26, u * 0.010)
	ci.draw_rect(b, s["mid"])
	ci.draw_rect(Rect2(b.position, Vector2(b.size.x, maxf(u * 0.010, 1.0))), s["lit"])
	for k in count:
		var x0 := b.position.x + bay * float(k) + pier * 0.5
		var w := maxf(bay - pier, 1.0)
		var head := minf(w * 0.5, b.size.y * 0.52)
		var top := b.position.y + b.size.y * 0.18 + (head if round_arch else 0.0)
		ci.draw_rect(Rect2(x0, top, w, maxf(b.end.y - top, 1.0)),
			Color(s["mid"].darkened(dark), 0.92))
		if round_arch:
			var centre := Vector2(x0 + w * 0.5, top)
			var poly := PackedVector2Array()
			for j in range(13):
				var a := PI + PI * float(j) / 12.0
				poly.append(centre + Vector2(cos(a) * w * 0.5, sin(a) * head))
			poly.append(Vector2(x0 + w, top))
			poly.append(Vector2(x0, top))
			ci.draw_colored_polygon(poly, Color(s["mid"].darkened(dark), 0.92))
			ci.draw_arc(centre, w * 0.5, PI, TAU, 14, s["ink"], maxf(1.0, u * 0.005))
			var voussoirs := int(p.get("voussoirs", 0))
			for j in voussoirs:
				var a2 := PI + PI * (float(j) + 0.5) / float(voussoirs)
				var dir := Vector2(cos(a2), sin(a2) * head / maxf(w * 0.5, 0.001))
				ci.draw_line(centre + dir * w * 0.5, centre + dir * w * 0.60,
					s["ink"], maxf(1.0, u * 0.004))
	if bool(p.get("channel", false)):
		ci.draw_rect(Rect2(b.position - Vector2(0.0, u * 0.020),
			Vector2(b.size.x, maxf(u * 0.020, 1.0))), s["lit"])
	ci.draw_rect(b, s["ink"], false, maxf(1.0, u * 0.005 * float(s.get("edge", 0.8))))


static func _crest(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var count := clampi(int(p.get("count", 9)), 2, 40)
	var style := String(p.get("style", "crenel"))
	var pitch := b.size.x / float(count)
	for k in count:
		var x := b.position.x + pitch * float(k)
		match style:
			"crenel":
				ci.draw_rect(Rect2(x, b.position.y, maxf(pitch * 0.60, 1.0), b.size.y), s["mid"])
				ci.draw_rect(Rect2(x, b.position.y, maxf(pitch * 0.60, 1.0),
					maxf(b.size.y * 0.30, 1.0)), s["lit"])
			"ridge":
				ci.draw_circle(Vector2(x + pitch * 0.5, b.end.y), maxf(pitch * 0.22, 1.0), s["lit"])
			_:
				ci.draw_colored_polygon(PackedVector2Array([
					Vector2(x, b.end.y), Vector2(x + pitch * 0.5, b.position.y),
					Vector2(x + pitch, b.end.y)]), s["lit"])


## --- earth, timber and ground ----------------------------------------------

static func _bank(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var batter := float(p.get("batter", 0.4)) * b.size.x * 0.5
	if bool(p.get("ditch", false)):
		ci.draw_colored_polygon(PackedVector2Array([
			b.position, Vector2(b.end.x, b.position.y),
			Vector2(b.end.x - batter, b.end.y), Vector2(b.position.x + batter, b.end.y)]),
			s["shadow"])
		return
	var face := PackedVector2Array([
		Vector2(b.position.x + batter, b.position.y), Vector2(b.end.x - batter, b.position.y),
		b.end, Vector2(b.position.x, b.end.y)])
	ci.draw_colored_polygon(face, s["mid"])
	ci.draw_colored_polygon(PackedVector2Array([
		face[0], face[1], face[1].lerp(face[2], 0.30), face[0].lerp(face[3], 0.30)]), s["lit"])
	var tufts := int(p.get("tufts", 0))
	for k in tufts:
		var t := (float(k) + 0.5) / float(maxi(tufts, 1))
		ReliefGlyphs.tuft(ci, Vector2(lerpf(face[0].x, face[1].x, t), b.position.y),
			u * 0.010, ArtNoise.hash01(seed, k), s)
	var stakes := int(p.get("stakes", 0))
	for k in stakes:
		var t2 := (float(k) + 0.5) / float(maxi(stakes, 1))
		var x := lerpf(face[0].x, face[1].x, t2)
		ci.draw_line(Vector2(x, b.position.y), Vector2(x + ArtNoise.swing(seed, k, u * 0.006),
			b.position.y - u * 0.030), s["shadow"], maxf(1.0, u * 0.005))


static func _posts(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	## Palisade, drill posts, practice dummies, fences, horse rail, net poles.
	var count := clampi(int(p.get("count", 8)), 1, 28)
	var cap := String(p.get("cap", "none"))
	var lean := float(p.get("lean", 0.0))
	var rails := int(p.get("rails", 0))
	var width := maxf(u * 0.010, 1.0)
	var tops: Array = []
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var x := lerpf(b.position.x, b.end.x, t)
		var tilt := ArtNoise.swing(seed, i, lean) * b.size.y
		var top := Vector2(x + tilt, b.position.y + b.size.y * 0.12 * ArtNoise.hash01(seed, i + 40))
		tops.append(top)
		ci.draw_line(Vector2(x, b.end.y), top, s["mid"], width)
		ci.draw_line(Vector2(x + width * 0.3, b.end.y), top + Vector2(width * 0.3, 0.0),
			s["shadow"], width * 0.5)
		match cap:
			"point":
				ci.draw_colored_polygon(PackedVector2Array([
					top + Vector2(-width, 0.0), top + Vector2(0.0, -u * 0.018),
					top + Vector2(width, 0.0)]), s["lit"])
			"cross":
				ci.draw_line(top + Vector2(-u * 0.018, u * 0.010),
					top + Vector2(u * 0.018, u * 0.010), s["mid"], width * 0.8)
			"shield":
				ci.draw_circle(top + Vector2(0.0, u * 0.016), maxf(u * 0.016, 1.0), s["lit"])
				ci.draw_arc(top + Vector2(0.0, u * 0.016), maxf(u * 0.016, 1.0), 0, TAU, 12,
					s["ink"], maxf(1.0, u * 0.004))
	for r in rails:
		var y := lerpf(b.position.y + b.size.y * 0.30, b.end.y - b.size.y * 0.12,
			float(r) / maxf(float(rails - 1), 1.0) if rails > 1 else 0.4)
		ci.draw_line(Vector2(b.position.x, y), Vector2(b.end.x, y), s["mid"], width * 0.7)
	if bool(p.get("drape", false)) and tops.size() >= 2:
		for i in range(tops.size() - 1):
			var a: Vector2 = tops[i]
			var c: Vector2 = tops[i + 1]
			ci.draw_polyline(PackedVector2Array([a,
				(a + c) * 0.5 + Vector2(0.0, b.size.y * 0.30), c]),
				Color(s["mid"], 0.75), maxf(1.0, u * 0.004))


static func _mound(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var arc := PackedVector2Array()
	for k in range(11):
		var t := float(k) / 10.0
		arc.append(Vector2(lerpf(b.position.x, b.end.x, t),
			b.end.y - b.size.y * sin(PI * t) * (0.85 + 0.30 * ArtNoise.hash01(seed, k))))
	arc.append(Vector2(b.end.x, b.end.y))
	arc.append(Vector2(b.position.x, b.end.y))
	ci.draw_colored_polygon(arc, s["mid"])
	ci.draw_polyline(arc, s["ink"], maxf(1.0, u * 0.004))
	for k in int(p.get("speckle", 0)):
		ci.draw_circle(Vector2(lerpf(b.position.x, b.end.x, ArtNoise.hash01(seed, k * 3 + 1)),
			lerpf(b.position.y + b.size.y * 0.4, b.end.y, ArtNoise.hash01(seed, k * 3 + 2))),
			maxf(u * 0.005, 1.0), s["shadow"])
	if bool(p.get("trodden", false)):
		ci.draw_line(Vector2(b.position.x, b.end.y - u * 0.006),
			Vector2(b.end.x, b.end.y - u * 0.006), s["shadow"], maxf(1.0, u * 0.005))


static func _field_strips(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	## Receding rows that narrow toward the horizon, so a farm reads as land
	## rather than a stripe. Same stroke idea as the map's furrow glyph.
	var rows := clampi(int(p.get("rows", 4)), 1, 9)
	var style := String(p.get("style", "furrow"))
	var vanish := Vector2(b.position.x + b.size.x * 0.5, b.position.y - b.size.y * 0.8)
	for k in range(rows + 1):
		var t := float(k) / float(rows)
		var y := lerpf(b.position.y, b.end.y, t * t)
		var half := lerpf(b.size.x * 0.30, b.size.x * 0.5, t)
		var mid := Vector2(b.position.x + b.size.x * 0.5, y)
		var colour: Color = s["furrow"] if style == "furrow" else s["grain"]
		ci.draw_line(mid - Vector2(half, 0.0), mid + Vector2(half, 0.0),
			colour, maxf(1.0, u * 0.005))
	if style == "paving" or style == "road":
		for k in 5:
			var t2 := (float(k) + 0.5) / 5.0
			var top := vanish.lerp(Vector2(lerpf(b.position.x, b.end.x, t2), b.end.y), 0.55)
			ci.draw_line(top, Vector2(lerpf(b.position.x, b.end.x, t2), b.end.y),
				s["grain"], maxf(1.0, u * 0.004))
	for k in int(p.get("crop", 0.0) * 22.0):
		var x := lerpf(b.position.x, b.end.x, ArtNoise.hash01(seed, k * 2 + 1))
		var y2 := lerpf(b.position.y + b.size.y * 0.35, b.end.y, ArtNoise.hash01(seed, k * 2 + 2))
		ci.draw_line(Vector2(x, y2), Vector2(x, y2 - u * 0.014), s["lit"], maxf(1.0, u * 0.003))
	for k in int(p.get("stumps", 0)):
		ci.draw_circle(Vector2(lerpf(b.position.x, b.end.x, ArtNoise.hash01(seed, 90 + k)),
			lerpf(b.position.y, b.end.y, 0.6)), maxf(u * 0.006, 1.0), s["shadow"])


## --- trade, craft and water -------------------------------------------------

static func _awning(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var scallops := clampi(int(p.get("scallops", 5)), 2, 12)
	var cloth := PackedVector2Array([b.position, Vector2(b.end.x, b.position.y + b.size.y * 0.18)])
	for k in range(scallops + 1):
		var t := 1.0 - float(k) / float(scallops)
		cloth.append(Vector2(lerpf(b.position.x, b.end.x, t),
			b.position.y + b.size.y * (0.52 + 0.16 * sin(PI * float(k)))))
	ci.draw_colored_polygon(cloth, s["lit"])
	ci.draw_polyline(cloth, s["ink"], maxf(1.0, u * 0.004))
	for k in int(p.get("poles", 2)):
		var x := lerpf(b.position.x, b.end.x, 0.08 + 0.84 * float(k))
		ci.draw_line(Vector2(x, b.position.y + b.size.y * 0.4), Vector2(x, b.end.y),
			s["shadow"], maxf(1.0, u * 0.006))


static func _stall(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var table := Rect2(b.position.x, b.end.y - b.size.y * 0.34, b.size.x, b.size.y * 0.34)
	_box(ci, table, s, {"courses": 1}, u, seed)
	if bool(p.get("awning", true)):
		_awning(ci, Rect2(b.position.x - b.size.x * 0.06, b.position.y,
			b.size.x * 1.12, b.size.y * 0.52), s, {"scallops": 4, "poles": 2}, u, seed)
	for k in int(p.get("goods", 3)):
		var x := lerpf(table.position.x + b.size.x * 0.12, table.end.x - b.size.x * 0.12,
			(float(k) + 0.5) / float(maxi(int(p.get("goods", 3)), 1)))
		ci.draw_circle(Vector2(x, table.position.y - u * 0.008), maxf(u * 0.008, 1.0),
			s["lit"] if k % 2 == 0 else s["shadow"])


static func _vessels(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var count := clampi(int(p.get("count", 4)), 1, 12)
	var per_row := maxi(1, int(ceil(sqrt(float(count)))))
	var w := b.size.x / float(per_row)
	var h := b.size.y
	for k in count:
		var col := k % per_row
		var row := int(k / per_row)
		var cx := b.position.x + w * (float(col) + 0.5) + w * 0.4 * float(row)
		var base := b.end.y - h * 0.30 * float(row)
		var half := w * 0.32
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(cx, base), Vector2(cx - half, base - h * 0.34),
			Vector2(cx - half * 0.9, base - h * 0.62),
			Vector2(cx - half * 0.4, base - h * 0.80), Vector2(cx + half * 0.4, base - h * 0.80),
			Vector2(cx + half * 0.9, base - h * 0.62), Vector2(cx + half, base - h * 0.34)]),
			s["mid"] if k % 2 == 0 else s["shadow"])
		ci.draw_line(Vector2(cx - half * 0.4, base - h * 0.80),
			Vector2(cx + half * 0.4, base - h * 0.80), s["lit"], maxf(1.0, u * 0.004))


static func _granary(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var count := maxi(1, int(p.get("count", 1)))
	var w := b.size.x / float(count)
	for k in count:
		var cell := Rect2(b.position.x + w * float(k), b.position.y, w * 0.86, b.size.y)
		var stilts := int(p.get("stilts", 0))
		var body_h := cell.size.y * (0.62 if stilts > 0 else 0.74)
		var body := Rect2(cell.position.x, cell.position.y + cell.size.y - body_h
			- (cell.size.y * 0.14 if stilts > 0 else 0.0), cell.size.x, body_h)
		_box(ci, body, s, {"courses": 2}, u, seed)
		for j in stilts:
			var x := lerpf(body.position.x + cell.size.x * 0.1, body.end.x - cell.size.x * 0.1,
				float(j) / maxf(float(stilts - 1), 1.0))
			ci.draw_line(Vector2(x, body.end.y), Vector2(x, cell.end.y), s["shadow"],
				maxf(1.0, u * 0.006))
		for j in int(p.get("vents", 0)):
			var vx := lerpf(body.position.x, body.end.x, (float(j) + 1.0)
				/ (float(p.get("vents", 1)) + 1.0))
			ci.draw_rect(Rect2(vx - u * 0.005, body.position.y + body.size.y * 0.3,
				maxf(u * 0.010, 1.0), maxf(body.size.y * 0.2, 1.0)), s["ink"])
		_roof(ci, Rect2(body.position.x - cell.size.x * 0.08, body.position.y - cell.size.y * 0.22,
			cell.size.x * 1.16, cell.size.y * 0.24), s,
			{"style": p.get("roof", "thatch"), "pitch": 0.6, "ribs": 5}, u, seed)


static func _forge(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var body := Rect2(b.position.x, b.position.y + b.size.y * 0.34, b.size.x * 0.78, b.size.y * 0.66)
	_box(ci, body, s, {"courses": 2}, u, seed)
	var chimney := Rect2(b.end.x - b.size.x * 0.24, b.position.y,
		b.size.x * 0.20, b.size.y * float(p.get("chimney", 0.5)) + b.size.y * 0.34)
	_box(ci, chimney, s, {"courses": 3, "cap": "cornice"}, u, seed)
	if bool(p.get("glow", false)):
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(body.position.x + body.size.x * 0.28, body.end.y),
			Vector2(body.position.x + body.size.x * 0.28, body.position.y + body.size.y * 0.35),
			Vector2(body.position.x + body.size.x * 0.62, body.position.y + body.size.y * 0.35),
			Vector2(body.position.x + body.size.x * 0.62, body.end.y)]),
			Color(1.0, 0.62, 0.25, 0.55))
	if int(p.get("smoke", 0)) > 0:
		_smoke(ci, Rect2(chimney.position.x, b.position.y - b.size.y * 0.5,
			chimney.size.x, b.size.y * 0.5), s, {"puffs": p.get("smoke", 3)}, u, seed)


static func _smoke(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var puffs := clampi(int(p.get("puffs", 3)), 1, 6)
	for k in puffs:
		var t := (float(k) + 1.0) / float(puffs + 1)
		var drift := ArtNoise.noise(seed + "s", t * 3.0) * b.size.x * 0.7
		ci.draw_circle(Vector2(b.position.x + b.size.x * 0.5 + drift,
			lerpf(b.end.y, b.position.y, t)),
			maxf(b.size.x * (0.20 + 0.30 * t), 1.0),
			Color(0.86, 0.85, 0.82, 0.32 * (1.0 - t * 0.7)))


static func _well(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var kerb := Rect2(b.position.x, b.end.y - b.size.y * 0.44, b.size.x, b.size.y * 0.44)
	ci.draw_rect(kerb, s["mid"])
	ci.draw_rect(Rect2(kerb.position, Vector2(kerb.size.x, maxf(u * 0.010, 1.0))), s["lit"])
	ci.draw_rect(kerb, s["ink"], false, maxf(1.0, u * 0.004))
	ci.draw_circle(Vector2(kerb.position.x + kerb.size.x * 0.5, kerb.position.y),
		maxf(kerb.size.x * 0.24, 1.0), Color(s["mid"].darkened(0.66), 0.9))
	if bool(p.get("frame", false)):
		for f in [0.14, 0.86]:
			ci.draw_line(Vector2(lerpf(kerb.position.x, kerb.end.x, f), kerb.position.y),
				Vector2(lerpf(kerb.position.x, kerb.end.x, f), b.position.y),
				s["shadow"], maxf(1.0, u * 0.005))
		ci.draw_line(Vector2(kerb.position.x + kerb.size.x * 0.14, b.position.y),
			Vector2(kerb.end.x - kerb.size.x * 0.14, b.position.y), s["shadow"],
			maxf(1.0, u * 0.005))
		ci.draw_rect(Rect2(kerb.position.x + kerb.size.x * 0.42,
			b.position.y + b.size.y * 0.18, maxf(kerb.size.x * 0.16, 1.0),
			maxf(b.size.y * 0.16, 1.0)), s["shadow"])


static func _quay(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	match String(p.get("style", "piles")):
		"canal":
			ci.draw_rect(b, s["mid"])
			for k in int(p.get("ripples", 4)):
				var y := lerpf(b.position.y, b.end.y, (float(k) + 0.5) / float(p.get("ripples", 4)))
				ci.draw_dashed_line(Vector2(b.position.x, y), Vector2(b.end.x, y),
					s["lit"], maxf(1.0, u * 0.004), u * 0.03)
		"stone":
			_box(ci, b, s, {"courses": p.get("courses", 3)}, u, seed)
			for k in int(p.get("bollards", 0)):
				var x := lerpf(b.position.x, b.end.x, (float(k) + 0.5) / float(p.get("bollards", 1)))
				ci.draw_rect(Rect2(x - u * 0.006, b.position.y - u * 0.018,
					maxf(u * 0.012, 1.0), maxf(u * 0.018, 1.0)), s["shadow"])
		_:
			var deck := Rect2(b.position, Vector2(b.size.x, b.size.y * 0.34))
			ci.draw_rect(deck, s["mid"])
			ci.draw_rect(Rect2(deck.position, Vector2(deck.size.x, maxf(u * 0.008, 1.0))), s["lit"])
			for k in int(p.get("piles", 6)):
				var x2 := lerpf(b.position.x, b.end.x, (float(k) + 0.5) / float(p.get("piles", 6)))
				ci.draw_line(Vector2(x2, deck.end.y), Vector2(x2, b.end.y), s["shadow"],
					maxf(1.0, u * 0.006))


static func _hull(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var sheer := b.position.y + b.size.y * 0.36
	var hull := PackedVector2Array([
		Vector2(b.position.x + b.size.x * 0.06, sheer),
		Vector2(b.end.x - b.size.x * 0.10, sheer),
		Vector2(b.end.x, sheer + b.size.y * 0.22),
		Vector2(b.end.x - b.size.x * 0.14, b.end.y),
		Vector2(b.position.x + b.size.x * 0.16, b.end.y),
		Vector2(b.position.x, sheer + b.size.y * 0.26)])
	ci.draw_colored_polygon(hull, s["mid"])
	ci.draw_polyline(PackedVector2Array([hull[0], hull[1]]), s["lit"], maxf(1.0, u * 0.008))
	var ring := hull.duplicate()
	ring.append(hull[0])
	ci.draw_polyline(ring, s["ink"], maxf(1.0, u * 0.005))
	if bool(p.get("ram", false)):
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(b.position.x, sheer + b.size.y * 0.30),
			Vector2(b.position.x - b.size.x * 0.10, b.end.y - b.size.y * 0.06),
			Vector2(b.position.x + b.size.x * 0.10, b.end.y)]), s["shadow"])
	for k in int(p.get("oars", 0)):
		var t := (float(k) + 0.5) / float(maxi(int(p.get("oars", 1)), 1))
		var x := lerpf(hull[0].x, hull[1].x, t)
		ci.draw_line(Vector2(x, sheer + b.size.y * 0.10),
			Vector2(x - b.size.x * 0.05, b.end.y + b.size.y * 0.12),
			s["shadow"], maxf(1.0, u * 0.004))
	for k in int(p.get("shields", 0)):
		var t2 := (float(k) + 0.5) / float(maxi(int(p.get("shields", 1)), 1))
		ci.draw_circle(Vector2(lerpf(hull[0].x, hull[1].x, t2), sheer),
			maxf(b.size.y * 0.10, 1.0), s["lit"])
	if bool(p.get("mast", false)):
		var mx := lerpf(hull[0].x, hull[1].x, 0.46)
		var top := b.position.y - b.size.y * 0.9
		ci.draw_line(Vector2(mx, sheer), Vector2(mx, top), s["shadow"], maxf(1.0, u * 0.006))
		if bool(p.get("sail", false)):
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(mx - b.size.x * 0.20, top + b.size.y * 0.14),
				Vector2(mx + b.size.x * 0.20, top + b.size.y * 0.14),
				Vector2(mx + b.size.x * 0.16, sheer - b.size.y * 0.10),
				Vector2(mx - b.size.x * 0.16, sheer - b.size.y * 0.10)]),
				Color(0.90, 0.86, 0.75, 0.92))


static func _mine_head(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var apex := Vector2(b.position.x + b.size.x * 0.5, b.position.y)
	ci.draw_line(Vector2(b.position.x, b.end.y), apex, s["mid"], maxf(1.0, u * 0.008))
	ci.draw_line(Vector2(b.end.x, b.end.y), apex, s["mid"], maxf(1.0, u * 0.008))
	ci.draw_line(Vector2(b.position.x + b.size.x * 0.18, b.position.y + b.size.y * 0.52),
		Vector2(b.end.x - b.size.x * 0.18, b.position.y + b.size.y * 0.52),
		s["shadow"], maxf(1.0, u * 0.006))
	if bool(p.get("windlass", false)):
		ci.draw_circle(apex + Vector2(0.0, b.size.y * 0.30), maxf(b.size.x * 0.14, 1.0), s["shadow"])
		ci.draw_arc(apex + Vector2(0.0, b.size.y * 0.30), maxf(b.size.x * 0.14, 1.0),
			0, TAU, 12, s["ink"], maxf(1.0, u * 0.004))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(b.position.x + b.size.x * 0.30, b.end.y),
		Vector2(b.position.x + b.size.x * 0.30, b.position.y + b.size.y * 0.66),
		Vector2(b.end.x - b.size.x * 0.30, b.position.y + b.size.y * 0.66),
		Vector2(b.end.x - b.size.x * 0.30, b.end.y)]), Color(0.06, 0.05, 0.05, 0.92))


static func _canopy(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var roof_h := b.size.y * 0.30
	_roof(ci, Rect2(b.position.x, b.position.y, b.size.x, roof_h), s,
		{"style": p.get("roof", "flat"), "pitch": 0.5, "ribs": 5}, u, seed)
	var posts := clampi(int(p.get("posts", 4)), 2, 6)
	for k in posts:
		var x := lerpf(b.position.x + b.size.x * 0.06, b.end.x - b.size.x * 0.06,
			float(k) / float(posts - 1))
		ci.draw_line(Vector2(x, b.position.y + roof_h), Vector2(x, b.end.y),
			s["mid"], maxf(1.0, u * 0.008))
	if bool(p.get("drape", false)):
		ci.draw_polyline(PackedVector2Array([
			Vector2(b.position.x + b.size.x * 0.10, b.position.y + roof_h),
			Vector2(b.position.x + b.size.x * 0.5, b.position.y + roof_h + b.size.y * 0.16),
			Vector2(b.end.x - b.size.x * 0.10, b.position.y + roof_h)]),
			Color(s["lit"], 0.75), maxf(1.0, u * 0.005))


## --- people, cult and signs -------------------------------------------------

static func _figure(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	## The scale figure, and the base every soldier is built from. Kept to a
	## silhouette: at plate size, detail below this reads as noise.
	var stance := String(p.get("stance", "guard"))
	var head_r := maxf(b.size.y * 0.11, 1.0)
	var head := Vector2(b.position.x + b.size.x * 0.5, b.position.y + head_r)
	var hip := Vector2(head.x, b.position.y + b.size.y * 0.58)
	var foot_l := Vector2(head.x - b.size.x * 0.28, b.end.y)
	var foot_r := Vector2(head.x + b.size.x * 0.30, b.end.y)
	if stance == "march":
		foot_l.x -= b.size.x * 0.16
		foot_r.x += b.size.x * 0.14
	var width := maxf(b.size.x * 0.34, 1.0)
	ci.draw_line(hip, foot_l, s["mid"], width * 0.55)
	ci.draw_line(hip, foot_r, s["shadow"], width * 0.55)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(head.x - width * 0.62, head.y + head_r * 0.8),
		Vector2(head.x + width * 0.62, head.y + head_r * 0.8),
		Vector2(head.x + width * 0.44, hip.y), Vector2(head.x - width * 0.44, hip.y)]),
		s["mid"])
	ci.draw_circle(head, head_r, s["lit"])
	ci.draw_arc(head, head_r, PI, TAU, 10, s["ink"], maxf(1.0, u * 0.004))
	match String(p.get("shield", "none")):
		"round", "hoplon":
			ci.draw_circle(Vector2(head.x - width * 0.52, hip.y - b.size.y * 0.14),
				maxf(b.size.y * 0.17, 1.0), s["lit"])
			ci.draw_arc(Vector2(head.x - width * 0.52, hip.y - b.size.y * 0.14),
				maxf(b.size.y * 0.17, 1.0), 0, TAU, 12, s["ink"], maxf(1.0, u * 0.004))
		"scutum", "tower", "oval":
			ci.draw_rect(Rect2(head.x - width * 0.90, head.y + head_r,
				maxf(width * 0.72, 1.0), maxf(b.size.y * 0.44, 1.0)), s["lit"])
			ci.draw_line(Vector2(head.x - width * 0.54, head.y + head_r),
				Vector2(head.x - width * 0.54, head.y + head_r + b.size.y * 0.44),
				s["ink"], maxf(1.0, u * 0.004))
	match String(p.get("weapon", "none")):
		"spear", "pike", "sarissa":
			var length := b.size.y * (1.65 if String(p.get("weapon")) != "spear" else 1.10)
			ci.draw_line(Vector2(head.x + width * 0.62, b.end.y),
				Vector2(head.x + width * 0.62 + b.size.x * 0.10, b.end.y - length),
				s["shadow"], maxf(1.0, u * 0.004))
		"bow":
			ci.draw_arc(Vector2(head.x + width * 0.60, hip.y - b.size.y * 0.10),
				maxf(b.size.y * 0.20, 1.0), -PI * 0.5, PI * 0.5, 10, s["shadow"],
				maxf(1.0, u * 0.004))
	match String(p.get("helmet", "none")):
		"crest", "crest_transverse", "plume":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(head.x - head_r * 0.7, head.y - head_r * 0.7),
				Vector2(head.x, head.y - head_r * 2.1),
				Vector2(head.x + head_r * 0.7, head.y - head_r * 0.7)]), s["shadow"])
		"horned":
			ci.draw_line(head + Vector2(-head_r, -head_r * 0.4),
				head + Vector2(-head_r * 1.9, -head_r * 1.5), s["shadow"], maxf(1.0, u * 0.004))
			ci.draw_line(head + Vector2(head_r, -head_r * 0.4),
				head + Vector2(head_r * 1.9, -head_r * 1.5), s["shadow"], maxf(1.0, u * 0.004))


static func _crowd(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	## Many people without many figures: a front rank, then rows fading toward
	## the sky colour, so 240 soldiers cost about twenty primitives.
	var count := clampi(int(p.get("count", 7)), 1, 24)
	var depth := clampi(int(p.get("depth", 2)), 1, 3)
	var ranked := bool(p.get("ranked", false))
	var ragged := bool(p.get("ragged", false))
	var per_row := maxi(1, int(ceil(float(count) / float(depth))))
	var sky := Color(0.72, 0.76, 0.78)
	for row in depth:
		var scale := 1.0 - 0.16 * float(row)
		var fade := 0.22 * float(row)
		var body: Color = (s["mid"] as Color).lerp(sky, fade)
		var head_c: Color = (s["lit"] as Color).lerp(sky, fade)
		var y := b.end.y - b.size.y * 0.30 * float(row)
		for k in per_row:
			if row * per_row + k >= count:
				break
			var t := (float(k) + 0.5) / float(per_row)
			if not ranked:
				t += ArtNoise.swing(seed, row * 31 + k, 0.35) / float(per_row)
			if ragged:
				t += ArtNoise.swing(seed, row * 17 + k, 0.20) / float(per_row)
			var x := lerpf(b.position.x, b.end.x, clampf(t, 0.0, 1.0))
			# People are sized from the STAGE, not from the strip they stand on:
			# an authored crowd rect is a short band, and sizing off it turned a
			# forum full of citizens into a row of tally marks.
			var h := u * 0.086 * scale
			var w := maxf(u * 0.030 * scale, 1.0)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x - w * 0.5, y), Vector2(x + w * 0.5, y),
				Vector2(x + w * 0.34, y - h * 0.72), Vector2(x - w * 0.34, y - h * 0.72)]), body)
			ci.draw_circle(Vector2(x, y - h * 0.84), maxf(w * 0.42, 1.0), head_c)


static func _beasts(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var count := clampi(int(p.get("count", 1)), 1, 4)
	var w := b.size.x / float(count)
	for k in count:
		var x := b.position.x + w * (float(k) + 0.5)
		var body_h := b.size.y * 0.52
		var top := b.end.y - body_h - b.size.y * 0.24
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.34, top + body_h * 0.30), Vector2(x - w * 0.26, top),
			Vector2(x + w * 0.26, top), Vector2(x + w * 0.34, top + body_h * 0.34),
			Vector2(x + w * 0.20, top + body_h), Vector2(x - w * 0.22, top + body_h)]), s["mid"])
		for f in [-0.24, -0.08, 0.10, 0.24]:
			ci.draw_line(Vector2(x + w * f, top + body_h),
				Vector2(x + w * f, b.end.y), s["shadow"], maxf(1.0, u * 0.005))
		var head := Vector2(x + w * 0.40, top + body_h * 0.16)
		ci.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-w * 0.10, -body_h * 0.16), head + Vector2(w * 0.16, -body_h * 0.06),
			head + Vector2(w * 0.14, body_h * 0.18), head + Vector2(-w * 0.10, body_h * 0.10)]),
			s["shadow"])
		if bool(p.get("yoke", false)) and k == 0:
			ci.draw_line(Vector2(x - w * 0.34, top), Vector2(x - w * 0.9, top + body_h * 0.30),
				s["shadow"], maxf(1.0, u * 0.005))


static func _tree(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var count := clampi(int(p.get("count", 2)), 1, 5)
	var kind := String(p.get("kind", "cypress"))
	for k in count:
		var x := lerpf(b.position.x, b.end.x, (float(k) + 0.5) / float(count))
		var roll := ArtNoise.hash01(seed, k)
		var at := Vector2(x, b.end.y)
		match kind:
			"palm":
				var top := at + Vector2(0.0, -b.size.y * (0.68 + 0.20 * roll))
				ci.draw_line(at, top, s["shadow"], maxf(1.0, u * 0.006))
				for f in 6:
					var a := PI + PI * (float(f) + 0.5) / 6.0
					ci.draw_line(top, top + Vector2(cos(a), sin(a) * 0.6) * b.size.x * 0.34,
						s["lit"], maxf(1.0, u * 0.005))
			"olive":
				var crown := at + Vector2(0.0, -b.size.y * 0.52)
				ci.draw_line(at, crown, s["shadow"], maxf(1.0, u * 0.005))
				for f in 3:
					ci.draw_circle(crown + Vector2((float(f) - 1.0) * b.size.x * 0.16,
						-b.size.y * 0.06 * float(f % 2)), maxf(b.size.x * 0.20, 1.0),
						s["mid"] if f != 1 else s["lit"])
			_:
				ReliefGlyphs.tree(ci, at, b.size.y / 22.0 * (0.8 + roll * 0.5), roll, s)


static func _statue(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var plinth_h := b.size.y * float(p.get("plinth", 0.30))
	_box(ci, Rect2(b.position.x, b.end.y - plinth_h, b.size.x, plinth_h), s,
		{"courses": 2, "cap": "cornice"}, u, seed)
	var body := Rect2(b.position.x + b.size.x * 0.10, b.position.y,
		b.size.x * 0.80, b.size.y - plinth_h)
	if String(p.get("pose", "standing")) == "seated":
		body.position.y += body.size.y * 0.20
		body.size.y *= 0.80
	_figure(ci, body, s, {"stance": "guard",
		"weapon": "spear" if bool(p.get("spear", false)) else "none"}, u, seed)


static func _altar(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var steps := int(p.get("steps", 0))
	var block := b
	if steps > 0:
		var step_h := b.size.y * 0.28
		_steps(ci, Rect2(b.position.x - b.size.x * 0.14, b.end.y - step_h,
			b.size.x * 1.28, step_h), s, {"count": steps}, u, seed)
		block = Rect2(b.position.x, b.position.y, b.size.x, b.size.y - step_h)
	_box(ci, block, s, {"courses": 1, "cap": "cornice"}, u, seed)
	if bool(p.get("fire", false)):
		var base := Vector2(block.position.x + block.size.x * 0.5, block.position.y)
		for k in 3:
			var h := block.size.y * (0.8 - 0.22 * float(k))
			var w := block.size.x * (0.34 - 0.08 * float(k))
			ci.draw_colored_polygon(PackedVector2Array([
				base + Vector2(-w, 0.0), base + Vector2(0.0, -h),
				base + Vector2(w, 0.0)]), FLAME[k])
	if int(p.get("smoke", 0)) > 0:
		_smoke(ci, Rect2(b.position.x, b.position.y - b.size.y * 1.4, b.size.x, b.size.y * 1.4),
			s, {"puffs": p.get("smoke", 3)}, u, seed)


static func _standard(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	## The one part that carries the house colour: cloth has tint 0.85, so the
	## banner is the faction's and the architecture stays its own material.
	var count := clampi(int(p.get("count", 1)), 1, 5)
	var fly := float(p.get("fly", 0.5))
	for k in count:
		var x := b.position.x + b.size.x * (0.5 + 0.65 * (float(k) - float(count - 1) * 0.5))
		var top := b.position.y + b.size.y * 0.10 * float(k % 2)
		ci.draw_line(Vector2(x, b.end.y), Vector2(x, top),
			Color(0.36, 0.38, 0.40), maxf(1.0, u * 0.005))
		var flag := PackedVector2Array([Vector2(x, top + b.size.y * 0.10)])
		for j in range(5):
			var t := float(j) / 4.0
			flag.append(Vector2(x + b.size.x * fly * (0.4 + 0.6 * t)
				+ b.size.x * 0.14 * ArtNoise.noise(seed + str(k), t * 3.0),
				top + b.size.y * (0.10 + 0.30 * t)))
		flag.append(Vector2(x, top + b.size.y * 0.44))
		ci.draw_colored_polygon(flag, s["mid"])
		ci.draw_polyline(flag, s["ink"], maxf(1.0, u * 0.003))
		_emblem(ci, Rect2(x - b.size.x * 0.28, top - b.size.y * 0.22,
			b.size.x * 0.56, b.size.y * 0.22), s,
			{"kind": p.get("finial", "disc")}, u, seed)


static func _emblem(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	## Twelve original devices, one to three primitives each. Historical
	## attributes only — a thunderbolt, a stalk of grain, a sun — never any
	## other game's mark.
	var c := b.get_center()
	var r := maxf(minf(b.size.x, b.size.y) * 0.5, 1.0)
	var ink: Color = s["lit"]
	var w := maxf(1.0, u * 0.005)
	match String(p.get("kind", "disc")):
		"bolt":
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-r * 0.6, -r), c + Vector2(r * 0.1, -r * 0.2),
				c + Vector2(-r * 0.3, -r * 0.1), c + Vector2(r * 0.6, r)]), ink, w)
		"spear":
			ci.draw_line(c + Vector2(0.0, r), c + Vector2(0.0, -r * 0.4), ink, w)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.35, -r * 0.4), c + Vector2(0.0, -r),
				c + Vector2(r * 0.35, -r * 0.4)]), ink)
		"grain":
			ci.draw_line(c + Vector2(0.0, r), c + Vector2(0.0, -r), ink, w)
			for k in 4:
				var y := lerpf(-r * 0.8, r * 0.3, float(k) / 3.0)
				ci.draw_line(c + Vector2(0.0, y), c + Vector2(r * 0.5, y - r * 0.2), ink, w * 0.7)
				ci.draw_line(c + Vector2(0.0, y), c + Vector2(-r * 0.5, y - r * 0.2), ink, w * 0.7)
		"sun":
			ci.draw_circle(c, r * 0.42, ink)
			for k in 8:
				var a := TAU * float(k) / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.55,
					c + Vector2(cos(a), sin(a)) * r, ink, w * 0.7)
		"moon":
			ci.draw_arc(c, r * 0.7, PI * 0.35, PI * 1.65, 14, ink, w * 1.4)
		"horse":
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-r * 0.8, r * 0.5), c + Vector2(-r * 0.2, -r * 0.1),
				c + Vector2(r * 0.3, -r * 0.2), c + Vector2(r * 0.8, -r * 0.7)]), ink, w)
		"eagle":
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-r, r * 0.3), c + Vector2(0.0, -r * 0.4),
				c + Vector2(r, r * 0.3)]), ink, w)
			ci.draw_circle(c + Vector2(0.0, -r * 0.55), r * 0.22, ink)
		"hammer":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.12, -r * 0.2), Vector2(r * 0.24, r * 1.1)), ink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.7), Vector2(r * 1.4, r * 0.5)), ink)
		"vine":
			var spiral := PackedVector2Array()
			for k in range(14):
				var t2 := float(k) / 13.0
				var a2 := t2 * TAU * 1.3
				spiral.append(c + Vector2(cos(a2), sin(a2)) * r * (0.25 + 0.65 * t2))
			ci.draw_polyline(spiral, ink, w)
		"caduceus":
			ci.draw_line(c + Vector2(0.0, r), c + Vector2(0.0, -r), ink, w)
			ci.draw_arc(c + Vector2(0.0, -r * 0.3), r * 0.4, PI, TAU, 10, ink, w * 0.8)
			ci.draw_arc(c + Vector2(0.0, r * 0.2), r * 0.4, 0, PI, 10, ink, w * 0.8)
		"flame":
			for k in 3:
				var h := r * (1.0 - 0.24 * float(k))
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(-r * 0.4 + r * 0.1 * float(k), r),
					c + Vector2(0.0, r - h * 1.6),
					c + Vector2(r * 0.4 - r * 0.1 * float(k), r)]), FLAME[k])
		"serpent":
			var wave := PackedVector2Array()
			for k in range(12):
				var t3 := float(k) / 11.0
				wave.append(c + Vector2(lerpf(-r, r, t3), sin(t3 * TAU) * r * 0.45))
			ci.draw_polyline(wave, ink, w)
		"wave":
			for k in 2:
				var wv := PackedVector2Array()
				for j in range(10):
					var t4 := float(j) / 9.0
					wv.append(c + Vector2(lerpf(-r, r, t4),
						-r * 0.3 + r * 0.5 * float(k) + sin(t4 * TAU) * r * 0.22))
				ci.draw_polyline(wv, ink, w * 0.8)
		"boar":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r, r * 0.4), c + Vector2(-r * 0.5, -r * 0.4),
				c + Vector2(r * 0.4, -r * 0.5), c + Vector2(r, r * 0.1),
				c + Vector2(r * 0.3, r * 0.5)]), ink)
		"skull":
			ci.draw_circle(c + Vector2(0.0, -r * 0.2), r * 0.5, ink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.25, r * 0.15), Vector2(r * 0.5, r * 0.45)), ink)
		_:
			ci.draw_circle(c, r * 0.6, ink)
			ci.draw_arc(c, r * 0.85, 0, TAU, 14, ink, w * 0.8)


static func _trophy(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var mid := b.position.x + b.size.x * 0.5
	ci.draw_line(Vector2(mid, b.end.y), Vector2(mid, b.position.y), s["mid"], maxf(1.0, u * 0.006))
	ci.draw_line(Vector2(b.position.x, b.position.y + b.size.y * 0.34),
		Vector2(b.end.x, b.position.y + b.size.y * 0.34), s["mid"], maxf(1.0, u * 0.005))
	ci.draw_circle(Vector2(mid, b.position.y + b.size.y * 0.50),
		maxf(b.size.x * 0.42, 1.0), s["lit"])
	ci.draw_arc(Vector2(mid, b.position.y + b.size.y * 0.50), maxf(b.size.x * 0.42, 1.0),
		0, TAU, 12, s["ink"], maxf(1.0, u * 0.004))
	ci.draw_arc(Vector2(mid, b.position.y + b.size.y * 0.14), maxf(b.size.x * 0.30, 1.0),
		PI, TAU, 10, s["shadow"], maxf(1.0, u * 0.006))


static func _stele(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	_box(ci, b, s, {"courses": 0, "cap": "cornice"}, u, seed)
	for k in int(p.get("lines", 4)):
		var y := lerpf(b.position.y + b.size.y * 0.24, b.end.y - b.size.y * 0.14,
			float(k) / maxf(float(int(p.get("lines", 4)) - 1), 1.0))
		ci.draw_line(Vector2(b.position.x + b.size.x * 0.20, y),
			Vector2(b.end.x - b.size.x * 0.20, y), s["ink"], maxf(1.0, u * 0.003))


static func _obelisk(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var top_w := b.size.x * 0.62
	var shaft := PackedVector2Array([
		Vector2(b.position.x + (b.size.x - top_w) * 0.5, b.position.y + b.size.y * 0.10),
		Vector2(b.end.x - (b.size.x - top_w) * 0.5, b.position.y + b.size.y * 0.10),
		b.end, Vector2(b.position.x, b.end.y)])
	ci.draw_colored_polygon(shaft, s["mid"])
	ci.draw_colored_polygon(PackedVector2Array([
		shaft[0].lerp(shaft[1], 0.58), shaft[1], shaft[2], shaft[3].lerp(shaft[2], 0.58)]),
		s["shadow"])
	ci.draw_colored_polygon(PackedVector2Array([
		shaft[0], shaft[1], Vector2(b.position.x + b.size.x * 0.5, b.position.y)]),
		s["lit"] if bool(p.get("pyramidion", true)) else s["mid"])
	ci.draw_polyline(PackedVector2Array([shaft[3], shaft[0],
		Vector2(b.position.x + b.size.x * 0.5, b.position.y), shaft[1], shaft[2]]),
		s["ink"], maxf(1.0, u * 0.004))


static func _pylon(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var batter := float(p.get("batter", 0.22))
	var gate_w := b.size.x * 0.22
	for side in [-1.0, 1.0]:
		var outer := b.position.x if side < 0.0 else b.end.x
		var inner: float = b.position.x + b.size.x * 0.5 + side * gate_w * 0.5
		var lean: float = (inner - outer) * batter * 0.5
		var tower := PackedVector2Array([
			Vector2(outer + lean, b.position.y), Vector2(inner - lean * 0.4, b.position.y),
			Vector2(inner, b.end.y), Vector2(outer, b.end.y)])
		ci.draw_colored_polygon(tower, s["mid"] if side < 0.0 else (s["mid"] as Color).lerp(s["shadow"], 0.45))
		ci.draw_polyline(PackedVector2Array([tower[0], tower[1], tower[2], tower[3], tower[0]]),
			s["ink"], maxf(1.0, u * 0.005))
		if bool(p.get("cavetto", true)):
			ci.draw_rect(Rect2(minf(tower[0].x, tower[1].x), b.position.y - u * 0.016,
				maxf(absf(tower[1].x - tower[0].x), 1.0), maxf(u * 0.016, 1.0)), s["lit"])
	for k in int(p.get("flagstaffs", 0)):
		var x := b.position.x + b.size.x * (0.16 + 0.68 * float(k))
		ci.draw_line(Vector2(x, b.position.y), Vector2(x, b.position.y - b.size.y * 0.34),
			s["shadow"], maxf(1.0, u * 0.005))


static func _stones(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var count := clampi(int(p.get("count", 5)), 2, 13)
	var w := b.size.x / float(count)
	var tops: Array = []
	for k in count:
		var x := b.position.x + w * (float(k) + 0.5)
		var h := b.size.y * (0.62 + 0.34 * ArtNoise.hash01(seed, k))
		var half := w * 0.30
		var top := b.end.y - h
		tops.append(Vector2(x, top))
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x - half, b.end.y),
			Vector2(x - half * (0.7 + 0.3 * ArtNoise.hash01(seed, k * 3 + 1)), top),
			Vector2(x + half * (0.6 + 0.4 * ArtNoise.hash01(seed, k * 3 + 2)), top),
			Vector2(x + half, b.end.y)]), s["mid"] if k % 2 == 0 else s["shadow"])
	if bool(p.get("lintels", false)):
		for k in range(0, tops.size() - 1, 2):
			var a: Vector2 = tops[k]
			var c: Vector2 = tops[k + 1]
			ci.draw_rect(Rect2(a.x - w * 0.30, minf(a.y, c.y) - u * 0.020,
				maxf(c.x - a.x + w * 0.60, 1.0), maxf(u * 0.020, 1.0)), s["lit"])


static func _rubble(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	for k in clampi(int(p.get("count", 6)), 1, 14):
		var x := lerpf(b.position.x, b.end.x, ArtNoise.hash01(seed, k * 2 + 1))
		var h := b.size.y * (0.4 + 0.6 * ArtNoise.hash01(seed, k * 2 + 2))
		var w := b.size.y * 0.9
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.5, b.end.y), Vector2(x - w * 0.3, b.end.y - h),
			Vector2(x + w * 0.35, b.end.y - h * 0.8), Vector2(x + w * 0.5, b.end.y)]),
			s["shadow"])


static func _scaffold(ci: CanvasItem, b: Rect2, s: Dictionary, p: Dictionary,
		u: float, seed: String) -> void:
	var bays := clampi(int(p.get("bays", 4)), 1, 10)
	for k in range(bays + 1):
		var x := lerpf(b.position.x, b.end.x, float(k) / float(bays))
		ci.draw_line(Vector2(x, b.position.y), Vector2(x, b.end.y), s["mid"], maxf(1.0, u * 0.004))
	for k in 4:
		var y := lerpf(b.position.y, b.end.y, float(k) / 3.0)
		ci.draw_line(Vector2(b.position.x, y), Vector2(b.end.x, y), s["mid"], maxf(1.0, u * 0.004))
