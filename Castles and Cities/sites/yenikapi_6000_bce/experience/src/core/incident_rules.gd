extends RefCounted
## Saved local incidents. Queries are pure; only commands and advance change state.
## Each authored incident occurs once, with one unresolved incident and a quiet interval.
var content: Dictionary
var balance: Dictionary
var specs: Dictionary={}
var project_specs: Dictionary={}
func _init(config: Dictionary,tuning: Dictionary) -> void:
	content=config;balance=tuning
	for item in content.get("incidents",[]):specs[item.id]=item
	for item in content.get("projects",[]):project_specs[item.id]=item
func active(s: Dictionary) -> bool:return s.get("incidents",{}) is Dictionary and not s.get("incidents",{}).is_empty()
func current(s: Dictionary) -> Dictionary:
	if not active(s) or s.incidents.records.is_empty():return {}
	var last: Dictionary=s.incidents.records[-1]
	return last if last.recovered<0 else {}
func record(id: String,start: int) -> Dictionary:
	return {"id":id,"started":start,"signs":start+int(balance.grace),"warning":start+int(balance.grace)+int(balance.public_delay),"due":start+int(balance.grace)+int(balance.public_delay)+int(balance.warning_seasons),"known":-1,"inspected":[],"restricted":false,"outcome":{},"recovered":-1}
func phase(s: Dictionary,e: Dictionary={}) -> String:
	if e.is_empty():e=current(s)
	if e.is_empty():return "quiet"
	if e.recovered>=0:return "recovered"
	if not e.outcome.is_empty():return "recovery"
	if int(s.turn)>=int(e.warning):return "warning"
	return "signs" if e.known>=0 else "exposure"
func command(s: Dictionary,a: Dictionary,r) -> Dictionary:
	var n: Dictionary=s.duplicate(true)
	if a.kind=="incident_begin":
		if s.role!="god":return {"error":"authority"}
		if active(s):return {"error":"incident_started"}
		if content.is_empty() or not r.living.active(s):return {"error":"incident_missing"}
		if r.assets.stage(s)!="settled":return {"error":"incident_lesson"}
		n.incidents={"version":1,"started":int(s.turn),"records":[record(content.incidents[0].id,int(s.turn))],"tutorial":0,"paused":false}
		return {"state":n}
	if not active(s):return {"error":"incident_missing"}
	var e: Dictionary=current(n)
	match a.kind:
		"incident_inspect":
			if e.is_empty() or a.get("id","") not in specs[e.id].subjects:return {"error":"incident_unknown"}
			if r.living.subjects.has(a.id):
				n=r.living.command(n,{"kind":"living_inspect","id":a.id},r).state;e=current(n)
			if int(s.turn)<int(e.signs):return {"state":n}
			if e.known<0:e.known=int(s.turn)
			if a.id not in e.inspected:e.inspected.append(a.id)
		"incident_restrict":
			if not r.permitted(s,"steward"):return {"error":"authority"}
			if e.is_empty() or e.known<0 or not e.outcome.is_empty() or not a.get("enabled") is bool:return {"error":"incident_phase"}
			e.restricted=a.enabled
			r.assets._record(n,"steward",a.kind,e.id,r,{"enabled":a.enabled})
		"incident_review":
			if not tutorial_ready(s,r):return {"error":"incident_review"}
			n.incidents.tutorial+=1
		_:return {"error":"incident_unknown"}
	return {"state":n}
func blocked(s: Dictionary,id: String,r) -> String:
	if not project_specs.has(id):return ""
	if not active(s):return "incident_missing"
	var e: Dictionary=current(s)
	if e.is_empty():return "incident_phase"
	var spec: Dictionary=specs[e.id]
	if id==spec.prepare:
		if e.known<0 or not e.outcome.is_empty():return "incident_phase"
	elif id==spec.repair:
		if e.outcome.is_empty():return "incident_phase"
	else:return "incident_phase"
	if s.living.blanks<project_specs[id].blanks:return "incident_materials"
	return ""
func commission(n: Dictionary,id: String) -> void:
	if project_specs.has(id):n.living.blanks-=int(project_specs[id].blanks)
func cancel(n: Dictionary,item: Dictionary,r) -> void:
	if project_specs.has(item.id):n.living.blanks=mini(int(r.living.balance.blank_capacity),int(n.living.blanks)+int(project_specs[item.id].blanks)*(int(r.projects[item.id].work)-int(item.progress))/int(r.projects[item.id].work))
func experience(s: Dictionary) -> int:
	var result: int=0
	for home in s.living.experience.values():result=maxi(result,int(home.woodland))
	return result
func covered(s: Dictionary,e: Dictionary,a: Dictionary,r) -> bool:
	var spec: Dictionary=specs[e.id]
	var workers: int=0
	for request in a.requests:
		if request.id=="watch":workers=int(request.filled)
	return s.living.patrol==spec.post and r.has_project(s,r.living.subjects[spec.post].project) and workers>=balance.coverage_workers and s.assets.conditions.watch>=r.assets.balance.condition_threshold
func will_complete(s: Dictionary,id: String,a: Dictionary,r) -> bool:
	if r.has_project(s,id):return true
	for item in s.queue:
		if item.id==id:return int(item.progress)+int(a.projects[id].work)>=int(r.projects[id].work)
	return false
func severity(s: Dictionary,e: Dictionary,a: Dictionary,r) -> Array:
	var spec: Dictionary=specs[e.id]
	var factors: Array=[{"id":"exposure","value":int(spec.strength)}]
	if spec.kind=="approach":
		factors.append({"id":"outer","value":int(balance.outer_exposure) if r.land.occupied_outer(s,r) else 0})
		factors.append({"id":"access","value":-int(balance.access_relief) if r.land.needs_access(s,r) and int(a.access_workers)>0 else 0})
		factors.append({"id":"experience","value":-int(balance.experience_relief) if experience(s)>=balance.experience_needed else 0})
	else:
		var local: bool=covered(s,e,a,r)
		factors.append({"id":"coverage","value":-int(balance.coverage_relief) if local else 0})
		factors.append({"id":"equipment","value":-mini(int(balance.equipment_relief),int(s.living.kits)) if local and s.living.readiness>=balance.training_needed else 0})
		factors.append({"id":"stores","value":-int(balance.store_relief) if s.households.orders.secure_stores and a.orders.get("secure_stores",0)>=r.households.balance.store_care_minimum else 0})
	factors.append({"id":"preparation","value":-int(balance.preparation_relief) if will_complete(s,spec.prepare,a,r) else 0})
	factors.append({"id":"restriction","value":-int(balance.restriction_relief) if e.restricted else 0})
	return factors
func damage(s: Dictionary,kind: String) -> int:
	var e: Dictionary=current(s)
	if e.is_empty() or specs[e.id].kind!=kind or e.outcome.is_empty():return 0
	return int(e.outcome.severity)
func restricted(s: Dictionary,kind: String) -> bool:
	var e: Dictionary=current(s)
	return not e.is_empty() and specs[e.id].kind==kind and e.restricted and e.outcome.is_empty()
func food_penalty(s: Dictionary) -> int:
	return damage(s,"stores")*int(balance.get("food_per_severity",0))+(int(balance.restriction_food) if restricted(s,"stores") else 0)
func timber_penalty(s: Dictionary) -> int:return damage(s,"approach")*int(balance.get("timber_per_severity",0))
func access_impaired(s: Dictionary) -> bool:return damage(s,"approach")>=int(balance.get("access_threshold",100))
func work_bonus(s: Dictionary,id: String,r) -> int:
	if not active(s) or not project_specs.has(id) or not id.ends_with("_repair"):return 0
	return int(balance.cooperation_work) if s.living.cooperate and s.living.practice>=r.living.balance.practice_needed and r.living.paired(s,r) else 0
func forecast(s: Dictionary,a: Dictionary,r) -> Dictionary:
	var e: Dictionary=current(s)
	if e.is_empty():return {}
	var spec: Dictionary=specs[e.id]
	var factors: Array=severity(s,e,a,r)
	var value: int=0
	for f in factors:value+=int(f.value)
	value=clampi(value,int(balance.minimum_severity),int(balance.maximum_severity))
	var loss: int=value*int(balance.loss_per_severity) if spec.kind=="stores" else 0
	if spec.kind=="stores" and will_complete(s,spec.prepare,a,r):loss=maxi(0,loss-int(balance.protected_food))
	return {"id":e.id,"resolves":e.outcome.is_empty() and int(s.turn)+1==int(e.due),"severity":value,"loss":loss,"factors":factors,"timber_penalty":value*int(balance.timber_per_severity) if spec.kind=="approach" else 0,"food_penalty":value*int(balance.food_per_severity) if spec.kind=="stores" else 0,"kit_loss":1 if spec.kind=="stores" and value>=balance.kit_loss_threshold and s.living.kits>0 else 0}
func advance(n: Dictionary,s: Dictionary,f: Dictionary,r) -> void:
	if not active(s):return
	var turn: int=int(s.turn)+1
	var e: Dictionary=current(n)
	if e.is_empty():
		var records: Array=n.incidents.records
		if records.size()<content.incidents.size() and turn>=int(records[-1].recovered)+int(balance.quiet_seasons):records.append(record(content.incidents[records.size()].id,turn))
		return
	var spec: Dictionary=specs[e.id]
	if e.known<0 and (turn>=int(e.warning) or (turn>=int(e.signs) and (covered(s,e,f.assets,r) or (spec.kind=="approach" and s.living.area=="north_wood" and f.plan.timber>0 and experience(s)>=balance.experience_needed)))):e.known=turn
	if f.incidents.resolves:
		var result: Dictionary=f.incidents.duplicate(true)
		result.erase("resolves");result.erase("id")
		result.turn=turn;result.lost=int(f.incident_lost)
		e.outcome=result
		n.living.kits=maxi(0,int(n.living.kits)-int(result.kit_loss))
	if not e.outcome.is_empty() and r.has_project(n,spec.repair):
		e.recovered=turn;e.restricted=false
func tutorial_ready(s: Dictionary,r) -> bool:
	if s.incidents.tutorial>=content.tutorial.size():return false
	var condition: String=content.tutorial[s.incidents.tutorial].condition
	for e in s.incidents.records:
		var spec: Dictionary=specs[e.id]
		match condition:
			"warning":if e.known>=0:return true
			"inspect":if not e.inspected.is_empty():return true
			"commit":if r.land.committed(s,spec.prepare,r):return true
			"resolved":if not e.outcome.is_empty():return true
			"recovery":if r.land.committed(s,spec.repair,r):return true
			"paused":if s.incidents.paused or e.recovered>=0:return true
			"restored":if e.recovered>=0:return true
	return false
func validate(s: Dictionary,r) -> bool:
	var v: Variant=s.get("incidents",{})
	if not v is Dictionary:return false
	if v.is_empty():
		for id in project_specs:
			if r.land.committed(s,id,r):return false
		return true
	if content.is_empty() or not r.living.active(s) or v.size()!=5:return false
	if not r.whole(v.get("version"),1,1) or not r.whole(v.get("started"),0,s.turn) or not r.whole(v.get("tutorial"),0,content.tutorial.size()) or not v.get("paused") is bool:return false
	if not v.get("records") is Array or v.records.is_empty() or v.records.size()>content.incidents.size():return false
	var previous: int=-1
	for i in range(v.records.size()):
		var e: Variant=v.records[i]
		if not e is Dictionary or e.size()!=10 or not e.get("id") is String:return false
		if e.id!=content.incidents[i].id:return false
		var spec: Dictionary=specs[e.id]
		if not r.whole(e.get("started"),int(v.started),int(s.turn)):return false
		if i==0 and e.started!=v.started:return false
		if i>0 and (previous<0 or e.started!=previous+int(balance.quiet_seasons)):return false
		for key in ["signs","warning","due"]:
			if not r.whole(e.get(key),0,1000000):return false
			if e[key]!=record(e.id,int(e.started))[key]:return false
		if not r.whole(e.get("known"),-1,s.turn) or (e.known>=0 and e.known<e.signs):return false
		if s.turn>=e.warning and e.known<0:return false
		if not e.get("restricted") is bool or not e.get("inspected") is Array:return false
		var seen: Array=[]
		for id in e.inspected:
			if id not in spec.subjects or id in seen or e.known<0:return false
			seen.append(id)
		if not r.whole(e.get("recovered"),-1,s.turn) or not e.get("outcome") is Dictionary:return false
		if e.outcome.is_empty():
			if s.turn>=e.due or e.recovered>=0 or r.land.committed(s,spec.repair,r):return false
		else:
			var o: Dictionary=e.outcome
			if o.size()!=8 or not r.whole(o.get("turn"),0,s.turn):return false
			if o.turn!=e.due or s.turn<e.due:return false
			for pair in [["severity",balance.minimum_severity,balance.maximum_severity],["loss",0,balance.maximum_severity*balance.loss_per_severity],["lost",0,o.get("loss",0)],["kit_loss",0,1],["timber_penalty",0,balance.maximum_severity],["food_penalty",0,balance.maximum_severity+balance.restriction_food]]:
				if not r.whole(o.get(pair[0]),int(pair[1]),int(pair[2])):return false
			if not o.get("factors") is Array:return false
			var expected: Array=["exposure","outer","access","experience","preparation","restriction"] if spec.kind=="approach" else ["exposure","coverage","equipment","stores","preparation","restriction"]
			if o.factors.size()!=expected.size():return false
			var total: int=0
			for j in range(expected.size()):
				var factor: Variant=o.factors[j]
				if not factor is Dictionary or factor.size()!=2 or factor.get("id")!=expected[j] or not r.whole(factor.get("value"),-balance.maximum_severity,balance.maximum_severity):return false
				total+=int(factor.value)
			if o.severity!=clampi(total,int(balance.minimum_severity),int(balance.maximum_severity)):return false
			if o.factors[0].value!=spec.strength:return false
			var domains: Dictionary={"outer":[0,int(balance.outer_exposure)],"access":[0,-int(balance.access_relief)],"experience":[0,-int(balance.experience_relief)],"preparation":[0,-int(balance.preparation_relief)],"restriction":[0,-int(balance.restriction_relief)],"coverage":[0,-int(balance.coverage_relief)],"equipment":[0,-1,-int(balance.equipment_relief)],"stores":[0,-int(balance.store_relief)]}
			for factor in o.factors:
				# JSON numbers load as floats; whole() above verifies integral values.
				if factor.id!="exposure" and int(factor.value) not in domains[factor.id]:return false
			var expected_loss: int=int(o.severity)*int(balance.loss_per_severity) if spec.kind=="stores" else 0
			if spec.kind=="stores" and o.factors[4].value<0:expected_loss=maxi(0,expected_loss-int(balance.protected_food))
			if o.loss!=expected_loss:return false
			if e.recovered>=0 and (e.recovered<e.due or not r.has_project(s,spec.repair)):return false
			if e.recovered<0 and r.has_project(s,spec.repair):return false
		previous=int(e.recovered)
	return true

func household_strain(s: Dictionary,f: Dictionary,home: String) -> int:
	var e: Dictionary=current(s)
	if e.is_empty() or home not in specs[e.id].households:return 0
	if f.get("incidents",{}).get("resolves",false):return int(f.incidents.severity)*int(balance.stress_per_severity)
	return int(balance.recovery_strain) if not e.outcome.is_empty() else 0

func restriction_timber(s: Dictionary) -> int:return int(balance.restriction_timber) if restricted(s,"approach") else 0
