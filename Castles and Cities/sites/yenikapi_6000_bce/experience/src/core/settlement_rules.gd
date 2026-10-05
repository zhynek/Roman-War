extends RefCounted
## Deterministic hypothetical household simulation. Integer stocks; no scene or RNG.
var content: Dictionary
var balance: Dictionary
var projects: Dictionary = {}
var neighbors
const Neighbors = preload("res://src/core/neighbor_rules.gd")

func _init(config: Dictionary, tuning: Dictionary, contacts_config: Dictionary = {}) -> void:
	content = canonical(config)
	balance = canonical(tuning)
	neighbors = Neighbors.new(canonical(contacts_config),balance.get("neighbors",{}))
	for project in content.projects:
		projects[project.id] = project

func new_state() -> Dictionary:
	var state := {
		"version": 1, "rules_version": 1, "scenario_id": content.scenario_id,
		"settlement_id": content.settlement_id, "turn": 0, "phase": "village",
		"stable_seasons": 0, "town_achieved": false, "food": balance.initial_food,
		"wood": balance.initial_wood, "wellbeing": balance.initial_wellbeing,
		"cooperation": balance.initial_cooperation, "security": balance.initial_security,
		"citizens": content.initial_citizens.duplicate(true), "leaders": {},
		"completed": [], "queue": [], "plan": balance.initial_plan.duplicate(true),
		"welcome": false, "tight_rations": false, "birth_credit": 0,
		"next_person": content.initial_citizens.size() + 1, "role": "god",
		"history": [], "report": {}, "assignments": [], "contacts": {}
	}
	for role in ["steward", "watch"]:
		state.leaders[role] = {"id": content.initial_leaders[role], "since": 0}
	state.plan = normalize_plan(state, state.plan)
	return state

func ensure_state_keys(state: Dictionary) -> void:
	if not state.has("contacts"): state.contacts={}

func people(state: Dictionary, adults_only: bool = false) -> Array:
	var result: Array = []
	for person in state.citizens:
		if person.active and (not adults_only or person.age >= balance.adult_age):
			result.append(person)
	result.sort_custom(func(a, b): return a.id < b.id)
	return result

func person_by_id(state: Dictionary, id: String) -> Dictionary:
	for person in state.citizens:
		if person.id == id: return person
	return {}

func has_project(state: Dictionary, id: String) -> bool:
	for item in state.completed:
		if item.id == id: return true
	return false

func effect(state: Dictionary, key: String) -> int:
	var value: int = 0
	for item in state.completed:
		value += int(projects[item.id].effects.get(key, 0))
	return value

func capacity(state: Dictionary) -> int:
	return int(balance.base_housing) + effect(state, "housing")

func storage(state: Dictionary) -> int:
	return int(balance.base_storage) + effect(state, "storage")

func normalize_plan(state: Dictionary, requested: Dictionary) -> Dictionary:
	var remaining: int = people(state, true).size()
	var exact: bool = requested.size()==5
	var total: int = 0
	for key in ["food","timber","care","watch","building"]:
		if not whole(requested.get(key),0,2048): exact=false
		else: total+=int(requested[key])
	if exact and total==remaining: return canonical(requested)
	var plan := {"food": 0, "timber": 0, "care": 0, "watch": 0, "building": 0}
	# Protect care and food under workforce loss; no worker can work twice.
	for key in ["care", "watch", "timber", "building"]:
		plan[key] = mini(maxi(0, int(requested.get(key, 0))), maxi(0, remaining - int(balance.minimum_food_workers)))
		remaining -= int(plan[key])
	plan.food = remaining
	return plan

func suggested_plan(state: Dictionary) -> Dictionary:
	var adults: int = people(state, true).size()
	var target := {"care": int(balance.care_target), "watch": int(balance.watch_target),
		"building": int(balance.build_target) if not state.queue.is_empty() else 0,
		"timber": int(balance.timber_target)}
	# Reserve enough gathering labor for the year's average needs, including winter.
	var average_yield: float = 0.0
	for yield_ in balance.food_yields: average_yield += float(yield_) / balance.food_yields.size()
	var needed: int = ceili(float(people(state).size()) / (average_yield + effect(state, "food_yield")))
	while adults - int(target.care) - int(target.watch) - int(target.building) - int(target.timber) < needed:
		if target.timber > 0: target.timber -= 1
		elif target.building > 0: target.building -= 1
		elif target.watch > 0: target.watch -= 1
		elif target.care > 0: target.care -= 1
		else: break
	return normalize_plan(state, target)

func permitted(state: Dictionary, role: String) -> bool:
	return state.role == "god" or state.role == role

func command(state: Dictionary, action: Dictionary) -> Dictionary:
	# Validate before copying or mutating. Rejected orders preserve the complete state.
	var kind: String = action.get("kind", "")
	if kind.begins_with("neighbor_"): return neighbors.command(state,action,self)
	var next: Dictionary = state.duplicate(true)
	match kind:
		"role":
			if action.get("role") not in ["god", "steward", "watch"]: return {"error": "authority"}
			next.role = action.role
		"plan":
			var plan: Variant = action.get("plan")
			if not plan is Dictionary or plan.size() != 5: return {"error": "invalid_plan"}
			var total: int = 0
			for key in ["food", "timber", "care", "watch", "building"]:
				if not plan.has(key) or not whole(plan[key], 0, 2048): return {"error": "invalid_plan"}
				total += int(plan[key])
			if total != people(state, true).size(): return {"error": "invalid_plan"}
			if state.role == "watch":
				for key in ["timber", "care", "building"]:
					if plan[key] != state.plan[key]: return {"error": "authority"}
			if state.role == "steward" and plan.watch != state.plan.watch: return {"error": "authority"}
			next.plan = plan.duplicate(true)
		"policy":
			if not permitted(state, "steward"): return {"error": "authority"}
			if not action.get("welcome") is bool or not action.get("tight_rations") is bool: return {"error": "authority"}
			next.welcome = action.welcome
			next.tight_rations = action.tight_rations
		"commission":
			var id: String = action.get("id", "")
			if not projects.has(id): return {"error": "unknown_project"}
			var project: Dictionary = projects[id]
			if not permitted(state, project.role): return {"error": "authority"}
			if has_project(state, id): return {"error": "already_ordered"}
			for item in state.queue:
				if item.id == id: return {"error": "already_ordered"}
			if state.queue.size() >= balance.queue_limit: return {"error": "queue_full"}
			for requirement in project.requires:
				if not has_project(state, requirement): return {"error": "prerequisite"}
			if state.wood < project.wood: return {"error": "insufficient_wood"}
			next.wood -= int(project.wood)
			next.queue.append({"id": id, "progress": 0})
		"cancel":
			var found: bool = false
			for i in range(state.queue.size()):
				var item: Dictionary = state.queue[i]
				if item.id != action.get("id"): continue
				var project: Dictionary = projects[item.id]
				if not permitted(state, project.role): return {"error": "authority"}
				var refund: int = int(project.wood) * (int(project.work) - int(item.progress)) / int(project.work)
				next.wood += refund
				next.queue.remove_at(i)
				_event(next, "cancel", {"project": item.id, "wood": refund})
				found = true
				break
			if not found: return {"error": "unknown_project"}
		"appoint":
			var role: String = action.get("role", "")
			if role not in ["steward", "watch"] or not permitted(state, role): return {"error": "authority"}
			var person: Dictionary = person_by_id(next, action.get("id", ""))
			if not eligible(person) or person.id == state.leaders["watch" if role == "steward" else "steward"].id: return {"error": "invalid_candidate"}
			next.leaders[role] = {"id": person.id, "since": int(state.turn)}
			_event(next, "appointment", {"role": role, "name": person.name})
		_: return {"error": "unknown_project"}
	return {"state": next}

func forecast(state: Dictionary) -> Dictionary:
	var population: int = people(state).size()
	var plan: Dictionary = normalize_plan(state, state.plan)
	var crew:Dictionary=neighbors.crew(state,plan)
	var cargo:Dictionary=neighbors.arrivals(state,plan)
	var workers: int = int(plan.food)-int(crew.carriers) + (int(plan.building) if state.queue.is_empty() else 0)
	var gathered: int = workers * (int(balance.food_yields[int(state.turn) % 4]) + effect(state, "food_yield"))
	var used: int = ceili(population * float(balance.tight_rations_percent if state.tight_rations else balance.full_rations_percent) / 100.0) * int(balance.food_per_person)
	var spoil: int = int(state.food) * int(balance.spoil_percent) / 100
	var available: int = maxi(0,int(state.food) + gathered - spoil)
	var eaten: int = mini(used,available)
	var covered: bool = eaten >= used
	var crowded: bool = population > capacity(state)
	var overwork: bool = (int(plan.building) + int(plan.watch)) * 100 > people(state, true).size() * int(balance.overwork_limit_percent)
	var factors := {
		"wellbeing": [{"id":"base","value":int(balance.wellbeing_base)}, {"id":"care","value":int(plan.care)*int(balance.wellbeing_care)}, {"id":"food","value":int(balance.wellbeing_fed if covered else balance.wellbeing_hunger)}, {"id":"crowding","value":int(balance.wellbeing_crowded) if crowded else 0}, {"id":"ration","value":int(balance.wellbeing_tight) if state.tight_rations else 0}, {"id":"overwork","value":int(balance.overwork_cost) if overwork else 0}, {"id":"projects","value":effect(state,"wellbeing")}],
		"cooperation": [{"id":"base","value":int(balance.cooperation_base)}, {"id":"care","value":int(plan.care)*int(balance.cooperation_care)}, {"id":"food","value":0 if covered else int(balance.cooperation_hunger)}, {"id":"crowding","value":int(balance.cooperation_crowded) if crowded else 0}, {"id":"ration","value":int(balance.cooperation_tight) if state.tight_rations else 0}, {"id":"overwork","value":int(balance.overwork_cost) if overwork else 0}, {"id":"projects","value":effect(state,"cooperation")}],
		"security": [{"id":"base","value":int(balance.security_base)}, {"id":"watch","value":(int(plan.watch)-int(crew.escorts))*int(balance.security_worker)}, {"id":"leadership","value":leader_skill(state,"watch")*int(balance.security_skill)}, {"id":"projects","value":effect(state,"security")}]
	}
	var stocks: Dictionary = {}
	for key in factors:
		var total: int = 0
		for factor in factors[key]: total += int(factor.value)
		stocks[key] = move_stock(int(state[key]), clampi(total, 0, 100))
	var pressure: int = int(balance.annual_pressure[int(state.turn) % balance.annual_pressure.size()])
	var losses: int = maxi(0, int(balance.pressure_base) + pressure - int(stocks.security)) * int(balance.loss_per_shortfall) if pressure > 0 else 0
	var remaining: int = maxi(0, int(state.food) + gathered - spoil - used)
	losses = mini(losses, remaining)
	remaining += int(cargo.food)
	var overflow: int = maxi(0,remaining-losses-storage(state))
	remaining = mini(storage(state), remaining - losses)
	return {"plan":plan,"population":population,"gathered":gathered,"used":eaten,"unfed":used-eaten,"overflow":overflow,"spoil":spoil,"losses":losses,"food":remaining,"food_delta":remaining-int(state.food),"covered":covered,"stocks":stocks,"factors":factors,"crew":crew,"cargo":cargo,"wood":int(plan.timber)*int(balance.timber_yield)+int(cargo.wood),"work":int(plan.building)*int(balance.work_yield)+leader_skill(state,"steward")/int(balance.steward_work_divisor) if plan.building>0 and not state.queue.is_empty() else 0}

func move_stock(current: int, target: int) -> int:
	return current + clampi(target - current, -int(balance.stock_step), int(balance.stock_step))

func leader_skill(state: Dictionary, role: String) -> int:
	var person: Dictionary = person_by_id(state, state.leaders[role].id)
	return int(person.get(role, 0)) if person.get("active", false) else 0

func eligible(person: Dictionary) -> bool:
	return not person.is_empty() and person.active and person.age >= balance.adult_age and person.age < balance.retirement_age

func advance(state: Dictionary) -> Dictionary:
	if state.turn >= balance.max_turns: return {"error":"horizon"}
	var next: Dictionary = state.duplicate(true)
	var f: Dictionary = forecast(state)
	next.report = f
	next.food = int(f.food)
	next.wood += int(f.wood)
	for key in f.stocks: next[key] = int(f.stocks[key])
	next.assignments = assignments(state, f.plan)
	var work: int = int(f.work)
	while work > 0 and not next.queue.is_empty():
		var item: Dictionary = next.queue[0]
		var amount: int = mini(work, int(projects[item.id].work) - int(item.progress))
		item.progress += amount
		work -= amount
		if item.progress < projects[item.id].work: break
		next.completed.append({"id":item.id,"turn":int(state.turn)})
		_event(next,"completed",{"project":item.id})
		next.queue.pop_front()
	if f.losses > 0: _event(next,"loss",{"count":int(f.losses)})
	for person in next.citizens:
		if not person.active: continue
		person.age += 1
		if person.age >= balance.death_age:
			person.active = false
			_event(next,"death",{"name":person.name})
	if not f.covered:
		var departed: int = 0
		var candidates: Array = people(next)
		candidates.reverse()
		for person in candidates:
			if departed >= balance.hunger_departures or people(next).size() <= balance.minimum_population: break
			if person.age >= balance.adult_age and people(next,true).size() <= balance.minimum_population: continue
			person.active = false
			departed += 1
		if departed > 0: _event(next,"departure",{"count":departed})
	if f.covered and people(next,true).size() >= balance.minimum_population and next.wellbeing >= balance.birth_min_wellbeing and people(next).size() < capacity(next):
		next.birth_credit += people(next).size() * int(balance.birth_credit_per_person)
		if next.birth_credit >= balance.birth_credit_threshold:
			next.birth_credit -= int(balance.birth_credit_threshold)
			_add_person(next,0)
			_event(next,"birth",{"count":1})
	if int(state.turn)%4 == int(balance.migration_season) and next.welcome and migration_supported(next):
		for i in range(int(balance.migration_size)):
			_add_person(next,int(balance.adult_age)+int(next.next_person)%int(balance.arrival_age_spread) if i<int(balance.migration_adults) else int(balance.arrival_child_age))
		_event(next,"arrival",{"count":int(balance.migration_size)})
	neighbors.advance(next,state,self)
	next.turn += 1
	_succession(next)
	next.plan = normalize_plan(next,next.plan)
	var qualifies: bool = town_conditions(next)
	next.stable_seasons = int(next.stable_seasons)+1 if qualifies else 0
	if next.stable_seasons >= balance.town_sustained_seasons:
		if next.phase != "town": _event(next,"town",{})
		next.phase = "town"
		next.town_achieved = true
	elif not qualifies and next.phase == "town":
		next.phase = "village"
		_event(next,"contracted",{})
	_event(next,"season",{"turn":int(next.turn),"food":int(next.food),"population":people(next).size(),"security":int(next.security)})
	return {"state":next}

func migration_supported(state: Dictionary) -> bool:
	var count: int = people(state).size()
	return capacity(state)-count >= balance.migration_size and state.food >= (count+int(balance.migration_size))*int(balance.migration_reserve_seasons) and state.wellbeing >= balance.migration_min_wellbeing and state.cooperation >= balance.migration_min_cooperation

func town_conditions(state: Dictionary) -> bool:
	for id in balance.town_required_projects:
		if not has_project(state,id): return false
	return people(state).size() >= balance.town_population and capacity(state)/int(balance.people_per_dwelling) >= balance.town_dwellings and state.food >= people(state).size()*int(balance.town_reserve_seasons) and state.wellbeing >= balance.town_wellbeing and state.cooperation >= balance.town_cooperation and state.security >= balance.town_security

func _add_person(state: Dictionary, age: int) -> void:
	var household_id: String = ""
	for household in content.households:
		if household.requires!="" and not has_project(state,household.requires): continue
		var occupants: int = 0
		for resident in people(state):
			if resident.household==household.id: occupants+=1
		if occupants < balance.people_per_dwelling: household_id=household.id;break
	assert(not household_id.is_empty())
	var serial: int = int(state.next_person)
	state.next_person += 1
	state.citizens.append({"id":"citizen_%04d"%serial,"name":content.name_pool[serial%content.name_pool.size()],"age":age,"steward":int(balance.skill_base)+serial%int(balance.skill_span),"watch":int(balance.skill_base)+(serial*3)%int(balance.skill_span),"household":household_id,"active":true})

func _succession(state: Dictionary) -> void:
	for role in ["steward","watch"]:
		var current: Dictionary = person_by_id(state,state.leaders[role].id)
		if eligible(current) and int(state.turn)-int(state.leaders[role].since) < balance.term_seasons: continue
		var candidates: Array = []
		var other: String = state.leaders["watch" if role=="steward" else "steward"].id
		for person in people(state,true):
			if eligible(person) and person.id != other and person.id != current.get("id",""): candidates.append(person)
		candidates.sort_custom(func(a,b): return a[role]>b[role] if a[role]!=b[role] else a.id<b.id)
		if candidates.is_empty() and eligible(current): candidates.append(current)
		var successor: Dictionary = candidates[0] if not candidates.is_empty() else {}
		state.leaders[role] = {"id":successor.get("id",""),"since":int(state.turn)}
		_event(state,"succession",{"role":role,"name":successor.get("name","—"),"previous":current.get("name","—")})

func assignments(state: Dictionary, plan: Dictionary) -> Array:
	var adults: Array = people(state,true)
	var result: Array = []
	var index: int = 0
	for job in ["food","timber","care","watch","building"]:
		for i in range(int(plan[job])):
			var person: Dictionary = adults[(index+int(state.turn))%adults.size()]
			var destination: Array = content.job_sites[job]
			var actual: String = job
			if job == "building":
				if not state.queue.is_empty(): destination = projects[state.queue[0].id].at
				else: destination = content.job_sites.food; actual = "food"
			var home: Array = content.home_sites[0]
			for household in content.households:
				if household.id==person.household: home=household.at;break
			result.append({"id":person.id,"job":actual,"from":home.duplicate(),"to":destination.duplicate()})
			index += 1
	var crew:Dictionary=neighbors.crew(state,plan)
	for task in result:
		if (task.job=="food" and crew.carriers>0) or (task.job=="watch" and crew.escorts>0):
			if task.job=="food":crew.carriers-=1
			else:crew.escorts-=1
			task.job="travel";task.to=neighbors.content.meeting_at.duplicate()
	return result

func _event(state: Dictionary, kind: String, params: Dictionary) -> void:
	state.history.append({"turn":int(state.turn),"kind":kind,"params":params})

static func whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=low and value<=high

func validate_state(value: Variant) -> bool:
	if not value is Dictionary: return false
	var state: Dictionary = value
	for key in new_state().keys():
		if not state.has(key): return false
	if not whole(state.version,1,1) or not whole(state.rules_version,1,1): return false
	if not state.scenario_id is String or not state.settlement_id is String: return false
	if state.version != 1 or state.rules_version != 1 or state.scenario_id != content.scenario_id or state.settlement_id != content.settlement_id: return false
	if state.role not in ["god","steward","watch"] or state.phase not in ["village","town"]: return false
	for key in ["welcome","tight_rations","town_achieved"]:
		if not state[key] is bool: return false
	for key in ["turn","food","wood","birth_credit","next_person","stable_seasons"]:
		if not whole(state[key],0,1000000): return false
	if state.turn > balance.max_turns: return false
	for key in ["wellbeing","cooperation","security"]:
		if not whole(state[key],0,100): return false
	if not state.citizens is Array or state.citizens.size()>2048 or state.citizens.is_empty(): return false
	var ids: Dictionary = {}
	var max_serial: int = 0
	for person in state.citizens:
		if not person is Dictionary: return false
		for key in ["id","name","household"]:
			if not person.get(key) is String or person[key].length()>100: return false
		if not person.id.begins_with("citizen_") or not person.id.trim_prefix("citizen_").is_valid_int() or ids.has(person.id): return false
		ids[person.id]=true;max_serial=maxi(max_serial,int(person.id.trim_prefix("citizen_")))
		if not person.get("active") is bool or not whole(person.get("age"),0,2000) or not whole(person.get("steward"),0,5) or not whole(person.get("watch"),0,5): return false
	if state.next_person<=max_serial: return false
	var households: Dictionary={}
	for household in content.households: households[household.id]=household
	for person in state.citizens:
		if not households.has(person.household): return false
	if not state.leaders is Dictionary or state.leaders.size()!=2: return false
	for role in ["steward","watch"]:
		var leader: Variant = state.leaders.get(role)
		if not leader is Dictionary or not leader.get("id") is String or (leader.id!="" and not ids.has(leader.id)) or not whole(leader.get("since"),0,int(state.turn)): return false
	if state.leaders.steward.id!="" and state.leaders.steward.id==state.leaders.watch.id: return false
	if not state.completed is Array or not state.queue is Array or state.queue.size()>balance.queue_limit: return false
	var ordered: Dictionary = {}
	for item in state.completed:
		if not item is Dictionary or not item.get("id") is String or not projects.has(item.id) or ordered.has(item.id) or not whole(item.get("turn"),0,int(state.turn)): return false
		for requirement in projects[item.id].requires:
			if not ordered.has(requirement): return false
		ordered[item.id]=true
	for item in state.queue:
		if not item is Dictionary or not item.get("id") is String or not projects.has(item.id) or ordered.has(item.id): return false
		if not whole(item.get("progress"),0,int(projects[item.id].work)-1): return false
		for requirement in projects[item.id].requires:
			if not has_project(state,requirement): return false
		ordered[item.id]=true
	if not neighbors.validate(state,self): return false
	if not state.plan is Dictionary: return false
	if command(state,{"kind":"plan","plan":state.plan}).has("error"): return false
	if not state.report is Dictionary or not state.assignments is Array or not state.history is Array or state.history.size()>20000: return false
	for task in state.assignments:
		if not task is Dictionary or not ids.has(task.get("id","")) or task.get("job") not in ["food","timber","care","watch","building","travel"]: return false
		for key in ["from","to"]:
			if not task.get(key) is Array or task[key].size()!=2: return false
			for number in task[key]:
				if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number))>170: return false
	for event in state.history:
		if not event is Dictionary or not whole(event.get("turn"),0,int(state.turn)) or not event.get("kind") is String or not event.get("params") is Dictionary: return false
	return true

static func canonical(value: Variant) -> Variant:
	# JSON parses all numbers as doubles. Canonicalize integral state before replay.
	if value is float and is_finite(value) and value==floorf(value): return int(value)
	if value is Array:
		var result: Array=[]
		for item in value: result.append(canonical(item))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key in value: result[key]=canonical(value[key])
		return result
	return value
