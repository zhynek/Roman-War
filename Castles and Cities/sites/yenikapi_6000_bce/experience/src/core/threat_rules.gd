extends RefCounted
## Explicit seasonal scheduling only. Combat, stocks and recovery remain in their owners.
## No scene, rendering clock or randomness participates in a warning or a cycle.
var content: Dictionary
var tuning: Dictionary
var encounters: Dictionary={}
var sequence: Array=[]
func _init(config: Dictionary,balance: Dictionary) -> void:
	content=config;tuning=balance
	for item in content.get("encounters",[]):
		var record: Dictionary=item.duplicate(true)
		record.merge(tuning.get("encounters",{}).get(item.id,{}),true)
		encounters[item.id]=record;sequence.append(item.id)
func enabled(s: Dictionary) -> bool:
	return s.get("warfare",{}) is Dictionary and s.warfare.get("threats",{}) is Dictionary and not s.warfare.get("threats",{}).is_empty()
func begin(s: Dictionary,r) -> Dictionary:
	if not s.get("warfare",{}) is Dictionary or s.get("warfare",{}).is_empty():return {"error":"warfare_missing"}
	if enabled(s):return {"error":"threat_started"}
	if r.defense.locked(s):return {"error":"blocked"}
	if not r.permitted(s,"watch"):return {"error":"authority"}
	if int(s.turn)+int(tuning.quiet_seasons)+int(tuning.warning_seasons)+int(tuning.contact_warning)>int(r.balance.max_turns):return {"error":"threat_horizon"}
	var n: Dictionary=s.duplicate(true)
	n.warfare.threats={"version":1,"started":int(s.turn),"cycle":0,"last_accepted":-1,"next_turn":int(s.turn)+int(tuning.quiet_seasons),"pending":{},"last_turn":int(s.turn)}
	return {"state":n}
func reason(s: Dictionary,r) -> String:
	if not s.get("defense",{}).get("recovery",{}).is_empty():return "threat_recovery"
	if r.incidents.phase(s) in ["signs","warning","recovery"]:return "threat_incident"
	var quote: Dictionary=r.defense.quote(s,r)
	if int(quote.count)<=0:return "threat_watch"
	var reserve: int=r.people(s).size()*int(r.balance.food_per_person)*int(tuning.recovery_food_seasons)
	if int(s.food)<int(quote.food)+reserve:return "threat_food"
	return ""
func ready(s: Dictionary,r) -> bool:
	if not enabled(s):return false
	var pending: Dictionary=s.warfare.threats.pending
	return not pending.is_empty() and int(s.turn)>=int(pending.due) and reason(s,r).is_empty()
func spec(s: Dictionary) -> Dictionary:
	var id: String=str(sequence[0]) if not sequence.is_empty() else ""
	if enabled(s):id=str(s.warfare.threats.get("pending",{}).get("id",id))
	return encounters.get(id,{}).duplicate(true)
func _contact(s: Dictionary,r) -> String:
	if not r.neighbors.active(s):return ""
	var ids: Array=s.contacts.neighbors.keys();ids.sort()
	for id in ids:
		var local: Dictionary=s.contacts.neighbors[id]
		if int(local.trust)>=int(r.neighbors.balance.trust_trade_min) and (int(local.trades)>0 or int(local.aid)>0):return str(id)
	return ""
func advance(n: Dictionary,before: Dictionary,_forecast: Dictionary,r) -> void:
	if not enabled(n) or int(n.turn)!=int(before.turn)+1:return
	var state: Dictionary=n.warfare.threats
	if int(state.last_turn)>=int(n.turn):return
	state.last_turn=int(n.turn)
	if not state.pending.is_empty() or int(n.turn)<int(state.next_turn) or not reason(n,r).is_empty():return
	var contact: String=_contact(n,r)
	var due: int=int(n.turn)+int(tuning.warning_seasons)+(int(tuning.contact_warning) if not contact.is_empty() else 0)
	if due>int(r.balance.max_turns):return
	state.pending={"id":sequence[int(state.cycle)%sequence.size()],"serial":int(state.cycle)+1,"announced":int(n.turn),"due":due,"contact":contact}
func accepted(n: Dictionary,before: Dictionary,_report: Dictionary,r) -> void:
	if not enabled(before) or not enabled(n):return
	var pending: Dictionary=before.warfare.threats.pending
	if pending.is_empty() or n.warfare.threats.pending!=pending:return
	var battle: Dictionary=before.get("defense",{}).get("battle",{})
	var encounter: Dictionary=battle.get("tactics",{}).get("encounter",{})
	if battle.get("phase")!="ended" or encounter.get("id")!=pending.id or encounter.get("serial")!=pending.serial:return
	if n.get("defense",{}).get("reports",[]).size()!=before.get("defense",{}).get("reports",[]).size()+1:return
	if int(n.warfare.threats.cycle)!=int(before.warfare.threats.cycle):return
	n.warfare.threats.cycle=int(pending.serial)
	n.warfare.threats.last_accepted=int(n.turn)
	n.warfare.threats.next_turn=int(n.turn)+int(tuning.quiet_seasons)
	n.warfare.threats.pending={}
	# At the chapter horizon, the next warning remains deferred rather than truncated.
	n.warfare.threats.last_turn=mini(int(n.turn),int(r.balance.max_turns))
func validate(s: Dictionary,r) -> bool:
	var warfare: Variant=s.get("warfare",{})
	if not warfare is Dictionary:return false
	var state: Variant=warfare.get("threats",{})
	if not state is Dictionary:return false
	if state.is_empty():return true
	if state.size()!=7 or state.get("version")!=1:return false
	var defense: Variant=s.get("defense",{})
	if not defense is Dictionary or not defense.get("reports",[]) is Array:return false
	if not r.whole(state.get("cycle"),0,int(r.balance.max_turns)):return false
	if int(state.cycle)>defense.get("reports",[]).size():return false
	if not r.whole(state.get("started"),int(s.warfare.started),int(s.turn)):return false
	var last: int=int(state.started)
	if int(state.cycle)==0:
		if not r.whole(state.get("last_accepted"),-1,-1):return false
	else:
		var earliest: int=int(state.started)+int(state.cycle)*(int(tuning.quiet_seasons)+int(tuning.warning_seasons))
		if not r.whole(state.get("last_accepted"),earliest,int(s.turn)):return false
		last=int(state.last_accepted)
	if not r.whole(state.get("next_turn"),int(s.warfare.started)+int(tuning.quiet_seasons),int(r.balance.max_turns)+int(tuning.quiet_seasons)):return false
	if int(state.next_turn)!=last+int(tuning.quiet_seasons):return false
	if not r.whole(state.get("last_turn"),int(s.turn),int(s.turn)):return false
	var pending: Variant=state.get("pending")
	if not pending is Dictionary:return false
	if pending.is_empty():return true
	if pending.size()!=5 or pending.get("id")!=sequence[int(state.cycle)%sequence.size()]:return false
	if not r.whole(pending.get("serial"),int(state.cycle)+1,int(state.cycle)+1):return false
	if not r.whole(pending.get("announced"),int(state.next_turn),int(s.turn)):return false
	if not pending.get("contact") is String:return false
	var bonus: int=0
	if not pending.contact.is_empty():
		var contacts: Variant=s.get("contacts",{})
		if not contacts is Dictionary or not contacts.get("neighbors") is Dictionary or not contacts.neighbors.has(pending.contact):return false
		var local: Variant=contacts.neighbors[pending.contact]
		if not local is Dictionary or not r.whole(local.get("trades"),0,int(r.balance.max_turns)) or not r.whole(local.get("aid"),0,int(r.balance.max_turns)):return false
		if int(local.trades)<=0 and int(local.aid)<=0:return false
		bonus=int(tuning.contact_warning)
	var due: int=int(pending.announced)+int(tuning.warning_seasons)+bonus
	if due>int(r.balance.max_turns) or not r.whole(pending.get("due"),due,due):return false
	return true
