extends RefCounted
var panel
var copy: Dictionary
var selected: String=""
func _init(p,c: Dictionary) -> void:panel=p;copy=c
func begin() -> void:
	if is_instance_valid(panel.app.visual_commands):panel.app.visual_commands.enabled=false;panel.app.visual_commands.sync()
	var s: Dictionary=panel.rules.new_state()
	for kind in ["asset_begin","land_begin","living_begin","incident_begin"]:s=panel.rules.command(s,{"kind":kind}).state
	panel.state=s;panel.last_message=""
	panel.app.show_campaign(s,panel.rules);panel.refresh()
	panel.tabs.current_tab=9
func action(body: VBoxContainer,text_: String,a: Dictionary,id: String) -> void:
	var quote: Dictionary=panel.rules.quote(panel.state,a)
	var b: Button=panel.button(text_,func():panel.dispatch(a),id);body.add_child(b)
	if quote.has("error"):
		b.disabled=true;body.add_child(panel.label(copy.errors.get(quote.error,panel.copy.get(quote.error,panel.asset_panel.reason(quote.error))),13))
func inspect(id: String) -> void:
	selected=id
	panel.dispatch({"kind":"incident_inspect","id":id})
	panel.app.hud.show();panel.show();panel.tabs.current_tab=9
func visit() -> void:
	var e: Dictionary=panel.rules.incidents.current(panel.state)
	if e.is_empty():return
	var at: Array=panel.rules.incidents.specs[e.id].at
	var target:=Vector3(at[0],panel.app.world.floor_height(at[0],at[1]),at[1])
	panel.app.set_view(target+Vector3(9,7,13),target);panel.hide()
func notice() -> String:
	var r=panel.rules;var s: Dictionary=panel.state
	var e: Dictionary=r.incidents.current(s)
	if e.is_empty():return copy.ui.quiet
	if e.known<0:return copy.ui.exposure
	if not e.outcome.is_empty():return copy.ui.recovery_notice.format({"title":r.incidents.specs[e.id].title,"turn":e.outcome.turn,"severity":e.outcome.severity})
	return copy.ui.notice.format({"title":r.incidents.specs[e.id].title,"phase":copy.phases[r.incidents.phase(s)],"due":e.due,"lead":maxi(0,int(e.due)-int(s.turn))})
func build(body: VBoxContainer) -> void:
	var r=panel.rules;var s: Dictionary=panel.state
	body.add_child(panel.label(copy.ui.intro,16))
	if not r.incidents.active(s):
		body.add_child(panel.label(copy.ui.migration,15));action(body,copy.ui.adopt,{"kind":"incident_begin"},"AdoptIncidents");return
	body.add_child(panel.label(notice(),19))
	var e: Dictionary=r.incidents.current(s)
	if not e.is_empty():
		var spec: Dictionary=r.incidents.specs[e.id]
		if not e.outcome.is_empty():
			var actual: Dictionary=e.outcome.duplicate();actual.recovered=copy.phases.recovery
			body.add_child(panel.label(copy.ui.actual.format(actual),17))
		var ids: Array=spec.subjects
		if selected not in ids:selected=ids[0]
		var picker:=OptionButton.new();picker.name="IncidentSubject";body.add_child(picker)
		for id in ids:
			picker.add_item(panel.living_panel.title(id))
			if id==selected:picker.select(picker.item_count-1)
		picker.item_selected.connect(func(i):inspect(ids[i]))
		body.add_child(panel.button(copy.ui.inspect,func():inspect(selected),"InspectIncident"))
		body.add_child(panel.button(copy.ui.visit,visit,"VisitIncident"))
		if e.known>=0:
			if e.outcome.is_empty():
				body.add_child(panel.label(spec.signs,15))
				body.add_child(panel.label(copy.ui.early if e.known<e.warning else copy.ui.public,14))
			if not e.inspected.is_empty():body.add_child(panel.label(spec.detail,15))
			var f: Dictionary=r.forecast(s)
			body.add_child(panel.label(copy.ui.known,19))
			if e.outcome.is_empty():
				body.add_child(panel.label(copy.ui.forecast.format(f.incidents),14))
				factors(body,f.incidents.factors)
				body.add_child(panel.label(copy.ui.restriction_note,14))
				action(body,copy.ui.reopen if e.restricted else copy.ui.restriction,{"kind":"incident_restrict","enabled":not e.restricted},"RestrictIncident")
				project(body,spec.prepare,f)
			else:
				outcome(body,e)
				body.add_child(panel.label(spec.result,15))
				body.add_child(panel.label(copy.ui.recovery,15))
				project(body,spec.repair,f)
			body.add_child(panel.label(copy.ui.commitment,14))
			panel.asset_panel.allocation(body,f)
			panel.asset_panel.forecast(body,f)
	body.add_child(panel.button(copy.ui.return_living,func():panel.tabs.current_tab=8,"IncidentLiving"))
	body.add_child(panel.label(copy.ui.record,20))
	for item in s.incidents.records:
		if item.known>=0:
			body.add_child(panel.label(copy.ui.record_entry.format({"id":item.id,"kind":r.incidents.specs[item.id].title,"turn":item.known}),15))
			for subject in item.inspected:body.add_child(panel.label(panel.living_panel.title(subject)+" · "+r.incidents.specs[item.id].detail,14))
		if not item.outcome.is_empty():
			outcome(body,item)
			for home in r.incidents.specs[item.id].households:body.add_child(panel.label(panel.living_panel.title(home)+" · "+copy.ui.memories,14))
func project(body: VBoxContainer,id: String,f: Dictionary) -> void:
	body.add_child(panel.label(panel.rules.projects[id].title,19))
	body.add_child(panel.label(copy.ui.cost.format(panel.rules.incidents.project_specs[id]),14))
	panel.asset_panel.project(body,id,f,false)
func factors(body: VBoxContainer,items: Array) -> void:
	body.add_child(panel.label(copy.ui.factors,16))
	for item in items:body.add_child(panel.label("%s: %+d"%[copy.factors[item.id],int(item.value)],14))
func outcome(body: VBoxContainer,e: Dictionary) -> void:
	var fields: Dictionary=e.outcome.duplicate();fields.recovered=str(e.recovered) if e.recovered>=0 else copy.phases.recovery
	body.add_child(panel.label(copy.ui.actual.format(fields),15));factors(body,e.outcome.factors)
func guide(body: VBoxContainer) -> void:
	var s: Dictionary=panel.state
	if s.incidents.tutorial<copy.tutorial.size():
		var step: Dictionary=copy.tutorial[s.incidents.tutorial]
		body.add_child(panel.label(step.title,20));body.add_child(panel.label(step.body,16))
		action(body,copy.ui.ready,{"kind":"incident_review"},"ReviewIncidentStep")
	else:body.add_child(panel.label(copy.ui.done,17))
	body.add_child(panel.label(copy.ui.guidance,14))
	body.add_child(panel.button(copy.ui.tab,func():panel.tabs.current_tab=9,"OpenIncidents"))
	panel.asset_panel.forecast(body,panel.rules.forecast(s));panel.asset_panel.growth(body)
