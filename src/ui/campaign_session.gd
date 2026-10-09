class_name CampaignSession
extends Control
## One campaign, one save, retained city and strategic views. The tactical
## worker is joined before another view is allowed to access the shared game.
signal main_menu_requested

var game: Game
var save_path := CampaignScreen.SAVE_PATH
var city: RomaCityScreen
var campaign: CampaignScreen
var initial_view := "campaign"
var active_view := ""
var marcus
var marcus_context
var lucius
var lucius_context
var gaius
var gaius_context
var advisor_panels: Dictionary = {}
var advisor_contexts: Dictionary = {}
var advisor_statuses: Dictionary = {}
var active_advisor := "marcus"
var living_council
var _lucius_status: Dictionary = {}
var _season_review_pending := false
var _last_season_offered := -1
var _tutorial_refresh_left := 0.0


func _process(delta: float) -> void:
	# Presentation-only polling of already-recorded milestones. No detection,
	# progress or awards are performed by a frame/timer callback.
	_tutorial_refresh_left-=delta
	if _tutorial_refresh_left>0.0:return
	_tutorial_refresh_left=0.5
	if is_instance_valid(marcus):marcus.refresh_tutorial_offer()


static func create(current_game: Game, view: String = "campaign", slot: String = CampaignScreen.SAVE_PATH) -> CampaignSession:
	var session := CampaignSession.new()
	session.game = current_game
	session.initial_view = view
	session.save_path = slot
	return session


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Seed earned seats before a resumed city battle can start its worker.
	# Later refreshes reuse this cache while that worker owns mutable state.
	for id in game.data.advisors:advisor_statuses[id]=game.advisor_status(id)
	_lucius_status=advisor_statuses.get("lucius",{}).duplicate(true)
	if initial_view == "city" and can_enter_city():
		show_city()
	else:
		show_campaign()
	# Retain distinct conversations above both views, outside refresh cycles.
	marcus_context = preload("res://src/ui/advisors/marcus_campaign_context.gd").new(self)
	lucius_context = preload("res://src/ui/advisors/lucius_context.gd").new(self)
	gaius_context = preload("res://src/ui/advisors/gaius_context.gd").new(self)
	advisor_contexts = {"marcus":marcus_context,"lucius":lucius_context,"gaius":gaius_context}
	living_council=preload("res://src/ui/advisors/living_council.gd").new(self)
	add_child(living_council)
	living_council.changed.connect(_discussion_changed)
	var advisor_layer := CanvasLayer.new()
	advisor_layer.layer = 20
	add_child(advisor_layer)
	for id in advisor_contexts:
		var advisor = preload("res://Castles and Cities/sites/yenikapi_6000_bce/experience/src/marcus_panel.gd").new()
		advisor_panels[id] = advisor
		advisor_layer.add_child(advisor)
		advisor.opened_changed.connect(_advisor_opened)
		advisor.configure_context(advisor_contexts[id],id=="marcus")
		if id!="marcus":advisor.hide()
		advisor.advisor_requested.connect(_choose_advisor)
		advisor.council_speaker_requested.connect(_ask_council)
		advisor.refresh_requested.connect(_refresh_council)
	marcus = advisor_panels.marcus
	lucius = advisor_panels.lucius
	gaius = advisor_panels.gaius
	_refresh_council()


func can_enter_city() -> bool:
	var owner: String = game.state["player_faction"]
	return game.state["settlements"].get("latium", {}).get("owner", "") == owner or game.state.get("city_battles", {}).get("latium", {}).get("owner", "") == owner


func _suspend_views() -> void:
	_stop_discussion("context_changed")
	if is_instance_valid(city):
		city.battle_panel.host.stop()
		city.hide()
		city.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(campaign):
		campaign.map_view.finish_marches()
		campaign.hide()
		campaign.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_city() -> void:
	if not can_enter_city():
		show_campaign()
		return
	_suspend_views()
	if not is_instance_valid(city):
		city = RomaCityScreen.new()
		city.game = game
		city.standalone = false
		city.shared_session = true
		city.save_path = save_path
		city.campaign_requested.connect(show_campaign, CONNECT_DEFERRED)
		city.campaign_zoom_requested.connect(show_campaign_from_city, CONNECT_DEFERRED)
		city.main_menu_requested.connect(return_to_menu, CONNECT_DEFERRED)
		city.state_loaded.connect(_state_loaded)
		city.season_presented.connect(_season_presented)
		city.season_started.connect(_season_started)
		add_child(city)
		city.show_city_overview()
		city.battle_panel.closed.connect(_battle_view_closed, CONNECT_DEFERRED)
	city.process_mode = Node.PROCESS_MODE_INHERIT
	city.show()
	active_view = "city"
	city.refresh_city()
	city._refresh_drawer()
	_advisor_opened(is_instance_valid(_active_panel()) and _active_panel().is_open())
	var battle := game.city_battle_status("latium")
	if battle.get("active", false) or battle.get("can_defend", false):
		city.open_battle()


func show_campaign() -> void:
	_suspend_views()
	if not is_instance_valid(campaign):
		campaign = CampaignScreen.create(game)
		campaign.save_path = save_path
		campaign.shared_session = true
		campaign.main_menu_enabled = true
		campaign.city_requested.connect(show_city, CONNECT_DEFERRED)
		campaign.main_menu_requested.connect(return_to_menu, CONNECT_DEFERRED)
		campaign.state_loaded.connect(_state_loaded)
		campaign.season_presented.connect(_season_presented)
		campaign.season_started.connect(_season_started)
		add_child(campaign)
	campaign.process_mode = Node.PROCESS_MODE_INHERIT
	campaign.show()
	active_view = "campaign"
	campaign.refresh()
	_advisor_opened(is_instance_valid(_active_panel()) and _active_panel().is_open())
	if can_enter_city():
		campaign.map_view.center_on("latium")


func show_campaign_from_city() -> void:
	## Crossing the aerial camera's outer limit is navigation only. The shared
	## session stops any worker before the campaign renderer reads its state.
	show_campaign()
	campaign.map_view.focus_settlement("latium")


func _state_loaded() -> void:
	if is_instance_valid(living_council):living_council.reset()
	# Both views borrow the facade, so replacing its Dictionary replaces the
	# world for both. Clear only stale presentation, never make a second Game.
	if is_instance_valid(city):
		city.battle_panel.host.stop()
		if city.battle_panel.visible:
			city.battle_panel.close()
		if game.state["settlements"]["latium"]["owner"] == game.state["player_faction"]:
			game.city_campaign_enter("latium")
		city.refresh_city()
		city._refresh_drawer()
	if is_instance_valid(campaign):
		campaign._restore_loaded_presentation()
		campaign.refresh()
	if is_instance_valid(marcus):
		for id in advisor_panels:
			advisor_contexts[id].capture_season()
			advisor_panels[id].reset_conversation()
			advisor_panels[id].hide()
		active_advisor = "marcus"
		marcus.show()
		_refresh_council()
	_season_review_pending = false
	_last_season_offered = int(game.state.turn)


func return_to_menu() -> void:
	_stop_discussion()
	for advisor in advisor_panels.values():advisor.voice.stop()
	if is_instance_valid(city):
		city.battle_panel.host.stop()
	if not game.save_to(save_path):
		var message := String(game.data.effects_glossary["city_view"]["shared_save_failed"])
		if active_view == "city":
			city.show_message(message)
		else:
			campaign._log(message)
		return
	main_menu_requested.emit()


func _battle_view_closed() -> void:
	if active_view == "city" and game.state["settlements"]["latium"]["owner"] != game.state["player_faction"]:
		show_campaign()
	if _season_review_pending:_season_presented()
	_refresh_council()


func _advisor_opened(active: bool) -> void:
	if is_instance_valid(campaign):
		campaign.advisor_input_blocked = active
		if active:campaign.map_view.camera_input_enabled = false
	if is_instance_valid(city):city.advisor_input_blocked = active


func _season_started() -> void:
	_stop_discussion("context_changed")
	for advisor in advisor_panels.values():advisor.refresh_briefing(false)
	_season_review_pending = true


func _season_presented() -> void:
	if not is_instance_valid(marcus):return
	_season_review_pending = not marcus_context.capture_season()
	if not _season_review_pending:
		for id in advisor_contexts:
			if id!="marcus":advisor_contexts[id].capture_season()
		_refresh_council()
		var season: Dictionary = marcus_context.season_briefing()
		var turn: int = int(season.get("turn", -1))
		if turn != _last_season_offered:
			_last_season_offered = turn
			for advisor in advisor_panels.values():advisor.refresh_briefing()


func _exit_tree() -> void:
	_stop_discussion()
	if is_instance_valid(city) and city.battle_panel != null:
		city.battle_panel.host.stop()

func advisor_ids() -> Array:
	return advisor_contexts.keys()

func advisor_available(id: String) -> bool:
	return id=="marcus" or advisor_statuses.get(id,{}).get("available",false)

func _active_panel():
	return advisor_panels.get(active_advisor,marcus)

func _choose_advisor(id: String) -> void:
	if not advisor_panels.has(id) or id==active_advisor:return
	_refresh_council()
	if not advisor_available(id):return
	_stop_discussion()
	var previous = _active_panel()
	previous.close_panel() # End the old transport before changing speakers.
	previous.hide()
	active_advisor = id
	_active_panel().show()
	_active_panel().open()

func _ask_council(id: String) -> void:
	if not advisor_panels.has(id):return
	if marcus_context.council_context.blocked()!="":return
	_choose_advisor(id)
	if active_advisor==id:
		_active_panel().open_council_question(String(marcus_context.council_words().question))

func _refresh_council() -> void:
	if not is_instance_valid(marcus):return
	# A tactical worker owns mutable state while its view is open. Preserve
	# the last safe permanent-unlock reading until that view closes.
	var battle: bool = marcus_context._battle_visible()
	if not battle:
		for id in game.data.advisors:advisor_statuses[id] = game.advisor_status(id)
		_lucius_status = advisor_statuses.get("lucius",{}).duplicate(true)
	var words: Dictionary = game.data.advisor_content.ui
	var choices: Array = []
	for id in advisor_ids():
		var available: bool = advisor_available(id)
		var advisor_name: String = advisor_contexts[id].content.name
		choices.append({"id":id,"label":advisor_name if available else String(words.locked_name).format({"name":advisor_name}),
			"available":available,"detail":_advisor_detail(id) if not battle else words.battle})
	for id in advisor_panels:
		advisor_panels[id].set_council(choices,String(words.battle) if battle else _advisor_detail(id))

func _advisor_detail(id: String) -> String:
	var words: Dictionary = game.data.advisor_content.ui
	if id=="marcus":
		var lines: PackedStringArray=[]
		for specialist in game.data.advisors:
			var profile: Dictionary=game.data.advisors[specialist]
			var status: Dictionary=advisor_statuses.get(specialist,{})
			lines.append(String(words.roster_ready if advisor_available(specialist) else words.roster_locked).format({
				"name":profile.name,"required":profile.unlock.min_level,"kind":profile.unlock_label,"current":status.get("level",0)}))
		return "\n".join(lines)
	var profile: Dictionary=game.data.advisors.get(id,{})
	var status: Dictionary=advisor_statuses.get(id,{})
	if profile.is_empty():return ""
	if status.get("available",false):
		var earned: Dictionary=status.unlocked
		return String(words.advisor_available).format({"name":profile.name,"settlement":game.data.regions.get(earned.region,{}).get("settlement_name",earned.region),"turn":earned.turn})
	var detail: String=String(words.locked_requirement).format({"name":profile.name,"kind":profile.unlock_label,"required":profile.unlock.min_level,"current":status.get("level",0)})
	if status.get("required_building","")!="":
		detail+=" "+String(words.building_example).format({"settlement":game.data.regions.get(status.region,{}).get("settlement_name",status.region),"building":status.required_building})
	return detail

func _stop_discussion(reason: String="stopped") -> void:
	if is_instance_valid(living_council) and living_council.active:living_council.stop(reason)

func _discussion_changed() -> void:
	for panel in advisor_panels.values():panel.refresh_living_council()
