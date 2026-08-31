class_name MapGeometry
extends RefCounted
## Procedural landmass for the campaign map. The 70 region points in GameData
## become one Mediterranean coastline cut into province polygons, from nothing
## but `position`, `adjacent` and `sea_zones`. Pure geometry: no game state, no
## Node, no RNG. Built once per GameData and cached.

const WORLD_SCALE := 14.0
const COAST_SEGS := 96
const COAST_WOBBLE := 0.17
const STRAIT_GAP := 9.0
const BRIDGE_KEEP := 6.0
const FRONTIER_CAP := 165.0
const BORDER_STEP := 17.0
const BORDER_WAVE := 46.0
const BORDER_AMP := 6.5
const BORDER_TAPER := 22.0

const COAST := ""
const FRONTIER := "~"

static var _cache := {}

var ids: Array = []
var cells := {}          # id -> PackedVector2Array (world space)
var tags := {}           # id -> PackedStringArray, per edge i (poly[i]->poly[i+1])
var closed := {}         # id -> ring with first point repeated
var bounds := {}         # id -> Rect2
var centroid := {}       # id -> Vector2
var coast_lines := PackedVector2Array()
var frontier_lines := PackedVector2Array()
var coast_runs := {}     # id -> Array of PackedVector2Array, shore only
var glyphs := {}         # id -> Array of {p: Vector2, r: float, roll: float}
var roads: Array = []    # [{a, b, pts: PackedVector2Array, ra, rb}]
var lanes: Array = []    # [{a: Vector2, b: Vector2}]
var _pos := {}
var _radius := {}
var _frames := {}


static func for_data(data) -> MapGeometry:
	var key: int = data.get_instance_id()
	if not _cache.has(key):
		_cache.clear()
		var geometry := MapGeometry.new()
		geometry._build(data)
		_cache[key] = geometry
	return _cache[key]


static func _hash01(key: String, salt: int) -> float:
	# One hash for the whole project: ArtNoise owns it, the building plates use
	# the same one, and test_map_geometry asserts the two never drift apart.
	return ArtNoise.hash01(key, salt)



static func _noise(key: String, t: float) -> float:
	return ArtNoise.noise(key, t)



func _build(data) -> void:
	ids = data.regions.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = data.regions[id]["position"]
		_pos[id] = Vector2(float(p["x"]), float(p["y"])) * WORLD_SCALE
	for id in ids:
		_radius[id] = _coast_radius(data, id)
	for id in ids:
		_carve(data, id)
	for id in ids:
		_scatter(data, id)
	_build_network(data)


func world_of(id: String) -> Vector2:
	return _pos.get(id, Vector2.ZERO)


func _coast_radius(data, id: String) -> float:
	var here: Vector2 = _pos[id]
	var adjacent: Array = data.regions[id].get("adjacent", [])
	if adjacent.is_empty():
		var nearest := INF
		for other in ids:
			if other != id:
				nearest = minf(nearest, here.distance_to(_pos[other]))
		return minf(nearest * 0.42, 46.0)
	var far := 0.0
	var total := 0.0
	for other in adjacent:
		var span := here.distance_to(_pos[other])
		far = maxf(far, span)
		total += span
	if (data.regions[id].get("sea_zones", []) as Array).is_empty():
		return minf(far * 1.30, FRONTIER_CAP)
	return minf(maxf(far * 0.74, total / float(adjacent.size()) * 0.88), 150.0)


func _carve(data, id: String) -> void:
	var here: Vector2 = _pos[id]
	var radius: float = _radius[id]
	var adjacent: Array = data.regions[id].get("adjacent", [])
	var landlocked: bool = (data.regions[id].get("sea_zones", []) as Array).is_empty()
	var open_tag: String = FRONTIER if landlocked else COAST

	var poly := PackedVector2Array()
	var tag_list := PackedStringArray()
	poly.resize(COAST_SEGS)
	tag_list.resize(COAST_SEGS)
	for k in COAST_SEGS:
		var theta := TAU * float(k) / float(COAST_SEGS)
		var wobble := 1.0 + COAST_WOBBLE * (
			0.55 * _noise(id + "c", theta * 2.3)
			+ 0.30 * _noise(id + "d", theta * 5.9)
			+ 0.15 * _noise(id + "e", theta * 13.1))
		poly[k] = here + Vector2.from_angle(theta) * radius * wobble
		tag_list[k] = open_tag

	var bridges: Array[Vector2] = []
	for neighbour in adjacent:
		bridges.append((here + _pos[neighbour]) * 0.5)

	for other in ids:
		if other == id:
			continue
		var there: Vector2 = _pos[other]
		var span := here.distance_to(there)
		if span < 0.001:
			continue
		var is_adjacent: bool = adjacent.has(other)
		if not is_adjacent and span * 0.5 - STRAIT_GAP > radius + 40.0:
			continue
		var normal := (there - here) / span
		var offset := normal.dot((here + there) * 0.5)
		var tag := "%s|%s" % ([id, other] if id < other else [other, id])
		if not is_adjacent and _shares_sea(data, id, other):
			offset -= STRAIT_GAP
			for bridge in bridges:
				offset = maxf(offset, normal.dot(bridge) + BRIDGE_KEEP)
			tag = COAST
		var result := _clip(poly, tag_list, normal, offset, tag)
		poly = result[0]
		tag_list = result[1]
		if poly.size() < 3:
			break

	if poly.size() < 3:
		push_warning("MapGeometry: region %s clipped away entirely" % id)
		cells[id] = PackedVector2Array()
		tags[id] = PackedStringArray()
		closed[id] = PackedVector2Array()
		coast_runs[id] = []
		bounds[id] = Rect2(here, Vector2.ZERO)
		centroid[id] = here
		glyphs[id] = []
		return

	var wobbled := _wobble_borders(poly, tag_list)
	poly = wobbled[0]
	tag_list = wobbled[1]

	cells[id] = poly
	tags[id] = tag_list
	var ring := poly.duplicate()
	ring.append(poly[0])
	closed[id] = ring
	var box := Rect2(poly[0], Vector2.ZERO)
	var sum := Vector2.ZERO
	for point in poly:
		box = box.expand(point)
		sum += point
	bounds[id] = box
	centroid[id] = sum / float(poly.size())
	for i in poly.size():
		var t: String = tag_list[i]
		if t == COAST:
			coast_lines.append(poly[i])
			coast_lines.append(poly[(i + 1) % poly.size()])
		elif t == FRONTIER:
			frontier_lines.append(poly[i])
			frontier_lines.append(poly[(i + 1) % poly.size()])
	coast_runs[id] = _coast_runs(poly, tag_list)


func _coast_runs(poly: PackedVector2Array, tag_list: PackedStringArray) -> Array:
	## Consecutive shore edges joined into open polylines, wrapping across
	## index 0. The shelf is stroked along these — never along a landlocked
	## region's frontier, which is the edge of the known world, not a beach.
	var count := poly.size()
	var runs: Array = []
	var shore := 0
	for tag in tag_list:
		if tag == COAST:
			shore += 1
	if shore == 0:
		return runs
	if shore == count:
		var whole := poly.duplicate()
		whole.append(poly[0])
		return [whole]
	# Start after a non-shore edge, so no run is split across the seam.
	var start := 0
	for i in count:
		if tag_list[i] != COAST and tag_list[(i + 1) % count] == COAST:
			start = (i + 1) % count
			break
	var run := PackedVector2Array()
	for step in count:
		var i := (start + step) % count
		if tag_list[i] == COAST:
			if run.is_empty():
				run.append(poly[i])
			run.append(poly[(i + 1) % count])
		elif not run.is_empty():
			runs.append(run)
			run = PackedVector2Array()
	if not run.is_empty():
		runs.append(run)
	return runs


func _shares_sea(data, a: String, b: String) -> bool:
	for zone in data.regions[a].get("sea_zones", []):
		if data.regions[b].get("sea_zones", []).has(zone):
			return true
	return false


func _clip(poly: PackedVector2Array, tag_list: PackedStringArray,
		normal: Vector2, offset: float, tag: String) -> Array:
	var out_poly := PackedVector2Array()
	var out_tags := PackedStringArray()
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var da := normal.dot(a) - offset
		var db := normal.dot(b) - offset
		if da <= 0.0:
			out_poly.append(a)
			out_tags.append(tag_list[i])
		if (da <= 0.0) != (db <= 0.0):
			out_poly.append(a.lerp(b, da / (da - db)))
			out_tags.append(tag if da <= 0.0 else tag_list[i])
	return [out_poly, out_tags]


func _pair_frame(tag: String) -> Array:
	if _frames.has(tag):
		return _frames[tag]
	var pair := tag.split("|")
	var a: Vector2 = _pos[pair[0]]
	var b: Vector2 = _pos[pair[1]]
	var across := (b - a).normalized()
	var frame := [(a + b) * 0.5, Vector2(-across.y, across.x), across]
	_frames[tag] = frame
	return frame


func _wobble_borders(poly: PackedVector2Array, tag_list: PackedStringArray) -> Array:
	var out_poly := PackedVector2Array()
	var out_tags := PackedStringArray()
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var tag: String = tag_list[i]
		out_poly.append(a)
		out_tags.append(tag)
		if tag == COAST or tag == FRONTIER:
			continue
		var frame := _pair_frame(tag)
		var origin: Vector2 = frame[0]
		var along: Vector2 = frame[1]
		var across: Vector2 = frame[2]
		var sa := along.dot(a - origin)
		var sb := along.dot(b - origin)
		if absf(sb - sa) < BORDER_STEP * 0.6:
			continue
		var step := BORDER_STEP if sb > sa else -BORDER_STEP
		var first: float = ceil(minf(sa, sb) / BORDER_STEP) if sb > sa \
			else floor(maxf(sa, sb) / BORDER_STEP)
		var s := first * BORDER_STEP
		var guard := 0
		while (s - sa) * (s - sb) < 0.0 and guard < 64:
			var taper := minf(1.0, minf(absf(s - sa), absf(s - sb)) / BORDER_TAPER)
			var swing := BORDER_AMP * taper * _noise(tag, s / BORDER_WAVE)
			out_poly.append(origin + along * s + across * swing)
			out_tags.append(tag)
			s += step
			guard += 1
	return [out_poly, out_tags]


const SPACING := {
	"mountains": 30.0, "forest": 26.0, "hills": 32.0,
	"desert": 40.0, "steppe": 30.0, "marsh": 28.0, "plains": 38.0,
}


func _scatter(data, id: String) -> void:
	## A jittered lattice of glyph anchors clipped to the cell, sorted north to
	## south so relief overlaps into ranges. Deterministic: hash only.
	var out: Array = []
	glyphs[id] = out
	var poly: PackedVector2Array = cells[id]
	if poly.size() < 3:
		return
	var terrain: String = data.regions[id].get("terrain", "plains")
	var step: float = SPACING.get(terrain, 34.0)
	var box: Rect2 = bounds[id]
	var cols := maxi(1, int(ceil(box.size.x / step)))
	var rows := maxi(1, int(ceil(box.size.y / step)))
	if cols * rows > 4000:
		return
	var n := 0
	for row in rows:
		for col in cols:
			n += 1
			var jx := _hash01(id, n * 3 + 1) - 0.5
			var jy := _hash01(id, n * 3 + 2) - 0.5
			var roll := _hash01(id, n * 3 + 3)
			var p := box.position + Vector2(
				(float(col) + 0.5 + jx * 0.7) * step,
				(float(row) + 0.5 + jy * 0.7) * step)
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			out.append({"p": p, "roll": roll, "fine": (col + row) % 2 == 1})
	out.sort_custom(func(a, b): return a["p"].y < b["p"].y)


func _build_network(data) -> void:
	## The adjacency graph and the sea lanes, bowed and tessellated once, so the
	## per-frame O(n^2) pair loop in _draw disappears.
	for id in ids:
		for other in ids:
			if String(other) <= String(id):
				continue
			var a: Vector2 = _pos[id]
			var b: Vector2 = _pos[other]
			if data.regions[id].get("adjacent", []).has(other):
				var pair := "%s|%s" % [id, other]
				var bow := (_hash01(pair, 91) - 0.5) * 0.16
				var mid := (a + b) * 0.5 \
					+ (b - a).orthogonal().normalized() * (a.distance_to(b) * bow)
				var pts := PackedVector2Array()
				for k in 7:
					var t := float(k) / 6.0
					pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
				roads.append({"a": id, "b": other, "pts": pts})
			elif _shares_sea(data, id, other) and a.distance_to(b) < 220.0:
				lanes.append({"a": a, "b": b, "ia": id, "ib": other})
