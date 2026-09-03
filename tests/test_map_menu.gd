extends RefCounted
## The right-click dossier on the map: your city answers with its garrison,
## buildings and armies — rows opening the info cards — while fog and rival
## walls give up nothing the tooltip and panel would not.


func _texts(node: Node, found: Array) -> void:
	if node is Label:
		found.append((node as Label).text)
	if node is Button:
		found.append((node as Button).text)
	for child in node.get_children():
		_texts(child, found)


func _has_text(node: Node, needle: String) -> bool:
	var found: Array = []
	_texts(node, found)
	for text in found:
		if String(text).contains(needle):
			return true
	return false


func test_own_city_dossier_and_its_doors(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := CampaignScreen.create(Game.new_campaign("julii", 7))
	tree.root.add_child(screen)
	var game := screen.game
	var capital: String = game.state["factions"]["julii"]["capital"]
	var settlement: Dictionary = game.state["settlements"][capital]
	if (settlement["garrison"] as Array).is_empty():
		settlement["garrison"].append(
			{"template": "rural_levies", "strength_pct": 100, "experience": 0})

	screen.open_map_menu(capital)
	t.check(screen._card_catcher.visible, "the dossier opens over the click-away catcher")
	t.check(screen.map_menu.visible and not screen.info_card.visible,
		"as a menu, not a card")
	t.check(_has_text(screen.map_menu, "Garrison"), "it musters the garrison")
	t.check(_has_text(screen.map_menu, "Buildings"), "and lists the buildings")

	# A garrison row (name + strength) is a door into the unit card.
	var unit_row: Button = null
	var stack: Array = [screen.map_menu]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and (node as Button).text.contains("%"):
			unit_row = node
			break
		for child in node.get_children():
			stack.append(child)
	t.check(unit_row != null, "the garrison stands in clickable rows")
	if unit_row != null:
		unit_row.pressed.emit()
		t.check(screen.info_card.visible and not screen.map_menu.visible,
			"a row swaps the menu for its card")
		t.check(_has_text(screen.info_card, "Trained at"), "the unit's own card")

	screen.close_info_card()
	t.check(not screen._card_catcher.visible, "closing dismisses the whole surface")
	screen.free()


func test_fog_and_rivals_keep_their_secrets(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := CampaignScreen.create(Game.new_campaign("julii", 7))
	tree.root.add_child(screen)
	var game := screen.game
	var visible_set := game.visible_regions()
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()

	# Beyond the fog: the dossier grants the land's name and nothing more.
	var fogged := ""
	for region_id in region_ids:
		if not visible_set.has(region_id):
			fogged = region_id
			break
	t.check(fogged != "", "somewhere lies beyond the maps")
	if fogged != "":
		screen.open_map_menu(fogged)
		t.check(_has_text(screen.map_menu, "Beyond our maps"),
			"fog yields no reports")
		t.check(not _has_text(screen.map_menu, "Garrison"),
			"and certainly no garrison")
		var hidden_town := String(game.data.regions[fogged].get("settlement_name", "?"))
		if hidden_town != String(game.data.regions[fogged].get("name", "")):
			t.check(not _has_text(screen.map_menu, hidden_town),
				"nor even the settlement's name")

	# A rival city within sight: its rosters stay its own.
	var foreign := ""
	for region_id in region_ids:
		var owner := String(game.state["settlements"][region_id]["owner"])
		if not visible_set.has(region_id) or owner == "julii" or owner == "":
			continue
		var hosts_julii_army := false
		for army in game.state["armies"].values():
			if String(army["region"]) == region_id and String(army["owner"]) == "julii":
				hosts_julii_army = true
				break
		if not hosts_julii_army:
			foreign = region_id
			break
	t.check(foreign != "", "a rival city stands within sight")
	if foreign != "":
		game.state["settlements"][foreign]["garrison"] = [
			{"template": "rural_levies", "strength_pct": 100, "experience": 0}]
		screen.open_map_menu(foreign)
		t.check(not _has_text(screen.map_menu, "Rural Levies"),
			"a rival garrison never shows its rolls")
		t.check(not _has_text(screen.map_menu, "Buildings"),
			"nor its works")
		t.check(_has_text(screen.map_menu, "souls"),
			"though the town itself is plain to see")
	screen.free()
