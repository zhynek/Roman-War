extends Control
## Placeholder boot screen: proves the data tables load and a campaign starts.
## The real campaign-map UI replaces this scene; everything it will need comes
## from the Game facade's query methods.

@onready var summary_label: Label = $Summary


func _ready() -> void:
	var game := Game.new_campaign("julii", 42)
	if not game.data.ok():
		summary_label.text = "Data failed to load:\n" + "\n".join(game.data.load_errors)
		push_error(summary_label.text)
		return

	var factions_alive := 0
	for faction in game.state["factions"].values():
		if faction["alive"]:
			factions_alive += 1

	var year := int(game.state["year"])
	var year_label := "%d BC" % -year if year < 0 else "AD %d" % year
	summary_label.text = "ROMAN WAR — foundation build\n\n" \
		+ "%s, %s\n" % [year_label, String(game.state["season"]).capitalize()] \
		+ "%d factions · %d regions · %d settlements\n" % [
			factions_alive, game.data.regions.size(), game.state["settlements"].size()] \
		+ "%d unit types · %d building chains\n\n" % [game.data.units.size(), game.data.chains.size()] \
		+ "Playing: %s" % game.data.factions[game.state["player_faction"]]["name"]
	print(summary_label.text)
