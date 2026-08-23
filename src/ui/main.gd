extends Control
## Start menu: pick a house, a difficulty, and a seed, then take the field.
## Boots straight into the campaign screen; the campaign UI never knows the
## menu existed.

var _data: GameData
var _faction_ids: Array = []

@onready var faction_options: OptionButton = $Center/Menu/FactionRow/Factions
@onready var difficulty_options: OptionButton = $Center/Menu/DifficultyRow/Difficulty
@onready var seed_spin: SpinBox = $Center/Menu/SeedRow/Seed
@onready var status_label: Label = $Center/Menu/Status


func _ready() -> void:
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


func _on_start_pressed() -> void:
	if _faction_ids.is_empty():
		return
	var faction_id: String = _faction_ids[faction_options.selected]
	var difficulty: String = ["easy", "medium", "hard", "very_hard"][difficulty_options.selected]
	var game := Game.new_campaign(faction_id, int(seed_spin.value), difficulty)
	$Center.visible = false
	add_child(CampaignScreen.create(game))
