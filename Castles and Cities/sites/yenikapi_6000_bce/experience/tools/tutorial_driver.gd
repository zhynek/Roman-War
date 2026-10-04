extends RefCounted
## Deterministic player orders for reproducible tutorial acceptance, never live autoplay.
static func orders(rules,state: Dictionary) -> Dictionary:
	var next: Dictionary=state
	var response: Dictionary=rules.command(next,{"kind":"role","role":"god"});next=response.state
	response=rules.command(next,{"kind":"policy","welcome":true,"tight_rations":false});next=response.state
	if next.queue.is_empty():
		for id in rules.content.tutorial_projects:
			if rules.has_project(next,id):continue
			response=rules.command(next,{"kind":"commission","id":id})
			if response.has("state"):next=response.state
			break
	response=rules.command(next,{"kind":"plan","plan":rules.suggested_plan(next)})
	assert(response.has("state"))
	return response.state
