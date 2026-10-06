extends RefCounted
## QA strategies, ordinary public commands only. No authored resource grants.
static func initial(rules) -> Dictionary:
	var state: Dictionary=rules.command(rules.new_state(),{"kind":"asset_begin"}).state
	return rules.command(state,{"kind":"land_begin"}).state

static func orders(rules,input: Dictionary,compact: bool) -> Dictionary:
	var s: Dictionary=input
	for action in [{"kind":"asset_principle","id":"welcome","value":1},{"kind":"asset_principle","id":"reserve","value":1}]:
		s=rules.command(s,action).get("state",s)
	var steps: Array=["land_cultivate","shared_store","watch_shelter","care_shelter"]
	steps.append_array(["land_adapt_workroom","land_court_home","land_hearth_home"] if compact else ["land_outer_access","land_outer_west","land_outer_east"])
	steps.append_array(["council_ground","refuge_screen"])
	for id in steps:
		if rules.has_project(s,id):continue
		if s.queue.is_empty():s=rules.command(s,{"kind":"commission","id":id}).get("state",s)
		break
	return s

static func at_season(rules,compact: bool,seasons: int) -> Dictionary:
	var s: Dictionary=initial(rules)
	for i in range(seasons):
		s=orders(rules,s,compact)
		s=rules.advance(s).state
	return s
