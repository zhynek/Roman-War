extends RefCounted
## Pure read model. No commands, work, inventory, RNG or save fields live here.
var copy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/construction.json"))

static func benefit_values(rules,id: String) -> Dictionary:
	# The target is an authoring assertion. Display the actual incremental
	# effects/site capacity so prose cannot become a second source of balance.
	var spec: Dictionary=rules.projects[id]
	var town: Dictionary=rules.lifecycle.town_balance
	if id=="town_civic":return {"workers":town.civic_workers}
	if id=="town_preparation":return {"delta":town.preparation_bonus,"total":1+int(town.preparation_bonus),"shared_total":int(rules.living.balance.cooperative_yield)+int(town.preparation_bonus),"wood":town.preparation_wood,"places":town.preparation_places}
	if id=="town_provision":return {"delta":town.spoil_reduction,"total":town.spoil_reduction,"workers":town.service_workers}
	var target: Dictionary=spec.get("benefit_target",{})
	if target.is_empty():return {}
	var key: String=target.key
	if target.kind=="effect_total":
		var delta: int=int(spec.effects.get(key,0))
		var total: int=delta
		var predecessor: String=target.predecessor
		var seen: Dictionary={}
		seen[id]=true
		while not predecessor.is_empty() and rules.projects.has(predecessor) and not seen.has(predecessor):
			seen[predecessor]=true
			var previous: Dictionary=rules.projects[predecessor]
			total+=int(previous.effects.get(key,0))
			predecessor=previous.get("benefit_target",{}).get("predecessor","")
		return {"delta":delta,"total":total}
	if target.kind=="site_total" and rules.land.proposals.has(id) and rules.land.proposals.has(target.predecessor):
		var total: int=int(rules.land.proposals[id].get(key,0))
		return {"delta":total-int(rules.land.proposals[target.predecessor].get(key,0)),"total":total}
	return {}

static func text_for(rules,id: String,template: String) -> String:
	var values: Dictionary=benefit_values(rules,id)
	values.merge({"wellbeing":rules.balance.wellbeing_care,"cooperation":rules.balance.cooperation_care})
	return template.format(values) if not values.is_empty() else template

static func belongs_to(rules,id: String,asset: String) -> bool:
	# Related places are presentation aliases, never a second allocation owner.
	return rules.assets.project_assets.get(id,"")==asset or asset in rules.projects[id].get("presentation",{}).get("related_assets",[])

func queued(state: Dictionary,id: String) -> Dictionary:
	for item in state.queue:
		if item.id==id:return item
	return {}

func describe(state: Dictionary,rules,id: String,forecast: Dictionary={},include_people: bool=false) -> Dictionary:
	var spec: Dictionary=rules.projects[id]
	var q: Dictionary=queued(state,id)
	var done: bool=rules.has_project(state,id)
	var committed: bool=done or not q.is_empty()
	var progress: int=int(spec.work) if done else int(q.get("progress",0))
	var stage: int=4 if done else mini(3,progress*4/int(spec.work))
	var initiative: Dictionary=state.get("assets",{}).get("initiatives",{}).get(id,{})
	var a: Dictionary=forecast.get("assets",{})
	if a.is_empty() and rules.assets.active(state):a=rules.assets.allocation(state,rules)
	var allocation_: Dictionary=a.get("projects",{}).get(id,{"crew":0,"work":0})
	if not rules.assets.active(state) and not q.is_empty():
		var manual: Dictionary=rules.forecast(state) if forecast.is_empty() else forecast
		var remaining_work: int=int(manual.work)
		for item in state.queue:
			var work: int=mini(remaining_work,int(rules.projects[item.id].work)-int(item.progress))
			if item.id==id:
				allocation_={"crew":int(manual.plan.building) if work>0 else 0,"work":work};initiative={"crew":int(manual.plan.building)};break
			remaining_work-=work
	var blanks: int=0
	if rules.incidents.project_specs.has(id):blanks=int(rules.incidents.project_specs[id].blanks)
	elif id=="living_watch_kits":blanks=int(rules.balance.living.kit_inputs)
	var status: String="complete" if done else "available"
	var cause: String="complete" if done else "unpaid"
	var refusal: String=""
	var request: Dictionary={}
	for r in a.get("requests",[]):
		if r.id==id:request=r;break
	if not q.is_empty():
		status="active";cause="ready"
		if not rules.assets.active(state):cause="manual"
		elif initiative.get("paused",false):status="paused";cause="paused"
		elif int(initiative.get("crew",0))==0:status="none";cause="crew"
		elif request.get("reason","")=="access":
			status="blocked";cause="access_labor"
			if rules.incidents.access_impaired(state):cause="access_incident"
			elif not state.land.access_enabled:cause="access_disabled"
			else:
				for r in a.get("requests",[]):
					if r.id=="land_access" and r.reason=="materials":cause="access_materials"
		elif request.get("reason","") in ["labor","space"]:status="labor";cause=request.reason
		elif int(state.assets.conditions.workroom)<int(rules.assets.balance.condition_threshold):cause="workroom"
	elif not done:
		refusal=rules.quote(state,{"kind":"commission","id":id}).get("error","")
		if refusal!="":status="blocked"
	var assigned: Array=[]
	if include_people and not q.is_empty() and rules.assets.active(state):
		for task in rules.assets.assignments(state,rules):
			if task.get("duty","")==id:assigned.append(task.id)
	var presentation: Dictionary=spec.get("presentation",copy.projects.get(id,{}))
	var treatment: String=presentation.treatment
	var affected: Array=[]
	for change in spec.changes:
		for record in change.after:
			if record.kind in ["building","boundary"]:affected.append(record.id)
	if affected.is_empty() and rules.land.proposals.has(id):affected=rules.land.sites[rules.land.proposals[id].site].objects.duplicate()
	if id=="living_shared_room":affected=[copy.room.building]
	return {"id":id,"asset":rules.assets.project_assets.get(id,"yard"),"affected":affected,"status":status,"cause":cause,"refusal":refusal,"queued":not q.is_empty(),"complete":done,"committed":committed,"paid_wood":int(spec.wood) if committed else 0,"paid_blanks":blanks if committed else 0,"cost_wood":int(spec.wood),"cost_blanks":blanks,"progress":progress,"total":int(spec.work),"remaining":int(spec.work)-progress,"stage":stage,"stage_label":copy.stages[treatment][stage],"treatment":treatment,"crew":int(allocation_.crew),"limit":int(initiative.get("crew",0)),"work":int(allocation_.work),"priority":int(initiative.get("priority",2)),"paused":initiative.get("paused",false),"adults":rules.people(state,true).size(),"places":int(rules.land.totals(state,rules).work) if rules.land.active(state) else rules.people(state,true).size(),"assigned":assigned,"requires":spec.requires.duplicate(),"benefit":text_for(rules,id,presentation.benefit),"refund_wood":int(spec.wood)*(int(spec.work)-progress)/int(spec.work) if not q.is_empty() else 0,"refund_blanks":blanks*(int(spec.work)-progress)/int(spec.work) if not q.is_empty() else 0}

func ids(state: Dictionary,rules) -> Array:
	var result: Array=[]
	for id in rules.projects:
		if rules.warfare.forts.projects.has(id) and not rules.warfare.active(state):continue
		if rules.lifecycle.project_specs.has(id) and (not rules.lifecycle.active(state) or not rules.lifecycle.available(state,id)):continue
		if rules.land.active(state) and id in rules.land.content.legacy_projects and not rules.land.committed(state,id,rules):continue
		if rules.land.proposals.has(id) and not rules.land.active(state):continue
		if id.begins_with("living_") and not rules.living.active(state):continue
		if rules.incidents.project_specs.has(id) and not rules.land.committed(state,id,rules):
			var current: Dictionary=rules.incidents.current(state)
			if current.is_empty() or int(current.known)<0:continue
			var spec: Dictionary=rules.incidents.specs[current.id]
			if id not in [spec.prepare,spec.repair]:continue
			if id==spec.repair and current.outcome.is_empty():continue
		result.append(id)
	result.sort_custom(func(a,b):
		var ar: int=0 if not queued(state,a).is_empty() else (2 if rules.has_project(state,a) else 1)
		var br: int=0 if not queued(state,b).is_empty() else (2 if rules.has_project(state,b) else 1)
		return a<b if ar==br else ar<br)
	return result
