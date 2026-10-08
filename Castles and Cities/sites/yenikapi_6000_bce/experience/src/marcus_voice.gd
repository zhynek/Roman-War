extends Node
## Presentation-only ElevenLabs Agents transport. No world state, microphone,
## provider keys, save writes, reconnects or game commands belong in this node.
## Protocol: https://elevenlabs.io/docs/eleven-agents/api-reference/eleven-agents/websocket
## Event semantics: https://elevenlabs.io/docs/eleven-agents/customization/events/client-events

signal status_changed(code: String)
## Replaces the current answer: streamed cumulative text, final text or correction.
signal answer_received(text: String)
signal user_transcript(text: String)
signal speaking_changed(active: bool)

# Transport/resource limits, not simulation balance values.
const SAMPLE_RATE: int = 16000
const MAX_AUDIO_BYTES: int = SAMPLE_RATE * 2 * 45
const MAX_PACKET_BYTES: int = 262144
const MAX_CONTEXT_BYTES: int = 24576
const MAX_TEXT_CHARS: int = 12000
const CONNECT_TIMEOUT_MS: int = 20000
const RESPONSE_TIMEOUT_MS: int = 60000
const IDLE_TIMEOUT_MS: int = 120000
const PACKETS_PER_FRAME: int = 32
const AUDIO_BUFFER_SECONDS: float = 0.2

var _http: HTTPRequest
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _socket: WebSocketPeer
var _active: bool = false
var _opened: bool = false
var _metadata_ready: bool = false
var _request_pending: bool = false
var _muted: bool = false
var _speaking: bool = false
var _status: String = "disconnected"
var _context_json: String = "{}"
var _connected_at: int = 0
var _last_packet_at: int = 0
var _last_user_at: int = 0
var _response_started_at: int = 0
var _waiting_response: bool = false
var _response_event: int = -1
var _response_id: String = ""
var _retired_response_ids: Array[String] = []
var _minimum_text_event: int = -1
var _latest_audio_event: int = -1
var _minimum_audio_event: int = -1
var _audio_text_ready: bool = false
var _answer: String = ""
var _audio_chunks: Array[PackedByteArray] = []
var _audio_offset: int = 0
var _audio_bytes: int = 0
var _audio_drain_at: int = 0
var _suppress_audio: bool = false

func _ready() -> void:
	_ensure_children()

func _ensure_children() -> void:
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = CONNECT_TIMEOUT_MS / 1000.0
		_http.body_size_limit = 16384
		# Never redirect a request carrying the local broker bearer token.
		_http.max_redirects = 0
		add_child(_http)
		_http.request_completed.connect(_broker_completed)
	if _player == null:
		_player = AudioStreamPlayer.new()
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = SAMPLE_RATE
		generator.buffer_length = AUDIO_BUFFER_SECONDS
		_player.stream = generator
		add_child(_player)

func connect_agent(context: Dictionary) -> void:
	# Only a user action should call this. Never request a session from _ready.
	if _active:
		return
	_ensure_children()
	var broker: String = OS.get_environment("MARCUS_BROKER_URL").strip_edges()
	if broker.is_empty():
		broker = "http://127.0.0.1:2270"
	var token: String = OS.get_environment("MARCUS_BROKER_TOKEN")
	if not _valid_broker(broker) or token.length() < 32 or token.contains("\r") or token.contains("\n"):
		_set_status("setup_required")
		return
	_context_json = JSON.stringify(context)
	if _context_json.to_utf8_buffer().size() > MAX_CONTEXT_BYTES:
		_set_status("protocol_error")
		return
	_active = true
	_request_pending = true
	_connected_at = Time.get_ticks_msec()
	_last_user_at = _connected_at
	_last_packet_at = _connected_at
	_set_status("connecting")
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + token])
	var error: Error = _http.request(broker.trim_suffix("/") + "/session", headers, HTTPClient.METHOD_POST, "{}")
	# Credentials remain in request memory only; no URLs, headers or raw errors are logged.
	if error != OK:
		_fail("broker_unavailable")

func ask(text: String, context: Dictionary) -> void:
	if not is_agent_connected():
		return
	var question: String = text.strip_edges()
	if question.is_empty():
		return
	var visible_context: String = JSON.stringify(context)
	if question.length() > 2000 or visible_context.to_utf8_buffer().size() > MAX_CONTEXT_BYTES:
		_set_status("protocol_error")
		return
	# The server interrupts the old answer for user_message. Drop its remaining
	# local audio immediately and reject late events belonging to the previous turn.
	_retire_response_id()
	_minimum_text_event = maxi(_minimum_text_event, _response_event + 1)
	_minimum_audio_event = maxi(_minimum_audio_event, _latest_audio_event + 1)
	_response_event = -1
	_response_id = ""
	_answer = ""
	_audio_text_ready = false
	_suppress_audio = false
	_clear_audio()
	_last_user_at = Time.get_ticks_msec()
	_response_started_at = _last_user_at
	_waiting_response = true
	_set_status("thinking")
	if _send({"type": "contextual_update", "text": visible_context}):
		_send({"type": "user_message", "text": question})

func stop() -> void:
	_close()
	_set_status("disconnected")

func set_muted(muted: bool) -> void:
	_muted = muted
	# Unmuting never resumes a sentence halfway through; the next answer can speak.
	_suppress_audio = true
	_clear_audio()
	if is_agent_connected():
		_refresh_response_status()

func is_agent_connected() -> bool:
	# Object.is_connected(signal, callable) is already a Godot native method.
	return _active and _metadata_ready and _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func is_answering() -> bool:
	return _waiting_response or _speaking or not _audio_chunks.is_empty()

func _refresh_response_status() -> void:
	if _speaking or not _audio_chunks.is_empty():
		_set_status("speaking")
	elif _waiting_response:
		_set_status("thinking")
	else:
		_set_status("muted" if _muted else "connected")

func _process(_delta: float) -> void:
	if not _active:
		return
	var now: int = Time.get_ticks_msec()
	if not _metadata_ready and now - _connected_at > CONNECT_TIMEOUT_MS:
		_fail("connection_timeout")
		return
	if now - _last_user_at > IDLE_TIMEOUT_MS:
		_fail("idle_timeout")
		return
	if _waiting_response and now - _response_started_at > RESPONSE_TIMEOUT_MS:
		_fail("response_timeout")
		return
	if _socket != null:
		_socket.poll()
		var state: int = _socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not _opened:
				_opened = true
				_send({"type": "conversation_initiation_client_data", "dynamic_variables": {"visible_context": _context_json}})
			var count: int = 0
			while _socket != null and _socket.get_available_packet_count() > 0 and count < PACKETS_PER_FRAME:
				var packet: PackedByteArray = _socket.get_packet()
				count += 1
				if not _socket.was_string_packet() or packet.size() > MAX_PACKET_BYTES:
					_fail("protocol_error")
					return
				var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
				if not parsed is Dictionary:
					_fail("protocol_error")
					return
				_last_packet_at = now
				_handle_event(parsed)
		elif state == WebSocketPeer.STATE_CLOSED:
			_fail("disconnected" if _metadata_ready else "connection_failed")
			return
	if _metadata_ready and now - _last_packet_at > RESPONSE_TIMEOUT_MS:
		_fail("connection_timeout")
		return
	_pump_audio()

func _broker_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _active or not _request_pending:
		return
	_request_pending = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("broker_unavailable")
		return
	if response_code != 200:
		# Translate only known, fixed service codes. Never display a raw body,
		# provider message or URL that might contain account or session details.
		var failure: Variant = JSON.parse_string(body.get_string_from_utf8())
		var code: String = str(failure.get("error", "")) if failure is Dictionary else ""
		match code:
			"provider_not_configured": _fail("unconfigured")
			"agent_must_require_authentication": _fail("agent_private_required")
			"session_rate_limited": _fail("rate_limited")
			"broker_busy": _fail("service_busy")
			"provider_unavailable": _fail("broker_unavailable")
			_: _fail("broker_rejected")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("signed_url") is String:
		_fail("protocol_error")
		return
	var url: String = parsed.signed_url
	if not _valid_agent_url(url):
		_fail("protocol_error")
		return
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = MAX_PACKET_BYTES * 4
	_socket.outbound_buffer_size = MAX_CONTEXT_BYTES * 2
	_socket.max_queued_packets = 64
	if _socket.connect_to_url(url) != OK:
		_fail("connection_failed")

func _handle_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"conversation_initiation_metadata":
			var metadata: Dictionary = _payload(event, "conversation_initiation_metadata_event")
			if metadata.get("agent_output_audio_format", "") != "pcm_16000":
				_fail("unsupported_audio")
				return
			_metadata_ready = true
			_set_status("muted" if _muted else "connected")
		"ping":
			var ping: Dictionary = _payload(event, "ping_event")
			if ping.has("event_id"):
				_send({"type": "pong", "event_id": ping.event_id})
		"agent_chat_response_part":
			var part: Dictionary = _payload(event, "text_response_part")
			if not _observe_text_response(part):
				return
			if part.get("type", "") == "delta":
				_publish_answer(_answer + str(part.get("text", "")))
		"agent_response":
			var response: Dictionary = _payload(event, "agent_response_event")
			if _observe_text_response(response):
				_publish_answer(str(response.get("agent_response", "")))
		"agent_response_correction":
			var correction: Dictionary = _payload(event, "agent_response_correction_event")
			# A correction for the interrupted turn can follow a new user_message.
			# Never replace the new answer with that previous turn's transcript.
			var original: String = str(correction.get("original_agent_response", ""))
			if _answer.is_empty() or (not original.is_empty() and not original.begins_with(_answer)):
				return
			_clear_audio()
			_suppress_audio = true
			_publish_answer(str(correction.get("corrected_agent_response", "")))
		"user_transcript":
			var transcript: String = str(_payload(event, "user_transcription_event").get("user_transcript", ""))
			if not transcript.is_empty() and transcript.length() <= MAX_TEXT_CHARS:
				user_transcript.emit(transcript)
		"audio":
			_receive_audio(_payload(event, "audio_event"))
		"interruption":
			_clear_audio()
			_audio_text_ready = false
			_retire_response_id()
			# Some provider replies share the interruption event ID; allow equality.
			var interruption: Dictionary = _payload(event, "interruption_event")
			_minimum_audio_event = maxi(_minimum_audio_event, int(interruption.get("event_id", _minimum_audio_event)))
		"agent_response_complete":
			var completion: Dictionary = _payload(event, "agent_response_complete_event")
			var event_id: int = int(completion.get("event_id", -1))
			if event_id >= 0 and (event_id < _minimum_text_event or event_id < _response_event):
				return
			_waiting_response = false
			_refresh_response_status()
		"queue_status":
			var queue_status: String = str(_payload(event, "queue_status_event").get("status", ""))
			if queue_status == "waiting" or queue_status == "timed_out":
				_fail("agent_busy")
		"client_tool_call":
			# The advisor has no action capability. Reject accidental tool requests.
			var call: Dictionary = _payload(event, "client_tool_call")
			if call.get("expects_response", true) and call.has("tool_call_id"):
				_send({"type": "client_tool_result", "tool_call_id": call.tool_call_id, "is_error": true, "result": "read_only_advisor"})
		"client_error", "error", "guardrail_triggered":
			_fail("protocol_error")

func _observe_text_response(payload: Dictionary) -> bool:
	# response_id links streamed text to its committed agent_response. Audio
	# event IDs only sequence audio/interruption: they never start/reset text.
	# https://elevenlabs.io/docs/eleven-agents/customization/events/client-events
	var event_id: int = int(payload.get("event_id", -1))
	var response_id: String = str(payload.get("response_id", ""))
	if event_id >= 0 and event_id < _minimum_text_event:
		return false
	if not response_id.is_empty() and response_id in _retired_response_ids:
		return false
	var new_response: bool = response_id != _response_id if not response_id.is_empty() else (event_id >= 0 and event_id != _response_event)
	if new_response:
		if not _response_id.is_empty() or _response_event >= 0:
			_retire_response_id()
			_clear_audio()
		_response_id = response_id
		_response_event = event_id
		_answer = ""
		_audio_text_ready = false
		_suppress_audio = false
		_response_started_at = Time.get_ticks_msec()
		_waiting_response = true
		_set_status("thinking")
	elif _response_event < 0 and event_id >= 0:
		# A streamed response may omit its numeric ID and gain it on commit.
		# Retain both its accumulated text and already queued audio.
		_response_event = event_id
	return true

func _retire_response_id() -> void:
	if _response_id.is_empty() or _response_id in _retired_response_ids:
		return
	_retired_response_ids.append(_response_id)
	if _retired_response_ids.size() > 32:
		_retired_response_ids.pop_front()

func _publish_answer(text: String) -> void:
	if text.length() > MAX_TEXT_CHARS:
		_fail("protocol_error")
		return
	_answer = text
	_audio_text_ready = not text.is_empty()
	answer_received.emit(_answer)
	# A delta is not a completed turn. Keep the response deadline and composer
	# lock until agent_response_complete, including while voice is muted.
	_refresh_response_status()

func _receive_audio(payload: Dictionary) -> void:
	if not _metadata_ready or _muted or _suppress_audio:
		return
	var event_id: int = int(payload.get("event_id", -1))
	if event_id >= 0 and event_id < _minimum_audio_event:
		return
	_latest_audio_event = maxi(_latest_audio_event, event_id)
	var encoded: String = str(payload.get("audio_base_64", ""))
	if encoded.is_empty() or encoded.length() > MAX_PACKET_BYTES:
		_fail("protocol_error")
		return
	var pcm: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if pcm.is_empty() or pcm.size() % 2 != 0:
		_fail("protocol_error")
		return
	if _audio_bytes + pcm.size() > MAX_AUDIO_BYTES:
		_fail("audio_overflow")
		return
	_audio_chunks.append(pcm)
	_audio_bytes += pcm.size()

func _pump_audio() -> void:
	# Complete agent_response can arrive after audio. Until text exists, retain
	# bounded PCM instead of making the advisor speak without accompanying text.
	if _muted or _suppress_audio or not _audio_text_ready:
		return
	if not _audio_chunks.is_empty():
		if _playback == null:
			_player.play()
			_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _playback == null:
			_fail("unsupported_audio")
			return
		var capacity: int = mini(_playback.get_frames_available(), 8192)
		while capacity > 0 and not _audio_chunks.is_empty():
			var pcm: PackedByteArray = _audio_chunks[0]
			var count: int = mini(capacity, (pcm.size() - _audio_offset) / 2)
			var frames := PackedVector2Array()
			frames.resize(count)
			for index: int in range(count):
				var sample: float = float(pcm.decode_s16(_audio_offset + index * 2)) / 32768.0
				frames[index] = Vector2(sample, sample)
			if not _playback.push_buffer(frames):
				break
			_audio_offset += count * 2
			_audio_bytes -= count * 2
			capacity -= count
			_audio_drain_at = Time.get_ticks_msec() + int(AUDIO_BUFFER_SECONDS * 1000) + 50
			if _audio_offset == pcm.size():
				_audio_chunks.pop_front()
				_audio_offset = 0
			_set_speaking(true)
			_set_status("speaking")
	elif _speaking and Time.get_ticks_msec() >= _audio_drain_at:
		_clear_audio()
		_refresh_response_status()

func _clear_audio() -> void:
	_audio_chunks.clear()
	_audio_offset = 0
	_audio_bytes = 0
	_audio_drain_at = 0
	if _player != null:
		_player.stop()
	_playback = null
	_set_speaking(false)

func _send(message: Dictionary) -> bool:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if _socket.send_text(JSON.stringify(message)) != OK:
		_fail("connection_failed")
		return false
	return true

func _payload(event: Dictionary, key: String) -> Dictionary:
	var value: Variant = event.get(key, {})
	return value if value is Dictionary else {}

func _valid_broker(url: String) -> bool:
	# Local development only. A remote broker requires separate per-player auth
	# and rate limiting before enabling HTTPS production endpoints here.
	var expression := RegEx.new()
	expression.compile("^http://(?:127\\.0\\.0\\.1|localhost|\\[::1\\])(?::[0-9]{1,5})?/?$")
	return expression.search(url) != null

func _valid_agent_url(url: String) -> bool:
	# Exact host and endpoint: never send a capability URL to an arbitrary host.
	var prefix: String = "wss://api.elevenlabs.io/v1/convai/conversation?"
	if not url.begins_with(prefix) or url.length() > 8192:
		return false
	if url.contains("#") or url.contains("\r") or url.contains("\n") or url.contains(" "):
		return false
	var query: String = url.trim_prefix(prefix)
	var has_signature: bool = false
	var has_agent: bool = false
	for field: String in query.split("&"):
		if field.begins_with("conversation_signature=") and field.length() > 23:
			has_signature = true
		if field.begins_with("agent_id=") and field.length() > 9:
			has_agent = true
	return has_signature and has_agent

func _set_status(code: String) -> void:
	if _status != code:
		_status = code
		status_changed.emit(code)

func _set_speaking(active: bool) -> void:
	if _speaking != active:
		_speaking = active
		speaking_changed.emit(active)

func _fail(code: String) -> void:
	_close()
	_set_status(code)

func _close() -> void:
	_active = false
	_request_pending = false
	if _http != null:
		_http.cancel_request()
	if _socket != null:
		_socket.close(1000)
		_socket = null
	_opened = false
	_metadata_ready = false
	_waiting_response = false
	_response_event = -1
	_response_id = ""
	_retired_response_ids.clear()
	_minimum_text_event = -1
	_latest_audio_event = -1
	_minimum_audio_event = -1
	_audio_text_ready = false
	_answer = ""
	_context_json = "{}"
	_suppress_audio = false
	_clear_audio()

func _exit_tree() -> void:
	_close()
