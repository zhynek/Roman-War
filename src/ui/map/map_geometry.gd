class_name MapGeometry
extends RefCounted
## The offline-generated map geometry (data/map_geometry.json): landmass
## coastlines, one polygon cell per region, and land-hugging road paths per
## adjacency — scaled into world pixels and pre-triangulated for drawing.
## Presentation data only: it lives under src/ui and the core never reads it.


var landmasses: Array = []  # [{outline, tris, holes: [PackedVector2Array]}]
var cells := {}             # region_id -> {polygons, tris, label, bounds}
var edges := {}             # "a|b" (sorted) -> PackedVector2Array


static func load_for(data: GameData, scale: float, path: String = "res://data/map_geometry.json") -> MapGeometry:
	## null when the file is absent or does not cover every region of `data`
	## (the synthetic test fixtures): callers then fall back to the plain
	## token map, picking by nearest anchor as before.
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not (parsed is Dictionary):
		return null

	var geometry := MapGeometry.new()
	for entry in parsed.get("landmasses", []):
		var outline := _scaled(entry["outline"], scale)
		var holes: Array = []
		var hole_tris: Array = []
		for hole in entry.get("holes", []):
			var ring := _scaled(hole, scale)
			holes.append(ring)
			hole_tris.append_array(_triangulate(ring))
		geometry.landmasses.append({
			"outline": outline, "tris": _triangulate(outline),
			"holes": holes, "hole_tris": hole_tris,
		})

	for cell in parsed.get("cells", []):
		var polygons: Array = []
		var tris: Array = []
		var bounds := Rect2()
		for ring in cell["polygons"]:
			var polygon := _scaled(ring, scale)
			polygons.append(polygon)
			tris.append_array(_triangulate(polygon))
			var polygon_bounds := _bounds_of(polygon)
			bounds = polygon_bounds if polygons.size() == 1 else bounds.merge(polygon_bounds)
		geometry.cells[String(cell["region"])] = {
			"polygons": polygons, "tris": tris,
			"label": Vector2(float(cell["label"][0]), float(cell["label"][1])) * scale,
			"bounds": bounds.grow(1.0),
		}

	for edge in parsed.get("edges", []):
		geometry.edges[edge_key(String(edge["a"]), String(edge["b"]))] = _scaled(edge["path"], scale)

	for region_id in data.regions:
		if not geometry.cells.has(region_id):
			return null  # not this world's geometry — fall back
	return geometry


func region_at_world(world: Vector2) -> String:
	## The region whose cell contains a world-space point, or "".
	var region_ids: Array = cells.keys()
	region_ids.sort()
	for region_id in region_ids:
		var cell: Dictionary = cells[region_id]
		if not (cell["bounds"] as Rect2).has_point(world):
			continue
		for polygon in cell["polygons"]:
			if Geometry2D.is_point_in_polygon(world, polygon):
				return region_id
	return ""


func edge_path(a: String, b: String) -> PackedVector2Array:
	return edges.get(edge_key(a, b), PackedVector2Array())


func label_of(region_id: String) -> Vector2:
	return cells.get(region_id, {}).get("label", Vector2.ZERO)


static func edge_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


static func _scaled(points: Array, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in range(points.size()):
		out[i] = Vector2(float(points[i][0]), float(points[i][1])) * scale
	return out


static func _triangulate(polygon: PackedVector2Array) -> Array:
	## Concave-safe fill: ear-clipped triangles as 3-point polygons, ready
	## for draw_colored_polygon. Zero-area slivers (from collinear vertices)
	## are dropped — the renderer rejects them loudly and draws nothing.
	var tris: Array = []
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, indices.size(), 3):
		var tri := PackedVector2Array()
		tri.resize(3)
		tri[0] = polygon[indices[i]]
		tri[1] = polygon[indices[i + 1]]
		tri[2] = polygon[indices[i + 2]]
		if absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) > 0.01:
			tris.append(tri)
	return tris


static func _bounds_of(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	return bounds
