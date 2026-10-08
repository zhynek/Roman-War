extends Node3D
## Detached-snapshot presentation only. No animation, camera or draw operation
## issues a command, changes a battle dictionary or consumes simulation RNG.
var world
var actors: Dictionary = {}
var anchors: Dictionary = {}
var elapsed: float = 0.0
var places_built: bool = false
var place_labels: Dictionary = {}
var materials: Dictionary = {}

func material(color: String, unshaded: bool = false, billboard: bool = false) -> StandardMaterial3D:
	var key := color + str(unshaded) + str(billboard)
	if materials.has(key):return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = .95
	if unshaded:m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if billboard:m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	materials[key] = m
	return m

func part(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh;n.position = at;n.material_override = mat
	parent.add_child(n)
	return n

func pivot(parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new();n.position = at;parent.add_child(n);return n

func capsule(parent: Node3D, at: Vector3, mat: Material, length_: float, radius_: float) -> MeshInstance3D:
	var mesh := CapsuleMesh.new();mesh.radius = radius_;mesh.height = length_
	mesh.radial_segments = 8;mesh.rings = 3
	return part(parent, mesh, at, mat)

func sphere(parent: Node3D, at: Vector3, mat: Material, radius_: float, height_: float) -> MeshInstance3D:
	var mesh := SphereMesh.new();mesh.radius = radius_;mesh.height = height_
	mesh.radial_segments = 10;mesh.rings = 5
	return part(parent, mesh, at, mat)

func cylinder(parent: Node3D, at: Vector3, mat: Material, length_: float, top: float, bottom: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new();mesh.height = length_;mesh.top_radius = top;mesh.bottom_radius = bottom;mesh.radial_segments = 8
	return part(parent, mesh, at, mat)

func box(parent: Node3D, at: Vector3, mat: Material, size_: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size = size_;return part(parent, mesh, at, mat)

func ring(parent: Node3D, radius_: float, thickness: float, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new();mesh.inner_radius = radius_;mesh.outer_radius = radius_ + thickness
	mesh.rings = 32;mesh.ring_segments = 6
	return part(parent, mesh, Vector3(0,.08,0), mat)

func limb(parent: Node3D, at: Vector3, mat: Material, length_: float, radius_: float) -> Node3D:
	var joint := pivot(parent, at)
	capsule(joint, Vector3(0,-length_*.5,0), mat, length_, radius_)
	return joint

func build_person(parent: Node3D, watch: bool, equipped: bool, index: int) -> Dictionary:
	# Simple cloth/hide shapes and wooden equipment are original interpretive art.
	# Enemy appearance uses one generic observed role, never private kit or skills.
	var cloth := material(["587e75", "668a7c", "718c83"][index % 3] if watch else ["a87559", "987057", "b38563"][index % 3])
	var skin := material(["b58d70", "c09a7a", "a98264"][index % 3])
	var dark := material("4b4031");var hair := material(["44382d", "5e4934", "514436"][index % 3])
	var wood := material("775739")
	var body := pivot(parent, Vector3.ZERO)
	var trunk := pivot(body, Vector3(0,.83,0))
	capsule(trunk, Vector3(0,.23,0), cloth, .63, .185)
	cylinder(trunk, Vector3(0,-.055,0), cloth, .31, .185, .24)
	cylinder(trunk, Vector3(0,.015,0), dark, .065, .196, .196)
	var head := pivot(trunk, Vector3(0,.63,0))
	sphere(head, Vector3.ZERO, skin, .138, .29)
	sphere(head, Vector3(0,.09,-.01), hair, .14, .13)
	sphere(head, Vector3(0,.0,.125), skin, .029, .065)
	var arms: Array = [];var elbows: Array = [];var legs: Array = [];var knees: Array = []
	for side in [-1,1]:
		var leg := limb(body, Vector3(side*.105,.76,0), cloth, .35, .075)
		var knee := limb(leg, Vector3(0,-.32,0), skin, .35, .055)
		var foot := box(knee, Vector3(0,-.325,.045), dark, Vector3(.115,.075,.22))
		foot.rotation.x = -.04
		legs.append(leg);knees.append(knee)
		var arm := limb(trunk, Vector3(side*.235,.45,0), cloth, .27, .065)
		var elbow := limb(arm, Vector3(0,-.245,0), skin, .27, .047)
		sphere(elbow, Vector3(0,-.255,0), skin, .048, .095)
		arms.append(arm);elbows.append(elbow)
	var weapon: Node3D = null
	if equipped or not watch:
		weapon = pivot(elbows[1], Vector3(0,-.25,.01))
		# Generic raiders carry a plain short wooden branch; actual watch kits
		# select the full staff only for the player's known equipment.
		var length_: float = 1.6 if watch else .85
		cylinder(weapon, Vector3(0,length_*.13,0), wood, length_, .023 if watch else .047, .035)
		cylinder(weapon, Vector3.ZERO, dark, .16, .039, .039)
	return {"node":body,"trunk":trunk,"head":head,"arms":arms,"elbows":elbows,"legs":legs,"knees":knees,"weapon":weapon,"offset":Vector3.ZERO}

func status_bar(parent: Node3D, y: float, color: String) -> MeshInstance3D:
	var mesh := QuadMesh.new();mesh.size = Vector2(1.45,.075)
	return part(parent, mesh, Vector3(0,y,.004), material(color,true,true))

func build_group(f: Dictionary) -> Dictionary:
	var n := Node3D.new();n.name = f.id;add_child(n)
	var figures: Array = []
	var watch: bool = f.side == "watch"
	for i in range(int(f.initial)):
		figures.append(build_person(n, watch, watch and i < int(f.kits), i))
	var marker := ring(n,.72,.075,material("e4d195",true));marker.visible = false
	var contact := ring(n,.87,.04,material("d28d66",true));contact.visible = false
	var facing := pivot(n, Vector3(0,.06,0))
	box(facing,Vector3(0,0,1.10),material("e4d195",true),Vector3(.055,.035,.66))
	for sign_ in [-1,1]:
		var tip := box(facing,Vector3(sign_*.12,0,1.31),material("e4d195",true),Vector3(.045,.04,.34))
		tip.rotation.y = sign_*.78
	var label := Label3D.new();label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0,2.42,0);label.font_size = 25;label.pixel_size = .014;label.outline_size = 7
	n.add_child(label)
	var health := status_bar(n,2.02,"8bb693" if watch else "cf8d6a")
	var morale := status_bar(n,1.91,"95c0c7")
	var fatigue := status_bar(n,1.80,"d2b276")
	var impact := pivot(n,Vector3(0,1.12,.2));impact.visible = false
	for sign_ in [-1,1]:
		var flash := box(impact,Vector3.ZERO,material("f0ce8c",true),Vector3(.035,.55,.04));flash.rotation.z = sign_*.75
	# All goal objects are retained. Route vertices refresh only on a changed
	# snapshot/selection, never by deleting and replacing nodes each frame.
	var goal := Node3D.new();add_child(goal);goal.visible = false
	var destination := ring(goal,.65,.055,material("d9cd92",true))
	var goal_facing := box(goal,Vector3(0,.075,.86),material("d9cd92",true),Vector3(.07,.035,.8))
	var route := MeshInstance3D.new();route.mesh = ImmediateMesh.new();route.material_override = material("d9cd92",true);add_child(route);route.visible = false
	return {"node":n,"figures":figures,"ring":marker,"contact":contact,"facing":facing,"label":label,"goal":goal,"destination":destination,"goal_facing":goal_facing,"route":route,"route_state":{},"bar":health,"morale":morale,"fatigue":fatigue,"impact":impact,"attack_seq":int(f.attack_seq),"hit_seq":int(f.hit_seq),"attack_until":-1.0,"hit_until":-1.0,"width":0}

func ground(at: Array, rise: float = .0) -> Vector3:
	var point := Vector3(float(at[0])/100,0,float(at[1])/100)
	point.y = world.floor_height(point.x,point.z) + rise
	return point

func build_places(b: Dictionary, copy: Dictionary, tuning: Dictionary) -> void:
	places_built = true
	for id in b.nav.places:
		var at := ground(b.nav.places[id],.04)
		var place := pivot(self,at)
		var radius_: float = float(tuning.capture_radius_cm)/100 if id == "stores" else 2.7
		ring(place,radius_,.065,material("bbaa72" if id == "stores" else "819a8b"))
		var marker := Label3D.new();marker.text = copy.get("place_"+id,id)
		marker.position = at + Vector3.UP*3.5;marker.font_size = 22;marker.pixel_size = .019
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED;marker.outline_size = 6
		add_child(marker);place_labels[id] = marker

func update_bar(bar: MeshInstance3D, value: float) -> void:
	bar.scale.x = clampf(value,.001,1.0)

func formation_offsets(actor: Dictionary, count: int, width_: int) -> void:
	if int(actor.width) == width_:return
	actor.width = width_
	var columns: int = mini(count,width_)
	var rows: int = ceili(float(count)/columns)
	for i in range(count):
		var columns_here: int = mini(columns,count-(i/columns)*columns)
		var offset := Vector3((i%columns-(columns_here-1)*.5)*.55,0,(i/columns-(rows-1)*.5)*-.55)
		actor.figures[i].offset = offset
	# Ring encloses the same centered footprint; face remains along +Z.
	actor.ring.scale = Vector3(1.05 if columns > 1 else .80,1.0,1.10 if rows > 1 else .80)

func pose_person(fig: Dictionary, f: Dictionary, actor: Dictionary, index: int, standing: bool, fatigue: float) -> void:
	var body: Node3D = fig.node
	body.position = fig.offset
	if not standing:
		body.rotation = Vector3(0,0,PI*.5)
		body.position.y = .19
		fig.trunk.rotation = Vector3.ZERO
		for joint in fig.arms + fig.elbows + fig.legs + fig.knees:joint.rotation = Vector3.ZERO
		if fig.weapon != null:fig.weapon.rotation.x = .3
		return
	var moving: bool = bool(f.moving)
	var routing: bool = bool(f.routed) or f.order == "withdraw"
	# Pausing freezes elapsed and therefore the pose; deployment orders can still
	# change the formation root and facing without advancing this cosmetic clock.
	var stride: float = sin(elapsed*(10.0 if routing else 8.0)+index*.8) if moving else 0.0
	var hit: float = clampf((float(actor.hit_until)-elapsed)/.28,0.0,1.0)
	var attack: float = clampf(1.0-(float(actor.attack_until)-elapsed)/.62,0.0,1.0)
	var striking: bool = float(actor.attack_until) > elapsed and index < mini(2,actor.figures.size())
	body.rotation = Vector3((.14 if moving else 0.0)+fatigue*.08-hit*.18,0,0)
	body.position.y += absf(stride)*.022
	fig.trunk.rotation.x = fatigue*.12
	fig.head.rotation.x = -fatigue*.08
	for side in range(2):
		var swing: float = stride*(.34 if side == 0 else -.34)
		fig.legs[side].rotation.x = swing
		fig.knees[side].rotation.x = maxf(0,-swing)*1.45
		fig.arms[side].rotation.x = -swing*.62 - (.36 if f.engaged else .09)
		fig.arms[side].rotation.z = -.08 if side == 0 else .08
		fig.elbows[side].rotation.x = -.23 if f.engaged else -.10
	var weapon_pitch: float = .14
	if f.engaged:
		fig.arms[0].rotation.x = -.65-hit*.38
		fig.elbows[0].rotation.x = -.78
		fig.arms[1].rotation.x = -.34-hit*.20
		fig.elbows[1].rotation.x = -.50
		weapon_pitch = .37
	if striking:
		# One resolved attack sequence produces windup, extension and recovery.
		# This stroke never decides whether a hit lands; attack_seq already did.
		var extension: float = sin(clampf((attack-.14)/.72,0,1)*PI)
		fig.trunk.rotation.y = -.10+extension*.20
		fig.arms[1].rotation.x = -.30-extension*.90
		fig.elbows[1].rotation.x = -.75+extension*.66
		fig.arms[0].rotation.x = -.72-extension*.30
		fig.elbows[0].rotation.x = -.70+extension*.22
		weapon_pitch = .30+extension*1.02
	else:fig.trunk.rotation.y = 0
	if routing:
		fig.arms[0].rotation.x -= .12;fig.arms[1].rotation.x -= .10;weapon_pitch = -.32
	if fig.weapon != null:
		fig.weapon.rotation.x = weapon_pitch-float(fig.arms[1].rotation.x)-float(fig.elbows[1].rotation.x)-float(body.rotation.x)-float(fig.trunk.rotation.x)

func facing_intent(f: Dictionary) -> Array:
	var tactical: Dictionary = f.get("tactical",{})
	return tactical.get("face",f.facing) if tactical.get("face_locked",false) else f.facing

func update_route(actor: Dictionary, f: Dictionary, selected: bool, blocked: String) -> void:
	var visible_: bool = selected and not f.exited and f.hp > 0 and f.order not in ["hold","face"]
	actor.goal.visible = visible_;actor.route.visible = visible_
	if not visible_:return
	var facing: Array = facing_intent(f)
	var route_state: Dictionary = {"at":f.position,"path":f.path,"goal":f.goal,"facing":facing,"blocked":blocked}
	if actor.route_state == route_state:return
	actor.route_state = route_state.duplicate(true)
	var marker: Node3D = actor.goal;marker.position = ground(f.goal)
	marker.rotation.y = atan2(float(facing[0]),float(facing[1]))
	var mat := material("cb8b65" if not blocked.is_empty() else "d9cd92",true)
	actor.destination.material_override = mat;actor.goal_facing.material_override = mat;actor.route.material_override = mat
	var mesh: ImmediateMesh = actor.route.mesh;mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var previous := ground(f.position,.13)
	for waypoint in f.path:
		var next := ground(waypoint,.13)
		mesh.surface_add_vertex(previous);mesh.surface_add_vertex(next);previous = next
	var destination := ground(f.goal,.13)
	if previous.distance_squared_to(destination) > .0001:
		mesh.surface_add_vertex(previous);mesh.surface_add_vertex(destination)
	else:
		# ImmediateMesh requires vertices even when the group has arrived.
		mesh.surface_add_vertex(destination+Vector3(-.1,0,0));mesh.surface_add_vertex(destination+Vector3(.1,0,0))
	mesh.surface_end()

func update(b: Dictionary, selected: Array, copy: Dictionary, t: Dictionary, delta: float) -> void:
	if not b.paused:elapsed += minf(delta,.1)*float(b.get("speed",1))
	if not places_built:build_places(b,copy,t)
	anchors.clear()
	for f in b.groups:
		# No model is built from an enemy dictionary before it is observed.
		if f.side != "watch" and not f.revealed:
			if actors.has(f.id):
				actors[f.id].node.visible = false
				actors[f.id].goal.visible = false;actors[f.id].route.visible = false
			continue
		if not actors.has(f.id):actors[f.id] = build_group(f)
		var actor: Dictionary = actors[f.id];var n: Node3D = actor.node
		if not n.visible:
			# A re-observed group starts with its current state, without replaying
			# attack/impact events that happened outside the player's observation.
			actor.attack_seq = int(f.attack_seq);actor.hit_seq = int(f.hit_seq)
			actor.attack_until = -1.0;actor.hit_until = -1.0
		n.visible = not f.exited
		if not n.visible:
			actor.goal.visible = false;actor.route.visible = false;continue
		var at := ground(f.position)
		# Picking and drawing share this exact centered anchor, including while
		# paused. Person poses never move the authoritative formation root.
		n.position = at;anchors[f.id] = at + Vector3.UP
		n.rotation.y = atan2(float(f.facing[0]),float(f.facing[1]))
		var tactical: Dictionary = f.get("tactical",{})
		var width_: int = clampi(int(tactical.get("effective_width",tactical.get("width",2))),1,2)
		var fatigue: float = clampf(float(tactical.get("fatigue",0))/100.0,0,1)
		var blocked: String = str(tactical.get("blocked",""))
		formation_offsets(actor,int(f.initial),width_)
		if actor.attack_seq != int(f.attack_seq):actor.attack_seq = int(f.attack_seq);actor.attack_until = elapsed+.62
		if actor.hit_seq != int(f.hit_seq):actor.hit_seq = int(f.hit_seq);actor.hit_until = elapsed+.28
		update_bar(actor.bar,float(f.hp)/(int(f.initial)*int(t.hp_per_person)))
		update_bar(actor.morale,float(f.morale)/100.0)
		update_bar(actor.fatigue,fatigue)
		actor.fatigue.visible = not tactical.is_empty() and f.id in selected
		actor.morale.visible = f.id in selected or f.routed
		actor.impact.visible = elapsed < float(actor.hit_until) and f.hp > 0
		actor.impact.scale = Vector3.ONE*(1.0+(.28-maxf(0,float(actor.hit_until)-elapsed)))
		actor.ring.visible = f.id in selected
		actor.facing.visible = f.id in selected and f.hp > 0
		var facing: Array = facing_intent(f)
		# The bodies retain resolved facing; the selected arrow shows the accepted
		# intention immediately, including while paused before physical turning.
		actor.facing.rotation.y = atan2(float(facing[0]),float(facing[1]))-n.rotation.y
		actor.contact.visible = bool(f.engaged) and f.hp > 0
		var count: int = ceili(float(f.hp)/int(t.hp_per_person))
		var title: String = copy.group.format({"n":f.id.trim_prefix("watch_")}) if f.side == "watch" else str(copy.get("enemy_short",copy.enemy))
		actor.label.text = title + "  " + str(count) + "/" + str(f.initial)
		if f.routed:actor.label.text += "\n"+copy.routed
		elif f.hp == 0:actor.label.text = copy.injured
		elif f.id in selected:
			actor.label.text += "\n"+str(copy.get("order_"+f.order,f.order))
			var status: String = str(copy.get("tactical_"+blocked,"")) if not blocked.is_empty() else str(copy.get("engaged","")) if f.engaged else ""
			if not status.is_empty():actor.label.text += " · "+status
		actor.label.modulate = Color("ecc996" if f.routed else "f0e4be" if f.id in selected else "e3ded0")
		for i in range(actor.figures.size()):pose_person(actor.figures[i],f,actor,i,i<count,fatigue)
		update_route(actor,f,f.id in selected,blocked)
	layout_labels()
	# Place labels lift above nearby troops, avoiding the old overlapping stack
	# of objective, health and order text during the fight at the stores.
	for id in place_labels:
		var height_: float = 3.5;var at := ground(b.nav.places[id])
		for actor in actors.values():
			if actor.node.visible and at.distance_squared_to(actor.node.position)<42.0:
				height_ = maxf(height_,float(actor.label.position.y)+1.15)
		place_labels[id].position.y = at.y+height_

func label_rect(label: Label3D, camera: Camera3D) -> Rect2:
	var at := camera.unproject_position(label.global_position)
	var pixels_per_meter: float = at.distance_to(camera.unproject_position(label.global_position+camera.global_basis.x))
	var lines: PackedStringArray = label.text.split("\n")
	var columns: int = 1
	for line in lines:columns = maxi(columns,line.length())
	var extent := Vector2(columns*.62,lines.size()*1.3)*float(label.font_size)*label.pixel_size*pixels_per_meter
	return Rect2(at-extent*.5,extent).grow(4)

func layout_labels() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:return
	var occupied: Array[Rect2] = []
	for actor in actors.values():
		if not actor.node.visible:continue
		var label: Label3D = actor.label;label.position.y = 2.42
		if camera.is_position_behind(label.global_position):continue
		var rect := label_rect(label,camera)
		for attempt in range(12):
			var overlaps: bool = false
			for previous in occupied:
				if rect.intersects(previous):overlaps = true;break
			if not overlaps:break
			label.position.y += .5;rect = label_rect(label,camera)
		occupied.append(rect)
