extends Control
const Host=preload("res://src/defense_host.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const View=preload("res://src/defense_view.gd")
const Nav=preload("res://src/core/defense_navigation.gd")
const Saves=preload("res://src/campaign_save.gd")
var app
var p
var copy: Dictionary
var host
var view
var battle: Dictionary={}
var practice: bool=false
var selected: Array=[]
var mode: String="move"
var message: String=""
var phase: String=""
var summary: Label
var hint: Label
var roster: Label
var drag_start:=Vector2.ZERO
var dragging: bool=false
var drag_end:=Vector2.ZERO
var panning: bool=false
var prepared_nav: Dictionary={}
var saved_camera: Transform3D
var active_ui: bool=false
var quick_ui: bool=false
var quick_refresh: float=0.0
var aftermath_page: int=0
func w(id: String) -> String:return copy.get(id,id)
func configure(owner_app) -> void:
	app=owner_app;p=app.campaign;copy=p.rules.defense.content.ui.duplicate(true);copy.merge(p.rules.warfare.content.get("ui",{}),true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE;hide()
func panel(at: Vector2,size_: Vector2) -> VBoxContainer:
	var box:=PanelContainer.new();box.position=at;box.size=size_;box.add_theme_stylebox_override("panel",app.visual_commands.style("142b2e"));add_child(box)
	var v:=VBoxContainer.new();v.add_theme_constant_override("separation",8);box.add_child(v);return v
func label(parent: Node,text_: String,size_: int=16) -> Label:
	var l: Label=app._label(text_,size_);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(l);return l
func button(parent: Node,text_: String,callback: Callable,id: String) -> Button:
	var b: Button=app._button(text_,callback);b.name=id;parent.add_child(b);return b
func row(parent: Node) -> HFlowContainer:
	var n:=HFlowContainer.new();parent.add_child(n);return n
func clear_ui() -> void:
	for child in get_children():remove_child(child);child.queue_free()
func open() -> void:
	if p.state.is_empty():app.visual_commands.begin()
	if not app.campaign_mode:app.show_campaign(p.state,p.rules)
	active_ui=true;show();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	app._look_drag=false;saved_camera=app.camera.transform
	p.hide();app.visual_commands.hide();app.reference_top.hide();app.reference_bottom.hide();app.info.hide()
	if p.rules.defense.locked(p.state):attach(p.state.defense.battle);return
	battle={};phase="prepare";render_preparation()
func render_preparation() -> void:
	clear_ui();var size_: Vector2=get_viewport_rect().size
	var outer:=panel(Vector2(22,18),Vector2(minf(740,size_.x-44),size_.y-36))
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;outer.add_child(scroll)
	var v:=VBoxContainer.new();v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_theme_constant_override("separation",8);scroll.add_child(v)
	if p.rules.warfare.active(p.state):
		var spec: Dictionary=p.rules.warfare.threats.spec(p.state)
		if p.rules.warfare.threats.enabled(p.state) and p.state.warfare.threats.pending.is_empty():label(v,p.rules.defense.content.title,30)
		else:label(v,spec.title,30);label(v,spec.brief+"\n"+spec.stakes,17)
		label(v,w("warfare_guide"),16)
	else:
		label(v,p.rules.defense.content.subtitle,30);label(v,w("brief"),17);label(v,w("guide"),16)
	var q: Dictionary=p.rules.defense.quote(p.state,p.rules)
	label(v,w("cost").format(q),18)
	for id in q.ids:
		var person: Dictionary=p.rules.person_by_id(p.state,id)
		label(v,w("roster").format({"name":person.name,"duty":w("watch_duty"),"kit":w("equipped") if q.ids.find(id)<int(q.kits) else w("unarmed")}),15)
	if p.state.get("defense",{}).get("completed",false):
		var report: Dictionary=p.state.defense.reports.back()
		label(v,w("last_report").format({"outcome":w(report.outcome),"lost":report.lost,"wounded":report.wounded.size()}),16)
		var names: Array=[]
		for id in p.state.defense.recovery:names.append(p.rules.person_by_id(p.state,id).name)
		if not names.is_empty():
			label(v,w("recovery_names").format({"names":", ".join(names)}),15)
			if aftermath_data().is_empty():label(v,w("recovery"),15)
			else:
				for id in p.state.defense.recovery:label(v,recorded_person(id).name+" · "+w("aftermath_recovering").format({"remaining":p.state.defense.recovery[id]}),14)
				label(v,w("aftermath_recovery_route"),15)
		button(v,w("aftermath_title"),open_aftermath,"DefenseAftermath")
	if not p.rules.warfare.active(p.state):
		label(v,w("adoption"),15)
		button(v,w("adopt"),prep_command.bind({"kind":"warfare_begin"}),"WarfareAdopt")
	else:
		label(v,w("adopted"),15)
		render_threats(v)
		label(v,w("modes_brief"),15)
		var maximum: int=int(p.rules.defense.tactical_tuning.max_skill)
		var low: int=maximum;var high: int=0;var leader: String=w("leader_absent")
		for id in q.ids:
			var person: Dictionary=p.rules.person_by_id(p.state,id)
			var skill: int=p.rules.warfare.aftermath.skill(p.state,id,p.rules)
			low=mini(low,skill);high=maxi(high,skill)
			if id==p.state.leaders.watch.id:leader=person.name
		label(v,w("readiness_skills").format({"low":low if not q.ids.is_empty() else 0,"high":high,"maximum":maximum,"leader":leader}),15)
		label(v,w("preparation_advantages"),14)
		var filled: int=0
		for request in p.rules.assets.allocation(p.state,p.rules).requests:
			if request.id=="warfare_muster":filled=int(request.filled)
		label(v,w("muster_heading"),21);label(v,w("muster_hint"),14)
		label(v,w("muster_status").format({"requested":p.state.warfare.get("muster",0),"filled":filled}),16)
		var muster_controls:=row(v)
		for choice in [[0,"off"],[2,"two"],[4,"four"]]:button(muster_controls,w("muster_"+choice[1]),prep_command.bind({"kind":"warfare_muster","value":choice[0]}),"WarfareMuster_"+str(choice[0]))
	label(v,w("prep_hint"),15)
	var kit: Dictionary=p.rules.projects.living_watch_kits;var shelter: Dictionary=p.rules.projects.watch_shelter
	label(v,w("costs").format({"shelter_wood":shelter.wood,"shelter_work":shelter.work,"kit_wood":kit.wood,"kit_work":kit.work,"blanks":p.rules.living.balance.kit_inputs,"prepare_wood":p.rules.living.balance.prepare_wood}),15)
	label(v,w("kit_hint"),14)
	if p.rules.warfare.active(p.state):render_fortifications(v)
	label(v,p.rules.defense.content.evidence,13)
	if not message.is_empty():label(v,message,16)
	var preparations:=row(v)
	for spec in [["prepare",{"kind":"living_order","id":"prepare","value":1}],["shelter",{"kind":"commission","id":"watch_shelter"}],["kits",{"kind":"commission","id":"living_watch_kits"}],["training",{"kind":"living_order","id":"training","value":not p.state.get("living",{}).get("training",false)}]]:
		var b:=button(preparations,w("prep_"+spec[0]),prep_command.bind(spec[1]),"DefensePrep_"+spec[0]);b.disabled=p.rules.quote(p.state,spec[1]).has("error")
	button(preparations,w("prep_season"),prep_season,"DefensePrepSeason")
	var controls:=row(outer)
	var can_begin: bool=q.count>0 and p.state.food>=q.food and p.rules.living.active(p.state)
	can_begin=can_begin and (p.rules.warfare.threats.ready(p.state,p.rules) if p.rules.warfare.threats.enabled(p.state) else not p.state.get("defense",{}).get("completed",false))
	var begin:=button(controls,w("command_personally") if p.rules.warfare.active(p.state) else w("mobilize"),mobilize.bind(false),"DefenseMobilize")
	begin.disabled=not can_begin
	if p.rules.warfare.active(p.state):
		button(controls,w("delegate_battle"),mobilize.bind(false,"delegated"),"DefenseDelegateEncounter").disabled=not can_begin
		button(controls,w("resolve_quickly"),mobilize.bind(false,"quick"),"DefenseQuickEncounter").disabled=not can_begin
	button(controls,w("practice"),mobilize.bind(true),"DefensePractice")
	button(controls,w("load"),load_battle,"DefenseLoad")
	button(controls,w("save_preparation"),save_preparation,"WarfareSavePreparation")
	button(controls,w("load_preparation"),load_preparation,"WarfareLoadPreparation")
	button(controls,w("preparedness"),preparation_work,"DefensePrepare")
	button(controls,w("return"),close,"DefenseBack")
	if p.state.get("defense",{}).get("completed",false) and not p.rules.warfare.threats.enabled(p.state):label(v,w("completed"),15)
func render_threats(parent: Node) -> void:
	var threats=p.rules.warfare.threats
	if not threats.enabled(p.state):
		label(parent,w("threat_intro"),15)
		button(parent,w("threat_enable"),prep_command.bind({"kind":"warfare_threats"}),"WarfareThreatsEnable")
		return
	var state: Dictionary=p.state.warfare.threats
	if state.pending.is_empty():label(parent,w("threat_quiet").format({"turn":int(state.next_turn)+1}),16)
	else:
		var spec: Dictionary=threats.spec(p.state)
		label(parent,w("threat_warning").format({"title":spec.title,"turn":int(state.pending.due)+1}),19)
		if not state.pending.contact.is_empty():label(parent,w("threat_contact"),14)
		if threats.ready(p.state,p.rules):label(parent,w("threat_ready"),15)
	var reason: String=threats.reason(p.state,p.rules)
	if not reason.is_empty():label(parent,w(reason),15)
	label(parent,w("threat_unknown"),14)
func render_fortifications(parent: Node) -> void:
	label(parent,w("fortifications"),23)
	label(parent,w("fortification_upkeep"),14)
	var allocation: Dictionary=p.rules.assets.allocation(p.state,p.rules)
	for id in p.rules.warfare.forts.projects:
		var spec: Dictionary=p.rules.projects[id]
		label(parent,spec.title,18);label(parent,spec.body,14)
		var done: bool=p.rules.has_project(p.state,id)
		var progress: int=int(spec.work) if done else 0;var pending: bool=false
		for item in p.state.queue:
			if item.id==id:progress=int(item.progress);pending=true
		var crew: Dictionary=allocation.projects.get(id,{"crew":0,"work":0})
		label(parent,w("fortification_cost").format({"wood":spec.wood,"work":spec.work,"progress":progress,"crew":crew.crew,"next":crew.work}),14)
		if done:label(parent,w("fortification_ready" if int(p.state.assets.conditions.watch)>=int(p.rules.assets.balance.condition_threshold) else "fortification_worn"),14)
		var b:=button(parent,spec.title,prep_command.bind({"kind":"commission","id":id}),"WarfareBuild_"+id)
		b.disabled=done or pending or p.rules.quote(p.state,{"kind":"commission","id":id}).has("error")
	label(parent,w("defense_plan"),23);label(parent,w("plan_hint"),14)
	for slot in p.rules.warfare.forts.content.slots:
		var line:=HBoxContainer.new();parent.add_child(line)
		label(line,w("plan_"+slot),16)
		var positions: Array=p.rules.warfare.forts.content.positions.filter(func(place):return slot!="assembly" or float(place.at[1])*100>=int(p.rules.defense.content.deployment[1])*100-int(p.rules.defense.tuning.deployment_depth_cm))
		var index: int=0
		for i in range(positions.size()):
			if positions[i].id==p.state.warfare.plans[slot]:index=i
		button(line,"‹",prep_command.bind({"kind":"warfare_plan","slot":slot,"place":positions[posmod(index-1,positions.size())].id}),"WarfarePlanPrevious_"+slot)
		var place_label:=label(line,positions[index].title,15);place_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button(line,"›",prep_command.bind({"kind":"warfare_plan","slot":slot,"place":positions[(index+1)%positions.size()].id}),"WarfarePlanNext_"+slot)

func save_preparation() -> void:
	message=w("saved_preparation" if Saves.write(p.save_path,p.state,p.rules) else "battle_not_saved");render_preparation()
func load_preparation() -> void:
	var loaded: Dictionary=Saves.read(p.save_path,p.rules)
	if loaded.is_empty():message=w("invalid_save");render_preparation();return
	if p.rules.defense.locked(loaded):load_battle();return
	p.state=loaded;app.show_campaign(p.state,p.rules);open();message=w("loaded");render_preparation()
func prep_command(action: Dictionary) -> void:
	p.dispatch(action);message=p.last_message;prepared_nav={};render_preparation()
func prep_season() -> void:
	p.resolve_season();message=p.last_message;prepared_nav={};render_preparation()
func preparation_work() -> void:
	close();app.visual_commands.select_place("watch")
func mobilize(is_practice: bool,battle_mode: String="direct") -> void:
	message="";practice=is_practice
	var source: Dictionary=p.state.duplicate(true)
	if practice and p.rules.defense.active(source):
		source.defense.completed=false;source.defense.reports=[];source.defense.battle={}
	if practice and p.rules.warfare.active(source):source.warfare.threats={}
	if prepared_nav.is_empty():prepared_nav=Adapter.capture(app.world,p.rules.defense)
	var result: Dictionary=p.rules.command(source,{"kind":"defense_begin","nav":prepared_nav})
	if not result.has("state"):message=w(result.error);render_preparation();return
	if not practice:p.state=result.state
	attach(result.state.defense.battle)
	if battle_mode=="quick":start_quick()
	elif battle_mode=="delegated":set_command_mode("delegated",true)
func attach(b: Dictionary) -> void:
	if host!=null:host.stop()
	host=Host.new();host.attach(p.rules,b);host.run();battle=host.snapshot()
	if is_instance_valid(view):view.free()
	view=View.new();view.world=app.world;app.add_child(view)
	# Civilian households remain separate and sheltered during tactical presentation.
	if is_instance_valid(app.campaign_view):app.campaign_view.visible=false
	selected=[]
	for f in battle.groups:
		if f.side=="watch":selected.append(f.id)
	phase="";quick_ui=false;overhead();render_battle()
func render_battle() -> void:
	clear_ui();phase=battle.phase;quick_ui=false
	app.world.show()
	if is_instance_valid(view):view.show()
	var size_: Vector2=get_viewport_rect().size
	var top:=panel(Vector2(16,14),Vector2(size_.x-32,90))
	summary=label(top,"",21)
	var controls:=row(top)
	if phase=="deployment":
		button(controls,w("command_personally") if has_modes() else w("start"),set_command_mode.bind("direct",true) if has_modes() else invoke.bind({"kind":"defense_start"}),"DefenseStart")
		if has_modes():button(controls,w("delegate_battle"),set_command_mode.bind("delegated",true),"DefenseDelegate")
	elif phase!="ended" and has_modes():
		button(controls,w("take_command" if command_mode()=="delegated" else "handoff_command"),set_command_mode.bind("direct" if command_mode()=="delegated" else "delegated"),"DefenseTakeCommand" if command_mode()=="delegated" else "DefenseDelegate")
	if phase!="ended" and has_modes():button(controls,w("resolve_quickly"),start_quick,"DefenseQuick")
	if phase!="ended":
		button(controls,w("pause"),invoke.bind({"kind":"defense_pause"}),"DefensePause")
		button(controls,w("speed"),invoke.bind({"kind":"defense_speed"}),"DefenseSpeed")
	button(controls,w("save"),save_battle,"DefenseSave")
	button(controls,w("load"),load_battle,"DefenseLoad")
	button(controls,w("overhead"),overhead,"DefenseOverhead");button(controls,w("close"),close_view,"DefenseCloseView")
	if phase=="ended":
		var report_outer:=panel(Vector2(24,144),Vector2(minf(700,size_.x-48),size_.y-168))
		var report_scroll:=ScrollContainer.new();report_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;report_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;report_outer.add_child(report_scroll)
		var v:=VBoxContainer.new();v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_theme_constant_override("separation",8);report_scroll.add_child(v)
		var report: Dictionary=p.rules.defense.outcome(battle,p.rules)
		var remaining_food: int=maxi(0,int(p.state.food)-(int(battle.cost) if practice else 0))
		report.lost=mini(remaining_food,int(report.lost));report.protected=maxi(0,remaining_food-int(report.lost));report.wounded=report.wounded.size();report.outcome=w(report.outcome);report.reason=w(report.reason)
		label(v,w("practice_note") if practice else w("ended"),22)
		label(v,w("report").format(report),19)
		if report.has("aftermath"):
			label(v,w("aftermath_pending"),21);render_report_people(v,report.aftermath);label(v,w("aftermath_boundary"),14)
		else:label(v,w("recovery"),16)
		if not message.is_empty():label(v,message,15)
		button(report_outer,w("finish"),finish,"DefenseFinish")
	else:
		var side_outer:=panel(Vector2(size_.x-330,130),Vector2(314,size_.y-306))
		var side_scroll:=ScrollContainer.new();side_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;side_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;side_outer.add_child(side_scroll)
		var side:=VBoxContainer.new();side.size_flags_horizontal=Control.SIZE_EXPAND_FILL;side.add_theme_constant_override("separation",8);side_scroll.add_child(side)
		label(side,p.rules.warfare.threats.encounters[battle.tactics.encounter.id].title if has_modes() else p.rules.defense.content.subtitle,21)
		if has_modes():
			label(side,w("mode_"+command_mode()),15)
			if command_mode()=="delegated":label(side,w("delegated_notice"),14)
		roster=label(side,"",15)
		var groups:=row(side)
		for f in battle.groups:
			if f.side=="watch":button(groups,w("group").format({"n":f.id.trim_prefix("watch_")}),select_group.bind(f.id),"DefenseSelect_"+f.id)
		button(side,w("select"),select_all,"DefenseSelectAll")
		if battle.has("tactics"):
			var widths:=row(side)
			button(widths,w("column"),issue.bind({"order":"width","width":1}),"DefenseColumn")
			button(widths,w("spread"),issue.bind({"order":"width","width":2}),"DefenseSpread")
			label(side,w("width_hint"),13)
			label(side,w("factor_note"),13)
		var places:=row(side)
		for place in p.rules.defense.content.places:button(places,place.title,defend_place.bind(place.id),"DefensePlace_"+place.id)
		if battle.get("tactics",{}).has("plan"):
			var plans:=row(side)
			for slot in battle.tactics.plan:button(plans,w("plan_"+slot),use_plan.bind(slot),"WarfareUse_"+slot)
		var bottom:=panel(Vector2(16,size_.y-158),Vector2(size_.x-32,142))
		var orders:=row(bottom)
		for id in ["move","attack","advance","hold","defend","withdraw","face"]:button(orders,w("order_"+id),choose.bind(id),"DefenseOrder_"+id)
		button(orders,w("withdraw_all"),withdraw_all,"DefenseWithdrawAll")
		hint=label(bottom,w("controls"),14)
		label(bottom,w("practice_note") if practice else w("live_rules"),13)
func has_modes() -> bool:return battle.get("tactics",{}).has("encounter")
func command_mode() -> String:return battle.get("tactics",{}).get("encounter",{}).get("mode","direct")
func set_command_mode(value: String,start: bool=false) -> void:
	invoke({"kind":"defense_mode","mode":value})
	if start and battle.phase=="deployment":
		if value=="delegated":host.prepare_delegated()
		invoke({"kind":"defense_start"})
	render_battle()
func start_quick() -> void:
	if host==null:return
	var error: String=host.begin_quick()
	if not error.is_empty():message=w(error);return
	dragging=false;panning=false;render_quick()
func render_quick() -> void:
	clear_ui();quick_ui=true;quick_refresh=0
	# The worker keeps fixed rules ticking; the expensive village and people are
	# hidden while the lightweight progress and cancellation controls stay live.
	app.world.hide()
	if is_instance_valid(view):view.hide()
	var size_: Vector2=get_viewport_rect().size
	var box:=panel(Vector2(24,24),Vector2(minf(680,size_.x-48),220))
	summary=label(box,w("resolve_quickly"),24)
	label(box,w("quick_hint"),17)
	if practice:label(box,w("practice_note"),14)
	var buttons:=row(box)
	button(buttons,w("cancel_quick"),cancel_quick,"DefenseQuickCancel")
	button(buttons,w("save"),save_battle,"DefenseSave").disabled=practice
func cancel_quick() -> void:
	if host==null:return
	host.cancel_quick();battle=host.snapshot();message=w("paused");render_battle()
func select_group(id: String) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):selected=[]
	if id not in selected:selected.append(id)
func select_all() -> void:
	selected=[]
	for f in battle.groups:
		if f.side=="watch" and not f.routed and not f.exited and f.hp>0:selected.append(f.id)
func choose(id: String) -> void:
	mode=id;message=w("selected_order").format({"order":w("order_"+id)})
	if id=="hold":issue({"order":"hold"})
func invoke(action: Dictionary) -> void:
	if host==null:return
	var error: String=host.invoke(action)
	message=w(error) if not error.is_empty() else ""
	battle=host.snapshot()
	if battle.phase!=phase:render_battle()
func issue(a: Dictionary) -> void:
	if command_mode()=="delegated":set_command_mode("direct")
	a.kind="defense_order";a.ids=selected.duplicate();invoke(a)
func defend_place(id: String) -> void:mode="defend";issue({"order":"defend","at":battle.nav.places[id]})
func use_plan(slot: String) -> void:
	mode="withdraw" if slot=="fallback" else "move" if slot=="assembly" else "defend"
	issue({"order":mode,"at":battle.tactics.plan[slot]})
func withdraw_all() -> void:select_all();mode="withdraw";issue({"order":"withdraw","at":battle.exits.watch})
func save_battle() -> bool:
	if host==null:return false
	if practice:message=w("practice_save");return false
	host.pause();battle=host.snapshot();p.state.defense.battle=battle.duplicate(true)
	if quick_ui:render_battle()
	var ok: bool=Saves.write(p.save_path,p.state,p.rules)
	message=w("saved" if ok else "battle_not_saved");return ok
func load_battle() -> bool:
	var loaded: Dictionary=Saves.read(p.save_path,p.rules)
	if loaded.is_empty() or not p.rules.defense.locked(loaded):message=w("invalid_save");if_prepare_refresh();return false
	var previous: Dictionary=p.state.duplicate(true)
	var previous_battle: Dictionary=host.snapshot() if host!=null else {}
	if host!=null:host.stop();host=null
	app.show_campaign(loaded,p.rules,true)
	prepared_nav=Adapter.capture(app.world,p.rules.defense)
	if prepared_nav.signature!=loaded.defense.battle.nav.signature:
		app.show_campaign(previous,p.rules,true);prepared_nav={};message=w("invalid_save")
		if not previous_battle.is_empty():attach(previous_battle)
		else:render_preparation()
		return false
	practice=false;p.state=loaded
	active_ui=true;show();app.visual_commands.hide();app.reference_top.hide();app.reference_bottom.hide();p.hide()
	if loaded.defense.battle.phase=="fighting" and not loaded.defense.battle.paused:p.rules.defense.control(loaded.defense.battle,{"kind":"defense_pause"},p.rules)
	attach(loaded.defense.battle);message=w("loaded");return true
func if_prepare_refresh() -> void:
	if battle.is_empty():render_preparation()
func finish() -> void:
	if host==null or battle.phase!="ended":return
	host.stop();battle=host.snapshot()
	if not practice:
		p.state.defense.battle=battle.duplicate(true)
		var result: Dictionary=p.rules.command(p.state,{"kind":"defense_commit"})
		if not result.has("state"):message=w(result.error);return
		p.state=result.state
	# Reconciliation consumed this host. Closing an unresolved later cycle must
	# preserve its snapshot even though earlier reports marked completed=true.
	host=null
	close()
func close() -> void:
	if host!=null:
		host.pause();host.stop()
		if not practice:p.state.defense.battle=host.snapshot()
		host=null
	if is_instance_valid(view):view.free();view=null
	active_ui=false;hide();prepared_nav={};battle={};practice=false;quick_ui=false;app.world.show()
	app.camera.transform=saved_camera;app.yaw=app.camera.rotation.y;app.pitch=app.camera.rotation.x
	app.show_campaign(p.state,p.rules)
	if is_instance_valid(app.campaign_view):app.campaign_view.visible=true
	app.visual_commands.open()
func _exit_tree() -> void:
	if host!=null:host.stop()
func overhead() -> void:app.set_view(Vector3(22,65,52),Vector3(1,1,-12))
func close_view() -> void:
	var at:=Vector3(15,0,-8)
	for id in selected:
		if is_instance_valid(view) and view.anchors.has(id):at=view.anchors[id];break
	app.set_view(at+Vector3(8,9,10),at)
func ground(screen: Vector2) -> Array:
	var origin: Vector3=app.camera.project_ray_origin(screen);var dir: Vector3=app.camera.project_ray_normal(screen)
	for i in range(1,1500):
		var at: Vector3=origin+dir*float(i)*.25
		if at.y<=app.world.floor_height(at.x,at.z):return [roundi(at.x*100),roundi(at.z*100)]
	return []
func picked(screen: Vector2,enemy: bool=false) -> String:
	var best: float=32;var id: String=""
	for f in battle.groups:
		if f.hp<=0 or f.routed or f.exited or (f.side=="raider")!=enemy or not f.revealed or not view.anchors.has(f.id) or app.camera.is_position_behind(view.anchors[f.id]):continue
		var distance: float=app.camera.unproject_position(view.anchors[f.id]).distance_to(screen)
		if distance<best:best=distance;id=f.id
	return id
func _input(event: InputEvent) -> void:
	# A release over a UI control must still release camera panning.
	if active_ui and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_MIDDLE and not event.pressed:panning=false
func handle(event: InputEvent) -> void:
	if battle.is_empty():return
	if quick_ui:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE,KEY_ESCAPE]:cancel_quick()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:invoke({"kind":"defense_pause"})
			KEY_0:overhead()
			KEY_V:close_view()
			KEY_M:choose("move")
			KEY_T:choose("attack")
			KEY_A:
				if event.ctrl_pressed or event.meta_pressed:select_all()
				else:choose("advance")
			KEY_H:choose("hold")
			KEY_D:choose("defend")
			KEY_R:choose("withdraw")
			KEY_F:choose("face")
			KEY_ESCAPE:mode="move";dragging=false
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:
			panning=event.pressed
			if panning:dragging=false
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:app.camera.position+=-app.camera.basis.z*6
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:app.camera.position+=app.camera.basis.z*6
		app.camera.position.y=clampf(app.camera.position.y,app.world.floor_height(app.camera.position.x,app.camera.position.z)+3,180)
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:drag_start=event.position;drag_end=event.position;dragging=true
			elif dragging:
				dragging=false
				if not event.shift_pressed:selected=[]
				if event.position.distance_to(drag_start)<8:
					var id:=picked(event.position)
					if not id.is_empty() and id not in selected:selected.append(id)
				else:
					var rect:=Rect2(drag_start,event.position-drag_start).abs()
					for f in battle.groups:
						if f.side=="watch" and f.hp>0 and not f.routed and not f.exited and view.anchors.has(f.id) and rect.has_point(app.camera.unproject_position(view.anchors[f.id])) and f.id not in selected:selected.append(f.id)
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and not panning and not dragging:
			var target:=picked(event.position,true)
			if mode=="attack" or not target.is_empty():issue({"order":"attack","target":target})
			else:
				var at:=ground(event.position)
				if not at.is_empty():issue({"order":mode,"at":at})
	if event is InputEventMagnifyGesture:
		app.camera.position+=app.camera.basis.z*(1.0-clampf(event.factor,.5,2.0))*12
	if event is InputEventPanGesture:
		app.camera.position+=(-app.camera.basis.x*event.delta.x+Vector3(app.camera.basis.z.x,0,app.camera.basis.z.z)*event.delta.y)*.6
	if event is InputEventMouseMotion:
		drag_end=event.position
		if panning:app.camera.position+=(-app.camera.basis.x*event.relative.x+Vector3(app.camera.basis.z.x,0,app.camera.basis.z.z)*-event.relative.y)*.12
	app.camera.position.x=clampf(app.camera.position.x,float(battle.nav.origin[0])/100-40,float(battle.nav.origin[0]+battle.nav.width*battle.nav.cell)/100+40)
	app.camera.position.z=clampf(app.camera.position.z,float(battle.nav.origin[1])/100-40,float(battle.nav.origin[1]+battle.nav.height*battle.nav.cell)/100+40)
	app.camera.position.y=clampf(app.camera.position.y,app.world.floor_height(app.camera.position.x,app.camera.position.z)+3.01,180)
	queue_redraw()
func _draw() -> void:
	if dragging:draw_rect(Rect2(drag_start,drag_end-drag_start).abs(),Color("dfd397"),false,2)
func _process(delta: float) -> void:
	if not active_ui or host==null:return
	if quick_ui:
		quick_refresh-=delta
		if quick_refresh>0:return
		quick_refresh=.05
		var status: Dictionary=host.status()
		summary.text=w("quick_progress").format({"ticks":status.tick,"limit":status.limit,"seconds":"%.2f"%(float(status.elapsed_ms)/1000)})
		if status.quick:return
		message=w("quick_done").format({"seconds":"%.2f"%(float(status.elapsed_ms)/1000)})
		battle=host.snapshot();render_battle()
	battle=host.snapshot()
	if phase!=battle.phase:render_battle()
	view.update(battle,selected,copy,p.rules.defense.tuning,delta)
	var tuning: Dictionary=p.rules.defense.battle_tuning(battle)
	var status_values: Dictionary={"phase":w(battle.phase),"time":int(battle.tick)*int(tuning.tick_ms)/1000,"capture":float(battle.capture)*tuning.tick_ms/1000,"limit":float(tuning.capture_ticks)*tuning.tick_ms/1000,"speed":battle.speed,"paused":w("paused" if battle.paused else "running")}
	if has_modes():
		status_values.objective=w("objective_"+battle.tactics.encounter.kind)
		summary.text=w("objective_status").format(status_values)
		if battle.tactics.encounter.stage=="carrying":summary.text+=" · "+w("objective_carrying")
	else:summary.text=w("status").format(status_values)
	if phase!="ended":
		roster.text=""
		for f in battle.groups:
			if f.side!="watch":continue
			if f.has("tactical"):
				roster.text+=w("tactical_line").format({"name":w("group").format({"n":f.id.trim_prefix("watch_")}),"order":w("routed") if f.routed else w("order_"+f.order),"morale":f.morale,"fatigue":f.tactical.fatigue,"width":w("column" if f.tactical.effective_width==1 else "spread"),"state":w("tactical_"+f.tactical.blocked) if not f.tactical.blocked.is_empty() else w("engaged" if f.engaged else "group_moving" if f.moving else "group_ready")})+"\n"
				if f.id in selected:roster.text+=w("tactical_factors").format({"skill":f.tactical.skill,"training":f.readiness,"kits":f.kits,"friends":f.tactical.local_friends,"enemies":f.tactical.local_enemies,"cover":100-int(f.tactical.cover_percent),"ground":f.tactical.terrain_percent})+"\n"
				continue
			roster.text+=w("group_line").format({"name":w("group").format({"n":f.id.trim_prefix("watch_")}),"strength":ceili(float(f.hp)/int(p.rules.defense.tuning.hp_per_person)),"total":f.initial,"morale":f.morale,"order":w("routed") if f.routed else w("order_"+f.order)})+"\n"
		hint.text=(message+"\n" if not message.is_empty() else "")+w("controls")

func aftermath_data() -> Dictionary:return p.state.get("warfare",{}).get("aftermath",{})
func home_label(id: String) -> String:
	for home in p.rules.content.households:
		if home.id==id:return home.label
	return id
func recorded_person(id: String) -> Dictionary:
	var person: Dictionary=p.rules.person_by_id(p.state,id)
	if not person.is_empty():return person
	var reports: Array=p.state.get("defense",{}).get("reports",[])
	for index in range(reports.size()-1,-1,-1):
		for row_ in reports[index].get("aftermath",{}).get("participants",[]):
			if row_.id==id:return {"id":id,"name":row_.name,"household":row_.household}
	return {"id":id,"name":id,"household":""}
func person_aftermath_lines(id: String) -> Array:
	var data: Dictionary=aftermath_data();var lines: Array=[]
	if not data.get("people",{}).has(id):return lines
	var memory: Dictionary=data.people[id]
	if int(memory.battles)==0 and not p.state.get("defense",{}).get("recovery",{}).has(id):return lines
	lines.append(w("aftermath_participation").format({"battles":memory.battles,"xp":memory.experience}))
	var remaining: int=int(p.state.get("defense",{}).get("recovery",{}).get(id,0))
	var person: Dictionary=recorded_person(id)
	lines.append(w("aftermath_recovering").format({"remaining":remaining}) if remaining>0 else w("aftermath_ready" if person.get("active",false) else "aftermath_inactive"))
	return lines
func household_aftermath_lines(home: String) -> Array:
	var lines: Array=[]
	for id in aftermath_data().get("people",{}):
		var person: Dictionary=recorded_person(id)
		if person.get("household","")!=home:continue
		var details: Array=person_aftermath_lines(id)
		if not details.is_empty():lines.append(person.name+" · "+" · ".join(details))
	return lines
func aftermath_summary_lines() -> Array:
	var data: Dictionary=aftermath_data()
	if data.is_empty():return []
	var patients: int=p.state.get("defense",{}).get("recovery",{}).size()
	var wanted: int=0;var filled: int=0
	var forecast: Dictionary=p.rules.forecast(p.state)
	for request in forecast.get("assets",{}).get("requests",[]):
		if request.id=="warfare_care":wanted=int(request.wanted);filled=int(request.filled)
	return [w("aftermath_equipment").format({"condition":data.equipment_condition,"kits":p.state.living.kits}),w("aftermath_care").format({"filled":filled,"wanted":wanted,"patients":patients}),w("aftermath_care_short").format({"capacity":filled*int(p.rules.warfare.aftermath.tuning.patients_per_worker),"patients":patients}),w("aftermath_fed" if int(forecast.unfed)==0 else "aftermath_unfed")]
func open_aftermath() -> void:
	if not active_ui:open()
	if not battle.is_empty():return
	phase="aftermath";aftermath_page=0;render_aftermath()
func aftermath_action(action: Dictionary) -> void:
	p.dispatch(action);message=p.last_message;prepared_nav={};render_aftermath()
func aftermath_season() -> void:
	p.resolve_season();message=p.last_message;prepared_nav={};render_aftermath()
func aftermath_work() -> void:
	close();app.visual_commands.select_place("workroom")
func show_preparations() -> void:phase="prepare";render_preparation()
func render_aftermath() -> void:
	clear_ui();phase="aftermath"
	var size_: Vector2=get_viewport_rect().size
	var outer:=panel(Vector2(22,18),Vector2(minf(780,size_.x-44),size_.y-36))
	var scroll:=ScrollContainer.new();scroll.name="AftermathScroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;outer.add_child(scroll)
	var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",9);scroll.add_child(body)
	label(body,w("aftermath_title"),28);label(body,w("aftermath_intro"),16);label(body,w("aftermath_boundary"),14)
	var data: Dictionary=aftermath_data()
	if not data.is_empty():
		for line in aftermath_summary_lines():label(body,line,16)
		var tuning: Dictionary=p.rules.warfare.aftermath.tuning
		label(body,w("aftermath_care_rule").format({"patients":tuning.patients_per_worker}),14)
		label(body,w("aftermath_equipment_rule").format({"gain":tuning.equipment_repair_gain}),14)
		label(body,w("aftermath_repair_state").format({"blanks":p.state.living.blanks,"state":w("aftermath_care_enabled" if p.state.living.repair else "aftermath_care_disabled")}),15)
		label(body,w("aftermath_recovery_route"),15)
		var decisions:=row(body)
		for item in [[w("aftermath_care_off" if data.care else "aftermath_care_on"),{"kind":"warfare_care","enabled":not data.care},"AftermathCare"],[w("aftermath_release_watch"),{"kind":"warfare_muster","value":0},"AftermathReleaseWatch"],[w("aftermath_prepare"),{"kind":"living_order","id":"prepare","value":maxi(1,int(p.state.living.prepare))},"AftermathPrepare"],[w("aftermath_repair_off" if p.state.living.repair else "aftermath_repair_on"),{"kind":"living_order","id":"repair","value":not p.state.living.repair},"AftermathRepair"]]:
			var control:=button(decisions,item[0],aftermath_action.bind(item[1]),item[2])
			var quote: Dictionary=p.rules.quote(p.state,item[1]);control.disabled=quote.has("error")
			if control.disabled:control.tooltip_text=w(quote.error)
		label(body,w("aftermath_roster"),23)
		label(body,w("aftermath_experience_rule").format({"step":tuning.experience_per_skill}),14)
		for id in data.people:
			var details: Array=person_aftermath_lines(id)
			if details.is_empty():continue
			var person: Dictionary=recorded_person(id)
			label(body,w("aftermath_person").format({"name":person.name,"household":home_label(person.get("household",""))}),18)
			for line in details:label(body,line,15)
			var home: Dictionary=p.state.households.homes.get(person.get("household",""),{})
			if not home.is_empty():label(body,w("aftermath_household").format({"stress":home.stress}),14)
	label(body,w("aftermath_history"),23)
	var reports: Array=p.state.get("defense",{}).get("reports",[])
	if reports.is_empty():label(body,w("aftermath_empty"),16)
	aftermath_page=clampi(aftermath_page,0,maxi(0,(reports.size()-1)/4))
	var latest: int=reports.size()-aftermath_page*4
	for index in range(latest-1,maxi(-1,latest-5),-1):render_history_report(body,reports[index])
	if not reports.is_empty():
		label(body,w("aftermath_page").format({"shown":mini(4,latest),"total":reports.size()}),14)
		var pages:=row(body)
		button(pages,w("aftermath_newer"),turn_aftermath_page.bind(-1),"AftermathNewer").disabled=aftermath_page==0
		button(pages,w("aftermath_older"),turn_aftermath_page.bind(1),"AftermathOlder").disabled=latest<=4
	if not message.is_empty():label(body,message,15)
	var controls:=row(outer)
	button(controls,w("prep_season"),aftermath_season,"AftermathSeason")
	button(controls,w("aftermath_readiness"),show_preparations,"AftermathPreparations")
	button(controls,w("aftermath_open_work"),aftermath_work,"AftermathWork")
	button(controls,w("return"),close,"AftermathBack")
func render_history_report(parent: Node,report: Dictionary) -> void:
	parent.add_child(HSeparator.new())
	var meta: Dictionary=report.get("aftermath",{})
	if meta.is_empty():label(parent,w("last_report").format({"outcome":w(report.outcome),"lost":report.lost,"wounded":report.wounded.size()}),18)
	else:
		var encounter: Dictionary=p.rules.warfare.threats.encounters.get(meta.encounter,{})
		label(parent,w("aftermath_record").format({"turn":int(meta.turn)+1,"title":encounter.get("title",p.rules.defense.content.subtitle),"outcome":w(report.outcome)}),20)
	var text: Dictionary=report.duplicate(true);text.outcome=w(report.outcome);text.reason=w(report.reason);text.wounded=report.wounded.size()
	label(parent,w("report").format(text),16)
	if not meta.is_empty():render_report_people(parent,meta)
func render_report_people(parent: Node,meta: Dictionary) -> void:
	label(parent,w("aftermath_kit_report").format({"before":meta.condition_before,"after":meta.condition_after,"wear":meta.kit_wear}),15)
	for participant in meta.participants:
		var person: Dictionary=recorded_person(participant.id)
		label(parent,w("aftermath_person").format({"name":participant.name if not participant.name.is_empty() else person.name,"household":home_label(participant.household if not participant.household.is_empty() else person.get("household",""))}),18)
		label(parent,w("aftermath_result").format({"injury":w("aftermath_injury_"+participant.injury),"recovery":participant.recovery,"experience":participant.experience}),15)
		label(parent,w("aftermath_engaged" if participant.engaged else "aftermath_not_engaged")+" · "+w("aftermath_equipped" if participant.equipped else "aftermath_unequipped"),14)
		if int(meta.turn)>=0 and int(participant.stress)>0:label(parent,w("aftermath_stress").format({"stress":participant.stress}),14)

func turn_aftermath_page(direction: int) -> void:aftermath_page+=direction;render_aftermath()
