extends RefCounted
## Optional authored adversity/renewal. Memory belongs to stable households.
## Integer deterministic rules only: presentation never advances these values.
var content: Dictionary
var balance: Dictionary
var orders: Dictionary = {}
const ORDER_IDS = ["secure_stores", "refuge", "safe_routes", "learning"]
const STAGES = ["warning", "danger", "recovery", "renewal", "settled"]

func _init(config: Dictionary, tuning: Dictionary) -> void:
	content = config
	balance = tuning
	for item in config.get("orders", []): orders[item.id] = item

func active(state: Dictionary) -> bool:
	var value: Variant = state.get("households", {})
	return value is Dictionary and not value.is_empty()

func stage(state: Dictionary) -> String:
	if not active(state): return "inactive"
	if not state.get("assets",{}).is_empty():
		var start: int=int(state.assets.pressure_start)
		return "settled" if start<0 else _stage(maxi(0,int(state.turn)-start))
	return _stage(int(state.households.elapsed))

func _stage(elapsed: int) -> String:
	return STAGES[mini(elapsed / int(balance.stage_seasons), STAGES.size() - 1)]

func requirements(id: String) -> Dictionary:
	return {"care":int(balance.store_care_minimum) if id=="secure_stores" else (int(balance.care_minimum) if id in ["refuge","learning"] else 0), "watch":int(balance.watch_minimum) if id=="safe_routes" else 0}

func ready(state: Dictionary, id: String, rules) -> bool:
	if not active(state) or not state.households.orders.get(id, false): return false
	var needed: Dictionary = requirements(id)
	var plan: Dictionary = rules.effective_plan(state)
	var crew: Dictionary = rules.neighbors.crew(state,plan)
	if rules.assets.active(state):
		var assigned: Dictionary=rules.assets.allocation(state,rules).orders
		if int(assigned.get(id,0))<maxi(int(needed.care),int(needed.watch)):return false
	if int(plan.care)<int(needed.care) or int(plan.watch)-int(crew.escorts)<int(needed.watch): return false
	if id!="learning": return true
	var current: String=stage(state)
	if current not in ["recovery","renewal","settled"]: return false
	var workers: int=int(plan.food)-int(crew.carriers)+(int(plan.building) if state.queue.is_empty() and not rules.assets.active(state) else 0)
	var gathering: int=workers*(int(rules.balance.food_yields[int(state.turn)%4])+rules.effect(state,"food_yield"))
	if rules.assets.active(state):gathering-=rules.assets.food_penalty(state)
	return gathering>=int(balance.learning_food)+int(balance.stages[current].food_penalty)

func command(state: Dictionary, action: Dictionary, rules) -> Dictionary:
	if not validate(state,rules): return {"error":"household_invalid"}
	var kind: String = action.get("kind", "")
	var next: Dictionary = state.duplicate(true)
	if kind=="household_begin":
		if state.role!="god": return {"error":"authority"}
		if active(state): return {"error":"household_started"}
		if orders.size()!=ORDER_IDS.size(): return {"error":"household_unknown"}
		next.households={"version":1,"started":int(state.turn),"elapsed":0,"orders":{},"investments":{},"homes":{},"report":{}}
		for id in ORDER_IDS:
			next.households.orders[id]=false
			next.households.investments[id]=false
		_sync_homes(next,rules)
		rules._event(next,"household_started",{})
		return {"state":next}
	if not active(state): return {"error":"household_missing"}
	if kind!="household_order" or not action.get("id") is String or not orders.has(action.id) or not action.get("enabled") is bool: return {"error":"household_unknown"}
	var id: String = action.id
	if not rules.permitted(state,orders[id].role): return {"error":"authority"}
	var cost: int = 0
	if action.enabled:
		var needed: Dictionary = requirements(id)
		var plan: Dictionary = rules.effective_plan(state)
		var crew: Dictionary = rules.neighbors.crew(state,plan)
		if not rules.assets.active(state) and (int(plan.care)<int(needed.care) or int(plan.watch)-int(crew.escorts)<int(needed.watch)): return {"error":"household_labor"}
		if not state.households.investments[id]: cost=int(balance.costs[id])
		if int(state.wood)<cost: return {"error":"household_stock"}
		next.wood-=cost
		next.households.investments[id]=true
	next.households.orders[id]=action.enabled
	if rules.assets.active(next):rules.assets._record(next,orders[id].role,"household_order",id,rules,{"enabled":action.enabled})
	rules._event(next,"household_order",{"order":id,"enabled":action.enabled,"wood":cost})
	return {"state":next}

func forecast(state: Dictionary, rules) -> Dictionary:
	var result := {"food_penalty":0,"wellbeing":0,"cooperation":0,"security":0,"care_ready":false,"watch_ready":false,"learning_ready":false,"factors":{"food_penalty":[],"wellbeing":[],"cooperation":[],"security":[]}}
	if not active(state): return result
	var current: String = stage(state)
	var spec: Dictionary = balance.stages[current]
	var store: bool = ready(state,"secure_stores",rules)
	var care: bool = ready(state,"refuge",rules)
	var watch: bool = ready(state,"safe_routes",rules)
	var learning: bool = ready(state,"learning",rules)
	var danger: bool = current in ["warning","danger"]
	var remembered: int = 0
	var occupied: Array = _occupied(state,rules)
	for id in occupied: remembered+=int(state.households.homes.get(id,{}).get("stress",0))
	var average: int = remembered / maxi(1,occupied.size())
	var disruption: int = int(spec.food_penalty)
	var store_relief: int = mini(disruption,int(balance.secure_food_relief)) if store and danger else 0
	var route_relief: int = mini(disruption-store_relief,int(balance.route_food_relief)) if watch and danger else 0
	result.factors.food_penalty=[{"id":"circumstance","value":disruption},{"id":"store","value":-store_relief},{"id":"routes","value":-route_relief},{"id":"learning","value":int(balance.learning_food) if learning else 0}]
	result.factors.wellbeing=[{"id":"circumstance","value":int(spec.wellbeing)},{"id":"care","value":int(balance.refuge_wellbeing) if care else 0},{"id":"stress","value":-average/int(balance.stress_wellbeing_divisor)}]
	result.factors.cooperation=[{"id":"circumstance","value":int(spec.cooperation)},{"id":"stress","value":-average/int(balance.stress_cooperation_divisor)},{"id":"learning","value":int(balance.learning_cooperation) if learning else 0}]
	result.factors.security=[{"id":"circumstance","value":int(spec.security)},{"id":"routes","value":int(balance.route_security) if watch and danger else 0},{"id":"store","value":int(balance.store_security) if store and danger else 0}]
	for key in result.factors:
		for factor in result.factors[key]: result[key]+=int(factor.value)
	result.care_ready=care
	result.watch_ready=watch
	result.learning_ready=learning
	return result

func advance(next: Dictionary, before: Dictionary, rules) -> void:
	if not active(before): return
	_sync_homes(next,rules)
	var current: String = stage(before)
	var effect: Dictionary = forecast(before,rules)
	var stress_total: int = 0
	var practice_total: int = 0
	for id in _occupied(next,rules):
		var memory: Dictionary = next.households.homes[id]
		var stress_before: int = int(memory.stress)
		var practice_before: int = int(memory.practice)
		var delta: int = int(balance.stages[current].stress)
		if effect.care_ready: delta+=int(balance.refuge_stress)
		if int(next.report.get("unfed",0))>0: delta+=int(balance.stress_hunger)
		memory.stress=clampi(stress_before+delta,0,int(balance.max_stock))
		if effect.learning_ready:
			var base: int = int(balance[current+"_practice"])
			memory.practice=mini(int(balance.max_stock),practice_before+base+_affinity(id)*int(balance.practice_affinity_step))
		stress_total+=int(memory.stress)-stress_before
		practice_total+=int(memory.practice)-practice_before
	next.households.elapsed+=1
	var report := {"stage":current,"stress_total":stress_total,"practice_total":practice_total}
	for key in ["food_penalty","wellbeing","cooperation","security","care_ready","watch_ready","learning_ready"]: report[key]=effect[key]
	next.households.report=report
	rules._event(next,"household_season",{"stage":current,"food":int(effect.food_penalty),"stress":stress_total,"practice":practice_total})

func _occupied(state: Dictionary, rules) -> Array:
	var ids: Dictionary = {}
	for person in rules.people(state): ids[person.household]=true
	var result: Array = ids.keys()
	result.sort()
	return result

func _sync_homes(state: Dictionary, rules) -> void:
	for id in _occupied(state,rules):
		if not state.households.homes.has(id): state.households.homes[id]={"stress":0,"practice":0}

func _affinity(id: String) -> int:
	var total: int = 0
	for index in range(id.length()): total+=id.unicode_at(index)
	return total % int(balance.practice_affinity_span)

func validate(state: Dictionary, rules) -> bool:
	var extension: Variant = state.get("households",{})
	if not extension is Dictionary: return false
	if extension.is_empty(): return true
	if content.is_empty() or extension.size()!=7: return false
	for key in ["version","started","elapsed","orders","investments","homes","report"]:
		if not extension.has(key): return false
	if not rules.whole(extension.version,1,1) or not rules.whole(extension.started,0,int(state.turn)) or not rules.whole(extension.elapsed,0,int(rules.balance.max_turns)): return false
	if int(extension.elapsed)!=int(state.turn)-int(extension.started): return false
	for key in ["orders","investments"]:
		if not extension[key] is Dictionary or extension[key].size()!=ORDER_IDS.size(): return false
		for id in ORDER_IDS:
			if not extension[key].get(id) is bool: return false
	for id in ORDER_IDS:
		if extension.orders[id] and not extension.investments[id]: return false
	if not extension.homes is Dictionary or extension.homes.is_empty() or extension.homes.size()>rules.content.households.size(): return false
	var allowed: Dictionary = {}
	for home in rules.content.households:
		if home.requires=="" or rules.has_project(state,home.requires): allowed[home.id]=true
	for id in extension.homes:
		if not id is String or not allowed.has(id): return false
		var memory: Variant = extension.homes[id]
		if not memory is Dictionary or memory.size()!=2 or not rules.whole(memory.get("stress"),0,int(balance.max_stock)) or not rules.whole(memory.get("practice"),0,int(balance.max_stock)): return false
	for id in _occupied(state,rules):
		if not extension.homes.has(id): return false
	var report: Variant = extension.report
	if not report is Dictionary: return false
	if extension.elapsed==0: return report.is_empty()
	if report.size()!=10 or not report.get("stage") is String: return false
	var expected: String=_stage(int(extension.elapsed)-1)
	if rules.assets.active(state):
		expected="settled" if int(state.assets.pressure_start)==int(state.turn) else rules.assets.stage(state,int(state.turn)-1)
	if report.stage!=expected: return false
	for key in ["care_ready","watch_ready","learning_ready"]:
		if not report.get(key) is bool: return false
	for key in ["food_penalty","wellbeing","cooperation","security"]:
		if not rules.whole(report.get(key),0 if key=="food_penalty" else -int(balance.max_stock),int(balance.max_stock)): return false
	var bound: int = int(balance.max_stock)*rules.content.households.size()
	if not rules.whole(report.get("stress_total"),-bound,bound) or not rules.whole(report.get("practice_total"),0,bound): return false
	return true
