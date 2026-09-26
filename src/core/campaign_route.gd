class_name CampaignRoute
extends RefCounted
## Repeatable initial conditions for the separate development app. Once built,
## this is an ordinary Game: no scripted turns, movement or battle outcomes.

static func build() -> Game:
	var data := GameData.load_from()
	var route: Dictionary = data.terrain_content["development_route"]
	var game := Game.new_campaign(route["player"], int(route["seed"]))
	var state := game.state
	var player := String(route["player"])
	for region in route["regions"]:
		var settlement: Dictionary = state["settlements"][region]
		settlement["owner"] = player
		settlement["siege"] = null
		settlement["governor"] = null
		# Unimproved roads make the terrain costs directly comparable.
		for chain in settlement["buildings"].keys():
			if data.chains.get(chain, {}).get("kind", "") == "roads":
				settlement["buildings"].erase(chain)
	for faction in route["peace_with"]:
		DiplomacyRules.set_stance(state, player, faction, "alliance")
	var ids: Array = state["armies"].keys()
	ids.sort()
	var positioned := false
	var contact_positioned := false
	for id in ids:
		var army: Dictionary = state["armies"][id]
		if army["owner"] == player and not positioned:
			army["region"] = route["regions"][0]
			MovementRules.sync_general_location(state, army)
			positioned = true
		elif army["owner"] == route["contact_owner"] and not contact_positioned:
			contact_positioned = true
			army["region"] = route["contact_region"]
			army["units"] = NewGame._units(route["contact_units"])
			army["movement_left"] = MovementRules.movement_points_for(data, state, army)
			MovementRules.sync_general_location(state, army)
	# Initial geography comes from these observers. The additional atlas is
	# a signed directional agreement, exactly as in normal negotiations.
	state["cartography"] = {}
	state["recon"] = {"contacts": {}, "movements": []}
	CartographyRules.grant(data, state, route["map_grantor"], player)
	ReconRules.refresh_contacts(data, state)
	SettlementRules.refresh_governors(data, state)
	return game
