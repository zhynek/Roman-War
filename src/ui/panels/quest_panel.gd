class_name QuestPanel
extends VBoxContainer
## The guided trail's live checklist: the active stages, their objectives with
## progress, and the rewards waiting. Reads only GuidedRules.overview — all
## judgement stays in the rules layer. Hidden entirely when the trail is off.

const MAX_STAGES_SHOWN := 3

const OBJECTIVE_LABELS := {
	"set_taxes": "Set a tax level",
	"queue_building": "Queue a building",
	"recruit_units": "Recruit units",
	"raise_army": "Raise a field army",
	"move_army": "March an army",
	"hire_mercenaries": "Hire mercenaries",
	"explore_sites": "Search marked sites",
	"win_battles": "Win battles",
	"capture_regions": "Capture settlements",
	"senate_missions": "Complete a senate mission",
	"hold_regions": "Hold regions",
	"treasury_at_least": "Fill the treasury",
	"governor_in_capital": "A governor in your capital",
	"no_siege_on_target": "Break the siege",
	"no_intruders": "Clear your borders",
}


func render(game: Game, overview: Dictionary) -> void:
	for child in get_children():
		# remove_child before queue_free: freed rows linger until end of frame
		# otherwise (same idiom as RegionPanel).
		remove_child(child)
		child.queue_free()
	visible = overview["enabled"] and not overview["active"].is_empty()
	if not visible:
		return

	var header := Label.new()
	header.text = "Objectives — %d of %d trail steps done" % [int(overview["done"]), int(overview["total"])]
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	add_child(header)

	var active: Array = overview["active"]
	for i in range(mini(active.size(), MAX_STAGES_SHOWN)):
		_render_stage(game, active[i])
	if active.size() > MAX_STAGES_SHOWN:
		_line("… and %d more underway" % (active.size() - MAX_STAGES_SHOWN), Color(0.7, 0.7, 0.7), 10)


func _render_stage(game: Game, stage: Dictionary) -> void:
	var title: String = stage["name"]
	if stage["expires_in"] != null:
		title += "  (%d turns left)" % int(stage["expires_in"])
	_line(title, Color(0.9, 0.8, 0.5), 12)
	_line(stage["text"], Color(0.75, 0.75, 0.75), 10, true)

	var connector := "any of:" if stage["complete"] == "any" and stage["objectives"].size() > 1 else ""
	if connector != "":
		_line(connector, Color(0.7, 0.7, 0.7), 10)
	for objective in stage["objectives"]:
		var mark := "✓" if objective["met"] else "•"
		var text := "%s  %s" % [mark, _describe(objective)]
		if int(objective["need"]) > 1 or objective["kind"] == "treasury_at_least":
			text += "  (%d/%d)" % [int(objective["have"]), int(objective["need"])]
		_line(text, Color(0.55, 0.85, 0.55) if objective["met"] else Color(0.85, 0.85, 0.85), 11)

	var reward_text := _describe_reward(game, stage["reward"])
	if reward_text != "":
		_line("Reward: " + reward_text, Color(0.8, 0.72, 0.5), 10)


func _describe(objective: Dictionary) -> String:
	var label: String = OBJECTIVE_LABELS.get(objective["kind"], String(objective["kind"]).replace("_", " "))
	if objective["kind"] == "queue_building" and objective.has("building_kind"):
		label = "Queue a %s building" % String(objective["building_kind"]).replace("_", " ")
	return label


func _describe_reward(game: Game, reward: Dictionary) -> String:
	var parts: Array = []
	if reward.get("treasury", 0) > 0:
		parts.append("%d denarii" % int(reward["treasury"]))
	for grant in reward.get("units", []):
		var unit_name: String = game.data.units.get(grant["template"], {}).get("name", grant["template"])
		parts.append("%d× %s" % [int(grant["count"]), unit_name])
	if reward.get("experience", 0) > 0:
		parts.append("+%d experience" % int(reward["experience"]))
	var boon: Dictionary = reward.get("boon", {})
	if boon.has("recruit_xp"):
		parts.append("+%d recruit experience, forever" % int(boon["recruit_xp"]))
	if boon.has("income_pct"):
		parts.append("+%s%% income, forever" % str(boon["income_pct"]))
	if boon.has("movement"):
		parts.append("+%s march, forever" % str(boon["movement"]))
	return " · ".join(parts)


func _line(text: String, color: Color, size: int, wrap: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
