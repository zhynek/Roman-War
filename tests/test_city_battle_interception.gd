extends RefCounted
## A real campaign siege must offer command before the AI or supply clock
## consumes it. Cities without an authored battlefield keep their old flow.

const ENEMY := "city_battle_interception_enemy"


class CountingResolver:
	extends BattleResolver
	var calls := 0

	func resolve(_data: GameData, _rng: CampaignRng, _attackers: Array, _defenders: Array, _context: Dictionary) -> Dictionary:
		calls += 1
		return {"winner": "defender"}


func _game(region_id: String = "latium", player: String = "senate") -> Game:
	var game := Game.new_campaign(player, 42, "medium", "long", false)
	game.state["settlements"][region_id]["owner"] = "senate"
	var units: Array = []
	for index in range(20):
		units.append({"template": "gallic_long_swords", "strength_pct": 100,
			"experience": 9, "weapon": 3, "armor": 3})
	game.state["armies"][ENEMY] = {
		"owner": "gaul", "region": region_id, "units": units,
		"general": null, "movement_left": 0.0, "forced_march": false,
	}
	DiplomacyRules.declare_war(game.data, game.state, "gaul", "senate")
	game.state["settlements"][region_id]["siege"] = {
		"besieger": ENEMY, "turns": 1, "equipment_ready": true,
	}
	return game


func test_ai_keeps_ready_roma_siege_for_player_command(t) -> void:
	var game := _game()
	var resolver := CountingResolver.new()
	var rng := CampaignRng.from_state_string(game.state["rng_state"])
	var before := JSON.stringify(game.state)
	var handled := {}
	AiMilitary._press_sieges(game.data, game.state, "gaul", rng, resolver, handled, [], [])
	t.check_eq(resolver.calls, 0, "AI cannot silently fight the authored player's defensive battle")
	t.check(handled.has(ENEMY), "besieger stays committed instead of walking away after deferral")
	t.check_eq(JSON.stringify(game.state), before, "deferral spends no troops, ownership or battle records")
	t.check_eq(rng.state_string(), game.state["rng_state"], "offering command draws no battle randomness")


func test_pending_defense_cannot_be_lifted_by_ai_retreat_decision(t) -> void:
	var game := _game()
	game.state["armies"][ENEMY]["units"] = [{"template": "tribal_warband",
		"strength_pct": 1, "experience": 0, "weapon": 0, "armor": 0}]
	var resolver := CountingResolver.new()
	var handled := {}
	AiMilitary._press_sieges(game.data, game.state, "gaul",
		CampaignRng.from_state_string(game.state["rng_state"]), resolver, handled, [], [])
	t.check(game.state["settlements"]["latium"]["siege"] != null,
		"once a defensive decision is ready the AI cannot revoke it behind the player")
	t.check(handled.has(ENEMY), "the weak besieger remains assigned to its pending decision")
	t.check_eq(resolver.calls, 0, "pending decisions still require an explicit battle command")


func test_starvation_cannot_consume_pending_roma_defense(t) -> void:
	var game := _game()
	var siege: Dictionary = game.state["settlements"]["latium"]["siege"]
	var starve_turns: Array = game.data.balance["siege"]["starve_turns_per_settlement_level"]
	siege["turns"] = int(starve_turns.max()) + 5
	var resolver := CountingResolver.new()
	var rng := CampaignRng.from_state_string(game.state["rng_state"])
	var attackers := JSON.stringify(game.state["armies"][ENEMY]["units"])
	var defenders := JSON.stringify(game.state["settlements"]["latium"]["garrison"])
	var events := SiegeRules.advance_sieges(game.data, game.state, rng, resolver)
	t.check_eq(resolver.calls, 0, "the supply clock also respects the defensive command boundary")
	t.check(events.is_empty(), "no false starve-out outcome is sent to the turn journal")
	t.check_eq(JSON.stringify(game.state["armies"][ENEMY]["units"]), attackers, "besiegers remain available for the real battle")
	t.check_eq(JSON.stringify(game.state["settlements"]["latium"]["garrison"]), defenders, "garrison remains available for the real battle")
	t.check_eq(rng.state_string(), game.state["rng_state"], "deferring a forced sally consumes no randomness")


func test_equipment_becoming_ready_offers_defense_in_same_season(t) -> void:
	var game := _game()
	var siege: Dictionary = game.state["settlements"]["latium"]["siege"]
	siege["turns"] = SiegeRules.equipment_turns_for(game.data, game.state, "gaul") - 1
	siege["equipment_ready"] = false
	t.check(not CityBattleRules.pending_defense(game.data, game.state, "latium"), "unfinished equipment does not pause campaign seasons")
	var resolver := CountingResolver.new()
	SiegeRules.advance_sieges(game.data, game.state,
		CampaignRng.from_state_string(game.state["rng_state"]), resolver)
	t.check(CityBattleRules.pending_defense(game.data, game.state, "latium"), "newly finished equipment exposes a defense after this season")
	t.check_eq(resolver.calls, 0, "readiness itself is not an automatic battle")


func test_nonplayer_and_unmodeled_cities_keep_automatic_assaults(t) -> void:
	for setup in [["latium", "julii"], ["campania", "senate"]]:
		var game := _game(setup[0], setup[1])
		var resolver := CountingResolver.new()
		AiMilitary._press_sieges(game.data, game.state, "gaul",
			CampaignRng.from_state_string(game.state["rng_state"]), resolver, {}, [], [])
		t.check_eq(resolver.calls, 1, "ordinary siege assault remains automatic for %s as %s" % setup)
		game = _game(setup[0], setup[1])
		var starve_turns: Array = game.data.balance["siege"]["starve_turns_per_settlement_level"]
		game.state["settlements"][setup[0]]["siege"]["turns"] = int(starve_turns.max()) + 5
		resolver = CountingResolver.new()
		var events := SiegeRules.advance_sieges(game.data, game.state,
			CampaignRng.from_state_string(game.state["rng_state"]), resolver)
		t.check_eq(resolver.calls, 1, "ordinary starvation remains automatic for %s as %s" % setup)
		t.check_eq(events.size(), 1, "normal supply outcome remains available to the turn journal")


func test_empty_garrison_does_not_create_an_unfightable_pending_decision(t) -> void:
	var game := _game()
	game.state["settlements"]["latium"]["garrison"] = []
	t.check(not CityBattleRules.pending_defense(game.data, game.state, "latium"),
		"a city with no troops cannot freeze the season behind an unavailable defense")
	var resolver := CountingResolver.new()
	AiMilitary._press_sieges(game.data, game.state, "gaul",
		CampaignRng.from_state_string(game.state["rng_state"]), resolver, {}, [], [])
	t.check_eq(resolver.calls, 1, "the existing resolver handles the undefended settlement")
