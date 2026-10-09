class_name DivineDilemmaRules
extends RefCounted
## Authored choices quote existing policies. Only explicit confirmation commits;
## neither reading nor the LLM issues orders, moves time, awards money or draws RNG.

static func fresh() -> Dictionary:
	return {"cooldown_until":0,"resolved":{}}

static func status(data: GameData, state: Dictionary, region: String) -> Dictionary:
	if CityBattleRules.locked(state):return {"blocked":"battle_active","cards":[]}
	var ledger: Dictionary = state.get("divine_dilemmas",fresh())
	var result := {"blocked":PatronageRules.command_blocked(data,state),
		"turn":int(state.turn),"region":region,"cooldown_until":int(ledger.cooldown_until),"cards":[]}
	for profile in data.divine_dilemma_content.get("dilemmas",[]):
		var card: Dictionary = profile.duplicate(true)
		card.resolved = ledger.resolved.has(profile.id)
		card.receipt = ledger.resolved.get(profile.id,{}).duplicate(true)
		var base_reason := _base_reason(data,state,profile,region)
		for choice in card.choices:
			var gate := {"reason":base_reason,"detail":""} if base_reason != "" else _choice_gate(data,state,region,choice)
			choice.available = gate.reason == ""
			choice.reason = gate.reason
			choice.detail = gate.detail
		result.cards.append(card)
	return result

static func quote(data: GameData, state: Dictionary, id: String, choice_id: String, region: String) -> Dictionary:
	# The battle worker owns mutable state until closed. Return before traversing it.
	if CityBattleRules.locked(state):return {"ok":false,"reason":"battle_active"}
	var profile := _profile(data,id)
	if profile.is_empty():return {"ok":false,"reason":"unknown_dilemma"}
	var choice := _choice(profile,choice_id)
	if choice.is_empty():return {"ok":false,"reason":"unknown_choice"}
	var reason := _base_reason(data,state,profile,region)
	var result := {"ok":false,"reason":reason,"detail":"","id":id,"choice":choice_id,"region":region,
		"turn":int(state.turn),"choice_label":choice.label,"dilemma_title":profile.title,
		"city_name":data.regions.get(region,{}).get("settlement_name",region)}
	if reason != "":return result
	var gate := _choice_gate(data,state,region,choice)
	result.reason = gate.reason
	result.detail = gate.detail
	if gate.reason != "":return result
	result.consequences = _consequences(data,state.settlements[region],choice)
	result.cooldown_until = int(state.turn) + int(data.balance.divine_dilemmas.cooldown_turns)
	result.signature = _signature(data,state,profile,choice,region)
	result.ok = true
	return result

static func resolve(data: GameData, state: Dictionary, id: String, choice_id: String, region: String, signature: String) -> Dictionary:
	var current := quote(data,state,id,choice_id,region)
	if not current.get("ok",false):return {"ok":false,"reason":current.reason}
	if signature.length() != 64 or not signature.is_valid_hex_number():return {"ok":false,"reason":"invalid_signature"}
	if signature != current.signature:return {"ok":false,"reason":"stale_quote"}
	var choice := _choice(_profile(data,id),choice_id)
	# quote rechecked player ownership and the complete policy gate above.
	if choice.action == "edict":
		if not EdictRules.issue(data,state,region,choice.target):return {"ok":false,"reason":"commit_failed"}
	elif choice.action == "tax":
		state.settlements[region].tax_level = choice.target
		GuidedRules.bump(state,"taxes_set")
	if not state.has("divine_dilemmas"):state.divine_dilemmas = fresh()
	state.divine_dilemmas.resolved[id] = {"turn":int(state.turn),"region":region,"choice":choice_id}
	state.divine_dilemmas.cooldown_until = current.cooldown_until
	return {"ok":true,"reason":"","receipt":state.divine_dilemmas.resolved[id].duplicate(true),
		"cooldown_until":current.cooldown_until}

static func _base_reason(data: GameData, state: Dictionary, profile: Dictionary, region: String) -> String:
	var block := PatronageRules.command_blocked(data,state)
	if block != "":return block
	var city: Dictionary = state.get("settlements",{}).get(region,{})
	if city.is_empty() or city.owner != state.player_faction:return "not_owned"
	var ledger: Dictionary = state.get("divine_dilemmas",fresh())
	if ledger.resolved.has(profile.id):return "already_resolved"
	var pledge: Dictionary = state.get("patronage",{})
	if pledge.get("chosen","") != profile.patron:return "wrong_patron"
	if int(state.turn) < int(pledge.get("pledged_turn",state.turn)) + int(data.balance.divine_dilemmas.pledge_wait_turns):return "pledge_too_recent"
	if int(state.turn) < int(ledger.cooldown_until):return "cooldown_active"
	var patron: Dictionary = data.patrons.get(profile.patron,{})
	for chain_id in patron.get("temple_chains",[]):
		var chain: Dictionary = data.chains.get(chain_id,{})
		var level := int(city.get("buildings",{}).get(chain_id,0))
		if chain.get("kind","") == "temple" and level > 0 and level <= chain.get("levels",[]).size():return ""
	return "temple_required"

static func _choice_gate(data: GameData, state: Dictionary, region: String, choice: Dictionary) -> Dictionary:
	if choice.action == "tax":
		var current: String = state.settlements[region].tax_level
		if not Constants.TAX_LEVELS.has(choice.target):return {"reason":"unknown_choice","detail":""}
		if float(data.balance.taxes.income_multiplier[current]) <= float(data.balance.taxes.income_multiplier[choice.target]):
			return {"reason":"tax_not_lower","detail":""}
	elif choice.action == "edict":
		var gate := EdictRules.allowed(data,state,region,choice.target)
		if not gate.ok:return {"reason":"edict_unavailable","detail":gate.reason}
	elif choice.action != "decline":return {"reason":"unknown_choice","detail":""}
	return {"reason":"","detail":""}

static func _consequences(data: GameData, city: Dictionary, choice: Dictionary) -> Dictionary:
	var result := {"kind":choice.action,"immediate_cost":0}
	if choice.action == "tax":
		var prior: String = city.tax_level
		var after: String = choice.target
		result.merge({"tax_before":prior,"tax_after":after,
			"tax_income_multiplier_before":data.balance.taxes.income_multiplier[prior],
			"tax_income_multiplier_after":data.balance.taxes.income_multiplier[after],
			"order_tax_factor_before":data.balance.public_order.tax_happiness[prior],
			"order_tax_factor_after":data.balance.public_order.tax_happiness[after],
			"growth_tax_factor_before":data.balance.growth.tax_growth_pct[prior],
			"growth_tax_factor_after":data.balance.growth.tax_growth_pct[after]})
	elif choice.action == "edict":
		var definition: Dictionary = data.edicts[choice.target]
		var rate := float(definition.get("upkeep_per_1000_pop",0.0))
		result.merge({"edict_id":choice.target,"name":definition.name,
			"upkeep_per_turn":float(city.population)/1000.0*rate,"upkeep_per_1000_pop":rate,
			"population":int(city.population),"settle_turns":int(definition.settle_turns),
			"revoke_cooldown":int(definition.cooldown_turns),"effects":definition.effects.duplicate(true)})
	return result

static func _signature(data: GameData, state: Dictionary, profile: Dictionary, choice: Dictionary, region: String) -> String:
	# Only the selected owned city/faction, explicit pledge/receipts and rule data
	# participate. The hash never exposes their unreported societal values.
	var source := {"turn":int(state.turn),"player":state.player_faction,"region":region,
		"city":state.settlements[region],"faction":state.factions[state.player_faction],
		"patronage":state.get("patronage",{}),"ledger":state.get("divine_dilemmas",fresh()),
		"profile":profile,"choice":choice,"patron":data.patrons.get(profile.patron,{}),
		"edict":data.edicts.get(choice.target,{}),"tuning":data.balance.divine_dilemmas,
		"taxes":data.balance.taxes,"order_tax":data.balance.public_order.tax_happiness,
		"growth_tax":data.balance.growth.tax_growth_pct}
	# JSON parsing normalizes integer/float storage and key order across saves.
	return JSON.stringify(JSON.parse_string(JSON.stringify(source))).sha256_text()

static func _profile(data: GameData, id: String) -> Dictionary:
	for profile in data.divine_dilemma_content.get("dilemmas",[]):
		if profile.id == id:return profile
	return {}

static func _choice(profile: Dictionary, id: String) -> Dictionary:
	for choice in profile.get("choices",[]):
		if choice.id == id:return choice
	return {}
