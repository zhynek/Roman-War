extends RefCounted
## Deterministic hypothetical household simulation. Integer stocks; no scene or RNG.
var content: Dictionary
var balance: Dictionary
var projects: Dictionary = {}
var neighbors
var households
var assets
var land
var living
var incidents
const Incidents=preload("res://src/core/incident_rules.gd")
const Living=preload("res://src/core/living_rules.gd")
const Land = preload("res://src/core/land_rules.gd")
const Assets = preload("res://src/core/asset_rules.gd")
const Households = preload("res://src/core/household_rules.gd")
const Neighbors = preload("res://src/core/neighbor_rules.gd")

func _init(config: Dictionary, tuning: Dictionary, contacts_config: Dictionary = {}, household_config: Dictionary = {}, asset_config: Dictionary = {}, land_config: Dictionary = {}, living_config: Dictionary = {}, incident_config: Dictionary = {}) -> void:
	content = canonical(config)
	balance = canonical(tuning)
	incidents=Incidents.new(canonical(incident_config),balance.get("incidents",{}))
	for project in incidents.content.get("projects",[]):
		var item: Dictionary=project.duplicate(true);item.erase("blanks");content.projects.append(item)
	living=Living.new(canonical(living_config),balance.get("living",{}))
	content.projects.append_array(living.content.get("projects",[]))
	land = Land.new(canonical(land_config),balance.get("land",{}))
	content.projects.append_array(land.content.get("projects",[]))
	content.households.append_array(land.content.get("households",[]))
	assets = Assets.new(canonical(asset_config),balance.get("assets",{}))
	assets.stage_seasons=int(balance.get("households",{}).get("stage_seasons",2))
	neighbors = Neighbors.new(canonical(contacts_config),balance.get("neighbors",{}))
	households = Households.new(canonical(household_config),balance.get("households",{}))
	for proposal in land.content.get("proposals",[]):assets.project_assets[proposal.id]=proposal.asset
	for project in living.content.get("projects",[]):assets.project_assets[project.id]="watch" if project.role=="watch" else "workroom"
	for spec in incidents.content.get("incidents",[]):
		assets.project_assets[spec.prepare]=spec.asset;assets.project_assets[spec.repair]=spec.asset
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
		"history": [], "report": {}, "assignments": [], "contacts": {}, "households": {}, "assets": {}, "land": {}, "living": {}, "incidents": {}
	}
	for role in ["steward", "watch"]:
		state.leaders[role] = {"id": content.initial_leaders[role], "since": 0}
	state.plan = normalize_plan(state, state.plan)
	return state

func ensure_state_keys(state: Dictionary) -> void:
	if not state.has("incidents"):state.incidents={}
	if not state.has("living"):state.living={}
	if not state.has("land"):state.land={}
	if not state.has("assets"): state.assets={}
	if not state.has("contacts"): state.contacts={}
	if not state.has("households"): state.households={}

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
	var total: int=int(balance.base_storage) + effect(state, "storage")
	if assets.active(state) and state.assets.conditions.stores<assets.balance.condition_threshold:total-=total*int(assets.balance.storage_loss_percent)/100
	return total

func effective_plan(state: Dictionary) -> Dictionary:
	return assets.allocation(state,self).plan if assets.active(state) else normalize_plan(state,state.plan)

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

func quote(state: Dictionary, action: Dictionary) -> Dictionary:
	# Validation uses the exact command path but need not materialize a new plan.
	return _command(state,action)

func command(state: Dictionary, action: Dictionary) -> Dictionary:
	var result: Dictionary=_command(state,action)
	if result.has("state") and assets.active(result.state):result.state.plan=effective_plan(result.state)
	return result

func _command(state: Dictionary, action: Dictionary) -> Dictionary:
	# Validate before copying or mutating. Rejected orders preserve the complete state.
	var kind: String = action.get("kind", "")
	if kind.begins_with("incident_"):return incidents.command(state,action,self)
	if kind.begins_with("living_"):return living.command(state,action,self)
	if kind.begins_with("land_"):return land.command(state,action,self)
	if kind.begins_with("asset_"): return assets.command(state,action,self)
	if kind=="plan" and assets.active(state):return {"error":"asset_managed"}
	if kind.begins_with("household_"): return households.command(state,action,self)
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
			var land_error: String=land.blocked(state,id,self)
			if not land_error.is_empty():return {"error":land_error}
			var incident_error: String=incidents.blocked(state,id,self)
			if not incident_error.is_empty():return {"error":incident_error}
			var living_error: String=living.blocked(state,id,self)
			if not living_error.is_empty():return {"error":living_error}
			if state.wood < project.wood: return {"error": "insufficient_wood"}
			if assets.active(state) and id in assets.content.housing_steps.slice(1) and int(state.food)<people(state).size()*int(assets.balance.minimum_commission_reserve):return {"error":"asset_supplies"}
			incidents.commission(next,id)
			living.commission(next,id)
			next.wood -= int(project.wood)
			next.queue.append({"id": id, "progress": 0})
			if assets.active(next):
				next.assets.initiatives[id]=assets.metadata(next,id,self)
				next.assets.commissioned+=1
				assets._record(next,project.role,"commission",id,self)
		"cancel":
			var found: bool = false
			for i in range(state.queue.size()):
				var item: Dictionary = state.queue[i]
				if item.id != action.get("id"): continue
				var project: Dictionary = projects[item.id]
				if not permitted(state, project.role): return {"error": "authority"}
				var refund: int = int(project.wood) * (int(project.work) - int(item.progress)) / int(project.work)
				incidents.cancel(next,item,self)
				living.cancel(next,item,self)
				next.wood += refund
				next.queue.remove_at(i)
				if assets.active(next):assets._record(next,project.role,"cancel",item.id,self)
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
	var plan: Dictionary = effective_plan(state)
	var allocation_: Dictionary=assets.allocation(state,self) if assets.active(state) else {}
	var crew:Dictionary=neighbors.crew(state,plan)
	var cargo:Dictionary=neighbors.arrivals(state,plan)
	var workers: int = int(plan.food)-int(crew.carriers) + (int(plan.building) if state.queue.is_empty() and not assets.active(state) else 0)
	var household_effects: Dictionary = households.forecast(state,self)
	var gathered: int = maxi(0,workers * (int(balance.food_yields[int(state.turn) % 4]) + effect(state, "food_yield")) - int(household_effects.food_penalty))
	if assets.active(state):gathered=maxi(0,gathered-assets.food_penalty(state))
	var land_effects: Dictionary=land.totals(state,self)
	if land.active(state):
		land_effects.access=land.access_ready(state,allocation_,self)
		land_effects.food=int(land_effects.food) if workers>0 else 0
		gathered=maxi(0,gathered+int(land_effects.food))
	gathered=maxi(0,gathered-incidents.food_penalty(state))
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
	for key in ["wellbeing","cooperation","security"]:
		factors[key].append({"id":"household_life","value":int(household_effects[key])})
	if assets.active(state):
		factors.wellbeing.append({"id":"asset_upkeep","value":-int(assets.balance.wellbeing_loss) if state.assets.conditions.homes<assets.balance.condition_threshold else 0})
		factors.cooperation.append({"id":"asset_upkeep","value":-int(assets.balance.cooperation_loss) if state.assets.conditions.yard<assets.balance.condition_threshold else 0})
		factors.security.append({"id":"asset_upkeep","value":-int(assets.balance.security_loss) if state.assets.conditions.watch<assets.balance.condition_threshold else 0})
	var life: Dictionary=living.forecast(state,allocation_,self) if living.active(state) else {}
	if not life.is_empty():
		factors.wellbeing.append({"id":"living_fuel","value":int(life.fuel_penalty)})
		factors.security.append({"id":"living_equipment","value":int(life.equipment_security)})
		factors.security.append({"id":"living_coverage","value":int(life.coverage)})
	var stocks: Dictionary = {}
	for key in factors:
		var total: int = 0
		for factor in factors[key]: total += int(factor.value)
		stocks[key] = move_stock(int(state[key]), clampi(total, 0, 100))
	var pressure: int = 0 if incidents.active(state) else int(balance.annual_pressure[int(state.turn) % balance.annual_pressure.size()])
	var losses: int = maxi(0, int(balance.pressure_base) + pressure - int(stocks.security)) * int(balance.loss_per_shortfall) if pressure > 0 else 0
	var remaining: int = maxi(0, int(state.food) + gathered - spoil - used)
	losses = mini(losses, remaining)
	var incident_forecast: Dictionary=incidents.forecast(state,allocation_,self) if incidents.active(state) else {}
	var incident_lost: int=mini(maxi(0,remaining-losses),int(incident_forecast.loss)) if incident_forecast.get("resolves",false) else 0
	losses+=incident_lost
	remaining += int(cargo.food)
	var overflow: int = maxi(0,remaining-losses-storage(state))
	remaining = mini(storage(state), remaining - losses)
	if land.active(state):
		factors.wellbeing.append({"id":"land_access","value":-int(land.balance.unserved_wellbeing) if land.occupied_outer(state,self) and not land_effects.access else 0})
		factors.cooperation.append({"id":"land_access","value":int(land_effects.cooperation)})
		for key in ["wellbeing","cooperation","security"]:
			var total: int=0
			for factor in factors[key]:total+=int(factor.value)
			stocks[key]=move_stock(int(state[key]),clampi(total,0,100))
	var output: Dictionary={"households":household_effects,"plan":plan,"population":population,"gathered":gathered,"used":eaten,"unfed":used-eaten,"overflow":overflow,"spoil":spoil,"losses":losses,"food":remaining,"food_delta":remaining-int(state.food),"covered":covered,"stocks":stocks,"factors":factors,"crew":crew,"cargo":cargo,"wood":int(plan.timber)*int(balance.timber_yield)+int(cargo.wood),"work":int(plan.building)*int(balance.work_yield)+leader_skill(state,"steward")/int(balance.steward_work_divisor) if plan.building>0 and not state.queue.is_empty() else 0}
	if assets.active(state):
		output.assets=allocation_
		output.work=0
		for value in allocation_.projects.values():output.work+=int(value.work)
	if land.active(state):output.land=land_effects
	if living.active(state):
		output.living=life
		output.wood=int(life.harvest)+int(cargo.wood)
	if incidents.active(state):output.incidents=incident_forecast;output.incident_lost=incident_lost
	return output

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
	if assets.active(state):
		assets.advance(next,state,f,self)
		land.advance(next,state,f)
		living.advance(next,state,f,self)
		incidents.advance(next,state,f,self)
		work=0
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
	households.advance(next,state,self)
	next.turn += 1
	_succession(next)
	next.plan = effective_plan(next)
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
		if not land.foundation(state,id,self): return false
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
	if assets.active(state):return assets.assignments(state,self)
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
	if not assets.validate(state,self):return false
	if not land.validate(state,self):return false
	if not living.validate(state,self):return false
	if not incidents.validate(state,self):return false
	if not self.households.validate(state,self): return false
	if not state.plan is Dictionary: return false
	if assets.active(state):
		if canonical(state.plan)!=effective_plan(state):return false
	elif command(state,{"kind":"plan","plan":state.plan}).has("error"): return false
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
