extends Node3D
## Footprint outlines and paid construction share data with land picking.
var footprints: Array=[]

func build(state: Dictionary,rules,world) -> void:
	for site in rules.land.content.sites:
		if site.get("lifecycle",false) and not rules.lifecycle.active(state):continue
		if not rules.lifecycle.site_available(state,site.id):continue
		var use: String=rules.land.use_at(state,site.id,rules)
		var done: bool=use!="" and rules.has_project(state,use)
		var center:=Vector3(site.at[0],world.floor_height(site.at[0],site.at[1]),site.at[1])
		var half:=Vector2(site.size[0],site.size[1])*.5
		footprints.append({"id":site.id,"at":center,"half":half})
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("9d8759") if use=="" else (Color("718767") if done else Color("bca674"));mat.roughness=1
		for side in [-1,1]:
			_bar(center+Vector3(side*half.x,.07,0),Vector3(.06,.09,half.y*2),mat)
			_bar(center+Vector3(0,.07,side*half.y),Vector3(half.x*2,.09,.06),mat)
		if (use=="" or done) and not world.get_meta("project_presentation",false):
			var label:=Label3D.new();label.text=site.title;label.font_size=26;label.pixel_size=.012;label.position=center+Vector3(0,5 if done else 2,0);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=Color("e4d9b7");label.visibility_range_begin=12.0;add_child(label)
		if use!="" and not done and not rules.land.proposals[use].retain and not world.get_meta("project_presentation",false):
			var progress: int=0
			for item in state.queue:
				if item.id==use:progress=int(item.progress)
			var fraction: float=float(progress)/float(rules.projects[use].work)
			# All staged timber follows the paid commission; frame height follows
			# real work. Neither geometry nor arrivals increment that ledger.
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
				if fraction>0:_bar(center+Vector3(corner.x*2,.2+fraction,corner.y*2),Vector3(.13,.4+fraction*2,.13),mat)
			if fraction>=.5:
				for side in [-1,1]:_bar(center+Vector3(0,1.9,side*2),Vector3(4.1,.13,.13),mat)

func _bar(at: Vector3,size_: Vector3,mat: Material) -> void:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size_;node.mesh=mesh;node.material_override=mat;node.position=at;add_child(node)

func pick(origin: Vector3,direction: Vector3) -> String:
	var best: float=180.0
	var selected: String=""
	for footprint in footprints:
		if absf(direction.y)<.0001:continue
		var distance: float=(footprint.at.y+.07-origin.y)/direction.y
		if distance<0 or distance>best:continue
		var point: Vector3=origin+direction*distance-footprint.at
		if absf(point.x)<=footprint.half.x and absf(point.z)<=footprint.half.y:best=distance;selected=footprint.id
	return selected
