class_name VisibilityRules
## Fog of war on the region graph: a faction sees its own regions and armies,
## plus everything one hop out (and coastal regions of sea zones its fleets sit in).


static func visible_regions(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	## Returns a set: {region_id: true}. Dictionary-as-set keeps it JSON-friendly.
	var visible := {}

	for region_id in state["settlements"]:
		if state["settlements"][region_id]["owner"] == faction_id:
			visible[region_id] = true
			for neighbor in data.regions[region_id].get("adjacent", []):
				visible[neighbor] = true

	for army in state["armies"].values():
		if army["owner"] != faction_id:
			continue
		visible[army["region"]] = true
		for neighbor in data.regions[army["region"]].get("adjacent", []):
			visible[neighbor] = true

	for fleet in state["fleets"].values():
		if fleet["owner"] != faction_id:
			continue
		for region_id in data.regions:
			if data.regions[region_id].get("sea_zones", []).has(fleet["sea_zone"]):
				visible[region_id] = true

	return visible
