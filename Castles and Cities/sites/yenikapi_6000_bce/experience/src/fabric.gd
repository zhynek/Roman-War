extends RefCounted
## Scene-free explicit fabric lineage. No time, population or automatic upgrades.
## Dated snapshots never imply ancestry. Scenarios must name their base snapshot.
static func resolve(snapshot: Dictionary, scenario: Dictionary) -> Dictionary:
	if scenario.get("base_snapshot_id", "") != snapshot.get("snapshot_id", ""):
		return {"error": "wrong_base"}
	if scenario.get("kind", "") != "hypothetical":
		return {"error": "scenario_must_be_hypothetical"}
	var records: Dictionary = {}
	for item in snapshot.objects:
		records[item.id] = item.duplicate(true)
	var used: Dictionary = {}
	for change in scenario.get("changes", []):
		var kind: String = change.get("kind", "")
		var before: Array = change.get("before", [])
		var after: Array = change.get("after", [])
		if kind not in ["retained", "altered", "replaced", "added", "removed", "abandoned", "subdivided"]:
			return {"error": "unknown_relationship"}
		if (kind == "added" and (not before.is_empty() or after.is_empty())) or (kind != "added" and before.is_empty()):
			return {"error": "invalid_relationship"}
		for id in before:
			if not records.has(id) or used.has(id): return {"error": "missing_or_reused_predecessor"}
			used[id] = true
		if kind in ["retained", "removed", "abandoned"]:
			if not after.is_empty(): return {"error": "unexpected_successor"}
			for id in before:
				if kind != "retained":
					records[id].active = false
					records[id].revision += 1
					records[id].change = {"kind": kind, "predecessors": [id + "@" + str(int(records[id].revision) - 1)]}
			continue
		if kind == "altered" and (before.size() != 1 or after.size() != 1 or after[0].get("id") != before[0]):
			return {"error": "alteration_must_keep_identity"}
		if kind == "subdivided" and after.size() < 2: return {"error": "subdivision_needs_children"}
		if after.is_empty(): return {"error": "missing_successor"}
		var predecessors: Array = []
		for id in before:
			predecessors.append(id + "@" + str(int(records[id].revision)))
			if kind != "altered": records[id].active = false
		for item in after:
			var id: String = item.get("id", "")
			if id.is_empty() or (records.has(id) and kind != "altered"): return {"error": "identity_collision"}
			var next: Dictionary = item.duplicate(true)
			next.revision = int(records[id].revision) + 1 if kind == "altered" else 1
			next.active = true
			next.change = {"kind": kind, "predecessors": predecessors.duplicate()}
			records[id] = next
	var result: Array = []
	var ids: Array = records.keys()
	ids.sort()
	for id in ids: result.append(records[id])
	return {"objects": result, "snapshot_id": snapshot.snapshot_id, "scenario_id": scenario.get("id", "")}
