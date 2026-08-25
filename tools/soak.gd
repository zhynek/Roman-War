extends SceneTree
## Manual balance soak (not part of the test suite):
##   godot --headless --path . --script res://tools/soak.gd
## Runs long AI-driven campaigns at fixed seeds and prints what kind of world
## comes out: conquests, wars and peaces, surviving powers, rebel regions,
## treasury health and turn timing. Reading this output is how balance numbers
## get retuned — the campaign harness asserts invariants, this shows character.

const SEEDS := [42, 1234]
const TURNS := 100


func _init() -> void:
	for seed_value in SEEDS:
		_soak(seed_value)
	quit(0)


func _soak(seed_value: int) -> void:
	var game := Game.new_campaign("julii", seed_value)
	var wars := 0
	var peaces := 0
	var trades := 0
	var conquests := {}
	var player_sieges := 0
	var total_ms := 0

	for i in range(TURNS):
		var started := Time.get_ticks_msec()
		var report := game.end_turn()
		total_ms += Time.get_ticks_msec() - started
		for event in report["ai"]:
			match String(event.get("kind", "")):
				"war_declared":
					wars += 1
				"peace_made":
					peaces += 1
				"trade_agreed":
					trades += 1
				"ai_conquest":
					var faction: String = event["faction"]
					conquests[faction] = int(conquests.get(faction, 0)) + 1
				"ai_siege":
					if event.get("owner", "") == game.state["player_faction"]:
						player_sieges += 1

	var alive: Array = []
	var rebels_left := 0
	var broke := 0
	for faction_id in game.state["factions"]:
		if game.state["factions"][faction_id]["alive"]:
			alive.append(faction_id)
			if int(game.state["factions"][faction_id]["treasury"]) < 0:
				broke += 1
	for settlement in game.state["settlements"].values():
		if settlement["owner"] == "rebels":
			rebels_left += 1
	alive.sort()

	var by_conquests: Array = conquests.keys()
	by_conquests.sort_custom(func(a, b): return int(conquests[a]) > int(conquests[b]))
	var top := ""
	for i in range(mini(5, by_conquests.size())):
		top += "%s:%d " % [by_conquests[i], int(conquests[i]) if false else int(conquests[by_conquests[i]])]

	print("=== seed %d, %d turns ===" % [seed_value, TURNS])
	print("  wars declared: %d, peaces: %d, trade pacts: %d" % [wars, peaces, trades])
	print("  conquests: %d total, top: %s" % [_sum(conquests), top])
	print("  sieges laid on the idle player: %d" % player_sieges)
	print("  factions alive: %d/%d (%d in debt), rebel regions left: %d/33" \
		% [alive.size(), game.state["factions"].size(), broke, rebels_left])
	print("  avg end_turn: %d ms" % int(float(total_ms) / TURNS))


func _sum(counts: Dictionary) -> int:
	var total := 0
	for key in counts:
		total += int(counts[key])
	return total
