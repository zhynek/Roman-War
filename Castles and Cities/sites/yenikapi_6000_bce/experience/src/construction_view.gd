extends Node3D
## Derived construction fabric. All work and payment remain in the saved queue.
const ReadModel=preload("res://src/project_presentation.gd")
var model=ReadModel.new()
var world
var sites: Dictionary={}
var badges: Dictionary={}
var alerts: Node3D
var _alert_key: String=""
var selected: String=""
var connections: Node3D
var _state: Dictionary={}
var _rules
var _forecast: Dictionary={}

func _exit_tree() -> void:clear()
func clear() -> void:
	if is_instance_valid(world):
		for id in sites:_remove(id)
	sites.clear()
func _remove(id: String) -> void:
	var owner: String="construction_"+id
	if world.object_nodes.has(owner):world.object_nodes[owner].free();world.object_nodes.erase(owner)
	world.solids=world.solids.filter(func(s):return s.owner!=owner)
	if badges.has(id):badges[id].free();badges.erase(id)

func refresh(state: Dictionary,rules,w,forecast: Dictionary={}) -> void:
	if world!=w:clear();world=w
	_state=state;_rules=rules;_forecast=forecast
	var retained: Array=[]
	for item in state.queue:
		var d: Dictionary=model.describe(state,rules,item.id,forecast)
		retained.append(item.id)
		var key: String=JSON.stringify([d.stage,d.paid_wood,d.paid_blanks,world.revision])
		if not sites.has(item.id) or sites[item.id].key!=key:
			_remove(item.id)
			var site: Dictionary=build_site(item.id,d,rules,world)
			site.key=key;sites[item.id]=site
		_update_badge(item.id,d)
	for id in sites.keys():
		if id not in retained:_remove(id);sites.erase(id)
	_asset_alerts()
	select(selected)

static func building_record(id: String,rules) -> Dictionary:
	for change in rules.projects[id].changes:
		for record in change.after:
			if record.kind=="building":return record
	return {}

static func build_site(id: String,d: Dictionary,rules,w) -> Dictionary:
	var spec: Dictionary=rules.projects[id]
	var b: Dictionary=building_record(id,rules)
	var at:=Vector3(spec.at[0],w.floor_height(spec.at[0],spec.at[1]),spec.at[1])
	var yaw_: float=0
	var half:=Vector2(2,1.5)
	if not b.is_empty():
		at=w.building_position(b);yaw_=deg_to_rad(float(b.yaw));half=Vector2(b.size[0],b.size[1])*.5
	if d.treatment=="adapt":
		# Put repair materials alongside the occupied room, never over its walls,
		# furnishings, entrance or accommodation relationship.
		if b.is_empty():
			for existing in w.buildings:
				if existing.id=="yk_house_06":b=existing;break
		if not b.is_empty():
			var side: float=-1.0 if id=="living_shared_room" else 1.0
			at=w.building_position(b,Vector3(side*(float(b.size[0])*.5+1.0),0,-.6));yaw_=deg_to_rad(float(b.yaw))
			half=Vector2(.6,1.1)
	elif d.treatment in ["repair","equipment","path"]:
		# Edge work leaves the actual pedestrian route usable.
		at+=Vector3(3.0,0,-4.5 if id.ends_with("_prepare") else -2.0);at.y=w.floor_height(at.x,at.z);half=Vector2(1.0,1.1)
	elif d.treatment=="ground":half=Vector2(2.4,2.0)
	var owner: String="construction_"+id
	w._begin(owner,at,yaw_)
	if d.treatment=="building" and not b.is_empty():_new_building(w,b,int(d.stage))
	else:_work_surface(w,d,half)
	# Payment is a commitment, not a delivery count. The represented quantity
	# is bounded for clarity; the exact number always comes from the read model.
	for i in range(mini(8,int(d.paid_wood))):
		var p:=Vector3(half.x-.45,.13+float(i/3)*.12,-half.y+.25+float(i%3)*.18)
		w._geo.rod(p,p+Vector3(0,0,.8),.055,"wood_light",.045,6)
	if int(d.paid_wood)>0:w._solid_box(Vector3(half.x-.28,.22,-half.y+.8),Vector3(.6,.44,1.3),"wood")
	for i in range(mini(4,int(d.paid_blanks))):
		w._geo.box(Vector3(half.x-.9,.15+float(i)*.09,-half.y+.65),Vector3(.32,.07,.6),"mat")
	w._finish()
	return {"owner":owner,"at":at,"yaw":yaw_,"half":half,"stage":d.stage,"treatment":d.treatment}

static func _new_building(w,b: Dictionary,stage: int) -> void:
	var x: float=float(b.size[0])*.5
	var z: float=float(b.size[1])*.5
	var h: float=float(b.wall_height)
	# Marks remain shallow. From foundations onward supports have matching solids.
	for side in [-1,1]:
		w._geo.box(Vector3(side*x,.035,0),Vector3(.09,.04,z*2),"wood_light")
		w._geo.box(Vector3(0,.035,side*z),Vector3(x*2,.04,.09),"wood_light")
	if stage==0:return
	for side in [-1,1]:
		w._solid_box(Vector3(side*x,.10,0),Vector3(.22,.20,z*2),"stone")
		w._solid_box(Vector3(side*(x+.65)*.5,.10,z),Vector3(x-.65,.20,.22),"stone")
	w._solid_box(Vector3(0,.1,-z),Vector3(x*2,.2,.22),"stone")
	for sx in [-1,1]:
		for sz in [-1,1]:w._solid_box(Vector3(sx*x,h*.5,sz*z),Vector3(.15,h,.15),"wood")
	if stage<2:return
	for side in [-1,1]:
		w._geo.rod(Vector3(side*x,h,-z),Vector3(side*x,h,z),.085,"wood",.075,8)
		w._geo.rod(Vector3(-x,h,side*z),Vector3(x,h,side*z),.085,"wood",.075,8)
		w._solid_box(Vector3(side*x,h*.23,0),Vector3(.18,h*.46,z*2),"daub")
	w._solid_box(Vector3(0,h*.23,-z),Vector3(x*2,h*.46,.18),"daub")
	for side in [-1,1]:
		for row in range(6):w._geo.rod(Vector3(side*x,.3+row*.27,-z),Vector3(side*x,.3+row*.27,z),.018,"wood_light",.018,5)
	if stage<3:return
	var ridge: float=h+float(b.roof_rise)
	for step in range(5):
		var zz: float=lerpf(-z,z,float(step)/4)
		w._geo.rod(Vector3(-x-.25,h,zz),Vector3(0,ridge,zz),.055,"wood",.045,6)
		w._geo.rod(Vector3(0,ridge,zz),Vector3(x+.25,h,zz),.055,"wood",.045,6)
	# Incomplete roof coverage remains visibly open; completion uses normal fabric.
	w._geo.quad(Vector3(-x-.25,h,-z-.2),Vector3(0,ridge,-z-.2),Vector3(0,ridge,z*.2),Vector3(-x-.25,h,z*.2),"thatch")
	w._geo.quad(Vector3(0,ridge,-z-.2),Vector3(x+.25,h,-z-.2),Vector3(x+.25,h,-z*.15),Vector3(0,ridge,-z*.15),"thatch_light")

static func _work_surface(w,d: Dictionary,half: Vector2) -> void:
	var stage: int=int(d.stage)
	w._geo.box(Vector3(0,.025,0),Vector3(half.x*1.6,.03,half.y*1.6),"mat" if d.treatment in ["adapt","equipment","repair"] else "path")
	for i in range(stage+1):
		var x: float=-half.x*.65+i*half.x*.4
		w._geo.box(Vector3(x,.065,0),Vector3(.14,.08,half.y*1.25),"wood_light")
	if stage>=1:
		w._solid_box(Vector3(-half.x*.55,.35,-half.y*.4),Vector3(.18,.7,.18),"wood")
		w._solid_box(Vector3(half.x*.55,.35,-half.y*.4),Vector3(.18,.7,.18),"wood")
		w._geo.box(Vector3(0,.72,-half.y*.4),Vector3(half.x*1.25,.1,.32),"wood_light")
	if stage>=2:
		for i in range(4):w._geo.rod(Vector3(-half.x*.4+i*.17,.80,-half.y*.4),Vector3(-half.x*.4+i*.17,.80,half.y*.4),.035,"wood_light",.025,6)
	if stage>=3:
		for i in range(3):w._geo.box(Vector3(-half.x*.3+i*.2,.88,-half.y*.25),Vector3(.12,.04,.5),"mat")

func _update_badge(id: String,d: Dictionary) -> void:
	var label: Label3D
	if badges.has(id):label=badges[id]
	else:
		label=Label3D.new();label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.font_size=27;label.pixel_size=.012;label.outline_size=6;add_child(label);badges[id]=label
	var symbols: Dictionary={"active":"⚒","paused":"Ⅱ","none":"○","labor":"♙","blocked":"!"}
	label.text=symbols.get(d.status,"!")+" "+model.copy.ui.get(d.status,d.status)
	if selected==id:label.text+="\n"+d.stage_label+" · %d/%d"%[d.progress,d.total]
	label.position=sites[id].at+Vector3(0,5.0 if d.treatment=="building" else 1.5,0)
	label.modulate=Color("d7bb83") if d.status in ["paused","blocked","labor","none"] else Color("c3d7b0")
	label.visibility_range_end=100 if selected==id or d.status!="active" else 28

func select(id: String) -> void:
	selected=id
	if is_instance_valid(connections):connections.free()
	connections=Node3D.new();add_child(connections)
	for project in sites:
		_update_badge(project,model.describe(_state,_rules,project,_forecast))
	if id=="" or _rules==null or not _rules.projects.has(id):return
	var s: Dictionary=sites.get(id,{})
	if s.is_empty():
		var b: Dictionary=building_record(id,_rules)
		var at: Array=_rules.projects[id].at
		s={"at":Vector3(at[0],world.floor_height(at[0],at[1]),at[1]),"half":Vector2(2,2),"yaw":0.0}
		if not b.is_empty():s={"at":world.building_position(b),"half":Vector2(b.size[0],b.size[1])*.5,"yaw":deg_to_rad(float(b.yaw))}
	var geo=preload("res://src/geometry.gd").new(world.materials)
	var basis:=Basis(Vector3.UP,float(s.yaw))
	for side in [-1,1]:
		geo.rod(s.at+basis*Vector3(side*(s.half.x+.2),.09,-s.half.y-.2),s.at+basis*Vector3(side*(s.half.x+.2),.09,s.half.y+.2),.045,"mat",.045,5)
		geo.rod(s.at+basis*Vector3(-s.half.x-.2,.09,side*(s.half.y+.2)),s.at+basis*Vector3(s.half.x+.2,.09,side*(s.half.y+.2)),.045,"mat",.045,5)
	# Trace actual authored connection curves; helpful investments use UI plus signs.
	var path_ids: Array=[]
	if _rules.land.proposals.has(id):
		path_ids=[_rules.land.sites[_rules.land.proposals[id].site].connection]
	for record in world.data.objects:
		if record.id not in path_ids or record.kind!="path":continue
		for i in range(1,record.points.size()):
			var a: Array=record.points[i-1];var b: Array=record.points[i]
			geo.rod(Vector3(a[0],world.floor_height(a[0],a[1])+.09,a[1]),Vector3(b[0],world.floor_height(b[0],b[1])+.09,b[1]),.06,"mat",.06,5)
	var node:=MeshInstance3D.new();node.mesh=geo.finish();connections.add_child(node)

func pick(origin: Vector3,direction: Vector3) -> String:
	var best: float=180
	var hit_id: String=""
	for id in sites:
		var node: MeshInstance3D=world.object_nodes[sites[id].owner]
		var inv: Transform3D=node.global_transform.affine_inverse()
		var a: Vector3=inv*origin;var dir: Vector3=inv.basis*direction
		if node.mesh.get_aabb().intersects_segment(a,a+dir*best)==null:continue
		var faces: PackedVector3Array=node.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var hit: Variant=Geometry3D.ray_intersects_triangle(a,dir,faces[i],faces[i+1],faces[i+2])
			if hit!=null:
				var distance: float=origin.distance_to(node.global_transform*hit)
				if distance<best:best=distance;hit_id=id
	# A real wall between the observer and a site occludes it.
	if hit_id!="":
		for box in world.solids:
			if box.owner==sites[hit_id].owner:continue
			var basis:=Basis(Vector3.UP,-float(box.yaw));var a: Vector3=basis*(origin-box.at)
			var hit: Variant=AABB(-box.size*.5,box.size).intersects_segment(a,a+basis*direction*best)
			if hit!=null and a.distance_to(hit)<best-.02:return ""
	return hit_id

func _asset_alerts() -> void:
	var records: Array=[]
	if _rules.assets.active(_state):
		for asset in _rules.assets.content.assets:
			if int(_state.assets.conditions[asset.id])<int(_rules.assets.balance.condition_threshold):records.append([asset.id,"repair",asset.at])
	var incident: Dictionary=_rules.incidents.current(_state)
	if not incident.is_empty() and int(incident.known)>=0 and int(incident.recovered)<0:
		var spec: Dictionary=_rules.incidents.specs[incident.id]
		records.append([spec.id,"warning" if incident.outcome.is_empty() else "repair",spec.at])
	var key: String=JSON.stringify(records)
	if key==_alert_key:return
	_alert_key=key
	if is_instance_valid(alerts):alerts.free()
	alerts=Node3D.new();add_child(alerts)
	for record in records:
		var label:=Label3D.new();label.text=("! " if record[1]=="warning" else "⚒ ")+model.copy.ui[record[1]];label.font_size=27;label.pixel_size=.014;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.outline_size=6;label.modulate=Color("e7bd8a")
		label.position=Vector3(record[2][0],world.floor_height(record[2][0],record[2][1])+4.7,record[2][1]);alerts.add_child(label)

func _process(_delta: float) -> void:
	# Outdoor status text should not loom through an entrance during room visits.
	# This changes visibility only; mesh/picking and simulation records stay put.
	if not is_instance_valid(world):return
	var camera: Camera3D=get_viewport().get_camera_3d()
	if camera==null:return
	var indoors: bool=false
	for b in world.buildings:
		var local: Vector3=Basis(Vector3.UP,-deg_to_rad(float(b.yaw)))*(camera.global_position-world.building_position(b))
		if absf(local.x)<float(b.size[0])*.5 and absf(local.z)<float(b.size[1])*.5 and local.y<float(b.wall_height)+float(b.roof_rise) and local.y>0:
			indoors=true;break
	for badge in badges.values():badge.visible=not indoors
	if is_instance_valid(alerts):alerts.visible=not indoors
