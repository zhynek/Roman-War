extends RefCounted
## Optional civic continuity. Rank is derived from the existing completion ledger.
## Readiness has the only new temporal memory; no scene, random or clock authority.
var content: Dictionary
var balance: Dictionary
var project_specs: Dictionary = {}
var stages: Dictionary = {}
var definition_hash: String = ""
var town: Dictionary = {}
var town_balance: Dictionary = {}
var town_hash: String = ""
var town_projects: Dictionary = {}

func _init(config: Dictionary, tuning: Dictionary, town_tuning: Dictionary = {}, support: Dictionary = {}) -> void:
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
	# The published v1 hash above deliberately remains byte-for-byte unchanged.
	# Town is an explicitly adopted, independently pinned extension of that contract.
	town=content.get("town",{}).duplicate(true);town_balance=town_tuning.duplicate(true)
	if town.is_empty() or town_balance.is_empty():town={};return
	var town_semantics: Dictionary=town.duplicate(true)
	for project in town_semantics.projects:
		for key in ["title","body","presentation"]:project.erase(key)
		for change in project.changes:
			for object in change.after:object.erase("label")
	for site in town_semantics.sites:
		for key in ["title","use","beneficiaries"]:site.erase(key)
	town_hash=JSON.stringify({"base":definition_hash,"town":town_semantics,"tuning":town_balance,"support":support}).sha256_text()
	for project in town.projects:
		for key in ["wood","work","effects"]:project[key]=town_balance.projects[project.tuning][key]
		project_specs[project.id]=project;town_projects[project.id]=true
	content.projects.append_array(town.projects)
	content.sites.append_array(town.sites)
	content.proposals.append_array(town.proposals)

func active(state: Dictionary) -> bool:
	return state.get("lifecycle",{}) is Dictionary and not state.get("lifecycle",{}).is_empty()

func stage(state: Dictionary, _rules) -> String:
	var current: String=content.get("initial_stage","village_foundation")
	if not active(state):return current
	if state.lifecycle.recognition==content.recognized_stage:current=content.recognized_stage
	# Civic progression follows the same ordered ledger as physical continuity;
	# recognition is an entry rank, not a ceiling on later authored projects.
	for completed in state.completed:
		for transition in transitions(state):
			if transition.from==current and completed.id==transition.project:
				current=transition.to;break
	return current

func _rank(id: String) -> int:
	for i in range(content.stages.size()):
		if content.stages[i].id==id:return i
	return -1

func _transition(state: Dictionary,rules) -> Dictionary:
	var current: String=stage(state,rules)
	if town_active(state) and state.lifecycle.recognition==content.recognized_stage:
		for transition in transitions(state):
			if not rules.has_project(state,transition.project):return transition
	for transition in transitions(state):
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
	var factor: Dictionary={"id":predicate.id,"current":current,"required":required,"met":current>=required}
	if predicate.kind=="knowledge" and not factor.met and rules.living.active(state):
		# Practice only advances while an adult actually prepares or repairs.
		# Full prepared stores silently drop the preparation request, so name
		# that cause here instead of letting the factor stall unexplained.
		var capacity: int=int(rules.living.balance.blank_capacity)
		if int(state.living.prepare)==0:factor.suspended="order_off"
		elif int(state.living.blanks)>=capacity:factor.suspended="sets_full"
		factor.params={"blanks":int(state.living.blanks),"capacity":capacity}
	return factor

func status(state: Dictionary,rules) -> Dictionary:
	var current: String=stage(state,rules)
	var result: Dictionary={"stage":current,"stage_name":stages.get(current,{}).get("title",current),"recognition":state.get("lifecycle",{}).get("recognition",""),"transition":"","project":"","ready":false,"qualifying":false,"seasons":0,"required_seasons":int(balance.get("readiness",{}).get("sustained_seasons",0)),"factors":[],"unlocks":[],"upkeep":int(balance.get("civic_workers",0))}
	if content.is_empty():return result
	var transition: Dictionary=_transition(state,rules)
	if transition.get("readiness") is String:result.required_seasons=int(rules.balance.town_sustained_seasons)
	result.upkeep=int(town_balance.civic_workers) if not town.is_empty() and (transition.get("project")==town.transition.project or (town_active(state) and rules.has_project(state,town.transition.project))) else int(balance.civic_workers)
	var unlock_stage: String=transition.get("to",current)
	for id in project_specs:
		if project_specs[id].stage_requires==unlock_stage:result.unlocks.append(id)
	if not active(state) or transition.is_empty():return result
	result.transition=transition.id;result.project=transition.project
	result.seasons=int(state.lifecycle.readiness.seasons) if state.lifecycle.readiness.transition==transition.id else 0
	if town_active(state) and state.lifecycle.recognition==content.recognized_stage:
		result.ready=true;result.qualifying=true;result.required_seasons=0;result.seasons=0;result.recognized_fabric=true
		return result
	if transition.readiness is String:
		result.factors=rules.town_factors(state)
		result.qualifying=rules.town_conditions(state)
		result.ready=result.qualifying and result.seasons>=result.required_seasons
		return result
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
	if action.get("kind")=="lifecycle_town_begin":return adopt_town(state,rules)
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
	if town_projects.has(id) and not town_active(state):return "town_missing"
	if town_active(state) and state.lifecycle.town.definition_hash!=town_hash:return "town_definition"
	var project: Dictionary=project_specs[id]
	if _rank(stage(state,rules))<_rank(project.stage_requires):return "lifecycle_stage"
	for transition in transitions(state):
		if transition.project==id:
			var recognized: bool=town_active(state) and state.lifecycle.recognition==content.recognized_stage
			if stage(state,rules)!=transition.from and not recognized:return "lifecycle_stage"
			var readiness_: Dictionary=status(state,rules)
			if readiness_.project!=id or not readiness_.ready:return "lifecycle_readiness"
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
		if promoted:rules._event(next,"town_promoted" if stage(next,rules)=="town" else "lifecycle_promoted",{"stage":stage(next,rules)})
		return
	if int(memory.last_turn)>=int(next.turn):return
	memory.last_turn=int(next.turn)
	if transition.is_empty():memory.seasons=0;return
	var result: Dictionary=status(next,rules)
	memory.seasons=mini(int(result.required_seasons),int(memory.seasons)+1) if result.qualifying else 0

func requests(state: Dictionary,list: Array,rules) -> void:
	# Only an actual completed shelter carries staffing. Adoption recognition
	# grants no building and no automatic new duty; completion first affects the
	# next season's allocation, whose input is the previous authoritative state.
	if not active(state):return
	var civic: String=content.civic_project
	if rules.has_project(state,civic):
		var town_duty: bool=town_active(state) and rules.has_project(state,town.transition.project)
		rules.assets._request(list,"lifecycle_civic","care",int(town_balance.civic_workers if town_duty else balance.civic_workers),int(town_balance.civic_priority if town_duty else balance.civic_priority),project_specs[civic].asset)
	if town_active(state) and rules.has_project(state,"town_provision"):
		rules.assets._request(list,"town_service","care",int(town_balance.service_workers),int(town_balance.service_priority),"stores")

func validate(state: Dictionary,rules) -> bool:
	var data: Variant=state.get("lifecycle",{})
	if not data is Dictionary:return false
	if data.is_empty():
		if state.history is Array:
			for event in state.history:
				if event is Dictionary and event.get("kind") in ["lifecycle_adopted","town_adopted"]:return false
		for item in state.completed+state.queue:
			if project_specs.has(item.id):return false
		return true
	if content.is_empty() or rules.base_snapshot.is_empty():return false
	if not rules.assets.active(state) or not rules.land.active(state) or not rules.living.active(state):return false
	var keys: Array=["version","profile","revision","definition_hash","started","recognition","readiness"]
	if data.size()!=keys.size()+(1 if data.has("town") else 0):return false
	for key in keys:
		if not data.has(key):return false
	if not state.history is Array:return false
	if data.version!=1 or data.profile!=content.profile or data.revision!=content.version or data.definition_hash!=definition_hash:return false
	if not rules.whole(data.started,0,int(state.turn)) or data.recognition not in ["",content.recognized_stage]:return false
	if data.recognition==content.recognized_stage and not state.town_achieved:return false
	if not validate_town(state,rules):return false
	# The adoption event is the immutable evidence for the recognition exception.
	var found: bool=false
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
	if not memory.transition is String or not rules.whole(memory.seasons,0,int(rules.balance.town_sustained_seasons) if town_active(state) and memory.transition==town.transition.id else int(balance.readiness.sustained_seasons)) or not rules.whole(memory.last_turn,int(state.turn),int(state.turn)):return false
	var transition: Dictionary=_transition(state,rules)
	if memory.transition!=transition.get("id","") or (transition.is_empty() and memory.seasons!=0):return false
	if memory.seasons>int(state.turn)-int(data.started):return false
	var achieved: String=content.recognized_stage if data.recognition!="" else content.initial_stage
	for item in state.completed:
		if not project_specs.has(item.id):continue
		if int(item.turn)<int(data.started) or _rank(achieved)<_rank(project_specs[item.id].stage_requires):return false
		for step in transitions(state):
			if step.project==item.id:
				if step.from!=achieved and not (town_active(state) and data.recognition==content.recognized_stage):return false
				if _rank(step.to)>_rank(achieved):achieved=step.to
	for item in state.queue:
		if not project_specs.has(item.id):continue
		if _rank(achieved)<_rank(project_specs[item.id].stage_requires):return false
		for step in transitions(state):
			if step.project==item.id and step.from!=achieved and not (town_active(state) and data.recognition==content.recognized_stage):return false
	return true

func town_active(state: Dictionary) -> bool:
	return active(state) and state.lifecycle.get("town") is Dictionary and not state.lifecycle.town.is_empty()

func available(state: Dictionary,id: String) -> bool:
	return not town_projects.has(id) or town_active(state)

func transitions(state: Dictionary) -> Array:
	var result: Array=content.get("transitions",[]).duplicate()
	if town_active(state) and not town.is_empty():result.append(town.transition)
	return result

func adopt_town(state: Dictionary,rules) -> Dictionary:
	if state.role!="god":return {"error":"authority"}
	if not active(state):return {"error":"lifecycle_missing"}
	if town_active(state):return {"error":"town_started"}
	if town.is_empty():return {"error":"lifecycle_unknown"}
	if not validate(state,rules):return {"error":"lifecycle_definition"}
	var next: Dictionary=state.duplicate(true)
	next.lifecycle.town={"version":1,"profile":town.profile,"definition_hash":town_hash,"started":int(state.turn)}
	var transition: Dictionary=_transition(next,rules)
	if next.lifecycle.readiness.transition!=transition.get("id",""):
		next.lifecycle.readiness={"transition":transition.get("id",""),"seasons":0,"last_turn":int(state.turn)}
	rules._event(next,"town_adopted",{"profile":town.profile,"definition_hash":town_hash})
	return {"state":next}

func validate_town(state: Dictionary,rules) -> bool:
	var data: Variant=state.lifecycle.get("town")
	if not state.lifecycle.has("town"):
		for event in state.history:
			if event is Dictionary and event.get("kind")=="town_adopted":return false
		for item in state.completed+state.queue:
			if town_projects.has(item.id):return false
		return true
	if not data is Dictionary or data.size()!=4 or town.is_empty():return false
	if data.get("version")!=1 or data.get("profile")!=town.profile or data.get("definition_hash")!=town_hash or not rules.whole(data.get("started"),int(state.lifecycle.started),int(state.turn)):return false
	var found: bool=false
	for event in state.history:
		if not event is Dictionary:return false
		if event.get("kind")=="town_adopted":
			if found or event.get("turn")!=data.started or event.get("params")!={"profile":town.profile,"definition_hash":town_hash}:return false
			found=true
	for item in state.completed:
		if town_projects.has(item.id) and item.turn<data.started:return false
	return found

func operation(state: Dictionary,allocation_: Dictionary,rules) -> Dictionary:
	var result: Dictionary={"wanted":0,"filled":0,"condition":int(state.get("assets",{}).get("conditions",{}).get("stores",0)),"required":int(rules.assets.balance.get("condition_threshold",0)),"civic":false,"maintained":false,"service":0,"service_wanted":0,"prepared":0,"saved":0}
	if not town_active(state) or not rules.has_project(state,town.transition.project):return result
	result.wanted=int(town_balance.civic_workers)
	result.service_wanted=int(town_balance.service_workers) if rules.has_project(state,"town_provision") else 0
	for request in allocation_.get("requests",[]):
		if request.id=="lifecycle_civic":result.filled=int(request.filled)
		if request.id=="town_service":result.service=int(request.filled)
	result.civic=result.filled==result.wanted
	result.maintained=result.condition>=result.required
	if result.civic and result.maintained and result.service==int(town_balance.service_workers) and rules.has_project(state,"town_provision"):
		result.saved=mini(int(town_balance.spoil_reduction),int(state.food)*int(rules.balance.spoil_percent)/100)
	result.prepared=int(allocation_.get("town_prepared",0))
	return result

func apply_allocation(state: Dictionary,result: Dictionary,timber_left: int,places: int,rules) -> void:
	if not town_active(state) or not rules.has_project(state,"town_preparation"):return
	var op: Dictionary=operation(state,result,rules)
	if not op.civic or not op.maintained or int(result.living.prepared)==0:return
	if timber_left<int(town_balance.preparation_wood) or places<int(town_balance.preparation_places):return
	var extra: int=mini(int(town_balance.preparation_bonus),int(rules.living.balance.blank_capacity)-int(state.living.blanks)-int(result.living.prepared))
	if extra<=0:return
	result.living.prepared+=extra
	result.living.prepare_wood+=int(town_balance.preparation_wood)
	result.town_prepared=extra

func site_available(state: Dictionary,id: String) -> bool:
	if town_active(state):return true
	for site in town.get("sites",[]):
		if site.id==id:return false
	return true
