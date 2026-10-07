extends RefCounted
## Optional civic continuity. Rank is derived from the existing completion ledger.
## Readiness has the only new temporal memory; no scene, random or clock authority.
var content: Dictionary
var balance: Dictionary
var project_specs: Dictionary = {}
var stages: Dictionary = {}
var definition_hash: String = ""

func _init(config: Dictionary, tuning: Dictionary) -> void:
	content=config.duplicate(true);balance=tuning.duplicate(true)
	if content.is_empty():return
	var semantics: Dictionary={"version":content.version,"profile":content.profile,"initial_stage":content.initial_stage,"recognized_stage":content.recognized_stage,"civic_project":content.civic_project,"transitions":content.transitions,"tuning":balance,"projects":[],"sites":[],"proposals":content.proposals,"stages":[]}
	for item in content.stages:
		stages[item.id]=item
		semantics.stages.append({"id":item.id,"status":item.status})
	for site in content.sites:
		var spec: Dictionary=site.duplicate(true)
		for key in ["title","use","beneficiaries"]:spec.erase(key)
		semantics.sites.append(spec)
	for project in content.projects:
		var prices: Dictionary=balance.projects[project.tuning]
		for key in ["wood","work","effects"]:project[key]=prices[key]
		project_specs[project.id]=project
		var spec: Dictionary=project.duplicate(true)
		for key in ["title","body","presentation"]:spec.erase(key)
		for change in spec.changes:
			for object in change.after:object.erase("label")
		semantics.projects.append(spec)
	definition_hash=JSON.stringify(semantics).sha256_text()

func active(state: Dictionary) -> bool:
	return state.get("lifecycle",{}) is Dictionary and not state.get("lifecycle",{}).is_empty()

func stage(state: Dictionary, _rules) -> String:
	var current: String=content.get("initial_stage","village_foundation")
	if not active(state):return current
	if state.lifecycle.recognition==content.recognized_stage:current=content.recognized_stage
	# Civic progression follows the same ordered ledger as physical continuity;
	# recognition is an entry rank, not a ceiling on later authored projects.
	for completed in state.completed:
		for transition in content.transitions:
			if transition.from==current and completed.id==transition.project:
				current=transition.to;break
	return current

func _rank(id: String) -> int:
	for i in range(content.stages.size()):
		if content.stages[i].id==id:return i
	return -1

func _transition(state: Dictionary,rules) -> Dictionary:
	var current: String=stage(state,rules)
	for transition in content.get("transitions",[]):
		if transition.from==current:return transition
	return {}

func _factor(state: Dictionary,predicate: Dictionary,rules) -> Dictionary:
	var current: int=0
	var required: int=1
	if predicate.has("tuning"):required=int(balance.readiness[predicate.tuning])
	match predicate.kind:
		"population":current=rules.people(state).size()
		"housing":current=rules.capacity(state)
		"reserves":
			current=int(state.food)
			required*=rules.people(state).size()*int(rules.balance.food_per_person)
		"stock":current=int(state[predicate.tuning])
		"knowledge":
			var occupied: Dictionary={}
			for person in rules.people(state):occupied[person.household]=true
			for household in occupied:
				current=maxi(current,int(state.get("living",{}).get("experience",{}).get(household,{}).get(predicate.tuning,0)))
		"project":current=int(rules.has_project(state,predicate.project))
		"site":
			current=1
			for proposal in rules.land.content.proposals:
				if proposal.site==predicate.site and rules.land.committed(state,proposal.id,rules):current=0
	return {"id":predicate.id,"current":current,"required":required,"met":current>=required}

func status(state: Dictionary,rules) -> Dictionary:
	var current: String=stage(state,rules)
	var result: Dictionary={"stage":current,"stage_name":stages.get(current,{}).get("title",current),"recognition":state.get("lifecycle",{}).get("recognition",""),"transition":"","project":"","ready":false,"qualifying":false,"seasons":0,"required_seasons":int(balance.get("readiness",{}).get("sustained_seasons",0)),"factors":[],"unlocks":[],"upkeep":int(balance.get("civic_workers",0))}
	if content.is_empty():return result
	var transition: Dictionary=_transition(state,rules)
	var unlock_stage: String=transition.get("to",current)
	for id in project_specs:
		if project_specs[id].stage_requires==unlock_stage:result.unlocks.append(id)
	if not active(state) or transition.is_empty():return result
	result.transition=transition.id;result.project=transition.project
	result.seasons=int(state.lifecycle.readiness.seasons) if state.lifecycle.readiness.transition==transition.id else 0
	var qualifying: bool=true
	for predicate in transition.readiness.all:
		var factor: Dictionary=_factor(state,predicate,rules)
		result.factors.append(factor);qualifying=qualifying and factor.met
	for group in transition.readiness.any:
		var alternatives: Array=[]
		var met: bool=false
		for predicate in group.predicates:
			var factor: Dictionary=_factor(state,predicate,rules)
			alternatives.append(factor);met=met or factor.met
		result.factors.append({"id":group.id,"current":int(met),"required":1,"met":met,"alternatives":alternatives})
		qualifying=qualifying and met
	result.qualifying=qualifying
	result.ready=qualifying and result.seasons>=result.required_seasons
	return result

func readiness(state: Dictionary,rules) -> Dictionary:return status(state,rules)

func command(state: Dictionary,action: Dictionary,rules) -> Dictionary:
	if action.get("kind")!="lifecycle_begin":return {"error":"lifecycle_unknown"}
	if state.role!="god":return {"error":"authority"}
	if active(state):return {"error":"lifecycle_started"}
	if content.is_empty():return {"error":"lifecycle_unknown"}
	if not rules.assets.active(state):return {"error":"lifecycle_assets"}
	if not rules.land.active(state):return {"error":"lifecycle_land"}
	if not rules.living.active(state):return {"error":"lifecycle_living"}
	if rules.base_snapshot.is_empty():return {"error":"lifecycle_fabric"}
	var next: Dictionary=state.duplicate(true)
	next.lifecycle={"version":1,"profile":content.profile,"revision":int(content.version),"definition_hash":definition_hash,"started":int(state.turn),"recognition":content.recognized_stage if state.town_achieved else "","readiness":{"transition":"","seasons":0,"last_turn":int(state.turn)}}
	var transition: Dictionary=_transition(next,rules)
	next.lifecycle.readiness.transition=transition.get("id","")
	rules._event(next,"lifecycle_adopted",{"profile":content.profile,"recognition":next.lifecycle.recognition})
	return {"state":next}

func blocked(state: Dictionary,id: String,rules) -> String:
	if not project_specs.has(id):return ""
	if not active(state):return "lifecycle_missing"
	if state.lifecycle.definition_hash!=definition_hash:return "lifecycle_definition"
	var project: Dictionary=project_specs[id]
	if _rank(stage(state,rules))<_rank(project.stage_requires):return "lifecycle_stage"
	for transition in content.transitions:
		if transition.project==id:
			if stage(state,rules)!=transition.from:return "lifecycle_stage"
			if not status(state,rules).ready:return "lifecycle_readiness"
	if int(state.food)<rules.people(state).size()*int(rules.balance.food_per_person)*int(balance.commission_reserve_seasons):return "lifecycle_reserves"
	if int(state.wood)>=int(project.wood) and int(state.wood)-int(project.wood)<int(balance.commission_wood_reserve):return "lifecycle_reserves"
	return ""

func advance(next: Dictionary,before: Dictionary,rules) -> void:
	if not active(next):return
	var promoted: bool=stage(next,rules)!=stage(before,rules)
	var transition: Dictionary=_transition(next,rules)
	var memory: Dictionary=next.lifecycle.readiness
	if promoted or memory.transition!=transition.get("id",""):
		memory.transition=transition.get("id","");memory.seasons=0;memory.last_turn=int(next.turn)
		if promoted:rules._event(next,"lifecycle_promoted",{"stage":stage(next,rules)})
		return
	if int(memory.last_turn)>=int(next.turn):return
	memory.last_turn=int(next.turn)
	if transition.is_empty():memory.seasons=0;return
	var result: Dictionary=status(next,rules)
	memory.seasons=mini(int(balance.readiness.sustained_seasons),int(memory.seasons)+1) if result.qualifying else 0

func requests(state: Dictionary,list: Array,rules) -> void:
	# Only an actual completed shelter carries staffing. Adoption recognition
	# grants no building and no automatic new duty; completion first affects the
	# next season's allocation, whose input is the previous authoritative state.
	if not active(state):return
	var civic: String=content.civic_project
	if rules.has_project(state,civic):
		rules.assets._request(list,"lifecycle_civic","care",int(balance.civic_workers),int(balance.civic_priority),project_specs[civic].asset)

func validate(state: Dictionary,rules) -> bool:
	var data: Variant=state.get("lifecycle",{})
	if not data is Dictionary:return false
	if data.is_empty():
		for item in state.completed+state.queue:
			if project_specs.has(item.id):return false
		return true
	if content.is_empty() or rules.base_snapshot.is_empty():return false
	if not rules.assets.active(state) or not rules.land.active(state) or not rules.living.active(state):return false
	var keys: Array=["version","profile","revision","definition_hash","started","recognition","readiness"]
	if data.size()!=keys.size():return false
	for key in keys:
		if not data.has(key):return false
	if data.version!=1 or data.profile!=content.profile or data.revision!=content.version or data.definition_hash!=definition_hash:return false
	if not rules.whole(data.started,0,int(state.turn)) or data.recognition not in ["",content.recognized_stage]:return false
	if data.recognition==content.recognized_stage and not state.town_achieved:return false
	# The adoption event is the immutable evidence for the recognition exception.
	var found: bool=false
	if not state.history is Array:return false
	for event in state.history:
		if not event is Dictionary:return false
		if event.get("kind")=="lifecycle_adopted":
			if not event.get("params") is Dictionary:return false
			if found or event.get("turn")!=data.started or event.get("params",{}).get("profile")!=data.profile or event.get("params",{}).get("recognition")!=data.recognition:return false
			found=true
	if not found:return false
	var memory: Variant=data.readiness
	if not memory is Dictionary or memory.size()!=3:return false
	for key in ["transition","seasons","last_turn"]:
		if not memory.has(key):return false
	if not memory.transition is String or not rules.whole(memory.seasons,0,int(balance.readiness.sustained_seasons)) or not rules.whole(memory.last_turn,int(state.turn),int(state.turn)):return false
	var transition: Dictionary=_transition(state,rules)
	if memory.transition!=transition.get("id","") or (transition.is_empty() and memory.seasons!=0):return false
	if memory.seasons>int(state.turn)-int(data.started):return false
	var achieved: String=content.recognized_stage if data.recognition!="" else content.initial_stage
	for item in state.completed:
		if not project_specs.has(item.id):continue
		if int(item.turn)<int(data.started) or _rank(achieved)<_rank(project_specs[item.id].stage_requires):return false
		for step in content.transitions:
			if step.project==item.id:
				if step.from!=achieved:return false
				achieved=step.to
	for item in state.queue:
		if not project_specs.has(item.id):continue
		if _rank(achieved)<_rank(project_specs[item.id].stage_requires):return false
		for step in content.transitions:
			if step.project==item.id and step.from!=achieved:return false
	return true
