extends SceneTree
## Screenshot harness for eyeballing the UI without a desktop: boots the start
## menu, then a campaign, and writes PNGs. Needs a real (or virtual) display:
##
##   xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . \
##       --rendering-driver opengl3 --script res://tools/screenshot.gd -- /tmp/shots
##
## Writes menu.png, campaign.png, region.png, negotiation.png to the out dir.

var _out := "/tmp/shots"
var _step := 0
var _frames := 0
var _menu: Control
var _screen: CampaignScreen


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = String(args[0])
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames < 12:
		return  # let layout and fonts settle between steps
	_frames = 0
	match _step:
		0:
			DisplayServer.window_set_size(Vector2i(1600, 1000))
			_menu = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
			root.add_child(_menu)
		1:
			_capture("menu.png")
			# Go through the real menu flow so the campaign screen is parented
			# exactly as in play.
			_menu._on_start_pressed()
			for child in _menu.get_children():
				if child is CampaignScreen:
					_screen = child
			for i in range(4):
				_screen.game.end_turn()
			_screen.refresh()
		2:
			_capture("campaign.png")
			_screen.map_view.center_on("latium")
			_screen._on_region_clicked("latium")
		3:
			_capture("region.png")
			_screen.diplomacy_panel.open_for(_screen.game)
		4:
			_capture("diplomacy.png")
			_screen.diplomacy_panel.hide()
			_screen.family_panel.open_for(_screen.game)
		5:
			_capture("family.png")
			_screen.family_panel.hide()
			_screen.senate_panel.open_for(_screen.game)
		6:
			_capture("senate.png")
			print("screenshots written to " + _out)
			quit(0)
	_step += 1


func _capture(file_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(file_name))
