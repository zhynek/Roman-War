class_name RealismWorld
extends Node3D
## Retained 3D presentation of an authored development study. Public art data in,
## meshes out; this class deliberately has no Game or campaign-state reference.
var terrain: RealismTerrain
var spec: Dictionary
var camera: Camera3D
var target := Vector3.ZERO
var distance := 113.0
var yaw := 0.26
var pitch := 0.72
var friendly: MultiMeshInstance3D
var opposing: MultiMeshInstance3D
var commander: Node3D
var route_line: MeshInstance3D
var army_material: ShaderMaterial
var enemy_material: ShaderMaterial
var water_material: ShaderMaterial
var foliage_material: ShaderMaterial
var progress := 0.0
var marker_positions := {}
var selected_formation := "friendly"

func build(settings: Dictionary) -> void:
	spec = settings
	terrain = RealismTerrain.new(spec)
	_lighting()
	camera = Camera3D.new()
	camera.fov = 48
	camera.near = 0.15
	camera.far = 420
	add_child(camera)
	var ground_material := ShaderMaterial.new()
	ground_material.shader = preload("res://src/ui/realism/ground.gdshader")
	_mesh(terrain.build_mesh(),ground_material)
	water_material = ShaderMaterial.new()
	water_material.shader = preload("res://src/ui/realism/water.gdshader")
	var water := PlaneMesh.new()
	water.size = Vector2(spec.extent,spec.extent)
	var water_node := _mesh(water,water_material)
	water_node.position.y = float(spec.lake.level)
	_road()
	_vegetation()
	_stones()
	_camp()
	_armies()
	marker_positions = {
		"lake":terrain.ground(Vector3(-22,0,-1),1.7),
		"marsh":terrain.ground(Vector3(-26,0,17),1.2),
		"forest":terrain.ground(Vector3(25,0,-14),7.3),
		"mountain":terrain.ground(Vector3(6,0,-57),3.0)}
	set_camera("overview")
	set_progress(0.0,false)

func _lighting() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#708b98")
	sky_material.sky_horizon_color = Color("#c5c7b8")
	sky_material.ground_bottom_color = Color("#687263")
	sky_material.ground_horizon_color = Color("#c5c7b8")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b2c5cb")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.10
	environment.fog_enabled = true
	environment.fog_light_color = Color("#b7c0b1")
	environment.fog_density = 0.0007
	environment.fog_sky_affect = 0.25
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36,-39,0)
	sun.light_color = Color("#fff0cc")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.5
	add_child(sun)

func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	add_child(node)
	return node

func _material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	mat.metallic = metal
	return mat

func _batch(mesh: Mesh, material: Material, poses: Array[Transform3D]) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.instance_count = poses.size()
	mm.mesh = mesh
	for i in range(poses.size()):
		mm.set_instance_transform(i,poses[i])
		mm.set_instance_color(i,Color.WHITE)
		mm.set_instance_custom_data(i,Color(fmod(i*0.618,1.0),0,0,1))
	node.multimesh = mm
	node.material_override = material
	add_child(node)
	return node

func _road() -> void:
	var b := RealismModels.new()
	var line := RealismModels.new()
	var count := int(terrain.route.get_baked_length()/0.7)
	for i in range(count):
		var d := float(i)/count*terrain.route.get_baked_length()
		var next := float(i+1)/count*terrain.route.get_baked_length()
		var a := terrain.sample(terrain.route,d,-1.65).origin+Vector3.UP*0.035
		var c := terrain.sample(terrain.route,d,1.65).origin+Vector3.UP*0.035
		var e := terrain.sample(terrain.route,next,-1.65).origin+Vector3.UP*0.035
		var f := terrain.sample(terrain.route,next,1.65).origin+Vector3.UP*0.035
		var tint := RealismModels.pigment("#8b7c59").lerp(RealismModels.pigment("#a39570"),RealismModels.scatter(str(i),19)*0.5)
		b.triangle(a,c,e,tint)
		b.triangle(c,f,e,tint)
		# Two worn ruts are deliberately part of the road, below the troops.
		for offset in [-0.75,0.75]:
			var p := terrain.sample(terrain.route,d,offset).origin+Vector3.UP*0.06
			var q := terrain.sample(terrain.route,next,offset).origin+Vector3.UP*0.06
			b.triangle(p+Vector3.LEFT*0.065,p+Vector3.RIGHT*0.065,q,RealismModels.pigment("#60543d"))
		if i%5<3:
			var p := terrain.sample(terrain.route,d).origin+Vector3.UP*0.14
			var q := terrain.sample(terrain.route,next).origin+Vector3.UP*0.14
			line.rod(p,q,0.045,Color("#e8cc87"))
	var mat := _material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(b.finish(),mat)
	var route_mat := _material(Color("#dec48a"))
	route_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	route_line = _mesh(line.finish(),route_mat)

func _vegetation() -> void:
	foliage_material = ShaderMaterial.new()
	foliage_material.shader = preload("res://src/ui/realism/foliage.gdshader")
	var groups: Array = [[],[],[],[]]
	var forest: Dictionary = spec.woods
	for i in range(int(forest.trees)*3):
		var key := "tree/%s/%s" % [spec.seed,i]
		var x := float(forest.center[0])+(RealismModels.scatter(key,0)*2-1)*float(forest.radii[0])
		var z := float(forest.center[1])+(RealismModels.scatter(key,1)*2-1)*float(forest.radii[1])
		if terrain.ellipse(Vector2(x,z),forest)>1.0 or terrain.road_distance(Vector2(x,z))<3.1 or terrain.height(x,z)<1.3:
			continue
		if groups[0].size()+groups[1].size()+groups[2].size()+groups[3].size()>=int(forest.trees):
			break
		var scale_by := 0.68+RealismModels.scatter(key,2)*0.65
		groups[i%4].append(Transform3D(Basis(Vector3.UP,RealismModels.scatter(key,3)*TAU).scaled(Vector3.ONE*scale_by),Vector3(x,terrain.height(x,z)-0.08,z)))
	# Open woodland on the far slopes, leaving lake and road unobstructed.
	for i in range(145):
		var key := "outer/%s" % i
		var p := Vector2((RealismModels.scatter(key,0)*2-1)*69,(RealismModels.scatter(key,1)*2-1)*68)
		if terrain.road_distance(p)<5 or terrain.height(p.x,p.y)<1.8 or terrain.height(p.x,p.y)>12 or p.y>24:
			continue
		groups[i%4].append(Transform3D(Basis(Vector3.UP,RealismModels.scatter(key,2)*TAU).scaled(Vector3.ONE*(0.55+RealismModels.scatter(key,3)*0.55)),Vector3(p.x,terrain.height(p.x,p.y),p.y)))
	for j in range(4):
		var poses: Array[Transform3D] = []
		poses.assign(groups[j])
		_batch(RealismModels.tree(j),foliage_material,poses)
	var grass: Array[Transform3D] = []
	var reeds: Array[Transform3D] = []
	for i in range(17000):
		var key := "grass/%s" % i
		var x := (RealismModels.scatter(key,0)*2-1)*71
		var z := (RealismModels.scatter(key,1)*2-1)*71
		var h := terrain.height(x,z)
		if h<0.82 or h>15 or terrain.road_distance(Vector2(x,z))<1.9:
			continue
		var pose := Transform3D(Basis(Vector3.UP,RealismModels.scatter(key,2)*TAU).scaled(Vector3.ONE*(0.8+RealismModels.scatter(key,3)*0.65)),Vector3(x,h,z))
		if h<1.30:
			reeds.append(pose)
		else:
			grass.append(pose)
	var grasses := _batch(RealismModels.grass(),foliage_material,grass)
	grasses.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_batch(RealismModels.grass(true),foliage_material,reeds)

func _stones() -> void:
	var rock := SphereMesh.new()
	rock.radial_segments = 9
	rock.rings = 5
	var poses: Array[Transform3D] = []
	for i in range(580):
		var key := "rock/%s" % i
		var x := (RealismModels.scatter(key,0)*2-1)*73
		var z := (RealismModels.scatter(key,1)*2-1)*73
		var h := terrain.height(x,z)
		if h<1.0 or terrain.road_distance(Vector2(x,z))<2.2:
			continue
		var size := (0.25+RealismModels.scatter(key,2)*1.5)*(1.9 if h>9 else 0.55)
		poses.append(Transform3D(Basis.from_euler(Vector3(i*0.13,i*1.73,0.3)).scaled(Vector3(size*1.8,size*0.7,size)),Vector3(x,h,z)))
	_batch(rock,_material(Color("#41443c")),poses)

func _camp() -> void:
	var b := RealismModels.new()
	var center := terrain.ground(Vector3(-14,0,-38))
	var stone := Color("#484a40")
	for i in range(4):
		var at := center+Vector3((i%2)*4,0,(i/2)*4)
		b.box(at+Vector3(0,1.6,0),Vector3(2.7,3.2,2.7),stone)
		for j in range(4):
			b.box(at+Vector3(-1.1+j*0.73,3.5,-1.1),Vector3(0.38,0.6,0.38),stone)
	var mat := _material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	_mesh(b.finish(),mat)

func _armies() -> void:
	army_material = ShaderMaterial.new()
	army_material.shader = preload("res://src/ui/realism/soldier.gdshader")
	enemy_material = army_material.duplicate()
	var poses: Array[Transform3D] = []
	poses.resize(64)
	poses.fill(Transform3D.IDENTITY)
	var art := UnitArt.new()
	art.load_from("res://data/unit_art.json")
	var unit_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json"))
	var culture := "roman"
	for unit in unit_document.units:
		if unit.id==spec.friendly_template:
			culture = String(unit.culture)
	var friendly_tint := Color.html(art.kits[culture].tunic)
	var opposing_tint := Color.html(art.kits[String(spec.opposing_culture)].tunic)
	friendly = _batch(RealismModels.soldier(friendly_tint),army_material,poses)
	poses.resize(36)
	opposing = _batch(RealismModels.soldier(opposing_tint,true),enemy_material,poses)
	commander = Node3D.new()
	add_child(commander)
	var horse := MeshInstance3D.new()
	horse.mesh = RealismModels.horse()
	horse.material_override = army_material
	commander.add_child(horse)
	var rider := MeshInstance3D.new()
	rider.mesh = RealismModels.soldier(Color("#86322b"),false,true)
	rider.material_override = army_material
	rider.position = Vector3(0,0.66,0.1)
	commander.add_child(rider)
	# A tall cloth standard stays visible from the campaign camera.
	var banner := RealismModels.new()
	banner.rod(Vector3(0.46,1.15,0.0),Vector3(0.46,3.6,0.0),0.025,RealismModels.pigment("#a8894c",0.7))
	banner.box(Vector3(0.77,3.28,0),Vector3(0.57,0.57,0.028),RealismModels.pigment("#7d2c24"))
	banner.box(Vector3(0.77,3.30,-0.026),Vector3(0.3,0.045,0.013),RealismModels.pigment("#bf9b57",0.7))
	var banner_node := MeshInstance3D.new()
	banner_node.mesh = banner.finish()
	banner_node.material_override = army_material
	commander.add_child(banner_node)

func set_progress(value: float, _playing: bool) -> void:
	progress = clampf(value,0.0,1.0)
	var seconds := progress*float(spec.duration)
	var march := smoothstep(0.04,0.76,progress)
	var contact_distance := terrain.route.get_closest_offset(Vector3(10,0,8)) - 1.5
	var front := lerpf(32.0,contact_distance,march)
	for i in range(friendly.multimesh.instance_count):
		var pose := terrain.sample(terrain.route,front-float(i/4)*1.12,(i%4-1.5)*0.61)
		friendly.multimesh.set_instance_transform(i,pose)
	commander.transform = terrain.sample(terrain.route,front+2.2)
	var emerging := smoothstep(0.43,0.90,progress)
	var enemy_front := lerpf(8.0,terrain.flank.get_baked_length()-0.9,emerging)
	for i in range(opposing.multimesh.instance_count):
		var pose := terrain.sample(terrain.flank,maxf(0.4,enemy_front-float(i/4)*0.94),(i%4-1.5)*0.64)
		opposing.multimesh.set_instance_transform(i,pose)
	# This is a staged public formation. Nothing is read from an enemy roster.
	opposing.visible = progress>=0.43
	for mat in [army_material,enemy_material,water_material,foliage_material]:
		mat.set_shader_parameter("clock_time",seconds)
	army_material.set_shader_parameter("walking",1.0 if progress>0.04 and progress<0.76 else 0.0)
	enemy_material.set_shader_parameter("walking",1.0 if progress>0.43 and progress<0.90 else 0.0)

func set_camera(id: String) -> void:
	for preset in spec.cameras:
		if preset.id != id:
			continue
		target = Vector3(preset.target[0],preset.target[1],preset.target[2])
		distance = float(preset.distance)
		yaw = float(preset.yaw)
		pitch = float(preset.pitch)
		if id=="column" and friendly!=null:
			var pose := friendly.multimesh.get_instance_transform(20)
			target = pose.origin+Vector3.UP*0.65
			yaw = pose.basis.get_euler().y+PI-0.65
			distance = 19
		update_camera()
		return

func update_camera() -> void:
	pitch = clampf(pitch,0.17,1.35)
	distance = clampf(distance,8,175)
	target.x = clampf(target.x,-64,64)
	target.z = clampf(target.z,-64,64)
	camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.position.y = maxf(camera.position.y,terrain.height(camera.position.x,camera.position.z)+2.4)
	camera.look_at(target+Vector3.UP)

func pick_formation(screen_point: Vector2) -> String:
	# Picking uses precisely the transforms submitted to MultiMesh, including animation.
	var best := 22.0
	var result := ""
	for entry in [["friendly",friendly],["opposing",opposing]]:
		var node: MultiMeshInstance3D = entry[1]
		if not node.visible:
			continue
		for i in range(node.multimesh.instance_count):
			var point := node.multimesh.get_instance_transform(i).origin+Vector3.UP
			if camera.is_position_behind(point):
				continue
			var d := camera.unproject_position(point).distance_to(screen_point)
			if d<best:
				best = d
				result = entry[0]
	return result
