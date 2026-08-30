extends SceneTree
## Dev harness: boot the campaign screen, let it lay out, save a PNG.
## Run under a virtual display:
##   xvfb-run -a -s "-screen 0 1920x1200x24" godot --path . --script res://tools/screenshot.gd
## Env: SHOT_OUT (path), SHOT_TURNS (end turns first), SHOT_ZOOM (zoom steps)

var _frames := 0
var _screen


func _init() -> void:
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames == 2:
		var game := Game.new_campaign(
			OS.get_environment("SHOT_FACTION") if OS.get_environment("SHOT_FACTION") != "" else "cornelii",
			42)
		for i in range(int(OS.get_environment("SHOT_TURNS"))):
			game.end_turn()
		# Mirror the real app: main.tscn hosts the screen inside a full-rect Control.
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(host)
		_screen = CampaignScreen.create(game)
		host.add_child(_screen)
	if _frames == 8 and _screen != null:
		var zoom_steps := int(OS.get_environment("SHOT_ZOOM"))
		for i in range(abs(zoom_steps)):
			_screen.map_view.zoom_by(MapView.ZOOM_STEP if zoom_steps > 0 else 1.0 / MapView.ZOOM_STEP)
		_screen.map_view.queue_redraw()
	if _frames >= 14:
		var out := OS.get_environment("SHOT_OUT")
		if out == "":
			out = "user://shot.png"
		var image := root.get_texture().get_image()
		image.save_png(out)
		print("SHOT SAVED: %s  (%dx%d)" % [out, image.get_width(), image.get_height()])
		quit(0)
