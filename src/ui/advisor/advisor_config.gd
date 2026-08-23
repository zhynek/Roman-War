class_name AdvisorConfig
## Local, never-shipped configuration for the Advisor stack: which LLM to
## talk to, the GitHub token for filing feedback, and whether the guided
## opening has been seen. Lives in user://advisor.cfg (plain text — the
## settings dialog says so out loud). The path is injectable so tests can
## use a scratch file.

const DEFAULT_PATH := "user://advisor.cfg"
const GAME_VERSION := "0.9.0"

const DEFAULTS := {
	"provider": "ollama",             # ollama | anthropic | openai_compat
	"base_url": "http://127.0.0.1:11434/v1",
	"model": "llama3.1",
	"api_key": "",
	"github_token": "",
	"github_repo": "zhynek/roman-war",
	"tutorial_seen": false,
}


static func load_cfg(path: String = DEFAULT_PATH) -> Dictionary:
	var cfg := DEFAULTS.duplicate()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return cfg
	cfg["provider"] = String(file.get_value("advisor", "provider", cfg["provider"]))
	cfg["base_url"] = String(file.get_value("advisor", "base_url", cfg["base_url"]))
	cfg["model"] = String(file.get_value("advisor", "model", cfg["model"]))
	cfg["api_key"] = String(file.get_value("advisor", "api_key", cfg["api_key"]))
	cfg["github_token"] = String(file.get_value("github", "token", cfg["github_token"]))
	cfg["github_repo"] = String(file.get_value("github", "repo", cfg["github_repo"]))
	cfg["tutorial_seen"] = bool(file.get_value("meta", "tutorial_seen", cfg["tutorial_seen"]))
	return cfg


static func save_cfg(cfg: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var file := ConfigFile.new()
	file.load(path)  # keep any unknown keys a future version may have written
	file.set_value("advisor", "provider", cfg.get("provider", DEFAULTS["provider"]))
	file.set_value("advisor", "base_url", cfg.get("base_url", DEFAULTS["base_url"]))
	file.set_value("advisor", "model", cfg.get("model", DEFAULTS["model"]))
	file.set_value("advisor", "api_key", cfg.get("api_key", ""))
	file.set_value("github", "token", cfg.get("github_token", ""))
	file.set_value("github", "repo", cfg.get("github_repo", DEFAULTS["github_repo"]))
	file.set_value("meta", "tutorial_seen", cfg.get("tutorial_seen", false))
	return file.save(path) == OK


static func tutorial_seen(path: String = DEFAULT_PATH) -> bool:
	return bool(load_cfg(path)["tutorial_seen"])


static func mark_tutorial_seen(path: String = DEFAULT_PATH) -> void:
	var cfg := load_cfg(path)
	cfg["tutorial_seen"] = true
	save_cfg(cfg, path)
