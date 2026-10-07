extends RefCounted
## Reproducible QA strategy. Every state change uses an ordinary public command.
const Rules = preload("res://src/core/settlement_rules.gd")
const LivingDriver = preload("res://tools/living_driver.gd")

static func read(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + id + ".json"))

static func rules():
	return Rules.new(read("governance"), read("balance"), read("neighbors"), read("households"), read("assets"), read("land"), read("living"), read("incidents"), read("lifecycle"), read("settlement"))

static func initial(r) -> Dictionary:
	return LivingDriver.initial(r)

static func finished(r, s: Dictionary) -> bool:
	return r.has_project(s, "lifecycle_assembly") and r.has_project(s, "lifecycle_store") and r.has_project(s, "lifecycle_workroom")

static func next_action(r, s: Dictionary, compact: bool = true) -> Dictionary:
	if not r.lifecycle.active(s): return {"kind": "lifecycle_begin"}
	if int(s.assets.reserve) != 2: return {"kind": "asset_principle", "id": "reserve", "value": 1}
	if int(s.assets.watch) != 1: return {"kind": "asset_principle", "id": "watch", "value": 1}
	if not s.welcome: return {"kind": "asset_principle", "id": "welcome", "value": 1}
	var shaping: int = 0
	for experience in s.living.experience.values(): shaping = maxi(shaping, int(experience.shaping))
	var preparation: int = 1 if shaping < int(r.lifecycle.balance.readiness.shaping) else 0
	if s.living.prepare != preparation: return {"kind": "living_order", "id": "prepare", "value": preparation}
	var projects: Array = ["land_cultivate", "shared_store", "watch_shelter", "care_shelter"]
	projects.append_array(["land_adapt_workroom", "land_court_home", "land_hearth_home"] if compact else ["land_outer_access", "land_outer_west", "land_outer_east", "land_adapt_workroom"])
	projects.append_array(["council_ground", "refuge_screen", "lifecycle_assembly", "lifecycle_store", "lifecycle_workroom"])
	for id in projects:
		if r.has_project(s, id): continue
		if s.queue.is_empty():
			var action := {"kind": "commission", "id": id}
			if not r.quote(s, action).has("error"): return action
		return {}
	return {}

static func orders(r, input: Dictionary, compact: bool = true) -> Dictionary:
	var s: Dictionary = input
	for i in range(24):
		var action := next_action(r, s, compact)
		if action.is_empty(): return s
		var result: Dictionary = r.command(s, action)
		if not result.has("state"): return s
		s = result.state
	return s

static func at_season(r, compact: bool, seasons: int) -> Dictionary:
	var s := initial(r)
	for i in range(seasons): s = r.advance(orders(r, s, compact)).state
	return s

static func trace(r, compact: bool = true, seasons: int = 80) -> Dictionary:
	var s := initial(r)
	var commands: Array = []
	var milestones: Dictionary = {}
	for season in range(seasons):
		for i in range(24):
			var action := next_action(r, s, compact)
			if action.is_empty(): break
			var result: Dictionary = r.command(s, action)
			if not result.has("state"): return {"error": result.get("error", "command"), "action": action, "state": s}
			commands.append({"turn": s.turn, "action": action.duplicate(true)})
			s = result.state
		commands.append({"turn": s.turn, "action": {"kind": "advance"}})
		s = r.advance(s).state
		for item in s.completed:
			if String(item.id).begins_with("lifecycle_") and not milestones.has(item.id): milestones[item.id] = s.turn
	return {"state": s, "commands": commands, "milestones": milestones}
