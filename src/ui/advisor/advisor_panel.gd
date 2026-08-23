class_name AdvisorPanel
extends AcceptDialog
## The Quaestor's chamber: an in-game chat with an LLM that knows the game,
## the known gaps, and the campaign's current situation. Provider and keys
## come from AdvisorConfig; all traffic goes through the shared LlmClient.

var game: Game
var screen: CampaignScreen
var client: LlmClient

var _transcript: RichTextLabel
var _input: LineEdit
var _send_button: Button
var _issues_check: CheckBox
var _history: Array = []   # [{role, content}] user/assistant turns
var _pending_issues := false
var _pending_question := ""
var _settings_panel: AdvisorSettingsPanel


func _init() -> void:
	title = "The Quaestor"
	min_size = Vector2i(600, 620)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(570, 560)
	add_child(column)

	_transcript = RichTextLabel.new()
	_transcript.bbcode_enabled = true
	_transcript.scroll_following = true
	_transcript.selection_enabled = true
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transcript.custom_minimum_size = Vector2(0, 420)
	column.add_child(_transcript)

	var input_row := HBoxContainer.new()
	column.add_child(input_row)
	_input = LineEdit.new()
	_input.placeholder_text = "Ask about the game, or whether something is a bug…"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_text: String): _send())
	input_row.add_child(_input)
	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.pressed.connect(_send)
	input_row.add_child(_send_button)

	var tools_row := HBoxContainer.new()
	column.add_child(tools_row)
	_issues_check = CheckBox.new()
	_issues_check.text = "Check open tickets first"
	_issues_check.tooltip_text = "Fetches the open in-game issues from GitHub (needs the token in Settings) so the Quaestor can say \"already reported\"."
	_issues_check.add_theme_font_size_override("font_size", 11)
	tools_row.add_child(_issues_check)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_row.add_child(spacer)
	var settings := Button.new()
	settings.text = "Settings"
	settings.add_theme_font_size_override("font_size", 11)
	settings.pressed.connect(_open_settings)
	tools_row.add_child(settings)


func open_for(current_game: Game, campaign_screen: CampaignScreen) -> void:
	game = current_game
	screen = campaign_screen
	if client == null:
		client = LlmClient.new()
		client.completed.connect(_on_reply)
		client.failed.connect(_on_failed)
		client.json_completed.connect(_on_issues_fetched)
		add_child(client)
	if _transcript.text == "":
		var cfg := AdvisorConfig.load_cfg()
		_line("[color=#a4977c]The Quaestor looks up from his ledgers. Provider: %s (%s). Ask, and be brief about it.[/color]"
			% [String(cfg["provider"]), String(cfg["model"])])
	popup_centered()
	_input.grab_focus()


func _send() -> void:
	var question := _input.text.strip_edges()
	if question == "" or _send_button.disabled:
		return
	_input.text = ""
	_line("[b][color=#d4a938]You:[/color][/b] " + question.xml_escape())
	_set_busy(true)
	var cfg := AdvisorConfig.load_cfg()
	if _issues_check.button_pressed and String(cfg["github_token"]) != "":
		_pending_issues = true
		_pending_question = question
		client.post_json(AdvisorContext.build_issues_request(cfg), HTTPClient.METHOD_GET)
	else:
		_ask_model(question, [])


func _ask_model(question: String, open_issues: Array) -> void:
	var cfg := AdvisorConfig.load_cfg()
	var log_tail := _log_tail()
	var digest := AdvisorContext.build_state_digest(game, screen.map_view.selected_region, log_tail)
	var system := AdvisorContext.build_system_prompt(AdvisorContext.load_pack(), digest, open_issues)
	_history.append({"role": "user", "content": question})
	while _history.size() > 12:
		_history.pop_front()
	# History must open with a user turn after trimming.
	while not _history.is_empty() and String(_history[0].get("role", "")) != "user":
		_history.pop_front()
	_line("[color=#a4977c]…the Quaestor considers…[/color]")
	client.ask(cfg, system, _history.duplicate())


func _on_reply(text: String) -> void:
	_set_busy(false)
	_history.append({"role": "assistant", "content": text})
	_line("[b][color=#7fa15a]Quaestor:[/color][/b] " + text.xml_escape())


func _on_failed(reason: String) -> void:
	_set_busy(false)
	if _pending_issues:
		# The tickets lookup failed; answer anyway, without them.
		_pending_issues = false
		_line("[color=#a4977c](Could not fetch open tickets: %s)[/color]" % reason.xml_escape())
		_set_busy(true)
		_ask_model(_pending_question, [])
		return
	_line("[color=#cc6655]%s[/color]  [color=#a4977c](the Settings button below configures the provider)[/color]"
		% reason.xml_escape())


func _on_issues_fetched(code: int, body: String) -> void:
	if not _pending_issues:
		return
	_pending_issues = false
	var titles: Array = AdvisorContext.parse_issue_titles(body) if code == 200 else []
	if code != 200:
		_line("[color=#a4977c](Ticket lookup returned HTTP %d; answering without it.)[/color]" % code)
	_ask_model(_pending_question, titles)


func _open_settings() -> void:
	if _settings_panel == null:
		_settings_panel = AdvisorSettingsPanel.new()
		add_child(_settings_panel)
	_settings_panel.open_now()


func _set_busy(busy: bool) -> void:
	_send_button.disabled = busy
	_input.editable = not busy


func _log_tail() -> Array:
	if screen == null or screen.report_log == null:
		return []
	var lines := screen.report_log.get_parsed_text().split("\n")
	var tail: Array = []
	for i in range(maxi(0, lines.size() - 15), lines.size()):
		tail.append(lines[i])
	return tail


func _line(bbcode: String) -> void:
	_transcript.append_text(bbcode + "\n")
