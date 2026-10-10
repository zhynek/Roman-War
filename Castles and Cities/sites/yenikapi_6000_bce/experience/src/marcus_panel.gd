extends Control
## Presentation-only counselor: a replayable local guide and explicit online chat.
## Each adapter supplies navigation and visible facts; neither issues orders.
const Portrait=preload("marcus_portrait.gd")
const Voice=preload("marcus_voice.gd")
signal opened_changed(active: bool)
signal advisor_requested(advisor_id: String)
signal council_speaker_requested(advisor_id: String)
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
var page_navigation: HFlowContainer
var _patronage_confirmation: Dictionary={}
var _patronage_notice: String=""
var tutorial_offer: Button
var _tutorial_id: String=""
var _tutorial_pending: bool=false
var succession_offer: Button
var _succession_pending: bool=false
var _succession_notice := ""
var _succession_opened_key := ""
var _live_status: Label
var _live_text: RichTextLabel
var _live_hear: Button
var _live_help: Label
var _live_portrait
var _live_portrait_slot: HBoxContainer
var _live_portrait_id := ""
var _live_card: Control
var _live_caption_height := 128.0
var _dilemma_confirmation: Dictionary={}
var _dilemma_notice := ""
var _memory_source_ref := ""
var _memory_notice := ""

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

	season_offer=_button(_review_label(),show_briefing,"MarcusSeasonOffer")
	season_offer.hide()
	add_child(season_offer)
	if adapter.has_method("tutorial_page") and copy.id=="marcus":
		tutorial_offer=_button(tw("invitation"),show_tutorial,"MarcusTutorialOffer")
		tutorial_offer.hide()
		add_child(tutorial_offer)
	if adapter.has_method("succession_page") and copy.id=="marcus":
		succession_offer=_button(sw("invitation"),show_succession_council,"MarcusSuccessionOffer")
		succession_offer.hide()
		add_child(succession_offer)
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

	page_navigation=HFlowContainer.new()
	column.add_child(page_navigation)
	briefing_button=_button(_review_label(),show_briefing,"MarcusSeasonReview")
	page_navigation.add_child(briefing_button)
	briefing_button.hide()
	if adapter.has_method("advisor_reading") or adapter.has_method("city_reading"):
		var reading_label: String=adapter.reading_label() if adapter.has_method("reading_label") else w("city_reading")
		page_navigation.add_child(_button(reading_label,show_city_reading,"AdvisorCityReading"))
	if adapter.has_method("patronage_page"):
		page_navigation.add_child(_button(cw("patronage"),show_patronage,"AdvisorPatronage"))
	if adapter.has_method("dilemma_page"):
		page_navigation.add_child(_button(dw("navigation"),show_dilemmas,"AdvisorDilemmas"))
	if adapter.has_method("memory_page"):
		page_navigation.add_child(_button(mw("navigation"),show_memory,"AdvisorMemory"))
	if adapter.has_method("succession_page"):
		page_navigation.add_child(_button(sw("navigation"),show_succession_council,"AdvisorSuccessionCouncil"))
	if tutorial_offer!=null:
		page_navigation.add_child(_button(tw("history"),show_tutorial_archive,"MarcusTutorialArchive"))
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
	var wide: bool=_tab=="guide" and _mode in ["council","patronage","tutorial","dilemmas","memory"]
	var width: float=minf(780.0 if wide else 460.0,maxf(250.0,viewport.x-32.0))
	launcher.position=Vector2(maxf(8,viewport.x-198),maxf(8,viewport.y-90))
	launcher.size=Vector2(182,74)
	season_offer.position=Vector2(maxf(8,viewport.x-454),maxf(8,viewport.y-70))
	season_offer.size=Vector2(242,36)
	if tutorial_offer!=null:
		tutorial_offer.position=season_offer.position
		tutorial_offer.size=season_offer.size
	if succession_offer!=null:
		succession_offer.position=season_offer.position
		succession_offer.size=season_offer.size
	var height:=minf(730.0,maxf(300.0,viewport.y-122))
	panel.position=Vector2(maxf(8,viewport.x-width-16),maxf(16,viewport.y-106-height))
	panel.size=Vector2(width,height)
	var seats=guide_body.get_node_or_null("CouncilSeats")
	if seats!=null:seats.columns=2 if viewport.x>=800 else 1

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
	if tutorial_offer!=null:tutorial_offer.hide()
	if succession_offer!=null:succession_offer.hide()
	opened_changed.emit(true)
	_layout()
	_render_guide()
	_sync_connection()
	if _tab=="chat":question.grab_focus()
	else:panel.find_child("MarcusClose",true,false).grab_focus()

func close_panel() -> void:
	_stop_living_council()
	if _mode=="intro":_intro_seen=true
	# Hidden captions must never accompany continuing speech or a billed session.
	voice.stop()
	_awaiting_response=false
	_reply_index=-1
	_save_preferences()
	panel.hide()
	input_shield.hide()
	season_offer.visible=_offer_pending
	refresh_tutorial_offer()
	opened_changed.emit(false)
	var focus: Control=get_viewport().gui_get_focus_owner()
	if focus!=null and is_ancestor_of(focus):focus.release_focus()

func _choose_tab(tab: String) -> void:
	if tab!="guide":_stop_living_council()
	_tab=tab
	guide_scroll.visible=tab=="guide"
	page_navigation.visible=tab=="guide"
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
	_live_status=null;_live_text=null;_live_hear=null;_live_help=null;_live_portrait=null;_live_portrait_slot=null;_live_portrait_id="";_live_card=null
	if _mode!="council":_stop_living_council()
	guide_body.tooltip_text=""
	if _mode=="briefing":
		_render_briefing()
	elif _mode=="council":
		_render_council_page()
	elif _mode=="dilemmas":
		_render_dilemmas()
	elif _mode=="memory":
		_render_memory()
	elif _mode=="patronage":
		_render_patronage_page()
	elif _mode=="reading":
		_render_city_reading()
	elif _mode=="tutorial":
		_render_tutorial()
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
	if _living_active():_stop_living_council();return
	if _mode=="council" and _tab=="guide" and adapter.has_method("start_living_council"):_hear_council();return
	if voice.is_agent_connected() or _status_code=="connecting":
		voice.stop()
		return
	if not _validate_memory_focus():return
	voice.connect_agent(context_snapshot())

func _toggle_mute() -> void:
	if _living_active():
		var discussion=adapter.living_council_state()
		discussion.set_muted(not discussion.muted)
		return
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
	if _living_active():
		var discussion=adapter.living_council_state()
		status_label.text=cw("live_"+discussion.status).format({"name":String(discussion.speaker).capitalize()})
		connect_button.text=cw("live_stop")
		mute_button.text=cw("live_unmute" if discussion.muted else "live_mute")
		send_button.disabled=true
		return
	var connected: bool=voice.is_agent_connected()
	status_label.text=copy.status.get(_status_code,copy.status.unavailable)
	if _status_code in ["setup_required","unconfigured","agent_private_required"]:status_label.text+="\n"+w("setup_note")
	connect_button.text=cw("hear_council") if _mode=="council" and _tab=="guide" and adapter.has_method("start_living_council") else w("disconnect" if connected or _status_code=="connecting" else "connect")
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
	if not _validate_memory_focus():return
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
	_validate_memory_focus()
	var result: Dictionary=adapter.context_snapshot()
	result.guide={"mode":_mode,"index":_intro_step if _mode=="intro" else _lesson}
	if _mode=="intro":result.guide.page=copy.intro[_intro_step].duplicate(true)
	elif _mode=="briefing":result.guide.page=adapter.season_briefing()
	elif _mode=="reading":result.guide.page={"source":"advisor_reading"}
	elif _mode=="council":result.guide.page={"source":"council_session", "title":cw("title")}
	elif _mode=="memory":result.guide.page={"source":"campaign_memory"}
	elif _mode=="tutorial":
		result.guide.page={"source":"reactive_tutorial","id":_tutorial_id}
		for card in adapter.tutorial_page().get("milestones",[]):
			if card.id==_tutorial_id:result.guide.page=card.duplicate(true)
	elif _mode=="dilemmas":
		result.guide.page=adapter.dilemma_snapshot()
		if not _dilemma_confirmation.is_empty():
			result.guide.page.uncommitted_choice=_dilemma_confirmation.duplicate(true)
			result.guide.page.uncommitted_choice.erase("signature")
	elif _mode=="patronage":
		result.guide.page={"source":"patronage", "title":cw("patronage_title")}
		if not _patronage_confirmation.is_empty():result.guide.page.uncommitted_choice=_patronage_confirmation.duplicate(true)
	else:
		result.guide.page=lessons[_lesson].duplicate(true)
		result.guide.counsel=copy.lesson_counsel[_lesson]
	return result

func reset_conversation() -> void:
	_succession_notice="";_succession_pending=false;_succession_opened_key=""
	_memory_source_ref="";_memory_notice=""
	if adapter.has_method("memory_focus"):adapter.memory_focus("")
	_dilemma_confirmation.clear();_dilemma_notice=""
	_stop_living_council()
	close_panel()
	_patronage_confirmation.clear()
	_patronage_notice=""
	_tutorial_id=""
	if _mode in ["council","patronage","briefing","reading","tutorial","dilemmas","memory"]:_mode="guide"
	question.clear()
	message.text=""
	_conversation.clear()
	_render_transcript()
	refresh_briefing(false)
	refresh_tutorial_offer()

func refresh_briefing(offer: bool=true) -> void:
	var available: bool=not adapter.season_briefing().is_empty()
	briefing_button.visible=available or adapter.has_method("council_page")
	_offer_pending=offer and available
	season_offer.visible=_offer_pending and not is_open()
	refresh_tutorial_offer()
	if _mode in ["briefing","council","patronage","memory"]:_render_guide()
	_schedule_layout()

func show_briefing() -> void:
	_succession_notice="";_succession_opened_key=""
	if adapter.has_method("seasonal_council_select"):adapter.seasonal_council_select()
	_offer_pending=false
	_mode="council" if adapter.has_method("council_page") else "briefing"
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
		button.tooltip_text=choice.get("detail","")
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(button)
	council_body.add_child(_label(detail,12,"b8c5b8"))
	_schedule_layout()

func show_city_reading() -> void:
	_mode="reading"
	_choose_tab("guide")
	open()

func _render_city_reading() -> void:
	var reading: Dictionary=adapter.advisor_reading() if adapter.has_method("advisor_reading") else adapter.city_reading()
	guide_body.add_child(_label(reading.title,25,"eee3c2"))
	guide_body.add_child(_label(reading.note,14))
	for section in reading.get("sections",[]):
		guide_body.add_child(_label(section.title,18,"b8ccb9"))
		for line in section.lines:guide_body.add_child(_label(line,15))
	guide_body.add_child(_button(w("restart"),_choose_lesson.bind(0)))

func cw(id: String) -> String:
	return String(adapter.council_words().get(id,id))

func _review_label() -> String:
	return cw("council") if adapter.has_method("council_page") else w("review_season")

func _card(background: String="203832",parent: Control=null) -> VBoxContainer:
	var frame:=PanelContainer.new()
	frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel",_style(background))
	(parent if parent!=null else guide_body).add_child(frame)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	frame.add_child(body)
	return body

func open_council_question(text: String) -> void:
	_mode="council"
	_choose_tab("chat")
	open()
	_fill_question(text)

func _render_council_page() -> void:
	var page: Dictionary=adapter.council_page()
	if page.get("blocked","")!="":
		guide_body.add_child(_label(cw(page.blocked),15))
		return
	var succession: Dictionary=adapter.succession_page() if adapter.has_method("succession_page") else {}
	if not succession.is_empty():_render_succession_briefing(succession)
	_render_living_council()
	if succession.get("available",false) and succession.get("selected",false):
		if is_instance_valid(_live_hear):_live_hear.text=sw("listen")
		_render_succession_sources(succession)
	guide_body.add_child(_label(cw("source"),11,"cabb87"))
	guide_body.add_child(_label(cw("title"),25,"eee3c2"))
	guide_body.add_child(_label(cw("help"),13,"b8c5b8"))
	var season: Dictionary=page.get("season",{})
	if season.is_empty():guide_body.add_child(_label(cw("no_season"),14,"d4bd93"))
	else:
		guide_body.add_child(_label(cw("latest").format(season),14,"cabb87"))
		if season.get("stale",false):
			guide_body.add_child(_label(cw("stale").format({"turn":season.turn,"current":page.current_turn}),13,"d4bd93"))
	var seats:=GridContainer.new()
	seats.name="CouncilSeats"
	seats.columns=2 if get_viewport_rect().size.x>=800 else 1
	seats.add_theme_constant_override("h_separation",12)
	seats.add_theme_constant_override("v_separation",12)
	guide_body.add_child(seats)
	for speaker in page.get("speakers",[]):
		var body:=_card("203832" if speaker.id=="marcus" else "302f3b",seats)
		var identity:=HBoxContainer.new()
		identity.add_theme_constant_override("separation",12)
		body.add_child(identity)
		var portrait=adapter.council_portrait(String(speaker.id))
		portrait.custom_minimum_size=Vector2(58,58)
		portrait.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		identity.add_child(portrait)
		var name_label:=_label(speaker.name,23,"eee3c2")
		name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		identity.add_child(name_label)
		if not speaker.available:
			body.add_child(_label(speaker.get("locked",cw("lucius_locked")),14,"b8c5b8"))
			continue
		body.add_child(_label(speaker.stance,13,"cabb87"))
		body.add_child(_label(speaker.counsel,16))
		for key in ["city","season"]:
			if speaker.has(key):body.add_child(_label(speaker[key],14,"b8ccb9"))
		if speaker.get("mandate","")!="":
			body.add_child(_label(cw("mandate"),13,"cabb87"))
			body.add_child(_label(speaker.mandate,14,"b8c5b8"))
		body.add_child(_button(cw("ask").format({"name":speaker.name}),_council_speaker.bind(String(speaker.id)),"CouncilAsk"+String(speaker.name)))
	var city: Dictionary=page.get("city",{})
	if city.is_empty():guide_body.add_child(_label(cw("no_city"),14,"b8c5b8"))
	else:
		guide_body.add_child(_label(cw("city").format({"city":city.name}),21,"eee3c2"))
		guide_body.add_child(_label(cw("survey").format({"level":city.society.get("level",""),"age":city.society.get("stale_turns",0)}),13,"b8c5b8"))
		guide_body.add_child(_label(cw("tax").format({"tax":city.tax_level}),14))
		for key in ["public_order","growth","income"]:
			guide_body.add_child(_label(cw(key),17,"cabb87"))
			for factor in city.factors.get(key,[]):
				guide_body.add_child(_label("%s: %+.1f"%[String(factor.label).replace("_"," ").capitalize(),float(factor.value)],13))
		guide_body.add_child(_label(cw("factors_limited").format({"limit":city.factor_limit}),12,"b8c5b8"))
		guide_body.add_child(_label(cw("city_question"),16,"b8ccb9"))
	guide_body.add_child(_label(cw("reports"),21,"eee3c2"))
	if season.get("lines",[]).is_empty():guide_body.add_child(_label(cw("quiet"),14,"b8c5b8"))
	for line in season.get("lines",[]):guide_body.add_child(_label(String(line),14))
	if int(season.get("omitted",0))>0:
		guide_body.add_child(_label(cw("omitted").format({"count":season.omitted}),12,"d4bd93"))
	guide_body.add_child(_button(cw("return"),_choose_lesson.bind(0)))

func _council_speaker(id: String) -> void:
	council_speaker_requested.emit(id)

func sw(id: String) -> String:
	return String(adapter.succession_words().get(id,id))

func show_succession_council(key: String="") -> void:
	var page: Dictionary=adapter.succession_page()
	var selected_key: String=String(page.get("key","")) if key.is_empty() else key
	_succession_notice=""
	if not page.get("available",false):
		_succession_notice="no_briefing"
	elif not adapter.succession_select(selected_key):
		_succession_notice="stale_note"
	else:_succession_opened_key=selected_key
	_offer_pending=false
	_mode="council";_choose_tab("guide");open()

func _render_succession_briefing(page: Dictionary) -> void:
	if not _succession_opened_key.is_empty() and (not page.get("available",false) or not page.get("selected",false) or page.get("key","")!=_succession_opened_key):
		_succession_notice="stale_note"
		_succession_opened_key=""
	if _succession_notice!="":guide_body.add_child(_label(sw(_succession_notice),14,"d4bd93"))
	if not page.get("available",false):
		if _succession_notice=="" and page.get("selected",false):guide_body.add_child(_label(sw("stale_note"),14,"d4bd93"))
		return
	if not page.get("selected",false):
		guide_body.add_child(_button(sw("navigation"),show_succession_council.bind(String(page.key)),"CouncilReplaySuccession"))
		return
	var body:=_card("34382b")
	body.add_child(_label(String(page.get("title",sw("title"))),24,"eee3c2"))
	if String(page.get("notice",""))!="":body.add_child(_label(String(page.notice),14,"d4bd93"))
	var status: String=page.get("status","")
	if status in ["acknowledged","reviewed","dismissed"]:
		body.add_child(_label(sw("reviewed" if status=="acknowledged" else status),13,"cabb87"))
	if int(page.get("postponed_until",0))>0:
		body.add_child(_label(sw("postponed").format({"turn":page.postponed_until}),13,"cabb87"))
	var actions:=HFlowContainer.new()
	body.add_child(actions)
	for action in ["acknowledge","postpone","dismiss"]:
		var button:=_button(sw(action),_succession_respond.bind(String(page.key),String(action)),"SuccessionCouncil"+String(action).capitalize())
		button.disabled=status!="pending" or page.get("blocked","")!=""
		actions.add_child(button)
	var navigation:=HFlowContainer.new()
	body.add_child(navigation)
	navigation.add_child(_button(sw("refresh"),_refresh_succession,"SuccessionCouncilRefresh"))
	navigation.add_child(_button(sw("current_council"),show_briefing,"SuccessionCouncilCurrent"))

func _render_succession_sources(page: Dictionary) -> void:
	var body:=_card("28332d")
	body.add_child(_label(sw("source_note"),13,"cabb87"))
	body.add_child(_label(sw("help"),14,"b8c5b8"))
	for section in page.get("sections",[]):
		body.add_child(_label(String(section.title),18,"eee3c2"))
		for line in section.get("lines",[]):body.add_child(_label(String(line),14))

func _succession_respond(key: String,action: String) -> void:
	_succession_notice="" if adapter.succession_respond(key,action) else "stale_note"
	refresh_tutorial_offer()
	_render_guide()

func _refresh_succession() -> void:
	_succession_notice=""
	refresh_tutorial_offer()
	_render_guide()

func show_patronage() -> void:
	_patronage_confirmation.clear()
	_patronage_notice=""
	_mode="patronage"
	_choose_tab("guide")
	open()

func _render_patronage_page() -> void:
	var page: Dictionary=adapter.patronage_page()
	guide_body.add_child(_label(cw("divine_source"),11,"cabb87"))
	guide_body.add_child(_label(cw("patronage_title"),25,"eee3c2"))
	if page.get("blocked","")!="":
		guide_body.add_child(_label(cw(page.blocked),15))
		return
	guide_body.add_child(_label(cw("patronage_help"),14,"b8c5b8"))
	guide_body.add_child(_label(page.get("fiction",""),12,"b8c5b8"))
	if _patronage_notice!="":guide_body.add_child(_label(cw(_patronage_notice),15,"d4bd93"))
	var status: Dictionary=page.status
	var blocked: String=status.get("command_blocked","")
	if blocked!="":guide_body.add_child(_label(cw("finished" if blocked=="campaign_finished" else "blocked"),14,"d4bd93"))
	if not _patronage_confirmation.is_empty():
		_render_patronage_confirmation(blocked!="")
		return
	var active: Dictionary=status.get("active",{})
	if not active.is_empty():
		var body:=_card("343426")
		body.add_child(_label(cw("chosen").format({"name":active.name,"turn":status.pledged_turn}),20,"eee3c2"))
		body.add_child(_label(active.mission,15))
		if active.get("completed",false):body.add_child(_label(cw("fulfilled"),14,"b8ccb9"))
		else:
			body.add_child(_label(cw("progress").format({"progress":status.progress,"target":status.target,"turn":status.last_checked_turn}),14,"cabb87"))
			if int(status.last_checked_turn)<=int(status.pledged_turn):body.add_child(_label(cw("awaiting"),13,"b8c5b8"))
			if not status.get("has_matching_temple",false):body.add_child(_label(cw("temple_lost"),14,"d4bd93"))
		var renounce:=_button(cw("renounce"),_consider_renounce,"PatronageRenounce")
		renounce.disabled=blocked!=""
		body.add_child(renounce)
	for option in status.get("options",[]):
		var body:=_card("26333e" if option.id=="zeus" else "3b2c2a")
		body.add_child(_label(option.name,24,"eee3c2"))
		body.add_child(_label(option.address,18,"cabb87"))
		body.add_child(_label(cw("mission"),14,"b8ccb9"))
		body.add_child(_label(option.mission,15))
		body.add_child(_label(cw("tradeoff"),14,"b8ccb9"))
		body.add_child(_label(option.tradeoff,14))
		if option.get("completed",false):body.add_child(_label(cw("remembered"),13,"cabb87"))
		var temples: Array=option.get("temples",[])
		body.add_child(_label(cw("temples"),14,"b8ccb9"))
		body.add_child(_label(", ".join(option.get("required_temples",[])),14,"cabb87"))
		if temples.is_empty():
			body.add_child(_label(cw("temple_needed"),14,"b8c5b8"))
			continue
		body.add_child(_label(cw("select_seat"),13,"b8c5b8"))
		var picker:=OptionButton.new()
		picker.name="PatronageSeat"+String(option.id).capitalize()
		picker.clip_text=true
		picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for temple in temples:
			picker.add_item(cw("temple_seat").format({"city":temple.city,"temple":temple.name,"level":temple.level}))
			picker.set_item_metadata(picker.item_count-1,temple)
		body.add_child(picker)
		var pledge:=_button(cw("pledge").format({"name":option.name}),_consider_pledge.bind(String(option.id),String(option.name),picker),"PatronagePledge"+String(option.id).capitalize())
		pledge.disabled=blocked!="" or status.get("chosen","")==option.id
		body.add_child(pledge)
	guide_body.add_child(_button(cw("return"),_choose_lesson.bind(0)))

func _consider_pledge(id: String,patron_name: String,picker: OptionButton) -> void:
	if picker.selected<0:return
	var temple: Dictionary=picker.get_item_metadata(picker.selected)
	_patronage_confirmation={"action":"pledge","id":id,"name":patron_name,"region":temple.region,"city":temple.city}
	_patronage_notice=""
	_render_guide()

func _consider_renounce() -> void:
	_patronage_confirmation={"action":"renounce","id":"","region":""}
	_patronage_notice=""
	_render_guide()

func _render_patronage_confirmation(blocked: bool) -> void:
	var body:=_card("343426")
	body.add_child(_label(cw("confirm_title"),21,"eee3c2"))
	body.add_child(_label(cw("confirm_pledge" if _patronage_confirmation.action=="pledge" else "confirm_renounce").format(_patronage_confirmation),16))
	var confirm:=_button(cw("confirm"),_commit_patronage,"PatronageConfirm")
	confirm.disabled=blocked
	body.add_child(confirm)
	body.add_child(_button(cw("cancel"),_cancel_patronage,"PatronageCancel"))

func _cancel_patronage() -> void:
	_patronage_confirmation.clear()
	_render_guide()

func tw(id: String) -> String:
	return String(adapter.tutorial_words().get(id,id))

func refresh_tutorial_offer() -> void:
	_tutorial_pending=false
	if tutorial_offer!=null:
		var page: Dictionary=adapter.tutorial_page()
		_tutorial_pending=page.get("blocked","")=="" and not page.get("eligible",[]).is_empty()
	refresh_succession_offer()

func refresh_succession_offer() -> void:
	_succession_pending=false
	if succession_offer!=null:
		var page: Dictionary=adapter.succession_page()
		_succession_pending=page.get("blocked","")=="" and page.get("eligible",false)
		succession_offer.visible=_succession_pending and not is_open()
	if tutorial_offer!=null:tutorial_offer.visible=_tutorial_pending and not _succession_pending and not is_open()
	season_offer.visible=_offer_pending and not _tutorial_pending and not _succession_pending and not is_open()

func show_tutorial() -> void:
	var page: Dictionary=adapter.tutorial_page()
	if not page.get("eligible",[]).is_empty():_tutorial_id=page.eligible[0].id
	_mode="tutorial"
	_choose_tab("guide")
	open()

func show_tutorial_archive() -> void:
	_mode="tutorial"
	_choose_tab("guide")
	open()

func _render_tutorial() -> void:
	var page: Dictionary=adapter.tutorial_page()
	guide_body.add_child(_label(tw("title"),25,"eee3c2"))
	if page.get("blocked","")!="":
		guide_body.add_child(_label(tw("blocked"),15))
		return
	guide_body.tooltip_text=tw("source")
	var cards: Array=page.get("milestones",[])
	if cards.is_empty():
		guide_body.add_child(_label(tw("empty"),15))
		return
	var selected:=0
	var picker:=OptionButton.new()
	picker.name="MarcusEncounterPicker"
	picker.clip_text=true
	for i in range(cards.size()):
		picker.add_item(cards[i].title)
		if cards[i].id==_tutorial_id:selected=i
	_tutorial_id=cards[selected].id
	picker.selected=selected
	picker.item_selected.connect(func(index):_tutorial_id=cards[index].id;_render_guide())
	guide_body.add_child(picker)
	var card: Dictionary=cards[selected]
	guide_body.add_child(_label(tw(String(card.get("status","unseen"))),12,"cabb87"))
	if int(card.get("postponed_until",0))>int(page.get("turn",0)):
		guide_body.add_child(_label(tw("postponed").format({"turn":card.postponed_until}),12,"cabb87"))
	guide_body.add_child(_label(adapter.tutorial_text(card.body,card.get("params",{})),16))
	var navigation:=HFlowContainer.new()
	guide_body.add_child(navigation)
	navigation.add_child(_button(tw("show_me"),_tutorial_show_place,"MarcusEncounterShowMe"))
	navigation.add_child(_button(tw("ask"),_tutorial_ask.bind(String(card.get("question",""))),"MarcusEncounterAsk"))
	var actions:=HFlowContainer.new()
	guide_body.add_child(actions)
	for action in ["acknowledge","postpone","dismiss"]:
		var button:=_button(tw(action),_tutorial_respond.bind(String(action)),"MarcusEncounter"+String(action).capitalize())
		button.disabled=card.get("status","unseen")!="pending"
		actions.add_child(button)
	picker.tooltip_text=tw("help")

func _tutorial_respond(action: String) -> void:
	adapter.tutorial_respond(_tutorial_id,action)
	refresh_tutorial_offer()
	_render_guide()

func _tutorial_show_place() -> void:
	if adapter.tutorial_navigate(_tutorial_id):close_panel()

func _tutorial_ask(text: String) -> void:
	_choose_tab("chat")
	_fill_question(text)

func _commit_patronage() -> void:
	if _patronage_confirmation.is_empty():return
	_patronage_notice=adapter.commit_patronage(_patronage_confirmation.action,_patronage_confirmation.id,_patronage_confirmation.region)
	_patronage_confirmation.clear()
	_render_guide()

func _living_active() -> bool:
	return adapter!=null and adapter.has_method("living_council_state") and is_instance_valid(adapter.living_council_state()) and adapter.living_council_state().active

func _stop_living_council() -> void:
	if adapter!=null and adapter.has_method("stop_living_council"):adapter.stop_living_council()

func _render_living_council() -> void:
	if not adapter.has_method("living_council_state"):return
	var body:=_card("303829")
	_live_card=body.get_parent()
	_live_caption_height=128.0
	body.add_child(_label(cw("live_source"),11,"cabb87"))
	_live_help=_label(cw("live_help"),13,"b8c5b8")
	body.add_child(_live_help)
	_live_hear=_button(cw("hear_council"),_hear_council,"HearLivingCouncil")
	body.add_child(_live_hear)
	_live_portrait_slot=HBoxContainer.new()
	body.add_child(_live_portrait_slot)
	_live_status=_label("",14,"cabb87")
	_live_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_live_portrait_slot.add_child(_live_status)
	_live_text=RichTextLabel.new()
	_live_text.name="LivingCouncilTranscript"
	_live_text.bbcode_enabled=false
	_live_text.selection_enabled=true
	_live_text.scroll_following=true
	_live_text.fit_content=true
	_live_text.scroll_active=false
	_live_text.add_theme_font_size_override("normal_font_size",16)
	body.add_child(_live_text)
	refresh_living_council()

func _hear_council() -> void:
	adapter.start_living_council(_muted)
	refresh_living_council()
	_focus_living_council()

func _focus_living_council() -> void:
	# Only an explicit Hear request moves the reading position. Let the hidden
	# controls and wrapped status settle before fitting and revealing captions.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_open() or _mode!="council" or _tab!="guide" or not is_instance_valid(_live_card):return
	if _live_text.scroll_active:
		var overhead: float=_live_card.size.y-_live_text.size.y
		_live_caption_height=clampf(guide_scroll.size.y-overhead-4.0,64.0,128.0)
		_live_text.custom_minimum_size.y=_live_caption_height
		await get_tree().process_frame
		await get_tree().process_frame
	if not is_open() or _mode!="council" or _tab!="guide" or not is_instance_valid(_live_card):return
	guide_scroll.ensure_control_visible(_live_card)

func refresh_living_council() -> void:
	if adapter==null or not adapter.has_method("living_council_state"):return
	var discussion=adapter.living_council_state()
	if not is_instance_valid(discussion):return
	_sync_connection()
	if not is_instance_valid(_live_status):return
	_live_hear.disabled=discussion.active
	var discussing: bool=discussion.active or not discussion.turns.is_empty()
	_live_hear.visible=not discussing
	_live_help.visible=not discussing
	_live_text.fit_content=not discussing
	_live_text.scroll_active=discussing
	_live_text.custom_minimum_size.y=_live_caption_height if discussing else 0
	var lines:=PackedStringArray()
	for turn in discussion.turns:
		lines.append(String(turn.name)+"\n"+String(turn.text))
	_live_text.text="\n\n".join(lines) if not lines.is_empty() else cw("live_empty")
	_live_status.text=cw("live_"+discussion.status).format({"name":String(discussion.speaker).capitalize()})
	if not discussion.snapshot.is_empty():
		_live_status.text+="\n"+cw("live_snapshot").format({"date":discussion.snapshot.last_resolved_season.date,"city":discussion.snapshot.city.name})
	if discussion.speaker!="" and discussion.speaker!=_live_portrait_id:
		if is_instance_valid(_live_portrait):_live_portrait_slot.remove_child(_live_portrait);_live_portrait.queue_free()
		_live_portrait_id=discussion.speaker
		_live_portrait=adapter.council_portrait(discussion.speaker)
		_live_portrait.custom_minimum_size=Vector2(54,54)
		_live_portrait.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		_live_portrait_slot.add_child(_live_portrait)
		_live_portrait_slot.move_child(_live_portrait,0)
	if is_instance_valid(_live_portrait):_live_portrait.set_speaking(discussion.active and discussion.voice._speaking)

func mw(id: String) -> String:
	return String(adapter.memory_words().get(id,id))

func show_memory() -> void:
	_memory_notice=""
	_mode="memory";_choose_tab("guide");open()

func _render_memory() -> void:
	_validate_memory_focus()
	var page: Dictionary=adapter.memory_page()
	guide_body.add_child(_label(mw("title"),25,"eee3c2"))
	guide_body.add_child(_label(mw("source_note"),14,"cabb87"))
	guide_body.add_child(_label(mw("role_note"),14,"b8c5b8"))
	var actions:=HFlowContainer.new()
	guide_body.add_child(actions)
	actions.add_child(_button(mw("refresh"),_refresh_memory,"AdvisorMemoryRefresh"))
	var annals:=_button(mw("annals"),_open_memory_annals,"AdvisorMemoryAnnals")
	annals.disabled=page.get("blocked","")!=""
	actions.add_child(annals)
	if String(page.get("focus_ref", ""))!="":
		actions.add_child(_button(mw("clear_focus"),_clear_memory_focus,"AdvisorMemoryClearFocus"))
	if _memory_notice!="":guide_body.add_child(_label(mw(_memory_notice),14,"d4bd93"))
	var blocked: String=page.get("blocked","")
	if blocked!="":
		guide_body.add_child(_label(mw("battle_note" if blocked in ["battle","battle_active"] else "presentation_note"),15))
		return
	guide_body.add_child(_label(mw("retention_note"),13,"a6b8ab"))
	var ruler: Dictionary=page.get("current_ruler",{})
	var ruler_card:=_card("30382e")
	ruler_card.add_child(_label(mw("current_ruler").format(ruler) if not ruler.is_empty() else mw("unknown_ruler"),20,"eee3c2"))
	if not ruler.is_empty():
		ruler_card.add_child(_label(mw("unknown_since") if ruler.get("since_turn")==null else mw("since").format({"turn":ruler.since_turn}),13,"b8c5b8"))
	var reigns: Array=page.get("previous_reigns",[])
	if not reigns.is_empty():
		guide_body.add_child(_label(mw("previous_reigns"),20,"eee3c2"))
		guide_body.add_child(_label(mw("previous_reigns_note"),13,"a6b8ab"))
		for record in reigns:_render_memory_record(record,page)
	if int(page.get("previous_reigns_omitted",0))>0:
		guide_body.add_child(_label(mw("previous_reigns_omitted").format({"count":page.previous_reigns_omitted}),13,"a6b8ab"))
	guide_body.add_child(_label(mw("records"),20,"eee3c2"))
	var records: Array=page.get("records",[])
	if records.is_empty():guide_body.add_child(_label(mw("empty"),15))
	for record in records:_render_memory_record(record,page)
	if int(page.get("omitted_count",0))>0:
		guide_body.add_child(_label(mw("omitted").format({"count":page.omitted_count}),13,"a6b8ab"))
	guide_body.add_child(_button(mw("return"),_choose_lesson.bind(0),"AdvisorMemoryReturn"))

func _render_memory_record(record: Dictionary,page: Dictionary) -> void:
	var body:=_card("343b2d" if record.source_ref==page.get("focus_ref","") else "203832")
	body.add_child(_label(mw("record_source").format({"source":mw("source_"+String(record.source)),"turn":record.turn}),12,"cabb87"))
	body.add_child(_label(String(record.date),17,"eee3c2"))
	body.add_child(_label(String(record.summary),15))
	body.add_child(_button(mw("ask"),_ask_memory_record.bind(String(record.source_ref)),"AdvisorMemoryAsk"))

func _ask_memory_record(source_ref: String) -> void:
	# Resolve again when clicked: a displayed card may predate a load or season.
	if not adapter.memory_focus(source_ref):
		_invalidate_memory_focus();_render_guide();return
	var page: Dictionary=adapter.memory_page()
	var records: Array=page.get("records",[]).duplicate()
	records.append_array(page.get("previous_reigns",[]))
	for record in records:
		if record.source_ref!=source_ref:continue
		_memory_source_ref=source_ref;_memory_notice=""
		message.text=""
		_choose_tab("chat")
		_fill_question(mw("ask_prompt").format(record))
		return
	_invalidate_memory_focus();_render_guide()

func _validate_memory_focus() -> bool:
	if _memory_source_ref.is_empty():return true
	if adapter.has_method("memory_focus") and adapter.memory_focus(_memory_source_ref):return true
	_invalidate_memory_focus()
	return false

func _invalidate_memory_focus() -> void:
	_memory_source_ref="";_memory_notice="focus_missing"
	if adapter.has_method("memory_focus"):adapter.memory_focus("")
	if is_instance_valid(question):question.clear()
	if is_instance_valid(message):message.text=mw("focus_missing")

func _clear_memory_focus() -> void:
	_memory_source_ref="";_memory_notice=""
	adapter.memory_focus("")
	question.clear();message.text=""
	_render_guide()

func _refresh_memory() -> void:
	_memory_notice=""
	_render_guide()

func _open_memory_annals() -> void:
	if adapter.memory_navigate_annals():close_panel()
	else:_render_guide()

func dw(id: String) -> String:
	return String(adapter.dilemma_words().get(id,id))

func show_dilemmas() -> void:
	_dilemma_confirmation.clear();_dilemma_notice=""
	_mode="dilemmas";_choose_tab("guide");open()

func _render_dilemmas() -> void:
	var page: Dictionary=adapter.dilemma_page()
	guide_body.add_child(_label(dw("source"),11,"cabb87"))
	guide_body.add_child(_label(dw("title"),25,"eee3c2"))
	if _dilemma_confirmation.is_empty():guide_body.add_child(_label(dw("help"),14,"b8c5b8"))
	if _dilemma_notice!="":guide_body.add_child(_label(dw(_dilemma_notice),15,"d4bd93"))
	if page.get("blocked","")!="":
		guide_body.add_child(_label(dw(page.blocked),15));return
	if not _dilemma_confirmation.is_empty():_render_dilemma_confirmation();return
	if page.get("cards",[]).is_empty():guide_body.add_child(_label(dw("empty"),15))
	for card in page.get("cards",[]):
		var body:=_card("26333e" if card.patron=="zeus" else "3b2c2a")
		body.add_child(_label(card.title,23,"eee3c2"))
		body.add_child(_label(card.address,17,"cabb87"))
		body.add_child(_label(card.body,15))
		if card.get("resolved",false):
			var receipt: Dictionary=card.receipt.duplicate(true)
			for choice in card.choices:
				if choice.id==receipt.choice:receipt.choice=choice.label;break
			body.add_child(_label(dw("resolved").format(receipt),14,"b8c5b8"))
		else:
			for choice in card.choices:
				body.add_child(_label(choice.description,14,"b8c5b8"))
				var button:=_button(choice.label,_consider_dilemma.bind(card.id,choice.id,page.region),"DilemmaChoice"+String(choice.id).to_pascal_case())
				button.disabled=not choice.available
				body.add_child(button)
				if not choice.available:
					body.add_child(_label(dw(choice.reason)+(" "+choice.get("detail","") if choice.get("detail","")!="" else ""),12,"d4bd93"))
		for id in card.get("reactions",{}):
			if adapter.session.advisor_available(id):
				body.add_child(_label(dw("reaction").format({"name":String(id).capitalize()}),15,"cabb87"))
				body.add_child(_label(card.reactions[id],14,"b8c5b8"))
	if int(page.get("cooldown_until",0))>int(page.get("turn",0)):
		guide_body.add_child(_label(dw("cooldown").format({"turn":page.cooldown_until}),13,"d4bd93"))
	guide_body.add_child(_button(dw("return"),show_briefing))

func _consider_dilemma(id: String,choice: String,region: String) -> void:
	var quote: Dictionary=adapter.dilemma_quote(id,choice,region)
	_dilemma_notice="" if quote.get("ok",false) else quote.get("reason","stale_quote")
	_dilemma_confirmation=quote if quote.get("ok",false) else {}
	_render_guide()

func _render_dilemma_confirmation() -> void:
	var quote: Dictionary=_dilemma_confirmation
	var body:=_card("343426")
	body.add_child(_label(dw("confirm_title").format({"dilemma":quote.dilemma_title,"city":quote.city_name}),21,"eee3c2"))
	body.add_child(_label(quote.choice_label,19,"cabb87"))
	var cost: Dictionary=quote.consequences
	body.add_child(_label(dw("immediate_cost").format({"cost":cost.immediate_cost}),15))
	if cost.kind=="tax":
		for spec in [["tax_change","tax_before","tax_after"],["tax_income","tax_income_multiplier_before","tax_income_multiplier_after"],
			["tax_order","order_tax_factor_before","order_tax_factor_after"],["tax_growth","growth_tax_factor_before","growth_tax_factor_after"]]:
			body.add_child(_label(dw(spec[0]).format({"before":cost[spec[1]],"after":cost[spec[2]]}),15))
		body.add_child(_label(dw("tax_note"),13,"b8c5b8"))
	elif cost.kind=="edict":
		body.add_child(_label(dw("edict").format({"name":cost.name}),17))
		body.add_child(_label(dw("upkeep").format({"upkeep":str(cost.upkeep_per_turn),"population":cost.population,"per_1000":cost.upkeep_per_1000_pop}),15))
		body.add_child(_label(dw("upkeep_note"),13,"b8c5b8"))
		body.add_child(_label(dw("settle").format({"turns":cost.settle_turns}),15))
		body.add_child(_label(dw("revoke").format({"turns":cost.revoke_cooldown}),15))
		body.add_child(_label(dw("effects"),16,"cabb87"))
		for key in cost.effects:
			body.add_child(_label(dw("effect").format({"label":String(key).replace("_"," ").capitalize(),"value":cost.effects[key]}),14))
	else:body.add_child(_label(dw("decline_note"),15))
	body.add_child(_label(dw("cooldown").format({"turn":quote.cooldown_until}),14,"d4bd93"))
	body.add_child(_button(dw("confirm"),_confirm_dilemma,"DilemmaConfirm"))
	body.add_child(_button(dw("cancel"),_cancel_dilemma,"DilemmaCancel"))

func _confirm_dilemma() -> void:
	if _dilemma_confirmation.is_empty():return
	var quote: Dictionary=_dilemma_confirmation.duplicate(true)
	_dilemma_confirmation.clear() # Repeated clicks cannot reuse the confirmation.
	var result: Dictionary=adapter.resolve_dilemma(quote)
	_dilemma_notice="recorded" if result.get("ok",false) else result.get("reason","stale_quote")
	_render_guide()

func _cancel_dilemma() -> void:
	_dilemma_confirmation.clear();_render_guide()
