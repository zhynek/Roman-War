extends SceneTree
## Dev-only visual QA harness (not part of the game or the test suite):
## boots the campaign under a real renderer, walks the camera through a few
## compositions, and saves PNGs to $SCREENSHOT_DIR (default /tmp).
##   xvfb-run godot --path . --resolution 1500x950 --script res://tools/dev_screenshot.gd

var out_dir := OS.get_environment("SCREENSHOT_DIR")

var _frames := 0
var _screen: CampaignScreen
var _game: Game


func _init() -> void:
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames == 1:
		_game = Game.new_campaign("julii", 42)
		_screen = CampaignScreen.create(_game)
		root.add_child(_screen)
	elif _frames == 4:
		_screen.size = Vector2(root.size)
	elif _frames == 14:
		_shot("shot_1_boot")
		_screen.map_view._zoom = 0.55
		_screen.map_view.center_on("macedonia")
	elif _frames == 20:
		_shot("shot_2_zoomout")
		_screen.map_view._zoom = 1.9
		_screen.map_view.center_on("latium")
	elif _frames == 26:
		_shot("shot_3_roma")
		_screen.map_view._zoom = 1.4
		_screen.map_view.center_on("carthago_regio" if _game.data.regions.has("carthago_regio") else "africa")
	elif _frames == 32:
		_shot("shot_4_africa")
		# Select the capital and an army to exercise overlays.
		var capital: String = _game.state["factions"]["julii"]["capital"]
		_screen._on_region_clicked(capital)
		var army_ids: Array = _game.state["armies"].keys()
		army_ids.sort()
		for army_id in army_ids:
			if _game.state["armies"][army_id]["owner"] == "julii":
				_screen._on_region_clicked(_game.state["armies"][army_id]["region"])
				_screen._on_army_selected(army_id)
				break
		_screen.map_view._zoom = 1.2
		_screen.map_view.center_on(capital)
	elif _frames == 38:
		_shot("shot_5_selection")
		quit(0)


func _shot(shot_name: String) -> void:
	if out_dir == "":
		out_dir = "/tmp"
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [out_dir, shot_name])
	print("saved ", shot_name, " ", image.get_size())
