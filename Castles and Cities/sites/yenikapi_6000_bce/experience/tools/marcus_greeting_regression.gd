extends SceneTree
## Escaped-bug regression: greetings AND user answers omitted response_complete.
## No network or provider credentials; exercise that recorded protocol sequence.

class TransportProbe:
	extends "res://src/marcus_voice.gd"
	var sent: Array[Dictionary] = []
	func is_agent_connected() -> bool:
		return true
	func _send(message: Dictionary) -> bool:
		sent.append(message.duplicate(true))
		return true

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var transport := TransportProbe.new()
	root.add_child(transport)
	transport.set_process(false)
	transport._handle_event({"type": "conversation_initiation_metadata", "conversation_initiation_metadata_event": {"agent_output_audio_format": "pcm_16000"}})
	_part(transport, "start", "", 1, "greeting")
	_part(transport, "delta", "I am Gaius.", 1, "greeting")
	_part(transport, "stop", "", 1, "greeting")
	_check(transport.is_answering(), "stream stop must not finish greeting")
	var pcm := PackedByteArray()
	pcm.resize(320)
	transport._handle_event({"type": "audio", "audio_event": {"event_id": 1, "audio_base_64": Marshalls.raw_to_base64(pcm)}})
	_commit(transport, "I am Gaius.", 1, "greeting")
	_check(not transport._waiting_response, "committed greeting must finish without response_complete")
	_check(transport.is_answering(), "queued greeting audio must keep composer locked")
	transport._pump_audio()
	_check(transport._audio_chunks.is_empty() and transport._speaking, "PCM must remain busy while playback drains")
	_check(transport.is_answering(), "active greeting playback must keep composer locked")
	# Advance only the presentation drain deadline; avoid audio-device timing.
	transport._audio_drain_at = Time.get_ticks_msec() - 1
	transport._pump_audio()
	_check(transport.is_answering(), "audio settling must keep the composer locked after playback drains")
	transport._audio_settle_until = Time.get_ticks_msec() - 1
	transport._pump_audio()
	_check(not transport.is_answering() and transport._status == "connected", "finished greeting must release composer")
	transport.ask("What should I prepare?", {"season": 1})
	_check(transport.sent.size() == 2 and transport.sent[1].type == "user_message", "subsequent ask must reach the transport")
	_part(transport, "start", "", 2, "question")
	_part(transport, "delta", "Read the forecast.", 2, "question")
	_part(transport, "stop", "", 2, "question")
	_check(transport._waiting_response, "user stream stop must not finish the answer")
	_commit(transport, "Read the forecast.", 2, "question")
	_check(transport.is_answering() and not transport._waiting_response, "committed user answer must enter audio settling without response_complete")
	transport._audio_settle_until = Time.get_ticks_msec() - 1
	transport._pump_audio()
	_check(not transport.is_answering(), "committed user answer must release composer after its audio tail")
	transport.ask("What should I do next?", {"season": 1})
	_part(transport, "start", "", 3, "next_question")
	_part(transport, "delta", "Check the stores.", 3, "next_question")
	_commit(transport, "I am Gaius.", 1, "greeting")
	_commit(transport, "Read the forecast.", 2, "question")
	transport._handle_event({"type": "agent_response_complete", "agent_response_complete_event": {"event_id": 1}})
	_check(transport.is_answering() and transport._waiting_response and transport._answer == "Check the stores.", "late committed answers must not unlock or replace the pending turn")
	_commit(transport, "Check the stores.", 3, "next_question")
	transport._audio_settle_until = Time.get_ticks_msec() - 1
	transport._pump_audio()
	_check(not transport.is_answering(), "current committed answer must release composer after settling")
	transport.stop()
	_check(transport._audio_settle_until == 0 and not transport.is_answering(), "disconnect must clear the response and audio settling lifecycle")
	transport._handle_event({"type": "conversation_initiation_metadata", "conversation_initiation_metadata_event": {"agent_output_audio_format": "pcm_16000"}})
	transport.set_muted(true)
	_part(transport, "start", "", 10, "muted_greeting")
	_commit(transport, "I am Gaius.", 10, "muted_greeting")
	transport._handle_event({"type": "audio", "audio_event": {"event_id": 10, "audio_base_64": Marshalls.raw_to_base64(pcm)}})
	_check(transport._latest_audio_event == 10 and not transport.is_answering(), "muted greeting must retain its audio watermark without remaining busy")
	transport.set_muted(false)
	transport.ask("Give the council your advice.", {"season": 2})
	transport._handle_event({"type": "audio", "audio_event": {"event_id": 10, "audio_base_64": Marshalls.raw_to_base64(pcm)}})
	_check(transport._audio_chunks.is_empty() and transport._waiting_response, "late muted greeting audio must not leak into the next question")
	transport.stop()
	transport.free()
	# Let Godot release the stopped generator's audio-server references.
	await create_timer(0.05).timeout
	if _failures.is_empty():
		print("PASS: committed greeting/user replies, audio drain/settling, pending ask and stale/muted audio guards")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)

func _part(transport: TransportProbe, kind: String, text: String, event_id: int, response_id: String) -> void:
	transport._handle_event({"type": "agent_chat_response_part", "text_response_part": {"type": kind, "text": text, "event_id": event_id, "response_id": response_id}})

func _commit(transport: TransportProbe, text: String, event_id: int, response_id: String) -> void:
	transport._handle_event({"type": "agent_response", "agent_response_event": {"agent_response": text, "event_id": event_id, "response_id": response_id}})

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
