class_name PortNavigation
extends RefCounted
## Local inspection geometry only. No campaign state, RNG or force movement.
## Nodes and every connecting segment are derived from PortLayout footprints.
var layout: Dictionary
var graph := AStar2D.new()
var cells: Dictionary = {}
var reachable: Dictionary = {}
var spacing := 1.0
var radius := 0.28
var stride := 0
var bounds: Rect2
var traveler := "pedestrian"
var beam := 1.0

func build(plan: Dictionary, settings: Dictionary, kind: String = "pedestrian", vessel_beam: float = 1.0) -> void:
	layout = plan
	traveler = kind
	beam = vessel_beam
	spacing = float(settings["grid_spacing"])
	radius = float(settings["pedestrian_radius"])
	bounds = PortLayout.rectangle(plan["bounds"])
	stride = ceili(bounds.size.x / spacing)
	graph.clear()
	cells.clear()
	reachable.clear()
	for y in range(ceili(bounds.size.y / spacing)):
		for x in range(stride):
			var p := bounds.position + Vector2(x + 0.5, y + 0.5) * spacing
			if valid(p):
				var id := y * stride + x
				cells[Vector2i(x,y)] = id
				graph.add_point(id,p)
	for cell in cells:
		for offset in [Vector2i.RIGHT, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if cells.has(next) and segment(graph.get_point_position(cells[cell]),graph.get_point_position(cells[next])):
				graph.connect_points(cells[cell],cells[next])
	if graph.get_point_count() == 0:
		return
	var entrance := PortLayout.rectangle(plan["entrances"][0]["rect"]).get_center()
	if traveler == "vessel":
		var water := PortLayout.rectangle(plan["water"])
		entrance = Vector2(water.get_center().x,water.end.y-spacing)
	var start := graph.get_closest_point(entrance)
	var pending := [start]
	reachable[start] = true
	var cursor := 0
	while cursor < pending.size():
		for next in graph.get_point_connections(pending[cursor]):
			if not reachable.has(next):
				reachable[next] = true
				pending.append(next)
		cursor += 1

func valid(p: Vector2) -> bool:
	if traveler == "vessel":
		return PortLayout.vessel_at(layout,p,beam)
	for offset in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
		Vector2(-0.707,-0.707),Vector2(0.707,-0.707),Vector2(-0.707,0.707),Vector2(0.707,0.707)]:
		if not PortLayout.walkable_at(layout,p+offset*radius):
			return false
	return true

func segment(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1,ceili(a.distance_to(b)/(radius*0.7)))
	for i in range(steps+1):
		if not valid(a.lerp(b,float(i)/steps)):
			return false
	return true

func nearest(p: Vector2) -> Vector2:
	var best := INF
	var result := p
	for id in reachable:
		var candidate := graph.get_point_position(id)
		var distance := candidate.distance_squared_to(p)
		if distance < best:
			best = distance
			result = candidate
	return result

func battle_sites() -> Array:
	var result := PortLayout.battle_sites(layout)
	for f in layout["structures"]:
		if f["kind"] in ["shed","hall","warehouse","workshop","arsenal","barracks","shipshed"]:
			var p := approach(PortLayout.rectangle(f["rect"]))
			result.append({"id":f["id"]+"_entrance","role":"facility_approach","at":[p.x,p.y],"elevation":PortLayout.elevation_at(layout,p),"facility":f["id"]})
	for berth in layout["berths"]:
		var p := approach(PortLayout.rectangle(berth["rect"]))
		result.append({"id":berth["id"]+"_boarding","role":"boarding","at":[p.x,p.y],"elevation":PortLayout.elevation_at(layout,p),"berth":berth["id"]})
	return result

func _anchor(p: Vector2) -> int:
	var best := INF
	var found := -1
	for id in reachable:
		var candidate := graph.get_point_position(id)
		var distance := candidate.distance_squared_to(p)
		if distance < best and distance <= spacing*spacing*4 and segment(p,candidate):
			best = distance
			found = id
	return found

func route(origin: Vector2, destination: Vector2) -> Dictionary:
	if not valid(destination):
		return {"ok":false,"error":"blocked_destination","points":[]}
	var a := _anchor(origin)
	var b := _anchor(destination)
	if a < 0 or b < 0:
		return {"ok":false,"error":"unreachable_destination","points":[]}
	var raw: Array[Vector2] = [origin]
	raw.append_array(graph.get_point_path(a,b))
	raw.append(destination)
	var points: Array[Vector2] = [origin]
	var cursor := 0
	while cursor < raw.size()-1:
		var next := raw.size()-1
		while next > cursor+1 and not segment(raw[cursor],raw[next]):
			next -= 1
		points.append(raw[next])
		cursor = next
	return {"ok":true,"error":"","points":points}

func approach(rect: Rect2) -> Vector2:
	# Prefer the rendered south-facing door, then the closest reachable perimeter.
	var door := Vector2(rect.get_center().x,rect.end.y+spacing)
	if valid(door) and _anchor(door) >= 0:
		return door
	var best := INF
	var result := nearest(door)
	for id in reachable:
		var p := graph.get_point_position(id)
		if rect.has_point(p):
			continue
		var edge := Vector2(clampf(p.x,rect.position.x,rect.end.x),clampf(p.y,rect.position.y,rect.end.y))
		var score := p.distance_squared_to(edge)*1000 + p.distance_squared_to(door)
		if score < best:
			best = score
			result = p
	return result
