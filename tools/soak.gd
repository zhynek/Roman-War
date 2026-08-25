extends SceneTree
## Manual balance soak (not part of the test suite):
##   godot --headless --path . --script res://tools/soak.gd
## Runs long AI-driven campaigns at fixed seeds and prints what kind of world
## comes out: conquests, wars and peaces, surviving powers, rebel regions,
## treasury health, turn timing — and now the knowledge landscape: who
## practices what, how many DIFFERENT worlds the seeds produce (the
## "ten players, ten worlds" claim as a number), crisis-driven adoptions,
## the books of policies, and the chronicle's shape. Reading this output is
## how balance numbers get retuned — the campaign harness asserts
## invariants, this shows character.

const SEEDS := [42, 1234]
const TURNS := 100

var _adopted_by_seed := {}  # seed -> {fid: {tid: true}} for cross-seed divergence


func _init() -> void:
	for seed_value in SEEDS:
		_soak(seed_value)
	_print_divergence()
	quit(0)


func _soak(seed_value: int) -> void:
	var game := Game.new_campaign("julii", seed_value)
	var wars := 0
	var peaces := 0
	var trades := 0
	var conquests := {}
	var player_sieges := 0
	var total_ms := 0
	var crisis_adoptions := 0

	for i in range(TURNS):
		var started := Time.get_ticks_msec()
		var report := game.end_turn()
		total_ms += Time.get_ticks_msec() - started
		for event in report["knowledge"]:
			if String(event.get("kind", "")) == "technique_adopted":
				var adopter: String = event["faction"]
				if float(game.state["factions"][adopter].get("reform_pressure", 0.0)) > 0.0:
					crisis_adoptions += 1
		for event in report["ai"]:
			match String(event.get("kind", "")):
				"war_declared":
					wars += 1
				"peace_made":
					peaces += 1
				"trade_agreed":
					trades += 1
				"ai_conquest":
					var faction: String = event["faction"]
					conquests[faction] = int(conquests.get(faction, 0)) + 1
				"ai_siege":
					if event.get("owner", "") == game.state["player_faction"]:
						player_sieges += 1

	var alive: Array = []
	var rebels_left := 0
	var broke := 0
	for faction_id in game.state["factions"]:
		if game.state["factions"][faction_id]["alive"]:
			alive.append(faction_id)
			if int(game.state["factions"][faction_id]["treasury"]) < 0:
				broke += 1
	for settlement in game.state["settlements"].values():
		if settlement["owner"] == "rebels":
			rebels_left += 1
	alive.sort()

	var by_conquests: Array = conquests.keys()
	by_conquests.sort_custom(func(a, b): return int(conquests[a]) > int(conquests[b]))
	var top := ""
	for i in range(mini(5, by_conquests.size())):
		top += "%s:%d " % [by_conquests[i], int(conquests[i]) if false else int(conquests[by_conquests[i]])]

	# The knowledge landscape: what each living court practices beyond its
	# starting endowment, and how many distinct adopted-sets exist.
	var signatures := {}
	var seed_adopted := {}
	var adoptions_beyond_start := 0
	for faction_id in alive:
		var adopted: Array = []
		var knowledge: Dictionary = game.state["factions"][faction_id].get("knowledge", {})
		var tids: Array = knowledge.keys()
		tids.sort()
		for tid in tids:
			if String(knowledge[tid].get("stage", "")) == "adopted":
				adopted.append(tid)
				if int(knowledge[tid].get("turn", 0)) > 0:
					adoptions_beyond_start += 1
		signatures["+".join(adopted)] = true
		var adopted_set := {}
		for tid in adopted:
			adopted_set[tid] = true
		seed_adopted[faction_id] = adopted_set
	_adopted_by_seed[seed_value] = seed_adopted

	var edict_categories := {}
	var edicts_held := 0
	for faction_id in alive:
		for eid in game.state["factions"][faction_id].get("edicts", {}):
			var category: String = game.data.edicts.get(eid, {}).get("category", "?")
			edict_categories[category] = int(edict_categories.get(category, 0)) + 1
			edicts_held += 1

	var chronicle_kinds := {}
	for entry in game.state["chronicle"]:
		var kind: String = entry["kind"]
		chronicle_kinds[kind] = int(chronicle_kinds.get(kind, 0)) + 1

	print("=== seed %d, %d turns ===" % [seed_value, TURNS])
	print("  wars declared: %d, peaces: %d, trade pacts: %d" % [wars, peaces, trades])
	print("  conquests: %d total, top: %s" % [_sum(conquests), top])
	print("  sieges laid on the idle player: %d" % player_sieges)
	print("  factions alive: %d/%d (%d in debt), rebel regions left: %d/33" \
		% [alive.size(), game.state["factions"].size(), broke, rebels_left])
	print("  adoptions beyond the endowment: %d (%d in crisis), distinct signatures: %d/%d" \
		% [adoptions_beyond_start, crisis_adoptions, signatures.size(), alive.size()])
	print("  edicts held: %d %s" % [edicts_held, str(_sorted_counts(edict_categories))])
	print("  chronicle: %d entries %s" % [game.state["chronicle"].size(), str(_sorted_counts(chronicle_kinds))])
	print("  avg end_turn: %d ms" % int(float(total_ms) / TURNS))


func _print_divergence() -> void:
	## The "ten players, ten worlds" claim as a number: mean Jaccard DISTANCE
	## between the same faction's adopted-technique sets across seed pairs.
	## 0.00 = every seed converges on identical knowledge; 1.00 = no overlap.
	if SEEDS.size() < 2:
		return
	var total_distance := 0.0
	var pairs := 0
	for i in range(SEEDS.size()):
		for j in range(i + 1, SEEDS.size()):
			var a: Dictionary = _adopted_by_seed.get(SEEDS[i], {})
			var b: Dictionary = _adopted_by_seed.get(SEEDS[j], {})
			for faction_id in a:
				if not b.has(faction_id):
					continue
				var set_a: Dictionary = a[faction_id]
				var set_b: Dictionary = b[faction_id]
				var union := set_a.size()
				var intersection := 0
				for tid in set_b:
					if set_a.has(tid):
						intersection += 1
					else:
						union += 1
				if union > 0:
					total_distance += 1.0 - float(intersection) / float(union)
					pairs += 1
	if pairs > 0:
		print("divergence: %.2f (mean Jaccard distance of adopted sets across seeds)" \
			% (total_distance / pairs))


func _sum(counts: Dictionary) -> int:
	var total := 0
	for key in counts:
		total += int(counts[key])
	return total


func _sorted_counts(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b):
		return int(counts[a]) > int(counts[b]) if int(counts[a]) != int(counts[b]) else String(a) < String(b))
	var parts: Array = []
	for key in keys:
		parts.append("%s:%d" % [key, int(counts[key])])
	return "(" + " ".join(parts) + ")"
