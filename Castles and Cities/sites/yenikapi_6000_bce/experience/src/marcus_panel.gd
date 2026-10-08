extends Control
## Presentation-only counselor: a replayable local guide and explicit online chat.
## Each adapter supplies navigation and visible facts; neither issues orders.
const Portrait=preload("marcus_portrait.gd")
const Voice=preload("marcus_voice.gd")
signal opened_changed(active: bool)
signal advisor_requested(advisor_id: String)
signal refresh_requested
var adapter
var preference_path: String
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
var briefing_button: Button
var season_offer: Button
var _offer_pending: bool=false
var input_shield: Control
var council_body: VBoxContainer

func configure_context(context_adapter, auto_open: bool=true) -> void:
	adapter=context_adapter
	copy=adapter.content
	lessons=adapter.lessons
	preference_path=adapter.preference_path
	_load_preferences()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	name="MarcusAdvisor"
	voice=Voice.new()
	voice.advisor_id=String(copy.id)
	add_child(voice)
	voice.status_changed.connect(_status_changed)
	voice.answer_received.connect(_answer_received)
	voice.user_transcript.connect(_user_transcript)
	voice.speaking_changed.connect(_speaking_changed)
	voice.set_muted(_muted)
	_build()
	get_viewport().size_changed.connect(_layout)
	panel.minimum_size_changed.connect(_schedule_layout)
	panel.resized.connect(_schedule_layout)
	_layout()
	_schedule_layout()
	_sync_connection()
	refresh_briefing(false)
	if auto_open and not _intro_seen:open.call_deferred()

func _new_portrait():
	return adapter.create_portrait() if adapter.has_method("create_portrait") else Portrait.new()

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
	input_shield=Control.new()
	input_shield.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(input_shield)
	input_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_shield.hide()
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
	launcher_portrait=_new_portrait()
	launcher_portrait.custom_minimum_size=Vector2(60,60)
	launcher_portrait.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	launcher_row.add_child(launcher_portrait)
	var launcher_title:=_label(w("launcher"),17,"ded1a7")
	launcher_title.mouse_filter=Control.MOUSE_FILTER_IGNORE
	launcher_title.autowrap_mode=TextServer.AUTOWRAP_OFF
	launcher_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	launcher_title.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	launcher_row.add_child(launcher_title)

	season_offer=_button(w("review_season"),show_briefing,"MarcusSeasonOffer")
	season_offer.hide()
	add_child(season_offer)
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
	panel_portrait=_new_portrait()
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
	council_body=VBoxContainer.new()
	column.add_child(council_body)
	council_body.hide()
	var tabs:=HBoxContainer.new()
	column.add_child(tabs)
	guide_button=_button(w("guide"),_choose_tab.bind("guide"),"MarcusGuide")
	guide_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tabs.add_child(guide_button)
	chat_button=_button(w("conversation"),_choose_tab.bind("chat"),"MarcusChat")
	chat_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tabs.add_child(chat_button)

	briefing_button=_button(w("review_season"),show_briefing,"MarcusSeasonReview")
	column.add_child(briefing_button)
	briefing_button.hide()
	if adapter.has_method("city_reading"):
		column.add_child(_button(w("city_reading"),show_city_reading,"AdvisorCityReading"))
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
	season_offer.position=Vector2(maxf(8,viewport.x-454),maxf(8,viewport.y-70))
	season_offer.size=Vector2(242,36)
	var height:=minf(730.0,maxf(300.0,viewport.y-122))
	panel.position=Vector2(maxf(8,viewport.x-width-16),maxf(16,viewport.y-106-height))
	panel.size=Vector2(width,height)

func _schedule_layout() -> void:
	# Autowrapped labels initially measure at zero width and can enlarge the
	# panel before container sorting. Godot retains that oversized rectangle
	# after their minimum shrinks; reclamp when the real width has settled.
	if _layout_pending:return
	_layout_pending=true
	_flush_layout.call_deferred()

func _flush_layout() -> void:
	# Let containers sort new council labels at their real width before
	# reclamping: deferred callbacks alone can precede the final minimum update.
	await get_tree().process_frame
	_layout_pending=false
	_layout()

func _process(_delta: float) -> void:
	# Deep autowrapped children can settle after the deferred resize without
	# another parent minimum signal. Correct only a now-shrinkable overflow.
	if not is_open():return
	var height:=minf(730.0,maxf(300.0,get_viewport_rect().size.y-122))
	if panel.size.y>height and panel.get_combined_minimum_size().y<=height:
		_layout()

func is_open() -> bool:
	return is_instance_valid(panel) and panel.is_visible_in_tree()

func open() -> void:
	refresh_requested.emit()
	adapter.prepare_open()
	panel.show()
	input_shield.show()
	season_offer.hide()
	opened_changed.emit(true)
	_layout()
	_render_guide()
	_sync_connection()
	if _tab=="chat":question.grab_focus()
	else:panel.find_child("MarcusClose",true,false).grab_focus()

func close_panel() -> void:
	if _mode=="intro":_intro_seen=true
	# Hidden captions must never accompany continuing speech or a billed session.
	voice.stop()
	_awaiting_response=false
	_reply_index=-1
	_save_preferences()
	panel.hide()
	input_shield.hide()
	season_offer.visible=_offer_pending
	opened_changed.emit(false)
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

func _input(event: InputEvent) -> void:
	if not is_open() or not event is InputEventKey or not event.pressed:return
	if event.keycode==KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()
	elif event.keycode==KEY_TAB:
		# Keep keyboard focus inside the advisor just as the shield keeps clicks
		# out of the game. Enter must never activate an underlying turn/order.
		var controls: Array[Control]=[]
		_focusable(panel,controls)
		if not controls.is_empty():
			var index: int=controls.find(get_viewport().gui_get_focus_owner())
			controls[posmod(index+(-1 if event.shift_pressed else 1),controls.size())].grab_focus()
		get_viewport().set_input_as_handled()
	else:
		var focus: Control=get_viewport().gui_get_focus_owner()
		if focus==null or not panel.is_ancestor_of(focus):
			panel.find_child("MarcusClose",true,false).grab_focus()
			get_viewport().set_input_as_handled()

func _focusable(node: Node,result: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree():
			if child.focus_mode==Control.FOCUS_ALL and not (child is BaseButton and child.disabled):result.append(child)
			_focusable(child,result)

func _render_guide() -> void:
	if not is_instance_valid(guide_body):return
	for child in guide_body.get_children():
		guide_body.remove_child(child)
		child.queue_free()
	lesson_speech=null
	if _mode=="briefing":
		_render_briefing()
	elif _mode=="reading":
		_render_city_reading()
	elif _mode=="intro":
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
	return adapter.navigation_blocked(lessons[_lesson])

func _show_lesson_place() -> void:
	if _navigation_blocked()!="":_render_guide();return
	adapter.navigate(lessons[_lesson],_lesson)
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
	if config.load(preference_path)!=OK:return
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
	config.save(preference_path)

func context_snapshot() -> Dictionary:
	var result: Dictionary=adapter.context_snapshot()
	result.guide={"mode":_mode,"index":_intro_step if _mode=="intro" else _lesson}
	if _mode=="intro":result.guide.page=copy.intro[_intro_step].duplicate(true)
	elif _mode=="briefing":result.guide.page=adapter.season_briefing()
	elif _mode=="reading":result.guide.page=adapter.city_reading()
	else:
		result.guide.page=lessons[_lesson].duplicate(true)
		result.guide.counsel=copy.lesson_counsel[_lesson]
	return result

func reset_conversation() -> void:
	close_panel()
	_conversation.clear()
	_render_transcript()
	refresh_briefing(false)

func refresh_briefing(offer: bool=true) -> void:
	var available: bool=not adapter.season_briefing().is_empty()
	briefing_button.visible=available
	_offer_pending=offer and available
	season_offer.visible=_offer_pending and not is_open()
	if _mode=="briefing":_render_guide()
	_schedule_layout()

func show_briefing() -> void:
	_offer_pending=false
	_mode="briefing"
	_choose_tab("guide")
	open()

func _render_briefing() -> void:
	var briefing: Dictionary=adapter.season_briefing()
	guide_body.add_child(_label(w("season_title"),25,"eee3c2"))
	guide_body.add_child(_label(String(briefing.get("date","")),15,"b8ccb9"))
	guide_body.add_child(_label(w("season_help"),14))
	var lines: Array=briefing.get("lines",[])
	if lines.is_empty():guide_body.add_child(_label(w("season_quiet"),16))
	for line in lines:guide_body.add_child(_label(String(line),15))
	if briefing.get("omitted",0)>0:guide_body.add_child(_label(w("season_more"),12,"b8ccb9"))
	guide_body.add_child(_button(w("restart"),_choose_lesson.bind(0),"MarcusReturnLessons"))

func set_council(choices: Array, detail: String) -> void:
	for child in council_body.get_children():
		council_body.remove_child(child)
		child.queue_free()
	council_body.visible=not choices.is_empty()
	var row:=HBoxContainer.new()
	council_body.add_child(row)
	for choice in choices:
		var button:=_button(choice.label,func():advisor_requested.emit(choice.id))
		button.disabled=not choice.available or choice.id==copy.id
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(button)
	council_body.add_child(_label(detail,12,"b8c5b8"))
	_schedule_layout()

func show_city_reading() -> void:
	_mode="reading"
	_choose_tab("guide")
	open()

func _render_city_reading() -> void:
	var reading: Dictionary=adapter.city_reading()
	guide_body.add_child(_label(reading.title,25,"eee3c2"))
	guide_body.add_child(_label(reading.note,14))
	for section in reading.get("sections",[]):
		guide_body.add_child(_label(section.title,18,"b8ccb9"))
		for line in section.lines:guide_body.add_child(_label(line,15))
	guide_body.add_child(_button(w("restart"),_choose_lesson.bind(0)))
