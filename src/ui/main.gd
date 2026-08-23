extends Control
## Start menu: pick a house, a difficulty, and a seed, then take the field.
## Boots straight into the campaign screen; the campaign UI never knows the
## menu existed.

var _data: GameData
var _faction_ids: Array = []
var _guided_check: CheckBox

@onready var faction_options: OptionButton = $Center/Menu/FactionRow/Factions
@onready var difficulty_options: OptionButton = $Center/Menu/DifficultyRow/Difficulty
@onready var seed_spin: SpinBox = $Center/Menu/SeedRow/Seed
@onready var status_label: Label = $Center/Menu/Status


func _ready() -> void:
	theme = UiTheme.build()
	_decorate_menu()
	_data = GameData.load_from()
	if not _data.ok():
		status_label.text = "Data failed to load:\n" + "\n".join(_data.load_errors)
		push_error(status_label.text)
		return

	var faction_ids: Array = _data.factions.keys()
	faction_ids.sort()
	for playable_tier in ["playable", "unlockable"]:
		for faction_id in faction_ids:
			var faction: Dictionary = _data.factions[faction_id]
			if faction["playable"] != playable_tier:
				continue
			var label: String = faction["name"]
			if playable_tier == "unlockable":
				label += "  (unlockable)"
			faction_options.add_item(label)
			_faction_ids.append(faction_id)
	faction_options.selected = 0

	for difficulty in ["easy", "medium", "hard", "very_hard"]:
		difficulty_options.add_item(difficulty.capitalize().replace("_", " "))
	difficulty_options.selected = 1

	status_label.text = "%d factions · %d regions · %d unit types" \
		% [_data.factions.size(), _data.regions.size(), _data.units.size()]


func _decorate_menu() -> void:
	## Ink ground, a framed panel behind the menu, gold title, laurel rules —
	## all in code, no assets.
	var ground := ColorRect.new()
	ground.color = UiTheme.INK
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ground)
	move_child(ground, 0)

	var menu: VBoxContainer = $Center/Menu
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = UiTheme.PANEL
	frame_style.border_color = UiTheme.BORDER_BRIGHT
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(10)
	frame_style.content_margin_left = 36
	frame_style.content_margin_right = 36
	frame_style.content_margin_top = 28
	frame_style.content_margin_bottom = 28
	frame.add_theme_stylebox_override("panel", frame_style)
	var center: CenterContainer = $Center
	center.remove_child(menu)
	frame.add_child(menu)
	center.add_child(frame)

	var title: Label = $Center/Menu/Title if has_node("Center/Menu/Title") else null
	if title == null:
		title = menu.get_node("Title")
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	var subtitle: Label = menu.get_node("Subtitle")
	subtitle.add_theme_color_override("font_color", UiTheme.PARCHMENT_DIM)

	var rule := Label.new()
	rule.text = "─────────  S · P · Q · R  ─────────"
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule.add_theme_font_size_override("font_size", 12)
	rule.add_theme_color_override("font_color", UiTheme.BORDER_BRIGHT)
	menu.add_child(rule)
	menu.move_child(rule, subtitle.get_index() + 1)

	# The guided opening: on by default until it has been played once.
	_guided_check = CheckBox.new()
	_guided_check.text = "Guided opening (recommended for your first campaign)"
	_guided_check.add_theme_font_size_override("font_size", 12)
	_guided_check.button_pressed = not AdvisorConfig.tutorial_seen()
	_guided_check.toggled.connect(_on_guided_toggled)
	var start_button: Button = menu.get_node("Start")
	menu.add_child(_guided_check)
	menu.move_child(_guided_check, start_button.get_index())


func _on_guided_toggled(pressed: bool) -> void:
	## The walkthrough plays a fixed opening so its script matches the world.
	faction_options.disabled = pressed
	difficulty_options.disabled = pressed
	seed_spin.editable = not pressed
	if pressed:
		status_label.text = "The guided opening plays House Julii on a fixed seed."
	elif _data != null:
		status_label.text = "%d factions · %d regions · %d unit types" \
			% [_data.factions.size(), _data.regions.size(), _data.units.size()]


func _on_start_pressed() -> void:
	if _faction_ids.is_empty():
		return
	var guided: bool = _guided_check != null and _guided_check.button_pressed
	var game: Game
	if guided:
		var setup = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/tutorial.json")).get("tutorial", {})
		game = Game.new_campaign(String(setup.get("faction", "julii")),
			int(setup.get("seed", 42)), String(setup.get("difficulty", "easy")))
	else:
		var faction_id: String = _faction_ids[faction_options.selected]
		var difficulty: String = ["easy", "medium", "hard", "very_hard"][difficulty_options.selected]
		game = Game.new_campaign(faction_id, int(seed_spin.value), difficulty)
	$Center.visible = false
	var screen := CampaignScreen.create(game)
	screen.tutorial_requested = guided
	add_child(screen)
