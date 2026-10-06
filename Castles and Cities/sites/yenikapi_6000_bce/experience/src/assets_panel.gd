extends RefCounted
## All surfaces dispatch the same public commands; visiting is optional presentation.
var panel
var copy: Dictionary
var selected: String="stores"
func _init(owner_panel,config: Dictionary) -> void:
	panel=owner_panel;copy=config

func open() -> void:
	panel.open()
	if not panel.state.is_empty() and panel.rules.assets.active(panel.state):panel.tabs.current_tab=1

func begin() -> void:
	panel.state=panel.rules.new_state()
	panel.dispatch({"kind":"asset_begin"})
	panel.show()
	panel.tabs.current_tab=0

func inspect(id: String) -> void:
	selected=id
	if panel.rules.assets.active(panel.state):panel.dispatch({"kind":"asset_inspect","id":id})
	panel.show();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	panel.tabs.current_tab=1

func reason(error: String) -> String:
	if panel.living_panel!=null and panel.living_panel.copy.errors.has(error):return panel.living_panel.copy.errors[error]
	if panel.land_panel.copy.errors.has(error):return panel.land_panel.copy.errors[error]
	return str(copy.ui.errors.get(error,panel.copy.get(error,panel.household_panel.copy.errors.get(error,error))))

func action(body: VBoxContainer,title: String,command: Dictionary,id: String) -> Button:
	var result: Dictionary=panel.rules.quote(panel.state,command)
	var control: Button=panel.button(title,func():panel.dispatch(command),id)
	control.disabled=result.has("error")
	body.add_child(control)
	if control.disabled:
		control.tooltip_text=reason(result.error)
		body.add_child(panel.label(control.tooltip_text,13))
	return control

func ownership(body: VBoxContainer,office: String) -> void:
	var state: Dictionary=panel.state
	var leader: Dictionary=panel.rules.person_by_id(state,state.leaders[office].id)
	body.add_child(panel.label(copy.ui.role.format({"office":panel.copy[office],"name":leader.get("name","—"),"since":int(state.leaders[office].since)+1,"skill":panel.rules.leader_skill(state,office)}),15))

func build(body: VBoxContainer) -> void:
	var rules=panel.rules
	var state: Dictionary=panel.state
	if not rules.assets.active(state):
		body.add_child(panel.label(copy.ui.migration,16))
		action(body,copy.ui.adopt,{"kind":"asset_begin"},"AdoptAssets")
		return
	var picker:=OptionButton.new();picker.name="AssetPicker";picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for i in range(copy.assets.size()):
		picker.add_item(copy.assets[i].title)
		if copy.assets[i].id==selected:picker.select(i)
	picker.item_selected.connect(func(index):inspect(copy.assets[index].id))
	body.add_child(picker)
	var asset: Dictionary=rules.assets.assets[selected]
	body.add_child(panel.label(asset.title,22))
	body.add_child(panel.label(asset.function,15));ownership(body,asset.role)
	body.add_child(panel.label(copy.ui.benefit.format({"names":asset.beneficiaries}),14))
	var f: Dictionary=rules.forecast(state)
	body.add_child(panel.label(copy.ui.condition.format({"condition":state.assets.conditions[selected],"next":rules.assets.condition_next(state,selected,f.assets),"enabled":copy.ui.yes if state.assets.maintenance[selected] else copy.ui.no}),14))
	body.add_child(panel.label(copy.ui.ledger.format({"food":state.food,"storage":rules.storage(state),"target":f.assets.target,"wood":state.wood,"adults":rules.people(state,true).size(),"people":rules.people(state).size(),"housing":rules.capacity(state)}),15))
	var row:=HFlowContainer.new();body.add_child(row)
	row.add_child(panel.button(copy.ui.inspect,func():inspect(selected),"InspectAsset"))
	row.add_child(panel.button(copy.ui.visit,visit,"VisitAsset"))
	action(body,copy.ui.repair+" · "+(copy.ui.disable if state.assets.maintenance[selected] else copy.ui.enable),{"kind":"asset_maintenance","id":selected,"enabled":not state.assets.maintenance[selected]},"MaintainAsset")
	if selected=="homes":
		for home in rules.content.households:
			if home.requires!="" and not rules.has_project(state,home.requires):continue
			var count: int=0
			for person in rules.people(state):
				if person.household==home.id:count+=1
			var memory: Dictionary=state.households.homes.get(home.id,{"stress":0,"practice":0})
			body.add_child(panel.label(copy.ui.occupied.format({"home":home.label,"people":count,"capacity":rules.balance.people_per_dwelling,"stress":memory.stress,"practice":memory.practice}),14))
	for id in asset.orders:standing(body,id,f)
	for id in asset.projects:
		if rules.land.active(state) and id in rules.land.content.legacy_projects and not rules.land.committed(state,id,rules):continue
		project(body,id,f)
	if rules.land.active(state):
		for proposal in rules.land.content.proposals:
			if proposal.asset==selected:
				body.add_child(panel.button(panel.land_panel.copy.ui.inspect+" · "+rules.land.sites[proposal.site].title,func():panel.land_panel.inspect(proposal.site),"AssetLand_"+proposal.id))
				if rules.land.committed(state,proposal.id,rules):project(body,proposal.id,f)
	if selected in ["yard","homes"]:housing(body)
	body.add_child(HSeparator.new())
	allocation(body,f,selected)
	forecast(body,f)

func standing(body: VBoxContainer,id: String,f: Dictionary) -> void:
	var rules=panel.rules;var state: Dictionary=panel.state
	var order: Dictionary=rules.households.orders[id]
	body.add_child(HSeparator.new());body.add_child(panel.label(order.label,18));body.add_child(panel.label(order.description,14))
	var requirements: Dictionary=rules.households.requirements(id)
	body.add_child(panel.label(copy.ui.paid.format({"paid":copy.ui.yes if state.households.investments[id] else copy.ui.no,"ready":copy.ui.yes if rules.households.ready(state,id,rules) else copy.ui.no,"filled":f.assets.orders.get(id,0),"needed":maxi(requirements.care,requirements.watch),"wood":0 if state.households.investments[id] else rules.households.balance.costs[id]}),14))
	action(body,copy.ui.disable if state.households.orders[id] else copy.ui.enable,{"kind":"household_order","id":id,"enabled":not state.households.orders[id]},"AssetOrder_"+id)

func project(body: VBoxContainer,id: String,f: Dictionary,details: bool=true) -> void:
	var rules=panel.rules;var state: Dictionary=panel.state
	var p: Dictionary=rules.projects[id]
	if details:body.add_child(HSeparator.new());body.add_child(panel.label(p.title,18));body.add_child(panel.label(p.body,14))
	if rules.has_project(state,id):body.add_child(panel.label(copy.ui.done,14));return
	var queued: Dictionary={}
	for item in state.queue:
		if item.id==id:queued=item
	var requirements: PackedStringArray=[]
	for key in p.requires:requirements.append(rules.projects[key].title)
	if details and not requirements.is_empty():body.add_child(panel.label(copy.ui.dependencies.format({"items":", ".join(requirements)}),14))
	if queued.is_empty():
		if details:body.add_child(panel.label(panel.copy.project_cost%[p.title,p.wood,p.work],14))
		action(body,copy.ui.commission,{"kind":"commission","id":id},"AssetCommission_"+id)
		return
	var spec: Dictionary=state.assets.initiatives[id]
	var leader: Dictionary=rules.person_by_id(state,spec.author)
	body.add_child(panel.label(copy.ui.role.format({"office":panel.copy[spec.office],"name":leader.get("name","—"),"since":int(spec.turn)+1,"skill":leader.get(spec.office,0)}),13))
	body.add_child(panel.label(copy.ui.project.format({"title":p.title,"progress":queued.progress,"work":p.work,"wood":p.wood,"next":f.assets.projects[id].work}),15))
	if spec.paused:body.add_child(panel.label(copy.ui.paused,14))
	var row:=HBoxContainer.new();body.add_child(row)
	var priority:=SpinBox.new();priority.name="Priority_"+id;priority.min_value=1;priority.max_value=3;priority.value=spec.priority;priority.prefix=copy.ui.priority
	var crew:=SpinBox.new();crew.name="Crew_"+id;crew.min_value=0;crew.max_value=rules.assets.balance.max_crew;crew.value=spec.crew;crew.prefix=copy.ui.crew
	priority.editable=rules.permitted(state,p.role);crew.editable=priority.editable
	row.add_child(priority);row.add_child(crew)
	priority.value_changed.connect(func(value):panel.dispatch({"kind":"asset_project","id":id,"priority":int(value),"crew":spec.crew,"paused":spec.paused}))
	crew.value_changed.connect(func(value):panel.dispatch({"kind":"asset_project","id":id,"priority":spec.priority,"crew":int(value),"paused":spec.paused}))
	action(body,copy.ui.resume if spec.paused else copy.ui.pause,{"kind":"asset_project","id":id,"priority":spec.priority,"crew":spec.crew,"paused":not spec.paused},"AssetPause_"+id)
	var refund: int=int(p.wood)*(int(p.work)-int(queued.progress))/int(p.work)
	body.add_child(panel.label(copy.ui.refund.format({"wood":refund}),13))
	action(body,copy.ui.cancel,{"kind":"cancel","id":id},"AssetCancel_"+id)

func allocation(body: VBoxContainer,f: Dictionary,asset: String="") -> void:
	body.add_child(panel.label(copy.ui.allocation,18))
	for request in f.assets.requests:
		if asset!="" and request.asset!=asset:continue
		var title: String=panel.rules.projects.get(request.id,{}).get("title",panel.living_panel.copy.activities.get(request.id,copy.ui.jobs.get(request.id,request.id)))
		body.add_child(panel.label(copy.ui.request.format({"title":title,"filled":request.filled,"wanted":request.wanted,"reason":copy.ui.get(request.reason,request.reason)}),14))
	body.add_child(panel.label(copy.ui.allocation_order,13))

func forecast(body: VBoxContainer,f: Dictionary) -> void:
	var values: Dictionary=f.duplicate();values.delta="%+d"%int(f.food_delta);values.repair=f.assets.repair_cost
	body.add_child(panel.label(copy.ui.forecast.format(values),15))
	body.add_child(panel.label(copy.ui.food_upkeep.format({"food":panel.rules.assets.food_penalty(panel.state),"work":int(panel.rules.assets.balance.work_yield_loss) if panel.state.assets.conditions.workroom<panel.rules.assets.balance.condition_threshold else 0}),13))
	if not panel.state.report.is_empty():body.add_child(panel.label(copy.ui.actual.format(panel.state.report),14))
	else:body.add_child(panel.label(copy.ui.no_report,14))
	for key in ["wellbeing","cooperation","security"]:
		var factors: PackedStringArray=[]
		for factor in f.factors[key]:
			if factor.value!=0:factors.append(panel.copy.factor_names[factor.id]+" %+d"%int(factor.value))
		body.add_child(panel.label(panel.copy.factor_line%[panel.copy[key],panel.state[key],f.stocks[key],", ".join(factors)],13))

func principles(body: VBoxContainer) -> void:
	for p in copy.principles:
		body.add_child(panel.label(p.label,18));ownership(body,p.role);body.add_child(panel.label(p.body,14))
		var choices:=HFlowContainer.new();body.add_child(choices)
		for i in range(p.options.size()):
			var option: Button=panel.button(p.options[i],func():panel.dispatch({"kind":"asset_principle","id":p.id,"value":i}),"Principle_"+p.id+"_"+str(i))
			var quote: Dictionary=panel.rules.quote(panel.state,{"kind":"asset_principle","id":p.id,"value":i})
			option.disabled=quote.has("error") or panel.rules.assets.principle(panel.state,p.id)==i
			if quote.has("error"):option.tooltip_text=reason(quote.error);body.add_child(panel.label(option.tooltip_text,13))
			choices.add_child(option)
		body.add_child(HSeparator.new())
	# Rationing remains the existing single policy, never a second food setting.
	var ration:=CheckButton.new();ration.text=panel.copy.rations;ration.button_pressed=panel.state.tight_rations;ration.disabled=not panel.rules.permitted(panel.state,"steward")
	ration.toggled.connect(func(value):panel.dispatch({"kind":"policy","welcome":panel.state.welcome,"tight_rations":value}));body.add_child(ration)

func housing(body: VBoxContainer) -> void:
	if panel.rules.land.active(panel.state):
		body.add_child(panel.label(panel.land_panel.copy.ui.needs_choice,15));return
	body.add_child(panel.label(copy.ui.group,19));body.add_child(panel.label(copy.ui.group_body,14))
	action(body,copy.ui.group_stop if panel.state.assets.housing else copy.ui.group_start,{"kind":"asset_housing","enabled":not panel.state.assets.housing},"HousingCoordination")
	if panel.state.assets.housing:
		action(body,copy.ui.next_step,{"kind":"asset_housing_step"},"HousingNextStep")
		body.add_child(panel.label(copy.ui.group_wait,13))

func guide(body: VBoxContainer) -> void:
	var state: Dictionary=panel.state;var rules=panel.rules
	var index: int=state.assets.tutorial
	if index<copy.tutorial.size():
		var step: Dictionary=copy.tutorial[index]
		body.add_child(panel.label(step.title,21));body.add_child(panel.label(step.body,16))
		body.add_child(panel.button(copy.ui.inspect+" · "+rules.assets.assets[step.asset].title,func():inspect(step.asset),"GuideInspect"))
		if step.condition=="principle":body.add_child(panel.button(copy.ui.principles,func():panel.tabs.current_tab=4,"GuidePrinciples"))
		action(body,copy.ui.check,{"kind":"asset_review"},"ReviewAssetStep")
	else:body.add_child(panel.label(copy.ui.tutorial_complete,18))
	if state.assets.pressure_start<0:
		body.add_child(panel.label(copy.ui.pressure_note,14));action(body,copy.ui.begin_pressure,{"kind":"asset_pressure"},"AssetPressure")
	else:
		for phase in panel.household_panel.copy.stages:
			if phase.id==rules.households.stage(state):body.add_child(panel.label(phase.label+" · "+phase.description,15))
	var f: Dictionary=rules.forecast(state)
	allocation(body,f);forecast(body,f)
	growth(body)

func growth(body: VBoxContainer) -> void:
	var r=panel.rules;var s: Dictionary=panel.state;var b: Dictionary=r.balance
	body.add_child(panel.label(copy.ui.growth.format({"people":r.people(s).size(),"required":b.town_population,"homes":r.capacity(s)/int(b.people_per_dwelling),"dwellings":b.town_dwellings,"food":s.food,"reserve":r.people(s).size()*int(b.town_reserve_seasons),"wellbeing":s.wellbeing,"wellbeing_required":b.town_wellbeing,"cooperation":s.cooperation,"cooperation_required":b.town_cooperation,"security":s.security,"security_required":b.town_security,"stable":s.stable_seasons,"seasons":b.town_sustained_seasons}),15))
	for id in b.town_required_projects:body.add_child(panel.label(copy.ui.growth_project.format({"title":r.projects[id].title,"status":copy.ui.done if r.land.foundation(s,id,r) else copy.ui.status_waiting}),13))

func visit() -> void:
	var at: Array=panel.rules.assets.assets[selected].at
	var view=panel.app.campaign_view
	var position: Vector3=view._safe(Vector3(at[0],0,at[1]),panel.app.world)+Vector3.UP*1.68
	panel.app.set_view(position,position+Vector3(0,-.1,-1),false)
	panel.hide()

func journal(body: VBoxContainer) -> void:
	var decisions: Array=panel.state.assets.decisions
	for i in range(decisions.size()-1,maxi(-1,decisions.size()-31),-1):
		var decision: Dictionary=decisions[i]
		var name_: String=panel.rules.person_by_id(panel.state,decision.author).get("name","—")
		var target: String=panel.rules.projects.get(decision.target,{}).get("title",panel.rules.assets.assets.get(decision.target,{}).get("title",panel.rules.households.orders.get(decision.target,{}).get("label",decision.target)))
		var detail: String=""
		if decision.kind=="asset_principle":
			for p in copy.principles:
				if p.id==decision.target:target=p.label;detail=p.options[int(decision.details.value)]
		elif decision.details.has("enabled"):detail=copy.ui.enabled_choice.format({"enabled":copy.ui.yes if decision.details.enabled else copy.ui.no})
		elif decision.details.has("crew"):
			var values: Dictionary=decision.details.duplicate();values.paused=copy.ui.yes if values.paused else copy.ui.no
			detail=copy.ui.crew_choice.format(values)
		body.add_child(panel.label(copy.ui.decision.format({"turn":int(decision.turn)+1,"office":panel.copy[decision.office],"name":name_,"action":copy.ui.decision_actions[decision.kind],"target":target,"details":detail}),14))
