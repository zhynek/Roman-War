extends RefCounted
## Independent village adapter. Never invokes or alters the parent BattleResolver.
## Mobilization reserves existing home-watch assignments; outcome commits once.
const Nav=preload("res://src/core/defense_navigation.gd")
const Sim=preload("res://src/core/defense_sim.gd")
const Director=preload("res://src/core/battle_director.gd")
const ORDER_BUDGET: int=2000
var content: Dictionary
var tuning: Dictionary
var definition_hash: String
var tactical_tuning: Dictionary={}
var threat_tuning: Dictionary={}
func battle_tuning(b: Dictionary) -> Dictionary:
	if not b.has("tactics"):return tuning
	var merged: Dictionary=tuning.duplicate(true);merged.merge(tactical_tuning,true)
	if b.get("tactics") is Dictionary and b.tactics.get("encounter") is Dictionary and b.tactics.encounter.get("id") is String:
		merged.merge(threat_tuning.get("encounters",{}).get(b.tactics.encounter.id,{}),true)
	return merged
func prepare_delegated(b: Dictionary,r) -> void:
	for action in Director.deployment_orders(b,battle_tuning(b),r):control(b,action,r)
func step(b: Dictionary,r) -> void:
	if b.phase!="fighting" or b.paused:return
	for action in Director.orders(b,battle_tuning(b),r):
		control(b,action,r)
	Sim.tick(b,battle_tuning(b))
func _init(config: Dictionary,balance: Dictionary) -> void:
	content=config;tuning=balance
	definition_hash=JSON.stringify([content.get("profile"),content.get("bounds"),content.get("places"),content.get("enemy_origins"),content.get("deployment"),tuning]).sha256_text()
func active(s: Dictionary) -> bool:return s.get("defense",{}) is Dictionary and not s.get("defense",{}).is_empty()
func locked(s: Dictionary) -> bool:return active(s) and s.defense.get("battle",{}) is Dictionary and not s.defense.get("battle",{}).is_empty()
func unavailable(s: Dictionary,id: String) -> bool:
	var d: Variant=s.get("defense",{})
	if not d is Dictionary or not d.get("recovery",{}) is Dictionary:return false
	var value: Variant=d.get("recovery",{}).get(id,0)
	return (value is int or value is float) and is_finite(float(value)) and value>0
func candidates(s: Dictionary,r) -> Array:
	var result: Array=[]
	for task in r.assignments(s,r.effective_plan(s)):
		if task.job=="watch" and task.get("duty","watch") in ["watch","living_training","warfare_muster"] and not unavailable(s,task.id):result.append(task.id)
	result.sort()
	return result.slice(0,int(tuning.maximum_defenders))
func quote(s: Dictionary,r) -> Dictionary:
	var ids:=candidates(s,r)
	var kits: int=mini(ids.size(),int(s.get("living",{}).get("kits",0)))
	var posts: int=0
	if r.assets.active(s) and int(s.assets.conditions.watch)>=int(r.assets.balance.condition_threshold):
		posts=int(r.has_project(s,"watch_shelter"))+int(r.has_project(s,"living_north_post") and ids.size()>=int(r.living.balance.north_workers))
	return {"ids":ids,"count":ids.size(),"kits":kits,"readiness":int(s.get("living",{}).get("readiness",0)),"food":ids.size()*int(tuning.rations_per_person),"posts":posts}
func command(s: Dictionary,a: Dictionary,r) -> Dictionary:
	var kind: String=a.get("kind","")
	if kind=="defense_begin":
		if locked(s):return {"error":"blocked"}
		if not r.permitted(s,"watch"):return {"error":"authority"}
		if not r.living.active(s):return {"error":"living_missing"}
		if r.warfare.threats.enabled(s):
			if not r.warfare.threats.ready(s,r):return {"error":"threat_not_ready"}
		elif active(s) and s.defense.completed:return {"error":"completed"}
		var q:=quote(s,r)
		if q.count==0:return {"error":"no_defenders"}
		if s.food<q.food:return {"error":"funds"}
		if not navigation_valid(a.get("nav"),r):return {"error":"bad_order"}
		var n: Dictionary=s.duplicate(true)
		if not active(n):n.defense={"version":1,"profile":definition_hash,"completed":false,"battle":{},"recovery":{},"reports":[]}
		var nav: Dictionary=r.canonical(a.nav)
		var start: Array=Nav.nearest(nav,[int(content.deployment[0])*100,int(content.deployment[1])*100])
		var b: Dictionary={"version":1,"phase":"deployment","paused":true,"speed":1,"tick":0,"resolution_ticks":0,"capture":0,"idle":0,"nav":nav,"groups":[],"commands":[],"cost":q.food,"committed":false,"outcome":"","reason":"","deploy_limit":int(start[1])-int(tuning.deployment_depth_cm),"exits":{"watch":nav.places.refuge,"raider":[]}}
		var group_size: int=int(tuning.group_size)
		# Two independently selectable groups even with the ordinary two-person watch.
		if q.count<=group_size:group_size=1
		var kits_left: int=q.kits
		for i in range(0,q.ids.size(),group_size):
			var members: Array=q.ids.slice(i,i+group_size)
			var at: Array=Nav.nearest(nav,[start[0]+(i/group_size)*int(tuning.cell_cm)*3,start[1]])
			if Nav.route(nav,at,nav.places.stores).is_empty():return {"error":"bad_order"}
			var kits: int=mini(kits_left,members.size());kits_left-=kits
			var f:=Sim.formation("watch_"+str(i/group_size+1),"watch",at,members,kits,q.readiness,tuning)
			f.morale=maxi(0,int(f.morale)-(r.living.content.posts.size()-int(q.posts))*int(tuning.post_morale))
			b.groups.append(f)
		for i in range(content.enemy_origins.size()):
			var origin: Array=content.enemy_origins[i]
			var at:=Nav.nearest(nav,[int(origin[0])*100,int(origin[1])*100])
			if Nav.route(nav,at,nav.places.stores).is_empty():return {"error":"bad_order"}
			if i==0:b.exits.raider=at
			var members: Array=[]
			for j in range(int(tuning.enemy_people)):members.append("raider_%d_%d"%[i,j])
			var f:=Sim.formation("raider_"+str(i+1),"raider",at,members,0,0,tuning)
			f.order="advance";f.goal=nav.places.stores.duplicate();b.groups.append(f)
		if r.warfare.active(n):
			var error: String=r.warfare.enhance(b,n,r)
			if not error.is_empty():return {"error":error}
		n.defense.battle=b;n.food-=int(q.food)
		return {"state":n}
	if not locked(s):return {"error":"bad_order"}
	var n: Dictionary=s.duplicate(true);var b: Dictionary=n.defense.battle
	if kind=="defense_commit":
		if b.phase!="ended" or b.committed:return {"error":"bad_order"}
		var report:=outcome(b,r)
		for id in report.wounded:n.defense.recovery[id]=int(tuning.recovery_seasons)
		n.food=maxi(0,int(n.food)-int(report.lost))
		n.living.kits=maxi(0,int(n.living.kits)-int(report.kits))
		report.lost=mini(int(s.food),int(report.lost));report.protected=maxi(0,int(s.food)-int(report.lost))
		if r.warfare.active(n):r.warfare.aftermath.accept(n,s,report,r)
		n.defense.reports.append(report);n.defense.completed=true;n.defense.battle={}
		r.warfare.threats.accepted(n,s,report,r)
		r._event(n,"village_defense",{"outcome":report.outcome,"wounded":report.wounded.size(),"supplies":report.lost})
		n.assignments=[];n.plan=r.effective_plan(n)
		return {"state":n}
	var error: String=control(b,a,r)
	if not error.is_empty():return {"error":error}
	return {"state":n}
func control(b: Dictionary,a: Dictionary,r) -> String:
	if b.phase=="ended":return "bad_order"
	var safety_reserve: bool=b.commands.size()>=ORDER_BUDGET
	if safety_reserve:
		# A full ordinary log must never strand deployment or prevent saving,
		# cancellation and withdrawal. No new orders can reverse a withdrawal
		# in this reserve, so at most one is accepted per remaining formation.
		var safe: bool=a.get("kind")=="defense_start" and b.phase=="deployment"
		safe=safe or (a.get("kind")=="defense_pause" and b.phase=="fighting")
		if a.get("kind")=="defense_order" and a.get("order")=="withdraw" and a.get("ids") is Array and not a.ids.is_empty():
			safe=true
			for id in a.ids:
				var f: Dictionary=Sim.find(b,str(id))
				if f.is_empty() or f.order=="withdraw":safe=false;break
		if not safe:return "command_budget"
	match a.get("kind",""):
		"defense_start":
			if b.phase!="deployment":return "bad_order"
			b.phase="fighting";b.paused=false
		"defense_pause":b.paused=not b.paused if b.phase=="fighting" else true
		"defense_speed":b.speed=2 if b.speed==1 else 1
		"defense_mode":
			if not b.get("tactics",{}).has("encounter") or a.get("mode") not in ["direct","delegated"]:return "bad_order"
			b.tactics.encounter.mode=a.mode
			b.tactics.encounter.next_decision=int(b.tick)
		"defense_order":
			var error:=Sim.order(b,a,battle_tuning(b),r)
			if not error.is_empty():return error
		_:return "bad_order"
	# Two pause toggles at one fixed tick cancel exactly, even with intervening
	# orders (orders do not depend on pause). Do not cross the deployment start.
	# Thus the safety reserve needs at most one pause per encounter tick.
	if safety_reserve and a.get("kind")=="defense_pause":
		for index in range(b.commands.size()-1,-1,-1):
			var previous: Dictionary=b.commands[index]
			if int(previous.tick)!=int(b.tick) or previous.action.kind=="defense_start":break
			if previous.action.kind=="defense_pause":b.commands.remove_at(index);return ""
	b.commands.append({"tick":int(b.tick),"action":a.duplicate(true)})
	return ""
func outcome(b: Dictionary,r=null) -> Dictionary:
	var rules_tuning: Dictionary=battle_tuning(b)
	var wounded: Array=[];var kits: int=0
	for f in b.groups:
		if f.side!="watch":continue
		var count: int=maxi(0,int(f.initial)-Sim.standing(f,tuning))
		for id in f.members.slice(int(f.initial)-count):wounded.append(id)
		kits+=maxi(0,int(f.kits)-Sim.standing(f,tuning))
	var report: Dictionary={"outcome":b.outcome,"reason":b.reason,"wounded":wounded,"kits":kits,"lost":int(rules_tuning.supply_loss) if b.outcome in ["defeat","withdrawal"] else 0,"protected":0,"cost":b.cost,"ticks":b.tick}
	if r!=null and b.get("tactics",{}).has("encounter"):report=r.warfare.aftermath.decorate(b,report,r)
	return report
func recover(n: Dictionary,before: Dictionary,forecast: Dictionary) -> void:
	if not active(n) or not forecast.covered or int(forecast.plan.care)<int(tuning.care_workers):return
	for id in before.defense.recovery:
		var remaining: int=int(before.defense.recovery[id])-1
		if remaining<=0:n.defense.recovery.erase(id)
		else:n.defense.recovery[id]=remaining
func validate(s: Dictionary,r) -> bool:
	var d: Variant=s.get("defense",{})
	if not d is Dictionary:return false
	if d.is_empty():return true
	if d.size()!=6 or d.get("version")!=1 or d.get("profile")!=definition_hash or not d.get("completed") is bool:return false
	if not r.living.active(s) or not d.get("battle") is Dictionary or not d.get("recovery") is Dictionary or not d.get("reports") is Array or d.reports.size()>(int(r.balance.max_turns)+1 if r.warfare.active(s) else 1):return false
	for id in d.recovery:
		if r.person_by_id(s,str(id)).is_empty() or not r.whole(d.recovery[id],1,maxi(int(tuning.recovery_seasons),int(r.warfare.aftermath.tuning.incapacitated_recovery_seasons)) if r.warfare.active(s) else int(tuning.recovery_seasons)):return false
	if d.completed!=(not d.reports.is_empty()):return false
	for report in d.reports:
		if not report is Dictionary or report.size()!=(9 if report.has("aftermath") else 8):return false
		if report.has("aftermath") and (not r.warfare.active(s) or not r.warfare.aftermath.validate_report(report,s,r)):return false
		if report.get("outcome") not in ["victory","defeat","withdrawal","stalemate"] or report.get("reason") not in ["enemy_routed","stores_taken","watch_lost","withdrawn","time_limit","unreachable","objective_held","supplies_escaped","supplies_recovered","deadline_held"]:return false
		if not report.get("wounded") is Array:return false
		for id in report.wounded:
			if r.person_by_id(s,str(id)).is_empty():return false
		for k in ["kits","lost","protected","cost","ticks"]:
			if not r.whole(report.get(k),0,1000000):return false
	if d.battle.is_empty():return d.completed
	if d.completed and not r.warfare.threats.enabled(s):return false
	return valid_battle(d.battle,s,r)
func navigation_valid(nav: Variant,r) -> bool:
	if not Nav.valid(nav,r):return false
	return r.canonical(nav.origin)==content.bounds.slice(0,2) and nav.width==content.bounds[2] and nav.height==content.bounds[3] and nav.cell==tuning.cell_cm
func valid_battle(b: Dictionary,s: Dictionary,r) -> bool:
	if b.size()!=(18 if b.has("tactics") else 17) or b.get("version")!=1 or b.get("phase") not in ["deployment","fighting","ended"]:return false
	for key in ["paused","committed"]:
		if not b.get(key) is bool:return false
	if b.committed or not r.whole(b.get("speed"),1,2):return false
	for key in ["tick","capture","idle","cost","resolution_ticks"]:
		if not r.whole(b.get(key),0,100000):return false
	if not r.whole(b.get("deploy_limit"),-30000,30000):return false
	if not navigation_valid(b.get("nav"),r) or not b.get("exits") is Dictionary or b.exits.size()!=2:return false
	for side in ["watch","raider"]:
		if not Nav.position(b.exits.get(side),r) or not Nav.clear(b.nav,b.exits[side]):return false
	if b.get("outcome") not in ["","victory","defeat","withdrawal","stalemate"] or b.get("reason") not in ["","enemy_routed","stores_taken","watch_lost","withdrawn","time_limit","unreachable","objective_held","supplies_escaped","supplies_recovered","deadline_held"]:return false
	if (b.phase=="ended")!=(b.outcome!="" and b.reason!="") or (b.phase!="fighting" and not b.paused):return false
	if not b.get("groups") is Array or b.groups.size()<3 or b.groups.size()>10:return false
	var ids: Array=[];var people: Array=[]
	for f in b.groups:
		if not f is Dictionary or f.size()!=(23 if b.has("tactics") else 22) or not f.get("id") is String or f.id in ids:return false
		ids.append(f.id)
		if f.get("side") not in ["watch","raider"] or f.get("order") not in Sim.ORDERS or not f.get("target") is String:return false
		for key in ["routed","exited","revealed","moving","engaged"]:
			if not f.get(key) is bool:return false
		for key in ["hp","initial","kits","readiness","morale","cooldown","attack_seq","hit_seq"]:
			if not r.whole(f.get(key),0,100000):return false
		if f.initial<1 or f.initial>8 or f.hp>int(f.initial)*int(tuning.hp_per_person) or f.kits>f.initial or f.morale>100 or f.readiness>4:return false
		for key in ["position","goal","facing"]:
			if not Nav.position(f.get(key),r):return false
		if not Nav.clear(b.nav,f.position) or not Nav.clear(b.nav,f.goal):return false
		if not f.get("members") is Array or f.members.size()!=int(f.initial):return false
		for id in f.members:
			if not id is String or id in people:return false
			people.append(id)
			if f.side=="watch":
				var person: Dictionary=r.person_by_id(s,id)
				if person.is_empty() or not person.active or int(person.age)<int(r.balance.adult_age) or unavailable(s,id):return false
		if not f.get("path") is Array or f.path.size()>int(b.nav.width)*int(b.nav.height):return false
		var last: Array=f.position
		for p in f.path:
			if not Nav.position(p,r) or not Nav.clear(b.nav,p) or not Nav.line(b.nav,last,p):return false
			last=p
	for f in b.groups:
		if not f.target.is_empty():
			var target: Dictionary=Sim.find(b,f.target)
			if target.is_empty() or target.side==f.side:return false
	if not b.get("commands") is Array or b.commands.size()>ORDER_BUDGET+int(battle_tuning(b).limit_ticks)+12:return false
	var last_tick: int=0
	var reserve_pauses: Array=[];var reserve_withdrawals: Array=[]
	for index in range(b.commands.size()):
		var c: Variant=b.commands[index]
		if not c is Dictionary or c.size()!=2 or not r.whole(c.get("tick"),last_tick,int(b.tick)) or not c.get("action") is Dictionary:return false
		last_tick=int(c.tick)
		if c.action.get("kind") not in ["defense_start","defense_pause","defense_speed","defense_order","defense_mode"]:return false
		if index>=ORDER_BUDGET:
			if c.action.kind=="defense_pause":
				if c.tick in reserve_pauses:return false
				reserve_pauses.append(c.tick)
			elif c.action.kind=="defense_order" and c.action.get("order")=="withdraw" and c.action.get("ids") is Array:
				for id in c.action.ids:
					if id in reserve_withdrawals:return false
					reserve_withdrawals.append(id)
			elif c.action.kind!="defense_start":return false
		if c.action.kind=="defense_mode" and (not b.get("tactics",{}).has("encounter") or c.action.get("mode") not in ["direct","delegated"]):return false
		if c.action.kind=="defense_order":
			if c.action.get("order") not in (Sim.ORDERS+["width"] if b.has("tactics") else Sim.ORDERS) or not c.action.get("ids") is Array or c.action.ids.is_empty():return false
			var commanded: Array=[]
			for id in c.action.ids:
				if not id is String or id not in ids or id in commanded or Sim.find(b,id).side!="watch":return false
				commanded.append(id)
			if c.action.order=="attack":
				if not c.action.get("target") is String or c.action.target not in ids or Sim.find(b,c.action.target).side!="raider":return false
			elif c.action.order=="width":
				if not r.whole(c.action.get("width"),1,2):return false
			elif c.action.order!="hold" and not Nav.position(c.action.get("at"),r):return false
	return true
