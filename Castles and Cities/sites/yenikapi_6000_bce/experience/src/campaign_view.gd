extends Node3D
## Presentation adapter: never resolves a season, grants resources or changes people.
const Fabric = preload("res://src/fabric.gd")
var actors: Array = []
var elapsed: float = 0.0
var life
var land_view
var incident_view
var living_view
var markers: Node3D
var _marker_key: String=""
const HouseholdView = preload("res://src/household_view.gd")

static func snapshot(base: Dictionary, state: Dictionary, rules) -> Dictionary:
	var changes: Array = []
	for item in state.completed:
		changes.append_array(rules.projects[item.id].changes.duplicate(true))
	var resolved: Dictionary = Fabric.resolve(base,{"id":rules.content.scenario_id,"kind":"hypothetical","base_snapshot_id":base.snapshot_id,"changes":changes})
	assert(not resolved.has("error"))
	var result: Dictionary = base.duplicate(true)
	if rules.assets.active(state):result.presentation_food=state.food
	var staging: Array=[]
	if rules.land.active(state):
		for item in state.queue:
			if rules.land.proposals.has(item.id) and not rules.land.proposals[item.id].retain:
				staging.append_array(rules.land.sites[rules.land.proposals[item.id].site].objects)
	result.objects = []
	for record in resolved.objects:
		if record.get("active",true) and record.id not in staging: result.objects.append(record)
	return result

func refresh(state: Dictionary, rules, world) -> void:
	if rules.living.active(state):
		if not is_instance_valid(living_view):living_view=preload("res://src/living_view.gd").new();add_child(living_view)
		living_view.refresh(state,rules,world)
	elif is_instance_valid(living_view):living_view.free();living_view=null
	if rules.incidents.active(state):
		if not is_instance_valid(incident_view):incident_view=preload("res://src/incident_view.gd").new();add_child(incident_view)
		incident_view.refresh(state,rules,world)
	elif is_instance_valid(incident_view):incident_view.free();incident_view=null
	if rules.households.active(state):
		actors.clear()
		if not is_instance_valid(life):
			life=HouseholdView.new();add_child(life)
		life.refresh(state,rules,world)
		_project_markers(state,rules,world)
		return
	for child in get_children(): child.free()
	life=null
	actors.clear()
	elapsed = 0.0
	var tasks: Array = state.assignments if not state.assignments.is_empty() else rules.assignments(state,rules.normalize_plan(state,state.plan))
	var colors := {"travel":Color("c49b69"),"food":Color("b4a17a"),"timber":Color("746651"),"care":Color("a28470"),"watch":Color("69725b"),"building":Color("968161")}
	for i in range(tasks.size()):
		var task: Dictionary = tasks[i]
		var actor := Node3D.new()
		actor.name = task.id
		add_child(actor)
		var cloth := StandardMaterial3D.new();cloth.albedo_color=colors[task.job];cloth.roughness=1
		var skin := StandardMaterial3D.new();skin.albedo_color=Color("ad896d");skin.roughness=1
		var body := MeshInstance3D.new();var capsule := CapsuleMesh.new();capsule.radius=.17;capsule.height=.7;body.mesh=capsule;body.material_override=cloth;body.position.y=1.03;actor.add_child(body)
		var head := MeshInstance3D.new();var sphere := SphereMesh.new();sphere.radius=.135;sphere.height=.27;head.mesh=sphere;head.material_override=skin;head.position.y=1.59;actor.add_child(head)
		if task.job=="travel":
			var bundle:=MeshInstance3D.new();var sack:=BoxMesh.new();sack.size=Vector3(.4,.5,.25);bundle.mesh=sack;bundle.material_override=cloth;bundle.position=Vector3(0,1.05,-.23);actor.add_child(bundle)
		var limbs: Array = []
		for side in [-1.0,1.0]:
			var leg := _limb(cloth,.085,.67);leg.position=Vector3(side*.1,.68,0);actor.add_child(leg);limbs.append(leg)
			var arm := _limb(skin,.06,.53);arm.position=Vector3(side*.24,1.25,0);actor.add_child(arm);limbs.append(arm)
		var a := Vector3(task.from[0],0,task.from[1])
		var b := Vector3(task.to[0],0,task.to[1])
		# Walk the same controller when animating. Decorative actors do not block the player.
		a = _safe(a+Vector3((i%3-1)*.65,0,(i/6)*.55),world)
		b = _safe(b+Vector3((i%3-1)*.8,0,(i%4)*.6),world)
		actor.position = b if i%3==0 else a
		actors.append({"node":actor,"limbs":limbs,"a":a,"b":b,"job":task.job,"world":world,"phase":float(i)*.7,"working":i%3==0,"id":task.id})
	_project_markers(state,rules,world)

func _project_markers(state: Dictionary,rules,world) -> void:
	var key: String=JSON.stringify([state.queue,rules.land.active(state),state.completed])
	if key==_marker_key and is_instance_valid(markers):return
	_marker_key=key
	if is_instance_valid(markers):markers.free()
	markers=Node3D.new();add_child(markers)
	if rules.land.active(state):
		land_view=preload("res://src/land_view.gd").new();markers.add_child(land_view);land_view.build(state,rules,world)
	for item in state.queue:
		var project: Dictionary = rules.projects[item.id]
		var at: Vector3=Vector3(project.at[0],world.floor_height(project.at[0],project.at[1]),project.at[1])
		if rules.land.proposals.has(item.id) and rules.land.proposals[item.id].site=="workroom":
			for building in world.buildings:
				if building.id=="yk_house_06":at=world.building_position(building,Vector3(0,0,float(building.size[1])*.5+1.8))
		var marker := Node3D.new();marker.position=at;markers.add_child(marker)
		var mat := StandardMaterial3D.new();mat.albedo_color=Color("b99f69");mat.roughness=1
		if rules.assets.active(state):
			var fraction: float=float(item.progress)/float(project.work)
			for i in range(2+int(fraction*6)):
				var timber:=MeshInstance3D.new();var log_mesh:=BoxMesh.new();log_mesh.size=Vector3(1.5,.12,.14);timber.mesh=log_mesh;timber.material_override=mat;timber.position=Vector3(1.8,.13+float(i/3)*.13,float(i%3)*.2);marker.add_child(timber)
			for i in range(int(fraction*4)):
				var frame:=MeshInstance3D.new();var frame_mesh:=BoxMesh.new();frame_mesh.size=Vector3(.1,.5+fraction,.1);frame.mesh=frame_mesh;frame.material_override=mat;frame.position=Vector3(-1.1,float(.5+fraction)*.5,-1.0+float(i)*.65);marker.add_child(frame)
		for side in [-1.0,1.0]:
			var post := MeshInstance3D.new();var mesh := CylinderMesh.new();mesh.top_radius=.05;mesh.bottom_radius=.06;mesh.height=1.1;post.mesh=mesh;post.material_override=mat;post.position=Vector3(side*.8,.55,0);marker.add_child(post)
		var label := Label3D.new();label.text=project.title+"\n%d / %d"%[item.progress,project.work];label.font_size=24;label.pixel_size=.015;label.position.y=1.7;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=false;label.visibility_range_begin=8.0;marker.add_child(label)

func _safe(point: Vector3,world) -> Vector3:
	if world.blocked(point):
		for radius in range(1,7):
			for i in range(16):
				var candidate: Vector3 = point+Vector3(cos(i*TAU/16)*radius,0,sin(i*TAU/16)*radius)
				if not world.blocked(candidate): candidate.y=world.floor_height(candidate.x,candidate.z);return candidate
	point.y=world.floor_height(point.x,point.z)
	return point

func _limb(material: Material,radius: float,length: float) -> Node3D:
	var pivot := Node3D.new()
	var mesh := MeshInstance3D.new();var capsule := CapsuleMesh.new();capsule.radius=radius;capsule.height=length;mesh.mesh=capsule;mesh.material_override=material;mesh.position.y=-length*.5;pivot.add_child(mesh)
	return pivot

func _process(delta: float) -> void:
	elapsed += minf(delta,.1)
	for actor in actors:
		var node: Node3D = actor.node
		var cycle: float = fmod(elapsed+float(actor.phase),28.0)
		var moving: bool = not actor.working and (cycle<10 or (cycle>15 and cycle<25))
		if moving:
			var target: Vector3 = actor.b if cycle<10 else actor.a
			var direction: Vector3 = target-node.position;direction.y=0
			if direction.length()>.3:
				var before: Vector3 = node.position
				var at: Vector3 = actor.world.walk(before+Vector3.UP*1.68,direction.normalized()*1.3*minf(delta,.1))
				node.position=at-Vector3.UP*1.68
				if node.position.distance_to(before)<.005:
					# Collision-aware local detour; remains presentation only.
					var turn: Vector3=Vector3(-direction.z,0,direction.x).normalized()
					at=actor.world.walk(before+Vector3.UP*1.68,turn*1.3*minf(delta,.1));node.position=at-Vector3.UP*1.68
				if direction.length_squared()>.01: node.rotation.y=atan2(direction.x,direction.z)
			else: moving=false
		var phase: float = sin(elapsed*5+float(actor.phase))
		for i in range(actor.limbs.size()):
			actor.limbs[i].rotation.x=phase*(.42 if moving else (.14 if i%2==1 else .02))*(1 if i<2 else -1)
