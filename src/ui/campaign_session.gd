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
		add_child(city)
		city.show_city_overview()
		city.battle_panel.closed.connect(_battle_view_closed, CONNECT_DEFERRED)
	city.process_mode = Node.PROCESS_MODE_INHERIT
	city.show()
	active_view = "city"
	city.refresh_city()
	city._refresh_drawer()
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
		add_child(campaign)
	campaign.process_mode = Node.PROCESS_MODE_INHERIT
	campaign.show()
	active_view = "campaign"
	campaign.refresh()
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


func _exit_tree() -> void:
	if is_instance_valid(city) and city.battle_panel != null:
		city.battle_panel.host.stop()
