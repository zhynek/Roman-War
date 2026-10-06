extends RefCounted
var panel
var copy: Dictionary
var selected: String="west_wood"
func _init(owner_panel,config: Dictionary) -> void:panel=owner_panel;copy=config
func begin() -> void:
	panel.begin()
	panel.dispatch({"kind":"asset_begin"})
	panel.dispatch({"kind":"land_begin"})
	panel.dispatch({"kind":"living_begin"})
	panel.tabs.current_tab=8
func inspect(id: String) -> void:
	selected=id
	panel.dispatch({"kind":"living_inspect","id":id})
	panel.app.hud.show();panel.show();panel.tabs.current_tab=8
func title(id: String) -> String:
	if id in ["workroom","store"]:return copy.ui[id]
	for h in panel.rules.content.households:
		if h.id==id:return h.label
	return panel.rules.living.subjects[id].get("title",id)
func position(id: String) -> Array:
	if id=="workroom":return panel.rules.assets.assets.workroom.at
	if id=="store":return panel.rules.assets.assets.stores.at
	for h in panel.rules.content.households:
		if h.id==id:return h.at
	return panel.rules.living.subjects[id].at
func visit() -> void:
	if selected=="workroom":panel.household_panel.visit("household_workshop");return
	if selected=="store":panel.household_panel.visit("household_store");return
	var at: Array=position(selected)
	var center:=Vector3(at[0],panel.app.world.floor_height(at[0],at[1]),at[1])
	panel.app.set_view(center+Vector3(6,5,8),center)
	panel.hide()
func action(body: VBoxContainer,text_: String,a: Dictionary,id: String) -> void:
	var quote: Dictionary=panel.rules.quote(panel.state,a)
	var b: Button=panel.button(text_,func():panel.dispatch(a),id);body.add_child(b)
	if quote.has("error"):
		b.disabled=true;body.add_child(panel.label(copy.errors.get(quote.error,panel.copy.get(quote.error,panel.asset_panel.reason(quote.error))),13))
func order(body: VBoxContainer,id: String,labels: Array,values: Array) -> void:
	body.add_child(panel.label(copy.ui.get(id+"_order",copy.ui.get(id,id)),16))
	var row:=HFlowContainer.new();body.add_child(row)
	for i in range(values.size()):
		var b: Button=panel.button(str(labels[i]),func():panel.dispatch({"kind":"living_order","id":id,"value":values[i]}),"LivingOrder_"+id+"_"+str(i));row.add_child(b)
		b.disabled=values[i]==panel.state.living[id] or panel.rules.quote(panel.state,{"kind":"living_order","id":id,"value":values[i]}).has("error")
func build(body: VBoxContainer) -> void:
	var r=panel.rules;var s: Dictionary=panel.state
	body.add_child(panel.label(copy.ui.intro,16))
	if not r.living.active(s):
		body.add_child(panel.label(copy.ui.migration,15));action(body,copy.ui.adopt,{"kind":"living_begin"},"AdoptLiving");return
	var f: Dictionary=r.forecast(s)
	var fields: Dictionary=f.living.duplicate();fields.wood=s.wood;fields.blanks=s.living.blanks;fields.kits=s.living.kits
	body.add_child(panel.label(copy.ui.overview,20));body.add_child(panel.label(copy.ui.summary.format(fields),15))
	body.add_child(panel.label(copy.ui.timing,14))
	var picker:=OptionButton.new();picker.name="LivingSubject";body.add_child(picker)
	var ids: Array=r.living.subjects.keys()
	for id in ids:
		picker.add_item(title(id))
		if id==selected:picker.select(picker.item_count-1)
	picker.item_selected.connect(func(i):inspect(ids[i]))
	body.add_child(panel.label(title(selected),19))
	body.add_child(panel.label(r.living.subjects[selected].get("body",copy.ui.knowledge),15))
	if r.living.areas.has(selected):
		var area: Dictionary=r.living.areas[selected].duplicate()
		area.stock=s.living.woodland[selected];area.harvest=f.living.harvest if selected==s.living.area else 0
		area.next_stock=mini(int(area.capacity),int(area.stock)-int(area.harvest)+int(area.recovery));area.distance=f.living.distance if selected==s.living.area else area.distance_cost
		var names: Array=[]
		if selected==s.living.area:
			for task in r.assignments(s,f.plan):
				if task.duty=="timber":names.append(r.person_by_id(s,task.id).name)
		area.names=", ".join(names);body.add_child(panel.label(copy.ui.area.format(area),14))
	if selected=="store":body.add_child(panel.label(copy.ui.store_note,15))
	if s.living.experience.has(selected):body.add_child(panel.label(copy.ui.household.format(s.living.experience[selected]),15))
	body.add_child(panel.button(copy.ui.inspect,func():inspect(selected),"InspectLiving"))
	body.add_child(panel.button(copy.ui.visit,visit,"VisitLiving"))
	body.add_child(panel.label(copy.ui.relationship.format(s.living),14))
	body.add_child(panel.label(copy.ui.orders,19))
	order(body,"area",[copy.areas[0].title,copy.areas[1].title],[copy.areas[0].id,copy.areas[1].id])
	order(body,"prepare",copy.ui.prepare_options,[0,1,2])
	for id in ["cooperate","training","repair"]:
		order(body,id,[copy.ui.off,copy.ui.on],[false,true])
	order(body,"patrol",[copy.posts[0].title,copy.posts[1].title],[copy.posts[0].id,copy.posts[1].id])
	for id in ["living_shared_room","watch_shelter","living_north_post","living_watch_kits"]:
		body.add_child(panel.label(r.projects[id].title,18));body.add_child(panel.label(r.projects[id].body,14))
		body.add_child(panel.label(copy.ui.cost.format(r.projects[id]),14))
		if id=="living_watch_kits":body.add_child(panel.label(copy.ui.kits_cost,14))
		panel.asset_panel.project(body,id,f,false)
	body.add_child(panel.label(copy.ui.journal,20))
	if s.living.discoveries.is_empty():body.add_child(panel.label(copy.ui.none,14))
	for d in copy.discoveries:
		if s.living.discoveries.has(d.id):body.add_child(panel.label(d.title+"\n"+d.body,15))
	if not s.living.report.is_empty():body.add_child(panel.label(copy.ui.report.format(s.living.report),15))
	panel.asset_panel.allocation(body,f)
	panel.asset_panel.forecast(body,f)
	body.add_child(panel.label(copy.ui.recover,15))
func guide(body: VBoxContainer) -> void:
	var s: Dictionary=panel.state
	if s.living.tutorial<copy.tutorial.size():
		var step: Dictionary=copy.tutorial[s.living.tutorial]
		body.add_child(panel.label(step.title,20));body.add_child(panel.label(step.body,16))
		action(body,copy.ui.ready,{"kind":"living_review"},"ReviewLivingStep")
	else:body.add_child(panel.label(copy.ui.done,17))
	body.add_child(panel.button(copy.ui.tab,func():panel.tabs.current_tab=8,"OpenLiving"))
	body.add_child(panel.label(copy.ui.recover,14))
	panel.asset_panel.forecast(body,panel.rules.forecast(s))
	body.add_child(panel.label(copy.ui.growth,15));panel.asset_panel.growth(body)
	if s.assets.pressure_start<0:panel.asset_panel.action(body,panel.asset_panel.copy.ui.begin_pressure,{"kind":"asset_pressure"},"AssetPressure")
