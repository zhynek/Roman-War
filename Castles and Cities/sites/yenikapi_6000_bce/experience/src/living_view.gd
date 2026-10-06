extends Node3D
## Original work-area geometry. Stock bands read the season; animation owns nothing.
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
	var bands: Array=[]
	for a in r.living.content.areas:bands.append(int(s.living.woodland[a.id])/12)
	var equipped: int=int(r.forecast(s).living.equipped)
	var signature: String=JSON.stringify([w.get_instance_id(),bands,s.completed,s.living.patrol,s.living.kits,s.living.readiness,equipped])
	if signature==key:return
	clear();world=w;key=signature
	for a in r.living.content.areas:
		var center:=Vector3(a.at[0],world.floor_height(a.at[0],a.at[1]),a.at[1])
		var id: String="living_detail_"+a.id;owners.append(id);world._begin(id,center)
		for i in range(int(s.living.woodland[a.id])/12):
			world._solid_box(Vector3(3.8,.14+i*.12,-1),Vector3(1.6,.11,.23),"wood_light")
		# Low cut/rejected fragments express resolved use, never per-stroke felling.
		for i in range((int(a.capacity)-int(s.living.woodland[a.id]))/12):world._geo.box(Vector3(-3+i*.5,.035,2.8),Vector3(.25,.05,.3),"wood")
		for side in [-1,1]:
			world._geo.box(Vector3(side*5,.025,0),Vector3(.04,.04,8),"path")
			world._geo.box(Vector3(0,.025,side*4),Vector3(10,.04,.04),"path")
		world._finish();label_at(a.title,center+Vector3.UP*3)
		footprints.append({"id":a.id,"at":center,"half":Vector2(5,4)})
	for p in r.living.content.posts:
		if not r.has_project(s,p.project):continue
		var center:=Vector3(p.at[0],world.floor_height(p.at[0],p.at[1]),p.at[1])
		var id: String="living_detail_"+p.id;owners.append(id);world._begin(id,center)
		for side in [-1,1]:world._solid_box(Vector3(side*1.7,.55,-1.2),Vector3(.1,1.1,.1),"wood")
		world._geo.rod(Vector3(-1.7,.8,-1.2),Vector3(1.7,.8,-1.2),.025,"mat",.025,5)
		if p.id==s.living.patrol:
			for i in range(equipped):
				world._solid_box(Vector3(-1.3+i*.22,.65,-1.2),Vector3(.04,1.3,.04),"wood_light")
		world._finish();label_at(p.title,center+Vector3.UP*2.2)
		footprints.append({"id":p.id,"at":center,"half":Vector2(2,1.5)})
func label_at(text_: String,at: Vector3) -> void:
	var label:=Label3D.new();label.text=text_;label.position=at;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.font_size=27;label.pixel_size=.022;label.visibility_range_begin=9;add_child(label)
func pick(origin: Vector3,direction: Vector3) -> String:
	var best: float=180;var selected: String=""
	for f in footprints:
		if absf(direction.y)<.0001:continue
		var distance: float=(f.at.y+.05-origin.y)/direction.y
		if distance<0 or distance>best:continue
		var p: Vector3=origin+distance*direction-f.at
		if absf(p.x)<=f.half.x and absf(p.z)<=f.half.y:best=distance;selected=f.id
	if not selected.is_empty():
		var obstruction: Dictionary=world.pick(origin,direction,best)
		if not str(obstruction.get("id","")).is_empty() and not str(obstruction.get("id","")).begins_with("living_detail_"):return ""
	return selected
