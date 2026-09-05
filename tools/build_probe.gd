extends SceneTree
## Package probe for an exported build. The Linux export shares its .pck with
## the macOS one, so this proves a macOS build plays without owning a Mac:
##   ./RomanWar.x86_64 --headless --script res://tools/build_probe.gd
## (also runs from the editor binary: godot --headless --path . --script res://tools/build_probe.gd)
## Checks that every data table is packed, GameData loads, a campaign starts,
## five turns end, a save round-trips, and the loaded game marches in lockstep
## with the live one for five more turns. Exits nonzero on any failure.
## States are compared the way the suite compares them: normalized through a
## JSON round-trip, because JSON numbers come back as floats and the writer
## sorts keys — neither is a difference in the world.

const EXPECTED_TABLES := 34
const TURNS := 5


func _init() -> void:
	var failures := 0
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	print("probe: build version %s" % version)

	# 1. Every data table is in the package.
	var tables := 0
	var dir := DirAccess.open("res://data")
	if dir == null:
		print("probe FAIL: res://data is not in the package")
		failures += 1
	else:
		for f in dir.get_files():
			if f.ends_with(".json"):
				tables += 1
		print("probe: %d data tables packed (expected %d)" % [tables, EXPECTED_TABLES])
		if tables != EXPECTED_TABLES:
			failures += 1

	# 2. The content loads and a campaign starts.
	var data := GameData.load_from()
	if data == null or not data.ok():
		print("probe FAIL: GameData did not load")
		failures += 1
	var game := Game.new_campaign("julii", 7)
	if game == null:
		print("probe FAIL: new_campaign returned null")
		quit(1)
		return
	var regions_before := _owned(game, "julii")
	print("probe: campaign started, Julii hold %d regions, %d factions, %d armies" % [
		regions_before, game.state["factions"].size(), game.state["armies"].size()])

	# 3. Turns end, and the AI moves the world.
	var total_ms := 0
	for i in range(TURNS):
		var started := Time.get_ticks_msec()
		var report := game.end_turn()
		total_ms += Time.get_ticks_msec() - started
		if report.is_empty():
			print("probe FAIL: end_turn %d returned an empty report" % (i + 1))
			failures += 1
	print("probe: %d turns ended, now turn %s, %d ms/turn" % [
		TURNS, str(game.state.get("turn", "?")), total_ms / TURNS])

	# 4. A save round-trips, and the loaded world marches in step with the live one.
	var path := "user://build_probe_save.json"
	var saved := game.save_to(path)
	var copy := Game.new_campaign("julii", 7)
	var loaded := saved and copy.load_from(path)
	if not loaded:
		print("probe FAIL: save/load failed (saved=%s)" % str(saved))
		failures += 1
	else:
		var same := _canon(copy.state) == _canon(game.state)
		print("probe: save round-trip %s" % ("identical" if same else "DIFFERS"))
		if not same:
			failures += 1
		for i in range(TURNS):
			game.end_turn()
			copy.end_turn()
		var lockstep := _canon(copy.state) == _canon(game.state)
		print("probe: loaded game after %d more turns %s the live game" % [
			TURNS, "matches" if lockstep else "DIVERGES from"])
		if not lockstep:
			failures += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	if failures == 0:
		print("probe OK")
	else:
		print("probe FAILED with %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)


func _canon(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))


func _owned(game: Game, faction: String) -> int:
	var n := 0
	for rid in game.state["settlements"]:
		if String(game.state["settlements"][rid].get("owner", "")) == faction:
			n += 1
	return n
