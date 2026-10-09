extends RefCounted
## Focused money/policy confirmation and additive-save boundary checks.

func _game() -> Game:
	var game := Game.new()
	game.data = Fixtures.data()
	game.data.patronage_content = JSON.parse_string(FileAccess.get_file_as_string("res://data/patronage.json"))
	for profile in game.data.patronage_content.patrons:game.data.patrons[profile.id] = profile
	game.data.divine_dilemma_content = JSON.parse_string(FileAccess.get_file_as_string("res://data/divine_dilemmas.json"))
	var temples: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/temples.json"))
	for chain in temples.chains:game.data.chains[chain.id] = chain
	game.state = Fixtures.state(game.data)
	NewGame.ensure_state_keys(game.state,game.data)
	game.state.settlements.beta.buildings.roman_jupiter = 1
	game.state.settlements.beta.buildings.roman_mars = 1
	game.pledge_patron("zeus","beta")
	game.state.turn = 1
	return game

func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func test_tax_quote_pure_stale_and_exactly_once(t) -> void:
	var game := _game()
	var before := _canonical(game.state)
	var quote := game.divine_dilemma_quote("zeus_city_petition","tax_relief","beta")
	t.check(quote.ok,"owned matching temple offers tax relief after a season")
	t.check_eq(quote.consequences.tax_before,"normal","quote states existing setting")
	t.check_eq(quote.consequences.tax_after,"low","quote states proposed setting")
	t.check_eq(_canonical(game.state),before,"reading a policy quote is pure")
	game.state.factions.red.treasury += 1
	var changed := _canonical(game.state)
	var result := game.resolve_divine_dilemma("zeus_city_petition","tax_relief","beta",quote.signature)
	t.check_eq(result.reason,"stale_quote","changed treasury requires a new quote")
	t.check_eq(_canonical(game.state),changed,"stale quote makes no partial changes")
	quote = game.divine_dilemma_quote("zeus_city_petition","tax_relief","beta")
	var treasury := int(game.state.factions.red.treasury)
	var rng: String = game.state.rng_state
	t.check(game.resolve_divine_dilemma("zeus_city_petition","tax_relief","beta",quote.signature).ok,"fresh confirmation commits")
	t.check_eq(game.state.settlements.beta.tax_level,"low","existing tax policy changed")
	t.check_eq(game.state.factions.red.treasury,treasury,"no immediate invented monetary reward or cost")
	t.check_eq(game.state.rng_state,rng,"no RNG draw")
	t.check_eq(game.resolve_divine_dilemma("zeus_city_petition","tax_relief","beta",quote.signature).reason,"already_resolved","replaying confirmation cannot commit twice")

func test_edict_quote_matches_existing_cost_and_gate(t) -> void:
	var game := _game()
	var quote := game.divine_dilemma_quote("zeus_city_petition","public_works","beta")
	t.check(quote.ok,"eligible city can issue Public Works")
	t.check_near(float(quote.consequences.upkeep_per_turn),52.0,0.0001,"existing 26-per1000 upkeep quoted at population2000")
	t.check_eq(quote.consequences.settle_turns,5,"existing five-season settling delay disclosed")
	game.state.settlements.beta.population += 10
	var before := _canonical(game.state)
	t.check_eq(game.resolve_divine_dilemma("zeus_city_petition","public_works","beta",quote.signature).reason,"stale_quote","population-scaled cost change invalidates confirmation")
	t.check_eq(_canonical(game.state),before,"stale edict does not charge or install")
	quote = game.divine_dilemma_quote("zeus_city_petition","public_works","beta")
	var treasury := int(game.state.factions.red.treasury)
	t.check(game.resolve_divine_dilemma("zeus_city_petition","public_works","beta",quote.signature).ok,"fresh edict confirmation succeeds")
	t.check_eq(EdictRules.of(game.state.settlements.beta).id,"public_works","uses existing edict state")
	t.check_near(EdictRules.upkeep(game.data,game.state.settlements.beta),float(quote.consequences.upkeep_per_turn),0.0001,"normal economy will bill precisely quoted upkeep at unchanged population")
	t.check_eq(game.state.factions.red.treasury,treasury,"existing deferred billing remains unchanged")
	game.pledge_patron("ares","beta")
	game.state.turn = 3
	t.check_eq(game.divine_dilemma_quote("ares_levy_fields","legion_levy","beta").reason,"edict_unavailable","cannot silently replace existing edict")

func test_ownership_temples_wait_and_battle_guards(t) -> void:
	var game := _game()
	t.check_eq(game.divine_dilemma_quote("zeus_city_petition","decline","alpha").reason,"not_owned","foreign edict boundary explicitly rejects ownership")
	var quote := game.divine_dilemma_quote("zeus_city_petition","decline","beta")
	game.state.settlements.beta.buildings.erase("roman_jupiter")
	t.check_eq(game.resolve_divine_dilemma("zeus_city_petition","decline","beta",quote.signature).reason,"temple_required","lost temple invalidates previously quoted offer")
	game.state.settlements.beta.buildings.roman_jupiter = 1
	game.state.turn = 0
	t.check_eq(game.divine_dilemma_quote("zeus_city_petition","decline","beta").reason,"pledge_too_recent","new pledge must wait a resolved season")
	game.state.turn = 1
	game.state.winner = "red"
	t.check_eq(game.divine_dilemma_quote("zeus_city_petition","decline","beta").reason,"campaign_finished","no post-campaign policy choice")
	game.state.winner = null
	game.state.city_battles = {"beta":{"phase":"fighting"}}
	t.check_eq(game.divine_dilemma_quote("zeus_city_petition","decline","beta").reason,"battle_active","battle blocks quote before city traversal")
	game.state.city_battles = {}
	game.data.roma_city.region = "beta"
	game.state.settlements.beta.garrison = [{}]
	game.state.settlements.beta.siege = {"besieger":"enemy","equipment_ready":true}
	game.state.armies.enemy = {"owner":"blue","region":"beta","units":[{}]}
	t.check_eq(game.resolve_divine_dilemma("zeus_city_petition","decline","beta",quote.signature).reason,"defense_pending","pending defense blocks commit")

func test_saved_receipts_cooldowns_and_decline_have_no_rewards(t) -> void:
	var game := _game()
	var quote := game.divine_dilemma_quote("zeus_city_petition","decline","beta")
	var loaded := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(loaded,game.data)
	game.state = loaded
	t.check_eq(game.divine_dilemma_quote("zeus_city_petition","decline","beta").signature,quote.signature,"quote survives unchanged JSON save/load")
	var before: Dictionary = game.state.duplicate(true)
	t.check(game.resolve_divine_dilemma("zeus_city_petition","decline","beta",quote.signature).ok,"explicit decline commits once")
	before.divine_dilemmas = game.state.divine_dilemmas.duplicate(true)
	t.check_eq(_canonical(game.state),_canonical(before),"decline changes only saved receipt/cooldown")
	game.pledge_patron("ares","beta")
	game.state.turn = 2
	t.check_eq(game.divine_dilemma_quote("ares_levy_fields","decline","beta").reason,"cooldown_active","changing patron cannot bypass global cooldown")
	game.state = SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(game.state,game.data)
	game.state.turn = 3
	quote = game.divine_dilemma_quote("ares_levy_fields","legion_levy","beta")
	t.check(quote.ok,"existing barracks authorize levy after saved cooldown")
	var armies := _canonical(game.state.armies)
	t.check(game.resolve_divine_dilemma("ares_levy_fields","legion_levy","beta",quote.signature).ok,"second authored choice commits")
	t.check_eq(_canonical(game.state.armies),armies,"legion levy does not fabricate troops")
	t.check_eq(game.state.divine_dilemmas.resolved.size(),2,"both once-only receipts persist")

func test_legacy_neutral_and_malformed_receipts(t) -> void:
	var game := _game()
	game.state.erase("divine_dilemmas")
	var loaded := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(loaded,game.data)
	t.check_eq(_canonical(loaded.divine_dilemmas),_canonical(DivineDilemmaRules.fresh()),"legacy save has no invented choices or cooldown")
	for bad in [[],{},null,{"cooldown_until":-1,"resolved":{}},
		{"cooldown_until":1,"resolved":{}},
		{"cooldown_until":3,"resolved":{"zeus_city_petition":null}},
		{"cooldown_until":3,"resolved":{"zeus_city_petition":{"turn":2,"region":"beta","choice":"decline"}}},
		{"cooldown_until":3,"resolved":{"zeus_city_petition":{"turn":0.5,"region":"beta","choice":"decline"}}},
		{"cooldown_until":3,"resolved":{"zeus_city_petition":{"turn":1,"region":"missing","choice":"decline"}}}]:
		game.state.divine_dilemmas = bad
		t.check(SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"malformed financial-choice receipt rejected before migration")
