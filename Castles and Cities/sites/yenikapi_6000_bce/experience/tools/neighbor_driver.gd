extends RefCounted
## Reproducible acceptance orders. Never called by the running game.
const Tutorial=preload("res://tools/tutorial_driver.gd")
static func foundation(rules) -> Dictionary:
	var state:Dictionary=rules.new_state()
	while not state.town_achieved and state.turn<40:state=rules.advance(Tutorial.orders(rules,state)).state
	state=rules.command(state,{"kind":"commission","id":rules.neighbors.content.project_id}).state
	while not state.queue.is_empty():state=rules.advance(Tutorial.orders(rules,state)).state
	return state
static func orders(rules,state:Dictionary) -> Dictionary:
	var next:Dictionary=Tutorial.orders(rules,state)
	if not rules.neighbors.active(next):next=rules.command(next,{"kind":"neighbor_begin"}).state
	if not next.contacts.mission.is_empty():return next
	# First aid is useful before either store fills; then fulfill both exchanges.
	for kind in ["aid","trade"]:
		for id in rules.neighbors.communities:
			var local:Dictionary=next.contacts.neighbors[id]
			if (kind=="aid" and local.aid>0) or (kind=="trade" and local.trades>0):continue
			if kind=="aid":
				var done:bool=false
				for other in next.contacts.neighbors.values():
					if other.aid>0:done=true
				if done:continue
			var result:Dictionary=rules.command(next,{"kind":"neighbor_send","neighbor":id,"mission":kind})
			if result.has("state"):return result.state
	return next
