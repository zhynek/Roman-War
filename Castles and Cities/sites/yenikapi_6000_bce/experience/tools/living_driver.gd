extends RefCounted
static func initial(r) -> Dictionary:
	var s: Dictionary=preload("res://tools/land_driver.gd").initial(r)
	return r.command(s,{"kind":"living_begin"}).state
static func try_order(r,s: Dictionary,a: Dictionary) -> Dictionary:return r.command(s,a).get("state",s)
static func orders(r,s: Dictionary,attentive: bool) -> Dictionary:
	# Both strategies protect reserves and maintain ordinary care and ready watch.
	s=try_order(r,s,{"kind":"asset_principle","id":"reserve","value":1})
	s=try_order(r,s,{"kind":"asset_principle","id":"watch","value":1})
	for id in ["field_extension","shared_store","watch_shelter"]:s=try_order(r,s,{"kind":"commission","id":id})
	if attentive:
		for id in ["west_wood","sim_household_04","workroom","north_wood"]:s=try_order(r,s,{"kind":"living_inspect","id":id})
		for id in ["living_shared_room","living_north_post"]:s=try_order(r,s,{"kind":"commission","id":id})
		if r.has_project(s,"living_north_post"):
			s=try_order(r,s,{"kind":"living_order","id":"patrol","value":"north_post"})
			var area: String="north_wood" if s.living.woodland.north_wood>=12 else "west_wood"
			s=try_order(r,s,{"kind":"living_order","id":"area","value":area})
	var prepare: int=2 if attentive and r.has_project(s,"living_shared_room") else 1
	if s.living.blanks>=4 and r.has_project(s,"living_watch_kits"):prepare=0
	s=try_order(r,s,{"kind":"living_order","id":"prepare","value":prepare})
	if attentive:s=try_order(r,s,{"kind":"living_order","id":"cooperate","value":true})
	s=try_order(r,s,{"kind":"commission","id":"living_watch_kits"})
	s=try_order(r,s,{"kind":"living_order","id":"training","value":s.living.kits>0 and s.living.readiness<r.living.balance.training_max})
	return s
static func at_season(r,count: int,attentive: bool=true) -> Dictionary:
	var s: Dictionary=initial(r)
	for i in range(count):s=r.advance(orders(r,s,attentive)).state
	return orders(r,s,attentive)
