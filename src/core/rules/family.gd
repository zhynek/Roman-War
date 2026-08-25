class_name FamilyRules
## The family tree's yearly rhythm (Phase 4): aging, natural death, succession,
## coming of age, births, marriages, adoption, and the hero-of-the-field
## adoption after a captain's unlikely victory. Runs once per game year.


static func process_year(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	var rules: Dictionary = data.balance["characters"]
	var notices: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()

	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if not character["alive"]:
			continue
		character["age"] = int(character["age"]) + 1
		var age := int(character["age"])

		if age >= int(rules["max_age"]) \
				or (age > int(rules["natural_death_base_age"]) and rng.chance(float(rules["natural_death_chance_per_year"]))):
			CharacterRules.kill(state, char_id)
			notices.append({"kind": "death", "character": char_id, "faction": character["faction"]})
			continue

		if character["role"] == "child" and age >= int(rules["come_of_age"]):
			if character.get("gender", "male") == "male":
				character["role"] = "family"
				CharacterRules.fire_trigger(data, state, char_id, "came_of_age", {}, rng, notices)
				notices.append({"kind": "came_of_age", "character": char_id, "faction": character["faction"]})
			elif age >= int(rules["marriageable_age"]) \
					and _living_family_count(state, character["faction"]) < int(rules.get("max_family_size", 12)) \
					and rng.chance(float(rules["marriage_suitor_chance_per_year"])):
				_marry_in_suitor(data, state, rng, char_id, notices)

	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"] or data.factions.get(faction_id, {}).get("is_rebel", false):
			continue
		_births(data, state, rng, faction_id, notices)
		_adoption(data, state, rng, faction_id, notices)
		ensure_succession(data, state, faction_id, notices)

	return notices


static func ensure_succession(data: GameData, state: Dictionary, faction_id: String, notices: Array) -> void:
	## A living leader, and a living heir whenever anyone is eligible. The heir
	## follows the dead leader; the new heir is the most influential adult male.
	var leader := _find_role(state, faction_id, "leader")
	if leader == "":
		var heir := _find_role(state, faction_id, "heir")
		if heir != "":
			state["characters"][heir]["role"] = "leader"
			notices.append({"kind": "succession", "character": heir, "faction": faction_id})
			leader = heir
		else:
			var candidate := _best_heir_candidate(data, state, faction_id)
			if candidate != "":
				state["characters"][candidate]["role"] = "leader"
				notices.append({"kind": "succession", "character": candidate, "faction": faction_id})
				leader = candidate
	if leader != "" and _find_role(state, faction_id, "heir") == "":
		var next_heir := _best_heir_candidate(data, state, faction_id)
		if next_heir != "":
			state["characters"][next_heir]["role"] = "heir"
			notices.append({"kind": "new_heir", "character": next_heir, "faction": faction_id})


static func set_heir(data: GameData, state: Dictionary, faction_id: String, char_id: String) -> bool:
	## The player names any adult male family member heir; the displaced heir
	## returns to the family bench.
	var character: Dictionary = state["characters"].get(char_id, {})
	if character.is_empty() or not character["alive"] or character["faction"] != faction_id:
		return false
	if character["role"] not in ["family", "heir"] or character.get("gender", "male") != "male":
		return false
	if int(character["age"]) < int(data.balance["characters"]["come_of_age"]):
		return false
	var current := _find_role(state, faction_id, "heir")
	if current != "" and current != char_id:
		state["characters"][current]["role"] = "family"
		# Being passed over is remembered, and it costs the man his standing.
		if data.traits.has("disinherited"):
			var threshold := int(data.traits["disinherited"]["levels"][0]["threshold"])
			CharacterRules.award_points(data, state["characters"][current], "disinherited", threshold)
	character["role"] = "heir"
	return true


static func maybe_man_of_the_hour(data: GameData, state: Dictionary, rng: CampaignRng, army: Dictionary, own_soldiers: int, enemy_soldiers: int, notices: Array) -> String:
	## A captain who wins while badly outnumbered may be adopted into the family
	## and takes command of the army he saved. Returns the new character id.
	var rules: Dictionary = data.balance["characters"]
	if army.get("general") != null:
		return ""
	var faction_id: String = army["owner"]
	if data.factions.get(faction_id, {}).get("is_rebel", false):
		return ""
	if own_soldiers <= 0 or float(enemy_soldiers) < float(own_soldiers) * float(rules["odds_against_ratio"]):
		return ""
	if not rng.chance(float(rules["man_of_the_hour_chance"])):
		return ""
	var char_id := _spawn_character(data, state, rng, faction_id, {
		"role": "family", "age": rng.randi_range(22, 34),
		"command": rng.randi_range(2, 5), "management": rng.randi_range(0, 2),
		"influence": rng.randi_range(0, 2), "location": army["region"],
	})
	army["general"] = char_id
	notices.append({"kind": "man_of_the_hour", "character": char_id, "faction": faction_id})
	return char_id


## --- Internals ------------------------------------------------------------

static func _births(data: GameData, state: Dictionary, rng: CampaignRng, faction_id: String, notices: Array) -> void:
	var rules: Dictionary = data.balance["characters"]
	var cap := int(rules.get("max_family_size", 12))
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var father: Dictionary = state["characters"][char_id]
		if father["faction"] != faction_id or not father["alive"]:
			continue
		if father["role"] not in ["leader", "heir", "family"] or father.get("gender", "male") != "male":
			continue
		var age := int(father["age"])
		if age < int(rules["birth_parent_min_age"]) or age > int(rules["birth_parent_max_age"]):
			continue
		if _living_family_count(state, faction_id) >= cap:
			return
		if not rng.chance(float(rules["birth_chance_per_year"])):
			continue
		var gender := "male" if rng.chance(0.5) else "female"
		var child_id := _spawn_character(data, state, rng, faction_id, {
			"role": "child", "age": 0, "gender": gender, "father": char_id,
			"location": father.get("location", ""),
		})
		notices.append({"kind": "birth", "character": child_id, "father": char_id, "faction": faction_id})


static func _marry_in_suitor(data: GameData, state: Dictionary, rng: CampaignRng, bride_id: String, notices: Array) -> void:
	var bride: Dictionary = state["characters"][bride_id]
	bride["role"] = "spouse"
	var suitor_id := _spawn_character(data, state, rng, bride["faction"], {
		"role": "family", "age": rng.randi_range(20, 32),
		"command": rng.randi_range(0, 3), "management": rng.randi_range(0, 3),
		"influence": rng.randi_range(0, 2), "location": bride.get("location", ""),
	})
	notices.append({"kind": "marriage", "character": suitor_id, "bride": bride_id, "faction": bride["faction"]})


static func _adoption(data: GameData, state: Dictionary, rng: CampaignRng, faction_id: String, notices: Array) -> void:
	var rules: Dictionary = data.balance["characters"]
	if _adult_male_count(data, state, faction_id) >= int(rules["adoption_min_family"]):
		return
	if not rng.chance(float(rules["adoption_chance_per_year"])):
		return
	var capital: String = state["factions"][faction_id]["capital"]
	var adopted_id := _spawn_character(data, state, rng, faction_id, {
		"role": "family",
		"age": rng.randi_range(int(rules["adoption_candidate_age_min"]), int(rules["adoption_candidate_age_max"])),
		"command": rng.randi_range(1, 4), "management": rng.randi_range(1, 4),
		"influence": rng.randi_range(0, 2), "location": capital,
	})
	notices.append({"kind": "adoption", "character": adopted_id, "faction": faction_id})


static func _spawn_character(data: GameData, state: Dictionary, rng: CampaignRng, faction_id: String, overrides: Dictionary) -> String:
	var char_id := "char_%d" % state["next_id"]
	state["next_id"] += 1
	var culture := data.culture_of_faction(faction_id)
	var pool: Dictionary = data.names.get(culture, data.names.get("roman", {}))
	var gender: String = overrides.get("gender", "male")
	var name_list: Array = pool.get(gender, ["Nameless"])
	var name: String = rng.pick(name_list) if not name_list.is_empty() else "Nameless"
	var surnames: Array = pool.get("surnames", [])
	if gender == "male" and not surnames.is_empty():
		name += " " + String(rng.pick(surnames))
	state["characters"][char_id] = {
		"faction": faction_id,
		"name": name,
		"age": int(overrides.get("age", 0)),
		"role": overrides.get("role", "family"),
		"gender": gender,
		"father": overrides.get("father", null),
		"command": int(overrides.get("command", 0)),
		"management": int(overrides.get("management", 0)),
		"influence": int(overrides.get("influence", 0)),
		"trait_points": {},
		"ancillaries": [],
		"location": overrides.get("location", ""),
		"alive": true,
		"deeds": {},
		"epithet": "",
	}
	return char_id


static func _find_role(state: Dictionary, faction_id: String, role: String) -> String:
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] == faction_id and character["alive"] and character["role"] == role:
			return char_id
	return ""


static func _best_heir_candidate(data: GameData, state: Dictionary, faction_id: String) -> String:
	var best := ""
	var best_key: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] != faction_id or not character["alive"]:
			continue
		if character["role"] != "family" or character.get("gender", "male") != "male":
			continue
		if int(character["age"]) < int(data.balance["characters"]["come_of_age"]):
			continue
		var key := [_line_rank(state, faction_id, char_id),
			CharacterRules.effective(data, character, "influence"), int(character["age"])]
		if best == "" or key > best_key:
			best = char_id
			best_key = key
	return best


static func _line_rank(state: Dictionary, faction_id: String, char_id: String) -> int:
	## 2 = son of the leader, 1 = descended from the leader's line, 0 = adopted
	## or collateral. Sorted above influence so a stranger never leapfrogs a son.
	var leader := _find_role(state, faction_id, "leader")
	if leader == "":
		return 0
	var father = state["characters"][char_id].get("father")
	if father == leader:
		return 2
	var depth := 0
	while father != null and state["characters"].has(father) and depth < 8:
		if father == leader:
			return 1
		father = state["characters"][father].get("father")
		depth += 1
	return 0


static func _living_family_count(state: Dictionary, faction_id: String) -> int:
	var count := 0
	for character in state["characters"].values():
		if character["faction"] == faction_id and character["alive"] \
				and character["role"] in ["leader", "heir", "family", "child"]:
			count += 1
	return count


static func _adult_male_count(data: GameData, state: Dictionary, faction_id: String) -> int:
	var count := 0
	for character in state["characters"].values():
		if character["faction"] == faction_id and character["alive"] \
				and character.get("gender", "male") == "male" \
				and character["role"] in ["leader", "heir", "family"] \
				and int(character["age"]) >= int(data.balance["characters"]["come_of_age"]):
			count += 1
	return count
