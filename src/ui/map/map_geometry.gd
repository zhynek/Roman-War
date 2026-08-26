class_name MapGeometry
extends RefCounted
## Loads data/map_geometry.json (coastlines, province polygons, road paths)
## and serves it to the map renderer in world pixels: every coordinate is
## pre-scaled by MapView.WORLD_SCALE and every polygon pre-decomposed into
## convex fans, since CanvasItem fills are only defined for convex shapes.
## Presentation data only — the campaign rules never see this class.

var cells: Dictionary = {}      ## region_id -> {polys, fills, label}
var landmasses: Array = []      ## [{outline: PackedVector2Array}]
var edges: Dictionary = {}      ## "a|b" -> PackedVector2Array
var world_rect := Rect2()       ## bounds of all land, world pixels


static func load_from(path: String = "res://data/map_geometry.json") -> MapGeometry:
	## null when the file is absent (fixture worlds have no geometry).
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not (parsed is Dictionary):
		return null
	var geometry := MapGeometry.new()
	geometry._build(parsed)
	return geometry


func region_at_world(world: Vector2) -> String:
	## The region whose territory contains a world-pixel point, or "".
	for region_id in cells:
		if not cells[region_id]["bounds"].has_point(world):
			continue
		for polygon in cells[region_id]["polys"]:
			if Geometry2D.is_point_in_polygon(world, polygon):
				return region_id
	return ""


func edge_path(a: String, b: String) -> PackedVector2Array:
	var key := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
	var path: PackedVector2Array = edges.get(key, PackedVector2Array())
	if not path.is_empty() and a > b:
		var reversed := PackedVector2Array(path)
		reversed.reverse()
		return reversed
	return path


func label_of(region_id: String) -> Vector2:
	return cells.get(region_id, {}).get("label", Vector2.ZERO)


func _build(parsed: Dictionary) -> void:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for mass in parsed.get("landmasses", []):
		var outline := _points(mass["outline"])
		for point in outline:
			min_point = min_point.min(point)
			max_point = max_point.max(point)
		landmasses.append({"outline": outline, "fills": _decompose(outline)})
	for cell in parsed.get("cells", []):
		var polys: Array = []
		var fills: Array = []
		var bounds := Rect2()
		for ring in cell["polygons"]:
			var polygon := _points(ring)
			polys.append(polygon)
			fills.append_array(_decompose(polygon))
			var ring_rect := Rect2(polygon[0], Vector2.ZERO)
			for point in polygon:
				ring_rect = ring_rect.expand(point)
			bounds = ring_rect if polys.size() == 1 else bounds.merge(ring_rect)
		cells[cell["region"]] = {
			"polys": polys, "fills": fills, "bounds": bounds.grow(0.5),
			"label": Vector2(cell["label"][0], cell["label"][1]) * MapView.WORLD_SCALE,
		}
	for edge in parsed.get("edges", []):
		edges["%s|%s" % [edge["a"], edge["b"]]] = _points(edge["path"])
	if min_point.x < INF:
		world_rect = Rect2(min_point, max_point - min_point)


static func _points(pairs: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pairs.size())
	for i in range(pairs.size()):
		out[i] = Vector2(pairs[i][0], pairs[i][1]) * MapView.WORLD_SCALE
	return out


static func _decompose(polygon: PackedVector2Array) -> Array:
	## Convex pieces for filling; winding does not matter to the decomposer.
	## A rare degenerate ring decomposes to nothing — the stroke still shows.
	return Geometry2D.decompose_polygon_in_convex(polygon)
