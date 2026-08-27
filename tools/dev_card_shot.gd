extends SceneTree
## Throwaway QA: boot the campaign, open an info card, capture, quit.
## SHOT=unit|building SCREENSHOT_DIR=... xvfb-run godot --path . --script res://tools/dev_card_shot.gd

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
		if OS.get_environment("SHOT") == "building":
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
		root.get_viewport().get_texture().get_image().save_png(
			out + "/card_" + ("building" if OS.get_environment("SHOT") == "building" else "unit") + ".png")
		print("saved card shot")
		quit(0)
		return true
	return false
