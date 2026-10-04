extends SceneTree
const Driver=preload("res://tools/tutorial_driver.gd")
var app
var out_dir:String="/tmp/yenikapi-governance-qa"
var captures:Array=[]
var failures:int=0
var checks:int=0
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await process_frame
	var panel=app.campaign
	panel.save_path=out_dir.path_join("campaign-test.json")
	panel.open();await shot("01-tutorial-introduction")
	await click_button("BeginTutorial")
	check(not panel.state.is_empty(),"actual begin button")
	if panel.state.is_empty():quit(1);return
	await shot("02-first-season-guide")
	panel.tabs.current_tab=1;await shot("03-workforce-projects")
	panel.dispatch({"kind":"policy","welcome":true,"tight_rations":false})
	panel.tabs.current_tab=0
	panel._suggest()
	await click_button("RecommendedProject")
	panel._suggest()
	await click_button("ResolveSeason")
	check(panel.state.turn==1,"actual seasonal resolve button")
	panel.hide();app.visit(1);await shot("04-citizen-work-orders")
	var unchanged:String=JSON.stringify(panel.state)
	for i in range(60):await process_frame
	check(JSON.stringify(panel.state)==unchanged,"animation cannot change simulation")
	panel.open()
	for turn in range(1,24):
		# Drive the same public UI command boundary, without fabricating resources.
		if panel.state.queue.is_empty():
			var id:String=panel.recommended_project()
			if not id.is_empty() and panel.state.wood>=panel.rules.projects[id].wood:
				check(panel.dispatch({"kind":"commission","id":id}),"commission "+id)
		panel._suggest()
		check(panel.resolve_season(),"resolve season "+str(turn+1))
		await process_frame
		if turn==8:
			panel.tabs.current_tab=1;await shot("05-multi-season-projects")
		if turn==15:
			panel.tabs.current_tab=2;await shot("06-leadership-succession")
		if panel.state.phase=="town":break
	check(panel.state.phase=="town","tutorial reaches town via user commands")
	panel.tabs.current_tab=0;await shot("07-town-milestone")
	check(panel.save_campaign(),"save through campaign UI")
	var saved:String=JSON.stringify(panel.state)
	panel.resolve_season()
	check(panel.load_campaign() and JSON.stringify(panel.state)==saved,"save/resume exactly restores state")
	panel.tabs.current_tab=3;await shot("08-season-journal")
	panel.hide();app.hud.hide();app.overview();await shot("09-grown-town-aerial")
	app.set_view(Vector3(-22,7,-16),Vector3(-12,4,-37));await shot("10-new-households-street")
	# Enter every building in the actually grown world, then inspect a new home.
	for b in app.world.buildings:
		var start:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5+1.4))
		var target:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5-.6))
		var reached:Vector3=app.world.walk(start,target-start)
		check(Vector2(reached.x-target.x,reached.z-target.z).length()<.1,"grown entry "+b.id)
		var out:Vector3=app.world.walk(reached,start-reached)
		check(Vector2(out.x-start.x,out.z-start.z).length()<.1,"grown exit "+b.id)
		if b.id=="growth_home_north":
			app.set_view(reached,app.world.building_position(b,Vector3(0,1.2,-1)),false);await shot("11-new-home-interior")
	# New lanes remain connected and walkable along their actual drawn centerline.
	for path in app.data.objects:
		if path.kind!="path":continue
		var points:Array=path.points;var walker:=Vector3(points[0][0],0,points[0][1]);walker.y=app.world.floor_height(walker.x,walker.z)+1.68
		var passable:bool=true
		for i in range(points.size()-1):
			var a:=Vector2(points[i][0],points[i][1]);var b:=Vector2(points[i+1][0],points[i+1][1]);var prior:=Vector2(points[maxi(0,i-1)][0],points[maxi(0,i-1)][1]);var after:=Vector2(points[mini(points.size()-1,i+2)][0],points[mini(points.size()-1,i+2)][1])
			for j in range(1,41):
				var point:Vector2=a.cubic_interpolate(b,prior,after,float(j)/40)
				walker=app.world.walk(walker,Vector3(point.x-walker.x,0,point.y-walker.z))
				if Vector2(walker.x-point.x,walker.z-point.y).length()>.1:passable=false
		check(passable,"grown walking path "+path.id)
	app.hud.show();panel.open();root.size=Vector2i(1280,800);panel.tabs.current_tab=0;await shot("12-small-window-guide")
	check(panel.get_global_rect().end.y<=root.get_visible_rect().size.y,"panel stays within window")
	check(panel.get_global_rect().position.x>=0,"panel fits width")
	# Role selection and rejection preserve state; reference mode leaves campaign in memory.
	panel.dispatch({"kind":"role","role":"watch"});check(panel.state.role=="watch","role switch")
	var before:String=JSON.stringify(panel.state)
	check(not panel.dispatch({"kind":"policy","welcome":false,"tight_rations":false}) and JSON.stringify(panel.state)==before,"wrong office rejected in UI")
	app.show_reference();panel.hide();check(app.world.buildings.size()==9,"reference restores nine original buildings")
	panel.open();check(app.world.buildings.size()==13,"resume restores grown village")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"turn":panel.state.turn,"population":panel.rules.people(panel.state).size(),"stats":app.world.stats},"  "))
	print("GOVERNANCE RENDER: ",captures.size()," captures; ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func click_button(id:String) -> void:
	for i in range(3):await process_frame
	var button:Button=app.campaign.find_child(id,true,false)
	if button==null:check(false,"missing button "+id);return
	var at:Vector2=button.get_global_rect().get_center()
	print("CLICK ",id," ",at," rect ",button.get_global_rect())
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event)
		for i in range(3):await process_frame

func shot(name_:String) -> void:
	for i in range(12):await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(out_dir.path_join(name_+".png"))==OK,"capture "+name_)
	captures.append(name_);print("CAPTURE ",name_)
