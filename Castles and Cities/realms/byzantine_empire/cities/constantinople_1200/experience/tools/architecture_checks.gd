extends RefCounted
## Outcome checks for the real architectural library and instantiated city.
## Called by the release smoke gate; no snapshot of implementation internals.
static func run(world, check: Callable) -> void:
	var library = world.architecture
	var before: PackedByteArray = var_to_bytes(library.config)
	var silhouettes := {}
	var kinds := {}
	for type: Dictionary in library.config["types"]:
		var type_id: String = type["id"]
		kinds[type["kind"]] = true
		for floors in range(1,int(type["max_floors"])+1):
			for detail in [false,true]:
				var mesh: ArrayMesh = library.mesh(type_id,detail,floors)
				var valid := true
				var inside_plot := true
				var vertex_total := 0
				for surface in range(mesh.get_surface_count()):
					var arrays: Array = mesh.surface_get_arrays(surface)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					vertex_total += vertices.size()
					for vertex: Vector3 in vertices:
						valid = valid and vertex.is_finite()
						inside_plot = inside_plot and absf(vertex.x)<=5.001 and absf(vertex.z)<=6.001
				check.call(valid and vertex_total>40,"architecture has finite nonempty geometry: %s/%d/%s" % [type_id,floors,detail])
				check.call(inside_plot,"all architecture including eaves and detail stays inside reserved plot: %s/%d/%s" % [type_id,floors,detail])
				if not detail and floors==1:
					var points:=PackedVector3Array()
					for surface in range(mesh.get_surface_count()):points.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
					silhouettes[type_id]=hash(var_to_bytes(points))
	check.call(kinds.size()==4,"architecture includes homes, workshops, churches and town features")
	check.call(silhouettes.values().size()==16 and _unique(silhouettes.values()).size()==16,"sixteen architectural plans have distinct actual coarse geometry")
	# Courtyard voids must be real geometry openings, not painted roof rectangles.
	for type_id in ["l_court","u_court","weaver_court"]:
		var mesh: ArrayMesh = library.mesh(type_id,true,3)
		check.call(not _roof_above(mesh,Vector2(0.0,3.4),3.0),"courtyard has open sky through its actual roof mesh: "+type_id)
	# These three plans have exposed porches without a full courtyard platform.
	# Ray-test the stone geometry under actual front supports at both LODs.
	for type_id in ["hipped_house","storehouse","shop_house"]:
		var foot:=Vector2(-3.03,5.48)
		if type_id=="storehouse":foot=Vector2(-3.78,5.355)
		if type_id=="shop_house":foot=Vector2(-4.23,5.055)
		for detail in [false,true]:
			var mesh:ArrayMesh=library.mesh(type_id,detail,2)
			var hits:=_ray_hits(mesh,world.materials["stone"],Vector3(foot.x,10,foot.y),Vector3.DOWN)
			var low:=INF
			var high:=-INF
			for hit:Vector3 in hits:
				low=minf(low,hit.y)
				high=maxf(high,hit.y)
			check.call(low<=-5.99 and high>=-0.01,"exposed porch support has a deep stone footing at both detail levels: %s/%s" % [type_id,detail])
	var chapel:ArrayMesh=library.mesh("basilican_chapel",true,1)
	for z in [-2.65,0.0,2.65]:
		var origin:=Vector3(10,1.85,z)
		var wall_hits:=_ray_hits(chapel,world.materials["stone"],origin,Vector3.LEFT)
		var window_hits:=_ray_hits(chapel,world.materials["dark"],origin,Vector3.LEFT)
		var wall_x:=-INF
		var window_x:=-INF
		for hit:Vector3 in wall_hits:wall_x=maxf(wall_x,hit.x)
		for hit:Vector3 in window_hits:window_x=maxf(window_x,hit.x)
		check.call(is_finite(wall_x) and is_finite(window_x) and window_x>=wall_x and window_x-wall_x<0.15,"chapel windows remain attached to actual aisle masonry: %s" % z)
	var selected := {}
	var references := {}
	for item: Dictionary in world._layout["buildings"]:
		var first: String = library.select(item)
		var second: String = library.select(item.duplicate(true))
		if first!=second: selected["unstable"]=true
		selected[first]=int(selected.get(first,0))+1
		references[item["id"]]=first
	check.call(not selected.has("unstable"),"architecture selection is deterministic for every city plot")
	check.call(selected.size()==16,"all sixteen architectural types appear in the actual city")
	check.call(var_to_bytes(library.config)==before,"selection and generation preserve architecture source data")
	var street_types:Dictionary={}
	var repeated_neighbors:=0
	var previous:=""
	for i in range(512):
		var chosen:String=library.select({"style":"urban","seed":74531+i})
		street_types[chosen]=true
		if chosen==previous:repeated_neighbors+=1
		previous=chosen
	check.call(street_types.size()>=8 and repeated_neighbors<256,"neighboring plot seeds do not create long single-type architectural stripes")
	var grounded := true
	var below_ground := true
	for placed: Dictionary in world._architecture_placements:
		var transform: Transform3D = placed["transform"]
		grounded = grounded and transform.origin.y>=float(placed["ground_max"])
		var mesh: ArrayMesh = library.mesh(placed["type_id"],false,int(placed["floors"]))
		var base: float = transform.origin.y+mesh.get_aabb().position.y*transform.basis.y.length()
		below_ground = below_ground and base<=float(placed["ground_min"])
	check.call(grounded,"building bases sit above all nine sampled terrain points on each plot")
	check.call(below_ground,"every architectural footing reaches below the lowest sampled surrounding ground")
	var lods := {}
	var architectural_batches:=0
	var correctly_named:=true
	for node in world.urban.get_children():
		if not node is MultiMeshInstance3D:continue
		var threshold:float=library.config["dimensions"]["near_detail_m"]
		if node.visibility_range_end!=threshold and node.visibility_range_begin!=threshold:continue
		architectural_batches+=1
		correctly_named=correctly_named and (str(node.name).ends_with("_Detail") or str(node.name).ends_with("_Silhouette"))
		var key: String = str(node.multimesh.custom_aabb)
		if not lods.has(key):lods[key]=[]
		lods[key].append(node)
	var equal_ranges:=true
	for nodes: Array in lods.values():
		if nodes.size()!=2:
			equal_ranges=false
			continue
		var a=nodes[0]
		var b=nodes[1]
		equal_ranges=equal_ranges and ((a.visibility_range_end==b.visibility_range_begin and a.visibility_range_end>0) or (b.visibility_range_end==a.visibility_range_begin and b.visibility_range_end>0))
	check.call(equal_ranges and correctly_named and lods.size()>16 and architectural_batches==lods.size()*2,"all architectural near/far batches share exact spatial bounds and a matching LOD threshold")
	print("ARCHITECTURE: %d distinct types; %d grounded plots; %d near/far pairs" % [selected.size(),references.size(),lods.size()])

static func _unique(values:Array) -> Dictionary:
	var result:Dictionary={}
	for value in values:result[value]=true
	return result

static func _ray_hits(mesh:ArrayMesh,material:Material,origin:Vector3,direction:Vector3) -> Array[Vector3]:
	var hits:Array[Vector3]=[]
	for surface in range(mesh.get_surface_count()):
		if mesh.surface_get_material(surface)!=material:continue
		var arrays:Array=mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for index in range(0,indices.size(),3):
			var hit=Geometry3D.ray_intersects_triangle(origin,direction,vertices[indices[index]],vertices[indices[index+1]],vertices[indices[index+2]])
			if hit!=null:hits.append(hit)
	return hits

static func _roof_above(mesh:ArrayMesh,point:Vector2,min_y:float) -> bool:
	for surface in range(mesh.get_surface_count()):
		var arrays:Array=mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for index in range(0,indices.size(),3):
			var a:Vector3=vertices[indices[index]]
			var b:Vector3=vertices[indices[index+1]]
			var c:Vector3=vertices[indices[index+2]]
			if minf(a.y,minf(b.y,c.y))<min_y:continue
			var triangle:=PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
			if absf((triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]))<0.001:continue
			if Geometry2D.is_point_in_polygon(point,triangle):return true
	return false
