class_name InfoCard
extends PanelContainer
## The R1/R2/R3 payoff: one card that shows what a thing IS. A unit card
## carries its portrait, class, stats, speed, its skills explained, and the
## building that trains it; a building card carries its portrait, each
## level's named effects, and the troops each tier unlocks — the class-to-
## building correspondence, clickable in both directions (an unlock row
## opens that unit's card; a unit's trained-at line opens the building
## browser side). Everything it says comes from Game.unit_profile /
## Game.building_profile; everything it draws comes from Illustrations.

signal closed

const CARD_WIDTH := 340.0
const ART_HEIGHT := 150.0

var game: Game
var _content: VBoxContainer
var _scroll: ScrollContainer


class ArtPlate:
	extends Control
	## The swappable art slot: draws a building or a unit through the
	## Illustrations contract.
	var mode := ""          # "unit" | "building"
	var subject := ""       # unit class or building kind
	var culture := "neutral"
	var tier := 1

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.095, 0.11))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.32, 0.30, 0.26, 0.5), false, 1.0)
		if mode == "unit":
			Illustrations.draw_unit(self, Rect2(Vector2.ZERO, size), subject, culture)
		elif mode == "building":
			Illustrations.draw_building(self, Rect2(Vector2.ZERO, size), subject, culture, tier)


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)


func show_unit(current_game: Game, template_id: String) -> void:
	game = current_game
	var profile := game.unit_profile(template_id)
	if profile.is_empty():
		return
	_clear()
	_header_row(String(profile["name"]), String(profile["class_entry"]["name"]))
	_art("unit", String(profile["class_id"]), String(profile["culture"]), 1)
	_label(String(profile["class_entry"]["blurb"]), UiStyle.TEXT_DIM, 11)

	var grid := GridContainer.new()
	grid.columns = 4
	_content.add_child(grid)
	_stat(grid, "Men", str(profile["soldiers"]))
	_stat(grid, "Attack", str(profile["attack"]))
	_stat(grid, "Charge", str(profile["charge"]))
	_stat(grid, "Missile", str(profile["missile_attack"]) if int(profile["missile_attack"]) > 0 else "—")
	_stat(grid, "Defense", str(profile["defense"]))
	_stat(grid, "Morale", str(profile["morale"]))
	_stat(grid, "Speed", str(profile["speed"]))
	_stat(grid, "Upkeep", str(profile["upkeep"]))

	if not (profile["attributes"] as Array).is_empty():
		_section("Skills")
		for skill in profile["attributes"]:
			_label("• %s — %s" % [skill["name"], skill["blurb"]], UiStyle.TEXT, 11)

	_section("Trained at")
	var trained: Dictionary = profile["trained_at"]
	var where := "%s, tier %d" % [trained["kind_entry"]["name"], int(trained["level"])]
	if String(trained["temple_god"]) != "":
		where += " (of %s)" % String(trained["temple_god"]).capitalize()
	_label(where, UiStyle.PARCHMENT, 12)
	_label(String(trained["kind_entry"]["blurb"]), UiStyle.TEXT_DIM, 11)

	if String(profile["description"]) != "":
		_section("")
		_label("\"%s\"" % String(profile["description"]), UiStyle.TEXT_DIM, 11)
	_close_row()


func show_building(current_game: Game, chain_id: String, culture_hint: String = "") -> void:
	game = current_game
	var profile := game.building_profile(chain_id)
	if profile.is_empty():
		return
	_clear()
	_header_row(String(profile["name"]), String(profile["kind_entry"]["name"]))
	var culture := culture_hint
	if culture == "" and not (profile["cultures"] as Array).is_empty():
		culture = String(profile["cultures"][0])
	_art("building", String(profile["kind"]), culture, (profile["levels"] as Array).size())
	_label(String(profile["kind_entry"]["blurb"]), UiStyle.TEXT_DIM, 11)

	for level in profile["levels"]:
		_section("%d · %s   (%d, %d turns)" % [int(level["index"]), String(level["name"]),
			int(level["cost"]), int(level["build_turns"])])
		for effect in level["effects"]:
			_label("• %s %s — %s" % [effect["name"], str(effect["value"]), effect["blurb"]],
				UiStyle.TEXT, 11)
		for unlock in level["unlocks"]:
			var row := Button.new()
			row.text = "▸ %s  (%s)" % [String(unlock["name"]), String(unlock["class_entry"]["name"])]
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.add_theme_font_size_override("font_size", 11)
			var unlock_id := String(unlock["id"])
			row.pressed.connect(func(): show_unit(game, unlock_id))
			_content.add_child(row)
		if String(level["description"]) != "":
			_label(String(level["description"]), UiStyle.TEXT_DIM, 10)
	_close_row()


## --- assembly --------------------------------------------------------------

func _clear() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0


func _header_row(title: String, chip: String) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var chip_label := Label.new()
	chip_label.text = chip
	chip_label.add_theme_font_size_override("font_size", 11)
	chip_label.add_theme_color_override("font_color", UiStyle.ACCENT)
	row.add_child(chip_label)


func _art(mode: String, subject: String, culture: String, tier: int) -> void:
	var plate := ArtPlate.new()
	plate.mode = mode
	plate.subject = subject
	plate.culture = culture
	plate.tier = tier
	plate.custom_minimum_size = Vector2(CARD_WIDTH - 20, ART_HEIGHT)
	_content.add_child(plate)


func _section(text: String) -> void:
	_content.add_child(HSeparator.new())
	if text == "":
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	_content.add_child(label)


func _label(text: String, color: Color, font_size: int) -> void:
	if text == "":
		return
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_content.add_child(label)


func _stat(grid: GridContainer, stat_name: String, value: String) -> void:
	var name_label := Label.new()
	name_label.text = stat_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	grid.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value + "   "
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", UiStyle.TEXT)
	grid.add_child(value_label)


func _close_row() -> void:
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): closed.emit())
	_content.add_child(close)


func sized_for(viewport_height: float) -> void:
	_scroll.custom_minimum_size = Vector2(CARD_WIDTH, minf(520.0, viewport_height - 60.0))
