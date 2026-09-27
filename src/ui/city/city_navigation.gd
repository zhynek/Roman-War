class_name RomaCityNavigation
extends RefCounted
## Presentation-only picking and governor relocation. Physics is queried, never
## stepped here; there is no campaign movement, clock, command or RNG access.

static func pick(world: Node3D, camera: Camera3D, screen_position: Vector2, player: CharacterBody3D) -> Dictionary:
	var miss := {"hit": false, "position": Vector3.ZERO, "building_id": "", "site_id": "", "normal": Vector3.ZERO}
	if not is_instance_valid(world) or not world.is_inside_tree() or not is_instance_valid(camera):
		return miss
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * camera.far)
	if is_instance_valid(player):
		query.exclude = [player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return miss
	var identity := _shape_identity(hit)
	if str(identity.site_id).is_empty() and str(identity.building_id).is_empty() and hit.normal.y > 0.5:
		var layout: Dictionary = world.get("layout")
		var nearest := INF
		for site in layout.get("sites", []):
			var distance: float = Vector2(hit.position.x, hit.position.z).distance_to(Vector2(float(site.position[0]), float(site.position[1])))
			if distance <= float(site.radius) and distance < nearest:
				identity.site_id = str(site.id)
				nearest = distance
	return {"hit": true, "position": hit.position, "building_id": identity.building_id, "site_id": identity.site_id, "normal": hit.normal}

static func _shape_identity(hit: Dictionary) -> Dictionary:
	var identity := {"building_id": "", "site_id": ""}
	var collider = hit.get("collider")
	if not collider is CollisionObject3D:
		return identity
	var shape_index := int(hit.get("shape", -1))
	if shape_index < 0:
		return identity
	var owner_id: int = collider.shape_find_owner(shape_index)
	var owner: Object = collider.shape_owner_get_owner(owner_id)
	for key in identity:
		identity[key] = str(owner.get_meta(key, collider.get_meta(key, ""))) if owner != null else str(collider.get_meta(key, ""))
	return identity

static func landing(world: Node3D, player: CharacterBody3D, requested: Vector3, site_id: String = "", building_id: String = "") -> Dictionary:
	if not is_instance_valid(world) or not world.is_inside_tree() or not is_instance_valid(player):
		return _refusal("jump_unavailable")
	var layout: Dictionary = world.get("layout")
	var shape_node := _player_shape(player)
	if shape_node == null:
		return _refusal("jump_unavailable")
	var target := destination(layout, requested, site_id, building_id)
	if not bool(target.ok):
		return target
	var candidate: Vector3 = target.position
	var radius := _radius(shape_node.shape)
	if not inside_city(layout, candidate, radius):
		return _refusal("jump_outside")
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.exclude = [player.get_rid()]
	query.collision_mask = player.collision_mask
	query.margin = player.safe_margin
	# All authored ground is at grade. Use the player's real local shape offset
	# and clearance, so neither a roof hit nor a furniture hit becomes a perch.
	var ground_y := maxf(0.08, player.safe_margin * 2.0)
	candidate.y = ground_y
	var offsets := [Vector2.ZERO]
	# A close obstacle may nudge the landing at most one body length. This is
	# never a clamp from outside the walls or a jump to an unrelated district.
	for ring in [radius * 2.0, radius * 4.0, radius * 6.0]:
		for i in range(8):
			offsets.append(Vector2(cos(i * TAU / 8.0), sin(i * TAU / 8.0)) * ring)
	for offset in offsets:
		var point := candidate + Vector3(offset.x, 0, offset.y)
		if not inside_city(layout, point, radius) or not _clear(space, query, shape_node.transform, point):
			continue
		if _connected(world, layout, space, query, shape_node.transform, point, radius):
			return {"ok": true, "position": point, "reason": ""}
	return _refusal("jump_blocked")

## Resolve authored doors separately so both the minimap and the 3D view share
## one destination contract. Unknown explicit ids do not degrade to raw input.
static func destination(layout: Dictionary, requested: Vector3, site_id: String = "", building_id: String = "") -> Dictionary:
	if not requested.is_finite():
		return _refusal("jump_outside")
	if not building_id.is_empty():
		var building: Dictionary = {}
		for candidate in layout.get("buildings", []):
			if str(candidate.id) == building_id:
				building = candidate
				break
		if building.is_empty():
			return _refusal("jump_unknown")
		# The civic buildings' approach also avoids yard walls and portico steps.
		for site in layout.get("sites", []):
			if str(site.id) == building_id:
				return {"ok": true, "position": _point(site.approach), "reason": ""}
		return {"ok": true, "position": _point(building.position) + Vector3(0, 0, float(building.size[1]) * 0.5 + 1.2), "reason": ""}
	if not site_id.is_empty():
		for site in layout.get("sites", []):
			if str(site.id) == site_id:
				return {"ok": true, "position": _point(site.approach), "reason": ""}
		return _refusal("jump_unknown")
	return {"ok": true, "position": Vector3(requested.x, 0, requested.z), "reason": ""}

static func inside_city(layout: Dictionary, point: Vector3, radius: float) -> bool:
	if not point.is_finite():
		return false
	# Stay on the enclosed tactical surface, including when the decorative
	# exterior ground extends farther than the city wall.
	var half_extent := float(layout.get("walls", {}).get("half_extent", 0.0))
	var edge := half_extent - radius
	return edge > 0.0 and absf(point.x) < edge and absf(point.z) < edge

static func _player_shape(player: CharacterBody3D) -> CollisionShape3D:
	for child in player.get_children():
		if child is CollisionShape3D and child.shape != null and not child.disabled:
			return child
	return null

static func _radius(shape: Shape3D) -> float:
	if shape is CapsuleShape3D or shape is CylinderShape3D or shape is SphereShape3D:
		return shape.radius
	return 0.30

static func _clear(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, local_shape: Transform3D, point: Vector3) -> bool:
	query.transform = Transform3D(Basis.IDENTITY, point) * local_shape
	query.motion = Vector3.ZERO
	return space.intersect_shape(query, 1).is_empty()

static func _passage(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, local_shape: Transform3D, from: Vector3, to: Vector3) -> bool:
	query.transform = Transform3D(Basis.IDENTITY, from) * local_shape
	query.motion = to - from
	var fractions := space.cast_motion(query)
	query.motion = Vector3.ZERO
	return fractions.size() == 2 and fractions[0] >= 0.9999

## A clear capsule alone would accept the inside of a fountain or a sealed
## court. A small lazy street graph proves a swept capsule connection to the
## authored arrival street. Successful cells are retained on this world only.
static func _connected(world: Node3D, layout: Dictionary, space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, local_shape: Transform3D, target: Vector3, radius: float) -> bool:
	var spawn: Array = layout.get("spawn", [0, 0, 45])
	var origin := Vector3(float(spawn[0]), target.y, float(spawn[2]))
	if _passage(space, query, local_shape, target, origin):
		return true
	var step := radius * 4.0
	var connected: Dictionary = world.get_meta("roma_connected_street_cells", {})
	var clear_cells: Dictionary = world.get_meta("roma_clear_street_cells", {})
	var disconnected: Dictionary = world.get_meta("roma_disconnected_street_cells", {})
	var start := Vector2i(roundi(target.x / step), roundi(target.z / step))
	if disconnected.has(start):
		return false
	var start_position := _cell_point(start, step, target.y)
	if not _clear(space, query, local_shape, start_position) or not _passage(space, query, local_shape, target, start_position):
		return false
	var costs := {start: 0.0}
	var previous: Dictionary = {}
	var visited: Dictionary = {}
	var goal := Vector2(origin.x, origin.z) / step
	var open: Array[Dictionary] = []
	var serial := 0
	_heap_push(open, {"cell": start, "score": Vector2(start).distance_to(goal), "serial": serial})
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var found := false
	var finish := start
	while not open.is_empty() and visited.size() < 8192:
		var cell: Vector2i = _heap_pop(open).cell
		if visited.has(cell):
			continue
		visited[cell] = true
		var position := _cell_point(cell, step, target.y)
		if connected.has(cell) or (Vector2(cell).distance_to(goal) < 2.0 and _passage(space, query, local_shape, position, origin)):
			found = true
			finish = cell
			break
		for direction in directions:
			var next := cell + direction
			if visited.has(next):
				continue
			var next_position := _cell_point(next, step, target.y)
			if not clear_cells.has(next):
				clear_cells[next] = inside_city(layout, next_position, radius) and _clear(space, query, local_shape, next_position)
			if not bool(clear_cells[next]) or not _passage(space, query, local_shape, position, next_position):
				continue
			var next_cost: float = float(costs[cell]) + Vector2(direction).length()
			if costs.has(next) and float(costs[next]) <= next_cost:
				continue
			costs[next] = next_cost
			previous[next] = cell
			serial += 1
			_heap_push(open, {"cell": next, "score": next_cost + Vector2(next).distance_to(goal), "serial": serial})
	if found:
		connected[finish] = true
		while previous.has(finish):
			finish = previous[finish]
			connected[finish] = true
	elif open.is_empty():
		for cell in visited:
			disconnected[cell] = true
	world.set_meta("roma_connected_street_cells", connected)
	world.set_meta("roma_clear_street_cells", clear_cells)
	world.set_meta("roma_disconnected_street_cells", disconnected)
	return found

static func _heap_push(heap: Array[Dictionary], entry: Dictionary) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _heap_before(entry, heap[parent]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = entry

static func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	var first := heap[0]
	var last: Dictionary = heap.pop_back()
	if heap.is_empty():
		return first
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and _heap_before(heap[child + 1], heap[child]):
			child += 1
		if not _heap_before(heap[child], last):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return first

static func _heap_before(a: Dictionary, b: Dictionary) -> bool:
	return float(a.score) < float(b.score) or (float(a.score) == float(b.score) and int(a.serial) < int(b.serial))

static func _cell_point(cell: Vector2i, step: float, y: float) -> Vector3:
	return Vector3(cell.x * step, y, cell.y * step)

static func _point(point: Array) -> Vector3:
	return Vector3(float(point[0]), 0, float(point[1]))

static func _refusal(reason: String) -> Dictionary:
	return {"ok": false, "position": Vector3.ZERO, "reason": reason}
