class_name ModifierRules
## Stacking timed modifiers — the generalization of the old single-slot
## state.event_happiness (which stays untouched for save compatibility and
## still renders as its own "events" factor). A modifier is
##   {id, faction, region, effect, value, turns_left, source}
## where faction "" means every faction, region "" means faction-wide, and
## source names the author ("edict:grain_dole", "repeal:grain_dole",
## "event:..."). Decree moods and repeal shocks live here; later phases
## (events, chronicle) reuse the same container.


static func add(state: Dictionary, faction_id: String, region_id: String, effect: String, value: float, turns: int, source: String) -> void:
	var modifier_id := "mod_%d" % int(state["next_id"])
	state["next_id"] = int(state["next_id"]) + 1
	state["modifiers"].append({
		"id": modifier_id, "faction": faction_id, "region": region_id,
		"effect": effect, "value": value, "turns_left": turns, "source": source,
	})


static func sum_for(state: Dictionary, faction_id: String, region_id: String, effect: String) -> float:
	## Everything that applies here: global + this faction's, faction-wide +
	## this region's. Pure sum — order-free.
	var total := 0.0
	for modifier in state.get("modifiers", []):
		if modifier["effect"] != effect:
			continue
		if modifier["faction"] != "" and modifier["faction"] != faction_id:
			continue
		if modifier["region"] != "" and modifier["region"] != region_id:
			continue
		total += float(modifier["value"])
	return total


static func tick(state: Dictionary) -> void:
	## Once per end_turn: moods fade, spent ones vanish. In-place, order kept.
	var remaining: Array = []
	for modifier in state.get("modifiers", []):
		modifier["turns_left"] = int(modifier["turns_left"]) - 1
		if int(modifier["turns_left"]) > 0:
			remaining.append(modifier)
	state["modifiers"] = remaining
