class_name OffersPanel
extends AcceptDialog
## Offers foreign courts made to us this season, each with its terms spelled
## out and an Accept / Refuse pair. Unanswered offers lapse when the season
## ends; the campaign screen opens this scroll whenever a new one arrives.

signal responded
signal confirm_requested(text: String, on_accept: Callable)
signal notice(text: String)

var game: Game
var _content: VBoxContainer

const STANCE_TERMS := {
	"neutral": "peace", "trade": "trade rights", "alliance": "an alliance",
	"protectorate": "our submission as their protectorate",
}

## Refusal reasons are written from the proposer's side; the recipient reads
## them the other way round.
const RECIPIENT_REASONS := {
	"We cannot pay what we offer.": "They can no longer pay what they offered.",
	"They cannot pay what is asked.": "We cannot pay what they ask.",
	"We cannot promise more than we hold.": "They can no longer promise what they offered.",
}


func _init() -> void:
	title = "Offers from foreign courts"
	min_size = Vector2i(520, 360)
	ok_button_text = "Decide later"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(490, 300)
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
	var offers := game.pending_offers()
	if offers.is_empty():
		_label("No court has anything to say to us this season.")
		return
	_label("Offers left unanswered lapse when the season ends.", Color(0.7, 0.8, 0.9))
	for offer in offers:
		_build_offer(offer)


func _build_offer(offer: Dictionary) -> void:
	var faction: Dictionary = game.data.factions.get(offer["from"], {})
	var header := Label.new()
	header.text = "%s proposes:" % faction.get("name", offer["from"])
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color.html(faction.get("color", "#c0b060")))
	_content.add_child(header)
	_label("    " + describe(offer["proposal"]))
	var attitude := game.attitude_of(offer["from"])
	_label("    They regard us as %s." % attitude["label"], Color(0.7, 0.8, 0.9))

	if offer["proposal"].get("stance", "") == "protectorate":
		_label("    Submitting makes them our overlord: they take %d%% of every season's income, and only they can release us."
			% int(game.data.balance["diplomacy"]["protectorate_tribute_pct"]), Color(0.9, 0.6, 0.5))

	var row := HBoxContainer.new()
	var accept := Button.new()
	accept.text = "Accept"
	accept.add_theme_font_size_override("font_size", 11)
	accept.pressed.connect(func(): _answer(offer, true))
	row.add_child(accept)
	var refuse := Button.new()
	refuse.text = "Refuse"
	refuse.add_theme_font_size_override("font_size", 11)
	refuse.pressed.connect(func(): _answer(offer, false))
	row.add_child(refuse)
	_content.add_child(row)
	_content.add_child(HSeparator.new())


func _answer(offer: Dictionary, accept: bool) -> void:
	## Offers are answered by identity, never by row: a second press on an
	## answered row must not reach the next court's offer.
	var index := game.pending_offers().find(offer)
	if index < 0:
		_rebuild()
		return
	var faction_name: String = game.data.factions.get(offer["from"], {}).get("name", offer["from"])
	if accept and offer["proposal"].get("stance", "") == "protectorate":
		confirm_requested.emit("Submit to %s as their protectorate? They will take a share of every season's income, and only they can release us." % faction_name,
			func(): _resolve(offer, true, faction_name))
		return
	_resolve(offer, accept, faction_name)


func _resolve(offer: Dictionary, accept: bool, faction_name: String) -> void:
	var index := game.pending_offers().find(offer)
	if index < 0:
		_rebuild()
		return
	var result := game.respond_to_offer(index, accept)
	if accept:
		if result.get("accepted", false):
			notice.emit("[color=#80b080]We accept the terms of %s.[/color]" % faction_name)
		else:
			var reason: String = result.get("reason", "")
			notice.emit("The offer of %s can no longer be honoured: %s" % [faction_name, RECIPIENT_REASONS.get(reason, reason)])
	else:
		notice.emit("We refuse the offer of %s." % faction_name)
	responded.emit()
	_rebuild()
	if game.pending_offers().is_empty():
		hide()


func describe(proposal: Dictionary) -> String:
	## The terms in words, from the proposer's side.
	var parts: Array = []
	var stance: String = proposal.get("stance", "")
	if stance != "":
		parts.append(STANCE_TERMS.get(stance, stance))
	var gift := int(proposal.get("gift", 0))
	if gift > 0:
		parts.append("a gift of %d denarii" % gift)
	var demand := int(proposal.get("demand", 0))
	if demand > 0:
		parts.append("%d denarii from us" % demand)
	var tribute := int(proposal.get("tribute_per_turn", 0))
	if tribute > 0:
		parts.append("tribute of %d a season for %d seasons" % [tribute, int(proposal.get("tribute_turns", 0))])
	var demanded := int(proposal.get("tribute_demanded_per_turn", 0))
	if demanded > 0:
		parts.append("our tribute of %d a season for %d seasons" % [demanded, int(proposal.get("tribute_demanded_turns", 0))])
	for region_id in proposal.get("regions_offered", []):
		parts.append("the province of %s" % game.data.regions.get(region_id, {}).get("name", region_id))
	for region_id in proposal.get("regions_demanded", []):
		parts.append("%s ceded to them" % game.data.regions.get(region_id, {}).get("name", region_id))
	if parts.is_empty():
		return "nothing in particular."
	return ", ".join(parts) + "."


func _label(text: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
