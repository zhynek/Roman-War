extends SceneTree
## Neutral material glTF derivatives of original parametric source. No images,
## campaign resources or procedural shader claims enter the interchange files.
var out_dir := "/tmp/constantinople-models"
var _meshes: Dictionary = {}

func _init() -> void:
	ProjectSettings.set_setting("application/config/custom_user_dir_name","Roman War Constantinople Model Export")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var city:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/city.json"))
	var world=load("res://src/world.gd").new()
	root.add_child(world)
	world.configure(city)
	var scene:=Node3D.new()
	scene.name="Constantinople1200InterpretiveCity"
	root.add_child(scene)
	_copy_geometry(world,scene,Transform3D.IDENTITY)
	if not _write(scene,out_dir.path_join("Constantinople-1200-City.glb")):
		quit(1)
		return
	scene.free()
	for id in world.landmark_nodes:
		var original:Node3D=world.landmark_nodes[id]
		var model:=Node3D.new()
		model.name=id
		root.add_child(model)
		# Each individual architecture derivative is centered at its local datum.
		for child in original.get_children():_copy_geometry(child,model,Transform3D.IDENTITY)
		if not _write(model,out_dir.path_join(String(id)+".glb")):
			quit(1)
			return
		model.free()
	var manifest:={"reference_year_ce":1200,"coordinate_system":"metres; Godot/glTF X east, Y up, -Z north","city_origin":"Hagia Sophia vicinity; interpretive local frame","source":"Original procedural city source; geometry authored with cited and interpretive dimensions","appearance":"Neutral PBR materials; procedural application shaders are not baked into these models","city_mesh":"Detailed landmarks and economical whole-city dwelling meshes; no claim of cadastral survey or CAD solid history","stats":world.stats,"landmarks":city["landmarks"]}
	var file:=FileAccess.open(out_dir.path_join("model-provenance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"  "))
	file.close()
	print("MODEL EXPORT PASS ",world.stats)
	world.queue_free()
	await process_frame
	quit(0)

func _copy_geometry(node:Node,parent:Node3D,inherited:Transform3D) -> void:
	var pose:=inherited
	if node is Node3D:pose=inherited*node.transform
	if node is MeshInstance3D:
		if node.mesh!=null and node.mesh.get_surface_count()>0:
			var copy:=MeshInstance3D.new()
			copy.name=node.name
			copy.mesh=_neutral_mesh(node.mesh,node.material_override)
			copy.transform=pose
			parent.add_child(copy)
	elif node is MultiMeshInstance3D:
		# Far building representation is sufficient for the whole-city exchange
		# mesh. Exporting both LODs would produce overlapping duplicate buildings.
		if node.visibility_range_end>0:return
		var multi:MultiMesh=node.multimesh
		var mesh:ArrayMesh=_neutral_mesh(multi.mesh,null)
		for i in range(multi.instance_count):
			var copy:=MeshInstance3D.new()
			copy.mesh=mesh
			copy.transform=pose*multi.get_instance_transform(i)
			parent.add_child(copy)
	for child in node.get_children():_copy_geometry(child,parent,pose)

func _neutral_mesh(source:Mesh,override:Material) -> ArrayMesh:
	var key:="%d_%d" % [source.get_instance_id(),0 if override==null else override.get_instance_id()]
	if _meshes.has(key):return _meshes[key]
	var mesh:=ArrayMesh.new()
	for i in range(source.get_surface_count()):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(i))
		var old:Material=override if override!=null else source.surface_get_material(i)
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=Color("b5a98d")
		mat.roughness=0.87
		if old is ShaderMaterial:
			var tint=old.get_shader_parameter("tint")
			if tint is Color:mat.albedo_color=tint
			if old.shader.resource_path.ends_with("water.gdshader"):
				mat.albedo_color=Color("25545f")
				mat.metallic=0.45
				mat.roughness=0.28
		elif old is StandardMaterial3D:
			mat.albedo_color=old.albedo_color
		mesh.surface_set_material(i,mat)
	_meshes[key]=mesh
	return mesh

func _write(scene:Node3D,path:String) -> bool:
	var document:=GLTFDocument.new()
	document.image_format="None"
	var state:=GLTFState.new()
	var error:=document.append_from_scene(scene,state)
	if error==OK:error=document.write_to_filesystem(state,path)
	if error!=OK:
		push_error("Model export failed: %s (%d)" % [path,error])
		return false
	print("EXPORTED ",path)
	return true
