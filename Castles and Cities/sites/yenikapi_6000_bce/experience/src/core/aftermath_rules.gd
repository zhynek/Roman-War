extends RefCounted
## Named, recoverable consequences. All changes occur at acceptance or a season.
## Group HP is allocated in stable member order; this is not individual medicine.
var tuning: Dictionary
func _init(balance: Dictionary) -> void:tuning=balance
func active(s: Dictionary) -> bool:
	return s.get("warfare",{}) is Dictionary and s.warfare.get("aftermath") is Dictionary
func initial(s: Dictionary,r) -> Dictionary:
	var result: Dictionary={"version":1,"people":{},"equipment_condition":int(tuning.equipment_initial_condition),"care":true}
	for id in s.get("defense",{}).get("recovery",{}):
		if r.person_by_id(s,str(id)).is_empty():continue
		result.people[id]={"battles":0,"experience":0,"last_turn":int(s.turn),"injury":"wounded"}
	return result
func decorate(b: Dictionary,base_report: Dictionary,r) -> Dictionary:
	var report: Dictionary=base_report.duplicate(true)
	var encounter: Dictionary=b.get("tactics",{}).get("encounter",{})
	var after: Dictionary={"version":1,"encounter":encounter.get("id","stores"),"serial":int(encounter.get("serial",0)),"turn":-1,"participants":[],"kit_wear":0,"condition_before":int(tuning.equipment_initial_condition),"condition_after":int(tuning.equipment_initial_condition)}
	var wounded: Array=[];var wear: int=0;var first: bool=true
	var hp: int=int(r.defense.tuning.hp_per_person)
	for group in b.groups:
		if group.side!="watch":continue
		if first:after.condition_before=int(group.tactical.condition);first=false
		var engaged: bool=int(group.attack_seq)>0 or int(group.hit_seq)>0
		for index in range(group.members.size()):
			var remaining: int=clampi(int(group.hp)-index*hp,0,hp)
			var injury: String="incapacitated" if remaining==0 else "wounded" if hp-remaining>=int(tuning.mild_injury_hp_loss) else "none"
			var recovery: int=int(tuning.incapacitated_recovery_seasons) if injury=="incapacitated" else int(tuning.mild_recovery_seasons) if injury=="wounded" else 0
			var equipped: bool=index<int(group.kits)
			var id: String=group.members[index]
			after.participants.append({"id":id,"name":"","household":"","group":group.id,"injury":injury,"recovery":recovery,"experience":int(tuning.experience_per_engagement) if engaged else 0,"engaged":engaged,"equipped":equipped,"stress":0})
			if recovery>0:wounded.append(id)
			if equipped and engaged:wear+=int(tuning.equipment_wear_engaged)
			if equipped and injury=="incapacitated":wear+=int(tuning.equipment_wear_incapacitated)
	after.kit_wear=mini(int(after.condition_before),wear)
	after.condition_after=int(after.condition_before)-int(after.kit_wear)
	report.wounded=wounded;report.aftermath=after
	return report
func accept(n: Dictionary,before: Dictionary,report: Dictionary,r) -> void:
	if not active(before) or not report.get("aftermath") is Dictionary:return
	var source: Dictionary=before.warfare.aftermath
	var after: Dictionary=report.aftermath
	after.turn=int(before.turn)
	var homes: Dictionary={}
	for row in after.participants:
		var person: Dictionary=r.person_by_id(before,row.id)
		row.name=person.name;row.household=person.household;row.stress=0
		var record: Dictionary=source.people.get(row.id,{"battles":0,"experience":0,"last_turn":int(before.turn),"injury":"none"}).duplicate(true)
		record.battles=int(record.battles)+1
		record.experience=mini(int(tuning.maximum_experience),int(record.experience)+int(row.experience))
		record.last_turn=int(before.turn);record.injury=row.injury
		n.warfare.aftermath.people[row.id]=record
		if int(row.recovery)>0:
			n.defense.recovery[row.id]=maxi(int(before.defense.get("recovery",{}).get(row.id,0)),int(row.recovery))
		else:n.defense.recovery.erase(row.id)
		if row.injury!="none" and before.get("households",{}).get("homes",{}).has(row.household):
			if not homes.has(row.household):homes[row.household]=int(before.households.homes[row.household].stress)
			var strain: int=int(tuning.household_stress_incapacitated) if row.injury=="incapacitated" else int(tuning.household_stress_injury)
			row.stress=mini(strain,int(r.households.balance.max_stock)-int(homes[row.household]))
			homes[row.household]=int(homes[row.household])+int(row.stress)
	for home in homes:n.households.homes[home].stress=int(homes[home])
	# The parent commits the lost kit count once. This changes only the
	# condition of the surviving pooled equipment, never grants replacements.
	n.warfare.aftermath.equipment_condition=int(after.condition_after)
func requests(s: Dictionary,list: Array,r) -> void:
	if not active(s) or not s.warfare.aftermath.care:return
	var patients: int=0
	for id in s.get("defense",{}).get("recovery",{}):
		var person: Dictionary=r.person_by_id(s,str(id))
		if not person.is_empty() and person.active:patients+=1
	var wanted: int=ceili(float(patients)/int(tuning.patients_per_worker))
	r.assets._request(list,"warfare_care","care",wanted,int(tuning.care_priority),"homes")
func recover(n: Dictionary,before: Dictionary,forecast: Dictionary,r) -> void:
	if not active(before) or not before.get("defense",{}).get("recovery",{}) is Dictionary:return
	var capacity: int=0
	if before.warfare.aftermath.care and forecast.get("covered",false):
		for request in forecast.get("assets",{}).get("requests",[]):
			if request.id=="warfare_care":capacity=int(request.filled)*int(tuning.patients_per_worker)
	var patients: Array=[]
	for id in before.get("defense",{}).get("recovery",{}):
		var person: Dictionary=r.person_by_id(n,str(id))
		if person.is_empty() or not person.active:
			n.defense.recovery.erase(id)
			if n.warfare.aftermath.people.has(id):n.warfare.aftermath.people[id].injury="none"
		else:patients.append(id)
	patients.sort_custom(func(a,b):
		var left: int=int(before.defense.recovery[a]);var right: int=int(before.defense.recovery[b])
		if left!=right:return left>right
		var age_a: int=int(before.warfare.aftermath.people[a].last_turn);var age_b: int=int(before.warfare.aftermath.people[b].last_turn)
		return age_a<age_b if age_a!=age_b else str(a)<str(b))
	for id in patients.slice(0,capacity):
		var remaining: int=int(before.defense.recovery[id])-1
		if remaining<=0:n.defense.recovery.erase(id);n.warfare.aftermath.people[id].injury="none"
		else:n.defense.recovery[id]=remaining
func needs_repair(s: Dictionary) -> bool:
	return active(s) and int(s.warfare.aftermath.equipment_condition)<int(tuning.equipment_initial_condition)
func repair(n: Dictionary,before: Dictionary,forecast: Dictionary,r) -> void:
	if not active(before):return
	var repaired: int=int(forecast.get("living",{}).get("repaired",0))
	if repaired>0:n.warfare.aftermath.equipment_condition=mini(int(tuning.equipment_initial_condition),int(before.warfare.aftermath.equipment_condition)+repaired*int(tuning.equipment_repair_gain))
func skill(s: Dictionary,id: String,r) -> int:
	var person: Dictionary=r.person_by_id(s,id)
	if person.is_empty():return 0
	var experience: int=int(s.get("warfare",{}).get("aftermath",{}).get("people",{}).get(id,{}).get("experience",0))
	return mini(int(r.defense.tactical_tuning.max_skill),int(person.watch)+experience/int(tuning.experience_per_skill))
func validate_report(report: Variant,s: Dictionary,r) -> bool:
	if not report is Dictionary or report.size()!=9 or not report.get("aftermath") is Dictionary or not report.get("wounded") is Array:return false
	var after: Dictionary=report.aftermath
	if after.size()!=8 or after.get("version")!=1 or not after.get("encounter") is String or not r.warfare.threats.encounters.has(after.encounter):return false
	if not r.whole(after.get("serial"),0,int(r.balance.max_turns)+1) or not r.whole(after.get("turn"),int(s.warfare.started),int(s.turn)):return false
	for key in ["kit_wear","condition_before","condition_after"]:
		if not r.whole(after.get(key),0,int(tuning.equipment_initial_condition)):return false
	if not after.get("participants") is Array or after.participants.is_empty() or after.participants.size()>int(r.defense.tuning.maximum_defenders):return false
	var ids: Array=[];var wounded: Array=[];var lost: int=0;var wear: int=0
	for row in after.participants:
		if not row is Dictionary or row.size()!=10 or not row.get("id") is String or row.id in ids:return false
		var person: Dictionary=r.person_by_id(s,row.id)
		if person.is_empty():return false
		ids.append(row.id)
		if not row.get("name") is String or row.name.is_empty() or row.name.length()>100 or not row.get("household") is String:return false
		var household: bool=false
		for home in r.content.households:
			if home.id==row.household:household=true;break
		if not household or not row.get("group") is String or not row.group.begins_with("watch_") or row.group.length()>32:return false
		if row.get("injury") not in ["none","wounded","incapacitated"] or not row.get("engaged") is bool or not row.get("equipped") is bool:return false
		var recovery: int=int(tuning.incapacitated_recovery_seasons) if row.injury=="incapacitated" else int(tuning.mild_recovery_seasons) if row.injury=="wounded" else 0
		if not r.whole(row.get("recovery"),recovery,recovery):return false
		var experience: int=int(tuning.experience_per_engagement) if row.engaged else 0
		if not r.whole(row.get("experience"),experience,experience):return false
		var stress: int=int(tuning.household_stress_incapacitated) if row.injury=="incapacitated" else int(tuning.household_stress_injury) if row.injury=="wounded" else 0
		if not r.whole(row.get("stress"),0,stress):return false
		if recovery>0:wounded.append(row.id)
		if row.equipped and row.injury=="incapacitated":lost+=1;wear+=int(tuning.equipment_wear_incapacitated)
		if row.equipped and row.engaged:wear+=int(tuning.equipment_wear_engaged)
	if r.canonical(report.wounded)!=wounded or not r.whole(report.get("kits"),lost,lost):return false
	return int(after.kit_wear)==mini(int(after.condition_before),wear) and int(after.condition_after)==int(after.condition_before)-int(after.kit_wear)
func validate(s: Dictionary,r) -> bool:
	if not active(s):return false
	var defense: Variant=s.get("defense",{})
	if not defense is Dictionary or not defense.get("reports",[]) is Array or not defense.get("recovery",{}) is Dictionary:return false
	var after: Dictionary=s.warfare.aftermath
	if after.size()!=4 or after.get("version")!=1 or not after.get("people") is Dictionary or not after.get("care") is bool:return false
	if not r.whole(after.get("equipment_condition"),0,int(tuning.equipment_initial_condition)):return false
	var totals: Dictionary={}
	var serials: Array=[];var cycle: int=0;var last_turn: int=int(s.warfare.started)
	for report in s.get("defense",{}).get("reports",[]):
		if not report is Dictionary:return false
		if not report.has("aftermath"):continue
		if not validate_report(report,s,r):return false
		var serial: int=int(report.aftermath.serial)
		if serial in serials or int(report.aftermath.turn)<last_turn:return false
		serials.append(serial);last_turn=int(report.aftermath.turn)
		if serial>0:
			if serial!=cycle+1 or report.aftermath.encounter!=r.warfare.threats.sequence[cycle%r.warfare.threats.sequence.size()]:return false
			cycle=serial
		elif serials.size()!=1 or report.aftermath.encounter!=r.warfare.threats.sequence[0]:return false
		for row in report.aftermath.participants:
			if not totals.has(row.id):totals[row.id]={"battles":0,"experience":0,"last_turn":0}
			totals[row.id].battles+=1
			totals[row.id].experience=mini(int(tuning.maximum_experience),int(totals[row.id].experience)+int(row.experience))
			totals[row.id].last_turn=maxi(int(totals[row.id].last_turn),int(report.aftermath.turn))
	if cycle!=int(s.warfare.get("threats",{}).get("cycle",0)):return false
	for id in totals:
		if not after.people.has(id):return false
	for id in after.people:
		if not id is String or r.person_by_id(s,id).is_empty():return false
		var row: Variant=after.people[id]
		if not row is Dictionary or row.size()!=4 or row.get("injury") not in ["none","wounded","incapacitated"]:return false
		if not r.whole(row.get("battles"),0,int(r.balance.max_turns)+1) or not r.whole(row.get("experience"),0,int(tuning.maximum_experience)) or not r.whole(row.get("last_turn"),int(s.warfare.started),int(s.turn)):return false
		var expected: Dictionary=totals.get(id,{"battles":0,"experience":0,"last_turn":int(s.warfare.started)})
		if int(row.battles)!=int(expected.battles) or int(row.experience)!=int(expected.experience) or int(row.last_turn)!=int(expected.last_turn):return false
		var recovering: bool=s.get("defense",{}).get("recovery",{}).has(id)
		if recovering!=(row.injury!="none"):return false
		# A legacy unavailable record may predate adoption and an ordinary
		# natural death. The next recovery pass clears only its work exclusion.
		if recovering and int(row.battles)>0 and not r.person_by_id(s,id).active:return false
	for id in s.get("defense",{}).get("recovery",{}):
		if not after.people.has(id):return false
	return true
