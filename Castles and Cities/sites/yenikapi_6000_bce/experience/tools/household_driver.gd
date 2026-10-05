extends RefCounted
## Reproducible acceptance example. Runtime never plays decisions automatically.
static func prepared(rules) -> Dictionary:
	var state:Dictionary=rules.new_state()
	state=rules.command(state,{"kind":"household_begin"}).state
	state=rules.command(state,{"kind":"plan","plan":rules.suggested_plan(state)}).state
	for id in ["secure_stores","refuge","safe_routes","learning"]:
		state=rules.command(state,{"kind":"household_order","id":id,"enabled":true}).state
	return state
static func at_season(rules, elapsed:int) -> Dictionary:
	var state:Dictionary=prepared(rules)
	for i in range(elapsed):
		state=rules.command(state,{"kind":"plan","plan":rules.suggested_plan(state)}).state
		state=rules.advance(state).state
	return state
