extends RefCounted
## The Advisor stack's pure machinery: wire formats, prompt assembly, and the
## feedback ticket builders — all without a byte of network.


func test_openai_request_shape(t) -> void:
	var cfg := {"provider": "ollama", "base_url": "http://127.0.0.1:11434/v1/", "model": "llama3.1", "api_key": ""}
	var request := LlmClient.build_openai_request(cfg, [
		{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
	t.check_eq(request["url"], "http://127.0.0.1:11434/v1/chat/completions", "url joined without a double slash")
	t.check(Array(request["headers"]).has("Authorization: Bearer ollama"), "keyless Ollama gets a dummy bearer")
	var body = JSON.parse_string(String(request["body"]))
	t.check_eq(body["model"], "llama3.1", "model in body")
	t.check_eq(body["stream"], false, "streaming off")
	t.check_eq(body["messages"][0]["role"], "system", "system message leads")

	cfg["api_key"] = "sk-live"
	var keyed := LlmClient.build_openai_request(cfg, [])
	t.check(Array(keyed["headers"]).has("Authorization: Bearer sk-live"), "a real key rides the bearer")


func test_anthropic_request_shape(t) -> void:
	var cfg := {"provider": "anthropic", "model": "claude-haiku-4-5", "api_key": "sk-ant-x"}
	var request := LlmClient.build_anthropic_request(cfg, "the system prompt",
		[{"role": "user", "content": "hi"}])
	t.check_eq(request["url"], "https://api.anthropic.com/v1/messages", "anthropic endpoint")
	var headers := Array(request["headers"])
	t.check(headers.has("x-api-key: sk-ant-x"), "key header present")
	t.check(headers.has("anthropic-version: 2023-06-01"), "version header present")
	var body = JSON.parse_string(String(request["body"]))
	t.check_eq(body["system"], "the system prompt", "system is top-level")
	t.check(int(body["max_tokens"]) > 0, "max_tokens present")
	for message in body["messages"]:
		t.check(message["role"] != "system", "no system role in anthropic messages")


func test_response_parsing(t) -> void:
	var openai_ok := JSON.stringify({"choices": [{"message": {"role": "assistant", "content": "salve"}}]})
	var parsed := LlmClient.parse_chat_response("ollama", 200, openai_ok)
	t.check(parsed["ok"] and parsed["text"] == "salve", "openai-shape reply parsed")

	var anthropic_ok := JSON.stringify({"content": [{"type": "text", "text": "ave"}]})
	parsed = LlmClient.parse_chat_response("anthropic", 200, anthropic_ok)
	t.check(parsed["ok"] and parsed["text"] == "ave", "anthropic-shape reply parsed")

	var error_body := JSON.stringify({"error": {"message": "model not found"}})
	parsed = LlmClient.parse_chat_response("ollama", 404, error_body)
	t.check(not parsed["ok"] and String(parsed["error"]).contains("model not found"),
		"API error surfaced")

	var tags := JSON.stringify({"models": [{"name": "qwen"}, {"name": "llama3.1"}]})
	t.check_eq(LlmClient.parse_ollama_tags(tags), ["llama3.1", "qwen"], "ollama tags parsed sorted")


func test_friendly_errors(t) -> void:
	var refused := LlmClient.friendly_error(HTTPRequest.RESULT_CANT_CONNECT, 0, "ollama",
		"http://127.0.0.1:11434/v1")
	t.check(refused.contains("ollama serve"), "a dead Ollama gets actionable advice")
	t.check(LlmClient.friendly_error(HTTPRequest.RESULT_SUCCESS, 401, "anthropic").contains("key"),
		"401 blames the key")
	t.check(LlmClient.friendly_error(HTTPRequest.RESULT_TIMEOUT, 0, "ollama").contains("too long"),
		"timeouts explained")


func test_state_digest(t) -> void:
	var game := Game.new_campaign("julii", 42, "easy")
	var digest := AdvisorContext.build_state_digest(game, "etruria", ["The year is 270 BC."])
	t.check(digest.contains("World seed: 42"), "seed in the digest")
	t.check(digest.contains("270 BC"), "date in the digest")
	t.check(digest.contains("Julii"), "player named")
	t.check(digest.contains("Arretium"), "selected settlement described")
	t.check(digest.contains("rebels") or digest.contains("Rebel") or digest.contains("Independent"),
		"the standing rebel war is listed")
	t.check(digest.length() < 6000, "digest stays inside its budget (%d chars)" % digest.length())


func test_system_prompt_assembly(t) -> void:
	var pack := AdvisorContext.load_pack()
	t.check(not pack.is_empty(), "knowledge pack loads")
	var prompt := AdvisorContext.build_system_prompt(pack, "DIGEST_MARKER", ["#7 Naval bug"])
	t.check(prompt.contains("[not_built]"), "the gaps ledger is in the prompt")
	t.check(prompt.contains("Q: "), "the FAQ is in the prompt")
	t.check(prompt.contains("DIGEST_MARKER"), "the live digest is injected")
	t.check(prompt.contains("#7 Naval bug"), "open tickets are injected")
	t.check(prompt.contains("150 words"), "the brevity rule is standing")


func test_issue_builders(t) -> void:
	var game := Game.new_campaign("junii", 777, "hard")
	var meta := FeedbackPanel.gather_meta(game, ["line one", "", "line two"])
	t.check_eq(int(meta["seed"]), 777, "seed gathered")
	t.check_eq(meta["faction"], "junii", "faction gathered")
	t.check_eq(meta["difficulty"], "hard", "difficulty gathered")
	t.check_eq(meta["version"], AdvisorConfig.GAME_VERSION, "version stamped")

	var markdown := FeedbackPanel.build_issue_markdown(meta, "bug", "Weird siege", "It broke.")
	t.check(markdown.contains("| 777 |"), "seed row present")
	t.check(markdown.contains("It broke."), "description present")
	t.check(markdown.contains("<details>"), "log tail collapsed")
	t.check(markdown.contains("line two"), "log lines included")
	t.check(markdown.contains("sim_campaign.gd -- 777"), "reproduction command included")

	var no_log := FeedbackPanel.build_issue_markdown(
		FeedbackPanel.gather_meta(game, []), "idea", "More ships", "Please")
	t.check(not no_log.contains("<details>"), "no empty log block")

	var cfg := {"github_repo": "zhynek/roman-war", "github_token": "github_pat_x"}
	var request := FeedbackPanel.build_issue_request(cfg, "bug", "Weird siege", markdown)
	t.check_eq(request["url"], "https://api.github.com/repos/zhynek/roman-war/issues", "issues endpoint")
	t.check(Array(request["headers"]).has("Authorization: Bearer github_pat_x"), "PAT rides the bearer")
	var body = JSON.parse_string(String(request["body"]))
	t.check_eq(body["labels"], ["in-game", "bug"], "labels set")

	var issues_request := AdvisorContext.build_issues_request(cfg)
	t.check(String(issues_request["url"]).contains("labels=in-game"), "issue lookup filters the label")
	var titles := AdvisorContext.parse_issue_titles(JSON.stringify([
		{"number": 3, "title": "Ships"}, {"number": 9, "title": "Taxes"}]))
	t.check_eq(titles, ["#3 Ships", "#9 Taxes"], "issue titles parsed")


func test_panels_instantiate(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42, "easy")
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	t.check(screen.advisor_panel != null, "advisor panel exists")
	t.check(screen.feedback_panel != null, "feedback panel exists")
	screen.feedback_panel.open_for(game, screen)
	t.check(screen.feedback_panel._send_button.disabled, "no token: direct send disabled")
	t.check(screen.feedback_panel._context_preview.text.contains("seed 42"),
		"the attached context names the seed")
	screen.feedback_panel.hide()
	screen.advisor_panel.open_for(game, screen)
	t.check(screen.advisor_panel.client != null, "advisor client spawns")
	screen.advisor_panel.hide()
	screen.free()
