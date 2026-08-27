extends SceneTree
## Dev-only visual QA harness (not part of the game or the test suite):
## boots the campaign under a real renderer, arranges one composition, and
## saves a PNG. One capture per run — under the compatibility renderer,
## reading the root texture back stalls later presents, so a multi-shot
## flow would save stale frames after the first.
##
##   SHOT_STAGE=boot|zoomout|roma|africa|selection \
##   SCREENSHOT_DIR=/tmp \
##   xvfb-run godot --path . --resolution 1500x950 --script res://tools/dev_screenshot.gd

var out_dir := OS.get_environment("SCREENSHOT_DIR")
var stage := OS.get_environment("SHOT_STAGE")

var _frames := 0
var _screen: CampaignScreen
var _game: Game
var _chosen_army := ""


func _init() -> void:
	if stage == "":
		stage = "boot"
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames == 1:
		_game = Game.new_campaign("julii", 42)
		_screen = CampaignScreen.create(_game)
		root.add_child(_screen)
	elif _frames == 4:
		# In canvas_items stretch mode the canvas space differs from window
		# pixels; the viewport rect is the truth.
		_screen.size = _screen.get_viewport_rect().size
	elif _frames == 14:
		_arrange()
	elif _frames >= 20 and _frames <= 38:
		if stage == "selection" and _chosen_army != "":
			_hover_somewhere_far()
	elif _frames == 40:
		_shot("shot_" + stage)
		quit(0)


func _arrange() -> void:
	match stage:
		"zoomout":
			_screen.map_view._zoom = 0.55
			_screen.map_view.center_on("macedonia")
		"roma":
			_screen.map_view._zoom = 1.9
			_screen.map_view.center_on("latium")
		"africa":
			_screen.map_view._zoom = 1.4
			_screen.map_view.center_on("africa")
		"selection":
			var capital: String = _game.state["factions"]["julii"]["capital"]
			_screen._on_region_clicked(capital)
			var army_ids: Array = _game.state["armies"].keys()
			army_ids.sort()
			for army_id in army_ids:
				if _game.state["armies"][army_id]["owner"] == "julii":
					_screen._on_region_clicked(_game.state["armies"][army_id]["region"])
					_screen._on_army_selected(army_id)
					_chosen_army = army_id
					break
			_screen.map_view._zoom = 1.2
			_screen.map_view.center_on(capital)
		_:
			pass  # boot: default framing


func _hover_somewhere_far() -> void:
	## Re-applied every frame near the capture: synthetic mouse motion under
	## xvfb otherwise rebuilds the preview for wherever the pointer sits.
	var region_ids: Array = _game.data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		var route: Dictionary = _game.army_path_preview(_chosen_army, region_id)
		if route.get("reachable", false) and (route["path"] as Array).size() >= 3:
			_screen.map_view.hover_at(region_id)
			return


func _shot(shot_name: String) -> void:
	if out_dir == "":
		out_dir = "/tmp"
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [out_dir, shot_name])
	print("saved ", shot_name, " ", image.get_size())
