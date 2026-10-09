class_name CampaignCityModel
extends RefCounted
## A retained architectural miniature, built only from an observed city report.
## Static content resolves building kinds; the renderer never receives GameState.
## Dimensions are original illustrative artwork, not a historical city survey.

static func appearance_key(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	var buildings: Array = report.get("buildings", []).duplicate()
	buildings.sort()
	# A new observation date changes the intelligence label, not the geometry.
	return JSON.stringify([report.get("owner", ""), report.get("level", ""), int(report.get("population", 0)) / 250, buildings, report.get("watchpost", {}), report.get("construction", []), report.get("port", {})])

static func plan(data: GameData, region: String, report: Dictionary, approaches: Array = []) -> Dictionary:
	if report.is_empty():
		return {}
	var rank := 0
	var levels: Array = data.balance.get("settlement_levels", [])
	for i in range(levels.size()):
		if levels[i].id == report.get("level", "village"):
			rank = i
	var kinds := {}
	var completed: Array = report.get("buildings", []).duplicate()
	completed.sort()
	for building in completed:
		var info: Dictionary = data.building_levels.get(building, {})
		if not info.is_empty():
			var kind := String(info.kind)
			kinds[kind] = maxi(int(kinds.get(kind, 0)), int(info.index))
	var radius := 7.5 + rank * 1.7
	var culture := data.culture_of_faction(report.get("owner", ""))
	var result := {"region": region, "rank": rank, "radius": radius, "culture": culture, "kinds": kinds, "houses": [], "landmarks": [], "watchpost": report.get("watchpost", {}).duplicate(true), "construction": report.get("construction", []).duplicate(true), "approaches": approaches.duplicate(true)}
	# Civic buildings sit beside the street axes, in persistent precincts.
	var places := {
		"government": Vector2(radius * 0.40, -radius * 0.40),
		"temple": Vector2(-radius * 0.40, -radius * 0.40),
		"barracks": Vector2(radius * 0.40, radius * 0.40),
		"market": Vector2(-radius * 0.40, radius * 0.40),
	}
	for kind in places:
		if int(kinds.get(kind, 0)) > 0:
			var center: Vector2 = places[kind]
			var best := center
			var clearance := path_distance(center, approaches)
			for turn in [-0.45, 0.45, -0.8, 0.8]:
				var candidate := center.rotated(turn)
				var distance := path_distance(candidate, approaches)
				if distance > clearance and absf(candidate.x) > 2.6 and absf(candidate.y) > 2.6:
					clearance = distance
					best = candidate
			result.landmarks.append({"kind": kind, "tier": int(kinds[kind]), "at": best})
	# The same street blocks persist as the town grows. Geographic campaign
	# roads reserve corridors, including angled routes through the city wall.
	var spacing := 2.25
	var limit := floori((radius - 1.5) / spacing)
	var density := 0.66 + rank * 0.045
	var population_step := int(report.get("population", 0)) / 250
	density += minf(0.09, population_step * 0.002)
	for row in range(-limit, limit + 1):
		for col in range(-limit, limit + 1):
			if col == 0 or row == 0:
				continue
			var p := Vector2(col, row) * spacing
			if p.length() > radius - 1.35 or (absi(col) <= 1 and absi(row) <= 1):
				continue
			if path_distance(p, approaches) < 2.0:
				continue
			var reserved := false
			for landmark in result.landmarks:
				var delta: Vector2 = p - landmark.at
				if absf(delta.x) < 2.9 and absf(delta.y) < 3.3:
					reserved = true
			if reserved:
				continue
			var key := "%s/block/%s/%s" % [region, col, row]
			if RealismModels.scatter(key, 0) > density:
				continue
			var floors := 1 + (1 if rank >= 3 and RealismModels.scatter(key, 1) > 0.48 else 0)
			var height := 0.68 + floors * 0.43 + RealismModels.scatter(key, 2) * 0.28
			result.houses.append({"at": p, "size": Vector3(1.3 + RealismModels.scatter(key, 3) * 0.34, height, 1.30 + RealismModels.scatter(key, 4) * 0.35), "key": key, "floors": floors})
	return result

static func path_distance(point: Vector2, paths: Array) -> float:
	var nearest := INF
	for path in paths:
		for i in range(path.size() - 1):
			nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])))
	return nearest

static func gate_angles(paths: Array, radius: float) -> Array:
	var gates: Array = [0.0, PI * 0.5, PI, PI * 1.5]
	for path in paths:
		for i in range(path.size() - 1):
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			if (a.length() < radius) == (b.length() < radius):
				continue
			var inside := a if a.length() < radius else b
			var outside := b if a.length() < radius else a
			for j in range(16):
				var middle := (inside + outside) * 0.5
				if middle.length() < radius:
					inside = middle
				else:
					outside = middle
			var angle := inside.angle()
			var existing := false
			for gate in gates:
				if absf(angle_difference(float(gate), angle)) < 0.005:
					existing = true
			if not existing:
				gates.append(angle)
	return gates

static func build(spec: Dictionary, anchor: Vector2, ground: Callable, fine: bool = false) -> ArrayMesh:
	if spec.is_empty():
		return null
	var art := CampaignCityModel.new()
	art.spec = spec
	art.anchor = anchor
	art.ground = ground
	art.fine = fine
	art._build()
	return art.model.finish() if art.model.vertex_count > 0 else null

var spec: Dictionary
var anchor: Vector2
var ground: Callable
var fine := false
var model := RealismModels.new()
var stone := RealismModels.pigment("#b6aa91")
var plaster := RealismModels.pigment("#d2bf98")
var tile := RealismModels.pigment("#a96243")
var timber := RealismModels.pigment("#544434")
var paving := RealismModels.pigment("#9b947e")

func _at(p: Vector2, up: float = 0.0) -> Vector3:
	return (ground.call(anchor + p) as Vector3) + Vector3.UP * up

func _build() -> void:
	var radius := float(spec.radius)
	if spec.culture in ["eastern", "egyptian", "carthaginian"]:
		plaster = RealismModels.pigment("#d7c29b")
		tile = RealismModels.pigment("#baa17a")
	elif spec.culture == "barbarian":
		plaster = RealismModels.pigment("#9e9070")
		tile = RealismModels.pigment("#91845c")
	if not fine:
		# Paved forum and permanent street layout remain legible at all scales.
		model.box(_at(Vector2.ZERO, 0.045), Vector3(4.0, 0.07, 4.0), paving)
		for axis in [Vector2.RIGHT, Vector2.DOWN]:
			_strip(-axis * (radius + 0.7), axis * (radius + 0.7), 0.66, paving, 0.07)
		for row in range(-floori(radius / 2.25), floori(radius / 2.25) + 1):
			var offset := row * 2.25 + 1.125
			if absf(offset) >= radius - 1:
				continue
			var reach := sqrt(maxf(0, pow(radius - 0.7, 2) - offset * offset))
			_strip(Vector2(-reach, offset), Vector2(reach, offset), 0.14, paving.darkened(0.1), 0.055)
			_strip(Vector2(offset, -reach), Vector2(offset, reach), 0.14, paving.darkened(0.1), 0.055)
	for house in spec.houses:
		_house(house.at, house.size, house.key, int(house.floors))
	for landmark in spec.landmarks:
		_landmark(landmark)
	if int(spec.kinds.get("walls", 0)) > 0:
		_walls(int(spec.kinds.walls), radius)
	if int(spec.kinds.get("farms", 0)) > 0:
		_farms(int(spec.kinds.farms), radius)
	if not spec.watchpost.is_empty():
		_watchtower(Vector2(-radius - 3, radius * 0.45), int(spec.watchpost.get("level", 1)))
	if fine:
		_forum()
		for i in range(spec.construction.size()):
			_scaffolding(Vector2(radius * 0.35 + i * 1.5, radius * 0.57))

func _strip(a: Vector2, b: Vector2, width: float, tint: Color, height: float) -> void:
	var side := (b - a).orthogonal().normalized() * width
	var steps := maxi(1, ceili(a.distance_to(b) / 1.5))
	for i in range(steps):
		var start := a.lerp(b, float(i) / steps)
		var finish := a.lerp(b, float(i + 1) / steps)
		_quad(_at(start - side, height), _at(start + side, height), _at(finish - side, height), _at(finish + side, height), tint)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	model.triangle(a, c, b, tint)
	model.triangle(b, c, d, tint)

func _house(p: Vector2, size: Vector3, key: String, floors: int = 1) -> void:
	var at := _at(p)
	var w := size.x
	var h := size.y
	var d := size.z
	var tint := plaster.darkened(RealismModels.scatter(key, 5) * 0.18)
	var roof := tile.darkened(RealismModels.scatter(key, 6) * 0.18)
	if not fine:
		model.box(at + Vector3.UP * h * 0.5, size, tint)
		_roof(at + Vector3.UP * h, w + 0.15, d + 0.15, roof)
		return
	# Window recesses, wooden lintels, continuous cornices and tile courses are
	# a second batched mesh; no node, light or collider per building.
	model.box(at + Vector3(0, 0.30, -d * 0.5 - 0.018), Vector3(0.24, 0.60, 0.03), timber)
	model.box(at + Vector3(0, 0.62, -d * 0.5 - 0.036), Vector3(0.33, 0.07, 0.08), stone)
	model.box(at + Vector3(0, h - 0.045, 0), Vector3(w + 0.06, 0.085, d + 0.06), stone)
	for level in range(floors):
		for x in [-0.30, 0.30]:
			for side in [-1.0, 1.0]:
				model.box(at + Vector3(x * w, 0.82 + level * 0.43, side * (d * 0.5 + 0.022)), Vector3(0.18, 0.22, 0.035), timber)
	for side in [-1.0, 1.0]:
		for course in range(5):
			var blend := course / 5.0
			var pos := at + Vector3(side * (w + 0.15) * 0.5 * (1.0 - blend), h + w * 0.25 * blend, 0)
			model.box(pos, Vector3(0.025, 0.025, d + 0.18), roof.lightened(0.1))
	if int(RealismModels.scatter(key, 7) * 5) == 0:
		model.box(at + Vector3(w * 0.27, h + 0.13, d * 0.2), Vector3(0.20, 0.46, 0.23), stone)

func _roof(at: Vector3, w: float, d: float, tint: Color) -> void:
	var ridge := w * 0.25
	for side in [-1.0, 1.0]:
		var a := at + Vector3(side * w * 0.5, 0, -d * 0.5)
		var b := at + Vector3(side * w * 0.5, 0, d * 0.5)
		var c := at + Vector3(0, ridge, -d * 0.5)
		var e := at + Vector3(0, ridge, d * 0.5)
		_quad(a, b, c, e, tint)
	for side in [-1.0, 1.0]:
		model.triangle(at + Vector3(-w * 0.5, 0, side * d * 0.5), at + Vector3(w * 0.5, 0, side * d * 0.5), at + Vector3(0, ridge, side * d * 0.5), plaster)

func _landmark(landmark: Dictionary) -> void:
	var p: Vector2 = landmark.at
	var at := _at(p)
	var tier := int(landmark.tier)
	var kind := String(landmark.kind)
	var scale_by := 0.75 + tier * 0.10
	if kind in ["government", "temple"]:
		var w := 2.5 * scale_by
		var d := 3.3 * scale_by
		var h := 1.8 + tier * 0.15
		if not fine:
			model.box(at + Vector3.UP * 0.13, Vector3(w + 0.5, 0.26, d + 0.5), stone)
			model.box(at + Vector3(0, h * 0.5, 0.3), Vector3(w * 0.75, h, d * 0.7), plaster)
			model.box(at + Vector3.UP * h, Vector3(w + 0.18, 0.14, d + 0.2), stone)
			_roof(at + Vector3.UP * (h + 0.07), w + 0.4, d + 0.4, tile)
		else:
			for side in [-1.0, 1.0]:
				for i in range(5):
					var column := at + Vector3(side * w * 0.46, 0.25, -d * 0.40 + i * d * 0.2)
					_column(column, h - 0.25, 0.095)
			for i in range(4):
				_column(at + Vector3(-w * 0.42 + i * w * 0.28, 0.25, -d * 0.44), h - 0.25, 0.095)
			for step in range(3):
				model.box(at + Vector3(0, 0.05 + step * 0.06, -d * 0.56 - (2 - step) * 0.12), Vector3(w, 0.10, 0.26), stone)
			model.box(at + Vector3(0, 0.75, -d * 0.05 - 0.88), Vector3(0.50, 1.1, 0.03), timber)
	elif kind == "barracks":
		var width := 3.6 * scale_by
		if not fine:
			model.box(at + Vector3.UP * 0.05, Vector3(width, 0.1, 3.6), paving.darkened(0.1))
		for side in [-1.0, 1.0]:
			_house(p + Vector2(side * width * 0.37, 0), Vector3(0.95, 1.20 + tier * 0.1, 3.0), spec.region + "/barracks/" + str(side))
		if fine:
			for i in range(4):
				var post := at + Vector3(-0.5 + i * 0.34, 0, 0.6)
				model.rod(post, post + Vector3.UP * 0.8, 0.035, timber)
				model.rod(post + Vector3(-0.13, 0.55, 0), post + Vector3(0.13, 0.55, 0), 0.025, timber)
	elif kind == "market":
		if not fine:
			model.box(at + Vector3.UP * 0.06, Vector3(3.4, 0.10, 2.7), paving)
		for i in range(4 + tier):
			var stall := at + Vector3((i % 3 - 1) * 0.95, 0, (i / 3 - 0.5) * 0.85)
			if not fine:
				model.box(stall + Vector3.UP * 0.7, Vector3(0.8, 0.1, 0.67), tile.lightened(0.15 if i % 2 else 0))
			else:
				model.box(stall + Vector3.UP * 0.3, Vector3(0.65, 0.35, 0.45), timber)
				for side in [-1.0, 1.0]:
					model.rod(stall + Vector3(side * 0.32, 0, -0.2), stall + Vector3(side * 0.32, 0.7, -0.2), 0.025, timber)

func _column(at: Vector3, height: float, radius: float) -> void:
	model.rod(at, at + Vector3.UP * height, radius, stone, radius * 0.85)
	for y in [0.04, height - 0.035]:
		model.box(at + Vector3.UP * y, Vector3(radius * 2.8, 0.10, radius * 2.8), stone)

func _walls(tier: int, radius: float) -> void:
	var height := 0.9 + tier * 0.34
	var tint := timber if tier == 1 else stone.darkened(0.08)
	var segments := 64
	var gates := gate_angles(spec.approaches, radius)
	var opening := 1.45
	# Four gateway gaps lie on the permanent civic axes; no curtain crosses
	# an opening. The same ring expands only on an observed settlement upgrade.
	for i in range(segments):
		var theta := i * TAU / segments
		var gap := false
		for gate in gates:
			if absf(angle_difference(theta, float(gate))) < asin(opening / radius) + PI / segments:
				gap = true
		if gap:
			continue
		var half := PI / segments
		var a := Vector2(cos(theta - half), sin(theta - half)) * radius
		var b := Vector2(cos(theta + half), sin(theta + half)) * radius
		var center := _at((a + b) * 0.5)
		var yaw := -atan2(b.y - a.y, b.x - a.x)
		if not fine:
			_box_rotated(center + Vector3.UP * height * 0.5, Vector3(a.distance_to(b) + 0.06, height, 0.36), tint, yaw)
		else:
			var merlons := maxi(2, floori(a.distance_to(b) / 0.46))
			for j in range(merlons):
				var at := _at(a.lerp(b, (j + 0.5) / merlons), height + 0.13)
				_box_rotated(at, Vector3(0.22, 0.26, 0.43), tint, yaw)
			_box_rotated(center + Vector3.UP * (height - 0.15), Vector3(a.distance_to(b), 0.09, 0.50), stone, yaw)
	for value in gates:
		var angle := float(value)
		var center := Vector2(cos(angle), sin(angle)) * radius
		var side := Vector2(-sin(angle), cos(angle))
		for sign_value in [-1.0, 1.0]:
			var tower_at: Vector2 = center + side * (opening + 0.25) * float(sign_value)
			if path_distance(tower_at, spec.approaches) >= 1.48:
				_tower(tower_at, height + 0.6, tint)
		if not fine:
			_box_rotated(_at(center, height + 0.08), Vector3(opening * 2 + 0.5, 0.42, 0.70), tint, -angle - PI * 0.5)
	for i in range(4):
		var theta := (i + 0.5) * PI * 0.5
		var on_approach := path_distance(Vector2(cos(theta), sin(theta)) * radius, spec.approaches) < 2.0
		if not on_approach:
			_tower(Vector2(cos(theta), sin(theta)) * radius, height + 0.35, tint)

func _box_rotated(at: Vector3, size: Vector3, tint: Color, yaw: float) -> void:
	# Size belongs to local axes; RealismModels.box scales world axes after
	# rotation and would shear a diagonal curtain wall.
	var shape := BoxMesh.new()
	shape.size = size
	model.add(shape, at, Vector3.ONE, tint, Vector3(0, yaw, 0))

func _tower(p: Vector2, height: float, tint: Color) -> void:
	var at := _at(p)
	if not fine:
		model.box(at + Vector3.UP * height * 0.5, Vector3(0.88, height, 0.88), tint)
		model.box(at + Vector3.UP * (height - 0.05), Vector3(1.0, 0.17, 1.0), stone)
	else:
		for x in [-0.35, 0.35]:
			for z in [-0.35, 0.35]:
				model.box(at + Vector3(x, height + 0.10, z), Vector3(0.27, 0.28, 0.27), tint)
		for side in [-1.0, 1.0]:
			model.box(at + Vector3(0, height * 0.65, side * 0.447), Vector3(0.07, 0.35, 0.02), timber)

func _farms(tier: int, radius: float) -> void:
	for i in range(2 + tier):
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector2(side * (radius + 2.6), (i / 2 - 1) * 3.3)
		var crop := RealismModels.pigment("#8a8c4d" if i % 2 else "#a79858")
		if not fine:
			_strip(p + Vector2(-1.9, 0), p + Vector2(1.9, 0), 1.25, crop, 0.06)
		else:
			for row in range(8):
				var offset := Vector2(0, row * 0.3 - 1.05)
				_strip(p + offset - Vector2(1.8, 0), p + offset + Vector2(1.8, 0), 0.035, crop.darkened(0.25), 0.085)
			_strip(p - Vector2(2, 1.35), p + Vector2(2, -1.35), 0.055, timber.lightened(0.25), 0.1)
			_strip(p - Vector2(2, -1.35), p + Vector2(2, 1.35), 0.055, timber.lightened(0.25), 0.1)

func _watchtower(p: Vector2, tier: int) -> void:
	var height := 2.2 + tier * 0.45
	_tower(p, height, stone.darkened(0.12))
	if not fine:
		_roof(_at(p, height + 0.25), 1.3, 1.3, tile)
	else:
		for i in range(7):
			model.box(_at(p, 0.15 + i * 0.24) + Vector3(0.47, 0, 0), Vector3(0.08, 0.055, 0.30), timber)

func _forum() -> void:
	for row in range(10):
		for col in range(10):
			var key := "%s/forum/%s/%s" % [spec.region, row, col]
			var p := Vector2((col - 4.5) * 0.39, (row - 4.5) * 0.39)
			model.box(_at(p, 0.09), Vector3(0.37, 0.035, 0.37), paving.lightened(RealismModels.scatter(key) * 0.13))
	# A basin and small stone monument anchor the precinct without inventing
	# an unbuilt wonder or an anachronistic imperial amphitheatre.
	var at := _at(Vector2(0.55, 0.5))
	model.box(at + Vector3.UP * 0.17, Vector3(0.8, 0.32, 0.6), stone)
	model.box(at + Vector3.UP * 0.335, Vector3(0.63, 0.02, 0.43), RealismModels.pigment("#648981"))
	if int(spec.kinds.get("government", 0)) >= 3:
		_column(_at(Vector2(-0.6, -0.3), 0.1), 1.2, 0.12)
		model.box(_at(Vector2(-0.6, -0.3), 1.4), Vector3(0.25, 0.3, 0.2), stone)

func _scaffolding(p: Vector2) -> void:
	var at := _at(p)
	for x in [-0.6, 0.6]:
		for z in [-0.5, 0.5]:
			model.rod(at + Vector3(x, 0, z), at + Vector3(x, 1.8, z), 0.03, timber)
	for y in [0.6, 1.2, 1.7]:
		model.box(at + Vector3(0, y, -0.5), Vector3(1.35, 0.05, 0.22), timber)
		model.rod(at + Vector3(-0.6, y - 0.5, -0.5), at + Vector3(0.6, y, -0.5), 0.025, timber)
