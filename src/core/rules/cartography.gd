class_name CartographyRules
## Geographic reports persist; current military observation remains separate.
## Access is directional, revocable on war, and never shares live enemy rosters.

static func known_regions(data: GameData, state: Dictionary, faction: String) -> Dictionary:
	var known: Dictionary = state.get("cartography", {}).get(faction, {}).duplicate()
	known.merge(VisibilityRules.visible_regions(data, state, faction), true)
	return known

static func record_reports(data: GameData, state: Dictionary) -> void:
	if not state.has("cartography"):
		state["cartography"] = {}
	var ids: Array = state["factions"].keys()
	ids.sort()
	var own_reports := {}
	for faction in ids:
		var chart: Dictionary = state["cartography"].get(faction, {})
		state["cartography"][faction] = chart
		var observed := VisibilityRules.visible_regions(data, state, faction)
		var regions: Array = observed.keys()
		regions.sort()
		for region in regions:
			chart[region] = int(state.get("turn", 0))
		# Sharing only directly observed geography avoids transitive treaties
		# revealing another court's maps without that court's consent.
		own_reports[faction] = observed
	for grantor in ids:
		for recipient in state.get("map_access", {}).get(grantor, []):
			if not state["factions"].has(recipient) or DiplomacyRules.at_war(state, grantor, recipient):
				continue
			var regions: Array = own_reports[grantor].keys()
			regions.sort()
			for region in regions:
				state["cartography"][recipient][region] = int(state.get("turn", 0))

static func grant(data: GameData, state: Dictionary, grantor: String, recipient: String) -> void:
	if not state.has("map_access"):
		state["map_access"] = {}
	var recipients: Array = state["map_access"].get(grantor, []).duplicate()
	if not recipients.has(recipient):
		recipients.append(recipient)
		recipients.sort()
	state["map_access"][grantor] = recipients
	# The signed agreement includes the existing atlas; later updates are
	# direct reports only. A bought map cannot be unlearned after a rupture.
	record_reports(data, state)
	var chart := known_regions(data, state, grantor)
	var regions: Array = chart.keys()
	regions.sort()
	for region in regions:
		state["cartography"][recipient][region] = int(state.get("turn", 0))

static func access_value(data: GameData, state: Dictionary, grantor: String, recipient: String) -> float:
	if state.get("map_access", {}).get(grantor, []).has(recipient):
		return 0.0
	var their_chart := known_regions(data, state, grantor)
	var our_chart := known_regions(data, state, recipient)
	var new_regions := 0
	for region in their_chart:
		if not our_chart.has(region):
			new_regions += 1
	var rules: Dictionary = data.balance.get("terrain_routes", {})
	return float(rules.get("map_access_base_value", 0.0)) + new_regions * float(rules.get("map_access_value_per_region", 0.0))
