extends RefCounted
## QA measurement only. Every continuing-state change is an ordinary public
## command or resolved season. Recipes can replay from the ordinary opening.
const Base=preload("res://tools/lifecycle_driver.gd")

static func rules():return Base.rules()
static func digest(r,s: Dictionary) -> String:return JSON.stringify(r.canonical(s)).sha256_text()
static func command(r,s: Dictionary,a: Dictionary,recipe: Array,errors: Array) -> Dictionary:
	var response: Dictionary=r.advance(s) if a.kind=="advance" else r.command(s,a)
	if not response.has("state"):
		errors.append({"turn":s.turn,"action":a.duplicate(true),"error":response.get("error","unknown")});return s
	recipe.append({"turn":s.turn,"action":a.duplicate(true)})
	return response.state
static func initial(r,recipe: Array,errors: Array,warfare: bool=true) -> Dictionary:
	var s: Dictionary=r.new_state()
	for kind in ["asset_begin","land_begin","living_begin"]:s=command(r,s,{"kind":kind},recipe,errors)
	if warfare:s=command(r,s,{"kind":"warfare_begin"},recipe,errors)
	return s
static func shaping(s: Dictionary) -> int:
	var best: int=0
	for home in s.living.experience.values():best=maxi(best,int(home.shaping))
	return best
static func queue_has(s: Dictionary,id: String) -> bool:
	for item in s.queue:
		if item.id==id:return true
	return false
static func project_order(r,s: Dictionary,id: String) -> Dictionary:
	if r.has_project(s,id) or queue_has(s,id):return {}
	var a: Dictionary={"kind":"commission","id":id}
	return a if not r.quote(s,a).has("error") else {}
static func next_action(r,s: Dictionary,options: Dictionary={}) -> Dictionary:
	if not r.lifecycle.active(s):return {"kind":"lifecycle_begin"}
	if not r.lifecycle.town_active(s):return {"kind":"lifecycle_town_begin"}
	var reserve: int=int(options.get("reserve",2))
	if int(s.assets.reserve)!=reserve:return {"kind":"asset_principle","id":"reserve","value":reserve-1}
	if int(s.assets.watch)!=1:return {"kind":"asset_principle","id":"watch","value":1}
	var welcome: bool=bool(options.get("welcome",true))
	if s.welcome!=welcome:return {"kind":"asset_principle","id":"welcome","value":int(welcome)}
	var maintain: bool=bool(options.get("maintenance",true))
	if s.assets.maintenance.stores!=maintain:return {"kind":"asset_maintenance","id":"stores","enabled":maintain}
	var prepare: int=1 if bool(options.get("prepare",true)) and shaping(s)<int(r.lifecycle.balance.readiness.shaping) else 0
	if int(s.living.prepare)!=prepare:return {"kind":"living_order","id":"prepare","value":prepare}
	var projects: Array=["land_cultivate","shared_store","watch_shelter","care_shelter"]
	match str(options.get("layout","compact")):
		"compact":projects.append_array(["land_adapt_workroom","land_court_home","land_hearth_home"])
		"outward":projects.append_array(["land_outer_access","land_outer_west","land_outer_east","land_adapt_workroom"])
		"mixed":projects.append_array(["land_outer_access","land_court_home","land_outer_east","land_adapt_workroom"])
	projects.append_array(["council_ground","refuge_screen","lifecycle_assembly","lifecycle_store","lifecycle_workroom","town_civic"])
	if bool(options.get("facilities",true)):projects.append_array(["town_preparation","town_provision"])
	for id in projects:
		if r.has_project(s,id):continue
		return project_order(r,s,id) if s.queue.is_empty() else {}
	return {}
static func snapshot(r,s: Dictionary) -> Dictionary:
	var f: Dictionary=r.forecast(s)
	var duty: Dictionary={}
	for req in f.get("assets",{}).get("requests",[]):duty[req.id]={"wanted":req.wanted,"filled":req.filled,"priority":req.priority,"reason":req.reason}
	var costs: Dictionary={}
	for key in ["repair_cost","access_cost"]:costs[key]=f.get("assets",{}).get(key,0)
	for key in ["fuel","prepare_wood","repair_wood","support"]:costs[key]=f.get("living",{}).get(key,0)
	var stress: Dictionary={}
	for id in s.households.homes:stress[id]=s.households.homes[id].stress
	return {"turn":s.turn,"people":r.people(s).size(),"adults":r.people(s,true).size(),"food":s.food,"wood":s.wood,"housing":r.capacity(s),"storage":r.storage(s),"stage":r.lifecycle.stage(s,r),"support":r.town_conditions(s),"places":r.land.totals(s,r).work,"wellbeing":s.wellbeing,"cooperation":s.cooperation,"security":s.security,"shaping":shaping(s),"blanks":s.living.blanks,"kits":s.living.kits,"readiness":s.living.readiness,"conditions":s.assets.conditions.duplicate(true),"orders":s.households.orders.duplicate(true),"plan":f.plan.duplicate(true),"requests":duty,"costs":costs,"gathered":f.gathered,"overflow":f.overflow,"unfed":f.unfed,"losses":f.losses,"town":f.get("town",{}).duplicate(true),"readiness_factors":r.lifecycle.status(s,r).factors,"recovery":s.get("defense",{}).get("recovery",{}).duplicate(true),"equipment_condition":s.get("warfare",{}).get("aftermath",{}).get("equipment_condition",100),"household_stress":stress,"queue":s.queue.duplicate(true)}
static func trace(r,options: Dictionary={},seasons: int=100) -> Dictionary:
	var recipe: Array=[];var errors: Array=[]
	var s: Dictionary=initial(r,recipe,errors,bool(options.get("warfare",true)))
	var rows: Array=[snapshot(r,s)];var milestones: Dictionary={};var validity: bool=true
	for season in range(seasons):
		for i in range(24):
			var a: Dictionary=next_action(r,s,options)
			if a.is_empty():break
			s=command(r,s,a,recipe,errors)
			if not errors.is_empty():break
		if not errors.is_empty():break
		s=command(r,s,{"kind":"advance"},recipe,errors)
		validity=validity and r.validate_state(s)
		rows.append(snapshot(r,s))
		for item in s.completed:
			if not milestones.has(item.id):milestones[item.id]=s.turn
	return {"state":s,"commands":recipe,"errors":errors,"valid":validity,"milestones":milestones,"rows":rows,"digest":digest(r,s)}
static func replay(r,start: Dictionary,recipe: Array) -> Dictionary:
	var s: Dictionary=start.duplicate(true)
	for entry in recipe:
		if int(entry.turn)!=int(s.turn):return {}
		var action: Dictionary=r.canonical(entry.action)
		var response: Dictionary=r.advance(s) if action.kind=="advance" else r.command(s,action)
		if not response.has("state"):return {}
		s=response.state
	return s
static func battle_preparation(r,s: Dictionary,options: Dictionary,recipe: Array,errors: Array) -> Dictionary:
	if not r.warfare.active(s):s=command(r,s,{"kind":"warfare_begin"},recipe,errors)
	var equip: bool=bool(options.get("equipped",true))
	var prep: int=1 if equip and s.living.blanks<4 else 0
	for a in [{"kind":"living_order","id":"prepare","value":prep},{"kind":"living_order","id":"training","value":equip and s.living.kits>0 and s.living.readiness<r.living.balance.training_max},{"kind":"living_order","id":"repair","value":equip},{"kind":"asset_maintenance","id":"watch","enabled":bool(options.get("maintained",true))}]:
		var current: Variant=s.assets.maintenance.watch if a.kind=="asset_maintenance" else s.living[a.id]
		var wanted: Variant=a.get("value",a.get("enabled"))
		if current!=wanted:s=command(r,s,a,recipe,errors)
	var projects: Array=["living_watch_kits"] if equip else []
	if bool(options.get("fortified",false)):projects.append_array(["warfare_store_screen","warfare_landing_screen"])
	for id in projects:
		var a: Dictionary=project_order(r,s,id)
		if not a.is_empty():s=command(r,s,a,recipe,errors)
	return s
static func incident_orders(r,s: Dictionary,prepared: bool,recipe: Array,errors: Array) -> Dictionary:
	var prep: int=1 if s.living.blanks<4 else 0
	for a in [{"kind":"asset_principle","id":"watch","value":int(prepared)},{"kind":"living_order","id":"prepare","value":prep},{"kind":"living_order","id":"training","value":prepared and s.living.kits>0 and s.living.readiness<r.living.balance.training_max},{"kind":"household_order","id":"secure_stores","enabled":prepared}]:
		var old: Variant=s.assets.watch if a.kind=="asset_principle" else (s.households.orders.secure_stores if a.kind=="household_order" else s.living[a.id])
		if old!=a.get("value",a.get("enabled")):s=command(r,s,a,recipe,errors)
	if prepared:
		for id in ["living_watch_kits","living_north_post"]:
			var a: Dictionary=project_order(r,s,id)
			if not a.is_empty():s=command(r,s,a,recipe,errors)
	var e: Dictionary=r.incidents.current(s)
	if e.is_empty():return s
	var spec: Dictionary=r.incidents.specs[e.id]
	if prepared and e.known>=0:
		if spec.place not in e.inspected:s=command(r,s,{"kind":"incident_inspect","id":spec.place},recipe,errors)
		if s.living.patrol!=spec.post:s=command(r,s,{"kind":"living_order","id":"patrol","value":spec.post},recipe,errors)
		if e.outcome.is_empty():
			if not e.restricted:s=command(r,s,{"kind":"incident_restrict","enabled":true},recipe,errors)
			var a: Dictionary=project_order(r,s,spec.prepare)
			if not a.is_empty():s=command(r,s,a,recipe,errors)
	# Both routes receive the same ordinary repair opportunity after the loss.
	if not e.outcome.is_empty():
		var a: Dictionary=project_order(r,s,spec.repair)
		if not a.is_empty():s=command(r,s,a,recipe,errors)
	return s
