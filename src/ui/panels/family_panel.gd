class_name FamilyPanel
extends AcceptDialog
## The family scroll: every living member of the player's house with effective
## attributes, traits, and retinue; naming the heir; moving retinue members
## between co-located characters.

signal family_changed

var game: Game
var _content: VBoxContainer


func _init() -> void:
	title = "The Family"
	min_size = Vector2i(460, 520)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 460)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	add_child(scroll)


func open_for(current_game: Game) -> void:
	game = current_game
	_rebuild()
	popup_centered()


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var members := game.family_of()
	for entry in members:
		_build_member(entry["id"], entry["character"])


func _build_member(char_id: String, character: Dictionary) -> void:
	var sheet := game.character_sheet(char_id)
	var header := Label.new()
	var role_tag: String = {"leader": "★ Leader", "heir": "◆ Heir", "family": "Family",
		"child": "Child", "spouse": "Spouse"}.get(character["role"], "")
	var called := ""
	if String(sheet.get("epithet", "")) != "":
		called = ", called %s" % sheet["epithet"]
	var office_tag := ""
	if String(sheet.get("office", "")) != "":
		office_tag = " · %s" % sheet["office"]
	header.text = "%s%s — %s%s, age %d" % [sheet["name"], called, role_tag, office_tag, int(sheet["age"])]
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	_content.add_child(header)

	if character["role"] in ["leader", "heir", "family"]:
		var stats := Label.new()
		stats.text = "    Command %d · Management %d · Influence %d" \
			% [sheet["command"], sheet["management"], sheet["influence"]]
		stats.add_theme_font_size_override("font_size", 11)
		_content.add_child(stats)

	for trait_entry in sheet.get("traits", []):
		var trait_label := Label.new()
		trait_label.text = "    %s" % trait_entry["name"]
		trait_label.add_theme_font_size_override("font_size", 11)
		trait_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
		_content.add_child(trait_label)

	var ancillaries: Array = sheet.get("ancillaries", [])
	if not ancillaries.is_empty():
		var retinue := Label.new()
		retinue.text = "    Retinue: " + ", ".join(ancillaries)
		retinue.add_theme_font_size_override("font_size", 11)
		retinue.add_theme_color_override("font_color", Color(0.75, 0.75, 0.9))
		_content.add_child(retinue)
		_build_transfer_row(char_id, character)

	if character["role"] == "family" and character.get("gender", "male") == "male" \
			and int(character["age"]) >= int(game.data.balance["characters"]["come_of_age"]):
		var heir_button := Button.new()
		heir_button.text = "Name heir"
		heir_button.add_theme_font_size_override("font_size", 11)
		heir_button.pressed.connect(func():
			if game.set_heir(char_id):
				family_changed.emit()
				_rebuild())
		_content.add_child(heir_button)

	_content.add_child(HSeparator.new())


func _build_transfer_row(char_id: String, character: Dictionary) -> void:
	## Offer transfers to co-located kin.
	var targets: Array = []
	for entry in game.family_of():
		var other: Dictionary = entry["character"]
		if entry["id"] != char_id and other.get("location", "") == character.get("location", "") \
				and character.get("location", "") != "" and other["role"] in ["leader", "heir", "family"]:
			targets.append(entry["id"])
	if targets.is_empty():
		return
	var row := HBoxContainer.new()
	var ancillary_options := OptionButton.new()
	for ancillary_id in character["ancillaries"]:
		ancillary_options.add_item(game.data.ancillaries.get(ancillary_id, {}).get("name", ancillary_id))
	row.add_child(ancillary_options)
	var target_options := OptionButton.new()
	for target_id in targets:
		target_options.add_item(game.state["characters"][target_id]["name"])
	row.add_child(target_options)
	var transfer_button := Button.new()
	transfer_button.text = "Transfer"
	transfer_button.add_theme_font_size_override("font_size", 11)
	transfer_button.pressed.connect(func():
		if ancillary_options.selected >= 0 and target_options.selected >= 0:
			var ancillary_id: String = character["ancillaries"][ancillary_options.selected]
			if game.transfer_ancillary(char_id, targets[target_options.selected], ancillary_id):
				family_changed.emit()
				_rebuild())
	row.add_child(transfer_button)
	_content.add_child(row)
