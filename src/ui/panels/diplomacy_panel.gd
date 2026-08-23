class_name DiplomacyPanel
extends AcceptDialog
## The stances scroll: where every house stands with us and how warmly they
## regard us. War can be declared from here (no consent needed); everything
## else — peace, trade, alliances, gifts, tribute, buying towns — goes
## through the negotiation scroll, and only with an envoy at their court.
## Fleets share this window: they live in sea zones, not regions, so the map
## click cannot reach them.

signal stance_changed
signal negotiate_requested(faction_id: String)

var game: Game
var _content: VBoxContainer

const STANCE_NAMES := {
	"war": "At war", "neutral": "Neutral", "trade": "Trade rights",
	"alliance": "Allied", "protectorate": "Protectorate",
}


func _init() -> void:
	title = "Diplomacy & Fleets"
	min_size = Vector2i(640, 560)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(610, 500)
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

	var player: String = game.state["player_faction"]
	_header("The powers of the world")
	var faction_ids: Array = game.state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		if faction_id == player or not game.state["factions"][faction_id]["alive"]:
			continue
		if game.data.factions.get(faction_id, {}).get("is_rebel", false):
			continue
		_build_faction_row(player, faction_id)

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
	var row := HBoxContainer.new()

	var swatch := ColorRect.new()
	swatch.color = Color.html(faction.get("color", "#808080"))
	swatch.custom_minimum_size = Vector2(14, 14)
	row.add_child(swatch)

	var attitude := game.attitude_of(faction_id)
	var name_label := Label.new()
	name_label.text = " %s — %s  (%+.0f)" % [faction["name"], STANCE_NAMES.get(stance, stance),
		float(attitude["total"])]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.custom_minimum_size = Vector2(300, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	if game.can_negotiate_with(faction_id):
		var negotiate := Button.new()
		negotiate.text = "Negotiate"
		negotiate.add_theme_font_size_override("font_size", 11)
		negotiate.pressed.connect(func(): negotiate_requested.emit(faction_id))
		row.add_child(negotiate)
	else:
		var hint := Label.new()
		hint.text = "(no envoy at their court)"
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(hint)

	if stance != "war":
		var war_button := Button.new()
		war_button.text = "Declare war"
		war_button.add_theme_font_size_override("font_size", 11)
		war_button.pressed.connect(func():
			game.declare_war(faction_id)
			stance_changed.emit()
			_rebuild())
		row.add_child(war_button)
	_content.add_child(row)


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


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_content.add_child(label)


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	_content.add_child(label)
