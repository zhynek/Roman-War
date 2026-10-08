extends SceneTree
## Read-only guide/navigation checks with public-command civic and battle fixtures.
const Driver=preload("res://tools/town_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const Saves=preload("res://src/campaign_save.gd")
const Presentation=preload("res://src/project_presentation.gd")
var app
var checks: int=0
var failures: int=0
var out_dir: String="/tmp/village-integration-guide-headless"
var captures: Array=[]
var rendered: bool=false
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func texts(node: Node) -> Array:
	var found: Array=[]
	if node is Label or node is Button:found.append(node.text)
	for child in node.get_children():found.append_array(texts(child))
	return found
func click(id: String) -> void:
	var button=app.find_child(id,true,false)
	check(button is Button and not button.disabled,"usable control "+id)
	if button is Button and not button.disabled:button.pressed.emit()
	await process_frame;await process_frame
func shot(_id: String) -> void:await process_frame
func setup_shot() -> void:await process_frame
func show(s: Dictionary) -> void:
	if app.defense_panel.active_ui:app.defense_panel.close()
	app.campaign.state=s.duplicate(true);app.show_campaign(app.campaign.state,app.campaign.rules);app.visual_commands.open()
	await process_frame
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size=Vector2i(1280,800)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var r=app.campaign.rules;var p=app.campaign;var ui=app.visual_commands
	var hashes: Dictionary={"lifecycle":r.lifecycle.definition_hash,"town":r.lifecycle.town_hash,"defense":r.defense.definition_hash,"warfare":r.warfare.definition_hash,"paid_fixture":FileAccess.get_sha256("res://tools/fixtures/lifecycle-0.11-paid.json")}
	var expected: Dictionary={"lifecycle":"a4694114cc755d8f5a2113daabf71370a8b85824acc1317dbe973c3555f1fe35","town":"a5c1d5628d3e0a2950bdada2ae781ede5ea9c6e5071a864397887d30acdbd48c","defense":"6c42d4fcdfc6fa6eb4e2f4c38a5c7c6d9bd12fa5480d4818037350486ba9ae2d","warfare":"fea10f9e4c702c6ac82b3469e6cc62d61d69993d67918734ba9daec7d9d960a4","paid_fixture":"b0e0af7a47ffe5febe15d189bce0d4ffcb988180112dbf0412da293d607ae872"}
	for key in expected:check(hashes[key]==expected[key],"published identity retained "+key)
	var old: Dictionary=Saves.read("res://tools/fixtures/lifecycle-0.11-paid.json",r)
	check(not old.is_empty() and old.queue.size()>0,"frozen paid fixture loads with work retained")
	var source: Dictionary=Driver.initial(r)
	await show(source)
	check(p.support_title()==p.copy.phase_village,"unadopted legacy support wording retained")
	await click("Visual_help")
	check(ui.copy.lessons.size()==11,"five original and six new lessons")
	for i in range(ui.copy.lessons.size()):
		check(ui.lesson==i,"sequential lesson "+str(i))
		var content: Array=texts(ui.sheet)
		check(str(i+1)+" / "+str(ui.copy.lessons.size()) in content,"visible count matches current lesson catalog")
		check(ui.copy.lessons[i].title in content and ui.w("guide_setup") in content,"lesson and separate setup rendered")
		check(p.state==source,"reading guidance does not adopt, spend or resolve")
		if i in [0,5,8,9,10]:await shot("lesson-%02d"%(i+1))
		if i==0:await setup_shot()
		if i+1<ui.copy.lessons.size():await click("VisualLessonNext")
	for i in [5,8,10]:
		ui.lesson=i;ui.show_overlay("help");await process_frame
		await click("VisualLessonPlace")
		check(p.state==source,"destination preserves state "+str(i))
		check(ui.overlay=="lifecycle" if i==5 else app.defense_panel.phase==("prepare" if i==8 else "aftermath"),"destination opens intended review")
		await shot("destination-%02d"%(i+1))
		if app.defense_panel.active_ui:await click("DefenseBack" if i==8 else "AftermathBack")
		ui.show_overlay("help");await process_frame
	var earned: Dictionary=Driver.town_trace(r,true,60).state
	check(Driver.finished_town(r,earned),"ordinary command recipe completes civic house and facilities")
	await show(earned)
	check(Presentation.belongs_to(r,"town_provision","homes") and Presentation.belongs_to(r,"town_provision","stores"),"provision service has both presentation places")
	check(r.assets.project_assets.town_provision=="stores","published allocation owner unchanged")
	for place in ["homes","stores"]:
		await click("VisualPlace_"+place)
		check(ui.project_ids(place).count("town_provision")==1,"one discoverable card "+place)
		await click("VisualProject_town_provision")
		check(ui.detail.id=="town_provision" and p.state==earned,"same completed paid project opens without mutation")
		await shot("provision-from-"+place)
		await click("VisualClose")
	var body:=VBoxContainer.new();root.add_child(body);p.asset_panel.selected="homes";p.asset_panel.build(body)
	check(r.projects.town_provision.title in texts(body),"detailed Homes review includes same provision project")
	body.free()
	await click("VisualLifecycle")
	var operation_text: String="\n".join(texts(ui.sheet))
	check("priority "+str(r.lifecycle.town_balance.civic_priority) in operation_text and "priority "+str(r.lifecycle.town_balance.service_priority) in operation_text,"actual civic/service priorities displayed")
	check("overflow" in operation_text and "post-battle repair" in operation_text,"situational facility benefit explained")
	check("Civic and service duty" in operation_text,"existing social contribution explicit")
	await shot("town-operation")
	var contracted: Dictionary=r.command(earned,{"kind":"policy","welcome":earned.welcome,"tight_rations":true}).state
	for i in range(12):
		contracted=r.advance(contracted).state
		if contracted.phase=="village":break
	await show(contracted)
	check(r.lifecycle.stage(contracted,r)=="town" and contracted.phase=="village","actual public policy contracts support while rank remains")
	check(p.support_title()==p.copy.support_missing,"support contraction does not claim loss of civic rank")
	p.open();await process_frame;await shot("support-contraction")
	p.hide();ui.open()
	var illustrated: Dictionary=earned.duplicate(true)
	for id in illustrated.households.homes:illustrated.households.homes[id].practice=100
	check(r.forecast(illustrated)==r.forecast(earned),"illustrative practice scores have no forecast bonus")
	check(r.lifecycle.status(illustrated,r)==r.lifecycle.status(earned,r),"illustrative practice does not satisfy shaping")
	var learning: Dictionary=r.command(earned,{"kind":"household_order","id":"learning","enabled":true}).state
	var effect: Dictionary=r.households.forecast(learning,r)
	check(effect.learning_ready,"ordinary staffed learning is available")
	check(effect.factors.food_penalty.any(func(f):return f.id=="learning" and f.value==r.households.balance.learning_food),"learning still forgoes actual food")
	check(effect.factors.cooperation.any(func(f):return f.id=="learning" and f.value==r.households.balance.learning_cooperation),"learning still contributes actual cooperation")
	var defense_source: Dictionary=r.command(Living.at_season(r,12,true),{"kind":"warfare_begin"}).state
	await show(defense_source)
	app.defense_panel.open();app.defense_panel.mobilize(false)
	check(app.defense_panel.host!=null,"ordinary prepared residents mobilize")
	app.defense_panel.close()
	var unresolved: Dictionary=p.state.duplicate(true)
	ui.lesson=8;ui.show_overlay("help");await process_frame
	check(ui.find_child("VisualLessonPlace",true,false).disabled,"guide cannot start an unresolved worker")
	ui.guide_destination(ui.copy.lessons[8]);await process_frame
	check(p.state==unresolved and app.defense_panel.host==null,"guidance leaves authoritative battle ticks and orders unchanged")
	check(Saves.write(out_dir.path_join("deployment.json"),p.state,r),"guide preserves a valid active save")
	check(Saves.read(out_dir.path_join("deployment.json"),r)==p.state,"active battle exact save roundtrip")
	await shot("unresolved-guide")
	FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"hashes":hashes,"captures":captures},"  "))
	print("INTEGRATION GUIDE: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
