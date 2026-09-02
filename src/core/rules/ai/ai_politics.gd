class_name AiPolitics
## Phase 7: how a non-player Roman house answers the Senate. The rule is
## obedience — when the conscript fathers demand the patriarch's life, the
## house lets the charge run to its last turn hoping for a change of heart,
## then complies rather than be outlawed. (A defiance temperament per persona
## is a follow-up; see HANDOFF.) Deterministic, rng-free.


static func take_turn(data: GameData, state: Dictionary, faction_id: String, character_notices: Array) -> void:
	if not data.factions.get(faction_id, {}).get("is_roman_house", false):
		return
	var mission = state["factions"][faction_id].get("mission")
	if mission == null:
		return
	var kind := String(data.missions.get(String(mission.get("template", "")), {}).get("kind", ""))
	if kind != "leader_suicide":
		return
	# The AI acts before the Senate ticks the charge: turns_left == 1 now is
	# the turn the deadline falls on.
	if int(mission.get("turns_left", 0)) > 1:
		return
	SenateRules.comply_with_demand(data, state, faction_id, character_notices)
