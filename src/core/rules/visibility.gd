class_name VisibilityRules
## Province observation from towns, columns, scouts, fleets and built posts.
## All land radii come from balance.reconnaissance; no renderer writes sight.


static func visible_regions(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	## Returns a set: {region_id: true}. Dictionary-as-set keeps it JSON-friendly.
	var visible := {}

	var rules := ReconRules.rules(data)
	for region_id in state.get("settlements", {}):
		if state.get("settlements", {})[region_id]["owner"] == faction_id:
			add_radius(data, visible, region_id, int(rules.get("settlement_sight", 1)))
	for army in state.get("armies", {}).values():
		if army["owner"] == faction_id:
			add_radius(data, visible, army["region"], ReconRules.army_sight(data, army))
	for region_id in state.get("watchposts", {}):
		var post: Dictionary = state["watchposts"][region_id]
		if post["owner"] == faction_id and ReconRules.post_active(state, region_id, post):
			add_radius(data, visible, region_id, int(rules.get("fort_sight" if int(post["level"]) >= 2 else "watchtower_sight", 2)))

	for fleet in state.get("fleets", {}).values():
		if fleet["owner"] != faction_id:
			continue
		for region_id in data.regions:
			if NavalRules.zones_touching(data, region_id).has(fleet["sea_zone"]):
				visible[region_id] = true

	for agent in state.get("agents", {}).values():
		if agent["owner"] != faction_id:
			continue
		add_radius(data, visible, agent["region"], int(rules.get("spy_sight" if agent.get("kind", "") == "spy" else "agent_sight", 1)))

	return visible


static func visible_sea_zones(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	## The seas a faction has eyes on, as a set {zone_id: true}: every zone one
	## of its fleets sails (and the zones beyond it), plus every zone touching
	## a region it owns or has an army in. Fleets elsewhere are unseen.
	var visible := {}
	for fleet in state.get("fleets", {}).values():
		if fleet["owner"] != faction_id:
			continue
		visible[fleet["sea_zone"]] = true
		for adjacent in data.sea_zones.get(fleet["sea_zone"], {}).get("adjacent", []):
			visible[adjacent] = true
	for region_id in state.get("settlements", {}):
		if state.get("settlements", {})[region_id]["owner"] == faction_id:
			for zone in NavalRules.zones_touching(data, region_id):
				visible[zone] = true
	for army in state.get("armies", {}).values():
		if army["owner"] == faction_id:
			for zone in NavalRules.zones_touching(data, army["region"]):
				visible[zone] = true
	return visible


static func add_radius(data: GameData, visible: Dictionary, origin: String, hops: int) -> void:
	var reached := {origin: true}
	var frontier: Array = [origin]
	visible[origin] = true
	for depth in range(hops):
		var next: Array = []
		for region in frontier:
			for neighbor in data.regions.get(region, {}).get("adjacent", []):
				if not reached.has(neighbor) and TerrainRules.land_connection(data, region, neighbor):
					reached[neighbor] = true
					visible[neighbor] = true
					next.append(neighbor)
		frontier = next


static func forest_detection(data: GameData, state: Dictionary, faction: String) -> Dictionary:
	## Local presence and deliberate reconnaissance penetrate woodland. Town
	## lookouts map a forest, but cannot count columns under its canopy.
	var detected := {}
	var rules := ReconRules.rules(data)
	for army in state.get("armies", {}).values():
		if army["owner"] == faction:
			add_radius(data, detected, army["region"], int(rules.get("forest_mounted_detection", 1)) if MovementRules.mobility_profile(data, army)["mounted"] else 0)
	for agent in state.get("agents", {}).values():
		if agent["owner"] == faction:
			add_radius(data, detected, agent["region"], int(rules.get("forest_spy_detection", 1)) if agent.get("kind", "") == "spy" else 0)
	for region in state.get("watchposts", {}):
		var post: Dictionary = state["watchposts"][region]
		if post["owner"] == faction and ReconRules.post_active(state, region, post):
			add_radius(data, detected, region, int(rules.get("forest_fort_detection", 1)) if int(post["level"]) >= 2 else 0)
	for region in state.get("forest_patrols", {}).get(faction, {}):
		if int(state["forest_patrols"][faction][region]) == int(state["turn"]):
			detected[region] = true
	return detected


static func army_visible(data: GameData, state: Dictionary, faction: String,
		army: Dictionary, region: String = "", observed: Dictionary = {}, detected: Variant = null) -> bool:
	if army.is_empty():
		return false
	if army["owner"] == faction:
		return true
	var at := region if region != "" else String(army["region"])
	var sight := visible_regions(data, state, faction) if observed.is_empty() else observed
	if not sight.has(at):
		return false
	if data.regions.get(at, {}).get("terrain", "") != "forest":
		return true
	# A siege or forced march exposes the column; normal travel into cover
	# does not. This is evaluated at rule boundaries, never by animation.
	if army.get("forced_march", false):
		return true
	var siege = state.get("settlements", {}).get(at, {}).get("siege")
	if siege != null and state.get("armies", {}).get(siege["besieger"], {}) == army:
		return true
	var scouts: Dictionary = forest_detection(data, state, faction) if detected == null else detected
	return scouts.has(at)


static func visible_armies(data: GameData, state: Dictionary, faction: String) -> Dictionary:
	var result := {}
	var observed := visible_regions(data, state, faction)
	var detected := forest_detection(data, state, faction)
	for id in state.get("armies", {}):
		if army_visible(data, state, faction, state["armies"][id], "", observed, detected):
			result[id] = true
	return result
