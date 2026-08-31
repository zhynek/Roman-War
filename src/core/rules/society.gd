class_name SocietyRules
## The societal layer: six accumulating stocks whose flows are summed lists of
## named factors, exactly like growth and public order. Everything else in the
## engine reads instantaneous values; this module is the only place with memory,
## and that memory is what gives a decision its weight.
##
## Per settlement (state.settlements[id].society):
##   legitimacy   "Standing"       consent — rule accepted without force
##   grievance    "Grievance"      accumulated coerced obligation, hysteretic
##   assimilation "Belonging"      cultural convergence with the owner
##   expectation  "What the City Expects"  what it has come to believe it is owed
##   unrest_state calm|restive|rebellious, with unrest_turns
##
## Per faction (state.factions[id].society):
##   elite_pressure "Ambition"       claimants vs. finite offices and commands
##   martial_ethos  "Martial Spirit" the society's orientation toward war
##   knowledge      "Craft"          accumulated practice; decays without institutions
##   spoils         "Plunder's Share" how much of the income comes from taking
##   civic_shock                     a decaying empire-wide reputation penalty
##
## The load-bearing asymmetry: coercion raises public order but does not lower
## the load. Whatever consent does not cover must be coerced, and the coerced
## share charges grievance. A garrison therefore hides the problem while it grows.
##
## Its civic counterpart is the euergetism ratchet. Provision — games, baths,
## clean water — raises order at once, and a city slowly comes to expect it.
## Expectation rises in about twelve years and is forgotten in forty-five, so
## withdrawing a bath house leaves the city worse off than never having built
## one. Public generosity is a standing commitment, not a purchase.
##
## This module consumes NO randomness. All uncertainty in the societal layer is
## structural — delay, hysteresis, coupled feedback and partial observability —
## so a query may be called any number of times without touching state.rng_state.

const UNREST_CALM := "calm"
const UNREST_RESTIVE := "restive"
const UNREST_REBELLIOUS := "rebellious"

## Stocks are continuous, and Godot's JSON writer does NOT round-trip an
## arbitrary double exactly. Left alone, a loaded save would differ from the live
## game in the last digits and the two would diverge — the exact failure the
## determinism contract forbids. Rounding every stored stock onto a four-decimal
## grid makes it a value that survives save/load unchanged. Note that snappedf()
## is not equivalent: it can land on a double adjacent to the grid point, which
## then prints and re-parses as a different number.
const STOCK_PRECISION := 10000.0


static func quantize(value: float) -> float:
	return round(value * STOCK_PRECISION) / STOCK_PRECISION


## --- Reading the stocks (pure; never mutates) -----------------------------

static func stocks_of(data: GameData, settlement: Dictionary) -> Dictionary:
	## Society block of a settlement, backfilled from balance when absent so that
	## fixtures, saves written before this system, and freshly captured
	## settlements all read alike.
	var rules: Dictionary = data.balance["society"]
	var society: Dictionary = settlement.get("society", {})
	return {
		"legitimacy": float(society.get("legitimacy", rules["legitimacy_start"])),
		"grievance": float(society.get("grievance", rules["grievance_start"])),
		"assimilation": float(society.get("assimilation", rules["assimilation_start_native"])),
		"expectation": float(society.get("expectation", 0.0)),
		"unrest_state": String(society.get("unrest_state", UNREST_CALM)),
		"unrest_turns": int(society.get("unrest_turns", 0)),
	}


static func faction_stocks(data: GameData, faction: Dictionary) -> Dictionary:
	var rules: Dictionary = data.balance["society"]
	var society: Dictionary = faction.get("society", {})
	return {
		"elite_pressure": float(society.get("elite_pressure", rules["elite_start"])),
		"martial_ethos": float(society.get("martial_ethos", rules["martial_start"])),
		"knowledge": float(society.get("knowledge", rules["knowledge_start"])),
		"spoils": float(society.get("spoils", 0.0)),
		"plunder_pending": float(society.get("plunder_pending", 0.0)),
		"civic_shock": float(society.get("civic_shock", 0.0)),
	}


static func stocks_for_region(data: GameData, state: Dictionary, region_id: String) -> Dictionary:
	return stocks_of(data, state["settlements"][region_id])


static func faction_stocks_for(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	return faction_stocks(data, state["factions"].get(faction_id, {}))


static func provision(data: GameData, settlement: Dictionary) -> float:
	## What the state visibly provides here: spectacle, and the far less glamorous
	## business of clean water and drains.
	var rules: Dictionary = data.balance["society"]
	return SettlementRules.effect_total(data, settlement, "happiness") \
		+ SettlementRules.effect_total(data, settlement, "health") * float(rules["provision_health_scale"])


static func new_settlement_society(data: GameData, native_culture: bool, current_provision: float = 0.0) -> Dictionary:
	## Expectation is seeded AT what the city already receives, so nothing is
	## retroactively owed: a province only resents what it is given and then loses.
	var rules: Dictionary = data.balance["society"]
	var start_key := "assimilation_start_native" if native_culture else "assimilation_start_foreign"
	return {
		"legitimacy": quantize(float(rules["legitimacy_start"])),
		"grievance": quantize(float(rules["grievance_start"])),
		"assimilation": quantize(float(rules[start_key])),
		"expectation": quantize(clampf(current_provision, 0.0, float(rules["expectation_max"]))),
		"unrest_state": UNREST_CALM,
		"unrest_turns": 0,
		"survey": {},
	}


static func new_faction_society(data: GameData) -> Dictionary:
	var rules: Dictionary = data.balance["society"]
	return {
		"elite_pressure": quantize(float(rules["elite_start"])),
		"martial_ethos": quantize(float(rules["martial_start"])),
		"knowledge": quantize(float(rules["knowledge_start"])),
		"spoils": 0.0,
		"plunder_pending": 0.0,
		"civic_shock": 0.0,
	}


static func government_tier(data: GameData, settlement: Dictionary) -> int:
	return Constants.level_index(SettlementRules.settlement_level(data, settlement)) + 1


## --- Load: what the state demands of a province ---------------------------

static func load_breakdown(data: GameData, state: Dictionary, region_id: String) -> Array:
	## A summed list of named factors, in the same shape as growth and order.
	## Load is what the province is asked to bear; consent is what it grants
	## willingly. The difference is what has to be coerced.
	var settlement: Dictionary = state["settlements"][region_id]
	var rules: Dictionary = data.balance["society"]
	var stocks := stocks_of(data, settlement)
	var faction := faction_stocks_for(data, state, String(settlement["owner"]))
	var factors: Array = []

	factors.append({"label": "base", "value": float(rules["load_base"])})

	var tax_load: float = rules["load_tax"][settlement["tax_level"]]
	if tax_load != 0.0:
		factors.append({"label": "taxes", "value": tax_load})

	var squalor := GrowthRules.squalor_pct(data, settlement) * float(rules["load_squalor_scale"])
	if squalor > 0.0:
		factors.append({"label": "squalor", "value": squalor})

	# The empire's militarisation is felt in every province: levies, requisitions,
	# and sons who do not come home.
	var conscription := float(faction["martial_ethos"]) / 100.0 * float(rules["load_martial_scale"])
	if conscription > 0.0:
		factors.append({"label": "conscription", "value": conscription})

	# Troops quartered on a population are a burden even when they are your own.
	var population := maxi(int(settlement["population"]), 1)
	var garrison := float(SettlementRules.garrison_soldiers(data, settlement)) / float(population)
	garrison = minf(garrison * float(rules["load_garrison_scale"]), float(rules["load_garrison_max"]))
	if garrison > 0.0:
		factors.append({"label": "garrison_quartering", "value": garrison})

	var burden := SettlementRules.effect_total(data, settlement, "burden") * float(rules["load_burden_scale"])
	if burden != 0.0:
		factors.append({"label": "buildings", "value": burden})

	# Being ruled by strangers is itself a load, and it fades only as they stop
	# being strangers.
	var foreign := (100.0 - float(stocks["assimilation"])) / 100.0 * float(rules["load_foreign_rule_scale"])
	if foreign > 0.0:
		factors.append({"label": "foreign_rule", "value": foreign})

	var corruption := EconomyRules.corruption_pct(data, state, region_id) * float(rules["load_corruption_scale"])
	if corruption > 0.0:
		factors.append({"label": "corruption", "value": corruption})

	var elite := float(faction["elite_pressure"]) / 100.0 * float(rules["load_elite_scale"])
	if elite > 0.0:
		factors.append({"label": "elite_exactions", "value": elite})

	# What was given and then withdrawn. A city that never had baths does not
	# resent their absence; one that had them and lost them does.
	var shortfall := maxf(0.0, float(stocks["expectation"]) - provision(data, settlement))
	if shortfall > 0.0:
		factors.append({"label": "broken_promises",
			"value": shortfall * float(rules["load_broken_promises_scale"])})

	if int(settlement["recently_conquered"]) > 0:
		factors.append({"label": "recently_conquered", "value": float(rules["load_recently_conquered"])})

	if int(settlement["plague_turns"]) > 0:
		factors.append({"label": "plague", "value": float(rules["load_plague"])})

	return factors


static func load_total(data: GameData, state: Dictionary, region_id: String) -> float:
	var total := 0.0
	for factor in load_breakdown(data, state, region_id):
		total += float(factor["value"])
	return maxf(total, 0.0)


## --- Coercion: order bought with force rather than consent -----------------

static func coercion_total(data: GameData, state: Dictionary, region_id: String) -> float:
	var settlement: Dictionary = state["settlements"][region_id]
	var faction := faction_stocks_for(data, state, String(settlement["owner"]))
	var martial_share := float(faction["martial_ethos"]) / 100.0
	return SettlementRules.effect_total(data, settlement, "coercion") * (1.0 + martial_share)


## --- Legitimacy: the target a province drifts toward -----------------------

static func legitimacy_target_breakdown(data: GameData, state: Dictionary, region_id: String) -> Array:
	var settlement: Dictionary = state["settlements"][region_id]
	var rules: Dictionary = data.balance["society"]
	var stocks := stocks_of(data, settlement)
	var faction := faction_stocks_for(data, state, String(settlement["owner"]))
	var factors: Array = []

	factors.append({"label": "base", "value": float(rules["legitimacy_base_target"])})

	# Public benefit visibly delivered. Entertainment carries a NEGATIVE civic:
	# spectacle placates, it does not legitimate.
	var civic := SettlementRules.effect_total(data, settlement, "civic") * float(rules["legitimacy_civic_scale"])
	if civic != 0.0:
		factors.append({"label": "civic_buildings", "value": civic})

	var justice := PublicOrderRules.law_total(data, state, region_id) * float(rules["legitimacy_law_scale"])
	if justice != 0.0:
		factors.append({"label": "justice", "value": justice})

	var belonging := float(stocks["assimilation"]) / 100.0 * float(rules["legitimacy_assimilation_scale"])
	if belonging != 0.0:
		factors.append({"label": "belonging", "value": belonging})

	var coercion := coercion_total(data, state, region_id) * float(rules["legitimacy_coercion_scale"])
	if coercion > 0.0:
		factors.append({"label": "rule_by_fear", "value": -coercion})

	var elite := float(faction["elite_pressure"]) / 100.0 * float(rules["legitimacy_elite_drag"])
	if elite > 0.0:
		factors.append({"label": "grasping_elite", "value": -elite})

	var martial := float(faction["martial_ethos"]) / 100.0 * float(rules["legitimacy_martial_drag"])
	if martial > 0.0:
		factors.append({"label": "militarised_rule", "value": -martial})

	var resentment := float(stocks["grievance"]) / 100.0 * float(rules["legitimacy_grievance_drag"])
	if resentment > 0.0:
		factors.append({"label": "resentment", "value": -resentment})

	# A polity living off what it takes rather than what it makes is felt
	# everywhere it rules, including in provinces that never saw the war.
	var plunder := float(faction["spoils"]) / 100.0 * float(rules["legitimacy_spoils_drag"])
	if plunder > 0.0:
		factors.append({"label": "plunder", "value": -plunder})

	if float(faction["civic_shock"]) != 0.0:
		factors.append({"label": "reputation", "value": float(faction["civic_shock"])})

	var advances := AdvanceRules.effect_total(data, state, String(settlement["owner"]), "civic_target_bonus")
	if advances != 0.0:
		factors.append({"label": "advances", "value": advances})

	return factors


static func legitimacy_target(data: GameData, state: Dictionary, region_id: String) -> float:
	var total := 0.0
	for factor in legitimacy_target_breakdown(data, state, region_id):
		total += float(factor["value"])
	return clampf(total, 0.0, float(data.balance["society"]["legitimacy_max"]))


## --- Assimilation: contact drives diffusion, grievance is friction ---------

static func assimilation_contact(data: GameData, state: Dictionary, region_id: String) -> float:
	var settlement: Dictionary = state["settlements"][region_id]
	var rules: Dictionary = data.balance["society"]
	var owner_culture := data.culture_of_faction(String(settlement["owner"]))
	# Only buildings of the ruling culture carry the culture in. A conquered
	# city's own temples do nothing to make it yours.
	var pull := 0.0
	var chain_ids: Array = settlement["buildings"].keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty() or not chain["cultures"].has(owner_culture):
			continue
		var built_tier := mini(int(settlement["buildings"][chain_id]), chain["levels"].size())
		if built_tier > 0:
			pull += float(chain["levels"][built_tier - 1].get("effects", {}).get("assimilation_pull", 0.0))
	pull += float(government_tier(data, settlement)) * float(rules["assimilation_government_pull_per_tier"])
	# Another culture's stonework crowds yours out. Demolishing it is how you
	# clear the way — which is why the old penalty's release valve still works,
	# it just now buys drift rather than an instant correction.
	var foreign := SettlementRules.foreign_building_share(data, state, region_id)
	return maxf(0.0, pull * (1.0 - foreign))


## --- The stocks, for the UI -----------------------------------------------

static func society_breakdown(data: GameData, state: Dictionary, region_id: String) -> Array:
	var stocks := stocks_for_region(data, state, region_id)
	return [
		{"label": "standing", "value": float(stocks["legitimacy"])},
		{"label": "grievance", "value": -float(stocks["grievance"])},
		{"label": "belonging", "value": float(stocks["assimilation"])},
	]


static func faction_breakdown(data: GameData, state: Dictionary, faction_id: String) -> Array:
	var stocks := faction_stocks_for(data, state, faction_id)
	var factors: Array = [
		{"label": "ambition", "value": -float(stocks["elite_pressure"])},
		{"label": "martial_spirit", "value": float(stocks["martial_ethos"])},
		{"label": "craft", "value": float(stocks["knowledge"])},
	]
	if float(stocks["spoils"]) > 0.0:
		factors.append({"label": "plunders_share", "value": -float(stocks["spoils"])})
	if float(stocks["civic_shock"]) != 0.0:
		factors.append({"label": "reputation", "value": float(stocks["civic_shock"])})
	return factors


## --- Turn application -----------------------------------------------------
##
## Stocks are integrated simultaneously: every delta is computed from the same
## snapshot of the previous turn, then all three are written. That keeps the
## breakdown the UI shows identical to the one the engine used, and makes each
## equation independently testable.

static func apply_faction_turn(data: GameData, state: Dictionary, faction_id: String) -> void:
	var faction: Dictionary = state["factions"][faction_id]
	var rules: Dictionary = data.balance["society"]
	var stocks := faction_stocks(data, faction)

	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	var owned := 0
	var offices := 0
	var population_total := 0
	var soldiers_total := 0
	var martial_buildings := 0.0
	var knowledge_buildings := 0.0
	var legitimacy_total := 0.0
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] != faction_id:
			continue
		owned += 1
		offices += government_tier(data, settlement)
		population_total += int(settlement["population"])
		soldiers_total += SettlementRules.garrison_soldiers(data, settlement)
		martial_buildings += SettlementRules.effect_total(data, settlement, "martial")
		knowledge_buildings += SettlementRules.effect_total(data, settlement, "knowledge")
		legitimacy_total += float(stocks_of(data, settlement)["legitimacy"])

	var commands := 0
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["owner"] != faction_id:
			continue
		commands += 1
		for unit in army["units"]:
			var template: Dictionary = data.units.get(unit["template"], {})
			soldiers_total += int(ceil(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0))

	# Elite pressure: wealth and conquest breed claimants; offices and commands
	# absorb them. Both extremes fail — a militarised state hands armies to
	# ambitious men, a demilitarised one leaves them nowhere to go but politics.
	var income := float(EconomyRules.faction_turn_breakdown(data, state, faction_id)["income"])
	var elite := float(stocks["elite_pressure"])
	var martial_share := float(stocks["martial_ethos"]) / 100.0
	# A state its own elite believes in channels ambition into service; one they
	# do not turns the same men into factions.
	var legitimacy_share := 0.0
	if owned > 0:
		legitimacy_share = legitimacy_total / float(owned) / 100.0
	var damping := maxf(0.0, 1.0 - legitimacy_share * float(rules["elite_legitimacy_damping"]))
	var claimants := maxf(income, 0.0) / 1000.0 * float(rules["elite_gain_per_1000_income"])
	# Craft is double-edged. Schools and libraries do not only preserve technique,
	# they produce educated sons who expect a career — the credentialed aspirants
	# a state must find somewhere to put.
	claimants += float(stocks["knowledge"]) * float(rules["elite_gain_per_knowledge"])
	elite += claimants * damping
	# Standing orders that create new men with expectations — an enfranchisement,
	# an amnesty — add claimants the legitimacy of the state does not damp away.
	elite += EdictRules.faction_effect_total(data, state, faction_id, "elite_pressure", region_ids)
	elite -= float(offices) * float(rules["elite_office_absorption_per_tier"])
	elite -= float(commands) * float(rules["elite_command_absorption_per_army"]) \
		* (float(rules["elite_command_martial_floor"]) + martial_share)
	elite -= elite * float(rules["elite_decay_rate"])
	elite = clampf(elite, 0.0, float(rules["elite_max"]))

	# Martial ethos relaxes toward the militarisation actually practised: the
	# share of the people under arms, plus what has been built to keep them so.
	var under_arms := 0.0
	if population_total > 0:
		under_arms = float(soldiers_total) / float(population_total)
	var martial_target := under_arms * float(rules["martial_under_arms_scale"])
	if owned > 0:
		martial_target += martial_buildings / float(owned) * float(rules["martial_building_scale"])
	martial_target = clampf(martial_target, 0.0, float(rules["martial_max"]))
	# Asymmetric on purpose: a people can be turned to war in a few seasons and
	# takes a generation to be turned back. What you become is easier to reach
	# than to leave.
	var martial := float(stocks["martial_ethos"])
	var martial_rate := float(rules["martial_rise_rate"]) if martial_target > martial \
		else float(rules["martial_fall_rate"])
	martial += (martial_target - martial) * martial_rate
	martial = clampf(martial, 0.0, float(rules["martial_max"]))

	# Knowledge accrues from institutions and decays proportionally, so craft
	# that is not sustained is forgotten. A society in collapse learns nothing.
	var knowledge := float(stocks["knowledge"])
	var accrual := 0.0
	if owned > 0:
		var floor_share := float(rules["knowledge_legitimacy_floor"])
		accrual = knowledge_buildings / float(owned) * float(rules["knowledge_accrual_scale"]) \
			* (floor_share + (1.0 - floor_share) * legitimacy_share)
	var decay := float(rules["knowledge_decay_rate"])
	decay *= maxf(0.0, 1.0 - AdvanceRules.effect_total(data, state, faction_id, "knowledge_decay_reduction_pct") / 100.0)
	knowledge += accrual - knowledge * decay
	knowledge = clampf(knowledge, 0.0, float(rules["knowledge_max"]))

	# Plunder's share: how much of what came in this turn was taken rather than
	# made. An exponential moving average, so it outlives the conquest that
	# raised it by a generation — which is why the reckoning arrives in peacetime.
	var plunder := maxf(float(stocks["plunder_pending"]), 0.0)
	var produced := maxf(income, 0.0)
	var share := 0.0
	if plunder + produced > 0.0:
		share = plunder / (plunder + produced) * 100.0
	var spoils := float(stocks["spoils"])
	spoils += (share - spoils) * float(rules["spoils_rate"])
	spoils = clampf(spoils, 0.0, float(rules["spoils_max"]))

	# A reputation for atrocity is remembered everywhere, and fades slowly.
	var shock := float(stocks["civic_shock"])
	if shock < 0.0:
		shock = minf(0.0, shock + float(rules["civic_shock_decay_per_turn"]))

	faction["society"] = {
		"elite_pressure": quantize(elite),
		"martial_ethos": quantize(martial),
		"knowledge": quantize(knowledge),
		"spoils": quantize(spoils),
		"plunder_pending": 0.0,
		"civic_shock": quantize(shock),
	}


static func apply_settlement_turn(data: GameData, state: Dictionary, region_id: String) -> Dictionary:
	## Returns {} when nothing notable happened, or a notice when the province
	## crossed an unrest threshold.
	var settlement: Dictionary = state["settlements"][region_id]
	var rules: Dictionary = data.balance["society"]
	var stocks := stocks_of(data, settlement)

	var legitimacy := float(stocks["legitimacy"])
	var grievance := float(stocks["grievance"])
	var assimilation := float(stocks["assimilation"])
	var unrest_state := String(stocks["unrest_state"])

	var target := legitimacy_target(data, state, region_id)
	var settlement_load := load_total(data, state, region_id)
	var contact := assimilation_contact(data, state, region_id)

	# 1. Consent drifts toward what you have built — over a generation, not a turn.
	var new_legitimacy := legitimacy + (target - legitimacy) * float(rules["legitimacy_relax_rate"])
	new_legitimacy = clampf(new_legitimacy, 0.0, float(rules["legitimacy_max"]))

	# 2. The coerced share of the load charges grievance. Coercion raises public
	#    order (see PublicOrderRules) but never appears here — which is exactly
	#    why a garrisoned province reads calm while the pressure builds.
	var relief_factor := 1.0
	if unrest_state != UNREST_CALM:
		relief_factor = float(rules["grievance_restive_relief_factor"])
	var new_grievance := grievance \
		+ maxf(0.0, settlement_load - legitimacy) * float(rules["grievance_charge_rate"]) \
		- maxf(0.0, legitimacy - settlement_load) * float(rules["grievance_relief_rate"]) * relief_factor
	# An amnesty is the one hand the player has directly on a stock, and it is
	# the only way out of a crisis that does not take a generation. It is not
	# free: see the edict's own elite_pressure and law costs.
	new_grievance -= EdictRules.effect(data, settlement, "grievance_relief")
	new_grievance = clampf(new_grievance, 0.0, float(rules["grievance_max"]))

	# 3. Belonging diffuses on contact. A resentful province never assimilates.
	# Diffusion toward full belonging, with resentment as a proportional drag: a
	# province that resents you stops becoming yours and slips back, but a home
	# province does not turn foreign merely because it is unhappy.
	var new_assimilation := assimilation \
		+ float(rules["assimilation_rate"]) * contact * (100.0 - assimilation) / 100.0 \
		- float(rules["assimilation_friction_scale"]) * grievance / 100.0 * assimilation / 100.0
	new_assimilation = clampf(new_assimilation, 0.0, float(rules["assimilation_max"]))

	# 4. The city learns what to expect far faster than it forgets it. This is
	#    the civic counterpart of the coercion trap: generosity, once given,
	#    becomes the baseline it is measured against.
	var current := provision(data, settlement)
	var expectation := float(stocks["expectation"])
	var expectation_rate := float(rules["expectation_rise_rate"]) if current > expectation \
		else float(rules["expectation_fall_rate"])
	var new_expectation := expectation + (current - expectation) * expectation_rate
	new_expectation = clampf(new_expectation, 0.0, float(rules["expectation_max"]))

	# 5. Unrest ignites high and extinguishes low. Fixing the cause does not
	#    undo the crisis; that gap is what makes a decision irreversible.
	var new_state := unrest_state
	match unrest_state:
		UNREST_CALM:
			if new_grievance >= float(rules["restive_ignite"]):
				new_state = UNREST_RESTIVE
		UNREST_RESTIVE:
			if new_grievance >= float(rules["revolt_ignite"]):
				new_state = UNREST_REBELLIOUS
			elif new_grievance <= float(rules["restive_extinguish"]):
				new_state = UNREST_CALM
		UNREST_REBELLIOUS:
			if new_grievance <= float(rules["revolt_extinguish"]):
				new_state = UNREST_RESTIVE

	var unrest_turns := int(stocks["unrest_turns"]) + 1
	if new_state != unrest_state:
		unrest_turns = 0

	var survey = settlement.get("society", {}).get("survey", {})
	settlement["society"] = {
		"legitimacy": quantize(new_legitimacy),
		"grievance": quantize(new_grievance),
		"assimilation": quantize(new_assimilation),
		"expectation": quantize(new_expectation),
		"unrest_state": new_state,
		"unrest_turns": unrest_turns,
		"survey": survey,
	}

	if new_state != unrest_state:
		return {"region": region_id, "from": unrest_state, "to": new_state, "owner": settlement["owner"]}
	return {}


static func apply_turn(data: GameData, state: Dictionary, faction_ids: Array, region_ids: Array) -> Array:
	## Faction stocks resolve first: militarisation and elite pressure are inputs
	## to every province's load, so the empire's condition is settled before its
	## provinces respond to it.
	var notices: Array = []
	for faction_id in faction_ids:
		if state["factions"][faction_id]["alive"]:
			apply_faction_turn(data, state, faction_id)
	for region_id in region_ids:
		var notice := apply_settlement_turn(data, state, region_id)
		if not notice.is_empty():
			notices.append(notice)
	return notices


## --- Shocks fired by other systems ----------------------------------------

static func record_conquest(data: GameData, state: Dictionary, region_id: String,
		new_owner: String, occupation: String) -> void:
	## A captured province starts resentful and a stranger to its new masters,
	## and the conqueror's own elite grows by one more victorious house.
	var rules: Dictionary = data.balance["society"]
	var settlement: Dictionary = state["settlements"][region_id]
	var dominant := dominant_culture(data, settlement)
	var native := dominant == "" or data.culture_of_faction(new_owner) == dominant
	var society := new_settlement_society(data, native, provision(data, settlement))
	society["grievance"] = quantize(clampf(float(rules["grievance_conquest_shock"]), 0.0, float(rules["grievance_max"])))
	settlement["society"] = society

	var faction: Dictionary = state["factions"].get(new_owner, {})
	if faction.is_empty():
		return
	var stocks := faction_stocks(data, faction)
	var elite := float(stocks["elite_pressure"]) + float(rules["elite_conquest_shock"])
	var martial := float(stocks["martial_ethos"])
	var shock := float(stocks["civic_shock"])
	if occupation == "exterminate":
		martial = clampf(martial + float(rules["martial_extermination_shock"]), 0.0, float(rules["martial_max"]))
		shock += float(rules["civic_shock_exterminate"])
	elif occupation == "enslave":
		shock += float(rules["civic_shock_enslave"])
	faction["society"] = {
		"elite_pressure": quantize(clampf(elite, 0.0, float(rules["elite_max"]))),
		"martial_ethos": quantize(martial),
		"knowledge": quantize(float(stocks["knowledge"])),
		"spoils": quantize(float(stocks["spoils"])),
		"plunder_pending": quantize(float(stocks["plunder_pending"])),
		"civic_shock": quantize(shock),
	}


static func record_plunder(data: GameData, state: Dictionary, faction_id: String, loot: float) -> void:
	## Loot is buffered rather than applied directly, because the player storms
	## cities through Game.assault_settlement, which resolves OUTSIDE end_turn.
	## Without the buffer, Plunder's Share would only ever see the AI's sieges.
	var faction: Dictionary = state["factions"].get(faction_id, {})
	if faction.is_empty() or loot <= 0.0:
		return
	var stocks := faction_stocks(data, faction)
	var society: Dictionary = faction.get("society", {})
	if society.is_empty():
		society = new_faction_society(data)
	society["plunder_pending"] = quantize(float(stocks["plunder_pending"]) + loot)
	faction["society"] = society


static func record_recruitment(data: GameData, state: Dictionary, region_id: String, soldiers: int) -> void:
	## Conscription is felt where the men are taken from.
	var rules: Dictionary = data.balance["society"]
	var settlement: Dictionary = state["settlements"][region_id]
	var stocks := stocks_of(data, settlement)
	var added := float(soldiers) / 1000.0 * float(rules["grievance_per_recruited_1000"])
	var society: Dictionary = settlement.get("society", {})
	if society.is_empty():
		society = new_settlement_society(data, true)
		society["legitimacy"] = float(stocks["legitimacy"])
		society["assimilation"] = float(stocks["assimilation"])
	society["grievance"] = quantize(clampf(float(stocks["grievance"]) + added, 0.0, float(rules["grievance_max"])))
	settlement["society"] = society


static func dominant_culture(data: GameData, settlement: Dictionary) -> String:
	## The culture that built most of what stands here — used to decide whether a
	## new owner is coming home or arriving as a stranger.
	var counts := {}
	var chain_ids: Array = settlement["buildings"].keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		for culture in chain["cultures"]:
			counts[culture] = int(counts.get(culture, 0)) + 1
	var best := ""
	var best_count := 0
	var culture_ids: Array = counts.keys()
	culture_ids.sort()
	for culture in culture_ids:
		if int(counts[culture]) > best_count:
			best_count = int(counts[culture])
			best = culture
	return best
