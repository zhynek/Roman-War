extends RefCounted
## Acceptance decisions only. Live play never calls this driver.
static func orders(rules,state: Dictionary) -> Dictionary:
	var next: Dictionary=state
	if not rules.assets.active(next):next=rules.command(next,{"kind":"asset_begin"}).state
	next=rules.command(next,{"kind":"role","role":"god"}).state
	for id in ["welcome"]:next=rules.command(next,{"kind":"asset_principle","id":id,"value":1}).state
	if next.turn==3:next=rules.command(next,{"kind":"asset_pressure"}).state
	if next.turn==3:
		next=rules.command(next,{"kind":"asset_principle","id":"watch","value":1}).state
	for id in ["secure_stores","refuge","safe_routes","learning"]:
		if (id=="learning" and next.turn<7) or (id!="learning" and next.turn<3):continue
		if next.households.orders[id]:continue
		var response: Dictionary=rules.command(next,{"kind":"household_order","id":id,"enabled":true})
		if response.has("state"):next=response.state
	if next.queue.is_empty():
		for id in rules.content.tutorial_projects:
			if rules.has_project(next,id):continue
			var response: Dictionary=rules.command(next,{"kind":"commission","id":id})
			if response.has("state"):next=response.state
			break
	return next

static func at_season(rules,turn: int) -> Dictionary:
	var state: Dictionary=rules.new_state()
	for i in range(turn):state=rules.advance(orders(rules,state)).state
	return orders(rules,state)
