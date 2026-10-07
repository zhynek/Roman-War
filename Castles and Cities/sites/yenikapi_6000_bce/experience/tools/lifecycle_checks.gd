extends SceneTree
const Driver = preload("res://tools/lifecycle_driver.gd")
const Saves = preload("res://src/campaign_save.gd")
const FabricProjection = preload("res://src/core/fabric_projection.gd")
var checks: int = 0
var failures: int = 0
var rules
var out_dir: String = "/tmp/yenikapi-lifecycle-checks"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): out_dir = arg.trim_prefix("out_dir=")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", message)

func command(s: Dictionary, action: Dictionary) -> Dictionary:
	var result: Dictionary = rules.command(s, action)
	check(result.has("state"), JSON.stringify(action) + " " + str(result.get("error", "")))
	return result.get("state", s)

func saved(s: Dictionary, name: String) -> Dictionary:
	var path: String = out_dir.path_join(name + ".json")
	check(Saves.write(path, s, rules), "validated save " + name)
	var result: Dictionary = Saves.read(path, rules)
	check(result == s, "exact save readback " + name)
	return result

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	rules = Driver.rules()
	var initial: Dictionary = Driver.initial(rules)
	check(rules.validate_state(initial), "initial living state")
	var old: Dictionary = initial.duplicate(true); old.erase("lifecycle")
	var old_path: String = out_dir.path_join("legacy.json")
	FileAccess.open(old_path, FileAccess.WRITE).store_string(JSON.stringify({"format": "yenikapi_seasons", "version": 6, "state": old}))
	check(Saves.read(old_path, rules) == initial, "legacy wrapper backfills inactive lifecycle only")
	check(rules.command(rules.new_state(), {"kind": "lifecycle_begin"}).get("error") == "lifecycle_assets", "manual save names missing prerequisite")
	var watch: Dictionary = command(initial, {"kind": "role", "role": "watch"})
	check(rules.command(watch, {"kind": "lifecycle_begin"}).get("error") == "authority", "adoption requires God authority")
	var adopted: Dictionary = command(initial, {"kind": "lifecycle_begin"})
	for key in ["food", "wood", "queue", "completed", "citizens", "households", "assets", "land", "living", "contacts", "leaders"]:
		check(adopted[key] == initial[key], "adoption preserves " + key)
	var pure: Dictionary = adopted.duplicate(true)
	for i in range(10):
		rules.lifecycle.status(adopted, rules)
		rules.quote(adopted, {"kind": "commission", "id": "lifecycle_assembly"})
		rules.forecast(adopted)
	check(adopted == pure, "all queries leave authoritative state unchanged")
	check(not rules.command(adopted, {"kind": "commission", "id": "lifecycle_store"}).has("state"), "future upgrade gated before civic completion")
	check(adopted == pure, "rejected command immutable")
	var outcomes: Array = []
	for compact in [true, false]:
		var s: Dictionary = initial.duplicate(true)
		var replay: Dictionary = initial.duplicate(true)
		var milestones: Dictionary = {}
		var transcript: Array = []
		var captured: Dictionary = {}
		for season in range(80):
			for order in range(24):
				var action: Dictionary = Driver.next_action(rules, s, compact)
				if action.is_empty(): break
				transcript.append({"turn": s.turn, "action": action.duplicate(true)})
				var before: Dictionary = s.duplicate(true)
				if action.get("kind") == "commission" and String(action.id).begins_with("lifecycle_"):
					var spend_all: Dictionary = s.duplicate(true); spend_all.wood = int(rules.projects[action.id].wood)
					check(rules.quote(spend_all, action).get("error") == "lifecycle_reserves", "payment must leave fuel reserve")
					var foreign_role: Dictionary = s.duplicate(true); foreign_role.role = "watch"
					check(rules.command(foreign_role, action).get("error") == "authority", "watch cannot authorize civic commission")
				s = command(s, action); replay = command(replay, action)
				check(s == replay, "command lockstep")
				if action.get("kind") == "commission" and String(action.id).begins_with("lifecycle_"):
					check(s.wood == before.wood - int(rules.projects[action.id].wood), "one immediate material payment")
					check(s.food == before.food, "commission does not refill or duplicate food bills")
					saved(s, ("compact" if compact else "outward") + "-" + action.id + "-commission")
			check(rules.validate_state(s), "valid pre-season " + str(season))
			var forecast: Dictionary = rules.forecast(s)
			check(forecast.unfed == 0, "strategy protects meals " + str(compact) + " " + str(season))
			var ids: Array = []
			for task in rules.assignments(s, forecast.plan):
				check(task.id not in ids, "one assignment per adult"); ids.append(task.id)
				check(rules.person_by_id(s, task.id).age >= rules.balance.adult_age, "children never crew projects")
			var before: Dictionary = s.duplicate(true)
			var advanced: Dictionary = rules.advance(s)
			check(advanced.has("state"), "season resolves " + str(advanced.get("error", "")))
			if not advanced.has("state"): finish(); return
			s = advanced.state; replay = rules.advance(replay).state
			transcript.append({"turn": before.turn, "action": {"kind": "advance"}})
			check(s == replay, "season replay " + str(season))
			check(s.food == forecast.food, "forecast matches actual provisions")
			check(rules.validate_state(s), "valid closing state " + str(season))
			for item in s.completed:
				if String(item.id).begins_with("lifecycle_") and not milestones.has(item.id):
					milestones[item.id] = s.turn
					if item.id == "lifecycle_assembly":
						check(rules.lifecycle.stage(s, rules) == "village_established", "paid completion grants civic stage")
						check(s.lifecycle.readiness.seasons == 0, "promotion resets readiness")
						check(not rules.has_project(s, "lifecycle_store") and not rules.has_project(s, "lifecycle_workroom"), "civic upgrade grants no free buildings")
						replay = saved(replay, ("compact" if compact else "outward") + "-promoted")
			for item in s.queue:
				if String(item.id).begins_with("lifecycle_") and item.progress > 0 and not captured.has(item.id):
					captured[item.id] = true
					partial_contract(s, item.id)
			if season in [15, 39, 60]: replay = saved(replay, ("compact" if compact else "outward") + "-season-" + str(season))
		check(Driver.finished(rules, s), "all paid lifecycle projects reachable " + str(compact))
		check(rules.command(s, {"kind": "commission", "id": "lifecycle_store"}).get("error") == "already_ordered", "completed upgrade cannot charge or grant twice")
		var fabric: Dictionary = FabricProjection.resolve(rules.base_snapshot, s.completed, rules.projects, rules.content.scenario_id)
		check(not fabric.has("error"), "final sequential fabric resolves")
		if not fabric.has("error"):
			for id in ["yk_store_01", "yk_house_06"]:
				var object: Array = fabric.objects.filter(func(o): return o.id == id)
				check(object.size() == 1 and object[0].revision == 3, "same building reaches revision 3 " + id)
		check(rules.effect(s, "storage") == int(rules.projects.shared_store.effects.storage) + int(rules.projects.lifecycle_store.effects.storage), "storage upgrade increments once")
		var stressed: Dictionary = s.duplicate(true); stressed.food = 0
		var recovered: Dictionary = rules.advance(stressed).get("state", {})
		check(not recovered.is_empty() and rules.lifecycle.stage(recovered, rules) == rules.lifecycle.stage(s, rules), "shortage preserves civic achievement")
		check(recovered.get("completed", []) == s.completed, "shortage preserves completed physical history")
		var recipe: Dictionary = {"profile": rules.lifecycle.content.profile, "definition_hash": rules.lifecycle.definition_hash, "compact": compact, "commands": transcript, "milestones": milestones, "final_sha256": JSON.stringify(rules.canonical(s)).sha256_text()}
		FileAccess.open(out_dir.path_join("compact-recipe.json" if compact else "outward-recipe.json"), FileAccess.WRITE).store_string(JSON.stringify(recipe, "  "))
		outcomes.append({"compact": compact, "milestones": milestones, "food": s.food, "wood": s.wood, "population": rules.people(s).size(), "work_places": rules.land.totals(s, rules).work})
		malformed(s)
	check(outcomes[0].work_places != outcomes[1].work_places, "earlier spatial tradeoffs remain distinct")
	var legacy: Dictionary = preload("res://tools/land_driver.gd").at_season(rules, true, 28)
	check(legacy.town_achieved, "legacy town fixture earned through commands")
	legacy = command(legacy, {"kind": "living_begin"})
	var recognized: Dictionary = command(legacy, {"kind": "lifecycle_begin"})
	check(rules.lifecycle.stage(recognized, rules) == "town", "legacy town recognition carries forward")
	check(recognized.completed == legacy.completed and not rules.has_project(recognized, "lifecycle_assembly"), "recognition invents no hall")
	saved(recognized, "recognized-town")
	extension_continuity()
	print("LIFECYCLE STRATEGIES ", JSON.stringify(outcomes))
	FileAccess.open(out_dir.path_join("strategies.json"), FileAccess.WRITE).store_string(JSON.stringify(outcomes, "  "))
	finish()

func extension_continuity() -> void:
	var neighbors = preload("res://tools/neighbor_driver.gd")
	var s: Dictionary = neighbors.orders(rules, neighbors.foundation(rules))
	check(not s.contacts.mission.is_empty(), "real contact escrow fixture")
	for kind in ["asset_begin", "land_begin", "living_begin"]: s = command(s, {"kind": kind})
	var before: Dictionary = s.duplicate(true)
	s = command(s, {"kind": "lifecycle_begin"})
	check(s.contacts == before.contacts and s.queue == before.queue, "lifecycle adoption preserves active cargo and contracts")
	var replay: Dictionary = saved(s, "active-contact")
	for season in range(8):
		s = rules.advance(s).state; replay = rules.advance(replay).state
		check(s == replay and rules.validate_state(s), "contact escrow and arrival replay with lifecycle")
	var incidents = preload("res://tools/incident_driver.gd")
	s = incidents.at_season(rules, 5, "attentive")
	before = s.duplicate(true)
	s = command(s, {"kind": "lifecycle_begin"})
	check(s.incidents == before.incidents, "adoption preserves warning and preparedness")
	replay = saved(s, "active-incident")
	for season in range(24):
		s = incidents.orders(rules, s, "attentive"); replay = incidents.orders(rules, replay, "attentive")
		var result: Dictionary = rules.advance(s)
		check(result.has("state"), "incident resolution accepts lifecycle state")
		if not result.has("state"): return
		s = result.state; replay = rules.advance(replay).state
		check(s == replay and rules.validate_state(s), "warning response and recovery replay with lifecycle")

func partial_contract(s: Dictionary, id: String) -> void:
	var metadata: Dictionary = s.assets.initiatives[id]
	var pause := {"kind": "asset_project", "id": id, "priority": metadata.priority, "crew": metadata.crew, "paused": true}
	var paused: Dictionary = command(s, pause)
	var next: Dictionary = rules.advance(paused).state
	var queue: Array = next.queue.filter(func(q): return q.id == id)
	var old: Dictionary = s.queue.filter(func(q): return q.id == id)[0]
	check(queue.size() == 1 and queue[0].progress == old.progress, "pause retains paid progress " + id)
	saved(paused, "paused-" + id)
	var cancelled: Dictionary = command(s, {"kind": "cancel", "id": id})
	var refund: int = int(rules.projects[id].wood) * (int(rules.projects[id].work) - int(old.progress)) / int(rules.projects[id].work)
	check(cancelled.wood == s.wood + refund, "cancel refunds only unused material " + id)
	check(cancelled.completed == s.completed, "cancel retains earlier building revisions")
	check(rules.validate_state(cancelled), "cancelled state valid")

func malformed(s: Dictionary) -> void:
	for field in ["clock", "recognition", "revision", "progress", "params"]:
		var bad: Dictionary = s.duplicate(true)
		match field:
			"clock": bad.lifecycle.readiness.last_turn = s.turn + 1
			"recognition": bad.lifecycle.recognition = "huge_city"
			"revision": bad.lifecycle.definition_hash = "changed"
			"progress": bad.lifecycle.readiness.seasons = 999
			"params":
				for event in bad.history:
					if event.kind == "lifecycle_adopted": event.params = 3
		check(not rules.validate_state(bad), "reject malformed lifecycle " + field)

func finish() -> void:
	print("LIFECYCLE CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
