class_name DiplomacyRules
## Minimal diplomacy for the foundation: symmetric stances and war declaration.
## Offers, tribute, attitude modeling and the full negotiation scroll are the
## Phase 5 agent/diplomacy systems; the stance graph they will drive exists now.


static func stance_between(state: Dictionary, a: String, b: String) -> String:
	if a == b:
		return "self"
	return state["factions"][a]["diplomacy"].get(b, "neutral")


static func at_war(state: Dictionary, a: String, b: String) -> bool:
	return a != b and stance_between(state, a, b) == "war"


static func set_stance(state: Dictionary, a: String, b: String, stance: String) -> bool:
	if a == b or not Constants.STANCES.has(stance):
		return false
	if not state["factions"].has(a) or not state["factions"].has(b):
		return false
	state["factions"][a]["diplomacy"][b] = stance
	state["factions"][b]["diplomacy"][a] = stance
	if stance != "war":
		_lift_sieges_between(state, a, b)
	return true


static func _lift_sieges_between(state: Dictionary, a: String, b: String) -> void:
	## Peace means the siege lines come down — a parked army must never starve
	## out a settlement its faction is no longer at war with.
	for settlement in state["settlements"].values():
		var siege = settlement["siege"]
		if siege == null or not state["armies"].has(siege["besieger"]):
			continue
		var besieger: String = state["armies"][siege["besieger"]]["owner"]
		var holder: String = settlement["owner"]
		if (besieger == a and holder == b) or (besieger == b and holder == a):
			settlement["siege"] = null


static func declare_war(data: GameData, state: Dictionary, a: String, b: String) -> bool:
	## Any hostile act routes through here, so a betrayed alliance simply ends
	## — and the wronged side remembers who drew first (Phase 5 attitude).
	if a == b or at_war(state, a, b):
		return set_stance(state, a, b, "war")
	if not set_stance(state, a, b, "war"):
		return false
	NegotiationRules.shift_stored_attitude(data, state, b, a,
		float(data.balance["attitude"]["war_declared_penalty"]))
	return true
