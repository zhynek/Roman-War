class_name MapCommandBar
extends PanelContainer
## Persistent, readable map orders. Hover is transient; clicking a destination
## in planning mode pins it for review. This view never executes game rules.

signal planning_requested
signal issue_requested
signal cancel_requested
signal halt_requested
signal post_requested
signal sight_changed(enabled: bool)
signal focus_requested
signal forced_changed(enabled: bool)
signal follow_changed(enabled: bool)

var game: Game
var title: Label
var detail: Label
var hint: Label
var choose: Button
var issue: Button
var cancel: Button
var halt: Button
var focus: Button
var post: Button
var sight: CheckButton
var forced: CheckButton
var follow: CheckButton
var _last_fit_width := -1.0
var _actions: HFlowContainer


func _ready() -> void:
	var style := UiStyle._flat(Color(0.065, 0.09, 0.10, 0.97), 8)
	style.set_content_margin_all(12)
	style.border_color = Color(UiStyle.ACCENT, 0.65)
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)
	title = _line(column, 16, UiStyle.PARCHMENT)
	detail = _line(column, 12, UiStyle.TEXT)
	hint = _line(column, 12, UiStyle.TEXT_DIM)
	_actions = HFlowContainer.new()
	_actions.add_theme_constant_override("h_separation", 5)
	column.add_child(_actions)
	choose = _button("choose", func(): planning_requested.emit())
	issue = _button("issue", func(): issue_requested.emit())
	issue.theme_type_variation = &"EndTurnButton"
	cancel = _button("cancel", func(): cancel_requested.emit())
	halt = _button("halt", func(): halt_requested.emit())
	focus = _button("focus", func(): focus_requested.emit())
	post = _button("post_tower", func(): post_requested.emit())
	sight = CheckButton.new()
	sight.text = words("sight")
	sight.focus_mode = Control.FOCUS_NONE
	sight.toggled.connect(func(enabled: bool): sight_changed.emit(enabled))
	_actions.add_child(sight)
	forced = CheckButton.new()
	forced.text = words("forced")
	forced.focus_mode = Control.FOCUS_NONE
	forced.toggled.connect(func(enabled: bool): forced_changed.emit(enabled))
	_actions.add_child(forced)
	follow = CheckButton.new()
	follow.text = words("follow")
	follow.button_pressed = true
	follow.focus_mode = Control.FOCUS_NONE
	follow.toggled.connect(func(enabled: bool): follow_changed.emit(enabled))
	_actions.add_child(follow)


func words(key: String, params: Dictionary = {}) -> String:
	var text := String(game.data.effects_glossary.get("map_commands", {}).get(key, key)) if game != null else key
	return text.format(params)


func render(army_id: String, preview: Dictionary, planning: bool, pinned: bool) -> void:
	if title == null:
		return
	visible = army_id != ""
	if not visible:
		return
	var summary := game.force_summary(army_id)
	if summary.is_empty():
		hide()
		return
	var commander := words("captain")
	if summary["general"] != null:
		commander = String(summary["general"]["name"])
	title.text = words("column", {"commander": commander, "men": summary["soldiers"]})
	detail.text = words("ready", {"men": summary["soldiers"], "units": summary["units"],
		"movement": String.num(float(summary["movement_left"]), 2)})
	var army: Dictionary = game.state["armies"][army_id]
	var mobility := MovementRules.mobility_profile(game.data, army)
	detail.text = words("mobility", {"class": String(mobility["class"]).replace("_", " ").capitalize(),
		"left": String.num(float(summary["movement_left"]), 2), "max": String.num(float(summary["movement_max"]), 2),
		"sight": ReconRules.army_sight(game.data, army)})
	var supply := TerrainRules.supply_regions(game.data, game.state, String(army["owner"]))
	detail.text += " · " + words("ground_supply", {"status": words("supply_connected" if supply.has(army["region"]) else "supply_cut")})
	var quote := game.watchpost_quote(army_id)
	post.text = words("post_tower" if int(quote["level"]) == 1 else "post_fort", quote)
	post.disabled = not quote["ok"]
	post.tooltip_text = words("post_help", quote) if quote["ok"] else words(quote["reason"])
	post.visible = int(quote["level"]) <= 2
	hint.text = words("planning" if planning else "selected")
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	if not preview.is_empty():
		var target := String(preview["target"])
		var known := game.visible_regions().has(target)
		var region: Dictionary = game.data.regions[target] if game.known_regions().has(target) else {}
		var town := String(region.get("settlement_name" if known else "name", target))
		title.text = words(preview["action"], {"town": town})
		var turns := int(preview["turns"])
		var arrival := words("arrival_now") if turns <= 1 else words("arrival_later", {"turns": turns})
		detail.text = words("route", {"cost": String.num(float(preview["cost"]), 2),
			"arrival": arrival, "terrain": String(region.get("terrain", "")).capitalize()})
		if preview["action"] in ["attack", "siege", "assault"]:
			detail.text = words("combat_cost", {"cost": String.num(float(preview["cost"]), 2),
				"terrain": String(region.get("terrain", "")).capitalize()})
		if preview["reason"] in ["unreachable", "uncharted"]:
			detail.text = words("unavailable_route")
		var warnings: Array[String] = []
		var crossing := String(preview.get("crossing", ""))
		if crossing != "" and game.known_regions().has(target):
			var crossing_info: Dictionary = game.data.terrain_content.get("crossing_types", {}).get(crossing, {})
			warnings.append(String(crossing_info.get("description", "")))
		if preview["reason"] != "":
			warnings.append(words(preview["reason"]))
		elif preview["action"] in ["attack", "assault"]:
			warnings.append(words("combat_warning"))
		elif preview["action"] == "siege":
			warnings.append(words("siege_warning"))
		elif preview["action"] == "withdraw":
			warnings.append(words("withdraw_warning"))
		elif preview["blocked"]:
			warnings.append(words("approach_warning"))
		elif preview["forced"]:
			warnings.append(words("forced_warning"))
		if preview["uncertain"]:
			warnings.append(words("fog_warning"))
		hint.text = " ".join(warnings) if not warnings.is_empty() else words("pinned" if pinned else "planning" if planning else "selected")
		if not warnings.is_empty():
			hint.add_theme_color_override("font_color", UiStyle.CAPITAL_GOLD)
	choose.visible = not planning
	cancel.visible = planning
	issue.visible = planning and pinned
	issue.disabled = preview.is_empty() or preview.get("reason", "") != "" or preview.get("action", "") == "inspect"
	halt.visible = not game.state["armies"][army_id].get("march_path", []).is_empty()
	if preview.is_empty() and halt.visible:
		var path: Array = game.state["armies"][army_id]["march_path"]
		var town := String(game.data.regions[path.back()].get("name", path.back()))
		hint.text = words("queued", {"town": town, "steps": path.size()})


func fit_to(area: Vector2) -> void:
	custom_minimum_size.x = maxf(280, area.x - 82)
	# Seed a real wrapping width before measuring height. A just-created
	# Label otherwise measures every word on its own line until the next
	# container pass, briefly covering the entire map during selection.
	var content_width := custom_minimum_size.x - 24
	if not is_equal_approx(content_width, _last_fit_width):
		_last_fit_width = content_width
		for label in [title, detail, hint]:
			label.size.x = content_width
		_actions.size.x = content_width
	size = Vector2(custom_minimum_size.x, get_combined_minimum_size().y)
	position.x = 14
	position.y = area.y - size.y - 14


func _line(column: VBoxContainer, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 3
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	column.add_child(label)
	return label


func _button(key: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = words(key)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	_actions.add_child(button)
	return button
