extends SceneTree
## Throwaway QA: boot the campaign, open an info card, the map dossier, or a
## staged battle playback, capture, quit.
## SHOT=unit|building|menu|battle SCREENSHOT_DIR=... xvfb-run godot --path . --script res://tools/dev_card_shot.gd

var _frame := 0
var _screen: CampaignScreen
var _holder: Control


func _init() -> void:
	var game := Game.new_campaign("julii", 42)
	_screen = CampaignScreen.create(game)
	_holder = Control.new()
	root.add_child(_holder)
	_holder.add_child(_screen)


func _process(_delta: float) -> bool:
	_holder.size = root.size
	_frame += 1
	if _frame == 10:
		var region_ids: Array = _screen.game.state["settlements"].keys()
		region_ids.sort()
		for region_id in region_ids:
			if _screen.game.state["settlements"][region_id]["owner"] == "julii":
				_screen._on_region_clicked(region_id)
				break
		if OS.get_environment("SHOT") == "battle":
			var game := _screen.game
			var rng := CampaignRng.seeded(7)
			var attacker: Array = []
			var defender: Array = []
			var unit_ids: Array = game.data.units.keys()
			unit_ids.sort()
			for unit_id in unit_ids:
				var culture: String = game.data.units[unit_id].get("culture", "")
				if game.data.units[unit_id].get("class", "") == "ship":
					continue  # ships fight at sea; this is a field battle
				if culture == "roman" and attacker.size() < 4:
					attacker.append({"template": unit_id, "experience": 2, "strength_pct": 100})
				elif culture == "greek" and defender.size() < 3:
					defender.append({"template": unit_id, "experience": 0, "strength_pct": 100})
			var result := AutoResolver.new().resolve(game.data, rng, attacker, defender,
				{"terrain": "plains", "wall_level": 0})
			_screen._show_battle(result, "House of the Julii", "League of Taras")
			_screen.battle_screen._t = BattleScreen.ROUND_SECONDS * 2.3
		elif OS.get_environment("SHOT") == "menu":
			var capital: String = _screen.game.state["factions"]["julii"]["capital"]
			var settlement: Dictionary = _screen.game.state["settlements"][capital]
			if (settlement["garrison"] as Array).is_empty():
				settlement["garrison"].append(
					{"template": "rural_levies", "strength_pct": 100, "experience": 0})
			_screen.open_map_menu(capital)
		elif OS.get_environment("SHOT") == "building":
			var chain_ids: Array = _screen.game.data.chains.keys()
			chain_ids.sort()
			for chain_id in chain_ids:
				var chain: Dictionary = _screen.game.data.chains[chain_id]
				if chain["kind"] == "stables" and chain.get("cultures", []).has("roman"):
					_screen.open_building_card(chain_id)
					break
		else:
			_screen.open_unit_card("hastati" if _screen.game.data.units.has("hastati") else "rural_levies")
	elif _frame == 20:
		var out := OS.get_environment("SCREENSHOT_DIR")
		if out == "":
			out = "/tmp"
		var shot := OS.get_environment("SHOT")
		if not shot in ["building", "menu", "battle"]:
			shot = "unit"
		root.get_viewport().get_texture().get_image().save_png(out + "/card_" + shot + ".png")
		print("saved card shot")
		quit(0)
		return true
	return false
