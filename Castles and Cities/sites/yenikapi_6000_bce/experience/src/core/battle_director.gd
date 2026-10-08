extends RefCounted
## A deterministic commander that submits the same serialized orders as a person.
## Decisions see friendly state, prepared positions and currently observed enemies.
const Tactical=preload("res://src/core/tactical_sim.gd")
const Nav=preload("res://src/core/defense_navigation.gd")

static func configure(b: Dictionary,spec: Dictionary,serial: int,t: Dictionary) -> String:
	if b.get("phase")!="deployment" or not b.get("tactics") is Dictionary or b.tactics.has("encounter") or serial<0:return "bad_order"
	if not spec.get("id") is String or spec.id.is_empty() or spec.get("kind") not in ["occupy","snatch","probe"] or not spec.get("place") is String or not b.nav.places.has(spec.place):return "bad_order"
	if not spec.get("origins") is Array or spec.origins.is_empty():return "bad_order"
	for origin in spec.origins:
		if not origin is Array or origin.size()!=2:return "bad_order"
		for value in origin:
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>300:return "bad_order"
	var objective: Array=b.nav.places[spec.place].duplicate()
	var placements: Dictionary={};var occupied: Array=[];var first: Array=[];var index: int=0
	for f in b.groups:
		if f.side=="watch":occupied.append({"position":f.position,"width":int(f.tactical.effective_width),"count":int(f.initial)})
	for f in b.groups:
		if f.side!="raider":continue
		var origin: Array=spec.origins[index%spec.origins.size()];index+=1
		var near: Array=Nav.nearest(b.nav,[roundi(float(origin[0])*100),roundi(float(origin[1])*100)])
		if near.is_empty():return "unreachable_destination"
		var at: Array=Tactical._slot(b,near,occupied,[],f,t)
		if at.is_empty() or Nav.route(b.nav,at,objective).is_empty():return "unreachable_destination"
		placements[f.id]=at;occupied.append({"position":at,"width":int(f.tactical.effective_width),"count":int(f.initial)})
		if first.is_empty():first=at.duplicate()
	if first.is_empty():return "bad_order"
	# Nothing is changed until every initial approach has been checked.
	b.tactics.objective=objective;b.exits.raider=first
	b.tactics.encounter={"id":spec.id,"serial":serial,"kind":spec.kind,"mode":"direct","next_decision":0,"stage":"approach","carrier":"","held":0}
	for f in b.groups:
		f.tactical.contacts={}
		if f.side!="raider":continue
		f.position=placements[f.id].duplicate();f.goal=objective.duplicate();f.path=[];f.order="advance";f.target=""
		f.tactical.path_goal=[];f.tactical.next_repath=0;f.tactical.wait=0;f.tactical.yield_goal=[];f.tactical.yield_origin=[];f.tactical.yield_for=""
	Tactical._observe(b,t)
	return ""

static func _prepared_position(b: Dictionary,t: Dictionary) -> Array:
	var objective: Array=b.tactics.objective
	var chosen: Array=objective;var distance: float=INF
	for zone in b.tactics.defenses:
		if zone.side!="watch":continue
		var current: float=Nav.point(zone.at).distance_to(Nav.point(objective))
		if current<=int(t.defend_cm) and current<distance:chosen=zone.at;distance=current
	return chosen.duplicate()

static func deployment_orders(b: Dictionary,t: Dictionary,r) -> Array:
	if b.get("phase")!="deployment" or not b.get("tactics") is Dictionary or not b.tactics.get("encounter") is Dictionary or b.tactics.encounter.mode!="delegated":return []
	var assembly: Array=b.tactics.get("plan",{}).get("assembly",[])
	if assembly.is_empty():return []
	var ids: Array=[]
	for f in b.groups:
		if f.side!="watch" or not Tactical.active(f) or f.order!="move":continue
		if Nav.point(f.goal).distance_to(Nav.point(assembly))>int(t.group_spacing_cm):continue
		var customized: bool=false
		# The first logged move is the saved assembly applied at mobilization.
		# Later explicit placement/holding orders belong to the player.
		for i in range(1,b.commands.size()):
			var action: Dictionary=b.commands[i].action
			if action.get("kind")=="defense_order" and f.id in action.get("ids",[]) and action.get("order")!="width":customized=true;break
		if not customized:ids.append(f.id)
	if ids.is_empty():return []
	var wanted: Array=_prepared_position(b,t)
	# A northern objective can lie beyond legal village deployment. Stage at
	# the closest legal clear point, then walk there under normal live orders.
	var allowed: Dictionary=b.nav.duplicate(true)
	for y in range(int(allowed.height)):
		if int(Nav.at(allowed,Vector2i(0,y))[1])<int(b.deploy_limit):allowed.rows[y]="#".repeat(int(allowed.width))
	var at: Array=Nav.nearest(allowed,[int(wanted[0]),maxi(int(wanted[1]),int(b.deploy_limit))])
	if at.is_empty():return []
	var action: Dictionary={"kind":"defense_order","order":"defend","ids":ids,"at":at}
	var probe: Dictionary=b.duplicate(true)
	return [action] if Tactical.order(probe,action,t,r).is_empty() else []

static func orders(b: Dictionary,t: Dictionary,r) -> Array:
	if b.get("phase")!="fighting" or b.get("paused",true) or not b.get("tactics") is Dictionary or not b.tactics.get("encounter") is Dictionary:return []
	var encounter: Dictionary=b.tactics.encounter
	if encounter.get("mode")!="delegated" or int(b.tick)<int(encounter.next_decision):return []
	encounter.next_decision=int(b.tick)+int(t.director_decision_ticks)
	var requests: Array=[];var defending: Array=[];var withdrawing: Array=[]
	var position: Array=_prepared_position(b,t)
	var carrier: Dictionary={}
	if encounter.kind=="snatch" and encounter.stage=="carrying":
		var observed: Dictionary=Tactical.find(b,str(encounter.carrier))
		if not observed.is_empty() and observed.side=="raider" and Tactical.active(observed) and Tactical.visible(b,"watch",observed,t):carrier=observed
	var friends: Array=[]
	for f in b.groups:
		if f.side=="watch" and Tactical.active(f):friends.append(f)
	friends.sort_custom(func(a,c):return str(a.id)<str(c.id))
	for f in friends:
		if f.order=="withdraw":continue
		if int(f.morale)<=int(t.director_retreat_morale) or int(f.tactical.fatigue)>=int(t.director_retreat_fatigue):
			withdrawing.append(f.id);continue
		if not carrier.is_empty():
			if f.order!="attack" or f.target!=carrier.id:requests.append({"kind":"defense_order","order":"attack","ids":[f.id],"target":carrier.id})
			continue
		# Retain an appropriate existing deployment/order, including its slot.
		if f.order=="defend" and Nav.point(f.goal).distance_to(Nav.point(position))<=int(t.group_spacing_cm):continue
		defending.append(f.id)
	if not withdrawing.is_empty():requests.append({"kind":"defense_order","order":"withdraw","ids":withdrawing,"at":b.exits.watch.duplicate()})
	if not defending.is_empty():requests.append({"kind":"defense_order","order":"defend","ids":defending,"at":position})
	# Dry runs use a detached state and the exact order validator. Root records
	# and applies only this returned valid stream through defense.control.
	var valid: Array=[];var probe: Dictionary=b.duplicate(true)
	for action in requests:
		if Tactical.order(probe,action,t,r).is_empty():valid.append(action)
	return valid
