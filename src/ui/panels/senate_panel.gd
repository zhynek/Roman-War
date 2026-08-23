class_name SenatePanel
extends AcceptDialog
## The senate scroll (Phase 7): the standing of every Roman house with the
## Senate and the people, the offices of the Republic and who holds them,
## and the mission the Senate has set the player — including the one demand
## that can only be answered with a sword.

signal senate_changed

var game: Game
var _content: VBoxContainer


func _init() -> void:
	title = "The Senate"
	min_size = Vector2i(520, 560)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(490, 500)
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

	var overview := game.senate_overview()
	if not overview["senate_alive"]:
		_header("The Senate is no more.")
		_label("The Republic's old voice is silent. What replaces it is being decided in the field.")
		return

	_header("Standing of the houses")
	for row in overview["standings"]:
		var faction: Dictionary = game.data.factions.get(row["faction"], {})
		var status := ""
		if row["at_civil_war"]:
			status = "  — IN REBELLION"
		elif not row["alive"]:
			status = "  — destroyed"
		_label("%s — Senate %.0f · People %.0f%s" % [faction.get("name", row["faction"]),
			float(row["senate"]), float(row["popular"]), status],
			Color.html(faction.get("color", "#808080")))

	_content.add_child(HSeparator.new())
	_header("Offices of the Republic")
	if overview["offices"].is_empty():
		_label("No offices are filled this year.")
	for entry in overview["offices"]:
		var faction: Dictionary = game.data.factions.get(entry["faction"], {})
		_label("%s — %s (%s)" % [entry["office_name"], entry["holder_name"],
			faction.get("name", entry["faction"])])

	_content.add_child(HSeparator.new())
	_header("The Senate's charge to us")
	var mission = overview["mission"]
	if mission == null:
		_label("The Senate asks nothing of us this season.")
		return
	var template: Dictionary = game.data.missions.get(mission["template"], {})
	_label(String(template.get("name", mission["template"])), Color(0.95, 0.9, 0.75))
	_label(String(template.get("text", "")))
	_label("Turns remaining: %d" % int(mission["turns_left"]))
	var target_text := _target_text(mission)
	if target_text != "":
		_label(target_text)
	if String(template.get("kind", "")) == "leader_suicide":
		var comply := Button.new()
		comply.text = "He dies for the house. Comply."
		comply.add_theme_font_size_override("font_size", 12)
		comply.pressed.connect(func():
			if game.comply_senate_demand():
				senate_changed.emit()
				_rebuild())
		_content.add_child(comply)


func _target_text(mission: Dictionary) -> String:
	if mission.has("target_region"):
		return "Target: %s" % game.data.regions.get(mission["target_region"], {}).get("settlement_name", mission["target_region"])
	if mission.has("target_faction"):
		return "Target: %s" % game.data.factions.get(mission["target_faction"], {}).get("name", mission["target_faction"])
	if mission.has("target_char"):
		var character: Dictionary = game.state["characters"].get(mission["target_char"], {})
		return "Target: %s" % character.get("name", mission["target_char"])
	return ""


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_content.add_child(label)


func _label(text: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	_content.add_child(label)
