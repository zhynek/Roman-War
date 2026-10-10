class_name PortDialog
extends Window
signal changed
var game: Game
var region := ""
var view: PortView
var details: VBoxContainer
var status: Label
var heading: Label
var caption: Label
var navigation: CheckBox
var stages: OptionButton
var preview_rank := 0

func words(key: String, values: Dictionary = {}) -> String:
	var display := values.duplicate()
	for field in display:
		if display[field] is float and is_equal_approx(display[field], roundf(display[field])):
			display[field] = int(display[field])
	return String(game.data.effects_glossary["ports"].get(key,key)).format(display)

func stage_name(rank: int) -> String:
	if rank == 0:
		return words("shore")
	var definition := PortRules.stage_spec(game.data, rank)
	return definition["name"] if MapRules.coastal(game.data,region) else definition["inland_name"]

func open_for(current: Game, target: String) -> void:
	game = current
	region = target
	theme = UiStyle.build_theme()
	var background := ColorRect.new()
	background.color = UiStyle.BG_DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	title = "%s — %s" % [words("title"),game.data.regions[region]["settlement_name"]]
	size = Vector2i(1220,750)
	min_size = Vector2i(1040,660)
	transient = true
	exclusive = true
	close_requested.connect(queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,16)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",18)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	heading = label(left,"")
	heading.add_theme_font_size_override("font_size",23)
	var toolbar := HBoxContainer.new()
	left.add_child(toolbar)
	stages = OptionButton.new()
	stages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stages.add_item(words("live"))
	for rank in range(1,6):
		stages.add_item("%d · %s" % [rank,stage_name(rank)])
	toolbar.add_child(stages)
	stages.item_selected.connect(func(index):
		preview_rank = index
		_render())
	navigation = CheckBox.new()
	navigation.text = words("navigation")
	navigation.add_theme_font_size_override("font_size",12)
	left.add_child(navigation)
	navigation.toggled.connect(func(_on): _render())
	view = PortView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(view)
	caption = label(left,"")
	label(left,words("camera"))
	label(left,words("geometry_note"))
	button(left,words("close"),queue_free)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",9)
	scroll.add_child(details)
	_refresh()
	popup_centered()

func label(parent: Node, text: String) -> Label:
	var control := Label.new()
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.add_theme_font_size_override("font_size",13)
	parent.add_child(control)
	return control

func button(parent: Node, text: String, callback: Callable, quote: Dictionary = {}) -> Button:
	var control := Button.new()
	control.text = text.replace(" · ", "\n")
	control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	control.tooltip_text = text
	control.custom_minimum_size.y = 36
	control.add_theme_font_size_override("font_size",13)
	control.pressed.connect(callback)
	if not quote.is_empty():
		control.disabled = not quote.get("ok",false)
		if control.disabled:
			control.tooltip_text = words(quote.get("error","ship_required"),quote)
	parent.add_child(control)
	return control

func _section(text: String) -> void:
	var line := HSeparator.new()
	details.add_child(line)
	label(details,text).add_theme_color_override("font_color",UiStyle.CAPITAL_GOLD)

func _act(result: Dictionary) -> void:
	if not result.get("ok",false):
		status.text = words(result.get("error","ship_required"),result)
		return
	changed.emit()
	call_deferred("_refresh")

func _refresh() -> void:
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	var rank := PortRules.stage(game.data,game.state,region)
	var caps := PortRules.capabilities(game.data,game.state,region)
	var site := PortRules.site(game.data,region)
	label(details,words("site",{"setting":words(site["setting"]),"depth":words("deep" if site["deep_water"] else "shallow")}))
	label(details,words("capabilities",{"troops":caps["troop_handling"],"cargo":caps["cargo_handling"],"repair":caps["repair_pct"],"support":caps["support"],"defense":caps["defense_pct"],"upkeep":caps["upkeep"]}))
	label(details,words("handling",{"remaining":PortRules.handling_left(game.data,game.state,region),"total":caps["troop_handling"]}))
	status = label(details,"")
	var job: Dictionary = PortRules.record(game.state,region).get("project",{})
	if not job.is_empty():
		var name := stage_name(int(job["rank"])) if job["kind"]=="stage" else _facility_name(job["kind"])
		label(details,words("project",{"name":name,"turns":job["turns"]}))
	_section(words("next_stage"))
	if rank < 5:
		var quote := PortRules.project_quote(game.data,game.state,region)
		var definition := PortRules.stage_spec(game.data,rank+1)
		label(details,definition["description"])
		label(details,words("requirements",quote))
		var next_caps: Dictionary = PortRules.rules(game.data)["stages"][rank]
		label(details,words("capabilities",{"troops":next_caps["troop_handling"],"cargo":next_caps["cargo_handling"],"repair":next_caps["repair_pct"],"support":next_caps["support"],"defense":next_caps["defense_pct"],"upkeep":next_caps["upkeep"]}))
		var values := quote.duplicate()
		values["name"] = stage_name(rank+1)
		button(details,words("upgrade",values),func(): _act(game.develop_port(region)),quote)
		if not quote["ok"]:
			label(details,words(quote["error"],quote))
	else:
		label(details,words("complete"))
	_section(words("facilities"))
	var built := PortRules.facilities(game.data,game.state,region)
	for facility in game.data.ports["facilities"]:
		var id: String = facility["id"]
		var values: Dictionary = PortRules.rules(game.data)["facilities"][id].duplicate()
		values["name"] = facility["name"]
		label(details,facility["description"])
		if built.has(id):
			label(details,"%s · %s" % [facility["name"],words("built")])
		else:
			button(details,words("facility",values),func(): _act(game.develop_port(region,id)),PortRules.project_quote(game.data,game.state,region,id))
	button(details,words("repair"),func():
		var outcome := game.service_port(region)
		status.text = words("repaired",outcome)
		changed.emit())
	label(details,words("repair_note"))
	var town: Dictionary = game.state["settlements"][region]
	var position := 0
	var eta := 0
	for queued in town["recruitment_queue"]:
		position += 1
		eta += int(queued.get("turns_left",1))
		if game.data.units.get(queued["template"],{}).get("class") == "ship":
			label(details,words("ship_queue",{"name":game.data.units[queued["template"]]["name"],"turns":eta,"position":position}))
	_section(words("shipyard"))
	var ships: Array = game.data.ports["vessels"].keys()
	ships.sort_custom(func(a,b):
		var x := int(game.data.ports["vessels"][a]["stage"])
		var y := int(game.data.ports["vessels"][b]["stage"])
		return x<y if x!=y else a<b)
	for template in ships:
		var unit: Dictionary = game.data.units[template]
		if not unit["factions"].has("all") and not unit["factions"].has(town["owner"]):
			continue
		var id: String = template
		var spec: Dictionary = game.data.ports["vessels"][id]
		var profile := PortRules.vessel(game.data,id)
		label(details,unit["name"]).add_theme_color_override("font_color",UiStyle.CAPITAL_GOLD)
		label(details,unit["description"])
		label(details,words("ship_stats",{"troops":profile["troops"],"cargo":profile["cargo"],"crew":unit["soldiers"],"attack":unit["attack"],"defense":unit["defense"],"speed":unit.get("speed",5),"movement":profile["movement"],"upkeep":unit["upkeep"]}))
		var required := PackedStringArray()
		for facility in spec["facilities"]:
			required.append(_facility_name(facility))
		var waters := PackedStringArray()
		for water in spec["waters"]:
			waters.append(words(water))
		label(details,words("ship_needs",{"stage":spec["stage"],"facilities":", ".join(required) if not required.is_empty() else words("none"),"waters":" / ".join(waters),"repair":spec["repair_stage"]}))
		var quote := PortRules.ship_quote(game.data,game.state,region,id)
		var values := quote.duplicate()
		values["name"] = unit["name"]
		button(details,words("ship_button",values),func(): _act(game.commission_ship(region,id)),quote)
		if not quote["ok"]:
			label(details,words(quote["error"],quote))
	_render()

func _facility_name(id: String) -> String:
	for facility in game.data.ports["facilities"]:
		if facility["id"] == id:
			return facility["name"]
	return id

func _render() -> void:
	var architecture := PortRules.snapshot(game.data,game.state,region)
	if preview_rank > 0:
		architecture["stage"] = preview_rank
		architecture["facilities"] = []
		for facility in game.data.ports["facilities"]:
			if int(facility["stage"]) <= preview_rank:
				architecture["facilities"].append(facility["id"])
	var rank := int(architecture["stage"])
	heading.text = words("stage",{"stage":rank,"name":stage_name(rank)})
	caption.text = words("gallery_note") if preview_rank > 0 else words("live")
	var plan := PortLayout.build(game.data,region,architecture)
	plan["illustrative"] = preview_rank > 0
	view.display(plan,navigation.button_pressed)
