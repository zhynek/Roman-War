class_name RomaCityWorld
extends Node3D
## Original procedural streets, architecture and furnishings. All gameplay is
## elsewhere: this is a retained presentation of the authored tactical layout.
var layout: Dictionary = {}
var sites: Array = []
var solid_body: StaticBody3D
var rubble: MeshInstance3D
var repairs: MeshInstance3D
var restored_streets: MeshInstance3D
var water: MeshInstance3D
var tavern_closed: MeshInstance3D
var _stone := RealismModels.new()
var _detail := RealismModels.new()
var _timber := Color("#624633")
var _tile := Color("#a45c3e")
var _limestone := Color("#b4a58a")
var _plaster := [Color("#c9bb9f"), Color("#b8b095"), Color("#c6a881"), Color("#c0ab94")]
var _material: ShaderMaterial
var _building_id := ""
var _site_id := ""
var selection: MeshInstance3D
var project_scaffolds: Dictionary = {}
var project_improvements: Dictionary = {}
var gate_reinforcement: MeshInstance3D
var fire_stores: MeshInstance3D
var battle_gate: MeshInstance3D
var gate_collisions: Array[CollisionShape3D] = []
var preview_site_id := ""
var preview_center := Vector3.ZERO
var preview_radius := 18.0

func _prepare(authored_layout: Dictionary) -> void:
	layout = authored_layout
	sites = layout.get("sites", [])
	solid_body = StaticBody3D.new()
	solid_body.name = "AuthoredCityCollision"
	add_child(solid_body)
	_material = ShaderMaterial.new()
	_material.shader = preload("res://src/ui/city/city_surface.gdshader")
	# Vertex alpha is a surface-family tag, never transparency.
	_timber.a = 0.25
	_tile.a = 0.5
	for index in range(_plaster.size()):
		_plaster[index].a = 0.75
	_lighting()

func build(authored_layout: Dictionary) -> void:
	_prepare(authored_layout)
	_ground()
	var ground_mesh := _mesh(_stone,"GroundAndPaving")
	ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stone = RealismModels.new()
	for building in layout.buildings:
		_building(building)
	_city_walls()
	_fortress_detail()
	_site_id = "barracks"
	_barracks_yard()
	_site_id = "forum"
	_forum_colonnades()
	_site_id = "market"
	for point in layout.market_stalls:
		_market_stall(_v(point), str(point))
	_site_id = ""
	for point in layout.trees:
		_cypress(_v(point), str(point))
	_site_id = "fountain"
	_fountain(_v(layout.water_position))
	_site_id = ""
	_street_life()
	_mesh(_stone, "MasonryAndRoads")
	_mesh(_detail, "ArchitecturalDetails")
	_status_geometry()
	_project_geometry()
	_waterworks_geometry()
	_military_project_geometry()
	apply_status({})

func apply_status(status: Dictionary) -> void:
	if not is_instance_valid(rubble):
		return
	var cleanliness := float(status.get("cleanliness", 45.0))
	var projects: Dictionary = status.get("projects", {})
	var street: Dictionary = projects.get("repair_streets", {})
	var well: Dictionary = projects.get("clean_water", {})
	rubble.visible = cleanliness < 65.0
	repairs.visible = int(street.get("remaining", 0)) > 0 and not bool(street.get("completed", false))
	restored_streets.visible = bool(street.get("completed", false)) or float(status.get("street_condition", 40.0)) >= 80.0
	if is_instance_valid(water):
		var water_material := water.material_override as StandardMaterial3D
		water_material.albedo_color = Color("#629b9a") if bool(well.get("completed", false)) else Color("#637d65")
	var policies: Dictionary = status.get("policies", {})
	tavern_closed.visible = str(policies.get("taverns", "open")) == "closed"
	if gate_reinforcement != null:gate_reinforcement.visible=projects.get("reinforce_gate",{}).get("completed",false)
	if fire_stores != null:fire_stores.visible=projects.get("prepare_fire_arrows",{}).get("completed",false)
	for action_id in project_scaffolds:
		var project: Dictionary = projects.get(action_id, {})
		project_scaffolds[action_id].visible = int(project.get("remaining", 0)) > 0 and not bool(project.get("completed", false))
		project_improvements[action_id].visible = bool(project.get("completed", false))

func _v(point: Array, y: float = 0.0) -> Vector3:
	return Vector3(float(point[0]), y, float(point[1]))

func _lighting() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#718d9f")
	sky_mat.sky_horizon_color = Color("#d8cfb8")
	sky_mat.ground_bottom_color = Color("#88816d")
	sky_mat.ground_horizon_color = Color("#d8cfb8")
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c2c5bd")
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.ssao_enabled = true
		environment.ssao_radius = 1.3
		environment.ssao_intensity = 1.5
		environment.ssil_enabled = true
		environment.ssil_radius = 4.0
		environment.glow_enabled = true
	environment.fog_enabled = true
	environment.fog_light_color = Color("#bfc1ae")
	environment.fog_density = 0.0010
	environment.fog_sky_affect = 0.15
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -28, 0)
	sun.light_color = Color("#fff0d1")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 150
	sun.shadow_bias = 0.15
	sun.shadow_normal_bias = 1.3
	add_child(sun)

func _mesh(builder: RealismModels, node_name: String) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	mesh_node.mesh = builder.finish()
	mesh_node.material_override = _material
	add_child(mesh_node)
	return mesh_node

func _collision(at: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = at
	shape_node.rotation = rotation
	shape_node.set_meta("building_id", _building_id)
	shape_node.set_meta("site_id", _site_id)
	solid_body.add_child(shape_node)

func _box(builder: RealismModels, at: Vector3, size: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> void:
	# Size is local to the object. Scaling an already rotated basis distorts a
	# shallow sloping roof into a floating plate and disagrees with its collider.
	var shape := BoxMesh.new()
	shape.size = size
	builder.add(shape,at,Vector3.ONE,color,rotation)

func _solid(at: Vector3, size: Vector3, color: Color) -> void:
	_box(_stone,at, size, color)
	_collision(at, size)

func _ground() -> void:
	var extent := float(layout.extent)
	var earth := Color("#96836a")
	earth.a = 0.05
	_solid(Vector3(0,-0.3,0),Vector3(extent,0.6,extent),earth)
	for road in layout.roads:
		for i in range(road.points.size()-1):
			_road_segment(_v(road.points[i]),_v(road.points[i+1]),float(road.width),str(road.id))
	_forum_paving(_stone)

func _forum_paving(builder: RealismModels) -> void:
	var plaza: Dictionary = layout.forum
	var center := _v(plaza.position)
	var size := Vector2(float(plaza.size[0]),float(plaza.size[1]))
	var columns := int(size.x/0.95)
	var rows := int(size.y/0.8)
	# Close-set, worn limestone flags are quieter than alternating giant squares.
	for row in range(rows):
		for col in range(columns):
			var key := "forum/%s/%s" % [col,row]
			var tint := Color("#aaa38e").darkened(RealismModels.scatter(key,0)*0.13)
			var at := center+Vector3(-size.x/2+(col+0.5)*size.x/columns,0.023,-size.y/2+(row+0.5)*size.y/rows)
			_paving_stone(builder,at,Vector2(size.x/columns-0.018,size.y/rows-0.018),tint,key,0.0,0.05)
	# Narrow edge courses read as an intentional civic precinct from street level.
	for side in [-1.0,1.0]:
		_box(builder,center+Vector3(side*(size.x/2-0.25),0.047,0),Vector3(0.22,0.018,size.y),Color("#8d887a"))

func _road_segment(a: Vector3, b: Vector3, width: float, key: String) -> void:
	var direction := (b-a).normalized()
	var side := Vector3(-direction.z,0,direction.x)
	var length := a.distance_to(b)
	var yaw := atan2(direction.x,direction.z)
	var rotation := Vector3(0,yaw,0)
	var rows := maxi(1,int(length/0.66))
	var columns := maxi(2,int(width/0.62))
	for row in range(rows):
		for col in range(columns):
			var stone_key := "%s/%s/%s"%[key,row,col]
			var p := a+direction*((row+0.5)*length/rows)+side*((col+0.5)*width/columns-width/2)
			if _inside_forum(p):
				continue
			var tint := Color("#77796e").lerp(Color("#909080"),RealismModels.scatter(stone_key,2)*0.65)
			_paving_stone(_stone,p+Vector3.UP*0.022,Vector2(width/columns-0.014,length/rows-0.018),tint,stone_key,yaw,0.14)
	for edge in [-1.0,1.0]:
		for row in range(maxi(1,int(length/1.05))):
			var count := maxi(1,int(length/1.05))
			var p: Vector3 = a+direction*((row+0.5)*length/count)+side*(width*0.5+0.13)*float(edge)
			if _inside_forum(p):
				continue
			_box(_stone,p+Vector3.UP*0.07,Vector3(0.20,0.12,length/count-0.012),Color("#aa9f88"),rotation)
			_box(_stone,p+side*edge*0.2+Vector3.UP*0.014,Vector3(0.19,0.018,length/count),Color("#685e4a"),rotation)
			# Tiny verge shoots and grit stay off the shared walkable road surface.
			if row%5 == 1:
				var tuft: Vector3 = p+side*edge*0.42
				for stem in range(3):
					_detail.rod(tuft+Vector3(stem*0.06,0,0),tuft+Vector3(stem*0.09,0.15+stem*0.045,0.08),0.012,Color("#77764b"))

func _paving_stone(builder: RealismModels, p: Vector3, size: Vector2, tint: Color, key: String, yaw: float, irregularity: float) -> void:
	# Eight beveled corners break long perfectly straight seams without an image
	# texture. The geometry is deterministic and has no collision or rule effect.
	var bevel := minf(size.x,size.y)*(0.035+RealismModels.scatter(key,18)*irregularity)
	var rim: Array[Vector2] = [Vector2(-size.x/2+bevel,-size.y/2),Vector2(size.x/2-bevel,-size.y/2),Vector2(size.x/2,-size.y/2+bevel),Vector2(size.x/2,size.y/2-bevel),Vector2(size.x/2-bevel,size.y/2),Vector2(-size.x/2+bevel,size.y/2),Vector2(-size.x/2,size.y/2-bevel),Vector2(-size.x/2,-size.y/2+bevel)]
	for index in range(rim.size()):
		# Individually chipped corners, rather than eight identical tile cuts.
		var pull := RealismModels.scatter(key,30+index)*irregularity*0.4
		rim[index] *= 1.0-pull
	var basis := Basis(Vector3.UP,yaw)
	var height := 0.008+RealismModels.scatter(key,17)*0.005
	for index in range(8):
		var a := p+basis*Vector3(rim[index].x,0,rim[index].y)
		var b := p+basis*Vector3(rim[(index+1)%8].x,0,rim[(index+1)%8].y)
		var inner_a := p+(a-p)*0.94+Vector3.UP*height
		var inner_b := p+(b-p)*0.94+Vector3.UP*height
		_paving_triangle(builder,p+Vector3.UP*height,inner_b,inner_a,tint)
		_paving_triangle(builder,a,inner_a,inner_b,tint.darkened(0.08))
		_paving_triangle(builder,a,inner_b,b,tint.darkened(0.08))

func _paving_triangle(builder: RealismModels, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	# Godot's front faces use clockwise winding; explicit upward normals keep
	# the shallow dressed surface lit consistently with the surrounding floors.
	builder.surface.set_color(tint)
	builder.surface.set_normal(Vector3.UP)
	for point in [a,c,b]:
		builder.surface.add_vertex(point)
		builder.vertex_count += 1

func _inside_forum(p: Vector3) -> bool:
	var forum: Dictionary = layout.forum
	return absf(p.x-float(forum.position[0]))<float(forum.size[0])*0.5 and absf(p.z-float(forum.position[1]))<float(forum.size[1])*0.5

func _building(spec: Dictionary) -> void:
	_building_id = str(spec.id)
	_site_id = "" if str(spec.kind) == "house" else _building_id
	var p := _v(spec.position)
	var w := float(spec.size[0])
	var d := float(spec.size[1])
	var h := float(spec.height)
	var paint: Color = _plaster[int(spec.palette)]
	var door := float(spec.door_width)
	var enterable := bool(spec.enterable)
	var front := p.z+d*0.5
	if enterable:
		# The collision walls have an actual opening, not an invisible full box.
		_solid(p+Vector3(-w*0.5,h*0.5,0),Vector3(0.55,h,d),paint)
		_solid(p+Vector3(w*0.5,h*0.5,0),Vector3(0.55,h,d),paint)
		_solid(p+Vector3(0,h*0.5,-d*0.5),Vector3(w,h,0.55),paint)
		for side in [-1.0,1.0]:
			_solid(Vector3(p.x+side*(w+door)*0.25,h*0.5,front),Vector3((w-door)*0.5,h,0.55),paint)
		var opening_height := minf(3.6,h-0.5)
		_solid(Vector3(p.x,(h+opening_height)*0.5,front),Vector3(door,h-opening_height,0.55),paint)
		_box(_stone,p+Vector3.UP*0.035,Vector3(w-0.5,0.06,d-0.5),Color("#a18f71"))
		for j in range(6):
			_box(_detail,p+Vector3(0,h-0.2,-d*0.5+1+j*(d-2)/5),Vector3(w,0.22,0.24),_timber)
		_interior(spec)
	else:
		_solid(p+Vector3.UP*h*0.5,Vector3(w,h,d),paint)
		_box(_detail,Vector3(p.x,1.35,front+0.015),Vector3(door,2.7,0.10),_timber.darkened(0.25))
		for j in range(5):
			_box(_detail,Vector3(p.x-door/2+(j+0.5)*door/5,1.35,front+0.075),Vector3(door/5-0.025,2.65,0.035),_timber)
	var face := front+(0.28 if enterable else 0.015)
	# Ochre-red lower plaster, eaves, stone footings, and worn corner stones.
	for side in [-1.0,1.0]:
		_box(_detail,p+Vector3(side*(w*0.5+0.02),0.58,0),Vector3(0.045,1.1,d),Color("#9a6b51"))
		_box(_detail,p+Vector3(side*(w*0.5+0.04),0.15,0),Vector3(0.1,0.3,d),_limestone.darkened(0.17))
		for zside in [-1.0,1.0]:
			for row in range(int(h/0.55)):
				_box(_detail,p+Vector3(side*w*0.5,row*0.55+0.27,zside*d*0.5),Vector3(0.75 if row%2==0 else 0.54,0.49,0.70 if row%2==1 else 0.50),_limestone.lightened((row%3)*0.035))
		var end_width := (w-door)*0.5
		_box(_detail,Vector3(p.x+side*(w+door)*0.25,0.58,face+0.035),Vector3(end_width,1.1,0.045),Color("#9a6b51"))
		_box(_detail,Vector3(p.x+side*(w+door)*0.25,0.15,face+0.06),Vector3(end_width,0.3,0.09),_limestone.darkened(0.12))
		# Stone door jambs do not intrude into the authored door clearance.
		_box(_detail,Vector3(p.x+side*(door*0.5+0.15),1.6,face+0.06),Vector3(0.25,3.2,0.3),_limestone)
	_box(_detail,Vector3(p.x,3.25,face+0.07),Vector3(door+0.6,0.22,0.4),_limestone)
	_box(_detail,p+Vector3(0,h-0.12,0),Vector3(w+0.5,0.23,d+0.5),_timber)
	# Patchy plaster has thickness and long cracks, using stable building ids.
	for i in range(20):
		var u := RealismModels.scatter(str(spec.id),i*3)
		var v := RealismModels.scatter(str(spec.id),i*3+1)
		var x := p.x+(u-0.5)*(w-1.7)
		var y := 0.8+v*(h-1.6)
		if absf(x-p.x)<door*0.5+0.45 and y<3.7:
			continue
		_front_patch(Vector3(x,y,face+0.040),0.4+u*0.9,0.17+v*0.5,paint.darkened(0.08+v*0.08),str(spec.id)+str(i))
		if i%4==0:
			_detail.rod(Vector3(x,y,face+0.05),Vector3(x+0.12,y-0.55,face+0.05),0.008,paint.darkened(0.36))
	# Upper-storey wooden shutters and narrow ground-level ventilation openings.
	var windows := maxi(2,int(w/4.2))
	for i in range(windows):
		var x := p.x-w*0.5+(i+0.5)*w/windows
		var y := h-1.45
		if h<5.7 and absf(x-p.x)<door*0.5+0.7:
			continue
		_box(_detail,Vector3(x,y,face+0.045),Vector3(1.15,1.3,0.075),_timber.darkened(0.40))
		for shutter in [-1.0,1.0]:
			_box(_detail,Vector3(x+shutter*0.31,y,face+0.10),Vector3(0.54,1.2,0.10),_timber.lightened(0.10))
			for plank in range(3):
				_box(_detail,Vector3(x+shutter*0.31,y-0.42+plank*0.41,face+0.17),Vector3(0.54,0.042,0.032),_timber.darkened(0.18))
		_box(_detail,Vector3(x,y-0.7,face+0.22),Vector3(1.4,0.13,0.42),_limestone)
	_facade_craft(spec,face)
	_side_craft(spec)
	_roof(p,w,d,h,str(spec.id))
	if str(spec.kind)=="house":
		_awning(Vector3(p.x-w*0.25,0,face+0.12),minf(w*0.4,4.5),2.5,str(spec.id))
		_amphora(Vector3(p.x+w*0.30,0,face+0.85),0.7)
		_crate(Vector3(p.x+w*0.39,0,face+1.0),Vector3(1.0,0.75,0.8))
	_building_id = ""
	_site_id = ""

func _roof(p: Vector3, w: float, d: float, h: float, key: String) -> void:
	var half := d*0.5+0.6
	var rise := minf(2.8,d*0.18)
	var slope := atan2(rise,half)
	var roof_width := w+1.3
	var roof_length := sqrt(half*half+rise*rise)
	for side in [-1.0,1.0]:
		_box(_detail,p+Vector3(0,h+rise*0.5,side*half*0.5),Vector3(roof_width,0.13,roof_length),_tile,Vector3(side*slope,0,0))
		# Same thin planes as the drawn roof, so picking catches eaves accurately
		# while the doors and all space below the roof remain walkable.
		_collision(p+Vector3(0,h+rise*0.5,side*half*0.5),Vector3(roof_width,0.13,roof_length),Vector3(side*slope,0,0))
		for tile in range(int(roof_width/0.65)):
			var x := -roof_width*0.5+(tile+0.5)*0.65
			var tint := _tile.lightened(RealismModels.scatter(key,tile)*0.16)
			if key in ["tavern","barracks","curia"]:
				var courses := maxi(1,int(roof_length/0.64))
				for course in range(courses):
					var from := float(course)/courses
					var to := minf(1.0,float(course+1)/courses+0.012)
					var shade := tint.darkened(RealismModels.scatter(key+str(tile),course)*0.09)
					_detail.rod(p+Vector3(x,h+rise*(1-from)+0.075,side*half*from),p+Vector3(x,h+rise*(1-to)+0.075,side*half*to),0.074,shade,0.063)
			else:
				_detail.rod(p+Vector3(x,h+rise+0.075,0),p+Vector3(x,h+0.075,side*half),0.065,tint)
			# Dark exposed mouths and drip edges make the eaves read at eye level.
			_detail.ellipsoid(p+Vector3(x,h+0.068,side*(half+0.026)),Vector3(0.055,0.038,0.02),_tile.darkened(0.55))
			_box(_detail,p+Vector3(x+0.26,h-0.01,side*(half-0.08)),Vector3(0.47,0.09,0.23),tint)
		# Horizontal overlaps articulate tile courses without separate nodes.
		for course in range(1,int(roof_length/0.65)):
			var f := course*0.65/roof_length
			_box(_detail,p+Vector3(0,h+rise*(1-f)+0.09,side*half*f),Vector3(roof_width,0.045,0.055),_tile.darkened(0.08))
	_detail.rod(p+Vector3(-roof_width/2,h+rise+0.14,0),p+Vector3(roof_width/2,h+rise+0.14,0),0.16,_tile.lightened(0.15))
	# Gable ends are actual triangles under the roof.
	for side in [-1.0,1.0]:
		var a := p+Vector3(side*w*0.5,h,-d*0.5)
		var b := p+Vector3(side*w*0.5,h,d*0.5)
		var c := p+Vector3(side*w*0.5,h+rise,0)
		_detail.triangle(a,b,c,_limestone)
		_detail.triangle(c,b,a,_limestone)

func _interior(spec: Dictionary) -> void:
	var p := _v(spec.position)
	var w := float(spec.size[0])
	var d := float(spec.size[1])
	var kind := str(spec.kind)
	var light := OmniLight3D.new()
	light.position = p+Vector3(0,3,0)
	light.omni_range = maxf(w,d)*0.88
	light.light_color = Color("#eec591")
	light.light_energy = 1.2
	add_child(light)
	# Interior floors, a painted dado and ceiling lamps give the walkable rooms
	# their own material scale, rather than leaving an empty plaster shell.
	var floor_tint := Color("#b39d79") if kind=="curia" else Color("#9d8665")
	for ix in range(int((w-0.7)/1.2)):
		for iz in range(int((d-0.7)/1.2)):
			var tone := floor_tint.darkened(RealismModels.scatter("%s/%s/%s"%[kind,ix,iz],44)*0.12)
			_box(_detail,p+Vector3(-w/2+0.95+ix*1.2,0.071,-d/2+0.95+iz*1.2),Vector3(1.16,0.014,1.16),tone)
	for side in [-1.0,1.0]:
		_box(_detail,p+Vector3(side*(w/2-0.3),0.78,0),Vector3(0.025,1.5,d-0.6),Color("#925e48"))
		_box(_detail,p+Vector3(side*(w/2-0.32),1.55,0),Vector3(0.04,0.08,d-0.6),Color("#c8af79"))
	_box(_detail,p+Vector3(0,0.78,-d/2+0.3),Vector3(w-0.6,1.5,0.025),Color("#925e48"))
	_box(_detail,p+Vector3(0,1.55,-d/2+0.32),Vector3(w-0.6,0.08,0.04),Color("#c8af79"))
	for side in [-1.0,1.0]:
		var lamp := p+Vector3(side*3.0,2.85,1.0)
		_detail.ellipsoid(lamp,Vector3(0.25,0.065,0.25),Color("#887848"))
		_lamp_flame(lamp+Vector3.UP*0.10)
		var lamp_light := OmniLight3D.new()
		lamp_light.position = lamp+Vector3.DOWN*0.18
		lamp_light.omni_range = 9.0
		lamp_light.omni_attenuation = 0.65
		lamp_light.light_color = Color("#ffd29b")
		lamp_light.light_energy = 1.1
		add_child(lamp_light)
		for chain in range(3):
			var angle := chain*TAU/3
			_detail.rod(lamp+Vector3(cos(angle)*0.23,0,sin(angle)*0.23),lamp+Vector3(0,1.4,0),0.012,Color("#68634d"))
		_detail.rod(lamp+Vector3(0,1.4,0),p+Vector3(side*3.0,float(spec.height)-0.15,1.0),0.014,Color("#68634d"))
	_interior_details(spec)
	if kind=="tavern":
		# Serving counter, inset dolia, shelves and cooking hearth.
		_solid(p+Vector3(-5,0.58,-5),Vector3(8,1.15,1.5),Color("#ae9778"))
		_box(_detail,p+Vector3(-5,1.18,-5),Vector3(8.2,0.12,1.65),_limestone)
		for i in range(5):
			_amphora(p+Vector3(-8+i*1.6,1.25,-5),0.47)
			_amphora(p+Vector3(-8+i*1.8,0,-9),0.9)
		for shelf in range(3):
			_box(_detail,p+Vector3(4,1+shelf*0.8,-d/2+0.7),Vector3(7,0.13,0.75),_timber)
			for i in range(7):
				_amphora(p+Vector3(1+i,1.07+shelf*0.8,-d/2+0.7),0.3)
		for offset in [Vector3(5,0,3),Vector3(-5,0,6),Vector3(5,0,-3)]:
			_table(p+offset,Vector2(2.8,1.5))
			for side in [-1.0,1.0]:
				_bench(p+offset+Vector3(0,0,side*1.3),2.8)
		_solid(p+Vector3(8,0.6,-8),Vector3(2,1.2,2),Color("#766c57"))
		_detail.ellipsoid(p+Vector3(8,1.7,-8),Vector3(1.05,1.0,1.05),Color("#9c7758"))
		_box(_detail,p+Vector3(8,1.35,-6.99),Vector3(0.6,0.6,0.035),Color("#362d25"))
		_awning(p+Vector3(0,0,d/2+0.2),7.0,3.3,"tavern")
		# Existing furniture fixes the terrace footprint before refurbishment; the
		# project changes its finish and shade, never collision under the player.
		var terrace := p+Vector3(-w*0.31,0,d/2+1.17)
		_table(terrace,Vector2(1.5,0.85))
		for side in [-1.0,1.0]:
			_bench(terrace+Vector3(side*1.65,0,0),1.3)
	elif kind=="barracks":
		for side in [-1.0,1.0]:
			for i in range(4):
				var bed := p+Vector3(side*(w/2-3),0,-d/2+3+i*4.1)
				_solid(bed+Vector3.UP*0.33,Vector3(2.3,0.66,1.4),_timber)
				_box(_detail,bed+Vector3.UP*0.73,Vector3(2.15,0.19,1.3),Color("#b4a280"))
				_box(_detail,bed+Vector3(side*0.70,0.87,0),Vector3(0.50,0.16,1.15),Color("#d4c5a5"))
				_box(_detail,bed+Vector3(-side*0.25,0.84,0),Vector3(1.2,0.07,1.25),Color("#815348"))
		_weapon_rack(p+Vector3(-5,0,-d/2+1.0),5)
		_weapon_rack(p+Vector3(5,0,-d/2+1.0),5)
		_table(p+Vector3(0,0,-4),Vector2(4.2,2.0))
		_box(_detail,p+Vector3(0,1.04,-4),Vector3(2.4,0.018,1.5),Color("#d5c397"))
		for i in range(6):
			_box(_detail,p+Vector3(-0.9+i*0.35,1.07,-4),Vector3(0.11,0.06,0.13),Color("#995349"))
	elif kind=="curia":
		# Benches leave a broad aisle from the doorway to a low dais.
		for side in [-1.0,1.0]:
			for row in range(4):
				_bench(p+Vector3(side*7.7,0,-5.5+row*3),6.5)
		_solid(p+Vector3(0,0.18,-d/2+2.7),Vector3(9,0.36,3),_limestone)
		_table(p+Vector3(0,0.36,-d/2+2.8),Vector2(4,1.35))
		for i in range(5):
			_detail.rod(p+Vector3(-1.3+i*0.6,1.43,-6.8),p+Vector3(-1.3+i*0.6,1.43,-6.1),0.09,Color("#d9cba6"))
		for side in [-1.0,1.0]:
			for col in range(3):
				_column(p+Vector3(side*(w/2-1.3),0,-d/2+3+col*6),float(spec.height)-0.3,0.36)
		_portico(p+Vector3(0,0,d/2+2.5),w+4,4.5,5.0)

func _column(p: Vector3, height: float, radius: float) -> void:
	_solid(p+Vector3.UP*0.16,Vector3(radius*2.8,0.32,radius*2.8),_limestone)
	_detail.rod(p+Vector3.UP*0.25,p+Vector3.UP*(height-0.3),radius,_limestone.lightened(0.12),radius*0.8)
	_collision(p+Vector3.UP*height*0.5,Vector3(radius*1.8,height,radius*1.8))
	_box(_detail,p+Vector3.UP*(height-0.15),Vector3(radius*3,0.3,radius*3),_limestone)
	for ring in range(1,int(height/0.7)):
		_detail.rod(p+Vector3.UP*(ring*0.7),p+Vector3.UP*(ring*0.7+0.025),radius*1.025,_limestone.darkened(0.08))

func _portico(p: Vector3, width: float, depth: float, height: float) -> void:
	var n := maxi(4,int(width/4.0))
	for i in range(n):
		var x := -width/2+i*width/(n-1)
		if absf(x)<2.8:
			continue
		_column(p+Vector3(x,0,depth*0.5),height,0.32)
	_box(_detail,p+Vector3(0,height,depth*0.5),Vector3(width+0.8,0.4,0.9),_limestone)
	_box(_detail,p+Vector3(0,height+0.32,0),Vector3(width+1,0.2,depth+0.9),_tile)

func _forum_colonnades() -> void:
	for side in [-1.0,1.0]:
		for row in range(7):
			_column(Vector3(side*22.5,0,-22+row*6.3),4.6,0.33)
		_box(_detail,Vector3(side*22.5,4.6,-3),Vector3(0.85,0.42,42),_limestone)
		_box(_detail,Vector3(side*24.0,4.95,-3),Vector3(4,0.18,43),_tile)
	for i in range(3):
		_bench(Vector3(-20.5,0,-17+i*9),3.0)
	# Raised speaking platform and modest altar avoid later imperial monuments.
	_solid(Vector3(0,0.35,-25),Vector3(10,0.7,3),_limestone)
	_box(_detail,Vector3(0,0.9,-25),Vector3(2,0.4,0.9),Color("#a38d66"))

func _city_walls() -> void:
	var spec: Dictionary = layout.walls
	var e := float(spec.half_extent)
	var h := float(spec.height)
	var gate := float(spec.gate_width)
	for side in [-1.0,1.0]:
		_solid(Vector3(side*e,h/2,0),Vector3(2.4,h,e*2),Color("#9f997f"))
		_solid(Vector3(side*(e+gate/2)/2,h/2,e),Vector3(e-gate/2,h,2.4),Color("#9f997f"))
	_solid(Vector3(0,h/2,-e),Vector3(e*2,h,2.4),Color("#9f997f"))
	for x in range(-75,76,3):
		for z in [-e,e]:
			if z>0 and absf(x)<gate*0.5+1:
				continue
			_box(_detail,Vector3(x,h+0.5,z),Vector3(1.6,1.0,2.6),Color("#a9a38a"))
	for z in range(-75,76,3):
		for x in [-e,e]:
			_box(_detail,Vector3(x,h+0.5,z),Vector3(2.6,1.0,1.6),Color("#a9a38a"))
	# Masonry joints catch the afternoon sun on the city side.
	for row in range(int(h/0.65)):
		for i in range(51):
			var u := -76.5+i*3+(row%2)*1.5
			for side in [-1.0,1.0]:
				_box(_detail,Vector3(side*(e-1.22),row*0.65+0.30,u),Vector3(0.025,0.58,2.91),Color("#aaa38a").darkened((i%4)*0.025))
				if side<0 or absf(u)>gate/2+1:
					_box(_detail,Vector3(u,row*0.65+0.30,side*(e-1.22)),Vector3(2.91,0.58,0.025),Color("#aaa38a").darkened((i%4)*0.025))
	for x in [-e,e]:
		for z in [-e,e]:
			_tower(Vector3(x,0,z),h+2)
	for side in [-1.0,1.0]:
		_tower(Vector3(side*(gate/2+3),0,e),h+3)
		_box(_detail,Vector3(side*(gate/2-0.12),2.5,e+0.6),Vector3(0.3,5,4.2),_timber)
	_solid(Vector3(0,h-0.25,e),Vector3(gate+1,1.6,2.8),_limestone)
	if not bool(spec.get("gate_open", false)):
		var leaves := RealismModels.new()
		for side in [-1.0,1.0]:
			_box(leaves,Vector3(side*gate/4,2.7,e+0.35),Vector3(gate/2,5.4,0.35),_timber)
			_collision(Vector3(side*gate/4,2.7,e+0.35),Vector3(gate/2,5.4,0.35))
			gate_collisions.append(solid_body.get_child(solid_body.get_child_count()-1))
			for plank in range(6):
				var x: float = float(side)*gate/4-gate/4+(plank+0.5)*gate/12
				_box(leaves,Vector3(x,2.7,e+0.12),Vector3(gate/12-0.045,5.3,0.12),_timber.lightened((plank%3)*0.035))
			for rail in [1.3,3.8]:
				_box(leaves,Vector3(side*gate/4,rail,e),Vector3(gate/2-0.2,0.23,0.13),Color("#625e4e"))

		battle_gate = _mesh(leaves,"SouthGateLeaves")

func set_battle_gate_breached(breached: bool) -> void:
	# Presentation reflects the explicit battle step; this never changes rules.
	if battle_gate != null:
		battle_gate.visible = not breached
	if gate_reinforcement != null:
		gate_reinforcement.visible = gate_reinforcement.visible and not breached
	for shape in gate_collisions:
		shape.disabled = breached

func _tower(p: Vector3, h: float) -> void:
	_solid(p+Vector3.UP*h/2,Vector3(5.3,h,5.3),Color("#aaa185"))
	_box(_detail,p+Vector3.UP*(h-0.2),Vector3(5.7,0.5,5.7),_limestone)
	for side in [-1.0,1.0]:
		for i in range(3):
			_box(_detail,p+Vector3(side*2.6,h+0.4,-2+i*2),Vector3(0.75,1,1),_limestone)
			_box(_detail,p+Vector3(-2+i*2,h+0.4,side*2.6),Vector3(1,1,0.75),_limestone)

func _barracks_yard() -> void:
	var yard: Dictionary = layout.yard
	var p := _v(yard.position)
	var w := float(yard.size[0])
	var d := float(yard.size[1])
	var gate := float(yard.gate_width)
	_box(_stone,p+Vector3.UP*0.012,Vector3(w,0.018,d),Color("#b19a72"))
	for side in [-1.0,1.0]:
		_solid(p+Vector3(side*w/2,1.0,0),Vector3(0.4,2.0,d),_limestone.darkened(0.12))
		_solid(p+Vector3(side*(w+gate)/4,1.0,d/2),Vector3((w-gate)/2,2.0,0.4),_limestone.darkened(0.12))
		_box(_detail,p+Vector3(side*w/2,2.0,0),Vector3(0.65,0.16,d),_tile)
	for i in range(3):
		var target := p+Vector3(10,0,-5+i*6)
		_detail.rod(target,target+Vector3.UP*2.2,0.13,_timber)
		_detail.rod(target+Vector3(-0.7,1.5,0),target+Vector3(0.7,1.5,0),0.12,_timber)
		_detail.ellipsoid(target+Vector3.UP*1.6,Vector3(0.4,0.4,0.17),Color("#a88c54"))
	_weapon_rack(p+Vector3(-12,0,-9),6)
	_crate(p+Vector3(-11,0,10),Vector3(1.5,1.2,1.2))
	_crate(p+Vector3(-9.3,0,10),Vector3(1.2,0.8,1.0))

func _table(p: Vector3, size: Vector2) -> void:
	_solid(p+Vector3(0,0.95,0),Vector3(size.x,0.14,size.y),_timber.lightened(0.13))
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]:
			_box(_detail,p+Vector3(x*(size.x/2-0.15),0.45,z*(size.y/2-0.15)),Vector3(0.14,0.9,0.14),_timber)
	for i in range(3):
		_detail.rod(p+Vector3(-0.65+i*0.6,1.04,0),p+Vector3(-0.65+i*0.6,1.18,0),0.12,Color("#ae7450"))

func _bench(p: Vector3, width: float) -> void:
	_solid(p+Vector3.UP*0.47,Vector3(width,0.14,0.56),_timber)
	for side in [-1.0,1.0]:
		_box(_detail,p+Vector3(side*(width/2-0.25),0.23,0),Vector3(0.22,0.46,0.48),_timber.darkened(0.08))

func _amphora(p: Vector3, scale_by: float) -> void:
	var terracotta := Color("#b16e47")
	_detail.ellipsoid(p+Vector3.UP*scale_by*0.55,Vector3(0.31,0.48,0.31)*scale_by,terracotta)
	_detail.rod(p+Vector3.UP*scale_by*0.8,p+Vector3.UP*scale_by*1.18,0.105*scale_by,terracotta,0.13*scale_by)
	_detail.rod(p+Vector3.UP*scale_by*1.18,p+Vector3.UP*scale_by*1.21,0.145*scale_by,terracotta.lightened(0.12))
	for side in [-1.0,1.0]:
		var a := p+Vector3(side*0.12,1.08,0)*scale_by
		var b := p+Vector3(side*0.32,0.98,0)*scale_by
		var c := p+Vector3(side*0.25,0.74,0)*scale_by
		_detail.rod(a,b,0.035*scale_by,terracotta)
		_detail.rod(b,c,0.035*scale_by,terracotta)

func _crate(p: Vector3, size: Vector3) -> void:
	_solid(p+Vector3.UP*size.y/2,size,_timber.lightened(0.22))
	for i in range(4):
		_box(_detail,p+Vector3(0,(i+0.5)*size.y/4,size.z/2+0.02),Vector3(size.x,0.03,0.04),_timber.darkened(0.2))
	for side in [-1.0,1.0]:
		_box(_detail,p+Vector3(side*size.x*0.35,size.y/2,size.z/2+0.04),Vector3(0.1,size.y,0.055),_timber)

func _weapon_rack(p: Vector3, count: int) -> void:
	for side in [-1.0,1.0]:
		_box(_detail,p+Vector3(side*count*0.35,1,0),Vector3(0.13,2.0,0.13),_timber)
	_box(_detail,p+Vector3(0,1.5,0),Vector3(count*0.8,0.14,0.18),_timber)
	for i in range(count):
		var offset := Vector3((i-(count-1)/2.0)*0.65,0,0)
		_detail.rod(p+offset,p+offset+Vector3(0,2.9,-0.15),0.026,_timber)
		_detail.rod(p+offset+Vector3(0,2.9,-0.15),p+offset+Vector3(0,3.15,-0.16),0.055,Color("#6d716d"),0.0)
		_detail.ellipsoid(p+offset+Vector3(0,0.8,0.25),Vector3(0.29,0.57,0.07),Color("#85463c"))
		_detail.ellipsoid(p+offset+Vector3(0,0.8,0.32),Vector3(0.08,0.12,0.05),Color("#a39369"))

func _awning(p: Vector3, width: float, depth: float, key: String) -> void:
	var canvas := Color("#bfae82") if RealismModels.scatter(key,77)>0.5 else Color("#9e5b46")
	for side in [-1.0,1.0]:
		_detail.rod(p+Vector3(side*width/2,0,depth),p+Vector3(side*width/2,2.8,depth),0.065,_timber)
		_detail.rod(p+Vector3(side*width/2,2.8,depth),p+Vector3(side*width/2,3.3,0),0.06,_timber)
	for strip in range(8):
		var x := (strip+0.5)*width/8-width/2
		_box(_detail,p+Vector3(x,3.05,depth/2),Vector3(width/8+0.01,0.035,sqrt(depth*depth+0.25)),canvas.lightened(0.12 if strip%2 else 0.0),Vector3(atan2(0.5,depth),0,0))
		_box(_detail,p+Vector3(x,2.65,depth),Vector3(width/8,0.28,0.04),canvas)

func _market_stall(p: Vector3, key: String) -> void:
	_awning(p+Vector3(0,0,-1.7),5.5,3.4,key)
	_solid(p+Vector3(0,0.7,0),Vector3(4.8,0.18,1.8),_timber)
	for side in [-1.0,1.0]:
		_box(_detail,p+Vector3(side*2.0,0.35,0),Vector3(0.12,0.7,1.5),_timber)
	for i in range(5):
		var basket := p+Vector3(-1.8+i*0.9,0.88,0)
		_detail.ellipsoid(basket,Vector3(0.37,0.2,0.5),Color("#a1844c"))
		for j in range(5):
			var color := Color("#927740") if i%2==0 else Color("#637541")
			_detail.ellipsoid(basket+Vector3((j%3-1)*0.17,0.17,(j/3-0.5)*0.22),Vector3(0.11,0.1,0.12),color)
	for i in range(3):
		_amphora(p+Vector3(-2.8-i*0.42,0,0.5),0.75)

func _cypress(p: Vector3, key: String) -> void:
	var height := 7.0+RealismModels.scatter(key,17)*2.8
	_detail.rod(p,p+Vector3.UP*height*0.7,0.21,Color("#625641"),0.055)
	_collision(p+Vector3.UP*1.8,Vector3(0.42,3.6,0.42))
	var olive := RealismModels.scatter(key,91)>0.70
	var bark := Color("#6c624c")
	for branch in range(7 if olive else 5):
		var angle := branch*2.399+RealismModels.scatter(key,60)*TAU
		var reach := 1.5 if olive else 0.65
		var root := p+Vector3.UP*(2.4+branch*0.38)
		var tip := root+Vector3(cos(angle)*reach,0.6,sin(angle)*reach)
		_detail.rod(root,tip,0.08,bark,0.024)
	for i in range(25):
		var f := float(i)/25
		var angle := i*2.399
		var radius := (0.85+sin(f*PI)*0.85) if olive else (0.24+sin(f*PI)*0.56)
		var y := 3.0+f*2.4 if olive else 2.0+f*height
		var spread := 1.3 if olive else 0.28
		var at := p+Vector3(cos(angle)*spread*(1-f*0.6),y,sin(angle)*spread*(1-f*0.6))
		var tint := Color("#59654a") if olive else Color("#3e513c")
		tint = tint.lightened(RealismModels.scatter(key,i)*0.11)
		tint.a = 0.10
		var cluster := SphereMesh.new()
		cluster.radial_segments = 7
		cluster.rings = 4
		cluster.radius = 1
		cluster.height = 2
		_detail.add(cluster,at,Vector3(radius,0.48 if olive else 0.82,radius*0.79),tint,Vector3(0.12*sin(angle),angle,0.12*cos(angle)))

func _fountain(p: Vector3) -> void:
	var stone := Color("#bcb39b")
	for side in [-1.0,1.0]:
		_solid(p+Vector3(side*2,0.5,0),Vector3(0.4,1,3.6),stone)
		_solid(p+Vector3(0,0.5,side*1.8),Vector3(4.4,1,0.4),stone)
		_box(_detail,p+Vector3(side*2,1.04,0),Vector3(0.55,0.15,3.95),stone.lightened(0.1))
		_box(_detail,p+Vector3(0,1.04,side*1.8),Vector3(4.55,0.15,0.55),stone.lightened(0.1))
	_solid(p+Vector3(0,1.55,-1.6),Vector3(0.8,3.1,0.75),stone)
	_detail.rod(p+Vector3(0,1.7,-1.2),p+Vector3(0,1.7,-0.72),0.10,Color("#7e8767"))
	var pool := PlaneMesh.new()
	pool.size = Vector2(3.6,3.15)
	water = MeshInstance3D.new()
	water.mesh = pool
	water.position = p+Vector3(0,0.75,0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#698778")
	mat.roughness = 0.22
	mat.metallic = 0.15
	water.material_override = mat
	add_child(water)
	_detail.rod(p+Vector3(0,1.69,-0.71),p+Vector3(0,0.77,-0.45),0.035,Color("#a9c6b7"))
	_amphora(p+Vector3(2.8,0,0.8),0.85)

func _street_life() -> void:
	for x in [-1.0,1.0]:
		_cart(Vector3(x*8.5,0,56))
	# Roadside storage is kept out of the 8m central avenue.
	for i in range(4):
		_crate(Vector3(-55,0,36+i*1.2),Vector3(1,0.85,1))
	for i in range(5):
		_amphora(Vector3(28+i*0.7,0,33),0.85)
	# A public notice panel at the forum entrance.
	for side in [-1.0,1.0]:
		_box(_detail,Vector3(8+side*1.5,1.2,29),Vector3(0.14,2.4,0.14),_timber)
	_box(_detail,Vector3(8,1.65,29),Vector3(3.2,1.1,0.12),_timber)
	for i in range(4):
		_box(_detail,Vector3(6.9+i*0.7,1.65,29.08),Vector3(0.53,0.81,0.015),Color("#cabc92"))

func _cart(p: Vector3) -> void:
	_solid(p+Vector3.UP*0.85,Vector3(1.8,0.15,3.0),_timber)
	for side in [-1.0,1.0]:
		for plank in range(4):
			_box(_detail,p+Vector3(side*0.85,1+plank*0.18,0),Vector3(0.1,0.15,3.0),_timber.lightened(plank*0.03))
		_detail.rod(p+Vector3(side*0.6,0.8,1),p+Vector3(side*0.6,0.7,3.2),0.055,_timber)
		var center := p+Vector3(side*1.02,0.58,0)
		for i in range(16):
			var a := center+Vector3(0,sin(i*TAU/16),cos(i*TAU/16))*0.59
			var b := center+Vector3(0,sin((i+1)*TAU/16),cos((i+1)*TAU/16))*0.59
			_detail.rod(a,b,0.07,_timber.darkened(0.1))
			if i%2==0:
				_detail.rod(center,a,0.035,_timber)
		_detail.rod(center-Vector3.RIGHT*0.12,center+Vector3.RIGHT*0.12,0.15,_timber)
	for i in range(3):
		_detail.ellipsoid(p+Vector3(0,1.0,i*0.75-0.75),Vector3(0.65,0.3,0.4),Color("#b4a073"))

func _status_geometry() -> void:
	var dirt := RealismModels.new()
	for point in layout.rubbish:
		var p := _v(point)
		for i in range(13):
			var angle := i*2.399
			dirt.ellipsoid(p+Vector3(cos(angle)*0.7,0.10,sin(angle)*0.7),Vector3(0.22,0.08,0.16),Color("#746b44").lightened((i%3)*0.06))
			_box(dirt,p+Vector3(cos(angle)*0.8,0.09,sin(angle)*0.8),Vector3(0.16,0.08,0.24),Color("#a17250"),Vector3(0,angle,0.2))
	rubble = _mesh(dirt,"VisibleStreetRubbish")
	var repair := RealismModels.new()
	var restored := RealismModels.new()
	for point in layout.repair_areas:
		var p := _v(point)
		for side in [-1.0,1.0]:
			_box(repair,p+Vector3(side*2,0.5,1.8),Vector3(0.13,1,0.13),_timber)
			_box(repair,p+Vector3(0,0.75,side*1.8),Vector3(4.2,0.16,0.1),_timber)
		for i in range(9):
			_box(repair,p+Vector3((i%3-1)*0.65,0.11+(i/3)*0.12,0),Vector3(0.57,0.22,0.53),_limestone)
		for x in range(6):
			for z in range(5):
				_box(restored,p+Vector3(-2.25+x*0.9,0.055,-1.8+z*0.9),Vector3(0.86,0.02,0.86),Color("#bdb39b"))
	repairs = _mesh(repair,"ActiveStreetRepairs")
	restored_streets = _mesh(restored,"RepairedPaving")
	# A visible closure notice and closed serving shutters convey a decree. The
	# entrance remains physically accessible so the player cannot be trapped.
	var closed := RealismModels.new()
	for building in layout.buildings:
		if str(building.id)!="tavern":
			continue
		var p := _v(building.position)
		var z := p.z+float(building.size[1])/2+0.5
		for side in [-1.0,1.0]:
			_box(closed,Vector3(p.x+side*3,1.7,z),Vector3(1.8,2.4,0.14),_timber.darkened(0.13))
			_box(closed,Vector3(p.x+side*3,1.7,z+0.1),Vector3(1.9,0.15,0.08),Color("#aa8460"),Vector3(0,0,0.55))
		_box(closed,Vector3(p.x+2.6,2.3,z+0.2),Vector3(0.8,0.9,0.04),Color("#ded0a7"))
	tavern_closed = _mesh(closed,"TavernClosureNotice")

func _lamp_flame(p: Vector3) -> void:
	var mesh_node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = 0.04
	mesh.height = 0.17
	mesh_node.mesh = mesh
	mesh_node.position = p
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ffe0a4")
	material.emission_enabled = true
	material.emission = Color("#ffbe62")
	material.emission_energy_multiplier = 2.5
	mesh_node.material_override = material
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_node)

func _interior_details(spec: Dictionary) -> void:
	var p := _v(spec.position)
	var w := float(spec.size[0])
	var d := float(spec.size[1])
	# Geometric painted panels and worn lime framing are original decoration.
	for side in [-1.0,1.0]:
		for panel in range(3):
			var z := -d/2+3.4+panel*(d-5.2)/3
			var x: float = p.x+side*(w/2-0.33)
			_box(_detail,Vector3(x,2.6,p.z+z),Vector3(0.025,1.55,2.3),Color("#b29672"))
			_box(_detail,Vector3(x-side*0.018,2.6,p.z+z),Vector3(0.012,1.37,2.10),Color("#916a51"))
			_box(_detail,Vector3(x-side*0.028,2.6,p.z+z),Vector3(0.012,1.15,1.88),Color("#bda682"))
			_detail.rod(Vector3(x-side*0.045,2.15,p.z+z),Vector3(x-side*0.045,3.0,p.z+z),0.026,Color("#6e774f"))
			for leaf in range(4):
				_detail.ellipsoid(Vector3(x-side*0.045,2.24+leaf*0.18,p.z+z+(0.10 if leaf%2 else -0.10)),Vector3(0.014,0.065,0.13),Color("#6e774f"))
	if str(spec.kind) == "tavern":
		for index in range(5):
			var loaf := p+Vector3(-8+index*0.38,1.32,-4.6)
			_detail.ellipsoid(loaf,Vector3(0.16,0.06,0.10),Color("#b99759"))
		for index in range(3):
			var hook := p+Vector3(6.2+index*0.65,3.65,-8.6)
			_detail.rod(hook,hook+Vector3.UP*0.55,0.018,_timber)
			for leaf in range(4):
				_detail.ellipsoid(hook+Vector3((leaf%2-0.5)*0.12,-leaf*0.08,0),Vector3(0.10,0.20,0.07),Color("#707345"))
		for offset in [Vector3(5,0,3),Vector3(-5,0,6),Vector3(5,0,-3)]:
			var table: Vector3 = p+offset
			_detail.ellipsoid(table+Vector3(0.7,1.07,0),Vector3(0.23,0.025,0.23),Color("#c49567"))
			_detail.ellipsoid(table+Vector3(0.7,1.105,0),Vector3(0.16,0.06,0.13),Color("#ad915a"))
		_lamp_flame(p+Vector3(8,1.31,-6.96))
	elif str(spec.kind) == "barracks":
		for side in [-1.0,1.0]:
			for row in range(3):
				var peg := p+Vector3(side*(w/2-0.42),2.4,-7+row*5)
				_detail.rod(peg,peg+Vector3(-side*0.28,0,0),0.035,_timber)
				_box(_detail,peg+Vector3(-side*0.15,-0.55,0),Vector3(0.07,1.05,0.7),Color("#8c5243"))
	elif str(spec.kind) == "curia":
		for side in [-1.0,1.0]:
			var cabinet := p+Vector3(side*(w/2-1.7),0,-d/2+1.0)
			_box(_detail,cabinet+Vector3.UP*1.1,Vector3(2.0,2.2,0.85),_timber)
			for row in range(4):
				_box(_detail,cabinet+Vector3(0,0.38+row*0.49,0.45),Vector3(1.8,0.38,0.055),_timber.lightened(0.13))
				_detail.ellipsoid(cabinet+Vector3(0,0.38+row*0.49,0.51),Vector3(0.07,0.04,0.025),Color("#a58b4f"))

func set_selection(building_id: String, site_id: String) -> void:
	if is_instance_valid(selection):
		remove_child(selection)
		selection.queue_free()
	selection = null
	if building_id.is_empty() and site_id.is_empty():
		return
	var center := Vector3.ZERO
	var half := Vector2.ZERO
	for building in layout.buildings:
		if str(building.id) == building_id:
			center = _v(building.position)
			half = Vector2(float(building.size[0]),float(building.size[1]))*0.5+Vector2.ONE*0.6
			break
	if half == Vector2.ZERO:
		for site in sites:
			if str(site.id) == site_id:
				center = _v(site.position)
				half = Vector2.ONE*3.0
				break
	if half == Vector2.ZERO:
		return
	var rim := RealismModels.new()
	var color := Color("#d6b56f")
	for side in [-1.0,1.0]:
		# Corner brackets avoid painting a distracting full rectangle across roads.
		for end in [-1.0,1.0]:
			var corner := center+Vector3(side*half.x,0.09,end*half.y)
			rim.rod(corner,corner-Vector3(side*minf(2.6,half.x),0,0),0.035,color)
			rim.rod(corner,corner-Vector3(0,0,end*minf(2.6,half.y)),0.035,color)
	selection = _mesh(rim,"SelectedCityPlace")
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	selection.material_override = material
	selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _project_geometry() -> void:
	for site_id in ["tavern","barracks","market","curia"]:
		var p := Vector3.ZERO
		var width := 6.0
		var height := 4.3
		if site_id == "market":
			p = _v(layout.market_stalls[0])+Vector3(0,0,-1.7)
		else:
			for building in layout.buildings:
				if str(building.id) == site_id:
					p = _v(building.position)+Vector3(-float(building.size[0])*0.31,0,float(building.size[1])*0.5+0.42)
					width = float(building.size[0])*0.25
					height = minf(5.1,float(building.height))
		# Scaffolds stay beside a facade and have no new collision: a pending
		# work order cannot trap a governor standing in an existing doorway.
		var scaffold := RealismModels.new()
		for side in [-1.0,1.0]:
			for depth in [0.0,0.9]:
				var foot := p+Vector3(side*width/2,0,depth)
				scaffold.rod(foot,foot+Vector3.UP*height,0.055,_timber)
				scaffold.rod(foot+Vector3(0,0.3,0),p+Vector3(-side*width/2,height-0.4,depth),0.037,_timber)
		for level in range(1,3):
			var y := level*height/3
			_box(scaffold,p+Vector3(0,y,0.45),Vector3(width+0.35,0.08,1.15),_timber.lightened(0.13))
			for side in [-1.0,1.0]:
				scaffold.rod(p+Vector3(-width/2,y+0.75,side*0.45+0.45),p+Vector3(width/2,y+0.75,side*0.45+0.45),0.035,_timber)
		for step in range(8):
			scaffold.rod(p+Vector3(width/2-0.8,step*0.36,0.96),p+Vector3(width/2-0.28,step*0.36,0.96),0.025,_timber)
		for side in [0.28,0.8]:
			scaffold.rod(p+Vector3(width/2-side,0,0.96),p+Vector3(width/2-side,3.05,0.96),0.035,_timber)
		var action_id: String = "improve_"+site_id
		project_scaffolds[action_id] = _mesh(scaffold,"Works_"+site_id)
		var improved := RealismModels.new()
		if site_id == "tavern":
			# New serving shade and wall-side seating leave the centre entrance open.
			_box(improved,p+Vector3(0,3.45,0.6),Vector3(width+0.3,0.08,2.5),Color("#aa765a"),Vector3(0.10,0,0))
			for side in [-1.0,1.0]:
				improved.rod(p+Vector3(side*width/2,0,1.75),p+Vector3(side*width/2,3.3,1.75),0.07,_timber)
				_box(improved,p+Vector3(side*1.65,0.52,0.75),Vector3(1.3,0.14,0.5),_timber)
			_box(improved,p+Vector3(0,1.02,0.75),Vector3(1.5,0.12,0.85),_timber.lightened(0.14))
			for side in [-1.0,1.0]:
				improved.rod(p+Vector3(side*0.48,0,0.75),p+Vector3(side*0.48,1.0,0.75),0.07,_timber)
		elif site_id == "barracks":
			_box(improved,p+Vector3(0,2.5,0.20),Vector3(width*0.55,2.7,0.06),Color("#994c3d"))
			_box(improved,p+Vector3(0,3.8,0.24),Vector3(width*0.58,0.12,0.14),_timber)
			for i in range(5):
				var rack := p+Vector3(-2.0+i*0.85,0,0.65)
				improved.rod(rack,rack+Vector3.UP*2.85,0.032,_timber)
				improved.rod(rack+Vector3.UP*2.85,rack+Vector3.UP*3.15,0.05,Color("#8a8d88"),0.0)
				improved.ellipsoid(rack+Vector3(0,0.95,0.12),Vector3(0.32,0.61,0.07),Color("#88473b"))
			improved.rod(p+Vector3(-2.4,1.5,0.7),p+Vector3(2.1,1.5,0.7),0.065,_timber)
		elif site_id == "market":
			# A second overhead weather layer and reinforced shelves appear on every
			# existing stall; aisles and the authored merchant route stay unchanged.
			for point in layout.market_stalls:
				var stall := _v(point)
				_box(improved,stall+Vector3(0,3.36,0),Vector3(6.0,0.06,3.9),Color("#b39360"),Vector3(0.06,0,0))
				_box(improved,stall+Vector3(0,1.65,-0.85),Vector3(4.8,0.10,0.42),_timber)
				for j in range(6):
					improved.ellipsoid(stall+Vector3(-1.9+j*0.75,1.80,-0.85),Vector3(0.26,0.10,0.16),Color("#b6a276"))
		else:
			_box(improved,p+Vector3(0,2.45,0.035),Vector3(width,3.4,0.025),Color("#ad7258"))
			_box(improved,p+Vector3(0,2.0,0.10),Vector3(width*0.66,1.4,0.07),Color("#7c7350"))
			for row in range(7):
				_box(improved,p+Vector3(0,1.48+row*0.16,0.15),Vector3(width*0.56,0.023,0.015),Color("#c3ac72"))
		_completed_facade(improved,site_id)
		project_improvements[action_id] = _mesh(improved,"Completed_"+site_id)

func _front_patch(p: Vector3, width: float, height: float, color: Color, key: String) -> void:
	for i in range(7):
		var angle_a := i*TAU/7
		var angle_b := (i+1)*TAU/7
		var a := p+Vector3(cos(angle_a)*width*(0.35+RealismModels.scatter(key,i)*0.15),sin(angle_a)*height*(0.35+RealismModels.scatter(key,i+7)*0.15),0)
		var b := p+Vector3(cos(angle_b)*width*(0.35+RealismModels.scatter(key,(i+1)%7)*0.15),sin(angle_b)*height*(0.35+RealismModels.scatter(key,(i+1)%7+7)*0.15),0)
		_detail.surface.set_color(color)
		_detail.surface.set_normal(Vector3.BACK)
		for vertex in [p,b,a]:
			_detail.surface.add_vertex(vertex)
			_detail.vertex_count += 1

func _facade_craft(spec: Dictionary, face: float) -> void:
	var p := _v(spec.position)
	var w := float(spec.size[0])
	var h := float(spec.height)
	var door := float(spec.door_width)
	var key := str(spec.id)
	var iron := Color("#514e43")
	# An exposed dressed-stone plinth with staggered joints, chipped faces and
	# slightly recessed mortar carries the wall visually instead of a flat strip.
	for row in range(3):
		var blocks := maxi(3,int(w/0.85))
		for index in range(blocks):
			var x := p.x-w/2+(index+0.5)*w/blocks
			if absf(x-p.x)<door/2+0.47:
				continue
			var tone := _limestone.darkened(0.16+RealismModels.scatter(key+str(row),index)*0.10)
			_box(_detail,Vector3(x,0.13+row*0.24,face+0.058),Vector3(w/blocks-0.038,0.213,0.11),tone)
			if index%3 == 1:
				_front_patch(Vector3(x-0.16,0.17+row*0.24,face+0.12),0.14,0.06,tone.darkened(0.20),key+str(index))
	# Limewash peels near the damp foot of the walls in irregular, shallow patches.
	for index in range(int(w*1.3)):
		var x := p.x-w/2+0.55+RealismModels.scatter(key,index+170)*(w-1.1)
		if absf(x-p.x)<door/2+0.42:
			continue
		var high := 0.3+RealismModels.scatter(key,index+290)*0.85
		_front_patch(Vector3(x,0.92,face+0.053),0.25+high*0.3,high,Color("#b39b7d"),key+"wear"+str(index))
	# A lintel, bronze door furniture and open leaves flank accessible doorways.
	for side in [-1.0,1.0]:
		var x: float = p.x+side*(door/2+0.48)
		if bool(spec.enterable):
			var leaf_width := minf(1.05,door*0.32)
			for board in range(5):
				_box(_detail,Vector3(x+side*(board+0.5)*leaf_width/5,1.43,face+0.19),Vector3(leaf_width/5-0.017,2.75,0.12),_timber.darkened((board%3)*0.055))
			for height in [0.62,2.22]:
				_box(_detail,Vector3(x+side*leaf_width/2,height,face+0.263),Vector3(leaf_width,0.10,0.034),iron)
				for pin in range(3):
					_detail.ellipsoid(Vector3(x+side*(pin+0.5)*leaf_width/3,height,face+0.29),Vector3(0.025,0.025,0.018),iron.lightened(0.24))
			_detail.rod(Vector3(x,0.55,face+0.25),Vector3(x,2.6,face+0.25),0.032,iron)
		else:
			for height in [0.7,2.1]:
				_box(_detail,Vector3(p.x+side*door*0.23,height,face+0.14),Vector3(door*0.39,0.075,0.03),iron)
			_detail.ellipsoid(Vector3(p.x+side*0.18,1.3,face+0.15),Vector3(0.05,0.07,0.023),Color("#a08954"))
	# Timber ends, fascia joints and modest rafter tails articulate the roof load.
	var rafters := maxi(3,int(w/1.3))
	for index in range(rafters):
		var x := p.x-w/2+(index+0.5)*w/rafters
		_box(_detail,Vector3(x,h-0.23,face+0.23),Vector3(0.14,0.19,0.72),_timber.darkened(0.10))
		_box(_detail,Vector3(x,h-0.23,face+0.605),Vector3(0.095,0.145,0.025),_timber.lightened(0.11))
	# Recessed frames and visibly separate shutter boards hold sunlight at their
	# edges; all relief sits outside the actual wall surface, not inside it.
	var windows := maxi(2,int(w/4.2))
	for index in range(windows):
		var x := p.x-w/2+(index+0.5)*w/windows
		var y := h-1.45
		if h<5.7 and absf(x-p.x)<door/2+0.7:
			continue
		for side in [-1.0,1.0]:
			_box(_detail,Vector3(x+side*0.67,y,face+0.16),Vector3(0.15,1.6,0.23),_limestone.darkened(0.10))
			for line in range(3):
				_box(_detail,Vector3(x+side*(0.10+line*0.17),y,face+0.165),Vector3(0.025,1.12,0.02),_timber.darkened(0.32))
			for hinge in [-1.0,1.0]:
				_box(_detail,Vector3(x+side*0.49,y+hinge*0.36,face+0.20),Vector3(0.17,0.055,0.025),iron)
		_box(_detail,Vector3(x,y+0.78,face+0.13),Vector3(1.45,0.16,0.22),_limestone)

func build_preview(authored_layout: Dictionary, site_id: String) -> void:
	_prepare(authored_layout)
	preview_site_id = site_id
	_site_id = site_id
	var found := false
	for spec in layout.buildings:
		if str(spec.id) == site_id:
			preview_center = _v(spec.position,2.5)
			preview_radius = maxf(float(spec.size[0]),float(spec.size[1]))*0.70
			_building(spec)
			found = true
			break
	if not found:
		for site in sites:
			if str(site.id) == site_id:
				preview_center = _v(site.position,1.5)
		if site_id == "market":
			preview_radius = 17.0
			for point in layout.market_stalls:
				_market_stall(_v(point),str(point))
		elif site_id == "fountain":
			preview_radius = 4.5
			_fountain(_v(layout.water_position))
		else:
			preview_radius = 31.0
			_forum_colonnades()
			_forum_paving(_stone)
	# Isolated masonry/plaza base makes this an honest model of the same site,
	# without distant neighbours obscuring the future-state comparison.
	var ground := RealismModels.new()
	_box(ground,Vector3(preview_center.x,-0.10,preview_center.z),Vector3(preview_radius*2.5,0.15,preview_radius*2.0),Color("#a09276"))
	var floor_mesh := _mesh(ground,"PreviewGround")
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh(_stone,"PreviewMasonry")
	_mesh(_detail,"PreviewArchitecture")
	_status_geometry()
	_project_geometry()
	_waterworks_geometry()
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.background_mode = Environment.BG_COLOR
			child.environment.background_color = Color("#202c29")
			child.environment.fog_enabled = false

func preview_stage(status: Dictionary, stage: String) -> void:
	# This is a model comparison, never a command. Deep copies prevent the
	# hypothetical future from completing or paying for an actual city project.
	var sample := status.duplicate(true)
	var action_id := "improve_"+preview_site_id
	if preview_site_id == "forum":
		action_id = "repair_streets"
	elif preview_site_id == "fountain":
		action_id = "clean_water"
	var projects: Dictionary = sample.get("projects", {}).duplicate(true)
	projects[action_id] = {"remaining":1 if stage == "construction" else 0,"completed":stage == "improved"}
	sample["projects"] = projects
	sample["street_condition"] = 40.0
	apply_status(sample)
	rubble.visible = false
	repairs.visible = preview_site_id == "forum" and stage == "construction"
	restored_streets.visible = preview_site_id == "forum" and stage == "improved"
	tavern_closed.visible = preview_site_id == "tavern" and str(sample.get("policies", {}).get("taverns", "open")) == "closed"
	for project_id in project_scaffolds:
		project_scaffolds[project_id].visible = project_id == action_id and stage == "construction"
		project_improvements[project_id].visible = project_id == action_id and stage == "improved"

func _completed_facade(builder: RealismModels, site_id: String) -> void:
	for spec in layout.buildings:
		if str(spec.id) != site_id:
			continue
		var p := _v(spec.position)
		var w := float(spec.size[0])
		var h := float(spec.height)
		var face := p.z+float(spec.size[1])/2+0.32
		var trim := Color("#98513f") if site_id != "curia" else Color("#a37752")
		# A renewed painted frieze, cornice and bronze studs make completion
		# legible from the road and in the real geometry used by the model viewer.
		_box(builder,Vector3(p.x,h-0.68,face+0.04),Vector3(w-1.0,0.48,0.055),trim)
		for side in [-1.0,1.0]:
			_box(builder,Vector3(p.x,h-0.68+side*0.26,face+0.085),Vector3(w-0.75,0.07,0.09),_limestone.lightened(0.08))
		for index in range(int(w/1.1)):
			var x := p.x-w/2+0.7+index*1.1
			builder.ellipsoid(Vector3(x,h-0.68,face+0.09),Vector3(0.04,0.04,0.019),Color("#ba9d61"))
		if site_id == "tavern":
			_box(builder,Vector3(p.x+6.5,2.35,face+0.21),Vector3(3.0,0.92,0.11),_timber)
			for side in [-1.0,1.0]:
				builder.rod(Vector3(p.x+6.5+side*1.35,2.0,face+0.29),Vector3(p.x+6.5+side*1.35,2.7,face+0.29),0.035,Color("#b6a171"))
			builder.ellipsoid(Vector3(p.x+6.5,2.28,face+0.31),Vector3(0.21,0.25,0.035),Color("#b08a5b"))
			builder.rod(Vector3(p.x+6.5,2.45,face+0.31),Vector3(p.x+6.5,2.62,face+0.31),0.08,Color("#b08a5b"))
		elif site_id == "curia":
			for side in [-1.0,1.0]:
				var x: float = p.x+side*8.4
				_box(builder,Vector3(x,2.0,face+0.14),Vector3(3.0,2.2,0.13),_limestone.lightened(0.1))
				_box(builder,Vector3(x,2.0,face+0.22),Vector3(2.65,1.85,0.065),Color("#867751"))
				for row in range(8):
					_box(builder,Vector3(x,1.3+row*0.19,face+0.26),Vector3(2.2,0.026,0.014),Color("#b6a16f"))

func _military_project_geometry() -> void:
	var p := Vector3.ZERO
	for spec in layout.buildings:
		if str(spec.id) == "barracks":
			p = _v(spec.position)+Vector3(float(spec.size[0])*0.30,0,float(spec.size[1])/2+0.55)
	for project_id in ["drill_maniples","equip_maniples"]:
		var pending := RealismModels.new()
		_box(pending,p+Vector3(0,0.38,0.25),Vector3(3.1,0.75,0.75),_timber)
		for side in [-1.0,1.0]:
			_box(pending,p+Vector3(side*1.2,0.4,0.65),Vector3(0.12,0.8,0.055),Color("#aa9272"))
		project_scaffolds[project_id] = _mesh(pending,"MilitaryWorks_"+project_id)
		var completed := RealismModels.new()
		if project_id == "drill_maniples":
			for index in range(3):
				var at := _v(layout.yard.position)+Vector3(10,0,-5+index*6)
				completed.rod(at+Vector3(-0.65,1.5,0.05),at+Vector3(0.65,1.5,0.05),0.16,Color("#a48b61"))
				completed.ellipsoid(at+Vector3(0,1.62,0.2),Vector3(0.43,0.5,0.11),Color("#875542"))
				completed.rod(at+Vector3(0,0.65,0.37),at+Vector3(0,2.10,0.37),0.025,Color("#c2b17a"))
		else:
			for index in range(5):
				var at := p+Vector3(-1.7+index*0.85,0,0)
				completed.rod(at+Vector3.UP*0.2,at+Vector3.UP*2.9,0.03,_timber)
				completed.rod(at+Vector3.UP*2.9,at+Vector3.UP*3.18,0.052,Color("#91928a"),0.0)
				completed.ellipsoid(at+Vector3(0,1.1,0.28),Vector3(0.35,0.62,0.08),Color("#973e32"))
				completed.ellipsoid(at+Vector3(0,1.1,0.37),Vector3(0.10,0.15,0.065),Color("#b19b59"))
				_box(completed,at+Vector3(0,1.1,0.38),Vector3(0.035,1.1,0.025),Color("#c8ad6a"))
			_box(completed,p+Vector3(0,1.5,0),Vector3(4.4,0.13,0.16),_timber)
		project_improvements[project_id] = _mesh(completed,"Completed_"+project_id)

func _side_craft(spec: Dictionary) -> void:
	var p := _v(spec.position)
	var w := float(spec.size[0])
	var d := float(spec.size[1])
	var h := float(spec.height)
	var reach := w/2+(0.28 if bool(spec.enterable) else 0.02)
	var key := str(spec.id)
	for side in [-1.0,1.0]:
		var face: float = p.x+side*reach
		_box(_detail,Vector3(face,0.55,p.z),Vector3(0.07,1.10,d-0.5),Color("#986b51"))
		var stones := maxi(4,int(d/0.88))
		for row in range(3):
			for index in range(stones):
				var z := p.z-d/2+(index+0.5)*d/stones
				var tint := _limestone.darkened(0.18+RealismModels.scatter(key+str(row),index)*0.09)
				_box(_detail,Vector3(face+side*0.055,0.13+row*0.24,z),Vector3(0.11,0.21,d/stones-0.03),tint)
		var windows := maxi(2,int(d/4.8))
		for index in range(windows):
			var z := p.z-d/2+(index+0.5)*d/windows
			var y := h-1.4
			_box(_detail,Vector3(face+side*0.055,y,z),Vector3(0.11,1.3,1.05),_timber.darkened(0.28))
			for board in range(5):
				_box(_detail,Vector3(face+side*0.13,y,z-0.48+(board+0.5)*0.192),Vector3(0.065,1.2,0.175),_timber.lightened(RealismModels.scatter(key+str(index),board)*0.13))
			for end in [-1.0,1.0]:
				_box(_detail,Vector3(face+side*0.12,y+end*0.69,z),Vector3(0.21,0.13,1.35),_limestone)
				_box(_detail,Vector3(face+side*0.17,y+end*0.37,z),Vector3(0.04,0.065,0.99),Color("#544c3d"))
			_box(_detail,Vector3(face+side*0.23,y-0.75,z),Vector3(0.48,0.12,1.38),_limestone)
		# Broken limewash shows quieter unevenness below the closed shutters.
		for index in range(12):
			var z := p.z+(RealismModels.scatter(key,index+930)-0.5)*(d-1)
			var y := 0.95+RealismModels.scatter(key,index+890)*(h-2.7)
			var tint: Color = _plaster[int(spec.palette)].darkened(0.045+RealismModels.scatter(key,index+31)*0.045)
			_box(_detail,Vector3(face+side*0.043,y,z),Vector3(0.016,0.10+RealismModels.scatter(key,index+980)*0.45,0.3+RealismModels.scatter(key,index+650)*0.45),tint)

func _waterworks_geometry() -> void:
	var p := _v(layout.water_position)
	var work := RealismModels.new()
	# Work rails attach to the existing basin outline, leaving its approach free.
	for side in [-1.0,1.0]:
		work.rod(p+Vector3(side*2.15,0,-1.9),p+Vector3(side*2.15,2.2,-1.9),0.055,_timber)
		work.rod(p+Vector3(side*2.15,0,1.9),p+Vector3(side*2.15,1.7,1.9),0.055,_timber)
		work.rod(p+Vector3(side*2.15,1.5,-1.9),p+Vector3(side*2.15,1.5,1.9),0.04,_timber)
	_box(work,p+Vector3(0,1.16,0),Vector3(4.6,0.08,0.47),_timber)
	for index in range(4):
		_box(work,p+Vector3(-0.7+index*0.47,1.28,0),Vector3(0.36,0.2,0.42),_limestone.lightened(0.08))
	project_scaffolds["clean_water"] = _mesh(work,"WaterworksRepairs")
	var renewed := RealismModels.new()
	for side in [-1.0,1.0]:
		_box(renewed,p+Vector3(side*2.01,0.85,0),Vector3(0.44,0.17,3.95),_limestone.lightened(0.20))
		_box(renewed,p+Vector3(0,0.85,side*1.81),Vector3(4.6,0.17,0.44),_limestone.lightened(0.20))
		_box(renewed,p+Vector3(side*2.01,1.12,0),Vector3(0.58,0.045,4.03),_limestone.lightened(0.15))
		_box(renewed,p+Vector3(0,1.12,side*1.81),Vector3(4.61,0.045,0.58),_limestone.lightened(0.15))
	_box(renewed,p+Vector3(0,2.48,-1.18),Vector3(0.64,0.48,0.06),Color("#a48e55"))
	renewed.rod(p+Vector3(0,1.72,-1.21),p+Vector3(0,1.72,-0.69),0.12,Color("#92854f"))
	renewed.ellipsoid(p+Vector3(0,1.72,-0.67),Vector3(0.145,0.14,0.05),Color("#92854f"))
	project_improvements["clean_water"] = _mesh(renewed,"RestoredWaterBasin")

func _fortress_detail() -> void:
	var e:=float(layout.walls.half_extent)
	var h:=float(layout.walls.height)
	var width:=float(layout.walls.gate_width)
	# Deep, dressed arch voussoirs have an actual curved silhouette. Recessed
	# joints and alternating headers keep the gatehouse from reading as cubes.
	var radius:=width*0.5
	var center:=Vector3(0,3.4,e)
	for i in range(19):
		var a:=PI*float(i)/19+0.008
		var b:=PI*float(i+1)/19-0.008
		var color:=_limestone.darkened(RealismModels.scatter("gate-arch",i)*0.13)
		var inner_a:=Vector3(cos(a)*radius,sin(a)*radius*0.57,0)
		var inner_b:=Vector3(cos(b)*radius,sin(b)*radius*0.57,0)
		var outer_a:=Vector3(cos(a)*(radius+0.65),sin(a)*(radius*0.57+0.65),0)
		var outer_b:=Vector3(cos(b)*(radius+0.65),sin(b)*(radius*0.57+0.65),0)
		for side in [-1.0,1.0]:
			var face:=center+Vector3(0,0,side*1.44)
			_arch_face(face+inner_a,face+inner_b,face+outer_b,face+outer_a,Vector3(0,0,side),color)
		var inside:=Vector3(-cos((a+b)*0.5),-sin((a+b)*0.5)/0.57,0).normalized()
		_arch_face(center+inner_a+Vector3(0,0,-1.44),center+inner_b+Vector3(0,0,-1.44),center+inner_b+Vector3(0,0,1.44),center+inner_a+Vector3(0,0,1.44),inside,color.darkened(0.12))
	_box(_detail,Vector3(0,5.93,e+0.36),Vector3(width,1.06,0.38),_timber)
	for side in [-1.0,1.0]:
		# Buttresses stay entirely within the already blocked curtain footprint.
		for z in range(-60,61,20):
			_box(_detail,Vector3(side*(e-1.12),h*0.45,z),Vector3(0.4,h*0.9,1.15),_limestone.darkened(0.14))
			_box(_detail,Vector3(side*(e-1.12),0.23,z),Vector3(0.6,0.46,1.6),_limestone)
		var tower:=Vector3(side*(width/2+3),0,e)
		for floor_y in [3.1,6.0]:
			for face_side in [-1.0,1.0]:
				var p:=tower+Vector3(0,floor_y,face_side*2.67)
				_box(_detail,p,Vector3(0.22,1.05,0.035),Color("#33312b"))
				for jamb in [-1.0,1.0]:_box(_detail,p+Vector3(jamb*0.22,0,0.055),Vector3(0.20,1.32,0.16),_limestone)
				_box(_detail,p+Vector3(0,-0.59,0.09),Vector3(0.7,0.17,0.27),_limestone)
	var brace:=RealismModels.new()
	var iron:=Color("#494b44")
	for side in [-1.0,1.0]:
		for y in [1.1,2.8,4.8]:
			_box(brace,Vector3(side*width/4,y,e-0.15),Vector3(width/2-0.25,0.21,0.19),iron)
			for rivet in range(7):brace.ellipsoid(Vector3(side*width/4-width/4+0.35+rivet*(width/2-0.7)/6,y,e-0.27),Vector3(0.05,0.05,0.03),iron.lightened(0.2))
		brace.rod(Vector3(side*0.4,0.7,e-0.2),Vector3(side*(width/2-0.35),5.0,e-0.2),0.12,_timber)
	gate_reinforcement=_mesh(brace,"CompletedGateReinforcement")
	var stores:=RealismModels.new()
	for i in range(5):
		var p:=Vector3(59+i*0.48,0.55,-6)
		stores.rod(p-Vector3.UP*0.45,p+Vector3.UP*0.45,0.18,_timber)
		stores.rod(p+Vector3.UP*0.45,p+Vector3.UP*0.5,0.20,_tile)
	fire_stores=_mesh(stores,"PreparedFireArrowStores")

func _arch_face(a: Vector3,b: Vector3,c: Vector3,d: Vector3,normal: Vector3,color: Color) -> void:
	# Clockwise front faces, explicit outward normals; never two coplanar
	# opposite triangles, which fight for depth and create black wedges.
	var points: Array=[a,c,b,a,d,c] if (b-a).cross(c-a).dot(normal)>0 else [a,b,c,a,c,d]
	_detail.surface.set_color(color)
	_detail.surface.set_normal(normal)
	for point in points:
		_detail.surface.add_vertex(point)
		_detail.vertex_count+=1
