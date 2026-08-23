class_name FeedbackPanel
extends AcceptDialog
## From "this feels wrong" to a debuggable ticket without leaving the game:
## the form gathers the world seed, date, faction, difficulty, version, and
## the recent turn log, and files a labeled GitHub issue — or copies a
## ready-to-paste markdown body when no token is configured.

const CATEGORIES := ["bug", "confusing", "idea"]
const CATEGORY_LABELS := ["Bug — something built is misbehaving",
	"Confusing — I don't understand what happened", "Idea — something the game should have"]

var game: Game
var screen: CampaignScreen
var client: LlmClient

var _category: OptionButton
var _title_input: LineEdit
var _description: TextEdit
var _context_preview: Label
var _send_button: Button
var _status: RichTextLabel


func _init() -> void:
	title = "Feedback to the Builders"
	min_size = Vector2i(600, 640)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(570, 580)
	add_child(column)

	_category = OptionButton.new()
	for label in CATEGORY_LABELS:
		_category.add_item(label)
	column.add_child(_category)

	_title_input = LineEdit.new()
	_title_input.placeholder_text = "One line: what happened?"
	column.add_child(_title_input)

	_description = TextEdit.new()
	_description.placeholder_text = "What did you do, what did you expect, what happened instead?"
	_description.custom_minimum_size = Vector2(0, 180)
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(_description)

	var preview_header := Label.new()
	preview_header.text = "Attached automatically:"
	preview_header.add_theme_font_size_override("font_size", 11)
	preview_header.add_theme_color_override("font_color", UiTheme.GOLD)
	column.add_child(preview_header)
	_context_preview = Label.new()
	_context_preview.add_theme_font_size_override("font_size", 10)
	_context_preview.add_theme_color_override("font_color", UiTheme.PARCHMENT_DIM)
	column.add_child(_context_preview)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_send_button = Button.new()
	_send_button.text = "Send to GitHub"
	_send_button.pressed.connect(_send)
	buttons.add_child(_send_button)
	var copy := Button.new()
	copy.text = "Copy as Markdown"
	copy.pressed.connect(_copy)
	buttons.add_child(copy)

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size = Vector2(0, 40)
	_status.meta_clicked.connect(func(meta): OS.shell_open(String(meta)))
	column.add_child(_status)


func open_for(current_game: Game, campaign_screen: CampaignScreen) -> void:
	game = current_game
	screen = campaign_screen
	if client == null:
		client = LlmClient.new()
		client.json_completed.connect(_on_response)
		client.failed.connect(_on_failed)
		add_child(client)
	var cfg := AdvisorConfig.load_cfg()
	var meta := gather_meta(game, _log_tail())
	_context_preview.text = "seed %d · turn %d (%s %s) · %s · %s · v%s · last %d log lines" % [
		int(meta["seed"]), int(meta["turn"]), String(meta["season"]), _year_text(int(meta["year"])),
		String(meta["faction"]), String(meta["difficulty"]), String(meta["version"]),
		meta["log_tail"].size()]
	var has_token := String(cfg["github_token"]) != ""
	_send_button.disabled = not has_token
	_send_button.tooltip_text = "" if has_token \
		else "Add a GitHub token in the Advisor's Settings to file tickets directly."
	_status.text = ""
	popup_centered()


## --- Pure builders (headless-testable) -------------------------------------

static func gather_meta(current_game: Game, log_tail: Array) -> Dictionary:
	var state: Dictionary = current_game.state
	return {
		"seed": int(state.get("world_seed", 0)),
		"turn": int(state["turn"]),
		"year": int(state["year"]),
		"season": String(state["season"]),
		"faction": String(state["player_faction"]),
		"difficulty": String(state["difficulty"]),
		"version": AdvisorConfig.GAME_VERSION,
		"log_tail": log_tail,
	}


static func build_issue_markdown(meta: Dictionary, category: String, title_text: String, description: String) -> String:
	var year := int(meta["year"])
	var year_text := ("%d BC" % -year) if year < 0 else ("AD %d" % year)
	var parts: Array = []
	parts.append(description.strip_edges())
	parts.append("")
	parts.append("| Seed | Turn | Date | Faction | Difficulty | Version | Category |")
	parts.append("|---|---|---|---|---|---|---|")
	parts.append("| %d | %d | %s, %s | %s | %s | %s | %s |" % [
		int(meta["seed"]), int(meta["turn"]), year_text, String(meta["season"]),
		String(meta["faction"]), String(meta["difficulty"]), String(meta["version"]), category])
	var log_tail: Array = meta.get("log_tail", [])
	var log_lines: Array = []
	for entry in log_tail:
		var clean := String(entry).strip_edges()
		if clean != "":
			log_lines.append(clean)
	if not log_lines.is_empty():
		parts.append("")
		parts.append("<details><summary>Recent turn log</summary>")
		parts.append("")
		parts.append("```")
		parts.append_array(log_lines)
		parts.append("```")
		parts.append("</details>")
	parts.append("")
	parts.append("_Filed from inside the game. Reproduce with `tools/sim_campaign.gd -- %d <turns> %s %s`._" % [
		int(meta["seed"]), String(meta["faction"]), String(meta["difficulty"])])
	return "\n".join(parts)


static func build_issue_request(cfg: Dictionary, category: String, title_text: String, body_md: String) -> Dictionary:
	return {
		"url": "https://api.github.com/repos/%s/issues" % String(cfg.get("github_repo", "")),
		"headers": PackedStringArray([
			"Authorization: Bearer " + String(cfg.get("github_token", "")),
			"Accept: application/vnd.github+json",
			"X-GitHub-Api-Version: 2022-11-28",
			"Content-Type: application/json",
			"User-Agent: roman-war-advisor",
		]),
		"body": JSON.stringify({
			"title": title_text,
			"body": body_md,
			"labels": ["in-game", category],
		}),
	}


## --- Actions ----------------------------------------------------------------

func _send() -> void:
	var title_text := _title_input.text.strip_edges()
	if title_text == "":
		_status.text = "[color=#cc6655]A ticket needs a title.[/color]"
		return
	var cfg := AdvisorConfig.load_cfg()
	var category: String = CATEGORIES[_category.selected]
	var body := build_issue_markdown(gather_meta(game, _log_tail()), category,
		title_text, _description.text)
	_send_button.disabled = true
	_status.text = "[color=#a4977c]Filing the ticket…[/color]"
	client.post_json(build_issue_request(cfg, category, title_text, body))


func _copy() -> void:
	var title_text := _title_input.text.strip_edges()
	var category: String = CATEGORIES[_category.selected]
	var body := "## %s\n\n%s" % [title_text if title_text != "" else "(untitled)",
		build_issue_markdown(gather_meta(game, _log_tail()), category, title_text, _description.text)]
	DisplayServer.clipboard_set(body)
	var cfg := AdvisorConfig.load_cfg()
	_status.text = "[color=#7fa15a]Copied. Paste it at[/color] [url=https://github.com/%s/issues/new]github.com/%s/issues/new[/url]" \
		% [String(cfg["github_repo"]), String(cfg["github_repo"])]


func _on_response(code: int, body: String) -> void:
	_send_button.disabled = false
	if code == 201:
		var parsed = JSON.parse_string(body)
		var url := String(parsed.get("html_url", "")) if parsed is Dictionary else ""
		_status.text = "[color=#7fa15a]Ticket filed:[/color] [url=%s]%s[/url]" % [url, url]
		if screen != null:
			screen._log("[color=#7fa15a]Feedback filed: [url=%s]%s[/url][/color]" % [url, url])
		_title_input.text = ""
		_description.text = ""
	elif code == 401 or code == 403:
		_status.text = "[color=#cc6655]GitHub rejected the token (HTTP %d). Check it in the Advisor's Settings, or use Copy as Markdown.[/color]" % code
	elif code == 404:
		_status.text = "[color=#cc6655]Repo not found (404) — the token may lack access to it. Copy as Markdown still works.[/color]"
	else:
		_status.text = "[color=#cc6655]GitHub answered HTTP %d. Copy as Markdown still works.[/color]" % code


func _on_failed(reason: String) -> void:
	_send_button.disabled = false
	_status.text = "[color=#cc6655]%s Copy as Markdown still works.[/color]" % reason.xml_escape()


func _log_tail() -> Array:
	if screen == null or screen.report_log == null:
		return []
	var lines := screen.report_log.get_parsed_text().split("\n")
	var tail: Array = []
	for i in range(maxi(0, lines.size() - 20), lines.size()):
		tail.append(lines[i])
	return tail


func _year_text(year: int) -> String:
	return ("%d BC" % -year) if year < 0 else ("AD %d" % year)
