extends SceneTree
## Long-campaign observatory for balance work: run a whole campaign headless
## and print the shape of the world as it evolves — who holds what, who is at
## war, treasuries, and every capture. Usage:
##
##   godot --headless --path . --script res://tools/sim_campaign.gd -- \
##       [seed] [turns] [player_faction] [difficulty]
##
## Defaults: seed 42, 60 turns, julii, medium. The "player" faction sits idle
## (no orders are given), which makes the printout a pure view of the AI.

var _ran := false


func _init() -> void:
	process_frame.connect(_run)


func _run() -> void:
	if _ran:
		return
	_ran = true

	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 42
	var turns := int(args[1]) if args.size() > 1 else 60
	var player := String(args[2]) if args.size() > 2 else "julii"
	var difficulty := String(args[3]) if args.size() > 3 else "medium"

	var game := Game.new_campaign(player, seed_value, difficulty)
	print("seed %d · %d turns · player %s (idle) · %s" % [seed_value, turns, player, difficulty])
	_print_world(game, 0)

	var captures := 0
	var wars := 0
	var peaces := 0
	for i in range(turns):
		var report := game.end_turn()
		for notice in report.get("world", []):
			match String(notice.get("kind", "")):
				"captured":
					captures += 1
					print("  t%03d  %s takes %s from %s" % [i + 1, notice["faction"],
						notice["region"], notice["from"]])
				"war_declared":
					wars += 1
					print("  t%03d  WAR: %s -> %s" % [i + 1, notice["faction"], notice["other"]])
				"peace":
					peaces += 1
					print("  t%03d  peace: %s ~ %s" % [i + 1, notice["faction"], notice["other"]])
		for faction_id in report.get("destroyed_factions", []):
			print("  t%03d  DESTROYED: %s" % [i + 1, faction_id])
		if (i + 1) % 10 == 0:
			_print_world(game, i + 1)
		if report.get("winner") != null:
			print("  WINNER at turn %d: %s" % [i + 1, str(report["winner"])])
			break

	print("\ntotals: %d captures, %d wars declared, %d peaces" % [captures, wars, peaces])
	quit(0)


func _print_world(game: Game, turn: int) -> void:
	var holdings := {}
	for settlement in game.state["settlements"].values():
		var owner: String = settlement["owner"]
		holdings[owner] = int(holdings.get(owner, 0)) + 1
	var rows: Array = []
	var faction_ids: Array = holdings.keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var treasury := int(game.state["factions"][faction_id]["treasury"])
		rows.append("%s:%d(%dk)" % [faction_id, holdings[faction_id], treasury / 1000])
	var armies: int = game.state["armies"].size()
	print("t%03d  armies:%d  %s" % [turn, armies, "  ".join(rows)])
