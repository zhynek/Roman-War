extends Control
## Presentation-only counselor: a replayable local guide and explicit online chat.
## Nothing here dispatches village commands, adopts profiles or writes game saves.
const Portrait=preload("res://src/marcus_portrait.gd")
const Voice=preload("res://src/marcus_voice.gd")
const ProjectPresentation=preload("res://src/project_presentation.gd")
const PREFERENCES_PATH: String="user://marcus_preferences.cfg"
var app
var voice
var copy: Dictionary={}
var lessons: Array=[]
var panel: PanelContainer
var launcher: Button
var launcher_portrait
var panel_portrait
var status_label: Label
var connect_button: Button
var mute_button: Button
var guide_button: Button
var chat_button: Button
var guide_scroll: ScrollContainer
var guide_body: VBoxContainer
var chat_body: VBoxContainer
var transcript: RichTextLabel
var question: LineEdit
var send_button: Button
var message: Label
var lesson_speech: Button
var _status_code: String="disconnected"
var _muted: bool=false
var _intro_seen: bool=false
var _intro_step: int=0
var _lesson: int=0
var _guide_finished: bool=false
var _mode: String="intro"
var _tab: String="guide"
var _conversation: Array=[]
var _reply_index: int=-1
var _awaiting_response: bool=false
var _layout_pending: bool=false

func configure(owner_app) -> void:
	app=owner_app
	copy=JSON.parse_string(FileAccess.get_file_as_string("res://data/marcus.json"))
	lessons=app.visual_commands.copy.lessons
	_load_preferences()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	name="MarcusAdvisor"
	voice=Voice.new()
	add_child(voice)
	voice.status_changed.connect(_status_changed)
	voice.answer_received.connect(_answer_received)
	voice.user_transcript.connect(_user_transcript)
	voice.speaking_changed.connect(_speaking_changed)
	voice.set_muted(_muted)
	_build()
	get_viewport().size_changed.connect(_layout)
	panel.minimum_size_changed.connect(_schedule_layout)
	_layout()
	_schedule_layout()
	_sync_connection()
	if not _intro_seen:open.call_deferred()

func w(id: String) -> String:
	return String(copy.ui.get(id,id))

func _style(background: String="172c2b") -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(background)
	style.border_color=Color("8b805e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(17)
	style.shadow_color=Color(0,0,0,.3)
	style.shadow_size=8
	return style

func _label(text: String,font_size: int=16,color: String="e7e0cc") -> Label:
	var label:=Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color(color))
	return label

func _button(text: String,callback: Callable,id: String="") -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size.y=36
	button.add_theme_font_size_override("font_size",14)
	button.pressed.connect(callback)
	if id!="":button.name=id
	return button

func _build() -> void:
	launcher=_button("",open,"MarcusLauncher")
	launcher.tooltip_text=w("launcher_hint")
	launcher.add_theme_stylebox_override("normal",_style())
	launcher.add_theme_stylebox_override("hover",_style("28443e"))
	add_child(launcher)
	var launcher_row:=HBoxContainer.new()
	launcher.add_child(launcher_row)
	launcher_row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	launcher_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	launcher_row.offset_left=8;launcher_row.offset_right=-12;launcher_row.offset_top=4;launcher_row.offset_bottom=-4
	launcher_portrait=Portrait.new()
	launcher_portrait.custom_minimum_size=Vector2(60,60)
	launcher_portrait.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	launcher_row.add_child(launcher_portrait)
	var launcher_title:=_label(w("launcher"),17,"ded1a7")
	launcher_title.mouse_filter=Control.MOUSE_FILTER_IGNORE
	launcher_title.autowrap_mode=TextServer.AUTOWRAP_OFF
	launcher_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	launcher_title.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	launcher_row.add_child(launcher_title)

	panel=PanelContainer.new()
	panel.name="MarcusPanel"
	panel.add_theme_stylebox_override("panel",_style())
	panel.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(panel)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	panel.add_child(column)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	column.add_child(header)
	panel_portrait=Portrait.new()
	panel_portrait.custom_minimum_size=Vector2(58,58)
	header.add_child(panel_portrait)
	var identity:=VBoxContainer.new()
	identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	identity.add_child(_label(copy.name,25,"ded1a7"))
	identity.add_child(_label(copy.role,12,"b8c5b8"))
	var close:=_button("×",close_panel,"MarcusClose")
	close.tooltip_text=w("close")
	close.custom_minimum_size=Vector2(36,36)
	close.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	header.add_child(close)
	var tabs:=HBoxContainer.new()
	column.add_child(tabs)
	guide_button=_button(w("guide"),_choose_tab.bind("guide"),"MarcusGuide")
	guide_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tabs.add_child(guide_button)
	chat_button=_button(w("conversation"),_choose_tab.bind("chat"),"MarcusChat")
	chat_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tabs.add_child(chat_button)

	guide_scroll=ScrollContainer.new()
	guide_scroll.name="MarcusGuideScroll"
	guide_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	guide_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(guide_scroll)
	guide_body=VBoxContainer.new()
	guide_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	guide_body.add_theme_constant_override("separation",13)
	guide_scroll.add_child(guide_body)

	chat_body=VBoxContainer.new()
	chat_body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	chat_body.add_theme_constant_override("separation",9)
	column.add_child(chat_body)
	transcript=RichTextLabel.new()
	transcript.name="MarcusTranscript"
	transcript.bbcode_enabled=false
	transcript.selection_enabled=true
	transcript.scroll_following=true
	transcript.size_flags_vertical=Control.SIZE_EXPAND_FILL
	transcript.custom_minimum_size.y=110
	transcript.add_theme_font_size_override("normal_font_size",16)
	transcript.add_theme_color_override("default_color",Color("e7e0cc"))
	chat_body.add_child(transcript)
	var suggestions:=HFlowContainer.new()
	suggestions.add_theme_constant_override("h_separation",5)
	chat_body.add_child(suggestions)
	for key in ["ask_supplies","ask_building","ask_next"]:
		var suggestion:=_button(w(key),_fill_question.bind(w(key)))
		suggestion.add_theme_font_size_override("font_size",12)
		suggestion.custom_minimum_size.y=30
		suggestions.add_child(suggestion)
	var composer:=HBoxContainer.new()
	chat_body.add_child(composer)
	question=LineEdit.new()
	question.name="MarcusQuestion"
	question.placeholder_text=w("placeholder")
	question.max_length=int(copy.limits.question_characters)
	question.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	question.custom_minimum_size.y=38
	question.text_submitted.connect(_ask)
	composer.add_child(question)
	send_button=_button(w("send"),func():_ask(question.text),"MarcusSend")
	composer.add_child(send_button)
	chat_body.add_child(_label(w("context_note"),11,"a6b8ab"))
	message=_label("",12,"e1bd82")
	chat_body.add_child(message)
	column.add_child(HSeparator.new())
	column.add_child(_label(w("connection_note"),11,"a6b8ab"))
	status_label=_label("",13,"c9bd95")
	status_label.name="MarcusStatus"
	column.add_child(status_label)
	var connection:=HBoxContainer.new()
	column.add_child(connection)
	connect_button=_button(w("connect"),_toggle_connection,"MarcusConnect")
	connect_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	connection.add_child(connect_button)
	mute_button=_button("",_toggle_mute,"MarcusMute")
	connection.add_child(mute_button)
	panel.hide()
	_render_guide()
	_render_transcript()
	_choose_tab(_tab)

func _layout() -> void:
	if not is_instance_valid(panel):return
	var viewport: Vector2=get_viewport_rect().size
	var width: float=minf(460.0,maxf(250.0,viewport.x-32.0))
	launcher.position=Vector2(maxf(8,viewport.x-198),maxf(8,viewport.y-90))
	launcher.size=Vector2(182,74)
	panel.position=Vector2(maxf(8,viewport.x-width-16),16)
	panel.size=Vector2(width,maxf(300.0,viewport.y-122))
	# A long lesson scrolls inside the panel instead of covering the launcher.
	if panel.size.y>730:
		panel.position.y=viewport.y-106-730
		panel.size.y=730

func _schedule_layout() -> void:
	# Autowrapped labels initially measure at zero width and can enlarge the
	# panel before container sorting. Godot retains that oversized rectangle
	# after their minimum shrinks; reclamp when the real width has settled.
	if _layout_pending:return
	_layout_pending=true
	_flush_layout.call_deferred()

func _flush_layout() -> void:
	_layout_pending=false
	_layout()

func is_open() -> bool:
	return is_instance_valid(panel) and panel.visible

func open() -> void:
	app.hud.show()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	app._look_drag=false
	panel.show()
	_layout()
	_render_guide()
	_sync_connection()
	if _tab=="chat":question.grab_focus()

func close_panel() -> void:
	if _mode=="intro":_intro_seen=true
	# Hidden captions must never accompany continuing speech or a billed session.
	voice.stop()
	_awaiting_response=false
	_reply_index=-1
	_save_preferences()
	panel.hide()
	var focus: Control=get_viewport().gui_get_focus_owner()
	if focus!=null and is_ancestor_of(focus):focus.release_focus()

func _choose_tab(tab: String) -> void:
	_tab=tab
	guide_scroll.visible=tab=="guide"
	chat_body.visible=tab=="chat"
	guide_button.disabled=tab=="guide"
	chat_button.disabled=tab=="chat"
	if tab=="chat" and panel.visible:question.grab_focus()
	_schedule_layout()

func _render_guide() -> void:
	if not is_instance_valid(guide_body):return
	for child in guide_body.get_children():
		guide_body.remove_child(child)
		child.queue_free()
	lesson_speech=null
	if _mode=="intro":
		var page: Dictionary=copy.intro[_intro_step]
		guide_body.add_child(_label(w("intro_tag"),11,"bdb17f"))
		guide_body.add_child(_label(w("progress").format({"number":_intro_step+1,"total":copy.intro.size()}),12,"a6b8ab"))
		guide_body.add_child(_label(page.title,27,"eee3c2"))
		guide_body.add_child(_label(page.body,17))
		guide_body.add_child(_label(page.counsel,17,"b8ccb9"))
		guide_body.add_child(_label(copy.fiction_note,11,"99ad9f"))
		if _intro_step==1:guide_body.add_child(_label(copy.future_note,11,"99ad9f"))
		var navigation:=HBoxContainer.new()
		guide_body.add_child(navigation)
		var previous:=_button(w("previous"),_intro_previous,"MarcusIntroPrevious")
		previous.disabled=_intro_step==0
		navigation.add_child(previous)
		var next:=_button(w("begin_guide" if _intro_step==copy.intro.size()-1 else "next"),_intro_next,"MarcusIntroNext")
		next.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		navigation.add_child(next)
		guide_body.add_child(_button(w("skip"),_skip_guide,"MarcusSkip"))
	else:
		guide_body.add_child(_label(w("lesson_tag"),11,"bdb17f"))
		var picker:=OptionButton.new()
		picker.name="MarcusLessons"
		picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		picker.clip_text=true
		for i in range(lessons.size()):picker.add_item("%d · %s"%[i+1,lessons[i].title])
		picker.selected=_lesson
		picker.item_selected.connect(_choose_lesson)
		guide_body.add_child(picker)
		if _guide_finished:
			guide_body.add_child(_label(w("finished"),26,"eee3c2"))
			guide_body.add_child(_label(w("finished_body"),17))
			guide_body.add_child(_button(w("restart"),_choose_lesson.bind(0),"MarcusRestart"))
		else:
			var lesson: Dictionary=lessons[_lesson]
			guide_body.add_child(_label(w("progress").format({"number":_lesson+1,"total":lessons.size()}),12,"a6b8ab"))
			guide_body.add_child(_label(lesson.title,25,"eee3c2"))
			guide_body.add_child(_label(lesson.body,17))
			guide_body.add_child(_label(copy.lesson_counsel[_lesson],16,"b8ccb9"))
			guide_body.add_child(_label(w("lesson_source"),11,"99ad9f"))
			var show_place:=_button(w("show_me"),_show_lesson_place,"MarcusShowMe")
			var blocked: String=_navigation_blocked()
			show_place.disabled=blocked!=""
			guide_body.add_child(show_place)
			if blocked!="":guide_body.add_child(_label(w(blocked),12,"d4bd93"))
			if _lesson>=4:guide_body.add_child(_label(w("chapter_note"),12,"a6b8ab"))
			var navigation:=HBoxContainer.new()
			guide_body.add_child(navigation)
			var previous:=_button(w("previous"),_choose_lesson.bind(_lesson-1),"MarcusLessonPrevious")
			previous.disabled=_lesson==0
			navigation.add_child(previous)
			var next:=_button(w("finish" if _lesson==lessons.size()-1 else "next"),_lesson_next,"MarcusLessonNext")
			next.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			navigation.add_child(next)
		guide_body.add_child(_button(w("replay"),_replay_intro,"MarcusReplay"))
	lesson_speech=_button(w("hear"),_explain_page,"MarcusHearLesson")
	lesson_speech.tooltip_text=w("hear_hint")
	guide_body.add_child(lesson_speech)
	lesson_speech.disabled=not voice.is_agent_connected()
	guide_scroll.set_deferred("scroll_vertical",0)
	_schedule_layout()

func _intro_previous() -> void:
	_intro_step=maxi(0,_intro_step-1)
	_save_preferences()
	_render_guide()

func _intro_next() -> void:
	if _intro_step+1<copy.intro.size():_intro_step+=1
	else:
		_intro_seen=true
		_mode="guide"
	_save_preferences()
	_render_guide()

func _skip_guide() -> void:
	_intro_seen=true
	_mode="guide"
	close_panel()

func _replay_intro() -> void:
	_mode="intro"
	_intro_step=0
	_render_guide()

func _choose_lesson(index: int) -> void:
	_mode="guide"
	_lesson=clampi(index,0,lessons.size()-1)
	_guide_finished=false
	_save_preferences()
	_render_guide()

func _lesson_next() -> void:
	if _lesson+1<lessons.size():_lesson+=1
	else:_guide_finished=true
	_save_preferences()
	_render_guide()

func _navigation_blocked() -> String:
	if app.campaign.state.is_empty() or not app.campaign_mode:return "active_village_needed"
	if app.defense_panel.active_ui or app.campaign.rules.defense.locked(app.campaign.state):return "battle_navigation_blocked"
	return ""

func _show_lesson_place() -> void:
	if _navigation_blocked()!="":_render_guide();return
	app.visual_commands.open()
	app.visual_commands.lesson=_lesson
	app.visual_commands.guide_destination(lessons[_lesson])
	close_panel()

func _explain_page() -> void:
	_choose_tab("chat")
	_ask(w("explain_prompt"))

func _toggle_connection() -> void:
	if voice.is_agent_connected() or _status_code=="connecting":
		voice.stop()
		return
	voice.connect_agent(context_snapshot())

func _toggle_mute() -> void:
	_muted=not _muted
	voice.set_muted(_muted)
	_save_preferences()
	_sync_connection()

func _status_changed(code: String) -> void:
	_status_code=code
	if code=="thinking" and not _awaiting_response:
		_reply_index=-1
		_awaiting_response=true
	elif code in ["connected","disconnected","idle_timeout","response_timeout","connection_failed","protocol_error"]:
		_awaiting_response=false
	_sync_connection()

func _sync_connection() -> void:
	if not is_instance_valid(status_label):return
	var connected: bool=voice.is_agent_connected()
	status_label.text=copy.status.get(_status_code,copy.status.unavailable)
	if _status_code in ["setup_required","unconfigured","agent_private_required"]:status_label.text+="\n"+w("setup_note")
	connect_button.text=w("disconnect" if connected or _status_code=="connecting" else "connect")
	mute_button.text=w("unmute" if _muted else "mute")
	send_button.disabled=not connected or voice.is_answering()
	if is_instance_valid(lesson_speech):lesson_speech.disabled=send_button.disabled

func _fill_question(text: String) -> void:
	question.text=text
	question.grab_focus()
	question.caret_column=text.length()

func _ask(text: String) -> void:
	var trimmed: String=text.strip_edges()
	if trimmed.is_empty():return
	if not voice.is_agent_connected():message.text=w("not_connected");return
	if send_button.disabled:return
	if trimmed.length()>int(copy.limits.question_characters):
		message.text=w("question_too_long").format({"limit":copy.limits.question_characters})
		return
	message.text=""
	_add_entry("user",trimmed)
	_reply_index=-1
	_awaiting_response=true
	question.clear()
	voice.ask(trimmed,context_snapshot())

func _add_entry(role: String,text: String) -> int:
	_conversation.append({"role":role,"text":text})
	while _conversation.size()>int(copy.limits.conversation_entries):
		_conversation.pop_front()
		_reply_index-=1
	_render_transcript()
	return _conversation.size()-1

func _user_transcript(text: String) -> void:
	if text.strip_edges().is_empty():return
	if not _conversation.is_empty() and _conversation.back().role=="user" and _conversation.back().text==text:return
	_add_entry("user",text)
	_reply_index=-1
	_awaiting_response=true

func _answer_received(text: String) -> void:
	if text.is_empty():return
	if _reply_index<0 or _reply_index>=_conversation.size():_reply_index=_add_entry("marcus",text)
	else:
		_conversation[_reply_index].text=text
		_render_transcript()

func _render_transcript() -> void:
	if not is_instance_valid(transcript):return
	if _conversation.is_empty():transcript.text=w("empty_chat");return
	var paragraphs:=PackedStringArray()
	for entry in _conversation:
		paragraphs.append((w("you") if entry.role=="user" else String(copy.name))+"\n"+String(entry.text))
	transcript.text="\n\n".join(paragraphs)
	transcript.scroll_to_line(maxi(0,transcript.get_line_count()-1))

func _speaking_changed(active: bool) -> void:
	if is_instance_valid(launcher_portrait):launcher_portrait.set_speaking(active)
	if is_instance_valid(panel_portrait):panel_portrait.set_speaking(active)

func _load_preferences() -> void:
	var config:=ConfigFile.new()
	if config.load(PREFERENCES_PATH)!=OK:return
	_muted=bool(config.get_value("marcus","muted",false))
	_intro_seen=bool(config.get_value("marcus","intro_seen",false))
	_intro_step=clampi(int(config.get_value("marcus","intro_step",0)),0,copy.intro.size()-1)
	_lesson=clampi(int(config.get_value("marcus","lesson",0)),0,lessons.size()-1)
	_guide_finished=bool(config.get_value("marcus","guide_finished",false))
	_mode="guide" if _intro_seen else "intro"

func _save_preferences() -> void:
	var config:=ConfigFile.new()
	config.set_value("marcus","muted",_muted)
	config.set_value("marcus","intro_seen",_intro_seen)
	config.set_value("marcus","intro_step",_intro_step)
	config.set_value("marcus","lesson",_lesson)
	config.set_value("marcus","guide_finished",_guide_finished)
	config.save(PREFERENCES_PATH)

func _select_fields(source: Dictionary,keys: Array) -> Dictionary:
	var result: Dictionary={}
	for key in keys:
		if source.has(key):result[key]=source[key]
	return result

func _screen_snapshot() -> Dictionary:
	var p=app.campaign
	if app.defense_panel.active_ui:
		return {"surface":"defense","phase":app.defense_panel.phase}
	if p.visible:
		var ledger: Dictionary={"surface":"village_ledger"}
		if is_instance_valid(p.tabs) and p.tabs.current_tab>=0:
			ledger.tab=p.tabs.current_tab
			ledger.title=p.tabs.get_tab_title(p.tabs.current_tab)
		return ledger
	if not app.campaign_mode:return {"surface":"reference_village"}
	if app.visual_commands.visible:
		return {"surface":"village_commands","place":app.visual_commands.selected,"page":app.visual_commands.page,"overlay":app.visual_commands.overlay,"detail":_select_fields(app.visual_commands.detail,["kind","id"])}
	return {"surface":"village_walk"}

func context_snapshot() -> Dictionary:
	## Build a bounded, explicit read model at the player's request. In particular,
	## forecast.incidents and quote.state contain undiscovered/candidate state.
	## Never serialize those, full saves, tactical rosters or citizen histories.
	var p=app.campaign
	var rules=p.rules
	var state: Dictionary=p.state
	var result: Dictionary={
		"experience":"yenikapi_early_settlement",
		"mode":w("village_mode" if app.campaign_mode else "reference_mode"),
		"fiction":copy.fiction_note,
		"planned_story":copy.future_note,
		"screen":_screen_snapshot(),
		"guide":{"mode":_mode,"index":_intro_step if _mode=="intro" else _lesson}
	}
	if _mode=="intro":result.guide.page=copy.intro[_intro_step].duplicate(true)
	else:
		result.guide.page=lessons[_lesson].duplicate(true)
		result.guide.counsel=copy.lesson_counsel[_lesson]
	if state.is_empty() or not app.campaign_mode:return result
	result.calendar={"turn":int(state.turn),"year":1+int(state.turn)/4,"season":p.copy.seasons[int(state.turn)%4]}
	result.village=_select_fields(state,["food","wood","wellbeing","cooperation","security","role"])
	result.village.population=rules.people(state).size()
	result.village.available_adults=rules.people(state,true).size()
	result.village.housing=rules.capacity(state)
	result.village.storage=rules.storage(state)
	result.chapters={"households":rules.households.active(state),"assets":rules.assets.active(state),"land":rules.land.active(state),"living":rules.living.active(state),"incidents":rules.incidents.active(state),"lifecycle":rules.lifecycle.active(state),"town":rules.lifecycle.town_active(state),"warfare":rules.warfare.active(state)}
	# Detached host status exposes the battle clock without hidden contacts.
	if app.defense_panel.host!=null:
		result.battle=_select_fields(app.defense_panel.host.status(),["phase","tick","quick"])
		return result
	var forecast: Dictionary=rules.forecast(state)
	result.forecast=_select_fields(forecast,["population","plan","gathered","used","unfed","overflow","spoil","food","food_delta","covered","wood","work","stocks"])
	result.forecast.factors={}
	for key in forecast.factors:
		result.forecast.factors[key]=[]
		for factor in forecast.factors[key]:result.forecast.factors[key].append({"name":p.copy.factor_names.get(factor.id,factor.id),"value":factor.value})
	if rules.assets.active(state):
		result.staffing=[]
		for request in forecast.assets.requests.slice(0,int(copy.limits.context_requests)):
			result.staffing.append(_select_fields(request,["id","asset","wanted","filled","reason"]))
		result.principles={}
		for spec in p.asset_panel.copy.principles:
			var index: int=rules.assets.principle(state,spec.id)
			result.principles[spec.label]=spec.options[index]
	if rules.living.active(state):result.living=_select_fields(state.living,["blanks","kits","prepare","training","repair","area","patrol","cooperate"])
	var presentation=ProjectPresentation.new()
	result.projects=[]
	var ids: Array=presentation.ids(state,rules)
	var detail: Dictionary=result.screen.get("detail",{})
	if detail.get("kind","")=="project" and detail.get("id","") in ids:
		ids.erase(detail.id)
		ids.push_front(detail.id)
	for id in ids.slice(0,int(copy.limits.context_projects)):
		var description: Dictionary=presentation.describe(state,rules,id,forecast)
		var project: Dictionary=_select_fields(description,["id","status","cause","cost_wood","cost_blanks","progress","total","remaining","crew","limit","work","paused","requires","benefit"])
		project.title=rules.projects[id].title
		project.refusal=p.reason(description.refusal) if description.refusal!="" else ""
		result.projects.append(project)
	if rules.lifecycle.active(state):
		var lifecycle: Dictionary=rules.lifecycle.status(state,rules)
		result.lifecycle=_select_fields(lifecycle,["stage","stage_name","project","ready","qualifying","seasons","required_seasons","upkeep"])
		result.lifecycle.factors=[]
		for factor in lifecycle.factors:
			var item: Dictionary=_select_fields(factor,["id","current","required","met","suspended","params","alternatives"])
			item.name=rules.lifecycle.content.factors.get(factor.id,rules.projects.get(factor.id,{}).get("title",factor.id))
			result.lifecycle.factors.append(item)
	if forecast.has("town"):result.town=_select_fields(forecast.town,["wanted","filled","condition","required","civic","maintained","service","service_wanted","prepared","saved"])
	var incident: Dictionary=rules.incidents.current(state)
	if not incident.is_empty() and int(incident.known)>=0:
		result.incident={"notice":p.incident_panel.notice(),"title":rules.incidents.specs[incident.id].title}
		if not incident.inspected.is_empty():result.incident.detail=rules.incidents.specs[incident.id].detail
	if not state.report.is_empty():result.last_season=_select_fields(state.report,["food","wood","gathered","used","unfed","overflow","spoil","losses","work"])
	return result
