extends RefCounted
var panel
var copy: Dictionary
var selected: String="clay_court"

func _init(owner_panel,config: Dictionary) -> void:
	panel=owner_panel;copy=config

func begin() -> void:
	panel.begin()
	panel.dispatch({"kind":"asset_begin"})
	panel.dispatch({"kind":"land_begin"})
	panel.tabs.current_tab=7

func inspect(id: String) -> void:
	selected=id
	panel.dispatch({"kind":"land_inspect","id":id})
	panel.show();panel.tabs.current_tab=7

func visit() -> void:
	var at: Array=panel.rules.land.sites[selected].at
	var center:=Vector3(at[0],panel.app.world.floor_height(at[0],at[1]),at[1])
	panel.app.set_view(center+Vector3(9,9,12),center)
	panel.hide()

func build(body: VBoxContainer) -> void:
	var rules=panel.rules
	var state: Dictionary=panel.state
	if not rules.land.active(state):
		body.add_child(panel.label(copy.ui.intro,16))
		body.add_child(panel.label(copy.ui.migration,15))
		panel.asset_panel.action(body,copy.ui.adopt,{"kind":"land_begin"},"AdoptLand")
		return
	panel.asset_panel.ownership(body,"steward")
	var f: Dictionary=rules.forecast(state)
	var totals: Dictionary=f.land.duplicate()
	totals.crew=f.assets.access_workers;totals.wood=f.assets.access_cost
	totals.access=copy.ui.none if not rules.land.needs_access(state,rules) else copy.ui.ready if f.land.access else copy.ui.waiting
	body.add_child(panel.label(copy.ui.totals.format(totals),15))
	var picker:=OptionButton.new();picker.name="LandPicker"
	for site in copy.sites:
		picker.add_item(site.title)
		if site.id==selected:picker.select(picker.item_count-1)
	picker.item_selected.connect(func(index):inspect(copy.sites[index].id));body.add_child(picker)
	var site: Dictionary=rules.land.sites[selected]
	var use: String=rules.land.use_at(state,selected,rules)
	var fields: Dictionary=site.duplicate()
	fields.objects=", ".join(site.objects) if not site.objects.is_empty() else copy.ui.none
	if use!="" and rules.has_project(state,use):
		fields.use=rules.projects[use].title
		var ids: Array=[]
		for change in rules.projects[use].changes:
			for record in change.after:ids.append(record.id)
		fields.objects=", ".join(ids)
	body.add_child(panel.label(copy.ui.now.format(fields),15))
	if use!="":body.add_child(panel.label((copy.ui.completed if rules.has_project(state,use) else copy.ui.reserved).format({"project":rules.projects[use].title}),15))
	body.add_child(panel.button(copy.ui.visit,visit,"VisitLand"))
	for proposal in copy.proposals:
		if proposal.site!=selected:continue
		var p: Dictionary=rules.projects[proposal.id]
		body.add_child(panel.label(p.title,19));body.add_child(panel.label(p.body,15))
		var cost: Dictionary=p.duplicate();cost.slots=f.land.work
		body.add_child(panel.label(copy.ui.cost.format(cost),14))
		body.add_child(panel.label(copy.ui.effect.format({"housing":p.effects.get("housing",0),"storage":p.effects.get("storage",0),"food":int(proposal.food)-int(site.food),"work":int(proposal.work)-int(site.work),"cooperation":int(proposal.cooperation)-int(site.cooperation)}),14))
		body.add_child(panel.label(copy.ui.requirements.format({"requires":", ".join(p.requires) if not p.requires.is_empty() else copy.ui.none,"access":copy.ui.yes if proposal.requires_access else copy.ui.no,"retain":copy.ui.yes if proposal.retain else copy.ui.no}),14))
		panel.asset_panel.project(body,proposal.id,f,false)
	panel.asset_panel.action(body,copy.ui.upkeep+" · "+(copy.ui.off if state.land.access_enabled else copy.ui.on),{"kind":"land_access","enabled":not state.land.access_enabled},"LandAccess")
	body.add_child(panel.label(copy.ui.compare,19))
	for alternative in copy.sites:
		if alternative.id==selected:continue
		body.add_child(panel.button(alternative.title+" · "+alternative.use,func():inspect(alternative.id),"LandInspect_"+alternative.id))
	panel.asset_panel.allocation(body,f)
	panel.asset_panel.forecast(body,f)
	if not state.land.report.is_empty():body.add_child(panel.label(copy.ui.report.format(state.land.report),14))
	body.add_child(panel.label(copy.ui.recover,15))

func guide(body: VBoxContainer) -> void:
	var state: Dictionary=panel.state
	var rules=panel.rules
	if state.land.tutorial<copy.tutorial.size():
		var step: Dictionary=copy.tutorial[state.land.tutorial]
		body.add_child(panel.label(step.title,19));body.add_child(panel.label(step.body,16))
		body.add_child(panel.button(copy.ui.inspect,func():inspect(selected),"GuideLand"))
		panel.asset_panel.action(body,copy.ui.review,{"kind":"land_review"},"ReviewLandStep")
	else:body.add_child(panel.label(copy.ui.guide_done,17))
	body.add_child(panel.label(copy.ui.readiness.format({"housing":rules.capacity(state),"people":rules.people(state).size(),"food":state.food,"reserve":(rules.people(state).size()+int(rules.balance.migration_size))*int(rules.balance.migration_reserve_seasons)}),15))
	panel.asset_panel.forecast(body,rules.forecast(state))
	panel.asset_panel.growth(body)
	body.add_child(panel.label(copy.ui.recover,14))
	if state.assets.pressure_start<0:panel.asset_panel.action(body,panel.asset_panel.copy.ui.begin_pressure,{"kind":"asset_pressure"},"AssetPressure")
