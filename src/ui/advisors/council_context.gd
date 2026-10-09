extends RefCounted
## UI-only shared evidence and authored perspectives. No autonomous orders,
## provider requests, hidden journals, or economic reads during a battle.
var _owner: WeakRef
var owner:
	get:return _owner.get_ref()
var content: Dictionary

func _init(context_owner) -> void:
	_owner=weakref(context_owner)
	content=JSON.parse_string(FileAccess.get_file_as_string("res://data/council.json"))

func blocked() -> String:
	if owner._battle_visible():return "battle"
	var session=owner.session
	if is_instance_valid(session.campaign):
		if session.campaign.turn_sequence.is_playing() or session.campaign.dispatch_panel.visible:return "presentation"
	if session.active_view=="city" and is_instance_valid(session.city) and session.city.dawn.visible:return "presentation"
	return ""

func page() -> Dictionary:
	var result: Dictionary={"source":"authored_council", "scope":"latest_resolved_season", "blocked":blocked(),
		"season":{}, "city":{}, "speakers":[], "patron":{}}
	if result.blocked!="":return result
	var session=owner.session
	var game: Game=session.game
	result.season=session.marcus_context.season_briefing()
	if not result.season.is_empty():result.season.stale=int(result.season.turn)!=int(game.state.turn)
	result.current_turn=int(game.state.turn)
	result.city=_city()
	var patron: Dictionary=game.patronage_status().get("active",{})
	if not patron.is_empty():result.patron={"id":patron.id,"name":patron.name,"mission":patron.mission,"tradeoff":patron.tradeoff}
	for id in ["marcus","lucius"]:
		var available: bool=id=="marcus" or session._lucius_status.get("available",false)
		var profile: Dictionary=content.speakers[id]
		var card: Dictionary={"id":id,"name":profile.name,"available":available}
		if available:
			card.stance=profile.stance
			card.counsel=profile.counsel
			if not result.city.is_empty():card.city=profile.city
			if not result.season.is_empty():card.season=profile.season
			if not patron.is_empty():card.mandate=profile.patrons.get(patron.id,"")
		result.speakers.append(card)
	return result

func _city() -> Dictionary:
	var game: Game=owner.session.game
	var region: String=owner._screen().get("region", "")
	if game.state.settlements.get(region,{}).get("owner","")!=game.state.player_faction:return {}
	var result: Dictionary={"region":region,"name":game.data.regions[region].get("settlement_name",region),
		"society":owner._fields(game.society_report(region),["level","stale_turns","unrest_state","legitimacy","grievance","assimilation"]),
		"tax_level":game.state.settlements[region].tax_level,"factors":{},"factor_limit":int(owner.content.limits.context_factors)}
	result.factors.public_order=owner._factors(game.order_breakdown(region))
	result.factors.growth=owner._factors(game.growth_breakdown(region))
	result.factors.income=owner._factors(game.income_breakdown(region))
	return result

func patronage_page() -> Dictionary:
	var result: Dictionary={"blocked":blocked(),"status":{},"fiction":owner.session.game.data.patronage_content.ui.fiction}
	if result.blocked!="":return result
	var game: Game=owner.session.game
	result.status=game.patronage_status().duplicate(true)
	# Keep eligible seats bounded by the campaign's actual owned settlement
	# list, using only public names and completed temple records.
	for option in result.status.get("options",[]):
		option.required_temples=[]
		for chain_id in option.get("temple_chains",[]):
			var chain: Dictionary=game.data.chains.get(chain_id,{})
			if not chain.is_empty():option.required_temples.append(String(chain.name))
		for temple in option.get("temples",[]):
			temple.city=game.data.regions.get(temple.region,{}).get("settlement_name",temple.region)
			var levels: Array=game.data.chains.get(temple.chain,{}).get("levels",[])
			temple.name=levels[int(temple.level)-1].name if int(temple.level)>0 and int(temple.level)<=levels.size() else temple.chain
	return result

func commit_patronage(action: String, id: String, region: String) -> String:
	var block: String=blocked()
	if block!="":return block
	var game: Game=owner.session.game
	var status: Dictionary=game.patronage_status()
	if status.get("command_blocked","")!="":return "finished" if status.command_blocked=="campaign_finished" else "blocked"
	var success:=false
	if action=="pledge":success=game.pledge_patron(id,region)
	elif action=="renounce":success=game.renounce_patron()
	if not success:return "changed"
	return "pledged" if action=="pledge" else "renounced"

func patronage_snapshot() -> Dictionary:
	if blocked()!="":return {"scope":"unavailable_during_battle_or_presentation"}
	var status: Dictionary=owner.session.game.patronage_status()
	var result: Dictionary=owner._fields(status,["chosen","pledged_turn","progress","last_checked_turn","target","has_matching_temple","completed"])
	# No temple inventory is needed in the live prompt. It is visible in the
	# explicit pledge page, not copied wholesale into every conversation.
	if not status.get("active",{}).is_empty():
		result.active=owner._fields(status.active,["id","name","mission","tradeoff","mandates","completed"])
	result.available_patrons=[]
	for option in status.get("options",[]):
		result.available_patrons.append(owner._fields(option,["id","name","mission","tradeoff","eligible","completed","temple_chains"]))
	return result
