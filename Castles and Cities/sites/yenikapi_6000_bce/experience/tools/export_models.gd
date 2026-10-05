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
	# Export a reproducible hypothetical milestone separately from the dated reference.
	var rules=preload("res://src/core/settlement_rules.gd").new(JSON.parse_string(FileAccess.get_file_as_string("res://data/governance.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json")))
	var state:Dictionary=rules.new_state()
	for i in range(40):
		state=preload("res://tools/tutorial_driver.gd").orders(rules,state)
		state=rules.advance(state).state
		if state.phase=="town":break
	if state.phase!="town":push_error("Model tutorial did not reach milestone");quit(1);return
	var town_data:Dictionary=preload("res://src/campaign_view.gd").snapshot(data,state,rules)
	var town=load("res://src/village.gd").new();root.add_child(town);town.build(town_data)
	var town_scene:=Node3D.new();town_scene.name="YenikapiHypotheticalTown";root.add_child(town_scene)
	for id in town.object_nodes:
		var original:MeshInstance3D=town.object_nodes[id]
		var copy:=MeshInstance3D.new();copy.name=id;copy.transform=original.transform;copy.mesh=neutral_mesh(original.mesh);town_scene.add_child(copy)
		if id in ["growth_care_shelter","growth_watch_shelter","growth_home_north","growth_home_east","yk_store_01"]:
			var local:=MeshInstance3D.new();local.name=id;local.mesh=copy.mesh;root.add_child(local)
			if not write_model(local,out_dir.path_join(id+("-revision-2" if id=="yk_store_01" else "")+".glb")):quit(1);return
			local.free()
	if not write_model(town_scene,out_dir.path_join("Yenikapi-Hypothetical-Town.glb")):quit(1);return
	FileAccess.open(out_dir.path_join("hypothetical-town-provenance.json"),FileAccess.WRITE).store_string(JSON.stringify({"scenario_id":rules.content.scenario_id,"status":"Hypothetical playable town milestone, not dated archaeology","state":state,"fabric":town_data.objects,"citizen_meshes":"Not included; application animates original stylized representations"},"  "))
	FileAccess.open(out_dir.path_join("model-provenance.json"),FileAccess.WRITE).store_string(JSON.stringify({"snapshot":data,"status":"Original interpretive geometry, not a survey or recovered village plan","coordinates":"metres; X east, Y up, Z south; local sea y=0, no surveyed datum","materials":"Neutral PBR derivatives, no procedural shader, lights, water animation or controller","individual_models":"Nine building models centered at their own ground datum; whole-village model preserves placement"},"  "))
	var contact_rules=preload("res://src/core/settlement_rules.gd").new(JSON.parse_string(FileAccess.get_file_as_string("res://data/governance.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/neighbors.json")))
	var contact_state:Dictionary=preload("res://tools/neighbor_driver.gd").foundation(contact_rules)
	var contact_data:Dictionary=preload("res://src/campaign_view.gd").snapshot(data,contact_state,contact_rules)
	var contact_world=load("res://src/village.gd").new();root.add_child(contact_world);contact_world.build(contact_data)
	var contact_scene:=Node3D.new();contact_scene.name="YenikapiHypotheticalContactSettlement";root.add_child(contact_scene)
	for id in contact_world.object_nodes:
		var original:MeshInstance3D=contact_world.object_nodes[id]
		var copy:=MeshInstance3D.new();copy.name=id;copy.transform=original.transform;copy.mesh=neutral_mesh(original.mesh);contact_scene.add_child(copy)
		if id=="growth_exchange_house":
			var local:=MeshInstance3D.new();local.name=id;local.mesh=copy.mesh;root.add_child(local)
			if not write_model(local,out_dir.path_join(id+".glb")):quit(1);return
			local.free()
	if not write_model(contact_scene,out_dir.path_join("Yenikapi-Hypothetical-Contact-Settlement.glb")):quit(1);return
	FileAccess.open(out_dir.path_join("hypothetical-contact-provenance.json"),FileAccess.WRITE).store_string(JSON.stringify({"scenario_id":contact_rules.content.scenario_id,"status":"Hypothetical meeting place, not a dated market reconstruction or neighboring village","state":contact_state,"fabric":contact_data.objects},"  "))
	print("VILLAGE MODEL EXPORT PASS: 18 GLBs")
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
