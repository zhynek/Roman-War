extends RefCounted
## Optional spatial semantics. The original project queue/completions remain the
## only construction ledger. Site reservation and use are derived, never copied.
var content: Dictionary
var balance: Dictionary
var sites: Dictionary = {}
var proposals: Dictionary = {}

func _init(config: Dictionary, tuning: Dictionary) -> void:
	content=config;balance=tuning
	for item in content.get("sites",[]):sites[item.id]=item
	for item in content.get("proposals",[]):proposals[item.id]=item

func active(state: Dictionary) -> bool:
	return state.get("land",{}) is Dictionary and not state.get("land",{}).is_empty()

func committed(state: Dictionary,id: String,rules) -> bool:
	if rules.has_project(state,id):return true
	for item in state.queue:
		if item.id==id:return true
	return false

func use_at(state: Dictionary,site: String,rules) -> String:
	for p in content.proposals:
		if p.site==site and committed(state,p.id,rules):return p.id
	return ""

func totals(state: Dictionary,rules) -> Dictionary:
	var result: Dictionary={"food":0,"work":0,"cooperation":0}
	if not active(state):return result
	for site in content.sites:
		var id: String=use_at(state,site.id,rules)
		# Retained fabric keeps its contribution during adaptation. Conversion
		# closes the whole former use from paid staging until cancellation.
		var use: Dictionary=site
		if not id.is_empty() and (rules.has_project(state,id) or not proposals[id].retain):
			use=proposals[id] if rules.has_project(state,id) else {"food":0,"work":0,"cooperation":0}
		result.food+=int(use.food)-int(site.food)
		result.work+=int(use.work)
		result.cooperation+=int(use.cooperation)-int(site.cooperation)
	return result

func needs_access(state: Dictionary,rules) -> bool:
	return active(state) and rules.has_project(state,"land_outer_access")

func access_ready(state: Dictionary,allocation_: Dictionary,rules) -> bool:
	return not rules.incidents.access_impaired(state) and needs_access(state,rules) and int(allocation_.get("access_workers",0))==int(balance.access_workers) and int(allocation_.get("access_cost",0))==int(balance.access_wood)

func occupied_outer(state: Dictionary,rules) -> bool:
	for person in rules.people(state):
		if person.household in ["land_outer_west_household","land_outer_east_household"]:return true
	return false

func blocked(state: Dictionary,id: String,rules) -> String:
	if not proposals.has(id):
		if active(state) and id in content.legacy_projects:return "land_choice"
		return ""
	if not active(state):return "land_missing"
	var proposal: Dictionary=proposals[id]
	for other in content.proposals:
		if other.id==id or not committed(state,other.id,rules):continue
		if other.site==proposal.site or (proposal.choice_group!="" and proposal.choice_group==other.choice_group):return "land_conflict"
	if proposal.requires_access and not access_ready(state,rules.assets.allocation(state,rules),rules):return "land_access"
	if int(state.food)<rules.people(state).size()*int(balance.minimum_reserve):return "asset_supplies"
	# A future removal cannot silently erase an occupied home. This phase only
	# adapts nonresidential fabric; residential replacements need a new explicit
	# accommodation command and relationship, not this commissioning shortcut.
	for change in rules.projects[id].changes:
		for home in rules.content.households:
			if home.building_id not in change.before:continue
			var retains: bool=false
			for after in change.after:
				if after.id==home.building_id and after.get("use","")=="dwelling":retains=true
			if not retains:
				for person in rules.people(state):
					if person.household==home.id:return "land_accommodation"
	return ""

func foundation(state: Dictionary,id: String,rules) -> bool:
	if rules.has_project(state,id):return true
	if active(state):
		for alternative in content.alternatives.get(id,[]):
			if rules.has_project(state,alternative):return true
	return false

func growth_ready(state: Dictionary,rules) -> bool:
	return rules.capacity(state)>=int(rules.balance.town_dwellings)*int(rules.balance.people_per_dwelling) and state.food>=(rules.people(state).size()+int(rules.balance.migration_size))*int(rules.balance.migration_reserve_seasons)

func tutorial_ready(state: Dictionary,rules) -> bool:
	if state.land.tutorial>=content.tutorial.size():return false
	match content.tutorial[state.land.tutorial].condition:
		"inspect":return "clay_court" in state.land.inspected and "north_west" in state.land.inspected
		"prepare":
			for id in ["land_adapt_workroom","land_outer_access","land_cultivate"]:
				if committed(state,id,rules):return true
		"commission":
			for id in proposals:
				if proposals[id].choice_group!="" and committed(state,id,rules):return true
		"season":return not state.land.report.is_empty()
		"growth":return growth_ready(state,rules)
	return false

func command(state: Dictionary,action: Dictionary,rules) -> Dictionary:
	var next: Dictionary=state.duplicate(true)
	var kind: String=action.get("kind","")
	if kind=="land_begin":
		if state.role!="god":return {"error":"authority"}
		if content.is_empty():return {"error":"land_unknown"}
		if active(state):return {"error":"land_started"}
		if not rules.assets.active(state):return {"error":"asset_missing"}
		next.land={"version":1,"started":int(state.turn),"inspected":[],"tutorial":0,"access_enabled":true,"report":{}}
		return {"state":next}
	if not active(state):return {"error":"land_missing"}
	match kind:
		"land_inspect":
			var id: String=action.get("id","")
			if not sites.has(id):return {"error":"land_unknown"}
			if id not in next.land.inspected:next.land.inspected.append(id)
		"land_access":
			if not rules.permitted(state,"steward"):return {"error":"authority"}
			if not action.get("enabled") is bool:return {"error":"land_unknown"}
			next.land.access_enabled=action.enabled
			rules.assets._record(next,"steward",kind,"north_access",rules,{"enabled":action.enabled})
		"land_review":
			if not tutorial_ready(state,rules):return {"error":"land_review"}
			next.land.tutorial+=1
		_:return {"error":"land_unknown"}
	return {"state":next}

func advance(next: Dictionary,before: Dictionary,forecast: Dictionary) -> void:
	if not active(before):return
	next.wood-=int(forecast.assets.access_cost)
	next.land.report={"turn":int(before.turn),"food":int(forecast.land.food),"wood":int(forecast.assets.access_cost),"work":int(forecast.land.work),"access":bool(forecast.land.access)}

func validate(state: Dictionary,rules) -> bool:
	var l: Variant=state.get("land",{})
	if not l is Dictionary:return false
	if l.is_empty():
		for id in proposals:
			if committed(state,id,rules):return false
		return true
	if content.is_empty() or not rules.assets.active(state) or l.size()!=6:return false
	if not rules.whole(l.get("version"),1,1) or not rules.whole(l.get("started"),0,int(state.turn)) or not rules.whole(l.get("tutorial"),0,content.tutorial.size()):return false
	if not l.get("access_enabled") is bool or not l.get("inspected") is Array or l.inspected.size()>sites.size():return false
	var seen: Array=[]
	for id in l.inspected:
		if not sites.has(id) or id in seen:return false
		seen.append(id)
	var used: Array=[]
	var groups: Array=[]
	for p in content.proposals:
		if not committed(state,p.id,rules):continue
		if p.site in used or (p.choice_group!="" and p.choice_group in groups):return false
		used.append(p.site);groups.append(p.choice_group)
	var occupants: Dictionary={}
	for person in rules.people(state):occupants[person.household]=int(occupants.get(person.household,0))+1
	for home in rules.content.households:
		if int(occupants.get(home.id,0))>int(rules.balance.people_per_dwelling):return false
		if occupants.has(home.id) and home.requires!="" and not rules.has_project(state,home.requires):return false
	if not l.get("report") is Dictionary:return false
	if not l.report.is_empty():
		if l.report.size()!=5 or not rules.whole(l.report.get("turn"),0,maxi(0,int(state.turn)-1)) or not l.report.get("access") is bool:return false
		for key in ["food","wood","work"]:
			if not rules.whole(l.report.get(key),-1000,1000):return false
	return true
