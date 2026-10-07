extends RefCounted
## Pure read model. No commands, work, inventory, RNG or save fields live here.
var copy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/construction.json"))

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
	var treatment: String=copy.projects[id].treatment
	var affected: Array=[]
	for change in spec.changes:
		for record in change.after:
			if record.kind=="building":affected.append(record.id)
	if affected.is_empty() and rules.land.proposals.has(id):affected=rules.land.sites[rules.land.proposals[id].site].objects.duplicate()
	if id=="living_shared_room":affected=[copy.room.building]
	return {"id":id,"asset":rules.assets.project_assets.get(id,"yard"),"affected":affected,"status":status,"cause":cause,"refusal":refusal,"queued":not q.is_empty(),"complete":done,"committed":committed,"paid_wood":int(spec.wood) if committed else 0,"paid_blanks":blanks if committed else 0,"cost_wood":int(spec.wood),"cost_blanks":blanks,"progress":progress,"total":int(spec.work),"remaining":int(spec.work)-progress,"stage":stage,"stage_label":copy.stages[treatment][stage],"treatment":treatment,"crew":int(allocation_.crew),"limit":int(initiative.get("crew",0)),"work":int(allocation_.work),"priority":int(initiative.get("priority",2)),"paused":initiative.get("paused",false),"adults":rules.people(state,true).size(),"places":int(rules.land.totals(state,rules).work) if rules.land.active(state) else rules.people(state,true).size(),"assigned":assigned,"requires":spec.requires.duplicate(),"benefit":copy.projects[id].benefit,"refund_wood":int(spec.wood)*(int(spec.work)-progress)/int(spec.work) if not q.is_empty() else 0,"refund_blanks":blanks*(int(spec.work)-progress)/int(spec.work) if not q.is_empty() else 0}

func ids(state: Dictionary,rules) -> Array:
	var result: Array=[]
	for id in rules.projects:
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
