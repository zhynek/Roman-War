class_name DiplomacyPanel
extends AcceptDialog
## The diplomacy scroll: envoys waiting with offers, how every power regards
## us (the attitude factor total, expandable into the negotiation dialog's
## breakdown), and the two instruments — negotiate terms, or declare war.
## Fleets share this window: they live in sea zones, not regions, so the map
## click cannot reach them.

signal stance_changed

var game: Game
var _content: VBoxContainer
var negotiation: NegotiationDialog

const STANCE_NAMES := {
	"war": "At war", "neutral": "Neutral", "trade": "Trade rights",
	"alliance": "Allied", "protectorate": "Protectorate",
}


func _init() -> void:
	title = "Diplomacy & Fleets"
	min_size = Vector2i(560, 580)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(530, 520)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	add_child(scroll)
	negotiation = NegotiationDialog.new()
	negotiation.offer_concluded.connect(func():
		stance_changed.emit()
		_rebuild())
	add_child(negotiation)


func open_for(current_game: Game) -> void:
	game = current_game
	_rebuild()
	popup_centered()


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	var offers := game.pending_offers()
	if not offers.is_empty():
		_header("Envoys await our answer")
		for offer in offers:
			_build_offer_row(offer)
		_content.add_child(HSeparator.new())

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


func _build_offer_row(offer: Dictionary) -> void:
	var from_name: String = game.data.factions.get(offer["from"], {}).get("name", offer["from"])
	var row := HBoxContainer.new()
	var text := Label.new()
	text.text = "%s: %s" % [from_name, offer_summary(offer)]
	text.add_theme_font_size_override("font_size", 12)
	text.custom_minimum_size = Vector2(330, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)

	var accept := Button.new()
	accept.text = "Accept"
	accept.add_theme_font_size_override("font_size", 11)
	accept.pressed.connect(func():
		game.respond_offer(offer["id"], true)
		stance_changed.emit()
		_rebuild())
	row.add_child(accept)

	var decline := Button.new()
	decline.text = "Decline"
	decline.add_theme_font_size_override("font_size", 11)
	decline.pressed.connect(func():
		game.respond_offer(offer["id"], false)
		stance_changed.emit()
		_rebuild())
	row.add_child(decline)
	_content.add_child(row)


func offer_summary(offer: Dictionary) -> String:
	var parts: Array = []
	var stance: String = offer.get("stance", "")
	if stance != "":
		parts.append({"neutral": "peace", "trade": "trade rights",
			"alliance": "an alliance", "protectorate": "protectorate", "war": "war"}.get(stance, stance))
	if int(offer.get("give_payment", 0)) > 0:
		parts.append("paying %d" % int(offer["give_payment"]))
	var give_tribute = offer.get("give_tribute")
	if give_tribute != null and int(give_tribute.get("amount", 0)) > 0:
		parts.append("tribute of %d for %d seasons" % [int(give_tribute["amount"]), int(give_tribute["turns"])])
	for region_id in offer.get("give_regions", []):
		parts.append("ceding %s" % game.data.regions.get(region_id, {}).get("settlement_name", region_id))
	if int(offer.get("ask_payment", 0)) > 0:
		parts.append("asking %d" % int(offer["ask_payment"]))
	var ask_tribute = offer.get("ask_tribute")
	if ask_tribute != null and int(ask_tribute.get("amount", 0)) > 0:
		parts.append("asking tribute of %d for %d seasons" % [int(ask_tribute["amount"]), int(ask_tribute["turns"])])
	for region_id in offer.get("ask_regions", []):
		parts.append("asking for %s" % game.data.regions.get(region_id, {}).get("settlement_name", region_id))
	if parts.is_empty():
		return "an audience"
	return "offers " + ", ".join(parts)


func _build_faction_row(player: String, faction_id: String) -> void:
	var faction: Dictionary = game.data.factions[faction_id]
	var stance := DiplomacyRules.stance_between(game.state, player, faction_id)
	var row := HBoxContainer.new()

	var swatch := ColorRect.new()
	swatch.color = Color.html(faction.get("color", "#808080"))
	swatch.custom_minimum_size = Vector2(14, 14)
	row.add_child(swatch)

	var attitude := DiplomacyRules.attitude_total(game.data, game.state, faction_id, player)
	var temperament: String = AiRules.persona_for(game.data, faction_id).get("name", "")
	var name_label := Label.new()
	name_label.text = " %s — %s · %s (%+.0f) · %s" \
		% [faction["name"], STANCE_NAMES.get(stance, stance), _attitude_word(attitude), attitude, temperament]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.custom_minimum_size = Vector2(320, 0)
	row.add_child(name_label)

	var negotiate := Button.new()
	negotiate.text = "Negotiate"
	negotiate.add_theme_font_size_override("font_size", 11)
	negotiate.pressed.connect(func(): negotiation.open_for(game, faction_id))
	row.add_child(negotiate)

	if stance != "war":
		var declare := Button.new()
		declare.text = "Declare war"
		declare.add_theme_font_size_override("font_size", 11)
		declare.pressed.connect(func(): _confirm_war(faction_id, faction["name"]))
		row.add_child(declare)
	_content.add_child(row)


func _confirm_war(faction_id: String, faction_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Declare war on %s? Oaths broken this way are long remembered." % faction_name
	dialog.confirmed.connect(func():
		game.declare_war(faction_id)
		stance_changed.emit()
		_rebuild()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _attitude_word(attitude: float) -> String:
	if attitude >= 20.0:
		return "warm"
	if attitude >= 0.0:
		return "civil"
	if attitude >= -25.0:
		return "wary"
	if attitude >= -45.0:
		return "hostile"
	return "hateful"


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
	label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	_content.add_child(label)


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	_content.add_child(label)
