extends SceneTree
const Driver=preload("res://tools/neighbor_driver.gd")
var app
var out_dir:String="/tmp/yenikapi-neighbor-qa"
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
	panel.save_path=out_dir.path_join("contacts-test.json")
	panel.begin();panel.open();panel.tabs.current_tab=5
	check(panel.find_child("BeginNeighbors",true,false).disabled,"new chapter locked for starting village")
	await shot("01-locked-chapter")
	panel.state=Driver.foundation(panel.rules);panel.open();panel.tabs.current_tab=5
	await click_button("BeginNeighbors")
	check(panel.rules.neighbors.active(panel.state),"begin chapter through real UI")
	await shot("02-neighbor-ledger")
	await click_button("Neighbor_oakrise")
	await click_button("SendTrade")
	check(not panel.state.contacts.mission.is_empty(),"dispatch exchange through real UI")
	await shot("03-dispatched-mission")
	await click_button("ResolveSeason")
	check(panel.state.contacts.mission.remaining==1,"journey advances exactly one season")
	check(panel.save_campaign(),"save in-flight through UI")
	var saved:String=JSON.stringify(panel.state)
	panel.resolve_season()
	check(panel.load_campaign() and JSON.stringify(panel.state)==saved,"load in-flight through UI restores escrow")
	await shot("04-journey-resumed")
	for i in range(16):
		panel.state=Driver.orders(panel.rules,panel.state)
		panel.resolve_season()
		if panel.state.contacts.chapter_complete:break
	check(panel.state.contacts.chapter_complete,"contact tutorial can be completed")
	panel.tabs.current_tab=5;await shot("05-contact-chapter-complete")
	panel.hide();app.hud.hide();app.set_view(Vector3(90,80,127),Vector3(-8,2,12));await shot("06-contact-landscape")
	for b in app.world.buildings:
		var start:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5+1.4))
		var target:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5-.6))
		var reached:Vector3=app.world.walk(start,target-start)
		check(Vector2(reached.x-target.x,reached.z-target.z).length()<.1,"contact entry "+b.id)
		var out:Vector3=app.world.walk(reached,start-reached)
		check(Vector2(out.x-start.x,out.z-start.z).length()<.1,"contact exit "+b.id)
		if b.id=="growth_exchange_house":
			app.set_view(start+Vector3(4,.1,4),app.world.building_position(b,Vector3(0,1.4,0)),false);await shot("07-meeting-place-street")
			app.set_view(reached,app.world.building_position(b,Vector3(0,1.2,-1)),false);await shot("08-meeting-room-interior")
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
		check(passable,"contact walking path "+path.id)
	app.hud.show();panel.open();panel.tabs.current_tab=5;root.size=Vector2i(1280,800);await shot("09-small-window-neighbors")
	check(panel.get_global_rect().end.y<=root.get_visible_rect().size.y and panel.get_global_rect().position.x>=0,"contact pane fits smaller window")
	var visit:Button=panel.find_child("VisitMeeting",true,false)
	panel.tabs.get_child(5).ensure_control_visible(visit)
	await shot("10-small-window-escort-controls")
	await click_button("VisitMeeting")
	check(not panel.visible and not app.flying and not app.world.blocked(app.camera.position),"meeting navigation enters safe walking mode")
	var before:String=JSON.stringify(panel.state)
	for i in range(60):await process_frame
	check(JSON.stringify(panel.state)==before,"contact animation cannot advance simulation")
	app.show_reference();check(app.world.buildings.size()==9,"original reference preserved")
	panel.open();check(app.world.buildings.size()==14,"contact fabric restored")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"turn":panel.state.turn,"stats":app.world.stats},"  "))
	print("NEIGHBOR RENDER: ",captures.size()," captures; ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func click_button(id:String) -> void:
	for i in range(3):await process_frame
	var button:Button=app.campaign.find_child(id,true,false)
	if button==null:check(false,"missing button "+id);return
	var parent:Node=button.get_parent()
	while parent!=null:
		if parent is ScrollContainer:parent.ensure_control_visible(button)
		parent=parent.get_parent()
	for i in range(3):await process_frame
	var at:Vector2=button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true)
		for i in range(3):await process_frame
func shot(name_:String) -> void:
	for i in range(12):await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(out_dir.path_join(name_+".png"))==OK,"capture "+name_)
	captures.append(name_);print("CAPTURE ",name_)
