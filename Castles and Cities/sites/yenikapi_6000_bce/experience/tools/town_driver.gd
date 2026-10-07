extends "res://tools/lifecycle_driver.gd"
## Continuous public-command strategy. No grants, rank edits or simulated UI work.
static func finished_town(r,s: Dictionary) -> bool:
	return r.has_project(s,"town_civic") and r.has_project(s,"town_preparation") and r.has_project(s,"town_provision")

static func town_action(r,s: Dictionary,compact: bool=true) -> Dictionary:
	if not r.lifecycle.active(s):return {"kind":"lifecycle_begin"}
	if not r.lifecycle.town_active(s):return {"kind":"lifecycle_town_begin"}
	if not finished(r,s):return next_action(r,s,compact)
	for id in ["town_civic","town_preparation","town_provision"]:
		if r.has_project(s,id):continue
		if s.queue.is_empty() and not r.quote(s,{"kind":"commission","id":id}).has("error"):return {"kind":"commission","id":id}
		return {}
	return {}

static func town_trace(r,compact: bool=true,seasons: int=100) -> Dictionary:
	var s: Dictionary=initial(r)
	var commands: Array=[]
	var milestones: Dictionary={}
	for season in range(seasons):
		for i in range(24):
			var action: Dictionary=town_action(r,s,compact)
			if action.is_empty():break
			var result: Dictionary=r.command(s,action)
			if not result.has("state"):return {"error":result,"action":action}
			commands.append({"turn":s.turn,"action":action.duplicate(true)})
			s=result.state
		commands.append({"turn":s.turn,"action":{"kind":"advance"}})
		var result: Dictionary=r.advance(s)
		if not result.has("state"):return {"error":result}
		s=result.state
		for item in s.completed:
			if (String(item.id).begins_with("town_") or String(item.id).begins_with("lifecycle_")) and not milestones.has(item.id):milestones[item.id]=s.turn
	return {"state":s,"commands":commands,"milestones":milestones}
