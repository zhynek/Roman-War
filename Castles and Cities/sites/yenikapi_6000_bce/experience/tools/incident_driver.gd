extends RefCounted
const Living=preload("res://tools/living_driver.gd")
static func initial(r) -> Dictionary:return r.command(Living.initial(r),{"kind":"incident_begin"}).state
static func order(r,s: Dictionary,a: Dictionary) -> Dictionary:return r.command(s,a).get("state",s)
static func orders(r,s: Dictionary,strategy: String) -> Dictionary:
	s=order(r,s,{"kind":"asset_principle","id":"reserve","value":1})
	s=order(r,s,{"kind":"asset_principle","id":"watch","value":1 if strategy!="underprepared" else 0})
	# Produce everything from the normal opening stocks; no fixture supplies.
	s=order(r,s,{"kind":"living_order","id":"prepare","value":1 if s.living.blanks<4 else 0})
	var e: Dictionary=r.incidents.current(s)
	if not e.is_empty():
		var spec: Dictionary=r.incidents.specs[e.id]
		if strategy=="attentive" and int(s.turn)>=e.signs:s=order(r,s,{"kind":"incident_inspect","id":spec.place})
		if e.known>=0 or (strategy=="attentive" and s.turn>=e.signs):
			if strategy!="underprepared":
				s=order(r,s,{"kind":"living_order","id":"patrol","value":spec.post})
				if strategy=="attentive":s=order(r,s,{"kind":"incident_restrict","enabled":true})
				if e.outcome.is_empty():s=order(r,s,{"kind":"commission","id":spec.prepare})
			if not e.outcome.is_empty():
				s=order(r,s,{"kind":"living_order","id":"training","value":false})
				s=order(r,s,{"kind":"commission","id":spec.repair})
				if s.assets.initiatives.has(spec.repair):s=order(r,s,{"kind":"asset_project","id":spec.repair,"priority":1,"crew":2,"paused":false})
	for id in ["field_extension","shared_store","watch_shelter"]:s=order(r,s,{"kind":"commission","id":id})
	if strategy!="underprepared":
		s=order(r,s,{"kind":"commission","id":"living_watch_kits"})
		s=order(r,s,{"kind":"living_order","id":"training","value":s.living.kits>0 and s.living.readiness<r.living.balance.training_max})
	if strategy=="attentive":
		for id in ["living_north_post","land_outer_access"]:s=order(r,s,{"kind":"commission","id":id})
		s=order(r,s,{"kind":"household_order","id":"secure_stores","enabled":true})
	return s
static func at_season(r,count: int,strategy: String="attentive") -> Dictionary:
	var s: Dictionary=initial(r)
	for i in range(count):s=r.advance(orders(r,s,strategy)).state
	return s
