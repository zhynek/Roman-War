class_name EdictsPanel
extends AcceptDialog
## The book of policies: what the court holds (with upkeep, effects, and the
## true price of striking each down), and every edict it could hold — priced,
## its first bar named, its real history told. Reads Game.edict_overview();
## acting goes through Game.enact_edict / Game.repeal_edict.

signal edicts_changed

const CATEGORY_NAMES := {
	"welfare": "Welfare", "religion": "Religion", "land": "Land",
	"citizenship": "Citizenship", "taxation": "Taxation", "debt": "Debt",
	"military": "Military", "trade": "Trade",
}
const REASON_TEXT := {
	"too_soon": "too soon after the last act",
	"book_full": "the book is full — repeal something first",
	"wants_building": "wants a greater institution",
	"wants_technique": "wants a craft not yet practiced",
	"treasury": "the purse refuses",
}

var game: Game
var _content: VBoxContainer


func _init() -> void:
	title = "The Book of Policies"
	min_size = Vector2i(540, 560)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(510, 500)
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

	var overview := game.edict_overview()
	_line("Held: %d of %d — costing %d each turn" % [overview["held"].size(),
		int(overview["max_enacted"]), int(overview["upkeep"])], 14, Color(0.95, 0.9, 0.75))
	_content.add_child(HSeparator.new())

	for entry in overview["held"]:
		_build_held_entry(entry)

	_line("The court could enact", 15, Color(0.95, 0.9, 0.75))
	var treasury := int(game.state["factions"][game.state["player_faction"]]["treasury"])
	for entry in overview["available"]:
		_build_available_entry(entry, treasury)


func _build_held_entry(entry: Dictionary) -> void:
	var edict: Dictionary = entry["edict"]
	_line("%s — %s" % [String(edict["name"]), _category(edict)], 13, Color(0.7, 0.85, 0.7))
	var effects := _effects_text(edict.get("effects", {}))
	if effects != "":
		_line("    " + effects, 11, Color(0.6, 0.75, 0.6))
	var upkeep_bits: Array = []
	if int(edict.get("upkeep_per_turn", 0)) > 0:
		upkeep_bits.append("%d a turn" % int(edict["upkeep_per_turn"]))
	if float(edict.get("upkeep_per_1000_pop", 0.0)) > 0.0:
		upkeep_bits.append("%.0f per 1000 heads" % float(edict["upkeep_per_1000_pop"]))
	if not upkeep_bits.is_empty():
		_line("    Upkeep: " + ", ".join(upkeep_bits), 11, Color(0.7, 0.7, 0.7))

	var shock: Dictionary = edict.get("tensions", {}).get("repeal_unrest", {})
	var repeal := Button.new()
	var consequence := ""
	if float(shock.get("penalty", 0.0)) > 0.0:
		consequence = " (the crowd: -%.0f mood for %d seasons)" % [float(shock["penalty"]), int(shock["turns"])]
	repeal.text = "Strike it down%s" % consequence
	repeal.add_theme_font_size_override("font_size", 11)
	var edict_id := String(entry["id"])
	repeal.pressed.connect(func():
		if game.repeal_edict(edict_id):
			edicts_changed.emit()
			_rebuild())
	_content.add_child(repeal)
	_content.add_child(HSeparator.new())


func _build_available_entry(entry: Dictionary, treasury: int) -> void:
	var edict: Dictionary = entry["edict"]
	_line("%s — %s" % [String(edict["name"]), _category(edict)], 13, Color(0.8, 0.85, 0.95))
	var effects := _effects_text(edict.get("effects", {}))
	if String(edict["kind"]) == "decree":
		var mood: Dictionary = edict.get("timed_happiness", {})
		effects = "one act: +%.0f mood for %d seasons" % [float(mood.get("value", 0)), int(mood.get("turns", 0))] \
			+ ("" if effects == "" else ", " + effects)
	if effects != "":
		_line("    " + effects, 11, Color(0.65, 0.7, 0.8))
	var reason := String(entry["reason"])
	var cost := int(entry["cost"])
	if reason == "":
		var enact := Button.new()
		enact.text = "Enact — %d" % cost
		enact.add_theme_font_size_override("font_size", 11)
		enact.disabled = treasury < cost
		var edict_id := String(entry["id"])
		enact.pressed.connect(func():
			if bool(game.enact_edict(edict_id).get("ok", false)):
				edicts_changed.emit()
				_rebuild())
		_content.add_child(enact)
	else:
		if reason.begins_with("contradicts_"):
			var other := reason.trim_prefix("contradicts_")
			reason = "contradicts " + String(game.data.edicts.get(other, {}).get("name", other))
		else:
			reason = REASON_TEXT.get(reason, reason)
		_line("    Barred: %s" % reason, 11, Color(0.75, 0.65, 0.55))
	var basis := RichTextLabel.new()
	basis.bbcode_enabled = true
	basis.fit_content = true
	basis.append_text("[i][color=#9a9382]%s[/color][/i]" % String(edict["historical_basis"]))
	basis.add_theme_font_size_override("normal_font_size", 10)
	basis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(basis)
	_content.add_child(HSeparator.new())


func _effects_text(effects: Dictionary) -> String:
	var parts: Array = []
	var keys: Array = effects.keys()
	keys.sort()
	for key in keys:
		parts.append("%s %s" % [String(key).replace("_", " "), str(effects[key])])
	return ", ".join(parts)


func _category(edict: Dictionary) -> String:
	var kind_tag := "decree" if String(edict["kind"]) == "decree" else "standing"
	return "%s, %s" % [CATEGORY_NAMES.get(String(edict["category"]), String(edict["category"])), kind_tag]


func _line(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
