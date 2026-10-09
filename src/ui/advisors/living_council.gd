extends Node
## One explicitly requested, finite presentation. Never owns campaign commands.
signal changed
const Voice = preload("res://Castles and Cities/sites/yenikapi_6000_bce/experience/src/marcus_voice.gd")
var _session: WeakRef
var session:
	get:return _session.get_ref()
var voice
var active := false
var muted := false
var status := "ready"
var speaker := ""
var turns: Array = []
var snapshot: Dictionary = {}
var _context_key := ""
var _speakers: Array = []
var _index := -1
var _stage := ""
var _greeting_seen := false
var _settle_at := 0
var _deadline := 0
var _speaker_deadline := 0
var _limits: Dictionary = {}

func _init(owner_session) -> void:
	_session=weakref(owner_session)

func _ready() -> void:
	voice=Voice.new()
	add_child(voice)
	voice.answer_received.connect(_answer)
	voice.status_changed.connect(_status)
	voice.speaking_changed.connect(func(_speaking):changed.emit())

func start(quiet: bool) -> bool:
	if active:return false
	var context=session.marcus_context.council_context
	var frozen: Dictionary=context.discussion_snapshot()
	if frozen.is_empty():status="needs_context";changed.emit();return false
	_limits=context.content.discussion.limits.duplicate(true)
	if JSON.stringify(frozen).to_utf8_buffer().size()>int(_limits.snapshot_bytes):
		status="too_large";changed.emit();return false
	for panel in session.advisor_panels.values():panel.voice.stop()
	snapshot=frozen.duplicate(true)
	_context_key=context.discussion_key()
	_speakers=snapshot.advisors.slice(0,int(_limits.turns))
	turns.clear();_index=-1;muted=quiet;active=true
	_deadline=Time.get_ticks_msec()+int(_limits.session_seconds*1000)
	_next_speaker()
	return true

func _next_speaker() -> void:
	# Always close the preceding connection before another voice can begin.
	_stage="switching"
	voice.stop()
	_index+=1
	if _index>=_speakers.size():stop("complete");return
	speaker=_speakers[_index].id
	_stage="greeting";status="connecting";_greeting_seen=false;_settle_at=0
	_speaker_deadline=Time.get_ticks_msec()+int(_limits.speaker_seconds*1000)
	voice.advisor_id=speaker
	voice.set_muted(true) # Introductions are not extra council turns.
	voice.connect_agent(_turn_context())
	changed.emit()

func _turn_context() -> Dictionary:
	var result: Dictionary=snapshot.duplicate(true)
	result.council_discussion={"speaker":speaker,"turn":_index+1,"maximum_turns":_speakers.size(),
		"prior_turns":turns.slice(0,_index).duplicate(true),"max_words":int(_limits.words),
		"priorities":_speakers[_index].stance,"mode":"one_explicit_council_turn"}
	return result

func _process(_delta: float) -> void:
	if not active:return
	if session.marcus_context.council_context.discussion_key()!=_context_key:
		stop("context_changed");return
	var now:=Time.get_ticks_msec()
	if now>=_deadline or now>=_speaker_deadline:stop("timeout");return
	if _stage=="greeting" and _greeting_seen and voice.is_agent_connected() and not voice.is_answering():
		if _settle_at==0:_settle_at=now+int(_limits.greeting_settle_ms)
		if now<_settle_at:return
		_stage="answer";status="discussing"
		voice.set_muted(muted)
		turns.append({"id":speaker,"name":_speakers[_index].name,"text":""})
		voice.ask(session.marcus_context.council_context.content.discussion.prompt,_turn_context())
		changed.emit()
	elif _stage=="answer" and not turns.back().text.is_empty() and voice.is_agent_connected() and not voice.is_answering():
		_next_speaker()

func _answer(text: String) -> void:
	if not active:return
	if _stage=="greeting":_greeting_seen=not text.is_empty();return
	if _stage!="answer":return
	if text.length()>int(_limits.response_characters):
		turns.back().text=text.left(int(_limits.response_characters))
		stop("too_long");return
	turns.back().text=text
	changed.emit()

func _status(code: String) -> void:
	if not active or _stage=="switching":return
	if code in ["unconfigured","setup_required","broker_unavailable","broker_rejected","agent_private_required",
		"rate_limited","service_busy","connection_failed","connection_timeout","unsupported_audio","protocol_error",
		"audio_overflow","response_timeout","idle_timeout","agent_busy","disconnected"]:
		stop("unavailable")

func set_muted(quiet: bool) -> void:
	muted=quiet
	voice.set_muted(true if _stage=="greeting" else muted)
	changed.emit()

func stop(reason: String="stopped") -> void:
	active=false;_stage="";status=reason
	if is_instance_valid(voice):voice.stop()
	changed.emit()

func reset() -> void:
	stop("ready")
	turns.clear();snapshot.clear();speaker=""
	changed.emit()

func _exit_tree() -> void:
	if is_instance_valid(voice):voice.stop()
