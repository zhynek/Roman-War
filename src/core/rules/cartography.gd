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
	if not state.has("settlement_memory"):
		state["settlement_memory"] = {}
	var ids: Array = state["factions"].keys()
	ids.sort()
	var own_reports := {}
	var snapshots := {}
	for faction in ids:
		var chart: Dictionary = state["cartography"].get(faction, {})
		state["cartography"][faction] = chart
		var memory: Dictionary = state["settlement_memory"].get(faction, {})
		state["settlement_memory"][faction] = memory
		var observed := VisibilityRules.visible_regions(data, state, faction)
		var regions: Array = observed.keys()
		regions.sort()
		for region in regions:
			chart[region] = int(state.get("turn", 0))
			if not snapshots.has(region):
				snapshots[region] = _snapshot(data, state, region)
			var report: Dictionary = snapshots[region]
			if not report.is_empty():
				memory[region] = report.duplicate(true)
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

static func settlement_report(data: GameData, state: Dictionary, faction: String,
		region: String, observed: Variant = null) -> Dictionary:
	## Detached public architecture only. Looking, zooming and loading a panel
	## never refresh intelligence. Geography bought by treaty is not live sight.
	var sight: Dictionary = VisibilityRules.visible_regions(data, state, faction) if observed == null else observed
	var current := sight.has(region)
	var report: Dictionary = _snapshot(data, state, region) if current else state.get("settlement_memory", {}).get(faction, {}).get(region, {}).duplicate(true)
	if not report.is_empty():
		report["observed"] = current
	return report

static func _snapshot(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var settlement: Dictionary = state.get("settlements", {}).get(region, {})
	if settlement.is_empty():
		return {}
	var buildings: Array = []
	var chains: Array = settlement.get("buildings", {}).keys()
	chains.sort()
	for chain in chains:
		var levels: Array = data.chains.get(chain, {}).get("levels", [])
		var tier := mini(int(settlement["buildings"][chain]), levels.size())
		if tier > 0:
			buildings.append(String(levels[tier - 1]["id"]))
	var post: Dictionary = state.get("watchposts", {}).get(region, {})
	var watchpost := {}
	if ReconRules.post_active(state, region, post):
		watchpost = {"owner": String(post["owner"]), "level": int(post["level"])}
	# Only the working project has scaffolding. Later queue entries are plans,
	# not visible construction and must never appear in an architectural survey.
	var construction: Array = []
	var queue: Array = settlement.get("construction_queue", [])
	if not queue.is_empty():
		var chain := String(queue[0]["chain"])
		var levels: Array = data.chains.get(chain, {}).get("levels", [])
		var tier := int(settlement.get("buildings", {}).get(chain, 0))
		if tier >= 0 and tier < levels.size():
			construction.append(String(levels[tier]["id"]))
	return {"owner": String(settlement["owner"]),
		"level": SettlementRules.settlement_level(data, settlement),
		"population": int(settlement["population"]), "buildings": buildings,
		"port": PortRules.snapshot(data, state, region), "watchpost": watchpost, "construction": construction, "turn": int(state.get("turn", 0))}

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
