class_name PortOperations
## Read-only, owner-scoped presentation facts. Never part of public PortLayout.
static func snapshot(data: GameData, state: Dictionary, region: String, layout: Dictionary) -> Dictionary:
	var result := {"berths":{},"waiting":[],"fleets":[],"queue":[],"project":{}}
	var town: Dictionary = state.get("settlements",{}).get(region,{})
	if town.get("owner","") != state.get("player_faction",""):
		return result
	result["project"] = PortRules.record(state,region).get("project",{}).duplicate(true)
	var eta := 0
	for job in town.get("recruitment_queue",[]):
		eta += int(job["turns_left"])
		if data.units.get(job["template"],{}).get("class","") == "ship":
			result["queue"].append({"template":job["template"],"turns":eta,"remaining":job["turns_left"]})
	for berth in layout["berths"]:
		result["berths"][berth["id"]] = []
	for i in range(town.get("harbour",[]).size()):
		var ship: Dictionary = town["harbour"][i]
		var rating := PortRules.vessel(data,ship["template"])
		var needs: Dictionary = data.ports["vessels"].get(ship["template"],{})
		var preferred := "military_berth" if needs.get("facilities",[]).has("arsenal") else ("deep_berth" if needs.get("deep_water",false) else ("merchant_berth" if int(rating.get("cargo",0)) > 100 else "landing_berth"))
		var candidates: Array = []
		for berth in layout["berths"]:
			if int(needs.get("stage",1)) <= int(berth.get("max_vessel_stage",1)):
				candidates.append(berth["id"])
		if candidates.has(preferred):
			candidates.erase(preferred)
			candidates.push_front(preferred)
		var assigned := false
		for id in candidates:
			if result["berths"][id].is_empty():
				result["berths"][id].append({"index":i,"template":ship["template"],"readiness":ship["strength_pct"]})
				assigned = true
				break
		if not assigned:
			result["waiting"].append(i)
	var ids: Array = state.get("fleets",{}).keys()
	ids.sort()
	for id in ids:
		var fleet: Dictionary = state["fleets"][id]
		if fleet["owner"] == state["player_faction"] and NavalRules.zones_touching(data,region).has(fleet["sea_zone"]):
			result["fleets"].append(id)
	return result
