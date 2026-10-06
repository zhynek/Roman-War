extends Node3D
const Village = preload("res://src/village.gd")
var data: Dictionary
var world
var camera: Camera3D
var hud: CanvasLayer
var ready_for_capture: bool = false
var flying: bool = false
var yaw: float = 0.0
var pitch: float = 0.0
var flight_speed: float = 12.0
var info: PanelContainer
var note: Label
var mode_label: Label
var location_label: Label
var status: Label
var campaign
var campaign_view
var campaign_mode: bool = false
var reference_data: Dictionary
var _fabric_key: String = ""
var _look_drag: bool = false
var _selected: String = ""
var _update_accum: float = 0.0
var _save_path: String = "user://early_settlement_view.json"

func _ready() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string("res://data/settlement.json"))
	reference_data=data.duplicate(true)
	world=Village.new()
	add_child(world)
	world.build(data)
	_environment()
	camera=Camera3D.new()
	camera.near=.045
	camera.far=2400
	camera.fov=70
	add_child(camera)
	camera.current=true
	_interface()
	visit(0)
	ready_for_capture=true

func _environment() -> void:
	var env:=Environment.new()
	env.background_mode=Environment.BG_SKY
	var sky:=Sky.new()
	var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("7198b5")
	sky_material.sky_horizon_color=Color("bdcbd0")
	sky_material.ground_horizon_color=Color("bdcbd0")
	sky_material.ground_bottom_color=Color("696c56")
	sky_material.sun_angle_max=3
	sky.sky_material=sky_material
	env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("c2d0df")
	env.ambient_light_energy=.4
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure=.78
	env.ssao_enabled=true
	env.ssao_radius=1.0
	env.ssao_intensity=1.2
	env.fog_enabled=true
	env.fog_density=.00075
	env.fog_light_color=Color("b0bdc4")
	env.fog_sun_scatter=.18
	var we:=WorldEnvironment.new()
	we.environment=env
	add_child(we)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-43,-38,0)
	sun.light_color=Color("fff4e4")
	sun.light_energy=1.1
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=220
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)

func _style() -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=Color(.09,.105,.095,.94)
	box.border_color=Color("797963")
	box.set_border_width_all(1)
	box.set_content_margin_all(14)
	box.set_corner_radius_all(5)
	return box

func _label(text_: String,size: int = 16,color: Color = Color("e8e3d1")) -> Label:
	var label:=Label.new()
	label.text=text_
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label

func _button(text_: String,callback: Callable) -> Button:
	var button:=Button.new()
	button.text=text_
	button.focus_mode=Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size",15)
	button.pressed.connect(callback)
	return button

func _interface() -> void:
	hud=CanvasLayer.new()
	add_child(hud)
	var root:=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	var top:=PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=22;top.offset_right=-22;top.offset_top=20
	top.add_theme_stylebox_override("panel",_style())
	root.add_child(top)
	var column:=VBoxContainer.new()
	top.add_child(column)
	var title_row:=HBoxContainer.new()
	column.add_child(title_row)
	var title:=_label("Y E N İ K A P I",27)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(_label("c. 6000 BCE  /  EARLY SETTLEMENT",17,Color("c5bd96")))
	column.add_child(_label("An interpretive village on Istanbul’s historic peninsula",15,Color("b8bfae")))
	var commands:=HFlowContainer.new()
	column.add_child(commands)
	commands.add_child(_button(data.ui.walk,func(): set_flying(false)))
	commands.add_child(_button(data.ui.fly,func(): set_flying(true)))
	commands.add_child(_button(data.ui.overview,overview))
	commands.add_child(_button(data.ui.evidence,func(): info.visible=not info.visible))
	commands.add_child(_button(data.ui.save,func(): status.text=campaign.copy.reference_save_notice if campaign_mode else (data.ui.saved if save_view(_save_path) else data.ui.missing)))
	commands.add_child(_button(data.ui.load,func(): status.text=campaign.copy.reference_save_notice if campaign_mode else (data.ui.loaded if load_view(_save_path) else data.ui.missing)))
	mode_label=_label("",14,Color("c5bd96"));commands.add_child(mode_label)
	var bottom:=PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left=22;bottom.offset_right=-22;bottom.offset_top=-166;bottom.offset_bottom=-20
	bottom.add_theme_stylebox_override("panel",_style())
	root.add_child(bottom)
	var bc:=VBoxContainer.new()
	bottom.add_child(bc)
	var links:=HFlowContainer.new()
	bc.add_child(links)
	for i in range(data.stops.size()):
		var stop:Dictionary=data.stops[i]
		links.add_child(_button(stop.key+"  "+stop.title,visit.bind(i)))
	location_label=_label("",18);bc.add_child(location_label)
	note=_label("",15,Color("b8bfae"));note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;bc.add_child(note)
	bc.add_child(_label(data.ui.help,14,Color("c5bd96")))
	status=_label("",14);bc.add_child(status)
	info=PanelContainer.new()
	info.position=Vector2(22,165)
	info.custom_minimum_size=Vector2(470,0)
	info.add_theme_stylebox_override("panel",_style())
	root.add_child(info)
	var text:=RichTextLabel.new()
	text.custom_minimum_size=Vector2(470,345)
	text.bbcode_enabled=true
	text.fit_content=true
	text.add_theme_font_size_override("normal_font_size",16)
	text.text="[b]Reading this landscape[/b]\n\n"+data.evidence_note+"\n\n"
	for source in data.sources:
		text.text+="[b]"+("Regional analogy" if source["class"]=="regional_analogy" else "Direct site evidence")+"[/b]\n"+source.claim+"\n[url="+source.url+"]"+source.title+"[/url]\n\n"
	text.text+="The historic plan and the modern shore are not reused. No population is asserted. Nine building models are an authoring choice, not a count of excavated households. Full source ledger is in the editable download."
	text.custom_minimum_size.y=410
	text.fit_content=false
	text.meta_clicked.connect(func(url): OS.shell_open(str(url)))
	info.add_child(text)
	info.hide()
	campaign=load("res://src/governance_panel.gd").new()
	root.add_child(campaign)
	campaign.configure(self)
	commands.add_child(_button(campaign.asset_panel.copy.ui.open,campaign.asset_panel.open))
	commands.add_child(_button(campaign.copy.play,campaign.open))

func set_flying(value: bool) -> void:
	if not value:
		# Flight may end over a roof, water or solid. Find a safe ground spot nearby.
		var candidate:Vector3=camera.position
		var found:bool=not world.blocked(candidate)
		for radius in range(1,21):
			if found:break
			for i in range(24):
				var p:Vector3=camera.position+Vector3(cos(i*TAU/24)*radius,0,sin(i*TAU/24)*radius)
				if not world.blocked(p):candidate=p;found=true;break
		if not found:visit(0);return
		camera.position=candidate
		camera.position.y=world.floor_height(candidate.x,candidate.z)+1.68
	flying=value
	_update_mode()

func _update_mode() -> void:
	if mode_label:mode_label.text=("FLIGHT · %.0f m/s"%flight_speed) if flying else "WALK · 1.68 m eye height"

func visit(index: int) -> void:
	var stop:Dictionary=data.stops[index]
	var p:=Vector3(stop.at[0],world.floor_height(stop.at[0],stop.at[1])+1.68,stop.at[1])
	set_view(p,Vector3(stop.target[0],p.y-.1,stop.target[1]),false)
	_selected=""
	location_label.text=stop.title
	note.text=stop.note
	status.text=""

func set_view(at: Vector3,target: Vector3,flight: bool = true) -> void:
	camera.position=at
	camera.look_at(target,Vector3.UP)
	yaw=camera.rotation.y
	pitch=camera.rotation.x
	flying=flight
	_update_mode()

func overview() -> void:
	set_view(Vector3(66,63,96),Vector3(-7,2,-1))
	location_label.text=data.title
	note.text=data.evidence_note

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			KEY_ESCAPE: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;info.hide();campaign.hide()
			KEY_F: set_flying(not flying)
			KEY_H: hud.visible=not hud.visible
			KEY_I: info.visible=not info.visible
			KEY_0: overview()
			KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8:visit(int(event.keycode)-int(KEY_1))
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:_look_drag=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:flight_speed=clampf(flight_speed*1.4,3,120);_update_mode()
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:flight_speed=clampf(flight_speed/1.4,3,120);_update_mode()
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var point:Vector2=get_viewport().get_visible_rect().size*.5 if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED else event.position
			if campaign_mode and not campaign.visible and not info.visible and is_instance_valid(campaign_view) and is_instance_valid(campaign_view.life):
				var resident:String=pick_resident(camera.project_ray_origin(point),camera.project_ray_normal(point))
				if not resident.is_empty():
					campaign.household_panel.inspect_resident(resident)
					return
			if campaign_mode and campaign.rules.incidents.active(campaign.state):
				var subject: String=campaign_view.incident_view.pick(camera.project_ray_origin(point),camera.project_ray_normal(point))
				var e: Dictionary=campaign.rules.incidents.current(campaign.state)
				if subject.is_empty() and not e.is_empty():
					var object_id: String=world.pick(camera.project_ray_origin(point),camera.project_ray_normal(point)).get("id","")
					if object_id=="yk_house_06":subject="workroom"
					elif object_id.begins_with("yk_store"):subject="store"
					else:
						for home in campaign.rules.content.households:
							if home.building_id==object_id:subject=home.id
					if subject.is_empty():subject=campaign.rules.assets.object_asset(object_id)
				if not subject.is_empty() and not e.is_empty() and subject in campaign.rules.incidents.specs[e.id].subjects:campaign.incident_panel.inspect(subject);return
			if campaign_mode and campaign.rules.living.active(campaign.state):
				var subject: String=campaign_view.living_view.pick(camera.project_ray_origin(point),camera.project_ray_normal(point))
				if subject.is_empty():
					var picked: Dictionary=world.pick(camera.project_ray_origin(point),camera.project_ray_normal(point))
					var object_id: String=picked.get("id","")
					if object_id=="yk_house_06":subject="workroom"
					elif object_id.begins_with("yk_store"):subject="store"
					else:
						for home in campaign.rules.content.households:
							if home.building_id==object_id and campaign.rules.living.subjects.has(home.id):subject=home.id
				if not subject.is_empty():campaign.living_panel.inspect(subject);return
			if campaign_mode and campaign.rules.land.active(campaign.state) and is_instance_valid(campaign_view.land_view):
				var site: String=campaign_view.land_view.pick(camera.project_ray_origin(point),camera.project_ray_normal(point))
				if not site.is_empty():campaign.land_panel.inspect(site);return
			if campaign_mode and campaign.rules.assets.active(campaign.state):
				var asset_hit: String=pick_asset(camera.project_ray_origin(point),camera.project_ray_normal(point))
				if not asset_hit.is_empty():campaign.asset_panel.inspect(asset_hit);return
			var hit:Dictionary=world.pick(camera.project_ray_origin(point),camera.project_ray_normal(point))
			for record in data.objects:
				if record.id==hit.id:
					_selected=record.id
					if campaign_mode and campaign.rules.assets.active(campaign.state):
						var asset_id: String=campaign.rules.assets.object_asset(record.id)
						if not asset_id.is_empty():campaign.asset_panel.inspect(asset_id);return
					location_label.text=record.label
					note.text="Interpretive design · "+record.id+" · revision "+str(record.revision)+". Plan, roof and furnishing positions are authored."
	if event is InputEventMouseMotion and (_look_drag or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED):
		yaw-=event.relative.x*.0025
		pitch=clampf(pitch-event.relative.y*.0025,-1.48,1.48)
		camera.rotation=Vector3(pitch,yaw,0)

func _process(delta: float) -> void:
	if not ready_for_capture:return
	var focus:Control=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is SpinBox:return
	var move:=Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):move.z-=1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):move.z+=1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):move.x-=1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):move.x+=1
	if flying:
		if Input.is_key_pressed(KEY_E):move.y+=1
		if Input.is_key_pressed(KEY_Q):move.y-=1
	if move.length_squared()>0:
		var speed:float=flight_speed if flying else 2.3
		if Input.is_key_pressed(KEY_SHIFT):speed*=3.0 if flying else 1.6
		var direction:Vector3=(camera.basis if flying else Basis(Vector3.UP,yaw))*move.normalized()
		var displacement:Vector3=direction*speed*minf(delta,.1)
		if flying:
			camera.position+=displacement
			camera.position.y=clampf(camera.position.y,.3,600)
			camera.position.x=clampf(camera.position.x,-800,800)
			camera.position.z=clampf(camera.position.z,-800,800)
		else:camera.position=world.walk(camera.position,displacement)
		_selected=""
	_update_accum+=delta
	if _update_accum>.5 and _selected.is_empty():
		_update_accum=0
		var nearest:Dictionary={}
		var distance:float=12
		for stop in data.stops:
			var d:float=Vector2(camera.position.x-stop.at[0],camera.position.z-stop.at[1]).length()
			if d<distance:distance=d;nearest=stop
		if not nearest.is_empty() and not flying:
			location_label.text=nearest.title;note.text=nearest.note

func save_view(path: String) -> bool:
	if campaign_mode:return false
	var record:Dictionary={"format":"yenikapi_view","version":1,"snapshot_id":data.snapshot_id,"scenario_id":null,"position":[camera.position.x,camera.position.y,camera.position.z],"rotation":[pitch,yaw],"navigation":"fly" if flying else "walk","flight_speed":flight_speed}
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(record,"  "));file.close()
	return DirAccess.rename_absolute(path+".tmp",path)==OK

func load_view(path: String) -> bool:
	if campaign_mode:return false
	if not FileAccess.file_exists(path):return false
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>8192:return false
	var record:Variant=JSON.parse_string(file.get_as_text())
	if not record is Dictionary:return false
	if not record.get("format") is String or not record.get("snapshot_id") is String or (not record.get("version") is int and not record.get("version") is float):return false
	if record.get("format")!="yenikapi_view" or record.get("version")!=1 or record.get("snapshot_id")!=data.snapshot_id or record.get("scenario_id")!=null:return false
	if not record.get("navigation") is String or record.get("navigation") not in ["walk","fly"]:return false
	for spec in [["position",3,1000.0],["rotation",2,10000.0]]:
		var values:Variant=record.get(spec[0])
		if not values is Array or values.size()!=spec[1]:return false
		for value in values:
			if (not value is float and not value is int) or not is_finite(float(value)) or absf(float(value))>spec[2]:return false
	var speed:Variant=record.get("flight_speed")
	if (not speed is float and not speed is int) or not is_finite(float(speed)) or float(speed)<3 or float(speed)>120:return false
	var p:=Vector3(record.position[0],record.position[1],record.position[2])
	if p.y<.3 or p.y>600 or absf(p.x)>800 or absf(p.z)>800:return false
	if record.navigation=="walk" and world.blocked(p):return false
	camera.position=p
	pitch=clampf(record.rotation[0],-1.48,1.48);yaw=record.rotation[1]
	camera.rotation=Vector3(pitch,yaw,0)
	flying=record.navigation=="fly"
	if not flying:camera.position.y=world.floor_height(p.x,p.z)+1.68
	flight_speed=speed
	_update_mode()
	return true

func show_campaign(state: Dictionary,rules,force: bool = false) -> void:
	var View=load("res://src/campaign_view.gd")
	var staging: Array=[]
	if rules.land.active(state):
		for item in state.queue:
			if rules.land.proposals.has(item.id) and not rules.land.proposals[item.id].retain:staging.append(item.id)
	staging.sort()
	var empty_supplies: bool=rules.assets.active(state) and state.food==0
	var key: String=JSON.stringify([state.completed,staging,empty_supplies])
	var reference_matches: bool=not campaign_mode and state.completed.is_empty() and staging.is_empty() and not empty_supplies
	if not reference_matches and (force or not campaign_mode or key!=_fabric_key):
		var config: Dictionary=View.snapshot(reference_data,state,rules)
		if not world.update_fabric(config):_rebuild_world(config)
		else:data=config
	_fabric_key=key
	campaign_mode=true
	if not is_instance_valid(campaign_view):
		campaign_view=View.new();add_child(campaign_view)
	campaign_view.refresh(state,rules,world)

func show_reference() -> void:
	if not campaign_mode:return
	if is_instance_valid(campaign_view):campaign_view.free()
	campaign_view=null
	_rebuild_world(reference_data.duplicate(true))
	campaign_mode=false
	_fabric_key=""

func _rebuild_world(config: Dictionary) -> void:
	if is_instance_valid(campaign_view):campaign_view.free();campaign_view=null
	world.free()
	data=config
	world=Village.new();add_child(world);world.build(data)
	if not flying:set_flying(false)

func pick_resident(origin:Vector3,direction:Vector3) -> String:
	if not is_instance_valid(campaign_view) or not is_instance_valid(campaign_view.life):return ""
	var best:float=12.0
	# Respect every rendered wall/furnishing collider, including later additions.
	for box in world.solids:
		var basis:=Basis(Vector3.UP,-float(box.yaw))
		var start:Vector3=basis*(origin-box.at)
		var hit:Variant=AABB(-box.size*.5,box.size).intersects_segment(start,start+basis*direction*best)
		if hit!=null:best=minf(best,start.distance_to(hit))
	var selected:String=""
	for routine in campaign_view.life.routines:
		var node:Node3D=routine.node
		var inverse:Transform3D=node.global_transform.affine_inverse()
		var start:Vector3=inverse*origin
		var finish:Vector3=inverse*(origin+direction*best)
		var height:float=1.76 if routine.moving or routine.pose not in ["kneel","sit","rest"] else 1.30
		var hit:Variant=AABB(Vector3(-.3,0,-.3),Vector3(.6,height,.6)).intersects_segment(start,finish)
		if hit!=null:
			var distance:float=origin.distance_to(node.global_transform*hit)
			if distance<best:best=distance;selected=routine.id
	return selected

func pick_asset(origin: Vector3,direction: Vector3) -> String:
	# Mesh triangle queries share actual drawing transforms, including roofs,
	# new fabric and shared outdoor places. Only run on a click, never per frame.
	var best: float=180.0
	var selected: String=""
	for id in world.object_nodes:
		var asset: String=campaign.rules.assets.object_asset(str(id).trim_prefix("household_interior_"))
		if asset.is_empty():continue
		var node: MeshInstance3D=world.object_nodes[id]
		var inverse: Transform3D=node.global_transform.affine_inverse()
		var a: Vector3=inverse*origin
		var dir: Vector3=inverse.basis*direction
		if node.mesh.get_aabb().intersects_segment(a,a+dir*best)==null:continue
		var faces: PackedVector3Array=node.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var hit: Variant=Geometry3D.ray_intersects_triangle(a,dir,faces[i],faces[i+1],faces[i+2])
			if hit!=null:
				var distance: float=origin.distance_to(node.global_transform*hit)
				if distance<best:best=distance;selected=asset
	return selected
