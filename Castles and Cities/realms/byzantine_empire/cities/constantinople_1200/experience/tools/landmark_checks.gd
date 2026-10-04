extends SceneTree
## Checks actual geometry of distinct landmark families, independent of the city.
const Landmarks = preload("res://src/landmarks.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL: "+description)

func _run() -> void:
	_test_column_joints()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/city.json"))
	for item: Dictionary in data.landmarks:
		var dims: Dictionary = item.dimensions
		if not bool(dims.get("octagonal_gallery",0)) and not bool(dims.get("adjoining_sanctuaries",0)) and not bool(dims.get("cruciform_five_domes",0)):
			continue
		var assembly: Node3D = Landmarks.build(item,{})
		root.add_child(assembly)
		var mesh_bounds := AABB()
		var first := true
		var stack: Array[Node] = [assembly]
		var collision_boxes: Array[CollisionShape3D] = []
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for child in node.get_children():
				stack.append(child)
			if node is CollisionShape3D and node.shape is BoxShape3D:
				collision_boxes.append(node)
			if not node is MeshInstance3D:
				continue
			var mesh: Mesh = node.mesh
			_check(mesh != null and mesh.get_surface_count()>0,"nonempty assembly part: "+str(node.name))
			if mesh == null:
				continue
			var transform: Transform3D = assembly.global_transform.affine_inverse()*node.global_transform
			var bounds: AABB = transform*mesh.get_aabb()
			mesh_bounds = bounds if first else mesh_bounds.merge(bounds)
			first = false
			for surface in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var finite := vertices.size()>0 and vertices.size()==normals.size()
				for index in range(vertices.size()):
					finite = finite and vertices[index].is_finite() and normals[index].is_finite() and normals[index].length_squared()>0.90 and normals[index].length_squared()<1.10
				_check(finite,"finite positions and unit normals: "+str(node.name)+"/"+str(surface))
		_check(mesh_bounds.size.x<float(dims.width_m)*1.12 and mesh_bounds.size.z<float(dims.depth_m)*1.12,"typology respects reserved landmark envelope: "+str(item.id))
		_check(mesh_bounds.size.y<float(dims.height_m)*1.12 and mesh_bounds.size.y>float(dims.height_m)*0.9,"landmark maintains authored scale: "+str(item.id))
		var anchor: Vector3 = assembly.get_meta("interior_anchor")
		for offset in [Vector3.ZERO,Vector3(0,0,1.2),Vector3(0,0,-1.2),Vector3(1.0,0,0),Vector3(-1.0,0,0)]:
			for height in [-1.25,0.0,0.40]:
				var sample: Vector3 = assembly.global_transform*(anchor+offset+Vector3.UP*height)
				var clear := true
				for box in collision_boxes:
					var local: Vector3 = box.global_transform.affine_inverse()*sample
					var half: Vector3 = box.shape.size*0.5
					clear = clear and not (absf(local.x)<half.x+0.25 and absf(local.y)<half.y+0.10 and absf(local.z)<half.z+0.25)
				_check(clear,"walkable inspection volume: "+str(item.id)+"/"+str(offset)+"/"+str(height))
		if bool(dims.get("octagonal_gallery",0)):
			var ring: MeshInstance3D = assembly.get_node("OctagonalGallery")
			var dome: MeshInstance3D = assembly.get_node("SixteenCompartmentDome")
			_check(ring.mesh.get_aabb().size.y>float(dims.gallery_height_m)*1.5,"octagonal gallery has lower and upper architectural orders")
			_check(dome.mesh.get_aabb().size.x>float(dims.dome_radius_m)*1.95,"octagonal church has full-span compartmented dome")
			var core_piers := 0
			for box in collision_boxes:
				if is_equal_approx(box.shape.size.x,1.05) and is_equal_approx(box.shape.size.z,1.05) and box.shape.size.y>float(dims.gallery_height_m):
					core_piers += 1
			_check(core_piers==8,"octagonal core has eight actual load-bearing pier solids")
			for sx in [-1.0,1.0]:
				for sz in [-1.0,1.0]:
					_check(_roof_hit(ring.mesh,Vector2(sx*float(dims.width_m)*0.44,sz*float(dims.depth_m)*0.39),float(dims.height_m)*0.50),"rectangular gallery corner is roofed")
			var wall_mesh: Mesh = assembly.get_node("OriginalArchitecture").mesh
			var top_y: float = (float(dims.height_m)-float(dims.dome_height_m))*0.79+0.06
			for side in [-1.0,1.0]:
				_check(_front_hit(wall_mesh,Vector3(side*float(dims.dome_radius_m)*0.43*0.75,top_y,float(dims.depth_m)*0.41-1.0),Vector3.BACK,2.0),"apse conch has an enclosed tympanum when seen from inside")
		if bool(dims.get("adjoining_sanctuaries",0)):
			var north: Node3D = assembly.get_node("NorthSanctuary")
			var south: Node3D = assembly.get_node("SouthSanctuary")
			var chapel: Node3D = assembly.get_node("FuneraryChapel")
			var north_mesh: Mesh = north.get_node("OriginalArchitecture").mesh
			var south_mesh: Mesh = south.get_node("OriginalArchitecture").mesh
			_check(south_mesh.get_aabb().size.x>north_mesh.get_aabb().size.x*1.15,"flanking sanctuaries have different physical widths")
			_check(south_mesh.get_aabb().size.y>north_mesh.get_aabb().size.y*1.08,"flanking sanctuaries have different physical heights")
			var left: MeshInstance3D = chapel.get_node("HallDome0")
			var right: MeshInstance3D = chapel.get_node("HallDome1")
			_check(left.mesh.get_aabb().get_center().z<right.mesh.get_aabb().get_center().z-5.0,"funerary chapel contains two separate domed spans")
			_check(left.mesh.get_aabb().size.x<north_mesh.get_aabb().size.x*0.60,"funerary chapel is physically narrower than flanking church")
			var chapel_mesh: Mesh = chapel.get_node("OriginalArchitecture").mesh
			var r: float = float(dims.width_m)*0.084*0.45
			for sx in [-1.0,1.0]:
				for sz in [-1.0,1.0]:
					_check(_roof_hit(chapel_mesh,Vector2(sx*r*0.90,left.mesh.get_aabb().get_center().z+sz*r*0.90),float(dims.height_m)*0.5),"chapel square-to-dome spandrel has roof geometry")
			_check(_front_hit(chapel_mesh,Vector3(0,2,-float(dims.depth_m)*0.43*0.39),Vector3.UP,float(dims.height_m)),"chapel roof is visible from below between domes and end wall")
			for flank in [north,south]:
				var flank_mesh: Mesh = flank.get_node("OriginalArchitecture").mesh
				var flank_w: float = float(dims.width_m)*(0.19 if flank==north else 0.24)
				var flank_d: float = float(dims.depth_m)*(0.41 if flank==north else 0.49)
				for side in [-1.0,1.0]:
					_check(_front_hit(flank_mesh,Vector3(side*flank_w*0.335,2,flank_d*0.41),Vector3.BACK,flank_d*0.1),"flanking sanctuary rear aisle bay has an enclosing wall")
		if bool(dims.get("cruciform_five_domes",0)):
			var west: Node3D = assembly.get_node("WestArm")
			var east: Node3D = assembly.get_node("EastArm")
			_check(absf(west.position.z)>absf(east.position.z)+3.0,"cruciform church has a longer western arm")
			_check(assembly.has_node("CentralCrossing"),"cross has independent central crossing geometry")
			var crossing_mesh: Mesh = assembly.get_node("CentralCrossing").mesh
			var corner: float = float(dims.dome_radius_m)*1.30
			for sx in [-1.0,1.0]:
				for sz in [-1.0,1.0]:
					_check(_roof_hit(crossing_mesh,Vector2(sx*corner,sz*corner),float(dims.height_m)*0.50),"central crossing roof closes its corners")
			for arm_name in ["WestArm","EastArm","NorthArm","SouthArm"]:
				var arm: Node3D = assembly.get_node(arm_name)
				var roof: MeshInstance3D = arm.get_node("HallDome0")
				_check(roof.mesh.get_aabb().size.y>5.0,"each cruciform arm carries its own dome: "+arm_name)
				_check(not arm.has_node("HallDome1"),"one dome per cross arm: "+arm_name)
				var arm_mesh: Mesh = arm.get_node("OriginalArchitecture").mesh
				var arm_depth: float = arm_mesh.get_aabb().size.z
				_check(_front_hit(arm_mesh,Vector3(0,2,-arm_depth*0.38),Vector3.UP,float(dims.height_m)),"arm roof interval is visible from inside: "+arm_name)
				_check(_front_hit(arm_mesh,Vector3(float(dims.dome_radius_m)*1.15,2,0),Vector3.UP,float(dims.height_m)),"arm side roof is visible from inside: "+arm_name)
		assembly.queue_free()
		await process_frame
	print("LANDMARK CHECKS: %s checks, %s failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _roof_hit(mesh: Mesh, point: Vector2, minimum_y: float) -> bool:
	var origin := Vector3(point.x,200,point.y)
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0,indices.size(),3):
			var hit = Geometry3D.ray_intersects_triangle(origin,Vector3.DOWN,vertices[indices[index]],vertices[indices[index+1]],vertices[indices[index+2]])
			if hit != null and hit.y>minimum_y:
				return true
	return false

func _front_hit(mesh: Mesh, origin: Vector3, direction: Vector3, maximum: float) -> bool:
	# Rendering accepts the clockwise FRONT face. A double-sided mathematical
	# ray test alone can falsely approve a ceiling whose visible side faces up.
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0,indices.size(),3):
			var a: Vector3 = vertices[indices[index]]
			var b: Vector3 = vertices[indices[index+1]]
			var c: Vector3 = vertices[indices[index+2]]
			if (c-a).cross(b-a).dot(direction)>=-0.000001:
				continue
			var hit = Geometry3D.ray_intersects_triangle(origin,direction,a,b,c)
			if hit != null and origin.distance_to(hit)<maximum:
				return true
	return false

func _test_column_joints() -> void:
	for height in [6.0,18.0,30.0]:
		var builder = Landmarks.new()
		builder.g = load("res://src/geometry.gd").new({})
		var radius := 0.30
		builder._column(Vector3.ZERO,height,radius,"stone")
		var mesh: Mesh = builder.g.finish()
		var foot: float = minf(radius*0.65,height*0.08)
		for y in [foot*1.9+0.03,height-foot*2.1-0.03]:
			_check(_front_hit(mesh,Vector3(-radius*2,y,0),Vector3.RIGHT,radius*4),"column shaft joins base/capital continuously: "+str(height)+"/"+str(y))
