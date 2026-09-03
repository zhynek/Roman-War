class_name MapContextMenu
extends PanelContainer
## The map's right-click dossier (R2): what stands in a province, at a
## glance — your garrison, your buildings, the armies present with each
## troop's skills named — and every row a door into its full info card.
## It reveals nothing the panel and tooltip do not already grant: a fogged
## province stays a name, and a rival city keeps its rosters to itself.

signal unit_info_requested(template_id: String)
signal building_info_requested(chain_id: String)

const MENU_WIDTH := 300.0
## Roster rows shown before the list folds into an "and N more" line — the
## menu is a glance; the full muster lives one left-click away in the panel.
const MAX_ROSTER_ROWS := 12

var game: Game
var _content: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(MENU_WIDTH, 0)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)


func open_for(current_game: Game, region_id: String) -> void:
	game = current_game
	_clear()
	var region: Dictionary = game.data.regions.get(region_id, {})
	if region.is_empty():
		return
	if not game.visible_regions().has(region_id):
		# Fog grants the land's name and nothing else — the same line the
		# tooltip draws, and no settlement name either.
		_title(String(region.get("name", region_id)))
		_line("Beyond our maps: no reports come from this land.", UiStyle.TEXT_DIM)
		return
	_title("%s — %s" % [String(region.get("settlement_name", region_id)),
		String(region.get("name", ""))])
	var player: String = game.state["player_faction"]
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	if not settlement.is_empty():
		_settlement_section(settlement, player)
	_armies_section(region_id, player)


## --- sections ---------------------------------------------------------------

func _settlement_section(settlement: Dictionary, player: String) -> void:
	var owner := String(settlement["owner"])
	var faction: Dictionary = game.data.factions.get(owner, {})
	var level := SettlementRules.settlement_level(game.data, settlement)
	_line("%s · %s, %d souls" % [String(faction.get("name", owner)),
		level.capitalize().replace("_", " "), int(settlement["population"])],
		Color.html(faction.get("color", "#808080")))
	if owner != player:
		# A rival city's garrison and works are its own business — the menu
		# holds the same fog discipline as the region panel.
		_line("Their walls keep their own count.", UiStyle.TEXT_DIM)
		return

	_section("Garrison")
	var garrison: Array = settlement["garrison"]
	if garrison.is_empty():
		_line("The walls stand unmanned.", Color(0.9, 0.8, 0.5))
	_roster(garrison)

	var chain_ids: Array = settlement["buildings"].keys()
	chain_ids.sort()
	if chain_ids.is_empty():
		return
	_section("Buildings")
	for chain_id in chain_ids:
		var chain: Dictionary = game.data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		var chain_levels: Array = chain.get("levels", [])
		var tier := mini(int(settlement["buildings"][chain_id]), chain_levels.size())
		var row_name := String(chain.get("name", chain_id))
		if tier >= 1:
			row_name = String(chain_levels[tier - 1]["name"])
		var target_chain := String(chain_id)
		_row(row_name, func(): building_info_requested.emit(target_chain))


func _armies_section(region_id: String, player: String) -> void:
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = game.state["armies"][army_id]
		if String(army["region"]) != region_id:
			continue
		var faction: Dictionary = game.data.factions.get(army["owner"], {})
		var general_name := "a captain"
		if army["general"] != null and game.state["characters"].has(army["general"]):
			general_name = String(game.state["characters"][army["general"]]["name"])
		_section("%s — %s" % [String(faction.get("name", army["owner"])), general_name])
		if String(army["owner"]) == player:
			_roster(army["units"])
		else:
			# The map roundel already shows a foreign stack's size;
			# its composition stays theirs.
			_line("%d units under arms." % (army["units"] as Array).size(),
				Color.html(faction.get("color", "#808080")))


func _roster(units: Array) -> void:
	for i in range(units.size()):
		if i == MAX_ROSTER_ROWS and units.size() > MAX_ROSTER_ROWS + 1:
			_line("… and %d more under the standard." % (units.size() - MAX_ROSTER_ROWS),
				UiStyle.TEXT_DIM)
			return
		_unit_row(units[i])


func _unit_row(unit: Dictionary) -> void:
	## One troop line: name, strength, and its skills named — R2's "skills
	## at a glance". A click opens the full card.
	var template_id := String(unit["template"])
	var profile := game.unit_profile(template_id)
	var text := "%s  %d%%" % [String(profile.get("name", template_id)),
		int(unit["strength_pct"])]
	var skills: Array = []
	for skill in profile.get("attributes", []):
		skills.append(String(skill["name"]))
	if not skills.is_empty():
		text += "  ·  %s" % ", ".join(skills)
	_row(text, func(): unit_info_requested.emit(template_id))


## --- small builders ---------------------------------------------------------

func _clear() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


## Menu labels never autowrap: with wrap on, a label's minimum height is
## computed against the panel's not-yet-laid-out width, and the menu's
## reset_size freezes that inflated guess as its real height. Every line
## here is authored short; a long one widens the panel instead.

func _title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	_content.add_child(label)


func _section(text: String) -> void:
	_content.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	_content.add_child(label)


func _line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	_content.add_child(label)


func _row(text: String, handler: Callable) -> void:
	var row := Button.new()
	row.text = text
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_theme_font_size_override("font_size", 11)
	row.pressed.connect(handler)
	_content.add_child(row)
