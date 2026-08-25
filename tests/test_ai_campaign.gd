extends RefCounted
## The Phase 6 acceptance harness, on the real authored data: a long headless
## campaign where the AI actually plays — the map must change hands, the world
## must stay invariant-clean, and determinism must survive both a straight
## replay and a mid-campaign save/resume with every AI system active.

const LONG_TURNS := 60
const REPLAY_TURNS := 24
const SAVE_AT := 20
const RESUME_TURNS := 10
const SEED := 42


func test_map_changes_hands(t) -> void:
	var game := Game.new_campaign("julii", SEED)
	var owners_at_start := {}
	var rebel_regions_at_start := 0
	for region_id in game.state["settlements"]:
		var owner: String = game.state["settlements"][region_id]["owner"]
		owners_at_start[region_id] = owner
		if owner == "rebels":
			rebel_regions_at_start += 1

	var total_ms := 0
	for i in range(LONG_TURNS):
		var started := Time.get_ticks_msec()
		game.end_turn()
		total_ms += Time.get_ticks_msec() - started

	var changed := 0
	var rebel_regions_now := 0
	for region_id in game.state["settlements"]:
		var owner: String = game.state["settlements"][region_id]["owner"]
		if owner != owners_at_start[region_id]:
			changed += 1
		if owner == "rebels":
			rebel_regions_now += 1
	t.check(changed >= 8, "the map changed hands (%d ownership changes)" % changed)
	t.check(rebel_regions_now < rebel_regions_at_start,
		"the rebel patchwork shrinks (%d -> %d)" % [rebel_regions_at_start, rebel_regions_now])

	# World invariants after 60 AI-driven turns.
	for region_id in game.state["settlements"]:
		var settlement: Dictionary = game.state["settlements"][region_id]
		t.check(game.state["factions"].has(settlement["owner"]), "owner exists for " + region_id)
		t.check(int(settlement["population"]) >= 400, "population floor holds in " + region_id)
	for army_id in game.state["armies"]:
		var army: Dictionary = game.state["armies"][army_id]
		t.check(game.state["factions"].has(army["owner"]), "army owner exists: " + army_id)
		t.check(not army["units"].is_empty(), "no ghost armies: " + army_id)
	for faction_id in game.state["factions"]:
		var treasury = game.state["factions"][faction_id]["treasury"]
		t.check(typeof(treasury) == TYPE_INT or typeof(treasury) == TYPE_FLOAT,
			"treasury numeric for " + faction_id)

	var average_ms := float(total_ms) / float(LONG_TURNS)
	t.check(average_ms < 250.0, "end_turn stays fast (%.0f ms average)" % average_ms)


func test_same_seed_replay_with_ai(t) -> void:
	var first := Game.new_campaign("julii", 1234)
	var second := Game.new_campaign("julii", 1234)
	for i in range(REPLAY_TURNS):
		first.end_turn()
		second.end_turn()
	t.check_eq(JSON.stringify(first.state), JSON.stringify(second.state),
		"a full AI world replays byte-identically from the same seed")


func test_save_resume_equivalence_with_ai(t) -> void:
	## The determinism test that catches unsorted AI loops: a JSON round trip
	## re-orders every dictionary, so a resumed campaign only marches in step
	## if every rng-steering iteration sorts its keys first.
	var game := Game.new_campaign("julii", SEED)
	for i in range(SAVE_AT):
		game.end_turn()

	var restored := SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not restored.is_empty(), "mid-campaign save parses back")
	NewGame.ensure_state_keys(restored)
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored

	for i in range(RESUME_TURNS):
		game.end_turn()
		resumed.end_turn()
	t.check_eq(_canonical(game.state), _canonical(resumed.state),
		"the resumed campaign marches in step with the unsaved one")


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))
