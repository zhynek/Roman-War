class_name BuildDrawer
extends PanelContainer
## The building yard: a drawer over the map showing what a settlement can raise,
## what it does, and where it leads. A pure view — CampaignScreen owns every
## scrap of its selection state, exactly as it owns selected_army, because the
## panels around it are destroyed and rebuilt on each refresh.
##
## PanelContainer rather than a bare Control: it needs an opaque ground over the
## painted map.

signal closed
signal queued
signal chain_selected(chain_id: String)
signal tier_selected(index: int)
signal tab_selected(tab: String)

const GOLD := Color(0.95, 0.90, 0.75)
const BODY := Color(0.85, 0.85, 0.85)
const DIM := Color(0.62, 0.62, 0.60)
const GOOD := Color(0.55, 0.85, 0.55)
const BAD := Color(0.90, 0.55, 0.50)
const WARN := Color(0.90, 0.80, 0.50)
const LIST_W := 250.0
const LADDER_H := 132.0
const COMPACT_BELOW := 320.0
# The order a governor thinks in — what rules the town, what defends it, what
# feeds it, what pays for it, what arms it — rather than the alphabet.
const KIND_ORDER := ["government", "walls", "farms", "market", "roads", "port",
	"mines", "health", "entertainment", "education", "temple", "barracks",
	"stables", "archery_range", "siege_workshop", "naval", "execution"]

var game: Game
var _list: VBoxContainer
var _detail: VBoxContainer
var _ladder: HBoxContainer
var _ladder_box: ScrollContainer
var _title: Label
var _tabs := {}
var _compact := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.12, 0.97)
	style.border_color = Color(0.86, 0.80, 0.66, 0.55)
	style.border_width_top = 2
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	add_child(root)
	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(LIST_W, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)

	_ladder_box = ScrollContainer.new()
	_ladder_box.custom_minimum_size = Vector2(0, LADDER_H)
	_ladder_box.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_ladder_box)
	_ladder = HBoxContainer.new()
	_ladder.add_theme_constant_override("separation", 4)
	_ladder_box.add_child(_ladder)


func fit_to(map_size: Vector2) -> void:
	## Sized off the map's real height, never a fixed minimum: MapView's own
	## minimum is 600x400, and a tall plate simply will not coexist with that.
	var height := clampf(map_size.y * 0.62, 180.0, 400.0)
	offset_top = -height
	_compact = height < COMPACT_BELOW
	_ladder_box.custom_minimum_size = Vector2(0, 62.0 if _compact else LADDER_H)


func render(new_game: Game, region_id: String, tab: String, chain_id: String, tier: int) -> void:
	game = new_game
	if not visible or region_id == "":
		return
	_clear(_list)
	_clear(_detail)
	_clear(_ladder)
	for key in _tabs:
		_tabs[key].add_theme_color_override("font_color", GOLD if key == tab else DIM)

	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if settlement.is_empty():
		_line(_detail, "Nothing is built here.", BODY, 12)
		return
	var region: Dictionary = game.data.regions[region_id]
	_title.text = "  %s · %s" % [region.get("settlement_name", region["name"]),
		String(SettlementRules.settlement_level(game.data, settlement)).replace("_", " ").capitalize()]

	if tab == "units":
		_render_units(region_id, chain_id)
		return
	var rows := game.building_chains(region_id)
	if chain_id == "":
		chain_id = _default_chain(rows)
	_build_list(rows, chain_id)
	if chain_id == "":
		return
	var sheet := game.building_dossier(region_id, chain_id)
	if sheet.is_empty():
		return
	var shown := _shown_tier(sheet, tier)
	_build_detail(region_id, sheet, shown)
	_build_ladder(region_id, sheet, shown)


## --- the muster hall -------------------------------------------------------

func _render_units(region_id: String, template_id: String) -> void:
	var rows := game.recruitable_units(region_id)
	if rows.is_empty():
		_line(_detail, "  No troops can be raised here.", BODY, 12)
		return
	if template_id == "":
		template_id = _default_unit(rows)
	_build_unit_list(rows, template_id)
	var sheet := game.unit_dossier(region_id, template_id)
	if sheet.is_empty():
		return
	_build_unit_detail(region_id, sheet)
	_build_unit_ladder(region_id, sheet)


func _default_unit(rows: Array) -> String:
	for row in rows:
		if bool(row["action"]["can_queue"]):
			return String(row["id"])
	return String(rows[0]["id"])


func _build_unit_list(rows: Array, selected: String) -> void:
	var by_class := {}
	for row in rows:
		by_class.get_or_add(String(row["class"]), []).append(row)
	var names: Array = by_class.keys()
	names.sort()
	for cls in names:
		_line(_list, String(cls).replace("_", " ").capitalize(), GOLD, 11)
		for row in by_class[cls]:
			var ready: bool = bool(row["action"]["can_queue"])
			var reason := String(row["action"]["reason"])
			var colour := BODY if ready else (DIM if reason == "building" or reason == "era" else WARN)
			var button := Button.new()
			button.text = "%s %s %s" % ["▶" if row["id"] == selected else " ",
				"○" if ready else "·", row["name"]]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 11)
			button.add_theme_color_override("font_color", colour)
			var id := String(row["id"])
			button.pressed.connect(func(): chain_selected.emit(id))
			_list.add_child(button)


func _build_unit_detail(region_id: String, sheet: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_child(head)
	var plate_h := 92.0 if _compact else 150.0
	var plate := ArtPlate.new()
	plate.custom_minimum_size = Vector2(plate_h * 1.63, plate_h)
	var ctx := ArtContext.for_settlement(game, region_id, 2)
	ctx["experience"] = int(sheet["starts_with_experience"])
	plate.set_plate(UnitArt.for_data(game.data).unit_plate(game.data, String(sheet["id"]), ctx))
	head.add_child(plate)

	var prose := VBoxContainer.new()
	prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(prose)
	_line(prose, "  " + String(sheet["name"]), GOLD, 15)
	_line(prose, "  %s  ·  %d men  ·  %d denarii, %d upkeep"
		% [String(sheet["class"]).replace("_", " "), int(sheet["soldiers"]),
		   int(sheet["cost"]), int(sheet["upkeep"])], DIM, 10)
	_wrap(prose, String(sheet["description"]), BODY, 11)
	_build_unit_action(prose, region_id, sheet)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prose.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	_fit(left, "  IN THE LINE", GOLD, 10)
	for pair in [["attack", "Attack"], ["missile_attack", "Missiles"], ["charge", "Charge"],
			["defense", "Defence"], ["morale", "Morale"], ["speed", "Speed"]]:
		if int(sheet[pair[0]]) > 0:
			_fit(left, "     %s  %d" % [pair[1], int(sheet[pair[0]])], BODY, 11)
	if int(sheet["starts_with_experience"]) > 0:
		_fit(left, "     Musters with %d experience" % int(sheet["starts_with_experience"]), GOOD, 11)

	_fit(right, "  WHAT THEY NEED", GOLD, 10)
	var requires: Dictionary = sheet["requires"]
	for candidate in requires["chains"]:
		var mark := "▪" if bool(candidate["met"]) else "○"
		_fit(right, "     %s %s at tier %d" % [mark, candidate["name"], int(candidate["needs_tier"])],
			GOOD if bool(candidate["met"]) else DIM, 11)
		if not bool(candidate["met"]):
			_fit(right, "        (%s stands at %d)" % [candidate["name"], int(candidate["built_tier"])],
				DIM, 10)
	if String(sheet["action"]["reason"]) == "era":
		# Only when the age is actually wrong: a pre-Marian unit in 270 BC is
		# not "locked", it is simply the unit of the day.
		_fit(right, "     " + BuildingInfo.caption(game.data, "era_locked"), DIM, 10)


func _build_unit_action(box: Control, region_id: String, sheet: Dictionary) -> void:
	var action: Dictionary = sheet["action"]
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	if bool(action["can_queue"]):
		button.text = "Muster — %d denarii, %d men" % [int(sheet["cost"]), int(sheet["soldiers"])]
		button.add_theme_color_override("font_color", GOLD)
		var id := String(sheet["id"])
		button.pressed.connect(func():
			game.queue_unit(region_id, id)
			queued.emit())
	else:
		button.disabled = true
		button.add_theme_color_override("font_color_disabled", BAD)
		# queue_unit refuses on population as well as on coin, so both gates get
		# a sentence rather than a button that quietly does nothing.
		match String(action["reason"]):
			"unaffordable":
				button.text = "Muster — %d denarii (you have %d)" % [int(sheet["cost"]),
					int(action["treasury"])]
			"manpower":
				button.text = "Not enough men — %d live here, %d would leave fewer than %d" \
					% [int(action["population"]), int(sheet["soldiers"]), int(action["min_population"])]
			"era":
				button.text = "Not until the legions are reformed"
			_:
				button.text = "The training ground is not built"
	box.add_child(button)


func _build_unit_ladder(region_id: String, sheet: Dictionary) -> void:
	## The reverse link: which rung of which chain opens this unit, drawn as the
	## same ladder so the two tabs read as one idea.
	var requires: Dictionary = sheet["requires"]
	if (requires["chains"] as Array).is_empty():
		return
	var chain_id := String(requires["chains"][0]["chain"])
	for candidate in requires["chains"]:
		if bool(candidate["met"]):
			chain_id = String(candidate["chain"])
			break
	var dossier := game.building_dossier(region_id, chain_id)
	if dossier.is_empty():
		return
	_build_ladder(region_id, dossier, int(requires["level"]))


func _default_chain(rows: Array) -> String:
	## Opening with nothing chosen must never land on a blank pane: the first
	## thing worth building, else the first thing standing, else the first row.
	for row in rows:
		if row["buildable_now"]:
			return String(row["chain"])
	for row in rows:
		if int(row["built_tier"]) > 0:
			return String(row["chain"])
	return String(rows[0]["chain"]) if not rows.is_empty() else ""


func _shown_tier(sheet: Dictionary, tier: int) -> int:
	var count: int = (sheet["tiers"] as Array).size()
	if tier >= 1 and tier <= count:
		return tier
	return clampi(int(sheet["built_tier"]) + 1, 1, count)


## --- the three panes -------------------------------------------------------

func _build_list(rows: Array, selected: String) -> void:
	var by_kind := {}
	for row in rows:
		by_kind.get_or_add(String(row["kind"]), []).append(row)
	var kinds: Array = by_kind.keys()
	kinds.sort_custom(func(a, b):
		var ia := KIND_ORDER.find(String(a))
		var ib := KIND_ORDER.find(String(b))
		if ia < 0:
			ia = 99
		if ib < 0:
			ib = 99
		return ia < ib if ia != ib else String(a) < String(b))
	for kind in kinds:
		_line(_list, String(kind).replace("_", " ").capitalize(), GOLD, 11)
		for row in by_kind[kind]:
			var mark := "·"
			var colour := DIM
			if row["queued"]:
				mark = "◐"
				colour = WARN
			elif row["buildable_now"]:
				mark = "○"
				colour = BODY
			if int(row["built_tier"]) > 0:
				mark = "▪"
				colour = GOOD if not row["foreign"] else WARN
			var text := "  %s %s" % [mark, row["name"]]
			if int(row["built_tier"]) > 0:
				text += "  %d/%d" % [int(row["built_tier"]), int(row["tier_count"])]
			var button := Button.new()
			button.text = ("▶" if row["chain"] == selected else " ") + text
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 11)
			button.add_theme_color_override("font_color", colour)
			var id := String(row["chain"])
			button.pressed.connect(func(): chain_selected.emit(id))
			_list.add_child(button)


func _build_detail(region_id: String, sheet: Dictionary, tier_index: int) -> void:
	var tier: Dictionary = sheet["tiers"][tier_index - 1]
	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_child(head)

	var plate_h := 92.0 if _compact else 150.0
	var plate := ArtPlate.new()
	plate.custom_minimum_size = Vector2(plate_h * 1.63, plate_h)
	plate.set_plate(BuildingArt.for_data(game.data).building_plate(
		game.data, String(tier["level_id"]),
		ArtContext.for_settlement(game, region_id, 2)))
	head.add_child(plate)

	var prose := VBoxContainer.new()
	prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(prose)
	_line(prose, "  " + String(tier["name"]), GOLD, 15)
	_line(prose, "  " + String(sheet["name"]) + "  ·  tier %d of %d"
		% [tier_index, (sheet["tiers"] as Array).size()], DIM, 10)
	_wrap(prose, String(tier["description"]), BODY, 11)

	if sheet["foreign"] and int(sheet["built_tier"]) > 0:
		_wrap(prose, BuildingInfo.caption(game.data, "foreign_chain"), WARN, 10)

	_build_action(prose, region_id, sheet, tier, tier_index)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prose.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_build_effects(left, region_id, sheet, tier, tier_index)
	_build_unlocks(right, tier)


func _build_effects(box: Control, region_id: String, sheet: Dictionary,
		tier: Dictionary, tier_index: int) -> void:
	var lines: Array = tier["lines"]
	var steps := int(tier_index) - int(sheet["built_tier"])
	if int(sheet["built_tier"]) > 0 and steps > 1:
		# Standing totals, so inspecting a far rung measures several steps at
		# once. Say so, or the numbers read as a lie.
		_fit(box, "  " + BuildingInfo.caption(game.data, "cumulative_delta",
			{"steps": steps}), DIM, 10)
	if lines.is_empty():
		_fit(box, "  Nothing changes but the building itself.", DIM, 11)
	var by_heading := {}
	for line in lines:
		by_heading.get_or_add(String(line["heading"]), []).append(line)
	for heading in BuildingInfo.headings(game.data):
		var id := String(heading["id"])
		if not by_heading.has(id):
			continue
		_fit(box, "  " + String(heading["name"]).to_upper(), GOLD, 10)
		for line in by_heading[id]:
			var colour := BODY
			if String(line["status"]) == "inert":
				colour = DIM
			elif bool(line["matched"]):
				colour = DIM
			elif float(line["value"]) > 0.0:
				colour = GOOD
			elif float(line["value"]) < 0.0:
				colour = BAD
			_fit(box, "     " + String(line["text"]), colour, 11)
			if bool(line["matched"]) and String(line["rival"]) != "":
				_fit(box, "        " + BuildingInfo.caption(game.data,
					"already_matched", {"rival": line["rival"]}), DIM, 10)
			elif String(line["note"]) != "":
				_fit(box, "        " + String(line["note"]), DIM, 10)
			if String(line["key"]) == "growth" and BuildingInfo.growth_at_cap(
					game.data, game.state, region_id):
				_fit(box, "        " + BuildingInfo.caption(game.data,
					"growth_at_cap"), WARN, 10)
			if String(line["heading"]) == "money":
				pass
	var note: Dictionary = sheet["kind_note"]
	if not note.is_empty():
		var heading_name := ""
		for heading in BuildingInfo.headings(game.data):
			if heading["id"] == note["heading"]:
				heading_name = String(heading["name"])
		_fit(box, "  " + heading_name.to_upper(), GOLD, 10)
		_wrap(box, "     " + String(note["text"]), BODY, 11)
	for line in lines:
		if String(line["heading"]) == "money":
			_fit(box, "  " + BuildingInfo.caption(game.data, "income_approximate"), DIM, 9)
			break


func _build_unlocks(box: Control, tier: Dictionary) -> void:
	var unlocks: Array = tier["unlocks"]
	if unlocks.is_empty():
		return
	_fit(box, "  TROOPS THIS OPENS", GOLD, 10)
	for unit in unlocks:
		var text := "     %s  (%d men, %d denarii)" % [unit["name"],
			int(unit["soldiers"]), int(unit["cost"])]
		if bool(unit["era_locked"]):
			_fit(box, text, DIM, 11)
			_fit(box, "        " + BuildingInfo.caption(game.data, "era_locked"), DIM, 10)
		else:
			_fit(box, text, GOOD, 11)


func _build_action(box: Control, region_id: String, sheet: Dictionary,
		tier: Dictionary, tier_index: int) -> void:
	var action: Dictionary = sheet["action"]
	var next_tier := int(sheet["built_tier"]) + 1
	var state := String(tier["state"])
	if state == "built":
		_line(box, "  This stands here already.", DIM, 11)
		return
	if state == "in_progress":
		_line(box, "  Rising now.", WARN, 11)
		return
	if not (tier["blockers"] as Array).is_empty():
		for blocker in tier["blockers"]:
			_line(box, "  ✕ " + BuildingInfo.blocker_text(game.data, blocker), BAD, 11)
		return
	if tier_index != next_tier:
		return
	var verb := "Upgrade" if int(sheet["built_tier"]) > 0 else "Found"
	var label := "%s — %d denarii, %d turns" % [verb, int(action["cost"]), int(action["build_turns"])]
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	if not bool(action["affordable"]):
		# available_projects has never filtered on money and queue_project just
		# returns false, so the old panel showed a button that did nothing.
		button.text = "%s  (you have %d)" % [label, int(action["treasury"])]
		button.disabled = true
		button.add_theme_color_override("font_color_disabled", BAD)
	else:
		button.text = label
		button.add_theme_color_override("font_color", GOLD)
		var chain := String(sheet["chain"])
		button.pressed.connect(func():
			# Through the Game facade, so the guided trail's counters still fire.
			game.queue_building(region_id, chain)
			queued.emit())
	box.add_child(button)


func _build_ladder(region_id: String, sheet: Dictionary, shown: int) -> void:
	var ctx := ArtContext.for_settlement(game, region_id, 0)
	for tier in sheet["tiers"]:
		if _ladder.get_child_count() > 0:
			_line(_ladder, " › ", DIM, 14)
		_ladder.add_child(_tier_card(sheet, tier, shown, ctx))


func _tier_card(sheet: Dictionary, tier: Dictionary, shown: int, ctx: Dictionary) -> Control:
	var index := int(tier["index"])
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(126, 0)
	var state := String(tier["state"])
	var mark: String = {"built": "▪", "in_progress": "◐", "next": "●", "locked": "○"}.get(state, "○")
	var colour: Color = {"built": GOOD, "in_progress": WARN, "next": GOLD, "locked": DIM}.get(state, DIM)

	if not _compact:
		var thumb := ArtPlate.new()
		thumb.custom_minimum_size = Vector2(126, 58)
		thumb.modulate = Color(1, 1, 1, 1.0 if state != "locked" else 0.62)
		thumb.set_plate(BuildingArt.for_data(game.data).building_plate(
			game.data, String(tier["level_id"]), ctx))
		var pick := Button.new()
		pick.flat = true
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(126, 58)
		pick.pressed.connect(func(): tier_selected.emit(index))
		thumb.add_child(pick)
		card.add_child(thumb)

	var name_button := Button.new()
	name_button.text = "%s %d %s" % ["▶" if index == shown else " ", index, tier["name"]]
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.focus_mode = Control.FOCUS_NONE
	name_button.flat = true
	name_button.add_theme_font_size_override("font_size", 10)
	name_button.add_theme_color_override("font_color", colour)
	name_button.pressed.connect(func(): tier_selected.emit(index))
	card.add_child(name_button)

	var footer: String = str(mark) + " "
	match state:
		"built": footer += "built"
		"in_progress": footer += "rising"
		"next": footer += "%d denarii" % int(tier["cost"])
		_: footer += _short_blocker(tier)
	_line(card, "  " + footer, colour, 9)
	var unlocks: Array = tier["unlocks"]
	if not unlocks.is_empty():
		var names: Array = []
		for unit in unlocks:
			names.append(String(unit["name"]))
		_line(card, "  → " + ", ".join(names), BODY, 9)
	elif _military(String(sheet["kind"])):
		_line(card, "  " + BuildingInfo.caption(game.data, "no_new_troops"), DIM, 9)
	return card


func _short_blocker(tier: Dictionary) -> String:
	var blockers: Array = tier["blockers"]
	if blockers.is_empty():
		return "locked"
	return BuildingInfo.blocker_text(game.data, blockers[0])


static func _military(kind: String) -> bool:
	return kind in ["barracks", "stables", "archery_range", "siege_workshop", "naval", "temple"]


## --- chrome ---------------------------------------------------------------

func _build_header() -> HBoxContainer:
	var bar := HBoxContainer.new()
	for pair in [["construction", "Construction"], ["units", "Soldiers"]]:
		var button := Button.new()
		button.text = "  %s  " % pair[1]
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		var id := String(pair[0])
		button.pressed.connect(func(): tab_selected.emit(id))
		bar.add_child(button)
		_tabs[id] = button
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", BODY)
	bar.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var close := Button.new()
	close.text = " ✕ "
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(func(): closed.emit())
	bar.add_child(close)
	return bar


func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _line(box: Control, text: String, colour: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	box.add_child(label)
	return label


func _wrap(box: Control, text: String, colour: Color, size: int) -> Label:
	## Wrapping only works if the label may shrink: a custom minimum width
	## inside a ScrollContainer with horizontal scrolling off pushes the text
	## past the edge and it is clipped instead of wrapped.
	var label := _line(box, text, colour, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _fit(box: Control, text: String, colour: Color, size: int) -> Label:
	var label := _line(box, text, colour, size)
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
