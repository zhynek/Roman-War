class_name RomaCityPeople
extends Node3D
## A display-only population. Authored street routes and anchors are consumed
## here; neither the campaign state nor its RNG is ever stored or modified.

const CitizenMeshes = preload("res://src/ui/city/citizen_meshes.gd")
const Models = preload("res://src/ui/realism/models.gd")

var people: Array[Dictionary] = []
var _meshes: Dictionary = {}
var _material: ShaderMaterial
var _elapsed := 0.0
var _status: Dictionary = {}

func build(layout: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	people.clear()
	_elapsed = 0.0
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://src/ui/city/citizen_surface.gdshader")
	var routes: Array = layout.get("citizen_routes", [])
	for index in range(routes.size()):
		var route: Dictionary = routes[index] if routes[index] is Dictionary else {"points": routes[index]}
		var points: Array = route.get("points", [])
		if points.size() < 2:
			continue
		var path := _path(points, bool(route.get("loop", true)))
		if float(path.get("length", 0.0)) <= 0.01:
			continue
		var count := clampi(int(route.get("count", 4)), 1, 24)
		for member in range(count):
			var id := "%s_%02d" % [String(route.get("id", "route_%s" % index)), member]
			var role := String(route.get("role", "citizen"))
			var person := _make_person(id, role, member, count, route)
			person["path"] = path
			person["phase"] = float(member) / count * float(path.length)
			person["speed"] = float(route.get("speed", 0.70)) * (0.88 + Models.scatter(id, 5) * 0.24)
			people.append(person)
	var anchors: Array = layout.get("people_anchors", [])
	for index in range(anchors.size()):
		var anchor: Dictionary = anchors[index]
		var position_data: Array = anchor.get("position", [])
		if position_data.size() < 2:
			continue
		var count := clampi(int(anchor.get("count", 1)), 1, 24)
		var default_columns := 1 if String(anchor.get("role", "")) == "grain_queue" else ceili(sqrt(count))
		var columns := maxi(1, int(anchor.get("columns", default_columns)))
		var spacing := float(anchor.get("spacing", 0.85))
		for member in range(count):
			var id := "%s_%02d" % [String(anchor.get("id", "anchor_%s" % index)), member]
			var role := String(anchor.get("role", "citizen"))
			var person := _make_person(id, role, member, count, anchor)
			var offset := Vector3((member % columns - (columns - 1) * 0.5) * spacing, 0, floorf(float(member) / columns) * spacing)
			person["anchor"] = Vector3(float(position_data[0]), 0.025, float(position_data[1])) + offset
			person["facing"] = float(anchor.get("facing", 0.0))
			people.append(person)
	apply_status(_status)

func apply_status(status: Dictionary) -> void:
	_status = status.duplicate(true)
	var policies: Dictionary = _status.get("policies", {})
	var projects: Dictionary = _status.get("projects", {})
	var trained := bool(projects.get("drill_maniples", {}).get("completed", false))
	var equipped := bool(projects.get("equip_maniples", {}).get("completed", false))
	var unrest := clampf(float(_status.get("unrest", 20)), 0, 100)
	for person in people:
		var group: String = person.status_group
		var active := true
		if group == "patrol_extra":
			active = String(policies.get("patrols", "normal")) == "heavy"
		elif group == "protest":
			var crowd := ceili(float(person.group_count) * clampf((unrest - 25.0) / 65.0, 0.0, 1.0))
			active = int(person.group_index) < crowd
		elif group == "grain_queue":
			active = int(_status.get("grain_days", 0)) > 0
		elif group == "tavern":
			active = String(policies.get("taverns", "open")) == "open"
		person.trained = trained
		if person.equipment != null:
			person.equipment.visible = equipped
		person.active = active
		person.node.visible = active
		person.mood = String(_status.get("mood", "calm"))
		person.text_key = "city.dialogue.%s.%s" % [person.role, person.mood]
	# Newly visible groups appear at their authored location immediately, even
	# if the caller inspects or renders before the next presentation frame.
	_animate()

func nearest_person(at: Vector3, max_distance: float = 3.0) -> Dictionary:
	var closest: Dictionary = {}
	var distance_squared := max_distance * max_distance
	for person in people:
		if not bool(person.active):
			continue
		var node: Node3D = person.node
		var distance := at.distance_squared_to(node.global_position)
		if distance < distance_squared:
			distance_squared = distance
			closest = {"id": person.id, "role": person.role, "mood": person.mood, "text_key": person.text_key}
	return closest

func _process(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	_animate()

func _make_person(id: String, role: String, member: int, count: int, source: Dictionary) -> Dictionary:
	var variant := int(Models.scatter(id, 2) * 12) % 12
	var mesh_role := role if role in ["guard", "merchant", "porter"] else "citizen"
	var mesh_key := "%s/%s" % [mesh_role, variant]
	if not _meshes.has(mesh_key):
		_meshes[mesh_key] = CitizenMeshes.build(mesh_role, variant)
	var parts: Dictionary = _meshes[mesh_key]
	var root := Node3D.new()
	root.name = id.validate_node_name()
	add_child(root)
	var height := 0.93 + Models.scatter(id, 3) * 0.12
	root.scale = Vector3.ONE * height
	var rig := Node3D.new()
	root.add_child(rig)
	var body := _part(rig, parts.body, Vector3.ZERO)
	var head := _joint(rig, Vector3(0, 1.445, 0))
	_part(head, parts.head, Vector3(0, -1.445, 0))
	var left_arm := _joint(rig, Vector3(-0.205, 1.335, 0))
	var right_arm := _joint(rig, Vector3(0.205, 1.335, 0))
	_part(left_arm, parts.left_arm, Vector3.ZERO)
	_part(right_arm, parts.right_arm, Vector3.ZERO)
	var left_elbow := _joint(left_arm, Vector3(0, -0.27, 0))
	var right_elbow := _joint(right_arm, Vector3(0, -0.27, 0))
	_part(left_elbow, parts.left_forearm, Vector3.ZERO)
	_part(right_elbow, parts.right_forearm, Vector3.ZERO)
	var left_hand := _joint(left_elbow, Vector3(0, -0.24, 0))
	var right_hand := _joint(right_elbow, Vector3(0, -0.24, 0))
	_part(left_hand, parts.left_hand, Vector3.ZERO)
	_part(right_hand, parts.right_hand, Vector3.ZERO)
	var left_leg := _joint(rig, Vector3(-0.105, 0.86, 0))
	var right_leg := _joint(rig, Vector3(0.105, 0.86, 0))
	_part(left_leg, parts.left_leg, Vector3.ZERO).visible = not bool(parts.long_tunic)
	_part(right_leg, parts.right_leg, Vector3.ZERO).visible = not bool(parts.long_tunic)
	var left_knee := _joint(left_leg, Vector3(0, -0.37, 0))
	var right_knee := _joint(right_leg, Vector3(0, -0.37, 0))
	_part(left_knee, parts.calf, Vector3.ZERO)
	_part(right_knee, parts.calf, Vector3.ZERO)
	var left_foot := _joint(left_knee, Vector3(0, -0.40, 0))
	var right_foot := _joint(right_knee, Vector3(0, -0.40, 0))
	_part(left_foot, parts.foot, Vector3.ZERO)
	_part(right_foot, parts.foot, Vector3.ZERO)
	var equipment: MeshInstance3D = null
	if role == "guard":
		_part(left_hand, parts.shield, Vector3(0, -0.02, 0))
		_part(right_hand, parts.spear, Vector3(0, -0.02, 0))
		equipment = _part(rig, parts.equipment, Vector3.ZERO)
		equipment.visible = false
	var group := String(source.get("status_group", ""))
	if group.is_empty():
		group = {"protester": "protest", "grain_queue": "grain_queue", "patron": "tavern"}.get(role, "")
	return {"id": id, "role": role, "mood": "calm", "text_key": "", "node": root,
		"rig": rig, "body": body, "head": head, "left_arm": left_arm, "right_arm": right_arm,
		"left_elbow": left_elbow, "right_elbow": right_elbow, "left_hand": left_hand, "right_hand": right_hand,
		"left_leg": left_leg, "right_leg": right_leg, "left_knee": left_knee, "right_knee": right_knee,
		"left_foot": left_foot, "right_foot": right_foot, "equipment": equipment, "trained": false,
		"phase": 0.0, "speed": 0.0, "path": {}, "anchor": Vector3.ZERO, "facing": 0.0,
		"gesture_phase": Models.scatter(id, 7) * TAU, "active": true,
		"status_group": group, "group_index": member, "group_count": count,
		"activity": String(source.get("activity", "")), "long_tunic": bool(parts.long_tunic)}

func _joint(parent: Node3D, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = at
	parent.add_child(joint)
	return joint

func _part(parent: Node3D, mesh: ArrayMesh, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material
	instance.position = at
	parent.add_child(instance)
	return instance

func _path(points: Array, loop: bool) -> Dictionary:
	var vertices: Array[Vector3] = []
	for point in points:
		if point is Array and point.size() >= 2:
			vertices.append(Vector3(float(point[0]), 0.025, float(point[1])))
	if vertices.size() < 2:
		return {}
	if loop:
		if not vertices[-1].is_equal_approx(vertices[0]):
			vertices.append(vertices[0])
	else:
		# A two-way walk retraces its authored street, never a diagonal shortcut.
		for index in range(vertices.size() - 2, -1, -1):
			vertices.append(vertices[index])
	var lengths: Array[float] = []
	var total := 0.0
	for index in range(vertices.size() - 1):
		total += vertices[index].distance_to(vertices[index + 1])
		lengths.append(total)
	return {"vertices": vertices, "lengths": lengths, "length": total}

func _animate() -> void:
	for person in people:
		if not bool(person.active):
			continue
		var node: Node3D = person.node
		var path: Dictionary = person.path
		var moving := not path.is_empty()
		if moving:
			var distance := fposmod(float(person.phase) + _elapsed * float(person.speed), float(path.length))
			var previous := 0.0
			var vertices: Array = path.vertices
			var lengths: Array = path.lengths
			for index in range(lengths.size()):
				var end := float(lengths[index])
				if distance <= end and end > previous:
					var start_point: Vector3 = vertices[index]
					var end_point: Vector3 = vertices[index + 1]
					node.position = start_point.lerp(end_point, (distance - previous) / (end - previous))
					var direction := end_point - start_point
					node.rotation.y = atan2(-direction.x, -direction.z)
					break
				previous = end
		else:
			node.position = person.anchor
			node.rotation.y = float(person.facing)
		_pose(person, moving)

func _pose(person: Dictionary, moving: bool) -> void:
	var seed_phase := float(person.gesture_phase)
	var phase := _elapsed * TAU * float(person.speed) / 0.80 + seed_phase
	var idle := _elapsed * 1.5 + seed_phase
	var rig: Node3D = person.rig
	var head: Node3D = person.head
	var body: MeshInstance3D = person.body
	var left_arm: Node3D = person.left_arm
	var right_arm: Node3D = person.right_arm
	var left_elbow: Node3D = person.left_elbow
	var right_elbow: Node3D = person.right_elbow
	var left_hand: Node3D = person.left_hand
	var right_hand: Node3D = person.right_hand
	var guarded := String(person.role) == "guard"
	var carrying := String(person.role) == "porter"
	var trained := guarded and bool(person.trained)
	# Root stays exactly on the authored street. Weight transfer belongs to the
	# visual rig, so picking, navigation, civic days and forces never move here.
	rig.position = Vector3(0, -0.018, 0)
	rig.rotation = Vector3.ZERO
	body.rotation = Vector3.ZERO
	body.scale.y = 1.0
	head.rotation = Vector3(sin(idle * 0.6) * 0.015, sin(idle * 0.21) * (0.12 if guarded else 0.22), 0)
	left_arm.rotation = Vector3(0.02, 0, -0.07)
	right_arm.rotation = Vector3(0.02, 0, 0.07)
	left_elbow.rotation = Vector3(0.18, 0, 0)
	right_elbow.rotation = Vector3(0.18, 0, 0)
	left_hand.rotation = Vector3(-0.10, 0, 0)
	right_hand.rotation = Vector3(-0.10, 0, 0)
	if moving:
		var wave := sin(phase)
		rig.position.x = wave * 0.013
		rig.position.y = -0.040 - cos(phase * 2.0) * 0.018
		rig.rotation.z = wave * 0.016
		body.rotation.y = -wave * 0.022
		head.rotation.z = -rig.rotation.z * 0.75
		_step(person.left_leg, person.left_knee, person.left_foot, phase, rig.position.y, bool(person.long_tunic))
		_step(person.right_leg, person.right_knee, person.right_foot, phase + PI, rig.position.y, bool(person.long_tunic))
		left_arm.rotation.x = -wave * (0.035 if guarded or carrying else 0.24)
		right_arm.rotation.x = wave * (0.035 if guarded or carrying else 0.24)
		left_elbow.rotation.x = 0.20 + maxf(0, -wave) * 0.15
		right_elbow.rotation.x = 0.20 + maxf(0, wave) * 0.15
	else:
		# Quiet weight changes and breathing keep a stationary person alive.
		rig.position.x = sin(idle * 0.26) * (0.006 if trained else 0.016)
		body.scale.y = 1.0 + sin(idle) * 0.0018
		_stand(person.left_leg, person.left_knee, person.left_foot, rig.position.y)
		_stand(person.right_leg, person.right_knee, person.right_foot, rig.position.y)
		if String(person.role) == "protester":
			right_arm.rotation.x = 1.60 + sin(idle) * 0.20
			right_elbow.rotation.x = 0.60 + sin(idle + 1.0) * 0.20
			right_arm.rotation.z = 0.20
			left_arm.rotation.x = 0.13 + maxf(0, sin(idle + 2.0)) * 0.30
			left_elbow.rotation.x = 0.42
			body.rotation.z = sin(idle) * 0.018
		elif not guarded and not carrying:
			var gesture := maxf(0.0, sin(idle * 0.63))
			right_arm.rotation.x = gesture * 0.15
			right_elbow.rotation.x = 0.20 + gesture * 0.88
			right_hand.rotation.x = -gesture * 0.35
			right_arm.rotation.z = 0.07 + gesture * 0.12
			left_elbow.rotation.x = 0.18 + maxf(0, sin(idle * 0.63 + 1.4)) * 0.26
	if guarded:
		left_elbow.rotation.x = 1.12
		right_elbow.rotation.x = 1.05
		if String(person.activity) == "drill" and not moving:
			var drill_phase := _elapsed * 1.4 + (0.0 if trained else seed_phase)
			right_arm.rotation.x = maxf(0, sin(drill_phase)) * (0.21 if trained else 0.12)
			head.rotation.y *= 0.25 if trained else 0.65
		# The spear remains upright as the arm bends, held at the fist.
		left_hand.rotation.x = -left_arm.rotation.x - left_elbow.rotation.x
		right_hand.rotation.x = -right_arm.rotation.x - right_elbow.rotation.x
	elif carrying:
		left_arm.rotation.x = 0.12
		right_arm.rotation.x = 0.12
		left_arm.rotation.z = 0.09
		right_arm.rotation.z = -0.09
		left_elbow.rotation.x = 1.21
		right_elbow.rotation.x = 1.21
		left_hand.rotation.x = -0.70
		right_hand.rotation.x = -0.70

func _step(hip: Node3D, knee: Node3D, foot: Node3D, phase: float, body_y: float, long_tunic: bool) -> void:
	var cycle := fposmod(phase / TAU, 1.0)
	var foot_z: float
	var lift := 0.0
	var pitch := 0.0
	if cycle < 0.60:
		# Contact travels backwards relative to the advancing pelvis: the sandal
		# stays planted in world space during the support portion of each stride.
		var support := cycle / 0.60
		foot_z = lerpf(-0.24, 0.24, support)
		pitch = -maxf(0.0, (support - 0.82) / 0.18) * 0.17
	else:
		var swing := (cycle - 0.60) / 0.40
		foot_z = lerpf(0.24, -0.24, smoothstep(0.0, 1.0, swing))
		lift = sin(swing * PI) * (0.075 if long_tunic else 0.11)
		pitch = sin(swing * PI) * 0.10
	_leg_target(hip, knee, foot, foot_z, 0.075 + lift, body_y, pitch)

func _stand(hip: Node3D, knee: Node3D, foot: Node3D, body_y: float) -> void:
	_leg_target(hip, knee, foot, 0.015, 0.075, body_y, 0.0)

func _leg_target(hip: Node3D, knee: Node3D, foot: Node3D, foot_z: float, ankle_y: float, body_y: float, pitch: float) -> void:
	var dy := ankle_y - hip.position.y - body_y
	var distance := clampf(sqrt(dy * dy + foot_z * foot_z), 0.08, 0.769)
	var bend := -acos(clampf((distance * distance - 0.37 * 0.37 - 0.40 * 0.40) / (2.0 * 0.37 * 0.40), -1.0, 1.0))
	var upper := atan2(-foot_z, -dy) - atan2(0.40 * sin(bend), 0.37 + 0.40 * cos(bend))
	hip.rotation.x = upper
	knee.rotation.x = bend
	foot.rotation.x = -upper - bend + pitch
