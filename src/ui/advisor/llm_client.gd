class_name LlmClient
extends Node
## One HTTP door for the whole Advisor stack: LLM chat (OpenAI-compatible
## endpoints — Ollama, OpenAI, OpenRouter — and Anthropic's Messages API),
## the Ollama model listing, and generic JSON calls (GitHub issues). One
## request in flight; the rest queue. Request building and response parsing
## are pure statics so tests cover the wire format without any network.

signal completed(text: String)
signal failed(reason: String)
signal models_listed(names: Array)
signal json_completed(code: int, body: String)

const ANTHROPIC_URL := "https://api.anthropic.com/v1/messages"

var _http: HTTPRequest
var _queue: Array = []
var _busy := false
var _current_kind := ""   # chat | models | json
var _current_provider := ""
var _current_base_url := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


## --- Pure wire-format builders (headless-testable) ------------------------

static func build_openai_request(cfg: Dictionary, messages: Array) -> Dictionary:
	## messages: [{role: system|user|assistant, content}] — system first.
	var key := String(cfg.get("api_key", ""))
	return {
		"url": String(cfg.get("base_url", "")).trim_suffix("/") + "/chat/completions",
		"headers": PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + (key if key != "" else "ollama"),
		]),
		"body": JSON.stringify({
			"model": cfg.get("model", ""),
			"messages": messages,
			"stream": false,
		}),
	}


static func build_anthropic_request(cfg: Dictionary, system: String, messages: Array) -> Dictionary:
	## messages: user/assistant turns only; the system prompt is top-level.
	return {
		"url": ANTHROPIC_URL,
		"headers": PackedStringArray([
			"Content-Type: application/json",
			"x-api-key: " + String(cfg.get("api_key", "")),
			"anthropic-version: 2023-06-01",
		]),
		"body": JSON.stringify({
			"model": cfg.get("model", ""),
			"max_tokens": 1024,
			"system": system,
			"messages": messages,
		}),
	}


static func parse_chat_response(provider: String, code: int, body: String) -> Dictionary:
	## -> {ok, text, error}
	var parsed = JSON.parse_string(body)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "text": "", "error": "Unreadable reply (HTTP %d)." % code}
	if code < 200 or code >= 300:
		var message := ""
		var error_obj = parsed.get("error")
		if error_obj is Dictionary:
			message = String(error_obj.get("message", ""))
		elif error_obj is String:
			message = error_obj
		return {"ok": false, "text": "", "error": "HTTP %d: %s" % [code, message]}
	if provider == "anthropic":
		var content: Array = parsed.get("content", [])
		if not content.is_empty() and content[0] is Dictionary:
			return {"ok": true, "text": String(content[0].get("text", "")), "error": ""}
	else:
		var choices: Array = parsed.get("choices", [])
		if not choices.is_empty() and choices[0] is Dictionary:
			var message_obj = choices[0].get("message", {})
			if message_obj is Dictionary:
				return {"ok": true, "text": String(message_obj.get("content", "")), "error": ""}
	return {"ok": false, "text": "", "error": "The reply had no message in it."}


static func parse_ollama_tags(body: String) -> Array:
	var parsed = JSON.parse_string(body)
	if parsed == null or not (parsed is Dictionary):
		return []
	var names: Array = []
	for model in parsed.get("models", []):
		if model is Dictionary and model.has("name"):
			names.append(String(model["name"]))
	names.sort()
	return names


static func friendly_error(result: int, code: int, provider: String, base_url: String = "") -> String:
	if result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CANT_RESOLVE:
		if provider == "ollama":
			return "Could not reach Ollama at %s — is `ollama serve` running?" % base_url
		return "Could not reach the server at %s." % (base_url if base_url != "" else "the configured address")
	if result == HTTPRequest.RESULT_TIMEOUT:
		return "The model took too long to answer (60s). A smaller model may help."
	if result != HTTPRequest.RESULT_SUCCESS:
		return "The request failed on the way out (network result %d)." % result
	match code:
		401, 403:
			return "The API key was rejected — check it in Settings."
		404:
			if provider == "ollama":
				return "Model not found — pull it with `ollama pull <model>` or pick another in Settings."
			return "Not found (404) — check the endpoint and model in Settings."
		429:
			return "Rate limited — wait a moment and try again."
	if code >= 500:
		return "The provider had an internal error (HTTP %d). Try again." % code
	return "HTTP %d." % code


## --- Instance API ----------------------------------------------------------

func ask(cfg: Dictionary, system: String, history: Array) -> void:
	## history: [{role: user|assistant, content}] oldest first.
	var provider := String(cfg.get("provider", "ollama"))
	var request: Dictionary
	if provider == "anthropic":
		request = build_anthropic_request(cfg, system, history)
	else:
		var messages: Array = [{"role": "system", "content": system}]
		messages.append_array(history)
		request = build_openai_request(cfg, messages)
	_enqueue("chat", provider, String(cfg.get("base_url", "")), request, HTTPClient.METHOD_POST)


func list_ollama_models(base_url: String) -> void:
	var request := {
		"url": base_url.trim_suffix("/").trim_suffix("/v1") + "/api/tags",
		"headers": PackedStringArray([]),
		"body": "",
	}
	_enqueue("models", "ollama", base_url, request, HTTPClient.METHOD_GET)


func post_json(request: Dictionary, method: int = HTTPClient.METHOD_POST) -> void:
	## Generic JSON call (GitHub). Emits json_completed(code, body) or failed.
	_enqueue("json", "github", String(request.get("url", "")), request, method)


func _enqueue(kind: String, provider: String, base_url: String, request: Dictionary, method: int) -> void:
	_queue.append({"kind": kind, "provider": provider, "base_url": base_url,
		"request": request, "method": method})
	_pump()


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	var job: Dictionary = _queue.pop_front()
	_busy = true
	_current_kind = job["kind"]
	_current_provider = job["provider"]
	_current_base_url = String(job["base_url"])
	var request: Dictionary = job["request"]
	var error := _http.request(String(request["url"]), request["headers"],
		job["method"], String(request.get("body", "")))
	if error != OK:
		_busy = false
		failed.emit("The request could not be started (error %d)." % error)
		_pump()


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _current_kind
	var provider := _current_provider
	_busy = false
	var text := body.get_string_from_utf8()
	match kind:
		"chat":
			if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
				failed.emit(friendly_error(result, code, provider, _current_base_url))
			else:
				var parsed := parse_chat_response(provider, code, text)
				if parsed["ok"]:
					completed.emit(parsed["text"])
				else:
					failed.emit(String(parsed["error"]))
		"models":
			if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
				failed.emit(friendly_error(result, code, provider, _current_base_url))
			else:
				models_listed.emit(parse_ollama_tags(text))
		"json":
			if result != HTTPRequest.RESULT_SUCCESS:
				failed.emit(friendly_error(result, code, provider, _current_base_url))
			else:
				json_completed.emit(code, text)
	_pump()
