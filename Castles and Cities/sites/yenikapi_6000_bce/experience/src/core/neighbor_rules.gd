extends RefCounted
## Optional, deterministic aggregate communities. No scenes, clocks or randomness.
var content: Dictionary
var balance: Dictionary
var communities: Dictionary = {}

func _init(config: Dictionary, tuning: Dictionary) -> void:
	content = config
	balance = tuning
	for community in config.get("neighbors", []): communities[community.id] = community

func active(state: Dictionary) -> bool:
	return not state.get("contacts", {}).is_empty()

func leader(state: Dictionary, id: String) -> Dictionary:
	return communities[id].leaders[int(state.contacts.neighbors[id].leader_index)]

func crew(state: Dictionary, plan: Dictionary) -> Dictionary:
	var result := {"carriers":0,"escorts":0,"ready":false}
	if not active(state) or state.contacts.mission.is_empty(): return result
	var mission: Dictionary = state.contacts.mission
	result.ready = plan.food >= balance.carriers and plan.watch >= mission.escorts
	if result.ready:
		result.carriers = int(balance.carriers)
		result.escorts = int(mission.escorts)
	return result

func arrivals(state: Dictionary, plan: Dictionary) -> Dictionary:
	var result := {"food":0,"wood":0}
	if not crew(state, plan).ready: return result
	var mission: Dictionary = state.contacts.mission
	if mission.remaining == 1 and mission.kind == "trade":
		result[mission.receive] = delivered(int(mission.receive_amount), int(mission.loss))
	return result

func delivered(amount: int, loss: int) -> int:
	return amount - amount * loss / 100

func quote(state: Dictionary, id: String, kind: String, rules) -> Dictionary:
	if not active(state): return {"error":"contact_missing"}
	if not communities.has(id) or kind not in ["trade","aid"]: return {"error":"contact_unknown"}
	var spec: Dictionary = communities[id]
	var local: Dictionary = state.contacts.neighbors[id]
	var escorts: int = int(state.contacts.escort_policy)
	var pressure: int = int(spec.pressure[int(state.turn)%4])
	var escort_power: int = escorts * int(balance.escort_power)
	var leader_power: int = rules.leader_skill(state,"watch") * int(balance.leader_protection)
	var loss: int = clampi(pressure-escort_power-leader_power,0,int(balance.max_loss_percent))
	var offer: Dictionary = spec.offer
	var result := {"neighbor":id,"kind":kind,"give":offer.give if kind=="trade" else spec.aid.resource,
		"give_amount":int(offer.give_amount if kind=="trade" else spec.aid.amount),
		"receive":offer.receive,"receive_amount":int(offer.receive_amount) if kind=="trade" else 0,
		"duration":int(spec.duration),"escorts":escorts,"loss":loss,
		"pressure":pressure,"escort_power":escort_power,"leader_power":leader_power}
	result.delivered = delivered(result.receive_amount,loss)
	var reason: String = ""
	if not state.contacts.mission.is_empty(): reason="contact_busy"
	elif state.plan.food < balance.carriers or state.plan.watch < escorts: reason="contact_crew"
	elif state[result.give] < result.give_amount or (result.give=="food" and int(state.food)-int(result.give_amount)<rules.people(state).size()*int(balance.min_home_reserve)): reason="contact_stock"
	elif kind=="trade" and local.trust<balance.trust_trade_min: reason="contact_trust"
	elif kind=="trade" and int(local[result.receive])-int(result.receive_amount)<int(spec[result.receive+"_reserve"])+int(leader(state,id).reserve_margin): reason="contact_reserve"
	elif kind=="aid" and local[spec.aid.resource]>=spec.aid.below: reason="contact_aid"
	if not reason.is_empty(): result.error=reason
	return result

func command(state: Dictionary, action: Dictionary, rules) -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	var kind: String = action.get("kind","")
	if kind=="neighbor_begin":
		if not rules.permitted(state,"steward"): return {"error":"authority"}
		if active(state): return {"error":"contact_started"}
		if communities.is_empty() or not state.town_achieved or not rules.has_project(state,content.project_id): return {"error":"contact_locked"}
		next.contacts={"version":1,"started":int(state.turn),"elapsed":0,"escort_policy":int(balance.initial_escorts),"next_mission":1,"mission":{},"neighbors":{},"chapter_complete":false}
		for id in communities:
			var spec: Dictionary=communities[id]
			next.contacts.neighbors[id]={"food":int(spec.food),"wood":int(spec.wood),"trust":int(balance.initial_trust),"leader_index":0,"leader_serial":1,"leader_since":int(state.turn)-int(spec.term_offset),"trades":0,"aid":0,"report":{}}
		rules._event(next,"contact_started",{})
		return {"state":next}
	if not active(state): return {"error":"contact_missing"}
	if kind=="neighbor_escort":
		if not rules.permitted(state,"watch"): return {"error":"authority"}
		if not rules.whole(action.get("escorts"),0,int(balance.max_escorts)): return {"error":"contact_unknown"}
		next.contacts.escort_policy=int(action.escorts)
	elif kind=="neighbor_send":
		if not rules.permitted(state,"steward"): return {"error":"authority"}
		var q: Dictionary=quote(state,action.get("neighbor",""),action.get("mission",""),rules)
		if q.has("error"): return {"error":q.error}
		var mission: Dictionary={}
		for key in ["neighbor","kind","give","give_amount","receive","receive_amount","duration","escorts","loss"]:mission[key]=q[key]
		mission.id="mission_%04d"%int(state.contacts.next_mission)
		mission.remaining=mission.duration
		mission.started=false
		next.contacts.next_mission+=1
		next.contacts.mission=mission
		next[mission.give]-=int(mission.give_amount)
		if mission.kind=="trade": next.contacts.neighbors[mission.neighbor][mission.receive]-=int(mission.receive_amount)
		rules._event(next,"contact_sent",{"mission":mission.id,"neighbor":mission.neighbor,"give":mission.give,"give_amount":mission.give_amount,"escorts":mission.escorts,"duration":mission.duration})
	elif kind=="neighbor_cancel":
		if not rules.permitted(state,"steward"): return {"error":"authority"}
		var mission: Dictionary=state.contacts.mission
		if mission.is_empty(): return {"error":"contact_none"}
		if mission.started: return {"error":"contact_transit"}
		next[mission.give]+=int(mission.give_amount)
		var overflow:int=maxi(0,int(next.food)-rules.storage(next));next.food=mini(next.food,rules.storage(next))
		if mission.kind=="trade":
			var spec:Dictionary=communities[mission.neighbor]
			var local:Dictionary=next.contacts.neighbors[mission.neighbor]
			local[mission.receive]=mini(int(spec[mission.receive+"_capacity"]),int(local[mission.receive])+int(mission.receive_amount))
		next.contacts.mission={}
		rules._event(next,"contact_cancelled",{"mission":mission.id,"food":overflow,"wood":0})
	else: return {"error":"contact_unknown"}
	return {"state":next}

func advance(next: Dictionary, before: Dictionary, rules) -> void:
	if not active(before): return
	var contact: Dictionary=next.contacts
	var returning: String=""
	var mission: Dictionary=contact.mission
	if not mission.is_empty() and crew(before,rules.normalize_plan(before,before.plan)).ready:
		mission.started=true
		mission.remaining-=1
		if mission.remaining==0: returning=mission.neighbor
	for id in communities:
		var spec:Dictionary=communities[id]
		var local:Dictionary=contact.neighbors[id]
		var gathered:int=int(spec.food_yields[int(before.turn)%4])
		var spoil:int=int(local.food)*int(balance.neighbor_spoil_percent)/100
		var available:int=int(local.food)+gathered-spoil
		var eaten:int=mini(int(spec.population),available)
		var overflow:int=maxi(0,available-eaten-int(spec.food_capacity))
		local.food=mini(int(spec.food_capacity),available-eaten)
		var wood_gain:int=mini(int(spec.wood_yield),int(spec.wood_capacity)-int(local.wood))
		local.wood+=wood_gain
		var drift:int=-mini(int(balance.trust_decay),maxi(0,int(local.trust)-int(balance.trust_floor))) if returning!=id else 0
		var trade:int=int(balance.trade_trust) if returning==id and mission.kind=="trade" else 0
		var aid:int=int(balance.aid_trust) if returning==id and mission.kind=="aid" else 0
		var old_trust:int=int(local.trust)
		local.trust=clampi(old_trust+drift+trade+aid,0,100)
		local.report={"gathered":gathered,"eaten":eaten,"unfed":int(spec.population)-eaten,"spoil":spoil,"overflow":overflow,"wood_gain":wood_gain,"drift":drift,"trade":trade,"aid":aid,"total":int(local.trust)-old_trust,"delivered":0,"cargo_overflow":0}
		if returning==id:
			var amount:int=delivered(int(mission.give_amount),int(mission.loss))
			local.report.delivered=amount
			local.report.cargo_overflow=maxi(0,int(local[mission.give])+amount-int(spec[mission.give+"_capacity"]))
			local[mission.give]=mini(int(spec[mission.give+"_capacity"]),int(local[mission.give])+amount)
			if mission.kind=="trade":local.trades+=1
			else:
				local.aid+=1
				rules._event(next,"contact_aid",{"neighbor":id,"amount":amount,"resource":mission.give})
		if int(before.turn)+1-int(local.leader_since)>=int(balance.leader_term):
			local.leader_index=(int(local.leader_index)+1)%spec.leaders.size()
			local.leader_serial+=1;local.leader_since=int(before.turn)+1
			rules._event(next,"contact_succession",{"neighbor":id,"name":leader(next,id).name})
	if not returning.is_empty():
		var cargo:Dictionary=arrivals(before,before.plan)
		rules._event(next,"contact_return",{"mission":mission.id,"neighbor":returning,"food":cargo.food,"wood":cargo.wood,"loss":mission.loss})
		contact.mission={}
	contact.elapsed+=1
	if not contact.chapter_complete and chapter_ready(next,rules):
		contact.chapter_complete=true
		rules._event(next,"contact_complete",{})

func chapter_ready(state: Dictionary,rules) -> bool:
	if not active(state) or state.food<rules.people(state).size()*int(balance.chapter_home_reserve): return false
	var aided:bool=false
	for local in state.contacts.neighbors.values():
		if local.trades<1 or local.trust<balance.chapter_trust:return false
		if local.aid>0:aided=true
	return aided

func validate(state: Dictionary,rules) -> bool:
	var c:Variant=state.get("contacts")
	if not c is Dictionary:return false
	if c.is_empty():return true
	if communities.is_empty() or c.size()!=8:return false
	for key in ["version","started","elapsed","escort_policy","next_mission"]:
		if not rules.whole(c.get(key),0,int(balance.max_stock)):return false
	if c.version!=1 or c.started>state.turn or c.elapsed!=int(state.turn)-int(c.started) or c.escort_policy>balance.max_escorts or c.next_mission<1:return false
	if not c.get("chapter_complete") is bool or not c.get("mission") is Dictionary or not c.get("neighbors") is Dictionary or c.neighbors.size()!=communities.size():return false
	if not state.town_achieved or not rules.has_project(state,content.project_id):return false
	for id in communities:
		var spec:Dictionary=communities[id]
		var local:Variant=c.neighbors.get(id)
		if not local is Dictionary or local.size()!=9:return false
		for key in ["food","wood","trust","leader_index","leader_serial","trades","aid"]:
			if not rules.whole(local.get(key),0,int(balance.max_stock)):return false
		if local.food>spec.food_capacity or local.wood>spec.wood_capacity or local.trust>100 or local.leader_index>=spec.leaders.size() or local.leader_serial<1:return false
		if not rules.whole(local.get("leader_since"),-int(balance.leader_term),int(state.turn)) or not local.get("report") is Dictionary:return false
		if not local.report.is_empty():
			if local.report.size()!=12:return false
			for key in ["gathered","eaten","unfed","spoil","overflow","wood_gain","drift","trade","aid","total","delivered","cargo_overflow"]:
				if not rules.whole(local.report.get(key),-int(balance.max_stock),int(balance.max_stock)):return false
	var m:Dictionary=c.mission
	if m.is_empty():return true
	if m.size()!=12 or not m.get("id") is String or not m.id.begins_with("mission_") or not m.id.trim_prefix("mission_").is_valid_int():return false
	if int(m.id.trim_prefix("mission_"))<1 or int(m.id.trim_prefix("mission_"))>=int(c.next_mission):return false
	if not communities.has(m.get("neighbor","")) or m.get("kind") not in ["trade","aid"] or not m.get("started") is bool:return false
	var spec:Dictionary=communities[m.neighbor]
	var offer:Dictionary=spec.offer
	if not m.get("give") is String or not m.get("receive") is String:return false
	if m.get("give")!=(offer.give if m.kind=="trade" else spec.aid.resource) or m.get("receive")!=offer.receive:return false
	for key in ["give_amount","receive_amount","duration","remaining","escorts","loss"]:
		if not rules.whole(m.get(key),0,int(balance.max_stock)):return false
	if m.give_amount!=(offer.give_amount if m.kind=="trade" else spec.aid.amount) or m.receive_amount!=(offer.receive_amount if m.kind=="trade" else 0):return false
	if m.duration!=spec.duration or m.remaining<1 or m.remaining>m.duration or m.escorts>balance.max_escorts or m.loss>balance.max_loss_percent:return false
	return m.started or m.remaining==m.duration
