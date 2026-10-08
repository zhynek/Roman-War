extends "marcus_campaign_context.gd"
## Lucius receives the same visibility boundary, narrowed to civil government.
func _init(owner_session) -> void:
	super(owner_session)
	content=JSON.parse_string(FileAccess.get_file_as_string("res://data/lucius.json"))
	lessons=content.lessons
	preference_path="user://lucius_campaign_preferences.cfg"

func create_portrait():
	return preload("res://src/ui/advisors/lucius_portrait.gd").new()

func context_snapshot() -> Dictionary:
	var result: Dictionary=super()
	result.advisor={"id":"lucius","role":content.role}
	for key in ["observed_armies","observed_armies_omitted","selected_fleet","order_preview"]:result.erase(key)
	# During battles super() returns only an already-detached UI snapshot.
	if not _battle_visible():result.city_reading=city_reading()
	return result

func city_reading() -> Dictionary:
	var words: Dictionary=session.game.data.advisor_content.reading
	var result: Dictionary={"title":words.heading,"note":words.source,"sections":[]}
	if _battle_visible():
		result.note=words.battle
		return result
	var game: Game=session.game
	var region: String=_screen().get("region", "")
	if game.state.settlements.get(region,{}).get("owner", "") != game.state.player_faction:
		result.note=words.no_selection
		return result
	result.title=game.data.regions[region].get("settlement_name",region)
	var report: Dictionary=game.society_report(region)
	result.note += "\n"+String(words.survey).format({"level":report.get("level",""),"turns":report.get("stale_turns",0)})
	result.note += "\n"+String(words.tax).format({"tax":game.state.settlements[region].tax_level})
	var groups: Dictionary={"public_order":game.order_breakdown(region),"growth":game.growth_breakdown(region),"income":game.income_breakdown(region)}
	for key in ["public_order","growth","income"]:
		var lines: Array=[]
		var factors: Array=groups[key]
		var total:=0.0
		for factor in factors:total+=float(factor.value)
		for factor in factors.slice(0,int(content.limits.context_factors)):
			lines.append(String(words.factor).format({"label":String(factor.label).replace("_"," ").capitalize(),"value":"%+.1f"%float(factor.value)}))
		lines.append(String(words.total).format({"value":"%.1f"%total}))
		if factors.size()>int(content.limits.context_factors):lines.append(String(words.limited).format({"limit":content.limits.context_factors}))
		result.sections.append({"title":words[key],"lines":lines})
	var lines: Array=[]
	for key in ["legitimacy","grievance","assimilation","unrest_state"]:
		var value=report.get(key)
		lines.append(String(words.factor).format({"label":words[key],"value":str(value) if value!=null else words.unknown}))
	result.sections.append({"title":words.society,"lines":lines})
	return result
