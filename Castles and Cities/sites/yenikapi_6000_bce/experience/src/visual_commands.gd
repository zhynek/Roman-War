extends Control
## Presentation adapter: every purchase/order uses the existing public quote/command.
const Icon=preload("res://src/place_icon.gd")
# Read-only acceptance observers; all authority remains in public commands.
signal command_applied(action: Dictionary)
signal save_finished(writing: bool)
var app
var p
var copy: Dictionary
var enabled: bool=true
var selected: String="stores"
var page: String="projects"
var detail: Dictionary={}
var overlay: String=""
var lesson: int=0
var dock: PanelContainer
var header: PanelContainer
var sheet: PanelContainer
var forecast: Dictionary={}
var _pending: bool=false
var _busy: bool=false
var timings: Dictionary={}
var preview_meshes: Dictionary={}
var preview_stage: String="planned"
var projects=preload("res://src/project_presentation.gd").new()
var room_mode: bool=false
var return_view: Dictionary={}
var expanded_details: bool=false
var _forecast_key: int=0
var _project_meshes: Dictionary={}
var _ui_signature: String=""
func lw(id: String) -> String:return p.rules.lifecycle.content.strings.get(id,id)
func cw(id: String) -> String:return projects.copy.ui.get(id,id)
func room():return app.campaign_view.planning_room if is_instance_valid(app.campaign_view) else null
func construction():return app.campaign_view.construction_view if is_instance_valid(app.campaign_view) else null

func configure(owner_app) -> void:
	app=owner_app;p=app.campaign
	copy=p.rules.canonical(JSON.parse_string(FileAccess.get_file_as_string("res://data/visual_commands.json")))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.visibility_changed.connect(sync)
	get_viewport().size_changed.connect(schedule_refresh)
	refresh()
func w(id: String) -> String:return copy.ui.get(id,id)
func style(color: String="203638") -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=Color(color);box.bg_color.a=.97
	box.border_color=Color("527069");box.set_border_width_all(1);box.set_corner_radius_all(9);box.set_content_margin_all(12)
	return box
func label(text_: String,font_size: int=15) -> Label:
	var l:=Label.new();l.text=text_;l.add_theme_font_size_override("font_size",font_size);l.add_theme_color_override("font_color",Color("eee6cf"));return l
func paragraph(parent: Node,text_: String,font_size: int=15) -> Label:
	var l:=label(text_,font_size);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(l);return l
func button(text_: String,callback: Callable,id: String="") -> Button:
	var b:=Button.new();b.text=text_;b.name=id if id!="" else "Action";b.custom_minimum_size.y=36
	b.add_theme_font_size_override("font_size",15);b.add_theme_stylebox_override("normal",style());b.add_theme_stylebox_override("hover",style("3b5551"));b.add_theme_stylebox_override("pressed",style("52665a"));b.add_theme_stylebox_override("disabled",style("253332"))
	b.pressed.connect(callback);return b
func icon_button(title: String,kind: String,subtitle: String,callback: Callable,id: String,wide: bool=true) -> Button:
	var b:=button("",callback,id);b.tooltip_text=title
	b.custom_minimum_size=Vector2(162 if wide else 110,133 if wide else 89)
	var v:=VBoxContainer.new();v.mouse_filter=Control.MOUSE_FILTER_IGNORE;v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);v.offset_left=8;v.offset_right=-8;v.offset_top=4;v.offset_bottom=-4;v.add_theme_constant_override("separation",0);b.add_child(v)
	var icon:=Icon.new();icon.kind=kind;icon.custom_minimum_size.y=67 if wide else 48;v.add_child(icon)
	var l:=label(title,15 if wide else 14);l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;l.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;v.add_child(l)
	var sub:=label(subtitle,12);sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;sub.add_theme_color_override("font_color",Color("b9cabe"));sub.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;v.add_child(sub)
	return b
func row(parent: Node) -> HBoxContainer:
	var r:=HBoxContainer.new();r.add_theme_constant_override("separation",8);parent.add_child(r);return r
func scroller(parent: Node) -> VBoxContainer:
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(scroll)
	var v:=VBoxContainer.new();v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_theme_constant_override("separation",10);scroll.add_child(v);return v
func sync() -> void:
	visible=enabled and not p.visible
	var modern: bool=visible and app.campaign_mode
	app.reference_top.visible=not modern
	app.reference_bottom.visible=not visible
	var scale_size:=Vector2i.ZERO if visible and app.campaign_mode else Vector2i(1600,1000)
	if get_window().content_scale_size!=scale_size:get_window().content_scale_size=scale_size
	if visible:schedule_refresh()
func open() -> void:
	enabled=true;p.hide();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;app.hud.show()
	if not p.state.is_empty():app.show_campaign(p.state,p.rules)
	sync();refresh()
func legacy(tab: int=0) -> void:
	enabled=false;p.open()
	if is_instance_valid(p.tabs):p.tabs.current_tab=tab
	sync()
func schedule_refresh() -> void:
	if _pending:return
	_pending=true;flush_refresh.call_deferred()
func flush_refresh() -> void:
	if _pending:refresh()
func refresh() -> void:
	_pending=false
	visible=enabled and not p.visible
	if not visible:return
	app.reference_bottom.hide()
	var start: int=Time.get_ticks_usec()
	var signature: String=str([hash(p.state),p.last_message,app.campaign_mode,get_viewport_rect().size,selected,page,detail,overlay,lesson,preview_stage,expanded_details,room_mode,room().selected if is_instance_valid(room()) else "",room().page if is_instance_valid(room()) else 0])
	if signature==_ui_signature and is_instance_valid(dock):return
	_ui_signature=signature
	for child in get_children():remove_child(child);child.queue_free()
	header=null;sheet=null
	dock=PanelContainer.new();dock.name="VisualDock";dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);dock.offset_left=18;dock.offset_right=-18;dock.offset_top=-356;dock.offset_bottom=-14;dock.add_theme_stylebox_override("panel",style("142b2e"));add_child(dock)
	var v:=VBoxContainer.new();v.add_theme_constant_override("separation",8);dock.add_child(v)
	if p.state.is_empty() or not app.campaign_mode:
		paragraph(v,copy.title,25);paragraph(v,copy.subtitle,17)
		if overlay=="new_confirm":
			paragraph(v,w("overwrite"),18);v.add_child(button(w("start"),begin,"VisualConfirmNew"));v.add_child(button(w("back"),close_sheet,"VisualCancelNew"));return
		var cards:=row(v)
		cards.add_child(icon_button(w("start"),"homes",w("new_title"),start_new,"VisualNew"))
		cards.add_child(icon_button(w("resume"),"stores",w("load"),load_saved,"VisualLoad"))
		cards.add_child(icon_button(w("ledger"),"guide",w("legacy"),legacy,"VisualLegacy"))
		if not p.state.is_empty():cards.add_child(icon_button(w("adopt"),"yard","",open,"VisualResume"))
		paragraph(v,w("new_note"),14)
		return
	var state_key: int=hash(p.state)
	if state_key!=_forecast_key or forecast.is_empty():forecast=p.rules.forecast(p.state);_forecast_key=state_key
	app.reference_top.hide();app.reference_bottom.hide()
	if get_window().content_scale_size!=Vector2i.ZERO:get_window().content_scale_size=Vector2i.ZERO
	build_header()
	var compact: bool=not detail.is_empty() or overlay!="" or room_mode
	if compact:dock.offset_top=-126
	if room_mode and detail.is_empty() and overlay=="":
		dock.offset_top=-132
		var heading:=row(v)
		heading.add_child(button(cw("board"),look_at_board,"PlanningBoard"))
		heading.add_child(button(cw("previous"),func():room().turn_page(-1);refresh(),"PlanningPrevious"))
		heading.add_child(button(cw("next"),func():room().turn_page(1);refresh(),"PlanningNext"))
		heading.add_child(button(cw("all_projects"),show_overlay.bind("oversight"),"PlanningAll"))
		heading.add_child(button(cw("leave_room"),leave_room,"PlanningLeave"))
		paragraph(v,cw("room_selected").format({"title":p.rules.projects[room().selected].title})+" · "+cw("plan_hint"),14)
	if not compact:
		var heading:=row(v)
		var title:=label(copy.assets.filter(func(a):return a.id==selected)[0].label,22);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
		for id in ["projects","orders","queue"]:
			var b:=button(w(id),choose_page.bind(id),"VisualPage_"+id);b.disabled=page==id;heading.add_child(b)
		heading.add_child(button(w("visit"),visit,"VisualVisit"));heading.add_child(button(w("inspect"),inspect,"VisualInspect"))
		if p.rules.assets.active(p.state):
			var count: int=0
			for request in forecast.assets.requests:
				if request.asset==selected:count+=int(request.filled)
			paragraph(v,w("condition_line").format({"condition":p.state.assets.conditions[selected],"workers":count}),13)
		var action_scroll:=ScrollContainer.new();action_scroll.name="VisualActions";action_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;action_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;v.add_child(action_scroll)
		var cards:=row(action_scroll)
		if not p.rules.assets.active(p.state):
			paragraph(cards,w("legacy"),14);cards.add_child(button(w("ledger"),legacy,"VisualOldSave"))
		elif page=="projects":
			for id in project_ids(selected):cards.add_child(project_card(id))
			if cards.get_child_count()==0:cards.add_child(icon_button(w("incident"),"warning",w("begin_incident"),show_overlay.bind("incident"),"VisualEmptyIncident"))
		elif page=="orders":build_orders(cards)
		else:
			for item in p.state.queue:cards.add_child(project_card(item.id))
			if p.state.queue.is_empty():paragraph(cards,w("no_queue"),18)
	if not room_mode or not detail.is_empty() or overlay!="":
		var places:=row(v)
		for a in copy.assets:
			var place:=icon_button(a.label,a.icon,a.hint,select_place.bind(a.id),"VisualPlace_"+a.id,false);place.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			if a.id==selected:place.add_theme_stylebox_override("normal",style("496255"))
			places.add_child(place)
	if not detail.is_empty() or overlay!="":build_sheet()
	timings.refresh_us=Time.get_ticks_usec()-start
func build_header() -> void:
	header=PanelContainer.new();header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);header.offset_left=18;header.offset_right=-18;header.offset_top=14;header.add_theme_stylebox_override("panel",style("142b2e"));add_child(header)
	var v:=VBoxContainer.new();header.add_child(v)
	var r:=row(v)
	var season:=label(w("season_index").format({"year":1+int(p.state.turn)/4,"season":p.copy.seasons[int(p.state.turn)%4]}),19);r.add_child(season)
	for stat in [["food",p.state.food],["wood",p.state.wood],["people",p.rules.people(p.state).size()],["blanks",p.state.get("living",{}).get("blanks",0)]]:
		var icon:=Icon.new();icon.kind=stat[0];icon.custom_minimum_size=Vector2(36,30);r.add_child(icon);var l:=label(str(stat[1]),19);l.tooltip_text=w(stat[0]);r.add_child(l)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;r.add_child(spacer)
	var role:=OptionButton.new();role.name="VisualRole"
	for id in ["god","steward","watch"]:role.add_item(p.copy[id])
	role.select(["god","steward","watch"].find(p.state.role));role.item_selected.connect(func(i):execute({"kind":"role","role":["god","steward","watch"][i]}));r.add_child(role)
	r.add_child(button(w("save"),save,"VisualSave"));r.add_child(button(w("load"),load_saved,"VisualLoad"));r.add_child(button(w("menu"),show_overlay.bind("menu"),"VisualMenu"))
	var controls:=HFlowContainer.new();v.add_child(controls)
	controls.add_child(button(cw("oversight"),show_overlay.bind("oversight"),"VisualOversight"))
	var civic_title: String=p.rules.lifecycle.stages[p.rules.lifecycle.stage(p.state,p.rules)].title if p.rules.lifecycle.active(p.state) else lw("title")
	var civic:=button(civic_title,show_overlay.bind("lifecycle"),"VisualLifecycle");civic.tooltip_text=lw("title");controls.add_child(civic)
	for c in [["expand","growth"],["learn","help"],["incident","incident"],["report","report"]]:controls.add_child(button(w(c[0]),show_overlay.bind(c[1]),"Visual_"+c[1]))
	controls.add_child(button(w("overview"),app.overview,"VisualAerial"))
	var next:=button(w("season"),advance,"VisualSeason");next.size_flags_horizontal=Control.SIZE_EXPAND_FILL;next.add_theme_stylebox_override("normal",style("617055"));controls.add_child(next)
	var f:=label(w("forecast")+": "+w("food_delta").format({"food":forecast.food,"delta":"%+d"%int(forecast.food_delta)})+"  ·  "+w("work_total").format(forecast),14);v.add_child(f)
	if forecast.unfed>0:f.add_theme_color_override("font_color",Color("f2ae8e"));f.text+="  ·  "+w("shortage").format({"count":forecast.unfed})
	if p.rules.incidents.active(p.state):
		var e: Dictionary=p.rules.incidents.current(p.state)
		if not e.is_empty() and e.known>=0:
			var warning:=button(p.incident_panel.notice(),show_overlay.bind("incident"),"VisualWarning");warning.tooltip_text=p.incident_panel.notice();warning.clip_text=true;warning.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;warning.add_theme_stylebox_override("normal",style("645137"));v.add_child(warning)
	if p.last_message!="":paragraph(v,p.last_message,13)
func project_ids(asset: String) -> Array:
	var ids: Array=[]
	for id in p.rules.projects:
		if p.rules.lifecycle.project_specs.has(id) and (not p.rules.lifecycle.active(p.state) or not p.rules.lifecycle.available(p.state,id)):continue
		if p.rules.assets.project_assets.get(id,"")!=asset:continue
		if p.rules.land.active(p.state) and id in p.rules.land.content.legacy_projects and not p.rules.land.committed(p.state,id,p.rules):continue
		if id in p.rules.living.content.projects.map(func(a):return a.id) and not p.rules.living.active(p.state):continue
		if p.rules.incidents.project_specs.has(id):
			var e: Dictionary=p.rules.incidents.current(p.state)
			if e.is_empty() or e.known<0:continue
			var spec: Dictionary=p.rules.incidents.specs[e.id]
			if id!=spec.prepare and id!=spec.repair:continue
			if id==spec.repair and e.outcome.is_empty():continue
		ids.append(id)
	return ids
func project_icon(id: String) -> String:
	if "access" in id or "approach" in id or "lane" in id:return "path"
	if "kits" in id:return "kits"
	return p.rules.assets.project_assets.get(id,selected)
func queued(id: String) -> Dictionary:
	for item in p.state.queue:
		if item.id==id:return item
	return {}
func project_status(id: String) -> String:
	if p.rules.has_project(p.state,id):return w("complete")
	var q:=queued(id)
	if not q.is_empty():return (w("paused")+" · " if p.state.get("assets",{}).get("initiatives",{}).get(id,{}).get("paused",false) else "")+w("progress").format({"done":q.progress,"total":p.rules.projects[id].work})
	return w("locked") if p.rules.quote(p.state,{"kind":"commission","id":id}).has("error") else w("ready")
func project_card(id: String) -> Button:
	var spec: Dictionary=p.rules.projects[id]
	var b:=icon_button(copy.project_labels.get(id,spec.title),project_icon(id),project_status(id),show_project.bind(id),"VisualProject_"+id)
	if p.rules.lifecycle.project_specs.has(id):
		b.custom_minimum_size=Vector2(270,158)
		var title: Label=b.get_child(0).get_child(1)
		title.text=spec.title
		title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		title.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING
	b.tooltip_text=spec.title+"\n"+w("cost").format({"wood":spec.wood,"blanks":project_blanks(id)})+"\n"+w("effort").format(spec)
	return b
func project_blanks(id: String) -> int:
	if p.rules.incidents.project_specs.has(id):return int(p.rules.incidents.project_specs[id].blanks)
	if id=="living_watch_kits":return int(p.rules.balance.living.kit_inputs)
	return 0
func select_place(id: String) -> void:
	selected=id;detail={};overlay="";room_mode=false;refresh()
func choose_page(id: String) -> void:page=id;detail={};overlay="";refresh()
func show_project(id: String) -> void:
	preview_stage="current" if not queued(id).is_empty() or p.rules.has_project(p.state,id) else "planned"
	expanded_details=false;selected=p.rules.assets.project_assets[id];page="projects";detail={"kind":"project","id":id};overlay=""
	if is_instance_valid(construction()):construction().select(id)
	if room_mode and is_instance_valid(room()):room().choose(id)
	refresh()
func show_order(kind: String,id: String) -> void:detail={"kind":kind,"id":id};overlay="";refresh()
func show_overlay(id: String) -> void:overlay=id;detail={};refresh()
func close_sheet() -> void:
	detail={};overlay="";refresh()
func build_orders(cards: HBoxContainer) -> void:
	for principle in p.asset_panel.copy.principles:
		if principle.asset!=selected:continue
		var value: int=p.rules.assets.principle(p.state,principle.id)
		cards.add_child(icon_button(copy.principle_labels[principle.id],selected,principle.options[value],show_order.bind("principle",principle.id),"VisualPrinciple_"+principle.id))
	if p.rules.living.active(p.state):
		for order in copy.living_orders:
			if order.asset!=selected:continue
			var i: int=order.values.find(p.state.living[order.id])
			cards.add_child(icon_button(order.label,order.icon,order.labels[i],show_order.bind("living",order.id),"VisualOrder_"+order.id))
	cards.add_child(icon_button(w("maintain"),selected,w("on") if p.state.assets.maintenance[selected] else w("off"),show_order.bind("maintenance",selected),"VisualMaintenance"))
	if selected=="yard" and p.rules.land.active(p.state):cards.add_child(icon_button(w("access"),"path",w("on") if p.state.land.access_enabled else w("off"),show_order.bind("access",""),"VisualAccess"))
	for id in p.rules.assets.assets[selected].orders:
		var order: Dictionary=p.rules.households.orders[id]
		cards.add_child(icon_button(order.label,selected,w("on") if p.state.households.orders[id] else w("off"),show_order.bind("household",id),"VisualHousehold_"+id))
func build_sheet() -> void:
	sheet=PanelContainer.new();sheet.name="VisualSheet";sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);sheet.offset_left=32;sheet.offset_right=-32;sheet.offset_top=210;sheet.offset_bottom=-140;sheet.add_theme_stylebox_override("panel",style("1e3436"));add_child(sheet)
	header.resized.connect(layout_sheet)
	layout_sheet.call_deferred()
	var v:=VBoxContainer.new();sheet.add_child(v)
	var r:=row(v);var title:=label(lw("title") if overlay=="lifecycle" else (cw(overlay) if overlay=="oversight" else (w(overlay) if overlay!="" else w("details"))),20);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;r.add_child(title);r.add_child(button(w("close"),close_sheet,"VisualClose"))
	var body:=scroller(v)
	if not detail.is_empty():
		if detail.kind=="project":project_detail(body,detail.id)
		else:order_detail(body,detail.kind,detail.id)
	elif overlay=="oversight":project_overview(body)
	elif overlay=="growth":growth(body)
	elif overlay=="lifecycle":lifecycle(body)
	elif overlay=="help":help(body)
	elif overlay=="incident":incidents(body)
	elif overlay=="knowledge":knowledge(body)
	elif overlay=="report":report(body)
	elif overlay=="new_confirm":
		paragraph(body,w("overwrite"),20)
		body.add_child(button(w("start"),begin,"VisualConfirmNew"))
		body.add_child(button(w("back"),show_overlay.bind("menu"),"VisualCancelNew"))
	elif overlay=="menu":
		body.add_child(button(w("start"),start_new,"VisualNew"))
		body.add_child(button(w("reference"),func():enabled=false;app.show_reference();sync(),"VisualReference"))
		body.add_child(button(w("ledger"),legacy,"VisualMenuLedger"))
func command_button(parent: Node,text_: String,action: Dictionary,id: String) -> Button:
	var quote: Dictionary=p.rules.quote(p.state,action)
	var b:=button(text_,execute.bind(action),id);parent.add_child(b)
	if quote.has("error"):
		b.disabled=true;b.tooltip_text=p.reason(quote.error);paragraph(parent,b.tooltip_text,14)
	return b
func project_detail(body: VBoxContainer,id: String) -> void:
	var spec: Dictionary=p.rules.projects[id]
	var top:=row(body)
	var d: Dictionary=projects.describe(p.state,p.rules,id,forecast,expanded_details)
	var mesh: Mesh=site_preview(id) if d.queued and preview_stage=="current" else preview_mesh(id,preview_stage=="planned")
	if mesh!=null:
		var model_column:=VBoxContainer.new();top.add_child(model_column)
		var model=preload("res://src/place_preview.gd").new();model.name="ProjectModel";model_column.add_child(model);model.show_mesh(mesh)
		paragraph(model_column,d.stage_label if d.queued and preview_stage=="current" else (w("model_future") if has_building_change(id) and preview_stage=="planned" else w("model_current")),12)

	else:
		var icon:=Icon.new();icon.kind=project_icon(id);icon.custom_minimum_size=Vector2(125,95);top.add_child(icon)
	var brief:=VBoxContainer.new();brief.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(brief)
	paragraph(brief,spec.title,23)
	paragraph(brief,cw("stage").format({"stage":d.stage_label,"percent":d.progress*100/d.total}) if d.committed else cw("quote").format({"wood":d.cost_wood,"blanks":d.cost_blanks}),17)
	if p.rules.lifecycle.project_specs.has(id) and not d.committed:
		var reserves:=paragraph(brief,lw("stocks_after").format({"food":p.state.food,"wood":int(p.state.wood)-int(d.cost_wood)}),15);reserves.name="ProjectReserves"
	var progress:=ProgressBar.new();progress.name="ProjectProgress";progress.max_value=d.total;progress.value=d.progress;progress.custom_minimum_size.y=18;brief.add_child(progress)
	paragraph(brief,cw("progress").format({"done":d.progress,"total":d.total}),15)
	paragraph(brief,project_cause(d),15)
	project_flow(body,d)
	body.add_child(button(w("visit_site"),visit_project.bind(id),"VisualVisitProject"))
	if has_building_change(id) or d.queued:
		var stages:=row(body)
		for stage in ["current","planned"]:
			var b:=button(w("view_"+stage),func():preview_stage=stage;refresh(),"VisualStage_"+stage);b.disabled=preview_stage==stage;stages.add_child(b)
		if mesh==null:paragraph(body,w("model_empty"),14)
	if p.rules.lifecycle.project_specs.has(id):lifecycle_project(body,id)
	if not spec.requires.is_empty():
		paragraph(body,cw("prerequisites"),14)
		var dependencies:=HFlowContainer.new();body.add_child(dependencies)
		for key in spec.requires:dependencies.add_child(button(("✓ " if p.rules.has_project(p.state,key) else "→ ")+p.rules.projects[key].title,show_project.bind(key),"ProjectRequires_"+key))
	if p.rules.land.active(p.state) and id in ["land_court_home","land_hearth_home"]:
		body.add_child(button(cw("helpful").format({"title":p.rules.projects.land_adapt_workroom.title}),show_project.bind("land_adapt_workroom"),"ProjectHelpful"))
	body.add_child(button(cw("less_details") if expanded_details else cw("details"),func():expanded_details=not expanded_details;refresh(),"ProjectMore"))
	if expanded_details:
		paragraph(body,projects.text_for(p.rules,id,spec.body),15);paragraph(body,cw("investment"),14);paragraph(body,projects.copy.interpretation,13)
		paragraph(body,str(d.affected),13)
		for citizen in p.state.citizens:
			if citizen.id in d.assigned:paragraph(body,citizen.name+" · "+citizen.household,13)
	var q:=queued(id)
	if p.rules.has_project(p.state,id):paragraph(body,cw("completed_rule"),15);return
	if q.is_empty():command_button(body,w("confirm"),{"kind":"commission","id":id},"VisualCommission");paragraph(body,w("paid"),13)
	else:
		if not p.rules.assets.active(p.state):
			paragraph(body,cw("manual"));body.add_child(button(w("ledger"),legacy,"ProjectManual"));return
		var initiative: Dictionary=p.state.assets.initiatives[id]
		var controls:=HBoxContainer.new();body.add_child(controls)
		for key in ["crew","priority"]:
			controls.add_child(label(w(key)))
			var spin:=SpinBox.new();spin.name="Visual_"+key;spin.min_value=0 if key=="crew" else 1;spin.max_value=p.rules.assets.balance.max_crew if key=="crew" else 3;spin.value=initiative[key];spin.custom_minimum_size.x=110;controls.add_child(spin)
			spin.editable=p.rules.permitted(p.state,spec.role)
			spin.value_changed.connect(func(value):
				var a: Dictionary={"kind":"asset_project","id":id,"crew":initiative.crew,"priority":initiative.priority,"paused":initiative.paused};a[key]=int(value);execute(a))
		command_button(body,w("unpause") if initiative.paused else w("pause"),{"kind":"asset_project","id":id,"crew":initiative.crew,"priority":initiative.priority,"paused":not initiative.paused},"VisualPause")
		paragraph(body,w("refund").format({"wood":int(spec.wood)*(int(spec.work)-int(q.progress))/int(spec.work),"blanks":project_blanks(id)*(int(spec.work)-int(q.progress))/int(spec.work)}),14)
		command_button(body,w("cancel"),{"kind":"cancel","id":id},"VisualCancel")
func order_detail(body: VBoxContainer,kind: String,id: String) -> void:
	paragraph(body,w("standing"),16)
	var options: Array=[];var values: Array=[];var current: Variant
	var command: Dictionary
	if kind=="principle":
		var spec: Dictionary=p.asset_panel.copy.principles.filter(func(a):return a.id==id)[0]
		paragraph(body,spec.label,22);paragraph(body,spec.body);options=spec.options;current=p.rules.assets.principle(p.state,id);command={"kind":"asset_principle","id":id}
		for i in range(options.size()):values.append(i)
	elif kind=="living":
		var spec: Dictionary=copy.living_orders.filter(func(a):return a.id==id)[0]
		paragraph(body,spec.label,22);paragraph(body,spec.detail);options=spec.labels;values=spec.values;current=p.state.living[id];command={"kind":"living_order","id":id}
	else:
		options=[w("off"),w("on")];values=[false,true]
		match kind:
			"maintenance":paragraph(body,w("maintenance"));current=p.state.assets.maintenance[id];command={"kind":"asset_maintenance","id":id}
			"access":paragraph(body,w("access_note"));current=p.state.land.access_enabled;command={"kind":"land_access"}
			"household":
				paragraph(body,p.rules.households.orders[id].description);paragraph(body,w("cost").format({"wood":0 if p.state.households.investments[id] else p.rules.households.balance.costs[id],"blanks":0}));current=p.state.households.orders[id];command={"kind":"household_order","id":id}
	for i in range(options.size()):
		var a: Dictionary=command.duplicate();a["value" if kind in ["living","principle"] else "enabled"]=values[i]
		var b:=command_button(body,options[i]+(" · "+w("current") if values[i]==current else ""),a,"VisualChoice_"+str(i));b.disabled=b.disabled or values[i]==current
func growth(body: VBoxContainer) -> void:
	lifecycle(body)
	body.add_child(HSeparator.new())
	paragraph(body,w("growth_note"))
	if not p.rules.land.active(p.state):paragraph(body,w("legacy"));return
	for chain in copy.chains:
		paragraph(body,w(chain.id),21);paragraph(body,chain.note,14)
		var r:=row(body)
		for i in range(chain.projects.size()):
			if i>0:r.add_child(label(w(chain.links[i-1]),23))
			r.add_child(project_card(chain.projects[i]))
	var review:=button(w("growth_review"),func():legacy(0),"VisualGrowthReview");body.add_child(review)
func lifecycle(body: VBoxContainer) -> void:
	var life=p.rules.lifecycle
	if overlay=="growth":paragraph(body,lw("title"),21)
	if not life.active(p.state):
		paragraph(body,lw("adoption"),17)
		var missing: Array=[]
		for extension in [["assets",p.rules.assets.active(p.state),4],["land",p.rules.land.active(p.state),7],["living",p.rules.living.active(p.state),8]]:
			if not extension[1]:missing.append(extension)
		if not missing.is_empty():
			paragraph(body,lw("missing_extensions"),15)
			for extension in missing:body.add_child(button(lw(extension[0]),legacy.bind(extension[2]),"LifecycleExtension_"+extension[0]))
		command_button(body,lw("adopt"),{"kind":"lifecycle_begin"},"VisualBeginLifecycle")
		lifecycle_ladder(body,"")
		return
	if not life.town_active(p.state):
		paragraph(body,lw("town_adoption"),15)
		command_button(body,lw("town_adopt"),{"kind":"lifecycle_town_begin"},"VisualBeginTown")
	var status: Dictionary=life.status(p.state,p.rules)
	paragraph(body,lw("stage_line").format({"stage":status.stage_name}),23)
	paragraph(body,lw("continuity"),15)
	if status.recognition!="":paragraph(body,lw("recognized"),16)
	if status.project!="":
		if queued(status.project).is_empty():lifecycle_factors(body,status)
		else:paragraph(body,cw("investment"),15)
		paragraph(body,lw("next"),19)
		body.add_child(project_card(status.project))
		paragraph(body,lw("upkeep")%int(status.upkeep),14)
	else:paragraph(body,lw("unavailable"),16)
	town_operations(body)
	paragraph(body,lw("unlocks"),19)
	var offers:=HFlowContainer.new();offers.add_theme_constant_override("h_separation",8);body.add_child(offers)
	for id in life.project_specs:
		if life.available(p.state,id) and life.project_specs[id].stage_requires!=life.content.initial_stage and not life.transitions(p.state).any(func(t):return t.project==id):offers.add_child(project_card(id))
	paragraph(body,lw("live_support"),14)
	body.add_child(button(w("growth_review"),func():legacy(0),"LifecycleSupportReview"))
	lifecycle_ladder(body,status.stage)

func lifecycle_factors(body: VBoxContainer,status: Dictionary) -> void:
	if status.get("recognized_fabric",false):paragraph(body,lw("town_ready_legacy"),15);return
	paragraph(body,lw("requirements"),19)
	var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",26);grid.add_theme_constant_override("v_separation",6);body.add_child(grid)
	for factor in status.factors:
		var fields: Dictionary=factor.duplicate()
		fields.name=p.rules.lifecycle.content.factors.get(factor.id,p.rules.projects.get(factor.id,{}).get("title",factor.id))
		if status.project=="town_civic" and factor.id=="housing":fields.name=lw("town_dwellings")
		var line:=paragraph(grid,("✓ " if factor.met else "○ ")+lw("factor").format(fields),14)
		line.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		line.add_theme_color_override("font_color",Color("c5d6b5") if factor.met else Color("edc490"))
		if factor.has("alternatives"):
			var alternatives: PackedStringArray=[]
			for option in factor.alternatives:alternatives.append(("✓ " if option.met else "○ ")+p.rules.lifecycle.content.factors.get(option.id,p.rules.projects.get(option.id,{}).get("title",option.id)))
			line.text+="\n"+lw("any_of").format({"alternatives":", ".join(alternatives)})
	paragraph(body,lw("readiness").format({"seasons":status.seasons,"required":status.required_seasons}),16)

func lifecycle_ladder(body: VBoxContainer,current: String) -> void:
	body.add_child(HSeparator.new())
	var ladder:=HFlowContainer.new();ladder.add_theme_constant_override("h_separation",14);body.add_child(ladder)
	for stage in p.rules.lifecycle.content.stages:
		var title: String=stage.title
		if stage.id==current:title="✓ "+title
		var planned: bool=stage.status=="planned" and not (stage.id=="town" and p.rules.lifecycle.town_active(p.state))
		if planned:title+=" · "+lw("planned")
		var line:=label(title,14);ladder.add_child(line)
		if planned:line.add_theme_color_override("font_color",Color("b4b8ad"))

func lifecycle_project(body: VBoxContainer,id: String) -> void:
	var spec: Dictionary=p.rules.projects[id]
	var status: Dictionary=p.rules.lifecycle.status(p.state,p.rules)
	paragraph(body,lw("continuity"),14)
	paragraph(body,lw("reserve_after").format({"food":p.rules.people(p.state).size()*int(p.rules.balance.food_per_person)*int(p.rules.lifecycle.balance.commission_reserve_seasons),"wood":p.rules.lifecycle.balance.commission_wood_reserve}),14)
	if status.project==id:
		paragraph(body,lw("upkeep")%int(status.upkeep),15)
		if queued(id).is_empty() and not p.rules.has_project(p.state,id):lifecycle_factors(body,status)
		var titles: PackedStringArray=[]
		for next_id in p.rules.lifecycle.project_specs:
			if next_id in status.unlocks and p.rules.lifecycle.available(p.state,next_id):titles.append(p.rules.projects[next_id].title)
		paragraph(body,lw("unlocks")+": "+", ".join(titles),14)
	if p.rules.lifecycle.town_projects.has(id):
		paragraph(body,lw("town_required") if id=="town_civic" else lw("town_optional"),17)
		town_operations(body)
	for change in spec.changes:
		for record in change.after:
			if record.kind!="building":continue
			paragraph(body,lw("lineage").format({"object":record.label,"from":change.get("expected_revisions",{}).get(record.id,0),"to":record.revision}),14)
			if not p.rules.has_project(p.state,id) and change.get("expected_revisions",{}).has(record.id):paragraph(body,lw("predecessor").format({"revision":change.expected_revisions[record.id]}),13)

func help(body: VBoxContainer) -> void:
	var step: Dictionary=copy.lessons[lesson]
	paragraph(body,w("guide_step").format({"number":lesson+1}),15);paragraph(body,step.title,24);paragraph(body,step.body,18)
	body.add_child(icon_button(copy.assets.filter(func(a):return a.id==step.asset)[0].label,step.asset,"",select_place.bind(step.asset),"VisualLessonPlace"))
	var r:=row(body)
	var prev:=button(w("guide_previous"),func():lesson-=1;refresh(),"VisualLessonPrevious");prev.disabled=lesson==0;r.add_child(prev)
	var next:=button(w("guide_next"),func():lesson+=1;refresh(),"VisualLessonNext");next.disabled=lesson==copy.lessons.size()-1;r.add_child(next)
	paragraph(body,w("help_keys"),14)
func incidents(body: VBoxContainer) -> void:
	if not p.rules.incidents.active(p.state):
		paragraph(body,w("incident_note"),18);command_button(body,w("begin_incident"),{"kind":"incident_begin"},"VisualBeginIncidents");return
	paragraph(body,p.incident_panel.notice(),19)
	var e: Dictionary=p.rules.incidents.current(p.state)
	if e.is_empty() or e.known<0:return
	var spec: Dictionary=p.rules.incidents.specs[e.id]
	if e.outcome.is_empty():
		paragraph(body,spec.signs);paragraph(body,w("restriction_note"))
		command_button(body,w("restrict")+" · "+(w("off") if e.restricted else w("on")),{"kind":"incident_restrict","enabled":not e.restricted},"VisualRestrict")
		body.add_child(project_card(spec.prepare))
		p.incident_panel.factors(body,forecast.incidents.factors)
	else:
		p.incident_panel.outcome(body,e);body.add_child(project_card(spec.repair))
	body.add_child(button(w("visit"),func():p.incident_panel.visit(),"VisualIncidentVisit"))
func knowledge(body: VBoxContainer) -> void:
	paragraph(body,w("inspect_note"),14)
	if p.rules.assets.active(p.state):paragraph(body,p.rules.assets.assets[selected].function,18)
	if p.rules.living.active(p.state):
		var subjects: Array=[]
		if selected in ["homes","workroom"]:
			for h in p.living_panel.copy.households:subjects.append(h.id)
		if selected=="workroom":
			for a in p.living_panel.copy.areas:subjects.append(a.id)
		if selected=="watch":
			for post in p.living_panel.copy.posts:subjects.append(post.id)
		var choices:=HFlowContainer.new();body.add_child(choices)
		for subject in subjects:
			choices.add_child(button(p.living_panel.title(subject),ask.bind(subject),"VisualAsk_"+subject))
		for d in p.living_panel.copy.discoveries:
			if p.state.living.discoveries.has(d.id):paragraph(body,d.title,18);paragraph(body,d.body)
	if p.rules.incidents.active(p.state):
		for e in p.state.incidents.records:
			if e.known>=0:paragraph(body,p.rules.incidents.specs[e.id].title,19)
			if not e.inspected.is_empty():paragraph(body,p.rules.incidents.specs[e.id].detail)
func report(body: VBoxContainer) -> void:
	paragraph(body,w("report_note"))
	if p.state.report.is_empty():paragraph(body,p.asset_panel.copy.ui.no_report);return
	paragraph(body,p.asset_panel.copy.ui.actual.format(p.state.report),18)
	for key in ["wellbeing","cooperation","security"]:
		var factors: Array=[]
		for factor in p.state.report.factors[key]:
			if factor.value!=0:factors.append(p.copy.factor_names[factor.id]+" %+d"%int(factor.value))
		paragraph(body,p.copy[key]+": "+", ".join(factors))
func execute(action: Dictionary) -> void:
	if _busy:return
	_busy=true
	var start: int=Time.get_ticks_usec()
	var accepted: bool=p.dispatch(p.rules.canonical(action))
	timings[action.kind+"_us"]=Time.get_ticks_usec()-start
	if accepted:command_applied.emit(p.rules.canonical(action))
	_busy=false;refresh()
func advance() -> void:
	if _busy or p._season_input_locked:return
	_busy=true
	var b: Button=find_child("VisualSeason",true,false)
	if b!=null:b.disabled=true;b.text=w("busy")
	if DisplayServer.get_name()!="headless":RenderingServer.force_draw(true)
	var start: int=Time.get_ticks_usec();var turn: int=p.state.turn
	p.resolve_from_ui();timings.season_us=Time.get_ticks_usec()-start
	if p.state.turn>turn:command_applied.emit({"kind":"advance"})
	_busy=false;refresh()
func save() -> void:
	if p.save_campaign():save_finished.emit(true)
	refresh()
func load_saved() -> void:
	if p.load_campaign():
		room_mode=false;return_view={};detail={};overlay="";page="projects";open();save_finished.emit(false)
	else:refresh()
func start_new() -> void:
	if not p.state.is_empty() or FileAccess.file_exists(p.save_path):show_overlay("new_confirm");return
	begin()
func begin() -> void:
	room_mode=false;return_view={}
	detail={};overlay="";selected="stores";page="projects"
	var start: int=Time.get_ticks_usec()
	var state: Dictionary=p.rules.new_state()
	for kind in ["asset_begin","land_begin","living_begin"]:state=p.rules.command(state,{"kind":kind}).state
	p.state=state;p.last_message="";p.app.show_campaign(state,p.rules);p.refresh();p.hide();enabled=true;open();app.overview()
	timings.open_us=Time.get_ticks_usec()-start
func visit() -> void:
	if selected in ["workroom","stores"]:
		p.household_panel.visit("household_workshop" if selected=="workroom" else "household_store")
	else:p.asset_panel.selected=selected;p.asset_panel.visit()
	close_sheet()
func inspect() -> void:
	var subject: String="store" if selected=="stores" else selected
	var e: Dictionary=p.rules.incidents.current(p.state)
	if not e.is_empty() and subject in p.rules.incidents.specs[e.id].subjects:execute({"kind":"incident_inspect","id":subject})
	elif p.rules.living.active(p.state) and p.rules.living.subjects.has(subject):execute({"kind":"living_inspect","id":subject})
	elif p.rules.assets.active(p.state):execute({"kind":"asset_inspect","id":selected})
	show_overlay("knowledge")
func pick(origin: Vector3,direction: Vector3) -> bool:
	if not enabled or p.visible or not app.campaign_mode:return false
	if is_instance_valid(room()):
		var plan: String=room().pick(origin,direction)
		if plan!="":
			room_mode=true
			if plan=="easel":show_project(room().selected)
			else:room().choose(plan);look_at_easel();refresh()
			return true
	if is_instance_valid(construction()):
		var project: String=construction().pick(origin,direction)
		if project!="":show_project(project);return true
	var subject: String=""
	if p.rules.living.active(p.state):subject=app.campaign_view.living_view.pick(origin,direction)
	if subject!="":
		selected="watch" if subject.ends_with("post") else "workroom"
		var e: Dictionary=p.rules.incidents.current(p.state)
		execute({"kind":"incident_inspect" if not e.is_empty() and subject in p.rules.incidents.specs[e.id].subjects else "living_inspect","id":subject});show_overlay("knowledge");return true
	var object_id: String=app.pick_asset(origin,direction,true)
	if object_id!="":
		# An occupied adaptation keeps its ordinary building selectable as its site.
		for item in p.state.queue:
			if object_id in projects.describe(p.state,p.rules,item.id,forecast).affected:
				show_project(item.id);return true
		select_place(p.rules.assets.object_asset(object_id));return true
	return false

func has_building_change(id: String) -> bool:
	for change in p.rules.projects[id].changes:
		for record in change.after:
			if record.kind=="building":return true
	return false
func preview_mesh(id: String,planned: bool=true) -> Mesh:
	# Authored future buildings are generated once with the production builder.
	# Other cards show the current place, explicitly labelled; no imagined upgrade.
	for change in p.rules.projects[id].changes:
		for record in change.after:
			if record.kind!="building" or not planned:continue
			if not preview_meshes.has(id):
				var model=preload("res://src/village.gd").new();model.data=app.data;model.materials=app.world.materials;model._building(record)
				preview_meshes[id]=model.object_nodes[record.id].mesh;model.free()
			return preview_meshes[id]
	if not planned and p.rules.has_project(p.state,id):
		for change in p.rules.projects[id].changes:
			for record in change.after:
				if record.kind=="building" and app.world.object_nodes.has(record.id):return app.world.object_nodes[record.id].mesh
	for change in p.rules.projects[id].changes:
		for object_id in change.before:
			if app.world.object_nodes.has(object_id):return app.world.object_nodes[object_id].mesh
	if p.rules.land.proposals.has(id):
		var site: Dictionary=p.rules.land.sites[p.rules.land.proposals[id].site]
		for object_id in site.objects:
			if app.world.object_nodes.has(object_id):return app.world.object_nodes[object_id].mesh
		return null
	if has_building_change(id) or p.rules.incidents.project_specs.has(id):return null
	var asset: String=p.rules.assets.project_assets.get(id,selected)
	for object_id in p.rules.assets.assets[asset].objects:
		if app.world.object_nodes.has(object_id):return app.world.object_nodes[object_id].mesh
	return null

func ask(subject: String) -> void:
	var e: Dictionary=p.rules.incidents.current(p.state)
	execute({"kind":"incident_inspect" if not e.is_empty() and subject in p.rules.incidents.specs[e.id].subjects else "living_inspect","id":subject})
	show_overlay("knowledge")

func visit_project(id: String) -> void:
	var at: Array=p.rules.projects[id].at
	var center:=Vector3(at[0],app.world.floor_height(at[0],at[1]),at[1])
	app.set_view(center+Vector3(10,9,14),center);close_sheet()

func layout_sheet() -> void:
	if is_instance_valid(sheet) and is_instance_valid(header):sheet.offset_top=header.position.y+header.size.y+12

func project_cause(d: Dictionary) -> String:
	if d.refusal!="":return p.reason(d.refusal)
	return cw("manual") if d.cause=="manual" else cw("cause_"+d.cause)

func project_flow(body: VBoxContainer,d: Dictionary) -> void:
	var flow:=HBoxContainer.new();flow.name="ProjectFlow";flow.add_theme_constant_override("separation",10);body.add_child(flow)
	for kind in ["materials","workers","result"]:
		if kind!="materials":flow.add_child(label("→",24))
		var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.size_flags_stretch_ratio=1;panel.add_theme_stylebox_override("panel",style("304846"));flow.add_child(panel)
		var v:=VBoxContainer.new();panel.add_child(v)
		var icon:=Icon.new();icon.kind="wood" if kind=="materials" else ("people" if kind=="workers" else project_icon(d.id));icon.custom_minimum_size=Vector2(70,38);v.add_child(icon)
		paragraph(v,cw(kind),17)
		if kind=="materials":
			paragraph(v,cw("paid" if d.committed else "quote").format({"wood":d.paid_wood if d.committed else d.cost_wood,"blanks":d.paid_blanks if d.committed else d.cost_blanks}),14)
			paragraph(v,cw("stock").format({"wood":p.state.wood,"blanks":p.state.living.get("blanks",0)}),13)
		elif kind=="workers":
			paragraph(v,cw("capacity").format(d),14);paragraph(v,cw("adults").format(d),13)
			paragraph(v,cw("next_work").format(d),15);paragraph(v,cw("remaining").format(d),13)
		else:paragraph(v,d.benefit,14)

func project_overview(body: VBoxContainer) -> void:
	paragraph(body,cw("overview_note"),16)
	var controls:=row(body);controls.add_child(button(cw("enter_room"),enter_room,"EnterPlanningRoom"))
	paragraph(body,cw("legend"),13)
	for group in ["active","paused","available","complete"]:
		var ids: Array=[]
		for id in projects.ids(p.state,p.rules):
			var d: Dictionary=projects.describe(p.state,p.rules,id,forecast)
			var actual: String="complete" if d.complete else ("paused" if d.paused else ("active" if d.queued else "available"))
			if group==actual:ids.append(id)
		if ids.is_empty():continue
		paragraph(body,cw(group),20)
		var cards:=HFlowContainer.new();body.add_child(cards)
		for id in ids:
			var d: Dictionary=projects.describe(p.state,p.rules,id,forecast)
			var card:=project_card(id)
			card.tooltip_text=p.rules.projects[id].title+"\n"+d.stage_label+"\n"+project_cause(d)
			if d.queued:card.get_child(0).get_child(2).text="%d/%d · %d adults · +%d"%[d.progress,d.total,d.crew,d.work]
			cards.add_child(card)

func enter_room() -> void:
	if not is_instance_valid(room()):return
	if not room_mode:return_view={"position":app.camera.position,"rotation":app.camera.rotation,"flying":app.flying}
	room_mode=true;detail={};overlay="";look_at_board();refresh()
func look_at_board() -> void:
	if not is_instance_valid(room()):return
	app.set_view(room().point(Vector3(.12,1.68,1.24)),room().board_center(),false)
func look_at_easel() -> void:
	if not is_instance_valid(room()):return
	app.set_view(room().point(Vector3(.12,1.68,1.24)),room().easel_center(),false)
func leave_room() -> void:
	room_mode=false;detail={};overlay=""
	if not return_view.is_empty():
		app.camera.position=return_view.position;app.camera.rotation=return_view.rotation;app.yaw=app.camera.rotation.y;app.pitch=app.camera.rotation.x;app.flying=return_view.flying;app._update_mode()
	return_view={};refresh()
func site_preview(id: String) -> Mesh:
	if not is_instance_valid(construction()) or not construction().sites.has(id):return preview_mesh(id,false)
	return app.world.object_nodes[construction().sites[id].owner].mesh

func town_operations(body: VBoxContainer) -> void:
	var life=p.rules.lifecycle
	if not life.town_active(p.state):return
	paragraph(body,lw("town_obligation").format({"workers":life.town_balance.civic_workers,"previous":life.balance.civic_workers,"service":life.town_balance.service_workers}),14)
	if p.rules.has_project(p.state,"town_civic"):
		var op: Dictionary=life.operation(p.state,forecast.get("assets",{}),p.rules)
		paragraph(body,lw("town_operation").format(op),16)
		paragraph(body,lw("town_unstaffed" if not op.civic else "town_condition" if not op.maintained else "town_service_unstaffed" if op.service<op.service_wanted else "town_operating"),14)
		paragraph(body,lw("town_effects").format(op),14)
