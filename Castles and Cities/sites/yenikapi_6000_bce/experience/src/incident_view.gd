extends Node3D
## State-only procedural signs; edge markers leave the pedestrian passage clear.
var world
var key: String=""
var footprints: Array=[]
var owners: Array=[]
func _exit_tree() -> void:clear()
func clear() -> void:
	if is_instance_valid(world):
		for id in owners:
			if world.object_nodes.has(id):world.object_nodes[id].free();world.object_nodes.erase(id)
		world.solids=world.solids.filter(func(s):return s.owner not in owners)
	owners.clear();footprints.clear()
	for c in get_children():c.free()
func refresh(s: Dictionary,r,w) -> void:
	var visible_: Array=[]
	for e in s.incidents.records:
		if s.turn>=e.signs:visible_.append([e.id,"signs" if e.known<0 else r.incidents.phase(s,e),e.restricted,r.land.committed(s,r.incidents.specs[e.id].prepare,r),r.land.committed(s,r.incidents.specs[e.id].repair,r)])
	var signature: String=JSON.stringify([w.get_instance_id(),visible_])
	if signature==key:return
	clear();world=w;key=signature
	for item in visible_:
		var spec: Dictionary=r.incidents.specs[item[0]]
		var center:=Vector3(spec.at[0],w.floor_height(spec.at[0],spec.at[1]),spec.at[1])
		var owner: String="incident_detail_"+spec.id;owners.append(owner);w._begin(owner,center)
		# Raised edge stakes use the same shape for drawing and collision/picking.
		for side in [-1,1]:
			w._solid_box(Vector3(side*4.8,.4,3.7),Vector3(.10,.8,.10),"wood")
			w._geo.box(Vector3(side*4.8,.05,0),Vector3(.10,.05,7.4),"wood_light" if item[1]=="recovered" else "mat")
		if item[1]=="recovery":
			for j in range(4):w._geo.box(Vector3(3.6,.035,-2+j*.8),Vector3(.8,.03,.2),"earth")
		if item[3] or item[4]:
			for j in range(3):w._geo.box(Vector3(4,.025,-3+j*.22),Vector3(.9,.04,.15),"wood_light")
		w._finish()
		var label:=Label3D.new();label.text=spec.marker+"\n"+r.incidents.content.phases[item[1]];label.position=center+Vector3.UP*7;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.font_size=22;label.pixel_size=.022;add_child(label)
		footprints.append({"id":spec.place,"at":center,"half":Vector2(5,4)})
func pick(origin: Vector3,direction: Vector3) -> String:
	var best: float=180;var selected: String=""
	for f in footprints:
		if absf(direction.y)<.0001:continue
		var distance: float=(f.at.y+.05-origin.y)/direction.y
		if distance<0 or distance>best:continue
		var p: Vector3=origin+distance*direction-f.at
		if absf(p.x)<=f.half.x and absf(p.z)<=f.half.y:best=distance;selected=f.id
	if not selected.is_empty():
		var hit: String=world.pick(origin,direction,best).get("id","")
		if not hit.is_empty() and not hit.begins_with("incident_detail_") and not hit.begins_with("living_detail_"):return ""
	return selected
