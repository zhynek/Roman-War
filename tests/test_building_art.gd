extends RefCounted
## The procedural building art. Headless tests never rasterise, so these pin the
## four properties the painter depends on: every level resolves to something,
## the tiers of a chain are visibly different buildings, coordinates stay on the
## plate, and resolution is deterministic.

const CTX := {"culture": "roman", "terrain": "hills", "fertility": 2.0,
	"season": "summer", "progress": 1.0, "damaged": false, "lod": 2}


func test_every_building_level_resolves(t) -> void:
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	t.check(art.load_errors.is_empty(),
		"building_art.json loads clean: " + ", ".join(art.load_errors))
	var resolved := 0
	for level_id in data.building_levels:
		var entry: Dictionary = data.building_levels[level_id]
		var ctx := CTX.duplicate()
		ctx["culture"] = String(data.chains[entry["chain"]]["cultures"][0])
		var plate := art.building_plate(data, level_id, ctx)
		t.check((plate["parts"] as Array).size() >= 3,
			"%s draws a building (%d parts)" % [level_id, (plate["parts"] as Array).size()])
		resolved += 1
	t.check_eq(resolved, data.building_levels.size(), "every authored building level has a picture")
	t.check(resolved >= 320, "the illustrated roster only grows (%d levels)" % resolved)


func test_tier_progression_is_visible(t) -> void:
	## The whole point: tier 1 and the top tier must be different BUILDINGS,
	## not the same shape at two sizes.
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	var checked := 0
	for chain_id in data.chains:
		var chain: Dictionary = data.chains[chain_id]
		var levels: Array = chain["levels"]
		if levels.size() < 3:
			continue
		var ctx := CTX.duplicate()
		ctx["culture"] = String(chain["cultures"][0])
		var low := art.building_plate(data, String(levels[0]["id"]), ctx)
		var high := art.building_plate(data, String(levels[-1]["id"]), ctx)
		t.check(_signature(low) != _signature(high),
			"%s: tier 1 and tier %d are different buildings" % [chain_id, levels.size()])
		t.check((high["parts"] as Array).size() > (low["parts"] as Array).size(),
			"%s: the top tier is the richer picture" % chain_id)
		checked += 1
	t.check(checked >= 60, "the progression test actually swept the table (%d chains)" % checked)


func test_the_muster_field_is_not_the_field_of_mars(t) -> void:
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	var low := _names(art.building_plate(data, "roman_brk_1", CTX))
	var high := _names(art.building_plate(data, "roman_brk_5", CTX))
	t.check(not low.has("column_row"), "a muster field has no colonnade")
	t.check(not low.has("altar"), "a muster field has no altar")
	t.check(low.has("posts"), "it has a fence and a speaking mound")
	t.check(high.has("column_row"), "the Field of Mars has a colonnade")
	t.check(high.has("altar"), "and an altar")
	t.check(high.has("statue"), "and a statue")


func test_culture_changes_the_building(t) -> void:
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	var roman := CTX.duplicate()
	var egyptian := CTX.duplicate()
	egyptian["culture"] = "egyptian"
	# One shared chain, two cultures: the material track alone must tell them apart.
	var a := art.building_plate(data, "city_walls_3", roman)
	var b := art.building_plate(data, "city_walls_3", egyptian)
	t.check(_signature(a) != _signature(b), "a shared chain still looks Roman or Egyptian")
	# And a culture with its own temple shell builds something else entirely.
	var pylon := _names(art.building_plate(data, "egyptian_ra_3", egyptian))
	t.check(pylon.has("pylon"), "an Egyptian temple raises a pylon")
	t.check(not pylon.has("pediment"), "and not a Greek pediment")


func test_winter_repaints_the_building(t) -> void:
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	var winter := CTX.duplicate()
	winter["season"] = "winter"
	t.check(_fingerprint(art.building_plate(data, "roman_walls_4", CTX))
		!= _fingerprint(art.building_plate(data, "roman_walls_4", winter)),
		"the same walls read differently in winter")


func test_every_part_name_is_implemented(t) -> void:
	## An unimplemented part would silently fall through to a box. The schema
	## closes the vocabulary; this proves the painter matches it.
	var implemented := {}
	for method in (ArtPainter as Script).get_script_method_list():
		implemented[String(method["name"])] = true
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	var seen := {}
	for level_id in data.building_levels:
		var entry: Dictionary = data.building_levels[level_id]
		var ctx := CTX.duplicate()
		ctx["culture"] = String(data.chains[entry["chain"]]["cultures"][0])
		for part in art.building_plate(data, level_id, ctx)["parts"]:
			seen[String(part["part"])] = true
	for name in seen:
		t.check(implemented.has("_" + String(name)),
			"ArtPainter implements the '%s' part" % name)
	t.check(seen.size() >= 18, "the recipes exercise the vocabulary (%d parts)" % seen.size())


func test_parts_stay_on_the_plate(t) -> void:
	## A curtain wall runs off the frame on purpose, but nothing may wander off
	## the picture altogether.
	var bounds := Rect2(-0.20, -0.20, 1.40, 1.40)
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	for level_id in data.building_levels:
		var entry: Dictionary = data.building_levels[level_id]
		var ctx := CTX.duplicate()
		ctx["culture"] = String(data.chains[entry["chain"]]["cultures"][0])
		for part in art.building_plate(data, level_id, ctx)["parts"]:
			var r: Rect2 = part["rect"]
			t.check(bounds.encloses(r), "%s: %s stays on the plate" % [level_id, part["part"]])
			t.check(r.size.x > 0.0 and r.size.y > 0.0,
				"%s: %s has a real size" % [level_id, part["part"]])


func test_budgets_are_bounded(t) -> void:
	var data := GameData.load_from("res://data")
	var art := BuildingArt.for_data(data)
	for level_id in data.building_levels:
		var entry: Dictionary = data.building_levels[level_id]
		var ctx := CTX.duplicate()
		ctx["culture"] = String(data.chains[entry["chain"]]["cultures"][0])
		var plate := art.building_plate(data, level_id, ctx)
		t.check((plate["parts"] as Array).size() <= BuildingArt.MAX_PARTS,
			"%s is within the part budget" % level_id)
		t.check(art.primitive_estimate(plate) <= 620,
			"%s is within the primitive budget (%d)" % [level_id, art.primitive_estimate(plate)])


func test_resolution_is_deterministic(t) -> void:
	## The campaign's replay promise, applied to pictures: no randf anywhere, so
	## a building looks identical every run and every screenshot.
	var data := GameData.load_from("res://data")
	var first := BuildingArt.new()
	first.load_from("res://data/building_art.json")
	var second := BuildingArt.new()
	second.load_from("res://data/building_art.json")
	for level_id in data.building_levels:
		t.check_eq(_fingerprint(first.building_plate(data, level_id, CTX)),
			_fingerprint(second.building_plate(data, level_id, CTX)),
			"%s resolves identically twice" % level_id)


func test_the_fallback_never_leaves_a_level_blank(t) -> void:
	## Fixtures' synthetic chains have no authored recipe at all, which is
	## exactly what exercises the kind / generic / last-resort rungs.
	var data := Fixtures.data()
	var art := BuildingArt.for_data(data)
	for level_id in data.building_levels:
		t.check((art.building_plate(data, level_id, CTX)["parts"] as Array).size() >= 2,
			"unrecipe'd %s still draws a building" % level_id)
	t.check((art.building_plate(data, "no_such_level", CTX)["parts"] as Array).size() >= 2,
		"even an unknown level id draws something")


func test_one_stage_serves_hero_and_thumbnail(t) -> void:
	var hero := ArtPainter.stage_of(Rect2(0, 0, 320, 196))
	var thumb := ArtPainter.stage_of(Rect2(0, 0, 132, 60))
	t.check_near(hero.size.x / hero.size.y, 1.6, 0.001, "the hero stage is 8:5")
	t.check_near(thumb.size.x / thumb.size.y, 1.6, 0.001, "the thumbnail stage is 8:5")
	t.check(Rect2(0, 0, 320, 196).grow(1.0).encloses(hero), "the hero stage fits its box")
	t.check(Rect2(0, 0, 132, 60).grow(1.0).encloses(thumb), "the thumbnail fits its box")


## test_the_map_and_the_art_share_one_hash lived here. It pinned MapGeometry's
## landmass hash to ArtNoise.hash01, a coupling that existed only in the map
## renderer this branch brought. main keeps the other renderer (see DESIGN §2.4),
## whose geometry does no hashing at all, so the two systems are now genuinely
## independent and there is nothing left to pin. Building art still hashes
## through ArtNoise, which the tests above cover.

func _names(plate: Dictionary) -> Dictionary:
	var found := {}
	for part in plate["parts"]:
		found[String(part["part"])] = true
	return found


func _signature(plate: Dictionary) -> String:
	var marks: Array = []
	for part in plate["parts"]:
		marks.append("%s:%s" % [part["part"], (part["shade"]["mid"] as Color).to_html(false)])
	marks.sort()
	return ",".join(marks)


func _fingerprint(plate: Dictionary) -> String:
	var text := String(plate["title"])
	for part in plate["parts"]:
		var r: Rect2 = part["rect"]
		text += "|%s@%.4f,%.4f,%.4f,%.4f#%s%d" % [part["part"], r.position.x, r.position.y,
			r.size.x, r.size.y, (part["shade"]["mid"] as Color).to_html(false), int(part["z"])]
	return text
