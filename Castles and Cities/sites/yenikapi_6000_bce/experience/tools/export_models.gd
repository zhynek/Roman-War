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
	var household_rules=preload("res://src/core/settlement_rules.gd").new(JSON.parse_string(FileAccess.get_file_as_string("res://data/governance.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/neighbors.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/households.json")))
	for elapsed in [2,6]:
		var household_state:Dictionary=preload("res://tools/household_driver.gd").at_season(household_rules,elapsed)
		var household_world=load("res://src/village.gd").new();root.add_child(household_world);household_world.build(data)
		var view=preload("res://src/campaign_view.gd").new();root.add_child(view);view.refresh(household_state,household_rules,household_world)
		var phase:String=household_rules.households.stage(household_state)
		for station in household_rules.households.content.stations:
			var building:Dictionary={}
			for record in household_world.buildings:
				if record.id==station.building:building=record;break
			var room:=Node3D.new();room.name=station.id+"_"+phase;root.add_child(room)
			var origin:Transform3D=household_world.object_nodes[station.building].transform
			for id in [station.building,"household_interior_"+station.building]:
				var original:MeshInstance3D=household_world.object_nodes[id]
				var copy:=MeshInstance3D.new();copy.name=id;copy.transform=origin.affine_inverse()*original.transform;copy.mesh=neutral_mesh(original.mesh);room.add_child(copy)
			if not write_model(room,out_dir.path_join("household-"+phase+"-"+station.building+".glb")):quit(1);return
			room.free()
		FileAccess.open(out_dir.path_join("household-"+phase+"-provenance.json"),FileAccess.WRITE).store_string(JSON.stringify({"status":"Hypothetical portable interior arrangements; no archaeological inventory or siege reconstruction","state":household_state,"models":"Three furnished rooms centered at original building datum. Citizens, lighting, procedural shaders and simulation are available in the app/source, not these static GLBs."},"  "))
		view.free();household_world.free()
	var asset_rules=preload("res://src/core/settlement_rules.gd").new(_read("governance"),_read("balance"),_read("neighbors"),_read("households"),_read("assets"))
	for specimen in ["stocked-store","empty-store","repair-workroom"]:
		var asset_state: Dictionary=preload("res://tools/asset_driver.gd").at_season(asset_rules,9)
		if specimen=="empty-store":asset_state.food=0
		if specimen=="repair-workroom":asset_state.assets.conditions.workroom=35
		asset_state.plan=asset_rules.effective_plan(asset_state)
		var asset_data: Dictionary=preload("res://src/campaign_view.gd").snapshot(data,asset_state,asset_rules)
		var asset_world=load("res://src/village.gd").new();root.add_child(asset_world);asset_world.build(asset_data)
		var view=preload("res://src/campaign_view.gd").new();root.add_child(view);view.refresh(asset_state,asset_rules,asset_world)
		var building_id: String="yk_house_06" if specimen=="repair-workroom" else "yk_store_01"
		var room:=Node3D.new();room.name="asset_"+specimen;root.add_child(room)
		var origin: Transform3D=asset_world.object_nodes[building_id].transform
		for id in [building_id,"household_interior_"+building_id]:
			var original: MeshInstance3D=asset_world.object_nodes[id]
			var copy:=MeshInstance3D.new();copy.name=id;copy.transform=origin.affine_inverse()*original.transform;copy.mesh=neutral_mesh(original.mesh);room.add_child(copy)
		if not write_model(room,out_dir.path_join("asset-"+specimen+".glb")):quit(1);return
		FileAccess.open(out_dir.path_join("asset-"+specimen+"-provenance.json"),FileAccess.WRITE).store_string(JSON.stringify({"status":"Hypothetical management specimen; empty supplies and neglected workroom are explicitly authored comparison states, not a playthrough or archaeological inventory","state":asset_state},"  "))
		room.free();view.free();asset_world.free()
	var land_rules=preload("res://src/core/settlement_rules.gd").new(_read("governance"),_read("balance"),_read("neighbors"),_read("households"),_read("assets"),_read("land"))
	for compact in [true,false]:
		var land_state: Dictionary=preload("res://tools/land_driver.gd").at_season(land_rules,compact,32)
		var layout: String="compact" if compact else "outward"
		var land_data: Dictionary=preload("res://src/campaign_view.gd").snapshot(data,land_state,land_rules)
		var land_world=load("res://src/village.gd").new();root.add_child(land_world);land_world.build(land_data)
		var view=preload("res://src/campaign_view.gd").new();root.add_child(view);view.refresh(land_state,land_rules,land_world)
		var model:=Node3D.new();model.name="Land"+layout;root.add_child(model)
		for id in land_world.object_nodes:
			var original: MeshInstance3D=land_world.object_nodes[id]
			var copy:=MeshInstance3D.new();copy.name=id;copy.transform=original.transform;copy.mesh=neutral_mesh(original.mesh);model.add_child(copy)
		if not write_model(model,out_dir.path_join("land-"+layout+"-settlement.glb")):quit(1);return
		if compact:
			var room:=Node3D.new();room.name="AdaptedWorkroom";root.add_child(room)
			var origin: Transform3D=land_world.object_nodes.yk_house_06.transform
			for id in ["yk_house_06","household_interior_yk_house_06"]:
				var original: MeshInstance3D=land_world.object_nodes[id]
				var copy:=MeshInstance3D.new();copy.name=id;copy.transform=origin.affine_inverse()*original.transform;copy.mesh=neutral_mesh(original.mesh);room.add_child(copy)
			if not write_model(room,out_dir.path_join("land-adapted-workroom.glb")):quit(1);return
			room.free()
		FileAccess.open(out_dir.path_join("land-"+layout+"-provenance.json"),FileAccess.WRITE).store_string(JSON.stringify({"status":"Hypothetical spatial strategy from the same village, 32 real seasons; no resource grants. Dated reference is separate.","state":land_state,"fabric":land_data.objects,"models":"Neutral static geometry; original shaders, autonomous citizens and seasonal rules remain in application/source."},"  "))
		model.free();view.free();land_world.free()
	var living_rules=preload("res://src/core/settlement_rules.gd").new(_read("governance"),_read("balance"),_read("neighbors"),_read("households"),_read("assets"),_read("land"),_read("living"))
	var living_state: Dictionary=preload("res://tools/living_driver.gd").at_season(living_rules,20)
	var living_data: Dictionary=preload("res://src/campaign_view.gd").snapshot(data,living_state,living_rules)
	var living_world=load("res://src/village.gd").new();root.add_child(living_world);living_world.build(living_data)
	var living_view=preload("res://src/campaign_view.gd").new();root.add_child(living_view);living_view.refresh(living_state,living_rules,living_world)
	for specimen in ["village","working-room","northern-post"]:
		var model:=Node3D.new();model.name="LivingVillage";root.add_child(model)
		var origin:=Transform3D.IDENTITY
		if specimen=="working-room":origin=living_world.object_nodes.yk_house_06.transform
		if specimen=="northern-post":origin=living_world.object_nodes.living_detail_north_post.transform
		for id in living_world.object_nodes:
			if specimen=="working-room" and id not in ["yk_house_06","household_interior_yk_house_06"]:continue
			if specimen=="northern-post" and id!="living_detail_north_post":continue
			var original: MeshInstance3D=living_world.object_nodes[id]
			var copy:=MeshInstance3D.new();copy.name=id;copy.transform=origin.affine_inverse()*original.transform;copy.mesh=neutral_mesh(original.mesh);model.add_child(copy)
		if not write_model(model,out_dir.path_join("living-"+specimen+".glb")):quit(1);return
		model.free()
	FileAccess.open(out_dir.path_join("living-provenance.json"),FileAccess.WRITE).store_string(JSON.stringify({"status":"Hypothetical paid work, shared preparation and wooden watch kits; not archaeological weapon reconstruction","state":living_state,"fabric":living_data.objects,"models":"Neutral geometry only. Citizens, seasonal rules and original shaders remain in the app/source."},"  "))
	living_view.free();living_world.free()
	print("VILLAGE MODEL EXPORT PASS: 33 GLBs")
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

func _read(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/"+id+".json"))
