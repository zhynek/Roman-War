extends RefCounted
## Presentation only: all mutations pass through settlement commands.
var panel
var copy: Dictionary
var selected: String = ""

func _init(owner_panel, prose: Dictionary) -> void:
	panel=owner_panel
	copy=prose

func build(body: VBoxContainer) -> void:
	var state:Dictionary=panel.state
	var rules=panel.rules
	var contacts=rules.neighbors
	body.add_child(panel.label(copy.intro,20))
	body.add_child(panel.label(copy.hypothesis,14))
	if not contacts.active(state):
		body.add_child(panel.label(copy.locked,16))
		var begin:Button=panel.button(copy.begin,func():panel.dispatch({"kind":"neighbor_begin"}),"BeginNeighbors")
		begin.disabled=not state.town_achieved or not rules.has_project(state,contacts.content.project_id) or not rules.permitted(state,"steward")
		body.add_child(begin)
		return
	body.add_child(panel.label(copy.complete if state.contacts.chapter_complete else copy.guide,16))
	var mission:Dictionary=state.contacts.mission
	if not mission.is_empty():
		var params:Dictionary=mission.duplicate(true)
		params.id=mission.id.trim_prefix("mission_")
		params.neighbor=contacts.communities[mission.neighbor].name
		params.status=copy.moving if contacts.crew(state,state.plan).ready else copy.waiting
		body.add_child(panel.label(copy.mission.format(params),16))
		var cancel:Button=panel.button(copy.cancel,func():panel.dispatch({"kind":"neighbor_cancel"}),"CancelMission")
		cancel.disabled=mission.started or not rules.permitted(state,"steward");body.add_child(cancel)
	else:body.add_child(panel.label(copy.no_mission,14))
	var row:=HBoxContainer.new();body.add_child(row)
	if selected.is_empty():selected=contacts.communities.keys()[0]
	for id in contacts.communities:
		var choice:Button=panel.button(contacts.communities[id].name,func():selected=id;panel.refresh(),"Neighbor_"+id)
		choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choice.toggle_mode=true;choice.button_pressed=id==selected;row.add_child(choice)
	var spec:Dictionary=contacts.communities[selected]
	var local:Dictionary=state.contacts.neighbors[selected]
	var speaker:Dictionary=contacts.leader(state,selected).duplicate(true)
	speaker.remaining=maxi(0,int(contacts.balance.leader_term)-int(state.turn)+int(local.leader_since))
	body.add_child(panel.label(spec.description,15))
	body.add_child(panel.label(copy.leader.format(speaker),16))
	var stats:Dictionary=spec.duplicate(true);stats.merge(local,true)
	body.add_child(panel.label(copy.stocks.format(stats),16))
	body.add_child(panel.label(copy.progress.format(local),14))
	var q:Dictionary=contacts.quote(state,selected,"trade",rules)
	var offer:Dictionary=q.duplicate(true);offer.give=copy[q.give];offer.receive=copy[q.receive];offer.carriers=contacts.balance.carriers
	body.add_child(panel.label(copy.offer.format(offer),17))
	body.add_child(panel.label(copy.risk.format(offer),14))
	body.add_child(panel.label(copy.risk_factors.format(q),14))
	body.add_child(panel.label(copy.availability.format({"reason":copy.get(q.get("error","ready"),q.get("error","ready"))}),14))
	var trade:Button=panel.button(copy.trade,func():panel.dispatch({"kind":"neighbor_send","neighbor":selected,"mission":"trade"}),"SendTrade")
	trade.disabled=q.has("error") or not rules.permitted(state,"steward");body.add_child(trade)
	var aid_copy:Dictionary=spec.aid.duplicate(true);aid_copy.resource=copy[spec.aid.resource]
	body.add_child(panel.label(copy.aid_line.format(aid_copy),14))
	var aq:Dictionary=contacts.quote(state,selected,"aid",rules)
	var aid:Button=panel.button(copy.aid,func():panel.dispatch({"kind":"neighbor_send","neighbor":selected,"mission":"aid"}),"SendAid")
	aid.disabled=aq.has("error") or not rules.permitted(state,"steward");body.add_child(aid)
	if not local.report.is_empty():
		body.add_child(panel.label(copy.neighbor_report.format(local.report),14))
		body.add_child(panel.label(copy.trust_report.format(local.report),14))
		body.add_child(panel.label(copy.cargo_report.format(local.report),14))
	body.add_child(HSeparator.new())
	body.add_child(panel.label(copy.escort_label,18))
	body.add_child(panel.label(copy.escort_note,14))
	var escort:=SpinBox.new();escort.name="EscortCount";escort.min_value=0;escort.max_value=contacts.balance.max_escorts;escort.value=state.contacts.escort_policy;escort.editable=rules.permitted(state,"watch");body.add_child(escort)
	var apply:Button=panel.button(copy.apply_escort,func():panel.dispatch({"kind":"neighbor_escort","escorts":int(escort.value)}),"SetEscort")
	apply.disabled=not rules.permitted(state,"watch");body.add_child(apply)
	body.add_child(panel.button(copy.visit,_visit,"VisitMeeting"))

func _visit() -> void:
	var at:Array=panel.rules.neighbors.content.meeting_at
	var eye:=Vector3(at[0],panel.app.world.floor_height(at[0],at[1])+1.68,at[1])
	panel.app.set_view(eye,eye+Vector3(0,0,-1),false)
	panel.hide()
