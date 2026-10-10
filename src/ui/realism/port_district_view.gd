class_name PortDistrictView
extends PortView
signal selected(id: String)
signal notice(key: String)
signal preferences_changed
var navigator: PortNavigation
var representative := Vector2.ZERO
var path: Array = []
var mode := "command"
var follow := false
var speed := 8.0
var sites: Array = []
var actor: MeshInstance3D
var activity: Node3D
var route_mesh: MeshInstance3D
var press := Vector2.ZERO
var moved := false
var held_button := 0
var restored := false
var text: Dictionary = {}
var signs: Array = []

func _ready() -> void:
	super._ready()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	actor = MeshInstance3D.new()
	var art := RealismModels.new()
	art.ellipsoid(Vector3(0,2.05,0),Vector3(0.38,0.4,0.38),Color("dfb58a"))
	art.box(Vector3(0,1.05,0),Vector3(0.75,1.4,0.5),Color("ede0b3"))
	art.rod(Vector3(0.65,0,0),Vector3(0.65,3,0),0.06,Color("6b462e"))
	art.box(Vector3(1.1,2.6,0),Vector3(0.9,0.65,0.06),Color("e6b85d"))
	actor.mesh = art.finish()
	actor.material_override = mesh.material_override
	world.add_child(actor)
	route_mesh = MeshInstance3D.new()
	route_mesh.material_override = mesh.material_override
	world.add_child(route_mesh)
	activity = Node3D.new()
	world.add_child(activity)

func configure(layout: Dictionary, settings: Dictionary, saved: Dictionary = {}) -> void:
	var old := representative
	var interrupted := not path.is_empty()
	plan = layout
	plan["illustrative"] = false
	navigator = PortNavigation.new()
	navigator.build(layout,settings)
	speed = settings["walk_speed"]
	if not restored:
		var p: Array = saved.get("position",[0,-44])
		old = Vector2(p[0],p[1])
		mode = saved.get("mode","command")
		zoom = float(saved.get("zoom",112))
		yaw = float(saved.get("yaw",0))
		var center: Array = saved.get("pan",[0,0])
		pan = Vector3(center[0],0,center[1])
		follow = saved.get("follow",false)
		restored = true
	representative = old if navigator.valid(old) and navigator.route(navigator.nearest(old),old)["ok"] else navigator.nearest(old)
	path.clear()
	sites.clear()
	for f in layout["structures"]:
		if not f["kind"] in ["road","wall","cargo","monument","breakwater"]:
			var at := navigator.approach(PortLayout.rectangle(f["rect"]))
			if f["kind"] in ["court","ramp","pier","quay","bridge"]:
				at = navigator.nearest(PortLayout.rectangle(f["rect"]).get_center())
			sites.append({"id":f["id"],"name":f["name"],"kind":f["kind"],"rect":f["rect"],"height":f["height"],"at":at})
	for b in layout["berths"]:
		sites.append({"id":b["id"],"name":String(text.get(b["id"],b["id"])),"kind":"berth","rect":b["rect"],"height":2.0,"at":navigator.approach(PortLayout.rectangle(b["rect"]))})
	for gate in layout["gates"]:
		sites.append({"id":gate["id"],"name":String(text.get(gate["id"],gate["id"])),"kind":"gate","rect":gate["rect"],"height":0.1,"at":navigator.nearest(PortLayout.rectangle(gate["rect"]).get_center())})
	mesh.mesh = PortModel.build(plan)
	pitch = 1.48 if mode == "command" else 0.72
	_update_actor()
	_draw_route()
	_pose()
	if interrupted or representative.distance_to(old) > 0.1:
		notice.emit("route_interrupted")

func visit() -> Dictionary:
	return {"position":[snappedf(representative.x,0.001),snappedf(representative.y,0.001)],"pan":[snappedf(pan.x,0.001),snappedf(pan.z,0.001)],"mode":mode,"zoom":snappedf(zoom,0.001),"yaw":snappedf(yaw,0.001),"follow":follow}

func set_mode(value: String) -> void:
	mode = value
	pitch = 1.48 if mode == "command" else 0.72
	zoom = 112 if mode == "command" else 40
	if mode == "explore":
		follow = true
		pan = Vector3(representative.x,0,representative.y)
	else:
		pan = Vector3.ZERO
		yaw = 0
		follow = false
	_pose()
	preferences_changed.emit()

func focus_site(id: String, walk: bool = false) -> void:
	for site in sites:
		if site["id"] != id:
			continue
		var at: Vector2 = site["at"]
		pan = Vector3(at.x,0,at.y)
		follow = false
		_pose()
		selected.emit(id)
		if walk:
			walk_to(at)
		preferences_changed.emit()
		return

func walk_to(point: Vector2) -> Dictionary:
	var quote := navigator.route(representative,point)
	if quote["ok"]:
		path = quote["points"].duplicate()
		_draw_route()
		notice.emit("walking")
	else:
		notice.emit(quote["error"])
	return quote

func _process(delta: float) -> void:
	if path.is_empty() or navigator == null:
		return
	var budget := speed * delta
	while budget > 0 and not path.is_empty():
		var next: Vector2 = path[0]
		var distance := representative.distance_to(next)
		if distance <= budget:
			representative = next
			budget -= distance
			path.pop_front()
		else:
			representative = representative.move_toward(next,budget)
			budget = 0
	_update_actor()
	if follow:
		pan = Vector3(representative.x,0,representative.y)
		_pose()
	if path.is_empty():
		_draw_route()
		notice.emit("arrived")
		preferences_changed.emit()

func _update_actor() -> void:
	actor.position = Vector3(representative.x,PortLayout.elevation_at(plan,representative)+0.12,representative.y)

func _draw_route() -> void:
	var art := RealismModels.new()
	var previous := representative
	for point in path:
		var steps := maxi(1,ceili(previous.distance_to(point)))
		for i in range(steps):
			var p := previous.lerp(point,float(i)/steps)
			art.ellipsoid(Vector3(p.x,PortLayout.elevation_at(plan,p)+0.17,p.y),Vector3(0.20,0.08,0.20),Color("efc56e"))
		previous = point
	route_mesh.mesh = art.finish() if not path.is_empty() else null

func show_operations(operations: Dictionary, data: GameData, state: Dictionary) -> void:
	for sign in signs:
		sign["control"].queue_free()
	signs.clear()
	for child in activity.get_children():
		activity.remove_child(child)
		child.queue_free()
	var project: Dictionary = operations["project"]
	if not project.is_empty():
		var art := RealismModels.new()
		for f in data.ports["layout"]["structures"]:
			var included: bool = (project["kind"]=="stage" and int(f["stage"])==int(project["rank"]) and f["facility"]=="") or f["facility"]==project["kind"]
			if not included or (plan["setting"]=="riverbank" and (f["kind"] in ["beacon","breakwater"] or f.get("coastal_only",false))):
				continue
			var r := PortLayout.rectangle(f["rect"])
			for p in [r.position,r.end,Vector2(r.position.x,r.end.y),Vector2(r.end.x,r.position.y)]:
				art.rod(Vector3(p.x,0,p.y),Vector3(p.x,2,p.y),0.09,Color("d2aa58"))
		var stakes := MeshInstance3D.new()
		stakes.mesh = art.finish()
		stakes.material_override = mesh.material_override
		activity.add_child(stakes)
	for berth in plan["berths"]:
		var ships: Array = operations["berths"].get(berth["id"],[])
		var r := PortLayout.rectangle(berth["rect"])
		if ships.is_empty():
			continue
		var ship: Dictionary = ships[0]
		var art := PortModel.new()
		art._boat(Vector3(r.get_center().x,0.1,r.get_center().y),minf(12,r.size.y*0.75),true)
		var hull := MeshInstance3D.new()
		hull.mesh = art.model.finish()
		hull.material_override = mesh.material_override
		activity.add_child(hull)
		var caption := "%s · %d%%" % [data.units[ship["template"]]["name"],ship["readiness"]]
		if int(ship["readiness"]) < 100:
			caption = String(text["damaged_sign"]).format({"name":data.units[ship["template"]]["name"],"ready":int(ship["readiness"])})
		_sign(caption,Vector3(r.get_center().x,4,r.get_center().y),Color("ede0b3"))
	if not operations["queue"].is_empty():
		var at := Vector2(-13,7)
		for f in plan["structures"]:
			if f["id"] == "slip":
				at = PortLayout.rectangle(f["rect"]).get_center()
		var art := RealismModels.new()
		for i in range(7):
			art.rod(Vector3(at.x-2,0.8,at.y-3+i),Vector3(at.x+2,0.8,at.y-3+i),0.12,Color("99734d"))
		var ribs := MeshInstance3D.new()
		ribs.mesh = art.finish()
		ribs.material_override = mesh.material_override
		activity.add_child(ribs)
		var job: Dictionary = operations["queue"][0]
		_sign(String(text["work_sign"]).format({"name":data.units[job["template"]]["name"],"turns":job["turns"]}),Vector3(at.x,5,at.y),Color("efc56e"))
	# Only committed passenger manifests produce assembly figures.
	var passengers := 0
	for id in operations["fleets"]:
		passengers += PortRules.passengers(data,state["fleets"][id].get("cargo",{}).get("army",{}))
	if passengers > 0:
		var at := Vector2(-9,0)
		for site in sites:
			if site["id"] == "assembly":
				at = site["at"]
		var art := RealismModels.new()
		for i in range(6):
			art.box(Vector3(at.x+i%3,0.9,at.y+floori(i/3.0)),Vector3(0.45,1.6,0.45),Color("984b3b"))
		var figures := MeshInstance3D.new()
		figures.mesh = art.finish()
		figures.material_override = mesh.material_override
		activity.add_child(figures)
		_sign(String(text["manifest_sign"]).format({"count":passengers}),Vector3(at.x,4,at.y),Color("efc56e"))
	for site in sites:
		if site["id"] in ["landing_shelter","boatbuilder","arsenal","warehouse_depot","repair_workshop","assembly"]:
			var at: Vector2 = site["at"]
			_sign(site["name"],Vector3(at.x,3,at.y),Color("d7b86c") if site["id"] in ["arsenal","assembly"] else Color("97cccb"))
		if site["id"] == "repair_workshop" and int(PortRules.record(state,plan["region"]).get("repair_turn",-1)) == int(state["turn"]):
			var at: Vector2 = site["at"]
			_sign(text["service_sign"],Vector3(at.x,6,at.y),Color("efc56e"))
	_position_signs()

func _sign(caption: String, at: Vector3, color: Color) -> void:
	var sign := Label.new()
	sign.text = caption
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.add_theme_font_size_override("font_size",12)
	sign.add_theme_color_override("font_color",color)
	sign.add_theme_color_override("font_outline_color",Color("142126"))
	sign.add_theme_constant_override("outline_size",5)
	add_child(sign)
	signs.append({"control":sign,"at":at})

func _pose() -> void:
	super._pose()
	_position_signs()

func _position_signs() -> void:
	var occupied: Array[Rect2] = []
	for entry in signs:
		var sign: Label = entry["control"]
		var p := camera.unproject_position(entry["at"])
		var box := Rect2(p-sign.get_combined_minimum_size()*0.5,sign.get_combined_minimum_size())
		var visible_here := Rect2(Vector2.ZERO,size).encloses(box)
		for previous in occupied:
			visible_here = visible_here and not previous.intersects(box)
		sign.visible = visible_here
		sign.position = box.position
		if visible_here:
			occupied.append(box.grow(2))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				press = event.position
				moved = false
				held_button = event.button_index
			elif held_button == event.button_index:
				if not moved and event.button_index == MOUSE_BUTTON_LEFT:
					_pick(event.position)
				held_button = 0
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			follow = false
			zoom = clampf(zoom*(0.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),18,160)
			_pose()
			preferences_changed.emit()
		accept_event()
	elif event is InputEventMouseMotion and held_button != 0:
		moved = moved or press.distance_to(event.position)>4
		if not moved:
			return
		follow = false
		if held_button == MOUSE_BUTTON_RIGHT and not event.shift_pressed:
			yaw = wrapf(yaw-event.relative.x*0.006,-PI,PI)
		else:
			var right := Vector3(cos(yaw),0,-sin(yaw))
			var down := Vector3(sin(yaw),0,cos(yaw))
			pan -= (right*event.relative.x+down*event.relative.y)*zoom/maxf(1,size.y)
			pan.x = clampf(pan.x,-60,60)
			pan.z = clampf(pan.z,-45,50)
		_pose()
		preferences_changed.emit()
		accept_event()

func _pick(screen: Vector2) -> void:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var best := INF
	var id := ""
	for site in sites:
		var r := PortLayout.rectangle(site["rect"])
		var hit = Plane(Vector3.UP,float(site["height"])).intersects_ray(origin,direction)
		if hit != null and r.has_point(Vector2(hit.x,hit.z)) and origin.distance_to(hit)<best:
			best = origin.distance_to(hit)
			id = site["id"]
	if id != "":
		selected.emit(id)
		return
	var hit = Plane(Vector3.UP,0).intersects_ray(origin,direction)
	if hit != null:
		walk_to(Vector2(hit.x,hit.z))
