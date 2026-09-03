class_name KnowledgePanel
extends AcceptDialog
## The knowledge scroll: what the house practices, what its craftsmen are
## institutionalizing, and what its court merely knows of — each with the
## price of taking it up and the true story the craft is drawn from. Reads
## Game.technique_overview(); acting goes through Game.begin_adoption.

signal knowledge_changed

const DOMAIN_NAMES := {
	"warcraft": "Warcraft", "military_engineering": "Military Engineering", "naval": "Seacraft",
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
	_war_record_lines(overview)
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
		var effects := _grant_text(entry)
		if effects != "":
			_line("    " + effects, 11, Color(0.6, 0.75, 0.6))


func _build_aware_entry(entry: Dictionary, busy: bool, treasury: int) -> void:
	_line("%s — %s" % [entry["name"], _domain_name(entry)], 13, Color(0.8, 0.85, 0.95))
	if String(entry.get("description", "")) != "":
		_line("    " + String(entry["description"]), 11, Color(0.75, 0.78, 0.85))
	var effects := _grant_text(entry)
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
	# Warcraft learns from the war record: what the court has fought and won.
	if String(prereq.get("era", "")) != "":
		wants.append("the %s era" % String(prereq["era"]).replace("_", "-"))
	if int(prereq.get("battles_won", 0)) > 0:
		wants.append("%d battle%s won" % [int(prereq["battles_won"]), "" if int(prereq["battles_won"]) == 1 else "s"])
	if int(prereq.get("battles_lost", 0)) > 0:
		wants.append("%d battle%s lost" % [int(prereq["battles_lost"]), "" if int(prereq["battles_lost"]) == 1 else "s"])
	var faced: Dictionary = prereq.get("faced", {})
	if not faced.is_empty():
		wants.append("%d battle%s against %s" % [int(faced["battles"]), "" if int(faced["battles"]) == 1 else "s",
			String(faced["class"]).replace("_", " ")])
	if not technique.get("factions", []).is_empty():
		wants.append("a tradition of another people")
	return ", ".join(wants) if not wants.is_empty() else "nothing more"


func _war_record_lines(overview: Dictionary) -> void:
	## The ledger the warcraft techniques read: battles won and lost, the arms
	## met in the field, and the realm's mood after a decisive battle.
	var record: Dictionary = overview.get("war_record", {})
	if record.is_empty():
		return
	var faced: Dictionary = record.get("faced", {})
	var classes: Array = faced.keys()
	classes.sort()
	var met: Array = []
	for unit_class in classes:
		met.append("%s ×%d" % [String(unit_class).replace("_", " "), int(faced[unit_class])])
	_line("War record: %d won, %d lost%s" % [int(record.get("battles_won", 0)), int(record.get("battles_lost", 0)),
		"" if met.is_empty() else " — faced " + ", ".join(met)], 12, Color(0.85, 0.8, 0.7))
	var mood = overview.get("war_mood")
	if mood is Dictionary and int(mood.get("turns", 0)) > 0:
		var value := float(mood.get("value", 0.0))
		_line("The realm's mood: %s (%+d order in every town, %d season%s more)" % [String(mood.get("label", "")),
			int(round(value)), int(mood["turns"]), "" if int(mood["turns"]) == 1 else "s"],
			12, Color(0.7, 0.85, 0.7) if value > 0.0 else Color(0.9, 0.6, 0.5))
	_content.add_child(HSeparator.new())


func _grant_text(entry: Dictionary) -> String:
	## Flat effects and the warcraft tables, as one readable line.
	var parts: Array = []
	var effects: Dictionary = entry.get("effects", {})
	var keys: Array = effects.keys()
	keys.sort()
	for key in keys:
		parts.append("%s %s" % [String(key).replace("_", " "), str(effects[key])])
	var war: Dictionary = entry.get("war", {})
	for stat_entry in war.get("class_stats", []):
		var deltas: Array = []
		for stat in KnowledgeRules.WAR_STAT_KEYS:
			if stat_entry.has(stat):
				deltas.append("%+d %s" % [int(stat_entry[stat]), String(stat).replace("_", " ")])
		parts.append("%s %s" % [String(stat_entry["class"]).replace("_", " "), ", ".join(deltas)])
	for matchup in war.get("matchups", []):
		parts.append("%s %+d%% vs %s" % [String(matchup["class"]).replace("_", " "), int(matchup["pct"]),
			String(matchup["versus"]).replace("_", " ")])
	for ground in war.get("terrain", []):
		parts.append("%s %+d%% on %s" % [String(ground["class"]).replace("_", " "), int(ground["pct"]), String(ground["terrain"])])
	for upkeep in war.get("upkeep_pct", []):
		parts.append("%s upkeep %+d%%" % [String(upkeep["class"]).replace("_", " "), int(upkeep["pct"])])
	for xp in war.get("recruit_xp", []):
		parts.append("%s recruits +%d xp" % [String(xp["class"]).replace("_", " "), int(xp["xp"])])
	if bool(war.get("fatigue_immune", false)):
		parts.append("tireless on a forced march")
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
