extends RefCounted
## Phase 5 diplomacy: attitude factors, the balance of an offer, hard
## refusals, peace, alliances, submission, tribute, land, and memory.


func _neutral(state: Dictionary) -> void:
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")


func _labels(factors: Array) -> Dictionary:
	var by_label := {}
	for factor in factors:
		by_label[factor["label"]] = float(factor["value"])
	return by_label


func test_attitude_factors(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var factors := _labels(DiplomacyRules.attitude_breakdown(data, state, "blue", "red"))
	t.check_near(factors.get("stance", 0.0), -20.0, 0.001, "war weighs on every judgement")
	t.check_near(factors.get("shared_borders", 0.0), -3.0, 0.001, "neighbours are rivals")
	t.check_near(DiplomacyRules.attitude(data, state, "blue", "red"), -23.0, 0.001, "the sum")
	_neutral(state)
	t.check_near(DiplomacyRules.attitude(data, state, "blue", "red"), -3.0, 0.001, "peace lifts the war penalty")
	state["factions"]["blue"]["opinion"]["red"] = 20.0
	t.check_near(DiplomacyRules.attitude(data, state, "blue", "red"), 7.0, 0.001, "good dealings count at half weight")
	state["factions"]["red"]["treachery"] = 2
	t.check_near(DiplomacyRules.attitude(data, state, "blue", "red"), -3.0, 0.001, "two broken treaties cost 10")

	t.check_eq(DiplomacyRules.attitude_label(data, -50.0), "hostile", "label: hostile")
	t.check_eq(DiplomacyRules.attitude_label(data, -10.0), "wary", "label: wary")
	t.check_eq(DiplomacyRules.attitude_label(data, 0.0), "indifferent", "label: indifferent")
	t.check_eq(DiplomacyRules.attitude_label(data, 20.0), "friendly", "label: friendly")
	t.check_eq(DiplomacyRules.attitude_label(data, 50.0), "warm", "label: warm")


func test_trade_rights_and_gifts(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_neutral(state)
	var offer := {"from": "red", "to": "blue", "stance": "trade"}
	var verdict := DiplomacyRules.evaluate(data, state, offer)
	t.check(verdict["accept"], "a neighbour takes trade rights")
	t.check_near(verdict["score"], 5.0, 0.001, "-3 for the border, +8 for the trade")

	state["factions"]["blue"]["opinion"]["red"] = -30.0
	verdict = DiplomacyRules.evaluate(data, state, offer)
	t.check(not verdict["accept"], "a grudge closes the market")
	offer["gift"] = 2500
	verdict = DiplomacyRules.evaluate(data, state, offer)
	t.check(verdict["accept"], "gold reopens it")
	t.check_near(_labels(verdict["factors"]).get("gift", 0.0), 10.0, 0.001, "2500 denarii weigh 10 points")

	var result := DiplomacyRules.propose(data, state, offer)
	t.check(result["accepted"], "the offer is made and taken")
	t.check_eq(DiplomacyRules.stance_between(state, "blue", "red"), "trade", "trade rights signed both ways")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 2500, "the gift leaves our purse")
	t.check_eq(int(state["factions"]["blue"]["treasury"]), 7500, "and reaches theirs")
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), 0.0, 0.001, "-30 + 5 for the treaty + 25 for the gold")


func test_hard_refusals(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_neutral(state)
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "demand": 6000})["reason"] != "",
		"they cannot pay more than they have")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "regions_demanded": ["alpha"]})["reason"] != "",
		"nobody yields a capital")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "regions_offered": ["beta"]})["reason"] != "",
		"nor gives one away")
	state["factions"]["red"]["capital"] = "gamma"  # a capital lost to conquest still points at its old region
	state["settlements"].erase("epsilon")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "regions_offered": ["beta"]})["reason"] != "",
		"a house never cedes its last city, whatever its capital record says")
	state["settlements"]["epsilon"] = Fixtures._settlement("red", 6000, {"test_government": 2})
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "rebels", "stance": "trade"})["reason"] != "",
		"the independents keep no court")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "stance": "war"})["reason"] != "",
		"war is declared, not proposed")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "gift": 99999})["reason"] != "",
		"we cannot offer what we do not have")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "tribute_per_turn": 100})["reason"] != "",
		"a tribute needs a term")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "tribute_per_turn": 3000, "tribute_turns": 2})["reason"] != "",
		"no promising more than the treasury holds")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "stance": "protectorate"})["reason"] != "",
		"no court submits to an equal")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "envoy": "no_such_agent", "stance": "trade"})["reason"] != "",
		"a made-up envoy speaks for nobody")
	var far := Fixtures.add_agent(state, "red", "envoy", "epsilon")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "envoy": far, "stance": "trade"})["reason"] != "",
		"nor does one out of contact")
	DiplomacyRules.set_stance(state, "red", "blue", "war")
	var verdict := DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "stance": "trade"})
	t.check(verdict["reason"].to_lower().contains("peace"), "no treaties while at war")
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "regions_offered": ["epsilon"]})["reason"] != "",
		"no land changes hands at war unless the offer ends it")
	state["factions"]["blue"]["alive"] = false
	t.check(DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "stance": "neutral"})["reason"] != "",
		"the dead do not treat")


func test_net_gold_and_duplicate_land(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_neutral(state)
	var wrapped := {"from": "red", "to": "blue", "stance": "trade", "gift": 2000, "demand": 2000}
	var factors := _labels(DiplomacyRules.evaluate(data, state, wrapped)["factors"])
	t.check(not factors.has("gift") and not factors.has("gold_demanded"), "a gift wrapped around a demand is neither")
	DiplomacyRules.propose(data, state, wrapped)
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), 5.0, 0.001, "only the treaty itself is remembered")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 5000, "and no gold moved")

	var once := DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "regions_offered": ["epsilon"], "demand": 5000})
	var twice := DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "regions_offered": ["epsilon", "epsilon"], "demand": 5000})
	t.check_near(float(twice["score"]), float(once["score"]), 0.001, "naming a region twice does not double it")


func test_peace_lifts_sieges(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(3)
	var host: Array = []
	for i in range(6):
		host.append("test_elites")
	var army_id := Fixtures.add_army(state, "red", "beta", host)
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege laid")
	t.check(DiplomacyRules.propose(data, state, {"from": "red", "to": "blue", "stance": "neutral"})["accepted"],
		"the weaker side takes peace")
	t.check(state["settlements"]["alpha"]["siege"] == null, "and the siege lifts with it")

	# A siege whose besieger is no longer at war lifts at the turn, and no assault goes in.
	state["settlements"]["alpha"]["siege"] = {"besieger": army_id, "turns": 2, "equipment_ready": true}
	t.check(SiegeRules.assault(data, state, rng, resolver, army_id, "alpha").is_empty(), "no assault without a war")
	state["settlements"]["alpha"]["siege"] = {"besieger": army_id, "turns": 2, "equipment_ready": true}
	SiegeRules.advance_sieges(data, state, rng, resolver)
	t.check(state["settlements"]["alpha"]["siege"] == null, "the turn lifts a siege at peace")


func test_peace_follows_the_fortunes_of_war(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var peace := {"from": "red", "to": "blue", "stance": "neutral"}
	var legions := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	var verdict := DiplomacyRules.evaluate(data, state, peace)
	t.check(verdict["accept"], "the weaker side welcomes peace")
	t.check_near(_labels(verdict["factors"]).get("relative_power", 0.0), 30.0, 0.001, "our strength weighs the cap")

	state["armies"].erase(legions)
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears", "test_spears"])
	verdict = DiplomacyRules.evaluate(data, state, peace)
	t.check(not verdict["accept"], "the winning side fights on")
	state["factions"]["blue"]["war_turns"]["red"] = 20
	verdict = DiplomacyRules.evaluate(data, state, peace)
	t.check_near(_labels(verdict["factors"]).get("war_weariness", 0.0), 20.0, 0.001, "twenty seasons of war weary them")
	t.check(not verdict["accept"], "but not enough")
	peace["gift"] = 5000
	verdict = DiplomacyRules.evaluate(data, state, peace)
	t.check(verdict["accept"], "gold ends the war")
	DiplomacyRules.propose(data, state, peace)
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "neutral", "peace signed")
	t.check_eq(DiplomacyRules.war_turns(state, "blue", "red"), 0, "the war count resets")


func test_alliances_need_common_enemies_or_gold(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_neutral(state)
	var offer := {"from": "red", "to": "blue", "stance": "alliance"}
	var verdict := DiplomacyRules.evaluate(data, state, offer)
	t.check(not verdict["accept"], "no one allies for nothing")
	t.check_near(verdict["score"], -15.0, 0.001, "-3 border, -12 for the commitment, equal strength")

	data.factions["green"] = {"id": "green", "name": "Green", "culture": "roman"}
	state["factions"]["green"] = Fixtures._faction("")
	state["factions"]["green"]["diplomacy"] = {}
	DiplomacyRules.set_stance(state, "green", "red", "war")
	DiplomacyRules.set_stance(state, "green", "blue", "war")
	verdict = DiplomacyRules.evaluate(data, state, offer)
	var factors := _labels(verdict["factors"])
	t.check_near(factors.get("common_enemies", 0.0), 6.0, 0.001, "a shared enemy argues for the pact")
	t.check_near(verdict["score"], -4.0, 0.001, "and lifts the attitude too, but not enough")
	offer["gift"] = 1000
	var envoy := Fixtures.add_agent(state, "red", "envoy", "beta")
	offer["envoy"] = envoy
	verdict = DiplomacyRules.evaluate(data, state, offer)
	t.check_near(_labels(verdict["factors"]).get("envoy_skill", 0.0), 2.0, 0.001, "a skilled envoy sweetens any deal")
	t.check(verdict["accept"], "gold and a good envoy seal it")
	DiplomacyRules.propose(data, state, offer)
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "alliance", "allied")
	t.check_eq(int(state["agents"][envoy]["skill"]), 2, "the envoy learns from a treaty concluded")


func test_submission_only_when_crushed(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var demand := {"from": "red", "to": "blue", "stance": "protectorate"}
	t.check(DiplomacyRules.evaluate(data, state, demand)["reason"] != "", "no one submits to an equal")
	var host: Array = []
	for i in range(20):
		host.append("test_elites")
	Fixtures.add_army(state, "red", "beta", host)
	var verdict := DiplomacyRules.evaluate(data, state, demand)
	t.check_near(_labels(verdict["factors"]).get("our_weakness", 0.0), 90.0, 0.001, "overwhelming force weighs the cap")
	t.check(not verdict["accept"], "but pride holds a little longer")
	state["factions"]["blue"]["war_turns"]["red"] = 20
	verdict = DiplomacyRules.evaluate(data, state, demand)
	t.check(verdict["accept"], "crushed and weary, they submit")
	DiplomacyRules.propose(data, state, demand)
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "protectorate", "the protectorate stands")
	t.check_eq(state["factions"]["blue"]["overlord"], "red", "with us as overlord")

	var red_before := int(state["factions"]["red"]["treasury"])
	var blue_before := int(state["factions"]["blue"]["treasury"])
	var notices := DiplomacyRules.process_turn(data, state)
	var dues := 0
	for notice in notices:
		if notice["kind"] == "protectorate_tribute":
			dues = int(notice["amount"])
	t.check(dues > 0, "the vassal pays dues")
	t.check_eq(int(state["factions"]["red"]["treasury"]), red_before + dues, "which reach the overlord")
	t.check_eq(int(state["factions"]["blue"]["treasury"]), blue_before - dues, "from the vassal's purse")

	DiplomacyRules.declare_war(state, "blue", "red", data)
	t.check(state["factions"]["blue"]["overlord"] == null, "war ends the protectorate")


func test_tribute_streams(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_neutral(state)
	var offer := {"from": "red", "to": "blue", "tribute_per_turn": 500, "tribute_turns": 2}
	var result := DiplomacyRules.propose(data, state, offer)
	t.check(result["accepted"], "a stream of gold is welcome")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 4500, "the first installment goes with the signatures")
	t.check_eq(int(state["factions"]["blue"]["treasury"]), 5500, "and arrives")
	t.check_eq(state["tributes"].size(), 1, "the rest is recorded")
	var notices := DiplomacyRules.process_turn(data, state)
	t.check_eq(int(state["factions"]["red"]["treasury"]), 4000, "the second payment leaves at season's end")
	t.check_eq(notices[0]["kind"], "tribute_paid", "and is reported")
	t.check(notices[1]["kind"] == "tribute_ended" and not notices[1]["lapsed"], "then the stream runs its course")
	t.check(state["tributes"].is_empty(), "nothing is owed")

	# Walking away from a tribute still owed is a betrayal, and the rest lapses.
	DiplomacyRules.propose(data, state, {"from": "red", "to": "blue", "tribute_per_turn": 500, "tribute_turns": 3})
	t.check_eq(int(state["factions"]["red"]["treasury"]), 3500, "a new stream, first installment paid")
	DiplomacyRules.declare_war(state, "red", "blue", data)
	t.check_eq(int(state["factions"]["red"]["treachery"]), 1, "reneging on tribute marks us treacherous")
	notices = DiplomacyRules.process_turn(data, state)
	t.check(state["tributes"].is_empty(), "war ends the tribute")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 3500, "no more payments")
	t.check(notices[0]["kind"] == "tribute_ended" and notices[0]["lapsed"], "reported as lapsed")

	# An empty purse lapses a promise rather than borrowing to keep it.
	_neutral(state)
	state["tributes"].append({"from": "red", "to": "blue", "per_turn": 500, "turns_left": 2})
	state["factions"]["red"]["treasury"] = 100
	notices = DiplomacyRules.process_turn(data, state)
	t.check(state["tributes"].is_empty() and int(state["factions"]["red"]["treasury"]) == 100,
		"the unpayable installment lapses the stream")


func test_ceding_land_moves_the_garrison_out(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_neutral(state)
	state["settlements"]["epsilon"]["garrison"] = [{"template": "test_spears", "experience": 0, "strength_pct": 100}]
	Fixtures.add_character(state, "red", "cousin", {"location": "epsilon"})
	SettlementRules.refresh_governors(data, state)
	var offer := {"from": "red", "to": "blue", "regions_offered": ["epsilon"]}
	var verdict := DiplomacyRules.evaluate(data, state, offer)
	t.check_near(_labels(verdict["factors"]).get("regions_offered", 0.0), 25.0, 0.001,
		"6000 souls and a hall are worth 25")
	t.check(DiplomacyRules.propose(data, state, offer)["accepted"], "land is always welcome")
	t.check_eq(state["settlements"]["epsilon"]["owner"], "blue", "epsilon is theirs")
	t.check(state["settlements"]["epsilon"]["garrison"].is_empty(), "our garrison does not stay")
	var marched_out := false
	for army in state["armies"].values():
		if army["owner"] == "red" and army["region"] == "epsilon" and army["units"].size() == 1:
			marched_out = true
	t.check(marched_out, "it stands outside as a field army")
	t.check_eq(state["characters"]["cousin"]["location"], "beta", "the cousin goes home")
	t.check(state["settlements"]["epsilon"]["governor"] == null, "the seat is empty")


func test_war_declarations_are_remembered(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	DiplomacyRules.declare_war(state, "red", "blue", data)
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), -60.0, 0.001, "a declaration and a betrayal")
	t.check_eq(int(state["factions"]["red"]["treachery"]), 1, "the world takes note")
	t.check_eq(DiplomacyRules.war_turns(state, "red", "blue"), 0, "a fresh war")
	DiplomacyRules.process_turn(data, state)
	t.check_eq(DiplomacyRules.war_turns(state, "blue", "red"), 1, "which ages")
	var factors := _labels(DiplomacyRules.attitude_breakdown(data, state, "blue", "red"))
	t.check_near(factors.get("treachery", 0.0), -5.0, 0.001, "treachery weighs on their view of us")
	t.check_near(factors.get("past_dealings", 0.0), -29.5, 0.001, "as does the memory, already fading")
	DiplomacyRules.declare_war(state, "red", "blue", data)
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), -59.0, 0.001, "declaring twice changes nothing")


func test_opinions_drift_home(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["factions"]["blue"]["opinion"]["red"] = 2.5
	state["factions"]["red"]["opinion"]["blue"] = -1.5
	DiplomacyRules.process_turn(data, state)
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), 1.5, 0.001, "goodwill fades")
	t.check_near(DiplomacyRules.opinion(state, "red", "blue"), -0.5, 0.001, "so do grudges")
	DiplomacyRules.process_turn(data, state)
	DiplomacyRules.process_turn(data, state)
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), 0.0, 0.001, "to indifference")
	t.check_near(DiplomacyRules.opinion(state, "red", "blue"), 0.0, 0.001, "and never past it")


func test_dissolving_a_treaty_is_unilateral(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	state["factions"]["blue"]["opinion"]["red"] = -90.0
	var squeeze := DiplomacyRules.evaluate(data, state, {"from": "red", "to": "blue", "stance": "neutral", "demand": 100})
	t.check(not squeeze["accept"], "leaving with a demand is a bargain they may refuse")
	var envoy := Fixtures.add_agent(state, "red", "envoy", "beta")
	var result := DiplomacyRules.propose(data, state, {"from": "red", "to": "blue", "stance": "trade", "envoy": envoy})
	t.check(result["accepted"], "stepping down from alliance to trade needs no consent either")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "trade", "the alliance is reduced to trade")
	t.check_eq(int(state["agents"][envoy]["skill"]), 1, "and teaches the envoy nothing")
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), -100.0, 0.001, "and is resented, to the floor")
	result = DiplomacyRules.propose(data, state, {"from": "red", "to": "blue", "stance": "neutral"})
	t.check(result["accepted"], "leaving quietly needs no consent")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "neutral", "the treaty is over")

	# A vassal cannot release itself; only the overlord can.
	DiplomacyRules.set_stance(state, "red", "blue", "protectorate")
	state["factions"]["blue"]["overlord"] = "red"
	var escape := DiplomacyRules.evaluate(data, state, {"from": "blue", "to": "red", "stance": "trade"})
	t.check(escape["reason"].to_lower().contains("overlord"), "the vassal stays a vassal")
	t.check(DiplomacyRules.propose(data, state, {"from": "red", "to": "blue", "stance": "neutral"})["accepted"],
		"the overlord may let it go")
	t.check(state["factions"]["blue"]["overlord"] == null, "and the bond is gone")


func test_offers_go_through_an_envoy(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_neutral(state)
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	var result := game.propose({"to": "blue", "stance": "trade"})
	t.check(not result["accepted"], "no envoy, no talks")
	t.check(result["reason"].to_lower().contains("envoy"), "and the scroll says why")
	var envoy := Fixtures.add_agent(state, "red", "envoy", "beta")
	var preview := game.evaluate_proposal({"to": "blue", "stance": "trade"})
	t.check(_labels(preview["factors"]).has("envoy_skill"), "the envoy in contact is found on our behalf")
	result = game.propose({"to": "blue", "stance": "trade"})
	t.check(result["accepted"], "with him, the treaty is made")
	t.check_eq(int(state["agents"][envoy]["skill"]), 2, "and he is the better for it")
	t.check(not AgentRules.can_act(state["agents"][envoy]), "the treaty was his work for the season")
	result = game.propose({"to": "blue", "stance": "alliance", "gift": 3000})
	t.check(not result["accepted"] and result["reason"].to_lower().contains("envoy"), "no second treaty this season")
	result = game.propose({"to": "blue", "stance": "neutral"})
	t.check(result["accepted"], "but ending our own treaty needs no envoy")
	t.check(not game.propose({"from": "blue", "to": "red", "regions_offered": ["alpha"]})["accepted"],
		"the player speaks only for the player's house")
	var attitude := game.attitude_of("blue")
	t.check(attitude.has("label") and attitude.has("factors"), "the facade explains their regard")
