class_name DiplomacyPanel
extends AcceptDialog
## The stances scroll: where every house stands with us, and the blunt
## instruments available before the Phase 5 negotiation engine exists —
## declare war, or offer terms the other side simply accepts.

signal stance_changed

var game: Game
var _content: VBoxContainer

const STANCE_NAMES := {
	"war": "At war", "neutral": "Neutral", "trade": "Trade rights",
	"alliance": "Allied", "protectorate": "Protectorate",
}


func _init() -> void:
	title = "Diplomacy"
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


func _build_faction_row(player: String, faction_id: String) -> void:
	var faction: Dictionary = game.data.factions[faction_id]
	var stance := DiplomacyRules.stance_between(game.state, player, faction_id)
	var row := HBoxContainer.new()

	var swatch := ColorRect.new()
	swatch.color = Color.html(faction.get("color", "#808080"))
	swatch.custom_minimum_size = Vector2(14, 14)
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = " %s — %s" % [faction["name"], STANCE_NAMES.get(stance, stance)]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.custom_minimum_size = Vector2(280, 0)
	row.add_child(name_label)

	for offer in ["war", "neutral", "trade", "alliance"]:
		if offer == stance:
			continue
		var button := Button.new()
		button.text = {"war": "Declare war", "neutral": "Peace",
			"trade": "Trade", "alliance": "Alliance"}[offer]
		button.add_theme_font_size_override("font_size", 11)
		button.pressed.connect(func():
			game.set_stance(faction_id, offer)
			stance_changed.emit()
			_rebuild())
		row.add_child(button)
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
