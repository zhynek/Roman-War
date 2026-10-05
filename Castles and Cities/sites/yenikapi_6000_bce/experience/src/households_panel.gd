extends RefCounted
## Renders household decisions and the presentation adapter's current routines.
var panel
var copy: Dictionary
var selected: String = ""

func _init(owner_panel, content: Dictionary) -> void:
	panel=owner_panel
	copy=content

func build(body: VBoxContainer) -> void:
	var rules=panel.rules
	var state:Dictionary=panel.state
	var life=rules.households
	body.add_child(panel.label(copy.title,20))
	body.add_child(panel.label(copy.disclaimer,14))
	if not life.active(state):
		body.add_child(panel.label(copy.intro,16))
		body.add_child(panel.label(copy.ui.inactive,15))
		var begin:Button=panel.button(copy.begin,func():panel.dispatch({"kind":"household_begin"}),"BeginHouseholds")
		begin.disabled=state.role!="god";body.add_child(begin)
		return
	var phase:String=life.stage(state)
	for spec in copy.stages:
		if spec.id!=phase:continue
		body.add_child(panel.label(copy.ui.season.format({"elapsed":int(state.households.elapsed)+1,"stage":spec.label}),20))
		body.add_child(panel.label(spec.description,15))
		body.add_child(panel.label(spec.hint,17))
	if phase=="settled":body.add_child(panel.label(copy.complete,15))
	var f:Dictionary=life.forecast(state,rules)
	var effects:Dictionary=f.duplicate();effects.food=f.food_penalty
	body.add_child(panel.label(copy.ui.effects.format(effects),16))
	body.add_child(panel.label(copy.ui.factors,16))
	for key in f.get("factors",{}):
		var parts:PackedStringArray=[]
		for item in f.factors[key]:
			if item.value!=0:parts.append(str(copy.factors.get(item.id,item.id))+" %+d"%int(item.value))
		if not parts.is_empty():body.add_child(panel.label(str(copy.ui.get("lost_food",key).format({"value":f.food_penalty}) if key=="food_penalty" else panel.copy.get(key,key))+": "+", ".join(parts),13))
	for station in copy.stations:
		body.add_child(panel.button(copy.ui.visit.format(station),func():visit(station.id),"Visit_"+station.id))
	body.add_child(panel.label(copy.ui.orders,19))
	body.add_child(panel.label(copy.ui.labor,14))
	body.add_child(panel.button(panel.copy.suggest,panel._suggest,"HouseholdSuggestedWorkforce"))
	for order in copy.orders:
		body.add_child(HSeparator.new())
		body.add_child(panel.label(order.label,17))
		body.add_child(panel.label(order.description,14))
		var paid:bool=state.households.investments[order.id]
		body.add_child(panel.label(copy.ui.paid if paid else copy.ui.cost.format({"wood":rules.balance.households.costs[order.id],"role":panel.copy.get(order.role,order.role)}),14))
		body.add_child(panel.label(copy.ui.staffing.format(life.requirements(order.id)),13))
		var enabled:bool=state.households.orders[order.id]
		if enabled:body.add_child(panel.label(copy.ui.active if life.ready(state,order.id,rules) else (copy.ui.learning_wait if order.id=="learning" and phase in ["warning","danger"] else copy.ui.understaffed),14))
		var toggle:Button=panel.button(copy.ui.disable if enabled else copy.ui.enable,func():panel.dispatch({"kind":"household_order","id":order.id,"enabled":not enabled}),"Order_"+order.id)
		toggle.disabled=not rules.permitted(state,order.role);body.add_child(toggle)
	body.add_child(HSeparator.new())
	body.add_child(panel.label(copy.ui.households,19))
	for id in state.households.homes:
		var home:Dictionary=state.households.homes[id].duplicate();home.id=id
		for household in rules.content.households:
			if household.id==id:home.id=household.label
		body.add_child(panel.label(copy.ui.memory.format(home),14))
	body.add_child(panel.label(copy.ui.residents,19))
	var view=panel.app.campaign_view
	if is_instance_valid(view) and is_instance_valid(view.life):
		var choices:=OptionButton.new();choices.name="HouseholdResident";choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(choices)
		var routines:Array=view.life.routines
		if not routines.is_empty():
			var index:int=0
			for i in range(routines.size()):
				choices.add_item(routines[i].name)
				if routines[i].id==selected:index=i
			choices.select(index);selected=routines[index].id
			choices.item_selected.connect(func(i):selected=routines[i].id;panel.refresh())
			var routine:Dictionary=routines[index]
			var params:Dictionary=routine.duplicate()
			params.activity=copy.presentation.activity_labels.get(routine.activity,routine.activity)
			params.reason=copy.presentation.reason_labels.get(routine.reason,routine.reason)
			body.add_child(panel.label(copy.ui.routine.format(params),16))
			body.add_child(panel.button(copy.ui.inspect.format(params),func():visit(routine.station),"FollowResident"))
	body.add_child(panel.label(copy.ui.interpretation,13))

func visit(id: String) -> void:
	var view=panel.app.campaign_view
	if not is_instance_valid(view) or not is_instance_valid(view.life) or not view.life.stations.has(id):return
	var station:Dictionary=view.life.stations[id]
	var at:Vector3=station.get("viewpoint",station.position)
	# Arrival uses a known passable station, never a raw building centre.
	var eye:Vector3=at+Vector3.UP*1.68
	panel.app.set_view(eye,station.get("look_at",eye+Vector3(0,-.3,-1)),false)
	panel.app.location_label.text=station.label
	panel.app.note.text=copy.ui.interpretation
	panel.app.status.text=""
	panel.hide()

func inspect_resident(id:String) -> void:
	selected=id
	panel.open();panel.tabs.current_tab=6
	for i in range(3):await panel.get_tree().process_frame
	var picker:Control=panel.find_child("HouseholdResident",true,false)
	if picker!=null:panel.tabs.get_child(6).ensure_control_visible(picker)
