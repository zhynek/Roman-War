class_name AiStub
## Phase-6 placeholder: non-player factions manage settlements passively so the
## world economy runs and long headless campaigns exercise every system. Real
## modular AI (economy / expansion / diplomacy / war behaviors) replaces this.


static func take_turn(data: GameData, state: Dictionary, faction_id: String) -> void:
	var faction: Dictionary = state["factions"][faction_id]
	if not faction["alive"]:
		return
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] != faction_id:
			continue

		# Keep a token garrison for order, then build whatever is cheapest.
		if settlement["garrison"].size() < 2 and settlement["recruitment_queue"].is_empty():
			var cheapest := {}
			for unit in RecruitmentRules.available_units(data, state, region_id):
				if unit.get("class", "") == "ship":
					continue  # a garrison wants men; ships are a fleet's business
				if cheapest.is_empty() or int(unit["cost"]) < int(cheapest["cost"]):
					cheapest = unit
			if not cheapest.is_empty() and int(faction["treasury"]) > int(cheapest["cost"]) + 2000:
				RecruitmentRules.queue_unit(data, state, region_id, cheapest["id"])

		if settlement["construction_queue"].is_empty():
			var best := {}
			for project in ConstructionRules.available_projects(data, state, region_id):
				if best.is_empty() or int(project["cost"]) < int(best["cost"]):
					best = project
			if not best.is_empty() and int(faction["treasury"]) > int(best["cost"]) + 1000:
				ConstructionRules.queue_project(data, state, region_id, best["chain"])
