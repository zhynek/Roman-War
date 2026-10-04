extends RefCounted
## Independent, deterministic authoring geometry. No campaign imports or state.
## All geographic detail is an explicitly interpretive local-metre model.


static func world(data: Dictionary, p: Array) -> Vector3:
	return Vector3(float(p[0]), height_at(data, float(p[0]), float(p[1])), -float(p[1]))


static func height_at(data: Dictionary, east: float, north: float) -> float:
	var p := Vector2(east, north)
	var raw: float = _raw_height(data, p)
	if raw < 0.0:
		return raw
	# Make a level foundation plane under each monument, with a soft apron.
	# The aqueduct follows the saddle and must not flatten a kilometre of city.
	var best_weight := 0.0
	var platform := raw
	for item: Dictionary in data.get("landmarks", []):
		if str(item.get("kind", "")) == "aqueduct":
			continue
		var center: Vector2 = _v2(item["position_m"])
		var d: Dictionary = item["dimensions"]
		var half := Vector2(float(d["width_m"]), float(d["depth_m"])) * 0.5
		var outer: float = maxf(half.x, half.y) + 32.0
		if absf(p.x - center.x) > outer or absf(p.y - center.y) > outer:
			continue
		var local: Vector2 = (p - center).rotated(-deg_to_rad(float(item.get("rotation_deg", 0.0))))
		var beyond: float = maxf(absf(local.x) - half.x, absf(local.y) - half.y)
		var weight: float = 1.0 - smoothstep(4.0, 28.0, beyond)
		if weight > best_weight:
			best_weight = weight
			platform = _raw_height(data, center)
	return lerpf(raw, platform, best_weight)


static func generate(data: Dictionary, stage_id: String = "reference_1200") -> Dictionary:
	var config: Dictionary = data["site"]["generation"]
	var multiplier := 1.0
	for stage: Dictionary in data["stages"]:
		if str(stage["id"]) == stage_id:
			multiplier = float(stage["density_multiplier"])
			break
	var land: PackedVector2Array = _polygon(data["site"]["boundary_m"])
	var blockers: Array = _segments(data)
	var footprints: Array = _landmark_footprints(data)
	var buildings: Array = []
	var trees: Array = []
	var lanes: Array = []
	var occupancy: Dictionary = {}
	var candidates: Array = []
	var infill: Array = []
	var max_count: int = int(config["max_buildings"])
	var districts: Array = data["districts"].duplicate()
	districts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for district: Dictionary in districts:
		var polygon: PackedVector2Array = _polygon(district["polygon_m"])
		var angle: float = deg_to_rad(float(district.get("grid_rotation_deg", 0.0)))
		var pitch: float = float(district.get("plot_pitch_m", 25.0))
		var bounds: Rect2 = _rotated_bounds(polygon, -angle)
		var density: float = float(district["density"])
		var first_x: int = int(floor(bounds.position.x / pitch))
		var last_x: int = int(ceil(bounds.end.x / pitch))
		var first_y: int = int(floor(bounds.position.y / pitch))
		var last_y: int = int(ceil(bounds.end.y / pitch))
		_append_lanes(lanes, district, polygon, angle, pitch, bounds, footprints, config)
		for iy in range(first_y, last_y + 1):
			for ix in range(first_x, last_x + 1):
				if posmod(ix, int(config["lane_every_x"])) == 0 or posmod(iy, int(config["lane_every_y"])) == 0:
					continue
				var object_id := "%s_%d_%d" % [district["id"], ix, iy]
				var seed_value: int = _stable_hash(object_id) ^ int(config["seed"])
				var rng := RandomNumberGenerator.new()
				rng.seed = seed_value
				var occupancy_draw: float = rng.randf()
				# Keep the original objects byte-identical when creative infill is enabled.
				if occupancy_draw > minf(0.98, density * multiplier):
					continue
				var local := Vector2(float(ix) * pitch, float(iy) * pitch)
				local += Vector2(rng.randf_range(-1.8, 1.8), rng.randf_range(-1.8, 1.8))
				var p: Vector2 = _warp_plot(local, district).rotated(angle)
				if not Geometry2D.is_point_in_polygon(p, polygon):
					continue
				var size := Vector3(rng.randf_range(9.0, 16.5), 0.0, rng.randf_range(10.0, 18.0))
				var style: String = str(district["style"])
				var floors: int = 1 + rng.randi_range(0, 2)
				if style == "merchant" or style == "urban":
					floors += 1 if rng.randf() < 0.42 else 0
				if style == "garden":
					floors = mini(floors, 2)
				size.y = float(floors) * rng.randf_range(2.8, 3.4) + 1.1
				var radius: float = Vector2(size.x, size.z).length() * 0.5
				var tangent: Vector2 = _warp_plot(local + Vector2(1.0, 0.0), district) - _warp_plot(local, district)
				var yaw := angle + tangent.angle() + rng.randf_range(-0.055, 0.055)
				# Houses front on the nearest arterial when close; internal plots follow ward lanes.
				var nearest: Dictionary = _nearest_segment(p, blockers, true)
				if float(nearest["distance"]) < 42.0:
					yaw = float(nearest["angle"])
				if not _clear_site(p, radius, land, blockers, footprints, config):
					continue
				var corners_ok := true
				for offset: Vector2 in [Vector2(-size.x, -size.z), Vector2(size.x, -size.z), Vector2(size.x, size.z), Vector2(-size.x, size.z)]:
					if not Geometry2D.is_point_in_polygon(p + (offset * 0.5).rotated(yaw), polygon):
						corners_ok = false
						break
				if not corners_ok:
					continue
				var candidate := {"id": object_id, "point": p, "size": size, "yaw": yaw, "style": style, "seed": seed_value, "radius": radius}
				if occupancy_draw <= density:
					candidates.append(candidate)
				else:
					infill.append(candidate)
	# Existing city first, then creative additions: extra plots cannot evict reference ones.
	candidates.append_array(infill)
	for candidate: Dictionary in candidates:
		if buildings.size() >= max_count:
			break
		var p: Vector2 = candidate["point"]
		var radius: float = float(candidate["radius"])
		if not _vacant_plot(p, Vector2(candidate["size"].x, candidate["size"].z) * 0.5, float(candidate["yaw"]), occupancy, float(config["house_gap_m"])):
			continue
		_occupy_plot(p, Vector2(candidate["size"].x, candidate["size"].z) * 0.5, float(candidate["yaw"]), occupancy)
		buildings.append({"id": candidate["id"], "position": Vector3(p.x, height_at(data, p.x, p.y), -p.y), "size": candidate["size"], "yaw": candidate["yaw"], "style": candidate["style"], "seed": candidate["seed"]})
	var bounds: Rect2 = _rotated_bounds(land, 0.0)
	var tree_rng := RandomNumberGenerator.new()
	tree_rng.seed = int(config["seed"]) ^ 173028
	for attempt in range(int(config["tree_attempts"])):
		if trees.size() >= int(config["max_trees"]):
			break
		var p := Vector2(tree_rng.randf_range(bounds.position.x, bounds.end.x), tree_rng.randf_range(bounds.position.y, bounds.end.y))
		# Consume the same draws for every candidate in every stage. Infill can
		# clear a tree without changing all later tree candidate locations.
		var tree_density_draw: float = tree_rng.randf()
		if not _clear_site(p, 3.0, land, blockers, footprints, config):
			continue
		if not _vacant(p, 4.0, occupancy, 3.0):
			continue
		# More trees in western gardens and hinterland, sparse trees in central wards.
		if p.x > -2800.0 and tree_density_draw > 0.32:
			continue
		_occupy(p, 4.0, occupancy)
		trees.append(Vector3(p.x, height_at(data, p.x, p.y), -p.y))
	return {"buildings": buildings, "trees": trees, "fields": data.get("fields", []).duplicate(true), "lanes": lanes, "stage_id": stage_id, "approximate": true}


static func _raw_height(data: Dictionary, p: Vector2) -> float:
	var site: Dictionary = data["site"]
	var boundary: Array = site["boundary_m"]
	# The modeled western border is a crop through land, not a coastline.
	var test_point := Vector2(maxf(p.x, float(site.get("western_land_edge_m", -6700.0)) + 1.0), p.y)
	var inside: bool = _inside_array(test_point, boundary)
	var edge_distance := 100000.0
	for i in range(boundary.size() - 1):
		edge_distance = minf(edge_distance, _distance_segment(p, _v2(boundary[i]), _v2(boundary[i + 1])))
	if not inside:
		return -minf(24.0, 0.15 + edge_distance * 0.13)
	var terrain: float = float(site.get("base_height_m", 4.0))
	for hill: Dictionary in site["hills"]:
		var radius: float = float(hill["radius_m"])
		var distance_sq: float = p.distance_squared_to(_v2(hill["position_m"]))
		terrain = maxf(terrain, float(hill["height_m"]) * exp(-distance_sq / (radius * radius * 0.85)))
	# Fine relief stays deterministic and modest; it represents authored ground, not a DEM.
	terrain += 0.75 * sin(p.x * 0.0073) * sin(p.y * 0.0051)
	var shore: float = smoothstep(0.0, float(site.get("coast_falloff_m", 130.0)), edge_distance)
	return maxf(0.15, terrain * shore)


static func _clear_site(p: Vector2, radius: float, land: PackedVector2Array, segments: Array, footprints: Array, config: Dictionary) -> bool:
	if not Geometry2D.is_point_in_polygon(p, land):
		return false
	for i in range(land.size()):
		if _distance_segment(p, land[i], land[(i + 1) % land.size()]) < radius + float(config["coast_clearance_m"]):
			return false
	for segment: Dictionary in segments:
		if absf(p.x - float(segment["center_x"])) > float(segment["half_x"]) + radius + float(segment["clearance"]):
			continue
		if absf(p.y - float(segment["center_y"])) > float(segment["half_y"]) + radius + float(segment["clearance"]):
			continue
		if _distance_segment(p, segment["a"], segment["b"]) < radius + float(segment["clearance"]):
			return false
	for fp: Dictionary in footprints:
		var local: Vector2 = (p - Vector2(fp["center"])).rotated(-float(fp["angle"]))
		var half: Vector2 = fp["half"]
		if absf(local.x) < half.x + radius and absf(local.y) < half.y + radius:
			return false
	return true


static func _segments(data: Dictionary) -> Array:
	var result: Array = []
	var config: Dictionary = data["site"]["generation"]
	for kind in ["roads", "walls"]:
		for line: Dictionary in data[kind]:
			var points: Array = line["points_m"]
			var clearance: float = float(line["width_m"]) * 0.5 + float(config["road_setback_m"] if kind == "roads" else config["wall_setback_m"])
			for i in range(points.size() - 1):
				var a: Vector2 = _v2(points[i])
				var b: Vector2 = _v2(points[i + 1])
				result.append({"a": a, "b": b, "clearance": clearance, "road": kind == "roads", "center_x": (a.x + b.x) * 0.5, "center_y": (a.y + b.y) * 0.5, "half_x": absf(b.x - a.x) * 0.5, "half_y": absf(b.y - a.y) * 0.5})
	return result


static func _landmark_footprints(data: Dictionary) -> Array:
	var result: Array = []
	for item: Dictionary in data["landmarks"]:
		var d: Dictionary = item["dimensions"]
		var margin: float = float(item.get("exclusion_margin_m", data["site"]["generation"]["landmark_margin_m"]))
		if str(item["kind"]) == "column":
			margin = maxf(margin, 42.0)
		result.append({"center": _v2(item["position_m"]), "half": Vector2(float(d["width_m"]) * 0.5 + margin, float(d["depth_m"]) * 0.5 + margin), "angle": deg_to_rad(float(item.get("rotation_deg", 0.0)))})
	return result


static func _nearest_segment(p: Vector2, segments: Array, roads_only: bool) -> Dictionary:
	var distance := 100000.0
	var angle := 0.0
	for segment: Dictionary in segments:
		if roads_only and not bool(segment["road"]):
			continue
		var d: float = _distance_segment(p, segment["a"], segment["b"])
		if d < distance:
			distance = d
			var direction: Vector2 = Vector2(segment["b"]) - Vector2(segment["a"])
			angle = direction.angle()
	return {"distance": distance, "angle": angle}


static func _warp_plot(local: Vector2, district: Dictionary) -> Vector2:
	# Modest continuous bends preserve walkable lanes while avoiding uniform blocks.
	# This is authored variation, never a claim to recovered medieval street plots.
	var phase: float = float(_stable_hash(str(district["id"])) % 1000) * 0.01
	return local + Vector2(8.0 * sin(local.y * 0.011 + phase) + 3.0 * sin(local.x * 0.019), 7.0 * sin(local.x * 0.009 - phase))


static func _append_lanes(out: Array, district: Dictionary, polygon: PackedVector2Array, angle: float, pitch: float, bounds: Rect2, footprints: Array, config: Dictionary) -> void:
	for vertical in [true, false]:
		var interval: float = pitch * float(config["lane_every_x"] if vertical else config["lane_every_y"])
		var cross_min: float = bounds.position.x if vertical else bounds.position.y
		var cross_max: float = bounds.end.x if vertical else bounds.end.y
		var along_min: float = bounds.position.y if vertical else bounds.position.x
		var along_max: float = bounds.end.y if vertical else bounds.end.x
		for line_index in range(int(floor(cross_min / interval)), int(ceil(cross_max / interval)) + 1):
			var cross_value: float = float(line_index) * interval
			var run: Array = []
			for step in range(int(floor(along_min / pitch)) - 1, int(ceil(along_max / pitch)) + 2):
				var along: float = float(step) * pitch
				var local_point := Vector2(cross_value, along) if vertical else Vector2(along, cross_value)
				var point: Vector2 = _warp_plot(local_point, district).rotated(angle)
				var valid: bool = Geometry2D.is_point_in_polygon(point, polygon)
				if valid:
					for fp: Dictionary in footprints:
						var local: Vector2 = (point - Vector2(fp["center"])).rotated(-float(fp["angle"]))
						var half: Vector2 = fp["half"]
						if absf(local.x) < half.x and absf(local.y) < half.y:
							valid = false
							break
				if valid:
					run.append([point.x, point.y])
				elif not run.is_empty():
					if run.size() > 2:
						out.append({"id": "%s_lane_%d" % [district["id"], out.size()], "points_m": run.duplicate(), "width_m": float(config["lane_width_m"]), "evidence": "Interpretive procedural neighborhood lane."})
					run.clear()


static func _vacant_plot(p: Vector2, half: Vector2, angle: float, occupied: Dictionary, gap: float) -> bool:
	var cell := Vector2i(floori(p.x / 40.0), floori(p.y / 40.0))
	var radius: float = half.length()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for other: Dictionary in occupied.get(Vector2i(cell.x + dx, cell.y + dy), []):
				var delta: Vector2 = other["point"] - p
				if delta.length_squared() >= pow(radius + float(other["radius"]) + gap, 2.0):
					continue
				var separated := false
				var other_half: Vector2 = other["half"]
				var other_angle: float = float(other["angle"])
				for axis: Vector2 in [Vector2.RIGHT.rotated(angle), Vector2.UP.rotated(angle), Vector2.RIGHT.rotated(other_angle), Vector2.UP.rotated(other_angle)]:
					var own_extent: float = absf(axis.dot(Vector2.RIGHT.rotated(angle))) * half.x + absf(axis.dot(Vector2.UP.rotated(angle))) * half.y
					var other_extent: float = absf(axis.dot(Vector2.RIGHT.rotated(other_angle))) * other_half.x + absf(axis.dot(Vector2.UP.rotated(other_angle))) * other_half.y
					if absf(delta.dot(axis)) >= own_extent + other_extent + gap:
						separated = true
						break
				if not separated:
					return false
	return true


static func _vacant(p: Vector2, radius: float, occupied: Dictionary, gap: float) -> bool:
	var cell := Vector2i(floori(p.x / 40.0), floori(p.y / 40.0))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for other: Dictionary in occupied.get(Vector2i(cell.x + dx, cell.y + dy), []):
				if p.distance_squared_to(other["point"]) < pow(radius + float(other["radius"]) + gap, 2.0):
					return false
	return true


static func _occupy_plot(p: Vector2, half: Vector2, angle: float, occupied: Dictionary) -> void:
	var cell := Vector2i(floori(p.x / 40.0), floori(p.y / 40.0))
	if not occupied.has(cell):
		occupied[cell] = []
	occupied[cell].append({"point": p, "half": half, "angle": angle, "radius": half.length()})


static func _occupy(p: Vector2, radius: float, occupied: Dictionary) -> void:
	_occupy_plot(p, Vector2(radius, radius), 0.0, occupied)


static func _inside_array(p: Vector2, polygon: Array) -> bool:
	var inside := false
	var j: int = polygon.size() - 1
	for i in range(polygon.size()):
		var a: Vector2 = _v2(polygon[i])
		var b: Vector2 = _v2(polygon[j])
		if (a.y > p.y) != (b.y > p.y):
			if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
		j = i
	return inside


static func _distance_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq < 0.00001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / length_sq, 0.0, 1.0))


static func _rotated_bounds(polygon: PackedVector2Array, angle: float) -> Rect2:
	var result := Rect2(polygon[0].rotated(angle), Vector2.ZERO)
	for p: Vector2 in polygon:
		result = result.expand(p.rotated(angle))
	return result


static func _polygon(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p: Array in points:
		result.append(_v2(p))
	return result


static func _v2(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


static func _stable_hash(value: String) -> int:
	var accumulator: int = 5381
	for byte in value.to_utf8_buffer():
		accumulator = ((accumulator * 33) + int(byte)) % 2147483647
	return accumulator
