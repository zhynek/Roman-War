extends RefCounted
## Paid village screens reuse the queue, fabric ledger and watch maintenance.
## Named planning ground grants neither structures nor standing defenders.
const Nav=preload("res://src/core/defense_navigation.gd")
var content: Dictionary
var tuning: Dictionary
var projects: Dictionary={}

func _init(config: Dictionary,balance: Dictionary) -> void:
	content=config.duplicate(true);tuning=balance.duplicate(true)
	for authored in content.get("projects",[]):
		var project: Dictionary=authored.duplicate(true)
		var price: Dictionary=tuning.projects[project.tuning]
		for key in ["wood","work","effects"]:project[key]=price[key].duplicate(true) if price[key] is Dictionary else price[key]
		projects[project.id]=project

func blocked(state: Dictionary,id: String,rules) -> String:
	if projects.has(id) and not rules.warfare.active(state):return "warfare_missing"
	return ""

func plan_locations(nav: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for position in content.get("positions",[]):
		result[position.id]=Nav.nearest(nav,[roundi(float(position.at[0])*100),roundi(float(position.at[1])*100)])
	return result

func enhance(battle: Dictionary,state: Dictionary,rules) -> void:
	if not rules.warfare.active(state) or not rules.assets.active(state) or not battle.has("tactics"):return
	if int(state.assets.conditions.watch)<int(rules.assets.balance.condition_threshold):return
	var locations: Dictionary=plan_locations(battle.nav)
	for defense in content.get("defenses",[]):
		if not rules.has_project(state,defense.project):continue
		var at: Array=locations.get(defense.position,[])
		if at.is_empty():continue
		var zone: Dictionary={"at":at.duplicate(),"radius":int(tuning.radius_cm),"protection":int(tuning.protection),"side":"watch"}
		if zone not in battle.tactics.defenses:battle.tactics.defenses.append(zone)
