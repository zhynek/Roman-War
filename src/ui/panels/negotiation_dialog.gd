class_name NegotiationDialog
extends AcceptDialog
## The offer builder: pick terms — a new stance, payments and tribute either
## way, a region changing hands — and watch the other side's live appraisal
## (the evaluate_offer factor breakdown) before committing. Proposing is final:
## an accepted offer takes effect at once.

signal offer_concluded

const NONE_REGION := "— none —"

var game: Game
var other_id := ""

var _stance: OptionButton
var _give_payment: SpinBox
var _ask_payment: SpinBox
var _give_tribute_amount: SpinBox
var _give_tribute_turns: SpinBox
var _ask_tribute_amount: SpinBox
var _ask_tribute_turns: SpinBox
var _give_region: OptionButton
var _ask_region: OptionButton
var _hint: RichTextLabel
var _stance_values: Array = []
var _give_region_ids: Array = []
var _ask_region_ids: Array = []


func _init() -> void:
	title = "Negotiation"
	min_size = Vector2i(560, 620)
	ok_button_text = "Close"


func open_for(current_game: Game, faction_id: String) -> void:
	game = current_game
	other_id = faction_id
	title = "Negotiate with %s" % game.data.factions.get(other_id, {}).get("name", other_id)
	_build_form()
	_refresh_hint()
	popup_centered()


func _build_form() -> void:
	for child in get_children():
		if child is VBoxContainer:
			remove_child(child)
			child.queue_free()
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)

	var player: String = game.state["player_faction"]
	var current := DiplomacyRules.stance_between(game.state, player, other_id)

	_label(content, "Terms of the agreement", 14)
	var stance_row := HBoxContainer.new()
	_label(stance_row, "New stance: ", 12)
	_stance = OptionButton.new()
	_stance_values = [""]
	_stance.add_item("No change")
	var stance_names := {"neutral": "Peace", "trade": "Trade rights", "alliance": "Alliance"}
	for stance in ["neutral", "trade", "alliance"]:
		if stance == current:
			continue
		if stance == "neutral" and current != "war":
			continue  # "peace" only means something in a war
		_stance.add_item(stance_names[stance])
		_stance_values.append(stance)
	_stance.item_selected.connect(func(_index): _refresh_hint())
	stance_row.add_child(_stance)
	content.add_child(stance_row)

	content.add_child(HSeparator.new())
	_label(content, "We give", 13)
	_give_payment = _money_row(content, "Payment: ",
		maxi(int(game.state["factions"][player]["treasury"]), 0))
	var give_tribute := _tribute_row(content)
	_give_tribute_amount = give_tribute[0]
	_give_tribute_turns = give_tribute[1]
	_give_region = _region_row(content, "Cede region: ", player, _give_region_ids, true)

	content.add_child(HSeparator.new())
	_label(content, "We ask", 13)
	_ask_payment = _money_row(content, "Payment: ", 100000)
	var ask_tribute := _tribute_row(content)
	_ask_tribute_amount = ask_tribute[0]
	_ask_tribute_turns = ask_tribute[1]
	_ask_region = _region_row(content, "Their region: ", other_id, _ask_region_ids, false)

	content.add_child(HSeparator.new())
	_hint = RichTextLabel.new()
	_hint.bbcode_enabled = true
	_hint.fit_content = true
	_hint.custom_minimum_size = Vector2(520, 140)
	content.add_child(_hint)

	var propose := Button.new()
	propose.text = "Propose these terms"
	propose.pressed.connect(_propose)
	content.add_child(propose)


func build_offer() -> Dictionary:
	var offer := {
		"to": other_id,
		"stance": _stance_values[maxi(_stance.selected, 0)],
		"give_payment": int(_give_payment.value),
		"give_tribute": null,
		"give_regions": [],
		"ask_payment": int(_ask_payment.value),
		"ask_tribute": null,
		"ask_regions": [],
	}
	if int(_give_tribute_amount.value) > 0:
		offer["give_tribute"] = {"amount": int(_give_tribute_amount.value),
			"turns": int(_give_tribute_turns.value)}
	if int(_ask_tribute_amount.value) > 0:
		offer["ask_tribute"] = {"amount": int(_ask_tribute_amount.value),
			"turns": int(_ask_tribute_turns.value)}
	if _give_region.selected > 0:
		offer["give_regions"] = [_give_region_ids[_give_region.selected - 1]]
	if _ask_region.selected > 0:
		offer["ask_regions"] = [_ask_region_ids[_ask_region.selected - 1]]
	return offer


func _propose() -> void:
	var verdict := game.propose_offer(build_offer())
	if verdict["accept"]:
		_hint.text = "[color=#80c080][b]They accept the terms.[/b][/color]"
		offer_concluded.emit()
		# The agreement stands; the scroll can close at leisure.
	else:
		_refresh_hint()
		_hint.append_text("\n[color=#e06050][b]They refuse these terms.[/b][/color]")


func _refresh_hint() -> void:
	if game == null:
		return
	var verdict := game.preview_offer(build_offer())
	var lines := "[b]Their appraisal:[/b]\n"
	for factor in verdict["breakdown"]:
		var value := float(factor["value"])
		var color := "#80c080" if value >= 0 else "#e0a060"
		lines += "[color=%s]%+.0f[/color]  %s\n" % [color, value, String(factor["label"]).replace("_", " ")]
	var leaning := "[color=#80c080]They would accept.[/color]" if verdict["accept"] \
		else "[color=#e0a060]They would refuse.[/color]"
	_hint.text = lines + leaning


func _money_row(parent: VBoxContainer, caption: String, cap: int) -> SpinBox:
	var row := HBoxContainer.new()
	_label(row, caption, 12)
	var spin := SpinBox.new()
	spin.max_value = cap
	spin.step = 50
	spin.value_changed.connect(func(_value): _refresh_hint())
	row.add_child(spin)
	parent.add_child(row)
	return spin


func _tribute_row(parent: VBoxContainer) -> Array:
	var row := HBoxContainer.new()
	_label(row, "Tribute: ", 12)
	var amount := SpinBox.new()
	amount.max_value = 5000
	amount.step = 50
	amount.value_changed.connect(func(_value): _refresh_hint())
	row.add_child(amount)
	_label(row, " a season, for ", 12)
	var turns := SpinBox.new()
	turns.min_value = 1
	turns.max_value = 40
	turns.value = 8
	turns.value_changed.connect(func(_value): _refresh_hint())
	row.add_child(turns)
	_label(row, " seasons", 12)
	parent.add_child(row)
	return [amount, turns]


func _region_row(parent: VBoxContainer, caption: String, owner: String, into_ids: Array, exclude_capital: bool) -> OptionButton:
	var row := HBoxContainer.new()
	_label(row, caption, 12)
	var picker := OptionButton.new()
	picker.add_item(NONE_REGION)
	into_ids.clear()
	var capital: String = game.state["factions"][owner]["capital"]
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if game.state["settlements"][region_id]["owner"] != owner:
			continue
		if exclude_capital and region_id == capital:
			continue
		picker.add_item(game.data.regions[region_id]["settlement_name"])
		into_ids.append(region_id)
	picker.item_selected.connect(func(_index): _refresh_hint())
	row.add_child(picker)
	parent.add_child(row)
	return picker


func _label(parent: Node, text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
