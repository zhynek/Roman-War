class_name TurnJournal
## The day's transcript. Every notable thing an end-turn does appends one beat
## here, and the UI replays them as the turn sequence and the Daily Dispatch.
##
## A beat is deliberately CONTENT-FREE: ids and numbers only. Every word the
## player reads comes from data/dispatch.json, keyed by the beat kind. That
## keeps the engine thin, keeps the prose in data where it can be edited and
## validated, and keeps the journal JSON-safe so it round-trips through a save
## byte for byte.
##
## The journal lives in state["journal"] and holds ONE turn — it is rebuilt
## every end_turn, so it never grows across a 568-turn campaign, and a save
## taken while the Dispatch is open reopens on exactly the same day.


## Every beat kind the engine can emit. tools/validate_data.py parses this list
## and requires it to match data/dispatch.json exactly in both directions, so a
## kind with no prose (or prose for a kind nothing emits) fails the build.
const KINDS: Array[String] = [
	# Our works — what the player's own orders finished.
	"building_completed",
	"unit_mustered",
	# Our coffers and people.
	"treasury_change",
	"unit_disbanded",
	"settlement_riot",
	"settlement_revolt",
	"settlement_grew",
	"settlement_shrank",
	"plague_outbreak",
	# The province's temper, from the society layer.
	"province_settled",
	"province_restive",
	"province_rebellious",
	# What the people have worked out, and what they have forgotten.
	"advance_gained",
	# The crafts a people works out, takes up, or hears of from abroad.
	"technique_originated",
	"technique_adopted",
	"technique_spread",
	"advance_lost",
	"capital_growth",
	"capital_decline",
	# The wider world.
	"war_declared",
	"peace_made",
	"alliance_formed",
	"alliance_broken",
	"trade_agreed",
	"faction_destroyed",
	"army_march",
	"army_sighted",
	"march_arrived",
	"march_halted",
	"march_onward",
	"battle_fought",
	"siege_begun",
	"assault_repelled",
	"siege_starved",
	"settlement_captured",
	"world_event",
	"disaster",
	# Our cause.
	"mission_issued",
	# The guided campaign trail — the player's own thread through the age.
	"trail_started",
	"trail_complete",
	"trail_expired",
	"mission_progress",
	"mission_complete",
	"mission_failed",
	"mission_voided",
	"civil_war",
	"civil_war_ambition",
	# The Republic's politics (Phase 7): the cursus honorum and the civil war's sides.
	"office_gained",
	"consuls_elected",
	"house_joins_rebellion",
	"house_stays_loyal",
	"civil_war_over",
	"victory_progress",
	"campaign_decided",
	"family_birth",
	"family_came_of_age",
	"family_marriage",
	"family_adoption",
	"family_new_heir",
	"family_succession",
	"family_death",
	"family_trait",
	"family_ancillary",
	"family_man_of_the_hour",
]


static func fresh(turn: int) -> Dictionary:
	return {"turn": turn, "beats": []}


static func of(state: Dictionary) -> Array:
	## The current turn's beats, safe on a save written before journals existed.
	return state.get("journal", {}).get("beats", [])


static func add(journal: Array, kind: String, fields: Dictionary = {}) -> void:
	## Appends one beat, filled out to the canonical shape so every record has
	## the same keys and a JSON round trip cannot reorder them into a different
	## dictionary. Unknown kinds are dropped rather than shipped to a UI that
	## has no prose for them — the validator is what catches them at build time.
	if not KINDS.has(kind):
		return
	journal.append({
		"kind": kind,
		"faction": String(fields.get("faction", "")),
		"other": String(fields.get("other", "")),
		"region": String(fields.get("region", "")),
		"subject": String(fields.get("subject", "")),
		"value": fields.get("value", 0),
		"extra": fields.get("extra", {}),
	})


## The character engine reports one notice kind per thing that can happen to a
## person; each gets its own beat so data/dispatch.json can give a birth, a
## death and a won laurel their own words instead of one shared line.
const FAMILY_BEATS := {
	"birth": "family_birth",
	"came_of_age": "family_came_of_age",
	"marriage": "family_marriage",
	"adoption": "family_adoption",
	"new_heir": "family_new_heir",
	"succession": "family_succession",
	"death": "family_death",
	"trait": "family_trait",
	"ancillary": "family_ancillary",
	"man_of_the_hour": "family_man_of_the_hour",
}


static func add_character_notice(state: Dictionary, journal: Array, notice: Dictionary) -> void:
	var beat_kind: String = String(FAMILY_BEATS.get(String(notice.get("kind", "")), ""))
	if beat_kind == "":
		return
	var char_id: String = String(notice.get("character", ""))
	var character: Dictionary = state["characters"].get(char_id, {})
	# Trait and ancillary notices carry a second id worth naming; everything
	# else is about the person alone.
	var detail: String = String(notice.get("trait", notice.get("ancillary", "")))
	add(journal, beat_kind, {
		"faction": String(notice.get("faction", character.get("faction", ""))),
		"region": String(character.get("location", "")),
		"subject": char_id,
		"value": int(notice.get("level", 0)),
		"extra": {"detail": detail},
	})


## --- Snapshot and diff ----------------------------------------------------
##
## Diplomacy changes hands in too many places to instrument: the player's own
## panel, the AI, and CombatRules.attack_army, where attacking IS a declaration
## of war. Rather than thread a journal through all of them, end_turn photographs
## the world before and after and reports the difference. Same for the treasury
## and the capital, which the player wants to watch rise and fall.


static func snapshot(data: GameData, state: Dictionary) -> Dictionary:
	var factions := {}
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		var capital: String = String(faction.get("capital", ""))
		factions[faction_id] = {
			"alive": bool(faction["alive"]),
			"treasury": int(faction["treasury"]),
			"capital": capital,
			"capital_population": int(state["settlements"].get(capital, {}).get("population", 0)),
		}
	return {
		"factions": factions,
		"stances": _stances(state),
		"levels": _levels(data, state),
		"regions_held": _regions_held(state),
	}


static func diff(data: GameData, state: Dictionary, before: Dictionary, journal: Array) -> void:
	var after := snapshot(data, state)

	# Stance changes, reported once per pair (the graph is symmetric).
	var pairs: Array = after["stances"].keys()
	pairs.sort()
	for pair in pairs:
		var was: String = String(before["stances"].get(pair, "neutral"))
		var now: String = String(after["stances"][pair])
		if was == now:
			continue
		var sides: PackedStringArray = String(pair).split("|")
		var fields := {"faction": sides[0], "other": sides[1]}
		if now == "war":
			add(journal, "war_declared", fields)
		elif was == "war":
			add(journal, "peace_made", fields)
		elif now == "alliance":
			add(journal, "alliance_formed", fields)
		elif was == "alliance":
			add(journal, "alliance_broken", fields)
		elif now == "trade":
			add(journal, "trade_agreed", fields)

	# A city changes tier when a government building finishes, when a riot
	# wrecks one, or when it changes hands. Only the first is worth a beat —
	# a captured city already has its own.
	var region_ids: Array = after["levels"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var was_level: Dictionary = before["levels"].get(region_id, {})
		var now_level: Dictionary = after["levels"][region_id]
		if was_level.is_empty() or String(was_level["owner"]) != String(now_level["owner"]):
			continue
		var was_rank := Constants.level_index(String(was_level["level"]))
		var now_rank := Constants.level_index(String(now_level["level"]))
		if was_rank == now_rank:
			continue
		add(journal, "settlement_grew" if now_rank > was_rank else "settlement_shrank", {
			"faction": now_level["owner"], "region": region_id,
			"subject": now_level["level"],
			"value": int(now_level["population"]) - int(was_level["population"]),
			"extra": {"population": int(now_level["population"])},
		})

	var faction_ids: Array = after["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var was: Dictionary = before["factions"].get(faction_id, {})
		var now: Dictionary = after["factions"][faction_id]
		if was.is_empty():
			continue
		if was["alive"] and not now["alive"]:
			add(journal, "faction_destroyed", {"faction": faction_id})
			continue
		if not now["alive"]:
			continue
		# The capital rising or falling is the player's clearest read on whether
		# the day went well, so it is reported every turn it moves at all.
		var population_delta: int = int(now["capital_population"]) - int(was["capital_population"])
		if population_delta != 0 and String(now["capital"]) == String(was["capital"]):
			add(journal, "capital_growth" if population_delta > 0 else "capital_decline", {
				"faction": faction_id, "region": now["capital"], "value": population_delta,
				"extra": {"population": int(now["capital_population"])},
			})
		# Victory progress is only news when the map moved. Reporting it every
		# turn would bury the day the border actually shifted.
		var held_now := int(after["regions_held"].get(faction_id, 0))
		var held_was := int(before["regions_held"].get(faction_id, 0))
		if held_now != held_was:
			add(journal, "victory_progress", {
				"faction": faction_id, "value": held_now,
				"extra": {"gained": held_now - held_was},
			})


static func _levels(data: GameData, state: Dictionary) -> Dictionary:
	## {region_id: {level, owner}}. The snapshot runs before and after the whole
	## turn, so a diff catches a city outgrowing its walls whether the cause was
	## a finished government building, a riot that wrecked one, or a change of
	## owner — without any of those three phases knowing about the journal.
	var levels := {}
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		levels[region_id] = {
			"level": SettlementRules.settlement_level(data, settlement),
			"owner": String(settlement["owner"]),
			"population": int(settlement["population"]),
		}
	return levels


static func _regions_held(state: Dictionary) -> Dictionary:
	var held := {}
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var owner: String = String(state["settlements"][region_id]["owner"])
		held[owner] = int(held.get(owner, 0)) + 1
	return held


static func _stances(state: Dictionary) -> Dictionary:
	## {"a|b": stance} over sorted pairs, so the diff order never depends on how
	## the state dictionary happened to be built.
	var stances := {}
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for i in range(faction_ids.size()):
		for j in range(i + 1, faction_ids.size()):
			var a: String = faction_ids[i]
			var b: String = faction_ids[j]
			stances["%s|%s" % [a, b]] = DiplomacyRules.stance_between(state, a, b)
	return stances
