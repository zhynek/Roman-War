extends Control
## Separate development app entry point. Isolate Save/Load before constructing
## campaign UI so comparing views can never replace a player's normal save.
var screen: CampaignScreen

func _enter_tree() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","Roman War Realism Study/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen = CampaignScreen.create(Game.new_campaign("julii",42))
	screen.realism_development_enabled = true
	add_child(screen)
	for id in screen.game.state.armies:
		if screen.game.state.armies[id].owner=="julii":
			screen.select_force("army",id)
			break
	screen.map_view.set_zoom_level(3.5)
	screen.map_view.focus_force()
	var compare := Button.new()
	compare.text = RealismStudy.read_settings().copy.reopen
	compare.position = Vector2(16,186)
	compare.custom_minimum_size.y = 34
	compare.pressed.connect(screen.open_realism_study)
	screen.add_child(compare)
