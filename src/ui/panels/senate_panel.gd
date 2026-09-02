class_name SenatePanel
extends AcceptDialog
## The Senate scroll: where the houses stand with the conscript fathers and
## the people, who sits in the Republic's magistracies, which of your own men
## may stand next summer, the charge laid on the house, and how close it is to
## the break. Reads Game.senate_overview(); the one act taken here is
## Game.comply_senate_demand().

signal senate_changed

var game: Game
var _content: VBoxContainer


func _init() -> void:
	title = "The Senate"
	min_size = Vector2i(560, 600)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(530, 540)
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
	if not overview["is_roman_house"]:
		_line("The Senate of Rome has no dealings with this house.", 13, UiStyle.TEXT_DIM)
		return
	if not overview["senate_alive"]:
		_line("The Senate has fallen. The Republic is over, and its magistracies with it; whoever holds Rome holds it by the sword.", 13, Color(0.9, 0.7, 0.5))
		return

	_line("The houses of Rome", 15, UiStyle.PARCHMENT)
	for house in overview["houses"]:
		var standing := "Senate %+.0f · People %.0f · seats %d" % [house["senate_standing"], house["popular_standing"], house["seats"]]
		if house["outlawed"]:
			standing += " · OUTLAWED"
		elif house["at_civil_war"]:
			standing += " · in arms against the Republic"
		_line("%s — %s" % [house["name"], standing], 13, Color.html(house["color"]).lightened(0.35))
	_content.add_child(HSeparator.new())

	if overview["at_civil_war"]:
		_line("The house is at war with the Republic. No envoy can end it and no silver can buy it off: it ends when the Senate falls, or we do.", 12, Color(0.9, 0.55, 0.5))
		_content.add_child(HSeparator.new())
	var charge = overview["charge"]
	_line("The Senate's charge", 15, UiStyle.PARCHMENT)
	if charge == null:
		_line("    The conscript fathers have nothing for us this season.", 11, UiStyle.TEXT_DIM)
	else:
		_line("%s — %d turn%s to answer" % [charge["name"], int(charge["turns_left"]), "" if int(charge["turns_left"]) == 1 else "s"], 13, Color(0.95, 0.9, 0.75))
		_line("    " + String(charge["text"]), 11, UiStyle.TEXT_DIM)
		if charge["is_demand"]:
			_line("    They name %s. Refuse, and the house is outlawed when the deadline falls." % charge["target_name"], 11, Color(0.9, 0.55, 0.5))
			var comply := Button.new()
			comply.text = "He dies for the house. Comply."
			comply.add_theme_font_size_override("font_size", 11)
			comply.focus_mode = Control.FOCUS_NONE
			comply.pressed.connect(func():
				if game.comply_senate_demand():
					senate_changed.emit()
					_rebuild())
			_content.add_child(comply)
	_content.add_child(HSeparator.new())

	_line("Offices of the Republic", 15, UiStyle.PARCHMENT)
	for office in overview["ladder"]:
		var names: Array = []
		for holder in office["holders"]:
			names.append("%s (%s)" % [holder["name"], _house_name(holder["faction"])])
		var who := ", ".join(names) if not names.is_empty() else "vacant"
		_line("%s (%d) — %s" % [office["name"], int(office["seats"]), who], 12,
			Color(0.85, 0.8, 0.6) if not names.is_empty() else UiStyle.TEXT_DIM)
	_content.add_child(HSeparator.new())

	_line("Our men before the Senate", 15, UiStyle.PARCHMENT)
	if overview["men"].is_empty():
		_line("    No man of the house may stand.", 11, UiStyle.TEXT_DIM)
	for man in overview["men"]:
		var held := String(man["office"])
		_line("%s, %d — %s · influence %d" % [man["name"], int(man["age"]),
			held if held != "" else "holds no office", int(man["influence"])], 12, Color(0.8, 0.85, 0.95))
		var stands: Array = []
		for entry in man["eligible"]:
			stands.append(String(entry["name"]) + ("" if entry["on_ladder"] else " (as suffect)"))
		_line("    may stand for: " + (", ".join(stands) if not stands.is_empty() else "nothing yet"), 10, UiStyle.TEXT_DIM)
	_content.add_child(HSeparator.new())

	_line("The road to the break", 15, UiStyle.PARCHMENT)
	_line("    The Senate demands a patriarch's life when its regard falls to %+.0f while the people's rises past %.0f. Ambition stands at %.0f; at %.0f the great men of the house break with Rome on their own." % [
		overview["demand_standing"], overview["demand_popular"], overview["ambition"], overview["ambition_break"]], 11, UiStyle.TEXT_DIM)


func _house_name(faction_id: String) -> String:
	return String(game.data.factions.get(faction_id, {}).get("name", faction_id))


func _line(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
