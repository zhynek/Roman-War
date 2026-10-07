extends RefCounted
## Pure replay of the authoritative completion ledger. Generated scene objects
## and meshes are never saved. Each project is one atomic fabric transaction.
const Fabric = preload("res://src/fabric.gd")

static func resolve(base: Dictionary, completed: Array, projects: Dictionary, scenario_id: String) -> Dictionary:
	if base.is_empty(): return {"error": "missing_base_snapshot"}
	var current: Dictionary = base.duplicate(true)
	var used: Dictionary = {}
	var seen: Dictionary = {}
	var lineage: Array = []
	for entry in completed:
		if not entry is Dictionary or not entry.get("id") is String or not projects.has(entry.id) or seen.has(entry.id):
			return {"error": "invalid_project_ledger"}
		var project: Dictionary = projects[entry.id]
		var strict: bool = project.get("lifecycle", false)
		# Legacy changes never had revision contracts. Do not make a formerly
		# conflicting legacy ledger valid simply by introducing ordered replay.
		for change in project.get("changes", []):
			for id in change.get("before", []):
				if not strict and used.has(id): return {"error": "missing_or_reused_predecessor"}
		var next: Dictionary = _transaction(current, project, scenario_id)
		if next.has("error"): return next
		for change in project.get("changes", []):
			for id in change.get("before", []): used[id] = true
			lineage.append({"project_id": entry.id, "kind": change.kind,
				"expected_revisions": change.get("expected_revisions", {}).duplicate(true),
				"before": change.before.duplicate(), "after": _successors(next.objects, change)})
		seen[entry.id] = true
		current.objects = next.objects
	# Fabric.resolve sorts even an untouched snapshot. Keep that legacy order.
	var result: Dictionary = Fabric.resolve(current, {"id": scenario_id, "kind": "hypothetical", "base_snapshot_id": base.snapshot_id, "changes": []})
	if not result.has("error"): result.lineage = lineage
	return result

static func pending(base: Dictionary, state: Dictionary, projects: Dictionary, scenario_id: String, project_id: String = "") -> Dictionary:
	var resolved: Dictionary = resolve(base, state.get("completed", []), projects, scenario_id)
	if resolved.has("error"): return resolved
	var current: Dictionary = base.duplicate(true)
	current.objects = resolved.objects
	var queued: Array = state.get("queue", []).duplicate(true)
	if not project_id.is_empty(): queued.append({"id": project_id})
	var claimed: Dictionary = {}
	var seen: Dictionary = {}
	for entry in state.get("completed", []): seen[entry.id] = true
	for entry in queued:
		if not entry is Dictionary or not entry.get("id") is String or not projects.has(entry.id) or seen.has(entry.id):
			return {"error": "invalid_project_ledger"}
		seen[entry.id] = true
		var project: Dictionary = projects[entry.id]
		# Queued projects cannot borrow each other's future revisions. Existing
		# prerequisites require completed work; every candidate sees that state.
		var candidate: Dictionary = _transaction(current, project, scenario_id)
		if candidate.has("error"): return candidate
		var local_claims: Dictionary = {}
		for change in project.get("changes", []):
			for id in change.get("before", []): local_claims[id] = true
			for item in change.get("after", []): local_claims[item.id] = true
		for id in local_claims:
			if claimed.has(id): return {"error": "fabric_reserved"}
			claimed[id] = entry.id
	return resolved

static func _transaction(base: Dictionary, project: Dictionary, scenario_id: String) -> Dictionary:
	return Fabric.resolve(base, {"id": scenario_id, "kind": "hypothetical", "base_snapshot_id": base.snapshot_id,
		"project_id": project.id, "require_expected_revisions": project.get("lifecycle", false), "changes": project.get("changes", [])})

static func _successors(objects: Array, change: Dictionary) -> Array:
	var ids: Array = []
	for item in change.get("after", []): ids.append(item.id)
	if ids.is_empty(): ids.append_array(change.get("before", []))
	var result: Array = []
	for item in objects:
		if item.id in ids: result.append(item.id + "@" + str(int(item.revision)))
	return result
