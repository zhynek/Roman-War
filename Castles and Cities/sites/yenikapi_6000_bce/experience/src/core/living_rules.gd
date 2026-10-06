extends RefCounted
## Seasonal wood, knowledge and preparedness. No scene, clock or random authority.
var content: Dictionary
var balance: Dictionary
var areas: Dictionary={}
var subjects: Dictionary={}
func _init(config: Dictionary,tuning: Dictionary) -> void:
	content=config;balance=tuning
	for a in content.get("areas",[]):areas[a.id]=a;subjects[a.id]=a
	for a in content.get("posts",[]):subjects[a.id]=a
	for a in content.get("households",[]):subjects[a.id]=a
	if not content.is_empty():subjects.workroom={};subjects.store={}
func active(s: Dictionary) -> bool:return s.get("living",{}) is Dictionary and not s.get("living",{}).is_empty()
func command(s: Dictionary,a: Dictionary,r) -> Dictionary:
	var n: Dictionary=s.duplicate(true)
	if a.kind=="living_begin":
		if s.role!="god":return {"error":"authority"}
		if active(s):return {"error":"living_started"}
		if content.is_empty() or not r.land.active(s):return {"error":"living_missing"}
		n.living={"version":1,"started":int(s.turn),"area":content.areas[0].id,"prepare":0,"cooperate":false,"training":false,"repair":true,"patrol":content.posts[0].id,"woodland":{},"experience":{},"inspected":[],"discoveries":{},"meetings":0,"practice":0,"blanks":int(balance.initial_blanks),"kits":0,"readiness":0,"wear_total":0,"tutorial":0,"report":{}}
		for id in areas:n.living.woodland[id]=int(areas[id].capacity)
		for home in r.content.households:n.living.experience[home.id]={"woodland":0,"shaping":0}
		for home in content.households:
			for key in ["woodland","shaping"]:n.living.experience[home.id][key]=int(home[key])
		return {"state":n}
	if not active(s):return {"error":"living_missing"}
	var id: String=a.get("id","")
	match a.kind:
		"living_inspect":
			if not subjects.has(id):return {"error":"living_unknown"}
			if id not in n.living.inspected:n.living.inspected.append(id)
			for d in content.discoveries:
				if id in d.subjects and eligible(s,d.condition,r) and not n.living.discoveries.has(d.id):n.living.discoveries[d.id]=int(s.turn)
		"living_order":
			if not r.permitted(s,"watch" if id in ["training","repair","patrol"] else "steward"):return {"error":"authority"}
			var v: Variant=a.get("value")
			match id:
				"area":
					if not v is String or not areas.has(v):return {"error":"living_unknown"}
				"prepare":
					if not r.whole(v,0,2):return {"error":"living_unknown"}
					if v==2 and not r.has_project(s,"living_shared_room"):return {"error":"living_room"}
				"cooperate","training","repair":
					if not v is bool:return {"error":"living_unknown"}
					if id=="cooperate" and v and not s.living.discoveries.has("cooperation"):return {"error":"living_discovery"}
				"patrol":
					if v not in ["landing_post","north_post"]:return {"error":"living_unknown"}
				_:return {"error":"living_unknown"}
			n.living[id]=v
			r.assets._record(n,"watch" if id in ["training","repair","patrol"] else "steward",a.kind,id,r,{"value":v})
		"living_review":
			if not tutorial_ready(s,r):return {"error":"living_review"}
			n.living.tutorial+=1
		_:return {"error":"living_unknown"}
	return {"state":n}
func paired(s: Dictionary,r) -> bool:
	for h in content.households:
		var found: bool=false
		for p in r.people(s,true):
			if p.household==h.id:found=true;break
		if not found:return false
	return true
func eligible(s: Dictionary,condition: String,r) -> bool:
	match condition:
		"always":return true
		"woodland":return int(s.living.experience[content.households[0].id].woodland)>0
		"shaping":return int(s.living.experience[content.households[1].id].shaping)>0
		"meeting":return s.living.meetings>0 and paired(s,r) and s.living.discoveries.has("woodland_interest") and s.living.discoveries.has("shaping_interest")
		"wear":return s.living.wear_total>0
	return false
func blocked(s: Dictionary,id: String,r) -> String:
	if not id.begins_with("living_"):return ""
	if not active(s):return "living_missing"
	if id=="living_watch_kits" and s.living.blanks<balance.kit_inputs:return "living_materials"
	return ""
func commission(n: Dictionary,id: String) -> void:
	if id=="living_watch_kits":n.living.blanks-=int(balance.kit_inputs)
func cancel(n: Dictionary,item: Dictionary,r) -> void:
	if item.id=="living_watch_kits":n.living.blanks=mini(int(balance.blank_capacity),int(n.living.blanks)+int(balance.kit_inputs)*(int(r.projects[item.id].work)-int(item.progress))/int(r.projects[item.id].work))
func requests(s: Dictionary,list: Array,r) -> void:
	if not active(s):return
	var l: Dictionary=s.living
	if l.prepare>0 and l.blanks<balance.blank_capacity:
		r.assets._request(list,"living_prepare","building",int(balance.shared_workers if l.prepare==2 else balance.prepare_workers),int(balance.priority),"workroom")
	if l.repair and l.kits<balance.kit_capacity and r.has_project(s,"living_watch_kits"):
		r.assets._request(list,"living_repair","building",int(balance.repair_workers),3,"watch")
	if l.training:r.assets._request(list,"living_training","watch",int(balance.training_workers),int(balance.priority),"watch")
func prepare_allocation(s: Dictionary,result: Dictionary) -> void:
	result.living={"fuel":mini(int(s.wood),int(balance.fuel)),"prepare_wood":0,"support":0,"repair_wood":0,"prepared":0,"repaired":0,"training_workers":0,"shared":false}
func allocate(s: Dictionary,request: Dictionary,count: int,wood_left: int,places: int,result: Dictionary,r) -> Dictionary:
	var cost: int=0
	if request.id=="living_prepare":
		var support: int=int(balance.support_wood) if s.living.prepare==2 else 0
		if count<int(request.wanted):count=0;request.reason="labor"
		elif s.living.prepare==2 and not paired(s,r):count=0;request.reason="labor"
		elif places<count:count=0;request.reason="space"
		elif wood_left<int(balance.prepare_wood)+support:count=0;request.reason="materials"
		if count>0:
			cost=int(balance.prepare_wood)+support
			result.living.prepare_wood=int(balance.prepare_wood);result.living.support=support;result.living.shared=s.living.prepare==2
			var output: int=int(balance.cooperative_yield) if result.living.shared and s.living.cooperate and s.living.practice>=balance.practice_needed else 1
			result.living.prepared=mini(output,int(balance.blank_capacity)-int(s.living.blanks));places-=count
	elif request.id=="living_repair":
		if count<int(request.wanted):count=0;request.reason="labor"
		elif wood_left<int(balance.repair_wood) or s.living.blanks<1:count=0;request.reason="materials"
		if count>0:cost=int(balance.repair_wood);result.living.repair_wood=cost;result.living.repaired=1
	elif request.id=="living_training":result.living.training_workers=count
	return {"count":count,"wood":wood_left-cost,"places":places}
func forecast(s: Dictionary,allocation_: Dictionary,r) -> Dictionary:
	var f: Dictionary=allocation_.living.duplicate(true)
	var l: Dictionary=s.living
	var area_id: String="west_wood" if r.incidents.restricted(s,"approach") else l.area
	var area: Dictionary=areas[area_id]
	var watch: int=0
	for request in allocation_.requests:
		if request.id=="watch":watch=int(request.filled)
	var post: String=""
	for spec in content.posts:
		if spec.id==l.patrol:post=spec.project
	var covered: bool=r.has_project(s,post) and watch>0 and s.assets.conditions.watch>=r.assets.balance.condition_threshold
	var supported: bool=covered and l.patrol=="north_post" and watch>=balance.north_workers
	var distance: int=0 if supported else int(area.distance_cost)
	f.workers=int(allocation_.plan.timber)
	f.harvest=mini(int(l.woodland[area_id]),f.workers*maxi(0,int(area.yield)-distance))
	if area_id=="north_wood":f.harvest=maxi(0,int(f.harvest)-r.incidents.timber_penalty(s))
	f.harvest=maxi(0,int(f.harvest)-r.incidents.restriction_timber(s))
	f.area=area_id;f.distance=distance;f.yield=int(area.yield);f.next_stock=mini(int(area.capacity),int(l.woodland[area_id])-int(f.harvest)+int(area.recovery))
	f.fuel_need=int(balance.fuel)
	f.equipped=mini(watch,int(l.kits))
	f.wear=1 if f.equipped>0 and (int(s.turn)-int(l.started)+1)%int(balance.wear_period)==0 else 0
	f.training=int(l.readiness)
	f.equipment_security=int(f.equipped)*mini(int(balance.equipment_security),int(l.readiness))
	f.coverage=int(balance.coverage_security) if covered else 0
	f.fuel_penalty=-int(balance.fuel_penalty) if f.fuel<int(balance.fuel) else 0
	return f
func advance(n: Dictionary,s: Dictionary,f: Dictionary,r) -> void:
	if not active(s):return
	var v: Dictionary=f.living
	n.wood-=int(v.fuel)+int(v.prepare_wood)+int(v.support)+int(v.repair_wood)
	var l: Dictionary=n.living
	l.blanks+=int(v.prepared)-int(v.repaired)
	l.kits=clampi(int(l.kits)+int(v.repaired)-int(v.wear),0,int(balance.kit_capacity))
	if r.has_project(n,"living_watch_kits") and not r.has_project(s,"living_watch_kits"):l.kits=int(balance.kit_capacity)
	l.wear_total+=int(v.wear)
	if v.training_workers>0 and s.living.kits>0:l.readiness=mini(int(balance.training_max),int(l.readiness)+1)
	for id in areas:l.woodland[id]=mini(int(areas[id].capacity),int(l.woodland[id])-(int(v.harvest) if id==v.area else 0)+int(areas[id].recovery))
	if v.shared:
		l.meetings+=1
		if l.cooperate:l.practice=mini(int(balance.practice_needed),int(l.practice)+1)
	var practiced: Dictionary={}
	for task in n.assignments:
		var p: Dictionary=r.person_by_id(s,task.id)
		var skill: String="woodland" if task.duty=="timber" else "shaping" if task.duty in ["living_prepare","living_repair"] else ""
		var key: String=p.household+skill
		if skill.is_empty() or practiced.has(key):continue
		practiced[key]=true;l.experience[p.household][skill]=mini(int(balance.experience_max),int(l.experience[p.household][skill])+1)
	l.report=v.duplicate(true);l.report.turn=int(s.turn)
func destination(s: Dictionary,request: Dictionary,fallback: Array) -> Array:
	if not active(s):return fallback
	if request.id=="timber":return areas[s.living.area].at
	if request.id in ["watch","living_training","living_repair"]:return subjects[s.living.patrol].at
	return fallback
func tutorial_ready(s: Dictionary,r) -> bool:
	var l: Dictionary=s.living
	if l.tutorial>=content.tutorial.size():return false
	match content.tutorial[l.tutorial].condition:
		"area":return "west_wood" in l.inspected or "north_wood" in l.inspected
		"store":return "store" in l.inspected
		"interests":return l.discoveries.has("woodland_interest") and l.discoveries.has("shaping_interest")
		"cooperate":return l.cooperate
		"kits":return r.has_project(s,"living_watch_kits") or r.land.committed(s,"living_watch_kits",r)
		"result":return not l.report.is_empty() and l.report.equipped>0
		"recover":return l.prepare==0 and not l.report.is_empty() and l.report.prepared>0
	return false
func validate(s: Dictionary,r) -> bool:
	var l: Variant=s.get("living",{})
	if not l is Dictionary:return false
	if l.is_empty():
		for p in content.get("projects",[]):
			if r.land.committed(s,p.id,r):return false
		return true
	if content.is_empty() or not r.land.active(s) or l.size()!=20:return false
	for pair in [["version",1,1],["started",0,s.turn],["prepare",0,2],["meetings",0,s.turn],["practice",0,balance.practice_needed],["blanks",0,balance.blank_capacity],["kits",0,balance.kit_capacity],["readiness",0,balance.training_max],["wear_total",0,s.turn],["tutorial",0,content.tutorial.size()]]:
		if not r.whole(l.get(pair[0]),int(pair[1]),int(pair[2])):return false
	for key in ["cooperate","training","repair"]:
		if not l.get(key) is bool:return false
	if l.get("area") not in areas or l.get("patrol") not in ["landing_post","north_post"]:return false
	if not l.get("woodland") is Dictionary or l.woodland.size()!=areas.size():return false
	for id in areas:
		if not r.whole(l.woodland.get(id),0,int(areas[id].capacity)):return false
	if not l.get("experience") is Dictionary or l.experience.size()!=r.content.households.size():return false
	for home in r.content.households:
		var e: Variant=l.experience.get(home.id)
		if not e is Dictionary or e.size()!=2:return false
		for key in ["woodland","shaping"]:
			if not r.whole(e.get(key),0,int(balance.experience_max)):return false
	if not l.get("inspected") is Array or not l.get("discoveries") is Dictionary:return false
	var seen: Array=[]
	for id in l.inspected:
		if id not in subjects or id in seen:return false
		seen.append(id)
	var ids: Array=[]
	for d in content.discoveries:ids.append(d.id)
	for id in l.discoveries:
		if id not in ids or not r.whole(l.discoveries[id],int(l.started),int(s.turn)):return false
	if l.cooperate and not l.discoveries.has("cooperation"):return false
	if l.prepare==2 and not r.has_project(s,"living_shared_room"):return false
	if l.kits>0 and not r.has_project(s,"living_watch_kits"):return false
	if not l.get("report") is Dictionary:return false
	if not l.report.is_empty():
		var keys: Array=["fuel","prepare_wood","support","repair_wood","prepared","repaired","training_workers","shared","workers","harvest","area","distance","yield","next_stock","fuel_need","equipped","wear","training","equipment_security","coverage","fuel_penalty","turn"]
		if l.report.size()!=keys.size():return false
		for key in keys:
			if not l.report.has(key):return false
			if key not in ["shared","area"] and not r.whole(l.report[key],-int(balance.fuel_penalty),100000):return false
		if not l.report.shared is bool or l.report.area not in areas or l.report.turn!=int(s.turn)-1:return false
	elif int(s.turn)>int(l.started):return false
	return true
