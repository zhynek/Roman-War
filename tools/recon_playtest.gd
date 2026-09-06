extends SceneTree
## Deterministic rendered QA for v0.13. Scenario setup is confined to this tool;
## the UI and march/scouting actions below use the real campaign implementation.
var screen: CampaignScreen
var holder: Control
var out := "/tmp/roman-v13-recon"
var failed := false

func _init() -> void:
	# Test/QA scripts must never read or overwrite a player's campaign slot.
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War Recon QA/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			out = arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if holder != null:
		holder.size = root.get_visible_rect().size
	return false

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	holder = Control.new()
	root.add_child(holder)
	screen = CampaignScreen.create(Game.new_campaign("julii",42))
	holder.add_child(screen)
	screen.playback_enabled = false
	var game := screen.game
	var own := ""
	for id in game.state["armies"]:
		if game.state["armies"][id]["owner"] == "julii":
			own = id
			break
	screen.select_force("army",own)
	await _frames(12)
	var view := screen.map_view
	view.set_zoom_level(4.5)
	view.focus_force()
	var initial_sight := game.visible_regions().size()
	screen.command_bar.post.pressed.emit()
	_check(game.state["watchposts"].size() == 1,"watchtower built through the command bar")
	screen.command_bar.post.pressed.emit()
	_check(int(game.state["watchposts"][game.state["armies"][own]["region"]]["level"]) == 2,"post upgraded through the command bar")
	screen.command_bar.sight.button_pressed = true
	_check(game.visible_regions().size() > initial_sight,"fortified lookouts extend actual observation")
	await _shot("01-fortified-post")
	view.set_zoom_level(1.2)
	view.focus_force()
	await _shot("02-scouting-coverage")
	# Select an existing foreign commander and bring a visible road into the QA
	# scenario. No hidden roster is ever sent to the map or the replay record.
	var enemy := ""
	for id in game.state["armies"]:
		if game.state["armies"][id]["owner"] == "gaul":
			enemy = id
			break
	var from := ""
	var to := ""
	for region in game.visible_regions():
		for adjacent in game.data.regions[region]["adjacent"]:
			if game.visible_regions().has(adjacent):
				game.state["armies"][enemy]["region"] = region
				if MovementRules.can_enter(game.data,game.state,enemy,adjacent):
					from = region
					to = adjacent
					break
		if to != "":
			break
	_check(to != "","scenario has an observable road")
	game.state["armies"][enemy]["movement_left"] = 5.0
	game.state["recon"]["movements"] = []
	_check(MovementRules.move_army(game.data,game.state,enemy,to),"enemy traverses the real movement rule")
	var records: Array = game.state["recon"]["movements"]
	_check(records.size() == 1,"the actual move leaves a sighting")
	screen.refresh()
	view.set_zoom_level(5.5)
	view.play_sighting(records[0])
	var resolved := JSON.stringify(game.state)
	await create_timer(0.8).timeout
	await _shot("03-observed-enemy-march")
	_check(JSON.stringify(game.state) == resolved,"rendered enemy replay cannot alter the simulation")
	view.finish_marches()
	# A portrait/contact sheet uses the same live map painter and all 21 authored
	# faction kits. This is a QA image outside the repository, never an asset.
	screen.hide()
	var gallery := Control.new()
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(gallery)
	gallery.draw.connect(func(): _gallery(gallery,game))
	await _shot("04-commanders-of-the-world")
	print("recon playtest: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _gallery(canvas: Control, game: Game) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO,holder.size),Color("#142326"))
	var font := canvas.get_theme_default_font()
	canvas.draw_string(font,Vector2(32,42),"COMMANDERS OF THE CAMPAIGN",HORIZONTAL_ALIGNMENT_LEFT,-1,25,UiStyle.PARCHMENT)
	var factions: Array = game.data.factions.keys()
	factions.sort()
	var cell := Vector2((holder.size.x-64)/7,(holder.size.y-90)/3)
	for i in range(factions.size()):
		var faction: String = factions[i]
		var at := Vector2(32+(i%7)*cell.x,72+floori(i/7.0)*cell.y)
		var general = {"id":faction+"_qa","age":30+i,"name":faction}
		for character in game.state["characters"].values():
			if character["faction"] == faction:
				general = {"id":character.get("name",faction),"name":character["name"],"age":character["age"]}
				break
		var portrait := minf(cell.x-20,cell.y-64)
		var style := CommanderArt.profile(game.data,faction,general)
		CommanderArt.portrait(canvas,Rect2(at,Vector2(portrait,portrait)),style)
		canvas.draw_string(font,at+Vector2(0,portrait+20),game.data.factions[faction]["name"],HORIZONTAL_ALIGNMENT_LEFT,cell.x-12,11,UiStyle.PARCHMENT)
		var kit: Dictionary = UnitArt.for_data(game.data).kits[game.data.factions[faction]["culture"]]
		canvas.draw_set_transform(at+Vector2(portrait+10,portrait-5),0,Vector2.ONE*2.4)
		CampaignMiniatures._soldier(canvas,Vector2.ZERO,style["cape"],"commander",0,false,style)
		CampaignMiniatures._soldier(canvas,Vector2(0,10),style["cape"],"infantry",0,false,kit)
		canvas.draw_set_transform(Vector2.ZERO)

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
	print("saved ",out.path_join(name+".png"))

func _check(ok: bool, message: String) -> void:
	failed = failed or not ok
	print("PASS " if ok else "FAIL ",message)
