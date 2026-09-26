extends Control
## Start menu: pick a house, a difficulty, and a seed, then take the field.
## One app launches the full campaign or the authored Alpine route.

var _data: GameData
var _faction_ids: Array = []
var active_session: Control

@onready var faction_options: OptionButton = $Center/Menu/FactionRow/Factions
@onready var difficulty_options: OptionButton = $Center/Menu/DifficultyRow/Difficulty
@onready var seed_spin: SpinBox = $Center/Menu/SeedRow/Seed
@onready var guided_check: CheckButton = $Center/Menu/GuidedRow/Guided
@onready var status_label: Label = $Center/Menu/Status


func _ready() -> void:
	theme = UiStyle.build_theme()
	_data = GameData.load_from()
	if not _data.ok():
		status_label.text = "Data failed to load:\n" + "\n".join(_data.load_errors)
		push_error(status_label.text)
		return

	var words: Dictionary = _data.effects_glossary["map_commands"]
	$Center/Menu/Alpine.text = words["route_start"]
	$Center/Menu/AlpineHelp.text = words["route_menu_help"]
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

	# The version is on screen so a stale copy of the app is obvious at a glance.
	status_label.text = "v%s  ·  %d factions · %d regions · %d unit types" \
		% [str(ProjectSettings.get_setting("application/config/version", "dev")),
			_data.factions.size(), _data.regions.size(), _data.units.size()]


func _on_start_pressed() -> void:
	if active_session != null or _faction_ids.is_empty():
		return
	var faction_id: String = _faction_ids[faction_options.selected]
	var difficulty: String = ["easy", "medium", "hard", "very_hard"][difficulty_options.selected]
	var game := Game.new_campaign(faction_id, int(seed_spin.value), difficulty,
		"long", guided_check.button_pressed)
	var screen := CampaignScreen.create(game)
	screen.main_menu_enabled = true
	screen.main_menu_requested.connect(_return_to_menu, CONNECT_DEFERRED)
	_open_session(screen)


func _on_alpine_pressed() -> void:
	if active_session != null or not _data.ok():
		return
	var route = load("res://src/ui/realism/development.tscn").instantiate()
	route.embedded = true
	route.main_menu_requested.connect(_return_to_menu, CONNECT_DEFERRED)
	_open_session(route)


func _open_session(session: Control) -> void:
	active_session = session
	$Center.hide()
	add_child(session)


func _return_to_menu() -> void:
	if active_session != null:
		remove_child(active_session)
		active_session.queue_free()
		active_session = null
	$Center.show()
	$Center/Menu/Start.grab_focus()
