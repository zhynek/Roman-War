extends SceneTree
var out_dir:="/tmp/yenikapi-models"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settlement.json"))
	var world=load("res://src/village.gd").new()
	root.add_child(world);world.build(data)
	var scene:=Node3D.new();scene.name="YenikapiInterpretiveEarlySettlement"
	root.add_child(scene)
	for id in world.object_nodes:
		var original:MeshInstance3D=world.object_nodes[id]
		var copy:=MeshInstance3D.new();copy.name=id;copy.transform=original.transform
		copy.mesh=neutral_mesh(original.mesh);scene.add_child(copy)
		if id.begins_with("yk_house_") or id.begins_with("yk_store_"):
			var local:=MeshInstance3D.new();local.name=id;local.mesh=copy.mesh
			root.add_child(local)
			if not write_model(local,out_dir.path_join(id+".glb")):quit(1);return
			local.free()
	if not write_model(scene,out_dir.path_join("Yenikapi-Early-Settlement.glb")):quit(1);return
	FileAccess.open(out_dir.path_join("model-provenance.json"),FileAccess.WRITE).store_string(JSON.stringify({"snapshot":data,"status":"Original interpretive geometry, not a survey or recovered village plan","coordinates":"metres; X east, Y up, Z south; local sea y=0, no surveyed datum","materials":"Neutral PBR derivatives, no procedural shader, lights, water animation or controller","individual_models":"Nine building models centered at their own ground datum; whole-village model preserves placement"},"  "))
	print("VILLAGE MODEL EXPORT PASS: 10 GLBs")
	quit()
func neutral_mesh(source:ArrayMesh) -> ArrayMesh:
	var mesh:=ArrayMesh.new()
	for i in range(source.get_surface_count()):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(i))
		var old:ShaderMaterial=source.surface_get_material(i)
		var material:=StandardMaterial3D.new();material.roughness=.9
		var pigment:Variant=old.get_shader_parameter("pigment")
		material.albedo_color=pigment if pigment is Color else Color("707b55")
		if old.shader.resource_path.ends_with("water.gdshader"):material.albedo_color=Color("3d666b");material.roughness=.3
		mesh.surface_set_material(i,material)
	return mesh
func write_model(scene:Node3D,path:String) -> bool:
	var document:=GLTFDocument.new();document.image_format="None"
	var state:=GLTFState.new()
	var result:int=document.append_from_scene(scene,state)
	if result==OK:result=document.write_to_filesystem(state,path)
	if result!=OK:push_error("GLB export failed "+path);return false
	print("EXPORTED ",path)
	return true
