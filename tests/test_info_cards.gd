extends RefCounted
## The R2 info cards: unit and building cards carry the glossary-explained
## content, unlock rows cross-navigate to unit cards, the region panel's
## right-click gesture requests them, and the campaign screen hosts and
## dismisses them.


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


func test_unit_card_reads_like_a_card(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new()
	game.data = GameData.load_from("res://data")
	var card := InfoCard.new()
	tree.root.add_child(card)
	card.show_unit(game, "rural_levies")
	t.check(_has_text(card, "Rural Levies"), "the unit's name shows")
	t.check(_has_text(card, "Levies"), "its class chip shows")
	t.check(_has_text(card, "Trained at"), "the trained-at section shows")
	t.check(_has_text(card, "Farms"), "naming the building kind")
	t.check(_has_text(card, "Speed"), "the speed stat finally rendered")
	card.free()


func test_building_card_unlocks_navigate_to_units(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new()
	game.data = GameData.load_from("res://data")
	var chain_ids: Array = game.data.chains.keys()
	chain_ids.sort()
	var barracks_id := ""
	for chain_id in chain_ids:
		var chain: Dictionary = game.data.chains[chain_id]
		if chain["kind"] == "barracks" and chain.get("cultures", []).has("roman"):
			barracks_id = chain_id
			break
	var card := InfoCard.new()
	tree.root.add_child(card)
	card.show_building(game, barracks_id, "roman")
	t.check(_has_text(card, "Barracks"), "the kind chip shows")

	var unlock_button: Button = null
	var stack: Array = [card]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and (node as Button).text.begins_with("▸"):
			unlock_button = node
			break
		for child in node.get_children():
			stack.append(child)
	t.check(unlock_button != null, "the barracks lists unlockable troops")
	if unlock_button != null:
		var unlocked_name := unlock_button.text.split("(")[0].replace("▸", "").strip_edges()
		unlock_button.pressed.emit()
		t.check(_has_text(card, "Trained at"), "clicking an unlock flips to that unit's card")
		t.check(_has_text(card, unlocked_name), "showing the clicked unit")
	card.free()


func test_screen_hosts_and_dismisses_cards(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := CampaignScreen.create(Game.new_campaign("julii", 7))
	tree.root.add_child(screen)

	screen.region_panel.unit_info_requested.emit("rural_levies")
	t.check(screen.info_card != null, "a request opens the card")
	t.check(screen._card_catcher.visible, "over its click-away catcher")
	t.check(_has_text(screen.info_card, "Rural Levies"), "with the right content")

	screen.close_info_card()
	t.check(not screen._card_catcher.visible, "closing hides it")

	screen.region_panel.building_info_requested.emit(
		screen.game.data.chains.keys()[0])
	t.check(screen._card_catcher.visible, "building requests open it too")
	screen.close_info_card()
	screen.free()


func test_panel_rows_answer_right_click(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := CampaignScreen.create(Game.new_campaign("julii", 7))
	tree.root.add_child(screen)
	var game := screen.game

	# Select a julii settlement so the panel builds recruit rows.
	var region := ""
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if game.state["settlements"][region_id]["owner"] == "julii" \
				and not game.available_units(region_id).is_empty():
			region = region_id
			break
	t.check(region != "", "julii can recruit somewhere")
	screen._on_region_clicked(region)

	var recruit_button: Button = null
	var stack: Array = [screen.region_panel]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and (node as Button).text.begins_with("Recruit"):
			recruit_button = node
			break
		for child in node.get_children():
			stack.append(child)
	t.check(recruit_button != null, "a recruit row exists")
	if recruit_button != null:
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		rmb.pressed = true
		recruit_button.gui_input.emit(rmb)
		t.check(screen._card_catcher != null and screen._card_catcher.visible,
			"right-clicking the row opens the unit card")
		t.check(_has_text(screen.info_card, "Trained at"), "and it is a unit card")
	screen.free()
