class_name AdvisorSettingsPanel
extends AcceptDialog
## Where the Advisor's plumbing is configured: which model answers (local
## Ollama by default, Anthropic, or any OpenAI-compatible endpoint), and the
## GitHub token that lets Feedback file tickets. Everything is written to
## user://advisor.cfg — plain text, local only, never shipped with the game.

const PRESETS := {
	"ollama": {"label": "Ollama (local, free)", "base_url": "http://127.0.0.1:11434/v1", "model": "llama3.1"},
	"anthropic": {"label": "Anthropic API", "base_url": "", "model": "claude-haiku-4-5"},
	"openai_compat": {"label": "Custom OpenAI-compatible", "base_url": "https://api.openai.com/v1", "model": "gpt-4o-mini"},
}
const PRESET_ORDER := ["ollama", "anthropic", "openai_compat"]

var client: LlmClient

var _provider: OptionButton
var _base_url: LineEdit
var _model: LineEdit
var _model_pick: OptionButton
var _api_key: LineEdit
var _github_token: LineEdit
var _github_repo: LineEdit
var _status: Label


func _init() -> void:
	title = "Advisor Settings"
	min_size = Vector2i(560, 560)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(530, 500)
	add_child(column)

	column.add_child(_field_label("Who answers"))
	_provider = OptionButton.new()
	for preset_id in PRESET_ORDER:
		_provider.add_item(PRESETS[preset_id]["label"])
	_provider.item_selected.connect(_on_preset_picked)
	column.add_child(_provider)

	column.add_child(_field_label("Endpoint (base URL)"))
	_base_url = LineEdit.new()
	column.add_child(_base_url)

	column.add_child(_field_label("Model"))
	var model_row := HBoxContainer.new()
	column.add_child(model_row)
	_model = LineEdit.new()
	_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model.tooltip_text = "Anthropic: claude-haiku-4-5 is fast and inexpensive; claude-opus-5 answers best."
	model_row.add_child(_model)
	_model_pick = OptionButton.new()
	_model_pick.visible = false
	_model_pick.item_selected.connect(func(index: int):
		_model.text = _model_pick.get_item_text(index))
	model_row.add_child(_model_pick)
	var list_models := Button.new()
	list_models.text = "List local models"
	list_models.add_theme_font_size_override("font_size", 11)
	list_models.pressed.connect(_list_models)
	model_row.add_child(list_models)

	column.add_child(_field_label("API key (not needed for Ollama)"))
	_api_key = LineEdit.new()
	_api_key.secret = true
	column.add_child(_api_key)

	column.add_child(HSeparator.new())
	column.add_child(_field_label("GitHub — for filing Feedback tickets"))
	var hint := Label.new()
	hint.text = "A fine-grained personal access token for the repo below, with\nIssues: Read and write only. Leave empty to use copy-paste instead."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", UiTheme.PARCHMENT_DIM)
	column.add_child(hint)
	_github_token = LineEdit.new()
	_github_token.secret = true
	_github_token.placeholder_text = "github_pat_…"
	column.add_child(_github_token)
	_github_repo = LineEdit.new()
	column.add_child(_github_repo)

	var warning := Label.new()
	warning.text = "Keys are stored in plain text in your user folder. They never enter\nthe game's files, saves, or any ticket you file."
	warning.add_theme_font_size_override("font_size", 10)
	warning.add_theme_color_override("font_color", UiTheme.WARN)
	column.add_child(warning)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var test := Button.new()
	test.text = "Test connection"
	test.pressed.connect(_test_connection)
	buttons.add_child(test)
	var save := Button.new()
	save.text = "Save settings"
	save.pressed.connect(_save)
	buttons.add_child(save)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	buttons.add_child(_status)


func open_now() -> void:
	if client == null:
		client = LlmClient.new()
		client.models_listed.connect(_on_models)
		client.completed.connect(_on_test_reply)
		client.failed.connect(_on_test_failed)
		add_child(client)
	var cfg := AdvisorConfig.load_cfg()
	_provider.selected = maxi(0, PRESET_ORDER.find(String(cfg["provider"])))
	_base_url.text = String(cfg["base_url"])
	_model.text = String(cfg["model"])
	_api_key.text = String(cfg["api_key"])
	_github_token.text = String(cfg["github_token"])
	_github_repo.text = String(cfg["github_repo"])
	_status.text = ""
	popup_centered()


func _gathered_cfg() -> Dictionary:
	var cfg := AdvisorConfig.load_cfg()
	cfg["provider"] = PRESET_ORDER[_provider.selected]
	cfg["base_url"] = _base_url.text.strip_edges()
	cfg["model"] = _model.text.strip_edges()
	cfg["api_key"] = _api_key.text.strip_edges()
	cfg["github_token"] = _github_token.text.strip_edges()
	cfg["github_repo"] = _github_repo.text.strip_edges()
	return cfg


func _save() -> void:
	if AdvisorConfig.save_cfg(_gathered_cfg()):
		_status.text = "Saved."
		_status.add_theme_color_override("font_color", UiTheme.GOOD)
	else:
		_status.text = "Could not write the config file."
		_status.add_theme_color_override("font_color", UiTheme.BAD)


func _on_preset_picked(index: int) -> void:
	var preset: Dictionary = PRESETS[PRESET_ORDER[index]]
	_base_url.text = String(preset["base_url"])
	_model.text = String(preset["model"])
	_base_url.editable = PRESET_ORDER[index] != "anthropic"
	_model_pick.visible = false


func _list_models() -> void:
	if client == null:
		return
	_status.text = "Asking Ollama…"
	_status.add_theme_color_override("font_color", UiTheme.PARCHMENT_DIM)
	client.list_ollama_models(_base_url.text.strip_edges())


func _on_models(names: Array) -> void:
	if names.is_empty():
		_status.text = "Ollama answered, but no models are pulled."
		_status.add_theme_color_override("font_color", UiTheme.WARN)
		return
	_model_pick.clear()
	for model_name in names:
		_model_pick.add_item(String(model_name))
	_model_pick.visible = true
	_model.text = String(names[0])
	_status.text = "%d local models found." % names.size()
	_status.add_theme_color_override("font_color", UiTheme.GOOD)


func _test_connection() -> void:
	if client == null:
		return
	_status.text = "Testing…"
	_status.add_theme_color_override("font_color", UiTheme.PARCHMENT_DIM)
	client.ask(_gathered_cfg(), "Reply with the single word: SALVE",
		[{"role": "user", "content": "Test."}])


func _on_test_reply(_text: String) -> void:
	if not visible:
		return
	_status.text = "Connection good — the model answered."
	_status.add_theme_color_override("font_color", UiTheme.GOOD)


func _on_test_failed(reason: String) -> void:
	if not visible:
		return
	_status.text = reason
	_status.add_theme_color_override("font_color", UiTheme.BAD)


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiTheme.GOLD)
	return label
