extends RefCounted
## Optional institutional allocation. No nodes, clocks, RNG or parallel inventory.
var content: Dictionary
var balance: Dictionary
var stage_seasons: int=2
var assets: Dictionary = {}
var project_assets: Dictionary = {}

func _init(config: Dictionary, tuning: Dictionary) -> void:
	content=config;balance=tuning
	for item in content.get("assets",[]):
		assets[item.id]=item
		for id in item.projects:project_assets[id]=item.id

func active(state: Dictionary) -> bool:
	return state.get("assets",{}) is Dictionary and not state.get("assets",{}).is_empty()

func stage(state: Dictionary, turn: int = -1) -> String:
	var start: int=int(state.assets.pressure_start)
	if start<0:return "settled"
	return ["warning","danger","recovery","renewal","settled"][mini(4,maxi(0,(int(state.turn) if turn<0 else turn)-start)/stage_seasons)]

func object_asset(id: String) -> String:
	for item in content.assets:
		if id in item.objects:return item.id
	return ""

func metadata(state: Dictionary, id: String, rules) -> Dictionary:
	var office: String=rules.projects[id].role
	return {"priority":int(balance.default_priority),"crew":int(balance.default_crew),"paused":false,"office":office,"author":state.leaders[office].id,"turn":int(state.turn)}

func command(state: Dictionary, action: Dictionary, rules) -> Dictionary:
	var kind: String=action.get("kind","")
	var next: Dictionary=state.duplicate(true)
	if kind=="asset_begin":
		if state.role!="god":return {"error":"authority"}
		if active(state):return {"error":"asset_started"}
		if assets.is_empty():return {"error":"asset_unknown"}
		var previous: bool=rules.households.active(state)
		if not previous:
			var response: Dictionary=rules.command(state,{"kind":"household_begin"})
			if response.has("error"):return response
			next=response.state
		next.assets={"version":1,"started":int(state.turn),"manual_plan":state.plan.duplicate(true),"reserve":int(balance.initial_reserve),"upkeep":0,"watch":int(balance.initial_watch)-1,"pressure_start":int(state.households.started) if previous else -1,"conditions":{},"maintenance":{},"initiatives":{},"decisions":[],"tutorial":0,"inspected":[],"principle_changes":0,"commissioned":0,"pressure_decisions":0,"learning_seasons":0,"housing":false,"report":{}}
		for id in assets:
			next.assets.conditions[id]=int(balance.initial_condition)
			next.assets.maintenance[id]=true
		for item in state.queue:next.assets.initiatives[item.id]=metadata(state,item.id,rules)
		return {"state":next}
	if not active(state):return {"error":"asset_missing"}
	var id: String=action.get("id","")
	match kind:
		"asset_inspect":
			if not assets.has(id):return {"error":"asset_unknown"}
			if id not in next.assets.inspected:next.assets.inspected.append(id)
		"asset_principle":
			var spec: Dictionary={}
			for p in content.principles:
				if p.id==id:spec=p
			if spec.is_empty() or not rules.whole(action.get("value"),0,spec.options.size()-1):return {"error":"asset_unknown"}
			if not rules.permitted(state,spec.role):return {"error":"authority"}
			var value: int=int(action.value)
			if id in ["care","learning"]:
				var result: Dictionary=rules.command(next,{"kind":"household_order","id":"refuge" if id=="care" else "learning","enabled":value==1})
				if result.has("error"):return result
				next=result.state
			elif id=="welcome":next.welcome=value==1
			elif id=="reserve":next.assets.reserve=value+1
			else:next.assets[id]=value
			next.assets.principle_changes+=1
			_record(next,spec.role,kind,id,rules,{"value":value})
		"asset_project":
			if not state.assets.initiatives.has(id):return {"error":"unknown_project"}
			var queued: bool=false
			for item in state.queue:
				if item.id==id:queued=true
			if not queued:return {"error":"already_ordered"}
			if not rules.permitted(state,rules.projects[id].role):return {"error":"authority"}
			if not rules.whole(action.get("priority"),1,3) or not rules.whole(action.get("crew"),0,int(balance.max_crew)) or not action.get("paused") is bool:return {"error":"asset_unknown"}
			for key in ["priority","crew","paused"]:next.assets.initiatives[id][key]=action[key]
			if rules.incidents.active(next) and id in rules.incidents.project_specs and id.ends_with("_repair") and action.paused:next.incidents.paused=true
			_record(next,rules.projects[id].role,kind,id,rules,{"priority":int(action.priority),"crew":int(action.crew),"paused":action.paused})
		"asset_maintenance":
			if not assets.has(id) or not action.get("enabled") is bool:return {"error":"asset_unknown"}
			if not rules.permitted(state,assets[id].role):return {"error":"authority"}
			next.assets.maintenance[id]=action.enabled
			_record(next,assets[id].role,kind,id,rules,{"enabled":action.enabled})
		"asset_pressure":
			if rules.incidents.active(state):return {"error":"incident_lesson"}
			if state.role!="god":return {"error":"authority"}
			if state.assets.pressure_start>=0:return {"error":"asset_pressure"}
			next.assets.pressure_start=int(state.turn)
		"asset_housing":
			if rules.land.active(state):return {"error":"land_choice"}
			if not rules.permitted(state,"steward"):return {"error":"authority"}
			if not action.get("enabled") is bool:return {"error":"asset_unknown"}
			next.assets.housing=action.enabled
			_record(next,"steward",kind,"homes",rules,{"enabled":action.enabled})
		"asset_housing_step":
			if rules.land.active(state):return {"error":"land_choice"}
			if not state.assets.housing:return {"error":"asset_growth"}
			var step: String=housing_next(state,rules)
			if step.is_empty():return {"error":"asset_growth"}
			return rules.command(state,{"kind":"commission","id":step})
		"asset_review":
			if not tutorial_ready(state,rules):return {"error":"asset_review"}
			next.assets.tutorial+=1
		_:return {"error":"asset_unknown"}
	return {"state":next}

func _record(state: Dictionary, office: String, kind: String, target: String, rules, details: Dictionary={}) -> void:
	state.assets.decisions.append({"turn":int(state.turn),"office":office,"author":state.leaders[office].id,"kind":kind,"target":target,"details":details.duplicate(true)})
	if stage(state) in ["warning","danger"]:state.assets.pressure_decisions+=1

func principle(state: Dictionary, id: String) -> int:
	if id=="care":return int(state.households.orders.refuge)
	if id=="learning":return int(state.households.orders.learning)
	if id=="welcome":return int(state.welcome)
	if id=="reserve":return int(state.assets.reserve)-1
	return int(state.assets[id])

func housing_next(state: Dictionary, rules) -> String:
	for id in content.housing_steps:
		if rules.has_project(state,id):continue
		for item in state.queue:
			if item.id==id:return ""
		return id
	return ""

func tutorial_ready(state: Dictionary,rules) -> bool:
	var index: int=int(state.assets.tutorial)
	if index>=content.tutorial.size():return false
	match content.tutorial[index].condition:
		"inspect":return content.tutorial[index].asset in state.assets.inspected
		"principle":return state.assets.principle_changes>0
		"commission":return state.assets.commissioned>0
		"season":return state.turn>state.assets.started
		"pressure":return state.assets.pressure_start>=0 and state.assets.pressure_decisions>0
		"learning":return state.assets.learning_seasons>0 and stage(state) in ["recovery","renewal","settled"]
		"growth":
			if rules.land.active(state):return rules.land.growth_ready(state,rules)
			for id in content.housing_steps:
				if not rules.has_project(state,id):return false
			return state.food>=(rules.people(state).size()+int(rules.balance.migration_size))*int(rules.balance.migration_reserve_seasons)
	return false

func allocation(state: Dictionary, rules) -> Dictionary:
	var result := {"plan":{"food":0,"timber":0,"care":0,"watch":0,"building":0},"requests":[],"projects":{},"orders":{},"repair":"","repair_cost":0,"repair_workers":0,"target":mini(rules.storage(state),rules.people(state).size()*int(state.assets.reserve))}
	result.access_workers=0;result.access_cost=0
	var requests: Array=[]
	var adults: int=rules.people(state,true).size()
	var mission: Dictionary=state.get("contacts",{}).get("mission",{})
	# Escrowed journeys have first call on the same finite home workforce.
	if not mission.is_empty():
		_request(requests,"carriers","food",int(rules.neighbors.balance.carriers),0,"landing")
		_request(requests,"escorts","watch",int(mission.escorts),0,"watch")
	var population: int=rules.people(state).size()
	var eaten: int=ceili(population*float(rules.balance.tight_rations_percent if state.tight_rations else rules.balance.full_rations_percent)/100.0)
	var yield_: int=int(rules.balance.food_yields[int(state.turn)%4])+rules.effect(state,"food_yield")
	var average: float=0
	for value in rules.balance.food_yields:average+=float(value)/4.0
	average+=rules.effect(state,"food_yield")
	var spoil: int=int(state.food)*int(rules.balance.spoil_percent)/100
	var land_effects: Dictionary=rules.land.totals(state,rules)
	var disruption: int=int(rules.households.balance.stages[stage(state)].food_penalty)+food_penalty(state)+rules.incidents.food_penalty(state)-int(land_effects.food)
	var essential: int=maxi(ceili(float(population)/average),ceili(float(eaten+spoil+disruption-int(state.food))/yield_))
	_request(requests,"food","food",maxi(1,essential),1,"fields")
	_request(requests,"refuge" if state.households.orders.refuge else "care","care",int(balance.care_workers),2,"homes")
	_request(requests,"watch","watch",int(state.assets.watch)+1,2 if state.assets.watch==1 else 6,"watch")
	if state.households.orders.secure_stores:_request(requests,"secure_stores","care",int(rules.households.balance.store_care_minimum),3,"stores")
	var reserve_need: int=ceili(float(maxi(0,int(result.target)-int(state.food)))/int(balance.reserve_recovery_seasons))
	var desired: int=ceili(float(eaten+spoil+disruption+reserve_need)/yield_)
	_request(requests,"reserve","food",maxi(0,desired-essential),3 if state.assets.reserve>=2 else 7,"stores")
	if rules.land.needs_access(state,rules) and state.land.access_enabled:
		_request(requests,"land_access","building",int(rules.land.balance.access_workers),int(rules.land.balance.access_priority),"yard")
	var repair: String=""
	var ids: Array=assets.keys();ids.sort()
	for id in ids:
		if state.assets.maintenance[id] and int(state.assets.conditions[id])<int(balance.repair_threshold) and (repair.is_empty() or int(state.assets.conditions[id])<int(state.assets.conditions[repair])):repair=id
	if not repair.is_empty():_request(requests,"repair","building",int(balance.repair_workers),3 if state.assets.upkeep==0 else 8,repair)
	for item in state.queue:
		var spec: Dictionary=state.assets.initiatives[item.id]
		result.projects[item.id]={"crew":0,"work":0}
		if not spec.paused:_request(requests,item.id,"building",int(spec.crew),3+int(spec.priority),project_assets[item.id])
	_request(requests,"timber","timber",int(balance.timber_workers),5,"workroom")
	if state.households.orders.learning:_request(requests,"learning","care",int(rules.households.balance.care_minimum),6,"workroom")
	rules.living.requests(state,requests,rules)
	requests.sort_custom(func(a,b):return a.priority<b.priority if a.priority!=b.priority else a.id<b.id)
	var remaining: int=adults
	var places: int=int(land_effects.work) if rules.land.active(state) else adults
	var timber_left: int=int(state.wood)
	if rules.living.active(state):
		rules.living.prepare_allocation(state,result)
		timber_left-=int(result.living.fuel)
	for request in requests:
		var count: int=mini(remaining,int(request.wanted))
		request.reason="allocated" if count==request.wanted else "labor"
		if request.id in ["carriers","escorts"] and adults<int(rules.neighbors.balance.carriers)+int(mission.escorts):count=0;request.reason="labor"
		if request.id=="learning" and stage(state) in ["warning","danger"]:count=0;request.reason="phase"
		if request.id=="land_access":
			if timber_left<int(rules.land.balance.access_wood):count=0;request.reason="materials"
			if count==request.wanted:
				result.access_workers=count;result.access_cost=int(rules.land.balance.access_wood);timber_left-=int(result.access_cost)
		if request.id=="repair" and timber_left<int(balance.repair_wood):count=0;request.reason="materials"
		if result.projects.has(request.id):
			if rules.land.proposals.has(request.id) and rules.land.proposals[request.id].requires_access and not rules.land.access_ready(state,result,rules):count=0;request.reason="access"
			if count>places:count=places;request.reason="space"
			places-=count
		if rules.living.active(state) and request.id.begins_with("living_") and not result.projects.has(request.id):
			var allocated: Dictionary=rules.living.allocate(state,request,count,timber_left,places,result,rules)
			count=int(allocated.count);timber_left=int(allocated.wood);places=int(allocated.places)
		# Partial special crews contribute ordinary care, but cannot activate an order.
		request.filled=count;remaining-=count
		result.plan[request.job]+=count
		if request.id in ["refuge","secure_stores","learning"]:result.orders[request.id]=count
		if request.id=="watch":result.orders.safe_routes=count
		if result.projects.has(request.id):
			result.projects[request.id].crew=count
			result.projects[request.id].work=(rules.incidents.work_bonus(state,request.id,rules) if count>0 else 0)+count*maxi(0,int(rules.balance.work_yield)-(int(balance.work_yield_loss) if state.assets.conditions.workroom<balance.condition_threshold else 0))
		if request.id=="repair" and count==request.wanted:
			timber_left-=int(balance.repair_wood)
			result.repair=request.asset;result.repair_cost=int(balance.repair_wood);result.repair_workers=count
	result.plan.food+=remaining
	result.requests=requests
	# The steward's coordination bonus is finite: first staffed project only.
	for request in requests:
		if result.projects.has(request.id) and result.projects[request.id].crew>0:
			result.projects[request.id].work+=rules.leader_skill(state,"steward")/int(rules.balance.steward_work_divisor)
			break
	for item in state.queue:
		result.projects[item.id].work=mini(int(result.projects[item.id].work),int(rules.projects[item.id].work)-int(item.progress))
	return result

func _request(list: Array,id: String,job: String,wanted: int,priority: int,asset: String) -> void:
	if wanted>0:list.append({"id":id,"job":job,"wanted":wanted,"priority":priority,"asset":asset,"filled":0,"reason":"labor"})

func food_penalty(state: Dictionary) -> int:
	var value: int=0
	for id in ["fields","landing"]:
		if state.assets.conditions[id]<balance.condition_threshold:value+=int(balance.food_loss)
	return value

func wear(state: Dictionary) -> int:
	return int(balance.wear)+(int(balance.pressure_wear) if stage(state) in ["warning","danger"] else 0)

func condition_next(state: Dictionary,id: String,allocation_: Dictionary) -> int:
	return clampi(int(state.assets.conditions[id])-wear(state)+(int(balance.repair_gain) if allocation_.repair==id else 0),0,int(balance.condition_max))

func advance(next: Dictionary,before: Dictionary,forecast: Dictionary,rules) -> void:
	var allocation_: Dictionary=forecast.assets
	next.wood-=int(allocation_.repair_cost)
	for id in assets:next.assets.conditions[id]=condition_next(before,id,allocation_)
	var queue: Array=[]
	for item in next.queue:
		var work: int=int(allocation_.projects[item.id].work)
		item.progress=mini(int(rules.projects[item.id].work),int(item.progress)+work)
		if item.progress>=rules.projects[item.id].work:
			next.completed.append({"id":item.id,"turn":int(before.turn)})
			rules._event(next,"completed",{"project":item.id})
		else:queue.append(item)
	next.queue=queue
	if forecast.households.learning_ready:next.assets.learning_seasons+=1
	next.assets.report={"turn":int(before.turn),"repair":allocation_.repair,"repair_cost":int(allocation_.repair_cost),"projects":allocation_.projects.duplicate(true),"requests":allocation_.requests.duplicate(true)}

func assignments(state: Dictionary,rules) -> Array:
	var allocation_: Dictionary=allocation(state,rules)
	var adults: Array=rules.people(state,true)
	var result: Array=[]
	var index: int=0
	var ordered: Array=[]
	for i in range(adults.size()):ordered.append(adults[(i+int(state.turn))%adults.size()])
	if rules.living.active(state) and state.living.prepare==2 and allocation_.living.shared:
		var start: int=0
		for request in allocation_.requests:
			if request.id=="living_prepare":break
			start+=int(request.filled)
		for i in range(rules.living.content.households.size()):
			for j in range(ordered.size()):
				if ordered[j].household==rules.living.content.households[i].id:
					var person: Dictionary=ordered[start+i];ordered[start+i]=ordered[j];ordered[j]=person;break
	for request in allocation_.requests:
		for i in range(int(request.filled)):
			var person: Dictionary=ordered[index]
			result.append(_task(state,person,request,rules));index+=1
	while index<adults.size():
		result.append(_task(state,ordered[index],{"id":"food","job":"food","asset":"fields"},rules));index+=1
	return result

func _task(state: Dictionary,person: Dictionary,request: Dictionary,rules) -> Dictionary:
	var home: Array=[]
	for item in rules.content.households:
		if item.id==person.household:home=item.at
	var destination: Array=assets[request.asset].at
	if request.id=="timber":destination=rules.content.job_sites.timber
	if rules.land.active(state):
		if request.id=="land_access":destination=rules.land.sites.north_access.at
		if request.id=="food" and rules.land.use_at(state,"west_field",rules)=="land_cultivate" and int(person.id.trim_prefix("citizen_"))%2==0:destination=rules.land.sites.west_field.at
	if rules.projects.has(request.id):destination=rules.projects[request.id].at
	var job: String=request.job
	if request.id in ["carriers","escorts"]:job="travel";destination=rules.neighbors.content.meeting_at
	# A bounded subset of ordinary food duty illustrates existing waterside work.
	if request.id=="food" and int(person.id.trim_prefix("citizen_"))%4==0:destination=assets.landing.at
	destination=rules.living.destination(state,request,destination)
	if rules.incidents.restricted(state,"approach") and request.id=="timber":destination=rules.living.areas.west_wood.at
	if rules.incidents.restricted(state,"stores") and request.id=="food" and destination==assets.landing.at:destination=assets.fields.at
	return {"id":person.id,"job":job,"from":home.duplicate(),"to":destination.duplicate(),"duty":request.id,"asset":request.asset}

func validate(state: Dictionary,rules) -> bool:
	var a: Variant=state.get("assets",{})
	if not a is Dictionary:return false
	if a.is_empty():return true
	if assets.is_empty():return false
	var keys: Array=["version","started","manual_plan","reserve","upkeep","watch","pressure_start","conditions","maintenance","initiatives","decisions","tutorial","inspected","principle_changes","commissioned","pressure_decisions","learning_seasons","housing","report"]
	if a.size()!=keys.size():return false
	for key in keys:
		if not a.has(key):return false
	if not rules.whole(a.version,1,1) or not rules.whole(a.started,0,int(state.turn)) or not rules.whole(a.pressure_start,-1,int(state.turn)):return false
	if not rules.households.active(state) or not a.housing is bool:return false
	if not rules.whole(a.reserve,1,3) or not rules.whole(a.upkeep,0,1) or not rules.whole(a.watch,0,1) or not rules.whole(a.tutorial,0,content.tutorial.size()):return false
	for key in ["principle_changes","commissioned","pressure_decisions","learning_seasons"]:
		if not rules.whole(a[key],0,1000000):return false
	if not a.manual_plan is Dictionary or a.manual_plan.size()!=5:return false
	for job in ["food","timber","care","watch","building"]:
		if not rules.whole(a.manual_plan.get(job),0,2048):return false
	for key in ["conditions","maintenance"]:
		if not a[key] is Dictionary or a[key].size()!=assets.size():return false
		for id in assets:
			if key=="conditions" and not rules.whole(a[key].get(id),0,int(balance.condition_max)):return false
			if key=="maintenance" and not a[key].get(id) is bool:return false
	if not a.initiatives is Dictionary or a.initiatives.size()>rules.projects.size():return false
	for id in a.initiatives:
		if not rules.projects.has(id):return false
		var item: Variant=a.initiatives[id]
		if not item is Dictionary or item.size()!=6:return false
		if not rules.whole(item.get("priority"),1,3) or not rules.whole(item.get("crew"),0,int(balance.max_crew)) or not item.get("paused") is bool:return false
		if item.get("office")!=rules.projects[id].role or not item.get("author") is String or not rules.whole(item.get("turn"),0,int(state.turn)):return false
		if item.author!="" and rules.person_by_id(state,item.author).is_empty():return false
	for item in state.queue:
		if not a.initiatives.has(item.id):return false
	if not a.inspected is Array or a.inspected.size()>assets.size():return false
	for id in a.inspected:
		if not assets.has(id):return false
	if not a.decisions is Array or a.decisions.size()>20000:return false
	for decision in a.decisions:
		if not decision is Dictionary or decision.size()!=6:return false
		if not rules.whole(decision.get("turn"),0,int(state.turn)) or decision.get("office") not in ["steward","watch"] or not decision.get("author") is String or not decision.get("kind") is String or not decision.get("target") is String:return false
		if decision.author!="" and rules.person_by_id(state,decision.author).is_empty():return false
		if not decision.get("details") is Dictionary:return false
		if decision.kind not in ["asset_principle","asset_project","asset_maintenance","asset_housing","household_order","commission","cancel","land_access","living_order","incident_restrict"]:return false
		if decision.kind=="living_order":
			if decision.target not in ["area","prepare","cooperate","training","repair","patrol"] or not decision.details.has("value"):return false
			var value_: Variant=decision.details.value
			if decision.target=="area" and value_ not in rules.living.areas:return false
			if decision.target=="patrol" and value_ not in ["landing_post","north_post"]:return false
			if decision.target=="prepare" and not rules.whole(value_,0,2):return false
			if decision.target in ["cooperate","training","repair"] and not value_ is bool:return false
			continue
		for value in decision.details.values():
			if not value is bool and not rules.whole(value,0,int(balance.max_crew)):return false
	if not a.report is Dictionary:return false
	if not a.report.is_empty():
		if a.report.size()!=5 or not rules.whole(a.report.get("turn"),0,maxi(0,int(state.turn)-1)) or not a.report.get("repair") is String:return false
		if a.report.repair!="" and not assets.has(a.report.repair):return false
		if not rules.whole(a.report.get("repair_cost"),0,int(balance.repair_wood)) or not a.report.get("projects") is Dictionary or not a.report.get("requests") is Array:return false
		for id in a.report.projects:
			if not rules.projects.has(id):return false
			var value: Variant=a.report.projects[id]
			if not value is Dictionary or value.size()!=2 or not rules.whole(value.get("crew"),0,int(balance.max_crew)) or not rules.whole(value.get("work"),0,int(rules.projects[id].work)):return false
		if a.report.requests.size()>assets.size()+rules.projects.size()+5:return false
		for request in a.report.requests:
			if not request is Dictionary or request.size()!=7:return false
			if not request.get("id") is String or not assets.has(request.get("asset","")) or request.get("job") not in ["food","timber","care","watch","building"]:return false
			if not rules.whole(request.get("wanted"),0,2048) or not rules.whole(request.get("filled"),0,int(request.wanted)) or not rules.whole(request.get("priority"),0,8):return false
			if request.get("reason") not in ["allocated","labor","phase","materials","space","access"]:return false
	return true
