class_name CampaignScreen
extends Control
## The campaign in play: top bar (treasury, date, standings, end turn), the
## map in the middle, the region context panel and turn log on the right.
## All rules go through the Game facade — this screen never touches state
## except to read it for display.

const SAVE_PATH := "user://roman_war_save.json"

var game: Game

var map_view: MapView
var region_panel: RegionPanel
var family_panel: FamilyPanel
var diplomacy_panel: DiplomacyPanel
var offers_panel: OffersPanel
var report_log: RichTextLabel
var top_labels := {}
var selected_army := ""
var selected_agent := ""
var _victory_shown := false


static func create(new_game: Game) -> CampaignScreen:
	var screen := CampaignScreen.new()
	screen.game = new_game
	return screen


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_top_bar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	map_view = MapView.new()
	map_view.game = game
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.custom_minimum_size = Vector2(600, 400)
	map_view.region_clicked.connect(_on_region_clicked)
	split.add_child(map_view)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	split.add_child(side)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	region_panel = RegionPanel.new()
	region_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_panel.action_taken.connect(refresh)
	region_panel.army_selected.connect(_on_army_selected)
	region_panel.agent_selected.connect(_on_agent_selected)
	region_panel.attack_requested.connect(attack_army_order)
	region_panel.siege_requested.connect(besiege_order)
	region_panel.negotiate_requested.connect(func(faction_id: String): diplomacy_panel.open_for(game, faction_id))
	region_panel.confirm_requested.connect(func(text: String, on_accept: Callable): _confirm(text, on_accept))
	region_panel.notice.connect(_log)
	scroll.add_child(region_panel)

	report_log = RichTextLabel.new()
	report_log.custom_minimum_size = Vector2(0, 160)
	report_log.scroll_following = true
	report_log.bbcode_enabled = true
	side.add_child(report_log)

	family_panel = FamilyPanel.new()
	family_panel.family_changed.connect(refresh)
	add_child(family_panel)

	diplomacy_panel = DiplomacyPanel.new()
	diplomacy_panel.stance_changed.connect(refresh)
	diplomacy_panel.war_requested.connect(declare_war_order)
	diplomacy_panel.treaty_end_requested.connect(end_treaty_order)
	diplomacy_panel.region_focus_requested.connect(focus_region)
	diplomacy_panel.notice.connect(_log)
	add_child(diplomacy_panel)

	offers_panel = OffersPanel.new()
	offers_panel.responded.connect(refresh)
	offers_panel.confirm_requested.connect(func(text: String, on_accept: Callable): _confirm(text, on_accept, offers_panel))
	offers_panel.notice.connect(_log)
	add_child(offers_panel)

	_log("[b]The year is 270 BC.[/b] Your house awaits its orders.")
	# Centering must wait for the first layout, or it centers on the map's
	# minimum size rather than the window it actually gets.
	var capital: String = game.state["factions"][game.state["player_faction"]]["capital"]
	map_view.center_on.call_deferred(capital)
	refresh()


func _build_top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 34)

	var faction: Dictionary = game.data.factions[game.state["player_faction"]]
	var swatch := ColorRect.new()
	swatch.color = Color.html(faction.get("color", "#808080"))
	swatch.custom_minimum_size = Vector2(18, 18)
	bar.add_child(swatch)

	for key in ["faction", "treasury", "date", "senate", "victory"]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		bar.add_child(label)
		top_labels[key] = label
	top_labels["faction"].text = " %s   " % faction["name"]

	bar.add_child(_spacer())
	bar.add_child(_bar_button("Family", func(): family_panel.open_for(game)))
	bar.add_child(_bar_button("Diplomacy", func(): diplomacy_panel.open_for(game)))
	top_labels["offers"] = _bar_button("Offers", func(): offers_panel.open_for(game))
	bar.add_child(top_labels["offers"])
	bar.add_child(_bar_button("Save", _save_game))
	bar.add_child(_bar_button("Load", _load_game))
	var end_turn := _bar_button("END TURN", _end_turn)
	end_turn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	bar.add_child(end_turn)
	return bar


func refresh() -> void:
	var faction: Dictionary = game.state["factions"][game.state["player_faction"]]
	top_labels["treasury"].text = "Treasury: %d   " % int(faction["treasury"])
	var year := int(game.state["year"])
	var year_text := "%d BC" % -year if year < 0 else "AD %d" % year
	top_labels["date"].text = "%s, %s   " % [year_text, String(game.state["season"]).capitalize()]
	if game.data.factions[game.state["player_faction"]].get("is_roman_house", false):
		top_labels["senate"].text = "Senate %.0f · People %.0f   " \
			% [float(faction["senate_standing"]), float(faction["popular_standing"])]
	var progress := game.victory_progress()
	if not progress.is_empty():
		top_labels["victory"].text = "Regions %d/%d" \
			% [int(progress["regions_held"]), int(progress["regions_needed"])]
	var waiting := game.pending_offers().size()
	top_labels["offers"].text = "Offers (%d)" % waiting if waiting > 0 else "Offers"
	top_labels["offers"].disabled = waiting == 0

	# An army or agent that died or was dismissed leaves no dangling selection.
	if selected_army != "" and not game.state["armies"].has(selected_army):
		selected_army = ""
	if selected_agent != "" and not game.state["agents"].has(selected_agent):
		selected_agent = ""
	if map_view.selected_region != "":
		region_panel.show_region(game, map_view.selected_region, selected_army, selected_agent)
	map_view.queue_redraw()

	if game.state["winner"] != null and not _victory_shown:
		_show_victory_banner(String(game.state["winner"]))


func _on_region_clicked(region_id: String) -> void:
	# With one of our armies selected, a click on another region is an order.
	# Shift makes it a forced march: double range, weary men.
	if selected_army != "" and game.state["armies"].has(selected_army) \
			and region_id != game.state["armies"][selected_army]["region"]:
		_army_order(region_id, Input.is_key_pressed(KEY_SHIFT))
		return
	# An agent travels the same way, but crosses any border.
	if selected_agent != "" and game.state["agents"].has(selected_agent) \
			and region_id != game.state["agents"][selected_agent]["region"]:
		_agent_order(region_id)
		return
	map_view.selected_region = region_id
	selected_army = ""
	selected_agent = ""
	region_panel.show_region(game, region_id)
	map_view.queue_redraw()


func _on_army_selected(army_id: String) -> void:
	selected_army = "" if selected_army == army_id else army_id
	selected_agent = ""
	region_panel.show_region(game, map_view.selected_region, selected_army)


func _on_agent_selected(agent_id: String) -> void:
	selected_agent = "" if selected_agent == agent_id else agent_id
	selected_army = ""
	region_panel.show_region(game, map_view.selected_region, "", selected_agent)


func _agent_order(target_region: String) -> void:
	var agent: Dictionary = game.state["agents"][selected_agent]
	var kind_name: String = String(game.data.agent_kinds.get(agent["kind"], {}).get("name", agent["kind"])).to_lower()
	var target_name: String = game.data.regions[target_region]["name"]
	if game.move_agent(selected_agent, target_region):
		_log("Our %s travels to %s." % [kind_name, target_name])
	elif game.sea_move_agent(selected_agent, target_region):
		_log("Our %s takes ship for %s." % [kind_name, target_name])
	else:
		_log("Our %s cannot reach %s this season." % [kind_name, target_name])
	_after_order()


func _army_order(target_region: String, forced_march: bool = false) -> void:
	var army: Dictionary = game.state["armies"][selected_army]
	var player: String = game.state["player_faction"]

	# Only an army we are ALREADY at war with is a target — marching past a
	# neutral must never start a war by accident. Deliberate first strikes go
	# through the explicit Attack button in the region panel.
	var defender := _enemy_army_in(target_region)
	if defender != "":
		attack_army_order(defender)
		return

	# A settlement of a faction we are at war with can be invested.
	var settlement: Dictionary = game.state["settlements"].get(target_region, {})
	if not settlement.is_empty() and settlement["owner"] != player \
			and DiplomacyRules.at_war(game.state, player, settlement["owner"]) \
			and MapRules.are_adjacent(game.data, army["region"], target_region):
		besiege_order(target_region)
		return

	# Otherwise: march (or sail).
	if game.move_army(selected_army, target_region, forced_march):
		var suffix := " by forced march — the men will be weary." if forced_march else "."
		_log("The army marches to %s%s" % [game.data.regions[target_region]["name"], suffix])
	elif game.sea_move_army(selected_army, target_region):
		_log("The army takes ship for %s." % game.data.regions[target_region]["name"])
	else:
		_log("The army cannot reach %s this season." % game.data.regions[target_region]["name"])
	_after_order()


func _enemy_army_in(region_id: String) -> String:
	## An at-war army we can actually see. Invisible armies must not influence
	## orders at all, or the log itself leaks their presence.
	var player: String = game.state["player_faction"]
	if not game.visible_regions().has(region_id):
		return ""
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var other: Dictionary = game.state["armies"][army_id]
		if other["region"] == region_id and DiplomacyRules.at_war(game.state, player, other["owner"]):
			return army_id
	return ""


func attack_army_order(defender_id: String) -> void:
	## Attacking a faction we are not yet at war with is a decision, not a
	## mis-click, so it is confirmed first.
	var defender: Dictionary = game.state["armies"].get(defender_id, {})
	if defender.is_empty():
		return
	var player: String = game.state["player_faction"]
	if not DiplomacyRules.at_war(game.state, player, defender["owner"]):
		var faction_name: String = game.data.factions.get(defender["owner"], {}).get("name", defender["owner"])
		_confirm("This will declare war on %s. Attack?" % faction_name,
			func(): _resolve_attack(defender_id))
		return
	_resolve_attack(defender_id)


func _resolve_attack(defender_id: String) -> void:
	var result := game.attack_army(selected_army, defender_id)
	if result.is_empty():
		_log("The army cannot come to grips with the enemy from here.")
	else:
		_log("[b]Battle![/b] The %s prevail." % ("attackers" if result["winner"] == "attacker" else "defenders"))
	_after_order()


func besiege_order(target_region: String) -> void:
	var settlement: Dictionary = game.state["settlements"].get(target_region, {})
	if settlement.is_empty():
		return
	var player: String = game.state["player_faction"]
	if not DiplomacyRules.at_war(game.state, player, settlement["owner"]):
		var faction_name: String = game.data.factions.get(settlement["owner"], {}).get("name", settlement["owner"])
		_confirm("This will declare war on %s. Lay siege?" % faction_name,
			func(): _resolve_siege(target_region))
		return
	_resolve_siege(target_region)


func _resolve_siege(target_region: String) -> void:
	if game.besiege(selected_army, target_region):
		_log("Siege laid to %s." % game.data.regions[target_region]["settlement_name"])
	else:
		_log("No siege can be laid there.")
	_after_order()


func _confirm(text: String, on_accept: Callable, host: Node = null) -> void:
	## `host` is the window the question belongs to: a dialog raised while the
	## diplomacy scroll (itself exclusive) is open must be its child, or Godot
	## refuses a second exclusive child of the root.
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = text
	dialog.confirmed.connect(on_accept)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	(host if host != null else self).add_child(dialog)
	dialog.popup_centered()


func declare_war_order(faction_id: String) -> void:
	## A declaration from the scroll is confirmed like any other first strike.
	## Breaking a treaty to do it is the costlier act, and the dialog says so.
	var faction_name: String = game.data.factions.get(faction_id, {}).get("name", faction_id)
	var player: String = game.state["player_faction"]
	var text := "Declare war on %s? They will remember it." % faction_name
	if DiplomacyRules.stance_between(game.state, player, faction_id) in ["trade", "alliance", "protectorate"]:
		text = "Tear up our treaty and declare war on %s? Every court will call us treacherous for it." % faction_name
	_confirm(text, func():
		if game.declare_war(faction_id):
			_log("[color=#e06050]We are at war with %s.[/color]" % faction_name)
		refresh()
		if diplomacy_panel.visible:
			diplomacy_panel.open_for(game),
		diplomacy_panel if diplomacy_panel.visible else null)


func end_treaty_order(faction_id: String) -> void:
	## Ending our own treaty needs no envoy and no consent, only a moment's
	## thought: the other court resents it.
	var faction_name: String = game.data.factions.get(faction_id, {}).get("name", faction_id)
	_confirm("End our treaty with %s? They will resent it." % faction_name, func():
		var result := game.propose({"to": faction_id, "stance": "neutral"})
		if result.get("accepted", false):
			_log("Our treaty with %s is at an end." % faction_name)
		else:
			_log("%s: %s" % [faction_name, result.get("reason", "the treaty stands")])
		refresh()
		if diplomacy_panel.visible:
			diplomacy_panel.open_for(game),
		diplomacy_panel if diplomacy_panel.visible else null)


func focus_region(region_id: String) -> void:
	## Jump the map and the panel to a region (the agents list uses it).
	if not game.data.regions.has(region_id):
		return
	selected_army = ""
	selected_agent = ""
	map_view.selected_region = region_id
	map_view.center_on(region_id)
	region_panel.show_region(game, region_id)
	refresh()


func _after_order() -> void:
	if game.state["armies"].has(selected_army):
		map_view.selected_region = game.state["armies"][selected_army]["region"]
	else:
		selected_army = ""
	if game.state["agents"].has(selected_agent):
		map_view.selected_region = game.state["agents"][selected_agent]["region"]
	else:
		selected_agent = ""
	region_panel.show_region(game, map_view.selected_region, selected_army, selected_agent)
	refresh()


func _end_turn() -> void:
	var report := game.end_turn()
	_log_report(report)
	selected_army = ""
	selected_agent = ""
	refresh()
	# The victory banner and the offers scroll cannot both be the root's
	# exclusive child; on the deciding turn the banner has the floor.
	if game.state["winner"] == null and not game.pending_offers().is_empty():
		offers_panel.open_for(game)


func _log_report(report: Dictionary) -> void:
	var year := int(game.state["year"])
	var year_text := "%d BC" % -year if year < 0 else "AD %d" % year
	_log("[b]— %s, %s —[/b]" % [year_text, String(game.state["season"]).capitalize()])

	var player: String = game.state["player_faction"]
	for region_id in report["completed_buildings"]:
		if game.state["settlements"].has(region_id) and game.state["settlements"][region_id]["owner"] == player:
			for level_id in report["completed_buildings"][region_id]:
				_log("Completed in %s: %s" % [game.data.regions[region_id]["settlement_name"],
					game.data.building_levels.get(level_id, {}).get("level", {}).get("name", level_id)])
	for region_id in report["completed_units"]:
		if game.state["settlements"].has(region_id) and game.state["settlements"][region_id]["owner"] == player:
			for template_id in report["completed_units"][region_id]:
				_log("Mustered in %s: %s" % [game.data.regions[region_id]["settlement_name"],
					game.data.units.get(template_id, {}).get("name", template_id)])
	for region_id in report["rioted"]:
		if game.state["settlements"][region_id]["owner"] == player:
			_log("[color=#e0a060]Riots in %s![/color]" % game.data.regions[region_id]["settlement_name"])
	for region_id in report["revolted"]:
		_log("[color=#e06050]%s has risen in revolt![/color]" % game.data.regions[region_id]["settlement_name"])
	for event in report["events"]:
		if event["kind"] == "event":
			var event_def := {}
			for candidate in game.data.events:
				if candidate["id"] == event["id"]:
					event_def = candidate
			_log("[color=#c0b060][b]%s[/b][/color] %s" % [event_def.get("name", event["id"]), event_def.get("text", "")])
		else:
			var struck: String = event.get("region", "")
			_log("[color=#e06050]Disaster strikes %s![/color]"
				% game.data.regions.get(struck, {}).get("settlement_name", struck))
	for notice in report["senate"]:
		if notice["faction"] == player:
			var mission_id: String = str(notice.get("mission", ""))
			var mission_name: String = game.data.missions.get(mission_id, {}).get("name", mission_id)
			var target: String = str(notice.get("target", ""))
			var target_name: String = game.data.regions.get(target, {}).get("name",
				game.data.factions.get(target, {}).get("name", ""))
			if target_name != "":
				mission_name += " (%s)" % target_name
			_log("[color=#9090d0]Senate: %s%s[/color]" % [String(notice["kind"]).replace("_", " "),
				"" if mission_name == "" else " — " + mission_name])
	_log_ai_report(report.get("ai", []))
	for notice in report.get("agents", []):
		var where: String = game.data.regions.get(notice.get("region", ""), {}).get("settlement_name", "")
		var kind_name: String = String(game.data.agent_kinds.get(notice.get("agent_kind", ""), {}).get("name", "agent")).to_lower()
		if notice.get("owner", "") == player:
			_log("[color=#e06050]Our %s %s was caught in %s and killed.[/color]" % [kind_name, notice.get("name", ""), where])
		elif notice.get("by", "") == player:
			var owner_name: String = game.data.factions.get(notice.get("owner", ""), {}).get("name", "")
			_log("[color=#80b080]Our watch in %s caught a %s %s.[/color]" % [where, owner_name, kind_name])
	for notice in report.get("diplomacy", []):
		if notice.get("from", "") != player and notice.get("to", "") != player:
			continue
		var other: String = notice["to"] if notice.get("from", "") == player else notice["from"]
		var other_name: String = game.data.factions.get(other, {}).get("name", other)
		match notice["kind"]:
			"tribute_paid":
				if notice["from"] == player:
					_log("Tribute of %d paid to %s." % [int(notice["amount"]), other_name])
				else:
					_log("Tribute of %d received from %s." % [int(notice["amount"]), other_name])
			"tribute_ended":
				_log("The tribute agreed with %s has %s." % [other_name, "lapsed" if notice.get("lapsed", false) else "run its course"])
			"protectorate_tribute":
				if notice["from"] == player:
					_log("Our overlord %s takes %d of the season's income." % [other_name, int(notice["amount"])])
				else:
					_log("Our protectorate %s sends %d in dues." % [other_name, int(notice["amount"])])
	for notice in report["characters"]:
		if notice.get("faction", "") != player and not _is_player_character(notice.get("character", "")):
			continue
		var who: String = game.state["characters"].get(notice.get("character", ""), {}).get("name", "")
		var detail := ""
		if notice.has("name"):
			detail = " — " + String(notice["name"])
		elif notice.has("ancillary"):
			detail = " — " + String(game.data.ancillaries.get(notice["ancillary"], {}).get("name", notice["ancillary"]))
		_log("[color=#80b080]%s: %s%s[/color]" % [String(notice["kind"]).replace("_", " "), who, detail])
	for siege_event in report["sieges"]:
		var town: String = game.data.regions[siege_event["region"]]["settlement_name"]
		var result: Dictionary = siege_event.get("result", {})
		var defender: String = siege_event.get("defender_was", "")
		var besieger: String = siege_event.get("besieger_owner", "")
		var besieger_name: String = game.data.factions.get(besieger, {}).get("name", besieger)
		var fate: String = {"occupy": "occupied", "enslave": "enslaved", "exterminate": "put to the sword"}.get(
			siege_event.get("occupation", "occupy"), "occupied")
		if result.get("captured", false):
			if defender == player:
				_log("[color=#e06050]Our city of %s, starved out, falls to %s and is %s.[/color]" % [town, besieger_name, fate])
			elif besieger == player:
				_log("[color=#80b080]The starving garrison of %s sallied and broke; the city is ours.[/color]" % town)
			elif visible_set_has(siege_event["region"]):
				_log("%s, starved out, falls to %s." % [town, besieger_name])
		elif defender == player:
			_log("[color=#80b080]The starving garrison of %s sallied out and broke the siege.[/color]" % town)
		elif besieger == player:
			_log("[color=#e06050]The starving garrison of %s sallied out and broke our siege.[/color]" % town)
		elif visible_set_has(siege_event["region"]):
			_log("The garrison of %s breaks its siege." % town)


const TREATY_TERMS := {
	"neutral": "make peace", "trade": "exchange trade rights", "alliance": "swear an alliance",
}


func visible_set_has(region_id: String) -> bool:
	return game.visible_regions().has(region_id)


func _log_ai_report(notices: Array) -> void:
	## What the other courts did this season, as far as it touches us or
	## lands we can see.
	var player: String = game.state["player_faction"]
	var visible_set := game.visible_regions()
	for notice in notices:
		var from_name: String = game.data.factions.get(notice.get("from", notice.get("attacker", "")), {}).get("name", "")
		match notice["kind"]:
			"war_declared":
				var target: String = notice["to"]
				if target == player:
					_log("[color=#e06050][b]%s declares war on us!%s[/b][/color]" % [from_name,
						" They have torn up our treaty." if notice.get("broke_treaty", false) else ""])
				elif _knows(notice["from"], visible_set) or _knows(target, visible_set):
					_log("%s declares war on %s." % [from_name, game.data.factions.get(target, {}).get("name", target)])
			"treaty":
				var other: String = notice["to"]
				if _knows(notice["from"], visible_set) and _knows(other, visible_set):
					var other_name: String = game.data.factions.get(other, {}).get("name", other)
					if notice.get("stance", "") == "protectorate":
						_log("%s submits to %s as a protectorate." % [other_name, from_name])
					else:
						_log("%s and %s %s." % [from_name, other_name,
							TREATY_TERMS.get(notice.get("stance", ""), "come to terms")])
			"offer":
				_log("[color=#c0b060]An envoy of %s brings an offer.[/color]" % from_name)
			"siege_laid":
				var ours: bool = notice.get("owner", "") == player
				if visible_set.has(notice["region"]) or ours:
					var town: String = game.data.regions[notice["region"]]["settlement_name"]
					_log("[color=#e0a060]%s lays siege to %s.[/color]" % [from_name, "our city of " + town if ours else town])
			"assault":
				var ours: bool = notice.get("owner", "") == player
				if visible_set.has(notice["region"]) or ours:
					var town: String = game.data.regions[notice["region"]]["settlement_name"]
					var city_text := "our city of " + town if ours else town
					if notice.get("captured", false):
						var fate: String = {"occupy": "occupies it", "enslave": "sells its people into slavery",
							"exterminate": "puts it to the sword"}.get(notice.get("occupation", "occupy"), "occupies it")
						_log("[color=#e06050]%s storms %s and %s.[/color]" % [from_name, city_text, fate])
					else:
						_log("%s assaults %s and is thrown back." % [from_name, city_text])
			"battle":
				var ours: bool = notice.get("defender", "") == player
				if ours or notice.get("attacker", "") == player or visible_set.has(notice["region"]):
					var defender_name: String = game.data.factions.get(notice["defender"], {}).get("name", "")
					var line := "[b]Battle[/b] near %s: %s attack %s; the %s prevail." % [
						game.data.regions[notice["region"]]["name"], from_name,
						"our army" if ours else defender_name,
						"attackers" if notice["winner"] == "attacker" else "defenders"]
					if ours and notice.get("defender_destroyed", false):
						line += " Our army is destroyed."
					if ours and notice.get("defender_general_died", false):
						line += " Our general fell."
					_log(("[color=#e06050]%s[/color]" % line) if ours else line)
			"assassination":
				if notice.get("faction", "") == player:
					if notice.get("success", false):
						_log("[color=#e06050]%s has been murdered. The whispers name %s.[/color]" % [notice["target_name"], from_name])
					else:
						_log("[color=#e0a060]An attempt on %s failed%s.[/color]" % [notice["target_name"],
							"; the assassin was caught and named " + from_name if notice.get("caught", false) else ""])
			"gates":
				if visible_set.has(notice["region"]):
					_log("Spies of %s %s the gates of %s." % [from_name,
						"open" if notice.get("success", false) else "fail to open",
						game.data.regions[notice["region"]]["settlement_name"]])


func _knows(faction_id: String, visible_set: Dictionary) -> bool:
	## A power we can see the lands of, or are treating with.
	if faction_id == game.state["player_faction"]:
		return true
	if DiplomacyRules.stance_between(game.state, game.state["player_faction"], faction_id) != "neutral":
		return true
	for region_id in visible_set:
		if game.state["settlements"].get(region_id, {}).get("owner", "") == faction_id:
			return true
	return false


func _is_player_character(char_id: String) -> bool:
	return game.state["characters"].get(char_id, {}).get("faction", "") == game.state["player_faction"]


func _show_victory_banner(winner: String) -> void:
	_victory_shown = true
	var dialog := AcceptDialog.new()
	dialog.title = "The campaign is decided"
	if winner == "time_up":
		dialog.dialog_text = "AD 14 has come. The age closes with no master of the world."
	elif winner == game.state["player_faction"]:
		dialog.dialog_text = "Your house rules the world. The campaign is won!"
	else:
		dialog.dialog_text = "%s has won the age." % game.data.factions.get(winner, {}).get("name", winner)
	add_child(dialog)
	dialog.popup_centered()


func _save_game() -> void:
	_log("Game saved." if game.save_to(SAVE_PATH) else "Save failed.")


func _load_game() -> void:
	if game.load_from(SAVE_PATH):
		selected_army = ""
		selected_agent = ""
		map_view.selected_region = ""
		region_panel.clear_panel()
		_victory_shown = false
		_log("Game loaded.")
		refresh()
	else:
		_log("No saved game to load.")


func _log(text: String) -> void:
	report_log.append_text(text + "\n")


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _bar_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button
