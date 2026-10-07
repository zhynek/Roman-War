extends Node3D
## Optional, wholly interpretive interior life. This adapter only reads the season;
## routes, gestures, pauses and carried objects never mutate the saved simulation.
const Geometry = preload("res://src/geometry.gd")
var routines: Array = []
var stations: Dictionary = {}
var unreachable: Array = []
var completed_routes: int = 0
var elapsed: float = 0.0
var last_refresh_profile: Dictionary={}
var world
var _asset_state: Dictionary={}
var _incident_visual: Array=[]
var _living_state: Dictionary={}
var _shared_room: bool=false
var _living_wood: int=0
var _asset_allocation: Dictionary={}
var _land_adapted: bool=false
var _supply_level: int=-1
var _signature: String = ""
var _geometry_signature: String = ""
var _nav_signature: int = 0
var _world_revision: int=-1
var _owned: Array = []
var _buildings: Dictionary = {}
var _homes: Dictionary = {}
var _text: Dictionary = {}
var _routes: Dictionary = {}
var _cells: Dictionary = {}
var _edges: Dictionary = {}
var _segments: Dictionary = {}
var _materials: Dictionary = {}
var _figure_cache: Dictionary = {}
var _obstacles: Dictionary = {}
var _heights: Dictionary = {}
# Presentation grid only: doors retain exact authored coordinates. No pathfinder
# result is a saved citizen position or a contribution to production/protection.
const GRID: float = .8
const EYE: float = 1.68
const OVERLAY_PREFIX: String = "household_interior_"

func _exit_tree() -> void:
	_clear_overlay()
	for template in _figure_cache.values():template.free()
	_figure_cache.clear()

func refresh(state: Dictionary, rules, scene_world) -> void:
	var profile_start: int=Time.get_ticks_usec()
	var journey_us: int=0
	var figure_us: int=0
	var changed_world: bool = not is_instance_valid(world) or world != scene_world
	if changed_world:
		_clear_overlay()
		world=scene_world
		_geometry_signature=""
		_signature=""
		_routes.clear();_cells.clear();_edges.clear();_segments.clear();_heights.clear();_nav_signature=0
	var stage: String=rules.households.stage(state)
	var orders: Dictionary=state.households.orders
	var ready: Dictionary={}
	for id in orders:ready[id]=rules.households.ready(state,id,rules)
	var tasks: Array=rules.assignments(state,rules.effective_plan(state))
	var allocation_: Dictionary=rules.assets.allocation(state,rules) if rules.assets.active(state) else {}
	var bands: Array=[]
	if rules.assets.active(state):
		for id in ["homes","stores","workroom"]:bands.append(int(state.assets.conditions[id])/25)
	var supply: int=mini(4,ceili(float(state.food)/float(rules.storage(state))*4.0)) if rules.assets.active(state) else -1
	# Only actual duties, visible preparations, stock bands and household memory
	# invalidate actors. A changed target or priority with identical assignments
	# no longer replans every citizen or rebuilds their geometry.
	var incident_visual: Array=[]
	if rules.incidents.active(state):
		for e in state.incidents.records:incident_visual.append([e.id,rules.incidents.phase(state,e),rules.has_project(state,rules.incidents.specs[e.id].prepare)])
	var life_visual: Array=[state.living.get("blanks",0),state.living.get("kits",0),rules.has_project(state,"living_shared_room"),hash(world.solids),mini(6,int(state.wood)/10) if rules.living.active(state) else 0]
	var fingerprint: String=JSON.stringify([incident_visual,life_visual,world.revision,hash(world.solids),tasks,state.citizens,state.households.homes,stage,orders,ready,supply,bands,allocation_.get("repair",""),int(state.food)<rules.people(state).size()])
	if fingerprint==_signature:
		last_refresh_profile={"unchanged":true};return
	_signature=fingerprint
	for child in get_children():child.free()
	routines.clear();stations.clear();unreachable.clear();completed_routes=0;elapsed=0
	_buildings.clear();_homes.clear()
	for b in world.buildings:_buildings[b.id]=b
	for home in rules.content.households:
		if _buildings.has(home.building_id):_homes[home.id]=home.building_id
	_text=rules.households.content.get("presentation",{})
	_incident_visual=incident_visual
	_living_state=state.living if rules.living.active(state) else {}
	_shared_room=rules.has_project(state,"living_shared_room")
	_living_wood=int(life_visual[4])
	_asset_state=state.assets if rules.assets.active(state) else {}
	_asset_allocation=allocation_
	_land_adapted=rules.has_project(state,"land_adapt_workroom")
	_supply_level=supply
	var appearance: String=JSON.stringify([incident_visual,[life_visual[0],life_visual[1],life_visual[2],life_visual[4]],world.revision,_land_adapted,stage,orders,_supply_level,bands,_asset_allocation.get("repair","")])
	if appearance!=_geometry_signature:
		_clear_overlay()
		_interiors(stage,orders)
		_geometry_signature=appearance
	# Keep collision-safe routes when a local building or prop changes. Clear the
	# primitive caches first; validating against old segments would hide new walls.
	if hash(world.solids)!=_nav_signature:
		_revalidate_navigation()
	_make_stations(rules)
	_actor_materials()
	var by_person: Dictionary={}
	# Render current standing orders, including the current party, rather than a
	# stale last-season assignment after the player changes the work plan.
	for task in tasks:by_person[task.id]=task
	var people: Array=rules.people(state)
	var count_by_home: Dictionary={}
	var count_by_job: Dictionary={}
	var occupied_slots: Dictionary={}
	var refuge_guests: int=0
	var workshop_children: int=0
	var setup_us: int=Time.get_ticks_usec()-profile_start
	for i in range(people.size()):
		var person: Dictionary=people[i]
		var child: bool=person.age<rules.balance.adult_age
		var infant: bool=person.age<12
		var home_id: String=person.household
		var home_number: int=int(count_by_home.get(home_id,0))
		count_by_home[home_id]=home_number+1
		var task: Dictionary=by_person.get(person.id,{"job":"care","to":[0,0]})
		var job: String=str(task.job)
		var job_number: int=int(count_by_job.get(job,0))
		count_by_job[job]=job_number+1
		var target_id: String="home_"+home_id
		var activity: String="child_near_home" if child else job
		var reason: String="child" if child else "daily"
		var pose: String="sit" if child else ("stand" if job in ["watch","travel"] else ("kneel" if job in ["food","care"] else "work"))
		var carry: bool=false
		var tense: bool=stage in ["warning","danger"]
		var home_data: Dictionary=state.households.homes.get(home_id,{"stress":0,"practice":0})
		if child:
			if tense and ready.refuge and home_id!="sim_household_01" and refuge_guests<1:
				target_id="household_home";activity="refuge_care";reason=stage;refuge_guests+=1
			elif ready.learning and workshop_children<1 and stage in ["recovery","renewal","settled"] and i%4==0:
				target_id="household_workshop";activity="child_learning";reason="practice";pose="kneel";workshop_children+=1
			elif tense:reason=stage
			elif int(home_data.practice)>0 and i%3==0:
				activity="child_learning";reason="practice";pose="kneel"
		else:
			target_id="task_"+person.id
			var at:=Vector3(float(task.to[0]),0,float(task.to[1]))
			at+=Vector3((job_number%3-1)*1.1,0,float(job_number/3)*.9)
			_station(target_id,_safe(at),"",_label("station_labels",job))
			if job=="care":
				if tense and ready.refuge and job_number==0:
					target_id="household_home";activity="refuge_care";reason=stage;pose="kneel"
				elif ready.learning and stage in ["recovery","renewal","settled"] and job_number==0:
					target_id="household_workshop";activity="learning";reason="practice";pose="kneel"
				else:target_id="home_"+home_id;activity="care";pose="kneel"
			elif job=="food" and (job_number%4==0 if _asset_state.is_empty() else (job_number==0 and not orders.secure_stores)):
				target_id="household_store";activity="store_carry" if tense and ready.secure_stores else "store_sort";carry=true;pose="work" if _asset_state.is_empty() else "kneel";reason=stage if tense else "daily"
			elif job=="watch" and tense and ready.safe_routes:
				target_id="household_route";activity="route_watch";reason=stage;pose="stand"
			elif job=="building" and state.queue.is_empty():
				target_id="household_workshop";activity="repair";pose="kneel";reason=stage
			elif job=="travel":carry=true
			elif job=="timber":carry=true
			if not _asset_state.is_empty():
				match task.get("duty",""):
					"land_adapt_workroom":target_id="household_workshop";activity="repair";pose="kneel"
					"secure_stores":target_id="household_store";activity="store_carry" if tense else "store_sort";carry=state.food>0;pose="kneel"
					"refuge":
						if job_number==0 and ready.refuge:target_id="household_home";activity="refuge_care";pose="kneel"
					"learning":
						if ready.learning:target_id="household_workshop";activity="learning";reason="practice";pose="kneel"
						else:target_id="home_"+home_id;activity="care";reason="daily";pose="kneel"
					"repair":
						activity="repair";pose="kneel"
						if task.asset=="workroom":target_id="household_workshop"
						elif task.asset=="stores":target_id="household_store"
						elif task.asset=="homes":target_id="household_home"
			if rules.living.active(state):
				if task.get("duty","") == "living_prepare":target_id="household_workshop";activity="living_prepare";pose="work";carry=false
				elif task.get("duty","") in ["living_repair","living_training"]:activity=task.duty;target_id="task_"+person.id;pose="work";carry=false
				elif job=="watch":target_id="task_"+person.id;activity="watch"
			if str(task.get("duty","")).begins_with("incident_"):activity="repair";pose="kneel";target_id="task_"+person.id
			if home_data.stress>=65 and job=="care":reason="hunger" if state.food<people.size() else stage
		if infant:target_id="home_"+home_id;activity="child_near_home";reason="child";pose="rest";carry=false
		if not stations.has(target_id):target_id="home_"+home_id
		if not stations.has(target_id):continue
		var home_station: String="home_"+home_id
		var origin: Vector3=stations[home_station].position
		var destination: Vector3=stations[target_id].position
		# Only one additional guest and one caregiver visit the small care room.
		# Other care continues at home; a capacity limit here concerns visible
		# bodies, not housing, worker counts or the seasonal rules.
		var target_building: String=str(stations[target_id].building)
		if not target_building.is_empty():
			destination=_activity_slot(_buildings[target_building],child,occupied_slots)
		var goal_facing: float=_station_facing(destination,target_building)

		var destination_building: String=target_building if _inside_building(destination,target_building) else ""
		var route_start: int=Time.get_ticks_usec()
		var route: Array=[destination] if infant else _journey(origin,destination,str(stations[home_station].building),destination_building)
		if route.is_empty():
			unreachable.append(person.id)
			route=[origin]
		journey_us+=Time.get_ticks_usec()-route_start
		var figure_start: int=Time.get_ticks_usec()
		var figure: Dictionary=_figure(person,child,carry)
		var node: Node3D=figure.node
		add_child(node)
		if rules.living.active(state) and not child and job=="timber":
			var tool:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=Vector3(.055,.45,.05);tool.mesh=shape;tool.material_override=_materials.get("skin");tool.position=Vector3(.25,.86,.22);node.add_child(tool)
			var head:=MeshInstance3D.new();var stone:=BoxMesh.new();stone.size=Vector3(.18,.09,.07);head.mesh=stone;head.material_override=world.materials.stone;head.position=Vector3(.29,1.06,.22);node.add_child(head)
		var begin_at_goal: bool=child or i%3!=1
		var departure_index: int=mini(2,route.size()-1)
		node.position=route[-1] if begin_at_goal else route[departure_index]
		node.rotation.y=goal_facing if begin_at_goal else _station_facing(origin,str(stations[home_station].building))
		var target_index: int=route.size()-2 if begin_at_goal else mini(departure_index+1,route.size()-1)
		var routine: Dictionary={"id":person.id,"name":person.name,"household":home_id,"age":int(person.age),"child":child,"infant":infant,"job":"child" if child else job,"activity":activity,"reason":reason,"station":target_id,"route":route,"node":node,"parts":figure.parts,"carry":carry,"pose":pose,"stress":int(home_data.stress),"practice":int(home_data.practice),"target_index":target_index,"direction":-1 if begin_at_goal else 1,"pause":float(i%5)*1.4+4.0 if begin_at_goal else float(i%3)*.7,"phase":float(i)*.79,"arrivals":0,"moving":false,"goal_facing":goal_facing,"home_facing":_station_facing(origin,str(stations[home_station].building))}
		routines.append(routine)
		_pose(routine,false,0)
		figure_us+=Time.get_ticks_usec()-figure_start
	life_visual[3]=hash(world.solids)
	_signature=JSON.stringify([incident_visual,life_visual,world.revision,hash(world.solids),tasks,state.citizens,state.households.homes,stage,orders,ready,supply,bands,allocation_.get("repair",""),int(state.food)<rules.people(state).size()])
	last_refresh_profile={"setup_us":setup_us,"journey_us":journey_us,"figure_us":figure_us,"total_us":Time.get_ticks_usec()-profile_start}

func _label(table: String,key: String) -> String:
	return str(_text.get(table,{}).get(key,key))

func _clear_overlay() -> void:
	if is_instance_valid(world):
		for owner in _owned:
			var node: Variant=world.object_nodes.get(owner)
			if is_instance_valid(node):node.free()
			world.object_nodes.erase(owner)
		var retained: Array=[]
		for solid in world.solids:
			if not str(solid.owner).begins_with(OVERLAY_PREFIX):retained.append(solid)
		world.solids=retained
	_owned.clear()

func _interiors(stage: String,orders: Dictionary) -> void:
	for id in ["yk_house_01","yk_store_01","yk_house_06"]:
		if not _buildings.has(id):continue
		var b: Dictionary=_buildings[id]
		var owner: String=OVERLAY_PREFIX+id
		world._begin(owner,world.building_position(b),deg_to_rad(float(b.yaw)))
		if id=="yk_house_01":_dwelling(b,stage,orders)
		elif id=="yk_store_01":_store(b,stage,orders)
		else:_workroom(b,stage,orders)
		if not _asset_state.is_empty():_asset_detail(b)
		if not _incident_visual.is_empty():
			var last: Array=_incident_visual[-1]
			if last[1] in ["signs","warning","recovery"]:
				if id=="yk_house_01" and orders.refuge:world._geo.rod(Vector3(-1.78,.19,-1.9),Vector3(-.83,.19,-1.9),.14,"mat",.14,14)
				if id=="yk_store_01" and last[2]:world._geo.box(Vector3(0,1.5,-float(b.size[1])*.5+.33),Vector3(1.4,.03,.45),"mat")
		world._finish();_owned.append(owner)

func _dwelling(b: Dictionary,stage: String,orders: Dictionary) -> void:
	var geo=world._geo
	# A low woven divider encloses the sleeping side without narrowing the door
	# or center aisle. Uprights and the screen use the same collider envelope.
	_screen(Vector3(-1.56,.07,-.10),1.35,1.03)
	_shelf(Vector3(1.97,0,-.88),.43,1.15,1.18)
	for i in range(3):
		_bundle(Vector3(-.45+i*.58,1.55,-float(b.size[1])*.5+.24),.21,.48,true)
		geo.rod(Vector3(-.45+i*.58,2.2,-float(b.size[1])*.5+.24),Vector3(-.45+i*.58,1.78,-float(b.size[1])*.5+.24),.009,"mat",.009,4)
	# Hand repair kit laid on a mat, plus curled offcuts and a smooth stone tool.
	_repair_mat(Vector3(-1.35,.11,-1.03),false)
	geo.box(Vector3(1.95,1.25,-1.2),Vector3(.22,.10,.34),"wood_light")
	for i in range(3):geo.rod(Vector3(1.98,1.23,-.85+i*.17),Vector3(1.98,1.42,-.85+i*.17),.028,"wood_light",.018,7)
	if stage in ["warning","danger"]:
		for i in range(2):_bundle(Vector3(-1.92,.20,1.47-i*.6),.25,.40,false)
		if orders.refuge:
			# Spare rolls and drinking bowls signal care, not new housing capacity.
			for i in range(2):geo.rod(Vector3(-1.78,.19,-1.9+i*.30),Vector3(-.83,.19,-1.9+i*.30),.14,"mat",.14,14)
			world._pot(Vector3(.58,.08,-1.88),.18,.13,"pottery")
	elif stage in ["recovery","renewal","settled"]:
		_repair_mat(Vector3(1.72,.08,1.38),true)

func _store(b: Dictionary,stage: String,orders: Dictionary) -> void:
	var geo=world._geo
	var z: float=-float(b.size[1])*.5+.33
	_shelf(Vector3(0,0,z),float(b.size[0])-.50,.46,1.11)
	for i in range(4 if _supply_level<0 else _supply_level):
		_bundle(Vector3(-1.05+i*.65,1.20,z),.18,.28,false)
		geo.rod(Vector3(-1.04+i*.65,1.38,z-.04),Vector3(-.86+i*.65,1.40,z+.04),.012,"wood_dark",.012,5)
	var secured: bool=orders.secure_stores and (stage in ["warning","danger"] or not _asset_state.is_empty())
	for item in b.furniture:
		if item.kind!="pot":continue
		var at:=Vector3(item.at[0],.705,item.at[1])
		if secured:
			# Woven covers and cross ties show the specific packing order. The
			# original pot bodies and their colliders remain unchanged below.
			geo.cylinder(at,.205,.043,"mat")
			for i in range(9):geo.rod(at+Vector3(-.16,.027,-.14+i*.035),at+Vector3(.16,.027,-.14+i*.035),.006,"wood_light",.006,4)
			geo.rod(at+Vector3(-.19,.04,0),at+Vector3(.19,.04,0),.013,"wood_dark",.013,5)
			geo.rod(at+Vector3(0,.042,-.19),at+Vector3(0,.042,.19),.013,"wood_dark",.013,5)
		elif _supply_level!=0:
			geo.dome(at-Vector3.UP*.07,.17,.06,"grain")
		geo.box(Vector3(item.at[0]+.18,.12,item.at[1]-.15),Vector3(.10,.08,.13),"stone")
	geo.box(Vector3(1.35,.10,1.25),Vector3(.32,.03,.51),"mat")
	for i in range(5 if _supply_level!=0 else 0):geo.box(Vector3(1.26+i*.042,.125,1.24),Vector3(.019,.012,.11),"grain")

	if not _living_state.is_empty():
		for i in range(_living_wood):geo.rod(Vector3(-1.1,.74+i*.065,z),Vector3(1.1,.74+i*.065,z),.035,"wood",.03,6)
		for i in range(int(_living_state.blanks)):
			geo.rod(Vector3(-.8+i*.13,1.0,z-.1),Vector3(-.8+i*.13,1.0,z+.25),.025,"wood_light",.023,6)
		for i in range(int(_living_state.kits)):
			geo.rod(Vector3(-.7+i*.25,.48,z-.1),Vector3(-.7+i*.25,.48,z+.3),.025,"wood",.025,6)

func _workroom(b: Dictionary,stage: String,orders: Dictionary) -> void:
	var geo=world._geo
	_shelf(Vector3(-1.91,0,-.85),.47,1.5,1.25)
	for i in range(5):
		var at:=Vector3(-1.91,1.30,-1.35+i*.22)
		geo.rod(at,at+Vector3(.1,.11,.10),.034,"wood_light",.016,6)
		geo.box(at+Vector3(.09,.03,.035),Vector3(.09,.035,.08),"stone",Vector3(0,i*.5,0))
	# Coil-built vessel in progress. Concentric coils, tool marks and offcuts
	# are a material-culture analogy; this is neither a wheel nor a metal forge.
	var clay_at:=Vector3(1.8,.08,.67)
	for ring in range(8):
		for j in range(18):
			var a:float=TAU*j/18.0;var c:float=TAU*(j+1)/18.0
			var radius:float=.17+sin(float(ring)/8.0*PI)*.075
			geo.rod(clay_at+Vector3(cos(a)*radius,.03+ring*.035,sin(a)*radius),clay_at+Vector3(cos(c)*radius,.03+ring*.035,sin(c)*radius),.022,"clay",.022,5)
	world.solids.append({"at":world._origin+Basis(Vector3.UP,world._yaw)*(clay_at+Vector3.UP*.14),"size":Vector3(.49,.28,.49),"yaw":world._yaw,"owner":world._owner})
	_repair_mat(Vector3(-1.04,.10,-.74),stage in ["recovery","renewal","settled"] and orders.learning)
	# The low frame is for a loose net/cord panel, not an asserted loom type.
	var left:=Vector3(.48,.42,-1.73);var right:=Vector3(1.76,.42,-1.73)
	geo.rod(left,right,.022,"wood_light",.022,6)
	geo.rod(left+Vector3.UP*.83,right+Vector3.UP*.83,.022,"wood_light",.022,6)
	for side in [left,right]:geo.rod(side,side+Vector3.UP*.84,.032,"wood",.026,6)
	for i in range(11):geo.rod(left+Vector3(i*.128,.02,0),left+Vector3(i*.128,.81,0),.006,"mat",.006,4)
	for i in range(8):geo.rod(left+Vector3(0,i*.10+.04,0),right+Vector3(0,i*.10+.04,0),.006,"mat",.006,4)
	if stage in ["warning","danger"]:
		_bundle(Vector3(-1.97,.21,.64),.22,.40,false)
	elif orders.learning:
		for i in range(3):
			geo.box(Vector3(1.82,.095,1.42-i*.21),Vector3(.27,.027,.17),"mat")
			geo.dome(Vector3(1.82,.11,1.42-i*.21),.065,.055,"clay")

	_living_workroom()

func _living_workroom() -> void:
	if _living_state.is_empty():return
	var geo=world._geo
	# Preparation pieces stay along the wall, outside circulation and original mats.
	if _shared_room:
		world._solid_box(Vector3(-1.87,.39,-1.0),Vector3(.25,.12,1.1),"wood")
		for i in range(mini(6,int(_living_state.blanks))):
			geo.rod(Vector3(-1.87,.50+i*.06,-1.45),Vector3(-1.87,.50+i*.06,-.58),.024,"wood_light",.021,6)
		for i in range(3):
			for j in range(8):
				var a: float=j*TAU/8;var b: float=(j+1)*TAU/8
				geo.rod(Vector3(-1.85+cos(a)*.07,.5,-1.3+i*.24+sin(a)*.07),Vector3(-1.85+cos(b)*.07,.5,-1.3+i*.24+sin(b)*.07),.008,"mat",.008,4)

func _screen(at: Vector3,width: float,height: float) -> void:
	var geo=world._geo
	for i in range(6):geo.rod(at+Vector3(-width*.5+i*width/5,0,0),at+Vector3(-width*.5+i*width/5,height,0),.028,"wood",.023,6)
	for row in range(17):
		for i in range(10):
			var x:float=-width*.5+i*width/10
			geo.rod(at+Vector3(x,.05+row*.054,sin(i*PI*.5)*.035),at+Vector3(x+width/10,.05+row*.054,sin((i+1)*PI*.5)*.035),.011,"wood_light",.011,5)
	world.solids.append({"at":world._origin+Basis(Vector3.UP,world._yaw)*(at+Vector3.UP*height*.5),"size":Vector3(width,height,.12),"yaw":world._yaw,"owner":world._owner})

func _shelf(at: Vector3,width: float,depth: float,height: float) -> void:
	var geo=world._geo
	for x in [-width*.40,width*.40]:
		for z in [-depth*.39,depth*.39]:geo.rod(at+Vector3(x,.04,z),at+Vector3(x,height+.06,z),.035,"wood",.028,7)
	for i in range(maxi(3,int(width/.085))):
		var x:float=-width*.48+float(i)/maxi(1,int(width/.085)-1)*width*.96
		geo.rod(at+Vector3(x,height,-depth*.5),at+Vector3(x,height,depth*.5),.042,"wood_light",.030,7)
	for z in [-depth*.42,depth*.42]:geo.rod(at+Vector3(-width*.47,height-.075,z),at+Vector3(width*.47,height-.075,z),.035,"wood",.035,7)
	world.solids.append({"at":world._origin+Basis(Vector3.UP,world._yaw)*(at+Vector3.UP*height*.5),"size":Vector3(width,height+.12,depth),"yaw":world._yaw,"owner":world._owner})

func _bundle(at: Vector3,radius: float,height: float,hanging: bool) -> void:
	var geo=world._geo
	geo.cylinder(at+Vector3.UP*height*.45,radius,height*.84,"mat",radius*.66)
	for i in range(12):
		var angle:float=TAU*i/12.0
		var base:=at+Vector3(cos(angle)*radius,.05,sin(angle)*radius)
		geo.rod(base,at+Vector3(cos(angle)*radius*.66,height*.85,sin(angle)*radius*.66),.006,"thatch_dark",.006,4)
	geo.rod(at+Vector3(-radius*.7,height*.82,0),at+Vector3(radius*.7,height*.82,0),.014,"wood_dark",.014,5)
	if hanging:geo.rod(at+Vector3(0,height*.83,0),at+Vector3(.07,height+.15,0),.012,"mat",.010,5)
	else:world.solids.append({"at":world._origin+Basis(Vector3.UP,world._yaw)*(at+Vector3.UP*height*.45),"size":Vector3(radius*2,height,radius*2),"yaw":world._yaw,"owner":world._owner})

func _repair_mat(at: Vector3,learning: bool) -> void:
	var geo=world._geo
	geo.box(at,Vector3(.58,.015,.46),"mat")
	for row in range(13):geo.rod(at+Vector3(-.28,.015,-.21+row*.035),at+Vector3(.28,.015,-.21+row*.035),.005,"thatch_dark",.005,4)
	for i in range(6):geo.rod(at+Vector3(-.21+i*.085,.034,-.14),at+Vector3(-.15+i*.065,.04,.14),.007,"mat",.007,5)
	geo.box(at+Vector3(.13,.04,.09),Vector3(.11,.039,.07),"stone",Vector3(.04,.55,0))
	geo.rod(at+Vector3(-.2,.025,.05),at+Vector3(.10,.03,-.08),.010,"wood_light",.003,6)
	if learning:
		for i in range(4):geo.cylinder(at+Vector3(-.16+i*.10,.033,-.17),.023,.027,"clay")

func _make_stations(rules) -> void:
	for id in _homes:
		var b: Dictionary=_buildings[_homes[id]]
		_station("home_"+id,_local_safe(b,Vector3(0,0,-.20)),b.id,_label("station_labels","home"))
	for definition in rules.households.content.get("stations",[]):
		if not _buildings.has(definition.building):continue
		var b: Dictionary=_buildings[definition.building]
		var local:=Vector3(.10,0,-.48) if definition.use=="store" else Vector3(0,0,.28)
		_station(str(definition.id),_local_safe(b,local),str(b.id),str(definition.label))
	# Stable aliases permit authoring tables to add named station records later.
	for pair in [["household_home","yk_house_01","refuge"],["household_store","yk_store_01","store"],["household_workshop","yk_house_06","workshop"]]:
		if not stations.has(pair[0]) and _buildings.has(pair[1]):
			_station(pair[0],_local_safe(_buildings[pair[1]],Vector3(0,0,.28)),pair[1],_label("station_labels",pair[2]))
	_station("household_route",_safe(Vector3(1.4,0,14)),"",_label("station_labels","route"))

func _station(id: String,at: Vector3,building: String,label: String) -> void:
	stations[id]={"id":id,"position":at,"building":building,"label":label,"viewpoint":at,"look_at":at+Vector3(0,.95,-1)}
	if _buildings.has(building):
		var record: Dictionary=_buildings[building]
		stations[id].viewpoint=_floor(world.building_position(record,Vector3(0,0,float(record.size[1])*.5-.65)))
		stations[id].look_at=world.building_position(record,Vector3(0,.85,-.7))

func _local_safe(b: Dictionary,local: Vector3) -> Vector3:
	var point: Vector3=world.building_position(b,local)
	if not world.blocked(point):return _floor(point)
	for i in range(24):
		var candidate: Vector3=world.building_position(b,Vector3(-.30+float(i%3)*.3,0,-.65+float(i/3)*.25))
		if not world.blocked(candidate):return _floor(candidate)
	return _floor(world.building_position(b,Vector3(0,0,float(b.size[1])*.5-.5)))

func _activity_slot(b: Dictionary,child: bool,occupied: Dictionary) -> Vector3:
	var candidates: Array=[]
	if b.id=="yk_house_01":
		candidates=[Vector3(-1.25,0,-1.03),Vector3(-1.86,0,.48),Vector3(.15,0,-1.04),Vector3(1.67,0,1.36)] if child else [Vector3(.15,0,-1.04),Vector3(-1.86,0,.48),Vector3(1.67,0,1.36),Vector3(-1.25,0,-1.03)]
	elif b.id=="yk_house_06":
		candidates=[Vector3(-1.15,0,-.61),Vector3(.0,0,-.68),Vector3(.0,0,.57)] if child else [Vector3(.0,0,-.68),Vector3(-1.15,0,-.61),Vector3(.0,0,.57)]
	elif b.use=="storage":
		candidates=[Vector3(.02,0,-.65),Vector3(.04,0,1.25)]
	else:
		candidates=[Vector3(-float(b.size[0])*.25,0,-.66),Vector3(.04,0,-.73),Vector3(-.05,0,.60),Vector3(float(b.size[0])*.28,0,1.42)]
	if not occupied.has(b.id):occupied[b.id]=[]
	for local in candidates:
		var point: Vector3=world.building_position(b,local)
		if world.blocked(point):continue
		var clear: bool=true
		for other in occupied[b.id]:
			if Vector2(point.x-other.x,point.z-other.z).length()<.72:clear=false
		if clear:
			point=_floor(point);occupied[b.id].append(point);return point
	# A crowded home uses its doorstep rather than superimposing another body
	# on a resident. This remains the same household's activity destination.
	var outside: Vector3=_safe(world.building_position(b,Vector3(.9,0,float(b.size[1])*.5+1.45+occupied[b.id].size()*.35)))
	occupied[b.id].append(outside)
	return outside

func _inside_building(point: Vector3,id: String) -> bool:
	if not _buildings.has(id):return false
	var b: Dictionary=_buildings[id]
	var local: Vector3=Basis(Vector3.UP,-deg_to_rad(float(b.yaw)))*(point-world.building_position(b))
	return absf(local.x)<float(b.size[0])*.5 and absf(local.z)<float(b.size[1])*.5

func _station_facing(point: Vector3,building: String) -> float:
	if not _buildings.has(building):return 0
	var record: Dictionary=_buildings[building]
	var focus: Vector3=world.building_position(record,Vector3(-.85,0,-.7))
	if record.use=="storage":focus=world.building_position(record,Vector3(.92,0,-1.06))
	var direction: Vector3=focus-point
	return atan2(direction.x,direction.z)

func _floor(point: Vector3) -> Vector3:
	point.y=world.floor_height(point.x,point.z)
	return point

func _safe(point: Vector3) -> Vector3:
	if not world.blocked(point):return _floor(point)
	for ring in range(1,13):
		for i in range(16):
			var p: Vector3=point+Vector3(cos(i*TAU/16),0,sin(i*TAU/16))*(ring*.25)
			if not world.blocked(p):return _floor(p)
	return _floor(point)

func _journey(a: Vector3,b: Vector3,home: String,destination: String) -> Array:
	var key: String=str([a,b,home,destination])
	if _routes.has(key):return _routes[key].duplicate()
	var result: Array=[]
	if home==destination:
		result=_interior_route(a,b)
	else:
		var start: Vector3=a
		var finish: Vector3=b
		var tail: Array=[]
		if _buildings.has(home):
			var record: Dictionary=_buildings[home]
			var inside: Vector3=_floor(world.building_position(record,Vector3(0,0,float(record.size[1])*.5-.58)))
			start=_floor(world.building_position(record,Vector3(0,0,float(record.size[1])*.5+1.10)))
			result=_interior_route(a,inside)
			if result.is_empty() or not _clear(inside,start):return []
			result.append(start)
		if _buildings.has(destination):
			var record: Dictionary=_buildings[destination]
			var inside: Vector3=_floor(world.building_position(record,Vector3(0,0,float(record.size[1])*.5-.58)))
			finish=_floor(world.building_position(record,Vector3(0,0,float(record.size[1])*.5+1.10)))
			tail=_interior_route(inside,b)
			if tail.is_empty() or not _clear(finish,inside):return []
		var across: Array=_outdoor_route(start,finish)
		if across.is_empty():return []
		if result.is_empty():result.append(a)
		_append_route(result,across)
		_append_route(result,tail)
		if result[-1].distance_to(b)>.04:result.append(b)
	_routes[key]=result.duplicate()
	return result

func _append_route(target: Array,extra: Array) -> void:
	for p in extra:
		if target.is_empty() or target[-1].distance_to(p)>.04:target.append(p)

func _interior_route(a: Vector3,b: Vector3) -> Array:
	var key: String=str(["interior",a,b])
	if not _routes.has(key):_routes[key]=_interior_uncached(a,b)
	return _routes[key].duplicate()

func _interior_uncached(a: Vector3,b: Vector3) -> Array:
	if _clear(a,b):return [a,b] if a.distance_to(b)>.03 else [a]
	# Tiny local grid handles furniture corners; exact endpoints retain doorway
	# clearance even where a global grid would entirely miss a narrow threshold.
	return _search(a,b,.32,9.0,1800,false)

func _outdoor_route(a: Vector3,b: Vector3) -> Array:
	var key: String=str(["outdoor",a,b])
	if not _routes.has(key):_routes[key]=_outdoor_uncached(a,b)
	return _routes[key].duplicate()

func _outdoor_uncached(a: Vector3,b: Vector3) -> Array:
	if _clear(a,b):return [a,b]
	return _search(a,b,GRID,20.0,9000,true)

func _clear(a: Vector3,b: Vector3) -> bool:
	# Many residents share door segments. Cache the same exact swept samples,
	# invalidating with collider geometry; this never changes a route result.
	var key:=Vector4(a.x,a.z,b.x,b.z)
	if _segments.has(key):return _segments[key]
	var clear: bool=_clear_uncached(a,b)
	if _segments.size()>200000:_segments.clear()
	_segments[key]=clear
	return clear

func _clear_uncached(a: Vector3,b: Vector3) -> bool:
	var delta: Vector3=b-a;delta.y=0
	var steps: int=maxi(1,ceili(delta.length()/.16))
	var previous: float=_nav_height(a)
	for i in range(steps+1):
		var p: Vector3=a+delta*(float(i)/steps)
		if _nav_blocked(p):return false
		var h: float=_nav_height(p)
		if absf(h-previous)>=.27:return false
		previous=h
	return true

func _index_obstacles() -> void:
	# Broad phase contains the exact village boxes; only the candidate set is
	# reduced. This is not a second collision shape or navigation approximation.
	_obstacles.clear()
	for solid in world.solids:
		var extent: Vector3=solid.size*.5
		var basis:=Basis(Vector3.UP,float(solid.yaw))
		var x: float=absf(basis.x.x)*extent.x+absf(basis.z.x)*extent.z+.23
		var z: float=absf(basis.x.z)*extent.x+absf(basis.z.z)*extent.z+.23
		var low:=Vector2i(floori((solid.at.x-x)/4.0),floori((solid.at.z-z)/4.0))
		var high:=Vector2i(floori((solid.at.x+x)/4.0),floori((solid.at.z+z)/4.0))
		for ix in range(low.x,high.x+1):
			for iz in range(low.y,high.y+1):
				var key:=Vector2i(ix,iz)
				if not _obstacles.has(key):_obstacles[key]=[]
				_obstacles[key].append(solid)

func _nav_height(point: Vector3) -> float:
	var key:=Vector2(point.x,point.z)
	if not _heights.has(key):_heights[key]=world.floor_height(point.x,point.z)
	return _heights[key]

func _nav_blocked(point: Vector3) -> bool:
	var h: float=_nav_height(point)
	if h<.12 or absf(point.x)>world.data.terrain.walk_limit or absf(point.z)>world.data.terrain.walk_limit:return true
	var key:=Vector2i(floori(point.x/4.0),floori(point.z/4.0))
	for box in _obstacles.get(key,[]):
		var half: Vector3=box.size*.5
		if box.at.y+half.y<h+.14 or box.at.y-half.y>h+1.82:continue
		var local: Vector3=Basis(Vector3.UP,-float(box.yaw))*(point-box.at)
		var dx: float=maxf(absf(local.x)-half.x,0)
		var dz: float=maxf(absf(local.z)-half.z,0)
		if dx*dx+dz*dz<.23*.23:return true
	return false

func _cell(point: Vector3,step: float) -> Vector2i:
	return Vector2i(roundi(point.x/step),roundi(point.z/step))

func _point(cell: Vector2i,step: float) -> Vector3:
	return Vector3(cell.x*step,0,cell.y*step)

func _free_cell(cell: Vector2i,step: float,cache: bool) -> bool:
	if cache and _cells.has(cell):return _cells[cell]
	var free: bool=not _nav_blocked(_point(cell,step))
	if cache:_cells[cell]=free
	return free

func _search(a: Vector3,b: Vector3,step: float,margin: float,limit: int,cache: bool) -> Array:
	var start: Vector2i=_cell(a,step)
	var end: Vector2i=_cell(b,step)
	var seeds: Array=[]
	var goals: Dictionary={}
	for dx in range(-1,2):
		for dy in range(-1,2):
			var s: Vector2i=start+Vector2i(dx,dy)
			if _free_cell(s,step,cache) and _clear(a,_point(s,step)):seeds.append(s)
			var e: Vector2i=end+Vector2i(dx,dy)
			if _free_cell(e,step,cache) and _clear(_point(e,step),b):goals[e]=true
	if seeds.is_empty() or goals.is_empty():return []
	var heap: Array=[]
	var cost: Dictionary={}
	var previous: Dictionary={}
	for seed in seeds:
		var d: float=Vector2(a.x,a.z).distance_to(Vector2(seed)*step)
		cost[seed]=d
		_heap_push(heap,{"cell":seed,"score":d+Vector2(seed-end).length()*step})
	var closed: Dictionary={}
	var found:=Vector2i(2147483647,2147483647)
	var low_x: float=minf(a.x,b.x)-margin
	var high_x: float=maxf(a.x,b.x)+margin
	var low_z: float=minf(a.z,b.z)-margin
	var high_z: float=maxf(a.z,b.z)+margin
	var directions: Array=[Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1),Vector2i(1,-1)]
	while not heap.is_empty() and closed.size()<limit:
		var current: Vector2i=_heap_pop(heap).cell
		if closed.has(current):continue
		closed[current]=true
		if goals.has(current):found=current;break
		for direction in directions:
			var next: Vector2i=current+direction
			var p: Vector3=_point(next,step)
			if closed.has(next) or p.x<low_x or p.x>high_x or p.z<low_z or p.z>high_z:continue
			if not _free_cell(next,step,cache):continue
			var edge: String=str(current)+":"+str(next)
			var clear: bool
			if cache and _edges.has(edge):clear=_edges[edge]
			else:
				clear=_clear(_point(current,step),p)
				if cache:_edges[edge]=clear
			if not clear:continue
			var candidate: float=float(cost[current])+Vector2(direction).length()*step
			if not cost.has(next) or candidate<float(cost[next]):
				cost[next]=candidate;previous[next]=current
				_heap_push(heap,{"cell":next,"score":candidate+Vector2(next-end).length()*step})
	if found.x==2147483647:return []
	var raw: Array=[b,_floor(_point(found,step))]
	while previous.has(found):found=previous[found];raw.append(_floor(_point(found,step)))
	raw.append(a);raw.reverse()
	# String pulling is collision tested, producing clear intentional walks rather
	# than a grid zigzag or a fallback that pushes sideways through a wall.
	var result: Array=[a]
	var index: int=0
	while index<raw.size()-1:
		var next: int=raw.size()-1
		while next>index+1 and not _clear(raw[index],raw[next]):next-=1
		result.append(raw[next]);index=next
	return result

func _heap_push(heap: Array,item: Dictionary) -> void:
	heap.append(item)
	var i: int=heap.size()-1
	while i>0:
		var parent: int=(i-1)/2
		if not _heap_before(heap[i],heap[parent]):break
		var swap: Dictionary=heap[parent];heap[parent]=heap[i];heap[i]=swap;i=parent

func _heap_before(a: Dictionary,b: Dictionary) -> bool:
	if not is_equal_approx(a.score,b.score):return a.score<b.score
	if a.cell.x!=b.cell.x:return a.cell.x<b.cell.x
	return a.cell.y<b.cell.y

func _heap_pop(heap: Array) -> Dictionary:
	var first: Dictionary=heap[0]
	var last: Dictionary=heap.pop_back()
	if heap.is_empty():return first
	heap[0]=last
	var i: int=0
	while i*2+1<heap.size():
		var child: int=i*2+1
		if child+1<heap.size() and _heap_before(heap[child+1],heap[child]):child+=1
		if not _heap_before(heap[child],heap[i]):break
		var swap: Dictionary=heap[i];heap[i]=heap[child];heap[child]=swap;i=child
	return first

func _actor_materials() -> void:
	if not _materials.is_empty():return
	for pair in [["cloth",Color("897964")],["light",Color("b1a083")],["dark",Color("655948")],["skin",Color("ac8060")],["hair",Color("41392f")],["tie",Color("cfb789")],["bag",Color("a48b5d")]]:
		var material:=StandardMaterial3D.new();material.albedo_color=pair[1];material.roughness=1
		_materials[pair[0]]=material

func _figure(person: Dictionary,child: bool,carry: bool) -> Dictionary:
	var cache_key: String="infant" if person.age<12 else str([posmod(str(person.id).hash(),3),carry])
	if _figure_cache.has(cache_key):return _clone_figure(_figure_cache[cache_key],person,child)
	var actor:=Node3D.new();actor.name=person.id
	if person.age<12:
		var bundle_geo=Geometry.new(_materials)
		_ellipsoid(bundle_geo,Vector3(0,.13,0),Vector3(.14,.11,.28),"light")
		_ellipsoid(bundle_geo,Vector3(0,.17,-.29),Vector3(.066,.071,.064),"skin")
		for i in range(3):bundle_geo.rod(Vector3(-.12,.19,-.14+i*.13),Vector3(.12,.19,-.14+i*.13),.009,"tie",.009,5)
		var bundle:=MeshInstance3D.new();bundle.mesh=bundle_geo.finish();actor.add_child(bundle)
		_figure_cache[cache_key]=actor.duplicate(0)
		return {"node":actor,"parts":{"body":bundle,"legs":[],"arms":[]}}
	var variant: int=posmod(str(person.id).hash(),3)
	var cloth: String=["cloth","light","dark"][variant]
	var geometry=Geometry.new(_materials)
	# Separate wrapped garment, belt, neck, asymmetric hair and exposed lower
	# arms make a resident legible at eye level without imported character art.
	geometry.cylinder(Vector3(0,1.03,0),.205,.56,cloth,.18)
	geometry.cylinder(Vector3(0,.75,0),.255,.29,cloth,.198)
	geometry.cylinder(Vector3(0,.91,0),.207,.045,"tie",.207)
	geometry.cylinder(Vector3(0,1.34,0),.058,.10,"skin")
	_ellipsoid(geometry,Vector3(0,1.49,0),Vector3(.124,.165,.116),"skin")
	_hair_cap(geometry,Vector3(0,1.49,-.012),.130,.175)
	_ellipsoid(geometry,Vector3(0,1.478,.117),Vector3(.026,.047,.026),"skin")
	for side in [-1.0,1.0]:
		_ellipsoid(geometry,Vector3(side*.123,1.49,-.005),Vector3(.022,.043,.024),"skin")
		_ellipsoid(geometry,Vector3(side*.046,1.519,.110),Vector3(.009,.006,.006),"hair")
	if variant==1:_ellipsoid(geometry,Vector3(0,1.52,-.120),Vector3(.080,.093,.056),"hair")

	if carry:
		geometry.box(Vector3(0,1.04,-.24),Vector3(.40,.46,.24),"bag",Vector3(0,0,.08))
		for side in [-1.0,1.0]:geometry.rod(Vector3(side*.145,.88,-.37),Vector3(side*.145,1.27,.10),.017,"tie",.017,6)
	var body:=MeshInstance3D.new();body.mesh=geometry.finish();actor.add_child(body)
	var parts: Dictionary={"body":body,"legs":[],"arms":[]}
	for side in [-1.0,1.0]:
		var leg:=Node3D.new();leg.position=Vector3(side*.105,.76,0);actor.add_child(leg)
		var leg_geo=Geometry.new(_materials)
		leg_geo.rod(Vector3.ZERO,Vector3(0,-.69,0),.074,"skin",.055,8)
		_ellipsoid(leg_geo,Vector3(0,-.71,.045),Vector3(.061,.045,.12),"skin")
		var leg_mesh:=MeshInstance3D.new();leg_mesh.mesh=leg_geo.finish();leg.add_child(leg_mesh);parts.legs.append(leg)
		var arm:=Node3D.new();arm.position=Vector3(side*.20,1.26,0);actor.add_child(arm)
		var arm_geo=Geometry.new(_materials)
		arm_geo.rod(Vector3.ZERO,Vector3(side*.025,-.22,.015),.073,cloth,.067,8)
		arm_geo.rod(Vector3(side*.025,-.20,.015),Vector3(side*.02,-.51,.06),.052,"skin",.035,8)
		_ellipsoid(arm_geo,Vector3(side*.02,-.52,.065),Vector3(.035,.056,.029),"skin")
		var arm_mesh:=MeshInstance3D.new();arm_mesh.mesh=arm_geo.finish();arm.add_child(arm_mesh);parts.arms.append(arm)
	if child:
		var size: float=clampf(.43+float(person.age)/72.0*.39,.46,.83)
		actor.scale=Vector3.ONE*size
	else:actor.scale=Vector3.ONE*(.95+variant*.035)
	_figure_cache[cache_key]=actor.duplicate(0)
	return {"node":actor,"parts":parts}

func _clone_figure(template: Node3D,person: Dictionary,child: bool) -> Dictionary:
	var actor: Node3D=template.duplicate(0);actor.name=person.id
	var parts: Dictionary={"body":actor.get_child(0),"legs":[],"arms":[]}
	if person.age>=12:
		for index in [1,3]:parts.legs.append(actor.get_child(index))
		for index in [2,4]:parts.arms.append(actor.get_child(index))
		actor.scale=Vector3.ONE*(clampf(.43+float(person.age)/72.0*.39,.46,.83) if child else .95+posmod(str(person.id).hash(),3)*.035)
	return {"node":actor,"parts":parts}

func _ellipsoid(geo,at: Vector3,size: Vector3,material: String) -> void:
	# Solid small forms need no inner lining. Geometry.dome's architectural
	# shell thickness is intentionally unsuitable for fingers, ears or faces.
	for ring in range(10):
		var a: float=-PI*.5+PI*ring/10.0
		var b: float=-PI*.5+PI*(ring+1)/10.0
		for segment in range(16):
			var u: float=TAU*segment/16.0
			var v: float=TAU*(segment+1)/16.0
			var p:=at+Vector3(cos(a)*cos(u),sin(a),cos(a)*sin(u))*size
			var q:=at+Vector3(cos(a)*cos(v),sin(a),cos(a)*sin(v))*size
			var r:=at+Vector3(cos(b)*cos(v),sin(b),cos(b)*sin(v))*size
			var t:=at+Vector3(cos(b)*cos(u),sin(b),cos(b)*sin(u))*size
			geo._oriented_quad(p,q,r,t,((p+q+r+t)*.25-at).normalized(),material)

func _hair_cap(geo,at: Vector3,radius: float,height: float) -> void:
	for ring in range(6):
		var a: float=.22+(PI*.5-.22)*ring/6.0
		var b: float=.22+(PI*.5-.22)*(ring+1)/6.0
		for segment in range(20):
			var u: float=TAU*segment/20.0
			var v: float=TAU*(segment+1)/20.0
			var p:=at+Vector3(cos(a)*cos(u)*radius,sin(a)*height,cos(a)*sin(u)*radius)
			var q:=at+Vector3(cos(a)*cos(v)*radius,sin(a)*height,cos(a)*sin(v)*radius)
			var r:=at+Vector3(cos(b)*cos(v)*radius,sin(b)*height,cos(b)*sin(v)*radius)
			var t:=at+Vector3(cos(b)*cos(u)*radius,sin(b)*height,cos(b)*sin(u)*radius)
			geo._oriented_quad(p,q,r,t,((p+q+r+t)*.25-at).normalized(),"hair")

func _process(delta: float) -> void:
	step(minf(delta,.1))

func step(delta: float) -> void:
	if not is_instance_valid(world):return
	elapsed+=delta
	for routine in routines:
		var moving: bool=false
		var node: Node3D=routine.node
		var route: Array=routine.route
		if routine.pause>0:routine.pause=maxf(0,float(routine.pause)-delta)
		elif route.size()>1:
			var index: int=clampi(int(routine.target_index),0,route.size()-1)
			var target: Vector3=route[index]
			var direction: Vector3=target-node.position;direction.y=0
			var speed: float=1.12 if routine.child else 1.30
			if routine.stress>=65:speed*=.82
			var amount: float=minf(direction.length(),speed*delta)
			if amount>.003:
				var next: Vector3=world.walk(node.position+Vector3.UP*EYE,direction.normalized()*amount)-Vector3.UP*EYE
				moving=Vector2(next.x-node.position.x,next.z-node.position.z).length()>.001
				node.position=next
				node.rotation.y=atan2(direction.x,direction.z)
			if Vector2(target.x-node.position.x,target.z-node.position.z).length()<.045:
				routine.target_index=index+int(routine.direction)
				if routine.target_index<0 or routine.target_index>=route.size():
					routine.arrivals+=1;completed_routes+=1
					node.rotation.y=float(routine.goal_facing) if index==route.size()-1 else float(routine.home_facing)
					routine.direction=-int(routine.direction)
					routine.target_index=index+int(routine.direction)
					routine.pause=7.0+fmod(float(routine.phase)*3,6.0)
		routine.moving=moving
		_pose(routine,moving,elapsed)

func _pose(routine: Dictionary,moving: bool,time: float) -> void:
	var parts: Dictionary=routine.parts
	var body: Node3D=parts.body
	if routine.infant:return
	var phase: float=sin(time*5.2+float(routine.phase))
	var knee: bool=not moving and routine.pose in ["kneel","sit"]
	var lower: float=.44 if knee else 0.0
	var working: bool=not moving and routine.pose=="work"
	body.position.y=-lower
	body.rotation.x=.025 if knee else (.035 if working else (.05 if routine.stress>=65 and not moving else 0.0))
	for i in range(2):
		var leg: Node3D=parts.legs[i]
		leg.position.y=.76-lower
		leg.rotation.x=-1.12 if knee else phase*.35*(1 if i==0 else -1)
		if not moving and not knee:leg.rotation.x=0
		var arm: Node3D=parts.arms[i]
		arm.position.y=1.26-lower
		arm.rotation.x=(-.85+phase*.07 if knee else (-.24 if routine.carry else phase*.26*(1 if i==1 else -1))) if moving or knee else -.12
		if working:arm.rotation.x=-.55+phase*.10
		arm.rotation.z=(.12 if i==0 else -.12) if knee else 0

func _asset_detail(b: Dictionary) -> void:
	var asset: String={"yk_house_01":"homes","yk_store_01":"stores","yk_house_06":"workroom"}[b.id]
	var condition: int=int(_asset_state.conditions[asset])
	var geo=world._geo
	# Shallow wall finish changes stay behind the existing collision envelope.
	var x: float=-float(b.size[0])*.5+.15
	for i in range(1 if condition>=75 else (3 if condition>=50 else 6)):
		geo.box(Vector3(x,.55+float(i%3)*.23,-.45-float(i/3)*.65),Vector3(.025,.13,.42),"daub_light" if condition>=75 else "daub_dark")
	if asset=="workroom" and _land_adapted:
		# New preparation surface retains old fabric and doorway. All extra
		# geometry stays against the rear wall, outside circulation.
		_repair_mat(Vector3(.9,.1,-1.2),true)
		for i in range(4):geo.box(Vector3(x,.6+i*.22,-.8),Vector3(.025,.17,1.6),"daub_light")
	if _asset_allocation.repair==asset:
		_repair_mat(Vector3(float(b.size[0])*.5-.6,.09,float(b.size[1])*.5-.7),true)
		for i in range(3):geo.rod(Vector3(x+.22,.12,-1.5+i*.15),Vector3(x+.9,.12,-1.5+i*.15),.035,"wood_light",.028,6)
	if asset=="homes" and _asset_state.get("pressure_start",-1)<0:
		# Ordinary shared care is a useful interior arrangement too.
		if _asset_allocation.orders.get("refuge",0)>0:
			geo.rod(Vector3(-1.78,.19,-1.9),Vector3(-.83,.19,-1.9),.14,"mat",.14,14)

func _revalidate_navigation() -> void:
	_cells.clear();_edges.clear();_segments.clear();_heights.clear()
	_index_obstacles()
	var retained: int=0
	for key in _routes.keys():
		var route: Array=_routes[key]
		var valid: bool=not route.is_empty()
		for i in range(route.size()):
			route[i]=_floor(route[i])
			if _nav_blocked(route[i]):valid=false;break
			if i>0 and not _clear(route[i-1],route[i]):valid=false;break
		if not valid:_routes.erase(key)
		else:retained+=1
	_nav_signature=hash(world.solids)
	last_refresh_profile.retained_routes=retained
