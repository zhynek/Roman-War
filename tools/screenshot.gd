extends SceneTree
## Boots a campaign and saves screenshots of the map for visual QA. Runs
## under a real renderer (use xvfb-run on a headless box):
##
##   xvfb-run -a godot --path . --script res://tools/screenshot.gd -- out_dir=/tmp/shots seed=42 zooms=0.5,1.0,2.0
##
## Not a test: CI never runs this. It exists so map work can be eyeballed.

var _screen: CampaignScreen
var _out_dir := "/tmp/shots"
var _seed := 42
var _zooms: Array = [0.6, 1.2, 2.2]
var _frame := 0
var _shot := 0


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"out_dir": _out_dir = parts[1]
			"seed": _seed = int(parts[1])
			"zooms":
				_zooms = []
				for z in parts[1].split(","):
					_zooms.append(float(z))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var game := Game.new_campaign("julii", _seed)
	_screen = CampaignScreen.create(game)
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	if _shot >= _zooms.size():
		quit(0)
		return true
	# Reframe between shots, then give the renderer two frames to draw.
	if (_frame - 20) % 3 == 0:
		var view := _screen.map_view
		var capital: String = _screen.game.state["factions"]["julii"]["capital"]
		view._zoom = float(_zooms[_shot])
		view.center_on(capital)
		view.queue_redraw()
	elif (_frame - 20) % 3 == 2:
		var image := root.get_viewport().get_texture().get_image()
		var path := "%s/map_zoom_%s.png" % [_out_dir, String.num(float(_zooms[_shot]), 1)]
		image.save_png(path)
		print("saved ", path)
		_shot += 1
	return false
