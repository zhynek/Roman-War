extends PanelContainer
const Rules = preload("res://src/core/settlement_rules.gd")
const Saves = preload("res://src/campaign_save.gd")
var app
var land_panel
var incident_panel
var living_panel
const LandPanel=preload("res://src/land_panel.gd")
var asset_panel
const AssetPanel=preload("res://src/assets_panel.gd")
var household_panel
const HouseholdPanel=preload("res://src/households_panel.gd")
var contacts_panel
const ContactsPanel=preload("res://src/neighbors_panel.gd")
var rules
var copy: Dictionary
var state: Dictionary = {}
var tabs: TabContainer
var column: VBoxContainer
var notice: Label
var workforce: Dictionary = {}
var save_path: String = "user://early_settlement_campaign.json"
var last_message: String = ""
var _refreshing: bool = false
var _command_busy: bool=false
var _season_input_locked: bool=false

func configure(owner_app) -> void:
	app = owner_app
	copy = JSON.parse_string(FileAccess.get_file_as_string("res://data/governance_ui.json"))
	contacts_panel=ContactsPanel.new(self,JSON.parse_string(FileAccess.get_file_as_string("res://data/neighbors_ui.json")))
	var household_content:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/households.json"))
	household_panel=HouseholdPanel.new(self,household_content)
	var asset_content: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/assets.json"))
	asset_panel=AssetPanel.new(self,asset_content)
	var land_content: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/land.json"))
	land_panel=LandPanel.new(self,land_content)
	var living_content: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/living.json"))
	living_panel=preload("res://src/living_panel.gd").new(self,living_content)
	var incident_content: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/incidents.json"))
	incident_panel=preload("res://src/incident_panel.gd").new(self,incident_content)
	copy.factor_names.merge(incident_content.factors)
	living_content.errors.merge(incident_content.errors)
	copy.factor_names.merge(living_content.factors)
	rules = Rules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/governance.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/neighbors.json")),household_content,asset_content,land_content,living_content,incident_content)
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -638; offset_right = -22; offset_top = 164; offset_bottom = -22
	var panel_style:StyleBoxFlat=app._style();panel_style.bg_color.a=1.0
	add_theme_stylebox_override("panel",panel_style)
	refresh()
	hide()

func label(text: String, size: int = 16) -> Label:
	var result: Label = app._label(text,size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func button(text: String, callback: Callable, id: String = "") -> Button:
	var result: Button = app._button(text,callback)
	result.focus_mode=Control.FOCUS_ALL
	if not id.is_empty(): result.name=id
	return result

func open() -> void:
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if not state.is_empty(): app.show_campaign(state,rules)
	show()
	refresh()

func begin() -> void:
	state=rules.new_state()
	last_message=copy.new_campaign
	app.show_campaign(state,rules)
	refresh()

func dispatch(action: Dictionary) -> bool:
	if state.is_empty() or _command_busy: return false
	var result: Dictionary=rules.command(state,action)
	if result.has("error"):
		last_message=living_panel.copy.errors[result.error] if living_panel.copy.errors.has(result.error) else asset_panel.reason(result.error) if result.error.begins_with("asset_") or result.error.begins_with("land_") else copy.get(result.error,contacts_panel.copy.get(result.error,household_panel.copy.errors.get(result.error,result.error)));refresh();return false
	state=result.state
	if action.kind.begins_with("incident_") or action.kind.begins_with("living_") or action.kind.begins_with("land_"):
		last_message=""
	elif action.kind.begins_with("asset_"):
		last_message=asset_panel.copy.ui.checked if action.kind=="asset_review" else ""
	elif action.kind.begins_with("household_"):
		last_message=household_panel.copy.ui.updated
	elif action.kind.begins_with("neighbor_"):
		last_message=contacts_panel.copy.get({"neighbor_begin":"start_success","neighbor_send":"sent","neighbor_escort":"escort_set","neighbor_cancel":"cancelled"}.get(action.kind,""),"")
	else:
		last_message=copy.get({"plan":"assigned","commission":"ordered","cancel":"cancelled","appoint":"appointed","policy":"policies_set"}.get(action.kind,"roles_note"),"")
	app.show_campaign(state,rules)
	refresh()
	return true

func resolve_from_ui() -> void:
	if _season_input_locked:return
	_season_input_locked=true
	resolve_season()
	set_deferred("_season_input_locked",false)

func resolve_season() -> bool:
	if state.is_empty() or _command_busy: return false
	_command_busy=true
	if is_instance_valid(notice):notice.text=living_panel.copy.ui.busy
	var control: Button=find_child("ResolveSeason",true,false)
	if control!=null:control.disabled=true
	if DisplayServer.get_name()!="headless":RenderingServer.force_draw(true)
	var result: Dictionary=rules.advance(state)
	_command_busy=false
	if result.has("error"): last_message=living_panel.copy.errors[result.error] if living_panel.copy.errors.has(result.error) else asset_panel.reason(result.error) if result.error.begins_with("asset_") or result.error.begins_with("land_") else copy.get(result.error,contacts_panel.copy.get(result.error,household_panel.copy.errors.get(result.error,result.error)));refresh();return false
	state=result.state
	last_message=copy.resolved
	app.show_campaign(state,rules)
	refresh()
	return true

func save_campaign() -> bool:
	var ok: bool=not state.is_empty() and Saves.write(save_path,state,rules)
	last_message=copy.saved if ok else copy.save_failed
	refresh()
	return ok

func load_campaign() -> bool:
	var loaded: Dictionary=Saves.read(save_path,rules)
	if loaded.is_empty(): last_message=copy.load_failed;refresh();return false
	state=loaded
	last_message=copy.loaded
	app.show_campaign(state,rules,true)
	refresh()
	return true

func _tab(title: String) -> VBoxContainer:
	var scroll:=ScrollContainer.new();scroll.name=title;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",10);scroll.add_child(body)
	return body

func refresh() -> void:
	if _refreshing:return
	_refreshing=true
	var selected:int=tabs.current_tab if is_instance_valid(tabs) else 0
	var scrolls:Array=[]
	if is_instance_valid(tabs):
		for child in tabs.get_children():scrolls.append(child.scroll_vertical)
	for child in get_children():remove_child(child);child.queue_free()
	column=VBoxContainer.new();column.add_theme_constant_override("separation",8);add_child(column)
	column.add_child(label(incident_panel.copy.title if not state.is_empty() and rules.incidents.active(state) else living_panel.copy.title if not state.is_empty() and rules.living.active(state) else land_panel.copy.title if not state.is_empty() and rules.land.active(state) else asset_panel.copy.title if not state.is_empty() and rules.assets.active(state) else copy.panel_title,21))
	column.add_child(label(copy.hypothesis,13))
	var top:=HFlowContainer.new();column.add_child(top)
	top.add_child(button(copy.close,hide,"ExploreCampaign"))
	top.add_child(button(copy.reference,func(): app.show_reference();hide(),"ReferenceVillage"))
	top.add_child(button(copy.save,save_campaign,"SaveCampaign"))
	top.add_child(button(copy.load,load_campaign,"LoadCampaign"))
	if state.is_empty():
		var intro_scroll:=ScrollContainer.new();intro_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;intro_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(intro_scroll)
		var introduction:=VBoxContainer.new();introduction.size_flags_horizontal=Control.SIZE_EXPAND_FILL;introduction.add_theme_constant_override("separation",14);intro_scroll.add_child(introduction)
		introduction.add_child(label(copy.intro,18))
		introduction.add_child(button(incident_panel.copy.ui.begin,incident_panel.begin,"BeginIncidents"))
		introduction.add_child(label(incident_panel.copy.ui.intro,15))
		introduction.add_child(button(living_panel.copy.ui.begin,living_panel.begin,"BeginLiving"))
		introduction.add_child(label(living_panel.copy.ui.intro,15))
		introduction.add_child(button(land_panel.copy.ui.begin,land_panel.begin,"BeginLandPlanning"))
		introduction.add_child(label(land_panel.copy.ui.intro,15))
		introduction.add_child(button(asset_panel.copy.ui.begin,asset_panel.begin,"BeginAssetGovernance"))
		introduction.add_child(label(asset_panel.copy.ui.migration,14))
		introduction.add_child(button(copy.begin,begin,"BeginTutorial"))
		introduction.add_child(label(copy.principle_text,15))
		tabs=null
	else:
		top.add_child(button(incident_panel.copy.ui.tab,func():tabs.current_tab=9,"IncidentsTab"))
		if rules.incidents.active(state):column.add_child(label(incident_panel.notice(),14))
		top.add_child(button(living_panel.copy.ui.tab,func():tabs.current_tab=8,"VillageTab"))
		var role_row:=HBoxContainer.new();column.add_child(role_row)
		var role_picker:=OptionButton.new();role_picker.name="RolePicker";role_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for role in ["god","steward","watch"]:
			role_picker.add_item(copy[role]+(" · "+rules.person_by_id(state,state.leaders[role].id).get("name","—") if role!="god" else ""))
		role_picker.select(["god","steward","watch"].find(state.role))
		role_picker.item_selected.connect(func(index):dispatch({"kind":"role","role":["god","steward","watch"][index]}))
		role_row.add_child(role_picker)
		var season: String=copy.year%[1+int(state.turn)/4,copy.seasons[int(state.turn)%4]]
		column.add_child(label(season+" · "+copy["phase_"+state.phase],20))
		tabs=TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;tabs.clip_tabs=true;column.add_child(tabs)
		var bodies: Array=[]
		for title in [copy.overview,asset_panel.copy.ui.overview if rules.assets.active(state) else copy.work,copy.leaders,copy.journal,asset_panel.copy.ui.principles if rules.assets.active(state) else copy.principles,contacts_panel.copy.tab,household_panel.copy.ui.tab,land_panel.copy.ui.tab,living_panel.copy.ui.tab,incident_panel.copy.ui.tab]:bodies.append(_tab(title))
		# Only the visible tab builds controls and quotations. Changing tabs uses
		# the same builder; hidden pages no longer multiply ordinary order cost.
		match selected:
			0:
				if rules.incidents.active(state):incident_panel.guide(bodies[0])
				elif rules.living.active(state):living_panel.guide(bodies[0])
				elif rules.land.active(state):land_panel.guide(bodies[0])
				elif rules.assets.active(state):asset_panel.guide(bodies[0])
				else:_guide(bodies[0])
			1:
				if rules.assets.active(state):asset_panel.build(bodies[1])
				else:_work(bodies[1])
			2:_leaders(bodies[2])
			3:_journal(bodies[3])
			4:
				if rules.assets.active(state):asset_panel.principles(bodies[4])
				else:
					bodies[4].add_child(label(copy.principle_text,15));bodies[4].add_child(label(copy.units_note,14));asset_panel.build(bodies[4])
				bodies[4].add_child(button(copy.restart,_confirm_restart,"RestartTutorial"))
			5:contacts_panel.build(bodies[5])
			6:household_panel.build(bodies[6])
			7:land_panel.build(bodies[7])
			8:living_panel.build(bodies[8])
			9:incident_panel.build(bodies[9])
		tabs.current_tab=clampi(selected,0,tabs.get_tab_count()-1)
		for i in range(mini(scrolls.size(),tabs.get_child_count())):tabs.get_child(i).set_deferred("scroll_vertical",scrolls[i])
		tabs.tab_changed.connect(func(_index):if not _refreshing:refresh.call_deferred())
		var advance:=button(copy.end_season,resolve_from_ui,"ResolveSeason");advance.custom_minimum_size.y=40;column.add_child(advance)
		column.add_child(label(copy.pause_notice,12))
	notice=label(last_message,13);notice.add_theme_color_override("font_color",Color("d6c794"));column.add_child(notice)
	_refreshing=false

func _guide(body: VBoxContainer) -> void:
	var count:int=rules.people(state).size()
	body.add_child(label("%s %d / %d   ·   %s %d / %d   ·   %s %d"%[copy.population,count,rules.capacity(state),copy.provisions,state.food,rules.storage(state),copy.wood,state.wood],18))
	if state.phase=="town":body.add_child(label(copy.complete,17))
	elif state.town_achieved:body.add_child(label(copy.recovery,17))
	elif state.turn==0:body.add_child(label(copy.intro,17))
	var recommended:String=recommended_project()
	if not recommended.is_empty():
		var p:Dictionary=rules.projects[recommended]
		body.add_child(label(copy.guide_project%[p.title,p.body],17))
		var queued:bool=false
		for item in state.queue:
			if item.id==recommended:queued=true
		if not queued:
			var commission:=button(copy.queue_recommended,func():dispatch({"kind":"commission","id":recommended}),"RecommendedProject")
			commission.disabled=not rules.permitted(state,p.role);body.add_child(commission)
	elif state.phase!="town":body.add_child(label(copy.guide_growth if count<rules.balance.town_population else copy.guide_sustain,17))
	if state.town_achieved:
		body.add_child(button(contacts_panel.copy.next,func():tabs.current_tab=5,"OpenNeighbors"))
	body.add_child(button(household_panel.copy.ui.next,func():tabs.current_tab=6,"OpenHouseholds"))
	body.add_child(button(copy.suggest,_suggest,"SuggestedWorkforce"))
	_forecast(body)
	var b:Dictionary=rules.balance
	body.add_child(label(copy.milestone%[b.town_population,b.town_dwellings,b.town_reserve_seasons,b.town_wellbeing,b.town_cooperation,b.town_security,state.stable_seasons,b.town_sustained_seasons],14))

func recommended_project() -> String:
	for id in rules.content.tutorial_projects:
		if not rules.has_project(state,id):return id
	if state.town_achieved and not rules.has_project(state,rules.neighbors.content.project_id):return rules.neighbors.content.project_id
	return ""

func _forecast(body: VBoxContainer) -> void:
	var f:Dictionary=rules.forecast(state)
	body.add_child(label(copy.preview,19))
	if rules.neighbors.active(state):
		var cargo:Dictionary=f.crew.duplicate();cargo.merge(f.cargo);body.add_child(label(contacts_panel.copy.home_labor.format(cargo),14))
	body.add_child(label(copy.forecast_line%[f.food_delta,f.gathered,f.used,f.spoil,f.losses,f.food,rules.storage(state),f.wood,f.work],15))
	body.add_child(label(copy.forecast_losses%[f.unfed,f.overflow],14))
	for key in ["wellbeing","cooperation","security"]:
		var factors:PackedStringArray=[]
		for factor in f.factors[key]:
			if factor.value!=0:factors.append(copy.factor_names[factor.id]+" %+d"%factor.value)
		body.add_child(label(copy.factor_line%[copy[key],state[key],f.stocks[key],", ".join(factors)],14))

func _work(body: VBoxContainer) -> void:
	body.add_child(label(copy.labor_note,14))
	var grid:=GridContainer.new();grid.columns=5;body.add_child(grid);workforce={}
	for job in ["food","timber","care","watch","building"]:grid.add_child(label(copy.watch_job if job=="watch" else copy[job],14))
	for job in ["food","timber","care","watch","building"]:
		var spin:=SpinBox.new();spin.name="Workers_"+job;spin.min_value=0;spin.max_value=rules.people(state,true).size();spin.step=1;spin.value=state.plan[job];spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		spin.editable=job!="food" and (state.role=="god" or (job=="watch" and state.role=="watch") or (job!="watch" and state.role=="steward"))
		grid.add_child(spin);workforce[job]=spin
		if job!="food":spin.value_changed.connect(_balance_food)
	body.add_child(button(copy.assign,_assign,"AssignWorkforce"))
	body.add_child(button(copy.suggest,_suggest,"SuggestedWorkforceWork"))
	var welcome:=CheckButton.new();welcome.text=copy.welcome;welcome.button_pressed=state.welcome;welcome.disabled=not rules.permitted(state,"steward");welcome.toggled.connect(func(value):dispatch({"kind":"policy","welcome":value,"tight_rations":state.tight_rations}));body.add_child(welcome)
	var ration:=CheckButton.new();ration.text=copy.rations;ration.button_pressed=state.tight_rations;ration.disabled=not rules.permitted(state,"steward");ration.toggled.connect(func(value):dispatch({"kind":"policy","welcome":state.welcome,"tight_rations":value}));body.add_child(ration)
	for item in state.queue:
		var p:Dictionary=rules.projects[item.id]
		body.add_child(label(copy.queue_line%[p.title,item.progress,p.work,p.wood],16))
		var cancel:=button(copy.cancel,func():dispatch({"kind":"cancel","id":item.id}),"Cancel_"+item.id);cancel.disabled=not rules.permitted(state,p.role);body.add_child(cancel)
	for p in rules.content.projects:
		if rules.has_project(state,p.id):continue
		var queued:bool=false
		for item in state.queue:
			if item.id==p.id:queued=true
		if queued:continue
		body.add_child(HSeparator.new())
		body.add_child(label(copy.project_cost%[p.title,p.wood,p.work],17))
		body.add_child(label(p.body,14))
		var order:=button(copy.queue,func():dispatch({"kind":"commission","id":p.id}),"Commission_"+p.id)
		order.disabled=not rules.permitted(state,p.role) or state.wood<p.wood or state.queue.size()>=rules.balance.queue_limit
		for requirement in p.requires:
			if not rules.has_project(state,requirement):order.disabled=true
		body.add_child(order)

func _balance_food(_value: float) -> void:
	var remaining:int=rules.people(state,true).size()
	for key in ["timber","care","watch","building"]:remaining-=int(workforce[key].value)
	workforce.food.value=maxi(0,remaining)

func _assign() -> void:
	var plan:Dictionary={}
	for key in workforce:plan[key]=int(workforce[key].value)
	dispatch({"kind":"plan","plan":plan})

func _suggest() -> void:
	var plan:Dictionary=rules.suggested_plan(state)
	if state.role=="watch":
		plan=state.plan.duplicate(true);plan.watch=mini(int(rules.balance.watch_target),int(plan.food)+int(plan.watch));plan.food=rules.people(state,true).size()-int(plan.timber)-int(plan.care)-int(plan.building)-int(plan.watch)
	elif state.role=="steward":
		plan.watch=state.plan.watch;plan.food=rules.people(state,true).size()-int(plan.timber)-int(plan.care)-int(plan.building)-int(plan.watch)
	dispatch({"kind":"plan","plan":plan})

func _leaders(body: VBoxContainer) -> void:
	body.add_child(label(copy.roles_note,14))
	if rules.assets.active(state):
		body.add_child(label(asset_panel.copy.ui.people,14))
		for asset in rules.assets.content.assets:
			asset_panel.ownership(body,asset.role)
			body.add_child(button(asset.title,func():asset_panel.inspect(asset.id),"Responsibility_"+asset.id))
	for role in ["steward","watch"]:
		var leader:Dictionary=rules.person_by_id(state,state.leaders[role].id)
		body.add_child(label(copy.lead_line%[copy[role],leader.get("name","—"),int(leader.get("age",0))/4,rules.leader_skill(state,role),maxi(0,int(rules.balance.term_seasons)-int(state.turn)+int(state.leaders[role].since))],17))
		var picker:=OptionButton.new();var candidates:Array=[]
		for person in rules.people(state,true):
			if rules.eligible(person) and person.id!=state.leaders["watch" if role=="steward" else "steward"].id:
				candidates.append(person.id);picker.add_item(person.name+" · %d/5"%person[role])
		body.add_child(picker)
		var appoint:=button(copy.appoint,func():
			if picker.selected>=0:dispatch({"kind":"appoint","role":role,"id":candidates[picker.selected]}))
		appoint.disabled=not rules.permitted(state,role) or candidates.is_empty();body.add_child(appoint)
	var jobs:Dictionary={}
	for task in state.assignments:jobs[task.id]=task.job
	for person in rules.people(state):
		var job:String=jobs.get(person.id,"child")
		var household_label:String=""
		for household in rules.content.households:
			if household.id==person.household:household_label=household.label
		body.add_child(label(copy.citizen_line%[person.name,int(person.age)/4,copy.watch_job if job=="watch" else copy.get(job,contacts_panel.copy.get(job,job)),household_label],14))

func _journal(body: VBoxContainer) -> void:
	if rules.assets.active(state):asset_panel.journal(body)
	for i in range(state.history.size()-1,maxi(-1,state.history.size()-101),-1):
		var event:Dictionary=state.history[i]
		var params:Dictionary=event.params.duplicate(true)
		if params.has("project"):params.project=rules.projects.get(params.project,{}).get("title",params.project)
		if params.has("role"):params.role=copy.get(params.role,params.role)
		if params.has("order") and rules.households.orders.has(params.order):params.order=rules.households.orders[params.order].label
		if params.has("enabled"):params.enabled=household_panel.copy.ui.enable if params.enabled else household_panel.copy.ui.disable
		if params.has("stage"):
			for spec in household_panel.copy.stages:
				if spec.id==params.stage:params.stage=spec.label;break
		if params.has("neighbor"):params.neighbor=rules.neighbors.communities.get(params.neighbor,{}).get("name",params.neighbor)
		for key in ["give","resource"]:
			if params.has(key):params[key]=contacts_panel.copy.get(params[key],params[key])
		body.add_child(label(str(copy.events.get(event.kind,contacts_panel.copy.events.get(event.kind,household_panel.copy.events.get(event.kind,event.kind)))).format(params),15))

func _confirm_restart() -> void:
	var confirm:=ConfirmationDialog.new();confirm.dialog_text=copy.restart_confirm;confirm.confirmed.connect(begin);confirm.confirmed.connect(confirm.queue_free);confirm.canceled.connect(confirm.queue_free);app.add_child(confirm);confirm.popup_centered(Vector2i(440,180))
