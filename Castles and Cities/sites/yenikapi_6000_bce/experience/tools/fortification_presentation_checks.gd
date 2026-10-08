extends SceneTree
## Paid screen geometry and ordinary-village access, through public commands.
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const ReadModel=preload("res://src/project_presentation.gd")
var app
var r
var checks: int=0
var failures: int=0
var render: bool=false
var out_dir: String="/tmp/village-fortification-presentation"
var captures: Array=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="render":render=true
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var result: Dictionary=r.command(s,a)
	check(result.has("state"),str(a)+": "+str(result.get("error","")))
	return result.get("state",s)
func show(s: Dictionary) -> void:
	app.campaign.state=s;app.show_campaign(s,r);app.visual_commands.open()
func access(id: String,stage: int) -> void:
	var records: Array=app.visual_commands.boundary_records(id)
	var first: Array=records[0].points.back();var second: Array=records[1].points.front()
	var point: Vector2=(Vector2(first[0],first[1])+Vector2(second[0],second[1]))*.5
	app.campaign_view.construction_view.select(id)
	var outline: PackedVector3Array=app.campaign_view.construction_view.connections.get_child(0).mesh.get_faces()
	var spans_gate: bool=false
	for i in range(0,outline.size(),3):
		var low: float=minf(outline[i].z,minf(outline[i+1].z,outline[i+2].z))
		var high: float=maxf(outline[i].z,maxf(outline[i+1].z,outline[i+2].z))
		if low<point.y and high>point.y:spans_gate=true
	check(not spans_gate,"selection outline preserves visible gate "+id+" stage "+str(stage))
	var start:=Vector3(point.x-2,app.world.floor_height(point.x-2,point.y)+1.68,point.y)
	var reached: Vector3=app.world.walk(start,Vector3(4,0,0))
	check(Vector2(reached.x-(start.x+4),reached.z-start.z).length()<.1,"authored gate stays open "+id+" stage "+str(stage))
	var life=app.campaign_view.life
	check(life.unreachable.is_empty(),"ordinary residents keep reachable work "+id+" stage "+str(stage))
	for routine in life.routines:
		for i in range(1,routine.route.size()):
			var from: Vector3=routine.route[i-1]+Vector3.UP*1.68;var to: Vector3=routine.route[i]+Vector3.UP*1.68
			var actual: Vector3=app.world.walk(from,to-from)
			check(Vector2(actual.x-to.x,actual.z-to.z).length()<.1,"actual resident route remains walkable "+routine.id+" "+id+" stage "+str(stage))
func run() -> void:
	if render:root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame;r=app.campaign.rules
	var model:=ReadModel.new()
	var s: Dictionary=Living.at_season(r,12,true);show(s)
	var ids: Array=r.warfare.forts.projects.keys();ids.sort()
	for id in ids:
		check(id not in model.ids(s,r) and id not in app.visual_commands.project_ids("watch"),"unadopted paid screen hidden "+id)
	s=cmd(s,{"kind":"warfare_begin"});show(s)
	var prepared: Dictionary=s.duplicate(true)
	for id in ids:
		# Exercise each paid project from the same ordinary village: later elections
		# can legitimately change work yield and skip a quarter-stage in one season.
		s=prepared.duplicate(true);show(s)
		check(id in model.ids(s,r) and id in app.visual_commands.project_ids("watch"),"adopted paid screen discoverable "+id)
		var original: String=JSON.stringify(s)
		check(app.visual_commands.preview_mesh(id,false)==null,"unbuilt current preview has no unrelated watch shelter "+id)
		var planned: Mesh=app.visual_commands.preview_mesh(id,true)
		var production=preload("res://src/village.gd").new();production.data=app.world.data;production.materials=app.world.materials;production.buildings=app.world.buildings
		var expected:=PackedVector3Array()
		for record in app.visual_commands.boundary_records(id):
			production._boundary(record);expected.append_array(production.object_nodes[record.id].mesh.get_faces())
		check(planned!=null and planned.get_faces()==expected,"planned preview is both exact production screen segments "+id)
		production.free()
		check(JSON.stringify(s)==original,"planned preview spends no resources "+id)
		var price: int=int(r.projects[id].wood);var before_wood: int=s.wood
		s=cmd(s,{"kind":"commission","id":id})
		check(s.wood==before_wood-price,"screen pays existing timber price "+id)
		s=cmd(s,{"kind":"asset_project","id":id,"crew":1,"priority":1,"paused":false})
		var seen: Array=[]
		for season in range(24):
			show(s)
			var d: Dictionary=model.describe(s,r,id,r.forecast(s))
			if int(d.stage) not in seen:
				seen.append(int(d.stage));access(id,int(d.stage))
				for record in app.visual_commands.boundary_records(id):check(record.id in d.affected,"screen record maps to its selectable project "+record.id)
				if d.queued:
					var site: Dictionary=app.campaign_view.construction_view.sites[id]
					check(site.stage==d.stage and site.treatment=="screen","site shows actual paid queue stage "+id)
					check(app.visual_commands.site_preview(id)!=null,"current preview is partial screen fabric "+id)
				if render:
					app.visual_commands.show_project(id)
					app.visual_commands.preview_stage="current";app.visual_commands.refresh()
					app.set_view(Vector3(r.projects[id].at[0]+12,15,r.projects[id].at[1]+12),Vector3(r.projects[id].at[0]-2,1,r.projects[id].at[1]))
					await shot(id+"-stage-"+str(d.stage))
					app.visual_commands.close_sheet()
					await shot(id+"-world-stage-"+str(d.stage))
			if d.complete:break
			var next: Dictionary=r.advance(s)
			check(next.has("state"),"ordinary seasonal screen work advances "+id)
			if not next.has("state"):break
			s=next.state
		check(seen==[0,1,2,3,4],"all screen stages reached through finite ordinary work "+id+": "+str(seen))
		show(s)
		var actual: Mesh=app.visual_commands.preview_mesh(id,false)
		var finished: Mesh=app.visual_commands.preview_mesh(id,true)
		check(actual!=null and finished!=null and actual.get_faces()==finished.get_faces(),"completed current/planned preview agree on both actual segments "+id)
		if render:
			app.visual_commands.show_project(id);app.visual_commands.preview_stage="planned";app.visual_commands.refresh();await shot(id+"-planned-pair")
	check(r.validate_state(s),"paid screens preserve a valid continuing village")
	if render:FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"  "))
	print("FORTIFICATION PRESENTATION: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func shot(name_: String) -> void:
	for i in range(8):await process_frame;RenderingServer.force_draw(true)
	check(root.get_texture().get_image().save_png(out_dir.path_join(name_+".png"))==OK,"capture "+name_)
	captures.append(name_)
