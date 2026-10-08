extends RefCounted
## Explicit additive village warfare profile. No scene, wall clock, or RNG.
const Forts=preload("res://src/core/fortification_rules.gd")
var forts
const Threats=preload("res://src/core/threat_rules.gd")
const Director=preload("res://src/core/battle_director.gd")
var threats
const Aftermath=preload("res://src/core/aftermath_rules.gd")
var aftermath
const Tactical=preload("res://src/core/tactical_sim.gd")
const Nav=preload("res://src/core/defense_navigation.gd")
var content: Dictionary
var tuning: Dictionary
var definition_hash: String
func _init(config: Dictionary,balance: Dictionary) -> void:
	content=config;tuning=balance
	forts=Forts.new(content.get("fortifications",{}),tuning.get("fortifications",{}))
	threats=Threats.new(content.get("threats",{}),tuning.get("threats",{}))
	aftermath=Aftermath.new(tuning.get("aftermath",{}))
	var semantic: Dictionary=content.duplicate(true);semantic.erase("ui")
	definition_hash=JSON.stringify([semantic,tuning]).sha256_text()
func active(s: Dictionary) -> bool:
	return s.get("warfare",{}) is Dictionary and not s.get("warfare",{}).is_empty()
func command(s: Dictionary,a: Dictionary,r) -> Dictionary:
	if r.defense.locked(s):return {"error":"blocked"}
	if a.get("kind")=="warfare_care" and active(s):
		if not r.permitted(s,"steward"):return {"error":"authority"}
		if not a.get("enabled") is bool:return {"error":"bad_order"}
		var n: Dictionary=s.duplicate(true);n.warfare.aftermath.care=a.enabled
		r.assets._record(n,"steward","warfare_care","homes",r,{"enabled":a.enabled})
		n.assignments=[];n.plan=r.effective_plan(n)
		return {"state":n}
	if not r.permitted(s,"watch"):return {"error":"authority"}
	if a.get("kind")=="warfare_begin":
		if active(s):return {"error":"bad_order"}
		if not r.living.active(s):return {"error":"living_missing"}
		var n: Dictionary=s.duplicate(true)
		n.warfare={"version":1,"profile":definition_hash,"started":int(s.turn),"plans":forts.content.get("slots",{}).duplicate(true),"threats":{},"muster":0,"aftermath":aftermath.initial(s,r)}
		r._event(n,"warfare_adopted",{})
		return {"state":n}
	if a.get("kind")=="warfare_muster" and active(s):
		if not r.whole(a.get("value"),0,int(tuning.muster.maximum)):return {"error":"bad_order"}
		var n: Dictionary=s.duplicate(true);n.warfare.muster=int(a.value)
		r.assets._record(n,"watch","warfare_muster","watch",r,{"value":int(a.value)})
		n.assignments=[];n.plan=r.effective_plan(n)
		return {"state":n}
	if a.get("kind")=="warfare_threats" and active(s):return threats.begin(s,r)
	if a.get("kind")=="warfare_plan" and active(s):
		if not a.get("slot") is String or not a.get("place") is String or not forts.content.slots.has(a.slot):return {"error":"bad_order"}
		var found: bool=false
		for place in forts.content.positions:
			if place.id==a.place:
				if a.slot=="assembly" and float(place.at[1])*100<int(r.defense.content.deployment[1])*100-int(r.defense.tuning.deployment_depth_cm):return {"error":"plan_invalid"}
				found=true
		if not found:return {"error":"bad_order"}
		var n: Dictionary=s.duplicate(true);n.warfare.plans[a.slot]=a.place
		return {"state":n}
	return {"error":"bad_order"}
func requests(s: Dictionary,list: Array,r) -> void:
	if active(s):
		r.assets._request(list,"warfare_muster","watch",int(s.warfare.muster),int(tuning.muster.priority),"watch")
		aftermath.requests(s,list,r)
func enhance(b: Dictionary,s: Dictionary,r) -> String:
	if not places_valid(b.nav,r):return "bad_order"
	Tactical.enhance(b,r.defense.battle_tuning({"tactics":{}}))
	var spec: Dictionary=threats.spec(s)
	var serial: int=int(s.warfare.get("threats",{}).get("pending",{}).get("serial",0))
	var encounter_error: String=Director.configure(b,spec,serial,r.defense.battle_tuning(b))
	if not encounter_error.is_empty():return encounter_error
	forts.enhance(b,s,r)
	var locations: Dictionary=forts.plan_locations(b.nav)
	b.tactics.plan={}
	for slot in s.warfare.plans:b.tactics.plan[slot]=locations[s.warfare.plans[slot]].duplicate()
	b.exits.watch=b.tactics.plan.fallback.duplicate()
	var ids: Array=[]
	for group in b.groups:
		if group.side=="watch":ids.append(group.id)
	# Apply the saved assembly as an ordinary serialized deployment command.
	var assembly_error: String=r.defense.control(b,{"kind":"defense_order","order":"move","ids":ids,"at":b.tactics.plan.assembly},r)
	if not assembly_error.is_empty():return assembly_error
	for f in b.groups:
		if f.side!="watch":continue
		var skill: int=0
		for id in f.members:
			var person: Dictionary=r.person_by_id(s,id)
			skill+=aftermath.skill(s,id,r)
			if id==s.leaders.watch.id:f.tactical.leadership=mini(4,int(person.watch))
		f.tactical.skill=skill/f.members.size()
		f.tactical.condition=int(s.warfare.aftermath.equipment_condition)
	return ""
func places_valid(nav: Dictionary,r) -> bool:
	# Terrain cells are the captured authoritative snapshot. Place identities
	# still come from authored data, resolved against that same saved snapshot.
	for place in r.defense.content.places:
		var expected: Array=Nav.nearest(nav,[roundi(float(place.at[0])*100),roundi(float(place.at[1])*100)])
		if r.canonical(nav.places[place.id])!=expected:return false
	return true
func mobilization_valid(s: Dictionary,r) -> bool:
	# Spending and the seasonal workforce are locked while this battle exists.
	# Restore only its paid rations in a detached quote to recover the exact
	# original allocation; current food already includes mobilization spending.
	var battle: Dictionary=s.defense.battle
	if not places_valid(battle.nav,r):return false
	var start: Array=Nav.nearest(battle.nav,[int(r.defense.content.deployment[0])*100,int(r.defense.content.deployment[1])*100])
	if int(battle.deploy_limit)!=int(start[1])-int(r.defense.tuning.deployment_depth_cm):return false
	var defenders: int=0
	for group in battle.groups:
		if group.side=="watch":defenders+=int(group.initial)
	if defenders<1 or defenders>int(r.defense.tuning.maximum_defenders):return false
	var cost: int=defenders*int(r.defense.tuning.rations_per_person)
	if int(battle.cost)!=cost:return false
	var before: Dictionary=s.duplicate(true);before.food=int(s.food)+cost
	var quote: Dictionary=r.defense.quote(before,r)
	if int(quote.count)!=defenders or int(quote.food)!=cost:return false
	var size: int=1 if defenders<=int(r.defense.tuning.group_size) else int(r.defense.tuning.group_size)
	var watch_groups: int=ceili(float(defenders)/size)
	var raider_groups: int=r.defense.content.enemy_origins.size()
	if battle.groups.size()!=watch_groups+raider_groups:return false
	var kits_left: int=int(quote.kits)
	var watch_morale: int=maxi(0,int(tuning.tactics.maximum_stat)-(r.living.content.posts.size()-int(quote.posts))*int(r.defense.tuning.post_morale))
	for index in range(watch_groups):
		var group: Dictionary=battle.groups[index]
		var members: Array=quote.ids.slice(index*size,(index+1)*size)
		var kits: int=mini(kits_left,members.size());kits_left-=kits
		if group.side!="watch" or group.id!="watch_"+str(index+1) or group.members!=members or int(group.initial)!=members.size():return false
		if int(group.kits)!=kits or int(group.readiness)!=int(quote.readiness) or int(group.tactical.initial_morale)!=watch_morale:return false
	var enemy_hp: int=0
	for index in range(raider_groups):
		var group: Dictionary=battle.groups[watch_groups+index]
		var members: Array=[]
		for person in range(int(r.defense.tuning.enemy_people)):members.append("raider_%d_%d"%[index,person])
		if group.side!="raider" or group.id!="raider_"+str(index+1) or group.members!=members or int(group.initial)!=members.size():return false
		if int(group.kits)!=0 or int(group.readiness)!=0 or int(group.tactical.skill)!=0 or int(group.tactical.leadership)!=0:return false
		if int(group.tactical.condition)!=int(tuning.tactics.maximum_stat) or int(group.tactical.initial_morale)!=int(r.defense.tuning.enemy_morale):return false
		enemy_hp+=members.size()*int(r.defense.tuning.hp_per_person)
	return int(battle.tactics.enemy_initial_hp)==enemy_hp
func validate(s: Dictionary,r) -> bool:
	var w: Variant=s.get("warfare",{})
	if not w is Dictionary:return false
	if w.is_empty():
		return not (s.get("defense",{}) is Dictionary and s.defense.get("battle",{}) is Dictionary and s.defense.get("battle",{}).has("tactics"))
	if w.size()!=7 or w.get("version")!=1 or w.get("profile")!=definition_hash or not r.whole(w.get("started"),0,int(s.turn)):return false
	if not r.living.active(s):return false
	if not threats.validate(s,r) or not aftermath.validate(s,r):return false
	if not r.whole(w.get("muster"),0,int(tuning.muster.maximum)):return false
	if not w.get("plans") is Dictionary or w.plans.size()!=forts.content.slots.size():return false
	var valid_places: Array=[]
	for place in forts.content.positions:valid_places.append(place.id)
	for slot in forts.content.slots:
		if not w.plans.get(slot) is String or w.plans[slot] not in valid_places:return false
	for place in forts.content.positions:
		if place.id==w.plans.assembly and float(place.at[1])*100<int(r.defense.content.deployment[1])*100-int(r.defense.tuning.deployment_depth_cm):return false
	if r.defense.locked(s):
		if not s.defense.battle.get("tactics") is Dictionary or not s.defense.battle.tactics.has("plan"):return false
	if r.defense.locked(s):
		if not r.defense.valid_battle(s.defense.battle,s,r) or not Tactical.validate(s.defense.battle,r):return false
		if not mobilization_valid(s,r):return false
		for group in s.defense.battle.groups:
			if group.side!="watch":continue
			var skill: int=0;var leadership: int=0
			for id in group.members:
				skill+=aftermath.skill(s,id,r)
				if id==s.leaders.watch.id:leadership=mini(4,int(r.person_by_id(s,id).watch))
			if int(group.tactical.skill)!=skill/group.members.size() or int(group.tactical.leadership)!=leadership or int(group.tactical.condition)!=int(w.aftermath.equipment_condition):return false
		var spec: Dictionary=threats.spec(s)
		var encounter: Dictionary=s.defense.battle.tactics.get("encounter",{})
		if encounter.get("id")!=spec.id or encounter.get("kind")!=spec.kind:return false
		if encounter.get("serial")!=int(w.threats.get("pending",{}).get("serial",0)):return false
		if r.canonical(s.defense.battle.tactics.objective)!=r.canonical(s.defense.battle.nav.places[spec.place]):return false
		var locations: Dictionary=forts.plan_locations(s.defense.battle.nav)
		var expected: Dictionary={}
		for slot in w.plans:expected[slot]=locations[w.plans[slot]]
		if r.canonical(s.defense.battle.tactics.plan)!=expected:return false
		if r.canonical(s.defense.battle.exits.watch)!=expected.fallback:return false
		var prepared: Dictionary={"nav":s.defense.battle.nav,"tactics":{"defenses":[]}}
		forts.enhance(prepared,s,r)
		if r.canonical(s.defense.battle.tactics.defenses)!=prepared.tactics.defenses:return false
		if not s.defense.battle.tactics.ground.is_empty():return false
	return true
