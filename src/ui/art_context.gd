class_name ArtContext
extends RefCounted
## Assembles the mutable half of a plate — season, terrain, owner's colour,
## whether the thing is half-built or knocked about — so BuildingArt itself
## never has to read GameState.


static func for_settlement(game, region_id: String, lod: int = 2) -> Dictionary:
	var region: Dictionary = game.data.regions.get(region_id, {})
	var settlement: Dictionary = game.state["settlements"].get(region_id, {})
	var owner: String = settlement.get("owner", "rebels")
	return {
		"culture": game.data.culture_of_faction(owner),
		"terrain": String(region.get("terrain", "plains")),
		"fertility": float(region.get("fertility", 1.5)),
		"season": String(game.state.get("season", "summer")),
		"tint": MapView._house_key(Color.html(
			game.data.factions.get(owner, {}).get("color", "#808080"))),
		"progress": 1.0,
		"damaged": settlement.get("siege") != null,
		"lod": lod,
	}
