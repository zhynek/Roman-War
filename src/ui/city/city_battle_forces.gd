class_name RomaCityBattleForces
extends Node3D
## Retained procedural cohorts. Interpolation, marching, attacks and arrows are
## presentation only; authoritative positions/health arrive in snapshots.
const DEFENDER_COLOR := Color("#487d9b")
const ATTACKER_COLOR := Color("#b44935")
var anchors: Dictionary = {}
var groups: Dictionary = {}
var targets: Dictionary = {}
var facing_targets: Dictionary = {}
var _meshes: Dictionary = {}
var _material: ShaderMaterial
var _clock := 0.0
var _last_event := 0
var _effects: Array = []
var _arrows: MeshInstance3D
var siege_visual: RomaCitySiegeVisual
var _paused := false
var _fallen: Array[MeshInstance3D] = []
var _hits: Dictionary = {}
var _visual_health: Dictionary = {}
var _pending_health: Dictionary = {}
var _last_layout: Dictionary = {}
var _last_snapshot: Dictionary = {}
var _last_selected := ""
var _last_selected_ids: Array = []
var moving := false
var soldiers_per_model := 4
signal presentation_changed

func _ready() -> void:
	_material=ShaderMaterial.new()
	_material.shader=preload("res://src/ui/city/battle_soldier.gdshader")
	_arrows=MeshInstance3D.new()
	var ink:=StandardMaterial3D.new()
	ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.vertex_color_use_as_albedo=true
	_arrows.material_override=ink
	add_child(_arrows)
	siege_visual=RomaCitySiegeVisual.new()
	add_child(siege_visual)

func sync(layout: Dictionary, snapshot: Dictionary, selected: String = "", selected_ids: Array = []) -> void:
	if _material==null:return
	_last_layout=layout
	_last_snapshot=snapshot
	_last_selected=selected
	_last_selected_ids=selected_ids
	siege_visual.sync(snapshot)
	_paused=(snapshot.get("paused",false) and snapshot.get("phase", "")!="finished") or snapshot.get("phase", "")=="deployment"
	if int(snapshot.get("tick",0))==0:
		_effects.clear()
		_last_event=0
		for body in _fallen:body.queue_free()
		_fallen.clear()
		_hits.clear()
		_visual_health.clear()
		_pending_health.clear()
	var volley_targets := {}
	var melee_targets := {}
	for event in snapshot.get("events",[]):
		if int(event["id"])>_last_event and event["kind"] in ["volley","fire_volley"]:
			volley_targets[event.get("target","")]=true
		elif int(event["id"])>_last_event and event["kind"]=="clash":
			melee_targets[event.get("target","")]=true
	var retained := {}
	for raw in snapshot.get("formations",[]):
		var f: Dictionary=raw.duplicate()
		f["unit"]=raw["unit"].duplicate()
		var identity:=String(f["id"])
		var actual:=int(f["unit"]["strength_pct"])
		if not _visual_health.has(identity) or int(_visual_health[identity])>int(f["initial_strength"]):
			_visual_health[identity]=actual
			_pending_health.erase(identity)
		if actual<int(_visual_health[identity]):
			if not _pending_health.has(identity):_pending_health[identity]={"due":_clock+(0.8 if volley_targets.has(identity) else (0.32 if melee_targets.has(identity) else 0.0)),"strength":actual}
			_pending_health[identity]["strength"]=actual
		if _pending_health.has(identity) and _clock>=float(_pending_health[identity]["due"]):
			_visual_health[identity]=_pending_health[identity]["strength"]
			_pending_health.erase(identity)
		f["unit"]["strength_pct"]=_visual_health[identity]
		if _pending_health.has(identity):f["routed"]=false
		var id:=String(f["id"])
		_record_losses(f)
		if int(f["unit"]["strength_pct"])<=0 or f.get("routed",false):continue
		retained[id]=true
		var defender: bool=f["side"]=="defender"
		# Only a physically observed role/specialty may change an enemy model.
		# Never resolve a rival's underlying template or hidden equipment here.
		var role:=String(f.get("role","soldier")) if defender or f.get("revealed",false) else "unknown"
		var specialty:=String(f.get("specialty","")) if defender or f.get("revealed",false) else ""
		var shape:=String(f.get("formation","line")) if defender or f.get("revealed",false) else "line"
		var spears:=shape=="phalanx" or specialty=="spear_guard"
		var key:=("own_" if defender else "enemy_")+role+("_"+specialty if specialty!="" else "")+("_spears" if spears else "")
		var color:=DEFENDER_COLOR if defender else ATTACKER_COLOR
		if not _meshes.has(key):
			_meshes[key]=RomaBattleModels.build(color,role,"spear_guard" if spears and specialty=="" else specialty)
		var at:=Vector3.ZERO
		if f.has("position"):
			at=Vector3(float(f["position"][0])/100.0,0.08,float(f["position"][1])/100.0)
		else:
			for node in layout["battle"]["nodes"]:
				if node["id"]==f["node"]:at=Vector3(node["position"][0],0.08,node["position"][1])
		if not groups.has(id):
			var group:=Node3D.new()
			group.name=id
			group.position=at
			add_child(group)
			groups[id]=group
			var troops:=MultiMeshInstance3D.new()
			troops.name="Troops"
			troops.multimesh=MultiMesh.new()
			troops.multimesh.transform_format=MultiMesh.TRANSFORM_3D
			troops.multimesh.use_custom_data=true
			troops.material_override=_material.duplicate()
			group.add_child(troops)
			var b:=RealismModels.new()
			b.rod(Vector3.ZERO,Vector3.UP*3.8,0.035,RealismModels.pigment("#ad914e"))
			b.box(Vector3(0.45,3.2,0),Vector3(0.9,0.8,0.04),color)
			var flag:=MeshInstance3D.new()
			flag.mesh=b.finish()
			flag.material_override=_material
			group.add_child(flag)
			var emblem:=MeshInstance3D.new()
			emblem.name="Ability"
			var badge:=RealismModels.new()
			badge.ellipsoid(Vector3(0,4.05,0),Vector3(0.20,0.22,0.04),RealismModels.pigment("#d4b474",0.7))
			for side in [-1,1]:badge.triangle(Vector3(side*0.06,4.05,0),Vector3(side*0.46,4.26,0),Vector3(side*0.30,3.98,0),RealismModels.pigment("#c4a464",0.7))
			emblem.mesh=badge.finish();emblem.material_override=_material
			group.add_child(emblem)
			var ring:=MeshInstance3D.new()
			ring.name="Selection"
			var torus:=TorusMesh.new()
			torus.inner_radius=1.65
			torus.outer_radius=1.8
			ring.mesh=torus
			var gold:=StandardMaterial3D.new()
			gold.albedo_color=UiStyle.ACCENT
			gold.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			ring.material_override=gold
			ring.position.y=0.1
			group.add_child(ring)
		var group:Node3D=groups[id]
		var troops:MultiMeshInstance3D=group.get_node("Troops")
		# Unobserved enemies use a fixed generic rank: neither template size nor
		# hidden losses may make their silhouette reveal a roster.
		var count:=24
		if defender or f.get("revealed",false):
			count=clampi(ceili(float(f.get("soldiers",120))*float(f["unit"]["strength_pct"])/100.0/soldiers_per_model),1,60)
		var reset_ranks:bool=troops.multimesh.mesh!=_meshes[key] or troops.multimesh.instance_count!=count
		if reset_ranks:
			troops.multimesh.mesh=_meshes[key]
			troops.multimesh.instance_count=count
		group.set_meta("mounted",role=="cavalry")
		group.set_meta("formation",shape)
		group.set_meta("engaged",f.get("engaged",false))
		var contact_distance:=3.4
		if f.get("engaged",false):
			for enemy in snapshot.get("formations",[]):
				if enemy["side"]==f["side"] or not CityBattleSim.active(enemy):continue
				contact_distance=minf(contact_distance,CityBattleNavigation.point(f["position"]).distance_to(CityBattleNavigation.point(enemy["position"]))/100.0)
		group.set_meta("contact_distance",contact_distance)
		_pose_ranks(group,1.0 if reset_ranks or snapshot.get("phase","")!="fighting" else 0.0)
		var mat:=troops.material_override as ShaderMaterial
		mat.set_shader_parameter("walking",1.0 if f.get("moving",false) else 0.0)
		mat.set_shader_parameter("fighting",1.0 if f.get("engaged",false) else 0.0)
		mat.set_shader_parameter("mounted",1.0 if role=="cavalry" else 0.0)
		mat.set_shader_parameter("archer",1.0 if role=="archer" else 0.0)
		mat.set_shader_parameter("spear",1.0 if spears else 0.0)
		mat.set_shader_parameter("bracing",1.0 if shape=="phalanx" or (specialty=="spear_guard" and int(f.get("ability_remaining_ms",0))>0) else 0.0)
		group.get_node("Ability").visible=specialty!="" and int(f.get("ability_remaining_ms",0))>0
		group.set_meta("strength",int(f["unit"]["strength_pct"]))
		group.set_meta("observed",defender or f.get("revealed",false))
		group.get_node("Selection").visible=id==selected or selected_ids.has(id)
		group.visible=not f.get("routed",false)
		var facing:Array=f.get("facing",[0,1000] if defender else [0,-1000])
		facing_targets[id]=atan2(-float(facing[0]),-float(facing[1]))
		if snapshot.get("phase","")!="fighting":
			group.position=at
			group.rotation.y=facing_targets[id]
		targets[id]=at
		anchors[id]=group.position
	for id in groups.keys():
		if not retained.has(id):
			groups[id].queue_free()
			groups.erase(id)
			targets.erase(id)
			facing_targets.erase(id)
			anchors.erase(id)
	for event in snapshot.get("events",[]):
		if int(event["id"])<=_last_event:continue
		_last_event=int(event["id"])
		var volley: bool=event["kind"] in ["volley","fire_volley"]
		_effects.append({"from":Vector3(event["from"][0]/100.0,1.7,event["from"][1]/100.0),"to":Vector3(event["to"][0]/100.0,1.7,event["to"][1]/100.0),"age":0.0,"volley":volley,"fire":event["kind"]=="fire_volley","arc":float(event.get("arc_cm",500))/100.0})
		var source: String=event.get("source", "")
		if volley and groups.has(source):groups[source].set_meta("shot_at",_clock)
		if event["kind"]=="clash":
			if groups.has(source):groups[source].set_meta("strike_at",_clock)
			if groups.has(event.get("target","")):groups[event["target"]].set_meta("block_at",_clock)
	# Fast-forward or loaded retained events must not grow an unbounded FX list.
	while _effects.size()>96:_effects.pop_front()

	if not snapshot.get("active",false):
		_effects.clear()
		_last_event=0

func _process(delta: float) -> void:
	if not visible:return
	if not _paused:_clock+=delta
	for pending in _pending_health.values():
		if _clock>=float(pending["due"]):
			sync(_last_layout,_last_snapshot,_last_selected,_last_selected_ids)
			break
	moving=false
	for id in groups:
		var group:Node3D=groups[id]
		var blend := 0.0 if _paused else 1.0-exp(-maxf(delta,0.0)*15.0)
		group.position=group.position.lerp(targets[id],blend)
		group.rotation.y=lerp_angle(group.rotation.y,float(facing_targets.get(id,group.rotation.y)),blend)
		anchors[id]=group.position
		moving=moving or group.position.distance_to(targets[id])>0.01
		var troop:MultiMeshInstance3D=group.get_node("Troops")
		var mat:=troop.material_override as ShaderMaterial
		mat.set_shader_parameter("clock_time",_clock)
		mat.set_shader_parameter("hit_reaction",maxf(0,1.0-(_clock-float(_hits.get(id,-100)))*2.2))
		mat.set_shader_parameter("shooting",maxf(0,1.0-(_clock-float(group.get_meta("shot_at",-100)))*1.6))
		mat.set_shader_parameter("attack_age",_clock-float(group.get_meta("strike_at",-100)))
		mat.set_shader_parameter("defend_age",_clock-float(group.get_meta("block_at",-100)))
		_pose_ranks(group,0.0 if _paused else 1.0-exp(-delta*9.0))
	var mesh:=ImmediateMesh.new()
	for effect in _effects:
		if not _paused:effect["age"]+=delta
	_effects=_effects.filter(func(e):return e["age"]<(2.5 if e["volley"] else 1.25))
	if not _effects.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for effect in _effects:
			var progress:=minf(1,float(effect["age"])/0.8)
			for i in range(12):
				var offset:=Vector3((i%4-1.5)*0.55,0,(i/4-1)*0.55)
				if effect["volley"] and progress<1.0:
					var a:Vector3=effect["from"].lerp(effect["to"],progress)+offset+Vector3.UP*4.0*float(effect["arc"])*progress*(1.0-progress)
					var tangent:Vector3=(effect["to"]-effect["from"]+Vector3.UP*4.0*float(effect["arc"])*(1.0-2.0*progress)).normalized()
					_line(mesh,a,a-tangent*0.9,Color("#d3bc84"))
					_line(mesh,a,a-tangent*0.16,Color("#ff8a26") if effect["fire"] else Color("#69716e"))
					_line(mesh,a-tangent*0.78,a-tangent*0.93+Vector3(0.08,0,0),Color("#e4dfc6"))
				elif float(effect["age"])<1.25:
					var age:=float(effect["age"])-(0.8 if effect["volley"] else 0.0)
					var p:Vector3=effect["to"]+offset+Vector3.UP*maxf(0,0.45-age)
					var scatter:=Vector3(sin(i*2.4),0.5,cos(i*2.4))*age*1.5
					_line(mesh,p+scatter,p+scatter+Vector3(0.05,0.09,0.04),Color("#bfaa80"))
				elif effect["volley"]:
					var p:Vector3=effect["to"]+offset;p.y=0.07
					_line(mesh,p,p+Vector3(0.1,0.32,0.4),Color("#796343"))
		mesh.surface_end()
	_arrows.mesh=mesh
	for body in _fallen:
		var fall:=clampf((_clock-float(body.get_meta("fall_at",-100)))/0.55,0,1)
		body.rotation.x=lerpf(-0.12,PI/2,smoothstep(0,1,fall))
		body.position.y=lerpf(0.08,0.23,fall)
	presentation_changed.emit()

func _pose_ranks(group: Node3D, blend: float) -> void:
	var troops:MultiMeshInstance3D=group.get_node("Troops")
	var mounted:bool=group.get_meta("mounted",false)
	var engaged:bool=group.get_meta("engaged",false)
	var shape:=String(group.get_meta("formation","line"))
	var columns:=2 if shape=="column" else (6 if shape=="phalanx" else 3 if mounted else 5)
	var rows:=ceili(float(troops.multimesh.instance_count)/columns)
	var spacing:=0.65 if shape=="phalanx" else 1.8 if mounted else 0.87
	for i in range(troops.multimesh.instance_count):
		var row:=floori(float(i)/columns)
		var front:float=-maxf(0,(float(group.get_meta("contact_distance",3.4))-(2.1 if mounted else 1.35))*0.5)
		var depth:=front+row*spacing if engaged else (row-(rows-1)*0.5)*spacing
		var offset:=Vector3((i%columns-(columns-1)*0.5)*(0.64 if shape=="phalanx" else 1.15 if mounted else 0.78),0,depth)
		var current:=troops.multimesh.get_instance_transform(i).origin
		troops.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.90),current.lerp(offset,blend)))
		troops.multimesh.set_instance_custom_data(i,Color(RealismModels.scatter(String(group.name),i),1.0 if row==0 else 0.0,0,1))

func _line(mesh: ImmediateMesh,a: Vector3,b: Vector3,color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a);mesh.surface_add_vertex(b)

func _record_losses(f: Dictionary) -> void:
	var id:=String(f["id"])
	if not groups.has(id):return
	var group:Node3D=groups[id]
	if not group.get_meta("observed",false):return
	var previous:=int(group.get_meta("strength",f["unit"]["strength_pct"]))
	var strength:=int(f["unit"]["strength_pct"])
	if strength>=previous:return
	_hits[id]=_clock
	var size_per_strength:=float(f.get("soldiers",120))/100.0/soldiers_per_model
	var count:=mini(4,ceili(previous*size_per_strength)-ceili(strength*size_per_strength))
	var troops:MultiMeshInstance3D=group.get_node("Troops")
	for i in range(count):
		var body:=MeshInstance3D.new()
		body.mesh=troops.multimesh.mesh
		body.material_override=_material
		var variation:=RealismModels.scatter(id+str(strength),i)
		body.position=group.position+Vector3((variation-0.5)*3,0.23,float(i)*0.48)
		body.rotation=Vector3(-0.12,group.rotation.y+variation*0.4,0.12)
		body.set_meta("fall_at",_clock)
		body.scale=Vector3.ONE*0.90
		add_child(body);_fallen.append(body)
	while _fallen.size()>80:
		var expired:MeshInstance3D=_fallen.pop_front();expired.queue_free()
