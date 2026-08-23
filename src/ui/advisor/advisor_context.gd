class_name AdvisorContext
## Pure assembly of everything the Advisor's model gets to see: the bundled
## knowledge pack (data/advisor.json) plus a live digest of the campaign.
## No network, no mutation — string building only, so tests cover it headless.


static func load_pack(path: String = "res://data/advisor.json") -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not (parsed is Dictionary):
		return {}
	return parsed.get("advisor", {})


static func build_state_digest(game: Game, selected_region: String, log_tail: Array) -> String:
	var state: Dictionary = game.state
	var player := String(state["player_faction"])
	var faction: Dictionary = state["factions"][player]
	var lines: Array = []

	var year := int(state["year"])
	var year_text := ("%d BC" % -year) if year < 0 else ("AD %d" % year)
	lines.append("Date: %s, %s (turn %d). Difficulty: %s. World seed: %d." % [
		year_text, String(state["season"]), int(state["turn"]),
		String(state["difficulty"]), int(state.get("world_seed", 0))])

	var projection := EconomyRules.faction_turn_breakdown(game.data, state, player)
	lines.append("Player: %s. Treasury %d denarii (net %+d per season)." % [
		game.data.factions.get(player, {}).get("name", player),
		int(faction["treasury"]), int(round(float(projection["net"])))])

	var progress := game.victory_progress()
	if not progress.is_empty():
		lines.append("Victory: holds %d of the %d regions required, before AD 14." % [
			int(progress["regions_held"]), int(progress["regions_needed"])])

	var wars: Array = []
	var other_ids: Array = state["factions"].keys()
	other_ids.sort()
	for other_id in other_ids:
		if other_id != player and state["factions"][other_id]["alive"] \
				and DiplomacyRules.at_war(state, player, other_id):
			wars.append(game.data.factions.get(other_id, {}).get("name", other_id))
	lines.append("At war with: %s." % (", ".join(wars) if not wars.is_empty() else "no one"))

	if selected_region != "" and state["settlements"].has(selected_region):
		var settlement: Dictionary = state["settlements"][selected_region]
		lines.append("Player is looking at %s (%s): owner %s, population %d, public order %d%%." % [
			game.data.regions[selected_region].get("settlement_name", selected_region),
			game.data.regions[selected_region].get("name", selected_region),
			String(settlement["owner"]), int(settlement["population"]),
			int(PublicOrderRules.total(game.data, state, selected_region))])

	if not log_tail.is_empty():
		lines.append("Recent turn log:")
		for entry in log_tail:
			var clean := String(entry).strip_edges()
			if clean != "":
				lines.append("  " + clean)
	return "\n".join(lines)


static func build_system_prompt(pack: Dictionary, digest: String, open_issues: Array) -> String:
	var parts: Array = []
	parts.append(String(pack.get("persona", "")))
	parts.append("\n## The game\n" + String(pack.get("overview", "")))

	parts.append("\n## System status ledger\nWhen the player reports something odd, check this ledger FIRST: if the system is not_built or partial, tell them plainly it is not built yet (not a bug) and suggest filing it through the Feedback form as an idea. If a built system is misbehaving, call it a likely bug and suggest filing it as a bug — the form attaches the world seed automatically.")
	for system in pack.get("systems", []):
		parts.append("- [%s] %s — %s" % [String(system["status"]), String(system["name"]),
			String(system["note"])])

	parts.append("\n## Questions players often ask")
	for entry in pack.get("faq", []):
		parts.append("Q: %s\nA: %s" % [String(entry["q"]), String(entry["a"])])

	parts.append("\n## The campaign right now\n" + digest)

	if not open_issues.is_empty():
		parts.append("\n## Already-reported in-game issues (open on GitHub)")
		for title in open_issues:
			parts.append("- " + String(title))
		parts.append("If the player's report matches one of these, say it is already filed.")

	parts.append("\n## How to answer\nKeep answers under 150 words. Never invent mechanics, numbers, or keybinds that are not in this briefing. You cannot change the game, only advise. If you do not know, say so and point at the Feedback form.")
	return "\n".join(parts)


static func build_issues_request(cfg: Dictionary) -> Dictionary:
	## GET the open in-game issues so the Advisor can say "already reported".
	return {
		"url": "https://api.github.com/repos/%s/issues?labels=in-game&state=open&per_page=20" \
			% String(cfg.get("github_repo", "")),
		"headers": PackedStringArray([
			"Authorization: Bearer " + String(cfg.get("github_token", "")),
			"Accept: application/vnd.github+json",
			"X-GitHub-Api-Version: 2022-11-28",
			"User-Agent: roman-war-advisor",
		]),
		"body": "",
	}


static func parse_issue_titles(body: String) -> Array:
	var parsed = JSON.parse_string(body)
	if parsed == null or not (parsed is Array):
		return []
	var titles: Array = []
	for issue in parsed:
		if issue is Dictionary and issue.has("title"):
			titles.append("#%d %s" % [int(issue.get("number", 0)), String(issue["title"])])
	return titles
