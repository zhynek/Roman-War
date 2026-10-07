extends Node3D
## Portable interpretive plans in existing space; selection has no simulation effect.
const ReadModel=preload("res://src/project_presentation.gd")
var model=ReadModel.new()
var short_labels: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/visual_commands.json")).project_labels
var world
var building: Dictionary={}
var selected: String=""
var page: int=0
var project_ids: Array=[]
var targets: Array=[]
var owners: Array=[]
var _key: String=""
var _easel_key: String=""
var _state: Dictionary={}
var _rules
var _forecast: Dictionary={}
var labels: Node3D

func _exit_tree() -> void:clear()
func clear() -> void:
	if is_instance_valid(world):
		for id in owners:
			if world.object_nodes.has(id):world.object_nodes[id].free();world.object_nodes.erase(id)
		world.solids=world.solids.filter(func(s):return s.owner not in owners)
	owners.clear();targets.clear();_key="";_easel_key=""
	if is_instance_valid(labels):labels.free()

func refresh(state: Dictionary,rules,w,forecast: Dictionary={}) -> void:
	if world!=w:clear();world=w
	_state=state;_rules=rules;_forecast=forecast
	building={}
	for b in w.buildings:
		if b.id==model.copy.room.building:building=b;break
	if building.is_empty():return
	project_ids=model.ids(state,rules)
	if selected not in project_ids:selected=project_ids[0] if not project_ids.is_empty() else ""
	page=clampi(page,0,maxi(0,(project_ids.size()-1)/int(model.copy.room.page_size)))
	var entries: Array=[]
	for id in page_ids():
		var d: Dictionary=model.describe(state,rules,id,forecast)
		entries.append([id,d.stage,d.status,d.progress])
	var key: String=JSON.stringify([world.revision,page,entries,selected])
	if key!=_key:
		for id in owners.duplicate():
			if not id.begins_with("planning_token_"):continue
			if world.object_nodes.has(id):world.object_nodes[id].free();world.object_nodes.erase(id)
			owners.erase(id)
		targets=targets.filter(func(t):return t.id=="easel")
		if is_instance_valid(labels):labels.free()
		_key=key;labels=Node3D.new();add_child(labels)
		_board(entries)
	_update_easel()

func page_ids() -> Array:
	var size_: int=int(model.copy.room.page_size)
	return project_ids.slice(page*size_,mini(project_ids.size(),(page+1)*size_))

func point(local: Vector3) -> Vector3:return world.building_position(building,local)
func board_center() -> Vector3:
	var a: Array=model.copy.room.board_at;return point(Vector3(a[0],a[1],a[2]))
func easel_center() -> Vector3:
	var a: Array=model.copy.room.easel_at;return point(Vector3(a[0],a[1],a[2]))
func _begin(id: String) -> void:
	owners.append(id);world._begin(id,world.building_position(building),deg_to_rad(float(building.yaw)))
func _board(entries: Array) -> void:
	var a: Array=model.copy.room.board_at;var center:=Vector3(a[0],a[1],a[2])
	if not world.object_nodes.has("planning_board"):
		_begin("planning_board")
		world._solid_box(center,Vector3(1.76,1.18,.07),"wood_dark")
		world._geo.box(center+Vector3(0,0,.045),Vector3(1.70,1.12,.03),"mat")
		# Curved settlement connections and home tokens form a miniature layout.
		for i in range(3):world._geo.rod(center+Vector3(-.8+i*.8,-.53,.067),center+Vector3(-.8+i*.8,.53,.067),.008,"wood_light",.008,4)
		world._finish()
	for i in range(entries.size()):
		var e: Array=entries[i];var id: String=e[0]
		var local: Vector3=center+Vector3(-.42+(i%2)*.84,.40-float(i/2)*.265,.084)
		_plan_object("planning_token_"+id,local,Vector2(.77,.23),id,false)
		_text(str(i+1)+" · "+short_labels.get(id,_rules.projects[id].title),point(local+Vector3(0,.07,.025)),.0025,16)
		var d: Dictionary=model.describe(_state,_rules,id,_forecast)
		_text(_status(d)+"  %d/%d"%[d.progress,d.total],point(local+Vector3(0,-.07,.035)),.0022,14)
		_target(id,local,Vector3(.77,.23,.06))
	_text(model.copy.ui.board,point(center+Vector3(0,.7,.05)),.0012,22)

func _status(d: Dictionary) -> String:
	return ("Ⅱ " if d.status=="paused" else ("✓ " if d.complete else ("! " if d.status in ["blocked","none","labor"] else "")))+model.copy.ui[d.status]

func _plan_object(owner: String,at: Vector3,size_: Vector2,id: String,easel: bool) -> void:
	_begin(owner)
	var d: Dictionary=model.describe(_state,_rules,id,_forecast)
	world._geo.box(at,Vector3(size_.x,size_.y,.022),"daub_light" if id==selected else "daub")
	var scale_: float=size_.x
	var base: Vector3=at+Vector3(0,-size_.y*.06,.022)
	if d.treatment in ["building","adapt"]:
		var width: float=scale_*.33;var h: float=size_.y*(.28 if easel else .18)
		for side in [-1,1]:world._geo.rod(base+Vector3(side*width,-h,0),base+Vector3(side*width,h,0),.008,"wood_dark",.008,4)
		world._geo.rod(base+Vector3(-width,-h,0),base+Vector3(width,-h,0),.008,"wood_dark",.008,4)
		world._geo.rod(base+Vector3(-width,h,0),base+Vector3(0,h*1.7,0),.01,"wood_dark",.01,4)
		world._geo.rod(base+Vector3(0,h*1.7,0),base+Vector3(width,h,0),.01,"wood_dark",.01,4)
	else:
		for i in range(3):world._geo.rod(base+Vector3(-scale_*.3,-size_.y*.23+i*size_.y*.2,0),base+Vector3(scale_*.3,-size_.y*.23+i*size_.y*.2,0),.009,"wood_dark",.009,4)
	for i in range(4):world._geo.box(at+Vector3(-scale_*.32+i*scale_*.21,-size_.y*.39,.025),Vector3(scale_*.17,.018,.012),"leaf_light" if i<int(d.stage) else "wood_dark")
	if d.paused:
		for side in [-1,1]:world._geo.box(at+Vector3(side*.025,0,.03),Vector3(.015,size_.y*.35,.02),"pottery_red")
	world._finish()
	if easel:_target("easel",at,Vector3(size_.x,size_.y,.08));_orient_easel(owner,at)

func _update_easel() -> void:
	if selected=="":return
	var d: Dictionary=model.describe(_state,_rules,selected,_forecast)
	var key: String=JSON.stringify([selected,d.stage,d.status,d.progress,d.crew,d.work])
	if key==_easel_key:return
	_easel_key=key
	for id in ["planning_easel_plan"]:
		if world.object_nodes.has(id):world.object_nodes[id].free();world.object_nodes.erase(id)
		world.solids=world.solids.filter(func(s):return s.owner!=id)
		owners.erase(id)
	targets=targets.filter(func(t):return t.id!="easel")
	var a: Array=model.copy.room.easel_at;var center:=Vector3(a[0],a[1],a[2])
	if not world.object_nodes.has("planning_easel"):
		_begin("planning_easel")
		for side in [-1,1]:world._solid_box(center+Vector3(side*.28,-.30,-.04),Vector3(.045,1.6,.045),"wood")
		world._solid_box(center,Vector3(.68,.90,.06),"wood_dark")
		world._finish()
		_orient_easel("planning_easel",center)
	_plan_object("planning_easel_plan",center+Vector3(0,0,.047),Vector2(.62,.82),selected,true)
	# Easel title lives in the HUD too, so its tiny physical text is optional.

func _target(id: String,local: Vector3,size_: Vector3) -> void:
	targets.append({"id":id,"at":point(local),"size":size_,"yaw":deg_to_rad(float(building.yaw))})

func _text(text_: String,at: Vector3,pixel: float,font: int) -> void:
	var label:=Label3D.new();label.text=text_;label.position=at;label.rotation.y=deg_to_rad(float(building.yaw));label.font_size=font;label.pixel_size=pixel;label.modulate=Color("f8ecd1");label.outline_size=2;labels.add_child(label)

func choose(id: String) -> void:
	if id not in project_ids:return
	selected=id;refresh(_state,_rules,world,_forecast)
func turn_page(delta: int) -> void:
	page=posmod(page+delta,maxi(1,ceili(float(project_ids.size())/int(model.copy.room.page_size))))
	refresh(_state,_rules,world,_forecast)

func pick(origin: Vector3,direction: Vector3) -> String:
	var best: float=12;var selected_hit: String=""
	for target in targets:
		var basis:=Basis(Vector3.UP,-float(target.yaw));var a: Vector3=basis*(origin-target.at)
		var hit: Variant=AABB(-target.size*.5,target.size).intersects_segment(a,a+basis*direction*best)
		if hit!=null:
			var distance: float=a.distance_to(hit)
			if distance<best:best=distance;selected_hit=target.id
	if selected_hit!="":
		for box in world.solids:
			if str(box.owner).begins_with("planning_"):continue
			var basis:=Basis(Vector3.UP,-float(box.yaw));var a: Vector3=basis*(origin-box.at)
			var hit: Variant=AABB(-box.size*.5,box.size).intersects_segment(a,a+basis*direction*best)
			if hit!=null and a.distance_to(hit)<best-.03:return ""
	return selected_hit

func _orient_easel(owner: String,center: Vector3) -> void:
	if owner=="planning_easel_plan":center-=Vector3(0,0,.047)
	var node: MeshInstance3D=world.object_nodes[owner]
	var local_basis:=Basis(Vector3.UP,PI*.5)
	var building_basis:=Basis(Vector3.UP,deg_to_rad(float(building.yaw)))
	# Mesh was authored in building-local coordinates; rotate around its own center.
	node.position=point(center)-building_basis*local_basis*center
	node.rotation.y=deg_to_rad(float(building.yaw))+PI*.5
	for solid in world.solids:
		if solid.owner!=owner:continue
		solid.at=point(center)+Basis(Vector3.UP,PI*.5)*(solid.at-point(center));solid.yaw+=PI*.5
	if owner=="planning_easel_plan":
		for target in targets:
			if target.id=="easel":target.at=point(center)+Basis(Vector3.UP,PI*.5)*(target.at-point(center));target.yaw+=PI*.5
