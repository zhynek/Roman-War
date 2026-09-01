class_name EdictRules
## One standing order per province — the player's fast lever on a simulation
## whose stocks otherwise move on 17-to-90 turn constants.
##
## An edict is deliberately shaped like a building you can put up and take down:
## its effects use the SAME closed vocabulary the building chains use, and
## SettlementRules.effect_total folds them in, so an edict reaches public order,
## growth, income, corruption, the load, the legitimacy target, provision (and
## therefore expectation), belonging, martial spirit and craft without any of
## those readers knowing edicts exist. Only five keys need their own reader,
## because they are not additive settlement effects: grievance_relief,
## elite_pressure, income_pct, clarity_bonus and build_cost_pct.
##
## Taking hold is gradual and letting go is instant. Effects scale by
## turns_held / settle_turns, so an edict bites over a few turns; revoking stops
## it the same turn, while whatever it moved decays at the stock's own pace.
## That asymmetry is what makes the Corn Dole a trap rather than a toggle: the
## provision vanishes at once and the expectation it created does not.
##
## Consumes no randomness.

const NONE := ""


static func of(settlement: Dictionary) -> Dictionary:
	## The settlement's edict record, defaulted so older saves and fixtures read
	## alike: {id, turns_held, cooldown}.
	var edict: Dictionary = settlement.get("edict", {})
	return {
		"id": String(edict.get("id", NONE)),
		"turns_held": int(edict.get("turns_held", 0)),
		"cooldown": int(edict.get("cooldown", 0)),
	}


static func new_record() -> Dictionary:
	return {"id": NONE, "turns_held": 0, "cooldown": 0}


static func strength(data: GameData, settlement: Dictionary) -> float:
	## How far an edict has taken hold, 0..1. A new order is not yet obeyed.
	var current := of(settlement)
	if current["id"] == NONE:
		return 0.0
	var definition: Dictionary = data.edicts.get(current["id"], {})
	if definition.is_empty():
		return 0.0
	var settle := maxi(int(definition.get("settle_turns", 1)), 1)
	return clampf(float(current["turns_held"]) / float(settle), 0.0, 1.0)


static func effect(data: GameData, settlement: Dictionary, key: String) -> float:
	## The ramp-scaled value of one effect key. This is what SettlementRules
	## folds into effect_total, and what the five dedicated readers call.
	var current := of(settlement)
	if current["id"] == NONE:
		return 0.0
	var definition: Dictionary = data.edicts.get(current["id"], {})
	if definition.is_empty():
		return 0.0
	var value := float(definition.get("effects", {}).get(key, 0.0))
	if value == 0.0:
		return 0.0
	return value * strength(data, settlement)


static func upkeep(data: GameData, settlement: Dictionary) -> float:
	## Denarii per turn, scaled by the population being provided for. Charged at
	## full rate from the turn it is issued — the corn is bought before it is
	## eaten, whatever the province thinks of you yet.
	var current := of(settlement)
	if current["id"] == NONE:
		return 0.0
	var definition: Dictionary = data.edicts.get(current["id"], {})
	var per_1000 := float(definition.get("upkeep_per_1000_pop", 0.0))
	if per_1000 == 0.0:
		return 0.0
	return float(settlement["population"]) / 1000.0 * per_1000


## --- Availability ---------------------------------------------------------

static func allowed(data: GameData, state: Dictionary, region_id: String, edict_id: String) -> Dictionary:
	## {ok: bool, reason: String}. Mirrors the gating shape of
	## ConstructionRules.available_projects so the UI can explain a refusal.
	var settlement: Dictionary = state["settlements"][region_id]
	var definition: Dictionary = data.edicts.get(edict_id, {})
	if definition.is_empty():
		return {"ok": false, "reason": "no such edict"}

	var current := of(settlement)
	if current["id"] == edict_id:
		return {"ok": false, "reason": "already in force"}
	if current["id"] != NONE:
		return {"ok": false, "reason": "revoke the standing edict first"}
	if int(current["cooldown"]) > 0:
		return {"ok": false, "reason": "the last edict is still being unwound (%d turns)" % int(current["cooldown"])}

	var cultures: Array = definition.get("cultures", [])
	if not cultures.is_empty() and not cultures.has(data.culture_of_faction(String(settlement["owner"]))):
		return {"ok": false, "reason": "not a thing your people do"}

	var level := SettlementRules.settlement_level(data, settlement)
	if not Constants.level_at_most(String(definition["min_settlement_level"]), level):
		return {"ok": false, "reason": "needs a %s" % String(definition["min_settlement_level"]).replace("_", " ")}

	var needed_kind: String = definition.get("requires_building_kind", "")
	if needed_kind != "" and not _has_kind(data, settlement, needed_kind):
		return {"ok": false, "reason": "needs a %s here" % needed_kind.replace("_", " ")}

	return {"ok": true, "reason": ""}


static func available(data: GameData, state: Dictionary, region_id: String) -> Array:
	## Every edict, in canonical id order, each with whether it may be issued and
	## why not. The UI lists them all so the player can see what a province could
	## have, not only what it can have today.
	var edict_ids: Array = data.edicts.keys()
	edict_ids.sort()
	var settlement: Dictionary = state["settlements"][region_id]
	var result: Array = []
	for edict_id in edict_ids:
		var definition: Dictionary = data.edicts[edict_id]
		var gate := allowed(data, state, region_id, edict_id)
		result.append({
			"id": edict_id,
			"name": definition["name"],
			"description": definition["description"],
			"effects": definition.get("effects", {}),
			"settle_turns": int(definition.get("settle_turns", 1)),
			"cooldown_turns": int(definition.get("cooldown_turns", 0)),
			"pattern": definition.get("pattern", ""),
			"upkeep": float(settlement["population"]) / 1000.0 * float(definition.get("upkeep_per_1000_pop", 0.0)),
			"allowed": gate["ok"],
			"reason": gate["reason"],
		})
	return result


static func status(data: GameData, state: Dictionary, region_id: String) -> Dictionary:
	var settlement: Dictionary = state["settlements"][region_id]
	var current := of(settlement)
	if current["id"] == NONE:
		return {"id": NONE, "name": "", "turns_held": 0, "settle_turns": 0,
			"strength": 0.0, "cooldown": int(current["cooldown"]), "upkeep": 0.0,
			"effects": {}, "pattern": ""}
	var definition: Dictionary = data.edicts.get(current["id"], {})
	return {
		"id": current["id"],
		"name": definition.get("name", current["id"]),
		"turns_held": int(current["turns_held"]),
		"settle_turns": int(definition.get("settle_turns", 1)),
		"strength": strength(data, settlement),
		"cooldown": 0,
		"upkeep": upkeep(data, settlement),
		"effects": definition.get("effects", {}),
		"pattern": definition.get("pattern", ""),
	}


## --- Player actions -------------------------------------------------------

static func issue(data: GameData, state: Dictionary, region_id: String, edict_id: String) -> bool:
	if not allowed(data, state, region_id, edict_id)["ok"]:
		return false
	state["settlements"][region_id]["edict"] = {"id": edict_id, "turns_held": 0, "cooldown": 0}
	return true


static func revoke(data: GameData, state: Dictionary, region_id: String) -> bool:
	## Immediate: the order stops today. The cooldown that follows is what stops
	## the player flip-flopping to farm the settling ramp.
	var settlement: Dictionary = state["settlements"][region_id]
	var current := of(settlement)
	if current["id"] == NONE:
		return false
	var definition: Dictionary = data.edicts.get(current["id"], {})
	settlement["edict"] = {
		"id": NONE, "turns_held": 0,
		"cooldown": int(definition.get("cooldown_turns", 0)),
	}
	return true


static func clear(settlement: Dictionary) -> void:
	## A province that changes hands answers to nobody's standing orders.
	settlement["edict"] = new_record()


## --- Turn ------------------------------------------------------------------

static func advance_turn(data: GameData, state: Dictionary, region_ids: Array) -> void:
	## Runs before the economy so a freshly issued edict is billed and counted in
	## the same turn it starts taking hold.
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var current := of(settlement)
		if current["id"] != NONE:
			var definition: Dictionary = data.edicts.get(current["id"], {})
			var settle := maxi(int(definition.get("settle_turns", 1)), 1)
			settlement["edict"] = {
				"id": current["id"],
				"turns_held": mini(int(current["turns_held"]) + 1, settle),
				"cooldown": 0,
			}
		elif int(current["cooldown"]) > 0:
			settlement["edict"] = {"id": NONE, "turns_held": 0, "cooldown": int(current["cooldown"]) - 1}


static func faction_effect_total(data: GameData, state: Dictionary, faction_id: String,
		key: String, region_ids: Array = []) -> float:
	## Sum an edict effect across every province a faction holds — for the keys
	## whose target is the faction rather than the settlement.
	##
	## Callers on a hot path pass the region list they already have. Callers
	## that do not have one omit it and pay for the scan: the settlements are
	## walked in sorted order so the result never depends on dictionary order.
	var scan := region_ids
	if scan.is_empty():
		scan = state["settlements"].keys()
		scan.sort()
	var total := 0.0
	for region_id in scan:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] != faction_id:
			continue
		total += effect(data, settlement, key)
	return total


static func _has_kind(data: GameData, settlement: Dictionary, kind: String) -> bool:
	for chain_id in settlement["buildings"]:
		if data.chains.get(chain_id, {}).get("kind", "") == kind \
				and int(settlement["buildings"][chain_id]) > 0:
			return true
	return false
