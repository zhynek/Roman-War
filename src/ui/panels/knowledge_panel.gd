class_name KnowledgePanel
extends AcceptDialog
## The knowledge scroll: what the house practices, what its craftsmen are
## institutionalizing, and what its court merely knows of — each with the
## price of taking it up and the true story the craft is drawn from. Reads
## Game.technique_overview(); acting goes through Game.begin_adoption.

signal knowledge_changed

const DOMAIN_NAMES := {
	"military_engineering": "Military Engineering", "naval": "Seacraft",
	"agrarian": "Husbandry", "hydraulic_civic": "Waters & Works",
	"metallurgy_craft": "Metal & Craft", "medicine": "Medicine",
	"scholarship_statecraft": "Scholarship & Statecraft",
	"logistics_trade": "Roads & Trade",
}

var game: Game
var _content: VBoxContainer


func _init() -> void:
	title = "Knowledge of the Age"
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

	var overview := game.technique_overview()
	var pressure := float(overview["reform_pressure"])
	if pressure > 0.0:
		var ratio := KnowledgeRules.pressure_ratio(game.data,
			game.state["factions"][game.state["player_faction"]])
		_line("Reform pressure: %.1f — defeat argues for new arms (military crafts %d%% cheaper)"
			% [pressure, int(round(ratio * float(game.data.balance["knowledge"]["reform_military_discount_pct_at_max"])))],
			14, Color(0.9, 0.6, 0.5))
		_content.add_child(HSeparator.new())

	var adopted: Array = []
	var adopting: Array = []
	var aware: Array = []
	for entry in overview["entries"]:
		match String(entry["stage"]):
			"adopted": adopted.append(entry)
			"adopting": adopting.append(entry)
			_: aware.append(entry)

	if not adopting.is_empty():
		_line("Being taken up", 15, Color(0.95, 0.9, 0.75))
		for entry in adopting:
			_line("%s — %s" % [entry["name"], _domain_name(entry)], 13, Color(0.85, 0.8, 0.6))
			_line("    %d season%s remain" % [int(entry["progress"]), "" if int(entry["progress"]) == 1 else "s"],
				11, Color(0.7, 0.7, 0.7))
		_content.add_child(HSeparator.new())

	_line("Known of (%d)" % aware.size(), 15, Color(0.95, 0.9, 0.75))
	if aware.is_empty():
		_line("    Nothing new has reached this court. Trade, scholarship, war and spies all carry word.",
			11, Color(0.6, 0.6, 0.6))
	var busy := not adopting.is_empty()
	var treasury := int(game.state["factions"][game.state["player_faction"]]["treasury"])
	for entry in aware:
		_build_aware_entry(entry, busy, treasury)

	_content.add_child(HSeparator.new())
	_line("Practiced (%d)" % adopted.size(), 15, Color(0.95, 0.9, 0.75))
	for entry in adopted:
		_line("%s — %s" % [entry["name"], _domain_name(entry)], 13, Color(0.7, 0.85, 0.7))
		var effects := _effects_text(entry["effects"])
		if effects != "":
			_line("    " + effects, 11, Color(0.6, 0.75, 0.6))


func _build_aware_entry(entry: Dictionary, busy: bool, treasury: int) -> void:
	_line("%s — %s" % [entry["name"], _domain_name(entry)], 13, Color(0.8, 0.85, 0.95))
	var effects := _effects_text(entry["effects"])
	if effects != "":
		_line("    Would grant: " + effects, 11, Color(0.65, 0.7, 0.8))
	var cost := int(entry["cost"])
	var turns := int(entry["turns"])
	if not bool(entry["ready"]):
		_line("    Wants: %s" % _prerequisites_text(entry["id"]), 11, Color(0.75, 0.65, 0.55))
	else:
		var row := HBoxContainer.new()
		var adopt := Button.new()
		adopt.text = "Take it up — %d, %d season%s" % [cost, turns, "" if turns == 1 else "s"]
		adopt.add_theme_font_size_override("font_size", 11)
		adopt.disabled = busy or treasury < cost
		adopt.pressed.connect(func():
			if bool(game.begin_adoption(String(entry["id"])).get("ok", false)):
				knowledge_changed.emit()
				_rebuild())
		row.add_child(adopt)
		if busy:
			var note := Label.new()
			note.text = "  (one program at a time)"
			note.add_theme_font_size_override("font_size", 10)
			note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			row.add_child(note)
		_content.add_child(row)
	var basis := RichTextLabel.new()
	basis.bbcode_enabled = true
	basis.fit_content = true
	basis.append_text("[i][color=#9a9382]%s[/color][/i]" % String(entry["historical_basis"]))
	basis.add_theme_font_size_override("normal_font_size", 10)
	basis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(basis)
	_content.add_child(HSeparator.new())


func _prerequisites_text(technique_id: String) -> String:
	## Human-readable unmet-wants line, from the data (not the engine's caches —
	## a static description suffices for the scroll).
	var technique: Dictionary = game.data.techniques.get(technique_id, {})
	var prereq: Dictionary = technique.get("prerequisites", {})
	var wants: Array = []
	var kind := String(prereq.get("building_kind", ""))
	if kind != "":
		wants.append("%s (tier %d)" % [kind.replace("_", " "), int(prereq.get("building_level", 1))])
	if String(prereq.get("resource", "")) != "":
		wants.append("the %s trade" % prereq["resource"])
	if String(prereq.get("hidden_resource", "")) != "":
		wants.append("lands of %s" % prereq["hidden_resource"])
	if bool(prereq.get("coastal", false)):
		wants.append("a coast")
	for needed in prereq.get("techniques", []):
		wants.append(String(game.data.techniques.get(needed, {}).get("name", needed)))
	return ", ".join(wants) if not wants.is_empty() else "nothing more"


func _effects_text(effects: Dictionary) -> String:
	var parts: Array = []
	var keys: Array = effects.keys()
	keys.sort()
	for key in keys:
		parts.append("%s %s" % [String(key).replace("_", " "), str(effects[key])])
	return ", ".join(parts)


func _domain_name(entry: Dictionary) -> String:
	return DOMAIN_NAMES.get(String(entry["domain"]), String(entry["domain"]))


func _line(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
