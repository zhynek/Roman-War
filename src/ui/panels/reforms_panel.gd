class_name ReformsPanel
extends AcceptDialog
## The reforms scroll: the house's military doctrines — what it practises,
## what it is adopting, what it could adopt and for how much, and what still
## bars the rest — together with the war record those prerequisites read.

signal reform_adopted

var game: Game
var _content: VBoxContainer


func _init() -> void:
	title = "Military Reforms"
	min_size = Vector2i(540, 580)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(510, 520)
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
	var summary := game.faction_doctrines()
	var treasury := int(game.state["factions"][game.state["player_faction"]]["treasury"])

	_header("War record")
	var record: Dictionary = summary["war_record"]
	_line("Battles won %d · lost %d" % [int(record.get("battles_won", 0)), int(record.get("battles_lost", 0))])
	var faced: Dictionary = record.get("faced", {})
	if not faced.is_empty():
		var classes: Array = faced.keys()
		classes.sort()
		var parts: Array = []
		for unit_class in classes:
			parts.append("%s ×%d" % [String(unit_class).replace("_", " "), int(faced[unit_class])])
		_line("Arms faced in battle: " + ", ".join(parts))
	var mood = summary["war_mood"]
	if mood is Dictionary:
		_line("Mood at home: %s %+d for %d more turns" % [String(mood["label"]), int(mood["value"]), int(mood["turns"])],
			Color(0.55, 0.85, 0.55) if float(mood["value"]) > 0.0 else Color(0.9, 0.55, 0.5))
	_content.add_child(HSeparator.new())

	var by_status := {"in_progress": [], "available": [], "locked": [], "adopted": []}
	for row in game.available_doctrines():
		by_status[row["status"]].append(row)

	if not by_status["in_progress"].is_empty():
		_header("Reform in progress")
		for row in by_status["in_progress"]:
			_line("%s — %d turns left" % [row["doctrine"]["name"], int(row["turns_left"])], Color(0.95, 0.9, 0.75))
			_note(row["doctrine"]["description"])
		_content.add_child(HSeparator.new())

	_header("Reforms open to the house")
	if by_status["available"].is_empty():
		_note("Nothing new can be adopted now." if by_status["in_progress"].is_empty()
			else "One reform at a time: the house is busy with the one above.")
	for row in by_status["available"]:
		var doctrine: Dictionary = row["doctrine"]
		var button := Button.new()
		button.text = "Adopt %s — %d denarii, %d turns" % [doctrine["name"], int(doctrine["cost"]), int(doctrine["turns"])]
		button.add_theme_font_size_override("font_size", 12)
		button.disabled = treasury < int(doctrine["cost"]) or not by_status["in_progress"].is_empty()
		var doctrine_id: String = row["id"]
		button.pressed.connect(func():
			if game.adopt_doctrine(doctrine_id):
				reform_adopted.emit()
				_rebuild())
		_content.add_child(button)
		_note(doctrine["description"])
		_note(doctrine["historical_note"], Color(0.7, 0.7, 0.85))
	_content.add_child(HSeparator.new())

	if not by_status["locked"].is_empty():
		_header("Not yet within reach")
		for row in by_status["locked"]:
			_line(row["doctrine"]["name"], Color(0.85, 0.85, 0.85))
			for reason in row["unmet"]:
				_line("    " + String(reason), Color(0.9, 0.55, 0.5))
		_content.add_child(HSeparator.new())

	_header("Practised")
	if by_status["adopted"].is_empty():
		_note("The house follows no particular doctrine yet.")
	for row in by_status["adopted"]:
		_line(row["doctrine"]["name"], Color(0.7, 0.85, 0.7))
		_note(row["doctrine"]["description"])


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_content.add_child(label)


func _line(text: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)


func _note(text: String, color: Color = Color(0.75, 0.75, 0.75)) -> void:
	var label := Label.new()
	label.text = "    " + text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
