class_name NegotiationPanel
extends AcceptDialog
## The negotiation scroll (Phase 5): one foreign power at a time, through an
## envoy on their soil. Shows how they regard us (the attitude breakdown the
## engine exposes), and puts offers — peace, trade, alliance, gifts, tribute
## demands, the purchase of whole towns — to their court.

signal deal_made

const RESPONSE_TEXT := {
	"war_ends": "They weigh the cost of the war, and agree. Peace is made.",
	"markets_open": "Agreed — the markets open between our peoples.",
	"oaths_sworn": "Oaths are sworn. Our houses stand together.",
	"gift_received": "The gift is graciously received.",
	"tribute_paid": "They grumble, and they pay.",
	"town_sold": "Papers are sealed; the town changes hands.",
	"no_envoy": "We have no envoy at their court.",
	"not_at_war": "There is no war to end.",
	"at_war": "They will not treat while we are at war.",
	"already_agreed": "That is already agreed between us.",
	"too_little_goodwill": "They refuse — there is too little goodwill.",
	"they_smell_victory": "They refuse — they believe they are winning.",
	"they_do_not_fear_us": "They laugh at the demand. Word of the insult spreads.",
	"they_are_poor": "Their treasury could not pay it.",
	"cannot_pay": "Our treasury cannot cover the sum.",
	"empty_handed": "An empty-handed gift flatters no one.",
	"insulting_price": "The price is beneath the town's worth.",
	"not_theirs": "That town is not theirs to sell.",
	"their_capital": "They will never sell their seat of power.",
	"their_last_town": "They will not sell their last holding.",
	"not_on_our_border": "Too far from our lands to govern.",
	"no_such_power": "There is no court to hear us.",
	"unknown_offer": "The envoy does not understand his own brief.",
}

var game: Game
var faction_id := ""

var _attitude_box: VBoxContainer
var _response: Label
var _sweeten: SpinBox
var _gift: SpinBox
var _buy_options: OptionButton
var _buyable: Array = []


func _init() -> void:
	title = "Negotiation"
	min_size = Vector2i(560, 620)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(530, 560)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	add_child(scroll)

	_attitude_box = VBoxContainer.new()
	content.add_child(_attitude_box)
	content.add_child(HSeparator.new())

	_response = Label.new()
	_response.text = "Our envoy awaits instructions."
	_response.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_response.add_theme_font_size_override("font_size", 12)
	_response.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	content.add_child(_response)
	content.add_child(HSeparator.new())

	var sweeten_row := HBoxContainer.new()
	sweeten_row.add_child(_small_label("Sweeten offers with denarii:"))
	_sweeten = SpinBox.new()
	_sweeten.max_value = 100000
	_sweeten.step = 250
	sweeten_row.add_child(_sweeten)
	content.add_child(sweeten_row)

	var offers_row := HBoxContainer.new()
	offers_row.add_child(_offer_button("Offer peace", func(): _propose({"kind": "peace", "payment": int(_sweeten.value)})))
	offers_row.add_child(_offer_button("Trade rights", func(): _propose({"kind": "trade", "payment": int(_sweeten.value)})))
	offers_row.add_child(_offer_button("Alliance", func(): _propose({"kind": "alliance", "payment": int(_sweeten.value)})))
	content.add_child(offers_row)

	var gift_row := HBoxContainer.new()
	gift_row.add_child(_small_label("Gift:"))
	_gift = SpinBox.new()
	_gift.max_value = 100000
	_gift.step = 250
	_gift.value = 1000
	gift_row.add_child(_gift)
	gift_row.add_child(_offer_button("Send the gift", func(): _propose({"kind": "gift", "payment": int(_gift.value)})))
	gift_row.add_child(_offer_button("Demand tribute", func(): _propose({"kind": "demand_tribute"})))
	content.add_child(gift_row)

	var buy_row := HBoxContainer.new()
	buy_row.add_child(_small_label("Buy town:"))
	_buy_options = OptionButton.new()
	buy_row.add_child(_buy_options)
	buy_row.add_child(_offer_button("Offer the price", _propose_purchase))
	content.add_child(buy_row)


func open_for(current_game: Game, target_faction: String) -> void:
	game = current_game
	faction_id = target_faction
	title = "Negotiation with %s" % game.data.factions.get(faction_id, {}).get("name", faction_id)
	_response.text = "Our envoy awaits instructions."
	_rebuild()
	popup_centered()


func _rebuild() -> void:
	for child in _attitude_box.get_children():
		_attitude_box.remove_child(child)
		child.queue_free()

	var attitude := game.attitude_of(faction_id)
	var total := float(attitude["total"])
	var header := Label.new()
	header.text = "They regard us as %s (%+.0f)" % [_descriptor(total), total]
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_attitude_box.add_child(header)
	for factor in attitude["factors"]:
		var value := float(factor["value"])
		var row := Label.new()
		row.text = "    %s  %+.0f" % [String(factor["label"]).replace("_", " "), value]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color",
			Color(0.55, 0.85, 0.55) if value >= 0 else Color(0.9, 0.55, 0.5))
		_attitude_box.add_child(row)

	_buyable = game.buyable_regions(faction_id)
	_buy_options.clear()
	for offer in _buyable:
		_buy_options.add_item("%s (%d)" % [
			game.data.regions[offer["region"]]["settlement_name"], int(offer["price"])])
	_buy_options.disabled = _buyable.is_empty()


func _propose(offer: Dictionary) -> void:
	var verdict := game.propose(faction_id, offer)
	var reason := String(verdict.get("reason", "unknown_offer"))
	_response.text = RESPONSE_TEXT.get(reason, reason)
	if verdict.get("accept", false):
		deal_made.emit()
	_rebuild()


func _propose_purchase() -> void:
	if _buy_options.selected < 0 or _buy_options.selected >= _buyable.size():
		return
	var offer: Dictionary = _buyable[_buy_options.selected]
	_propose({"kind": "buy_region", "region": offer["region"], "payment": int(offer["price"])})


func _descriptor(total: float) -> String:
	if total >= 40.0:
		return "a fast friend"
	if total >= 15.0:
		return "friendly"
	if total >= -14.0:
		return "wary"
	if total >= -40.0:
		return "cold"
	return "hostile"


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	return label


func _offer_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(handler)
	return button
