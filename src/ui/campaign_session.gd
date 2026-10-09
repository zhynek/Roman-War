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
var active_advisor := "marcus"
var _lucius_status: Dictionary = {}
var _season_review_pending := false
var _last_season_offered := -1


static func create(current_game: Game, view: String = "campaign", slot: String = CampaignScreen.SAVE_PATH) -> CampaignSession:
	var session := CampaignSession.new()
	session.game = current_game
	session.initial_view = view
	session.save_path = slot
	return session


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if initial_view == "city" and can_enter_city():
		show_city()
	else:
		show_campaign()
	# Retain advisor conversations above both views, outside their refresh cycles.
	marcus_context = preload("res://src/ui/advisors/marcus_campaign_context.gd").new(self)
	var advisor_layer := CanvasLayer.new()
	advisor_layer.layer = 20
	add_child(advisor_layer)
	marcus = preload("res://Castles and Cities/sites/yenikapi_6000_bce/experience/src/marcus_panel.gd").new()
	advisor_layer.add_child(marcus)
	marcus.opened_changed.connect(_advisor_opened)
	marcus.configure_context(marcus_context)
	lucius_context = preload("res://src/ui/advisors/lucius_context.gd").new(self)
	lucius = preload("res://Castles and Cities/sites/yenikapi_6000_bce/experience/src/marcus_panel.gd").new()
	advisor_layer.add_child(lucius)
	lucius.configure_context(lucius_context,false)
	lucius.hide()
	lucius.opened_changed.connect(_advisor_opened)
	for advisor in [marcus,lucius]:
		advisor.advisor_requested.connect(_choose_advisor)
		advisor.council_speaker_requested.connect(_ask_council)
		advisor.refresh_requested.connect(_refresh_council)
	_refresh_council()


func can_enter_city() -> bool:
	var owner: String = game.state["player_faction"]
	return game.state["settlements"].get("latium", {}).get("owner", "") == owner or game.state.get("city_battles", {}).get("latium", {}).get("owner", "") == owner


func _suspend_views() -> void:
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
		marcus_context.capture_season()
		marcus.reset_conversation()
		lucius_context.capture_season()
		lucius.reset_conversation()
		lucius.hide()
		active_advisor = "marcus"
		marcus.show()
		_refresh_council()
	_season_review_pending = false
	_last_season_offered = int(game.state.turn)


func return_to_menu() -> void:
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
	if is_instance_valid(marcus):
		marcus.refresh_briefing(false)
		lucius.refresh_briefing(false)
	_season_review_pending = true


func _season_presented() -> void:
	if not is_instance_valid(marcus):return
	_season_review_pending = not marcus_context.capture_season()
	if not _season_review_pending:
		lucius_context.capture_season()
		_refresh_council()
		var season: Dictionary = marcus_context.season_briefing()
		var turn: int = int(season.get("turn", -1))
		if turn != _last_season_offered:
			_last_season_offered = turn
			marcus.refresh_briefing()
			lucius.refresh_briefing()


func _exit_tree() -> void:
	if is_instance_valid(city) and city.battle_panel != null:
		city.battle_panel.host.stop()

func _active_panel():
	return lucius if active_advisor == "lucius" else marcus

func _choose_advisor(id: String) -> void:
	if id not in ["marcus","lucius"] or id == active_advisor:return
	_refresh_council()
	if id == "lucius" and not _lucius_status.get("available",false):return
	var previous = _active_panel()
	previous.close_panel() # stop streaming before changing the visible speaker
	previous.hide()
	active_advisor = id
	_active_panel().show()
	_active_panel().open()

func _ask_council(id: String) -> void:
	if id not in ["marcus","lucius"]:return
	if marcus_context.council_context.blocked()!="":return
	_choose_advisor(id)
	if active_advisor==id:
		_active_panel().open_council_question(String(marcus_context.council_words().question))

func _refresh_council() -> void:
	if not is_instance_valid(marcus) or not is_instance_valid(lucius):return
	var words: Dictionary = game.data.advisor_content.ui
	var detail: String = words.battle
	# The worker may be mutating campaign state: keep the last safe unlock
	# reading until the battle closes; no new eligibility read during combat.
	if not marcus_context._battle_visible():
		_lucius_status = game.advisor_status("lucius")
		if _lucius_status.get("available",false):
			var earned: Dictionary = _lucius_status.unlocked
			detail = String(words.available).format({"settlement":game.data.regions.get(earned.region,{}).get("settlement_name",earned.region),"turn":earned.turn})
		else:
			detail = String(words.locked).format({"required":_lucius_status.get("required_level",0),"current":_lucius_status.get("level",0)})
			if _lucius_status.get("qualifies",false):detail += " " + String(words.qualifying)
			if _lucius_status.get("required_building","") != "":
				detail += " " + String(words.building_example).format({"settlement":game.data.regions[_lucius_status.region].get("settlement_name",_lucius_status.region),"building":_lucius_status.required_building})
			else:detail += " " + String(words.no_seat)
	var available: bool = _lucius_status.get("available",false)
	var choices: Array = [{"id":"marcus","label":words.marcus,"available":true},
		{"id":"lucius","label":words.lucius if available else words.locked_button,"available":available}]
	marcus.set_council(choices,detail)
	lucius.set_council(choices,detail)
