class_name DiplomacyPanel
extends AcceptDialog
## The diplomacy scroll: where every court stands with us and how it regards
## us, and the negotiating table — terms, gold, tribute and land assembled
## into one offer, weighed on the other side's own scale before it is made.
## Offers travel through an envoy in contact with the other court; war alone
## needs no envoy. Fleets share this window: they live in sea zones, not
## regions, so the map click cannot reach them.

signal stance_changed
signal war_requested(faction_id: String)
signal notice(text: String)

var game: Game
var _content: VBoxContainer
var _focus := ""

var _terms: OptionButton
var _term_stances: Array = []
var _gift: SpinBox
var _demand: SpinBox
var _tribute: SpinBox
var _tribute_turns: SpinBox
var _tribute_demanded: SpinBox
var _tribute_demanded_turns: SpinBox
var _region_offered: OptionButton
var _regions_offerable: Array = []
var _region_demanded: OptionButton
var _regions_demandable: Array = []
var _verdict: VBoxContainer

const STANCE_NAMES := {
	"war": "At war", "neutral": "Neutral", "trade": "Trade rights",
	"alliance": "Allied", "protectorate": "Protectorate",
}


func _init() -> void:
	title = "Diplomacy & Fleets"
	min_size = Vector2i(560, 640)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(530, 580)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	add_child(scroll)


func open_for(current_game: Game, faction_id: String = "") -> void:
	game = current_game
	if faction_id != "":
		_focus = faction_id
	_rebuild()
	popup_centered()


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	var player: String = game.state["player_faction"]
	if _focus != "" and (not game.state["factions"].has(_focus) or not game.state["factions"][_focus]["alive"]):
		_focus = ""
	_header("The powers of the world")
	var faction_ids: Array = game.state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		if faction_id == player or not game.state["factions"][faction_id]["alive"]:
			continue
		if game.data.factions.get(faction_id, {}).get("is_rebel", false):
			continue
		_build_faction_row(player, faction_id)

	if _focus != "":
		_content.add_child(HSeparator.new())
		_build_negotiation(player, _focus)

	_content.add_child(HSeparator.new())
	_header("Fleets")
	var fleet_ids: Array = game.state["fleets"].keys()
	fleet_ids.sort()
	var any_fleet := false
	for fleet_id in fleet_ids:
		var fleet: Dictionary = game.state["fleets"][fleet_id]
		if fleet["owner"] != player:
			continue
		any_fleet = true
		_build_fleet_row(fleet_id, fleet)
	if not any_fleet:
		_label("We keep no ships at sea.")


func _build_faction_row(player: String, faction_id: String) -> void:
	var faction: Dictionary = game.data.factions[faction_id]
	var stance := DiplomacyRules.stance_between(game.state, player, faction_id)
	var attitude := game.attitude_of(faction_id)
	var row := HBoxContainer.new()

	var swatch := ColorRect.new()
	swatch.color = Color.html(faction.get("color", "#808080"))
	swatch.custom_minimum_size = Vector2(14, 14)
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = " %s — %s · regards us as %s" % [faction["name"], STANCE_NAMES.get(stance, stance), attitude["label"]]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.custom_minimum_size = Vector2(330, 0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)

	var envoy := game.best_envoy(faction_id)
	var treat := Button.new()
	treat.text = "Treat" if envoy != "" else "No envoy in contact"
	treat.disabled = envoy == ""
	treat.add_theme_font_size_override("font_size", 11)
	treat.pressed.connect(func():
		_focus = faction_id
		_rebuild())
	row.add_child(treat)

	if stance != "war":
		var war := Button.new()
		war.text = "Declare war"
		war.add_theme_font_size_override("font_size", 11)
		war.pressed.connect(func(): war_requested.emit(faction_id))
		row.add_child(war)
	_content.add_child(row)


func _build_negotiation(player: String, faction_id: String) -> void:
	var faction: Dictionary = game.data.factions[faction_id]
	_header("Talks with %s" % faction["name"])
	var envoy := game.best_envoy(faction_id)
	if envoy == "":
		_label("No envoy of ours is in contact with their court. Send one to their lands, or to meet their army.",
			Color(0.9, 0.8, 0.5))
	else:
		var agent: Dictionary = game.state["agents"][envoy]
		_label("Our envoy %s (skill %d) speaks for the house." % [agent["name"], int(agent["skill"])])

	var attitude := game.attitude_of(faction_id)
	_label("They regard us as %s (%+.0f):" % [attitude["label"], float(attitude["total"])], Color(0.95, 0.9, 0.75))
	for factor in attitude["factors"]:
		_factor_line(factor)

	var current := DiplomacyRules.stance_between(game.state, player, faction_id)
	_terms = OptionButton.new()
	_term_stances = []
	_add_term("No change of terms", "")
	match current:
		"war":
			_add_term("Peace", "neutral")
			_add_term("Demand their submission as our protectorate", "protectorate")
		"neutral":
			_add_term("Trade rights", "trade")
			_add_term("Alliance", "alliance")
			_add_term("Demand their submission as our protectorate", "protectorate")
		"trade":
			_add_term("Alliance", "alliance")
			_add_term("End the treaty", "neutral")
			_add_term("Demand their submission as our protectorate", "protectorate")
		"alliance":
			_add_term("End the alliance", "neutral")
			_add_term("Demand their submission as our protectorate", "protectorate")
		"protectorate":
			_add_term("End the protectorate", "neutral")
	_content.add_child(_labelled("Terms", _terms))

	var treasury := int(game.state["factions"][player]["treasury"])
	_gift = _spin(0, maxi(treasury, 0), 100)
	_content.add_child(_labelled("Gift of gold", _gift))
	_demand = _spin(0, 100000, 100)
	_content.add_child(_labelled("Gold demanded", _demand))
	var tribute_row := HBoxContainer.new()
	_tribute = _spin(0, 10000, 50)
	_tribute_turns = _spin(0, 40, 1)
	tribute_row.add_child(_caption("Tribute we pay per turn"))
	tribute_row.add_child(_tribute)
	tribute_row.add_child(_caption("for turns"))
	tribute_row.add_child(_tribute_turns)
	_content.add_child(tribute_row)
	var demanded_row := HBoxContainer.new()
	_tribute_demanded = _spin(0, 10000, 50)
	_tribute_demanded_turns = _spin(0, 40, 1)
	demanded_row.add_child(_caption("Tribute they pay per turn"))
	demanded_row.add_child(_tribute_demanded)
	demanded_row.add_child(_caption("for turns"))
	demanded_row.add_child(_tribute_demanded_turns)
	_content.add_child(demanded_row)

	_region_offered = OptionButton.new()
	_regions_offerable = [""]
	_region_offered.add_item("No land offered")
	var capital: String = game.state["factions"][player]["capital"]
	for region_id in _regions_of(player):
		if region_id == capital:
			continue
		_regions_offerable.append(region_id)
		_region_offered.add_item(game.data.regions[region_id]["name"])
	_content.add_child(_labelled("Land we cede", _region_offered))

	_region_demanded = OptionButton.new()
	_regions_demandable = [""]
	_region_demanded.add_item("No land demanded")
	var their_capital: String = game.state["factions"][faction_id]["capital"]
	var visible_set := game.visible_regions()
	for region_id in _regions_of(faction_id):
		if region_id == their_capital or not visible_set.has(region_id):
			continue
		_regions_demandable.append(region_id)
		_region_demanded.add_item(game.data.regions[region_id]["name"])
	_content.add_child(_labelled("Land we demand", _region_demanded))

	var buttons := HBoxContainer.new()
	var weigh := Button.new()
	weigh.text = "Weigh the offer"
	weigh.add_theme_font_size_override("font_size", 11)
	weigh.pressed.connect(_weigh)
	buttons.add_child(weigh)
	var offer := Button.new()
	offer.text = "Make the offer"
	offer.disabled = envoy == ""
	offer.add_theme_font_size_override("font_size", 11)
	offer.pressed.connect(_make_offer)
	buttons.add_child(offer)
	_content.add_child(buttons)

	_verdict = VBoxContainer.new()
	_content.add_child(_verdict)


func build_proposal() -> Dictionary:
	## The offer as the scroll currently reads it.
	var proposal := {
		"to": _focus,
		"stance": _term_stances[_terms.selected] if _terms.selected >= 0 else "",
		"gift": int(_gift.value),
		"demand": int(_demand.value),
		"tribute_per_turn": int(_tribute.value),
		"tribute_turns": int(_tribute_turns.value),
		"tribute_demanded_per_turn": int(_tribute_demanded.value),
		"tribute_demanded_turns": int(_tribute_demanded_turns.value),
		"regions_offered": [],
		"regions_demanded": [],
	}
	if _region_offered.selected > 0:
		proposal["regions_offered"].append(_regions_offerable[_region_offered.selected])
	if _region_demanded.selected > 0:
		proposal["regions_demanded"].append(_regions_demandable[_region_demanded.selected])
	return proposal


func _weigh() -> void:
	_show_verdict(game.evaluate_proposal(build_proposal()), false)


func _make_offer() -> void:
	var proposal := build_proposal()
	var result := game.propose(proposal)
	var faction_name: String = game.data.factions.get(_focus, {}).get("name", _focus)
	if result.get("accepted", false):
		notice.emit("[color=#80b080]%s accepts our terms.[/color]" % faction_name)
		stance_changed.emit()
		_rebuild()
		_show_verdict({"accept": true, "score": result["score"], "factors": result["factors"], "reason": ""}, true)
	else:
		var reason: String = result.get("reason", "")
		notice.emit("%s refuses our offer%s" % [faction_name, ": " + reason if reason != "" else "."])
		_show_verdict({"accept": false, "score": result.get("score", 0.0),
			"factors": result.get("factors", []), "reason": reason}, true)


func _show_verdict(verdict: Dictionary, made: bool) -> void:
	for child in _verdict.get_children():
		_verdict.remove_child(child)
		child.queue_free()
	var accept: bool = verdict.get("accept", false)
	var headline := ""
	if made:
		headline = "They accepted." if accept else "They refused."
	else:
		headline = "They would accept." if accept else "They would refuse."
	var reason: String = verdict.get("reason", "")
	if reason != "":
		headline += " " + reason
	var head := Label.new()
	head.text = headline
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55) if accept else Color(0.9, 0.55, 0.5))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict.add_child(head)
	for factor in verdict.get("factors", []):
		var line := Label.new()
		var value := float(factor["value"])
		line.text = "    %s  %+.1f" % [String(factor["label"]).replace("_", " "), value]
		line.add_theme_font_size_override("font_size", 11)
		line.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55) if value >= 0.0 else Color(0.9, 0.55, 0.5))
		_verdict.add_child(line)
	if not verdict.get("factors", []).is_empty():
		var total := Label.new()
		total.text = "    balance  %+.1f" % float(verdict.get("score", 0.0))
		total.add_theme_font_size_override("font_size", 11)
		_verdict.add_child(total)


func _build_fleet_row(fleet_id: String, fleet: Dictionary) -> void:
	var zone: Dictionary = game.data.sea_zones.get(fleet["sea_zone"], {})
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s — %d ships (move %.0f)" \
		% [zone.get("name", fleet["sea_zone"]), fleet["ships"].size(), float(fleet["movement_left"])]
	label.add_theme_font_size_override("font_size", 12)
	label.custom_minimum_size = Vector2(280, 0)
	row.add_child(label)

	var destinations := OptionButton.new()
	var adjacent: Array = zone.get("adjacent", []).duplicate()
	adjacent.sort()
	for zone_id in adjacent:
		destinations.add_item(game.data.sea_zones.get(zone_id, {}).get("name", zone_id))
	row.add_child(destinations)

	var sail := Button.new()
	sail.text = "Sail"
	sail.add_theme_font_size_override("font_size", 11)
	sail.pressed.connect(func():
		if destinations.selected >= 0:
			game.move_fleet(fleet_id, adjacent[destinations.selected])
			stance_changed.emit()
			_rebuild())
	row.add_child(sail)
	_content.add_child(row)


## --- Small builders -------------------------------------------------------

func _add_term(text: String, stance: String) -> void:
	_terms.add_item(text)
	_term_stances.append(stance)


func _regions_of(faction_id: String) -> Array:
	var result: Array = []
	for region_id in game.state["settlements"]:
		if game.state["settlements"][region_id]["owner"] == faction_id:
			result.append(region_id)
	result.sort()
	return result


func _spin(min_value: int, max_value: int, step: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = 0
	spin.custom_minimum_size = Vector2(110, 0)
	return spin


func _labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_caption(text))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text + " "
	label.add_theme_font_size_override("font_size", 11)
	return label


func _factor_line(factor: Dictionary) -> void:
	var value := float(factor["value"])
	_label("    %s  %+.1f" % [String(factor["label"]).replace("_", " "), value],
		Color(0.55, 0.85, 0.55) if value >= 0.0 else Color(0.9, 0.55, 0.5))


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_content.add_child(label)


func _label(text: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
