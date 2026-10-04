extends SceneTree
## Regression gate for roads/aprons crossing terrain cell creases, and cistern caps.
const World = preload("res://src/world.gd")
const Geometry = preload("res://src/geometry.gd")
var checks:=0
var failures:Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func _check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL: ",label)

func _run() -> void:
	# A sharp synthetic ridge makes a corner-only sampler fail decisively.
	var ridge=World.new()
	ridge.visuals={"terrain_grid_m":10.0}
	ridge._terrain_origin=Vector2.ZERO
	ridge._terrain_stride=3
	ridge._terrain_rows=3
	for j in range(3):
		for i in range(3):ridge._terrain_points.append(Vector3(i*10,10 if i==1 and j==1 else 0,-j*10))
	var a:=Vector3(1,0,-1)
	var b:=Vector3(19,0,-1)
	var c:=Vector3(1,0,-19)
	var builder=Geometry.new()
	ridge._ground_triangle(builder,a,b,c,0.22,"road")
	var mesh:ArrayMesh=builder.finish()
	var good:Dictionary=_clearance(mesh,ridge,0.22)
	_check(int(good.samples)>3 and float(good.worst)<0.005,"tessellated surface follows both halves of a sharp ridge")
	var legacy=Geometry.new()
	a.y=ridge._surface_height(a.x,-a.z)+0.22
	b.y=ridge._surface_height(b.x,-b.z)+0.22
	c.y=ridge._surface_height(c.x,-c.z)+0.22
	legacy.triangle(a,b,c,"road")
	var bad:Dictionary=_clearance(legacy.finish(),ridge,0.22)
	_check(float(bad.worst)>1.0,"negative control catches roads sunk through a terrain crease")
	ridge.urban.free()
	ridge.additions.free()
	ridge.free()
	var city=World.new()
	root.add_child(city)
	city.data=JSON.parse_string(FileAccess.get_file_as_string("res://data/city.json"))
	city.visuals=JSON.parse_string(FileAccess.get_file_as_string("res://data/visuals.json"))
	city.stats={"road_segments":0,"landmark_count":0}
	city._materials()
	city._terrain()
	city._roads()
	city._reservoir_paths()
	city._fields()
	city._landmarks()
	var total:=0
	for node in city.get_children():
		if not node is MeshInstance3D:continue
		if str(node.name).begins_with("StreetsAndProcessionalRoutes") or str(node.name)=="WesternCultivation":
			var expected:=0.1 if str(node.name)=="WesternCultivation" else 0.22
			var report:Dictionary=_clearance(node.mesh,city,expected)
			total+=int(report.samples)
			_check(float(report.worst)<0.025,"ground clearance stays constant across every surface triangle: "+str(node.name)+" worst "+str(report.worst))
	_check(total>1000,"real roads, basin access and fields sampled extensively")
	_check(city._cutaway_caps.size()==1,"only the enclosed reservoir has a ground cover")
	for cap in city._cutaway_caps:
		var cistern:Node3D=city.landmark_nodes.basilica_cistern
		var roof:MeshInstance3D=cistern.get_node("CisternVaultRoof")
		_check(cap.mesh.get_aabb().size.x<=70.01 and cap.mesh.get_aabb().size.z<=140.01,"cistern cover cannot span and bury neighboring roads")
		_check(cap.position.y>cistern.position.y+roof.mesh.get_aabb().end.y,"ground cover clears the actual roof geometry")
	city.urban.free()
	city.additions.free()
	city.free()
	print("SURFACE CHECKS: %d checks, %d failures, %d real samples" % [checks,failures.size(),total])
	quit(0 if failures.is_empty() else 1)

func _clearance(mesh:Mesh,world:Node3D,expected:float) -> Dictionary:
	var worst:=0.0
	var samples:=0
	for s in range(mesh.get_surface_count()):
		var arrays:=mesh.surface_get_arrays(s)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var count:=indices.size() if not indices.is_empty() else vertices.size()
		for index in range(0,count,3):
			var points:Array[Vector3]=[]
			for offset in range(3):points.append(vertices[indices[index+offset] if not indices.is_empty() else index+offset])
			# Interior samples, not just the already-grounded mesh vertices.
			for weights in [Vector3.ONE/3.0,Vector3(0.6,0.2,0.2),Vector3(0.2,0.6,0.2),Vector3(0.2,0.2,0.6)]:
				var p:Vector3=points[0]*weights.x+points[1]*weights.y+points[2]*weights.z
				worst=maxf(worst,absf(p.y-world._surface_height(p.x,-p.z)-expected))
				samples+=1
	return {"worst":worst,"samples":samples}
